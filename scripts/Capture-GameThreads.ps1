# SPDX-License-Identifier: MIT
# Read-only JVM thread snapshots for a running or hung game. Requires a Java 25 JDK.
[CmdletBinding()]
param(
    [ValidateRange(0,2147483647)][int]$GameProcessId=0,
    [string]$JavaHome='',
    [string]$OutputDirectory='',
    [ValidateRange(1,5)][int]$Samples=3,
    [ValidateRange(1,10)][int]$IntervalSeconds=5,
    [ValidateRange(5,30)][int]$TimeoutSeconds=15
)
$ErrorActionPreference='Stop'
if($GameProcessId -eq 0){
    $games=@(Get-Process -Name ProjectZomboid64 -ErrorAction SilentlyContinue)
    if($games.Count -ne 1){
        throw "Expected one ProjectZomboid64 process; found $($games.Count). Pass -GameProcessId with the game's PID from Task Manager."
    }
    $GameProcessId=$games[0].Id
}
$game=Get-Process -Id $GameProcessId -ErrorAction Stop
$homes=@($JavaHome,$env:JAVA_HOME,$env:SC_TEST_JAVA_HOME)
foreach($root in @('C:\Program Files\Java','C:\Program Files\Eclipse Adoptium',
    'C:\Program Files\Microsoft',(Join-Path $env:LOCALAPPDATA 'LivingFellowsDev\toolchains'))){
    if(Test-Path -LiteralPath $root -PathType Container){
        $homes+=@(Get-ChildItem -LiteralPath $root -Directory|Sort-Object Name -Descending|ForEach-Object FullName)
    }
}
$jcmd=$null
foreach($candidate in $homes){
    if([string]::IsNullOrWhiteSpace($candidate)){continue}
    $tool=Join-Path $candidate 'bin\jcmd.exe'
    $release=Join-Path $candidate 'release'
    if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){continue}
    if(-not (Test-Path -LiteralPath $release -PathType Leaf)){continue}
    $versionText=Get-Content -LiteralPath $release -Raw
    if($versionText -notmatch '(?m)^JAVA_VERSION="25(?:[.\-"])'){continue}
    $jcmd=(Resolve-Path -LiteralPath $tool).Path
    break
}
if(-not $jcmd){
    throw 'A Java 25 JDK with bin\jcmd.exe is required. Pass -JavaHome with its folder. The game bundled JRE does not include this tool.'
}
if([string]::IsNullOrWhiteSpace($OutputDirectory)){
    $OutputDirectory=Join-Path ([Environment]::GetFolderPath('Desktop')) (
        'LivingFellows-threads-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'process.txt'),
    "Captured: $([DateTime]::UtcNow.ToString('o'))`nProcess: $($game.ProcessName)`nPID: $GameProcessId`nJDK tool: $jcmd`n",$utf8)
for($index=1;$index -le $Samples;$index++){
    $game.Refresh()
    if($game.HasExited){throw "The game exited before sample $index. Existing evidence: $OutputDirectory"}
    $stdout=Join-Path $OutputDirectory ('threads-{0:D2}.txt' -f $index)
    $stderr=Join-Path $OutputDirectory ('threads-{0:D2}-stderr.txt' -f $index)
    $startInfo=New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName=$jcmd
    $startInfo.Arguments="$GameProcessId Thread.print -l"
    $startInfo.UseShellExecute=$false
    $startInfo.CreateNoWindow=$true
    $startInfo.RedirectStandardOutput=$true
    $startInfo.RedirectStandardError=$true
    $collector=[Diagnostics.Process]::Start($startInfo)
    $outputTask=$collector.StandardOutput.ReadToEndAsync()
    $errorTask=$collector.StandardError.ReadToEndAsync()
    if(-not $collector.WaitForExit($TimeoutSeconds*1000)){
        $collector.Refresh()
        if(-not $collector.HasExited){
            if(-not $collector.Path.Equals($jcmd,[StringComparison]::OrdinalIgnoreCase)){
                throw 'The diagnostic collector identity changed; no process was stopped.'
            }
            # Only the collector created above can be stopped. Never stop the game.
            Stop-Process -Id $collector.Id -Force
            $null=$collector.WaitForExit(3000)
        }
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'attach-timeout.txt'),
            "The JVM did not answer Thread.print within $TimeoutSeconds seconds. Game PID $GameProcessId was left running.`n",$utf8)
        throw "Thread capture timed out. The game is still running. Existing evidence: $OutputDirectory"
    }
    [IO.File]::WriteAllText($stdout,$outputTask.Result,$utf8)
    [IO.File]::WriteAllText($stderr,$errorTask.Result,$utf8)
    if($collector.ExitCode -ne 0 -or -not (Select-String -LiteralPath $stdout -SimpleMatch 'Full thread dump' -Quiet)){
        throw "Thread capture failed; check sample $index and stderr in $OutputDirectory. Run as the same Windows user as the game."
    }
    Write-Output "THREAD_CAPTURE_PASS sample=$index target=$GameProcessId"
    if($index -lt $Samples){Start-Sleep -Seconds $IntervalSeconds}
}
Write-Output "Thread snapshots saved in $OutputDirectory"
