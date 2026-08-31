# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = '',
    [switch]$InstallIntoPayload
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\native-bridge'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build'))
$buildPrefix = $buildRoot.TrimEnd('\') + '\'
if (-not $OutputRoot.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Native bridge output must stay inside the project build directory: $OutputRoot"
}

$javacCandidates = @(
    'C:\Program Files\Java\jdk-24\bin\javac.exe',
    'C:\Program Files\Java\jdk-17\bin\javac.exe'
)
$javac = $javacCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $javac) {
    $command = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($command) { $javac = $command.Source }
}
if (-not $javac) { throw 'A Java 17+ JDK with javac.exe is required to build the native bridge.' }
$jar = Join-Path (Split-Path -Parent $javac) 'jar.exe'
if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) { throw "jar.exe was not found beside $javac" }

$classes = Join-Path $OutputRoot 'classes'
if (Test-Path -LiteralPath $OutputRoot) {
    $resolved = [System.IO.Path]::GetFullPath($OutputRoot)
    if (-not $resolved.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected native output: $resolved"
    }
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $classes -Force | Out-Null

$stubs = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'bridge\api-stubs') `
    -Filter '*.java' -File -Recurse | Select-Object -ExpandProperty FullName
$sources = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'bridge\src\main\java') `
    -Filter '*.java' -File -Recurse | Select-Object -ExpandProperty FullName
if (-not $sources) { throw 'Native bridge sources were not found.' }

& $javac -encoding UTF-8 -d $classes @stubs @sources
if ($LASTEXITCODE -ne 0) { throw "Native bridge compilation failed with exit code $LASTEXITCODE" }

$bridgeJar = Join-Path $OutputRoot 'SurvivorCompanionBridge.jar'
$manifest = Join-Path $ProjectRoot 'bridge\native\MANIFEST.MF'
# Pin archive timestamps so rebuilding the same Java sources produces the same
# bridge bytes for source, Workshop staging, the release ZIP, and local install.
& $jar --create --file $bridgeJar --manifest $manifest `
    --date=2025-01-01T00:00:00Z -C $classes survivorcompanion
if ($LASTEXITCODE -ne 0) { throw "Native bridge JAR creation failed with exit code $LASTEXITCODE" }

$entries = & $jar tf $bridgeJar
if ($LASTEXITCODE -ne 0) { throw 'Native bridge JAR could not be inspected.' }
if ($entries | Where-Object { $_ -match '^zombie/' }) {
    throw 'Compile-only Project Zomboid stubs leaked into the native bridge JAR.'
}
foreach ($required in @(
    'survivorcompanion/bridge/SCNativeCompanion.class',
    'survivorcompanion/bridge/SCBridge.class',
    'survivorcompanion/bridge/SCBootstrap.class',
    'survivorcompanion/bridge/SCLauncher.class',
    'survivorcompanion/bridge/Main.class'
)) {
    if ($entries -notcontains $required) { throw "Native bridge JAR is missing $required" }
}

if ($InstallIntoPayload) {
    $payloadJava = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\java'
    New-Item -ItemType Directory -Path $payloadJava -Force | Out-Null
    Copy-Item -LiteralPath $bridgeJar -Destination (Join-Path $payloadJava 'SurvivorCompanionBridge.jar') -Force
}

$hash = (Get-FileHash -LiteralPath $bridgeJar -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "NATIVE_BRIDGE_BUILD_PASS jar=$bridgeJar sha256=$hash classes=$($sources.Count)"
Write-Output $bridgeJar
