using namespace System.IO

[CmdletBinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
    [string] $Source,
	
    [Parameter(Position=1, Mandatory=$false)]
    [string] $Destination,
    
	[Parameter(Mandatory=$false)]
	[switch]$Junction,
	
	[Parameter(Mandatory=$false)]
	[switch]$Hard
)

$ErrorActionPreference = "Stop"

# Usage on empty/incomplete params
if (-not $Source -or -not $Destination) {
	Write-Host "usage: ln.ps1 [-J|-H] <Source> <Destination>"
	exit 0
}

# Link type
$linkType = 'SymbolicLink'

if ($Junction -and $Hard) {
    Write-Error "can not apply both -Junction and -Hard"
} elseif ($Junction) {
	$linkType = 'Junction'
} elseif ($Hard) {
	$linkType = 'HardLink'
}

# Dest should not exist
if ([Path]::Exists($Destination)) {
    Write-Error "$Destination already exists"
    exit 1
}

# Source has to exist
$sourceInfo = Get-Item -LiteralPath $Source -ErrorAction SilentlyContinue

if (-not $sourceInfo) {
    Write-Error "$Source does not exist"
}

$linkFullPath = [System.IO.Path]::GetFullPath($Destination)

# Determine link type
if ($Junction -and $sourceInfo -isnot [DirectoryInfo]) {
	Write-Error "can not create junction to a file"
} elseif ($Hard -and $sourceInfo -isnot [FileInfo]) {
	Write-Error "can not create hardlink to a directory"
}

$linkInfo = New-Item -ItemType $linkType -Path $linkFullPath -Target $sourceInfo.FullName #-ErrorAction SilentlyContinue
Write-Output $linkInfo
