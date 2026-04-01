using namespace System.IO

[CmdletBinding()]
param(
	[Parameter(Position=0, Mandatory=$false)]
	[string]$InputPath
)

$ErrorActionPreference = "Stop"
$Script:NppPath = [Path]::Combine($Env:ProgramFiles, "Notepad++", "notepad++.exe")

if ([File]::Exists($Script:NppPath) -eq $false) {
	Write-Error "$Script:NppPath not found."
}

if ([Directory]::Exists($InputPath)) {
	Write-Error "$InputPath is a directory."
}

$AbsInputPath = [Path]::GetFullPath($InputPath, "$pwd")
& $Script:NppPath $InputPath
