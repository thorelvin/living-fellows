# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$StayWithMeRoot = '',
    [switch]$RequireSource
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $ProjectRoot 'tests\core'
$Gameplay = Join-Path $ProjectRoot 'tests\gameplay'
$Essential = Join-Path $ProjectRoot 'tests\essential'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')
$logs = Join-Path $ProjectRoot ('build\test-results\stay-with-me-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
$java = Join-Path $GameRoot 'jre64\bin\java.exe'
$native = Join-Path $ProjectRoot 'build\native-bridge\classes'
$classpath = "$logs;$(Join-Path $GameRoot 'projectzomboid.jar')"
function Invoke-SwmJava([string[]]$Arguments, [string]$Label) {
    Push-Location -LiteralPath $GameRoot
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $java @Arguments > (Join-Path $logs ($Label + '.log')) 2>&1
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior; Pop-Location }
}
function Require-SwmRun([string[]]$Arguments, [string]$Label) {
    $code = Invoke-SwmJava $Arguments $Label
    if ($code -ne 0) { Get-Content (Join-Path $logs ($Label + '.log')); throw "$Label failed ($code); see $logs" }
}
function Write-SwmMutation([string]$Path, [string]$Needle, [string]$Replacement, [string]$Label) {
    $source = [IO.File]::ReadAllText($Path)
    $changed = $source.Replace($Needle, $Replacement)
    if ($changed -eq $source) { throw "$Label did not change production source" }
    $folder = Join-Path $logs $Label
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $destination = Join-Path $folder (Split-Path -Leaf $Path)
    [IO.File]::WriteAllText($destination, $changed, (New-Object Text.UTF8Encoding($false)))
    return $destination
}
function Require-SwmNegative([string[]]$Arguments, [string]$Label, [string]$Expected) {
    $code = Invoke-SwmJava $Arguments $Label
    if ($code -eq 0 -or [IO.File]::ReadAllText((Join-Path $logs ($Label + '.log'))) -notmatch $Expected) {
        throw "$Label did not fail for its expected regression; see $logs"
    }
    Write-Output "$Label EXPECTED_FAIL exit=$code"
}
& $javac -d $logs (Join-Path $Gameplay 'KahluaTestRunner.java') (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java')
if ($LASTEXITCODE -ne 0) { throw 'SWM Lua runner compilation failed' }
$gameplayFiles = @(Get-ScGameplayFiles)
$identityFiles = $gameplayFiles + (Join-Path $Gameplay 'stay_with_me_identity_harness.lua')
$nativeLua = @('SCNativeTraversalActions.lua', 'SCNativeVisualActions.lua', 'SCNativeCombatActions.lua',
    'SCNativeWorkActions.lua', 'SCNativeMovementActions.lua', 'SCNativeActions.lua') | ForEach-Object { Join-Path $Client $_ }
$combatFiles = $gameplayFiles + $nativeLua + (Join-Path $Gameplay 'stay_with_me_combat_harness.lua')
foreach ($mode in @('normal', 'debug')) {
    $arguments = @('-cp', $classpath, 'ReflectLuaCompiler')
    if ($mode -eq 'debug') { $arguments += '--debug-compile' }
    Require-SwmRun ($arguments + @((Join-Path $Client 'SCStayWithMeAdapter.lua'),
        (Join-Path $Client 'SCGameplayUtil.lua'), (Join-Path $Client 'SCFactions.lua'),
        (Join-Path $Client 'SCNativeActions.lua'))) "compile-$mode"
}
Require-SwmRun (@('-cp', $classpath, 'KahluaTestRunner') + $identityFiles) 'identity-positive'
Require-SwmRun (@('-cp', $classpath, 'KahluaTestRunner') + $combatFiles) 'combat-positive'
$mutations = @(
    @{ Label='ownership-negative'; Path=(Join-Path $Client 'SCStayWithMeAdapter.lua');
        Needle='function Adapter.owns(actor)'; Replacement="function Adapter.owns(actor)`n    if true then return false end";
        Files=$identityFiles; Expected='live animation marker protects' },
    @{ Label='classification-negative'; Path=(Join-Path $Client 'SCGameplayUtil.lua');
        Needle='return U.isStayWithMeNpc(value) or U.isALifeNpc(value)'; Replacement='return U.isALifeNpc(value)';
        Files=$identityFiles; Expected='SWM bodies are human before perception' },
    @{ Label='same-frame-negative'; Path=(Join-Path $Client 'SCZombieFacts.lua');
        Needle='if SC.GameplayUtil and SC.GameplayUtil.isExternalHuman(zombie) then return ABSENT end';
        Replacement='if false then return ABSENT end'; Files=$identityFiles; Expected='same-frame promotion' },
    @{ Label='relationship-negative'; Path=(Join-Path $Client 'SCFactions.lua');
        Needle='if U().isStayWithMeNpc(source) or U().isStayWithMeNpc(target) then'; Replacement='if false then';
        Files=$combatFiles; Expected='takes priority over stale hostile' },
    @{ Label='dispatch-negative'; Path=(Join-Path $Client 'SCNativeActions.lua');
        Needle='if SC.StayWithMeAdapter and SC.StayWithMeAdapter.owns(target) then'; Replacement='if false then';
        Files=$combatFiles; Expected='stale/direct attack_melee' }
)
foreach ($mutation in $mutations) {
    $copy = Write-SwmMutation $mutation.Path $mutation.Needle $mutation.Replacement $mutation.Label
    $files = @($mutation.Files | ForEach-Object { if ($_ -eq $mutation.Path) { $copy } else { $_ } })
    Require-SwmNegative (@('-cp', $classpath, 'KahluaTestRunner') + $files) $mutation.Label $mutation.Expected
}
& (Join-Path $PSScriptRoot 'Build-NativeBridge.ps1') -ProjectRoot $ProjectRoot | Out-Null
$fixtures = Join-Path $logs 'native-fixtures'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null
$fixtureSources = @(Get-ChildItem (Join-Path $ProjectRoot 'tests\fixtures\stay-with-me') -Filter '*.java' -Recurse | ForEach-Object FullName)
$nativeTest = Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCStayWithMeProtectionTest.java'
& $javac --release 17 -cp $native -d $fixtures @fixtureSources $nativeTest
if ($LASTEXITCODE -ne 0) { throw 'SWM native fixture compilation failed' }
$nativeClass = 'survivorcompanion.bridge.SCStayWithMeProtectionTest'
Require-SwmRun @('-cp', "$fixtures;$native", $nativeClass) 'native-positive'
foreach ($mutation in @(
    @{ Label='native-filter-negative'; File='SCNativeCompanion.java';
        Needle='return SCStayWithMeProtection.filter(super.getHitInfoList());'; Replacement='return super.getHitInfoList();';
        Expected='SWM native hits removed' },
    @{ Label='native-api-negative'; File='SCStayWithMeProtection.java';
        Needle='Object owns = adapter.rawget("owns");'; Replacement='Object owns = null;';
        Expected='unmarked API-owned client/server mirrors' }
)) {
    $path = Join-Path $ProjectRoot ('bridge\src\main\java\survivorcompanion\bridge\' + $mutation.File)
    $copy = Write-SwmMutation $path $mutation.Needle $mutation.Replacement $mutation.Label
    $classes = Join-Path (Split-Path -Parent $copy) 'classes'
    New-Item -ItemType Directory -Path $classes -Force | Out-Null
    & $javac --release 17 -cp "$fixtures;$native" -d $classes $copy
    if ($LASTEXITCODE -ne 0) { throw ($mutation.Label + ' compilation failed') }
    Require-SwmNegative @('-cp', "$classes;$fixtures;$native", $nativeClass) $mutation.Label $mutation.Expected
}
if ($StayWithMeRoot -and (Test-Path -LiteralPath (Join-Path $StayWithMeRoot 'media\lua'))) {
    $lua = Join-Path $StayWithMeRoot 'media\lua'
    $source = @('shared\BridgeData.lua', 'shared\BridgeCompanion.lua', 'client\world\BridgeRemnant.lua',
        'client\BridgeMain.lua', 'client\movement\BridgeSeatPuppet.lua', 'server\BridgeServer.lua') |
        ForEach-Object { Join-Path $lua $_ }
    $sourceFiles = $gameplayFiles + (Join-Path $Gameplay 'stay_with_me_source_fixture.lua') + $source +
        (Join-Path $Gameplay 'stay_with_me_source_harness.lua')
    Require-SwmRun (@('-cp', $classpath, 'KahluaTestRunner') + $sourceFiles) 'original-source-positive'
    $originalNegative = @($sourceFiles | ForEach-Object {
        if ($_ -eq (Join-Path $Client 'SCStayWithMeAdapter.lua')) {
            Join-Path $logs 'ownership-negative\SCStayWithMeAdapter.lua'
        } else { $_ }
    })
    Require-SwmNegative (@('-cp', $classpath, 'KahluaTestRunner') + $originalNegative) `
        'original-source-negative' 'published animation marker agrees'
    $source | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 } |
        Select-Object Path, Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'dependency-hashes.json') -Encoding UTF8
} elseif ($RequireSource) { throw 'Downloaded original Stay With Me common mod directory is required.' }
else { Write-Output 'STAY_WITH_ME_SOURCE_SKIP optional dependency not supplied' }
Write-Output "STAY_WITH_ME_SUITE_PASS logs=$logs"
