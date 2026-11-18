# SPDX-License-Identifier: MIT
# Disposable fixture only. The native PZO main class and upstream loader stay active.
[CmdletBinding()]
param(
    [ValidateSet('approved','blocked','disabled')][string]$Scenario='approved',
    [Parameter(Mandatory)][string]$PayloadProjectRoot,
    [Parameter(Mandatory)][string]$GameRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$MediaSnapshotRoot,
    [Parameter(Mandatory)][string]$PzoJar
)
$ErrorActionPreference='Stop'
$sourceGame=[IO.Path]::GetFullPath($GameRoot)
$evidence=[IO.Path]::GetFullPath($OutputRoot)
$run=Join-Path $evidence ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'-'+$Scenario)
$game=Join-Path $run 'game'
$profile=Join-Path $run 'home'
$cache=Join-Path $profile 'Zomboid'
$utf8=New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path $game,(Join-Path $cache 'Lua'),(Join-Path $cache 'mods') -Force | Out-Null
foreach($name in @('jre64','license')) {
    New-Item -ItemType Junction -Path (Join-Path $game $name) -Target (Join-Path $sourceGame $name) | Out-Null
}
$mediaSnapshot=[IO.Path]::GetFullPath($MediaSnapshotRoot)
if($mediaSnapshot.StartsWith($sourceGame.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Use an owned asset snapshot, not the installed media directory.'}
if(-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $mediaSnapshot) 'snapshot-complete.txt'))){throw 'Complete owned media snapshot is required.'}
@'
import os,sys
source,target=sys.argv[1:]
for root,dirs,files in os.walk(source):
 out=os.path.join(target,os.path.relpath(root,source));os.makedirs(out,exist_ok=True)
 for name in files:os.link(os.path.join(root,name),os.path.join(out,name))
'@ | python -B - $mediaSnapshot (Join-Path $game 'media')
if($LASTEXITCODE -ne 0){throw 'Owned asset hardlink tree failed.'}
foreach($file in Get-ChildItem -LiteralPath $sourceGame -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -in @('ProjectZomboid64.exe','projectzomboid.jar','steam_appid.txt','stdlib.lua','stdlib.lbc') }) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $game $file.Name)
}
Copy-Item -LiteralPath $PzoJar -Destination (Join-Path $game 'PZOptimEngine.jar')
$config=[ordered]@{
    mainClass='com/pzoptimizer/PZOEntrypoint'
    classpath=@('.','projectzomboid.jar','PZOptimEngine.jar')
    vmArgs=@('-Xms256m','-Xmx3072m','-XX:ActiveProcessorCount=4','-Djava.awt.headless=false','-Dzomboid.steam=0','-Dzomboid.znetlog=1','-Djava.library.path=win64/;.',('-Duser.home='+$profile),'--enable-native-access=ALL-UNNAMED','--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED','-XX:+EnableDynamicAgentLoading','-XX:-CreateCoredumpOnCrash')
}
[IO.File]::WriteAllText((Join-Path $game 'ProjectZomboid64.json'),($config|ConvertTo-Json -Depth 6),$utf8)
& (Join-Path $PayloadProjectRoot 'scripts\Install-Standalone.ps1') -ProjectRoot $PayloadProjectRoot -GameRoot $game -ModsRoot (Join-Path $cache 'mods') -InstallDataRoot (Join-Path $run 'install-data') *> (Join-Path $run 'install.log')
if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw 'Fixture installation failed.'}
$hash=(Get-FileHash -LiteralPath (Join-Path $game 'LivingFellowsBridge.jar') -Algorithm SHA256).Hash.ToLowerInvariant()
$pzo=[ordered]@{
    beta_opt_in=$false; ignored_version='2.2'; multithreading_notice_ack_version='2.1';
    java_mods_enabled=($Scenario -ne 'disabled'); require_lua_mod=$false;
    crash_window=$false; gpu_pref_written=$true; approved_java_mods=''; blocked_java_mods=''
}
if($Scenario -eq 'approved'){$pzo.approved_java_mods=$hash}
if($Scenario -eq 'blocked'){$pzo.blocked_java_mods=$hash}
[IO.File]::WriteAllText((Join-Path $cache 'Lua\pzo_config.json'),($pzo|ConvertTo-Json -Compress),$utf8)
$userCache=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'
foreach($name in @('options.ini','options2.bin','version.txt','keysB42.ini')) {
    $path=Join-Path $userCache $name
    if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination (Join-Path $cache $name)}
}
$options=Join-Path $cache 'options.ini'
$lines=if(Test-Path -LiteralPath $options){@(Get-Content -LiteralPath $options)}else{@()}
$values=[ordered]@{width=1280;height=720;fullScreen='false';borderless='false';frameRate=30;uiRenderFPS=15;uncappedFPS='false';musicVolume=0;soundVolume=0;ambientVolume=0;vehicleEngineVolume=0}
foreach($key in $values.Keys){$lines=@($lines|Where-Object{$_ -notmatch ('^'+[regex]::Escape($key)+'=')});$lines+=($key+'='+$values[$key])}
[IO.File]::WriteAllLines($options,[string[]]$lines,$utf8)
$probe=Join-Path $cache 'mods\SCPzoStartupProbe'
New-Item -ItemType Directory -Path (Join-Path $probe '42\media\lua\client') -Force|Out-Null
$info="name=PZO startup fixture`nid=SCPzoStartupProbe`nmodversion=1`n"
[IO.File]::WriteAllText((Join-Path $probe 'mod.info'),$info,$utf8)
[IO.File]::WriteAllText((Join-Path $probe '42\mod.info'),$info,$utf8)
$lua=@'
local written = false
local function evidence()
    if written then return end
    written = true
    local bridge = rawget(_G, 'SCBridge')
    local value = bridge and tostring(bridge.getProtocol()) or 'absent'
    print('SC_PZO_NORMAL_PIPELINE menu bridge=' .. value)
    local writer = getFileWriter('pzo-startup-menu.txt', true, false)
    if writer then writer:write('bridge=' .. value .. '\n'); writer:close() end
end
Events.OnMainMenuEnter.Add(evidence)
'@
[IO.File]::WriteAllText((Join-Path $probe '42\media\lua\client\SCPzoStartupProbe.lua'),$lua,$utf8)
[IO.File]::WriteAllText((Join-Path $cache 'mods\default.txt'),"VERSION = 1,`nmods {`n mod = \SurvivorCompanion,`n mod = \SCPzoStartupProbe,`n}`n",$utf8)
[IO.File]::WriteAllText((Join-Path $cache 'mods\reset-mods-42_00.txt'),'',$utf8)
$manifest=[ordered]@{run=$run;game=$game;profile=$profile;cache=$cache;scenario=$Scenario;bridgeHash=$hash;pzoHash=(Get-FileHash -LiteralPath (Join-Path $game 'PZOptimEngine.jar') -Algorithm SHA256).Hash.ToLowerInvariant();payload=$PayloadProjectRoot}
[IO.File]::WriteAllText((Join-Path $run 'run.json'),($manifest|ConvertTo-Json -Depth 4),$utf8)
Write-Output $run
