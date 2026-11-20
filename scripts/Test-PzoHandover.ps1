# SPDX-License-Identifier: MIT
# Native Handover capabilities/acceptance in a disposable Rising-save clone.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PzoJar,
    [Parameter(Mandatory)][string]$SeedSave,
    [Parameter(Mandatory)][string]$MediaSnapshotRoot,
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [ValidateRange(240,900)][int]$TimeoutSeconds=600,
    [switch]$Acceptance,
    [switch]$Interrupt,
    [switch]$Vehicle,
    [switch]$Dormant,
    [switch]$NewSurvivor,
    [switch]$Rescue,
    [switch]$Remote,
    [switch]$Camp,
    [switch]$VisualOnly,
    [switch]$EngineSound,
    [string]$PayloadProjectRoot,
    [string]$ReuseRun
)
$ErrorActionPreference='Stop'
if(Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue){throw 'Only one native game client may run; close the existing client first.'}
$project=Split-Path -Parent $PSScriptRoot
$fixtures=Join-Path $project 'tests\live\pzo_startup'
if(-not $PayloadProjectRoot){$PayloadProjectRoot=$project}
$PayloadProjectRoot=[IO.Path]::GetFullPath($PayloadProjectRoot)
if($Acceptance -and $PayloadProjectRoot -ne $project){throw 'Final acceptance must use this checkout payload.'}
$pinnedPzo='026de0512c6058e00f2df1f30d68c1acddeb6efee27877a6015a49f1da2d4d5b'
if((Get-FileHash -LiteralPath $PzoJar).Hash.ToLowerInvariant() -ne $pinnedPzo){throw 'Supply the unmodified official PZO V2.2 engine.'}
if(-not (Test-Path -LiteralPath (Join-Path $SeedSave 'players.db'))){throw 'A complete disposable seed save is required.'}
$SeedSave=[IO.Path]::GetFullPath($SeedSave)
$output=Join-Path $project ('build\pzo-handover-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$classes=Join-Path $output 'classes'
New-Item -ItemType Directory -Path $classes -Force|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
function Get-SeedFingerprint {
    param([string]$Root=$SeedSave)
    $rows=foreach($file in Get-ChildItem -LiteralPath $Root -Recurse -File|Sort-Object FullName){
        $file.FullName.Substring($Root.Length)+'|'+(Get-FileHash -LiteralPath $file.FullName).Hash
    }
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes(($rows -join "`n")))).Replace('-','')}
    finally{$hash.Dispose()}
}
function Get-SourceManifest {
    $names=@(& git -C $PayloadProjectRoot ls-files --cached --others --exclude-standard -- SurvivorCompanion | Sort-Object -Unique)
    if($LASTEXITCODE -ne 0 -or -not $names.Count){throw 'Cannot freeze native payload project source files.'}
    foreach($name in $names){
        $path=Join-Path $PayloadProjectRoot $name
        if(Test-Path -LiteralPath $path -PathType Leaf){[pscustomobject]@{path=$name;sha256=(Get-FileHash -LiteralPath $path).Hash}}
    }
}
$sourceBefore=@(Get-SourceManifest)
[IO.File]::WriteAllText((Join-Path $output 'source-before.json'),($sourceBefore|ConvertTo-Json -Depth 3),$utf8)
$payloadRoot=Join-Path $PayloadProjectRoot 'SurvivorCompanion'
$payloadBefore=Get-SeedFingerprint $payloadRoot
$seedBefore=Get-SeedFingerprint
$installedMod=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods\SurvivorCompanion'
$installedModBefore=if(Test-Path -LiteralPath $installedMod){Get-SeedFingerprint $installedMod}else{'absent'}
$protected=@{}
foreach($name in @('ProjectZomboid64.json','LivingFellowsBridge.jar','projectzomboid.jar')){
    $path=Join-Path $GameRoot $name
    if(Test-Path -LiteralPath $path){$protected[$path]=(Get-FileHash -LiteralPath $path).Hash}
}
$run=$null
$client=$null
$receiptText=''
try {
    & (Join-Path $PSScriptRoot 'Test-PzRuntime.ps1') -GameRoot $GameRoot *> (Join-Path $output 'runtime.log')
    $apiRows=foreach($relative in @('scripts\generated\items\literature.txt','lua\client\ISUI\ISContextMenu.lua','lua\client\TimedActions\ISGrabItemAction.lua')){
        $installed=(Get-FileHash -LiteralPath (Join-Path (Join-Path $GameRoot 'media') $relative)).Hash
        $snapshot=(Get-FileHash -LiteralPath (Join-Path $MediaSnapshotRoot $relative)).Hash
        if($installed -ne $snapshot){throw "Native Handover API differs from the owned snapshot: $relative"}
        @{path=$relative;sha256=$installed}
    }
    [IO.File]::WriteAllText((Join-Path $output 'native-api-sources.json'),($apiRows|ConvertTo-Json),$utf8)
    $javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
    & $javac --release 17 -d $classes (Join-Path $project 'tests\live\auto_start\SCLoadingGateAgent.java') `
        (Join-Path $project 'tests\live\auto_start\SCPzoLoadingGateAgent.java')
    if($LASTEXITCODE -ne 0){throw 'Loading-gate compilation failed.'}
    $manifest=Join-Path $output 'MANIFEST.MF'
    [IO.File]::WriteAllText($manifest,"Manifest-Version: 1.0`nPremain-Class: survivorcompanion.harness.SCPzoLoadingGateAgent`n`n",$utf8)
    $gateJar=Join-Path $output 'loading-gate.jar'
    & (Join-Path (Split-Path -Parent $javac) 'jar.exe') --create --file $gateJar --manifest $manifest -C $classes survivorcompanion
    if($LASTEXITCODE -ne 0){throw 'Loading-gate packaging failed.'}
    if($ReuseRun){
        $run=[IO.Path]::GetFullPath($ReuseRun)
        $ownedPrefix=[IO.Path]::GetFullPath((Join-Path $project 'build')).TrimEnd('\')+'\'
        if(-not $run.StartsWith($ownedPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Reused native fixture must remain under this checkout build directory.'}
    }else{
        $run=& (Join-Path $fixtures 'PrepareFixture.ps1') -Scenario approved -PayloadProjectRoot $PayloadProjectRoot `
            -GameRoot $GameRoot -OutputRoot $output -MediaSnapshotRoot $MediaSnapshotRoot -PzoJar $PzoJar
    }
    if($run -is [array]){throw 'Unexpected fixture path output.'}
    $fixture=Get-Content -LiteralPath (Join-Path $run 'run.json') -Raw|ConvertFrom-Json
    if($ReuseRun){
        if([IO.Path]::GetFullPath($fixture.game) -ne (Join-Path $run 'game') -or
            [IO.Path]::GetFullPath($fixture.cache) -ne (Join-Path $run 'home\Zomboid') -or
            $fixture.scenario -ne 'approved'){throw 'Reused fixture paths or ownership do not match the owned run.'}
        & (Join-Path $PSScriptRoot 'Install-Standalone.ps1') -ProjectRoot $PayloadProjectRoot -GameRoot $fixture.game `
            -ModsRoot (Join-Path $fixture.cache 'mods') -InstallDataRoot (Join-Path $run 'install-data') *> (Join-Path $output 'refresh-install.log')
        if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw 'Owned fixture payload refresh failed.'}
        $fixture.bridgeHash=(Get-FileHash -LiteralPath (Join-Path $fixture.game 'LivingFellowsBridge.jar')).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText((Join-Path $run 'run.json'),($fixture|ConvertTo-Json),$utf8)
        $approvalPath=Join-Path $fixture.cache 'Lua\pzo_config.json'
        $approval=Get-Content -LiteralPath $approvalPath -Raw|ConvertFrom-Json
        $approval.approved_java_mods=$fixture.bridgeHash
        [IO.File]::WriteAllText($approvalPath,($approval|ConvertTo-Json -Compress),$utf8)
    }
    # The shipping standalone builder deliberately removes Workshop dependency
    # metadata. Compare against that exact public payload, including metadata.
    $expectedRoot=Join-Path $output 'expected-payload'
    & (Join-Path $PSScriptRoot 'New-StandalonePayload.ps1') -ProjectRoot $PayloadProjectRoot -OutputRoot $expectedRoot -AllowExternalOutput | Out-Null
    $expectedPayload=Join-Path $expectedRoot 'SurvivorCompanion'
    $sourceRows=@();$sourceFailures=@()
    foreach($file in Get-ChildItem -LiteralPath $expectedPayload -Recurse -File){
        $relative=$file.FullName.Substring($expectedPayload.Length).TrimStart([char[]]'\/')
        $staged=Join-Path (Join-Path $fixture.cache 'mods\SurvivorCompanion') $relative
        $expected=(Get-FileHash -LiteralPath $file.FullName).Hash
        $actual=if(Test-Path -LiteralPath $staged){(Get-FileHash -LiteralPath $staged).Hash}else{'missing'}
        $sourceRows+=@{path=$relative;sha256=$expected}
        if($actual -ne $expected){$sourceFailures+=@{path=$relative;expected=$expected;actual=$actual}}
    }
    $stagedPayload=Join-Path $fixture.cache 'mods\SurvivorCompanion'
    $installManifestPath=Join-Path $stagedPayload '.sc-install-manifest.json'
    $installManifest=Get-Content -LiteralPath $installManifestPath -Raw|ConvertFrom-Json
    if($installManifest.owner -ne 'LivingFellows.Companion.cleanroom.0.9.0' -or -not $installManifest.nativeBridge){throw 'Unexpected fixture installation manifest.'}
    if(@($installManifest.files.PSObject.Properties).Count -ne $sourceRows.Count){throw 'Fixture install manifest has a different file count.'}
    foreach($row in $sourceRows){
        $manifestName=$row.path.Replace('\','/')
        if($installManifest.files.$manifestName -ne $row.sha256){throw "Fixture install manifest SHA differs: $manifestName"}
    }
    foreach($file in Get-ChildItem -LiteralPath $stagedPayload -Recurse -File){
        $relative=$file.FullName.Substring($stagedPayload.Length).TrimStart([char[]]'\/')
        if($relative -ne '.sc-install-manifest.json' -and -not (Test-Path -LiteralPath (Join-Path $expectedPayload $relative) -PathType Leaf)){
            $sourceFailures+=@{path=$relative;expected='absent';actual='unexpected staged file'}
        }
    }
    [IO.File]::WriteAllText((Join-Path $output 'source-match.json'),(@{files=$sourceRows.Count;matches=($sourceFailures.Count -eq 0);expectedBuilder='New-StandalonePayload.ps1';installManifestSha256=(Get-FileHash -LiteralPath $installManifestPath).Hash;failures=$sourceFailures;manifest=$sourceRows}|ConvertTo-Json -Depth 5),$utf8)
    if($sourceFailures.Count){throw 'Staged native payload does not match the frozen source.'}
    $expectedBridge=(Get-FileHash -LiteralPath (Join-Path $expectedPayload '42\media\java\SurvivorCompanionBridge.jar')).Hash
    if((Get-FileHash -LiteralPath (Join-Path $fixture.game 'LivingFellowsBridge.jar')).Hash -ne $expectedBridge){
        throw 'Fixture game bridge differs from the exact staged payload bridge.'
    }
    $probe=Join-Path $output 'HandoverCapabilities.lua'
    $probeName=if($NewSurvivor -or $Rescue){'HandoverNewAcceptance.lua'}elseif($Acceptance -or $Interrupt -or $Vehicle -or $Dormant){'HandoverAcceptance.lua'}elseif($VisualOnly){'HandoverVisual.lua'}else{'HandoverCapabilities.lua'}
    Copy-Item -LiteralPath (Join-Path $fixtures $probeName) -Destination $probe
    $worldMode=if($VisualOnly){'disk-restored'}else{'seed'}
    & (Join-Path $fixtures 'PrepareWorld.ps1') -Run $run -Mode $worldMode -SeedSave $SeedSave -GateJar $gateJar -ProbePath $probe
    $config=Get-Content -LiteralPath (Join-Path $fixture.game 'ProjectZomboid64.json') -Raw|ConvertFrom-Json
    if($config.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or @($config.vmArgs|Where-Object {$_ -like '-javaagent:*'}).Count){throw 'The actual official PZO launcher/loader must own startup.'}
    $pzoConfigPath=Join-Path $fixture.cache 'Lua\pzo_config.json'
    $pzoConfig=Get-Content -LiteralPath $pzoConfigPath -Raw|ConvertFrom-Json
    $pzoConfig.ignored_version='2.3.1'
    [IO.File]::WriteAllText($pzoConfigPath,($pzoConfig|ConvertTo-Json -Compress),$utf8)
    $launchScript=Join-Path $fixtures 'StartClient.ps1'
    if($Acceptance -or $EngineSound){
        $launchScript=Join-Path $output 'StartHandoverClient.ps1'
        $launcher=Get-Content -LiteralPath (Join-Path $fixtures 'StartClient.ps1') -Raw
        [IO.File]::WriteAllText($launchScript,$launcher.Replace(' -nosteam -nosound -novoip',' -nosteam -novoip'),$utf8)
        $optionsPath=Join-Path $fixture.cache 'options.ini'
        $optionLines=@(Get-Content -LiteralPath $optionsPath|Where-Object {$_ -notmatch '^soundVolume='})+@('soundVolume=8')
        [IO.File]::WriteAllLines($optionsPath,[string[]]$optionLines,$utf8)
    }
    $modes=if($Dormant){@('dormant-setup','dormant','dormant-reload')}elseif($Vehicle){@('vehicle','vehicle-reload')}elseif($Rescue){@('rescue','rescue-reload')}elseif($NewSurvivor){@('new','new-reload')}elseif($Interrupt){@('interrupt','interrupt-reload')}elseif($Camp){@('camp-create','camp-reload')}elseif($Remote){@('remote-create','remote-reload')}elseif($Acceptance){@('acceptance','acceptance-reload')}elseif($VisualOnly){@('visual')}else{@('create','reload')}
    foreach($mode in $modes){
        if(Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue){throw 'Only one native game client may run.'}
        [IO.File]::WriteAllText((Join-Path $fixture.cache 'Lua\pzo-handover-mode.txt'),$mode,$utf8)
        $receipt=Join-Path $fixture.cache 'Lua\pzo-handover-result.txt'
        if(Test-Path -LiteralPath $receipt){Remove-Item -LiteralPath $receipt}
        Write-Output "Native PZO Handover ${mode}: $run"
        $stagedProbe=Join-Path $fixture.cache 'mods\SCPzoStartupProbe\42\media\lua\client\SCPzoStartupProbe.lua'
        $sourceProbe=Join-Path $fixtures $probeName
        $probeHash=(Get-FileHash -LiteralPath $sourceProbe).Hash
        if((Get-FileHash -LiteralPath $stagedProbe).Hash -ne $probeHash){throw 'Staged native probe differs from its frozen test source.'}
        [IO.File]::WriteAllText((Join-Path $output ($mode+'-probe-sha256.txt')),$probeHash,$utf8)
        Write-Output ('Frozen probe SHA256='+$probeHash)
        & $launchScript -Run $run
        $client=Get-Process -Id ([int](Get-Content -LiteralPath (Join-Path $run 'pid.txt')))
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $receiptText=''
        while([DateTime]::UtcNow -lt $deadline){
            if(Test-Path -LiteralPath $receipt){$receiptText=[string](Get-Content -LiteralPath $receipt -Raw);break}
            $client.Refresh();if($client.HasExited){throw 'Native PZO exited before its Handover receipt.'}
            Start-Sleep -Milliseconds 500
        }
        if(-not $receiptText){throw "Native Handover timed out. Evidence: $run"}
        Copy-Item -LiteralPath $receipt -Destination (Join-Path $output ($mode+'-result.txt'))
        Write-Output $receiptText
        if($receiptText -notmatch '(?m)^result=PASS\r?$'){throw 'Native Handover failed; see captured receipt.'}
        $client.Refresh()
        if(-not $client.HasExited){
            if($client.Path -ne (Join-Path $run 'game\ProjectZomboid64.exe')){throw 'Refusing to stop a process outside the owned fixture.'}
            Stop-Process -Id $client.Id -Force
            if(-not $client.WaitForExit(10000)){throw 'Owned native game failed to stop.'}
        }
        foreach($name in @('stdout.log','stderr.log','loading-gate.txt')){if(Test-Path -LiteralPath (Join-Path $run $name)){Copy-Item -LiteralPath (Join-Path $run $name) -Destination (Join-Path $output ($mode+'-'+$name))}}
        if($mode -eq 'dormant-setup' -or $mode -eq 'dormant' -or $mode -eq 'vehicle' -or $mode -eq 'new' -or $mode -eq 'rescue' -or $mode -eq 'interrupt' -or $mode -eq 'create' -or $mode -eq 'camp-create' -or $mode -eq 'remote-create' -or $mode -eq 'acceptance'){
            & (Join-Path $fixtures 'PrepareWorld.ps1') -Run $run -Mode disk-restored -SeedSave $SeedSave -GateJar $gateJar -ProbePath $probe
        }
    }
    $pzo=Get-Content -LiteralPath (Join-Path $fixture.cache 'Lua\pzo_engine.log') -Raw
    if($pzo -notmatch 'Invoked premain\(String, Instrumentation\) on survivorcompanion.bridge.SCBootstrapAgent'){
        throw 'PZO did not load the production bridge.'
    }
    Write-Output "NATIVE_PZO_HANDOVER_PASS evidence=$output"
} finally {
    if($client){
        $client.Refresh()
        if(-not $client.HasExited){
            if($client.Path -ne (Join-Path $run 'game\ProjectZomboid64.exe')){throw 'Refusing to stop a process outside the owned fixture.'}
            Stop-Process -Id $client.Id -Force
            if(-not $client.WaitForExit(10000)){throw 'Owned native game failed to stop.'}
        }
    }
    $seedAfter=Get-SeedFingerprint
    $installedModAfter=if(Test-Path -LiteralPath $installedMod){Get-SeedFingerprint $installedMod}else{'absent'}
    $payloadAfter=Get-SeedFingerprint $payloadRoot
    $sourceAfter=@(Get-SourceManifest)
    $sourceUnchanged=($sourceBefore|ConvertTo-Json -Compress) -eq ($sourceAfter|ConvertTo-Json -Compress)
    [IO.File]::WriteAllText((Join-Path $output 'source-after.json'),($sourceAfter|ConvertTo-Json -Depth 3),$utf8)
    $untouched=$sourceUnchanged -and ($payloadAfter -eq $payloadBefore) -and ($seedAfter -eq $seedBefore) -and ($installedModBefore -eq $installedModAfter)
    $protectedAfter=@{}
    foreach($path in $protected.Keys){
        $protectedAfter[$path]=(Get-FileHash -LiteralPath $path).Hash
        $untouched=$untouched -and $protectedAfter[$path] -eq $protected[$path]
    }
    [IO.File]::WriteAllText((Join-Path $output 'results.json'),(@{
        run=$run;sourceUntouched=$untouched;frozenSourceFiles=$sourceBefore.Count;frozenSourceUnchanged=$sourceUnchanged;receipt=$receiptText
        mode=$(if($Acceptance){'full-handover-acceptance'}else{'phase0-native-capabilities'});payloadProjectRoot=$PayloadProjectRoot
        seedFingerprintBefore=$seedBefore;seedFingerprintAfter=$seedAfter
        payloadFingerprintBefore=$payloadBefore;payloadFingerprintAfter=$payloadAfter
        installedHashesBefore=$protected;installedHashesAfter=$protectedAfter
        installedModFingerprintBefore=$installedModBefore;installedModFingerprintAfter=$installedModAfter
    }|ConvertTo-Json),$utf8)
    if(-not $untouched){throw 'The source save or protected installed files changed.'}
}
