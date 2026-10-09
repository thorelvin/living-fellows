# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path $ProjectRoot ('build\garage-rescue-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & 'C:\Program Files\Java\jdk-17\bin\javac.exe' -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Garage rescue runner compilation failed.' }
    $Files = @(
        (Join-Path $PSScriptRoot 'oddball_garage_rescue_fixture.lua'),
        (Join-Path $Client 'SCOddballGarageRescue.lua'),
        (Join-Path $PSScriptRoot 'oddball_garage_rescue_harness.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') `
            -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" `
            KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Garage rescue harness failed.' }
    }
    finally { Pop-Location }
}
finally {
    $Target = [System.IO.Path]::GetFullPath($BuildRoot)
    $Expected = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build'))
    if (-not $Target.StartsWith($Expected + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe test cleanup: $Target"
    }
    Remove-Item -LiteralPath $Target -Recurse -Force
}
