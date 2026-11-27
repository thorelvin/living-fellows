# SPDX-License-Identifier: MIT
param(
    [ValidateSet('controls','power','tripwalk','tripdrive','savesetup','saveverify','knowledge','radiodevices','followersitting')]
    [string]$Scenario = 'controls',
    [string]$HistoricalRunRoot = '',
    [string]$SeedSave = ''
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot = Join-Path $project ('build\computer-controls\native\' + $Scenario)
$probeName = if ($Scenario -eq 'followersitting') { 'follower-sitting-native.lua' } elseif ($Scenario -eq 'radiodevices') { 'taxi-radio-devices-native.lua' } elseif ($Scenario -eq 'knowledge') { 'terminal-knowledge-native.lua' } elseif ($Scenario.StartsWith('save')) { 'terminal-controls-save-native.lua' } elseif ($Scenario.StartsWith('trip')) { 'terminal-controls-trip-native.lua' } elseif ($Scenario -eq 'power') { 'terminal-controls-power-native.lua' } else { 'terminal-controls-native.lua' }
$logName = if ($Scenario -eq 'followersitting') { 'follower-sitting' } elseif ($Scenario -eq 'radiodevices') { 'taxi-radio-devices' } elseif ($Scenario -eq 'knowledge') { 'terminal-knowledge' } elseif ($Scenario.StartsWith('trip') -or $Scenario.StartsWith('save')) { 'terminal-controls-' + $Scenario } elseif ($Scenario -eq 'power') { 'terminal-controls-power' } else { 'terminal-controls' }
$passText = 'PASS native ' + $logName.Replace('-',' ') + ' acceptance complete'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$HistoricalRunRoot = Get-NativeProbeHistoricalRoot $project $HistoricalRunRoot
$session = Join-Path $project 'build\computer-controls\native\last-fixture.json'
$resuming = $Scenario -in @('saveverify','knowledge','radiodevices','followersitting')
$inputSave = if ($resuming) {
    if (Test-Path -LiteralPath $session -PathType Leaf) {
        $last = Get-Content -LiteralPath $session -Raw -Encoding utf8 | ConvertFrom-Json
        if ($last.history -eq $HistoricalRunRoot) { $last.targetSave }
    }
} else { $SeedSave }
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot `
    -ProbeName "terminal-controls-$Scenario" -InputSave $inputSave -UseSeedSave:(-not $resuming)
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
if ($resuming -and -not (Test-Path -LiteralPath (Join-Path $manifest.targetSave 'global_mod_data.bin'))) {
    throw 'Run savesetup before saveverify.'
}
$cloneMedia = $manifest.media
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $probeName) -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
if ($Scenario.StartsWith('trip')) {
    $probeTarget = Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'
    $probeSource = "LF_CONTROLS_TRIP_MODE='$Scenario'`n" + (Get-Content -LiteralPath $probeTarget -Raw)
    [IO.File]::WriteAllText($probeTarget, $probeSource, [Text.UTF8Encoding]::new($false))
}
if ($Scenario.StartsWith('save')) {
    $probeTarget = Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'
    $probeSource = "LF_CONTROLS_SAVE_MODE='$Scenario'`n" + (Get-Content -LiteralPath $probeTarget -Raw)
    [IO.File]::WriteAllText($probeTarget, $probeSource, [Text.UTF8Encoding]::new($false))
}
$evidence = Join-Path $manifest.cacheRoot ('Lua\LivingFellowsHarness\' + $logName + '.log')
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker = Join-Path $captureRoot ('terminal-controls-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-XX:ErrorFile="' + (Join-Path $captureRoot 'hs_err_pid%p.log') + '"'), ('-javaagent:"' + $manifest.loadingAgent + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'livingfellows.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip')
if ($Scenario -ne 'power') { $arguments += '-nosound' }
if ($Scenario -eq 'followersitting') { $arguments = @('-XX:ActiveProcessorCount=4') + $arguments }
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
    foreach ($name in $(if ($Scenario -eq 'followersitting') { @('emma-follower-sitting-short-pause','emma-follower-sitting-finished','emma-follower-sitting-follow-resumed') } elseif ($Scenario -eq 'radiodevices') { @() } elseif ($Scenario -eq 'knowledge') { @('emma-knowledge-conversation','emma-knowledge-categories','emma-knowledge-town','emma-knowledge-outbreak','emma-knowledge-rural-files',
        'emma-knowledge-logo-Twiggys','emma-knowledge-logo-WestPointDIY','emma-knowledge-logo-WizardsKeep',
        'emma-knowledge-logo-TacoDelPancho','emma-knowledge-logo-MuldraughPolice','emma-knowledge-logo-RosewoodFire',
        'emma-knowledge-logo-MeadeCountyPolice','emma-knowledge-logo-WestPointTownHall','emma-knowledge-logo-HobbsPerkinsHardware',
        'emma-knowledge-logo-OvoFarms','emma-knowledge-logo-LennysCarRepair','emma-knowledge-logo-EkronCommunityCollege',
        'emma-knowledge-logo-AlsAutoShop','emma-knowledge-logo-StuartAndLog','emma-knowledge-logo-DarkwallowGuestHouse',
        'emma-knowledge-logo-A1Hay','emma-knowledge-logo-GunsUnlimited','emma-knowledge-logo-GoldenSunset') } elseif ($Scenario.StartsWith('trip')) { @('emma-controls-' + $Scenario) } elseif ($Scenario.StartsWith('save')) { @() } elseif ($Scenario -eq 'power') { @('emma-controls-power','emma-controls-security') } else { @('emma-controls-station','emma-controls-services') })) {
        Copy-Item -LiteralPath (Join-Path $manifest.cacheRoot ('Screenshots\' + $name)) -Destination (Join-Path $captureRoot ($name + '.png')) -Force
    }
    Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'terminal-controls-evidence.log') -Force
} finally {
    if (-not $owned.HasExited) { Stop-Process -InputObject $owned -Force }
}
$next = @{ history = $HistoricalRunRoot; targetSave = $manifest.targetSave } | ConvertTo-Json
$receipt = Join-Path $manifest.runRoot 'controls-fixture.json'
[IO.File]::WriteAllText($receipt, $next, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $receipt -Destination $session -Force
