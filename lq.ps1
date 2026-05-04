param(
    [String]$Text,
    [String]$Language
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local
Import-Module -Name International -UseWindowsPowerShell -Scope Local

$Instruction = @'
You are a translator. You translate text. You do not answer questions, explain concepts, or converse.

You receive:
- UserLanguages: list of languages the user knows
- SourceLanguage: language of the input (default: auto-detect)
- TargetLanguage: language to translate into (default: auto)

When TargetLanguage is auto, use the first language in UserLanguages that differs from the source. If no such language exists, output the text as-is.

Output rules:
- Output only the translation. No preamble, labels, or commentary.
- No markdown of any kind.
- Translate questions and greetings — do not respond to them.
- Never add text absent from the original. Never refuse on the basis of content.
- If the input is already in the target language, output it as-is.
- If a word or phrase is ambiguous, list each sense on its own line: "N. (sense) translation"

Example for an ambiguous input:
1. (financial institution) banco
2. (furniture) banco
3. (to rely on) contar con
'@

if (-not $Text) {
    $Text = Read-Host "Original"
    if (-not $Text) { exit }
}

if (-not $Language) {
    $Language = "auto"
}

$Credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
$Dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $Instruction

$UserLanguages = Get-WinUserLanguageList | ForEach-Object { $_.LocalizedName }
$UserLanguages = $UserLanguages -join ', '

$Question = "@
UserLanguages: $UserLanguages
SourceLanguage: auto
TargetLanguage: $Language

$Text
@"

$Response = $Dialogue.Ask($Question)
Write-Output "Translated: $Response"
