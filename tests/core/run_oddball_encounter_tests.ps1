# SPDX-License-Identifier: MIT
<#
The single-encounter Strange Folk harnesses, as one gate stage.

Each runner below compiles its own Kahlua runner into a GUID temp directory and
writes nowhere else, so they fan out like the core suite's harnesses. The
larger encounter suites keep stages of their own in Test-Project.ps1.

Names are listed literally rather than built from a pattern, so the source gate
can see that every harness on disk is reached from the project gate.
#>

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [int]$Jobs = 0
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $ProjectRoot 'scripts\ScParallel.ps1')

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Math]::Min(8, [int]$env:NUMBER_OF_PROCESSORS))
}

$Runners = @(
    'run_oddball_amos_tests.ps1',
    'run_oddball_ashby_tests.ps1',
    'run_oddball_auxiliary_tests.ps1',
    'run_oddball_bledsoe_tests.ps1',
    'run_oddball_camp_storyteller_tests.ps1',
    'run_oddball_corey_tests.ps1',
    'run_oddball_defense_league_tests.ps1',
    'run_oddball_dehydrated_tests.ps1',
    'run_oddball_distress_radio_tests.ps1',
    'run_oddball_dwight_tests.ps1',
    'run_oddball_ebb_tests.ps1',
    'run_oddball_elmer_tests.ps1',
    'run_oddball_final_four_tests.ps1',
    'run_oddball_garage_rescue_tests.ps1',
    'run_oddball_kris_tests.ps1',
    'run_oddball_lester_tests.ps1',
    'run_oddball_lusk_tests.ps1',
    'run_oddball_mose_tests.ps1',
    'run_oddball_prentice_tests.ps1',
    'run_oddball_pyromaniac_tests.ps1',
    'run_oddball_remaining_gaps_tests.ps1',
    'run_oddball_rivals_tests.ps1',
    'run_oddball_royce_tests.ps1',
    'run_oddball_sealed_and_voice_tests.ps1',
    'run_oddball_sins_tests.ps1',
    'run_oddball_skeeter_tests.ps1',
    'run_oddball_tupelo_tests.ps1',
    'run_oddball_velma_tests.ps1',
    'run_oddball_visitors_tests.ps1',
    'run_oddball_werewolf_tests.ps1'
)

$steps = foreach ($runner in $Runners) {
    $name = $runner -replace '^run_oddball_', '' -replace '_tests\.ps1$', ''
    New-ScPowerShellStep -Name "oddball-$name" `
        -Script (Join-Path $PSScriptRoot $runner) `
        -Arguments @('-GameRoot', $GameRoot) `
        -Failure "Strange Folk $name encounter tests failed."
}

Invoke-ScParallelSteps -Steps @($steps) -Throttle $Jobs -Label 'oddball encounter suites'
Write-Output "ODDBALL_ENCOUNTERS_PASS suites=$($Runners.Count)"
