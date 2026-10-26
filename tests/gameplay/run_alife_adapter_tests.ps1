# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$ALifeRoot = 'C:\ZOMBOID\external\project-a-life-audit\steamcmd\steamapps\workshop\content\108600\3803984183\mods\ProjectALifeNPCs\42.20',
    [switch]$RequireALifeSource
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskOut = Join-Path $taskRoot ('build\alife-adapter-tests\kahlua-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskOut -Force | Out-Null
$taskJavac = & (Join-Path $taskRoot 'scripts\Resolve-TestJavac.ps1')
& $taskJavac -d $taskOut (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'A-Life test runner compilation failed' }
$taskFiles = @(
    (Join-Path $PSScriptRoot 'alife_adapter_fixture.lua'),
    (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCALifeAdapter.lua'),
    (Join-Path $PSScriptRoot 'alife_adapter_harness.lua')
)
Push-Location -LiteralPath $GameRoot
try {
    & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskFiles
    if ($LASTEXITCODE -ne 0) { throw 'A-Life adapter regression failed' }
    $taskHardeningFiles = @(
        (Join-Path $PSScriptRoot 'alife_adapter_fixture.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCALifeAdapter.lua'),
        (Join-Path $PSScriptRoot 'alife_hardening_harness.lua')
    )
    & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskHardeningFiles
    if ($LASTEXITCODE -ne 0) { throw 'A-Life hardening regression failed' }
    if (Test-Path -LiteralPath $ALifeRoot) {
        $taskLua = Join-Path $ALifeRoot 'media\lua'
        $taskSourceFiles = @(
            (Join-Path $PSScriptRoot 'alife_adapter_fixture.lua'),
            (Join-Path $PSScriptRoot 'alife_source_fixture.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Core\ALifePlayerLocator.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Decisions\ALifeReputation.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Decisions\ALifeRelations.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Decisions\ALifeTargetPolicy.lua'),
            (Join-Path $taskLua 'shared\ProjectALife\Compat\ALifeInterop.lua'),
            (Join-Path $taskLua 'shared\ProjectALife\Shells\ALifeWounds.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Combat\ALifeLineOfFire.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Senses\ALifePerception.lua'),
            (Join-Path $taskLua 'server\ProjectALife\Combat\ALifeCombatStrike.lua'),
            (Join-Path $PSScriptRoot 'alife_source_setup.lua'),
            (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCALifeAdapter.lua'),
            (Join-Path $PSScriptRoot 'alife_source_harness.lua')
        )
        & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskSourceFiles
        if ($LASTEXITCODE -ne 0) { throw 'Installed A-Life source contract failed' }
    } elseif ($RequireALifeSource) { throw 'Official A-Life source is required for this check' }
    else { Write-Output 'ALIFE_SOURCE_SKIP optional dependency not installed' }
} finally { Pop-Location }
