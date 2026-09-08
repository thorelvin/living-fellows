# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'
)

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = (Get-Command javac.exe -ErrorAction Stop).Source
$TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$BuildRoot = Join-Path $TempRoot ('sc-ai-response-' + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $Jar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $GameJava -PathType Leaf)) {
    throw "Project Zomboid runtime not found under $GameRoot"
}

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua test runner compilation failed.' }

    $files = @(
        (Join-Path $TestRoot 'core_fixture.lua'),
        (Join-Path $Shared 'SCNamespace.lua'),
        (Join-Path $Shared 'SCCall.lua'),
        (Join-Path $Shared 'SCConfig.lua'),
        (Join-Path $Shared 'SCDiagnostics.lua'),
        (Join-Path $TestRoot 'runtime_hook_fixture.lua'),
        (Join-Path $Client 'SCPerformance.lua'),
        (Join-Path $Client 'SCScheduler.lua'),
        (Join-Path $Client 'SCRuntime.lua'),
        (Join-Path $TestRoot 'ai_response_harness.lua')
    )

    Push-Location -LiteralPath $GameRoot
    try {
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @files
        if ($LASTEXITCODE -ne 0) { throw 'AI response/load harness failed.' }
    } finally {
        Pop-Location
    }
} finally {
    $ResolvedBuild = [System.IO.Path]::GetFullPath($BuildRoot)
    $safeName = [System.IO.Path]::GetFileName($ResolvedBuild) -match '^sc-ai-response-[0-9a-f]{32}$'
    if (-not $safeName -or
        -not $ResolvedBuild.StartsWith($TempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unsafe AI harness build path: $ResolvedBuild"
    }
    if (Test-Path -LiteralPath $ResolvedBuild) {
        Remove-Item -LiteralPath $ResolvedBuild -Recurse -Force
    }
}
