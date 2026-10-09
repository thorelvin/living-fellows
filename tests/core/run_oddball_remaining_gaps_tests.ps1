# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-remaining-gaps-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & javac.exe -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Runner compilation failed.' }
    $Files = @(
        (Join-Path $PSScriptRoot 'oddball_remaining_gaps_fixture.lua'),
        (Join-Path $Client 'SCOddballMerle.lua'),
        (Join-Path $Client 'SCOddballSleeper.lua'),
        (Join-Path $PSScriptRoot 'oddball_remaining_gaps_harness.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') `
            -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" `
            KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Remaining gaps harness failed.' }
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
