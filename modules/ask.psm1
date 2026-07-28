#Requires -Version 7.0

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

function Read-UserChoice(
    [Parameter(Mandatory)]
    [string] $Question,

    [string] $Format = 'y/N',

    [string] $Equals = 'y'
)
{
    <#
    .SYNOPSIS
        Prompts the user to pick one of several short variants, reprompting
        on invalid input instead of silently treating it as a denial.
    .PARAMETER Question
        The question text shown before the choice bracket.
    .PARAMETER Format
        Slash-separated list of accepted variants, e.g. 'y/n/E'. At most one
        variant may be uppercase; that variant becomes the default returned
        when the user presses Enter with no input.
    .PARAMETER Equals
        If non-empty, the function returns a [bool] indicating whether the
        user's choice equals this variant (case-insensitive). If empty, the
        function returns the matched variant itself, lowercased.
    .EXAMPLE
        Read-UserChoice -Question 'Approve?' -Format 'y/N'
    .EXAMPLE
        $choice = Read-UserChoice -Question 'Approve?' -Format 'y/n/E' -Equals ''
    #>

    $variants = $Format -split '/' | ForEach-Object { $_.Trim() };
    $defaultVariants = $variants | Where-Object { $_ -and [char]::IsUpper($_[0]) };

    if (@($defaultVariants).Count -gt 1)
    {
        throw [System.ArgumentException]::new('Format must contain at most one uppercase (default) variant', 'Format');
    }

    $default = $defaultVariants ? $defaultVariants.ToLowerInvariant() : $null;
    $lowerVariants = $variants | ForEach-Object { $_.ToLowerInvariant() };
    $prompt = "$Question [$($variants -join '/')]";

    $reply = $null;
    do
    {
        $reply = (Read-Host $prompt).Trim().ToLowerInvariant();
        if (-not $reply) { $reply = $default; }

        if ($reply -notin $lowerVariants)
        {
            Write-Host "Please answer one of: $($lowerVariants -join ', ')" -ForegroundColor Yellow;
        }
    }
    while ($reply -notin $lowerVariants);

    return $Equals ? ($reply -eq $Equals.ToLowerInvariant()) : $reply;
}

Export-ModuleMember -Function Read-UserChoice;
