# SPDX-License-Identifier: MIT
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$jar=Join-Path $GameRoot 'projectzomboid.jar'
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$javac=(Get-Command javac.exe -ErrorAction Stop).Source
$build=Join-Path ([System.IO.Path]::GetTempPath()) ('sc-final-four-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $build -Force | Out-Null
try {
    & $javac -d $build (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'Kahlua runner build failed' }
    Push-Location -LiteralPath $GameRoot
    try {
        $client=Join-Path $project 'SurvivorCompanion\42\media\lua\client'
        & $java -cp "$build;$jar" KahluaTestRunner `
            (Join-Path $PSScriptRoot 'oddball_final_four_fixture.lua') `
            (Join-Path $client 'SCOddballExchange.lua') `
            (Join-Path $client 'SCPersonalItems.lua') `
            (Join-Path $client 'SCOddballGordon.lua') `
            (Join-Path $client 'SCOddballMorton.lua') `
            (Join-Path $client 'SCOddballMien.lua') `
            (Join-Path $client 'SCOddballGrinder.lua') `
            (Join-Path $PSScriptRoot 'oddball_final_four_harness.lua')
        if ($LASTEXITCODE -ne 0) { throw 'Final four regression failed' }
    } finally { Pop-Location }
} finally {
    $full=[System.IO.Path]::GetFullPath($build)
    $temp=[System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe test build path: $full"
    }
    Remove-Item -LiteralPath $build -Recurse -Force
}
