# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$Files,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$mutants=@(
    @{Name='story-proof';File='SCTerminalLocks.lua';From='if how=="story" and (';To='if how=="story" and false and (';Expected='unfinished adventure cannot claim a story win'},
    @{Name='natural-one';File='SCTerminalLockStory.lua';From='good=false delta=-2';To='good=false delta=-1';Expected='natural rolls override ordinary skill'},
    @{Name='pending-replay';File='SCTerminalLockStory.lua';From='g.pending=nil g.last=result';To='g.pending=p g.last=result';Expected='resolved results contain no replayable pending transfer'},
    @{Name='ghost-choice';File='SCTerminalLockStory.lua';From='option.result=="good" and 100 or 0';To='option.result=="bad" and 100 or 0';Expected='ghost always recommends a good choice'}
)
foreach($mutant in $mutants){
    $source=@($Files|Where-Object{[IO.Path]::GetFileName($_)-eq $mutant.File})[0]
    $original=[IO.File]::ReadAllText($source)
    if(-not $original.Contains($mutant.From)){throw "Missing Phase 4 mutation anchor: $($mutant.Name)"}
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $path=Join-Path $BuildRoot ('lock-phase4-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $mutated=@($Files|ForEach-Object{if($_ -eq $source){$path}else{$_}})
    $log=Join-Path $BuildRoot ('lock-phase4-mutant-'+$mutant.Name+'.txt')
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @mutated *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or -not $detail.Contains($mutant.Expected)){throw "Phase 4 mutation missed intended assertion: $($mutant.Name); exit=$code log=$log detail=$($detail.Substring(0,[Math]::Min(1200,$detail.Length)))"}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Mutation changed production source.'}
    Write-Output "LOCK_PHASE4_NEGATIVE_PASS mutant=$($mutant.Name) exit=$code"
}
