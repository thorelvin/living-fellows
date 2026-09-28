# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$UserCache = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'),
    [string]$VerifiedSave = '',
    [string]$OutputRoot = '',
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$UserCache = [System.IO.Path]::GetFullPath($UserCache)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\radio-playtest-saves'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if ([string]::IsNullOrWhiteSpace($VerifiedSave)) {
    $VerifiedSave = Join-Path $ProjectRoot 'build\live-sandbox-runs\SC-Harness-20260927-033651-3d280e28\cache\Saves\Rising\SC-Harness-20260927-033651-3d280e28'
}
$VerifiedSave = [System.IO.Path]::GetFullPath($VerifiedSave)
foreach ($required in @('mods.txt', 'map_ver.bin', 'players.db', 'global_mod_data.bin')) {
    if (-not (Test-Path -LiteralPath (Join-Path $VerifiedSave $required) -PathType Leaf)) {
        throw "Verified radio save is missing $required`: $VerifiedSave"
    }
}
$saveMods = Get-Content -LiteralPath (Join-Path $VerifiedSave 'mods.txt') -Raw -Encoding utf8
if ($saveMods -notmatch '(?m)^\s*mod\s*=\s*SurvivorCompanion\s*,?\s*$' -or
    $saveMods -notmatch '(?m)^\s*mod\s*=\s*SCRealSandboxHarness\s*,?\s*$') {
    throw 'The source must be a verified radio harness save with both mod entries.'
}
if (-not $PrepareOnly) {
    $running = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or
        ($_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -match 'ProjectZomboid')
    })
    if ($running.Count -gt 0) { throw 'Close Project Zomboid before starting the radio playtest.' }
}

$gameExe = Join-Path $GameRoot 'ProjectZomboid64.exe'
$gameConfig = Join-Path $GameRoot 'ProjectZomboid64.json'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $gameConfig -PathType Leaf)) {
    throw "Project Zomboid client was not found under $GameRoot"
}
$launcher = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
if ($launcher.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'The native SCLauncher is not installed.'
}
$bridgeClassPath = @($launcher.classpath | Where-Object { $_ -match 'SurvivorCompanion.*Bridge.*\.jar' })
if ($bridgeClassPath.Count -ne 1) { throw 'Expected one native bridge in the launcher classpath.' }
$installedBridge = $bridgeClassPath[0].Replace('/', '\')
if (-not [System.IO.Path]::IsPathRooted($installedBridge)) {
    $installedBridge = Join-Path $GameRoot $installedBridge
}
if (-not (Test-Path -LiteralPath $installedBridge -PathType Leaf)) {
    throw "Native companion bridge is missing: $installedBridge"
}

$runId = 'LF-RadioTest-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N')).Substring(0, 8)
$runRoot = Join-Path $OutputRoot $runId
$cacheRoot = Join-Path $runRoot 'cache'
$cacheMods = Join-Path $cacheRoot 'mods'
$saveRoot = Join-Path $cacheRoot 'Saves\Rising'
$targetSave = Join-Path $saveRoot $runId
New-Item -ItemType Directory -Path $cacheMods,$saveRoot -Force | Out-Null

foreach ($name in @('options.ini', 'options2.bin', 'debuglog.ini', 'keysB42.ini', 'version.txt')) {
    $source = Join-Path $UserCache $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $cacheRoot $name)
    }
}
$bindings = Join-Path $UserCache 'InputBindings'
if (Test-Path -LiteralPath $bindings -PathType Container) {
    Copy-Item -LiteralPath $bindings -Destination (Join-Path $cacheRoot 'InputBindings') -Recurse
}
Copy-Item -LiteralPath $VerifiedSave -Destination $targetSave -Recurse

