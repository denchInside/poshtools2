#Requires -Version 7.0

using namespace System.Text
using namespace System.Text.RegularExpressions
using namespace System.Globalization
using namespace System.Collections.Generic

$ErrorActionPreference = 'Stop';
$WarningPreference = 'SilentlyContinue';

class MD_Ansi
{
    static [int] $Depth = 24;
    static [string] $Reset = "`e[0m";

    static [string] Color([string] $hex, [bool] $background)
    {
        $red = [Convert]::ToInt32($hex.Substring(1, 2), 16);
        $green = [Convert]::ToInt32($hex.Substring(3, 2), 16);
        $blue = [Convert]::ToInt32($hex.Substring(5, 2), 16);
        $base = $background ? 48 : 38;

        if ([MD_Ansi]::Depth -ge 24)
        {
            return [string]::Format("`e[{0};2;{1};{2};{3}m", $base, $red, $green, $blue);
        }

        $index = 16 + 36 * [int][Math]::Round($red / 51.0) + 6 * [int][Math]::Round($green / 51.0) + [int][Math]::Round($blue / 51.0);

        return [string]::Format("`e[{0};5;{1}m", $base, $index);
    }

    static [string] Parse([string] $spec)
    {
        $result = '';

        foreach ($token in ($spec -split '\s+'))
        {
            if ($token.Length -eq 0) { continue; }

            if ([regex]::IsMatch($token, '^#[0-9a-fA-F]{6}$')) { $result += [MD_Ansi]::Color($token, $false); }
            elseif ([regex]::IsMatch($token, '^on:#[0-9a-fA-F]{6}$')) { $result += [MD_Ansi]::Color($token.Substring(3), $true); }
            elseif ($token -eq 'bold') { $result += "`e[1m"; }
            elseif ($token -eq 'dim') { $result += "`e[2m"; }
            elseif ($token -eq 'italic') { $result += "`e[3m"; }
            elseif ($token -eq 'underline') { $result += "`e[4m"; }
            elseif ($token -eq 'strike') { $result += "`e[9m"; }
            else { throw [System.ArgumentException]::new("unknown style token: $token", 'spec'); }
        }

        return $result;
    }

    static [string] Paint([string] $style, [string] $text)
    {
        if ($style.Length -eq 0 -or $text.Length -eq 0) { return $text; }

        return $style + $text + [MD_Ansi]::Reset;
    }

    static [string] Link([string] $url, [string] $text)
    {
        $safe = [regex]::Replace($url.Replace(' ', '%20'), '[\x00-\x1F\x7F-\x9F]', '');

        return [string]::Format("`e]8;;{0}`e\{1}`e]8;;`e\", $safe, $text);
    }
}

class MD_Text
{
    static [regex] $NonAscii = [regex]::new('[^\x00-\x7F]');
    static [regex] $Control = [regex]::new('[\x00-\x08\x0B-\x1F\x7F-\x9F]');
    static [regex] $Escape = [regex]::new('\x1B\[[0-9;]*[A-Za-z]|\x1B\]8;[^\x1B]*\x1B\\');
    static [string[]] $Super = @("`u{2070}", "`u{00B9}", "`u{00B2}", "`u{00B3}", "`u{2074}", "`u{2075}", "`u{2076}", "`u{2077}", "`u{2078}", "`u{2079}");
    static [int[]] $Wide = @(
        0x1100, 0x115F, 0x231A, 0x231B, 0x23E9, 0x23EC, 0x23F0, 0x23F0, 0x23F3, 0x23F3,
        0x25FD, 0x25FE, 0x2614, 0x2615, 0x2648, 0x2653, 0x267F, 0x267F, 0x2693, 0x2693,
        0x26A1, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26CE,
        0x26D4, 0x26D4, 0x26EA, 0x26EA, 0x26F2, 0x26F3, 0x26F5, 0x26F5, 0x26FA, 0x26FA,
        0x26FD, 0x26FD, 0x2705, 0x2705, 0x270A, 0x270B, 0x2728, 0x2728, 0x274C, 0x274C,
        0x274E, 0x274E, 0x2753, 0x2755, 0x2757, 0x2757, 0x2795, 0x2797, 0x27B0, 0x27B0,
        0x27BF, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B50, 0x2B55, 0x2B55, 0x2E80, 0x303E,
        0x3041, 0x4DBF, 0x4E00, 0xA4CF, 0xAC00, 0xD7A3, 0xF900, 0xFAFF, 0xFE30, 0xFE6F,
        0xFF00, 0xFF60, 0xFFE0, 0xFFE6, 0x1F300, 0x1F64F, 0x1F680, 0x1F6FF, 0x1F7E0, 0x1F7EB,
        0x1F900, 0x1F9FF, 0x1FA70, 0x1FAFF, 0x20000, 0x3FFFD
    );

    static [string] Clean([string] $text)
    {
        $result = $text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`t", '    ').Replace([string][char] 0xFEFF, '');

        return [MD_Text]::Control.Replace($result, '');
    }

    static [string] Strip([string] $text)
    {
        return [MD_Text]::Escape.Replace($text, '');
    }

    static [int] Visible([string] $text)
    {
        return [MD_Text]::Width([MD_Text]::Strip($text));
    }

    static [string] Pad([string] $text, [int] $width, [string] $align)
    {
        $gap = $width - [MD_Text]::Visible($text);

        if ($gap -le 0) { return $text; }
        if ($align -eq 'right') { return (' ' * $gap) + $text; }

        if ($align -eq 'center')
        {
            $left = $gap -shr 1;

            return (' ' * $left) + $text + (' ' * ($gap - $left));
        }

        return $text + (' ' * $gap);
    }

    static [int] Share([int] $value, [int] $part, [int] $whole)
    {
        if ($whole -le 0) { return 0; }

        return [int][Math]::Floor([double] $value * $part / $whole);
    }

    static [string] Repeat([string] $text, [int] $count)
    {
        if ($count -le 0) { return ''; }

        return $text * $count;
    }

    static [List[string]] Elements([string] $text)
    {
        $elements = [List[string]]::new();
        $enumerator = [StringInfo]::GetTextElementEnumerator($text);

        while ($enumerator.MoveNext())
        {
            $elements.Add([string] $enumerator.Current);
        }

        return $elements;
    }

    static [int] ElementWidth([string] $element)
    {
        $code = [int] $element[0];

        if ($element.Length -gt 1 -and [char]::IsHighSurrogate($element[0]) -and [char]::IsLowSurrogate($element[1]))
        {
            $code = [char]::ConvertToUtf32($element[0], $element[1]);
        }

        if ($code -lt 32 -or ($code -ge 0x7F -and $code -lt 0xA0)) { return 0; }
        if ($element.Contains([char] 0xFE0F)) { return 2; }

        $category = [char]::GetUnicodeCategory($element, 0);

        if ($category -eq [UnicodeCategory]::NonSpacingMark -or $category -eq [UnicodeCategory]::EnclosingMark -or $category -eq [UnicodeCategory]::Format)
        {
            return 0;
        }

        $ranges = [MD_Text]::Wide;

        for ($k = 0; $k -lt $ranges.Length; $k += 2)
        {
            if ($code -ge $ranges[$k] -and $code -le $ranges[$k + 1]) { return 2; }
        }

        return 1;
    }

    static [int] Width([string] $text)
    {
        if (-not [MD_Text]::NonAscii.IsMatch($text)) { return $text.Length; }

        $width = 0;
        $enumerator = [StringInfo]::GetTextElementEnumerator($text);

        while ($enumerator.MoveNext())
        {
            $width += [MD_Text]::ElementWidth([string] $enumerator.Current);
        }

        return $width;
    }
}

class MD_Theme
{
    [bool] $Color;
    [hashtable] $Styles;
    [hashtable] $Marks;
    [hashtable] $Glyphs;
    [string[]] $Bullets;

    MD_Theme([bool] $color, [hashtable] $overrides)
    {
        $this.Color = $color;
        $this.Styles = @{};
        $this.Marks = @{};
        $this.Bullets = @("`u{2022}", "`u{25E6}", "`u{25AA}");
        $this.Glyphs = @{
            'h' = "`u{2500}"
            'v' = "`u{2502}"
            'tl' = "`u{256D}"
            'tr' = "`u{256E}"
            'bl' = "`u{2570}"
            'br' = "`u{256F}"
            'lj' = "`u{251C}"
            'rj' = "`u{2524}"
            'tj' = "`u{252C}"
            'bj' = "`u{2534}"
            'cross' = "`u{253C}"
            'rule1' = "`u{2550}"
            'rule2' = "`u{2500}"
            'quote' = "`u{2503}"
            'image' = "`u{25A3}"
            'task.done' = "`u{2611}"
            'task.open' = "`u{2610}"
            'note' = "`u{2139}"
            'tip' = "`u{2726}"
            'important' = "`u{203C}"
            'warning' = "`u{25B2}"
            'caution' = "`u{2716}"
        };

        $this.Glyphs['gutter'] = $color ? "`u{258C}" : "`u{2502}";

        if ($color)
        {
            $specs = [MD_Theme]::Defaults();

            if ($overrides)
            {
                foreach ($key in $overrides.Keys) { $specs[$key] = $overrides[$key]; }
            }

            foreach ($key in $specs.Keys) { $this.Styles[$key] = [MD_Ansi]::Parse([string] $specs[$key]); }

            $this.Marks['code'] = ' ';
        }
        else
        {
            $this.Marks['code'] = '`';
            $this.Marks['strong'] = '**';
            $this.Marks['em'] = '*';
            $this.Marks['strike'] = '~~';
        }
    }

    [string] Get([string] $name)
    {
        return $this.Styles.ContainsKey($name) ? $this.Styles[$name] : '';
    }

    [string] Mark([string] $name)
    {
        return $this.Marks.ContainsKey($name) ? $this.Marks[$name] : '';
    }

    [string] Glyph([string] $name)
    {
        return $this.Glyphs.ContainsKey($name) ? $this.Glyphs[$name] : '';
    }

    [string] Super([int] $number)
    {
        $result = '';

        foreach ($digit in $number.ToString().ToCharArray())
        {
            $result += [MD_Text]::Super[[int]::Parse([string] $digit)];
        }

        return $result;
    }

    static [hashtable] Defaults()
    {
        return @{
            'strong' = 'bold #f9e2af'
            'em' = 'italic #f5c2e7'
            'strike' = 'strike #6c7086'
            'underline' = 'underline'
            'mark' = '#1e1e2e on:#f9e2af'
            'kbd' = 'bold #cdd6f4 on:#45475a'
            'code' = '#fab387 on:#313244'
            'link' = 'underline #89b4fa'
            'link.ref' = '#74c7ec'
            'url' = 'underline #6c7086'
            'image' = 'italic #cba6f7'
            'footnote' = 'bold #f9e2af'
            'h1' = 'bold #cba6f7'
            'h2' = 'bold #89b4fa'
            'h3' = 'bold #94e2d5'
            'h4' = 'bold #a6e3a1'
            'h5' = 'bold #f9e2af'
            'h6' = 'bold #fab387'
            'h.mark' = '#6c7086'
            'h1.rule' = '#cba6f7'
            'h2.rule' = '#585b70'
            'rule' = '#585b70'
            'quote' = '#7f849c'
            'quote.bar' = '#585b70'
            'alert.note' = 'bold #89b4fa'
            'alert.tip' = 'bold #a6e3a1'
            'alert.important' = 'bold #cba6f7'
            'alert.warning' = 'bold #f9e2af'
            'alert.caution' = 'bold #f38ba8'
            'bullet' = '#fab387'
            'number' = 'bold #fab387'
            'task.done' = '#a6e3a1'
            'task.open' = '#f9e2af'
            'table.border' = '#6c7086'
            'table.header' = 'bold #89b4fa'
            'code.border' = '#585b70'
            'code.label' = 'italic #a6adc8'
            'code.bg' = 'on:#24273a'
            'code.text' = '#cdd6f4'
            'syn.comment' = 'italic #6c7086'
            'syn.string' = '#a6e3a1'
            'syn.number' = '#fab387'
            'syn.const' = '#fab387'
            'syn.keyword' = '#cba6f7'
            'syn.function' = '#89b4fa'
            'syn.variable' = '#f2cdcd'
            'syn.param' = '#94e2d5'
            'syn.type' = '#f9e2af'
            'syn.key' = '#89b4fa'
            'syn.added' = '#a6e3a1'
            'syn.removed' = '#f38ba8'
            'syn.hunk' = '#74c7ec'
        };
    }
}

class MD_Pattern
{
    static [regex] $Atx = [regex]::new('^ {0,3}(#{1,6})(?:[ ]+(.*?))?(?:[ ]+#+)?[ ]*$');
    static [regex] $Fence = [regex]::new('^( {0,3})(`{3,}|~{3,})[ ]*(.*?)[ ]*$');
    static [regex] $Rule = [regex]::new('^ {0,3}(?:(?:\*[ ]*){3,}|(?:-[ ]*){3,}|(?:_[ ]*){3,})$');
    static [regex] $Quote = [regex]::new('^ {0,3}>[ ]?(.*)$');
    static [regex] $Item = [regex]::new('^( {0,3})([-+*]|[0-9]{1,9}[.)])(?:( +)(.*))?$');
    static [regex] $Setext = [regex]::new('^ {0,3}(=+|-+)[ ]*$');
    static [regex] $Delimiter = [regex]::new('^ {0,3}\|?[ ]*:?-+:?[ ]*(?:\|[ ]*:?-+:?[ ]*)*\|?[ ]*$');
    static [regex] $Html = [regex]::new('(?i)^ {0,3}(?:<!--|</?(?:address|article|aside|blockquote|body|caption|center|dd|details|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|head|header|hr|html|li|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:[ >/]|$))');
    static [regex] $Reference = [regex]::new('^ {0,3}\[([^\]^][^\]]*)\]:[ ]*(?:<([^>]*)>|(\S+))(?:[ ]+(?:"([^"]*)"|''([^'']*)''|\(([^)]*)\)))?[ ]*$');
    static [regex] $Footnote = [regex]::new('^ {0,3}\[\^([^\]\s]+)\]:[ ]?(.*)$');
    static [regex] $Task = [regex]::new('^\[([ xX])\][ ]+');
    static [regex] $Alert = [regex]::new('(?i)^\[!(note|tip|important|warning|caution)\][ ]*(.*)$');

