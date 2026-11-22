# SPDX-License-Identifier: MIT

# ActiveModsFile accepts the backslash-prefixed form as well as a bare mod id.
$LivingFellowsProfileEntry = '(?m)^[ \t]*(?i:mod)[ \t]*=[ \t]*\\*SurvivorCompanion[ \t]*,?[ \t]*(?:\r?\n|$)'

function Read-LivingFellowsSteamKeyValues([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop }
    catch { return $null }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $root = @{}
    $tables = New-Object 'System.Collections.Generic.Stack[hashtable]'
    $tables.Push($root)
    $key = $null
    # Steam's library and workshop files use quoted KeyValues and nested tables.
    foreach ($token in [regex]::Matches($text, '//[^\r\n]*|"(?<text>(?:[^"\\]|\\.)*)"|[{}]')) {
        if ($token.Value -eq '{') {
            if ($null -eq $key) { return $null }
            $table = @{}
            $tables.Peek()[$key] = $table
            $tables.Push($table)
            $key = $null
        } elseif ($token.Value -eq '}') {
            if ($tables.Count -le 1 -or $null -ne $key) { return $null }
            $null = $tables.Pop()
        } elseif ($token.Groups['text'].Success) {
            $value = $token.Groups['text'].Value.Replace('\\', '\').Replace('\"', '"')
            if ($null -eq $key) { $key = $value }
            else {
                $tables.Peek()[$key] = $value
                $key = $null
            }
        }
    }
    if ($tables.Count -eq 1 -and $null -eq $key) { return $root }
    return $null
}

function Get-LivingFellowsSteamLibraries([string]$GameRoot, [switch]$IncludeRegistered) {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    if ($GameRoot) {
        $common = Split-Path -Parent ([IO.Path]::GetFullPath($GameRoot).TrimEnd('\'))
        $steamapps = if ($common) { Split-Path -Parent $common } else { '' }
        if ($steamapps -and (Split-Path -Leaf $common) -ieq 'common' -and
            (Split-Path -Leaf $steamapps) -ieq 'steamapps') {
            $roots.Add((Split-Path -Parent $steamapps))
        }
    }
    if ($IncludeRegistered) {
        foreach ($key in @('HKCU:\Software\Valve\Steam',
                'HKLM:\Software\WOW6432Node\Valve\Steam', 'HKLM:\Software\Valve\Steam')) {
            try {
                $steam = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                foreach ($property in @('SteamPath', 'InstallPath')) {
                    if ($steam.$property) { $roots.Add([string]$steam.$property) }
                }
            } catch { }
        }
        $roots.Add('C:\Program Files (x86)\Steam')
        $roots.Add('C:\Program Files\Steam')
    }

    $libraries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @($roots | Select-Object -Unique)) {
        $libraries.Add($root)
        $config = Read-LivingFellowsSteamKeyValues ([IO.Path]::Combine($root, 'steamapps\libraryfolders.vdf'))
        if ($config.libraryfolders -isnot [hashtable]) { continue }
        foreach ($index in @($config.libraryfolders.Keys | Where-Object { $_ -match '^[0-9]{1,9}$' } | Sort-Object { [int]$_ })) {
            $entry = $config.libraryfolders[$index]
            $path = if ($entry -is [hashtable]) { [string]$entry.path } else { [string]$entry }
            if ($path -and [IO.Path]::IsPathRooted($path)) { $libraries.Add($path) }
        }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        try { $path = [IO.Path]::GetFullPath($library) } catch { continue }
        if ($seen.Add($path) -and [IO.Directory]::Exists([IO.Path]::Combine($path, 'steamapps'))) { $path }
    }
}

function Get-LivingFellowsWorkshopCopies([string]$GameRoot) {
    if (-not $GameRoot) { return }
    # A game in another library or a custom location still uses the libraries
    # registered with Steam. Metadata-only game roots use their own library.
    $hasLauncher = Test-Path -LiteralPath (Join-Path $GameRoot 'ProjectZomboid64.exe') -PathType Leaf
    foreach ($library in @(Get-LivingFellowsSteamLibraries $GameRoot -IncludeRegistered:$hasLauncher)) {
        $workshop = Join-Path $library 'steamapps\workshop'
        $item = Join-Path $workshop 'content\108600\3805760339'
        $present = Test-Path -LiteralPath (Join-Path $item 'mods\SurvivorCompanion') -PathType Container
        $config = Read-LivingFellowsSteamKeyValues (Join-Path $workshop 'appworkshop_108600.acf')
        $record = $config.AppWorkshop
        # The details table can list a subscription before it has a folder or
        # an installed entry. Unlisted leftover content is safe after removal.
        $listed = ($record.WorkshopItemsInstalled -is [hashtable] -and
            $record.WorkshopItemsInstalled.ContainsKey('3805760339')) -or
            ($record.WorkshopItemDetails -is [hashtable] -and
                $record.WorkshopItemDetails.ContainsKey('3805760339'))
        if ($listed -or ($present -and $null -eq $record)) {
            [pscustomobject]@{ Path = $item; Installed = $present }
        }
    }
}

function Get-LivingFellowsStagingCopies([string]$ModsRoot) {
    $staging = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ModsRoot).TrimEnd('\'))) 'Workshop'
    if (Test-Path -LiteralPath $staging -PathType Container) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $staging -Directory -ErrorAction SilentlyContinue)) {
            $copy = Join-Path $folder.FullName 'Contents\mods\SurvivorCompanion'
            if (Test-Path -LiteralPath $copy -PathType Container) { $copy }
        }
    }
}
