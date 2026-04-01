using namespace System.IO

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

$InstallDir = "$Env:APPDATA\poshtools2"

$git = Get-Command git -ErrorAction SilentlyContinue
$poshtools2 = "$InstallDir\poshtools2.ps1"

if (-not $git) {
	Write-Error "Git installation is required."
}

if (-not [Directory]::Exists($InstallDir)) {
	$null = New-Item -Path $InstallDir -ItemType Directory
	& $git clone --depth 1 'http://192.168.178.42/dxizx/poshtools2.git' $InstallDir
}

& $poshtools2 Update
