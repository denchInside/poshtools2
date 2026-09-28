#Requires -Version 7.0

param(
    [string] $Path,
    [string[]] $Include
)

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

$total = Get-ChildItem -Recurse -Path $Path -Include $Include |
    Get-Content |
    Measure-Object -Line;

Write-Host $total.Lines;
