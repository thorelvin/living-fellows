# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$BridgeRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LivingFellowsDev\NativeBridge')
)

$ErrorActionPreference = 'Stop'
$Owner = 'SurvivorCompanion.NativeBridge'
$BridgeRoot = [System.IO.Path]::GetFullPath($BridgeRoot)
$manifestPath = Join-Path $BridgeRoot 'install-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "No owned native bridge manifest was found at $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($manifest.owner -ne $Owner) { throw "Refusing to remove bridge owned by $($manifest.owner)" }

$configPath = [System.IO.Path]::GetFullPath([string]$manifest.gameConfig)
$gameExecutable = Join-Path (Split-Path -Parent $configPath) 'ProjectZomboid64.exe'
if ((Test-Path -LiteralPath $gameExecutable -PathType Leaf) -and
    (Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue)) {
    throw 'Close Project Zomboid before uninstalling the native companion bridge.'
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Project Zomboid launcher configuration is missing: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
$wrapper = [string]$manifest.wrapperMainClass
if ($config.mainClass -ne $wrapper) {
    throw "Launcher mainClass changed after installation; refusing automatic rollback: $($config.mainClass)"
}
$bridgeJarArgument = ([string]$manifest.bridgeJar).Replace('\', '/')
$config.mainClass = [string]$manifest.originalMainClass
$config.classpath = @($config.classpath | Where-Object {
    -not ([string]$_).Equals($bridgeJarArgument, [System.StringComparison]::OrdinalIgnoreCase)
})
foreach ($entry in @($manifest.originalClasspath)) {
    if (@($config.classpath) -notcontains $entry) { $config.classpath += $entry }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$temp = Join-Path (Split-Path -Parent $configPath) `
    ('.ProjectZomboid64.sc-uninstall.' + [guid]::NewGuid().ToString('N') + '.json')
try {
    [System.IO.File]::WriteAllText($temp, ($config | ConvertTo-Json -Depth 12), $utf8NoBom)
    Get-Content -LiteralPath $temp -Raw -Encoding utf8 | ConvertFrom-Json | Out-Null
    Move-Item -LiteralPath $temp -Destination $configPath -Force
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}

$disabledManifest = Join-Path $BridgeRoot `
    ('install-manifest.uninstalled.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
Move-Item -LiteralPath $manifestPath -Destination $disabledManifest
Write-Output "NATIVE_BRIDGE_UNINSTALL_PASS config=$configPath retainedJar=$($manifest.bridgeJar)"
