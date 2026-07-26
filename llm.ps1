param(
    $Prompt,
    [String]$SystemPrompt,
    [switch]$Model,
    [switch]$Search,
    [switch]$Think = $true,
    [switch]$AsDialogue,
    [switch]$Reset,
    [switch]$ShowHistory
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$DefaultSystemPrompt = @'
YOU ARE AN AUTONOMOUS TERMINAL AGENT running inside "PowerShell 7".

GOAL LOOP — do this every turn, not just once:
1. DEFINE THE GOAL from the user's message and recent command history.
2. PLAN the steps needed to reach it.
3. ACT: call the "powershell" tool to gather info or make changes. You have the tool, use it, do not ask the user to run commands for you.
4. VERIFY before trusting a result. A command with narrow filters or exclusions can silently undercount or miss things, cross-check with a broader command if a number or listing looks suspicious.
5. REPEAT steps 2-4 with AS MANY tool calls as needed IN THIS SAME TURN. Do not stop after one step and wait for the user to say "do it" or "continue" or "recount", finishing the goal is your job, not theirs.
6. ONLY STOP when the goal is verifiably complete, or you truly cannot proceed without information only the user has.

TOOLS: "powershell" runs a command. The user approves or denies each one. Expect denials, read the feedback, adjust your plan, keep going.

FORMAT — follow exactly:
- NO markdown. No asterisks, backticks, headers, or bullet dashes.
- ONE sentence per line, NEVER two on one line.
- NO filler ("Sure!", "Great question", "Hope this helps").

Do the multi-step work silently through tool calls. BE CONCISE in what you actually say back.
'@

$PowerShellTool = [PSObject]@{
    type = "function"
    function = [PSObject]@{
        name = "powershell"
        description = "Run a PowerShell 7 command on the user's machine."
        parameters = [PSObject]@{
            type = "object"
            properties = [PSObject]@{
                command = [PSObject]@{
                    type = "string"
                    description = "The PowerShell 7 command to run."
                }
            }
            required = @("command")
        }
    }
}

function Invoke-LLM_PowerShellTool {
    param(
        [String]$Command
    )
    
    Write-Host ""
    Write-Host "MODEL WANTS TO RUN:"
    Write-Host $Command
    $approval = Read-Host "Approve? [y/N]"
    
    if ($approval -notin "y", "yes") {
        $feedback = Read-Host "Denied. Tell it why (optional)"
        if (-not $feedback) { $feedback = "Stop executing commands immediately" }
        return "User denied execution. LISTEN TO THE USER: $feedback"
    }
    
    try {
        return (Invoke-Expression $Command 2>&1 | Out-String)
    } catch {
        return "$_"
    }
}

function Invoke-LLM_ToolLoop {
    param(
        $Dialogue
    )
    
    $content = $null
    $consecutiveDenials = 0
    $maxConsecutiveDenials = 2
    $totalCalls = 0
    $maxTotalCalls = 20
    
    while ($Dialogue.PendingToolCalls) {
        foreach ($call in $Dialogue.PendingToolCalls) {
            $totalCalls++
            $arguments = $call.function.arguments | ConvertFrom-Json
            
            $output = switch ($call.function.name) {
                "powershell" { Invoke-LLM_PowerShellTool -Command $arguments.command }
                default { "Unknown tool: $($call.function.name)" }
            }
            
            if ($output.StartsWith("User denied execution")) {
                $consecutiveDenials++
            } else {
                $consecutiveDenials = 0
            }
            
            $Dialogue.SubmitToolResult($call.id, $call.function.name, $output)
        }
        
        if ($consecutiveDenials -ge $maxConsecutiveDenials) {
            Write-Host ""
            Write-Host "Stopping after $consecutiveDenials denials in a row, it wasn't listening."
            break
        }
        
        if ($totalCalls -ge $maxTotalCalls) {
            Write-Host ""
            Write-Host "Stopping after $totalCalls tool calls in one turn, that's too many for one question."
            break
        }
        
        $content = $Dialogue.Complete()
    }
    
    return $content
}

if (-not $global:__llm_Data) {
    $credentials = Get-LLM_Credentials -FileName "$PSScriptRoot\.data\llm.json" -SelectModel:$Model
    $dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $(if ($SystemPrompt) { $SystemPrompt } else { $DefaultSystemPrompt })
    $dialogue.SetTools(@($PowerShellTool))
    $global:__llm_Data = [PSObject]@{
        Dialogue = $dialogue
        LastCommandID = 0
    }
} elseif ($Model) {
    $global:__llm_Data.Dialogue.Credentials = Get-LLM_Credentials -FileName "$PSScriptRoot\.data\llm.json" -SelectModel
}

$data = $global:__llm_Data
$dialogue = $data.Dialogue
$dialogue.SetSearch($Search)
$dialogue.SetThink($Think)

if ($Reset -or $ShowHistory) {
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

if (-not $Prompt) {
    $Prompt = Read-Host "Prompt"
    if (-not $Prompt) { exit }
}
elseif ($Prompt -is [ScriptBlock]) {
    $realPrompt = Read-Host "Prompt"
    $output = try { & $Prompt 2>&1 | Out-String } catch { "$_" }
    $output = "Code provided by user:`n$Prompt`n`nCode output:`n$output"
    $Prompt = if ($realPrompt) { "User question:`n$realPrompt`n`n$output" } else { $output }
}
else {
    $Prompt = "$Prompt"
}

$history = Get-History -Count 30 |
    Where-Object -Property Id -GE $data.LastCommandID |
    Where-Object { $_.CommandLine -notlike "llm*" }

$lastId = $history | Sort-Object -Property Id | Select-Object -ExpandProperty Id -Last 1
if ($lastId) { $data.LastCommandID = $lastId }

if ($history) {
    $historyLines = $history | ForEach-Object {
        [String]::Format(
            "{0}`t{1}",
            $_.StartExecutionTime.ToString("HH:mm"),
            $_.CommandLine
        )
    }
    $dialogue.Append("user", $historyLines -join "`n")
}

$response = $dialogue.Ask($Prompt)
$toolResponse = Invoke-LLM_ToolLoop -Dialogue $dialogue
if ($null -ne $toolResponse) { $response = $toolResponse }

if ($AsDialogue) {
    Write-Output $dialogue.History
} else {
    Write-Output $response
}
