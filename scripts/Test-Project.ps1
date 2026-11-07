# SPDX-License-Identifier: MIT
<# Five production checks. Specialist regressions remain explicit on-demand runs. #>
[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [ValidateSet('Build', 'Lifecycle', 'Behaviour', 'Cargo', 'Interface')]
    [string[]]$Check = @('Build', 'Lifecycle', 'Behaviour', 'Cargo', 'Interface'),
    [switch]$Release,
    [switch]$Serial,
    [ValidateRange(0, 1)][int]$Jobs = 1
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$order = @('Build', 'Lifecycle', 'Behaviour', 'Cargo', 'Interface')
$selected = @($order | Where-Object { $Check -contains $_ })
if ($selected.Count -eq 0) { throw 'Select at least one essential check.' }
if ($Release -and $selected.Count -ne 5) { throw '-Release requires all five checks.' }
. (Join-Path $PSScriptRoot 'ScTestRuntime.ps1')
$Core = Join-Path $ProjectRoot 'tests\core'
$Gameplay = Join-Path $ProjectRoot 'tests\gameplay'
$UI = Join-Path $ProjectRoot 'tests\ui'
$Essential = Join-Path $ProjectRoot 'tests\essential'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')
$script:ScTestJvmStarts = 0
$prepared = $false
$compilation = $null
$tools = Join-Path ([IO.Path]::GetTempPath()) ('sc-essential-' + [guid]::NewGuid().ToString('N'))
$logs = Join-Path $ProjectRoot ('build\test-results\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $tools, $logs -Force | Out-Null
$jar = Join-Path $GameRoot 'projectzomboid.jar'
$java = Join-Path $GameRoot 'jre64\bin\java.exe'
$nativeClasses = Join-Path $ProjectRoot 'build\native-bridge\classes'
$nativeJar = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
$payloadJar = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\java\SurvivorCompanionBridge.jar'
$hostPath = Get-ScPowerShellHost
$native = @{
    Build = @('SCNativeApiSignatureTest', 'SCBridgeLuaNumberContractTest', 'SCNativeBridgeExposureTest')
    Lifecycle = @('SCIsoPlayerControlTest', 'SCIsoCompanionControlTest',
        'SCBootstrapLifecycleTest', 'SCLightingSlotRetirementTest', 'SCLightingSlotLifecycleTest',
        'SCNativeCleanupTransactionTest', 'SCRemoteArrivalTest', 'SCVehicleSaveBarrierTest')
    Behaviour = @('SCCompanionFatigueTest', 'SCCompanionComfortTest')
    Cargo = @('SCMovementClearanceTest', 'SCCompanionDrivingTest', 'SCRoadFollowerTest')
    Interface = @('SCTerminalLogoRendererTest')
}
$stubTests = @('SCBootstrapLifecycleTest', 'SCCompanionFatigueTest', 'SCCompanionComfortTest',
    'SCMovementClearanceTest', 'SCCompanionDrivingTest', 'SCRoadFollowerTest', 'SCTerminalLogoRendererTest')
$plainTests = @('SCNativeApiSignatureTest', 'SCBridgeLuaNumberContractTest')

function Invoke-EssentialScript([string]$Label, [string]$Path, [string[]]$ScriptArgs = @()) {
    Invoke-ScTestCommand -FilePath $hostPath -Arguments (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $ScriptArgs) `
        -LogPath (Join-Path $logs "$Label.log") -WorkingDirectory $ProjectRoot
}
function Initialize-EssentialTools {
    if ($script:prepared) { return }
    # Missing or different native runtimes are prerequisite failures, never skips.
    Invoke-EssentialScript 'runtime' (Join-Path $PSScriptRoot 'Test-PzRuntime.ps1') @('-GameRoot', $GameRoot)
    Invoke-EssentialScript 'native-build' (Join-Path $PSScriptRoot 'Build-NativeBridge.ps1') @('-ProjectRoot', $ProjectRoot)
    if ((Get-FileHash -LiteralPath $nativeJar -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $payloadJar -Algorithm SHA256).Hash) {
        throw 'The committed bridge differs from the reproducible native build.'
    }
    $javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
    $sources = @((Join-Path $Gameplay 'KahluaTestRunner.java'), (Join-Path $UI 'ReflectLuaCompiler.java'))
    foreach ($name in @($selected | ForEach-Object { $native[$_] } | Select-Object -Unique)) {
        if ($plainTests -contains $name) { $sources += Join-Path $Core "$name.java" }
        else { $sources += Join-Path $ProjectRoot "bridge\src\test\java\survivorcompanion\bridge\$name.java" }
    }
    Invoke-ScTestCommand -FilePath $javac -Arguments (@('-cp', $nativeClasses, '-d', $tools) + $sources) `
        -LogPath (Join-Path $logs 'tools.log') -WorkingDirectory $ProjectRoot
    $script:prepared = $true
}
function Invoke-EssentialNative([string]$Domain) {
    foreach ($name in $native[$Domain]) {
        $class = if ($plainTests -contains $name) { $name } else { "survivorcompanion.bridge.$name" }
        $classpath = if ($stubTests -contains $name) { "$tools;$nativeClasses" } else { "$tools;$nativeJar;$jar" }
        $arguments = @('-cp', $classpath, $class)
        if ($name -eq 'SCBootstrapLifecycleTest') { $arguments += @('--agent-jar', $nativeJar) }
        Invoke-ScTestCommand -FilePath $java -Arguments $arguments `
            -LogPath (Join-Path $logs "$Domain-$name.log") -WorkingDirectory $GameRoot
    }
}
function Invoke-EssentialLua([string]$Domain) {
    $groups = @(. (Join-Path $Essential "$Domain.ps1"))
    if ($groups.Count -eq 0) { throw "$Domain has no production scenario groups." }
    $lines = foreach ($group in $groups) {
        if (-not $group.Name -or -not $group.Files) { throw "Invalid $Domain source group." }
        "--group $($group.Name)"
        foreach ($file in $group.Files) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing $Domain source: $file" }
            [IO.Path]::GetFullPath($file)
        }
    }
    $list = Join-Path $tools "$Domain.groups"
    [IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    Invoke-ScTestCommand -FilePath $java -Arguments @('-cp', "$tools;$jar", 'KahluaTestRunner', '--groups', $list) `
        -LogPath (Join-Path $logs "$Domain-lua.log") -WorkingDirectory $GameRoot
}
function Invoke-EssentialBuild {
    Invoke-EssentialScript 'source' (Join-Path $PSScriptRoot 'Test-Source.ps1') @('-Scope', 'Metadata')
    $lua = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua') `
        -Recurse -File -Filter '*.lua' | Sort-Object FullName | ForEach-Object FullName)
    $inputKey = Get-ScLuaCompilationKey $ProjectRoot $GameRoot
    Invoke-ScTestCommand -FilePath $java -Arguments (@('-cp', "$tools;$jar", 'ReflectLuaCompiler') + $lua) `
        -LogPath (Join-Path $logs 'lua-normal.log') -WorkingDirectory $GameRoot
    Invoke-ScTestCommand -FilePath $java -Arguments (@('-cp', "$tools;$jar", 'ReflectLuaCompiler', '--debug-compile') + $lua) `
        -LogPath (Join-Path $logs 'lua-debug.log') -WorkingDirectory $GameRoot
    if ($inputKey -ne (Get-ScLuaCompilationKey $ProjectRoot $GameRoot)) {
        throw 'Compilation inputs changed during the run; no package receipt was issued.'
    }
    $script:compilation = @{ Key = $inputKey; Normal = $true; Debug = $true }
    Invoke-EssentialNative 'Build'
    if ($Release) {
        Invoke-EssentialScript 'installer' (Join-Path $Core 'test_installer.ps1') @(
            '-ProjectRoot', $ProjectRoot, '-Essential', '-Jobs', '1', '-PrebuiltBridgeJar', $nativeJar)
        # Same process: the compilation receipt is a per-run object, not an
        # unchecked skip flag. Each builder rechecks the exact input hashes.
        & (Join-Path $PSScriptRoot 'Build-Workshop.ps1') -ProjectRoot $ProjectRoot -GameRoot $GameRoot `
            -SkipNativeBridge -VerifiedCompilation $script:compilation *> (Join-Path $logs 'workshop.log')
        & (Join-Path $PSScriptRoot 'Build-Standalone.ps1') -ProjectRoot $ProjectRoot -GameRoot $GameRoot `
            -SkipNativeBridge -VerifiedCompilation $script:compilation *> (Join-Path $logs 'standalone.log')
    }
}

$timer = [Diagnostics.Stopwatch]::StartNew()
$results = @()
$currentProcess = [Diagnostics.Process]::GetCurrentProcess()
$previousPriority = $currentProcess.PriorityClass
$oldJava = $env:JAVA_TOOL_OPTIONS
$oldJdk = $env:JDK_JAVA_OPTIONS
$oldJobs = $env:SC_TEST_JOBS
$env:JAVA_TOOL_OPTIONS = '-Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC'
$env:JDK_JAVA_OPTIONS = $env:JAVA_TOOL_OPTIONS
$env:SC_TEST_JOBS = '1'
try {
    try { $currentProcess.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
    Write-Output 'Essential checks: serial, Java heap 256 MB, two processors; live game not launched.'
    foreach ($name in $order) {
        if ($selected -notcontains $name) { $results += @{ Check = $name; Status = 'not run'; Seconds = 0 }; continue }
        $step = [Diagnostics.Stopwatch]::StartNew()
        try {
            Initialize-EssentialTools
            if ($name -eq 'Build') { Invoke-EssentialBuild }
            else {
                if ($name -eq 'Interface') {
                    Invoke-EssentialScript 'content' (Join-Path $PSScriptRoot 'Test-Source.ps1') @('-Scope', 'Content')
                }
                Invoke-EssentialNative $name
                Invoke-EssentialLua $name
            }
            $results += @{ Check = $name; Status = 'passed'; Seconds = $step.Elapsed.TotalSeconds }
            Write-Output ("{0}: PASS ({1:N1}s)" -f $name, $step.Elapsed.TotalSeconds)
        } catch {
            $results += @{ Check = $name; Status = 'failed'; Seconds = $step.Elapsed.TotalSeconds; Error = $_.Exception.Message }
            Write-Output ("{0}: FAIL ({1:N1}s)`n{2}" -f $name, $step.Elapsed.TotalSeconds, $_.Exception.Message)
            if (-not $script:prepared -or $name -eq 'Build') {
                foreach ($remaining in $order | Where-Object { $results.Check -notcontains $_ }) {
                    $results += @{ Check = $remaining; Status = 'not run'; Seconds = 0 }
                }
                break
            }
        }
    }
} finally {
    $timer.Stop()
    $env:JAVA_TOOL_OPTIONS = $oldJava
    $env:JDK_JAVA_OPTIONS = $oldJdk
    $env:SC_TEST_JOBS = $oldJobs
    try { $currentProcess.PriorityClass = $previousPriority } catch { }
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not ([IO.Path]::GetFullPath($tools)).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test scratch cleanup: $tools"
    }
    Remove-Item -LiteralPath $tools -Recurse -Force
}
$summary = @{ Profile = $(if ($Release) { 'release' } else { 'routine' }); Checks = $results;
    Seconds = $timer.Elapsed.TotalSeconds; DirectJvmStarts = $script:ScTestJvmStarts; Live = 'not run' }
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logs 'summary.json') -Encoding utf8
Write-Output ("Elapsed {0:N1}s; direct JVM launches {1}; evidence {2}" -f $timer.Elapsed.TotalSeconds, $script:ScTestJvmStarts, $logs)
if (@($results | Where-Object { $_.Status -eq 'failed' }).Count -gt 0) { throw 'Essential checks failed.' }
if ($selected.Count -eq 5) {
    Write-Output ("PROJECT_TEST_PASS checks=5 profile={0} live=false" -f $summary.Profile)
} else {
    Write-Output ("FOCUSED_TEST_PASS checks={0}/5 full-project=false live=false" -f $selected.Count)
}
