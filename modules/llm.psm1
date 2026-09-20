#Requires -Version 7.0

using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Runtime.InteropServices

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

class LLM_Credentials
{
    [string] $HostName;
    [string] $Secret;
    [string] $Model;
}

class LLM_Dialogue
{
    [LLM_Credentials] $Credentials;
    [string] $SystemPrompt;
    [bool] $Search;
    [bool] $Think;
    [object[]] $Tools;
    [object[]] $PendingToolCalls;
    [LinkedList[pscustomobject]] $History;

    LLM_Dialogue([LLM_Credentials] $credentials, [string] $systemPrompt)
    {
        $this.Credentials = $credentials;
        $this.SystemPrompt = $systemPrompt;
        $this.Search = $false;
        $this.Think = $false;
        $this.Tools = @();
        $this.PendingToolCalls = @();
        $this.History = [LinkedList[pscustomobject]]::new();
        $this.Clear();
    }

    [void] Append([string] $role, [string] $content)
    {
        if ($role -notin 'system', 'user', 'assistant')
        {
            throw [System.ArgumentException]::new("invalid role: choose 'system', 'user' or 'assistant'", 'role');
        }
        $this.History.Add([pscustomobject]@{
            role = $role
            content = $content
            time = [datetime]::Now
        });
    }

    [void] SetSearch([bool] $search)
    {
        $this.Search = $search;
    }

    [void] SetThink([bool] $think)
    {
        $this.Think = $think;
    }

    [void] SetTools([object[]] $tools)
    {
        $this.Tools = $tools;
    }

    [void] SubmitToolResult([string] $toolCallId, [string] $name, [string] $content)
    {
        $this.History.Add([pscustomobject]@{
            role = 'tool'
            content = $content
            tool_call_id = $toolCallId
            name = $name
            time = [datetime]::Now
        });
    }

    [string] Ask([string] $prompt)
    {
        if (-not $prompt)
        {
            throw [System.ArgumentException]::new('no prompt provided', 'prompt');
        }

        $before = $this.History.Count;
        $this.Append('user', $prompt);

        try
        {
            return $this.Complete();
        }
        catch
        {
            while ($this.History.Count -gt $before)
            {
                $this.History.RemoveLast();
            }
            throw;
        }
    }

    [string] Complete()
    {
        $uri = Get-LLM_Uri -HostName $this.Credentials.HostName -Path '/v1/chat/completions';

        $messages = @($this.History | ForEach-Object {
            $message = [ordered]@{ role = $_.role; content = $_.content };
            if ($_.tool_call_id) { $message.tool_call_id = $_.tool_call_id; }
            if ($_.name) { $message.name = $_.name; }
            if ($_.tool_calls) { $message.tool_calls = $_.tool_calls; }
            $message
        });

        $payload = [ordered]@{
            model = $this.Credentials.Model
            messages = $messages
            stream = $false
        };

        if ($this.Search) { $payload.search = $true; }
        if ($this.Think) { $payload.reasoning_effort = 'high'; }
        if ($this.Tools -and $this.Tools.Count -gt 0) { $payload.tools = $this.Tools; }

        $result = try
        {
            $payload |
                ConvertTo-Json -Depth 10 -Compress |
                Invoke-RestMethod `
                    -Uri $uri `
                    -Method Post `
                    -ContentType 'application/json' `
                    -Headers @{ Authorization = "Bearer $($this.Credentials.Secret)" };
        }
        catch
        {
            throw (ConvertTo-LLM_ErrorMessage $_);
        }

        if (-not $result.choices)
        {
            throw 'the model returned no choices';
        }

        $message = $result.choices[0].message;
        $content = $message.content ? $message.content : '';

        $this.PendingToolCalls = $message.tool_calls ? @($message.tool_calls) : @();

        $this.History.Add([pscustomobject]@{
            role = 'assistant'
            content = $content
            tool_calls = $message.tool_calls
            time = [datetime]::Now
        });

        return $content;
    }

    [void] Clear()
    {
        $this.History.Clear();
        $this.PendingToolCalls = @();
        $this.Append('system', $this.SystemPrompt);
    }

    [void] Compact([scriptblock] $strategy)
    {
        $node = $this.History.First.Next;

        while ($node)
        {
            $next = $node.Next;
            if (-not (& $strategy $node.Value))
            {
                $this.History.Remove($node);
            }
            $node = $next;
        }

        while ($this.History.First.Next -and $this.History.First.Next.Value.role -eq 'tool')
        {
            $this.History.Remove($this.History.First.Next);
        }
    }
}

function ConvertTo-LLM_ErrorMessage($ErrorRecord)
{
    <#
    .SYNOPSIS
        Turns a failed Invoke-RestMethod error record into a readable message.
    .PARAMETER ErrorRecord
        The caught error record from a failed API call.
    #>

    $body = $ErrorRecord.ErrorDetails.Message;
    $parsed = $null;
    if ($body) { try { $parsed = $body | ConvertFrom-Json } catch { $parsed = $null } }

    if (-not $parsed)
    {
        return $ErrorRecord.Exception.Message;
    }

    $message = $parsed.error.message ? $parsed.error.message : 'request failed';
    $failedGeneration = $parsed.upstream_details.error.failed_generation;

    if ($failedGeneration)
    {
        return "$message`nmodel produced: $failedGeneration";
    }

    return $message;
}

$Script:DialogueFactory = [LLM_Dialogue]::new;
$Script:CredentialsFactory = [LLM_Credentials]::new;

