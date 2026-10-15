#Requires -Version 7.0

param(
    [string] $HostName,
    [string] $CredentialsFile = "$PSScriptRoot\.data\llm.json",
    [switch] $Reset,
    [switch] $Model
)

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local;

$credentials = Get-LLM_Credentials `
    -FileName $CredentialsFile `
    -HostName $HostName `
    -Reset:$Reset `
    -SelectModel:$Model;

# Push the new credentials into the live dialogue cached by llm.ps1, if any.
# Property-wise copy (via Sync-LLM_DialogueCredentials) so this works across
# the separate module instances each script imports with -Scope Local.
if ($global:__llm_Data -and $global:__llm_Data.Dialogue)
{
    $null = Sync-LLM_DialogueCredentials -Dialogue $global:__llm_Data.Dialogue -Credentials $credentials;
}

Write-Host 'authentication done.' -ForegroundColor Green;
