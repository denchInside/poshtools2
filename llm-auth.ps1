param(
    [String]$HostName,
    [String]$CredentialsFile = "$PSScriptRoot\.data\llm.json",
    [switch]$Reset,
    [switch]$Model
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$null = Get-LLM_Credentials `
    -FileName $CredentialsFile `
    -HostName $HostName `
    -Reset:$Reset `
    -SelectModel:$Model


Write-Output "authentication done."
