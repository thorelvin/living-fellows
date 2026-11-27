# SPDX-License-Identifier: MIT

# Build 42 strips block comments, including nested comments.
$ActiveModCommentPattern = '/\*(?:[^*/]|/(?!\*)|\*(?!/)|(?<depth>/\*)|(?<-depth>\*/))*(?(depth)(?!))\*/'

function Get-ActiveModsBlock([string]$Text) {
    $trivia = '(?:[ \t\r\n]|' + $ActiveModCommentPattern + ')*'
    $body = '(?:[^/{}]|/(?!\*)|' + $ActiveModCommentPattern + ')*'
    $pattern = '(?m:(?:^|(?<=,))' + $trivia + 'mods' + $trivia + '\{(?<entries>' + $body + ')\})|' +
        $ActiveModCommentPattern
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        if ($match.Groups['entries'].Success) { return $match }
    }
    return [System.Text.RegularExpressions.Match]::Empty
}

function Get-ActiveModEntryPattern([string[]]$ModIds) {
    $ids = ($ModIds | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # Look behind leading comments so removing an entry leaves the note intact.
    $prefix = '(?:(?<line>(?<=\n)[ \t]*)|(?:\A|(?<=,)|(?<=(?:\A|[,\n])[ \t\x1F]*\x1F))[ \t]*)'
    # Build 42 folds the key's case and accepts escaped values. Mod IDs are case-sensitive.
    return [regex]::new(
        $prefix + '(?i:mod)[ \t\x1F]*=[ \t\x1F]*\\*(?<id>' +
        $ids + ')[ \t\r\n\x1F]*,(?(line)(?:[ \t]*\r?\n)?)')
}

function Get-ActiveModEntries([string]$Text, [string[]]$ModIds) {
    # Keep original offsets while treating comments as syntax trivia. The
    # marker counts as whitespace inside an entry only, preserving other notes.
    $syntax = [regex]::Replace($Text, $ActiveModCommentPattern, {
        param($comment)
        ([string][char]0x1F) * $comment.Length
    })
    return (Get-ActiveModEntryPattern $ModIds).Matches($syntax)
}

function Add-ModEntry([string]$Text, [string]$ModId) {
    $block = Get-ActiveModsBlock $Text
    if (-not $block.Success) { throw 'mods.txt has no mods block.' }
    $entries = $block.Groups['entries']
    if (@(Get-ActiveModEntries $entries.Value @($ModId)).Count -gt 0) { return $Text }

    $firstNewline = [regex]::Match($entries.Value, '\A[ \t]*(?<newline>\r?\n)')
    if ($firstNewline.Success) {
        return $Text.Insert($entries.Index + $firstNewline.Length,
            ('    mod = ' + $ModId + ',' + $firstNewline.Groups['newline'].Value))
    }
    return $Text.Insert($entries.Index, (' mod = ' + $ModId + ','))
}

function Remove-ModEntry([string]$Text, [string]$ModId) {
    if ($ModId -notmatch '\A[A-Za-z0-9_. -]{1,128}\z') {
        throw "Unsafe excluded mod id: $ModId"
    }
    $block = Get-ActiveModsBlock $Text
    if (-not $block.Success) { return $Text }
    $entries = $block.Groups['entries']
    $matches = @(Get-ActiveModEntries $entries.Value @($ModId))
    for ($i = $matches.Count - 1; $i -ge 0; $i--) {
        $entry = $matches[$i]
        $Text = $Text.Remove($entries.Index + $entry.Index, $entry.Length)
    }
    return $Text
}
