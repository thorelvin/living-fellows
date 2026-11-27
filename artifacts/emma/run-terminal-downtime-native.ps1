# SPDX-License-Identifier: MIT
param([string]$HistoricalRunRoot='')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot -ProbeName 'terminal-downtime'
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$runRoot = $manifest.runRoot
$cloneMedia = $manifest.media
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-downtime-native.lua') -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
$evidence = Join-Path $manifest.cacheRoot 'Lua\LivingFellowsHarness\terminal-downtime.log'
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker = Join-Path $runRoot ('terminal-downtime-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-javaagent:"' + $manifest.loadingAgent + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'livingfellows.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip', '-nosound')
$owned = Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $runRoot 'terminal-downtime.stdout.log') -RedirectStandardError (Join-Path $runRoot 'terminal-downtime.stderr.log')
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    while (-not $owned.WaitForExit(1000)) {
        if (Test-Path -LiteralPath $evidence) {
            $result = Get-Content -LiteralPath $evidence -Raw
            if ($result -match '(?m)^FAIL ') { throw $result }
            if ($result -match 'PASS native terminal downtime acceptance complete') { Write-Output $result; break }
        }
        if ($timer.Elapsed.TotalSeconds -gt 240) { throw "Native terminal acceptance timed out; inspect $runRoot" }
    }
    if (-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native terminal downtime acceptance complete') {
        throw "Native terminal acceptance did not finish; inspect $runRoot"
    }
} finally {
    if (-not $owned.HasExited) { Stop-Process -InputObject $owned -Force }
}
