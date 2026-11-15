# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PzoJar,
    [string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$LegacyProjectRoot=''
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$pinnedPzo='417af446d2889bb80c0e92d07f5e70cae074f097bf1061c88981c6666ece2e26'
if ((Get-FileHash -LiteralPath $PzoJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinnedPzo) {
    throw 'This native receipt is pinned to the official PZO V2.1 engine; supply that release JAR.'
}
$runRoot=Join-Path $projectRoot ('build\pzo-startup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$game=Join-Path $runRoot 'game'
$classes=Join-Path $runRoot 'classes'
New-Item -ItemType Directory -Path $game,$classes | Out-Null
# Retain this owned test directory: its JRE junction must never be recursively deleted.
New-Item -ItemType Junction -Path (Join-Path $game 'jre64') -Target (Join-Path $GameRoot 'jre64') | Out-Null
foreach($name in @('ProjectZomboid64.exe','steam_api64.dll','steam_appid.txt')) {
    Copy-Item -LiteralPath (Join-Path $GameRoot $name) -Destination $game
}
Copy-Item -LiteralPath $PzoJar -Destination (Join-Path $game 'PZOptimEngine.jar')
$nativePath=@($env:PATH -split ';' | Where-Object {
    $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'jli.dll') -PathType Leaf)
}) -join ';'
$javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $javac --release 17 -d $classes (Join-Path $projectRoot 'tests\core\SCPzoLoaderSmokeTest.java')
if($LASTEXITCODE -ne 0){throw 'Native PZO smoke compilation failed.'}
# The compiler resolver prepends its JDK bin. That would hide this exact bug
# by making jli.dll visible to the native executable. Test a non-JDK PATH.
$env:PATH=$nativePath
$utf8=New-Object System.Text.UTF8Encoding($false)
$configPath=Join-Path $game 'ProjectZomboid64.json'
$config=@{mainClass='com/pzoptimizer/PZOEntrypoint';classpath=@('.',(Join-Path $GameRoot 'projectzomboid.jar').Replace('\','/'),'PZOptimEngine.jar',$classes);vmArgs=@('-Xmx256m','-XX:ActiveProcessorCount=2','-Djava.awt.headless=true',('-Duser.home='+(Join-Path $runRoot 'home')))}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 8),$utf8)
$originalConfig=[IO.File]::ReadAllText($configPath)
if($LegacyProjectRoot) {
    & (Join-Path $LegacyProjectRoot 'scripts\Install-Standalone.ps1') -ProjectRoot $LegacyProjectRoot -GameRoot $game -ModsRoot (Join-Path $runRoot 'mods') -InstallDataRoot (Join-Path $runRoot 'install-data') | Out-Null
    $legacy=Get-Content -LiteralPath $configPath -Raw -Encoding utf8|ConvertFrom-Json
    if(@($legacy.vmArgs|Where-Object {$_ -ceq '-javaagent:LivingFellowsBridge.jar'}).Count -ne 1){throw 'Legacy installer did not reproduce the shipped bootstrap option.'}
}
& (Join-Path $PSScriptRoot 'Install-Standalone.ps1') -ProjectRoot $projectRoot -GameRoot $game -ModsRoot (Join-Path $runRoot 'mods') -InstallDataRoot (Join-Path $runRoot 'install-data') | Out-Null
$installed=[IO.File]::ReadAllText($configPath)
$config=$installed|ConvertFrom-Json
if($config.mainClass -ne 'com/pzoptimizer/PZOEntrypoint' -or @($config.vmArgs|Where-Object {$_ -like '-javaagent:*LivingFellowsBridge.jar*'}).Count -ne 0){throw 'Installer did not retain PZO with loader-only bootstrap.'}
$config.mainClass='SCPzoLoaderSmokeTest'
$originalArgs=@($config.vmArgs)
$canonical=Join-Path $projectRoot 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
$standalone=Join-Path $runRoot 'mods\SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
$results=@()
try {
    foreach($mode in @('legacy-agent-control','pzo-loader')) {
        $config.vmArgs=$originalArgs
        if($mode -eq 'legacy-agent-control'){$config.vmArgs+=@('-javaagent:LivingFellowsBridge.jar')}
        [IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 8),$utf8)
        $out=Join-Path $runRoot ($mode+'-stdout.log')
        $err=Join-Path $runRoot ($mode+'-stderr.log')
        $process=Start-Process -FilePath (Join-Path $game 'ProjectZomboid64.exe') -ArgumentList @(('"'+$canonical+'"'),('"'+$standalone+'"')) -WorkingDirectory $game -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        $retainedHandle=$process.Handle
        if(-not $process.WaitForExit(20000)) {
            $owned=Get-Process -Id $process.Id -ErrorAction SilentlyContinue
            if($owned -and $owned.Path -eq (Join-Path $game 'ProjectZomboid64.exe')){Stop-Process -Id $process.Id -Force}
            throw "Owned native probe timed out: $mode"
        }
        $text=([IO.File]::ReadAllText($out))+([IO.File]::ReadAllText($err))
        $passed=if($mode -eq 'legacy-agent-control'){$process.ExitCode -ne 0 -and $text -match 'Could not find agent library' -and $text -notmatch 'SC_PZO_LOADER_SMOKE_PASS'}else{$process.ExitCode -eq 0 -and $text -match 'SC_PZO_LOADER_SMOKE_PASS'}
        $results+=@{mode=$mode;passed=$passed;exitCode=$process.ExitCode}
        if(-not $passed){throw "Native startup check failed: $mode; see $runRoot"}
        Write-Output "NATIVE_PZO_STARTUP_PASS $mode"
    }
} finally {[IO.File]::WriteAllText($configPath,$installed,$utf8)}
& (Join-Path $PSScriptRoot 'Uninstall-Standalone.ps1') -ProjectRoot $projectRoot -ModsRoot (Join-Path $runRoot 'mods') -InstallDataRoot (Join-Path $runRoot 'install-data') | Out-Null
if([IO.File]::ReadAllText($configPath) -cne $originalConfig -or
    (Test-Path -LiteralPath (Join-Path $game 'LivingFellowsBridge.jar')) -or
    (Test-Path -LiteralPath (Join-Path $runRoot 'mods\SurvivorCompanion')) -or
    (Get-FileHash -LiteralPath (Join-Path $game 'PZOptimEngine.jar') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pinnedPzo){throw 'Native startup fixture uninstall changed the original PZO installation.'}
Write-Output 'NATIVE_PZO_STARTUP_PASS original-launcher-restored'
[IO.File]::WriteAllText((Join-Path $runRoot 'results.json'),($results|ConvertTo-Json -Depth 8),$utf8)
Write-Output "NATIVE_PZO_STARTUP_EVIDENCE $runRoot"
