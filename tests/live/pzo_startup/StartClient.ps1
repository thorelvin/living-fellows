# SPDX-License-Identifier: MIT
param([Parameter(Mandatory)][string]$Run,[string]$LoadSave='')
$ErrorActionPreference='Stop'
$fixture=Get-Content -LiteralPath (Join-Path $Run 'run.json') -Raw|ConvertFrom-Json
$savedProfile=$env:USERPROFILE; $savedLocal=$env:LOCALAPPDATA; $savedRoaming=$env:APPDATA
try {
    $env:USERPROFILE=$fixture.profile
    $env:LOCALAPPDATA=Join-Path $fixture.profile 'AppData\Local'
    $env:APPDATA=Join-Path $fixture.profile 'AppData\Roaming'
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA,$env:APPDATA -Force|Out-Null
    $argsLine='-cachedir="'+$fixture.cache+'" -nosteam -nosound -novoip -debuglog=+General,+Lua'
    if($LoadSave){$argsLine+=' -loadsave="'+$LoadSave+'"'}
    $client=Start-Process -FilePath (Join-Path $fixture.game 'ProjectZomboid64.exe') -WorkingDirectory $fixture.game -ArgumentList $argsLine -WindowStyle Hidden -RedirectStandardOutput (Join-Path $fixture.run 'stdout.log') -RedirectStandardError (Join-Path $fixture.run 'stderr.log') -PassThru
    [IO.File]::WriteAllText((Join-Path $fixture.run 'pid.txt'),[string]$client.Id)
    Write-Output ('Started native PZO fixture pid='+$client.Id)
} finally {
    $env:USERPROFILE=$savedProfile; $env:LOCALAPPDATA=$savedLocal; $env:APPDATA=$savedRoaming
}
