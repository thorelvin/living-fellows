# SPDX-License-Identifier: MIT
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$captureRoot = Join-Path $project 'build\computer-reading\native'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$runRoot = Join-Path $project 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8'
$manifest = Get-Content -LiteralPath (Join-Path $runRoot 'run-manifest.json') -Raw | ConvertFrom-Json
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
foreach ($destination in @($manifest.cacheRoot,$manifest.sourceBridge)) {
    if (-not ([IO.Path]::GetFullPath($destination)).StartsWith($runRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Preview target is outside its disposable harness directory'
    }
}
$cloneMedia = Join-Path $manifest.cacheRoot 'mods\SurvivorCompanion\42\media'
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\*') -Destination $cloneMedia -Recurse -Force
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar') -Destination $manifest.sourceBridge -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'terminal-reading-native.lua') -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
$evidence = Join-Path $manifest.cacheRoot 'Lua\SurvivorCompanionHarness\terminal-reading.log'
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$classpath = @($launcher.classpath | ForEach-Object { if ($_ -eq 'LivingFellowsBridge.jar') { $manifest.sourceBridge } else { $_ } }) -join ';'
$marker = Join-Path $captureRoot ('terminal-reading-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-javaagent:"' + (Join-Path $runRoot 'terminal-loading-agent.jar') + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'survivorcompanion.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip', '-nosound')
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
