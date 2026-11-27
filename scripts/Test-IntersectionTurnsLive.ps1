# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SeedSave,
    [Parameter(Mandatory=$true)][string]$CandidateBridge,
    [Parameter(Mandatory=$true)][string]$BaselineProjectRoot,
    [string]$OutputRoot='',
    [ValidateSet('Right','Left')][string[]]$Side=@('Right','Left'),
    [ValidateSet('baseline','candidate')][string[]]$Variant=@('baseline','candidate'),
    [ValidateRange(1,3)][int]$Repeats=3,
    [switch]$Resume,
    [string[]]$RerunLabel=@(),
    [string]$RerunReason=''
)
$ErrorActionPreference='Stop'
$ProjectRoot=Split-Path -Parent $PSScriptRoot
$baselineBridge=Join-Path $BaselineProjectRoot 'LivingFellows\42\media\java\LivingFellowsBridge.jar'
foreach($path in @($SeedSave,$CandidateBridge,$baselineBridge)) {
    if(-not(Test-Path -LiteralPath $path)) { throw "Missing acceptance input: $path" }
}
if(-not $OutputRoot) { $OutputRoot=Join-Path $ProjectRoot ('build\test-results\intersection-live-'+(Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$hostPath=(Get-Command powershell.exe -ErrorAction Stop).Source
$records=@()
if($Resume -and (Test-Path -LiteralPath (Join-Path $OutputRoot 'runs.json'))) {
    foreach($saved in (Get-Content -LiteralPath (Join-Path $OutputRoot 'runs.json') -Raw | ConvertFrom-Json)) {
        $records+=,$saved
    }
}
for($repeat=1;$repeat -le $Repeats;$repeat++) {
    foreach($direction in $Side) { foreach($version in $Variant) {
        $label="$version-$direction-$repeat"
        $log=Join-Path $OutputRoot ($label+'.log')
        $previous=@($records | Where-Object { $_.label -eq $label })
        if($previous.Count -gt 1) { throw "Duplicate acceptance label: $label" }
        if($previous.Count -eq 1) {
            $expectedBridge=if($version -eq 'baseline') { $baselineBridge } else { $CandidateBridge }
            if($previous[0].bridge_sha256 -ne (Get-FileHash -LiteralPath $expectedBridge -Algorithm SHA256).Hash) {
                throw "Cannot resume $label with different code."
            }
            if($previous[0].exit -eq 0 -and $RerunLabel -notcontains $label) {
                Write-Output "TURN_LIVE_REUSED $label run=$($previous[0].run)"
                continue
            }
            $rejectedPath=Join-Path $OutputRoot 'rejected-runs.json'
            $rejected=@()
            if(Test-Path -LiteralPath $rejectedPath) {
                foreach($saved in (Get-Content -LiteralPath $rejectedPath -Raw | ConvertFrom-Json)) { $rejected+=,$saved }
            }
            $rejected+=,$previous[0]
            if($RerunLabel -contains $label) {
                $previous[0] | Add-Member -NotePropertyName rejection_reason -NotePropertyValue $RerunReason -Force
            }
            [IO.File]::WriteAllText($rejectedPath,(ConvertTo-Json -InputObject $rejected -Depth 4),[Text.UTF8Encoding]::new($false))
            if(Test-Path -LiteralPath $log) {
                Copy-Item -LiteralPath $log -Destination (Join-Path $OutputRoot ($label+'-rejected-'+[guid]::NewGuid().ToString('N')+'.log'))
            }
            $records=@($records | Where-Object { $_.label -ne $label })
        }
        Write-Output "TURN_LIVE_START $label"
        $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',
            (Join-Path $PSScriptRoot 'Invoke-LiveSandboxTests.ps1'),'-DrivingProbe','-DrivingTurn',
            '-DrivingTurnSide',$direction,'-SeedSave',$SeedSave,'-LivingFellowsOnly','-NoSteam',
            '-IsolatedSourceBridge','-EngineSound','-HiddenWindow','-TimeoutSeconds','240')
        $bridge=$CandidateBridge
        if($version -eq 'baseline') {
            $bridge=$baselineBridge
            $argsList+=@('-DrivingTurnBaseline','-SourcePayloadProjectRoot',$BaselineProjectRoot)
        }
        $argsList+=@('-IsolatedBridgePath',$bridge)
        $prior=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            & $hostPath @argsList > $log 2>&1
            $code=$LASTEXITCODE
        } finally { $ErrorActionPreference=$prior }
        $text=[IO.File]::ReadAllText($log)
        $match=[regex]::Match($text,'Prepared isolated live sandbox: ([^\r\n]+)')
        $run=if($match.Success) { $match.Groups[1].Value.Trim() } else { '' }
        $record=[ordered]@{label=$label;variant=$version;side=$direction;repeat=$repeat;exit=$code;
            run=$run;bridge_sha256=(Get-FileHash -LiteralPath $bridge -Algorithm SHA256).Hash}
        $records+=,$record
        [IO.File]::WriteAllText((Join-Path $OutputRoot 'runs.json'),
            (ConvertTo-Json -InputObject $records -Depth 4),[Text.UTF8Encoding]::new($false))
        Write-Output "TURN_LIVE_RESULT $label exit=$code run=$run"
        if($run) {
            $events=Join-Path $run 'cache\Lua\LivingFellowsHarness\events.log'
            if(Test-Path -LiteralPath $events) {
                Get-Content -LiteralPath $events | Where-Object { $_ -match '^(PASS|FAIL)\|turn_' }
            }
        }
        if($code -ne 0) { throw "Native turn comparison failed: $label; see $log" }
    } }
}
Write-Output "INTERSECTION_TURNS_LIVE_PASS runs=$($records.Count) records=$OutputRoot"
