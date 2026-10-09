# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Java = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -All -ErrorAction Stop |
    Where-Object { $_.Source -notlike '*\Oracle\Java\javapath\*' } |
    Select-Object -First 1).Source
if (-not $Javac) { $Javac = (Get-Command javac.exe -ErrorAction Stop).Source }
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-strike-barrier-' + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $Java -PathType Leaf)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

$LuaFiles = @((Join-Path $ProjectRoot 'tests\core\core_fixture.lua'))
$LuaFiles += @('SCNamespace.lua', 'SCCall.lua', 'SCStableValue.lua', 'SCTransaction.lua',
    'SCNativeList.lua', 'SCConfig.lua') | ForEach-Object { Join-Path $Shared $_ }
$LuaFiles += @('SCGameplayUtil.lua', 'SCTopology.lua', 'SCCombat.lua') |
    ForEach-Object { Join-Path $Client $_ }
$LuaFiles += Join-Path $TestRoot 'strike_barrier_regression_harness.lua'

New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $TestRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Strike barrier runner compilation failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & $Java -cp "$BuildRoot;$Jar" KahluaTestRunner @LuaFiles
        if ($LASTEXITCODE -ne 0) { throw 'Strike barrier regression failed.' }
    }
    finally { Pop-Location }
}
finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    $ResolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $ResolvedBuild.StartsWith($ResolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ((Split-Path -Leaf $ResolvedBuild) -like 'sc-strike-barrier-*')) {
        throw "Refusing cleanup outside owned test directory: $ResolvedBuild"
    }
    if (Test-Path -LiteralPath $ResolvedBuild) {
        Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force
    }
}
