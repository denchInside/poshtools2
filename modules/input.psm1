#Requires -Version 7.0

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

function Get-Input_ConsoleWidth
{
    $width = 0;

    try { $width = [Console]::BufferWidth; } catch { $width = 0; }

    if ($width -le 0)
    {
        try { $width = [Console]::WindowWidth; } catch { $width = 0; }
    }

    if ($width -le 0) { $width = 80; }

    return [Math]::Max(20, $width);
}

function Get-Input_ClipboardText
{
    try
    {
        $text = Get-Clipboard -Raw -ErrorAction Stop;

        if ($null -ne $text) { return "$text"; }
    }
    catch { }

    return '';
}

function Format-Input_Clean([string] $Text)
{
    if (-not $Text) { return ''; }

    $clean = $Text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`t", '    ');
    $clean = [regex]::Replace($clean, "`e\[[0-9;]*[A-Za-z~]", '');

    $builder = [System.Text.StringBuilder]::new($clean.Length);

    foreach ($char in $clean.ToCharArray())
    {
        if ($char -eq [char] "`n" -or -not [char]::IsControl($char)) { [void] $builder.Append($char); }
    }

    return $builder.ToString();
}

function Add-Input_Text($State, [string] $Text)
{
    $clean = Format-Input_Clean $Text;

    if ($clean.Length -eq 0) { return; }

    [void] $State.Buffer.Insert($State.Cursor, $clean);
    $State.Cursor += $clean.Length;
}

function Get-Input_Position($State, [int] $Index)
{
    $row = 0;
    $col = $State.StartLeft;
    $width = $State.Width;
    $text = $State.Buffer.ToString();
    $limit = [Math]::Max(0, [Math]::Min($Index, $text.Length));

    for ($i = 0; $i -lt $limit; $i++)
    {
        if ($text[$i] -eq [char] "`n") { $row++; $col = 0; continue; }

        $col++;

        if ($col -ge $width) { $row++; $col = 0; }
    }

    return @{ Row = $row; Col = $col };
}

function Get-Input_DiffStart([string] $Old, [string] $New)
{
    $limit = [Math]::Min($Old.Length, $New.Length);

    for ($i = 0; $i -lt $limit; $i++)
    {
        if ($Old[$i] -ne $New[$i]) { return $i; }
    }

    return $limit;
}

function Show-Input_Buffer($State, [switch] $Mask)
{
    $text = $State.Buffer.ToString();
    $shown = $text;

    if ($Mask)
    {
        $masked = [System.Text.StringBuilder]::new($text.Length);

        foreach ($char in $text.ToCharArray())
        {
            if ($char -eq [char] "`n") { [void] $masked.Append("`n"); }
            else { [void] $masked.Append('*'); }
        }

        $shown = $masked.ToString();
    }

    $cells = $text.Length;
    $end = Get-Input_Position $State $cells;
    $from = Get-Input_DiffStart $State.PrevText $text;

    $visible = $true;

    try { $visible = [Console]::CursorVisible; [Console]::CursorVisible = $false; } catch { }

    $left = 0;
    $top = 0;

    try
    {
        $at = Get-Input_Position $State $from;

        try { [Console]::SetCursorPosition([Math]::Min($at.Col, $State.Width - 1), $State.StartTop + $at.Row); }
        catch
        {
            try { $State.StartTop = [Math]::Max(0, [Console]::BufferHeight - 1 - $end.Row); } catch { }

            $at = Get-Input_Position $State $from;

            try { [Console]::SetCursorPosition([Math]::Min($at.Col, $State.Width - 1), $State.StartTop + $at.Row); } catch { }
        }

        [Console]::Write($shown.Substring($from));

        $over = $State.PrevCells - $cells;

        if ($over -gt 0) { [Console]::Write(' ' * $over); }

        try
        {
            $drift = ($State.StartTop + $end.Row) - [Console]::CursorTop;

            if ($drift -ne 0) { $State.StartTop -= $drift; }
        }
        catch { }

        $State.PrevCells = $cells;
        $State.PrevText = $text;

        $cur = Get-Input_Position $State $State.Cursor;
        $left = [Math]::Min($cur.Col, $State.Width - 1);
        $top = $State.StartTop + $cur.Row;

        try { $height = [Console]::BufferHeight; } catch { $height = $top + 1; }

        if ($top -ge $height) { $top = $height - 1; }
        if ($top -lt 0) { $top = 0; }
    }
    finally
    {
        try { [Console]::SetCursorPosition($left, $top); } catch { }
        try { [Console]::CursorVisible = $visible; } catch { }
    }
}

function Get-Input_WordStart([string] $Text, [int] $Index)
{
    $i = [Math]::Max(0, [Math]::Min($Index, $Text.Length));

    while ($i -gt 0 -and ($Text[$i - 1] -eq ' ' -or $Text[$i - 1] -eq [char] "`n")) { $i--; }
    while ($i -gt 0 -and $Text[$i - 1] -ne ' ' -and $Text[$i - 1] -ne [char] "`n") { $i--; }

    return $i;
}

function Get-Input_WordEnd([string] $Text, [int] $Index)
{
    $i = [Math]::Max(0, [Math]::Min($Index, $Text.Length));

    while ($i -lt $Text.Length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq [char] "`n")) { $i++; }
    while ($i -lt $Text.Length -and $Text[$i] -ne ' ' -and $Text[$i] -ne [char] "`n") { $i++; }

    return $i;
}

