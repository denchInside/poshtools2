param(
	[Parameter(Mandatory = $true)]
	[String]$Prompt,
	[String]$SystemPrompt,
	[ValidateSet("quality", "speed")]
	[String]$Mode = "speed",
	[switch]$Search = $false,
	[switch]$AsDialogue = $false
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
$poshIsShit = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $SystemPrompt
$poshIsShit.SetMode($Mode)
$poshIsShit.SetSearch($Search)
$text = $poshIsShit.Ask($Prompt)

if ($AsDialogue) {
	Write-Output $poshIsShit.History
} else {
	Write-Output $text
}
