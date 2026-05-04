param(
    [String]$Username,
    [String]$Password,
    [String]$HostName,
    [String]$CredentialsFile = "$PSScriptRoot\.data\llm.json",
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

if ($Reset) {
    Remove-Item -LiteralPath $CredentialsFile -ErrorAction SilentlyContinue
}

$null = Get-LLM_Credentials `
    -FileName $CredentialsFile `
    -Username $Username `
    -Password $Password `
    -HostName $HostName


Write-Output "authentication done."
