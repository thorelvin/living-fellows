# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sc-ui-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'UI Kahlua runner compilation failed.' }
    $files = @(
        (Join-Path $Client 'SCUIFormat.lua'),
        (Join-Path $TestRoot 'SCUIFormatTests.lua'),
        (Join-Path $Client 'SCUIBridge.lua'),
        (Join-Path $TestRoot 'SCUIBridgeTests.lua'),
        (Join-Path $TestRoot 'SCCompanionMapFixture.lua'),
        (Join-Path $Client 'SCCompanionMap.lua'),
        (Join-Path $TestRoot 'SCCompanionMapTests.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @files
        if ($LASTEXITCODE -ne 0) { throw 'UI Kahlua tests failed.' }
    }
    finally {
        Pop-Location
    }
    & python (Join-Path $TestRoot 'test_ui_contract.py')
    if ($LASTEXITCODE -ne 0) { throw 'UI contract tests failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe UI-test cleanup: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
