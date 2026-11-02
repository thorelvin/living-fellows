# SPDX-License-Identifier: MIT
param([string]$GameJava,[string]$Classpath,[string[]]$Files,[string]$BuildRoot)
$ErrorActionPreference='Stop'
$source=@($Files|Where-Object{[IO.Path]::GetFileName($_)-eq 'SCNeeds.lua'})[0]
$original=[IO.File]::ReadAllText($source)
$hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$mutants=@(
    @{Name='emergency-water-scope';From='if thirstEmergency(assessment) then waterScope=nil end';To='-- omit emergency scope';Expected='emergency follower drinks from its own nearby sink'},
    @{Name='emergency-food-scope';From='if hungerEmergency(assessment) then foodScope=nil end';To='-- omit emergency scope';Expected='starving follower fetches fresh food near itself'},
    @{Name='mission-player-pause';From='if commands.expeditionMember then return true end';To='-- use remote player pause';Expected='stopped expedition drinks carried water with real Follow orders'},
    @{Name='mission-food-marker';From='(options.expeditionMember or commands and commands.expeditionMember) and not emergency';To='options.expeditionMember and not emergency';Expected='stopped expedition uses carried food instead of starting a home resupply'},
    @{Name='seated-shared-clock';From='local inVehicle=select(1,U().call(player,"getVehicle"))~=nil';To='local inVehicle=select(1,U().call(player,"getVehicle"))~=nil or select(1,U().call(actor,"getVehicle"))~=nil';Expected='seated follower never resets the standing follower'},
    @{Name='errand-margin';From='if own and own.routineWork then';To='if false then';Expected='admitted errand keeps its interaction margin'}
)
foreach($mutant in $mutants){
    if(-not $original.Contains($mutant.From)){throw "Missing needs mutation anchor: $($mutant.Name)"}
    $path=Join-Path $BuildRoot ('needs-priority-mutant-'+$mutant.Name+'.lua')
    [IO.File]::WriteAllText($path,$original.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false))
    $mutated=@($Files|ForEach-Object{if($_ -eq $source){$path}else{$_}})
    $log=Join-Path $BuildRoot ('needs-priority-mutant-'+$mutant.Name+'.txt')
    $ErrorActionPreference='Continue'
    & $GameJava -cp $Classpath KahluaTestRunner @mutated *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    $detail=[IO.File]::ReadAllText($log)
    if($code -eq 0 -or -not $detail.Contains($mutant.Expected)){
        throw "Needs mutation missed its intended assertion: $($mutant.Name); exit=$code log=$log"
    }
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'Needs mutation changed production source.'}
    Write-Output "NEEDS_PRIORITY_NEGATIVE_PASS mutant=$($mutant.Name) exit=$code"
}
