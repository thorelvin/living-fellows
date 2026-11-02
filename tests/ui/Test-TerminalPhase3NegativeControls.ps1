# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$Files,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$mutants=@(
    @{Name='phone-emitter-tick';File='SCTerminalLockPhone.lua';From='U().call(c.emitter,"tick")';To='-- omitted owned emitter tick';Expected='owned phone emitter ticks on every active pulse'},
    @{Name='phone-between-rings-menu';File='SCTerminalLockPhone.lua';From='local c=P.answerable() if not c then return end';To='local c=P.ringing() if not c then return end';Expected='answer option is visible during the silent interval'},
    @{Name='phone-between-rings-click';File='SCTerminalLockPhone.lua';From='if P.answerable()~=c then return end';To='if P.ringing()~=c then return end';Expected='a menu opened during ringing still queues after its burst'},
    @{Name='phone-answer-message';File='SCTerminalLockPhone.lua';From='return false,"The internal call has ended. Return to the computer to redial."';To='return false,"Internal call answered."';Expected='expired answer action never claims success'},
    @{Name='phone-no-line-rechoice';File='SCTerminalLockPhone.lua';From='SC.TerminalLocks.rechoosePhone(w)';To='w.system.lock.kind="word"';Expected='missing phone reselects another eligible unseen method'},
    @{Name='phone-rechoice-prompt';File='SCTerminalLocks.lua';From='if w.entry then pcall(function() w.entry:setPlaceholderText(L.prompt(state)) end) end';To='-- omitted replacement prompt';Expected='input prompt follows the selected method'},
    @{Name='radio-quiet-nights';File='SCTerminalLockRadio.lua';From='ledger.lastNight==nil or #ledger.pending==0 and not broadcast';To='ledger.lastNight==nil';Expected='registration after quiet nights cannot start a daytime broadcast'},
    @{Name='rival-footer-digits';File='SCTerminalLocks.lua';From='(kind=="word" or kind=="remember" or kind=="rival")';To='(kind=="word" or kind=="remember")';Expected='typed rival footer digit opens the displayed history'},
    @{Name='phone-unheard';File='SCTerminalLocks.lua';From='not s.lock.heard or not w.lockCodeVerified';To='false or not w.lockCodeVerified';Expected='unheard phone code cannot unlock'},
    @{Name='phone-scan-cap';File='SCTerminalLockPhone.lua';From='f.scanned>=4096';To='f.scanned>=8192';Expected='phone discovery stops at the hard 4096-square bound'},
    @{Name='radio-receipt';File='SCTerminalLockRadio.lua';From='tostring(code)~="LF_LOCK_ESCROW"';To='false';Expected='unrelated radio events cannot create a receipt'},
    @{Name='radio-night';File='SCTerminalLockRadio.lua';From='night>ledger.lastNight';To='night>=ledger.lastNight';Expected='recovery station never starts before crossing 03:00'},
    @{Name='radio-retention';File='SCTerminalLockRadio.lua';From='if inspected>4096 then break end';To='if inspected>64 then break end';Expected='heard recovery keys survive beyond sixty four computers'},
    @{Name='rival-known';File='SCTerminalLockRival.lua';From='group.discovered~=true';To='true';Expected='discovered, dead or recruited groups cannot become USER2'},
    @{Name='rival-fifth';File='SCTerminalLockRival.lua';From='#r.guesses>=4';To='#r.guesses>=0';Expected='USER2 cannot choose the answer before its fifth guess'},
    @{Name='rival-paused';File='SCTerminalLockRival.lua';From='or type(isGamePaused)=="function" and isGamePaused()';To='or false';Expected='paused rival never advances'},
    @{Name='rival-reward';File='SCTerminalLocks.lua';From='if how=="rival" then amount=amount/2 end';To='if how=="rival" then amount=amount end';Expected='USER2 win discovers the actual group and pays half tier-three XP'}
)
foreach($mutant in $mutants){
    $source=@($Files|Where-Object{[IO.Path]::GetFileName($_)-eq $mutant.File})[0]
    $original=[IO.File]::ReadAllText($source)
    if(-not $original.Contains($mutant.From)){throw "Missing Phase 3 mutation anchor: $($mutant.Name)"}
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $path=Join-Path $BuildRoot ('lock-phase3-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $mutated=@($Files|ForEach-Object{if($_ -eq $source){$path}else{$_}})
    $log=Join-Path $BuildRoot ('lock-phase3-mutant-'+$mutant.Name+'.txt')
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @mutated *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or -not $detail.Contains($mutant.Expected)){throw "Phase 3 mutation missed intended assertion: $($mutant.Name); exit=$code log=$log detail=$($detail.Substring(0,[Math]::Min(1200,$detail.Length)))"}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Mutation changed production source.'}
    Write-Output "LOCK_PHASE3_NEGATIVE_PASS mutant=$($mutant.Name) exit=$code"
}
