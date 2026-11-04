# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GameJava,
    [Parameter(Mandatory=$true)][string]$Classpath,
    [Parameter(Mandatory=$true)][string[]]$VoiceDepthFiles,
    [Parameter(Mandatory=$true)][string]$BuildRoot
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($BuildRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Voice negative-control build root is missing.' }
$prefix=$root.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
$utf8=[Text.UTF8Encoding]::new($false)
# Every mutant removes one independently exercised context or one lint rule.
# A compiler crash or a different assertion cannot count as detection.
$cases=@(
    @{Name='night-contact';File='SCBaseAlert.lua';From='return Voice.available("camp_alert.night." .. level, regular)';To='return level == "contact" and regular or Voice.available("camp_alert.night." .. level, regular)';Expected='night contact'},
    @{Name='night-stand-to';File='SCBaseAlert.lua';From='return Voice.available("camp_alert.night." .. level, regular)';To='return level == "stand_to" and regular or Voice.available("camp_alert.night." .. level, regular)';Expected='night stand-to'},
    @{Name='blind';File='SCBaseAlert.lua';From='return Voice.available("camp_alert.blind", regular)';To='return regular';Expected='fog contact'},
    @{Name='again';File='SCBaseAlert.lua';From='return Voice.available("camp_alert.again", regular)';To='return regular';Expected='again precedes night'},
    @{Name='clear-fought';File='SCBaseAlert.lua';From='local topic = finished.fought and "camp_alert.clear.fought" or "camp_alert.clear.passed"';To='local topic = "camp_alert.clear.passed"';Expected='actual told combat owner'},
    @{Name='clear-passed';File='SCBaseAlert.lua';From='local topic = finished.fought and "camp_alert.clear.fought" or "camp_alert.clear.passed"';To='local topic = finished.fought and "camp_alert.clear.fought" or "camp_alert.clear"';Expected='all-clear after no combat'},
    @{Name='hurt';File='SCBaseAlert.lua';From='and Voice.hurt(entry.actor, entries, current) then';To='and false then';Expected='nearby visible buddy'},
    @{Name='rest';File='SCRelationship.lua';From='if tonumber(description.fatigue or 0) >= 0.68 then return "rest" end';To='if false then return "rest" end';Expected='status admits serious tiredness'},
    @{Name='camp-opinion';File='SCRelationship.lua';From='if resident and resident.baseId == base.id and (state.order == "base_duty"';To='if false and resident and resident.baseId == base.id and (state.order == "base_duty"';Expected='base-duty resident camp opinion'},
    @{Name='haul-tally';File='SCProduction.lua';From='if word then return "burial.haul.tally", { word } end';To='if false and word then return "burial.haul.tally", { word } end';Expected='haul tally milestone 5'},
    @{Name='haul-uniform';File='SCProduction.lua';From='then return "burial.haul.uniform" end';To='then return topic end';Expected='uniform hauling choice'},
    @{Name='haul-dressed';File='SCProduction.lua';From='then return "burial.haul.dressed" end';To='then return topic end';Expected='dressed hauling choice'},
    @{Name='night-pyre';File='SCProduction.lua';From='then return "burn.night" end';To='then return topic end';Expected='night pyre choice'},
    @{Name='rain-grave';File='SCProduction.lua';From='then return "burial.dig.rain" end';To='then return topic end';Expected='rain grave choice'},
    @{Name='repeat-study';File='SCDowntime.lua';From='if context and context.groups[group] == day and has("study.again") then';To='if false and context and context.groups[group] == day and has("study.again") then';Expected='same-day repeated outfit study'},
    @{Name='night-study';File='SCDowntime.lua';From='and has("study.night") then';To='and false and has("study.night") then';Expected='night and rain enter actual middle'},
    @{Name='rain-study';File='SCDowntime.lua';From='and has("study.rain") then';To='and false and has("study.rain") then';Expected='night and rain enter actual middle'},
    @{Name='camp-clean-twin';File='SCDialogue.lua';From='{ "Shit, coming!", clean = "Crap, coming!" }';To='{ "Shit, coming!" }';Expected='malformed or missing clean twin camp_alert.coming'},
    @{Name='talk-placeholder';File='SCDialogue.lua';From='"My eyes keep closing on their own."';To='"My eyes keep closing on %3."';Expected='render status.rest'},
    @{Name='disposal-clean-twin';File='SCProduction.lua';From='{ "Rain in the grave. Hell of a day for it.", clean = "Rain in the grave. What a day for it." }';To='{ "Rain in the grave. Hell of a day for it." }';Expected='malformed or missing clean twin burial.dig.rain'},
    @{Name='study-placeholder';File='SCDowntime.lua';From='"Rain or not, they don''t care."';To='"Rain or not, %3."';Expected='render study.rain'}
)
foreach($case in $cases) {
    $files=@($VoiceDepthFiles)
    $indices=@(for($i=0;$i -lt $files.Count;$i++){if([IO.Path]::GetFileName($files[$i]) -eq $case.File){$i}})
    if($indices.Count -ne 1){throw "Ambiguous negative-control source: $($case.Name)"}
    $source=$files[$indices[0]]
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $text=[IO.File]::ReadAllText($source)
    if([regex]::Matches($text,[regex]::Escape($case.From)).Count -ne 1){throw "Missing unique voice mutation: $($case.Name)"}
    $target=[IO.Path]::GetFullPath((Join-Path $root ('voice-mutant-'+$case.Name+'-'+$case.File)))
    if(-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $target.Equals($source,[StringComparison]::OrdinalIgnoreCase)){throw 'Voice mutation must stay in its build directory.'}
    [IO.File]::WriteAllText($target,$text.Replace($case.From,$case.To),$utf8)
    $files[$indices[0]]=$target
    $log=Join-Path $root ('voice-mutant-'+$case.Name+'.log')
    $prior=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $GameJava -cp $Classpath KahluaTestRunner @files *> $log
        $exitCode=$LASTEXITCODE
    } finally {
        $ErrorActionPreference=$prior
        if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash){throw 'A voice negative control altered production source.'}
    }
    $failure=[IO.File]::ReadAllText($log)
    if($exitCode -eq 0 -or -not $failure.Contains('java.lang.AssertionError:') -or
        -not $failure.Contains('voice_depth_harness.lua: VOICE_DEPTH '+$case.Expected)) {
        throw "Voice negative control did not fail its intended assertion: $($case.Name). See $log"
    }
    Write-Host ('VOICE_NEGATIVE_PASS case='+$case.Name)
}
Write-Host ('VOICE_NEGATIVE_CONTROLS_PASS cases='+$cases.Count+' source-untouched=true')
