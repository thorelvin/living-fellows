<#
.SYNOPSIS
    Runs every PZ Radio Link test.

.DESCRIPTION
    Three gates:
      1. Kahlua compile   -- every mod .lua must compile in the game's own VM.
      2. Kahlua behaviour -- the codec harness runs inside that VM and asserts,
                             among other things, that its framing and checksum
                             match the Python host byte for byte.
      3. Host end-to-end  -- the real HTTP server over a temporary mailbox.

    Gates 1 and 2 need a local game install for projectzomboid.jar and stdlib.lua.
    Gate 3 needs only Python.

.PARAMETER GameRoot
    Project Zomboid install folder.
#>
[CmdletBinding()]
param(
    [string] $GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string] $JdkBin = 'C:\ZOMBOID\tools\temurin-25\jdk-25.0.4.1+1\bin',
    [string] $QrVenvPython = 'C:\ZOMBOID\pz-radio-link\.qrvenv\Scripts\python.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tests = Join-Path $root 'tests'
$luaDir = Join-Path $root 'mod\PZRadioLink\42\media\lua\client\PZRL'
$failed = $false

function Write-Section($text) {
    Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan
}

$jar = Join-Path $GameRoot 'projectzomboid.jar'
$haveGame = (Test-Path $jar) -and (Test-Path (Join-Path $GameRoot 'stdlib.lua'))

if (-not $haveGame) {
    Write-Host "Game install not found at $GameRoot - skipping the Kahlua gates." -ForegroundColor Yellow
} else {
    Write-Section 'Kahlua compile gate'
    $javac = Join-Path $JdkBin 'javac.exe'
    $java = Join-Path $JdkBin 'java.exe'
    & $javac -cp $jar -d $tests (Join-Path $tests 'ReflectLuaCompiler.java')
    if ($LASTEXITCODE -ne 0) { throw 'ReflectLuaCompiler failed to build' }

    $luaFiles = Get-ChildItem -Path $luaDir -Filter *.lua | ForEach-Object { $_.FullName }
    Push-Location $GameRoot
    try {
        & $java -cp "$tests;$jar" ReflectLuaCompiler @luaFiles
        if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'COMPILE GATE FAILED' -ForegroundColor Red }

        Write-Section 'Kahlua behaviour gate'
        & $java -cp "$tests;$jar" ReflectLuaCompiler --run `
            (Join-Path $luaDir 'PZRL_Codec.lua') (Join-Path $luaDir 'PZRL_Device.lua') `
            (Join-Path $tests 'codec_harness.lua')
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Host 'CODEC HARNESS FAILED' -ForegroundColor Red
        } else {
            Write-Host 'codec harness passed (it raises on any failed check)'
        }
    } finally {
        Pop-Location
    }
}

Write-Section 'Host end-to-end gate'
& python (Join-Path $tests 'test_host.py')
if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'HOST GATE FAILED' -ForegroundColor Red }

Write-Section 'Page structure gate'
& python (Join-Path $tests 'test_page.py')
if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host 'PAGE GATE FAILED' -ForegroundColor Red }

Write-Section 'QR encoder gate'
# Needs `segno` as a reference oracle. It is a development-time dependency only
# and is deliberately not required to run the host, so exit code 2 means
# "inconclusive" rather than "passed".
$qrPython = $QrVenvPython
if (-not (Test-Path $qrPython)) { $qrPython = 'python' }
& $qrPython (Join-Path $tests 'test_qr.py')
switch ($LASTEXITCODE) {
    0 { Write-Host 'QR encoder verified against the reference.' }
    2 {
        Write-Host 'QR gate INCONCLUSIVE - segno not installed. Set up the oracle with:' -ForegroundColor Yellow
        Write-Host '  python -m venv .qrvenv; .qrvenv\Scripts\pip install segno' -ForegroundColor Yellow
        Write-Host '  then re-run with -QrVenvPython .qrvenv\Scripts\python.exe' -ForegroundColor Yellow
    }
    default { $failed = $true; Write-Host 'QR GATE FAILED' -ForegroundColor Red }
}

Write-Host ''
if ($failed) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}
Write-Host 'All gates passed.' -ForegroundColor Green
