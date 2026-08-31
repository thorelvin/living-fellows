# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $ProjectRoot 'tests\core\run_core_tests.ps1') -GameRoot $GameRoot
& (Join-Path $ProjectRoot 'tests\gameplay\run_gameplay_tests.ps1') -GameRoot $GameRoot
& (Join-Path $ProjectRoot 'tests\ui\run_ui_tests.ps1') -GameRoot $GameRoot
& (Join-Path $ProjectRoot 'tests\live\run_live_harness_static.ps1') -GameRoot $GameRoot
& (Join-Path $ProjectRoot 'scripts\Build-Workshop.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $ProjectRoot 'scripts\Build-Standalone.ps1') -ProjectRoot $ProjectRoot
Write-Output 'PROJECT_TEST_PASS core=true gameplay=true ui=true live-harness=true workshop=true standalone=true'
