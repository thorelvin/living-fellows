# SPDX-License-Identifier: MIT
param([int]$TimeoutSeconds=360,[switch]$ZeroSeatingBeds,[string]$HistoricalRunRoot='')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot=Join-Path $project 'build\bed-sleep\native'
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot -ProbeName 'bed-sleep'
if(-not (Test-Path -LiteralPath (Join-Path $manifest.targetSave 'global_mod_data.bin'))){throw 'Prepared clone is missing'}
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$cloneMedia = $manifest.media
$probeDestination=Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'
if($ZeroSeatingBeds){
 $probeSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-probe.lua') -Raw
 [IO.File]::WriteAllText($probeDestination,"SC_TEST_ZERO_SEATING_BED=true`n"+$probeSource,[Text.UTF8Encoding]::new($false))
}else{
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native-probe.lua') -Destination $probeDestination -Force
}
$evidence=Join-Path $manifest.cacheRoot 'Lua\LivingFellowsHarness\bed-sleep.log'
if(Test-Path -LiteralPath $evidence){
 Move-Item -LiteralPath $evidence -Destination ($evidence+'.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.previous')
}
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker=Join-Path $captureRoot ('bed-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-marker.txt')
$arguments=@('-XX:ActiveProcessorCount=4')+@($launcher.vmArgs)+@('-XX:+UseZGC',
 ('-XX:ErrorFile="'+(Join-Path $captureRoot 'hs_err_pid%p.log')+'"'),
 ('-javaagent:"'+$manifest.loadingAgent+'"="'+$marker+'"'),
 '-cp',('"'+$classpath+'"'),'livingfellows.bridge.SCLauncher',
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
   if($result -match 'PASS native bed sleep acceptance complete'){break}
  }
  if($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Native bed acceptance timed out'}
 }
 $crashes=@(Get-ChildItem -LiteralPath $captureRoot -Filter 'hs_err_pid*.log' | Where-Object LastWriteTime -ge $launchStarted)
 if($crashes.Count -gt 0 -or ($owned.HasExited -and $owned.ExitCode -ne 0)){throw 'Native process crashed; inspect captured evidence'}
 if(-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native bed sleep acceptance complete'){
  throw 'Native bed acceptance did not complete'
 }
 Get-Content -LiteralPath $evidence
 $captureNames=@('bed-sleep-lying','bed-sleep-awake','speech-single-line','speech-multi-line')
 if(-not $ZeroSeatingBeds){$captureNames+='bed-walking-away'}
 foreach($name in $captureNames){
  Copy-Item -LiteralPath (Join-Path $manifest.cacheRoot ('Screenshots\'+$name)) -Destination (Join-Path $captureRoot ($name+'.png')) -Force
 }
 if(-not $ZeroSeatingBeds){
  $zoomCaptures=@(Get-ChildItem -LiteralPath (Join-Path $manifest.cacheRoot 'Screenshots') -File -Filter 'speech-zoom-*' | Where-Object LastWriteTime -ge $launchStarted)
  if($zoomCaptures.Count -lt 6 -or $zoomCaptures.Count -gt 48){throw 'Zoom capture set is missing or exceeds its bounded matrix'}
  foreach($capture in $zoomCaptures){
   Copy-Item -LiteralPath $capture.FullName -Destination (Join-Path $captureRoot ($capture.Name+'.png')) -Force
  }
 }
 Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'evidence.txt') -Force
}finally{
 if(-not $owned.HasExited){Stop-Process -InputObject $owned -Force}
}
