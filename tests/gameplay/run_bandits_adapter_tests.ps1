# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BanditsRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3268487204\mods\Bandits\42.22',
    [switch]$RequireBanditsSource
)
$ErrorActionPreference = 'Stop'
# The adapter, hardening and fast-path regressions are Extended groups in the
# release gate (tests\essential). This script keeps only the contract against
# the installed third-party mod, which the gate cannot assume is present.
$taskRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Independent focused/gate invocations must not compile over a live class file.
$taskOut = Join-Path $taskRoot ('build\bandits-adapter-tests\kahlua-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskOut -Force | Out-Null
$taskJavac = & (Join-Path $taskRoot 'scripts\Resolve-TestJavac.ps1')
& $taskJavac -d $taskOut (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Bandits test runner compilation failed' }
Push-Location -LiteralPath $GameRoot
try {
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
        throw 'Official Bandits payload is required for this check'
    } else { Write-Output 'BANDITS_SOURCE_SKIP optional dependency not installed' }
} finally { Pop-Location }
