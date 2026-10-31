# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$GridFiles,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$original=[IO.File]::ReadAllText($GridFiles[1])
$mutants=@(
    @{Name='idle-service'; From='if not cached or cached.on~=true or not supported() or not validate(cached) then return end'; To='if not cached then return end'},
    @{Name='heat-rate'; From='local rate=95/s.windowHours'; To='local rate=100/s.windowHours'},
    @{Name='unbounded-lease'; From='local value=math.min(math.floor(days)+3,math.floor(days)+math.ceil(remaining/24)+1)'; To='local value=2147483647'},
    @{Name='foreign-owner'; From='if value==expected then'; To='if true then'},
    @{Name='radio-required'; From='if not radio(hardware(object)) then'; To='if false then'},
    @{Name='camp-required'; From='if cracking and (not SC.BaseLife or SC.BaseLife.isInside(object)~=true) then'; To='if false then'},
    @{Name='generator-required'; From='if power.generator~=true then'; To='if false then'},
    @{Name='progress-preserved'; From='task.lastHours=math.max(task.lastHours,hours)'; To='task.lastHours=math.max(task.lastHours,hours) if not task.powered then task.doneHours=0 end'},
    @{Name='power-at-contact'; From='if task.powered and supplied then'; To='if task.powered then'},
    @{Name='unloaded-waits'; From='if source=="unloaded" then return end'; To=''},
    @{Name='lost-connection-released'; From='s.connections[task.site]=nil'; To=''},
    @{Name='lost-crack-takeover'; From='if job.lost then'; To='if false then'},
    @{Name='busy-crack-refused'; From='if busy then return false,"Another computer is already cracking this substation." end'; To=''},
    @{Name='stale-lease-recovers'; From='value>s.originalShut and finite(days) and days>value+1'; To='false'},
    @{Name='live-lease-respected'; From='finite(days) and days>value+1'; To='finite(days)'},
    @{Name='warnings-shown'; From='if player then U().call(player,"setHaloNote","EMMA: "..text) end'; To=''},
    @{Name='warnings-saved'; From='s.unread[#s.unread+1]=text'; To=''},
    @{Name='camp-keeps-menu'; From='if not G.pinned(object) and SC.BaseLife and SC.BaseLife.isInside(object)==true then return nil end'; To=''}
)
foreach($mutant in $mutants){
    if(-not $original.Contains($mutant.From)){throw "Missing negative-control anchor: $($mutant.Name)"}
    $path=Join-Path $BuildRoot ('grid-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $files=@($GridFiles[0],$path,$GridFiles[2])
    $log=Join-Path $BuildRoot ('grid-mutant-'+$mutant.Name+'.txt')
    # A failing mutant writes to stderr on purpose. Windows PowerShell 5.1 turns
    # redirected native stderr into a terminating error under 'Stop'.
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @files *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or $detail -notmatch 'grid \d+:'){throw "Negative control did not fail an intended assertion: $($mutant.Name) exit=$code"}
    Write-Output "GRID_NEGATIVE_CONTROL_PASS mutant=$($mutant.Name) exit=$code"
}
