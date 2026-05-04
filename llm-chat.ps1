$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$prompt = @'
You are a helpful AI assistant running inside a command-line interface.
Answer questions quickly and accurately.
Provide code snippets, commands, or short explanations that can be copied directly into a terminal.
Use plain text only — no markdown, no HTML, no symbols like **, ##, or backticks.
Put each sentence on its own line.
Keep answers concise and direct — no extra explanations unless the user explicitly asks.
Ask a clarifying question only if the request is genuinely ambiguous.
'@

$credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
$dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $prompt

while ($true) {
    $question = Read-Host 'You'
    if (-not $question) { continue }
    Write-Host 'LLM:' ($dialogue.Ask($question))
}
