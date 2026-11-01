# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$ScanFiles,[string[]]$ScanUiFiles,[string[]]$ScanScreenFiles,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$engine=$ScanFiles | Where-Object { [IO.Path]::GetFileName($_) -eq 'SCBuildingScan.lua' }
$ui=$ScanUiFiles | Where-Object { [IO.Path]::GetFileName($_) -eq 'SCTerminalScanUI.lua' }
$terminal=$ScanUiFiles | Where-Object { [IO.Path]::GetFileName($_) -eq 'SCTerminal.lua' }
$mutants=@(
    @{Name='rate';Path=$engine;From='rate=64*';To='rate=32*'},
    @{Name='stall-cap';Path=$engine;From='math.min(32,whole)';To='math.min(64,whole)'},
    @{Name='closed-window';Path=$engine;From='window.closed or';To=''},
    @{Name='abort-fresh';Path=$engine;From='if prior and not prior.done and not prior.aborted and not restart then';To='if prior and not restart then'},
    @{Name='empty-is-loaded';Path=$engine;From='chunk~=nil or square~=nil';To='square~=nil'},
    @{Name='passive-classification';Path=$engine;From='return "fridge"';To='return "tv"'},
    @{Name='unloaded-kept';Path=$engine;From='if not scan.seen[id] and covered then';To='if not scan.seen[id] then'},
    @{Name='alias-owner';Path=$engine;From='active.computer==object';To='true'},
    @{Name='stale-ui-owner';Path=$engine;From='if window and current and window~=current then return end';To=''},
    @{Name='stale-abort-owner';Path=$engine;From='if scan.computer~=object then return false,"Resume this survey here before aborting it." end';To=''},
    @{Name='once-xp';Path=$engine;From='not scan.panel.scanXpAwarded';To='true'},
    @{Name='independent-find-cap';Path=$engine;From='scan.findCount>=B().MAX_FINDS';To='scan.findCount> B().MAX_FINDS'},
    @{Name='power-loss';Path=$engine;From='or not SC.Terminal.powered(object)';To=''},
    @{Name='budget';Path=$engine;From='or remaining and remaining()<=0';To=''},
    @{Name='equipment-idle';Path=$ui;From='if start then';To='if true then'},
    @{Name='read-only-open';Path=$ui;From='if value.readonly then';To='if false then'},
    @{Name='row-selection';Path=$ui;From='elseif key then';To='elseif false then'},
    @{Name='no-render-status';Path=$ui;From='local s=w.scanSnapshot if not s then return end';To='B().status({id="render"}) local s=w.scanSnapshot if not s then return end'},
    @{Name='no-text-overflow';Path=$ui;From='if fits(text) then return text end';To='if true then return text end'},
    @{Name='poll-rate';Path=$ui;From='now-w.scanSampleAt<200';To='false'},
    @{Name='status-rate';Path=$ui;From='now-w.scanStatusAt>=1000';To='true'},
    @{Name='prompt-priority';Path=$ui;From='not w.requestTicket and w.scanSnapshot';To='w.scanSnapshot'},
    @{Name='modal-input';Path=$ui;From='if w.requestTicket then return true end';To=''},
    @{Name='arrow-wrap';Path=$terminal;From='index - math.floor(index / count) * count + 1';To='index % count + 1'},
    @{Name='sound-throttle';Path=$ui;From='now-(w.scanBlipAt or -10000)>=250';To='true'},
    @{Name='small-floor-layout';Path=$ui;From='elseif floorTop>=g.contentTop+g.row then';To='else'},
    @{Name='extra-hidden';Path=$engine;From='if not f.extra or f.found>0 then';To='if true then'},
    @{Name='extra-fast';Path=$engine;From='if level and level.extra then';To='if false then'},
    @{Name='extra-percent';Path=$engine;From='scan.baseDone/math.max(1,scan.baseTotal)*100';To='scan.processed/math.max(1,scan.total)*100'},
    @{Name='extra-range';Path=$engine;From='else hidden=hidden+f.done end';To='else hidden=hidden+f.done outOfRange=outOfRange+f.outOfRange end'},
    @{Name='self-find';Path=$engine;From='if object==scan.computer then return end';To=''},
    @{Name='empty-while-scanning';Screen=$true;Path=$ui;From='local empty=#rows==0 and not state and';To='local empty=#rows==0 and'},
    @{Name='empty-overlap';Screen=$true;Path=$ui;From='(s.dataCount+(s.empty and 1 or 0))';To='s.dataCount'},
    @{Name='probe-hidden';Screen=$true;Path=$ui;From='if probeText and #noticeRows<room then';To='if probeText and #noticeRows==0 then'},
    @{Name='stale-probe';Screen=$true;Path=$ui;From='local probe=unfinished and state.lastProbe';To='local probe=state and state.lastProbe'},
    @{Name='notice-sticky';Screen=$true;Path=$ui;From='now>=w.scanNoticeUntil';To='false'},
    @{Name='report-clip';Screen=$true;Path=$ui;From='SC.Terminal.wrap(w.scanNotice,geometry.columns,noticeFits)';To='{clip(w,w.scanNotice,geometry.listWidth)}'},
    @{Name='report-fades';Screen=$true;Path=$ui;From='UI.notice(w,line,true)';To='UI.notice(w,line)'},
    @{Name='plural-header';Screen=$true;Path=$ui;From='string.upper(count(#floors,"floor"))';To='#floors.." FLOORS"'},
    @{Name='plural-report';Screen=$true;Path=$ui;From='floors=count(#result.floors,"floor")';To='floors=#result.floors.." floors"'},
    @{Name='floor-stale';Screen=$true;Path=$ui;From='w.scanFloorManual=known or nil';To=''},
    @{Name='floor-restart';Screen=$true;Path=$ui;From='w.scanUserSelected=false w.scanFloorManual=nil end';To='w.scanUserSelected=false end'},
    @{Name='floor-unknown';Screen=$true;Path=$ui;From='w.scanFloor=floors[mod(index,#floors)+1].z';To='if index>0 then w.scanFloor=floors[mod(index,#floors)+1].z end'},
    @{Name='rain-faint';Screen=$true;Path=$ui;From='running and (distance==0 and 1 or fade*.75) or fade*.3';To='fade*.3'},
    @{Name='esc-keeps-ticket';Screen=$true;Path=$ui;From='if pending then w:cancelRequest()';To='if false then w:cancelRequest()'},
    @{Name='wheel-scan';Screen=$true;Path=$terminal;From='SC.TerminalScanUI.scroll(self,tonumber(delta) or 0)';To='SC.TerminalScanUI.scroll(self,-(tonumber(delta) or 0))'},
    @{Name='wheel-grid';Screen=$true;Path=$terminal;From='SC.TerminalGridUI.scroll(self,(tonumber(delta) or 0)*3)';To='SC.TerminalGridUI.scroll(self,-(tonumber(delta) or 0)*3)'},
    @{Name='wheel-radio';Screen=$true;Path=$terminal;From='SC.TerminalRadioUI.scroll(self,(tonumber(delta) or 0)*3)';To='SC.TerminalRadioUI.scroll(self,-(tonumber(delta) or 0)*3)'},
    @{Name='prompt-hint';Screen=$true;Path=$terminal;From='hint=self.requestTicket and "Y/N: confirm   Esc: cancel" or "1-"..#self:menuOptions()..": select   PgUp/Dn';To='hint="1-"..#self:menuOptions()..": select   PgUp/Dn'}
)
foreach($mutant in $mutants){
    $original=[IO.File]::ReadAllText($mutant.Path)
    $hash=(Get-FileHash -LiteralPath $mutant.Path -Algorithm SHA256).Hash
    if(-not $original.Contains($mutant.From)){throw "Missing building negative-control anchor: $($mutant.Name)"}
    $path=Join-Path $BuildRoot ('scan-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $files=if($mutant.Screen){$ScanScreenFiles}elseif($mutant.Path -eq $engine){$ScanFiles}else{$ScanUiFiles}
    $files=@($files | ForEach-Object {if($_ -eq $mutant.Path){$path}else{$_}})
    $log=Join-Path $BuildRoot ('scan-mutant-'+$mutant.Name+'.txt')
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @files *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or $detail -notmatch '(building discovery|terminal ui) \d+:'){
        throw "Building negative control did not fail an intended assertion: $($mutant.Name) exit=$code log=$log"
    }
    if((Get-FileHash -LiteralPath $mutant.Path -Algorithm SHA256).Hash -ne $hash){throw 'Negative control changed production source.'}
    Write-Output "SCAN_NEGATIVE_CONTROL_PASS mutant=$($mutant.Name) exit=$code"
}
