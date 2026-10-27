# SPDX-License-Identifier: MIT
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runRoot = Join-Path $project 'build\live-sandbox-runs\SC-Harness-20261026-185641-59f036f8'
$manifest = Get-Content -LiteralPath (Join-Path $runRoot 'run-manifest.json') -Raw | ConvertFrom-Json
$game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
$cloneMedia = Join-Path $manifest.cacheRoot 'mods\SurvivorCompanion\42\media'
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar') -Destination $manifest.sourceBridge -Force
New-Item -ItemType Directory -Path (Join-Path $cloneMedia 'shaders') -Force | Out-Null
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\shaders\LF_TerminalLogo.*') -Destination (Join-Path $cloneMedia 'shaders') -Force
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\lua\client\SCTerminal*.lua') -Destination (Join-Path $cloneMedia 'lua\client') -Force
foreach ($module in @('SCDowntime.lua','SCComputerUse.lua','SCNativeActions.lua','SCRelationship.lua')) {
    Copy-Item -LiteralPath (Join-Path $project ('SurvivorCompanion\42\media\lua\client\' + $module)) -Destination (Join-Path $cloneMedia ('lua\client\' + $module)) -Force
}
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\lua\shared\SCNamespace.lua') -Destination (Join-Path $cloneMedia 'lua\shared\SCNamespace.lua') -Force
Copy-Item -LiteralPath (Join-Path $project 'SurvivorCompanion\42\media\lua\client\SCBootstrap.lua') -Destination (Join-Path $cloneMedia 'lua\client\SCBootstrap.lua') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bed-exit-native.lua') -Destination (Join-Path $cloneMedia 'lua\client\ZZSCTerminalAcceptance.lua') -Force
Copy-Item -Path (Join-Path $project 'SurvivorCompanion\42\media\textures\Terminal\*.png') -Destination (Join-Path $cloneMedia 'textures\Terminal') -Force
$evidence = Join-Path $manifest.cacheRoot 'Lua\SurvivorCompanionHarness\bed-exit.log'
if (Test-Path -LiteralPath $evidence) { Move-Item -LiteralPath $evidence -Destination ($evidence + '.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.previous') }
$launcher = Get-Content -LiteralPath (Join-Path $game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$classpath = @($launcher.classpath | ForEach-Object { if ($_ -eq 'LivingFellowsBridge.jar') { $manifest.sourceBridge } else { $_ } }) -join ';'
$marker = Join-Path $runRoot ('bed-exit-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-marker.txt')
$arguments = @($launcher.vmArgs) + @('-XX:+UseZGC', ('-javaagent:"' + (Join-Path $runRoot 'terminal-loading-agent.jar') + '"="' + $marker + '"'),
    '-cp', ('"' + $classpath + '"'), 'survivorcompanion.bridge.SCLauncher', ('-cachedir="' + $manifest.cacheRoot + '"'), '-nosteam', '-novoip', '-nosound')
$owned = Start-Process -FilePath (Join-Path $game 'jre64\bin\java.exe') -ArgumentList $arguments -WorkingDirectory $game -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $runRoot 'bed-exit.stdout.log') -RedirectStandardError (Join-Path $runRoot 'bed-exit.stderr.log')
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    while (-not $owned.WaitForExit(1000)) {
        if (Test-Path -LiteralPath $evidence) {
            $result = Get-Content -LiteralPath $evidence -Raw
            if ($result -match '(?m)^FAIL ') { throw $result }
            if ($result -match 'PASS native bed exit acceptance complete') { Write-Output $result; break }
        }
        if ($timer.Elapsed.TotalSeconds -gt 240) { throw "Native terminal acceptance timed out; inspect $runRoot" }
    }
    if (-not (Test-Path -LiteralPath $evidence) -or (Get-Content -LiteralPath $evidence -Raw) -notmatch 'PASS native bed exit acceptance complete') {
        throw "Native terminal acceptance did not finish; inspect $runRoot"
    }
} finally {
    if (-not $owned.HasExited) { Stop-Process -InputObject $owned -Force }
}
