# SPDX-License-Identifier: MIT
<# Runs release-gate Lua groups by name, from the same definitions the gate uses
   (tests\essential\<Domain>.ps1), in one Kahlua JVM. Use it for a focused run of
   one harness or a family instead of the full check:

     .\scripts\Run-TestGroups.ps1 -Name oddball-gunshop
     .\scripts\Run-TestGroups.ps1 -Name '*driving*','*convoy*'
     .\scripts\Run-TestGroups.ps1 -Domain Cargo
     .\scripts\Run-TestGroups.ps1 -Name '*taxi*' -List
#>
[CmdletBinding()]
param(
    [Alias('Name')][string[]]$Pattern = @(),
    [ValidateSet('Lifecycle', 'Behaviour', 'Cargo', 'Interface')]
    [string[]]$Domain = @('Lifecycle', 'Behaviour', 'Cargo', 'Interface'),
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $ProjectRoot 'tests\core'
$Gameplay = Join-Path $ProjectRoot 'tests\gameplay'
$UI = Join-Path $ProjectRoot 'tests\ui'
$Essential = Join-Path $ProjectRoot 'tests\essential'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')

$selected = @()
foreach ($domainName in $Domain) {
    # A child scope: domain files assign their own loop variables ($name,
    # $module), which must not overwrite this script's state.
    $groups = @(& { param($__domainFile) . $__domainFile } (Join-Path $Essential "$domainName.ps1"))
    foreach ($group in $groups) {
        $matched = $Pattern.Count -eq 0
        foreach ($wildcard in $Pattern) { if ($group.Name -like $wildcard) { $matched = $true } }
        if ($matched) { $selected += [pscustomobject]@{ Domain = $domainName; Group = $group } }
    }
}
if ($selected.Count -eq 0) { throw "No gate group matches: $($Pattern -join ', ')" }
if ($List) {
    $selected | ForEach-Object {
        '{0,-10} {1}{2}' -f $_.Domain, $_.Group.Name, $(if ($_.Group.Extended) { '  (extended)' } else { '' })
    }
    return
}

$privatePayload = @($selected | Where-Object { $_.Group.Files -match '\\build\\private-playtest\\' }).Count -gt 0
if ($privatePayload) {
    & (Join-Path $PSScriptRoot 'New-PrivatePlaytestPayload.ps1') -ProjectRoot $ProjectRoot | Out-Null
}
$tools = Join-Path ([IO.Path]::GetTempPath()) ('sc-groups-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tools -Force | Out-Null
try {
    $javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
    & $javac -d $tools (Join-Path $Gameplay 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua test runner compilation failed.' }
    $lines = foreach ($row in $selected) {
        "--group $($row.Group.Name)"
        foreach ($file in $row.Group.Files) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing source for $($row.Group.Name): $file" }
            [IO.Path]::GetFullPath($file)
        }
    }
    $listFile = Join-Path $tools 'selected.groups'
    [IO.File]::WriteAllLines($listFile, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$tools;$(Join-Path $GameRoot 'projectzomboid.jar')" `
            KahluaTestRunner --groups $listFile
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { throw "Selected gate groups failed (exit $code)." }
    Write-Output "TEST_GROUPS_PASS count=$($selected.Count)"
} finally {
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($tools).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tools -Recurse -Force -ErrorAction SilentlyContinue
    }
}
