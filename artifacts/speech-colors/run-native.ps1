# SPDX-License-Identifier: MIT
param([int]$TimeoutSeconds=420, [ValidateSet(2,6)][int]$FontSize=2, [switch]$CheckViewTransition,[string]$HistoricalRunRoot='')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot=Join-Path $project ('build\speech-colors\native-font-'+$FontSize)
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot -ProbeName 'speech-colors'
if(-not (Test-Path -LiteralPath (Join-Path $manifest.targetSave 'global_mod_data.bin'))){throw 'Prepared clone is missing'}
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$cloneMedia = $manifest.media
$probe='SC_SPEECH_TEST_VIEW='+$CheckViewTransition.IsPresent.ToString().ToLowerInvariant()+"`n"+[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'native-probe.lua'))
[IO.File]::WriteAllText((Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua'),$probe)
$evidence=Join-Path $manifest.cacheRoot 'Lua\LivingFellowsHarness\speech-colors.log'
if(Test-Path -LiteralPath $evidence){
 Move-Item -LiteralPath $evidence -Destination ($evidence+'.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.previous')
}
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker=Join-Path $captureRoot ('colours-'+(Get-Date -Format 'yyyyMMddHHmmss')+'-marker.txt')
$arguments=@('-XX:ActiveProcessorCount=4')+@($launcher.vmArgs)+@('-XX:+UseZGC',
 ('-XX:ErrorFile="'+(Join-Path $captureRoot 'hs_err_pid%p.log')+'"'),
 ('-javaagent:"'+$manifest.loadingAgent+'"="'+$marker+'"'),
 '-cp',('"'+$classpath+'"'),'livingfellows.bridge.SCLauncher',
 ('-cachedir="'+$manifest.cacheRoot+'"'),'-nosteam','-novoip','-nosound')
$optionsPath=Join-Path $manifest.cacheRoot 'options.ini'
$originalOptions=[IO.File]::ReadAllText($optionsPath)
[IO.File]::WriteAllText($optionsPath,($originalOptions -replace '(?m)^fontSize=\d+',('fontSize='+$FontSize)))
$launchStarted=Get-Date
$owned=Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
 -RedirectStandardOutput (Join-Path $captureRoot 'native.stdout.log') -RedirectStandardError (Join-Path $captureRoot 'native.stderr.log')
$timer=[Diagnostics.Stopwatch]::StartNew()
try{
 while(-not $owned.WaitForExit(1000)){
  if(Test-Path -LiteralPath $evidence){
   $result=Get-Content -LiteralPath $evidence -Raw
   if($result -match '(?m)^FAIL '){throw $result}
   if($result -match 'PASS native speech colour acceptance complete'){break}
  }
  if($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Native speech colour acceptance timed out'}
 }
 $crashes=@(Get-ChildItem -LiteralPath $captureRoot -Filter 'hs_err_pid*.log' | Where-Object LastWriteTime -ge $launchStarted)
 if($crashes.Count -gt 0 -or ($owned.HasExited -and $owned.ExitCode -ne 0)){throw 'Native process crashed; inspect captured evidence'}
 if(-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native speech colour acceptance complete'){
  throw 'Native speech colour acceptance did not complete'
 }
 Get-Content -LiteralPath $evidence
 $captures=@(Get-ChildItem -LiteralPath (Join-Path $manifest.cacheRoot 'Screenshots') -File -Filter 'colour-*' | Where-Object LastWriteTime -ge $launchStarted)
 if($captures.Count -lt 27 -or $captures.Count -gt 48){throw 'Speech capture matrix is missing or exceeds its bound'}
 foreach($capture in $captures){
  Copy-Item -LiteralPath $capture.FullName -Destination (Join-Path $captureRoot ($capture.Name+'.png')) -Force
 }
 Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'evidence.txt') -Force
}finally{
 if(-not $owned.HasExited){Stop-Process -InputObject $owned -Force}
 [IO.File]::WriteAllText($optionsPath,$originalOptions)
}
