# SPDX-License-Identifier: MIT
param([string]$HistoricalRunRoot='')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot = Join-Path $project 'build\computer-reading\native'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
. (Join-Path $PSScriptRoot '..\NativeProbeFixture.ps1')
$manifest = New-HistoricalNativeProbeFixture -ProjectRoot $project -HistoricalRunRoot $HistoricalRunRoot -ProbeName 'terminal-reading'
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$cloneMedia = $manifest.media
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-reading-native.lua') -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
$evidence = Join-Path $manifest.cacheRoot 'Lua\LivingFellowsHarness\terminal-reading.log'
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-NativeProbeLauncher $game $manifest.sourceBridge
$classpath = $launcher.classpath -join ';'
$marker = Join-Path $captureRoot ('terminal-reading-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-javaagent:"' + $manifest.loadingAgent + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'livingfellows.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip', '-nosound')
$owned = Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $captureRoot 'terminal-reading.stdout.log') -RedirectStandardError (Join-Path $captureRoot 'terminal-reading.stderr.log')
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    while (-not $owned.WaitForExit(1000)) {
        if (Test-Path -LiteralPath $evidence) {
            $result = Get-Content -LiteralPath $evidence -Raw
            if ($result -match '(?m)^FAIL ') { throw $result }
            if ($result -match 'PASS native terminal reading acceptance complete') { Write-Output $result; break }
        }
        if ($timer.Elapsed.TotalSeconds -gt 240) { throw 'Native terminal reading acceptance timed out' }
    }
    if (-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native terminal reading acceptance complete') {
        throw 'Native terminal reading acceptance did not complete'
    }
    foreach ($name in @('emma-reading-computer-1-desk','emma-reading-computer-1-screen','emma-reading-computer-2-desk','emma-reading-computer-2-screen','emma-reading-computer-1-paged','emma-reading-computer-2-paged','emma-reading-computer-2-feedback')) {
        Copy-Item -LiteralPath (Join-Path $manifest.cacheRoot ('Screenshots\' + $name)) -Destination (Join-Path $captureRoot ($name + '.png')) -Force
    }
    Copy-Item -LiteralPath $evidence -Destination (Join-Path $captureRoot 'terminal-reading-evidence.log') -Force
} finally {
    if (-not $owned.HasExited) { Stop-Process -InputObject $owned -Force }
}
