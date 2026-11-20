# SPDX-License-Identifier: MIT
# Native medical Phase 0 engine capabilities in a disposable Rising-save clone.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PzoJar,
    [Parameter(Mandatory)][string]$SeedSave,
    [Parameter(Mandatory)][string]$MediaSnapshotRoot,
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [ValidateRange(240,900)][int]$TimeoutSeconds=600,
    [switch]$Acceptance,
    [switch]$VisitsOnly
)
$ErrorActionPreference='Stop'
if(Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue){throw 'Only one native game client may run; close the existing client first.'}
$project=Split-Path -Parent $PSScriptRoot
$fixtures=Join-Path $project 'tests\live\pzo_startup'
$pinnedPzo='026de0512c6058e00f2df1f30d68c1acddeb6efee27877a6015a49f1da2d4d5b'
if((Get-FileHash -LiteralPath $PzoJar).Hash.ToLowerInvariant() -ne $pinnedPzo){throw 'Supply the unmodified official PZO V2.2 engine.'}
if(-not (Test-Path -LiteralPath (Join-Path $SeedSave 'players.db'))){throw 'A complete disposable seed save is required.'}
$SeedSave=[IO.Path]::GetFullPath($SeedSave)
$output=Join-Path $project ('build\pzo-medical-procedures-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
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
$payloadRoot=Join-Path $project 'SurvivorCompanion'
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
    $apiRows=foreach($relative in @('lua\shared\TimedActions\ISRemoveBullet.lua','lua\shared\TimedActions\ISRemoveGlass.lua',
        'lua\shared\TimedActions\ISCleanBurn.lua','lua\shared\TimedActions\ISDisinfect.lua','lua\client\XpSystem\ISUI\ISHealthPanel.lua')){
        $installed=(Get-FileHash -LiteralPath (Join-Path (Join-Path $GameRoot 'media') $relative)).Hash
        $snapshot=(Get-FileHash -LiteralPath (Join-Path $MediaSnapshotRoot $relative)).Hash
        if($installed -ne $snapshot){throw "Native medical API differs from the owned snapshot: $relative"}
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
    $run=& (Join-Path $fixtures 'PrepareFixture.ps1') -Scenario approved -PayloadProjectRoot $project `
        -GameRoot $GameRoot -OutputRoot $output -MediaSnapshotRoot $MediaSnapshotRoot -PzoJar $PzoJar
    if($run -is [array]){throw 'Unexpected fixture path output.'}
    $fixture=Get-Content -LiteralPath (Join-Path $run 'run.json') -Raw|ConvertFrom-Json
    # The shipping standalone builder deliberately removes Workshop dependency
    # metadata. Compare against that exact public payload, including metadata.
    $expectedRoot=Join-Path $output 'expected-payload'
    & (Join-Path $PSScriptRoot 'New-StandalonePayload.ps1') -ProjectRoot $project -OutputRoot $expectedRoot | Out-Null
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
    [IO.File]::WriteAllText((Join-Path $output 'source-match.json'),(@{files=$sourceRows.Count;matches=($sourceFailures.Count -eq 0);expectedBuilder='New-StandalonePayload.ps1';failures=$sourceFailures;manifest=$sourceRows}|ConvertTo-Json -Depth 5),$utf8)
    if($sourceFailures.Count){throw 'Staged native payload does not match the frozen source.'}
    $probe=Join-Path $output 'MedicalProceduresCapabilities.lua'
    $probeText=Get-Content -LiteralPath (Join-Path $fixtures 'MedicalProceduresCapabilities.lua') -Raw
    if($Acceptance -or $VisitsOnly){$probeText="SC_MEDICAL_PROCEDURES_ACCEPTANCE = true`n"+$probeText}
    if($VisitsOnly){$probeText="SC_MEDICAL_VISITS_DIAGNOSTIC_ONLY = true`n"+$probeText}
    [IO.File]::WriteAllText($probe,$probeText,$utf8)
    & (Join-Path $fixtures 'PrepareWorld.ps1') -Run $run -Mode seed -SeedSave $SeedSave `
        -GateJar $gateJar -ProbePath $probe
    foreach($helper in @('MedicalProceduresAcceptance.lua','MedicalVisitsAcceptance.lua')){
        $helperPath=Join-Path $fixtures $helper
        if(($Acceptance -or $VisitsOnly) -and -not (Test-Path -LiteralPath $helperPath)){throw "Missing final native acceptance helper: $helper"}
        if(Test-Path -LiteralPath $helperPath){
            Copy-Item -LiteralPath $helperPath -Destination (Join-Path $fixture.cache ('mods\SCPzoStartupProbe\42\media\lua\client\'+$helper))
        }
    }
    $config=Get-Content -LiteralPath (Join-Path $fixture.game 'ProjectZomboid64.json') -Raw|ConvertFrom-Json
    if($config.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or @($config.vmArgs|Where-Object {$_ -like '-javaagent:*'}).Count){
        throw 'The actual PZO launcher/loader must own startup.'
    }
    # This pinned compatibility fixture must not pause at the upstream update UI.
    # Approval/loading still belongs to the unchanged official PZO V2.2 engine.
    $pzoConfigPath=Join-Path $fixture.cache 'Lua\pzo_config.json'
    $pzoConfig=Get-Content -LiteralPath $pzoConfigPath -Raw|ConvertFrom-Json
    $pzoConfig.ignored_version='2.3'
    [IO.File]::WriteAllText($pzoConfigPath,($pzoConfig|ConvertTo-Json -Compress),$utf8)
    Write-Output "Native PZO medical procedures: $run"
    & (Join-Path $fixtures 'StartClient.ps1') -Run $run
    $client=Get-Process -Id ([int](Get-Content -LiteralPath (Join-Path $run 'pid.txt')))
    $receipt=Join-Path $fixture.cache 'Lua\pzo-medical-procedures-result.txt'
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline){
        if(Test-Path -LiteralPath $receipt){$receiptText=[string](Get-Content -LiteralPath $receipt -Raw);break}
        $client.Refresh()
        if($client.HasExited){throw 'Native PZO exited before its medical receipt.'}
        Start-Sleep -Milliseconds 500
    }
    if(-not $receiptText){throw "Native medical capabilities regression timed out. Evidence: $run"}
    Write-Output $receiptText
    if($receiptText -notmatch '(?m)^result=PASS\r?$'){throw 'Native medical capabilities regression failed; see the captured receipt.'}
    $pzo=Get-Content -LiteralPath (Join-Path $fixture.cache 'Lua\pzo_engine.log') -Raw
    if($pzo -notmatch 'Invoked premain\(String, Instrumentation\) on survivorcompanion.bridge.SCBootstrapAgent'){
        throw 'PZO did not load the production bridge.'
    }
    Write-Output "NATIVE_PZO_MEDICAL_PROCEDURES_PASS evidence=$output"
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
    $untouched=($payloadAfter -eq $payloadBefore) -and ($seedAfter -eq $seedBefore) -and ($installedModBefore -eq $installedModAfter)
    $protectedAfter=@{}
    foreach($path in $protected.Keys){
        $protectedAfter[$path]=(Get-FileHash -LiteralPath $path).Hash
        $untouched=$untouched -and $protectedAfter[$path] -eq $protected[$path]
    }
    [IO.File]::WriteAllText((Join-Path $output 'results.json'),(@{
        run=$run;sourceUntouched=$untouched;receipt=$receiptText
        mode=$(if($VisitsOnly){'visits-diagnostic-only'}elseif($Acceptance){'full-phase2-acceptance'}else{'native-capabilities'})
        seedFingerprintBefore=$seedBefore;seedFingerprintAfter=$seedAfter
        payloadFingerprintBefore=$payloadBefore;payloadFingerprintAfter=$payloadAfter
        installedHashesBefore=$protected;installedHashesAfter=$protectedAfter
        installedModFingerprintBefore=$installedModBefore;installedModFingerprintAfter=$installedModAfter
    }|ConvertTo-Json),$utf8)
    if(-not $untouched){throw 'The source save or protected installed files changed.'}
}
