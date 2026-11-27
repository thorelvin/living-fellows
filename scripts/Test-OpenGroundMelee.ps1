# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $ProjectRoot 'tests\core'
$Shared=Join-Path $ProjectRoot 'LivingFellows\42\media\lua\shared'
$Client=Join-Path $ProjectRoot 'LivingFellows\42\media\lua\client'
$Essential=Join-Path $ProjectRoot 'tests\essential'
$Gameplay=Join-Path $ProjectRoot 'tests\gameplay'
. (Join-Path $Essential 'Gameplay.ps1')
$logs=Join-Path $ProjectRoot ('build\test-results\open-ground-melee-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $javac -d $logs (Join-Path $Gameplay 'KahluaTestRunner.java') (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java')
if ($LASTEXITCODE -ne 0) { throw 'Melee test tool compilation failed.' }
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$classpath="$logs;$(Join-Path $GameRoot 'projectzomboid.jar')"
$sources=@(Get-ScGameplayFiles)+@(
    (Join-Path $Gameplay 'open_ground_melee_harness.lua'),
    (Join-Path $Gameplay 'melee_weapon_readiness_harness.lua'),
    (Join-Path $Gameplay 'ground_finisher_execution_harness.lua'))
function Run-MeleeJava([string[]]$Arguments,[string]$Label) {
    Push-Location -LiteralPath $GameRoot
    $prior=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $java @Arguments > (Join-Path $logs ($Label+'.log')) 2>&1
        return $LASTEXITCODE
    } finally { $ErrorActionPreference=$prior;Pop-Location }
}
foreach ($mode in @('normal','debug')) {
    $argsList=@('-cp',$classpath,'ReflectLuaCompiler')
    if ($mode -eq 'debug') { $argsList+='--debug-compile' }
    $code=Run-MeleeJava ($argsList+@((Join-Path $Client 'SCCombat.lua'),(Join-Path $Client 'SCMeleeKiting.lua'),(Join-Path $Client 'SCNavigation.lua'))) "compile-$mode"
    if ($code -ne 0) { throw "Melee $mode compilation failed; see $logs" }
}
$code=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$sources) 'positive'
if ($code -ne 0) { Get-Content (Join-Path $logs 'positive.log');throw "Melee regressions failed; see $logs" }
# Restore individual pre-fix production decisions in isolated source copies.
$combatPath=Join-Path $Client 'SCCombat.lua'
$combat=[IO.File]::ReadAllText($combatPath)
$kitingPath=Join-Path $Client 'SCMeleeKiting.lua'
$kiting=[IO.File]::ReadAllText($kitingPath)
$noReentry=$kiting.Replace('now - waiting.at >= 1200','now - waiting.at >= math.huge')
if ($noReentry -eq $kiting) { throw 'Stalled-gap negative control did not change the policy.' }
$noReentryPath=Join-Path $logs 'stalled-gap-reverted.lua'
[IO.File]::WriteAllText($noReentryPath,$noReentry,[Text.UTF8Encoding]::new($false))
$noReentrySources=@($sources | ForEach-Object { if ($_ -eq $kitingPath) { $noReentryPath } else { $_ } })
$noReentryExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noReentrySources) 'stalled-gap-negative'
if ($noReentryExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'stalled-gap-negative.log')) -notmatch 'stalled 3.47-metre gap') {
    throw 'Stalled-gap negative was not rejected for the expected gameplay behavior.'
}
$noSide=$kiting.Replace('"kite", snapshot, 3)','"backstep", snapshot, 3)')
if ($noSide -eq $kiting) { throw 'Lateral-lane negative control did not change the policy.' }
$noSidePath=Join-Path $logs 'lateral-lane-reverted.lua'
[IO.File]::WriteAllText($noSidePath,$noSide,[Text.UTF8Encoding]::new($false))
$noSideSources=@($sources | ForEach-Object { if ($_ -eq $kitingPath) { $noSidePath } else { $_ } })
$noSideExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noSideSources) 'lateral-lane-negative'
if ($noSideExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'lateral-lane-negative.log')) -notmatch 'blocked rear lane turns') {
    throw 'Lateral-lane negative was not rejected for the expected gameplay behavior.'
}
$noArrival=$kiting.Replace('and (band >= 0.5 or context.secondArrival > 1.2)','and true')
if ($noArrival -eq $kiting) { throw 'Short-blade arrival negative did not change the policy.' }
$noArrivalPath=Join-Path $logs 'short-blade-arrival-reverted.lua'
[IO.File]::WriteAllText($noArrivalPath,$noArrival,[Text.UTF8Encoding]::new($false))
$noArrivalSources=@($sources | ForEach-Object { if ($_ -eq $kitingPath) { $noArrivalPath } else { $_ } })
$noArrivalExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noArrivalSources) 'short-blade-arrival-negative'
if ($noArrivalExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'short-blade-arrival-negative.log')) -notmatch 'second pursuer can arrive during native recovery') {
    throw 'Short-blade arrival negative was not rejected for the expected gameplay behavior.'
}
$noCurve=$kiting.Replace('if curveWanted then','if false then')
if ($noCurve -eq $kiting) { throw 'Curved-escape negative did not change the policy.' }
$noCurvePath=Join-Path $logs 'curved-escape-reverted.lua'
[IO.File]::WriteAllText($noCurvePath,$noCurve,[Text.UTF8Encoding]::new($false))
$noCurveSources=@($sources | ForEach-Object { if ($_ -eq $kitingPath) { $noCurvePath } else { $_ } })
$noCurveExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noCurveSources) 'curved-escape-negative'
if ($noCurveExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'curved-escape-negative.log')) -notmatch 'clustered pursuers get a fully checked diagonal escape') {
    throw 'Curved-escape negative was not rejected for the expected gameplay behavior.'
}
$noControl=$kiting.Replace('if controlOpening then','if false then')
if ($noControl -eq $kiting) { throw 'Short-blade control negative did not change the policy.' }
$noControlPath=Join-Path $logs 'short-blade-control-reverted.lua'
[IO.File]::WriteAllText($noControlPath,$noControl,[Text.UTF8Encoding]::new($false))
$noControlSources=@($sources | ForEach-Object { if ($_ -eq $kitingPath) { $noControlPath } else { $_ } })
$noControlExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noControlSources) 'short-blade-control-negative'
if ($noControlExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'short-blade-control-negative.log')) -notmatch 'control the front contact') {
    throw 'Short-blade control negative was not rejected for the expected gameplay behavior.'
}
$navigationPath=Join-Path $Client 'SCNavigation.lua'
$navigation=[IO.File]::ReadAllText($navigationPath)
$noLongProbe=$navigation.Replace('tonumber(clearanceDistance) or','')
if ($noLongProbe -eq $navigation) { throw 'Full-lane steering negative did not change the policy.' }
$noLongProbePath=Join-Path $logs 'full-lane-steering-reverted.lua'
[IO.File]::WriteAllText($noLongProbePath,$noLongProbe,[Text.UTF8Encoding]::new($false))
$noLongProbeSources=@($sources | ForEach-Object { if ($_ -eq $navigationPath) { $noLongProbePath } else { $_ } })
$noLongProbeExit=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$noLongProbeSources) 'full-lane-steering-negative'
if ($noLongProbeExit -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs 'full-lane-steering-negative.log')) -notmatch 'full-lane steering selects a three-metre sideways escape') {
    throw 'Full-lane steering negative was not rejected for the expected gameplay behavior.'
}
$reverts=@{
    support=@('player.actor and player.actor ~= actor','player.actor')
    commitment=@('or best.action.localKite == true and previous','or false and previous')
    overrun=@('if localKite then overrun = false end','if false then overrun = false end')
    scoring=@('if planned then actions = { planned } end','if false then actions = { planned } end')
    gait=@('(action.kiteRun or action.rangedService) and "jog" or "walk"','action.rangedService and "jog" or "walk"')
    categories=@('if WeaponCategory ~= nil then','if false then')
    untrained=@('if recognized then return best, bestName end','if best > 0 then return best, bestName end')
    heavy_risk=@('math.max(0, weaponCost - 1.5) * 2.5 * (1 - endurance)','math.max(0, weaponCost - 1.5) * 2.5')
    heavy_strike=@('math.max(0, readiness.weaponCost - 1.5) * 3 * (1 - readiness.endurance)','math.max(0, readiness.weaponCost - 1.5) * 3')
    floor_clearance=@('postureChecked = true','postureChecked = false')
}
foreach ($label in @('support','overrun','scoring','gait','commitment','categories','untrained','heavy_risk','heavy_strike','floor_clearance')) {
    $pair=$reverts[$label]
    $changed=$combat.Replace($pair[0],$pair[1])
    if ($changed -eq $combat) { throw "No $label negative control was applied." }
    $path=Join-Path $logs ($label+'-reverted.lua')
    [IO.File]::WriteAllText($path,$changed,[Text.UTF8Encoding]::new($false))
    $negative=@($sources | ForEach-Object { if ($_ -eq $combatPath) { $path } else { $_ } })
    $negativeCode=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$negative) "$label-negative"
    if ($negativeCode -eq 0) { throw "$label negative control unexpectedly passed." }
    $expectedFailure = if ($label -eq 'floor_clearance') { 'ground finisher execution \d+:' } elseif ($label -in @('categories','untrained','heavy_risk','heavy_strike')) { 'melee weapon readiness \d+:' } else { 'open-ground melee \d+:' }
    if ([IO.File]::ReadAllText((Join-Path $logs ($label+'-negative.log'))) -notmatch $expectedFailure) {
        throw "$label negative failed for an unrelated reason."
    }
}
Get-Content (Join-Path $logs 'positive.log') | Select-Object -First 3
Write-Output "OPEN_GROUND_MELEE_PASS normal=true debug=true reverts=16 logs=$logs"
