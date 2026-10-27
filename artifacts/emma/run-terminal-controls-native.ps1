# SPDX-License-Identifier: MIT
param([ValidateSet('controls','power','tripwalk','tripdrive','savesetup','saveverify')][string]$Scenario='controls')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot = Join-Path $project ('build\computer-controls\native\' + $Scenario)
$probeName = if ($Scenario.StartsWith('save')) { 'terminal-controls-save-native.lua' } elseif ($Scenario.StartsWith('trip')) { 'terminal-controls-trip-native.lua' } elseif ($Scenario -eq 'power') { 'terminal-controls-power-native.lua' } else { 'terminal-controls-native.lua' }
$logName = if ($Scenario.StartsWith('trip') -or $Scenario.StartsWith('save')) { 'terminal-controls-' + $Scenario } elseif ($Scenario -eq 'power') { 'terminal-controls-power' } else { 'terminal-controls' }
$passText = 'PASS native ' + $logName.Replace('-',' ') + ' acceptance complete'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$runRoot = Join-Path $project 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8'
$manifest = Get-Content -LiteralPath (Join-Path $runRoot 'run-manifest.json') -Raw | ConvertFrom-Json
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
foreach ($destination in @($manifest.cacheRoot,$manifest.sourceBridge)) {
    if (-not ([IO.Path]::GetFullPath($destination)).StartsWith($runRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Preview target is outside its disposable harness directory'
    }
}
$targetSave = [IO.Path]::GetFullPath($manifest.targetSave)
$previousSave = $targetSave + '.controls-previous-' + (Get-Date -Format 'yyyyMMddHHmmss')
foreach ($checkedPath in @($targetSave,$previousSave)) {
    if (-not $checkedPath.StartsWith($runRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Save reset would leave the disposable harness directory'
    }
}
if ($Scenario -eq 'saveverify') {
    if (-not (Test-Path -LiteralPath (Join-Path $targetSave 'global_mod_data.bin'))) { throw 'Run savesetup before saveverify.' }
} else {
    if (Test-Path -LiteralPath $targetSave) { Move-Item -LiteralPath $targetSave -Destination $previousSave }
    Copy-Item -LiteralPath $manifest.seedSave -Destination $targetSave -Recurse
}
$cloneMedia = Join-Path $manifest.cacheRoot 'mods\SurvivorCompanion\42\media'
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\*') -Destination $cloneMedia -Recurse -Force
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar') -Destination $manifest.sourceBridge -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $probeName) -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
if ($Scenario.StartsWith('trip')) {
    $probeTarget = Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'
    $probeSource = "LF_CONTROLS_TRIP_MODE='$Scenario'`n" + (Get-Content -LiteralPath $probeTarget -Raw)
    Set-Content -LiteralPath $probeTarget -Value $probeSource -Encoding utf8NoBOM
}
if ($Scenario.StartsWith('save')) {
    $probeTarget = Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'
    $probeSource = "LF_CONTROLS_SAVE_MODE='$Scenario'`n" + (Get-Content -LiteralPath $probeTarget -Raw)
    Set-Content -LiteralPath $probeTarget -Value $probeSource -Encoding utf8NoBOM
}
$evidence = Join-Path $manifest.cacheRoot ('Lua\SurvivorCompanionHarness\' + $logName + '.log')
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$classpath = @($launcher.classpath | ForEach-Object { if ($_ -eq 'LivingFellowsBridge.jar') { $manifest.sourceBridge } else { $_ } }) -join ';'
$marker = Join-Path $captureRoot ('terminal-controls-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-XX:ErrorFile="' + (Join-Path $captureRoot 'hs_err_pid%p.log') + '"'), ('-javaagent:"' + (Join-Path $runRoot 'terminal-loading-agent.jar') + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'survivorcompanion.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip')
if ($Scenario -ne 'power') { $arguments += '-nosound' }
$owned = Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $captureRoot 'terminal-controls.stdout.log') -RedirectStandardError (Join-Path $captureRoot 'terminal-controls.stderr.log')
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    while (-not $owned.WaitForExit(1000)) {
        if (Test-Path -LiteralPath $evidence) {
            $result = Get-Content -LiteralPath $evidence -Raw
            if ($result -match '(?m)^FAIL ') { throw $result }
            if ($result -match $passText) { Write-Output $result; break }
        }
        if ($timer.Elapsed.TotalSeconds -gt 480) { throw 'Native terminal controls acceptance timed out' }
    }
    if (-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch $passText) {
        throw 'Native terminal controls acceptance did not complete'
    }
    foreach ($name in $(if ($Scenario.StartsWith('trip')) { @('emma-controls-' + $Scenario) } elseif ($Scenario.StartsWith('save')) { @() } elseif ($Scenario -eq 'power') { @('emma-controls-power','emma-controls-security') } else { @('emma-controls-station','emma-controls-services') })) {
        Copy-Item -LiteralPath (Join-Path $manifest.cacheRoot ('Screenshots\' + $name)) -Destination (Join-Path $captureRoot ($name + '.png')) -Force
    }
    Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'terminal-controls-evidence.log') -Force
} finally {
    if (-not $owned.HasExited) { Stop-Process -InputObject $owned -Force }
}
