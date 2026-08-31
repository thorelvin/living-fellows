# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot 'build\release'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION.txt') -Raw -Encoding utf8).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid release version: $Version" }

$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build'))
$buildPrefix = $buildRoot.TrimEnd('\') + '\'
if (-not $OutputRoot.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Offline output must stay inside the project build directory: $OutputRoot"
}
$stageRoot = Join-Path $buildRoot 'offline-playtest-stage'
$validationRoot = Join-Path $buildRoot 'offline-playtest-validation'
foreach ($path in @($stageRoot, $validationRoot)) {
    if (Test-Path -LiteralPath $path) {
        $resolved = [System.IO.Path]::GetFullPath($path)
        if (-not $resolved.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected path: $resolved"
        }
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $stageRoot, $OutputRoot -Force | Out-Null
& (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null
& (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
    -ProjectRoot $ProjectRoot -OutputRoot $stageRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $ProjectRoot 'VERSION.txt') -Destination $stageRoot
Copy-Item -Path (Join-Path $ProjectRoot 'offline-playtest\*') -Destination $stageRoot -Recurse
$toolsRoot = Join-Path $stageRoot 'tools'
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
foreach ($script in @(
    'Install-Local.ps1',
    'Install-NativeBridge.ps1',
    'Uninstall-Local.ps1',
    'Uninstall-NativeBridge.ps1')) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "scripts\$script") -Destination $toolsRoot
}

$payload = Join-Path $stageRoot 'SurvivorCompanion'
foreach ($metadataPath in @((Join-Path $payload 'mod.info'), (Join-Path $payload '42\mod.info'))) {
    $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding utf8
    if (($metadata -match '(?m)^require=\\ZombieBuddy$') -or ($metadata -match '(?m)^ZBVersionMin=')) {
        throw "Offline package retained a Workshop-only dependency: $metadataPath"
    }
}
$jars = @(Get-ChildItem -LiteralPath $payload -Recurse -File -Filter '*.jar')
if ($jars.Count -ne 1 -or $jars[0].Name -ne 'SurvivorCompanionBridge.jar') {
    throw 'Offline package must contain exactly one owned native bridge JAR.'
}
if (Get-ChildItem -LiteralPath $payload -Recurse -File -Filter '*.class') {
    throw 'Offline package contains forbidden loose Java classes.'
}

$manifestPath = Join-Path $stageRoot 'PACKAGE-MANIFEST-SHA256.txt'
$stagePrefix = $stageRoot.TrimEnd('\') + '\'
$manifestLines = Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object {
    $_.FullName -ne $manifestPath
} | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($stagePrefix.Length).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
}
[System.IO.File]::WriteAllLines($manifestPath, $manifestLines, (New-Object System.Text.UTF8Encoding($false)))

# Exercise the exact staged installer against an isolated fake game and cache.
$gameRoot = Join-Path $validationRoot 'game'
$modsRoot = Join-Path $validationRoot 'mods'
$dataRoot = Join-Path $validationRoot 'install-data'
New-Item -ItemType Directory -Path $gameRoot, $modsRoot -Force | Out-Null
$originalConfig = [ordered]@{
    mainClass = 'zombie/gameStates/MainScreenState'
    classpath = @('.', 'projectzomboid.jar')
    vmArgs = @('-Xmx1024m')
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $gameRoot 'ProjectZomboid64.json'), $originalConfig,
    (New-Object System.Text.UTF8Encoding($false)))
& (Join-Path $stageRoot 'Install.ps1') -GameRoot $gameRoot -ModsRoot $modsRoot -InstallDataRoot $dataRoot | Out-Null
$installed = Join-Path $modsRoot 'SurvivorCompanion'
if (-not (Test-Path -LiteralPath (Join-Path $installed '.sc-install-manifest.json') -PathType Leaf)) {
    throw 'Offline staged installer did not install an owned mod payload.'
}
$patched = Get-Content -LiteralPath (Join-Path $gameRoot 'ProjectZomboid64.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($patched.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'Offline staged installer did not activate the native launcher.'
}
& (Join-Path $stageRoot 'Uninstall.ps1') -ModsRoot $modsRoot -InstallDataRoot $dataRoot | Out-Null
$restored = Get-Content -LiteralPath (Join-Path $gameRoot 'ProjectZomboid64.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($restored.mainClass -ne 'zombie/gameStates/MainScreenState' -or (Test-Path -LiteralPath $installed)) {
    throw 'Offline staged uninstaller did not restore the isolated fixture.'
}

$zipName = "LivingFellowsCompanion-$Version-OFFLINE-PLAYTEST.zip"
$zipPath = Join-Path $OutputRoot $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$zipPath.sha256.txt"
[System.IO.File]::WriteAllText($hashPath, "$zipHash  $zipName`r`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Output "OFFLINE_PLAYTEST_PACKAGE_PASS version=$Version zip=$zipPath sha256=$zipHash installer=true uninstaller=true workshopDependency=false"
Write-Output $zipPath
