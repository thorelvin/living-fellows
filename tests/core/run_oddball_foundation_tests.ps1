# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$LocalJavac = 'C:\Program Files\Java\jdk-17\bin\javac.exe'
$Javac = if (Test-Path -LiteralPath $LocalJavac -PathType Leaf) {
    $LocalJavac
} else {
    (Get-Command javac.exe -ErrorAction Stop).Source
}
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-oddball-foundation-' + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $GameJava -PathType Leaf)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua runner build failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        $Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
        $Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner `
            (Join-Path $TestRoot 'core_fixture.lua') `
            (Join-Path $Shared 'SCNamespace.lua') `
            (Join-Path $Shared 'SCCall.lua') `
            (Join-Path $Shared 'SCStableValue.lua') `
            (Join-Path $Shared 'SCNativeList.lua') `
            (Join-Path $TestRoot 'faction_lifecycle_fixture.lua') `
            (Join-Path $Client 'SCFactions.lua') `
            (Join-Path $Client 'SCFactionRecruitment.lua') `
            (Join-Path $Client 'SCOddballs.lua') `
            (Join-Path $TestRoot 'oddball_foundation_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Oddball foundation regression failed.' }
    } finally {
        Pop-Location
    }
} finally {
    if (Test-Path -LiteralPath $BuildRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($BuildRoot)
        $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $full.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe test build path: $full"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
