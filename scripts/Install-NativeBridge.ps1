# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge'),
    [string]$ConfigBackupRoot,
    [string]$PrebuiltBridgeJar = ''
)

$ErrorActionPreference = 'Stop'
$Owner = 'SurvivorCompanion.NativeBridge'
$WrapperMain = 'survivorcompanion/bridge/SCLauncher'
$OriginalMain = 'zombie/gameStates/MainScreenState'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$BridgeRoot = [System.IO.Path]::GetFullPath($BridgeRoot)
$gameExecutable = Join-Path $GameRoot 'ProjectZomboid64.exe'
if ((Test-Path -LiteralPath $gameExecutable -PathType Leaf) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before installing the native companion bridge.'
}
$configPath = Join-Path $GameRoot 'ProjectZomboid64.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "ProjectZomboid64.json was not found at $configPath"
}
if ([string]::IsNullOrWhiteSpace($ConfigBackupRoot)) {
    $ConfigBackupRoot = Join-Path $ProjectRoot 'build\game-config-backups'
}
$ConfigBackupRoot = [System.IO.Path]::GetFullPath($ConfigBackupRoot)
New-Item -ItemType Directory -Path $BridgeRoot, $ConfigBackupRoot -Force | Out-Null

$manifestPath = Join-Path $BridgeRoot 'install-manifest.json'
$existingManifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $existingManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($existingManifest.owner -ne $Owner) {
        throw "Refusing to update a native bridge owned by $($existingManifest.owner)"
    }
}

$configText = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
$config = $configText | ConvertFrom-Json
if ($config.mainClass -ne $OriginalMain -and $config.mainClass -ne $WrapperMain) {
    throw "Refusing to replace an unknown Project Zomboid mainClass: $($config.mainClass)"
}
if ($null -eq $config.classpath) { throw 'ProjectZomboid64.json has no classpath array.' }

$buildOutput = $null
if ([string]::IsNullOrWhiteSpace($PrebuiltBridgeJar)) {
    $builder = Join-Path $ProjectRoot 'scripts\Build-NativeBridge.ps1'
    $buildOutput = & $builder -ProjectRoot $ProjectRoot -InstallIntoPayload
    $builtJar = Join-Path $ProjectRoot 'build\native-bridge\SurvivorCompanionBridge.jar'
    if (-not (Test-Path -LiteralPath $builtJar -PathType Leaf)) {
        throw 'Native bridge build did not produce the expected JAR.'
    }
} else {
    $builtJar = [System.IO.Path]::GetFullPath($PrebuiltBridgeJar)
    if (-not (Test-Path -LiteralPath $builtJar -PathType Leaf)) {
        throw "Prebuilt native bridge JAR was not found: $builtJar"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($builtJar)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($required in @(
            'survivorcompanion/bridge/SCNativeCompanion.class',
            'survivorcompanion/bridge/SCBridge.class',
            'survivorcompanion/bridge/SCBootstrap.class',
            'survivorcompanion/bridge/SCLauncher.class',
            'survivorcompanion/bridge/Main.class'
        )) {
            if ($entryNames -notcontains $required) {
                throw "Prebuilt native bridge JAR is missing $required"
            }
        }
        if ($entryNames | Where-Object { $_ -match '^zombie/' }) {
            throw 'Prebuilt native bridge JAR contains forbidden Project Zomboid classes.'
        }
    }
    finally {
        $archive.Dispose()
    }
    $buildOutput = "NATIVE_BRIDGE_PREBUILT_PASS jar=$builtJar sha256=$((Get-FileHash -LiteralPath $builtJar -Algorithm SHA256).Hash.ToLowerInvariant())"
}
$targetJar = Join-Path $BridgeRoot 'SurvivorCompanionBridge.jar'
$targetJarArgument = $targetJar.Replace('\', '/')

$backupPath = if ($existingManifest -and $existingManifest.originalConfigBackup) {
    [string]$existingManifest.originalConfigBackup
} else {
    $suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N')).Substring(0, 8)
    Join-Path $ConfigBackupRoot ("ProjectZomboid64.before-SurvivorCompanion.$suffix.json")
}
if (-not $existingManifest) {
    Copy-Item -LiteralPath $configPath -Destination $backupPath
}

$originalMainClass = if ($existingManifest) {
    [string]$existingManifest.originalMainClass
} else { [string]$config.mainClass }
$originalClasspath = if ($existingManifest) {
    @($existingManifest.originalClasspath)
} else { @($config.classpath) }

$newClasspath = @($config.classpath | Where-Object {
    -not ([string]$_).Equals($targetJarArgument, [System.StringComparison]::OrdinalIgnoreCase)
})
$newClasspath += $targetJarArgument
$config.mainClass = $WrapperMain
$config.classpath = @($newClasspath)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$configTemp = Join-Path $GameRoot ('.ProjectZomboid64.sc.' + [guid]::NewGuid().ToString('N') + '.json')
$jarTemp = Join-Path $BridgeRoot ('.SurvivorCompanionBridge.' + [guid]::NewGuid().ToString('N') + '.jar')
$configChanged = $false
try {
    Copy-Item -LiteralPath $builtJar -Destination $jarTemp
    [System.IO.File]::WriteAllText($configTemp, ($config | ConvertTo-Json -Depth 12), $utf8NoBom)
    Get-Content -LiteralPath $configTemp -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
    Move-Item -LiteralPath $configTemp -Destination $configPath -Force
    $configChanged = $true
    Move-Item -LiteralPath $jarTemp -Destination $targetJar -Force

    $manifest = [ordered]@{
        owner = $Owner
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        projectRoot = $ProjectRoot
        gameRoot = $GameRoot
        gameConfig = $configPath
        bridgeJar = $targetJar
        bridgeSha256 = (Get-FileHash -LiteralPath $targetJar -Algorithm SHA256).Hash.ToLowerInvariant()
        wrapperMainClass = $WrapperMain
        originalMainClass = $originalMainClass
        originalClasspath = @($originalClasspath)
        originalConfigBackup = $backupPath
    }
    [System.IO.File]::WriteAllText($manifestPath,
        ($manifest | ConvertTo-Json -Depth 12), $utf8NoBom)
}
catch {
    if ($configChanged) {
        [System.IO.File]::WriteAllText($configPath, $configText, $utf8NoBom)
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $configTemp) { Remove-Item -LiteralPath $configTemp -Force }
    if (Test-Path -LiteralPath $jarTemp) { Remove-Item -LiteralPath $jarTemp -Force }
}

Write-Output "NATIVE_BRIDGE_INSTALL_PASS config=$configPath jar=$targetJar backup=$backupPath"
Write-Output $buildOutput
