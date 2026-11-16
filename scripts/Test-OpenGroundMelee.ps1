# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $ProjectRoot 'tests\core'
$Shared=Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client=Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
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
$sources=@(Get-ScGameplayFiles)+(Join-Path $Gameplay 'open_ground_melee_harness.lua')
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
    $code=Run-MeleeJava ($argsList+@((Join-Path $Client 'SCCombat.lua'),(Join-Path $Client 'SCMeleeKiting.lua'))) "compile-$mode"
    if ($code -ne 0) { throw "Melee $mode compilation failed; see $logs" }
}
$code=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$sources) 'positive'
if ($code -ne 0) { Get-Content (Join-Path $logs 'positive.log');throw "Melee regressions failed; see $logs" }
# Restore individual pre-fix production decisions in isolated source copies.
$combatPath=Join-Path $Client 'SCCombat.lua'
$combat=[IO.File]::ReadAllText($combatPath)
$reverts=@{
    support=@('player.actor and player.actor ~= actor','player.actor')
    commitment=@('or best.action.localKite == true and previous','or false and previous')
    overrun=@('if localKite then overrun = false end','if false then overrun = false end')
    scoring=@('if planned then actions = { planned } end','if false then actions = { planned } end')
    gait=@('(action.kiteRun or action.rangedService) and "jog" or "walk"','action.rangedService and "jog" or "walk"')
}
foreach ($label in @('support','overrun','scoring','gait','commitment')) {
    $pair=$reverts[$label]
    $changed=$combat.Replace($pair[0],$pair[1])
    if ($changed -eq $combat) { throw "No $label negative control was applied." }
    $path=Join-Path $logs ($label+'-reverted.lua')
    [IO.File]::WriteAllText($path,$changed,[Text.UTF8Encoding]::new($false))
    $negative=@($sources | ForEach-Object { if ($_ -eq $combatPath) { $path } else { $_ } })
    $negativeCode=Run-MeleeJava (@('-cp',$classpath,'KahluaTestRunner')+$negative) "$label-negative"
    if ($negativeCode -eq 0) { throw "$label negative control unexpectedly passed." }
    if ([IO.File]::ReadAllText((Join-Path $logs ($label+'-negative.log'))) -notmatch 'open-ground melee \d+:') {
        throw "$label negative failed for an unrelated reason."
    }
}
Get-Content (Join-Path $logs 'positive.log') | Select-Object -First 1
Write-Output "OPEN_GROUND_MELEE_PASS normal=true debug=true reverts=5 logs=$logs"
