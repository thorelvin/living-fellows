# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$ClientRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$SharedRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sc-gameplay-tests-" + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $Jar) -or -not (Test-Path -LiteralPath $GameJava)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

$LuaFiles = @(
    (Join-Path $SharedRoot 'SCCall.lua'),
    (Join-Path $SharedRoot 'SCStableValue.lua')
)
$LuaFiles += @(
    'SCGameplayUtil.lua',
    'SCActionSupervisor.lua',
    'SCLocomotion.lua',
    'SCPerformance.lua',
    'SCDialogue.lua',
    'SCLifeEvents.lua',
    'SCCommunity.lua',
    'SCBackground.lua',
    'SCSenses.lua',
    'SCNavigation.lua',
    'SCPositioning.lua',
    'SCCombat.lua',
    'SCMedical.lua',
    'SCEncounter.lua',
    'SCLogistics.lua',
    'SCNeeds.lua',
    'SCDowntime.lua',
    'SCPersonality.lua',
    'SCPersonalItems.lua',
    'SCRelationship.lua',
    'SCObjectives.lua',
    'SCJournal.lua',
    'SCBaseLife.lua',
    'SCFactions.lua',
    'SCTrade.lua',
    'SCFactionLife.lua',
    'SCFactionContracts.lua',
    'SCFactionWorld.lua',
    'SCFactionBehavior.lua',
    'SCZombieTargeting.lua',
    'SCInfectionCrisis.lua',
    'SCAutonomy.lua',
    'SCCommands.lua',
    'SCFactionRecruitment.lua',
    'SCDecision.lua'
    ) | ForEach-Object { Join-Path $ClientRoot $_ }
$LuaFiles += Join-Path $TestRoot 'gameplay_harness.lua'

New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $TestRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay Kahlua runner compilation failed.' }

    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @LuaFiles
        if ($LASTEXITCODE -ne 0) { throw 'Gameplay Kahlua integration harness failed.' }
    }
    finally {
        Pop-Location
    }

    & python (Join-Path $TestRoot 'test_gameplay_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Gameplay static tests failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $ResolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
        $ResolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $ResolvedBuildRoot.StartsWith($ResolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean test build outside the temporary directory: $ResolvedBuildRoot"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
