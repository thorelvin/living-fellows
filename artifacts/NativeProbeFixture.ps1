# SPDX-License-Identifier: MIT

. (Join-Path $PSScriptRoot '..\scripts\ActiveModList.ps1')

function Set-NativeProbeModList([string]$Text) {
    # The probe supplies its own autoload hook and does not need the old harness.
    $Text = Remove-ModEntry $Text 'SCRealSandboxHarness'
    $block = Get-ActiveModsBlock $Text
    if (-not $block.Success) { throw 'Native probe fixture has no mods block.' }
    $entries = $block.Groups['entries']
    $updated = $Text.Substring($entries.Index, $entries.Length)
    $modEntries = @(Get-ActiveModEntries $updated @('SurvivorCompanion', 'LivingFellows'))
    if ($modEntries.Count -eq 0) { return Add-ModEntry $Text 'LivingFellows' }

    for ($i = $modEntries.Count - 1; $i -gt 0; $i--) {
        $updated = $updated.Remove($modEntries[$i].Index, $modEntries[$i].Length)
    }
    $id = $modEntries[0].Groups['id']
    $updated = $updated.Remove($id.Index, $id.Length).Insert($id.Index, 'LivingFellows')
    return $Text.Remove($entries.Index, $entries.Length).Insert($entries.Index, $updated)
}

function Get-NativeProbeHistoricalRoot([string]$ProjectRoot, [string]$HistoricalRunRoot) {
    if (-not $HistoricalRunRoot) {
        $HistoricalRunRoot = Join-Path $ProjectRoot 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8'
    }
    # Resolve a relative root against the PowerShell location. Windows
    # PowerShell 5.1 does not move the process directory that GetFullPath uses.
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HistoricalRunRoot)
    return [IO.Path]::GetFullPath($resolved)
}

# The controls scenarios that continue a save instead of reseeding. Only
# savesetup starts that save; each resuming scenario continues the latest one.
function Get-NativeProbeReceiptTarget([string]$Receipt) {
    if (-not (Test-Path -LiteralPath $Receipt -PathType Leaf)) { return '' }
    try { return [string](Get-Content -LiteralPath $Receipt -Raw -Encoding utf8 | ConvertFrom-Json).targetSave }
    catch { return '' }
}

function Get-NativeProbeResumeSave([string]$Receipt, [string]$HistoricalRunRoot) {
    if (-not (Test-Path -LiteralPath $Receipt -PathType Leaf)) {
        throw "Run savesetup first: there is no savesetup receipt at $Receipt"
    }
    $last = Get-Content -LiteralPath $Receipt -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$last.origin -cne 'savesetup') {
        throw "Run savesetup first: $Receipt was not written by a savesetup lineage."
    }
    if ([string]$last.history -ne $HistoricalRunRoot) {
        throw "Run savesetup first: the receipt belongs to another historical run: $($last.history)"
    }
    $target = [string]$last.targetSave
    if (-not $target -or -not (Test-Path -LiteralPath (Join-Path $target 'global_mod_data.bin') -PathType Leaf)) {
        throw "Run savesetup first: the receipt's save is missing: $target"
    }
    return $target
}

function Write-NativeProbeResumeReceipt([string]$Receipt, [string]$HistoricalRunRoot,
        [string]$TargetSave, [string]$Scenario) {
    $next = [ordered]@{
        origin = 'savesetup'; scenario = $Scenario
        history = $HistoricalRunRoot; targetSave = $TargetSave
    } | ConvertTo-Json
    New-Item -ItemType Directory -Path (Split-Path -Parent $Receipt) -Force | Out-Null
    $temporary = $Receipt + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, $next, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Receipt -Force
}