    static [regex] $Special = [regex]::new('[\\`*_~\[\]!<&\n]|(?i:(?<![\w/@.])(?:https?://|www\.))');
    static [regex] $Punctuation = [regex]::new('[!-/:-@\[-`{-~]');
    static [regex] $Entity = [regex]::new('\G&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});');
    static [regex] $AutoLink = [regex]::new('\G<([A-Za-z][A-Za-z0-9+.-]{1,31}:[^\s<>]*)>');
    static [regex] $AutoMail = [regex]::new('\G<([\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+)>');
    static [regex] $Tag = [regex]::new('(?i)\G(?:<!--[\s\S]*?-->|</?(?:a|abbr|b|big|br|cite|code|del|details|div|em|font|hr|i|img|ins|kbd|mark|p|q|s|samp|small|span|strike|strong|sub|summary|sup|tt|u|var)(?=[\s/>])[^<>]*>)');
    static [regex] $Bare = [regex]::new('(?i)\G(?:https?://|www\.)[^\s<]+');
    static [regex] $Footref = [regex]::new('\G\[\^([^\]\s]+)\]');
    static [regex] $Label = [regex]::new('\G\[([^\[\]]*)\]');
    static [regex] $Dest = [regex]::new('\G\([ \n]*(?:<([^<>\n]*)>|((?:[^\s()\\]|\\.|\((?:[^\s()\\]|\\.)*\))*))(?:[ \n]+(?:"((?:[^"\\]|\\.)*)"|''((?:[^''\\]|\\.)*)''|\(((?:[^()\\]|\\.)*)\)))?[ \n]*\)');
    static [regex] $TagName = [regex]::new('^<(/?)([A-Za-z0-9]+)');
    static [regex] $Scheme = [regex]::new('^[A-Za-z][A-Za-z0-9+.-]*:');
    static [regex] $Safe = [regex]::new('(?i)^(?:https?|mailto|ftps?|file|tel):');
    static [hashtable] $TagKeys = @{
        'b' = 'bold'
        'strong' = 'bold'
        'i' = 'italic'
        'em' = 'italic'
        'cite' = 'italic'
        'var' = 'italic'
        's' = 'strike'
        'strike' = 'strike'
        'del' = 'strike'
        'u' = 'underline'
        'ins' = 'underline'
        'kbd' = 'kbd'
        'code' = 'code'
        'tt' = 'code'
        'samp' = 'code'
        'mark' = 'mark'
    };
}

class MD_Inline
{
    [string] $Kind;
    [string] $Text;
    [string] $Url;
    [string] $Title;
    [string] $Mark;
    [int] $Count;
    [int] $Origin;
    [bool] $CanOpen;
    [bool] $CanClose;
    [bool] $Active;
    [bool] $Image;
    [List[MD_Inline]] $Children;

    MD_Inline([string] $kind, [string] $text)
    {
        $this.Kind = $kind;
        $this.Text = $text;
        $this.Url = '';
        $this.Title = '';
        $this.Mark = '';
        $this.Active = $true;
        $this.Children = [List[MD_Inline]]::new();
    }
}

class MD_Block
{
    [string] $Kind;
    [string] $Text;
    [string] $Info;
    [int] $Level;
    [int] $Task;
    [bool] $Ordered;
    [bool] $Tight;
    [string[]] $Align;
    [List[string[]]] $Rows;
    [List[MD_Block]] $Children;

    MD_Block([string] $kind)
    {
        $this.Kind = $kind;
        $this.Text = '';
        $this.Info = '';
        $this.Tight = $true;
        $this.Align = @();
        $this.Rows = [List[string[]]]::new();
        $this.Children = [List[MD_Block]]::new();
    }
}

class MD_Document
{
    [List[MD_Block]] $Blocks;
    [hashtable] $Links;
    [hashtable] $Footnotes;

    MD_Document()
    {
        $this.Blocks = [List[MD_Block]]::new();
        $this.Links = @{};
        $this.Footnotes = @{};
    }
}

class MD_Parser
{
    [hashtable] $Links;
    [hashtable] $Footnotes;
    [int] $HtmlDepth;

    MD_Parser()
    {
        $this.Links = @{};
        $this.Footnotes = @{};
        $this.HtmlDepth = 0;
    }

    [MD_Document] Parse([string] $markdown)
    {
        $lines = [List[string]]::new([string[]] ([MD_Text]::Clean($markdown) -split "`n"));
        $document = [MD_Document]::new();

        $document.Blocks = $this.ParseBlocks($lines);
        $document.Links = $this.Links;
        $document.Footnotes = $this.Footnotes;

        return $document;
    }

    [int] Indent([string] $line)
    {
        return $line.Length - $line.TrimStart(' ').Length;
    }

