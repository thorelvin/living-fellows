# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-live-harness-static-' + [guid]::NewGuid().ToString('N'))
$Compiler = Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java'
$RegressionRunner = Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java'
$Lua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCRealSandboxHarness.lua'
$OddballProbe = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCOddballCoreyEarlProbe.lua'
$ArthurPackProbe = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCOddballArthurPackProbe.lua'
$SmokerProbe = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCOddballSmokerProbe.lua'
$MilliProbe = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCMilliLiveProbe.lua'
$DrivingLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCDrivingProbe.lua'
$SixSeatLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCSixSeatProbe.lua'
$SquadCombatLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCSquadCombatLiveProbe.lua'
$FarmCorridorLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCFarmCorridorProbe.lua'
$WaterSourceLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCWaterSourceProbe.lua'
$UpstairsHaulLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCUpstairsHaulProbe.lua'
$FloorSortLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCFloorSortProbe.lua'
$BaseAlertLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCBaseAlertProbe.lua'
$ViewCutawayLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCViewCutawayProbe.lua'
$NormalKitchenLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCNormalExpeditionKitchenProbe.lua'
$WoodExpeditionLua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCWoodExpeditionProbe.lua'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $GameJava -PathType Leaf)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot $Compiler $RegressionRunner
    if ($LASTEXITCODE -ne 0) { throw 'Live harness Lua compiler build failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $Lua $DrivingLua $SixSeatLua $SquadCombatLua $FarmCorridorLua $WaterSourceLua $UpstairsHaulLua $FloorSortLua $BaseAlertLua $ViewCutawayLua $NormalKitchenLua $WoodExpeditionLua
        if ($LASTEXITCODE -ne 0) { throw 'Live harness Kahlua compilation failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner $ViewCutawayLua (Join-Path $TestRoot 'view_cutaway_probe_regression_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'View cutaway live probe regression failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner $NormalKitchenLua (Join-Path $TestRoot 'normal_expedition_kitchen_regression_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Normal expedition kitchen probe regression failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner $WoodExpeditionLua (Join-Path $TestRoot 'wood_expedition_probe_regression_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Wood expedition live probe regression failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $OddballProbe
        if ($LASTEXITCODE -ne 0) { throw 'Oddball live probe Kahlua compilation failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $ArthurPackProbe
        if ($LASTEXITCODE -ne 0) { throw 'Arthur and Pack live probe Kahlua compilation failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $SmokerProbe
        if ($LASTEXITCODE -ne 0) { throw 'Smoker live probe Kahlua compilation failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $MilliProbe
        if ($LASTEXITCODE -ne 0) { throw 'Milli live probe Kahlua compilation failed.' }

        # Execute the live harness's landing selection in a clean Kahlua VM.
        # No game process is started and no save is read or changed.
        $doorRegressionFiles = @(
            (Join-Path $ProjectRoot 'tests\core\core_fixture.lua'),
            (Join-Path $Shared 'SCNamespace.lua'),
            (Join-Path $Shared 'SCCall.lua'),
            (Join-Path $Shared 'SCStableValue.lua'),
            (Join-Path $Shared 'SCTransaction.lua'),
            (Join-Path $Shared 'SCNativeList.lua'),
            (Join-Path $Shared 'SCConfig.lua'),
            (Join-Path $Client 'SCGameplayUtil.lua'),
            (Join-Path $Client 'SCTopology.lua'),
            $Lua,
            (Join-Path $ProjectRoot 'tests\core\live_door_regression_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @doorRegressionFiles
        if ($LASTEXITCODE -ne 0) { throw 'Live doorway landing regression harness failed.' }

        $combatFixtureFiles = @($doorRegressionFiles | Select-Object -SkipLast 1)
        $combatFixtureFiles += Join-Path $TestRoot 'live_combat_fixture_regression_harness.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @combatFixtureFiles
        if ($LASTEXITCODE -ne 0) { throw 'Live combat fixture regression harness failed.' }

        $oddballFiles = @(
            $OddballProbe,
            $MilliProbe,
            (Join-Path $TestRoot 'oddball_corey_earl_probe_regression_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @oddballFiles
        if ($LASTEXITCODE -ne 0) { throw 'Oddball live probe isolation regression failed.' }
    }
    finally {
        Pop-Location
    }
    & python (Join-Path $TestRoot 'test_live_harness_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Live harness static contracts failed.' }
    & (Join-Path $TestRoot 'test_steam_launch_static.ps1')
    if (-not $?) { throw 'Steam launch ownership checks failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean live harness build outside temp: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
