# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $ProjectRoot 'tests\core'
$Gameplay=Join-Path $ProjectRoot 'tests\gameplay'
$Essential=Join-Path $ProjectRoot 'tests\essential'
$Shared=Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client=Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')
$logs=Join-Path $ProjectRoot ('build\test-results\logistics-pending-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $javac -d $logs (Join-Path $Gameplay 'KahluaTestRunner.java') (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java')
if ($LASTEXITCODE -ne 0) {throw 'Logistics test runner compilation failed'}
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$classpath="$logs;$(Join-Path $GameRoot 'projectzomboid.jar')"
$files=@(Get-ScGameplayFiles)+@((Join-Path $Client 'SCSupport.lua'))
function Run-Logistics([string[]]$Arguments,[string]$Label) {
    Push-Location -LiteralPath $GameRoot
    $prior=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $java @Arguments > (Join-Path $logs ($Label+'.log')) 2>&1
        return $LASTEXITCODE
    } finally {$ErrorActionPreference=$prior;Pop-Location}
}
foreach ($mode in @('normal','debug')) {
    $arguments=@('-cp',$classpath,'ReflectLuaCompiler')
    if ($mode -eq 'debug') {$arguments+='--debug-compile'}
    $code=Run-Logistics ($arguments+@((Join-Path $Client 'SCNavigation.lua'),
        (Join-Path $Client 'SCLogistics.lua'),(Join-Path $Client 'SCSupport.lua'))) "compile-$mode"
    if ($code -ne 0) {throw "Logistics $mode compilation failed; see $logs"}
}
$caseSources=@{}
foreach ($case in @('stalled','expiry','progress','evaluation','diagnostics','clock','churn','retry')) {
    $setup=Join-Path $logs ($case+'-setup.lua')
    [IO.File]::WriteAllText($setup,('SC_PENDING_CASE="'+$case+'"'),(New-Object Text.UTF8Encoding($false)))
    $sources=$files+@($setup,(Join-Path $Gameplay 'logistics_pending_harness.lua'))
    $caseSources[$case]=$sources
    $exit=Run-Logistics (@('-cp',$classpath,'KahluaTestRunner')+$sources) $case
    if ($exit -ne 0) {
        Get-Content (Join-Path $logs ($case+'.log')) -TotalCount 13
        throw "$case regression failed ($exit); see $logs"
    }
}
$mutations=@(
    @{Label='clock-negative';File='SCNavigation.lua';Case='clock';
        Needle='or (SC.Performance and SC.Performance.preciseNowMs)';Replacement='or nil';
        Expected='coarse wall-clock ticks cannot starve'},
    @{Label='stall-negative';File='SCNavigation.lua';Case='stalled';
        Needle='if now - (survey.progressAt or now) >= 15000 then';Replacement='if false then';
        Expected='zero-progress ordinary storage survey releases'},
    @{Label='expiry-negative';File='SCNavigation.lua';Case='expiry';
        Needle='and now >= (survey.expiresAt or 0) and not survey.winnerId';
        Replacement='and false and not survey.winnerId';Expected='expired unfinished survey terminates'},
    @{Label='evaluation-negative';File='SCNavigation.lua';Case='evaluation';
        Needle='if serial > (survey.lastProgressSerial or 0)';Replacement='if false';
        Expected='evaluation cursor progress renews'},
    @{Label='churn-negative';File='SCLogistics.lua';Case='churn';
        Needle='(ownerState.lootReturnCleanup and 15000 or 90000)';
        Replacement='(ownerState.lootReturnCleanup and 15000 or math.huge)';
        Expected='changing storage candidates cannot restart'},
    @{Label='worker-yield-negative';File='SCLogistics.lua';Case='stalled';
        Needle='moveMemory.note(actor, "deposit", state.item, U().nowMs())';
        Replacement='-- reverted storage failure cooldown';Expected='failed storage item cools down'},
    @{Label='diagnostics-negative';File='SCSupport.lua';Case='diagnostics';
        Needle='return SC.Logistics and SC.Logistics.progress';
        Replacement='return false and SC.Logistics.progress';Expected='copied Support report includes'},
    @{Label='retry-negative';File='SCLogistics.lua';Case='retry';
        Needle='if type(key) == "string" and key:match("^deposit%|") then ledger[key] = nil end';
        Replacement='if false then ledger[key] = nil end';
        Expected='manual retry clears the retained'}
)
foreach ($mutation in $mutations) {
    $path=Join-Path $Client $mutation.File
    $source=[IO.File]::ReadAllText($path)
    $changed=$source.Replace($mutation.Needle,$mutation.Replacement)
    if ($changed -eq $source) {throw ($mutation.Label+' did not change production code')}
    $copy=Join-Path $logs ($mutation.Label+'.lua')
    [IO.File]::WriteAllText($copy,$changed,(New-Object Text.UTF8Encoding($false)))
    $sources=@($caseSources[$mutation.Case] | ForEach-Object {if ($_ -eq $path) {$copy} else {$_}})
    $code=Run-Logistics (@('-cp',$classpath,'KahluaTestRunner')+$sources) $mutation.Label
    if ($code -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs ($mutation.Label+'.log'))) -notmatch $mutation.Expected) {
        throw ($mutation.Label+' did not fail for the expected regression; see '+$logs)
    }
    Write-Output ($mutation.Label+' EXPECTED_FAIL exit='+$code)
}
Write-Output "LOGISTICS_PENDING_SUITE_PASS logs=$logs"
