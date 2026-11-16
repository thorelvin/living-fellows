# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$active = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(javaw|ProjectZomboid64)\.exe$' -and
    $_.CommandLine -match 'SCLauncher|ProjectZomboid'
})
if ($active.Count) { throw 'Finish the live game before running the fixture compiler.' }
$logs = Join-Path $project ('build\test-results\solo-melee-fixture-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$classes = Join-Path $logs 'classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
$java = Join-Path $GameRoot 'jre64\bin\java.exe'
$jar = Join-Path $GameRoot 'projectzomboid.jar'
$classpath = "$classes;$jar"
$probe = Join-Path $project 'tests\live\mod\SCRealSandboxHarness\42\media\lua\client\SCSoloMeleeProbe.lua'
$main = Join-Path $project 'tests\live\mod\SCRealSandboxHarness\42\media\lua\client\SCRealSandboxHarness.lua'
$harness = Join-Path $project 'tests\live\solo_melee_fixture_harness.lua'
function Invoke-RecordedJava([string[]]$Arguments,[string]$LogPath) {
    $prior = $ErrorActionPreference
    Push-Location -LiteralPath $GameRoot
    try {
        $ErrorActionPreference = 'Continue'
        & $java @Arguments > $LogPath 2>&1
        return $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $prior
    }
}
& $javac -d $classes (Join-Path $project 'tests\ui\ReflectLuaCompiler.java') `
    (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Fixture compiler build failed.' }
foreach ($mode in @('normal','debug')) {
    $compileArgs = @('-cp',$classpath,'ReflectLuaCompiler')
    if ($mode -eq 'debug') { $compileArgs += '--debug-compile' }
    $compileExit = Invoke-RecordedJava ($compileArgs + @($probe,$main,$harness)) (Join-Path $logs "compile-$mode.log")
    if ($compileExit -ne 0) { throw "$mode live-fixture compilation failed; see $logs" }
}
$positiveExit = Invoke-RecordedJava @('-cp',$classpath,'KahluaTestRunner',$probe,$harness) (Join-Path $logs 'positive.log')
if ($positiveExit -ne 0) { throw "Fixture contract failed; see $logs" }

# Reproduce the inherited moving-object cleanup bug in an isolated source copy.
# The test must reject it by exit status, not by finding PASS text in output.
$text = [IO.File]::ReadAllText($probe)
$pattern = '(?s)function Probe\.removeBody\(body\).*?\nend(?=\nlocal function clearBodies)'
$broken = @'
function Probe.removeBody(body)
    call(body,"removeFromWorld");call(body,"removeFromSquare")
    return true
end
'@
$negative = [regex]::Replace($text,$pattern,$broken)
if ($negative -eq $text) { throw 'Negative control did not replace the cleanup helper.' }
$negativePath = Join-Path $logs 'old-cleanup-negative.lua'
[IO.File]::WriteAllText($negativePath,$negative,[Text.UTF8Encoding]::new($false))
$negativeExit = Invoke-RecordedJava @('-cp',$classpath,'KahluaTestRunner',$negativePath,$harness) (Join-Path $logs 'negative.log')
if ($negativeExit -eq 0) { throw 'Old-cleanup negative control unexpectedly passed.' }
$negativeLog = [IO.File]::ReadAllText((Join-Path $logs 'negative.log'))
if ($negativeLog -notmatch 'corpse leaves its static square list') {
    throw 'Negative control failed for an unexpected reason.'
}
Write-Output "SOLO_MELEE_FIXTURE_PASS normal=true debug=true positive_exit=0 old_cleanup_exit=$negativeExit logs=$logs"
