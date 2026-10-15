#Requires -Version 7.0

Set-StrictMode -Version Latest;
$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

class InputEditor
{
    [string] $Text = '';
    [int] $Pos = 0;
    [int] $Goal = -1;
    [int] $View = 0;
    [int] $CursorRow = 0;

    [string] $Prefix;
    [int] $Origin;
    [int] $Indent;
    [int] $Width;
    [int] $Height;
    [bool] $Mask;

    InputEditor([string] $promptText, [int] $startCol, [int] $termWidth, [int] $termHeight, [bool] $hideText)
    {
        $this.Prefix = $promptText;
        $this.Origin = $startCol;
        $this.Indent = $startCol + $promptText.Length;
        $this.Width = $termWidth;
        $this.Height = $termHeight;
        $this.Mask = $hideText;
    }

    # Visual rows: every logical line is wrapped at Width-1 columns. The last column is never
    # written, so the terminal never auto-wraps and the cursor always has a cell at line end.
    # Rendering, cursor placement and Up/Down all derive from this single layout.
    [object[]] Rows()
    {
        $rows = [System.Collections.Generic.List[object]]::new();
        $lineStart = 0;

        while ($true)
        {
            $eol = $this.Text.IndexOf([char] "`n", $lineStart);
            $lineEnd = ($eol -lt 0) ? $this.Text.Length : $eol;
            $rowIndent = ($rows.Count -eq 0) ? $this.Indent : 0;
            $start = $lineStart;

            do
            {
                $end = [Math]::Min($lineEnd, $start + [Math]::Max(1, $this.Width - 1 - $rowIndent));
                $rows.Add([pscustomobject] @{ Start = $start; End = $end; Indent = $rowIndent; Last = ($end -eq $lineEnd) });
                $start = $end;
                $rowIndent = 0;
            } while ($start -lt $lineEnd);

            if ($eol -lt 0) { break; }

            $lineStart = $eol + 1;
        }

        return $rows.ToArray();
    }

    # Index of the visual row containing $pos. Rows are ordered by Start, so take the last one that starts at or before $pos.
    [int] RowIndex([object[]] $rows, [int] $at)
    {
        $index = 0;

        while ($index + 1 -lt $rows.Count -and $rows[$index + 1].Start -le $at) { $index++; }

        return $index;
    }

    # Last cursor position inside a row. A wrap point belongs to the start of the next row, so a non-final row ends one column earlier.
    [int] RowLast([object] $row)
    {
        return ($row.Last ? $row.End : ($row.End - 1));
    }

    [void] Seek([int] $index)
    {
        $this.Pos = [Math]::Clamp($index, 0, $this.Text.Length);
        $this.Goal = -1;
    }

    [void] Insert([string] $insertion)
    {
        $this.Text = $this.Text.Insert($this.Pos, $insertion);
        $this.Seek($this.Pos + $insertion.Length);
    }

    [void] Delete([int] $from, [int] $to)
    {
        $from = [Math]::Clamp($from, 0, $this.Text.Length);
        $to = [Math]::Clamp($to, $from, $this.Text.Length);

        if ($to -eq $from) { return; }

        $this.Text = $this.Text.Remove($from, $to - $from);
        $this.Seek($from);
    }

    [int] LineStart()
    {
        return ($this.Pos -eq 0) ? 0 : ($this.Text.LastIndexOf([char] "`n", $this.Pos - 1) + 1);
    }

    [int] LineEnd()
    {
        $eol = $this.Text.IndexOf([char] "`n", $this.Pos);
        return ($eol -lt 0) ? $this.Text.Length : $eol;
    }

    [int] WordLeft()
    {
        $i = $this.Pos;

        while ($i -gt 0 -and [char]::IsWhiteSpace($this.Text[$i - 1])) { $i--; }
        while ($i -gt 0 -and -not [char]::IsWhiteSpace($this.Text[$i - 1])) { $i--; }

        return $i;
    }

    [int] WordRight()
    {
        $i = $this.Pos;
        $n = $this.Text.Length;

        while ($i -lt $n -and [char]::IsWhiteSpace($this.Text[$i])) { $i++; }
        while ($i -lt $n -and -not [char]::IsWhiteSpace($this.Text[$i])) { $i++; }

        return $i;
    }

    # Kills to the end of the logical line; at the end of a line it joins with the next one.
    [void] KillToLineEnd()
    {
        $end = $this.LineEnd();

        if ($end -eq $this.Pos) { $end = [Math]::Min($this.Text.Length, $end + 1); }

        $this.Delete($this.Pos, $end);
    }

