# SPDX-License-Identifier: MIT

$LivingFellowsModId = 'LivingFellows'
$LivingFellowsLegacyModId = 'SurvivorCompanion'
$LivingFellowsModIds = @($LivingFellowsModId, $LivingFellowsLegacyModId)
$LivingFellowsModInfoPaths = @('mod.info', '42\mod.info')
$LivingFellowsBridgeOwner = 'LivingFellows.NativeBridge'
$LivingFellowsLegacyBridgeOwner = 'SurvivorCompanion.NativeBridge'
$LivingFellowsBridgeJar = 'LivingFellowsBridge.jar'
$LivingFellowsLegacyBridgeJar = 'SurvivorCompanionBridge.jar'
$LivingFellowsWrapperMain = 'livingfellows/bridge/SCLauncher'
$LivingFellowsLegacyWrapperMain = 'survivorcompanion/bridge/SCLauncher'

function Get-LivingFellowsProfilePattern([string[]]$Ids) {
    # ActiveModsFile accepts a leading backslash as well as a bare mod ID. Like
    # scripts\ActiveModList.ps1, fold the key's case but not the ID's: Build 42
    # treats survivorcompanion as a different mod from SurvivorCompanion.
    $alternatives = ($Ids | ForEach-Object { [regex]::Escape($_) }) -join '|'
    return '(?m)^([ \t]*(?i:mod)[ \t]*=[ \t]*\\*)(?:' + $alternatives + ')([ \t]*,?[ \t]*)(\r?\n|$)'
}
$LivingFellowsProfileEntry = Get-LivingFellowsProfilePattern $LivingFellowsModIds
$LivingFellowsLegacyProfileEntry = Get-LivingFellowsProfilePattern @($LivingFellowsLegacyModId)

function Get-LivingFellowsInstalledTarget([string]$ModsRoot) {
    $paths = @($LivingFellowsModIds | ForEach-Object { Join-Path $ModsRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ })
    if ($paths.Count -gt 1) {
        throw 'Both the current and previous Living Fellows mod directories are present. Resolve the duplicate before changing either one.'
    }
    if ($paths.Count -eq 1) { return $paths[0] }
    return (Join-Path $ModsRoot $LivingFellowsModId)
}

function Get-LivingFellowsModInfoIds([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    # Match the game's UTF-8 reader, which leaves any BOM in the first line.
    $metadata = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))
    $trimCharacters = [char[]](0..32)
    foreach ($line in ($metadata -split '\r\n|[\r\n]')) {
        if ($line.StartsWith('id=', [StringComparison]::Ordinal)) {
            $line.Replace('id=', '').Trim($trimCharacters)
        }
    }
}

function Get-LivingFellowsAdditionalModInfoPaths([string]$GenerationPath) {
    foreach ($directory in (Get-ChildItem -LiteralPath $GenerationPath -Directory -Force)) {
        if ($directory.Name -notmatch '^[0-9]+(?:\.[0-9]+)*$') { continue }
        $relative = Join-Path $directory.Name 'mod.info'
        if ($relative -notin $LivingFellowsModInfoPaths -and
            (Test-Path -LiteralPath (Join-Path $GenerationPath $relative) -PathType Leaf)) {
            $relative
        }
    }
}

