-- SPDX-License-Identifier: MIT
local SC=LivingFellows
local V,C,D,T=SC.VoiceMemory,SC.Community,SC.Dialogue,SC.TestFixture
local checks,clock,age=0,100000,240
local function check(ok,why) checks=checks+1 assert(ok,"variety check "..checks..": "..why) end
function getTimestampMs() return clock end
function getGameTime() return {getWorldAgeHours=function() return age end} end
local actor=T.actor("sc-voice-memory",2,1,{recruited=true})
function actor:isAsleep() return false end
C.reset() D.reset() V.reset()
for _,value in ipairs({0,1,63,64,262143,2147483646}) do
    check(V._decodeForTests(V._encodeForTests(value,6))==value,"compact hashes round-trip exactly")
end
local lines={} for n=1,16 do lines[#lines+1]="Ordinary camp thought number "..n.."." end
D.register("banter.variety_test",{common=lines})
local heard={}
for n=1,12 do
    local spoken,line=D.say(actor,"banter.variety_test")
    check(spoken and not heard[line],"fresh lines before any repeat")
    heard[line]=true age=age+.1 clock=clock+10000
    if n==6 then
        local saved=C.export() check(C.restore(saved),"repeat memory survives world save")
        D.reset() V.reset()
    end
end
local remaining=V.filter(actor,"banter.variety_test",lines,function(line) return line end,16)
for _,line in ipairs(remaining) do check(not heard[line],"reloaded three-day exclusion matches actual speech") end
check(#remaining>0,"unheard choices remain available")
local before=C.export().voiceMemory["sc-voice-memory"].p
D.choose(actor,"banter.variety_test")
check(C.export().voiceMemory["sc-voice-memory"].p==before,"preparing unspoken text never records a heard line")
local saveSay=SC.GameplayUtil.say
SC.GameplayUtil.say=function() return false end
D.say(actor,"banter.variety_test")
check(C.export().voiceMemory["sc-voice-memory"].p==before,"rejected overhead never records speech")
SC.GameplayUtil.say=saveSay
V.noteKey(actor,"card:one")
local chosen=V.chooseKey(actor,{{id="one"},{id="two"}},"test")
check(chosen.id=="two","least-heard scene wins over a heard card")

C.reset() V.reset()
V.note(actor,"banter.busy","Original line.")
for n=1,160 do V.note(actor,"banter.busy","Other line "..n..".") end
check(V.count(actor,"Original line.")==0,"test evicted the exact-count entry")
local choices={"Original line.","A genuinely new line."}
remaining=V.filter(actor,"banter.busy",choices,function(line) return line end,8)
check(#remaining==1 and remaining[1]==choices[2],"daily filters retain the no-repeat guarantee after count eviction")
local getter=C.voiceMemoryFor
C.voiceMemoryFor=function() return {p="",b=""} end V.reset()
remaining=V.filter(actor,"banter.busy",choices,function(line) return line end,8)
check(#remaining==2,"persistence-removal negative control would allow the forbidden old line")
C.voiceMemoryFor=getter V.reset()
age=age+96
remaining=V.filter(actor,"banter.busy",choices,function(line) return line end,8)
check(#remaining==2,"old daily filters expire conservatively after the protection window")

C.reset() V.reset()
for companion=1,64 do
    local id="sc-voice-"..companion
    for n=1,120 do V.note(id,"banter.busy","Voice "..companion.." line "..n) end
end
local document=C.export()
local companions,maxBytes=0,0
for id,row in pairs(document.voiceMemory) do
    companions=companions+1
    local bytes=#id+#row.p+#row.b+40 maxBytes=math.max(bytes,maxBytes)
    check(bytes<=2048,"full companion voice record stays below two KB")
    check(#row.p<=1248 and #row.b<=272,"every packed field has a fixed bound")
    check(not row.p:find("Voice ",1,true),"only hashes are retained")
end
check(companions==64 and C.restore(document),"64 full records remain saveable")
V.note("sc-voice-overflow","banter.busy","overflow")
local count=0 for _ in pairs(C.export().voiceMemory) do count=count+1 end
check(count==64,"companion cap cannot grow")
document.voiceMemory["sc-voice-1"]={p=function() end,b=string.rep("x",100000)}
check(C.restore(document),"malformed additive voice fields are quarantined")
local cleaned=C.export().voiceMemory["sc-voice-1"]
check(cleaned and cleaned.p=="" and cleaned.b=="","malformed fields are not retained")
D.register("combat.urgent_test",{common={"Get back."}})
local first=D.say(actor,"combat.urgent_test") local second=D.say(actor,"combat.urgent_test")
check(first and second,"urgent warnings retain their existing availability")
local urgent={}
for n=1,8 do urgent[n]="Immediate warning "..n end
D.register("banter.refusal.test",{common=urgent})
for n=1,16 do check(D.say(actor,"banter.refusal.test"),"live withdrawal explanations cannot be exhausted by optional variety") end

do
    local banter, utility = SC.Banter, SC.GameplayUtil
    local pools = banter._poolsForTests()
    local routine = pools["banter.routine"]
    local crowded = "Funny how a room can feel crowded with nobody in it."
    check(#routine.common >= 100, "the routine pool has room for different speakers")
    local lowOnly = false
    for voice, pool in pairs(routine) do
        for _, line in ipairs(pool) do
            if line == crowded then
                check(voice == "low", "the empty-room reflection belongs to low mood")
                lowOnly = true
            end
        end
    end
    check(lowOnly, "the empty-room reflection remains available in context")

    C.reset()
    D.reset()
    V.reset()
    banter.reset()
    local party = banter._partyForTests()
    party.lastIntrusiveAt = math.huge
    local other = T.actor("sc-voice-partner", 1, 1, { recruited=true })
    function other:isAsleep() return false end
    local records = { { actor=actor }, { actor=other } }
    for _, record in ipairs(records) do
        local state = SC.Commands.peek(record.actor)
        state.recruited, state.personality = true, "practical"
    end
    local priorToken, priorHash = SC.ActionSupervisor.current, utility.stableHash
    local priorEmit = D.emitResolved
    SC.ActionSupervisor.current = function() return { owner="downtime", action="read" } end
    utility.stableHash = function() return 0 end
    utility.say = function() return false end
    check(not banter._routineForTests(T.player, records, clock) and #party.routineRecent == 0,
        "an unheard attempt does not advance party rotation")
    utility.say = saveSay
    D.reset()
    local spokenLines, speakers = {}, {}
    D.emitResolved = function(speaker, topic, line, options)
        local spoken, result, receipt = priorEmit(speaker, topic, line, options)
        if spoken and topic == "banter.routine" then
            spokenLines[#spokenLines + 1], speakers[#speakers + 1] = line, speaker
        end
        return spoken, result, receipt
    end
    for n=1,26 do
        clock, age = clock + 150000, age + 0.5
        check(banter._routineForTests(T.player, records, clock), "routine stays available in the shared rotation")
        for previous=math.max(1,n-24),n-1 do
            check(spokenLines[previous] ~= spokenLines[n], "a different companion cannot echo a recent routine line")
        end
    end
    check(speakers[1] == actor and speakers[2] == other, "the two companions still take turns")
    check(#party.routineRecent == 24 and party.routineRecent[1] == spokenLines[3]
        and not party.routineRecentSet[spokenLines[2]],
        "shared memory expires its oldest line at the fixed limit")
    SC.ActionSupervisor.current, utility.stableHash, D.emitResolved = priorToken, priorHash, priorEmit
end
SC_TEST_REPORT="VARIETY_PASS checks="..checks.." max_companion_bytes="..maxBytes
