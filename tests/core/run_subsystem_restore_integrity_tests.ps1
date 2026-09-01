# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Payload = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua'
$BuildRoot = Join-Path $ProjectRoot 'build\subsystem-restore-integrity-tests'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Java = Join-Path $GameRoot 'jre64\bin\java.exe'

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
& javac.exe -d $BuildRoot (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Kahlua test runner compilation failed.' }

$Files = @(
    (Join-Path $TestRoot 'core_fixture.lua'),
    (Join-Path $Payload 'shared\SCNamespace.lua'),
    (Join-Path $Payload 'shared\SCStableValue.lua'),
    (Join-Path $Payload 'shared\SCNativeList.lua'),
    (Join-Path $TestRoot 'subsystem_restore_integrity_fixture.lua'),
    (Join-Path $Payload 'client\SCBaseLife.lua'),
    (Join-Path $Payload 'client\SCInfectionCrisis.lua'),
    (Join-Path $Payload 'client\SCCommunity.lua'),
    (Join-Path $Payload 'client\SCFactions.lua'),
    (Join-Path $Payload 'client\SCFactionWorld.lua'),
    (Join-Path $TestRoot 'subsystem_restore_integrity_harness.lua')
)

Push-Location -LiteralPath $GameRoot
try {
    & $Java -cp "$BuildRoot;$Jar" KahluaTestRunner @Files
    if ($LASTEXITCODE -ne 0) { throw 'Subsystem restore-integrity harness failed.' }
}
finally {
    Pop-Location
}