# Each run stages a full save and mod copy. Keep the newest few per probe and
# any run that holds a save still needed; never recurse into a junction.
function Remove-StaleNativeProbeRuns([string]$ProjectRoot, [string]$ProbeName,
        [string[]]$Preserve = @(), [int]$Keep = 2) {
    $probes = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build\native-probes'))
    if (-not (Test-Path -LiteralPath $probes -PathType Container)) { return }
    $pattern = '^' + [regex]::Escape($ProbeName) + '-[0-9a-f]{8}$'
    $kept = @($Preserve | Where-Object { $_ } | ForEach-Object {
        $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_)
        [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'
    })
    $runs = @(Get-ChildItem -LiteralPath $probes -Directory |
        Where-Object { $_.Name -match $pattern } | Sort-Object CreationTimeUtc -Descending)
    foreach ($run in @($runs | Select-Object -Skip $Keep)) {
        $prefix = $run.FullName.TrimEnd('\') + '\'
        if (@($kept | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count) {
            continue
        }
        if (($run.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            @(Get-ChildItem -LiteralPath $run.FullName -Recurse -Force -Attributes ReparsePoint).Count) {
            Write-Warning "Native probe run contains a junction and was kept: $($run.FullName)"
            continue
        }
        Remove-Item -LiteralPath $run.FullName -Recurse -Force
    }
}

function Get-NativeProbeLoadingAgent([string]$HistoricalRunRoot) {
    # Both agents accept the same marker-file path as their Java agent argument.
    foreach ($name in @('terminal-loading-agent.jar', 'loading-gate-agent.jar')) {
        $agent = Join-Path $HistoricalRunRoot $name
        if (Test-Path -LiteralPath $agent -PathType Leaf) { return $agent }
    }
    throw "The historical loading agent is missing from $HistoricalRunRoot"
}

function New-NativeProbeFixture {
    param(
        [string]$ProjectRoot, [string]$RunRoot, [string]$InputCache, [string]$InputSave,
        [string]$GameMode, [string]$World, [string]$LoadingAgent, [string[]]$ModFolders = @(),
        [switch]$UseProbeAutoload
    )

    if ($GameMode -notmatch '^[A-Za-z0-9 _-]+$' -or $World -notmatch '^[A-Za-z0-9 _-]+$') {
        throw "Invalid native probe save identity: $GameMode / $World"
    }
    if (Test-Path -LiteralPath $RunRoot) { throw "Native probe output already exists: $RunRoot" }
    if (-not (Test-Path -LiteralPath (Join-Path $InputSave 'players.db') -PathType Leaf)) {
        throw "The native probe input save is missing players.db: $InputSave"
    }
    $inputMods = Join-Path $InputCache 'mods'
    $saveProfile = Get-Content -LiteralPath (Join-Path $InputSave 'mods.txt') -Raw -Encoding utf8
    $defaultProfile = Get-Content -LiteralPath (Join-Path $inputMods 'default.txt') -Raw -Encoding utf8
    $saveProfile = Set-NativeProbeModList $saveProfile
    $defaultProfile = Set-NativeProbeModList $defaultProfile

    $cacheRoot = Join-Path $RunRoot 'cache'
    $mods = Join-Path $cacheRoot 'mods'
    $saves = Join-Path $cacheRoot ('Saves\' + $GameMode)
    $targetSave = Join-Path $saves $World
    $logs = Join-Path $cacheRoot 'Lua\LivingFellowsHarness'
    New-Item -ItemType Directory -Path $mods,$saves,$logs -Force | Out-Null
    Copy-Item -LiteralPath $InputSave -Destination $targetSave -Recurse
    foreach ($name in @('options.ini', 'options2.bin', 'debuglog.ini', 'keysB42.ini', 'version.txt', 'InputBindings')) {
        $source = Join-Path $InputCache $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $cacheRoot -Recurse }
    }
    $modOptions = Join-Path $InputCache 'Lua\ModOptions.ini'
    if (Test-Path -LiteralPath $modOptions -PathType Leaf) {
        Copy-Item -LiteralPath $modOptions -Destination (Join-Path $cacheRoot 'Lua')
    }
    Copy-Item -LiteralPath (Join-Path $inputMods 'reset-mods-42_00.txt') -Destination $mods
    foreach ($directory in (Get-ChildItem -LiteralPath $inputMods -Directory)) {
        if ($directory.Name -in @('LivingFellows', 'SurvivorCompanion', 'SCRealSandboxHarness')) { continue }
        if ($ModFolders.Count -gt 0 -and $directory.Name -notin $ModFolders) { continue }
        Copy-Item -LiteralPath $directory.FullName -Destination (Join-Path $mods $directory.Name) -Recurse
    }
    $payload = & (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
        -ProjectRoot $ProjectRoot -OutputRoot $mods
    $media = Join-Path $payload '42\media'
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $mods 'default.txt'), $defaultProfile, $utf8)
    [IO.File]::WriteAllText((Join-Path $targetSave 'mods.txt'), $saveProfile, $utf8)
    [IO.File]::WriteAllText((Join-Path $cacheRoot 'latestSave.ini'), "$World`n$GameMode`n", $utf8)
    if (-not $UseProbeAutoload) {
        # Only the disposable payload has this hook. It loads the save named in latestSave.ini.
        $autoload = @"
local function loadNativeProbeFixture()
    Events.OnMainMenuEnter.Remove(loadNativeProbeFixture)
    require "OptionScreens/MainScreen"
    MainScreen.continueLatestSave("$GameMode", "$World")
end
Events.OnMainMenuEnter.Add(loadNativeProbeFixture)
"@
        [IO.File]::WriteAllText((Join-Path $media 'lua\client\ZZNativeProbeAutoload.lua'), $autoload, $utf8)
    }
    return [pscustomobject]@{
        runRoot = $RunRoot
        cacheRoot = $cacheRoot
        targetSave = $targetSave
        media = $media
        sourceBridge = Join-Path $media 'java\LivingFellowsBridge.jar'
        loadingAgent = $LoadingAgent
    }
}

function New-HistoricalNativeProbeFixture {
    param(
        [string]$ProjectRoot, [string]$HistoricalRunRoot, [string]$ProbeName,
        [string]$InputSave = '', [switch]$UseSeedSave, [string[]]$Preserve = @()
    )

    $HistoricalRunRoot = Get-NativeProbeHistoricalRoot $ProjectRoot $HistoricalRunRoot
    $historyManifest = Join-Path $HistoricalRunRoot 'run-manifest.json'
    $history = Get-Content -LiteralPath $historyManifest -Raw -Encoding utf8 | ConvertFrom-Json
    $inputCache = Join-Path $HistoricalRunRoot 'cache'
    if (-not $InputSave) {
        $InputSave = if ($UseSeedSave) { $history.seedSave }
        else { Join-Path $inputCache ('Saves\' + $history.gameMode + '\' + $history.runId) }
    }
    if (-not $InputSave) { throw "Historical run manifest has no seedSave: $historyManifest" }
    $agent = Get-NativeProbeLoadingAgent $HistoricalRunRoot
    Remove-StaleNativeProbeRuns $ProjectRoot $ProbeName (@($InputSave) + $Preserve)
    $name = $ProbeName + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $ProjectRoot ('build\native-probes\' + $name)
    return New-NativeProbeFixture -ProjectRoot $ProjectRoot -RunRoot $runRoot -InputCache $inputCache `
        -InputSave $InputSave -GameMode $history.gameMode -World $history.runId -LoadingAgent $agent
}

function Get-NativeProbeLauncher([string]$GameRoot, [string]$SourceBridge) {
    $config = Join-Path $GameRoot 'ProjectZomboid64.json'
    $launcher = Get-Content -LiteralPath $config -Raw -Encoding utf8 | ConvertFrom-Json
    $oldBridgeNames = @('LivingFellowsBridge.jar', 'SurvivorCompanionBridge.jar')
    $launcher.classpath = @($launcher.classpath | Where-Object {
        [IO.Path]::GetFileName($_.Trim('"')) -notin $oldBridgeNames
    }) + @($SourceBridge)
    # Match Install-NativeBridge.ps1: a launcher tool may quote the whole argument.
    $launcher.vmArgs = @($launcher.vmArgs | Where-Object {
        $_.Trim('"') -notmatch '^-javaagent:(.+?)(?:=.*)?$' -or
        [IO.Path]::GetFileName($Matches[1].Trim('"').Replace('/', '\')) -notin $oldBridgeNames
    })
    return $launcher
}