    # Moves to the adjacent visual row, keeping the screen column the cursor started from.
    [void] MoveVertical([int] $delta)
    {
        $rows = $this.Rows();
        $from = $this.RowIndex($rows, $this.Pos);
        $to = $from + $delta;

        if ($to -lt 0 -or $to -ge $rows.Count) { return; }

        $current = $rows[$from];

        if ($this.Goal -lt 0) { $this.Goal = $current.Indent + $this.Pos - $current.Start; }

        $target = $rows[$to];
        $offset = [Math]::Clamp($this.Goal - $target.Indent, 0, $this.RowLast($target) - $target.Start);

        $this.Pos = $target.Start + $offset;
    }

    [int] VisualStart()
    {
        $rows = $this.Rows();

        return $rows[$this.RowIndex($rows, $this.Pos)].Start;
    }

    [int] VisualEnd()
    {
        $rows = $this.Rows();

        return $this.RowLast($rows[$this.RowIndex($rows, $this.Pos)]);
    }

    # Keeps the cursor row inside the window of Height visible rows.
    [void] Scroll([int] $count, [int] $cursor)
    {
        $this.View = [Math]::Max(0, [Math]::Min($this.View, $count - $this.Height));

        if ($cursor -lt $this.View) { $this.View = $cursor; }
        elseif ($cursor -ge $this.View + $this.Height) { $this.View = $cursor - $this.Height + 1; }
    }

    # Redraws the visible window of rows. Everything is positioned relative to the cursor
    # left at the end of the previous frame, so the frame is correct regardless of scrolling.
    [void] Render()
    {
        $rows = $this.Rows();
        $cursor = $this.RowIndex($rows, $this.Pos);
        $this.Scroll($rows.Count, $cursor);

        # Once the view has scrolled past the prompt line, that line belongs to the input. The text
        # before the prompt is gone, so the input starts at column 0 from now on.
        if ($this.View -gt 0 -and $this.Origin -gt 0)
        {
            $this.Origin = 0;
            $this.Indent = $this.Prefix.Length;
            $rows = $this.Rows();
            $cursor = $this.RowIndex($rows, $this.Pos);
            $this.Scroll($rows.Count, $cursor);
        }

        $column = $rows[$cursor].Indent + $this.Pos - $rows[$cursor].Start;
        $first = $this.View;
        $last = [Math]::Min($rows.Count, $first + $this.Height) - 1;

        $frame = [System.Text.StringBuilder]::new();

        if ($this.CursorRow -gt 0) { [void] $frame.Append("`e[$($this.CursorRow)A"); }

        $startCol = ($first -eq 0) ? $this.Origin : 0;
        [void] $frame.Append("`e[$($startCol + 1)G`e[0J`e[?25l");

        for ($i = $first; $i -le $last; $i++)
        {
            if ($i -gt $first) { [void] $frame.Append("`r`n"); }
            if ($i -eq 0) { [void] $frame.Append($this.Prefix); }

            $row = $rows[$i];
            $chunk = $this.Text.Substring($row.Start, $row.End - $row.Start);
            $visible = $this.Mask ? ('*' * $chunk.Length) : $chunk;
            [void] $frame.Append($visible);
        }

        $up = $last - $cursor;

        if ($up -gt 0) { [void] $frame.Append("`e[$($up)A"); }

        [void] $frame.Append("`e[$($column + 1)G`e[?25h");

        $this.CursorRow = $cursor - $first;

        [Console]::Write($frame.ToString());
    }
}

function Get-Input_ConsoleWidth
{
    try { return [Math]::Max(20, [Console]::WindowWidth); }
    catch { return 80; }
}

function Get-Input_ConsoleHeight
{
    try { return [Math]::Max(1, [Console]::WindowHeight); }
    catch { return 25; }
}

function Test-Input_Interactive
{
    try
    {
        return $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected;
    }
    catch { return $false; }
}

function Format-Input_Clean([string] $Text)
{
    $clean = $Text -replace "`r`n?", "`n";
    $clean = $clean.Replace("`t", '    ');
    $clean = [regex]::Replace($clean, '\x1B\[[0-?]*[ -/]*[@-~]', '');

    return [regex]::Replace($clean, '[\x00-\x09\x0B-\x1F\x7F]', '');
}

function Get-Input_Paste
{
    try { return Format-Input_Clean ([string] (Get-Clipboard -Raw -ErrorAction Stop)); }
    catch { return ''; }
}

