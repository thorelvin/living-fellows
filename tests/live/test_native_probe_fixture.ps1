# SPDX-License-Identifier: MIT
<#
Checks the shared native probe fixture helpers in artifacts\NativeProbeFixture.ps1
without starting the game: history-root resolution, the launcher filter, the
controls resume receipt, stale-run cleanup and the missing-seed message. Every
file it writes lives in its own temporary directory.
#>

param(
    [string]$Helper = (Join-Path $PSScriptRoot '..\..\artifacts\NativeProbeFixture.ps1')
)

$ErrorActionPreference = 'Stop'
. $Helper

$checks = 0
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Probe([bool]$Condition, [string]$Description) {
    $script:checks++
    if (-not $Condition) { $failures.Add($Description) }
}
function Get-ProbeFailure([scriptblock]$Action) {
    try { & $Action | Out-Null; return '' } catch { return $_.Exception.Message }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('sc-native-probe-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$junction = ''
$processDirectory = [Environment]::CurrentDirectory
try {
    # A relative history root follows the PowerShell location, not the process directory.
    [Environment]::CurrentDirectory = [Environment]::GetFolderPath('System')
    Push-Location -LiteralPath $root
    try { $resolved = Get-NativeProbeHistoricalRoot 'C:\unused-project' 'runs\SC-Harness-X' }
    finally { Pop-Location }
    Assert-Probe ($resolved -eq (Join-Path $root 'runs\SC-Harness-X')) `
        "A relative history root must resolve against the PowerShell location: $resolved"

    # The launcher drops every installed bridge, including a wholly quoted agent.
    $game = Join-Path $root 'game'
    New-Item -ItemType Directory -Path $game | Out-Null
    @{
        mainClass = 'zombie/gameStates/MainScreenState'
        classpath = @('projectzomboid.jar', '"LivingFellowsBridge.jar"', 'C:/old/SurvivorCompanionBridge.jar')
        vmArgs = @('"-javaagent:LivingFellowsBridge.jar"', '-javaagent:C:/old/SurvivorCompanionBridge.jar=x',
            '-javaagent:pzoptimizer.jar', '-Xmx3072m')
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Encoding utf8
    $source = Join-Path $root 'source\LivingFellowsBridge.jar'
    $launcher = Get-NativeProbeLauncher $game $source
    Assert-Probe ((@($launcher.vmArgs) -join '|') -ceq '-javaagent:pzoptimizer.jar|-Xmx3072m') `
        "The launcher must drop quoted and legacy bridge agents only: $(@($launcher.vmArgs) -join ' ')"
    Assert-Probe ((@($launcher.classpath) -join '|') -ceq "projectzomboid.jar|$source") `
        "The launcher must replace every installed bridge with the source bridge: $(@($launcher.classpath) -join ' ')"

    # Resuming scenarios continue only a savesetup lineage from the same history.
    $history = Join-Path $root 'history'
    $receipt = Join-Path $root 'receipt\last-fixture.json'
    $save = Join-Path $root 'save'
    New-Item -ItemType Directory -Path $history, $save | Out-Null
    Assert-Probe ((Get-ProbeFailure { Get-NativeProbeResumeSave $receipt $history }) -match 'Run savesetup first') `
        'A resuming scenario without a receipt must refuse to fall back to another save.'
    Write-NativeProbeResumeReceipt $receipt $history $save 'savesetup'
    Assert-Probe ((Get-ProbeFailure { Get-NativeProbeResumeSave $receipt $history }) -match "save is missing") `
        'A receipt whose save has no world data must be refused.'
    Set-Content -LiteralPath (Join-Path $save 'global_mod_data.bin') -Value 'fixture' -Encoding ascii
    Assert-Probe ((Get-NativeProbeResumeSave $receipt $history) -eq $save) `
        'A savesetup receipt for the same history must resume its save.'
    Assert-Probe ((Get-NativeProbeReceiptTarget $receipt) -eq $save) 'The receipt target must be readable for cleanup.'
    Assert-Probe ((Get-ProbeFailure { Get-NativeProbeResumeSave $receipt (Join-Path $root 'other') }) -match 'another historical run') `
        'A receipt from another historical run must be refused.'
    @{ history = $history; targetSave = $save } | ConvertTo-Json |
        Set-Content -LiteralPath $receipt -Encoding utf8
    Assert-Probe ((Get-ProbeFailure { Get-NativeProbeResumeSave $receipt $history }) -match 'not written by a savesetup lineage') `
        'A receipt without a savesetup origin, such as one from 0.27.105, must be refused.'

    # A resuming scenario never takes -SeedSave; it would silently be ignored.
    $runner = Join-Path $PSScriptRoot '..\..\artifacts\emma\run-terminal-controls-native.ps1'
    $seedFailure = Get-ProbeFailure {
        & $runner -Scenario saveverify -HistoricalRunRoot $history -SeedSave $save
    }
    Assert-Probe ($seedFailure -match 'continues the savesetup save') `
        "A resuming controls scenario must reject -SeedSave: $seedFailure"

    # A history manifest without seedSave reports the manifest, not one probe.
    @{ gameMode = 'Sandbox'; runId = 'Fixture' } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $history 'run-manifest.json') -Encoding utf8
    $seedMessage = Get-ProbeFailure {
        New-HistoricalNativeProbeFixture -ProjectRoot $root -HistoricalRunRoot $history -ProbeName 'bed-sleep' -UseSeedSave
    }
    Assert-Probe ($seedMessage -match '^Historical run manifest has no seedSave: ') `
        "A missing seedSave must name the history manifest: $seedMessage"

    # Cleanup keeps the newest runs, a preserved save and a run holding a junction.
    $probes = Join-Path $root 'build\native-probes'
    $names = @('terminal-controls-save-00000001', 'terminal-controls-save-00000002',
        'terminal-controls-save-00000003', 'terminal-controls-save-00000004',
        'terminal-controls-save-00000005', 'terminal-controls-savesetup-00000006', 'bed-sleep-00000007')
    $created = [DateTime]::UtcNow.AddHours(-1)
    foreach ($name in $names) {
        $directory = New-Item -ItemType Directory -Path (Join-Path $probes $name)
        $created = $created.AddMinutes(1)
        $directory.CreationTimeUtc = $created
    }
    $preserved = Join-Path $probes 'terminal-controls-save-00000002\cache\Saves\Sandbox\World'
    New-Item -ItemType Directory -Path $preserved | Out-Null
    $outside = Join-Path $root 'outside-target'
    New-Item -ItemType Directory -Path $outside | Out-Null
    Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'outside' -Encoding ascii
    $junction = Join-Path $probes 'terminal-controls-save-00000001\linked'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Remove-StaleNativeProbeRuns $root 'terminal-controls-save' @($preserved) -Keep 2 3>$null
    $left = @(Get-ChildItem -LiteralPath $probes -Directory | ForEach-Object Name | Sort-Object)
    $expected = @('bed-sleep-00000007', 'terminal-controls-save-00000001', 'terminal-controls-save-00000002',
        'terminal-controls-save-00000004', 'terminal-controls-save-00000005',
        'terminal-controls-savesetup-00000006') | Sort-Object
    Assert-Probe (($left -join '|') -ceq ($expected -join '|')) `
        "Cleanup must keep the two newest, the preserved and the junction run, and other probes: $($left -join ', ')"
    Assert-Probe (Test-Path -LiteralPath (Join-Path $outside 'keep.txt')) 'Cleanup must never delete through a junction.'
}
finally {
    [Environment]::CurrentDirectory = $processDirectory
    # Remove the junction link itself first so cleanup cannot follow it.
    if ($junction -and (Test-Path -LiteralPath $junction)) { [IO.Directory]::Delete($junction, $false) }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

if ($failures.Count -gt 0) { throw ("Native probe fixture checks failed:`n" + ($failures -join "`n")) }
Write-Output "NATIVE_PROBE_FIXTURE_PASS checks=$checks"
