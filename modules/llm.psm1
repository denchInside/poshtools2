#Requires -Version 7.0

using namespace System.IO
using namespace System.Collections.Generic
using namespace System.Runtime.InteropServices

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

Import-Module "$PSScriptRoot\input.psm1" -Scope Local;

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
    $value = Read-Input_Multiline -Prompt $label -Mask:$Mask;

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

    if (-not $credentials.HostName) { $credentials.HostName = Read-Input_Multiline -Prompt 'host'; }
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

function Test-LLM_CredentialsEqual(
    $Left,
    $Right
)
{
    <#
    .SYNOPSIS
        Compares two credential objects by value.
    .PARAMETER Left
        First credentials object (LLM_Credentials or any object with
        HostName/Secret/Model properties).
    .PARAMETER Right
        Second credentials object.
    #>

    if ($null -eq $Left -or $null -eq $Right)
    {
        return $false;
    }

    return ($Left.HostName -eq $Right.HostName) `
        -and ($Left.Secret -ceq $Right.Secret) `
        -and ($Left.Model -ceq $Right.Model);
}

function Sync-LLM_DialogueCredentials(
    $Dialogue,
    $Credentials
)
{
    <#
    .SYNOPSIS
        Refreshes a live dialogue's credentials without dropping history.
    .PARAMETER Dialogue
        The LLM_Dialogue whose Credentials should be updated.
    .PARAMETER Credentials
        The new credentials. Properties are copied one by one so this also
        works when the credentials object comes from a different import of
        this module (e.g. llm-auth.ps1 pushing to llm.ps1's dialogue), where
        the class identities do not match and whole-object assignment fails.
    .OUTPUTS
        $true when credentials were updated, $false when already in sync.
    #>

    if ($null -eq $Dialogue -or $null -eq $Credentials)
    {
        return $false;
    }

    if ($null -eq $Dialogue.Credentials)
    {
        $Dialogue.Credentials = $Credentials;
        return $true;
    }

    if (Test-LLM_CredentialsEqual -Left $Dialogue.Credentials -Right $Credentials)
    {
        return $false;
    }

    $Dialogue.Credentials.HostName = $Credentials.HostName;
    $Dialogue.Credentials.Secret = $Credentials.Secret;
    $Dialogue.Credentials.Model = $Credentials.Model;

    return $true;
}

function Sync-LLM_DialogueCredentialsFromFile(
    $Dialogue,
    [string] $FileName
)
{
    <#
    .SYNOPSIS
        Re-reads the credentials file and applies it to a live dialogue.
    .DESCRIPTION
        Silent pull path for scripts that cache a dialogue across invocations
        (llm.ps1 keeps one in $global:__llm_Data). Unlike Get-LLM_Credentials
        this never prompts and never writes: a missing, unreadable or
        incomplete file simply leaves the dialogue untouched and returns
        $false, so normal calls stay non-interactive.
    .PARAMETER Dialogue
        The LLM_Dialogue to refresh.
    .PARAMETER FileName
        Path to the JSON credentials file.
    .OUTPUTS
        $true when credentials were updated, $false otherwise.
    #>

    if ($null -eq $Dialogue -or -not $FileName)
    {
        return $false;
    }

    try
    {
        if (-not [File]::Exists($FileName))
        {
            return $false;
        }

        $save = Get-Content -LiteralPath $FileName -Raw -Encoding utf8 | ConvertFrom-Json;
    }
    catch
    {
        return $false;
    }

    if (-not $save.HostName -or -not $save.Secret -or -not $save.Model)
    {
        return $false;
    }

    return Sync-LLM_DialogueCredentials -Dialogue $Dialogue -Credentials $save;
}

function Export-LLM_Session(
    $Dialogue,
    [string] $Path
)
{
    <#
    .SYNOPSIS
        Persists a dialogue's history to a JSON session file.
    .PARAMETER Dialogue
        The LLM_Dialogue whose History should be saved.
    .PARAMETER Path
        Destination file path. Missing parent directories are created.
    #>

    if ($null -eq $Dialogue -or -not $Path)
    {
        throw [System.ArgumentException]::new('dialogue and path are required');
    }

    $entries = @($Dialogue.History | ForEach-Object {
        $entry = [ordered]@{
            role = $_.role
            content = $_.content
            time = ([datetime]$_.time).ToString('o')
        };

        if ($null -ne $_.tool_call_id) { $entry.tool_call_id = $_.tool_call_id; }
        if ($null -ne $_.name) { $entry.name = $_.name; }
        if ($null -ne $_.tool_calls) { $entry.tool_calls = $_.tool_calls; }

        [pscustomobject]$entry
    });

    $full = [System.IO.Path]::IsPathRooted($Path) ? $Path : (Join-Path (Get-Location).Path $Path);
    $dir = [System.IO.Path]::GetDirectoryName($full);
    if ($dir -and -not [File]::Exists($dir))
    {
        $null = New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop;
    }

    [ordered]@{ version = 1; history = $entries } |
        ConvertTo-Json -Depth 10 |
        Out-File -LiteralPath "$full.tmp" -Encoding utf8;
    Move-Item -LiteralPath "$full.tmp" -Destination $full -Force;
}

function Repair-LLM_HistoryTail($Dialogue)
{
    <#
    .SYNOPSIS
        Drops a trailing assistant tool-call block whose results never arrived
        (interrupted turn), keeping everything else. A no-op on complete history.
    #>

    $entries = @($Dialogue.History);

    for ($i = $entries.Count - 1; $i -ge 0; $i--)
    {
        if ($entries[$i].role -ne 'assistant' -or -not $entries[$i].tool_calls) { continue; }

        $ids = @($entries[$i].tool_calls | ForEach-Object { $_.id });
        $have = @($entries | Select-Object -Skip ($i + 1) | Where-Object { $_.role -eq 'tool' } | ForEach-Object { $_.tool_call_id });
        $missing = @($ids | Where-Object { $_ -notin $have });

        if ($missing.Count -gt 0)
        {
            while ($Dialogue.History.Count -gt $i) { $Dialogue.History.RemoveLast(); }
        }

        break;
    }
}

function Import-LLM_Session(
    $Dialogue,
    [string] $Path
)
{
    <#
    .SYNOPSIS
        Replaces a dialogue's history with the contents of a JSON session file.
    .PARAMETER Dialogue
        The LLM_Dialogue whose History should be replaced.
    .PARAMETER Path
        Source file path previously written by Export-LLM_Session.
    #>

    if ($null -eq $Dialogue -or -not $Path)
    {
        throw [System.ArgumentException]::new('dialogue and path are required');
    }

    try
    {
        $doc = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop;
    }
    catch
    {
        throw "session file is corrupted: $Path ($($_.Exception.Message))";
    }

    $validRoles = @('system', 'user', 'assistant', 'tool');
    $items = @($doc.history);
    if ($doc.version -ne 1 -or $null -eq $doc.history)
    {
        throw "session file is corrupted: $Path (bad version or history)";
    }

    $restored = [System.Collections.Generic.List[pscustomobject]]::new();
    foreach ($item in $items)
    {
        if ($item.role -notin $validRoles -or $null -eq $item.content)
        {
            throw "session file is corrupted: $Path (invalid history entry)";
        }

        try
        {
            $time = [datetime]$item.time;
        }
        catch
        {
            throw "session file is corrupted: $Path (invalid timestamp)";
        }

        $entry = [pscustomobject]@{
            role = [string]$item.role
            content = [string]$item.content
            time = $time
        };

        if ($null -ne $item.tool_call_id) { $entry | Add-Member -NotePropertyName 'tool_call_id' -NotePropertyValue ([string]$item.tool_call_id); }
        if ($null -ne $item.name) { $entry | Add-Member -NotePropertyName 'name' -NotePropertyValue ([string]$item.name); }
        if ($null -ne $item.tool_calls) { $entry | Add-Member -NotePropertyName 'tool_calls' -NotePropertyValue $item.tool_calls; }

        $restored.Add($entry);
    }

    $Dialogue.History.Clear();
    $Dialogue.PendingToolCalls = @();
    foreach ($entry in $restored) { $Dialogue.History.Add($entry); }
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

Export-ModuleMember -Function New-LLM_Dialogue, Get-LLM_Credentials, Get-LLM_WorkspaceState, Test-LLM_CredentialsEqual, Sync-LLM_DialogueCredentials, Sync-LLM_DialogueCredentialsFromFile, Export-LLM_Session, Import-LLM_Session, Repair-LLM_HistoryTail;