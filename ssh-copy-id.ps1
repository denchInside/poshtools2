using namespace System.IO;

param(
	[string]$HostName,
	$Port = $null,
	[string]$Identity = $null
)

$ErrorActionPreference = "Stop"

function Assert($That, $Else) {
	if (-not $That) {
		$lambda = ($Else -as [ScriptBlock]) ?? { $Else }
		$text = ((& $lambda) -as [string]) ?? "Assertion failed: {$That} is falsy."
		throw $text
	}
	
	return $That
}

class SshProfileInfo {
	[string]$Directory
	[string]$DefaultKey
	[string[]]$SavedKeys
}

$Script:DefaultKeys = @(
    "id_ed25519_sk.pub",      # Ed25519 with security key (hardware-backed)
    "id_ecdsa_sk.pub",        # ECDSA with security key (hardware-backed) 
    "id_ed25519.pub",         # Ed25519 (most secure standard key)
    "id_ecdsa.pub",           # ECDSA (good security, elliptic curve)
    "id_rsa.pub",             # RSA (secure with proper key length)
    "id_dsa.pub"              # DSA (legacy, weakest, deprecated)
)

function Get-SshProfile($SshProfileDir) {
	$result = [SshProfileInfo]::new()
	$result.Directory = [Path]::GetFullPath($SshProfileDir)
	
	$result.SavedKeys =
		[Directory]::GetFiles($result.Directory, "*.pub") |
		ForEach-Object { [Path]::GetFileName($_) }
	
	foreach ($key in $Script:DefaultKeys) {
		if ($key -in $result.SavedKeys) {
			$result.DefaultKey = $key
			break
		}
	}
	
	return $result
}

function Parse-HostName($HostName) {
	($user, $host_) = $HostName -split "@"
	
	return $user -and $host_ `
		? @{ User = $user; Host = $host_ } `
		: $null
}

try {
	$Port = Assert `
		-That (($Port ?? 22) -as [int]) `
		-Else { "Invalid -Port: $Port" }
	
	$null = Assert `
		-That (Parse-HostName $HostName) `
		-Else { "Invalid -HostName: $HostName" }

	$Script:Name = [Path]::GetFileName($PSCommandPath)
	
	$Script:SshProfileDir = "$env:USERPROFILE\.ssh"
	$Script:SshProfile = Get-SshProfile $Script:SshProfileDir
	
	$Script:SshProfileNotFoundError = {
		"Public key not found, try one of these: {0}" `
			-f ($Script:SshProfile.SavedKeys -join ", ")
	}
	
	if (-not $Identity) {
		if (-not $Script:SshProfile.DefaultKey) {
			$choice = $Host.UI.PromptForChoice(
				"No key found",
				"No default key found. Generate a new one?",
				@('&Yes', '&No'), 0
			)
			
			$null = Assert `
				-That ($choice -eq 0) `
				-Else $Script:SshProfileNotFoundError
			
			ssh-keygen
			$Script:SshProfile = Get-SshProfile $Script:SshProfileDir
		}

		$Identity = Assert `
			-That $Script:SshProfile.DefaultKey `
			-Else $Script:SshProfileNotFoundError
	}
	
	if ("\" -notin $Identity -and "/" -notin $Identity) {
		$Identity = [Path]::Combine($Script:SshProfile.Directory, $Identity)
		$null = Assert `
			-That ([File]::Exists($Identity)) `
			-Else $Script:SshProfileNotFoundError
	}


	Get-Content $Identity -Encoding Utf-8 |
		ssh -p $Port $HostName "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
	
	$null = Assert `
		-That ($LASTEXITCODE -eq 0) `
		-Else { "Key transfer failed with exit code $LASTEXITCODE." }
	
	Write-Host "Public key copied successfully."
} catch {
	Write-Host "$Script:Name`:" $_ -ForegroundColor Red
	exit 1
}
