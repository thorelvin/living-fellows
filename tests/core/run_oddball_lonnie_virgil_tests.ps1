# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$BundledJavac = 'C:\Program Files\Java\jdk-17\bin\javac.exe'
$Javac = if (Test-Path -LiteralPath $BundledJavac -PathType Leaf) {
    $BundledJavac
} else {
    (Get-Command javac.exe -ErrorAction Stop).Source
}
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-oddball-lonnie-virgil-' + [guid]::NewGuid().ToString('N'))

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
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner `
            (Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared\SCNamespace.lua') `
            (Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client\SCOddballLonnie.lua') `
            (Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client\SCOddballVirgil.lua') `
            (Join-Path $TestRoot 'oddball_lonnie_virgil_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Wedding and mail contracts failed.' }
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
