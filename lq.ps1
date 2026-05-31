param(
    [Parameter(Mandatory=$true)]
    [String]$Text,

    [Parameter(Mandatory=$true)]
    [String]$Language
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local
Import-Module -Name International -UseWindowsPowerShell -Scope Local

$Prompt = @'
YOUR ROLE IS THE TRANSLATOR. YOU HELP TRANSLATING TEXT.
YOU MUST TRANSLATE USER'S MESSAGE TO THE {0} LANGUAGE AND ONLY THIS LANGUAGE.
DO NOT ANSWER QUESTIONS OR CONVERSE IN ANY WAY OTHER THAN TRANSLATING.
DO NOT WRITE ANY PREAMBLE TEXT, ONLY THE ACCURATE TRANSLATION AND NOTHING ELSE.
'@

$Credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
$Dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt ($Prompt -f $Language.ToUpper())

$Response = $Dialogue.Ask($Text)
Write-Output $Response
