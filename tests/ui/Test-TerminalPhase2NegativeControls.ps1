# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$Files,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$mutants=@(
    @{Name='wheel-wrap';File='SCTerminalLockWheel.lua';From='return value-math.floor(value/26)*26';To='return value%26';Expected='each window returns exactly one printable letter'},
    @{Name='carried-manual';File='SCTerminalLockWheel.lua';From='required=Wheel.carried(player) and 1 or 3';To='required=3';Expected='carried handbook gives one challenge'},
    @{Name='manual-receipt';File='SCTerminalLockWheel.lua';From='state.lock.manualSpawned=true';To='state.lock.manualSpawned=false';Expected='manual is physically placed on the real desk surface once'},
    @{Name='owner-first';File='SCTerminalLockSearch.lua';From='collect(profile)';To='-- omitted owner priority';Expected='owner hits precede every other owner'},
    @{Name='search-proof';File='SCTerminalLocks.lua';From='#(s.lock.found or {})~=4';To='#(s.lock.found or {})~=3';Expected='four restored files use the real tier-two unlock'},
    @{Name='bypass-tier';File='SCTerminalLocks.lua';From='tier=math.max(1,tier-1)';To='tier=tier';Expected='early medium crack uses one lower tier'},
    @{Name='claim-verification';File='SCTerminalLockEmma.lua';From='local caught=argument.claim and (';To='local caught=false and (';Expected='numeric lies are caught against real records'},
    @{Name='memory-cap';File='SCTerminalLockEmma.lua';From='or (e.mentions or 0)>=3';To='or false';Expected='EMMA quotes the actual recorded lie at most three times'},
    @{Name='render-world-scan';File='SCTerminalLockEmma.lua';From='function Emma.lines(w)';To="function Emma.lines(w)`n    Emma.facts(w)";Expected='EMMA rendering never scans live records or threats'},
    @{Name='instant-number';File='SCTerminalLockUI.lua';From='if kind=="emma" then';To='if false then';Expected='pressing one number chooses an argument without Enter'}
)
foreach($mutant in $mutants){
    $source=@($Files|Where-Object{[IO.Path]::GetFileName($_)-eq $mutant.File})[0]
    if(-not $source){throw "No source for negative control: $($mutant.Name)"}
    $original=[IO.File]::ReadAllText($source)
    if(-not $original.Contains($mutant.From)){throw "Missing phase-two mutation anchor: $($mutant.Name)"}
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $path=Join-Path $BuildRoot ('lock-phase2-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $mutated=@($Files|ForEach-Object{if($_ -eq $source){$path}else{$_}})
    $log=Join-Path $BuildRoot ('lock-phase2-mutant-'+$mutant.Name+'.txt')
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @mutated *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or -not $detail.Contains($mutant.Expected)){
        throw "Phase-two negative control missed its intended assertion: $($mutant.Name) exit=$code log=$log"
    }
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Negative control changed production source.'}
    Write-Output "LOCK_PHASE2_NEGATIVE_PASS mutant=$($mutant.Name) exit=$code"
}
