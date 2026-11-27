# SPDX-License-Identifier: MIT
param([switch]$Trip,[int]$TimeoutSeconds=600,[string]$HistoricalRunRoot='')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scenario=if($Trip){'maptrip'}else{'mapui'}
$captureRoot=Join-Path $project ('build\expedition-map\native\'+$scenario)
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot -ProbeName 'expedition-map'
if(-not (Test-Path -LiteralPath (Join-Path $manifest.targetSave 'global_mod_data.bin'))){throw 'Prepared clone is missing'}
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$cloneMedia = $manifest.media
$probe=if($Trip){'native-map-trip-probe.lua'}else{'native-map-probe.lua'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $probe) -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
$evidence=Join-Path $manifest.cacheRoot 'Lua\LivingFellowsHarness\expedition-map.log'
if(Test-Path -LiteralPath $evidence){
 Move-Item -LiteralPath $evidence -Destination ($evidence+'.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.previous')
}
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker=Join-Path $captureRoot ('map-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-marker.txt')
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
   if($result -match 'PASS native expedition map acceptance complete'){break}
  }
  if($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Native expedition acceptance timed out'}
 }
 $crashes=@(Get-ChildItem -LiteralPath $captureRoot -Filter 'hs_err_pid*.log' | Where-Object LastWriteTime -ge $launchStarted)
 if($crashes.Count -gt 0 -or ($owned.HasExited -and $owned.ExitCode -ne 0)){throw 'Native process crashed; inspect captured stdout and crash report'}
 if(-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native expedition map acceptance complete'){
  throw 'Native expedition acceptance did not complete'
 }
 Get-Content -LiteralPath $evidence
 $screens=@('expedition-map-picker','expedition-map-review')
 if(-not $Trip){$screens+= 'expedition-map-station-review'}
 foreach($name in $screens){
  Copy-Item -LiteralPath (Join-Path $manifest.cacheRoot ('Screenshots\'+$name)) -Destination (Join-Path $captureRoot ($name+'.png')) -Force
 }
 Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'evidence.txt') -Force
}finally{
 if(-not $owned.HasExited){Stop-Process -InputObject $owned -Force}
}
