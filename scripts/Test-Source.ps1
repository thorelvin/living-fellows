# SPDX-License-Identifier: MIT

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$Java = Join-Path (Split-Path -Parent $Javac) 'java.exe'
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('living-fellows-source-tests-' + [guid]::NewGuid().ToString('N'))

$parseErrors = @()
Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$null, [ref]$errors) | Out-Null
    foreach ($error in @($errors)) {
        $parseErrors += "$($_.FullName): $($error.Message)"
    }
}
if ($parseErrors.Count -gt 0) {
    throw "PowerShell syntax failures:`n$($parseErrors -join "`n")"
}

& (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
    -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -cp (Join-Path $ProjectRoot 'build\native-bridge\classes') `
        -d $BuildRoot `
        (Join-Path $ProjectRoot 'bridge\src\test\java\survivorcompanion\bridge\SCDeferredMainThreadQueueTest.java')
    if ($LASTEXITCODE -ne 0) { throw 'Repository-stub Java control compilation failed.' }
    & $Java -cp "$BuildRoot;$(Join-Path $ProjectRoot 'build\native-bridge\classes')" `
        survivorcompanion.bridge.SCDeferredMainThreadQueueTest
    if ($LASTEXITCODE -ne 0) { throw 'Repository-stub Java control failed.' }

    foreach ($test in @(
        'tests\core\test_core_static.py',
        'tests\gameplay\test_gameplay_static.py',
        'tests\ui\test_ui_contract.py',
        'tests\live\test_live_harness_static.py',
        'tests\source\test_release_sync.py'
    )) {
        & $Python (Join-Path $ProjectRoot $test)
        if ($LASTEXITCODE -ne 0) { throw "Source test failed: $test" }
    }
    & (Join-Path $ProjectRoot 'tests\core\test_installer.ps1') -ProjectRoot $ProjectRoot
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary,
            [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe source-test cleanup: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}

Write-Output 'SOURCE_TEST_PASS powershell=true java-stubs=true static=true installer=true'
