using namespace System.Collections.Generic;

param(
    [string] $Entry = "",
    [string] $Pattern = "",
    [int] $Last = 10
);

$ErrorActionPreference = 'Stop';
$historyFile = "$env:AppData\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";
$historyContents = Get-Content -LiteralPath $historyFile -ErrorAction SilentlyContinue;
$lineCount = [int] $historyContents.Length;

$entries = [HashSet[string]]::new();
$entriesTotal = 0;

for ($i = $lineCount - 1; $i -gt 0; $i--)
{
    $item = $historyContents[$i];

    if (($Entry -and $item.StartsWith($Entry)) -or ($Pattern -and $item -like $Pattern))
    {
        $entriesTotal++;

        if ($entries.Count -le $Last)
        {
            $null = $entries.Add($item);
        }
    }
}

foreach ($entry in $entries)
{
    Write-Host $entry;
}

Write-Host "$entriesTotal entries found."
