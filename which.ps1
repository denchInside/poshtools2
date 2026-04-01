[CmdletBinding()]
param(
	[Parameter(Position=0, Mandatory=$false)]
	[string]$Name,
	[Parameter(Mandatory=$false)]
	[switch]$Quiet
)

$ErrorActionPreference = "Stop"

if (-not $Name) {
	exit 1
}

$command = Get-Command $Name -ErrorAction SilentlyContinue

if (-not $command) {
	if (-not $Quiet) {
		Write-Output "$Name not found"
	}
	exit 1
}

Write-Output $command.Path
exit 0
