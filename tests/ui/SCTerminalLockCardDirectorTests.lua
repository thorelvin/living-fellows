-- SPDX-License-Identifier: MIT
-- Observable world-ledger, tour and old-save behavior with the tenth lock.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local L=SC.TerminalLocks
local check,before=T.check,T.checks
local oldMod,oldRecruitable=ModData,SC.TerminalLockRival.hasRecruitable
local ledger={opened=100,seen={},beaten={}}
ModData={getOrCreate=function() return ledger end}
SC.TerminalLockRival.hasRecruitable=function() return true end
for _,kind in ipairs(L.KINDS) do ledger.seen[kind]=true;ledger.beaten[kind]=true end
L.reset()
local normalized=L.ledger()
local count=0 for _ in pairs(normalized.seen) do count=count+1 end
check(count==10,"world ledger retains all ten seen kinds after normalization")
for _,kind in ipairs(L.KINDS) do
    check(normalized.seen[kind] and normalized.beaten[kind],"ten-kind ledger roundtrip retains "..kind)
end
local complete=0
for seed=1,3000 do
    local seen={}
    for n=1,17 do
        local kind=L.choose(seed*7919+n*53,{opened=n-1,seen=seen,beaten={}},"office",{phone=true,rival=true})
        check(L.WEIGHTS[kind]~=nil,"tour selects a real built kind")
        if n==1 then check(kind=="remember","new tour starts with Remembers") end
        if n==2 then check(kind=="word","new tour keeps the original puzzle second") end
        seen[kind]=true
    end
    local all=true for _,kind in ipairs(L.KINDS) do if not seen[kind] then all=false end end
    if all then complete=complete+1 end
end
check(complete>=2970,"ten-kind tour reaches all ten by machine17 in at least99 percent of3000 saves")
local allSeen,oldSeen={},{}
for _,kind in ipairs(L.KINDS) do allSeen[kind]=true;if kind~="card" then oldSeen[kind]=true end end
local ordinary,catchup,boosted=0,0,0
for seed=1,20000 do
    if L.choose(seed,{opened=100,seen=allSeen,beaten=allSeen},"office")=="card" then ordinary=ordinary+1 end
    if L.choose(seed,{opened=100,seen=oldSeen,beaten=oldSeen},"office")=="card" then catchup=catchup+1 end
    if L.choose(seed,{opened=100,seen=allSeen,beaten=allSeen},"security")=="card" then boosted=boosted+1 end
end
check(ordinary>1500 and ordinary<2200,"ordinary completed-tour card frequency follows weight10 of110")
check(catchup>3800 and catchup<5400,"old nine-kind saves receive the unseen card catchup weight")
check(boosted>ordinary*1.25,"believable card-reader sites increase its share")
for _,site in ipairs({"home","agriculture"}) do
    for seed=1,3000 do
        check(L.choose(seed,{opened=100,seen=oldSeen,beaten=oldSeen},site)~="card","card never appears at "..site)
    end
end
for _,available in ipairs({{phone=false,rival=false},{phone=true,rival=false},{phone=false,rival=true}}) do
    local nonword=0
    for seed=1,6000 do
        local kind=L.choose(seed,{opened=100,seen={},beaten={}},"office",available)
        check(kind~="phone" or available.phone,"unavailable telephone stays absent")
        check(kind~="rival" or available.rival,"unavailable USER2 stays absent")
        if kind~="word" and kind~="remember" then nonword=nonword+1 end
    end
    check(nonword>2400 and nonword<4500,"unavailable prerequisites do not trap the Director on words")
end
local player=T.player(100,100,0)
ledger={opened=100,seen=allSeen,beaten={}}
for _,kind in ipairs(L.KINDS) do if kind~="card" then ledger.beaten[kind]=true end end
L.reset()
check(not L.awardLicense(player) and not ledger.licensee,"new license requires the tenth card lock")
ledger.beaten.card=true
check(L.awardLicense(player) and ledger.licensee~=nil,"card recovery completes a new ten-kind license")
ledger.licensee="PREVIOUS OPERATOR";ledger.beaten.card=nil
check(not L.awardLicense(player) and ledger.licensee=="PREVIOUS OPERATOR","existing LICENSED title is retained before card recovery")
check(L.recovery():find("9/10",1,true)~=nil,"recovery log reports the current ten-kind target")
ModData,SC.TerminalLockRival.hasRecruitable=oldMod,oldRecruitable;L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; LARCH/KEY Director: "..(T.checks-before).." checks passed"
