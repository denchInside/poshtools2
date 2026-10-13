using namespace System.Collections.Generic;

param(
    [string] $Entry = "",
    [string] $Pattern = "",
    [int] $Last = 10,
    [switch] $Compress
);

$ErrorActionPreference = 'Stop';
$historyFile = "$env:AppData\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";
$historyContents = @(Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue);

if ($Entry -or $Pattern)
{
    $matches = @($historyContents[-1..-$historyContents.Count] | Where-Object {
        ($Entry -and $_.StartsWith($Entry)) -or ($Pattern -and $_ -like $Pattern)
    });

    $matches | Select-Object -Unique | Select-Object -First $Last | Write-Host;
    Write-Host "$($matches.Count) entries found.";
}

if ($Compress)
{
    $unique = $historyContents | Select-Object -Unique;
    $unique | Out-File -LiteralPath $historyFile -Encoding utf8;
    Write-Host "Compressed from $($historyContents.Count) to $($unique.Count) lines";
}
