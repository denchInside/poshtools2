using namespace System.Collections.Generic

param(
    [ValidateSet("review")]
    [Parameter(Mandatory = $true)]
    [String]$Action
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module "$PSScriptRoot\modules\ask.psm1" -Scope Local

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git not found"
}

$Prompts = @{
    "review" = @{
        SystemPrompt = @'
You are an AI that generates concise, high‑quality commit messages from a given `git diff`.

Your task:
1. Read the diff text (added, removed, or modified lines).
2. Summarize the overall purpose of the change in **≤ 72 characters**, using the imperative mood (e.g., "Fix …", "Add …", "Refactor …").
3. Include only the most important functional impact; ignore formatting‑only changes unless they affect behavior.
4. Do not mention file names, line numbers, or diff symbols.
5. Do not end the message with a period.
6. Output **only** the commit summary — no extra explanation or markup.

Focus on **why** the change exists or **what problem it solves**, not on the literal steps the code performs — even when only a single file was changed. For example, prefer "Support offline installation via local clone" over "Create install dir, clone via $git, and run update script".

If the diff contains multiple unrelated changes, produce a short, combined summary that captures the primary intent.
'@
        Command = {
            if (Ask-User "run 'git add .'?") {
                $null = git -C "$pwd" add .
            }
            
            $groupDiffs = @{}
            $groupCurrent = "unknown"
            $bigDiff = git -C "$pwd" --no-pager diff --cached -U1

            $nowChars = 0
            $maxChars = 1000
            $newLineLength = [Environment]::NewLine.Length
            
            # diff grouping by '^@@ .* @@'
            foreach ($line in $bigDiff) {                
                if ($line -match '^@@ .* @@') {
                    $groupCurrent = $line
                }
                if (-not $groupDiffs.ContainsKey($groupCurrent)) {
                    $groupDiffs[$groupCurrent] = [LinkedList[String]]::new()
                }

                $null = $groupDiffs[$groupCurrent].AddLast($line)
                $nowChars += $line.Length + $newLineLength
            }
            
            # line deletion (prioritizes the biggest group)
            while ($nowChars -gt $maxChars) {
                $maxCount = ($groupDiffs.Values |
                    Measure-Object -Property Count -Maximum).Maximum
                
                foreach ($group in $groupDiffs.Values) {
                    if ($nowChars -le $maxChars) { break }
                    
                    if ($group.Count -ge $maxCount) {
                        $nowChars -= $group.Last.Value.Length + $newLineLength
                        $group.RemoveLast()
                    }
                }
            }
            
            $strDiff = $groupDiffs.Values |
                ForEach-Object { $_ } |
                Out-String
            
            $strDiff
        }
    }
}

Import-Module "$PSScriptRoot\modules\llm.psm1" -Scope Local

$prompt = & $Prompts[$Action].Command

if ($prompt) {
    $credentials = Get-LLM_Credentials "$PSScriptRoot\.data\llm.json"
    $dialogue = New-LLM_Dialogue -Credentials $credentials -SystemPrompt $Prompts[$Action].SystemPrompt
    $dialogue.SetMode("speed")
    Write-Output $dialogue.Ask("$prompt")
} else {
    Write-Output "nothing to do."
}
