# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    # Accepted for callers of the former combined gate. Source validation does
    # not compile or launch Java, the game, or an installer.
    [switch]$SkipNativeBridge,
    [int]$Jobs = 0,
    [ValidateSet('All', 'Metadata', 'Content')][string]$Scope = 'All'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$parseErrors = @()
if ($Scope -ne 'Content') {
# Generated live runs can contain saves and junctions to external mods.
$scriptFiles = @(Get-ChildItem -LiteralPath $ProjectRoot -File -Filter '*.ps1')
foreach ($sourceDirectory in @('scripts', 'tests', 'tools', '.github')) {
    $sourcePath = Join-Path $ProjectRoot $sourceDirectory
    if (Test-Path -LiteralPath $sourcePath -PathType Container) {
        $scriptFiles += Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Filter '*.ps1'
    }
}
$scriptFiles | ForEach-Object {
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
}

$tests = @()
if ($Scope -ne 'Content') { $tests += 'tests\source\test_release_sync.py' }
if ($Scope -ne 'Metadata') { $tests += @(
    'tests\source\test_content_references.py',
    'tests\source\test_terminal_lock_assets.py',
    'tests\source\test_no_playtest_output.py'
) }
foreach ($test in $tests) {
    & $Python (Join-Path $ProjectRoot $test)
    if ($LASTEXITCODE -ne 0) { throw "Source test failed: $test" }
}
Write-Output "SOURCE_TEST_PASS scope=$Scope native=false game=false installer=false"
