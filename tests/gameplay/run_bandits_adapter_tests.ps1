# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BanditsRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3268487204\mods\Bandits\42.21',
    [switch]$RequireBanditsSource
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Independent focused/gate invocations must not compile over a live class file.
$taskOut = Join-Path $taskRoot ('build\bandits-adapter-tests\kahlua-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskOut -Force | Out-Null
$taskJavac = & (Join-Path $taskRoot 'scripts\Resolve-TestJavac.ps1')
& $taskJavac -d $taskOut (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Bandits test runner compilation failed' }
$taskFiles = @(
    (Join-Path $PSScriptRoot 'bandits_adapter_fixture.lua'),
    (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCBanditsAdapter.lua'),
    (Join-Path $PSScriptRoot 'bandits_adapter_harness.lua')
)
Push-Location -LiteralPath $GameRoot
try {
    & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskFiles
    if ($LASTEXITCODE -ne 0) { throw 'Bandits adapter regression failed' }
    $taskHardeningFiles = @(
        (Join-Path $PSScriptRoot 'bandits_adapter_fixture.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCBanditsAdapter.lua'),
        (Join-Path $PSScriptRoot 'bandits_hardening_harness.lua')
    )
    & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskHardeningFiles
    if ($LASTEXITCODE -ne 0) { throw 'Bandits hardening regression failed' }
    $taskFastPathFiles = @(
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\shared\SCCall.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCGameplayUtil.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCZombieFacts.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCBanditsAdapter.lua'),
        (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCALifeAdapter.lua'),
        (Join-Path $PSScriptRoot 'external_human_fastpath_harness.lua')
    )
    & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskFastPathFiles
    if ($LASTEXITCODE -ne 0) { throw 'External human absent-mod fast path regression failed' }
    if (Test-Path -LiteralPath $BanditsRoot) {
        $taskLua = Join-Path $BanditsRoot 'media\lua'
        $taskSourceFiles = @(
            (Join-Path $PSScriptRoot 'bandits_adapter_fixture.lua'),
            (Join-Path $PSScriptRoot 'bandits_source_fixture.lua'),
            (Join-Path $taskLua 'shared\BanditUtils.lua'),
            (Join-Path $taskLua 'client\BanditPlayer.lua'),
            (Join-Path $taskLua 'shared\PlayerDamageModel.lua'),
            (Join-Path $taskLua 'server\BanditServerCommands.lua'),
            (Join-Path $taskRoot 'SurvivorCompanion\42\media\lua\client\SCBanditsAdapter.lua'),
            (Join-Path $PSScriptRoot 'bandits_source_harness.lua')
        )
        & .\jre64\bin\java.exe -cp "$taskOut;$GameRoot\projectzomboid.jar" KahluaTestRunner @taskSourceFiles
        if ($LASTEXITCODE -ne 0) { throw 'Installed Bandits source contract failed' }
    } elseif ($RequireBanditsSource) {
        throw 'Official Bandits 42.21 payload is required for this check'
    } else { Write-Output 'BANDITS_SOURCE_SKIP optional dependency not installed' }
} finally { Pop-Location }
