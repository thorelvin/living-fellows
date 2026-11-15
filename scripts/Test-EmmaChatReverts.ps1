# SPDX-License-Identifier: MIT
# Exercise each public-chat fix with its original module reverted in an isolated
# source snapshot. The working tree and local game installation are never edited.
[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $ProjectRoot 'tests/core'
$Gameplay = Join-Path $ProjectRoot 'tests/gameplay'
$UI = Join-Path $ProjectRoot 'tests/ui'
$Shared = Join-Path $ProjectRoot 'SurvivorCompanion/42/media/lua/shared'
$Client = Join-Path $ProjectRoot 'SurvivorCompanion/42/media/lua/client'
$Essential = Join-Path $ProjectRoot 'tests/essential'
$InterfaceGroups = @(. (Join-Path $Essential 'Interface.ps1'))
& python (Join-Path $PSScriptRoot 'Build-EmmaTalkPolishData.py') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Conversation fixture compilation failed.' }
$Sources = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCEmmaCorpusData.lua'),
    (Join-Path $UI 'SCEmmaTalkPolishData.lua'),
    (Join-Path $UI 'SCEmmaTalkPolishFixture.lua'))
$Fixes = @(
    # F7 consumes strongIntent, so retain that helper and revert F1's context
    # admission, source deadline and repeat guard together in SCEmmaContext.
    @{Id='F1'; Commit='16351b50'; Modules=@('SCEmmaContext')},
    @{Id='F2'; Commit='4ca3897b'; Modules=@('SCEmmaContext','SCEmmaHooks')},
    @{Id='F3'; Commit='485cbe24'; Modules=@('SCEmmaConversation','SCEmmaHooks')},
    @{Id='F4'; Commit='7d9335e5'; Modules=@('SCEmmaConversation')},
    @{Id='F5'; Commit='4177c7c4'; Modules=@('SCEmmaLanguageData','SCTerminalBrain','SCEmmaUnderstand','SCEmmaReference')},
    @{Id='F6'; Commit='7376d42e'; Modules=@('SCTerminalLines','SCTerminalKnowledge','SCTerminalConversation','SCEmmaLanguageData')},
    @{Id='F7'; Commit='7f3e5db8'; Modules=@('SCEmmaFollowups')},
    @{Id='F8'; Commit='50c53de9'; Modules=@('SCEmmaUnderstand')},
    @{Id='F9'; Commit='3e620d8b'; Modules=@('SCEmmaUnderstand')},
    @{Id='F10'; Commit='95bb6dfe'; Modules=@('SCTerminalBrain','SCTerminalLines')})
$RunRoot = Join-Path $ProjectRoot ('build/emma-talk-polish/reverts-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $RunRoot | Out-Null
$Javac = & (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $Javac -d $RunRoot (Join-Path $Gameplay 'KahluaTestRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Kahlua runner compilation failed.' }
$Java = Join-Path $GameRoot 'jre64/bin/java.exe'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$Results = @()
foreach ($Fix in $Fixes) {
    $Snapshot = Join-Path $RunRoot $Fix.Id
    New-Item -ItemType Directory -Path $Snapshot | Out-Null
    $Parent = (& git -C $ProjectRoot rev-parse ($Fix.Commit + '^')).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve $($Fix.Id) parent." }
    $Overrides = @{}
    foreach ($Module in $Fix.Modules) {
        $Relative = 'SurvivorCompanion/42/media/lua/client/' + $Module + '.lua'
        $Content = @(& git -C $ProjectRoot show ($Parent + ':' + $Relative))
        if ($LASTEXITCODE -ne 0) { throw "Cannot read $($Fix.Id) reverted module $Module." }
        $Path = Join-Path $Snapshot ($Module + '.lua')
        [IO.File]::WriteAllLines($Path, [string[]]$Content, [Text.UTF8Encoding]::new($false))
        $Overrides[$Module + '.lua'] = $Path
    }
    $Prelude = Join-Path $Snapshot 'select.lua'
    [IO.File]::WriteAllText($Prelude, ('SC_EMMA_CHAT_CASE="' + $Fix.Id + '"'), [Text.UTF8Encoding]::new($false))
    $Entry = @{Fix=$Fix.Id; RevertedFrom=$Parent; Modules=$Fix.Modules}
    foreach ($Mode in @('current','reverted')) {
        $Files = @($Sources | ForEach-Object {
            $Name = [IO.Path]::GetFileName($_)
            if ($Mode -eq 'reverted' -and $Overrides.ContainsKey($Name)) { $Overrides[$Name] } else { $_ }
        }) + @($Prelude, (Join-Path $Gameplay 'emma_talk_care_harness.lua'),
            (Join-Path $Gameplay 'emma_talk_chat_harness.lua'))
        $Log = Join-Path $Snapshot ($Mode + '.log')
        $PriorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $GameRoot
        try {
            & $Java -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -cp "$RunRoot;$Jar" KahluaTestRunner @Files *> $Log
            $Code = $LASTEXITCODE
        } finally { Pop-Location; $ErrorActionPreference = $PriorPreference }
        $Entry[$Mode + 'ExitCode'] = $Code
        $Entry[$Mode + 'Log'] = $Log
        if ($Mode -eq 'current' -and $Code -ne 0) { throw "$($Fix.Id) current code failed; see $Log" }
        if ($Mode -eq 'reverted') {
            $Evidence = Get-Content -LiteralPath $Log -Raw
            if ($Code -eq 0 -or $Evidence -notmatch ('public chat regressions: ' + $Fix.Id + '\.')) {
                throw "$($Fix.Id) revert did not cause its public-chat assertion; see $Log"
            }
            $Entry.DetectedCases = @([regex]::Matches($Evidence, ($Fix.Id + '\.[a-zA-Z0-9.-]+')) |
                ForEach-Object { $_.Value } | Select-Object -Unique)
        }
        Write-Output "$($Fix.Id) $Mode exit=$Code"
    }
    $Results += $Entry
}
@{Commit=(& git -C $ProjectRoot rev-parse HEAD).Trim(); Results=$Results} |
    ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $RunRoot 'summary.json') -Encoding UTF8
Write-Output "EMMA_CHAT_REVERTS_PASS count=$($Results.Count) evidence=$RunRoot"
