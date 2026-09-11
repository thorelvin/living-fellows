# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$LuaRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua'
$BuildRoot = Join-Path ([IO.Path]::GetTempPath()) ('sc-perception-tests-' + [guid]::NewGuid().ToString('N'))
$Files = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
$Files += @('SCNamespace.lua','SCCall.lua','SCStableValue.lua','SCTransaction.lua','SCNativeList.lua','SCConfig.lua') | ForEach-Object { Join-Path $LuaRoot ('shared\' + $_) }
$Files += @('SCGameplayUtil.lua','SCPerformance.lua','SCTopology.lua','SCThreatSet.lua','SCPerceptionScan.lua','SCSenses.lua') | ForEach-Object { Join-Path $LuaRoot ('client\' + $_) }
$Files += Join-Path $PSScriptRoot 'perception_topology_regression_harness.lua'
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & javac.exe -d $BuildRoot (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Perception test runner compile failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Perception/topology regression failed.' }
    } finally { Pop-Location }
} finally {
    $ResolvedBuild = [IO.Path]::GetFullPath($BuildRoot)
    $ResolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $ResolvedBuild.StartsWith($ResolvedTemp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup target.' }
    Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force
}
