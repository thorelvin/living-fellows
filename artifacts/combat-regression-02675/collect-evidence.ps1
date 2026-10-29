# SPDX-License-Identifier: MIT
# Retain bounded evidence from the disposable native runs for this investigation.
[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$runs = [ordered]@{
    'one-on-one' = 'SC-Harness-20261029-202248-9ed3176e'
    'two-person-front' = 'SC-Harness-20261029-202904-f6de29b3'
    'incoming-control' = 'SC-Harness-20261029-203650-c235b833'
    'natural-acquisition' = 'SC-Harness-20261029-203941-88215ac0'
    'reported-follow' = 'SC-Harness-20261029-205238-08aefe14'
    'tired-tools-stay' = 'SC-Harness-20261029-205700-9771d815'
    'hardened-tired-tools-stay' = 'SC-Harness-20261029-215944-363afb79'
}
$evidence = [ordered]@{
    date = '2026-10-29'
    baseCommit = '6863ee42'
    game = '42.21.0'
    npcMods = 'Living Fellows only'
    runs = [ordered]@{}
}
foreach ($entry in $runs.GetEnumerator()) {
    $root = Join-Path $ProjectRoot ('build/live-sandbox-runs/' + $entry.Value)
    $events = Get-Content -LiteralPath (Join-Path $root 'cache/Lua/SurvivorCompanionHarness/events.log')
    if (@($events | Where-Object { $_ -match '^FAIL\|' }).Count -gt 0 -or
        @($events | Where-Object { $_ -match '^PASS\|squad_combat_results_written\|' }).Count -ne 1) {
        throw ('Run is failed or incomplete: ' + $entry.Value)
    }
    $csv = Join-Path $root 'cache/Lua/SurvivorCompanionHarness/squad-combat-results.txt'
    Copy-Item -LiteralPath $csv -Destination (Join-Path $PSScriptRoot ($entry.Key + '.csv')) -Force
    $console = Get-Content -LiteralPath (Join-Path $root 'cache/console.txt')
    $filtered = @($console | Where-Object {
        $_ -match 'SC_COMBAT_OBSERVE|SurvivorCompanion/(combat|safety-hold)|SC_REAL_SANDBOX\|.*\|(squad_combat_|incoming_attack_control)'
    })
    [System.IO.File]::WriteAllLines((Join-Path $PSScriptRoot ($entry.Key + '.log')), $filtered,
        [System.Text.UTF8Encoding]::new($false))
    $manifest = Get-Content -LiteralPath (Join-Path $root 'run-manifest.json') -Raw | ConvertFrom-Json
    $payloadHashes = [ordered]@{}
    foreach ($module in @('SCCombat.lua', 'SCBaseWork.lua', 'SCDowntime.lua')) {
        $modulePath = Join-Path $root ('private-playtest-payload/SurvivorCompanion/42/media/lua/client/' + $module)
        $payloadHashes[$module] = (Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $evidence.runs[$entry.Key] = [ordered]@{
        runId = $entry.Value
        hardened = $entry.Key.StartsWith('hardened-')
        payloadSha256 = $payloadHashes
        rows = @(Import-Csv -LiteralPath $csv)
        fixture = [ordered]@{
            weapon = $manifest.squadCombatWeaponType
            weapons = $manifest.squadCombatWeaponTypes
            fatigue = $manifest.squadCombatFatigue
            multiHitOverride = $manifest.squadCombatMultiHit
            order = $manifest.squadCombatOrder
            naturalAcquisition = $manifest.squadCombatNaturalAcquisition
            passive = $manifest.squadCombatPassiveControl
        }
        laneYieldReports = @($filtered | Where-Object { $_ -match 'combat-flank.*single_lane' }).Count
        luaErrorLines = @($console | Where-Object { $_ -match 'ERROR.*Lua' })
        combatExceptionLines = @($console | Where-Object { $_ -match '(ERROR|Exception).*(SCCombat|SCZombieAttack|SCZombieTargeting)' })
        shutdownArchiveWarning = @($console | Where-Object { $_ -match 'ReadOnlyFileSystemException' }).Count -gt 0
    }
}
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'results.json'),
    ($evidence | ConvertTo-Json -Depth 12) + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'build/combat-regression-harness-check.log') -Destination $PSScriptRoot -Force
Write-Output ('Retained ' + $runs.Count + ' completed combat runs.')
