# SPDX-License-Identifier: MIT
# Independent causal controls use scratch Lua copies, never the live payload.
[CmdletBinding()]
param([string]$GameRoot='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $ProjectRoot 'tests\core'
$Gameplay=Join-Path $ProjectRoot 'tests\gameplay'
$Essential=Join-Path $ProjectRoot 'tests\essential'
$Shared=Join-Path $ProjectRoot 'LivingFellows\42\media\lua\shared'
$Client=Join-Path $ProjectRoot 'LivingFellows\42\media\lua\client'
. (Join-Path $Essential 'Gameplay.ps1')
$lifecycle=@(. (Join-Path $Essential 'Lifecycle.ps1'))
$rescue=@($lifecycle | Where-Object Name -EQ 'handover-shelter-radio')[0]
$coldLoader=@($lifecycle | Where-Object Name -EQ 'handover-cold-loader-recovery')[0]
$decision=@(. (Join-Path $Essential 'Behaviour.ps1') | Where-Object Name -EQ 'behaviour.decision-arbitration-and-shelter-entry')[0]
$output=Join-Path $ProjectRoot ('build\shelter-review\controls-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$classes=Join-Path $output 'classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$java=Join-Path $GameRoot 'jre64\bin\java.exe'
$jar=Join-Path $GameRoot 'projectzomboid.jar'
$javac=& (Join-Path $PSScriptRoot 'Resolve-TestJavac.ps1')
& $javac -d $classes (Join-Path $Gameplay 'KahluaTestRunner.java')
if($LASTEXITCODE -ne 0){throw 'Causal-control runner compilation failed.'}
function Invoke-Case([string]$Name,[string[]]$Files){
    $log=Join-Path $output ($Name+'.log')
    Push-Location $GameRoot
    try {
        # Windows PowerShell 5.1 wraps redirected native stderr in error records.
        # A negative control intentionally writes a stack trace and exits nonzero.
        $ErrorActionPreference='Continue'
        $global:LASTEXITCODE=$null
        & $java '-Xmx256m' '-XX:ActiveProcessorCount=2' '-XX:+UseSerialGC' -cp "$classes;$jar" KahluaTestRunner @Files *> $log
        if($null -eq $LASTEXITCODE){throw "Java runner did not start: $Name"}
        return $LASTEXITCODE
    } finally { Pop-Location }
}
foreach($group in @($rescue,$decision,$coldLoader)){
    if((Invoke-Case ('full-'+$group.Name) $group.Files) -ne 0){throw "Positive regression failed: $($group.Name)"}
}
$controls=@(
    @{Name='actual-static-reason';Case='terminal';Old="reason=='path_blocked:blocked_static'";New="reason=='path_blocked:static'"},
    @{Name='native-step-recovery';Case='transient';Old="or reason=='shelter_unavailable'";New="or reason=='native_path_failed' or reason=='native_path_timeout' or reason=='native_path_stalled' or reason=='shelter_unavailable'"},
    @{Name='unloaded-grace';Case='unloaded';Old="if reason=='shelter_unloaded' then";New="if false and reason=='shelter_unloaded' then"},
    @{Name='unloaded-fixed-start';Case='unloaded';Old='if not attempt.unloadedSince or now<attempt.unloadedSince then';New='if true then'},
    @{Name='intermittent-streaming';Case='streaming_interruptions';Old='attempt.unloadedMs=unloadedTime(attempt,observedUntil)';New='attempt.unloadedMs=0'},
    @{Name='streaming-emergency-gap';Case='streaming_interruptions';Old='math.min(now,attempt.lastUnloadedAt+1000)';New='now'},
    @{Name='unloaded-not-rejected';Case='unloaded';Old="releaseShelter(actor,row,'shelter_unloaded_timeout',now,false)";New="releaseShelter(actor,row,'shelter_unloaded_timeout',now,true)"},
    @{Name='selected-route-length';Case='loop';Old='pathNodes=pathNodes(point.pathNodes)';New='pathNodes=nil'},
    @{Name='overall-deadline';Case='loop';Old='elseif row.shelterActiveMs>=attemptLimit(row.target) then';New='elseif false and row.shelterActiveMs>=attemptLimit(row.target) then'},
    @{Name='deadline-cap';Case='cap';Old='return math.min(80,math.max(1,math.ceil(count)))';New='return math.max(1,math.ceil(count))'},
    @{Name='moving-keeps-budget';Case='loop';Old="elseif math.floor(z)~=math.floor(attempt.z) or (x-attempt.x)^2+(y-attempt.y)^2>=.25 then";New="elseif math.floor(z)~=math.floor(attempt.z) or (x-attempt.x)^2+(y-attempt.y)^2>=.25 then row.shelterActiveMs=0"},
    @{Name='saved-consumed-budget';Case='reload';Old='local elapsed=tonumber(row.shelterActiveMs) or 0';New='local elapsed=0'},
    @{Name='interruptions-pause-budget';Case='interrupt';Old='row.shelterActiveMs=elapsed+math.min(gap,1000)';New='row.shelterActiveMs=elapsed+gap'},
    @{Name='physical-arrival-first';Case='arrival';Old="if atShelter(actor,row.target,x,y,z) then row.phase='sheltered';shelterAttempts[actor]=nil;return end";New="if false and atShelter(actor,row.target,x,y,z) then row.phase='sheltered';shelterAttempts[actor]=nil;return end"},
    @{Name='decision-streaming-result';Case='decision';Decision=$true;Old='handled,reason=true,"shelter_unloaded"';New='handled,reason=false,"shelter_unavailable"'},
    @{Name='lost-cold-loader';Case='loader';Old="if SC.ViewSession.owner()~='handover' then`n        loadingId,bootstrap=nil,nil";New="if false then`n        loadingId,bootstrap=nil,nil"},
    @{Name='lost-takeover-retry';Case='takeover_loader';ColdLoader=$true;File='SCHandover.lua';Old="if notice=='lost' then active.retryLoadAt=now+1000 end";New="if notice=='lost' then active.retryLoadAt=nil end"},
    @{Name='quarantined-loader-release';Case='quarantined_loader';ColdLoader=$true;Old="elseif SC.Persistence.pendingRestoreStatus(id)=='quarantined' and slot==bootstrap then";New="elseif false and SC.Persistence.pendingRestoreStatus(id)=='quarantined' and slot==bootstrap then"},
    @{Name='pending-loader-not-parked';Case='loader';Old="if missing and loadedSheltered and not loadingId and SC.ViewSession.owner()=='handover' then";New="if missing and loadedSheltered and SC.ViewSession.owner()=='handover' then"}
)
$results=foreach($control in $controls){
    $group=if($control.Decision){$decision}elseif($control.ColdLoader){$coldLoader}else{$rescue}
    $file=if($control.File){$control.File}elseif($control.Decision){'SCDecision.lua'}else{'SCHandoverRescue.lua'}
    $source=Join-Path $Client $file
    $text=(Get-Content -LiteralPath $source -Raw).Replace("`r`n","`n")
    if(([regex]::Matches($text,[regex]::Escape($control.Old))).Count -ne 1){throw "Mutation must match exactly once: $($control.Name)"}
    $variant=Join-Path $output ($control.Name+'.lua')
    [IO.File]::WriteAllText($variant,$text.Replace($control.Old,$control.New),$utf8)
    $prefix=Join-Path $output ($control.Name+'-case.lua')
    [IO.File]::WriteAllText($prefix,"SC_TEST_SHELTER_REVIEW_CASE='"+$control.Case+"'`n",$utf8)
    $positive=@($prefix)+@($group.Files)
    $positiveCode=Invoke-Case ($control.Name+'-positive') $positive
    if($positiveCode -ne 0){throw "Isolated positive failed: $($control.Name)"}
    $negative=@($prefix)+@($group.Files | ForEach-Object {if($_ -eq $source){$variant}else{$_}})
    $negativeCode=Invoke-Case ($control.Name+'-negative') $negative
    if($negativeCode -eq 0){throw "Causal control did not fail: $($control.Name)"}
    Write-Host "CAUSAL_CONTROL_PASS $($control.Name) positive=$positiveCode negative=$negativeCode"
    [pscustomobject]@{name=$control.Name;scenario=$control.Case;positiveExit=$positiveCode;negativeExit=$negativeCode}
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding utf8
Write-Output "SHELTER_REVIEW_CONTROLS_PASS controls=$($results.Count) evidence=$output"
