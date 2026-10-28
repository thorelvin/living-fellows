# SPDX-License-Identifier: MIT
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$shared=Join-Path $project 'SurvivorCompanion\42\media\lua\shared'
$client=Join-Path $project 'SurvivorCompanion\42\media\lua\client'
$scratch=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('sc-map-targets-'+[guid]::NewGuid().ToString('N'))))
$mapJavac=& (Join-Path $project 'scripts\Resolve-TestJavac.ps1')
$files=@(
 (Join-Path $PSScriptRoot 'expedition_map_fixture.lua'),
 (Join-Path $shared 'SCNamespace.lua'),(Join-Path $shared 'SCCall.lua'),
 (Join-Path $shared 'SCNativeList.lua'),(Join-Path $shared 'SCConfig.lua'),
 (Join-Path $PSScriptRoot 'expedition_places_fixture.lua'),
 (Join-Path $client 'SCExpeditionPlaces.lua'),(Join-Path $client 'SCExpeditionTargets.lua'),
 (Join-Path $client 'SCFishing.lua'),(Join-Path $client 'SCExpeditionMap.lua'),
 (Join-Path $PSScriptRoot 'expedition_map_targets_harness.lua')
)
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
 & $mapJavac -d $scratch (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
 if($LASTEXITCODE -ne 0){throw 'Map test runner compilation failed'}
 Push-Location -LiteralPath $GameRoot
 try {
  & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$scratch;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @files
  if($LASTEXITCODE -ne 0){throw 'Map targeting regression failed'}
  $restartFiles=@(
   (Join-Path $PSScriptRoot 'core_fixture.lua'),(Join-Path $client 'SCViewSession.lua'),
   (Join-Path $client 'SCExpeditionRoute.lua'),(Join-Path $client 'SCStairTransition.lua'),
   (Join-Path $client 'SCExpeditionCar.lua'),(Join-Path $client 'SCExpeditionTargets.lua'),
   (Join-Path $client 'SCExpeditionPrototype.lua'),(Join-Path $PSScriptRoot 'expedition_restart_harness.lua')
  )
  & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$scratch;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @restartFiles
  if($LASTEXITCODE -ne 0){throw 'Map target reload regression failed'}
  $woodFiles=@(
   (Join-Path $PSScriptRoot 'core_fixture.lua'),(Join-Path $client 'SCExpeditionRoute.lua'),
   (Join-Path $client 'SCExpeditionForests.lua'),(Join-Path $client 'SCExpeditionWood.lua'),
   (Join-Path $client 'SCExpeditionTargets.lua'),(Join-Path $client 'SCExpeditionPrototype.lua'),
   (Join-Path $PSScriptRoot 'expedition_wood_mission_harness.lua')
  )
  & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$scratch;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @woodFiles
  if($LASTEXITCODE -ne 0){throw 'Manual wood target reload regression failed'}
 } finally {Pop-Location}
} finally {
 $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $scratch.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path'}
 Remove-Item -LiteralPath $scratch -Recurse -Force
}
