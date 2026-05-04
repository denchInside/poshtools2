$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

function Ask-User {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Question,
        [String]$Format = "y/N",
        [String]$Equals = "y"
    )
    
    $variants = $Format -split '/' |
        ForEach-Object { $_.Trim() }
    $default = $variants |
        Where-Object { [Char]::IsUpper($_[0]) }
    $Format = $variants -join '/'
    
    if ($default.Length -gt 1) {
        throw "invalid format: multiple default variants"
    }
    
    $reply = $null
    $prompt = "$Question [$Format]"

    do {
        $reply = (Read-Host $prompt).Trim()
        if (-not $reply) { $reply = $default }
    } while (
        $reply -notin $variants
    )

    return $Equals ? ($reply -eq $Equals) : $reply
}

Export-ModuleMember -Function Ask-User
