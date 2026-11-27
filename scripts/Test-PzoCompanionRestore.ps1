# SPDX-License-Identifier: MIT
<# Real native PZO launch, blocked-provider save and native companion reload.
   Uses an owned game copy, asset snapshot, home and save. No installed launcher,
   real PZO approval or source save is changed. The only test Java mod advances
   the loading screen; PZO itself discovers and starts the production LF bridge.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PzoJar,
    [Parameter(Mandatory)][string]$SeedSave,
    [Parameter(Mandatory)][string]$MediaSnapshotRoot,
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$PayloadProjectRoot='',
    [ValidateRange(240,900)][int]$TimeoutSeconds=480
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
if(-not $PayloadProjectRoot){$PayloadProjectRoot=$project}
$PayloadProjectRoot=[IO.Path]::GetFullPath($PayloadProjectRoot)
$GameRoot=[IO.Path]::GetFullPath($GameRoot)
$SeedSave=[IO.Path]::GetFullPath($SeedSave)
$PzoJar=[IO.Path]::GetFullPath($PzoJar)
$pinnedPzo='026de0512c6058e00f2df1f30d68c1acddeb6efee27877a6015a49f1da2d4d5b'
if((Get-FileHash -LiteralPath $PzoJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinnedPzo){
    throw 'Supply the unmodified official PZO V2.2 PZOptimEngine.jar.'
}
if(-not (Test-Path -LiteralPath (Join-Path $SeedSave 'players.db') -PathType Leaf)){
    throw 'A complete single-player seed save is required.'
}
$fixtures=Join-Path $project 'tests\live\pzo_startup'
$output=Join-Path $project ('build\pzo-restore-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$tools=Join-Path $output 'tools'
New-Item -ItemType Directory -Path $tools -Force|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$results=New-Object Collections.Generic.List[object]
$client=$null
$run=$null
function Get-SeedFingerprint {
    $text=foreach($file in Get-ChildItem -LiteralPath $SeedSave -Recurse -File|Sort-Object FullName){
        $file.FullName.Substring($SeedSave.Length)+'|'+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($hasher.ComputeHash($utf8.GetBytes(($text -join "`n")))).Replace('-','')}
    finally{$hasher.Dispose()}
}
$seedBefore=Get-SeedFingerprint
$installedConfig=Join-Path $GameRoot 'ProjectZomboid64.json'
$configBefore=(Get-FileHash -LiteralPath $installedConfig -Algorithm SHA256).Hash
$installedBridge=Join-Path $GameRoot 'LivingFellowsBridge.jar'
$bridgeBefore=if(Test-Path -LiteralPath $installedBridge){(Get-FileHash -LiteralPath $installedBridge -Algorithm SHA256).Hash}else{''}
$gameJarBefore=(Get-FileHash -LiteralPath (Join-Path $GameRoot 'projectzomboid.jar') -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $output 'source-before.json'),(@{
    seedSha256=$seedBefore;launcherSha256=$configBefore;bridgeSha256=$bridgeBefore;gameJarSha256=$gameJarBefore
}|ConvertTo-Json),$utf8)

function Stop-OwnedClient {
    if(-not $script:client){return}
    $script:client.Refresh()
    if(-not $script:client.HasExited){
        $expected=Join-Path $script:run 'game\ProjectZomboid64.exe'
        if(-not $script:client.Path.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Refusing to stop a process outside the owned PZO fixture.'
        }
        Stop-Process -Id $script:client.Id -Force
        if(-not $script:client.WaitForExit(10000)){throw 'Owned native client did not exit after termination.'}
    }
    $script:client=$null
}
function Start-OwnedClient {
    & (Join-Path $fixtures 'StartClient.ps1') -Run $script:run
    $ownedId=[int](Get-Content -LiteralPath (Join-Path $script:run 'pid.txt'))
    $script:client=Get-Process -Id $ownedId -ErrorAction Stop
}
function Wait-OwnedReceipt([string]$Path,[string]$Mode){
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([DateTime]::UtcNow -lt $deadline){
        if(Test-Path -LiteralPath $Path){
            $text=Get-Content -LiteralPath $Path -Raw -Encoding utf8
            if($text -and (-not $Mode -or $text -match ('(?m)^mode='+[regex]::Escape($Mode)+'\r?$'))){return $text}
        }
        $script:client.Refresh()
        if($script:client.HasExited){throw "Native PZO exited before $Mode receipt, exit=$($script:client.ExitCode). Evidence: $script:run"}
        Start-Sleep -Milliseconds 500
    }
    throw "Native PZO $Mode timed out. Evidence: $script:run"
}
function Set-FixtureDecision([string]$Choice){
    $configPath=Join-Path $script:run 'home\Zomboid\Lua\pzo_config.json'
    $cfg=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
    $cfg.java_mods_enabled=$Choice -ne 'disabled'
    $cfg.approved_java_mods=$script:gateHash
    $cfg.blocked_java_mods=''
    if($Choice -eq 'blocked'){$cfg.blocked_java_mods=$script:bridgeHash}
    elseif($Choice -eq 'approved' -or $Choice -eq 'disabled'){$cfg.approved_java_mods+=','+$script:bridgeHash}
    else{throw 'Unknown fixture Java loading decision.'}
    # Explicit choices in the disposable home only, never the user's PZO file.
    [IO.File]::WriteAllText($configPath,($cfg|ConvertTo-Json -Compress),$utf8)
}
function Save-PhaseEvidence([string]$Name){
    $target=Join-Path $script:run ('evidence-'+$Name)
    New-Item -ItemType Directory -Path $target -Force|Out-Null
    foreach($relative in @('stdout.log','stderr.log','loading-gate.txt','game\ProjectZomboid64.json',
            'home\Zomboid\console.txt','home\Zomboid\Lua\pzo_engine.log','home\Zomboid\Lua\pzo_config.json',
            'home\Zomboid\Lua\pzo-world-result.txt','home\Zomboid\Lua\pzo-startup-menu.txt')){
        $source=Join-Path $script:run $relative
        if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination (Join-Path $target ($relative.Replace('\','-'))) -Force}
    }
}
function Invoke-WorldPhase([string]$Mode,[string]$InputRecord=''){
    & (Join-Path $fixtures 'PrepareWorld.ps1') -Run $script:run -Mode $Mode -RecordFile $InputRecord `
        -SeedSave $SeedSave -GateJar $script:gateJar -ProbePath (Join-Path $fixtures 'Probe.lua')
    Start-OwnedClient
    try {
        $receipt=Join-Path $script:run 'home\Zomboid\Lua\pzo-world-result.txt'
        $null=Wait-OwnedReceipt $receipt $Mode
        & (Join-Path $fixtures 'AssertWorldResult.ps1') -Run $script:run -Mode $Mode
        $pzo=Get-Content -LiteralPath (Join-Path $script:run 'home\Zomboid\Lua\pzo_engine.log') -Raw
        if($pzo -notmatch 'Build 42 JVM Instrumentation Agent Active'){throw 'The real PZO agent was not active.'}
        if($Mode -eq 'waiting'){
            if($pzo -notmatch 'is blocked by the user'){throw 'The real PZO loader did not exercise the fixture block.'}
            $text=Get-Content -LiteralPath $receipt -Raw
            if($text -notmatch 'F10 > JAVA'){throw 'PZO bridge absence did not expose actionable loader guidance.'}
        } elseif($pzo -notmatch 'Invoked premain\(String, Instrumentation\) on livingfellows.bridge.SCBootstrapAgent'){
            throw 'PZO did not discover and invoke the production LF bridge entry.'
        }
        $results.Add(@{phase=$Mode;exitCode=0})
    } finally {Stop-OwnedClient;Save-PhaseEvidence $Mode}
}
try {
    $javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
    & $javac --release 17 -d $tools (Join-Path $project 'tests\live\auto_start\SCLoadingGateAgent.java') `
        (Join-Path $project 'tests\live\auto_start\SCPzoLoadingGateAgent.java')
    if($LASTEXITCODE -ne 0){throw 'PZO loading helper compilation failed.'}
    $manifest=Join-Path $tools 'MANIFEST.MF'
    [IO.File]::WriteAllText($manifest,"Manifest-Version: 1.0`nPremain-Class: livingfellows.harness.SCPzoLoadingGateAgent`n`n",$utf8)
    $script:gateJar=Join-Path $output 'loading-gate.jar'
    & (Join-Path (Split-Path -Parent $javac) 'jar.exe') --create --file $script:gateJar --manifest $manifest -C $tools livingfellows
    if($LASTEXITCODE -ne 0){throw 'PZO loading helper packaging failed.'}
    $script:gateHash=(Get-FileHash -LiteralPath $script:gateJar -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:run=& (Join-Path $fixtures 'PrepareFixture.ps1') -Scenario approved -PayloadProjectRoot $PayloadProjectRoot `
        -GameRoot $GameRoot -OutputRoot $output -MediaSnapshotRoot $MediaSnapshotRoot -PzoJar $PzoJar
    if($script:run -is [array]){throw 'Fixture creation returned unexpected output.'}
    $fixture=Get-Content -LiteralPath (Join-Path $script:run 'run.json') -Raw|ConvertFrom-Json
    $script:bridgeHash=$fixture.bridgeHash
    Write-Output "Native PZO V2.2 restore fixture: $script:run"
    Invoke-WorldPhase 'seed'
    $captured=Join-Path $script:run 'home\Zomboid\Lua\pzo-captured-record.txt'
    if(-not (Test-Path -LiteralPath $captured -PathType Leaf)){throw 'Native seed did not capture its complete record.'}
    Set-FixtureDecision 'blocked'
    Invoke-WorldPhase 'waiting' $captured
    $retained=Join-Path $script:run 'home\Zomboid\Lua\pzo-retained-record.txt'
    if(-not (Test-Path -LiteralPath $retained -PathType Leaf)){throw 'Production save did not retain its waiting record.'}
    Set-FixtureDecision 'approved'
    Invoke-WorldPhase 'disk-restored' $retained

    # A disabled PZO Java loader must remain disabled. Do not replace PZO's
    # entrypoint or start the LF bridge through the test loading helper.
    Set-FixtureDecision 'disabled'
    $probe=Join-Path $script:run 'home\Zomboid\mods\SCPzoStartupProbe\42\media\lua\client\SCPzoStartupProbe.lua'
    $menuLua=@'
Events.OnMainMenuEnter.Add(function()
    local w=getFileWriter('pzo-startup-menu.txt',true,false)
    assert(w,'menu receipt unavailable')
    w:write('bridge='..tostring(SCBridge and SCBridge.getProtocol() or 'absent')..'\npzo='..tostring(PZOEngine~=nil)..'\n')
    w:close()
end)
'@
    [IO.File]::WriteAllText($probe,$menuLua,$utf8)
    $menuReceipt=Join-Path $script:run 'home\Zomboid\Lua\pzo-startup-menu.txt'
    [IO.File]::WriteAllText($menuReceipt,'',$utf8)
    Start-OwnedClient
    try {
        $menu=Wait-OwnedReceipt $menuReceipt ''
        $pzo=Get-Content -LiteralPath (Join-Path $script:run 'home\Zomboid\Lua\pzo_engine.log') -Raw
        if($menu -notmatch '(?m)^bridge=absent\r?$' -or $menu -notmatch '(?m)^pzo=true\r?$' -or
            $pzo -notmatch 'Third-party Java mod loading is disabled'){
            throw 'PZO global Java-off control was bypassed or did not run.'
        }
        $results.Add(@{phase='java-disabled';exitCode=0})
        Write-Output 'NATIVE_PZO_RESTORE_PASS mode=java-disabled'
    } finally {Stop-OwnedClient;Save-PhaseEvidence 'java-disabled'}
} finally {
    Stop-OwnedClient
    $afterBridge=if(Test-Path -LiteralPath $installedBridge){(Get-FileHash -LiteralPath $installedBridge -Algorithm SHA256).Hash}else{''}
    $untouched=(Get-SeedFingerprint) -eq $seedBefore -and
        (Get-FileHash -LiteralPath $installedConfig -Algorithm SHA256).Hash -eq $configBefore -and
        $afterBridge -eq $bridgeBefore -and
        (Get-FileHash -LiteralPath (Join-Path $GameRoot 'projectzomboid.jar') -Algorithm SHA256).Hash -eq $gameJarBefore
    [IO.File]::WriteAllText((Join-Path $output 'results.json'),(@{pzoSha256=$pinnedPzo;run=$script:run;phases=$results.ToArray();sourceUntouched=$untouched}|ConvertTo-Json -Depth 5),$utf8)
    if(-not $untouched){throw 'The installed game or source save changed during the isolated native test.'}
}
Write-Output "NATIVE_PZO_RESTORE_ALL_PASS phases=$($results.Count) evidence=$output"
