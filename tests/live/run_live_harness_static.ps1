# SPDX-License-Identifier: MIT

param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-live-harness-static-' + [guid]::NewGuid().ToString('N'))
$Compiler = Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java'
$Lua = Join-Path $TestRoot 'mod\SCRealSandboxHarness\42\media\lua\client\SCRealSandboxHarness.lua'

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $GameJava -PathType Leaf)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot | Out-Null
try {
    & $Javac -d $BuildRoot $Compiler
    if ($LASTEXITCODE -ne 0) { throw 'Live harness Lua compiler build failed.' }
    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler $Lua
        if ($LASTEXITCODE -ne 0) { throw 'Live harness Kahlua compilation failed.' }
    }
    finally {
        Pop-Location
    }
    & python (Join-Path $TestRoot 'test_live_harness_static.py')
    if ($LASTEXITCODE -ne 0) { throw 'Live harness static contracts failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean live harness build outside temp: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
