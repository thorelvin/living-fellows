param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$env:PZ_GAME_ROOT=$GameRoot
$env:JAVAC=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& python -u (Join-Path $ProjectRoot 'tests\source\test_persona_controls.py')
if ($LASTEXITCODE -ne 0) { throw 'Persona negative controls failed.' }
