# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-oddball-sins-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    $Javac = Join-Path (Split-Path -Parent (Get-Command javap.exe).Source) 'javac.exe'
    & $Javac -d $BuildRoot `
        (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Sins test runner compilation failed.' }
    $Files = @(
        (Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared\SCNamespace.lua'),
        (Join-Path $Client 'SCOddballSins.lua'),
        (Join-Path $PSScriptRoot 'oddball_sins_harness.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') `
            -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" `
            KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Sins encounter harness failed.' }
    }
    finally { Pop-Location }
}
finally {
    $Resolved = [System.IO.Path]::GetFullPath($BuildRoot)
    $Temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $Resolved.StartsWith($Temp,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe test cleanup: $Resolved"
    }
    Remove-Item -LiteralPath $Resolved -Recurse -Force
}
