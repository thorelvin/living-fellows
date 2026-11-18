# SPDX-License-Identifier: MIT
param([Parameter(Mandatory)][string]$Run,[ValidateSet('seed','waiting','restored','disk-restored')][string]$Mode='waiting')
$ErrorActionPreference='Stop'
$fixture=Get-Content -LiteralPath (Join-Path $Run 'run.json') -Raw|ConvertFrom-Json
$receipt=Join-Path $fixture.cache 'Lua\pzo-world-result.txt'
$text=Get-Content -LiteralPath $receipt -Raw -Encoding utf8
if($text -notmatch '(?m)^result=PASS\r?$' -or $text -notmatch ('(?m)^mode='+[regex]::Escape($Mode)+'\r?$')) {
    throw "Native PZO $Mode regression failed: $text"
}
if($Mode -eq 'waiting' -and ($text -notmatch '(?m)^status=waiting_environment\r?$' -or
    $text -notmatch '(?m)^attempts=0\r?$' -or $text -notmatch '(?m)^exact_record=true\r?$')) {
    throw "Waiting record did not preserve its retry budget and complete data: $text"
}
if($Mode -eq 'disk-restored') {
    $console=Join-Path $fixture.cache 'console.txt'
    if(-not (Select-String -LiteralPath $console -SimpleMatch 'SC_PZO_WORLD loaded exact native disk record id=sc-pzo-restore-02737' -Quiet)) {
        throw 'The disk reload did not complete its exact raw-record check.'
    }
}
Write-Output "NATIVE_PZO_RESTORE_PASS mode=$Mode run=$Run"
