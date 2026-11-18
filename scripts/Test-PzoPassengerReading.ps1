# SPDX-License-Identifier: MIT
# Real native PZO regression in a disposable game, home and complete save.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PzoJar,
    [Parameter(Mandatory)][string]$SeedSave,
    [Parameter(Mandatory)][string]$MediaSnapshotRoot,
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [switch]$RevertReadingPose,
    [ValidateRange(240,900)][int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$fixtures=Join-Path $project 'tests\live\pzo_startup'
$pinnedPzo='026de0512c6058e00f2df1f30d68c1acddeb6efee27877a6015a49f1da2d4d5b'
if((Get-FileHash -LiteralPath $PzoJar).Hash.ToLowerInvariant() -ne $pinnedPzo){throw 'Supply the unmodified official PZO V2.2 engine.'}
if(-not (Test-Path -LiteralPath (Join-Path $SeedSave 'players.db'))){throw 'A complete disposable seed save is required.'}
$SeedSave=[IO.Path]::GetFullPath($SeedSave)
$output=Join-Path $project ('build\pzo-passenger-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$classes=Join-Path $output 'classes'
New-Item -ItemType Directory -Path $classes -Force|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
function Get-SeedFingerprint {
    $rows=foreach($file in Get-ChildItem -LiteralPath $SeedSave -Recurse -File|Sort-Object FullName){
        $file.FullName.Substring($SeedSave.Length)+'|'+(Get-FileHash -LiteralPath $file.FullName).Hash
    }
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes(($rows -join "`n")))).Replace('-','')}
    finally{$hash.Dispose()}
}
$seedBefore=Get-SeedFingerprint
$protected=@{}
foreach($name in @('ProjectZomboid64.json','LivingFellowsBridge.jar','projectzomboid.jar')){
    $path=Join-Path $GameRoot $name
    if(Test-Path -LiteralPath $path){$protected[$path]=(Get-FileHash -LiteralPath $path).Hash}
}
$run=$null
$client=$null
$receiptText=''
try {
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
    if($RevertReadingPose){
        $lua=Join-Path $fixture.cache 'mods\SurvivorCompanion\42\media\lua\client\SCDowntime.lua'
        $text=Get-Content -LiteralPath $lua -Raw
        $pattern='(?m)^        passengerPose = activity\.kind == "read",\r?\n'
        if([regex]::Matches($text,$pattern).Count -ne 1){throw 'The exact pose opt-in to revert was not found.'}
        [IO.File]::WriteAllText($lua,([regex]::Replace($text,$pattern,'')),$utf8)
    }
    & (Join-Path $fixtures 'PrepareWorld.ps1') -Run $run -Mode seed -SeedSave $SeedSave `
        -GateJar $gateJar -ProbePath (Join-Path $fixtures 'PassengerReading.lua')
    $config=Get-Content -LiteralPath (Join-Path $fixture.game 'ProjectZomboid64.json') -Raw|ConvertFrom-Json
    if($config.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or @($config.vmArgs|Where-Object {$_ -like '-javaagent:*'}).Count){
        throw 'The actual PZO launcher/loader must own startup.'
    }
    Write-Output "Native PZO passenger fixture: $run reverted=$($RevertReadingPose.IsPresent)"
    & (Join-Path $fixtures 'StartClient.ps1') -Run $run
    $client=Get-Process -Id ([int](Get-Content -LiteralPath (Join-Path $run 'pid.txt')))
    $receipt=Join-Path $fixture.cache 'Lua\pzo-passenger-result.txt'
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline){
        if(Test-Path -LiteralPath $receipt){$receiptText=[string](Get-Content -LiteralPath $receipt -Raw);break}
        $client.Refresh()
        if($client.HasExited){throw 'Native PZO exited before its passenger receipt.'}
        Start-Sleep -Milliseconds 500
    }
    if(-not $receiptText){throw "Native passenger regression timed out. Evidence: $run"}
    Write-Output $receiptText
    if($receiptText -notmatch '(?m)^result=PASS\r?$'){throw 'Native passenger regression failed; see the captured receipt.'}
    $pzo=Get-Content -LiteralPath (Join-Path $fixture.cache 'Lua\pzo_engine.log') -Raw
    if($pzo -notmatch 'Invoked premain\(String, Instrumentation\) on survivorcompanion.bridge.SCBootstrapAgent'){
        throw 'PZO did not load the production bridge.'
    }
    Write-Output "NATIVE_PZO_PASSENGER_PASS evidence=$output"
} finally {
    if($client){
        $client.Refresh()
        if(-not $client.HasExited){
            if($client.Path -ne (Join-Path $run 'game\ProjectZomboid64.exe')){throw 'Refusing to stop a process outside the owned fixture.'}
            Stop-Process -Id $client.Id -Force
            if(-not $client.WaitForExit(10000)){throw 'Owned native game failed to stop.'}
        }
    }
    $untouched=(Get-SeedFingerprint) -eq $seedBefore
    foreach($path in $protected.Keys){$untouched=$untouched -and (Get-FileHash -LiteralPath $path).Hash -eq $protected[$path]}
    [IO.File]::WriteAllText((Join-Path $output 'results.json'),(@{
        run=$run;reverted=$RevertReadingPose.IsPresent;sourceUntouched=$untouched;receipt=$receiptText
    }|ConvertTo-Json),$utf8)
    if(-not $untouched){throw 'The source save or protected installed files changed.'}
}
