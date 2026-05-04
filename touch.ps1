using namespace System.IO

param(
    [Parameter(Mandatory = $true)]
    [String]$FileName
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

$FileName = [Path]::GetFullPath($FileName, $pwd)

if ([Path]::Exists($FileName)) {
    Write-Error "already exists."
}

$null = New-Item $FileName -ItemType File