function Get-LLM_Uri(
    [string] $HostName,
    [string] $Path
)
{
    <#
    .SYNOPSIS
        Builds the request uri for an API path on the given host.
    .PARAMETER HostName
        Either host[:port], which is reached over http, or a full origin such
        as https://example.com, which is used as given.
    .PARAMETER Path
        The absolute API path, for example /v1/models.
    #>

    $base = ($HostName -match '^https?://') ? $HostName.TrimEnd('/') : "http://$HostName";

    return [string]::Format('{0}{1}', $base, $Path);
}

function New-LLM_Dialogue(
    [Parameter(Mandatory)]
    [LLM_Credentials] $Credentials,

    [string] $SystemPrompt
)
{
    <#
    .SYNOPSIS
        Creates a new LLM_Dialogue bound to the given credentials.
    .PARAMETER Credentials
        Host, secret and model to use for completions.
    .PARAMETER SystemPrompt
        Optional system prompt; a generic default is used when omitted.
    .EXAMPLE
        New-LLM_Dialogue -Credentials $credentials -SystemPrompt 'You are terse.'
    #>

    if (-not $SystemPrompt)
    {
        $SystemPrompt = 'You are an assistant, answer briefly and clearly.';
    }

    return $Script:DialogueFactory.Invoke($Credentials, $SystemPrompt);
}

function Read-LLM_Value(
    [string] $Prompt,
    [string] $Default,
    [switch] $Mask
)
{
    $shown = $Mask ? '****' : $Default;
    $label = $Default ? "$Prompt [$shown]" : $Prompt;
    $value = $Mask ? (Read-Host $label -MaskInput) : (Read-Host $label);

    return $value ? $value : $Default;
}

function Get-LLM_ModelList(
    [string] $HostName,
    [string] $Secret
)
{
    $uri = Get-LLM_Uri -HostName $HostName -Path '/v1/models';

    $result = Invoke-RestMethod `
        -Uri $uri `
        -Method Get `
        -ContentType 'application/json' `
        -Headers @{ Authorization = "Bearer $Secret" };

    return $result.data.id;
}

function Select-LLM_Model(
    [string] $HostName,
    [string] $Secret,
    [string] $Default
)
{
    $ids = Get-LLM_ModelList -HostName $HostName -Secret $Secret;

    $ids | ForEach-Object { Write-Host $_; };

    while ($true)
    {
        $choice = Read-LLM_Value -Prompt 'model' -Default $Default;

        if ($choice -and $choice -in $ids)
        {
            return $choice;
        }

        Write-Host 'not a valid model id, pick one from the list above' -ForegroundColor Yellow;
    }
}

function Get-LLM_Credentials(
    [string] $FileName,
    [string] $HostName,
    [switch] $Reset,
    [switch] $SelectModel
)
{
    <#
    .SYNOPSIS
        Loads, prompts for, and persists LLM host/secret/model credentials.
    .PARAMETER FileName
        Path to the JSON credentials cache. When omitted, nothing is persisted.
    .PARAMETER HostName
        Overrides the stored host without prompting.
    .PARAMETER Reset
        Forces re-prompting for host and secret even if cached values exist.
    .PARAMETER SelectModel
        Forces re-prompting for the model even if a cached value exists.
    .EXAMPLE
        Get-LLM_Credentials -FileName '.\data\llm.json'
    #>

    $save = ($FileName -and [File]::Exists($FileName)) `
        ? (Get-Content -LiteralPath $FileName -Raw -Encoding utf8 | ConvertFrom-Json) `
        : [pscustomobject]@{};

    $credentials = $Script:CredentialsFactory.Invoke();

    $credentials.HostName = if ($HostName) {
        $HostName
    } elseif ($Reset) {
        Read-LLM_Value -Prompt 'host' -Default $save.HostName
    } else {
        $save.HostName
    }

    if (-not $credentials.HostName) { $credentials.HostName = Read-Host 'host'; }
    if (-not $credentials.HostName) { throw [System.ArgumentException]::new('cannot use empty host', 'HostName'); }

    $credentials.Secret = if ($Reset) {
        Read-LLM_Value -Prompt 'secret' -Default $save.Secret -Mask
    } else {
        $save.Secret
    }

    if (-not $credentials.Secret) { $credentials.Secret = Read-LLM_Value -Prompt 'secret' -Mask; }
    if (-not $credentials.Secret) { throw [System.ArgumentException]::new('cannot use empty secret', 'Secret'); }

    $credentials.Model = if ($SelectModel -or $Reset -or -not $save.Model) {
        Select-LLM_Model -HostName $credentials.HostName -Secret $credentials.Secret -Default $save.Model
    } else {
        $save.Model
    }

    if (-not $credentials.Model) { throw [System.ArgumentException]::new('cannot use empty model', 'Model'); }

    if ($FileName)
    {
        $dataDirName = [Path]::GetDirectoryName($FileName);
        $null = New-Item -Path $dataDirName -ItemType Directory -ErrorAction SilentlyContinue;

        $credentials |
            ConvertTo-Json |
            Out-File -LiteralPath $FileName -Encoding utf8;
    }

    return $credentials;
}

function Get-LLM_WorkspaceState()
{
    <#
    .SYNOPSIS
        Returns a short line describing the environment the model is working
        in: date, operating system, shell version, current directory and, if
        inside a git repository, the current branch. Used to ground the model
        before it proposes its first command.
    #>

    $date = [datetime]::Now.ToString('yyyy-MM-dd');
    $os = [RuntimeInformation]::OSDescription;
    $location = (Get-Location).Path;
    $line = "date: $date | os: $os | shell: PowerShell $($PSVersionTable.PSVersion) | cwd: $location";

    $branch = try { git rev-parse --abbrev-ref HEAD 2>$null } catch { $null }
    if ($branch) { $line += " | git branch: $branch"; }

    return $line;
}

Export-ModuleMember -Function New-LLM_Dialogue, Get-LLM_Credentials, Get-LLM_WorkspaceState;