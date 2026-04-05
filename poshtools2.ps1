using namespace System.IO

param(
	[Parameter(Position = 0)]
	[ValidateSet("Help", "Update", "UpdateShims", "ChangeDirectory", "Explorer", "DeveloperMode")]
	[String]$Category = "Help",
	[Parameter(Position = 1)]
	[String]$Action
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$GitRepo = 'http://192.168.178.42/dxizx/poshtools2.git'
$GuardFile = "$PSScriptRoot\.poshtools-is-dev-root"

function Category-Help {
	Get-Help $PSCommandPath
	Write-Output "Use <Tab> to navigate through possible values."
}

function Category-ChangeDirectory {
	Set-Location $PSScriptRoot
}

function Category-Explorer {
	explorer.exe $PSScriptRoot
}

function Category-DeveloperMode {
	param(
		[ValidateSet("Enable", "Disable")]
		$DeveloperMode
	)
	
	switch ($DeveloperMode) {
		"Disable" {
			Remove-Item -LiteralPath $GuardFile -ErrorAction SilentlyContinue
			Write-Output "Developer mode is disabled. Repository can update now."
		}
		"Enable" {
			New-Item -Path $GuardFile -ItemType File -ErrorAction SilentlyContinue | Out-Null
			Write-Host "Developer mode is enabled. Modifications are now secured."
		}
	}
}

function Category-Update {
	Import-Module "$PSScriptRoot\modules\path.psm1" -Scope Local
	
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-Error "Git installation is required."
	}

	if ([File]::Exists($GuardFile)) {
		Write-Error "I cannot update the development repository."
	}

	git -C $PSScriptRoot fetch --all &&
	git -C $PSScriptRoot reset --hard origin/main &&
	git -C $PSScriptRoot clean -fd

	Register-Path -Path $PSScriptRoot -Permanent
	Category-UpdateShims
}

function Category-UpdateShims {
	Import-Module "$PSScriptRoot\modules\path.psm1" -Scope Local
	Import-Module "$PSScriptRoot\modules\shim.psm1" -Scope Local
	
	$shimsPath = "$PSScriptRoot\.data\shims"
	$null = [Directory]::CreateDirectory($shimsPath)
	
	$shims = Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter "*.ps1" |
		ForEach-Object {
			New-PSShim -FromFile $_ -OutputDirectory $shimsPath
		}
	
	Register-Path -Path $shimsPath -Permanent
	Write-Host $shims
}

$FunctionLookup = @{
	"Help" = ${Function:Category-Help}
	"Explorer" = ${Function:Category-Explorer}
	"ChangeDirectory" = ${Function:Category-ChangeDirectory}
	"DeveloperMode" = ${Function:Category-DeveloperMode}
	"Update" = ${Function:Category-Update}
	"UpdateShims" = ${Function:Category-UpdateShims}
}

& $FunctionLookup[$Category] $Action
