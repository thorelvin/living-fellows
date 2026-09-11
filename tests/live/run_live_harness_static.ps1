# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-live-harness-static-' + [guid]::NewGuid().ToString('N'))
$Compiler = Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java'
$RegressionRunner = Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java'
$Lua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCRealSandboxHarness.lua'
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
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $Lua
        if ($LASTEXITCODE -ne 0) { throw 'Live harness Kahlua compilation failed.' }

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
    }
    finally {
        Pop-Location
    }
    & python (Join-Path $TestRoot 'test_live_harness_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Live harness static contracts failed.' }
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
