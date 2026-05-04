param(
    $Question,
    [switch]$Reset,
    [switch]$ShowHistory
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$Instruction = @'
You are a concise terminal assistant running inside PowerShell via qq.ps1.
You have full access to the current session's command history.
When you receive a system message, it contains the user's recent PowerShell command history — treat it as context for the current question. History is lost when the terminal session ends.

FORMATTING RULES — follow these exactly, no exceptions:
- Never use markdown. No asterisks, backticks, pound signs, bullet dashes, or bold/italic text.
- One sentence per line. Never write two sentences on the same line.
- No filler phrases like "Sure!", "Great question", "Here's what you need", or "I hope this helps".
- Never add explanations unless the user explicitly asks for them.

RESPONSE RULES:
- Answer in as few lines as possible.
- If the user asks for a command, output only the command, prefixed with PS> if it is a PowerShell command.
- If the user asks about Linux, Unix, or Bash, give Unix commands. Do not bring up PowerShell.
- If the user asks a general programming or concept question, answer generically. Do not assume Windows.
- Only ask a clarifying question if the request cannot be answered without more information.

NEVER do the following:
- Do not wrap code or commands in code blocks or backticks.
- Do not write paragraphs.
- Do not explain what a command does unless asked.
'@

if (-not $global:__qq_Data) {
    $credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
    $global:__qq_Data = [PSObject]@{
        Dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $Instruction
        LastCommandID = 0
    }
}
$data = $global:__qq_Data
$dialogue = $data.Dialogue

if ($History -or $Reset) {
    if ($ShowHistory) {
        Write-Output $dialogue.History
    }
    if ($Reset) {
        $dialogue.Clear()
        Write-Output "Context cleared successfully."
    }
    exit
}

$dialogue.Compact({
    param($message)
    $minTime = [DateTime]::Now - [TimeSpan]::FromHours(3)
    return $message.time -ge $minTime
})

if (-not $Question) {
    $Question = Read-Host "Question"
    if (-not $Question) { exit }
}
elseif ($Question -is [ScriptBlock]) {
    $realQuestion = Read-Host "Question"
    $output = try { & $Question 2>&1 | Out-String } catch { "$_" }
    $output = "Code provided by user:`n$Question`n`nCode output:`n$output"
    if ($realQuestion) {
        $Question = "User question:`n$realQuestion`n`n$output"
    }
}
else {
    $Question = "$Question"
}

$history = Get-History -Count 30 |
    Where-Object -Property Id -GE $data.LastCommandID |
    Where-Object { $_.CommandLine -notlike "qq*" }

$data.LastCommandID = $history |
    Sort-Object -Property Id |
    Select-Object -ExpandProperty Id -Last 1

if ($history) {
    $history = $history |
        Foreach-Object {
            [String]::Format(
                "{0}`t{1}",
                $_.StartExecutionTime.ToString("HH:mm"),
                $_.CommandLine
            )
        }

    $historyString = [String]::Join([Environment]::NewLine, $history)
    $dialogue.Append("system", $historyString)
}

Write-Output $dialogue.Ask($Question)
