# SPDX-License-Identifier: MIT
param([int]$TimeoutSeconds=300)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot=Join-Path $project 'build\terminal-radio\native'
$runRoot=Join-Path $project 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8'
$manifest=Get-Content -LiteralPath (Join-Path $runRoot 'run-manifest.json') -Raw | ConvertFrom-Json
foreach($destination in @($manifest.cacheRoot,$manifest.sourceBridge,$manifest.targetSave)){
 if(-not [IO.Path]::GetFullPath($destination).StartsWith($runRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
  throw 'Native acceptance target leaves the disposable clone'
 }
}
if(-not (Test-Path -LiteralPath (Join-Path $manifest.targetSave 'global_mod_data.bin'))){throw 'Prepared clone is missing'}
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$cloneMedia=Join-Path $manifest.cacheRoot 'mods\SurvivorCompanion\42\media'
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\*') -Destination $cloneMedia -Recurse -Force
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar') -Destination $manifest.sourceBridge -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-radio-native.lua') -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
$evidence=Join-Path $manifest.cacheRoot 'Lua\SurvivorCompanionHarness\terminal-radio.log'
if(Test-Path -LiteralPath $evidence){
 Move-Item -LiteralPath $evidence -Destination ($evidence+'.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.previous')
}
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher=Get-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$classpath=@($launcher.classpath | ForEach-Object {if($_ -eq 'LivingFellowsBridge.jar'){$manifest.sourceBridge}else{$_}}) -join ';'
$marker=Join-Path $captureRoot ('radio-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-marker.txt')
$arguments=@('-XX:ActiveProcessorCount=4')+@($launcher.vmArgs)+@('-XX:+UseZGC',
 ('-XX:ErrorFile="'+(Join-Path $captureRoot 'hs_err_pid%p.log')+'"'),
 ('-javaagent:"'+(Join-Path $runRoot 'terminal-loading-agent.jar')+'"="'+$marker+'"'),
 '-cp',('"'+$classpath+'"'),'survivorcompanion.bridge.SCLauncher',
 ('-cachedir="'+$manifest.cacheRoot+'"'),'-nosteam','-novoip','-nosound')
$launchStarted=Get-Date
$owned=Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
 -RedirectStandardOutput (Join-Path $captureRoot 'native.stdout.log') -RedirectStandardError (Join-Path $captureRoot 'native.stderr.log')
$timer=[Diagnostics.Stopwatch]::StartNew()
try{
 while(-not $owned.WaitForExit(1000)){
  if(Test-Path -LiteralPath $evidence){
   $result=Get-Content -LiteralPath $evidence -Raw
   if($result -match '(?m)^FAIL '){throw $result}
   if($result -match 'PASS native terminal radio acceptance complete'){break}
  }
  if($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Native terminal radio acceptance timed out'}
 }
 $crashes=@(Get-ChildItem -LiteralPath $captureRoot -Filter 'hs_err_pid*.log' | Where-Object LastWriteTime -ge $launchStarted)
 if($crashes.Count -gt 0 -or ($owned.HasExited -and $owned.ExitCode -ne 0)){throw 'Native process crashed; inspect captured evidence'}
 if(-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native terminal radio acceptance complete'){
  throw 'Native terminal radio acceptance did not complete'
 }
 Get-Content -LiteralPath $evidence
 $captures=@(Get-ChildItem -LiteralPath (Join-Path $manifest.cacheRoot 'Screenshots') -File -Filter 'emma-radio-*' | Where-Object LastWriteTime -ge $launchStarted)
 if($captures.Count -ne 7){throw 'Radio desk screenshots are missing'}
 foreach($capture in $captures){
  Copy-Item -LiteralPath $capture.FullName -Destination (Join-Path $captureRoot ($capture.Name+'.png')) -Force
 }
 Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'evidence.txt') -Force
}finally{
 if(-not $owned.HasExited){Stop-Process -InputObject $owned -Force; $owned.WaitForExit(5000) | Out-Null}
}
