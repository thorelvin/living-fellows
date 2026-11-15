# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string[]]$Harness = @('terminal_harness', 'terminal_system_harness',
        'terminal_lore_harness', 'terminal_knowledge_harness',
        'terminal_conversation_harness', 'terminal_grid_harness', 'persona_harness'),
    [switch]$Baseline,
    [switch]$ProductionOrder
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $ProjectRoot 'tests\core'
$Gameplay = Join-Path $ProjectRoot 'tests\gameplay'
$UI = Join-Path $ProjectRoot 'tests\ui'
$Essential = Join-Path $ProjectRoot 'tests\essential'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
# Use exactly the production terminal load order exercised by Interface.
$InterfaceGroups = @(. (Join-Path $Essential 'Interface.ps1'))
$Sources = @($interfaceTerminalFiles)
if ($Sources.Count -lt 40) { throw 'Production terminal sources were not resolved.' }
if (@($Harness | Where-Object { $_ -match '^(emma_talk_|lock_talk_)' }).Count -gt 0) {
    & python (Join-Path $PSScriptRoot 'Build-EmmaTalkPolishData.py') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Conversation fixture compilation failed.' }
    $Sources += Join-Path $UI 'SCEmmaTalkPolishData.lua'
    $Sources += Join-Path $UI 'SCEmmaTalkPolishFixture.lua'
    $Floor = Join-Path $UI 'SCEmmaTalkPolishBaseline.lua'
    if (Test-Path -LiteralPath $Floor) { $Sources += $Floor }
}
$RunRoot = Join-Path $ProjectRoot ('build\emma-talk-polish\harness-' +
    (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
$Javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $Javac -d $RunRoot (Join-Path $Gameplay 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'EMMA Kahlua runner compilation failed.' }
$Java = Join-Path $GameRoot 'jre64\bin\java.exe'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Results = @()
$Commit = (& git -C $ProjectRoot rev-parse HEAD).Trim()
Push-Location -LiteralPath $GameRoot
try {
    foreach ($Name in $Harness) {
        if ($Name -notmatch '^[a-z0-9_]+$') { throw "Invalid harness name: $Name" }
        $File = Join-Path $Gameplay ($Name + '.lua')
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Missing harness: $File" }
        $Log = Join-Path $RunRoot ($Name + '.log')
        $Timer = [Diagnostics.Stopwatch]::StartNew()
        $PriorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $RunSources = $Sources
        $BaseApi = $Name -like 'terminal_*' -and -not $ProductionOrder
        if ($BaseApi) { $RunSources = @($interfaceBaseTerminalFiles) }
        try {
            & $Java -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC `
                -cp "$RunRoot;$Jar" KahluaTestRunner @RunSources $File *> $Log
            $Code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $PriorPreference }
        $Timer.Stop()
        $Results += @{ Harness = $Name; ExitCode = $Code;
            Passed = $Code -eq 0; BaseParserAPI = $BaseApi; Seconds = $Timer.Elapsed.TotalSeconds; Log = $Log }
        Write-Output ("{0}: {1}" -f $Name, $(if ($Code -eq 0) { 'PASS' } else { 'FAIL (recorded)' }))
    }
} finally { Pop-Location }
$Receipt = @{ Commit = $Commit; Baseline = $Baseline.IsPresent;
    ProductionLoadOrder = $true; Results = $Results }
$Receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $RunRoot 'summary.json') -Encoding UTF8
Write-Output "EMMA_HARNESS_EVIDENCE $RunRoot"
if (@($Results | Where-Object { -not $_.Passed }).Count -gt 0 -and -not $Baseline) {
    throw 'EMMA computer harness failures; see the recorded logs.'
}
