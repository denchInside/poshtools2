using namespace System.IO
using namespace System.Collections.Generic

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

class LLM_Credentials {
	[String]$Host
	[String]$Secret
}

class LLM_Dialogue {
	[LLM_Credentials]$Credentials
	[String]$Mode
	[String]$SystemPrompt
	[Boolean]$Search
	[LinkedList[HashTable]]$History
	
	LLM_Dialogue([LLM_Credentials]$Credentials, [String]$SystemPrompt) {
		$this.Credentials = $Credentials
		$this.Mode = "quality"
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
	
	[void] SetMode([String]$Mode) {
		if ($Mode -notin "speed", "quality") {
			throw "invalid mode: choose 'speed' or 'quality'"
		}
		$this.Mode = $Mode
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
			"http://{0}/api?mode={1}&strict=false&search={2}",
			$this.Credentials.Host,
			$this.Mode.ToLowerInvariant(),
			$this.Search ? "true" : "false"
		)
		
		$result = $this.History |
			Select-Object role, content |
			ConvertTo-Json -Compress |
			Invoke-RestMethod `
				-Uri $uri `
				-Method Post `
				-ContentType "application/json" `
				-Headers @{ "X-Auth-Token" = $this.Credentials.Secret }
		
		$response = $result.Content
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
		[String]$Username,
		[String]$Password,
		[String]$Host = "31.57.46.139:5050"
	)
	
	$save = $FileName -and [File]::Exists($FileName) `
		? (Get-Content -LiteralPath $FileName -Raw -Encoding utf8 | ConvertFrom-Json) `
		: ([PSObject]@{})
	
	$credentials = $Script:CredentialsFactory.Invoke()
	$credentials.Host = if ($Host) { $Host } else { $save.Host }
	$credentials.Secret = $save.Secret

	if (-not $credentials.Secret) {
		if (-not $credentials.Host) { $credentials.Host = Read-Host "host" }
		if (-not $credentials.Host) { throw "cannot use empty host" }
		
		if (-not $Username) { $Username = Read-Host "username" }
		if (-not $Username) { throw "cannot use empty username" }

		if (-not $Password) { $Password = Read-Host "password" -MaskInput }
		if (-not $Password) { throw "cannot use empty password" }
		
		$loginUri = [String]::Format(
			"http://{0}/auth/login",
			$credentials.Host
		)
		$loginBody = [PSObject]@{
			"username" = $Username
			"password" = $Password
		} | ConvertTo-Json -Compress
		
		$credentials.Secret = $loginBody |
			Invoke-RestMethod `
				-Uri $loginUri `
				-Method Post `
				-ContentType "application/json" |
			Select-Object -ExpandProperty token
	}
	
	if ($FileName) {
		$null = New-Item "$FileName\..\" -ItemType Directory -ErrorAction SilentlyContinue
		($credentials | ConvertTo-Json) > $FileName
	}
	
	return $credentials
}

Export-ModuleMember -Function New-LLM_Dialogue, Get-LLM_Credentials
