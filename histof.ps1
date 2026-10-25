using namespace System.Collections.Generic;
using namespace System.Linq;

using module .\modules\ask.psm1;

param(
    [string] $Text,
    [switch] $Exact,
    [int] $Last = -1,
    [switch] $Compress
);

$ErrorActionPreference = 'Stop';
$historyFile = "$env:AppData\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";

[string[]] $historyContents = @(
    Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue
);

if (-not $historyContents)
{
    exit 0;
}

[Array]::Reverse($historyContents);
$uncompressedCount = $historyContents.Count;
$historyContents = [Enumerable]::Distinct($historyContents);

if ($Text)
{
    if ($Compress)
    {
        Write-Host "Cannot combine -Compress with -Text.";
        exit 1;
    }

    if ($Last -lt 0)
    {
        $Last = 15;
    }

    $matches = $historyContents.Where({
        (-not $Exact -and $_ -like $Text) -or $_.StartsWith($Text)
    });

    [Enumerable]::Take($matches, $Last) | Out-Host;
    Write-Host "$($matches.Count) entries found.";
}

if ($Compress)
{
    [Array]::Reverse($historyContents);

    if ($Last -ge 0 -and (Read-UserChoice -Question "Limit history to $Last last entries?" -Equals "y"))
    {
        $historyContents = [Enumerable]::TakeLast($historyContents, $Last);
    }

    $historyContents | Out-File -LiteralPath $historyFile -Encoding utf8;
    Write-Host "Compressed from $($uncompressedCount) to $($historyContents.Count) lines";
}
