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
    [LinkedList[HashTable]]$History
    
    LLM_Dialogue([LLM_Credentials]$Credentials, [String]$SystemPrompt) {
        $this.Credentials = $Credentials
        $this.SystemPrompt = $SystemPrompt
        $this.Search = $false
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
    
    [String] Ask([String]$Prompt) {
        if (-not $Prompt) {
            throw "no prompt provided"
        }
        
        $this.Append("user", $Prompt)
        
        $uri = [String]::Format(
            "http://{0}/v1/chat/completions",
            $this.Credentials.HostName
        )
        
        $payload = [PSObject]@{
            model = $this.Credentials.Model
            messages = $this.History | Select-Object role, content
            stream = $false
        }
        
        $result = $payload |
            ConvertTo-Json -Depth 10 -Compress |
            Invoke-RestMethod `
                -Uri $uri `
                -Method Post `
                -ContentType "application/json" `
                -Headers @{ "Authorization" = "Bearer $($this.Credentials.Secret)" }
        
        $response = $result.choices[0].message.content
        $this.Append("assistant", $response -or "<no response>")
        return $response
    }
    
    [void] Clear() {
        $this.History.Clear()
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

function Get-LLM_Credentials {
    param(
        [String]$FileName,
        [String]$HostName,
        [String]$Model
    )
    
    $save = if ($FileName -and [File]::Exists($FileName)) {
        Get-Content -LiteralPath $FileName -Raw -Encoding utf8 | ConvertFrom-Json
    } else {
        [PSObject]@{}
    }
    
    $credentials = $Script:CredentialsFactory.Invoke()
    
    $credentials.HostName = if ($HostName) {
        $HostName
    } else {
        $save.HostName
    }
    
    $credentials.Secret = $save.Secret
    $credentials.Model = if ($Model) {
        $Model
    } else {
        $save.Model
    }
    
    if (-not $credentials.Secret) {
        if (-not $credentials.HostName) { $credentials.HostName = Read-Host "host" }
        if (-not $credentials.HostName) { throw "cannot use empty host" }
    
        $credentials.Secret = Read-Host "secret"
        if (-not $credentials.Secret) { throw "cannot use empty secret" }
    }

    if (-not $credentials.Model) {
        $credentials.Model = Read-Host "model"
        if (-not $credentials.Model) { throw "cannot use empty model" }
    }
    
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
