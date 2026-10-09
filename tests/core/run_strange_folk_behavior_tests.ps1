# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-strange-folk-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & javac.exe -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Strange Folk runner compilation failed.' }
    $Files = @(
        (Join-Path $PSScriptRoot 'strange_folk_behavior_fixture.lua'),
        (Join-Path $Client 'SCOddballRed.lua'),
        (Join-Path $Client 'SCOddballSpiffo.lua'),
        (Join-Path $Client 'SCZombieTargeting.lua'),
        (Join-Path $PSScriptRoot 'strange_folk_behavior_harness.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') `
            -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" `
            KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Strange Folk behavior harness failed.' }
    }
    finally { Pop-Location }
}
finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    $TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $ResolvedBuild.StartsWith($TempRoot,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe test cleanup: $ResolvedBuild"
    }
    Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force
}