    [List[MD_Block]] ParseBlocks([List[string]] $lines)
    {
        $blocks = [List[MD_Block]]::new();
        $index = 0;

        while ($index -lt $lines.Count)
        {
            if ([string]::IsNullOrWhiteSpace($lines[$index]))
            {
                $index++;
                continue;
            }

            $next = $this.TryCode($lines, $index, $blocks);

            if ($next -lt 0) { $next = $this.TryFence($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryHeading($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryRule($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryQuote($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryList($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryTable($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryHtml($lines, $index, $blocks); }
            if ($next -lt 0) { $next = $this.TryDefinition($lines, $index); }
            if ($next -lt 0) { $next = $this.ParseParagraph($lines, $index, $blocks); }

            $index = $next;
        }

        return $blocks;
    }

    [bool] Interrupts([List[string]] $lines, [int] $index)
    {
        $line = $lines[$index];

        if ([MD_Pattern]::Atx.IsMatch($line) -or [MD_Pattern]::Quote.IsMatch($line) -or [MD_Pattern]::Rule.IsMatch($line))
        {
            return $true;
        }

        $fence = [MD_Pattern]::Fence.Match($line);

        if ($fence.Success -and -not ($fence.Groups[2].Value.StartsWith('`') -and $fence.Groups[3].Value.Contains('`')))
        {
            return $true;
        }

        if ($this.HtmlDepth -eq 0 -and [MD_Pattern]::Html.IsMatch($line))
        {
            return $true;
        }

        $item = [MD_Pattern]::Item.Match($line);

        if ($item.Success -and $item.Groups[4].Success -and $item.Groups[4].Value.Trim().Length -gt 0)
        {
            $marker = $item.Groups[2].Value;

            if (-not [char]::IsDigit($marker[0]) -or $marker.Substring(0, $marker.Length - 1) -eq '1')
            {
                return $true;
            }
        }

        return $this.IsTableStart($lines, $index);
    }

    [int] TryCode([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        if ($this.Indent($lines[$index]) -lt 4) { return -1; }

        $content = [List[string]]::new();
        $cursor = $index;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];

            if ([string]::IsNullOrWhiteSpace($line))
            {
                $stripped = ($line.Length -ge 4) ? $line.Substring(4) : '';
                $content.Add($stripped);
                $cursor++;
                continue;
            }

            if ($this.Indent($line) -lt 4) { break; }

            $content.Add($line.Substring(4));
            $cursor++;
        }

        while ($content.Count -gt 0 -and [string]::IsNullOrWhiteSpace($content[$content.Count - 1]))
        {
            $content.RemoveAt($content.Count - 1);
        }

        $block = [MD_Block]::new('code');
        $block.Text = [string]::Join("`n", $content);
        $blocks.Add($block);

        return $cursor;
    }

    [int] TryFence([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        $match = [MD_Pattern]::Fence.Match($lines[$index]);

        if (-not $match.Success) { return -1; }

        $fence = $match.Groups[2].Value;
        $info = $match.Groups[3].Value;

        if ($fence.StartsWith('`') -and $info.Contains('`')) { return -1; }

        $indent = $match.Groups[1].Length;
        $closing = [regex]::new('^ {0,3}' + [regex]::Escape($fence.Substring(0, 1)) + '{' + $fence.Length + ',}[ ]*$');
        $content = [List[string]]::new();
        $cursor = $index + 1;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];
            $cursor++;

            if ($closing.IsMatch($line)) { break; }

            $content.Add($line.Substring([Math]::Min($indent, $this.Indent($line))));
        }

        $block = [MD_Block]::new('code');
        $block.Info = ($info -split '\s+')[0];
        $block.Text = [string]::Join("`n", $content);
        $blocks.Add($block);

        return $cursor;
    }

    [int] TryHeading([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        $match = [MD_Pattern]::Atx.Match($lines[$index]);

        if (-not $match.Success) { return -1; }

        $block = [MD_Block]::new('heading');
        $block.Level = $match.Groups[1].Length;
        $block.Text = $match.Groups[2].Value.Trim();
        $blocks.Add($block);

        return $index + 1;
    }

    [int] TryRule([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        if (-not [MD_Pattern]::Rule.IsMatch($lines[$index])) { return -1; }

        $blocks.Add([MD_Block]::new('rule'));

        return $index + 1;
    }

    [int] TryQuote([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        if (-not [MD_Pattern]::Quote.IsMatch($lines[$index])) { return -1; }

        $inner = [List[string]]::new();
        $cursor = $index;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];
            $match = [MD_Pattern]::Quote.Match($line);

            if ($match.Success)
            {
                $inner.Add($match.Groups[1].Value);
            }
            elseif ($inner.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($line) -and -not [string]::IsNullOrWhiteSpace($inner[$inner.Count - 1]) -and -not $this.Interrupts($lines, $cursor))
            {
                $inner.Add($line.TrimStart());
            }
            else
            {
                break;
            }

            $cursor++;
        }

        $block = [MD_Block]::new('quote');
        $alert = [MD_Pattern]::Alert.Match($inner[0]);

        if ($alert.Success)
        {
            $block.Kind = 'alert';
            $block.Info = $alert.Groups[1].Value.ToLowerInvariant();

            if ($alert.Groups[2].Value.Length -gt 0) { $inner[0] = $alert.Groups[2].Value; }
            else { $inner.RemoveAt(0); }
        }

        $block.Children = $this.ParseBlocks($inner);
        $blocks.Add($block);

        return $cursor;
    }

    [int] TryList([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        $first = [MD_Pattern]::Item.Match($lines[$index]);

        if (-not $first.Success) { return -1; }

        $marker = $first.Groups[2].Value;
        $ordered = [char]::IsDigit($marker[0]);
        $kind = $this.Kind($marker);

        $list = [MD_Block]::new('list');
        $list.Ordered = $ordered;
        $list.Level = $ordered ? [int]::Parse($marker.Substring(0, $marker.Length - 1)) : 0;

        $loose = $false;
        $cursor = $index;

        while ($cursor -lt $lines.Count)
        {
            $match = [MD_Pattern]::Item.Match($lines[$cursor]);

            if (-not $match.Success -or [MD_Pattern]::Rule.IsMatch($lines[$cursor])) { break; }

            $current = $match.Groups[2].Value;

            if ($this.Kind($current) -ne $kind) { break; }

            $spaces = $match.Groups[3].Success ? $match.Groups[3].Length : 0;
            $text = $match.Groups[4].Success ? $match.Groups[4].Value : '';
            $offset = $match.Groups[1].Length + $current.Length + 1;

            if ($text.Length -gt 0 -and $spaces -le 4) { $offset = $match.Groups[1].Length + $current.Length + $spaces; }
            elseif ($text.Length -gt 0) { $text = (' ' * ($spaces - 1)) + $text; }

            $content = [List[string]]::new();
            $content.Add($text);
            $cursor++;
            $pending = 0;

            while ($cursor -lt $lines.Count)
            {
                $line = $lines[$cursor];

                if ([string]::IsNullOrWhiteSpace($line))
                {
                    $pending++;
                    $cursor++;
                    continue;
                }

                if ($this.Indent($line) -ge $offset)
                {
                    for ($blank = 0; $blank -lt $pending; $blank++) { $content.Add(''); }

                    $pending = 0;
                    $content.Add($line.Substring($offset));
                    $cursor++;
                    continue;
                }

                if ($pending -eq 0 -and -not [MD_Pattern]::Item.IsMatch($line) -and -not $this.Interrupts($lines, $cursor))
                {
                    $content.Add($line.TrimStart());
                    $cursor++;
                    continue;
                }

                break;
            }

            $item = [MD_Block]::new('item');
            $item.Children = $this.ParseBlocks($content);

            if ($pending -gt 0 -and $cursor -lt $lines.Count)
            {
                $following = [MD_Pattern]::Item.Match($lines[$cursor]);

                if ($following.Success -and $this.Kind($following.Groups[2].Value) -eq $kind) { $loose = $true; }
            }

            if ($item.Children.Count -gt 1 -and $this.HasGap($content))
            {
                $last = $item.Children[$item.Children.Count - 1];

                if (-not ($last.Kind -eq 'list' -and -not $last.Tight)) { $loose = $true; }
            }

            if ($item.Children.Count -gt 0 -and $item.Children[0].Kind -eq 'paragraph')
            {
                $task = [MD_Pattern]::Task.Match($item.Children[0].Text);

                if ($task.Success)
                {
                    $item.Task = ($task.Groups[1].Value -eq ' ') ? 1 : 2;
                    $item.Children[0].Text = $item.Children[0].Text.Substring($task.Length);
                }
            }

            $list.Children.Add($item);
        }

        $list.Tight = -not $loose;
        $blocks.Add($list);

        return $cursor;
    }

    [string] Kind([string] $marker)
    {
        return [char]::IsDigit($marker[0]) ? $marker.Substring($marker.Length - 1) : $marker;
    }

    [bool] HasGap([List[string]] $content)
    {
        $fence = '';

        foreach ($line in $content)
        {
            $match = [MD_Pattern]::Fence.Match($line);

            if ($fence.Length -eq 0 -and $match.Success)
            {
                $fence = $match.Groups[2].Value.Substring(0, 1);
                continue;
            }

            if ($fence.Length -gt 0 -and $match.Success -and $match.Groups[2].Value.StartsWith($fence))
            {
                $fence = '';
                continue;
            }

            if ($fence.Length -eq 0 -and [string]::IsNullOrWhiteSpace($line)) { return $true; }
        }

        return $false;
    }

    [string[]] Cells([string] $row)
    {
        $text = $row.Trim();

        if ($text.StartsWith('|')) { $text = $text.Substring(1); }
        if ($text.EndsWith('|') -and -not $text.EndsWith('\|')) { $text = $text.Substring(0, $text.Length - 1); }

        $cells = [regex]::Split($text, '(?<!\\)\|');

        for ($column = 0; $column -lt $cells.Length; $column++)
        {
            $cells[$column] = $cells[$column].Trim().Replace('\|', '|');
        }

        return $cells;
    }

    [bool] IsTableStart([List[string]] $lines, [int] $index)
    {
        if ($index + 1 -ge $lines.Count) { return $false; }

        $header = $lines[$index];
        $divider = $lines[$index + 1];

        if (-not $header.Contains('|') -or -not $divider.Contains('|')) { return $false; }
        if (-not [MD_Pattern]::Delimiter.IsMatch($divider)) { return $false; }

        return $this.Cells($header).Length -eq $this.Cells($divider).Length;
    }

    [int] TryTable([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        if (-not $this.IsTableStart($lines, $index)) { return -1; }

        $table = [MD_Block]::new('table');
        $headers = $this.Cells($lines[$index]);
        $columns = $headers.Length;
        $dividers = $this.Cells($lines[$index + 1]);

        $table.Align = [string[]]::new($columns);
        $table.Rows.Add($headers);

        for ($column = 0; $column -lt $columns; $column++)
        {
            $cell = $dividers[$column];

            if ($cell.StartsWith(':') -and $cell.EndsWith(':')) { $table.Align[$column] = 'center'; }
            elseif ($cell.EndsWith(':')) { $table.Align[$column] = 'right'; }
            else { $table.Align[$column] = 'left'; }
        }

        $cursor = $index + 2;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];

            if ([string]::IsNullOrWhiteSpace($line) -or -not $line.Contains('|')) { break; }

            $row = $this.Cells($line);
            $normalized = [string[]]::new($columns);

            for ($column = 0; $column -lt $columns; $column++)
            {
                $normalized[$column] = ($column -lt $row.Length) ? $row[$column] : '';
            }

            $table.Rows.Add($normalized);
            $cursor++;
        }

        $blocks.Add($table);

        return $cursor;
    }

    [string] HtmlToMarkdown([string] $html)
    {
        $text = [regex]::Replace($html, '(?s)<!--.*?-->', '');

        for ($level = 1; $level -le 6; $level++)
        {
            $text = [regex]::Replace($text, "(?is)<h${level}\b[^>]*>(.*?)</h${level}>", ("`n`n" + ('#' * $level) + ' $1' + "`n`n"));
        }

        $text = [regex]::Replace($text, '(?i)<br\s*/?>', "\`n");
        $text = [regex]::Replace($text, '(?i)<hr\s*/?>', "`n`n---`n`n");
        $text = [regex]::Replace($text, '(?is)<summary[^>]*>(.*?)</summary>', ("`n`n**" + '$1' + "**`n`n"));
        $text = [regex]::Replace($text, '(?i)<li[^>]*>', "`n- ");
        $text = [regex]::Replace($text, '(?i)</li\s*>', '');
        $text = [regex]::Replace($text, '(?i)</t[dh]\s*>', '  ');
        $text = [regex]::Replace($text, '(?i)</tr\s*>', "`n`n");
        $text = [regex]::Replace($text, '(?i)</?(?:address|article|aside|blockquote|body|caption|center|dd|details|div|dl|dt|fieldset|figcaption|figure|footer|form|head|header|html|main|nav|ol|p|pre|section|summary|table|tbody|td|tfoot|th|thead|tr|ul)(?:\s[^>]*)?/?>', "`n`n");

        $lines = $text -split "`n";

        for ($line = 0; $line -lt $lines.Length; $line++)
        {
            $lines[$line] = $lines[$line].Trim();
        }

        return [string]::Join("`n", $lines);
    }

    [int] TryHtml([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        if ($this.HtmlDepth -gt 0 -or -not [MD_Pattern]::Html.IsMatch($lines[$index])) { return -1; }

        $html = [List[string]]::new();
        $comment = $lines[$index].TrimStart().StartsWith('<!--');
        $cursor = $index;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];

            if ([string]::IsNullOrWhiteSpace($line) -and -not $comment) { break; }

            $html.Add($line);
            $cursor++;

            if ($comment -and $line.Contains('-->')) { break; }
        }

        $markdown = $this.HtmlToMarkdown([string]::Join("`n", $html));

        $this.HtmlDepth++;
        $blocks.AddRange($this.ParseBlocks([List[string]]::new([string[]] ($markdown -split "`n"))));
        $this.HtmlDepth--;

        return $cursor;
    }

    [int] TryDefinition([List[string]] $lines, [int] $index)
    {
        $line = $lines[$index];
        $note = [MD_Pattern]::Footnote.Match($line);

        if ($note.Success)
        {
            $content = [List[string]]::new();
            $content.Add($note.Groups[2].Value);
            $cursor = $index + 1;

            while ($cursor -lt $lines.Count)
            {
                $next = $lines[$cursor];

                if ([string]::IsNullOrWhiteSpace($next))
                {
                    if ($cursor + 1 -lt $lines.Count -and $this.Indent($lines[$cursor + 1]) -ge 4)
                    {
                        $content.Add('');
                        $cursor++;
                        continue;
                    }

                    break;
                }

                if ($this.Indent($next) -lt 2) { break; }

                $content.Add($next.Substring([Math]::Min(4, $this.Indent($next))));
                $cursor++;
            }

            $id = $note.Groups[1].Value;

            if (-not $this.Footnotes.ContainsKey($id)) { $this.Footnotes[$id] = $this.ParseBlocks($content); }

            return $cursor;
        }

        $reference = [MD_Pattern]::Reference.Match($line);

        if ($reference.Success)
        {
            $label = [regex]::Replace($reference.Groups[1].Value.Trim(), '\s+', ' ').ToLowerInvariant();
            $url = $reference.Groups[2].Success ? $reference.Groups[2].Value : $reference.Groups[3].Value;
            $title = '';

            foreach ($group in 4..6)
            {
                if ($reference.Groups[$group].Success) { $title = $reference.Groups[$group].Value; }
            }

            if (-not $this.Links.ContainsKey($label)) { $this.Links[$label] = @{ Url = $url; Title = $title }; }

            return $index + 1;
        }

        return -1;
    }

    [int] ParseParagraph([List[string]] $lines, [int] $index, [List[MD_Block]] $blocks)
    {
        $text = [List[string]]::new();
        $text.Add($lines[$index].TrimStart());
        $cursor = $index + 1;
        $level = 0;

        while ($cursor -lt $lines.Count)
        {
            $line = $lines[$cursor];

            if ([string]::IsNullOrWhiteSpace($line)) { break; }

            $setext = [MD_Pattern]::Setext.Match($line);

            if ($setext.Success)
            {
                $level = $setext.Groups[1].Value.StartsWith('=') ? 1 : 2;
                $cursor++;
                break;
            }

            if ($this.Interrupts($lines, $cursor)) { break; }

            $text.Add($line.TrimStart());
            $cursor++;
        }

        $kind = ($level -gt 0) ? 'heading' : 'paragraph';
        $block = [MD_Block]::new($kind);
        $block.Level = $level;
        $block.Text = ([string]::Join("`n", $text)).TrimEnd();
        $blocks.Add($block);

        return $cursor;
    }
}

class MD_InlineParser
{
    [hashtable] $Links;
    [hashtable] $Footnotes;

    MD_InlineParser([hashtable] $links, [hashtable] $footnotes)
    {
        $this.Links = $links;
        $this.Footnotes = $footnotes;
    }

    [List[MD_Inline]] Parse([string] $text)
    {
        $nodes = [List[MD_Inline]]::new();
        $buffer = [StringBuilder]::new();
        $position = 0;

        while ($position -lt $text.Length)
        {
            $found = [MD_Pattern]::Special.Match($text, $position);

            if (-not $found.Success)
            {
                [void] $buffer.Append($text, $position, $text.Length - $position);
                break;
            }

            if ($found.Index -gt $position) { [void] $buffer.Append($text, $position, $found.Index - $position); }

            $position = $found.Index;
            $char = $text[$position];

            if ($char -ceq "`n") { $position = $this.ScanNewline($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '\') { $position = $this.ScanEscape($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '`') { $position = $this.ScanCode($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '*' -or $char -ceq '_' -or $char -ceq '~') { $position = $this.ScanDelimiter($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '!') { $position = $this.ScanImage($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '[') { $position = $this.ScanOpen($text, $position, $nodes, $buffer); }
            elseif ($char -ceq ']') { $position = $this.ScanClose($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '<') { $position = $this.ScanAngle($text, $position, $nodes, $buffer); }
            elseif ($char -ceq '&') { $position = $this.ScanEntity($text, $position, $nodes, $buffer); }
            else { $position = $this.ScanBare($text, $position, $nodes, $buffer); }
        }

        $this.Flush($nodes, $buffer);
        $this.Emphasis($nodes, 0);
        $this.Resolve($nodes);

        return $nodes;
    }

    [void] Flush([List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        if ($buffer.Length -eq 0) { return; }

        $nodes.Add([MD_Inline]::new('text', $buffer.ToString()));
        [void] $buffer.Clear();
    }

    [int] ScanNewline([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $content = $buffer.ToString();
        $trailing = $content.Length - $content.TrimEnd(' ').Length;

        $buffer.Length = $content.Length - $trailing;
        $kind = ($trailing -ge 2) ? 'hard' : 'soft';

        $this.Flush($nodes, $buffer);
        $nodes.Add([MD_Inline]::new($kind, ''));

        $position++;

        while ($position -lt $text.Length -and $text[$position] -ceq ' ') { $position++; }

        return $position;
    }

    [int] ScanEscape([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        if ($position + 1 -ge $text.Length)
        {
            [void] $buffer.Append('\');

            return $position + 1;
        }

        $next = $text[$position + 1];

        if ($next -ceq "`n")
        {
            $this.Flush($nodes, $buffer);
            $nodes.Add([MD_Inline]::new('hard', ''));

            $position += 2;

            while ($position -lt $text.Length -and $text[$position] -ceq ' ') { $position++; }

            return $position;
        }

        if ([MD_Pattern]::Punctuation.IsMatch([string] $next))
        {
            [void] $buffer.Append($next);

            return $position + 2;
        }

        [void] $buffer.Append('\');

        return $position + 1;
    }

    [int] ScanCode([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $end = $position;

        while ($end -lt $text.Length -and $text[$end] -ceq '`') { $end++; }

        $length = $end - $position;
        $closing = [regex]::new('(?<!`)`{' + $length + '}(?!`)').Match($text, $end);

        if (-not $closing.Success)
        {
            [void] $buffer.Append($text, $position, $length);

            return $end;
        }

        $content = $text.Substring($end, $closing.Index - $end).Replace("`n", ' ');

        if ($content.Length -gt 2 -and $content.StartsWith(' ') -and $content.EndsWith(' ') -and $content.Trim().Length -gt 0)
        {
            $content = $content.Substring(1, $content.Length - 2);
        }

        $this.Flush($nodes, $buffer);
        $nodes.Add([MD_Inline]::new('code', $content));

        return $closing.Index + $length;
    }

    [int] ScanDelimiter([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $mark = $text[$position];
        $end = $position;

        while ($end -lt $text.Length -and $text[$end] -ceq $mark) { $end++; }

        $count = $end - $position;

        if ($mark -ceq '~' -and $count -ne 2)
        {
            [void] $buffer.Append($text, $position, $count);

            return $end;
        }

        $before = ($position -gt 0) ? $text[$position - 1] : [char] ' ';
        $after = ($end -lt $text.Length) ? $text[$end] : [char] ' ';

        $beforeSpace = [char]::IsWhiteSpace($before);
        $afterSpace = [char]::IsWhiteSpace($after);
        $beforePunct = [char]::IsPunctuation($before) -or [char]::IsSymbol($before);
        $afterPunct = [char]::IsPunctuation($after) -or [char]::IsSymbol($after);

        $left = (-not $afterSpace) -and ((-not $afterPunct) -or $beforeSpace -or $beforePunct);
        $right = (-not $beforeSpace) -and ((-not $beforePunct) -or $afterSpace -or $afterPunct);
        $open = $left;
        $close = $right;

        if ($mark -ceq '_')
        {
            $open = $left -and ((-not $right) -or $beforePunct);
            $close = $right -and ((-not $left) -or $afterPunct);
        }

        if (-not $open -and -not $close)
        {
            [void] $buffer.Append($text, $position, $count);

            return $end;
        }

        $this.Flush($nodes, $buffer);

        $node = [MD_Inline]::new('delim', '');
        $node.Mark = [string] $mark;
        $node.Count = $count;
        $node.Origin = $count;
        $node.CanOpen = $open;
        $node.CanClose = $close;
        $nodes.Add($node);

        return $end;
    }

    [int] ScanImage([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        if ($position + 1 -lt $text.Length -and $text[$position + 1] -ceq '[')
        {
            $this.Flush($nodes, $buffer);

            $bracket = [MD_Inline]::new('bracket', '![');
            $bracket.Image = $true;
            $bracket.Origin = $position + 2;
            $nodes.Add($bracket);

            return $position + 2;
        }

        [void] $buffer.Append('!');

        return $position + 1;
    }

    [int] ScanOpen([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $this.Flush($nodes, $buffer);

        $note = [MD_Pattern]::Footref.Match($text, $position);

        if ($note.Success -and $this.Footnotes.ContainsKey($note.Groups[1].Value))
        {
            $nodes.Add([MD_Inline]::new('footnote', $note.Groups[1].Value));

            return $position + $note.Length;
        }

        $bracket = [MD_Inline]::new('bracket', '[');
        $bracket.Origin = $position + 1;
        $nodes.Add($bracket);

        return $position + 1;
    }

    [int] ScanClose([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $this.Flush($nodes, $buffer);

        $opener = -1;

        for ($cursor = $nodes.Count - 1; $cursor -ge 0; $cursor--)
        {
            if ($nodes[$cursor].Kind -eq 'bracket')
            {
                $opener = $cursor;
                break;
            }
        }

        if ($opener -lt 0)
        {
            [void] $buffer.Append(']');

            return $position + 1;
        }

        $bracket = $nodes[$opener];

        if (-not $bracket.Active)
        {
            $nodes[$opener] = [MD_Inline]::new('text', $bracket.Text);
            [void] $buffer.Append(']');

            return $position + 1;
        }

        $after = $position + 1;
        $end = $after;
        $url = $null;
        $title = '';
        $inline = [MD_Pattern]::Dest.Match($text, $after);

        if ($inline.Success)
        {
            $url = $inline.Groups[1].Success ? $inline.Groups[1].Value : $inline.Groups[2].Value;
            $end = $after + $inline.Length;

            foreach ($group in 3..5)
            {
                if ($inline.Groups[$group].Success) { $title = $inline.Groups[$group].Value; }
            }

            $url = [regex]::Replace($url, '\\([!-/:-@\[-`{-~])', '$1');
        }
        else
        {
            $label = $text.Substring($bracket.Origin, $position - $bracket.Origin);
            $reference = [MD_Pattern]::Label.Match($text, $after);

            if ($reference.Success)
            {
                if ($reference.Groups[1].Value.Length -gt 0) { $label = $reference.Groups[1].Value; }

                $end = $after + $reference.Length;
            }

            $key = [regex]::Replace($label.Trim(), '\s+', ' ').ToLowerInvariant();

            if ($this.Links.ContainsKey($key))
            {
                $url = $this.Links[$key].Url;
                $title = $this.Links[$key].Title;
            }
        }

        if ($null -eq $url)
        {
            $nodes[$opener] = [MD_Inline]::new('text', $bracket.Text);
            [void] $buffer.Append(']');

            return $position + 1;
        }

        $this.Emphasis($nodes, $opener + 1);

        $kind = $bracket.Image ? 'image' : 'link';
        $link = [MD_Inline]::new($kind, '');
        $link.Url = $url;
        $link.Title = $title;

        $count = $nodes.Count - $opener - 1;

        if ($count -gt 0)
        {
            $link.Children.AddRange($nodes.GetRange($opener + 1, $count));
            $nodes.RemoveRange($opener + 1, $count);
        }

        $this.Resolve($link.Children);

        if (-not $bracket.Image)
        {
            $link.Children = $this.Unwrap($link.Children);

            for ($cursor = 0; $cursor -lt $opener; $cursor++)
            {
                if ($nodes[$cursor].Kind -eq 'bracket' -and -not $nodes[$cursor].Image) { $nodes[$cursor].Active = $false; }
            }
        }

        $nodes[$opener] = $link;

        return $end;
    }

    [int] ScanAngle([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $auto = [MD_Pattern]::AutoLink.Match($text, $position);

        if ($auto.Success)
        {
            $this.Flush($nodes, $buffer);

            $url = $auto.Groups[1].Value;
            $link = [MD_Inline]::new('link', '');
            $link.Url = $url;
            $link.Children.Add([MD_Inline]::new('text', [regex]::Replace($url, '(?i)^mailto:', '')));
            $nodes.Add($link);

            return $position + $auto.Length;
        }

        $mail = [MD_Pattern]::AutoMail.Match($text, $position);

        if ($mail.Success)
        {
            $this.Flush($nodes, $buffer);

            $link = [MD_Inline]::new('link', '');
            $link.Url = 'mailto:' + $mail.Groups[1].Value;
            $link.Children.Add([MD_Inline]::new('text', $mail.Groups[1].Value));
            $nodes.Add($link);

            return $position + $mail.Length;
        }

        $tag = [MD_Pattern]::Tag.Match($text, $position);

        if ($tag.Success)
        {
            $this.Flush($nodes, $buffer);
            $nodes.Add([MD_Inline]::new('html', $tag.Value));

            return $position + $tag.Length;
        }

        [void] $buffer.Append('<');

        return $position + 1;
    }

    [int] ScanEntity([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $entity = [MD_Pattern]::Entity.Match($text, $position);

        if ($entity.Success)
        {
            $decoded = [System.Net.WebUtility]::HtmlDecode($entity.Value);

            if ($decoded -cne $entity.Value)
            {
                $decoded = [MD_Text]::Control.Replace($decoded, '').Replace([string][char] 0xA0, ' ');
                [void] $buffer.Append($decoded);

                return $position + $entity.Length;
            }
        }

        [void] $buffer.Append('&');

        return $position + 1;
    }

    [int] ScanBare([string] $text, [int] $position, [List[MD_Inline]] $nodes, [StringBuilder] $buffer)
    {
        $match = [MD_Pattern]::Bare.Match($text, $position);

        if (-not $match.Success)
        {
            [void] $buffer.Append($text[$position]);

            return $position + 1;
        }

        $value = $match.Value;

        while ($value.Length -gt 0)
        {
            $last = $value[$value.Length - 1];

            if ('?!.,:;*_~''"'.Contains($last))
            {
                $value = $value.Substring(0, $value.Length - 1);
                continue;
            }

            if ($last -ceq ')' -and $value.Split('(').Length -lt $value.Split(')').Length)
            {
                $value = $value.Substring(0, $value.Length - 1);
                continue;
            }

            break;
        }

        if (-not [regex]::IsMatch($value, '(?i)^(?:https?://|www\.)\w'))
        {
            [void] $buffer.Append($text[$position]);

            return $position + 1;
        }

        $this.Flush($nodes, $buffer);

        $link = [MD_Inline]::new('link', '');
        $link.Url = $value.StartsWith('www.', [StringComparison]::OrdinalIgnoreCase) ? "https://$value" : $value;
        $link.Children.Add([MD_Inline]::new('text', $value));
        $nodes.Add($link);

        return $position + $value.Length;
    }

    [void] Emphasis([List[MD_Inline]] $nodes, [int] $start)
    {
        $cursor = $start;

        while ($cursor -lt $nodes.Count)
        {
            $closer = $nodes[$cursor];

            if ($closer.Kind -ne 'delim' -or -not $closer.CanClose -or $closer.Count -le 0)
            {
                $cursor++;
                continue;
            }

            $found = -1;

            for ($back = $cursor - 1; $back -ge $start; $back--)
            {
                $candidate = $nodes[$back];

                if ($candidate.Kind -ne 'delim' -or $candidate.Mark -cne $closer.Mark -or -not $candidate.CanOpen -or $candidate.Count -le 0) { continue; }

                $sum = $candidate.Origin + $closer.Origin;
                $both = ($candidate.Origin % 3 -eq 0) -and ($closer.Origin % 3 -eq 0);

                if (($candidate.CanClose -or $closer.CanOpen) -and ($sum % 3 -eq 0) -and -not $both) { continue; }

                $found = $back;
                break;
            }

            if ($found -lt 0)
            {
                $cursor++;
                continue;
            }

            $opener = $nodes[$found];
            $use = ($opener.Count -ge 2 -and $closer.Count -ge 2) ? 2 : 1;
            $kind = ($closer.Mark -ceq '~') ? 'strike' : (($use -eq 2) ? 'strong' : 'em');
            $wrapper = [MD_Inline]::new($kind, '');
            $inside = $cursor - $found - 1;

            if ($inside -gt 0)
            {
                $wrapper.Children.AddRange($nodes.GetRange($found + 1, $inside));
                $nodes.RemoveRange($found + 1, $inside);
            }

            $nodes.Insert($found + 1, $wrapper);

            $opener.Count -= $use;
            $closer.Count -= $use;

            $cursor = $found + 2;

            if ($opener.Count -le 0)
            {
                $nodes.RemoveAt($found);
                $cursor--;
            }

            if ($closer.Count -le 0) { $nodes.RemoveAt($cursor); }
        }
    }

    [void] Resolve([List[MD_Inline]] $nodes)
    {
        for ($cursor = 0; $cursor -lt $nodes.Count; $cursor++)
        {
            $node = $nodes[$cursor];

            if ($node.Kind -eq 'delim') { $nodes[$cursor] = [MD_Inline]::new('text', $node.Mark * $node.Count); }
            elseif ($node.Kind -eq 'bracket') { $nodes[$cursor] = [MD_Inline]::new('text', $node.Text); }
            elseif ($node.Children.Count -gt 0) { $this.Resolve($node.Children); }
        }
    }

    [List[MD_Inline]] Unwrap([List[MD_Inline]] $nodes)
    {
        $result = [List[MD_Inline]]::new();

        foreach ($node in $nodes)
        {
            if ($node.Kind -eq 'link') { $result.AddRange($this.Unwrap($node.Children)); }
            else { $result.Add($node); }
        }

        return $result;
    }
}

class MD_Highlighter
{
    static [hashtable] $Cache = @{};
    static [hashtable] $Aliases = @{
        'ps1' = 'powershell'
        'psm1' = 'powershell'
        'psd1' = 'powershell'
        'pwsh' = 'powershell'
        'sh' = 'bash'
        'zsh' = 'bash'
        'shell' = 'bash'
        'console' = 'bash'
        'py' = 'python'
        'python3' = 'python'
        'js' = 'javascript'
        'jsx' = 'javascript'
        'mjs' = 'javascript'
        'cjs' = 'javascript'
        'node' = 'javascript'
        'ts' = 'typescript'
        'tsx' = 'typescript'
        'cs' = 'csharp'
        'c#' = 'csharp'
        'kotlin' = 'java'
        'kt' = 'java'
        'h' = 'c'
        'cc' = 'c'
        'cxx' = 'c'
        'hpp' = 'c'
        'cpp' = 'c'
        'c++' = 'c'
        'golang' = 'go'
        'rs' = 'rust'
        'pgsql' = 'sql'
        'mysql' = 'sql'
        'tsql' = 'sql'
        'sqlite' = 'sql'
        'jsonc' = 'json'
        'json5' = 'json'
        'yml' = 'yaml'
        'toml' = 'yaml'
        'ini' = 'yaml'
        'html' = 'xml'
        'htm' = 'xml'
        'svg' = 'xml'
        'xaml' = 'xml'
        'csproj' = 'xml'
        'patch' = 'diff'
    };
    static [hashtable] $Styles = @{
        'comment' = 'syn.comment'
        'string' = 'syn.string'
        'key' = 'syn.key'
        'directive' = 'syn.param'
        'constant' = 'syn.const'
        'variable' = 'syn.variable'
        'param' = 'syn.param'
        'number' = 'syn.number'
        'keyword' = 'syn.keyword'
        'function' = 'syn.function'
        'type' = 'syn.type'
    };

    static [string] Canonical([string] $name)
    {
        $key = $name.ToLowerInvariant();

        return [MD_Highlighter]::Aliases.ContainsKey($key) ? [MD_Highlighter]::Aliases[$key] : $key;
    }

    static [string] Words([string] $list)
    {
        return '\b(?:' + $list + ')\b';
    }

    static [hashtable] Specs()
    {
        $q = "'";
        $dq = '"(?:\\.|[^"\\\n])*"';
        $sq = $q + '(?:\\.|[^' + $q + '\\\n])*' + $q;
        $tick = '`(?:\\.|[^`\\])*`';
        $cstyle = '//.*|/\*[\s\S]*?\*/';
        $hash = '(?<!\S)#.*';
        $number = '\b(?:0[xX][0-9a-fA-F_]+|[0-9][0-9_]*(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\b';
        $call = '\b[A-Za-z_]\w*(?=\()';
        $type = '\b[A-Z][A-Za-z0-9_]*\b';
        $consts = 'true|false|null';

        $psString = '@"[\s\S]*?"@|@' + $q + '[\s\S]*?' + $q + '@|"(?:`.|[^"`\n])*"|' + $q + '(?:[^' + $q + '\n]|' + $q + $q + ')*' + $q;
        $pyString = '"""[\s\S]*?"""|' + $q + $q + $q + '[\s\S]*?' + $q + $q + $q + '|' + $dq + '|' + $sq;
        $sqlString = $q + '(?:[^' + $q + ']|' + $q + $q + ')*' + $q + '|' + $dq;
        $rustChar = $q + '(?:\\.|[^' + $q + '\\\n])' + $q;

        $javascript = 'async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|with|yield';
        $typescript = $javascript + '|interface|type|enum|implements|namespace|abstract|private|protected|public|readonly|declare|as|keyof|is|never|unknown|any|string|number|boolean|object';

        return @{
            'powershell' = @{
                'comment' = '<#[\s\S]*?#>|' + $hash
                'string' = $psString
                'constant' = '\$(?:true|false|null)\b'
                'variable' = '\$(?:\{[^}\n]*\}|[\w?$^][\w:]*)'
                'param' = '(?<![\w-])-[A-Za-z]\w*'
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('function|filter|workflow|class|enum|using|namespace|module|param|begin|process|end|dynamicparam|if|elseif|else|switch|for|foreach|while|do|until|break|continue|return|throw|try|catch|finally|trap|exit|in|data|hidden|static')
                'function' = '(?-i:\b[A-Z][a-z]+-[A-Z][A-Za-z0-9]*)'
                'type' = '\[[A-Za-z_][\w.]*(?:\[\])?\]'
                'IgnoreCase' = $true
            }
            'bash' = @{
                'comment' = $hash
                'string' = $dq + '|' + $q + '[^' + $q + '\n]*' + $q
                'variable' = '\$(?:\{[^}\n]*\}|\w+|[?#@*!$0-9])'
                'param' = '(?<![\w-])--?[A-Za-z][\w-]*'
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('if|then|elif|else|fi|for|while|until|do|done|case|esac|in|function|select|return|exit|break|continue|local|export|readonly|declare|unset|source|alias|echo|cd|set|shift|trap|eval|exec|test')
            }
            'python' = @{
                'comment' = $hash
                'string' = $pyString
                'directive' = '(?<=^[ \t]*)@[\w.]+'
                'constant' = [MD_Highlighter]::Words('True|False|None|self|cls')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case')
                'function' = $call
                'type' = $type
            }
            'javascript' = @{
                'comment' = $cstyle
                'string' = $tick + '|' + $dq + '|' + $sq
                'constant' = [MD_Highlighter]::Words('true|false|null|undefined|NaN|Infinity')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words($javascript)
                'function' = $call
                'type' = $type
            }
            'typescript' = @{
                'comment' = $cstyle
                'string' = $tick + '|' + $dq + '|' + $sq
                'constant' = [MD_Highlighter]::Words('true|false|null|undefined|NaN|Infinity')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words($typescript)
                'function' = $call
                'type' = $type
            }
            'csharp' = @{
                'comment' = $cstyle
                'string' = '@"(?:""|[^"])*"|' + $dq + '|' + $sq
                'constant' = [MD_Highlighter]::Words($consts)
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('abstract|as|async|await|base|bool|break|byte|case|catch|char|checked|class|const|continue|decimal|default|delegate|do|double|else|enum|event|explicit|extern|finally|fixed|float|for|foreach|goto|if|implicit|in|int|interface|internal|is|lock|long|namespace|new|object|operator|out|override|params|private|protected|public|readonly|ref|return|sbyte|sealed|short|sizeof|static|string|struct|switch|this|throw|try|typeof|uint|ulong|unchecked|unsafe|ushort|using|var|virtual|void|volatile|while|record|init|required|yield|where|when')
                'function' = $call
                'type' = $type
            }
            'java' = @{
                'comment' = $cstyle
                'string' = $dq + '|' + $sq
                'directive' = '(?<![\w])@[A-Za-z]\w*'
                'constant' = [MD_Highlighter]::Words($consts)
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|package|private|protected|public|return|short|static|super|switch|synchronized|this|throw|throws|transient|try|var|void|volatile|while|record|fun|val|when|object')
                'function' = $call
                'type' = $type
            }
            'c' = @{
                'comment' = $cstyle
                'string' = $dq + '|' + $sq
                'directive' = '(?<=^[ \t]*)#[ \t]*\w+'
                'constant' = [MD_Highlighter]::Words('true|false|NULL|nullptr')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('auto|bool|break|case|catch|char|class|const|constexpr|continue|default|delete|do|double|else|enum|explicit|extern|float|for|friend|goto|if|inline|int|long|namespace|new|operator|private|protected|public|register|return|short|signed|sizeof|static|struct|switch|template|this|throw|try|typedef|typename|union|unsigned|using|virtual|void|volatile|while')
                'function' = $call
                'type' = $type
            }
            'go' = @{
                'comment' = $cstyle
                'string' = $tick + '|' + $dq + '|' + $sq
                'constant' = [MD_Highlighter]::Words('true|false|nil|iota')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var')
                'function' = $call
                'type' = $type
            }
            'rust' = @{
                'comment' = $cstyle
                'string' = $dq + '|' + $rustChar
                'directive' = '#!?\[[^\]\n]*\]'
                'constant' = [MD_Highlighter]::Words('true|false|None|Some|Ok|Err')
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('as|async|await|break|const|continue|crate|dyn|else|enum|extern|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|type|unsafe|use|where|while')
                'function' = $call
                'type' = $type
            }
            'sql' = @{
                'comment' = '--.*|/\*[\s\S]*?\*/'
                'string' = $sqlString
                'constant' = [MD_Highlighter]::Words($consts)
                'number' = $number
                'keyword' = [MD_Highlighter]::Words('select|from|where|insert|into|values|update|set|delete|create|alter|drop|table|index|view|database|join|inner|left|right|outer|full|cross|on|group|by|order|having|limit|offset|union|all|distinct|as|and|or|not|in|is|like|between|exists|case|when|then|else|end|primary|key|foreign|references|constraint|default|unique|check|with|asc|desc')
                'function' = $call
                'IgnoreCase' = $true
            }
            'json' = @{
                'comment' = $cstyle
                'key' = $dq + '(?=\s*:)'
                'string' = $dq
                'constant' = [MD_Highlighter]::Words($consts)
                'number' = '-?\b[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\b'
            }
            'yaml' = @{
                'comment' = $hash
                'key' = '(?<=^[ \t]*(?:-[ \t]+)*)[\w.\-/]+(?=[ \t]*(?::(?:[ \t]|$)|=))'
                'directive' = '(?<=^)\[[^\]\n]+\]$'
                'string' = $dq + '|' + $sq
                'constant' = [MD_Highlighter]::Words('true|false|null|yes|no|on|off')
                'number' = $number
            }
            'xml' = @{
                'comment' = '<!--[\s\S]*?-->'
                'string' = $dq + '|' + $sq
                'keyword' = '</?[A-Za-z][\w:.-]*|/?>|<\?[\w-]*|\?>|<!DOCTYPE'
                'param' = '[A-Za-z_:][\w:.-]*(?==)'
                'constant' = '&\w+;'
            }
        };
    }

    static [hashtable] Build([string] $name)
    {
        $store = [MD_Highlighter]::Cache;

        if ($store.ContainsKey($name)) { return $store[$name]; }

        if (-not $store.ContainsKey('#specs')) { $store['#specs'] = [MD_Highlighter]::Specs(); }

        $specs = $store['#specs'];

        if (-not $specs.ContainsKey($name))
        {
            $store[$name] = $null;

            return $null;
        }

        $spec = $specs[$name];
        $parts = [List[string]]::new();
        $groups = [List[string]]::new();

        foreach ($group in 'comment', 'string', 'key', 'directive', 'constant', 'variable', 'param', 'number', 'keyword', 'function', 'type')
        {
            if ($spec.ContainsKey($group))
            {
                $parts.Add("(?<$group>" + $spec[$group] + ')');
                $groups.Add($group);
            }
        }

        $options = [RegexOptions]::Multiline -bor [RegexOptions]::CultureInvariant;

        if ($spec.ContainsKey('IgnoreCase')) { $options = $options -bor [RegexOptions]::IgnoreCase; }

        $store[$name] = @{
            Regex = [regex]::new([string]::Join('|', $parts), $options)
            Groups = $groups.ToArray()
        };

        return $store[$name];
    }

    static [List[string]] Highlight([string] $code, [string] $language, [MD_Theme] $palTheme)
    {
        $lines = [List[string]]::new();
        $name = [MD_Highlighter]::Canonical($language);
        $plain = $palTheme.Get('code.text');

        if ($name -eq 'diff')
        {
            foreach ($line in ($code -split "`n"))
            {
                $style = $plain;

                if ($line.StartsWith('+')) { $style = $palTheme.Get('syn.added'); }
                elseif ($line.StartsWith('-')) { $style = $palTheme.Get('syn.removed'); }
                elseif ($line.StartsWith('@@')) { $style = $palTheme.Get('syn.hunk'); }

                $lines.Add([MD_Ansi]::Paint($style, $line));
            }

            return $lines;
        }

        $build = [MD_Highlighter]::Build($name);

        if ($null -eq $build -or -not $palTheme.Color)
        {
            foreach ($line in ($code -split "`n")) { $lines.Add([MD_Ansi]::Paint($plain, $line)); }

            return $lines;
        }

        $texts = [List[string]]::new();
        $pairStyles = [List[string]]::new();
        $cursor = 0;

        foreach ($match in $build.Regex.Matches($code))
        {
            if ($match.Index -gt $cursor)
            {
                $texts.Add($code.Substring($cursor, $match.Index - $cursor));
                $pairStyles.Add($plain);
            }

            $style = $plain;

            foreach ($group in $build.Groups)
            {
                if ($match.Groups[$group].Success)
                {
                    $style = $palTheme.Get([MD_Highlighter]::Styles[$group]);
                    break;
                }
            }

            $texts.Add($match.Value);
            $pairStyles.Add($style);
            $cursor = $match.Index + $match.Length;
        }

        if ($cursor -lt $code.Length)
        {
            $texts.Add($code.Substring($cursor));
            $pairStyles.Add($plain);
        }

        $builder = [StringBuilder]::new();

        for ($index = 0; $index -lt $texts.Count; $index++)
        {
            $parts = @($texts[$index] -split "`n");

            for ($part = 0; $part -lt $parts.Length; $part++)
            {
                if ($part -gt 0)
                {
                    $lines.Add($builder.ToString());
                    [void] $builder.Clear();
                }

                if ($parts[$part].Length -gt 0) { [void] $builder.Append([MD_Ansi]::Paint($pairStyles[$index], $parts[$part])); }
            }
        }

        $lines.Add($builder.ToString());

        return $lines;
    }
}

class MD_Seg
{
    [string] $Text;
    [string] $Style;
    [string] $Url;
    [bool] $Break;

    MD_Seg([string] $text, [string] $style, [string] $url)
    {
        $this.Text = $text;
        $this.Style = $style;
        $this.Url = $url;
    }

    static [MD_Seg] Newline()
    {
        $seg = [MD_Seg]::new('', '', '');
        $seg.Break = $true;

        return $seg;
    }

    [string] Render([string] $text)
    {
        $result = [MD_Ansi]::Paint($this.Style, $text);

        if ($this.Url.Length -gt 0) { $result = [MD_Ansi]::Link($this.Url, $result); }

        return $result;
    }
}

class MD_Cell
{
    [List[MD_Seg]] $Segments;
    [List[string]] $Lines;
    [int] $Min;
    [int] $Max;
}

class MD_Wrapper
{
    [int] $Width;
    [int] $Used;
    [int] $Size;
    [string] $TailStyle;
    [string] $TailUrl;
    [StringBuilder] $Line;
    [List[string]] $Lines;
    [List[MD_Seg]] $Word;

    MD_Wrapper([int] $width)
    {
        $this.Width = [Math]::Max(1, $width);
        $this.Used = 0;
        $this.Size = 0;
        $this.TailStyle = '';
        $this.TailUrl = '';
        $this.Line = [StringBuilder]::new();
        $this.Lines = [List[string]]::new();
        $this.Word = [List[MD_Seg]]::new();
    }

    [void] Push([MD_Seg] $seg)
    {
        if ($seg.Break)
        {
            $this.EndWord();
            $this.NewLine();

            return;
        }

        $parts = $seg.Text.Split([char] 32);

        for ($index = 0; $index -lt $parts.Length; $index++)
        {
            if ($index -gt 0) { $this.EndWord(); }
            if ($parts[$index].Length -eq 0) { continue; }

            $this.Word.Add([MD_Seg]::new($parts[$index], $seg.Style, $seg.Url));
            $this.Size += [MD_Text]::Width($parts[$index]);
        }
    }

    [void] NewLine()
    {
        $this.Lines.Add($this.Line.ToString());
        [void] $this.Line.Clear();
        $this.Used = 0;
    }

    [void] EndWord()
    {
        if ($this.Word.Count -eq 0) { return; }

        $first = $this.Word[0];
        $last = $this.Word[$this.Word.Count - 1];

        if ($this.Used -gt 0 -and $this.Used + 1 + $this.Size -gt $this.Width) { $this.NewLine(); }

        if ($this.Size -gt $this.Width)
        {
            $this.Split();
        }
        else
        {
            if ($this.Used -gt 0)
            {
                $joined = $first.Style.Length -gt 0 -and $first.Style -ceq $this.TailStyle -and $first.Url -ceq $this.TailUrl;
                $gap = ' ';

                if ($joined) { $gap = $first.Render(' '); }

                [void] $this.Line.Append($gap);
                $this.Used++;
            }

            foreach ($piece in $this.Word) { [void] $this.Line.Append($piece.Render($piece.Text)); }

            $this.Used += $this.Size;
        }

        $this.TailStyle = $last.Style;
        $this.TailUrl = $last.Url;
        $this.Word.Clear();
        $this.Size = 0;
    }

    [void] Split()
    {
        foreach ($piece in $this.Word)
        {
            $chunk = [StringBuilder]::new();

            foreach ($element in [MD_Text]::Elements($piece.Text))
            {
                $cells = [MD_Text]::ElementWidth($element);

                if ($this.Used -gt 0 -and $this.Used + $cells -gt $this.Width)
                {
                    if ($chunk.Length -gt 0)
                    {
                        [void] $this.Line.Append($piece.Render($chunk.ToString()));
                        [void] $chunk.Clear();
                    }

                    $this.NewLine();
                }

                [void] $chunk.Append($element);
                $this.Used += $cells;
            }

            if ($chunk.Length -gt 0) { [void] $this.Line.Append($piece.Render($chunk.ToString())); }
        }
    }

    [List[string]] Finish()
    {
        $this.EndWord();

        if ($this.Used -gt 0) { $this.NewLine(); }

        return $this.Lines;
    }
}

class MD_Renderer
{
    [MD_Theme] $Theme;
    [MD_InlineParser] $Inline;
    [MD_Document] $Document;
    [int] $Width;
    [int] $Depth;
    [string] $LinkStyle;
    [string] $BaseUri;
    [string] $Base;
    [string] $TagUrl;
    [string] $TagTarget;
    [hashtable] $Tags;
    [hashtable] $LinkNumbers;
    [hashtable] $FootnoteNumbers;
    [List[string]] $LinkList;
    [List[string]] $FootnoteOrder;

    MD_Renderer([MD_Theme] $palTheme, [int] $width, [string] $linkStyle, [string] $baseUri)
    {
        $this.Theme = $palTheme;
        $this.Width = [Math]::Max(20, $width);
        $this.LinkStyle = $linkStyle;
        $this.BaseUri = $baseUri;
        $this.Depth = 0;
        $this.Base = '';
        $this.TagUrl = '';
        $this.TagTarget = '';
        $this.Tags = @{};
        $this.LinkNumbers = @{};
        $this.FootnoteNumbers = @{};
        $this.LinkList = [List[string]]::new();
        $this.FootnoteOrder = [List[string]]::new();
    }

    [string] Render([string] $markdown)
    {
        $this.Document = [MD_Parser]::new().Parse($markdown);
        $this.Inline = [MD_InlineParser]::new($this.Document.Links, $this.Document.Footnotes);
        $this.LinkNumbers = @{};
        $this.FootnoteNumbers = @{};
        $this.LinkList = [List[string]]::new();
        $this.FootnoteOrder = [List[string]]::new();
        $this.Base = '';
        $this.Depth = 0;

        $lines = $this.Blocks($this.Document.Blocks, $this.Width, $false);
        $this.AppendNotes($lines);

        return [string]::Join("`n", $lines);
    }

    [List[string]] Blocks([List[MD_Block]] $blocks, [int] $width, [bool] $tight)
    {
        $lines = [List[string]]::new();

        foreach ($block in $blocks)
        {
            $rendered = $this.Block($block, $width);

            if ($rendered.Count -eq 0) { continue; }
            if ($lines.Count -gt 0 -and -not $tight) { $lines.Add(''); }

            $lines.AddRange($rendered);
        }

        return $lines;
    }

    [List[string]] Block([MD_Block] $block, [int] $width)
    {
        $kind = $block.Kind;

        if ($kind -eq 'paragraph') { return $this.Flow($this.Inline.Parse($block.Text), $this.Base, $false, $width); }
        if ($kind -eq 'heading') { return $this.Heading($block, $width); }
        if ($kind -eq 'code') { return $this.Code($block, $width); }
        if ($kind -eq 'quote' -or $kind -eq 'alert') { return $this.Quote($block, $width); }
        if ($kind -eq 'list') { return $this.ListBlock($block, $width); }
        if ($kind -eq 'table') { return $this.Table($block, $width); }
        if ($kind -eq 'rule') { return $this.Rule($width); }

        return [List[string]]::new();
    }

    [List[string]] Wrap([List[MD_Seg]] $segments, [int] $width)
    {
        $wrapper = [MD_Wrapper]::new($width);

        foreach ($seg in $segments) { $wrapper.Push($seg); }

        return $wrapper.Finish();
    }

    [List[MD_Seg]] Segments([List[MD_Inline]] $nodes, [string] $style, [bool] $accent)
    {
        $segments = [List[MD_Seg]]::new();

        $this.Tags = @{ bold = 0; italic = 0; strike = 0; underline = 0; kbd = 0; code = 0; mark = 0; link = 0 };
        $this.TagUrl = '';
        $this.TagTarget = '';
        $this.Spans($nodes, $style, '', $accent, $false, $segments);

        return $segments;
    }

    [List[string]] Flow([List[MD_Inline]] $nodes, [string] $style, [bool] $accent, [int] $width)
    {
        return $this.Wrap($this.Segments($nodes, $style, $accent), $width);
    }

    [string] Accent([string] $kind)
    {
        if (-not $this.Theme.Color) { return ''; }
        if ($kind -eq 'strong') { return "`e[1m"; }
        if ($kind -eq 'em') { return "`e[3m"; }

        return "`e[9m";
    }

    [string] Decorate([string] $style, [bool] $accent)
    {
        $palTheme = $this.Theme;
        $result = $style;

        if ($this.Tags['bold'] -gt 0) { $result += $accent ? $this.Accent('strong') : $palTheme.Get('strong'); }
        if ($this.Tags['italic'] -gt 0) { $result += $accent ? $this.Accent('em') : $palTheme.Get('em'); }
        if ($this.Tags['strike'] -gt 0) { $result += $accent ? $this.Accent('strike') : $palTheme.Get('strike'); }
        if ($this.Tags['underline'] -gt 0 -and $palTheme.Color) { $result += "`e[4m"; }
        if ($this.Tags['kbd'] -gt 0) { $result += $palTheme.Get('kbd'); }
        if ($this.Tags['code'] -gt 0) { $result += $palTheme.Get('code'); }
        if ($this.Tags['mark'] -gt 0) { $result += $palTheme.Get('mark'); }
        if ($this.Tags['link'] -gt 0) { $result += $palTheme.Get('link'); }

        return $result;
    }

    [void] Spans([List[MD_Inline]] $nodes, [string] $style, [string] $url, [bool] $accent, [bool] $inLink, [List[MD_Seg]] $out)
    {
        $palTheme = $this.Theme;

        foreach ($node in $nodes)
        {
            $kind = $node.Kind;
            $current = $this.Decorate($style, $accent);
            $target = ($url.Length -gt 0) ? $url : $this.TagUrl;

            if ($kind -eq 'text')
            {
                $out.Add([MD_Seg]::new($node.Text, $current, $target));
            }
            elseif ($kind -eq 'soft')
            {
                $out.Add([MD_Seg]::new(' ', '', ''));
            }
            elseif ($kind -eq 'hard')
            {
                $out.Add([MD_Seg]::Newline());
            }
            elseif ($kind -eq 'code')
            {
                $pad = $palTheme.Mark('code').Replace(' ', [string][char] 0xA0);
                $text = $pad + $node.Text.Replace(' ', [string][char] 0xA0) + $pad;

                $out.Add([MD_Seg]::new($text, $current + $palTheme.Get('code'), $target));
            }
            elseif ($kind -eq 'em' -or $kind -eq 'strong' -or $kind -eq 'strike')
            {
                $mark = $palTheme.Mark($kind);
                $inner = $style + ($accent ? $this.Accent($kind) : $palTheme.Get($kind));

                if ($mark.Length -gt 0) { $out.Add([MD_Seg]::new($mark, $current, $target)); }

                $this.Spans($node.Children, $inner, $url, $accent, $inLink, $out);

                if ($mark.Length -gt 0) { $out.Add([MD_Seg]::new($mark, $current, $target)); }
            }
            elseif ($kind -eq 'link')
            {
                $this.LinkSpans($node, $current, $url, $inLink, $out);
            }
            elseif ($kind -eq 'image')
            {
                $this.ImageSpans($node, $current, $url, $inLink, $out);
            }
            elseif ($kind -eq 'footnote')
            {
                $id = $node.Text;

                if (-not $this.FootnoteNumbers.ContainsKey($id))
                {
                    $this.FootnoteOrder.Add($id);
                    $this.FootnoteNumbers[$id] = $this.FootnoteOrder.Count;
                }

                $out.Add([MD_Seg]::new($palTheme.Super($this.FootnoteNumbers[$id]), $current + $palTheme.Get('footnote'), ''));
            }
            elseif ($kind -eq 'html')
            {
                $this.Tag($node.Text, $inLink, $out);
            }
        }
    }

    [string] Attr([string] $tag, [string] $name)
    {
        $match = [regex]::Match($tag, "(?i)\b$name\s*=\s*(?:`"([^`"]*)`"|'([^']*)'|([^\s>]+))");

        if (-not $match.Success) { return ''; }

        $value = '';

        foreach ($group in 1..3)
        {
            if ($match.Groups[$group].Success) { $value = $match.Groups[$group].Value; }
        }

        return [MD_Text]::Control.Replace([System.Net.WebUtility]::HtmlDecode($value), '');
    }

    [void] Tag([string] $tag, [bool] $inLink, [List[MD_Seg]] $out)
    {
        if ($tag.StartsWith('<!--')) { return; }

        $match = [MD_Pattern]::TagName.Match($tag);
        $closing = $match.Groups[1].Length -gt 0;
        $name = $match.Groups[2].Value.ToLowerInvariant();

        if ($name -eq 'br')
        {
            $out.Add([MD_Seg]::Newline());

            return;
        }

        if ($name -eq 'img')
        {
            $image = [MD_Inline]::new('image', '');
            $image.Url = $this.Attr($tag, 'src');
            $image.Children.Add([MD_Inline]::new('text', $this.Attr($tag, 'alt')));

            $this.ImageSpans($image, '', '', $inLink, $out);

            return;
        }

        if ($name -eq 'a')
        {
            if ($closing)
            {
                $this.Tags['link'] = [Math]::Max(0, $this.Tags['link'] - 1);

                if ($this.TagTarget.Length -gt 0 -and $this.TagUrl.Length -eq 0 -and -not $inLink -and $this.Listable($this.TagTarget))
                {
                    $out.Add($this.Suffix($this.TagTarget));
                }

                $this.TagUrl = '';
                $this.TagTarget = '';

                return;
            }

            $href = $this.Attr($tag, 'href');
            $absolute = $this.Absolute($href);

            if ($href.Length -gt 0)
            {
                $this.Tags['link'] = $this.Tags['link'] + 1;
                $this.TagTarget = $href;
                $this.TagUrl = ($this.LinkStyle -eq 'Hyperlink' -and $absolute.Length -gt 0 -and $this.Safe($absolute)) ? $absolute : '';
            }

            return;
        }

        if ([MD_Pattern]::TagKeys.ContainsKey($name))
        {
            $key = [MD_Pattern]::TagKeys[$name];
            $step = $closing ? -1 : 1;

            $this.Tags[$key] = [Math]::Max(0, $this.Tags[$key] + $step);
        }
    }

    [string] Plain([List[MD_Inline]] $nodes)
    {
        $builder = [StringBuilder]::new();

        foreach ($node in $nodes)
        {
            if ($node.Kind -eq 'text' -or $node.Kind -eq 'code') { [void] $builder.Append($node.Text); }
            elseif ($node.Kind -eq 'soft' -or $node.Kind -eq 'hard') { [void] $builder.Append(' '); }
            else { [void] $builder.Append($this.Plain($node.Children)); }
        }

        return $builder.ToString();
    }

    [string] Absolute([string] $url)
    {
        if ($url.Length -eq 0 -or $url.StartsWith('#')) { return ''; }
        if ([MD_Pattern]::Scheme.IsMatch($url)) { return $url; }
        if ($this.BaseUri.Length -eq 0) { return ''; }

        $result = '';

        try { $result = [Uri]::new([Uri]::new($this.BaseUri), $url).AbsoluteUri; }
        catch { $result = ''; }

        return $result;
    }

    [bool] Safe([string] $url)
    {
        return [MD_Pattern]::Safe.IsMatch($url);
    }

    [bool] Listable([string] $target)
    {
        return $target.Length -gt 0 -and -not $target.StartsWith('#') -and -not $target.StartsWith('data:');
    }

    [bool] Same([string] $text, [string] $url)
    {
        $left = [regex]::Replace($text.Trim(), '(?i)^(?:https?://|mailto:)', '').TrimEnd('/');
        $right = [regex]::Replace($url.Trim(), '(?i)^(?:https?://|mailto:)', '').TrimEnd('/');

        return $left -eq $right;
    }

    [string] Shown([string] $target)
    {
        $absolute = $this.Absolute($target);

        return ($absolute.Length -gt 0) ? $absolute : $target;
    }

    [MD_Seg] Suffix([string] $target)
    {
        $shown = $this.Shown($target);

        if ($this.LinkStyle -eq 'Inline')
        {
            return [MD_Seg]::new(' (' + $shown + ')', $this.Theme.Get('url'), '');
        }

        if (-not $this.LinkNumbers.ContainsKey($shown))
        {
            $this.LinkList.Add($shown);
            $this.LinkNumbers[$shown] = $this.LinkList.Count;
        }

        return [MD_Seg]::new('[' + $this.LinkNumbers[$shown] + ']', $this.Theme.Get('link.ref'), '');
    }

    [void] LinkSpans([MD_Inline] $node, [string] $style, [string] $url, [bool] $inLink, [List[MD_Seg]] $out)
    {
        $target = $node.Url;
        $absolute = $this.Absolute($target);
        $hyper = $this.LinkStyle -eq 'Hyperlink' -and $absolute.Length -gt 0 -and $this.Safe($absolute);
        $inner = $style + $this.Theme.Get('link');

        if ($hyper)
        {
            $this.Spans($node.Children, $inner, $absolute, $true, $true, $out);

            return;
        }

        $this.Spans($node.Children, $inner, $url, $true, $true, $out);

        if ($inLink -or -not $this.Listable($target) -or $this.Same($this.Plain($node.Children), $target)) { return; }

        $out.Add($this.Suffix($target));
    }

    [void] ImageSpans([MD_Inline] $node, [string] $style, [string] $url, [bool] $inLink, [List[MD_Seg]] $out)
    {
        $target = $node.Url;
        $alt = $this.Plain($node.Children).Trim();

        if ($alt.Length -eq 0 -and -not $target.StartsWith('data:'))
        {
            $path = ($target -split '[?#]')[0].TrimEnd('/');
            $alt = $path.Substring($path.LastIndexOf('/') + 1);
        }

        if ($alt.Length -eq 0) { $alt = 'image'; }

        $absolute = $this.Absolute($target);
        $hyper = $this.LinkStyle -eq 'Hyperlink' -and -not $inLink -and $absolute.Length -gt 0 -and $this.Safe($absolute);
        $segUrl = $hyper ? $absolute : $url;

        $out.Add([MD_Seg]::new($this.Theme.Glyph('image') + ' ' + $alt, $style + $this.Theme.Get('image'), $segUrl));

        if (-not $hyper -and -not $inLink -and $this.Listable($target)) { $out.Add($this.Suffix($target)); }
    }

    [List[string]] Heading([MD_Block] $block, [int] $width)
    {
        $palTheme = $this.Theme;
        $level = $block.Level;
        $style = $palTheme.Get("h$level");
        $prefix = ($level -ge 3) ? (('#' * $level) + ' ') : '';
        $body = $this.Flow($this.Inline.Parse($block.Text), $style, $true, $width - $prefix.Length);
        $lines = [List[string]]::new();

        for ($index = 0; $index -lt $body.Count; $index++)
        {
            $lead = ($index -eq 0) ? [MD_Ansi]::Paint($palTheme.Get('h.mark'), $prefix) : (' ' * $prefix.Length);
            $lines.Add($lead + $body[$index]);
        }

        if ($lines.Count -gt 0 -and $level -le 2)
        {
            $glyph = ($level -eq 1) ? 'rule1' : 'rule2';

            $lines.Add([MD_Ansi]::Paint($palTheme.Get("h${level}.rule"), [MD_Text]::Repeat($palTheme.Glyph($glyph), $width)));
        }

        return $lines;
    }

    [List[string]] Rule([int] $width)
    {
        $lines = [List[string]]::new();
        $lines.Add([MD_Ansi]::Paint($this.Theme.Get('rule'), [MD_Text]::Repeat($this.Theme.Glyph('rule2'), $width)));

        return $lines;
    }

    [List[string]] Code([MD_Block] $block, [int] $width)
    {
        $palTheme = $this.Theme;
        $language = $block.Info;
        $body = [MD_Highlighter]::Highlight($block.Text, $language, $palTheme);
        $gutter = [MD_Ansi]::Paint($palTheme.Get('code.border'), $palTheme.Glyph('gutter'));
        $label = ($language.Length -gt 0) ? ($palTheme.Color ? $language : "[$language]") : '';
        $widest = [MD_Text]::Width($label);
        $lines = [List[string]]::new();

        foreach ($line in $body) { $widest = [Math]::Max($widest, [MD_Text]::Visible($line)); }

        if (-not $palTheme.Color)
        {
            if ($label.Length -gt 0) { $lines.Add($gutter + ' ' + $label); }

            foreach ($line in $body) { $lines.Add($gutter + ' ' + $line); }

            return $lines;
        }

        $inner = [Math]::Min([Math]::Max(1, $width - 3), $widest);
        $background = $palTheme.Get('code.bg');
        $reset = [MD_Ansi]::Reset;
        $blank = $gutter + $background + [MD_Text]::Repeat(' ', $inner + 2) + $reset;

        if ($label.Length -gt 0)
        {
            $tail = [MD_Text]::Repeat(' ', $inner - [MD_Text]::Width($label));

            $lines.Add($gutter + $background + ' ' + $palTheme.Get('code.label') + $label + $reset + $background + $tail + ' ' + $reset);
        }
        else
        {
            $lines.Add($blank);
        }

        foreach ($line in $body)
        {
            $content = $line.Replace($reset, $reset + $background);
            $tail = [MD_Text]::Repeat(' ', $inner - [MD_Text]::Visible($line));

            $lines.Add($gutter + $background + ' ' + $content + $tail + ' ' + $reset);
        }

        $lines.Add($blank);

        return $lines;
    }

    [List[string]] Quote([MD_Block] $block, [int] $width)
    {
        $palTheme = $this.Theme;
        $saved = $this.Base;
        $glyph = $palTheme.Glyph('quote');
        $barStyle = $palTheme.Get('quote.bar');
        $lines = [List[string]]::new();

        if ($block.Kind -eq 'alert')
        {
            $barStyle = $palTheme.Get('alert.' + $block.Info);
            $title = $block.Info.Substring(0, 1).ToUpperInvariant() + $block.Info.Substring(1);
            $header = [MD_Ansi]::Paint($barStyle, $palTheme.Glyph($block.Info) + ' ' + $title);

            $lines.Add([MD_Ansi]::Paint($barStyle, $glyph) + ' ' + $header);
            $this.Base = '';
        }
        else
        {
            $this.Base = $palTheme.Get('quote');
        }

        $body = $this.Blocks($block.Children, [Math]::Max(10, $width - 2), $false);
        $this.Base = $saved;

        $bar = [MD_Ansi]::Paint($barStyle, $glyph);

        foreach ($line in $body)
        {
            if ($line.Length -eq 0) { $lines.Add($bar); }
            else { $lines.Add($bar + ' ' + $line); }
        }

        return $lines;
    }

    [List[string]] ListBlock([MD_Block] $block, [int] $width)
    {
        $palTheme = $this.Theme;
        $lines = [List[string]]::new();
        $digits = ($block.Level + $block.Children.Count - 1).ToString().Length;
        $number = $block.Level;
        $nestDepth = $this.Depth;

        $this.Depth++;

        foreach ($item in $block.Children)
        {
            $marker = '';
            $size = 1;

            if ($item.Task -gt 0)
            {
                $name = ($item.Task -eq 2) ? 'task.done' : 'task.open';
                $marker = [MD_Ansi]::Paint($palTheme.Get($name), $palTheme.Glyph($name));
            }
            elseif ($block.Ordered)
            {
                $label = $number.ToString().PadLeft($digits) + '.';
                $marker = [MD_Ansi]::Paint($palTheme.Get('number'), $label);
                $size = $label.Length;
            }
            else
            {
                $marker = [MD_Ansi]::Paint($palTheme.Get('bullet'), $palTheme.Bullets[$nestDepth % $palTheme.Bullets.Length]);
            }

            $indent = $size + 1;
            $body = $this.Blocks($item.Children, [Math]::Max(10, $width - $indent), $block.Tight);

            if ($lines.Count -gt 0 -and -not $block.Tight) { $lines.Add(''); }
            if ($body.Count -eq 0) { $lines.Add($marker); }

            for ($index = 0; $index -lt $body.Count; $index++)
            {
                if ($body[$index].Length -eq 0)
                {
                    $lines.Add('');
                    continue;
                }

                $lead = ($index -eq 0) ? ($marker + ' ') : (' ' * $indent);
                $lines.Add($lead + $body[$index]);
            }

            $number++;
        }

        $this.Depth--;

        return $lines;
    }

    [string] Edge([int[]] $widths, [string] $left, [string] $middle, [string] $right)
    {
        $palTheme = $this.Theme;
        $parts = [List[string]]::new();

        foreach ($size in $widths) { $parts.Add([MD_Text]::Repeat($palTheme.Glyph('h'), $size + 2)); }

        $text = $palTheme.Glyph($left) + [string]::Join($palTheme.Glyph($middle), $parts) + $palTheme.Glyph($right);

        return [MD_Ansi]::Paint($palTheme.Get('table.border'), $text);
    }

    [List[string]] Table([MD_Block] $block, [int] $width)
    {
        $palTheme = $this.Theme;
        $columns = $block.Align.Length;
        $grid = [List[MD_Cell[]]]::new();
        $natural = [int[]]::new($columns);
        $minimum = [int[]]::new($columns);

        for ($row = 0; $row -lt $block.Rows.Count; $row++)
        {
            $cells = [MD_Cell[]]::new($columns);
            $header = $row -eq 0;
            $style = $header ? $palTheme.Get('table.header') : $this.Base;

            for ($column = 0; $column -lt $columns; $column++)
            {
                $cell = [MD_Cell]::new();
                $cell.Segments = $this.Segments($this.Inline.Parse($block.Rows[$row][$column]), $style, $header);
                $cell.Lines = [List[string]]::new();
                $cell.Min = 1;
                $cell.Max = 0;

                $plain = [StringBuilder]::new();

                foreach ($segment in $cell.Segments)
                {
                    $piece = $segment.Break ? ' ' : $segment.Text;
                    [void] $plain.Append($piece);
                }

                foreach ($word in $plain.ToString().Split([char] 32, [StringSplitOptions]::RemoveEmptyEntries))
                {
                    $size = [MD_Text]::Width($word);
                    $cell.Min = [Math]::Max($cell.Min, $size);
                    $cell.Max += $size + 1;
                }

                $cell.Max = [Math]::Max(1, $cell.Max - 1);
                $natural[$column] = [Math]::Max($natural[$column], $cell.Max);
                $minimum[$column] = [Math]::Max($minimum[$column], $cell.Min);
                $cells[$column] = $cell;
            }

            $grid.Add($cells);
        }

        $room = $width - (3 * $columns + 1);
        $widths = [int[]]::new($columns);
        $total = 0;
        $floor = 0;

        for ($column = 0; $column -lt $columns; $column++)
        {
            $total += $natural[$column];
            $floor += $minimum[$column];
        }

        $ceiling = $natural;

        if ($total -le $room)
        {
            for ($column = 0; $column -lt $columns; $column++) { $widths[$column] = $natural[$column]; }
        }
        elseif ($floor -ge $room)
        {
            $ceiling = $minimum;

            for ($column = 0; $column -lt $columns; $column++)
            {
                $widths[$column] = [Math]::Max(1, [MD_Text]::Share($minimum[$column], $room, $floor));
            }
        }
        else
        {
            for ($column = 0; $column -lt $columns; $column++)
            {
                $extra = [MD_Text]::Share($room - $floor, $natural[$column] - $minimum[$column], $total - $floor);
                $widths[$column] = $minimum[$column] + $extra;
            }
        }

        if ($total -gt $room)
        {
            $left = $room;

            for ($column = 0; $column -lt $columns; $column++) { $left -= $widths[$column]; }

            $cursor = 0;

            while ($left -gt 0 -and $cursor -lt 10000)
            {
                $column = $cursor % $columns;

                if ($widths[$column] -lt $ceiling[$column])
                {
                    $widths[$column]++;
                    $left--;
                }

                $cursor++;
            }
        }

        $heights = [int[]]::new($grid.Count);
        $tall = $false;

        for ($row = 0; $row -lt $grid.Count; $row++)
        {
            $heights[$row] = 1;

            for ($column = 0; $column -lt $columns; $column++)
            {
                $cell = $grid[$row][$column];
                $cell.Lines = $this.Wrap($cell.Segments, $widths[$column]);

                if ($cell.Lines.Count -eq 0) { $cell.Lines.Add(''); }

                $heights[$row] = [Math]::Max($heights[$row], $cell.Lines.Count);
            }

            if ($row -gt 0 -and $heights[$row] -gt 1) { $tall = $true; }
        }

        $border = [MD_Ansi]::Paint($palTheme.Get('table.border'), $palTheme.Glyph('v'));
        $lines = [List[string]]::new();

        $lines.Add($this.Edge($widths, 'tl', 'tj', 'tr'));

        for ($row = 0; $row -lt $grid.Count; $row++)
        {
            if ($row -eq 1 -or ($row -gt 1 -and $tall)) { $lines.Add($this.Edge($widths, 'lj', 'cross', 'rj')); }

            for ($index = 0; $index -lt $heights[$row]; $index++)
            {
                $text = $border;

                for ($column = 0; $column -lt $columns; $column++)
                {
                    $cell = $grid[$row][$column];
                    $content = ($index -lt $cell.Lines.Count) ? $cell.Lines[$index] : '';
                    $text += ' ' + [MD_Text]::Pad($content, $widths[$column], $block.Align[$column]) + ' ' + $border;
                }

                $lines.Add($text);
            }
        }

        $lines.Add($this.Edge($widths, 'bl', 'bj', 'br'));

        return $lines;
    }

    [void] AppendNotes([List[string]] $lines)
    {
        $palTheme = $this.Theme;
        $notes = [List[string]]::new();
        $index = 0;

        while ($index -lt $this.FootnoteOrder.Count)
        {
            $number = $palTheme.Super($index + 1);
            $size = [MD_Text]::Width($number) + 1;
            $label = [MD_Ansi]::Paint($palTheme.Get('footnote'), $number) + ' ';
            $body = $this.Blocks($this.Document.Footnotes[$this.FootnoteOrder[$index]], [Math]::Max(10, $this.Width - $size), $true);

            for ($row = 0; $row -lt $body.Count; $row++)
            {
                $lead = ($row -eq 0) ? $label : (' ' * $size);
                $notes.Add($lead + $body[$row]);
            }

            $index++;
        }

        if ($notes.Count -gt 0)
        {
            if ($lines.Count -gt 0) { $lines.Add(''); }

            $lines.Add([MD_Ansi]::Paint($palTheme.Get('rule'), [MD_Text]::Repeat($palTheme.Glyph('rule2'), 12)));
            $lines.AddRange($notes);
        }

        if ($this.LinkList.Count -gt 0)
        {
            if ($lines.Count -gt 0) { $lines.Add(''); }

            $lines.Add([MD_Ansi]::Paint($palTheme.Get('h.mark'), [MD_Text]::Repeat($palTheme.Glyph('rule2'), 2) + ' Links'));

            for ($number = 0; $number -lt $this.LinkList.Count; $number++)
            {
                $label = [MD_Ansi]::Paint($palTheme.Get('link.ref'), '[' + ($number + 1) + ']');

                $lines.Add($label + ' ' + [MD_Ansi]::Paint($palTheme.Get('url'), $this.LinkList[$number]));
            }
        }
    }
}

$Script:ThemeFactory = [MD_Theme]::new;
$Script:RendererFactory = [MD_Renderer]::new;

function Test-MD_Hyperlink()
{
    <#
    .SYNOPSIS
        Tells whether the current terminal is known to support OSC 8
        hyperlinks. Set FORCE_HYPERLINK to override the detection.
    #>

    if ($env:FORCE_HYPERLINK) { return $true; }
    if ($env:WT_SESSION -or $env:KITTY_WINDOW_ID -or $env:KONSOLE_VERSION -or $env:WEZTERM_PANE -or $env:DOMTERM) { return $true; }
    if ($env:TERM_PROGRAM -in 'iTerm.app', 'vscode', 'WezTerm', 'ghostty', 'Hyper') { return $true; }
    if ($env:TERM -in 'xterm-kitty', 'xterm-ghostty', 'foot', 'alacritty') { return $true; }

    $vte = 0;

    return [int]::TryParse($env:VTE_VERSION, [ref] $vte) -and $vte -ge 5000;
}

function Test-MD_TrueColor()
{
    <#
    .SYNOPSIS
        Tells whether the current terminal is expected to render 24-bit
        colors. When it does not, the renderer falls back to the 256-color
        palette.
    #>

    if ($env:COLORTERM -in 'truecolor', '24bit') { return $true; }
    if ($env:WT_SESSION -or $env:TERM_PROGRAM -in 'iTerm.app', 'vscode', 'WezTerm', 'ghostty') { return $true; }

    return [bool] $IsWindows;
}

function Get-MD_Width()
{
    <#
    .SYNOPSIS
        Returns the line width used when none is given: the terminal width
        minus one column, capped at 100 for comfortable reading.
    #>

    $width = 0;

    try { $width = $Host.UI.RawUI.WindowSize.Width; } catch { $width = 0; }

    if ($width -le 0) { return 80; }

    return [Math]::Min($width - 1, 100);
}

function Get-MD_Theme()
{
    <#
    .SYNOPSIS
        Returns the default style table as a hashtable that can be edited and
        passed back through the Theme parameter.
    .DESCRIPTION
        Every value is a space separated list of tokens: a #rrggbb foreground,
        an on:#rrggbb background, and any of bold, dim, italic, underline and
        strike. Keys are element names such as h1, link, code, syn.keyword.
    .EXAMPLE
        $palTheme = Get-MD_Theme;
        $palTheme['h1'] = 'bold #ff5555';
        Write-MD_Markdown -Path .\README.md -Theme $palTheme;
    #>

    return [MD_Theme]::Defaults();
}

function ConvertTo-MD_Ansi(
    [Parameter(Mandatory, ValueFromPipeline)]
    [AllowEmptyString()]
    [string[]] $Markdown,

    [int] $Width,

    [ValidateSet('Auto', 'Hyperlink', 'Reference', 'Inline')]
    [string] $LinkStyle = 'Auto',

    [string] $BaseUri,
    [hashtable] $Theme,
    [switch] $NoColor
)
{
    <#
    .SYNOPSIS
        Renders markdown to a string of ANSI formatted terminal text.
    .DESCRIPTION
        Supports headings, paragraphs, emphasis, strikethrough, inline code,
        fenced and indented code blocks with syntax highlighting, block
        quotes, GitHub alerts, nested and task lists, tables, rules, links,
        images, footnotes and the common inline HTML tags. Mermaid and LaTeX
        are not interpreted: mermaid fences are shown as plain code and
        dollar signs are left alone.

        Links are rendered according to LinkStyle:
          Hyperlink  the link text is underlined and made clickable through
                     OSC 8, no url clutter in the text
          Reference  the link text is followed by a numbered marker and the
                     urls are listed under a Links heading at the end
          Inline     the link text is followed by its url in parentheses
          Auto       Hyperlink when the terminal is known to support it,
                     Reference otherwise
        Links that cannot be hyperlinks (relative without a BaseUri, unsafe
        schemes) fall back to Reference. Images become a labelled
        placeholder that follows the same rules.

        Control characters in the input are removed, so untrusted markdown
        cannot inject terminal escape sequences.
    .PARAMETER Markdown
        The markdown text. Several strings, such as the lines of a file, are
        joined with newlines.
    .PARAMETER Width
        Line width in columns. Defaults to the terminal width, at most 100.
    .PARAMETER LinkStyle
        Auto, Hyperlink, Reference or Inline, see the description.
    .PARAMETER BaseUri
        Absolute uri used to resolve relative links and image sources.
    .PARAMETER Theme
        Hashtable of style overrides, see Get-MD_Theme.
    .PARAMETER NoColor
        Produces plain text without escape sequences. Also implied by the
        NO_COLOR environment variable and plain output rendering.
    .EXAMPLE
        $answer | ConvertTo-MD_Ansi -Width 80 | Set-Clipboard
    #>

    begin
    {
        $buffer = [List[string]]::new();
    }

    process
    {
        foreach ($chunk in $Markdown) { $buffer.Add($chunk); }
    }

    end
    {
        $color = -not ($NoColor -or $env:NO_COLOR -or $PSStyle.OutputRendering -eq 'PlainText');
        $style = $LinkStyle;

        if ($style -eq 'Auto') { $style = ($color -and (Test-MD_Hyperlink)) ? 'Hyperlink' : 'Reference'; }
        if (-not $color -and $style -eq 'Hyperlink') { $style = 'Reference'; }
        if ($Width -le 0) { $Width = Get-MD_Width; }

        [MD_Ansi]::Depth = (Test-MD_TrueColor) ? 24 : 8;

        $palette = $Script:ThemeFactory.Invoke($color, $Theme);
        $renderer = $Script:RendererFactory.Invoke($palette, $Width, $style, $BaseUri);

        return $renderer.Render([string]::Join("`n", $buffer));
    }
}

function Write-MD_Markdown(
    [Parameter(ValueFromPipeline)]
    [AllowEmptyString()]
    [string[]] $Markdown,

    [string] $Path,
    [int] $Width,

    [ValidateSet('Auto', 'Hyperlink', 'Reference', 'Inline')]
    [string] $LinkStyle = 'Auto',

    [string] $BaseUri,
    [hashtable] $Theme,
    [switch] $NoColor
)
{
    <#
    .SYNOPSIS
        Prints markdown to the console as pretty formatted, colored text.
    .DESCRIPTION
        Takes markdown from the pipeline, the Markdown parameter or a file
        and prints it through ConvertTo-MD_Ansi. When reading a file, the
        file location is used as BaseUri unless one is given, so relative
        links to neighbouring files become clickable. Colors are dropped
        automatically when the output is redirected.
    .PARAMETER Markdown
        The markdown text, one or many strings.
    .PARAMETER Path
        Path of a markdown file to render.
    .PARAMETER Width
        Line width in columns. Defaults to the terminal width, at most 100.
    .PARAMETER LinkStyle
        Auto, Hyperlink, Reference or Inline, see ConvertTo-MD_Ansi.
    .PARAMETER BaseUri
        Absolute uri used to resolve relative links and image sources.
    .PARAMETER Theme
        Hashtable of style overrides, see Get-MD_Theme.
    .PARAMETER NoColor
        Prints plain text without escape sequences.
    .EXAMPLE
        Write-MD_Markdown -Path .\README.md
    .EXAMPLE
        $dialogue.Ask('explain pipes in powershell') | Write-MD_Markdown
    #>

    begin
    {
        $buffer = [List[string]]::new();
    }

    process
    {
        foreach ($chunk in $Markdown) { $buffer.Add($chunk); }
    }

    end
    {
        $arguments = @{
            Markdown = [string]::Join("`n", $buffer)
            LinkStyle = $LinkStyle
            NoColor = ($NoColor -or [Console]::IsOutputRedirected)
        };

        if ($Path)
        {
            $full = (Resolve-Path -LiteralPath $Path).Path;

            $arguments.Markdown = (Get-Content -LiteralPath $full -Raw -Encoding utf8) + "`n" + $arguments.Markdown;
            $arguments.BaseUri = [Uri]::new($full).AbsoluteUri;
        }

        if ($BaseUri) { $arguments.BaseUri = $BaseUri; }
        if ($Width -gt 0) { $arguments.Width = $Width; }
        if ($Theme) { $arguments.Theme = $Theme; }

        Write-Host (ConvertTo-MD_Ansi @arguments);
    }
}

function Show-MD_Demo(
    [ValidateSet('Auto', 'Hyperlink', 'Reference', 'Inline')]
    [string] $LinkStyle = 'Auto',

    [int] $Width,
    [switch] $NoColor
)
{
    <#
    .SYNOPSIS
        Renders a sample document that exercises every supported element.
    .PARAMETER LinkStyle
        Auto, Hyperlink, Reference or Inline, see ConvertTo-MD_Ansi.
    .PARAMETER Width
        Line width in columns. Defaults to the terminal width, at most 100.
    .PARAMETER NoColor
        Prints plain text without escape sequences.
    .EXAMPLE
        Show-MD_Demo -LinkStyle Reference
    #>

    $sample = @'
# Markdown in the terminal

A paragraph with **bold**, *italic*, ***both***, ~~strikethrough~~, `inline code`,
a [link with text](https://learn.microsoft.com/powershell/), a bare url https://example.com/docs
and an <https://example.com/auto> autolink.[^1] Escapes like \*this\* and entities like &copy; &amp; &lt;tag&gt; work too.
A hard break follows here:\
this is the next line.

## Lists

- Unordered item with a [reference link][pwsh]
  - Nested item
    - Even deeper
- [x] Finished task
- [ ] Open task

1. First
2. Second
   1. Nested ordered
3. Third

### Quotes and alerts

> A quote can hold *formatting* and
> span several lines.
>
> > Nested quotes work as well.

> [!TIP]
> Alerts keep the GitHub syntax and get their own color.

> [!WARNING]
> Watch out for **sharp edges**.

#### Code

```powershell
function Get-Answer([int] $Value = 42)
{
    # a comment
    $name = "world";
    return "hello $name, the answer is $Value";
}
```

```python
@decorator
def greet(name: str) -> str:
    """Say hello."""
    return f"hello {name}"  # trailing comment
```

```json
{ "name": "demo", "count": 3, "tags": ["a", "b"], "enabled": true }
```

```diff
@@ -1,2 +1,2 @@
-old line
+new line
```

##### Tables

| Feature | Status | Notes |
|:--------|:------:|------:|
| Headings | done | h1 to h6 |
| Tables | done | aligned, wrapped when they do not fit the terminal width |
| Links | done | `Hyperlink`, `Reference` or `Inline` |

###### Everything else

![Build status](https://img.shields.io/badge/build-passing-green) and a linked image
[![Logo](https://example.com/logo.png)](https://example.com).

Inline html: <kbd>Ctrl</kbd> + <kbd>C</kbd>, <b>bold</b>, <i>italic</i>, <u>underline</u>, <mark>marked</mark><br>
after a line break.

<details>
<summary>Collapsed section</summary>

Its content is shown as regular markdown.

</details>

---

[^1]: Footnotes are collected and printed at the end.

[pwsh]: https://github.com/PowerShell/PowerShell "PowerShell on GitHub"
'@;

    Write-MD_Markdown -Markdown $sample -LinkStyle $LinkStyle -Width $Width -NoColor:$NoColor;
}
