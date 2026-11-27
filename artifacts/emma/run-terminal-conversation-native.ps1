# SPDX-License-Identifier: MIT
param(
 [int]$TimeoutSeconds=240,
 [ValidatePattern('^[a-z0-9-]+$')][string]$RunName='emma-conversation-native',
 [string]$HistoricalRunRoot='',
 [string]$SeedSave='',
 [string]$UserCache=(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid')
)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$root=Join-Path $project ('build\'+$RunName)
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$world='LF-Skills5-Test-2026-10-29'
if(-not $SeedSave){$SeedSave=Join-Path $project ('build\skill-copy\pristine\'+$world)}
$agent=Get-NativeProbeLoadingAgent (Get-NativeProbeHistoricalRoot $project $HistoricalRunRoot)
$fixture=New-NativeProbeFixture -ProjectRoot $project -RunRoot $root -InputCache $UserCache `
 -InputSave $SeedSave -GameMode Rising -World $world -LoadingAgent $agent -ModFolders @('SurvivalControlPanel') -UseProbeAutoload
$cache=$fixture.cacheRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-conversation-native.lua') -Destination (Join-Path $fixture.media 'lua\client\ZZEmmaConversationAcceptance.lua')
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher=Get-NativeProbeLauncher $game $fixture.sourceBridge
$classpath=$launcher.classpath -join ';'
$arguments=@('-XX:ActiveProcessorCount=4')+@($launcher.vmArgs)+@('-XX:+UseZGC',
 ('-XX:ErrorFile="'+(Join-Path $root 'hs_err_pid%p.log')+'"'),
 ('-javaagent:"'+$agent+'"="'+(Join-Path $root 'marker.txt')+'"'),'-cp',('"'+$classpath+'"'),
 'livingfellows.bridge.SCLauncher',('-cachedir="'+$cache+'"'),'-nosteam','-novoip','-nosound')
$owned=Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
 -RedirectStandardOutput (Join-Path $root 'native.stdout.log') -RedirectStandardError (Join-Path $root 'native.stderr.log')
$timer=[Diagnostics.Stopwatch]::StartNew()
$evidence=Join-Path $cache 'Lua\LivingFellowsHarness\emma-conversation.log'
try{
 while(-not $owned.WaitForExit(1000)){
  if(Test-Path -LiteralPath $evidence){
   $text=Get-Content -LiteralPath $evidence -Raw
   if($text -match '(?m)^FAIL '){throw $text}
   if($text -match 'PASS native EMMA conversation acceptance complete'){
    $text | Set-Content -LiteralPath (Join-Path $root 'evidence.txt')
    Get-ChildItem -LiteralPath (Join-Path $cache 'Screenshots') -File -Filter 'emma-conversation-*' | ForEach-Object {
     Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $root ($_.Name+'.png'))
    }
    Write-Output $text
    return
   }
  }
  if($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Native conversation acceptance timed out'}
 }
 throw ('Native process exited before acceptance: '+$owned.ExitCode)
}finally{
 if(-not $owned.HasExited){Stop-Process -InputObject $owned -Force; $owned.WaitForExit(5000) | Out-Null}
}
