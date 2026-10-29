# SPDX-License-Identifier: MIT
param([int]$TimeoutSeconds=240,[ValidatePattern('^[a-z0-9-]+$')][string]$RunName='emma-conversation-native')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$root=Join-Path $project ('build\'+$RunName)
$cache=Join-Path $root 'cache'
$seed=Join-Path $project 'build\skill-copy\pristine\LF-Skills5-Test-2026-10-29'
if(-not (Test-Path -LiteralPath (Join-Path $seed 'players.db'))){throw 'Prepared pristine save copy is missing'}
if(Test-Path -LiteralPath $cache){throw 'Use a fresh disposable native cache; preserve previous evidence'}
New-Item -ItemType Directory -Path (Join-Path $cache 'Saves\Rising'),(Join-Path $cache 'mods') -Force | Out-Null
Copy-Item -LiteralPath $seed -Destination (Join-Path $cache 'Saves\Rising') -Recurse
foreach($mod in @('SurvivorCompanion','SurvivalControlPanel')){
 Copy-Item -LiteralPath (Join-Path 'C:\Users\thore\Zomboid\mods' $mod) -Destination (Join-Path $cache 'mods') -Recurse
}
$media=Join-Path $cache 'mods\SurvivorCompanion\42\media'
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\*') -Destination $media -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-conversation-native.lua') -Destination (Join-Path $media 'lua\client\ZZEmmaConversationAcceptance.lua')
foreach($name in @('default.txt','reset-mods-42_00.txt')){
 Copy-Item -LiteralPath (Join-Path 'C:\Users\thore\Zomboid\mods' $name) -Destination (Join-Path $cache ('mods\'+$name))
}
Copy-Item -LiteralPath 'C:\Users\thore\Zomboid\options.ini' -Destination (Join-Path $cache 'options.ini')
"LF-Skills5-Test-2026-10-29`nRising`n" | Set-Content -LiteralPath (Join-Path $cache 'latestSave.ini') -Encoding ascii
$game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$launcher=Get-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$bridge=Join-Path $media 'java\SurvivorCompanionBridge.jar'
$classpath=@($launcher.classpath | ForEach-Object {if($_ -eq 'LivingFellowsBridge.jar'){$bridge}else{$_}}) -join ';'
$agent=Join-Path $project 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8\terminal-loading-agent.jar'
$arguments=@('-XX:ActiveProcessorCount=4')+@($launcher.vmArgs)+@('-XX:+UseZGC',
 ('-XX:ErrorFile="'+(Join-Path $root 'hs_err_pid%p.log')+'"'),
 ('-javaagent:"'+$agent+'"="'+(Join-Path $root 'marker.txt')+'"'),'-cp',('"'+$classpath+'"'),
 'survivorcompanion.bridge.SCLauncher',('-cachedir="'+$cache+'"'),'-nosteam','-novoip','-nosound')
$owned=Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
 -RedirectStandardOutput (Join-Path $root 'native.stdout.log') -RedirectStandardError (Join-Path $root 'native.stderr.log')
$timer=[Diagnostics.Stopwatch]::StartNew()
$evidence=Join-Path $cache 'Lua\SurvivorCompanionHarness\emma-conversation.log'
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
