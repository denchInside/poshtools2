using namespace System.IO
using namespace System.Collections.Generic

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

class LLM_Credentials {
    [String]$HostName
    [String]$Secret
    [String]$Model
}

class LLM_Dialogue {
    [LLM_Credentials]$Credentials
    [String]$SystemPrompt
    [Boolean]$Search
    [Boolean]$Think
    [Object[]]$Tools
    [Object[]]$PendingToolCalls
    [LinkedList[HashTable]]$History
    
    LLM_Dialogue([LLM_Credentials]$Credentials, [String]$SystemPrompt) {
        $this.Credentials = $Credentials
        $this.SystemPrompt = $SystemPrompt
        $this.Search = $false
        $this.Think = $false
        $this.Tools = @()
        $this.PendingToolCalls = @()
        $this.History = [LinkedList[HashTable]]::new()
        $this.Clear()
    }
    
    [void] Append([String]$Role, [String]$Content) {
        if ($Role -notin "system", "user", "assistant") {
            throw "invalid role: choose 'system', 'user' or 'assistant'"
        }
        $this.History.Add([PSObject]@{
            role = $Role
            content = $Content
            time = [DateTime]::Now
        })
    }
    
    [void] SetSearch([Boolean]$Search) {
        $this.Search = $Search
    }
    
    [void] SetThink([Boolean]$Think) {
        $this.Think = $Think
    }
    
    [void] SetTools([Object[]]$Tools) {
        $this.Tools = $Tools
    }
    
    [void] SubmitToolResult([String]$ToolCallId, [String]$Name, [String]$Content) {
        $this.History.Add([PSObject]@{
            role = "tool"
            content = $Content
            tool_call_id = $ToolCallId
            name = $Name
            time = [DateTime]::Now
        })
    }
    
    [String] Ask([String]$Prompt) {
        if (-not $Prompt) {
            throw "no prompt provided"
        }
        
        $before = $this.History.Count
        $this.Append("user", $Prompt)
        
        try {
            return $this.Complete()
        } catch {
            while ($this.History.Count -gt $before) {
                $this.History.RemoveLast()
            }
            throw
        }
    }
    
    [String] Complete() {
        $uri = [String]::Format(
            "http://{0}/v1/chat/completions",
            $this.Credentials.HostName
        )
        
        $messages = $this.History | ForEach-Object {
            $message = [Ordered]@{ role = $_.role; content = $_.content }
            if ($_.tool_call_id) { $message.tool_call_id = $_.tool_call_id }
            if ($_.name) { $message.name = $_.name }
            if ($_.tool_calls) { $message.tool_calls = $_.tool_calls }
            $message
        }
        
        $payload = [Ordered]@{
            model = $this.Credentials.Model
            messages = $messages
            stream = $false
        }
        
        if ($this.Search) { $payload.search = $true }
        if ($this.Think) { $payload.reasoning_effort = "high" }
        if ($this.Tools -and $this.Tools.Count -gt 0) { $payload.tools = $this.Tools }
        
        $result = try {
            $payload |
                ConvertTo-Json -Depth 10 -Compress |
                Invoke-RestMethod `
                    -Uri $uri `
                    -Method Post `
                    -ContentType "application/json" `
                    -Headers @{ "Authorization" = "Bearer $($this.Credentials.Secret)" }
        } catch {
            throw ConvertTo-LLM_ErrorMessage $_
        }
        
        $message = $result.choices[0].message
        $content = if ($message.content) { $message.content } else { "" }
        
        $this.PendingToolCalls = @($message.tool_calls)
        
        $this.History.Add([PSObject]@{
            role = "assistant"
            content = $content
            tool_calls = $message.tool_calls
            time = [DateTime]::Now
        })
        
        return $content
    }
    
    [void] Clear() {
        $this.History.Clear()
        $this.PendingToolCalls = @()
        $this.Append("system", $this.SystemPrompt)
    }
    
    [void] Compact([ScriptBlock]$Strategy) {
        $node = $this.History.First
        
        while ($next = $node.Next) {
            if (-not (& $Strategy $next.Value)) {
                $this.History.Remove($next)
            }
            $node = $node.Next
        }
    }
}


