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
$buildRoot = Join-Path $ProjectRoot 'build'
$buildPrefix = [System.IO.Path]::GetFullPath($buildRoot).TrimEnd('\') + '\'
if (-not $OutputRoot.StartsWith($buildPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Standalone output must stay inside the project build directory: $OutputRoot"
}
$version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION.txt') -Raw -Encoding utf8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid release version: $version" }

$stageRoot = Join-Path $buildRoot 'standalone-release-stage'
$validationRoot = Join-Path $buildRoot 'standalone-release-validation'
foreach ($path in @($stageRoot, $validationRoot)) {
    if (Test-Path -LiteralPath $path) {
        $resolved = [System.IO.Path]::GetFullPath($path)
        if (-not $resolved.StartsWith($buildPrefix,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean unexpected path: $resolved"
        }
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}

New-Item -ItemType Directory -Path $stageRoot, $OutputRoot -Force | Out-Null
& (Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1') `
    -ProjectRoot $ProjectRoot -InstallIntoPayload | Out-Null
& (Join-Path $ProjectRoot 'scripts\New-StandalonePayload.ps1') `
    -ProjectRoot $ProjectRoot -OutputRoot $stageRoot | Out-Null

foreach ($file in @('VERSION.txt', 'LICENSE', 'README.md', 'Install.bat', 'Uninstall.bat')) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $file) -Destination $stageRoot
}
$assetRoot = Join-Path $stageRoot 'assets'
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'assets\preview-512.png') `
    -Destination $assetRoot
$scriptsRoot = Join-Path $stageRoot 'scripts'
New-Item -ItemType Directory -Path $scriptsRoot -Force | Out-Null
foreach ($script in @(
        'Install-Standalone.ps1',
        'New-StandalonePayload.ps1',
        'Install-Local.ps1',
        'Install-NativeBridge.ps1',
        'Uninstall-Standalone.ps1',
        'Uninstall-Local.ps1',
        'Uninstall-NativeBridge.ps1')) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "scripts\$script") -Destination $scriptsRoot
}

$payload = Join-Path $stageRoot 'SurvivorCompanion'
$metadata = Get-Content -LiteralPath (Join-Path $payload '42\mod.info') -Raw -Encoding utf8
if (($metadata -match '(?m)^require=\\ZombieBuddy$') -or
    ($metadata -match '(?m)^ZBVersionMin=')) {
    throw 'Standalone archive retained its Workshop-only dependency.'
}
$config = Get-Content -LiteralPath `
    (Join-Path $payload '42\media\lua\shared\SCConfig.lua') -Raw -Encoding utf8
foreach ($required in @(
        'experimentalNpcPlayerActor = false,',
        'debugSpawnEnabled = false,',
        'movementRecorderEnabled = false,')) {
    if ($config -notmatch [regex]::Escape($required)) {
        throw "Standalone archive changed a public configuration gate: $required"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $payload 'STANDALONE-NATIVE-BRIDGE.txt') -PathType Leaf)) {
    throw 'Standalone archive is missing its bridge marker.'
}
if (-not (Test-Path -LiteralPath (Join-Path $stageRoot 'assets\preview-512.png') -PathType Leaf)) {
    throw 'Standalone archive is missing the README banner.'
}
if (Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Filter '*.class') {
    throw 'Standalone archive contains forbidden loose Java classes.'
}
$jars = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Filter '*.jar')
if ($jars.Count -ne 1 -or $jars[0].Name -ne 'SurvivorCompanionBridge.jar') {
    throw 'Standalone archive must contain exactly one owned bridge JAR.'
}

# Exercise the exact staged scripts against an isolated fake game and cache.
$gameRoot = Join-Path $validationRoot 'game'
$modsRoot = Join-Path $validationRoot 'mods'
$dataRoot = Join-Path $validationRoot 'install-data'
New-Item -ItemType Directory -Path $gameRoot, $modsRoot -Force | Out-Null
$originalConfig = [ordered]@{
    mainClass = 'zombie/gameStates/MainScreenState'
    classpath = @('.', 'projectzomboid.jar')
    vmArgs = @('-Xmx1024m')
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $gameRoot 'ProjectZomboid64.json'),
    $originalConfig, (New-Object System.Text.UTF8Encoding($false)))
& (Join-Path $stageRoot 'scripts\Install-Standalone.ps1') `
    -ProjectRoot $stageRoot -GameRoot $gameRoot -ModsRoot $modsRoot `
    -InstallDataRoot $dataRoot | Out-Null
# Exercise an actual update so the staged uninstaller must unwind a managed
# backup chain rather than only the newest payload.
& (Join-Path $stageRoot 'scripts\Install-Standalone.ps1') `
    -ProjectRoot $stageRoot -GameRoot $gameRoot -ModsRoot $modsRoot `
    -InstallDataRoot $dataRoot | Out-Null
$installed = Join-Path $modsRoot 'SurvivorCompanion'
$manifestPath = Join-Path $installed '.sc-install-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Standalone staged installer did not create an owned installation.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($manifest.version -ne "${version}-standalone-native") {
    throw "Standalone install manifest has the wrong version: $($manifest.version)"
}
$patched = Get-Content -LiteralPath (Join-Path $gameRoot 'ProjectZomboid64.json') `
    -Raw -Encoding utf8 | ConvertFrom-Json
if ($patched.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'Standalone staged installer did not activate the native launcher.'
}
& (Join-Path $stageRoot 'scripts\Uninstall-Standalone.ps1') `
    -ProjectRoot $stageRoot -ModsRoot $modsRoot -InstallDataRoot $dataRoot | Out-Null
$restored = Get-Content -LiteralPath (Join-Path $gameRoot 'ProjectZomboid64.json') `
    -Raw -Encoding utf8 | ConvertFrom-Json
if (($restored.mainClass -ne 'zombie/gameStates/MainScreenState') -or
    (Test-Path -LiteralPath $installed)) {
    throw 'Standalone staged uninstaller did not restore the isolated fixture.'
}
$remainingBackups = @(Get-ChildItem -LiteralPath (Join-Path $dataRoot 'mod-backups') `
    -Directory -ErrorAction SilentlyContinue)
if ($remainingBackups.Count -ne 0 -or
    (Test-Path -LiteralPath (Join-Path $dataRoot 'bridge\install-manifest.json') -PathType Leaf)) {
    throw 'Standalone staged uninstaller left a managed update generation or active bridge manifest.'
}

$zipName = "LivingFellowsCompanion-$version-STANDALONE-WINDOWS.zip"
$zipPath = Join-Path $OutputRoot $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath `
    -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$zipPath.sha256.txt"
[System.IO.File]::WriteAllText($hashPath, "$zipHash  $zipName`r`n",
    (New-Object System.Text.UTF8Encoding($false)))

Write-Output "STANDALONE_PACKAGE_PASS version=$version installer=true uninstaller=true debug=false dependency=false sha256=$zipHash"
Write-Output $zipPath
