# SPDX-License-Identifier: MIT
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$BuildRoot = Join-Path ([IO.Path]::GetTempPath()) ('sc-seat-route-' + [guid]::NewGuid().ToString('N'))
$Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
$Files = @(
    (Join-Path $Shared 'SCNamespace.lua'), (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $PSScriptRoot 'reading_session_fixture.lua'),
    (Join-Path $Client 'SCActionSupervisor.lua'), (Join-Path $Client 'SCDowntime.lua'),
    (Join-Path $PSScriptRoot 'downtime_seat_route_harness.lua'),
    (Join-Path $PSScriptRoot 'follower_sitting_harness.lua')
)
New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $PSScriptRoot 'KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Seat-route runner compilation failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp "$BuildRoot;$(Join-Path $GameRoot 'projectzomboid.jar')" KahluaTestRunner @Files
        if ($LASTEXITCODE -ne 0) { throw 'Downtime seat-route regression failed.' }
    } finally { Pop-Location }
} finally {
    if ((Split-Path -Parent $BuildRoot) -eq [IO.Path]::GetTempPath().TrimEnd('\')) {
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