$realMods = Join-Path $UserCache 'mods'
if (-not (Test-Path -LiteralPath $realMods -PathType Container)) {
    throw "User mod directory is missing: $realMods"
}
foreach ($directory in Get-ChildItem -LiteralPath $realMods -Directory) {
    if ($directory.Name -in @('SurvivorCompanion', 'SCRealSandboxHarness')) { continue }
    New-Item -ItemType Junction -Path (Join-Path $cacheMods $directory.Name) `
        -Target $directory.FullName | Out-Null
}
$resetMarker = Join-Path $realMods 'reset-mods-42_00.txt'
if (-not (Test-Path -LiteralPath $resetMarker -PathType Leaf)) {
    throw 'Build 42 mod-reset marker is missing.'
}
Copy-Item -LiteralPath $resetMarker -Destination (Join-Path $cacheMods 'reset-mods-42_00.txt')

$payloadRoot = Join-Path $runRoot 'private-playtest-payload'
& (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
    -ProjectRoot $ProjectRoot -OutputRoot $payloadRoot | Out-Null
$sourceMod = Join-Path $payloadRoot 'SurvivorCompanion'
$sourceBridge = Join-Path $sourceMod '42\media\java\SurvivorCompanionBridge.jar'
if (-not (Test-Path -LiteralPath $sourceBridge -PathType Leaf)) {
    throw "Private payload bridge is missing: $sourceBridge"
}
$installedHash = (Get-FileHash -LiteralPath $installedBridge -Algorithm SHA256).Hash
$candidateHash = (Get-FileHash -LiteralPath $sourceBridge -Algorithm SHA256).Hash
Copy-Item -LiteralPath $sourceMod -Destination (Join-Path $cacheMods 'SurvivorCompanion') -Recurse

$playMods = [regex]::Replace($saveMods,
    '(?m)^[ \t]*mod[ \t]*=[ \t]*SCRealSandboxHarness[ \t]*,?[ \t]*\r?\n?', '')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $targetSave 'mods.txt'), $playMods, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $cacheMods 'default.txt'), $playMods, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $cacheRoot 'latestSave.ini'),
    ($runId + [Environment]::NewLine + 'Rising' + [Environment]::NewLine), $utf8NoBom)
$manifest = [ordered]@{
    schema = 1
    runId = $runId
    sourceSave = $VerifiedSave
    sourceSaveUnchanged = $true
    playableSave = $targetSave
    cacheRoot = $cacheRoot
    installedBridgeSha256 = $installedHash
    candidateBridgeSha256 = $candidateHash
    harnessRemoved = $true
    radioFrequency = 90000
    radioPreset = 'Living Fellows Team'
}
[System.IO.File]::WriteAllText((Join-Path $runRoot 'manifest.json'),
    ($manifest | ConvertTo-Json -Depth 3), $utf8NoBom)
Write-Output "Prepared five-radio playtest save: $targetSave"
Write-Output "Original Riverside save unchanged; isolated cache: $cacheRoot"
if ($PrepareOnly) { return }

# The installed bridge is older than the private build. Switch only the
# launcher classpath while this interactive client runs, then restore its exact
# original bytes even if the game exits abnormally.
$launcherBackup = Join-Path $runRoot 'ProjectZomboid64.original.json'
Copy-Item -LiteralPath $gameConfig -Destination $launcherBackup
$launcherHash = (Get-FileHash -LiteralPath $launcherBackup -Algorithm SHA256).Hash
$launcher.classpath = @($launcher.classpath | ForEach-Object {
    if ($_ -eq $bridgeClassPath[0]) { $sourceBridge.Replace('\', '/') } else { $_ }
})
try {
    [System.IO.File]::WriteAllText($gameConfig,
        ($launcher | ConvertTo-Json -Depth 10), $utf8NoBom)
    $process = Start-Process -FilePath $gameExe -WorkingDirectory $GameRoot `
        -ArgumentList ('-cachedir="' + $cacheRoot + '"') -PassThru
    Write-Output "Started interactive radio playtest pid=$($process.Id)"
    Write-Output 'Use Continue to open the isolated five-radio Riverside save.'
    $process.WaitForExit()
} finally {
    Copy-Item -LiteralPath $launcherBackup -Destination $gameConfig -Force
    $restoredHash = (Get-FileHash -LiteralPath $gameConfig -Algorithm SHA256).Hash
    if ($restoredHash -ne $launcherHash) {
        throw 'Project Zomboid launcher restore hash mismatch.'
    }
    Write-Output "Restored original Project Zomboid launcher JSON sha256=$restoredHash"
}