function Invoke-Input_Key([InputEditor] $Editor, [ConsoleKeyInfo] $Key)
{
    $modifiers = $Key.Modifiers;
    $ctrl = $modifiers.HasFlag([ConsoleModifiers]::Control) -and -not $modifiers.HasFlag([ConsoleModifiers]::Alt);
    $shift = $modifiers.HasFlag([ConsoleModifiers]::Shift);

    if ($ctrl)
    {
        switch ($Key.Key)
        {
            ([ConsoleKey]::A) { $Editor.Seek($Editor.LineStart()); return 'Continue'; }
            ([ConsoleKey]::E) { $Editor.Seek($Editor.LineEnd()); return 'Continue'; }
            ([ConsoleKey]::U) { $Editor.Delete($Editor.LineStart(), $Editor.Pos); return 'Continue'; }
            ([ConsoleKey]::K) { $Editor.KillToLineEnd(); return 'Continue'; }
            ([ConsoleKey]::W) { $Editor.Delete($Editor.WordLeft(), $Editor.Pos); return 'Continue'; }
            ([ConsoleKey]::V) { $Editor.Insert((Get-Input_Paste)); return 'Continue'; }
            ([ConsoleKey]::C) { return 'Cancel'; }
            ([ConsoleKey]::D)
            {
                if ($Editor.Text.Length -eq 0) { return 'Cancel'; }

                $Editor.Delete($Editor.Pos, $Editor.Pos + 1);
                return 'Continue';
            }
        }
    }

    switch ($Key.Key)
    {
        ([ConsoleKey]::Enter)
        {
            if ($shift -or $ctrl -or [Console]::KeyAvailable)
            {
                $Editor.Insert("`n");
                return 'Continue';
            }

            return 'Submit';
        }
        ([ConsoleKey]::Escape) { return 'Cancel'; }
        ([ConsoleKey]::Tab) { $Editor.Insert('    '); }
        ([ConsoleKey]::Backspace)
        {
            if ($ctrl) { $Editor.Delete($Editor.WordLeft(), $Editor.Pos); }
            else { $Editor.Delete($Editor.Pos - 1, $Editor.Pos); }
        }
        ([ConsoleKey]::Delete)
        {
            if ($ctrl) { $Editor.KillToLineEnd(); }
            else { $Editor.Delete($Editor.Pos, $Editor.Pos + 1); }
        }
        ([ConsoleKey]::LeftArrow)
        {
            if ($ctrl) { $Editor.Seek($Editor.WordLeft()); }
            else { $Editor.Seek($Editor.Pos - 1); }
        }
        ([ConsoleKey]::RightArrow)
        {
            if ($ctrl) { $Editor.Seek($Editor.WordRight()); }
            else { $Editor.Seek($Editor.Pos + 1); }
        }
        ([ConsoleKey]::UpArrow) { $Editor.MoveVertical(-1); }
        ([ConsoleKey]::DownArrow) { $Editor.MoveVertical(1); }
        ([ConsoleKey]::Home)
        {
            if ($ctrl) { $Editor.Seek(0); }
            else { $Editor.Seek($Editor.VisualStart()); }
        }
        ([ConsoleKey]::End)
        {
            if ($ctrl) { $Editor.Seek($Editor.Text.Length); }
            else { $Editor.Seek($Editor.VisualEnd()); }
        }
        ([ConsoleKey]::Insert)
        {
            if ($shift) { $Editor.Insert((Get-Input_Paste)); }
        }
        default
        {
            if (-not [char]::IsControl($Key.KeyChar)) { $Editor.Insert([string] $Key.KeyChar); }
        }
    }

    return 'Continue';
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
        Enter submits. Shift+Enter or Ctrl+Enter inserts a newline, and so does Enter when more input is
        already pending (a pasted block typed as keystrokes). Esc or Ctrl+C cancels and returns $null.
        Ctrl+V and Shift+Insert paste the clipboard as text. Falls back to Read-Host when the console is
        not interactive.
    #>

    if (-not (Test-Input_Interactive))
    {
        return Read-Host -Prompt $Prompt -MaskInput:($Mask -and -not [Console]::IsInputRedirected);
    }

    $editor = [InputEditor]::new("${Prompt}: ", [Console]::CursorLeft, (Get-Input_ConsoleWidth), (Get-Input_ConsoleHeight), $Mask.IsPresent);
    $action = 'Continue';
    $treatCAsInput = [Console]::TreatControlCAsInput;

    # Ctrl+C must arrive as a key. Otherwise .NET turns it into a signal, which a blocked ReadKey never handles.
    [Console]::TreatControlCAsInput = $true;

    try
    {
        $editor.Render();

        while ($action -eq 'Continue')
        {
            $action = Invoke-Input_Key $editor ([Console]::ReadKey($true));

            if ($action -eq 'Continue') { $editor.Render(); }
        }
    }
    finally
    {
        [Console]::TreatControlCAsInput = $treatCAsInput;
    }

    if ($action -eq 'Cancel') { $editor.Text = ''; }

    $editor.Seek($editor.Text.Length);
    $editor.Render();
    [Console]::WriteLine();

    if ($action -eq 'Cancel') { return $null; }

    return $editor.Text;
}

Export-ModuleMember -Function Read-Input_Multiline;
