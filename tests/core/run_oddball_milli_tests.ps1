# SPDX-License-Identifier: MIT
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$jar=Join-Path $GameRoot 'projectzomboid.jar'
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$javac='C:\Program Files\Java\jdk-17\bin\javac.exe'
if (-not (Test-Path -LiteralPath $javac)) {
    $javac=(Get-Command javac.exe -ErrorAction Stop).Source
}
$build=Join-Path ([System.IO.Path]::GetTempPath()) ('sc-milli-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $build -Force | Out-Null
try {
    & $javac -d $build (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua runner build failed' }
    Push-Location -LiteralPath $GameRoot
    try {
        $client=Join-Path $project 'SurvivorCompanion\42\media\lua\client'
        & $java -cp "$build;$jar" KahluaTestRunner `
            (Join-Path $PSScriptRoot 'oddball_milli_fixture.lua') `
            (Join-Path $client 'SCFactionContracts.lua') `
            (Join-Path $client 'SCOddballMilli.lua') `
            (Join-Path $PSScriptRoot 'oddball_milli_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Milli Wilson encounter regression failed' }
    } finally { Pop-Location }
} finally {
    $full=[System.IO.Path]::GetFullPath($build)
    $temp=[System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test build path: $full"
    }
    Remove-Item -LiteralPath $build -Recurse -Force
}
