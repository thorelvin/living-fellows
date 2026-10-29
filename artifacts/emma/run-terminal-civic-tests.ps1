# SPDX-License-Identifier: MIT
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$build=Join-Path $project 'build\terminal-civic'
New-Item -ItemType Directory -Force -Path (Join-Path $build 'tests') | Out-Null
$javac=& (Join-Path $project 'scripts\Resolve-TestJavac.ps1')
& $javac -d (Join-Path $build 'tests') (Join-Path $project 'tests\gameplay\KahluaTestRunner.java')
if($LASTEXITCODE -ne 0){throw 'Terminal test runner compilation failed'}
[string[]]$files=@((Join-Path $project 'SurvivorCompanion\42\media\lua\shared\SCNamespace.lua'))
$files+=@('SCTerminalLines.lua','SCTerminalKnowledge.lua','SCTerminalConversation.lua','SCTerminalBrain.lua',
    'SCTerminalLore.lua','SCTerminalFiles.lua','SCTerminalPresentation.lua',
    'SCTerminalBusinessData.lua','SCTerminalBrands.lua','SCTerminalArtBounds.lua',
    'SCTerminalSystem.lua','SCTerminalWorld.lua') | ForEach-Object {
        Join-Path $project ('SurvivorCompanion\42\media\lua\client\'+$_)
    }
$files+=@('terminal_harness.lua','terminal_system_harness.lua','terminal_lore_harness.lua',
    'terminal_knowledge_harness.lua','terminal_conversation_harness.lua') | ForEach-Object {Join-Path $project ('tests\gameplay\'+$_)}
Push-Location -LiteralPath $GameRoot
try{
    & (Join-Path $GameRoot 'jre64\bin\java.exe') -cp ((Join-Path $build 'tests')+';'+(Join-Path $GameRoot 'projectzomboid.jar')) KahluaTestRunner @files
    if($LASTEXITCODE -ne 0){throw 'Terminal civic/archive tests failed'}
}finally{Pop-Location}
