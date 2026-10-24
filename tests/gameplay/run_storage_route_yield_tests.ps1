# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$SharedRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$ClientRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$TemporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$BuildRoot = Join-Path $TemporaryRoot ('sc-storage-route-yield-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
$Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
& $Javac -d $BuildRoot (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Storage route/yield runner compilation failed.' }
$LuaFiles = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
$LuaFiles += @('SCNamespace.lua', 'SCCall.lua', 'SCStableValue.lua', 'SCTransaction.lua',
    'SCNativeList.lua', 'SCConfig.lua') | ForEach-Object { Join-Path $SharedRoot $_ }
$LuaFiles += @('SCGameplayUtil.lua', 'SCBaseObjectRef.lua', 'SCTopology.lua', 'SCPathSearch.lua',
    'SCNavTraffic.lua', 'SCNavTraversal.lua', 'SCActionSupervisor.lua', 'SCLocomotion.lua',
    'SCPerformance.lua', 'SCWorkRoutes.lua', 'SCStairTransition.lua', 'SCNavigation.lua',
    'SCBanter.lua') | ForEach-Object { Join-Path $ClientRoot $_ }
$LuaFiles += Join-Path $PSScriptRoot 'storage_route_yield_regression_harness.lua'
Push-Location -LiteralPath $GameRoot
try {
    & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @LuaFiles
    if ($LASTEXITCODE -ne 0) { throw 'Storage route/yield regressions failed.' }
} finally { Pop-Location }
} finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    if (-not $ResolvedBuild.StartsWith($TemporaryRoot.TrimEnd('\') + '\',
        [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ((Split-Path -Leaf $ResolvedBuild) -like 'sc-storage-route-yield-*')) {
        throw "Refusing cleanup outside owned temporary test directory: $ResolvedBuild"
    }
    if (Test-Path -LiteralPath $ResolvedBuild) { Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force }
}
