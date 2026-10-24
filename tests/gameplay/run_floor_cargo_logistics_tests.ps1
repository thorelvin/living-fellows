# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$ClientRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$SharedRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$TemporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$BuildRoot = Join-Path $TemporaryRoot ('sc-floor-cargo-logistics-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    $Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
    & $Javac -d $BuildRoot (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Floor cargo/logistics runner compilation failed.' }
    $LuaFiles = @('SCNamespace.lua', 'SCCall.lua', 'SCNativeList.lua') |
        ForEach-Object { Join-Path $SharedRoot $_ }
    $LuaFiles += Join-Path $PSScriptRoot 'base_work_fixture.lua'
    $LuaFiles += @('SCWorkTransport.lua', 'SCLogistics.lua', 'SCFloorSort.lua', 'SCBaseWork.lua') |
        ForEach-Object { Join-Path $ClientRoot $_ }
    $LuaFiles += Join-Path $PSScriptRoot 'floor_cargo_logistics_harness.lua'
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @LuaFiles
        if ($LASTEXITCODE -ne 0) { throw 'Floor cargo/logistics regressions failed.' }
        $FloorFiles = @('SCNamespace.lua', 'SCCall.lua', 'SCNativeList.lua') |
            ForEach-Object { Join-Path $SharedRoot $_ }
        $FloorFiles += Join-Path $ClientRoot 'SCGameplayUtil.lua'
        $FloorFiles += Join-Path $PSScriptRoot 'base_work_fixture.lua'
        $FloorFiles += @('SCWorkTransport.lua', 'SCFloorSort.lua', 'SCBaseWork.lua') |
            ForEach-Object { Join-Path $ClientRoot $_ }
        $FloorFiles += Join-Path $PSScriptRoot 'floor_sort_harness.lua'
        & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @FloorFiles
        if ($LASTEXITCODE -ne 0) { throw 'Existing floor sorting compatibility failed.' }
    } finally { Pop-Location }
} finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    if (-not $ResolvedBuild.StartsWith($TemporaryRoot.TrimEnd('\') + '\',
        [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ((Split-Path -Leaf $ResolvedBuild) -like 'sc-floor-cargo-logistics-*')) {
        throw "Refusing cleanup outside owned test directory: $ResolvedBuild"
    }
    if (Test-Path -LiteralPath $ResolvedBuild) { Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force }
}
