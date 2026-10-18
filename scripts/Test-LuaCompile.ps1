# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = (Resolve-Path -LiteralPath $GameRoot -ErrorAction Stop).Path

# Packaging must use the same pinned game compiler that will load the mod.
& (Join-Path $ProjectRoot 'scripts\Test-PzRuntime.ps1') -GameRoot $GameRoot | Out-Null

$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME) -and
    (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\javac.exe') -PathType Leaf)) {
    Join-Path $env:JAVA_HOME 'bin\javac.exe'
} else {
    (Get-Command javac.exe -ErrorAction Stop).Source
}
$Compiler = Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java'
$LuaRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua'
$LuaFiles = @(Get-ChildItem -LiteralPath $LuaRoot -Recurse -File -Filter '*.lua' |
    Sort-Object FullName | ForEach-Object FullName)
if ($LuaFiles.Count -eq 0) { throw "No payload Lua files found under $LuaRoot" }

$TemporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$BuildRoot = Join-Path $TemporaryRoot ('living-fellows-lua-compile-' +
    [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -d $BuildRoot $Compiler
    if ($LASTEXITCODE -ne 0) { throw 'Lua compiler harness Java compilation failed.' }

    & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler --verify-debug-limit
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua debug compiler fixture failed.' }

    & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler @LuaFiles | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Payload Lua compilation failed.' }

    # PZ records cumulative local declarations in a fixed debug array. This
    # pass catches functions that compile normally but fail for debug players.
    & $GameJava -cp "$BuildRoot;$Jar" ReflectLuaCompiler --debug-compile @LuaFiles | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Payload Lua debug compilation failed.' }
}
finally {
    $ResolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
    $TemporaryPrefix = $TemporaryRoot.TrimEnd('\') + '\'
    if (-not $ResolvedBuildRoot.StartsWith($TemporaryPrefix,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe Lua compiler cleanup: $ResolvedBuildRoot"
    }
    Remove-Item -LiteralPath $ResolvedBuildRoot -Recurse -Force
}

Write-Output "LUA_COMPILE_PASS files=$($LuaFiles.Count) normal=true debug=true"