function Get-Input_LineStart([string] $Text, [int] $Index)
{
    $i = [Math]::Max(0, [Math]::Min($Index, $Text.Length));

    if ($i -le 0) { return 0; }

    $found = $Text.LastIndexOf("`n", $i - 1);

    return ($found -lt 0) ? 0 : ($found + 1);
}

function Get-Input_LineEnd([string] $Text, [int] $Index)
{
    $i = [Math]::Max(0, [Math]::Min($Index, $Text.Length));
    $found = $Text.IndexOf("`n", $i);

    return ($found -lt 0) ? $Text.Length : $found;
}

function Read-Input_Multiline(
    [string] $Prompt = 'Prompt',
    [switch] $Mask
)
{
    <#
    .SYNOPSIS
        Reads one multiline input with safe paste handling.
    .DESCRIPTION
        Enter submits, Shift+Enter (or Ctrl+Enter) inserts a newline, Esc cancels
        and returns $null. Ctrl+V (or Shift+Insert) pastes the clipboard as text:
        embedded newlines stay in the buffer and never submit. Pasted bursts that
        arrive as keystrokes are detected through pending input and also stay in
        the buffer. Falls back to Read-Host when the console is not interactive.
    #>

    $interactive = $false;

    try { $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and $Host.Name -eq 'ConsoleHost'; }
    catch { $interactive = $false; }

    if (-not $interactive)
    {
        $canMask = $false;

        try { $canMask = -not [Console]::IsInputRedirected; } catch { $canMask = $false; }

        if ($Mask -and $canMask)
        {
            try { return Read-Host $Prompt -MaskInput; } catch { }
        }

        return Read-Host $Prompt;
    }

    try
    {
        [Console]::Write($Prompt + ': ');

        $state = @{
            Buffer = [System.Text.StringBuilder]::new();
            Cursor = 0;
            PrevCells = 0;
            PrevText = '';
            StartLeft = [Console]::CursorLeft;
            StartTop = [Console]::CursorTop;
            Width = Get-Input_ConsoleWidth;
        };

        $done = $false;
        $cancelled = $false;

        while (-not $done)
        {
            $key = [Console]::ReadKey($true);
            $control = ($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0;
            $shift = ($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0;
            $alt = ($key.Modifiers -band [ConsoleModifiers]::Alt) -ne 0;
            $ctrlOnly = $control -and -not $alt;
            $text = $state.Buffer.ToString();
            $handled = $false;

            if ($ctrlOnly)
            {
                $handled = $true;

                switch ($key.Key)
                {
                    ([ConsoleKey]::V) { Add-Input_Text $state (Get-Input_ClipboardText); }
                    ([ConsoleKey]::C) { $cancelled = $true; $done = $true; }
                    ([ConsoleKey]::D)
                    {
                        if ($state.Buffer.Length -eq 0) { $cancelled = $true; $done = $true; }
                    }
                    ([ConsoleKey]::A) { $state.Cursor = Get-Input_LineStart $text $state.Cursor; }
                    ([ConsoleKey]::E) { $state.Cursor = Get-Input_LineEnd $text $state.Cursor; }
                    ([ConsoleKey]::U)
                    {
                        $from = Get-Input_LineStart $text $state.Cursor;
                        [void] $state.Buffer.Remove($from, $state.Cursor - $from);
                        $state.Cursor = $from;
                    }
                    ([ConsoleKey]::K)
                    {
                        $to = Get-Input_LineEnd $text $state.Cursor;
                        [void] $state.Buffer.Remove($state.Cursor, $to - $state.Cursor);
                    }
                    ([ConsoleKey]::W)
                    {
                        $from = Get-Input_WordStart $text $state.Cursor;
                        [void] $state.Buffer.Remove($from, $state.Cursor - $from);
                        $state.Cursor = $from;
                    }
                    default { $handled = $false; }
                }
            }

            if (-not $handled)
            {
                switch ($key.Key)
                {
                    ([ConsoleKey]::Enter)
                    {
                        if ($shift -or $ctrlOnly) { Add-Input_Text $state "`n"; }
                        elseif ([Console]::KeyAvailable) { Add-Input_Text $state "`n"; }
                        else { $done = $true; }
                    }
                    ([ConsoleKey]::Escape) { $cancelled = $true; $done = $true; }
                    ([ConsoleKey]::Tab)
                    {
                        if (-not $alt) { Add-Input_Text $state '    '; }
                    }
                    ([ConsoleKey]::Backspace)
                    {
                        if ($state.Cursor -le 0) { break; }

                        if ($ctrlOnly)
                        {
                            $from = Get-Input_WordStart $text $state.Cursor;
                            [void] $state.Buffer.Remove($from, $state.Cursor - $from);
                            $state.Cursor = $from;
                        }
                        else
                        {
                            [void] $state.Buffer.Remove($state.Cursor - 1, 1);
                            $state.Cursor--;
                        }
                    }
                    ([ConsoleKey]::Delete)
                    {
                        if ($state.Cursor -ge $state.Buffer.Length) { break; }

                        if ($ctrlOnly)
                        {
                            $to = Get-Input_LineEnd $text $state.Cursor;
                            [void] $state.Buffer.Remove($state.Cursor, $to - $state.Cursor);
                        }
                        else
                        {
                            [void] $state.Buffer.Remove($state.Cursor, 1);
                        }
                    }
                    ([ConsoleKey]::LeftArrow)
                    {
                        $state.Cursor = $ctrlOnly ? (Get-Input_WordStart $text $state.Cursor) : ([Math]::Max(0, $state.Cursor - 1));
                    }
                    ([ConsoleKey]::RightArrow)
                    {
                        $state.Cursor = $ctrlOnly ? (Get-Input_WordEnd $text $state.Cursor) : ([Math]::Min($state.Buffer.Length, $state.Cursor + 1));
                    }
                    ([ConsoleKey]::UpArrow)
                    {
                        $lineStart = Get-Input_LineStart $text $state.Cursor;

                        if ($lineStart -gt 0)
                        {
                            $col = $state.Cursor - $lineStart;
                            $prevEnd = $lineStart - 1;
                            $prevStart = Get-Input_LineStart $text $prevEnd;
                            $state.Cursor = [Math]::Min($prevStart + $col, $prevEnd);
                        }
                    }
                    ([ConsoleKey]::DownArrow)
                    {
                        $lineStart = Get-Input_LineStart $text $state.Cursor;
                        $lineEnd = Get-Input_LineEnd $text $state.Cursor;

                        if ($lineEnd -lt $text.Length)
                        {
                            $col = $state.Cursor - $lineStart;
                            $nextStart = $lineEnd + 1;
                            $nextEnd = Get-Input_LineEnd $text $nextStart;
                            $state.Cursor = [Math]::Min($nextStart + $col, $nextEnd);
                        }
                    }
                    ([ConsoleKey]::Home)
                    {
                        $state.Cursor = $ctrlOnly ? 0 : (Get-Input_LineStart $text $state.Cursor);
                    }
                    ([ConsoleKey]::End)
                    {
                        $state.Cursor = $ctrlOnly ? $state.Buffer.Length : (Get-Input_LineEnd $text $state.Cursor);
                    }
                    ([ConsoleKey]::Insert)
                    {
                        if ($shift) { Add-Input_Text $state (Get-Input_ClipboardText); }
                    }
                    default
                    {
                        $char = $key.KeyChar;

                        if ($char -and -not [char]::IsControl($char)) { Add-Input_Text $state ([string] $char); }
                    }
                }
            }

            if (-not $done) { Show-Input_Buffer $state -Mask:$Mask; }
        }

        if ($cancelled)
        {
            [void] $state.Buffer.Clear();
            $state.Cursor = 0;
            Show-Input_Buffer $state -Mask:$Mask;
        }

        $end = Get-Input_Position $state $state.Buffer.Length;

        try { [Console]::SetCursorPosition([Math]::Min($end.Col, $state.Width - 1), $state.StartTop + $end.Row); } catch { }

        [Console]::WriteLine();

        if ($cancelled) { return $null; }

        return $state.Buffer.ToString();
    }
    catch
    {
        return Read-Host $Prompt;
    }
}

Export-ModuleMember -Function Read-Input_Multiline;
