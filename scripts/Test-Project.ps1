# SPDX-License-Identifier: MIT
<#
The full project gate.

The stages used to run one after another, and two of them -- the core suite and
the source gate -- accounted for most of the wall time. They do not depend on
each other: every stage reads the payload, the pinned game JAR and the built
bridge, and writes only into its own scratch directory.

What did make them serial was build\native-bridge. Test-Source, the core suite
and both packaging scripts each wiped and rebuilt it, so running them together
would have destroyed each other's classes mid-run. It is built once here and
the stages are told to skip it.

Use -Serial to run the old way, which is the right thing to do when a parallel
run reports something confusing and the interleaving is in question.
#>

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    # Stages to run at once, and the same budget again inside the core suite for
    # its own harnesses. 0 picks a value from the machine.
    [int]$Jobs = 0,
    [switch]$Serial
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $ProjectRoot 'scripts\ScParallel.ps1')

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Math]::Min(8, [int]$env:NUMBER_OF_PROCESSORS))
}
if ($Serial) { $Jobs = 1 }

$gate = [System.Diagnostics.Stopwatch]::StartNew()

# --- Serial prologue ---------------------------------------------------------
# The pinned runtime check gates everything: no stage means anything if the
# installed game is not the build this project is compiled and tested against.
& (Join-Path $ProjectRoot 'scripts\Test-PzRuntime.ps1') -GameRoot $GameRoot

# One build for every stage that follows. Deliberately without
# -InstallIntoPayload, so the comparison below still measures the committed
# payload JAR against a JAR freshly built from source.
& (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') -ProjectRoot $ProjectRoot | Out-Null
$builtBridge = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
$payloadBridge = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
foreach ($required in @($builtBridge, $payloadBridge)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Native bridge JAR is missing: $required"
    }
}
# Test-Source asserts this too, but it has to hold before anything packages the
# payload, and in a parallel run the packaging stages start alongside it.
if ((Get-FileHash -LiteralPath $builtBridge -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $payloadBridge -Algorithm SHA256).Hash) {
    throw 'Committed native bridge JAR differs from the reproducible Java 17 build.'
}

# --- Parallel stages ---------------------------------------------------------
# Each stage owns a GUID scratch directory under the user temp folder and writes
# nowhere else, except the two packaging stages, which own separate directories
# under build\ (Workshop\Contents and build\standalone-release-stage).
$stages = @(
    (New-ScPowerShellStep -Name 'core' `
        -Script (Join-Path $ProjectRoot 'tests\core\run_core_tests.ps1') `
        -Arguments @('-GameRoot', $GameRoot, '-SkipNativeBridge',
                     '-SkipSharedSourceChecks', '-Jobs', "$Jobs") `
        -Failure 'Core suite failed.'),
    (New-ScPowerShellStep -Name 'source' `
        -Script (Join-Path $ProjectRoot 'scripts\Test-Source.ps1') `
        -Arguments @('-SkipNativeBridge') `
        -Failure 'Source gate failed.'),
    (New-ScPowerShellStep -Name 'gameplay' `
        -Script (Join-Path $ProjectRoot 'tests\gameplay\run_gameplay_tests.ps1') `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure 'Gameplay suite failed.'),
    (New-ScPowerShellStep -Name 'navigation-stability' `
        -Script (Join-Path $ProjectRoot 'tests\gameplay\run_navigation_stability_tests.ps1') `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure 'Navigation stability suite failed.'),
    (New-ScPowerShellStep -Name 'perception-topology' `
        -Script (Join-Path $ProjectRoot 'tests\gameplay\run_perception_topology_tests.ps1') `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure 'Perception topology suite failed.'),
    (New-ScPowerShellStep -Name 'ui' `
        -Script (Join-Path $ProjectRoot 'tests\ui\run_ui_tests.ps1') `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure 'UI suite failed.'),
    (New-ScPowerShellStep -Name 'live-harness-static' `
        -Script (Join-Path $ProjectRoot 'tests\live\run_live_harness_static.ps1') `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure 'Live harness static suite failed.'),
    (New-ScPowerShellStep -Name 'workshop' `
        -Script (Join-Path $ProjectRoot 'scripts\Build-Workshop.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot, '-SkipNativeBridge') `
        -Failure 'Workshop packaging failed.'),
    (New-ScPowerShellStep -Name 'standalone' `
        -Script (Join-Path $ProjectRoot 'scripts\Build-Standalone.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot, '-SkipNativeBridge') `
        -Failure 'Standalone packaging failed.')
)

Invoke-ScParallelSteps -Steps $stages -Throttle $Jobs -Label 'gate stages'

$gate.Stop()
Write-Output ("PROJECT_TEST_PASS pz-runtime=true source=true core=true gameplay=true " +
    "navigation-stability=true perception-topology=true ui=true live-harness-static=true " +
    "workshop=true standalone=true seconds={0:N0} jobs={1}" -f $gate.Elapsed.TotalSeconds, $Jobs)
