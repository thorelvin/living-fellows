# SPDX-License-Identifier: MIT
param([Parameter(Mandatory)][string]$Run,[ValidateSet('seed','waiting','restored','disk-restored')][string]$Mode='waiting',[string]$RecordFile='',[Parameter(Mandatory)][string]$SeedSave,[Parameter(Mandatory)][string]$GateJar,[Parameter(Mandatory)][string]$ProbePath)
$ErrorActionPreference='Stop'
$fixture=Get-Content -LiteralPath (Join-Path $Run 'run.json') -Raw|ConvertFrom-Json
$utf8=New-Object Text.UTF8Encoding($false)
$target=Join-Path $fixture.cache 'Saves\Sandbox\PzoRestoreFixture'
if($Mode -ne 'disk-restored' -and (Test-Path -LiteralPath $target)) {
    $backup=$target+'-previous-'+(Get-Date -Format 'yyyyMMddHHmmss')
    $prefix=[IO.Path]::GetFullPath($Run).TrimEnd('\')+'\'
    if(-not [IO.Path]::GetFullPath($target).StartsWith($prefix) -or -not [IO.Path]::GetFullPath($backup).StartsWith($prefix)) {throw 'Fixture save move escaped the owned run.'}
    Move-Item -LiteralPath $target -Destination $backup
}
if($Mode -ne 'disk-restored') {
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null
    Copy-Item -LiteralPath $SeedSave -Destination $target -Recurse
} elseif(-not (Test-Path -LiteralPath (Join-Path $target 'global_mod_data.bin') -PathType Leaf)) {
    throw 'A durably saved waiting world is required for the disk reload.'
}
$list="VERSION = 1,`nmods {`n mod = \LivingFellows,`n mod = \SCPzoStartupProbe,`n mod = \SCPzoLoadingGate,`n}`n"
[IO.File]::WriteAllText((Join-Path $target 'mods.txt'),$list,$utf8)
[IO.File]::WriteAllText((Join-Path $fixture.cache 'mods\default.txt'),$list,$utf8)
$gate=Join-Path $fixture.cache 'mods\SCPzoLoadingGate'
New-Item -ItemType Directory -Path (Join-Path $gate '42\media\java') -Force|Out-Null
$info="name=PZO disposable loading gate`nid=SCPzoLoadingGate`nmodversion=1`njavaJarFile=media/java/PzoLoadingGate.jar`n"
[IO.File]::WriteAllText((Join-Path $gate 'mod.info'),$info,$utf8)
[IO.File]::WriteAllText((Join-Path $gate '42\mod.info'),$info,$utf8)
Copy-Item -LiteralPath $GateJar -Destination (Join-Path $gate '42\media\java\PzoLoadingGate.jar') -Force
$gateHash=(Get-FileHash -LiteralPath (Join-Path $gate '42\media\java\PzoLoadingGate.jar') -Algorithm SHA256).Hash.ToLowerInvariant()
$pzoPath=Join-Path $fixture.cache 'Lua\pzo_config.json'
$pzo=Get-Content -LiteralPath $pzoPath -Raw|ConvertFrom-Json
$hashes=@(([string]$pzo.approved_java_mods -split ',')|Where-Object {$_})+@($gateHash)
$pzo.approved_java_mods=($hashes|Select-Object -Unique)-join ','
[IO.File]::WriteAllText($pzoPath,($pzo|ConvertTo-Json -Compress),$utf8)
$configPath=Join-Path $fixture.game 'ProjectZomboid64.json'
$config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
$config.vmArgs=@($config.vmArgs|Where-Object {$_ -notlike '-Dsc.pzo.loadingGateMarker=*'})+@('-Dsc.pzo.loadingGateMarker='+(Join-Path $fixture.run 'loading-gate.txt'))
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 6),$utf8)
Copy-Item -LiteralPath $ProbePath -Destination (Join-Path $fixture.cache 'mods\SCPzoStartupProbe\42\media\lua\client\SCPzoStartupProbe.lua') -Force
[IO.File]::WriteAllText((Join-Path $fixture.cache 'Lua\pzo-world-mode.txt'),$Mode,$utf8)
if($RecordFile){Copy-Item -LiteralPath $RecordFile -Destination (Join-Path $fixture.cache 'Lua\pzo-input-record.txt') -Force}
foreach($receipt in @('pzo-world-result.txt','pzo-startup-menu.txt')) {
    $receiptPath=Join-Path $fixture.cache ('Lua\'+$receipt)
    if(Test-Path -LiteralPath $receiptPath) {
        Copy-Item -LiteralPath $receiptPath -Destination (Join-Path $fixture.run ($receipt+'-'+(Get-Date -Format 'yyyyMMddHHmmssfff')+'.previous'))
        [IO.File]::WriteAllText($receiptPath,'',$utf8)
    }
}
Write-Output ('World prepared '+$Run+' mode='+$Mode)
