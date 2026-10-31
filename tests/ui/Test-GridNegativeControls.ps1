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
    @{Name='progress-preserved'; From='task.lastHours=math.max(task.lastHours,hours)'; To='task.lastHours=math.max(task.lastHours,hours) if not task.powered then task.doneHours=0 end'}
)
foreach($mutant in $mutants){
    if(-not $original.Contains($mutant.From)){throw "Missing negative-control anchor: $($mutant.Name)"}
    $path=Join-Path $BuildRoot ('grid-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $files=@($GridFiles[0],$path,$GridFiles[2])
    $log=Join-Path $BuildRoot ('grid-mutant-'+$mutant.Name+'.txt')
    & $GameJava -cp $Classpath KahluaTestRunner @files *> $log
    $code=$LASTEXITCODE
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or $detail -notmatch 'grid \d+:'){throw "Negative control did not fail an intended assertion: $($mutant.Name) exit=$code"}
    Write-Output "GRID_NEGATIVE_CONTROL_PASS mutant=$($mutant.Name) exit=$code"
}
