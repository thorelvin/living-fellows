# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [ValidateRange(1,100)][int]$Days = 60,
    [switch]$Baseline,
    [switch]$LedgerOnly,
    [switch]$ScenesOnly,
    [switch]$VarietyOnly,
    [switch]$RecallOnly,
    [switch]$LegacyDocumentOnly,
    [switch]$CompareBaseline,
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_./-]*$')][string]$SourceRef
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $ProjectRoot 'tests\core'
$Gameplay = Join-Path $ProjectRoot 'tests\gameplay'
$Essential = Join-Path $ProjectRoot 'tests\essential'
$Shared = Join-Path $ProjectRoot 'LivingFellows\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'LivingFellows\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')
$RunRoot = Join-Path $ProjectRoot ('build\voice-soak\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
if ($SourceRef) {
    $SnapshotRoot=Join-Path $RunRoot 'source'
    $SnapshotZip=Join-Path $RunRoot 'source.zip'
    & git -C $ProjectRoot archive --format=zip -o $SnapshotZip $SourceRef LivingFellows/42/media/lua
    if ($LASTEXITCODE -ne 0) { throw 'Historical voice source snapshot failed.' }
    Expand-Archive -LiteralPath $SnapshotZip -DestinationPath $SnapshotRoot
    $Shared=Join-Path $SnapshotRoot 'LivingFellows\42\media\lua\shared'
    $Client=Join-Path $SnapshotRoot 'LivingFellows\42\media\lua\client'
}
$ConfigFile = Join-Path $RunRoot 'soak_config.lua'
$Strict = if ($Baseline) { 'false' } else { 'true' }
[IO.File]::WriteAllText($ConfigFile,"SC_VOICE_SOAK_DAYS=$Days`nSC_VOICE_SOAK_STRICT=$Strict`n",[Text.UTF8Encoding]::new($false))
$Harness = if ($LegacyDocumentOnly) { 'legacy_community_export_harness.lua' } elseif ($LedgerOnly) { 'shared_history_harness.lua' } elseif ($ScenesOnly) { 'scene_harness.lua' } elseif ($VarietyOnly) { 'voice_memory_harness.lua' } elseif ($RecallOnly) { 'recall_harness.lua' } else { 'voice_soak_harness.lua' }
$ProductionSources=@(Get-ScGameplayFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($LedgerOnly) {
    $ProductionSources += Join-Path $ProjectRoot 'tests\fixtures\voice-soak\community-02718.lua'
}
$Sources = @('--group voice-soak') + $ProductionSources + @($ConfigFile,
    (Join-Path $Gameplay 'voice_soak_gates.lua'),
    (Join-Path $Gameplay $Harness))
$GroupFile = Join-Path $RunRoot 'groups.txt'
[IO.File]::WriteAllLines($GroupFile,[string[]]$Sources,[Text.UTF8Encoding]::new($false))
$Javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $Javac -d $RunRoot (Join-Path $Gameplay 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Voice soak runner compilation failed.' }
$Java = Join-Path $GameRoot 'jre64\bin\java.exe'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Log = Join-Path $RunRoot 'soak.log'
Push-Location -LiteralPath $GameRoot
try {
    $PreviousPreference=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    & $Java -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -cp "$RunRoot;$Jar" KahluaTestRunner --groups $GroupFile *> $Log
    $Code=$LASTEXITCODE
} finally { $ErrorActionPreference=$PreviousPreference; Pop-Location }
$Text=Get-Content -LiteralPath $Log -Raw
$Receipt=@{ Commit=(& git -C $ProjectRoot rev-parse HEAD).Trim(); Baseline=$Baseline.IsPresent;
    SourceRef=$SourceRef; Days=$Days; ExitCode=$Code; Log=$Log; GameHoursPerRealHour=24 }
$Receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RunRoot 'summary.json') -Encoding UTF8
$Start=$Text.IndexOf('VOICE_TRANSCRIPT_BEGIN')
$End=$Text.IndexOf('VOICE_TRANSCRIPT_END')
if ($Start -ge 0 -and $End -gt $Start) {
    $Transcript=$Text.Substring($Start+22,$End-$Start-22).Trim()
    [IO.File]::WriteAllText((Join-Path $RunRoot 'sample-week.txt'),$Transcript,[Text.UTF8Encoding]::new($false))
}
if ($LegacyDocumentOnly -and $Code -eq 0) {
    $BeginMarker='LEGACY_COMMUNITY_BEGIN'
    $EndMarker='LEGACY_COMMUNITY_END'
    $Begin=$Text.IndexOf($BeginMarker)
    $Finish=$Text.IndexOf($EndMarker)
    if ($Begin -lt 0 -or $Finish -le $Begin) { throw 'Historical community export receipt missing.' }
    $Document=$Text.Substring($Begin+$BeginMarker.Length,$Finish-$Begin-$BeginMarker.Length).Trim()
    [IO.File]::WriteAllText((Join-Path $RunRoot 'community-02718.lua'),$Document,[Text.UTF8Encoding]::new($false))
}
Select-String -LiteralPath $Log -Pattern '^VOICE_SOAK_|^SHARED_HISTORY_|^SCENE_|^VARIETY_|^RECALL_' | ForEach-Object { Write-Output $_.Line }
if ($CompareBaseline -and $Code -eq 0) {
    $Expected=Get-Content -LiteralPath (Join-Path $ProjectRoot 'tests\fixtures\voice-soak\baseline.json') -Raw | ConvertFrom-Json
    $Match=[regex]::Match($Text,'(?m)^VOICE_SOAK_HASH (\d+)')
    if (-not $Match.Success -or $Match.Groups[1].Value -ne [string]$Expected.speech_hash) {
        throw 'Speech differs from the frozen pre-ledger baseline.'
    }
    Write-Output 'VOICE_SOAK_BASELINE_IDENTICAL'
}
Write-Output "VOICE_SOAK_EVIDENCE $RunRoot"
if ($Code -ne 0) { Get-Content -LiteralPath $Log -Tail 16; throw 'Voice soak failed; see recorded evidence.' }