function Test-LivingFellowsPayloadOwnership([string]$GenerationPath, $Manifest) {
    # A retained manifest, a common asset such as the license, or a few copied
    # scripts are not enough: most of the code the installed generation's
    # receipt lists must still match it.
    $mediaPrefix = [IO.Path]::GetFullPath((Join-Path $GenerationPath '42\media')) + '\'
    $code = @(foreach ($property in $Manifest.files.PSObject.Properties) {
        $relative = [string]$property.Name
        if ($relative -notmatch '^42/media/(lua|java)/.+\.(lua|jar)$' -or
            $relative -match '[:\\]|(?:^|/)\.\.?(?:/|$)' -or
            [string]$property.Value -notmatch '^[a-f0-9]{64}$') {
            continue
        }
        $path = [IO.Path]::GetFullPath((Join-Path $GenerationPath $relative.Replace('/', '\')))
        if ($path.StartsWith($mediaPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            [pscustomobject]@{ path = $path; hash = [string]$property.Value }
        }
    })
    $needed = [math]::Floor($code.Count / 2) + 1
    $matched = 0
    $remaining = $code.Count
    foreach ($file in $code) {
        $remaining--
        if ((Test-Path -LiteralPath $file.path -PathType Leaf) -and
            (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash -eq $file.hash) {
            $matched++
        }
        if ($matched -ge $needed) { return $true }
        if ($matched + $remaining -lt $needed) { return $false }
    }
    return $false
}

# A managed generation's mod ID. From 0.27.102 on, the ownership manifest records
# it. An older generation uses the ID its caller recorded when the backup was
# made, and failing that its whitelisted directory or backup name. If either
# mod.info is damaged, require matching payload code before accepting ownership.
# An alternate version directory may override the canonical files in the game.
function Get-LivingFellowsGenerationId([string]$GenerationPath, $Manifest, [string]$RecordedId = '') {
    $leaf = Split-Path -Leaf $GenerationPath
    $leafId = ''
    foreach ($candidate in $LivingFellowsModIds) {
        if ($leaf -eq $candidate -or
            $leaf.StartsWith("$candidate-managed-backup-", [StringComparison]::OrdinalIgnoreCase)) {
            $leafId = $candidate
        }
    }
    $id = [string]$Manifest.modId
    if (-not $id) { $id = $RecordedId }
    if (-not $id) { $id = $leafId }
    if ($id -cnotin $LivingFellowsModIds) {
        throw "Managed generation has an unrecognized mod ID: $GenerationPath"
    }
    $metadataAgrees = $true
    $metadataPaths = $LivingFellowsModInfoPaths + @(Get-LivingFellowsAdditionalModInfoPaths $GenerationPath)
    foreach ($relative in $metadataPaths) {
        $path = Join-Path $GenerationPath $relative
        $infoIds = @(Get-LivingFellowsModInfoIds $path)
        foreach ($infoId in $infoIds) {
            if ($infoId -cin $LivingFellowsModIds -and $infoId -cne $id) {
                throw "Managed generation's mod.info names a different mod ID: $path"
            }
        }
        if ($infoIds.Count -ne 1 -or $infoIds[0] -cne $id) { $metadataAgrees = $false }
    }
    if (-not $metadataAgrees -and -not (Test-LivingFellowsPayloadOwnership $GenerationPath $Manifest)) {
        throw "Managed generation's metadata and payload do not verify ownership: $GenerationPath"
    }
    return $id
}

function Test-LivingFellowsBackupName([string]$Leaf) {
    foreach ($id in $LivingFellowsModIds) {
        if ($Leaf.StartsWith("$id-managed-backup-", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-LivingFellowsNativeLayout([string]$Owner) {
    if ($Owner -ceq $LivingFellowsBridgeOwner) {
        return @{ jar = $LivingFellowsBridgeJar; wrapper = $LivingFellowsWrapperMain }
    }
    if ($Owner -ceq $LivingFellowsLegacyBridgeOwner) {
        return @{ jar = $LivingFellowsLegacyBridgeJar; wrapper = $LivingFellowsLegacyWrapperMain }
    }
    return $null
}

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
        $present = $false
        foreach ($id in $LivingFellowsModIds) {
            if (Test-Path -LiteralPath (Join-Path $item "mods\$id") -PathType Container) { $present = $true; break }
        }
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
            foreach ($id in $LivingFellowsModIds) {
                $copy = Join-Path $folder.FullName "Contents\mods\$id"
                if (Test-Path -LiteralPath $copy -PathType Container) { $copy }
            }
        }
    }
}
