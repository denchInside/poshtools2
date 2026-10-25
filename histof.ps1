using namespace System.Collections.Generic;

using module .\modules\ask.psm1;

param(
    [string] $Entry,
    [string] $Pattern,
    [int] $Last = -1,
    [switch] $Compress
);

$ErrorActionPreference = 'Stop';
$historyFile = "$env:AppData\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";

$historyContents = @(
    Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue
);

if (-not $historyContents)
{
    exit 0;
}

[Array]::Reverse($historyContents);
$uncompressedCount = $historyContents.Count;
$historyContents = $historyContents | Select-Object -Unique

if ($Entry -or $Pattern)
{
    if ($Compress)
    {
        Write-Host "Cannot combine -Compress with -Entry or -Pattern.";
        exit 1;
    }

    if ($Last -lt 0)
    {
        $Last = 15;
    }

    $matches = $historyContents | Where-Object {
        ($Entry -and $_.StartsWith($Entry)) -or ($Pattern -and $_ -like $Pattern)
    };

    $matches | Select-Object -First $Last | Out-Host;
    Write-Host "$($matches.Count) entries found.";
}

if ($Compress)
{
    [Array]::Reverse($historyContents);

    if ($Last -ge 0 -and (Read-UserChoice -Question "Limit history to $Last last entries?" -Equals "y"))
    {
        $historyContents = $historyContents | Select-Object -Last $Last;
    }

    $historyContents | Out-File -LiteralPath $historyFile -Encoding utf8;
    Write-Host "Compressed from $($uncompressedCount) to $($historyContents.Count) lines";
}
