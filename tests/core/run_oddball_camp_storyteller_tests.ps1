# SPDX-License-Identifier: MIT
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$jar=Join-Path $GameRoot 'projectzomboid.jar'
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$localJavac='C:\Program Files\Java\jdk-17\bin\javac.exe'
$javac=if(Test-Path -LiteralPath $localJavac -PathType Leaf){$localJavac}else{(Get-Command javac.exe -ErrorAction Stop).Source}
$build=Join-Path $project 'build\tests\oddball-camp-storyteller'
New-Item -ItemType Directory -Path $build -Force | Out-Null
& $javac -d $build (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Kahlua runner build failed' }
Push-Location -LiteralPath $GameRoot
try {
    $client=Join-Path $project 'SurvivorCompanion\42\media\lua\client'
    & $java -cp "$build;$jar" KahluaTestRunner `
        (Join-Path $project 'tests\core\oddball_camp_storyteller_fixture.lua') `
        (Join-Path $project 'SurvivorCompanion\42\media\lua\server\SCCampStorytellerServer.lua') `
        (Join-Path $client 'SCOddballCampStoryteller.lua') `
        (Join-Path $project 'tests\core\oddball_camp_storyteller_harness.lua')
    if ($LASTEXITCODE -ne 0) { throw 'Camp storyteller regression failed' }
} finally { Pop-Location }
