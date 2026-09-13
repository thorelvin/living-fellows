# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$SharedRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$ClientRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sc-nav-stability-' + [guid]::NewGuid().ToString('N'))
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Java = Join-Path $GameRoot 'jre64\bin\java.exe'
$LuaFiles = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
$LuaFiles += @('SCNamespace.lua', 'SCCall.lua', 'SCStableValue.lua', 'SCTransaction.lua',
    'SCNativeList.lua', 'SCConfig.lua') | ForEach-Object { Join-Path $SharedRoot $_ }
$LuaFiles += @('SCGameplayUtil.lua', 'SCBaseObjectRef.lua', 'SCTopology.lua', 'SCPathSearch.lua',
    'SCNavTraffic.lua', 'SCNavTraversal.lua', 'SCActionSupervisor.lua', 'SCLocomotion.lua',
    'SCPerformance.lua', 'SCWorkRoutes.lua', 'SCNavigation.lua') | ForEach-Object { Join-Path $ClientRoot $_ }
$LuaFiles += Join-Path $TestRoot 'navigation_stability_regression_harness.lua'
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & javac.exe -d $BuildRoot (Join-Path $TestRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Navigation runner compilation failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & $Java -cp "$BuildRoot;$Jar" KahluaTestRunner @LuaFiles
        if ($LASTEXITCODE -ne 0) { throw 'Navigation stability regression failed.' }
    } finally { Pop-Location }
} finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    $ResolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $ResolvedBuild.StartsWith($ResolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ((Split-Path -Leaf $ResolvedBuild) -like 'sc-nav-stability-*')) {
        throw "Refusing cleanup outside owned test directory: $ResolvedBuild"
    }
    if (Test-Path -LiteralPath $ResolvedBuild) { Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force }
}