function ConvertTo-LLM_ErrorMessage {
    param(
        $ErrorRecord
    )
    
    $body = $ErrorRecord.ErrorDetails.Message
    $parsed = if ($body) { try { $body | ConvertFrom-Json } catch { $null } } else { $null }
    
    if (-not $parsed) {
        return $ErrorRecord.Exception.Message
    }
    
    $message = if ($parsed.error.message) { $parsed.error.message } else { "request failed" }
    $failedGeneration = $parsed.upstream_details.error.failed_generation
    
    if ($failedGeneration) {
        return "$message`nmodel produced: $failedGeneration"
    }
    
    return $message
}

$Script:DialogueFactory = [LLM_Dialogue]::new
$Script:CredentialsFactory = [LLM_Credentials]::new

function New-LLM_Dialogue {
    param(
        [Parameter(Mandatory = $true)]
        [LLM_Credentials]$Credentials,
        [String]$SystemPrompt
    )
    
    if (-not $SystemPrompt) {
        $SystemPrompt = "You are an assistant, answer briefly and clearly."
    }
    
    return $Script:DialogueFactory.Invoke($Credentials, $SystemPrompt)
}

function Read-LLM_Value {
    param(
        [String]$Prompt,
        [String]$Default
    )
    
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $value = Read-Host $label
    
    if (-not $value) {
        return $Default
    }
    
    return $value
}

function Get-LLM_ModelList {
    param(
        [String]$HostName,
        [String]$Secret
    )
    
    $uri = [String]::Format("http://{0}/v1", $HostName)
    
    $result = Invoke-RestMethod `
        -Uri $uri `
        -Method Get `
        -ContentType "application/json" `
        -Headers @{ "Authorization" = "Bearer $Secret" }
    
    return $result.data.id
}

function Select-LLM_Model {
    param(
        [String]$HostName,
        [String]$Secret,
        [String]$Default
    )
    
    $ids = Get-LLM_ModelList -HostName $HostName -Secret $Secret
    
    $ids | ForEach-Object { Write-Host $_ }
    
    while ($true) {
        $choice = Read-LLM_Value -Prompt "model" -Default $Default
        
        if ($choice -and $choice -in $ids) {
            return $choice
        }
        
        Write-Host "not a valid model id, pick one from the list above"
    }
}

function Get-LLM_Credentials {
    param(
        [String]$FileName,
        [String]$HostName,
        [switch]$Reset,
        [switch]$SelectModel
    )
    
    $save = if ($FileName -and [File]::Exists($FileName)) {
        Get-Content -LiteralPath $FileName -Raw -Encoding utf8 | ConvertFrom-Json
    } else {
        [PSObject]@{}
    }
    
    $credentials = $Script:CredentialsFactory.Invoke()
    
    $credentials.HostName = if ($HostName) {
        $HostName
    } elseif ($Reset) {
        Read-LLM_Value -Prompt "host" -Default $save.HostName
    } else {
        $save.HostName
    }
    
    if (-not $credentials.HostName) { $credentials.HostName = Read-Host "host" }
    if (-not $credentials.HostName) { throw "cannot use empty host" }
    
    $credentials.Secret = if ($Reset) {
        Read-LLM_Value -Prompt "secret" -Default $save.Secret
    } else {
        $save.Secret
    }
    
    if (-not $credentials.Secret) { $credentials.Secret = Read-Host "secret" }
    if (-not $credentials.Secret) { throw "cannot use empty secret" }
    
    $credentials.Model = if ($SelectModel -or $Reset -or -not $save.Model) {
        Select-LLM_Model -HostName $credentials.HostName -Secret $credentials.Secret -Default $save.Model
    } else {
        $save.Model
    }
    
    if (-not $credentials.Model) { throw "cannot use empty model" }
    
    if ($FileName) {
        $dataDirName = [Path]::GetDirectoryName($FileName)
        $null = New-Item -Path $dataDirName -ItemType Directory -ErrorAction SilentlyContinue
        
        $credentials |
            ConvertTo-Json |
            Out-File -LiteralPath $FileName -Encoding utf8
    }
    
    return $credentials
}


Export-ModuleMember -Function New-LLM_Dialogue, Get-LLM_Credentials
