-- SPDX-License-Identifier: MIT
-- Director integration, not a second implementation of its probability rules.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local D,P,S,L,Drawers=SC.TerminalPersonaDiscovery,SC.TerminalPersona,SC.TerminalSystem,SC.TerminalLocks,SC.TerminalDrawers
local check,before=T.check,T.checks
local saved={mod=ModData,options=SandboxVars,debug=isDebugEnabled,config=SCConfig,nativeConfig=SC.Config,
    find=Drawers.find,claim=Drawers.claim,days=SC.TerminalPayoff.daysSinceOutbreak,
    world=SC.TerminalWorld.new,kind=SC.TerminalWorld.computerKind}
local raw,day,free,claimOkay,finds,claims={},23,true,true,0,0
ModData={getOrCreate=function() return raw end}
SandboxVars={LivingFellows={RareComputers=2,LockRealItems=true,LockedComputerPercent=100}}
SCConfig={} isDebugEnabled=function() return false end
SC.TerminalPayoff.daysSinceOutbreak=function() return day end
SC.TerminalWorld.new=function() return {camp=function() return {inside=false} end} end
SC.TerminalWorld.computerKind=function(pc) return pc.kind or "office" end
Drawers.find=function() finds=finds+1 return free and {x=100,y=100,z=0,type="desk"} or nil end
Drawers.claim=function(_,_,state)
    check(state.lock.realItems==true,"real-item policy is set before claim")
    claims=claims+1
    if claimOkay then state.lock.drawer={x=100,y=100,z=0,type="desk"} end
end
local player=T.player(101,100,0)
local pc=T.computer(T.square(100,100,0,true)) pc.kind="clinic"
local serial=0
local function state(seed,brand)
    serial=serial+1
    local s=S.create(seed or 1,"home",false,false,"discovery:"..serial,brand) s.brand=brand
    return s
end
local function book(boots,met,last)
    raw={opened=17,persona={boots=boots or 30,met=met or {},lastAt=last}}
    L.reset() L.ledger() return raw.persona
end
local function seedFor(id,kind,brand)
    for seed=1,10000 do
        local b={boots=30,met={}}
        for _,other in ipairs(P.ORDER) do if other~=id then b.met[other]=true end end
        if P.choose(b,kind,brand,seed,true,2,false,23)==id then return seed end
    end
    error("no deterministic seed for "..id)
end
local seeds={spiffy=seedFor("spiffy","retail","Spiffos"),ellis=seedFor("ellis","clinic"),duty=seedFor("duty","security")}
book()
for _,locked in ipairs({true,false}) do
    local old=state(seeds.ellis) old.fresh=nil old.locked=locked
    if not locked then old.lock=nil end
    local copy=S.normalize(old)
    check(not D.settle(copy,player,pc,false) and copy.locked==locked and raw.persona.boots==30,
        "old locked/unlocked saves never roll or consume Director boots")
end
local legacy=S.create(1,"home",false,true,"legacy-import")
check(not legacy.fresh and not D.settle(legacy,player,pc,false),"legacy EMMA import is not a newly discovered machine")
local factory=state() factory.archive="_factory"
check(not D.settle(factory,player,pc,false) and not factory.fresh and raw.persona.boots==30,"factory archive never rolls")
local camp=state(seeds.ellis)
check(not D.settle(camp,player,pc,true) and raw.persona.boots==30,"home machines are excluded before Director")
day=22 finds=0 local july=state(seeds.ellis)
check(not D.settle(july,player,pc,false) and raw.persona.boots==31 and finds==0,"July machines stay ordinary, without a furniture scan")
day=23
local reopened=S.normalize(july)
check(not D.settle(reopened,player,pc,false) and raw.persona.boots==31,"crossing August cannot reroll an opened machine")
SandboxVars.LivingFellows.RareComputers=1 finds=0
check(not D.settle(state(seeds.ellis),player,pc,false) and finds==0,"Off suppresses new personalities without scanning furniture")
SandboxVars.LivingFellows.RareComputers=2 SandboxVars.LivingFellows.LockRealItems=false finds=0
check(not D.settle(state(seeds.ellis),player,pc,false) and finds==0,"real-items Off suppresses the entire feature")
SandboxVars.LivingFellows.LockRealItems=true free=false
check(not D.settle(state(seeds.ellis),player,pc,false) and not raw.persona.met.ellis,"a missing drawer cannot spend a personality")
free=true
for _,id in ipairs(P.ORDER) do
    local met={} for _,other in ipairs(P.ORDER) do if other~=id then met[other]=true end end
    book(30,met) pc.kind=id=="spiffy" and "retail" or id=="ellis" and "clinic" or "security"
    local s=state(seeds[id],id=="spiffy" and "Spiffos" or nil)
    check(D.settle(s,player,pc,false) and s.lock.persona.id==id and s.lock.drawer
        and s.theme==SC.TerminalPersonaData[id].theme,"natural discovery installs "..id.." and its physical claim")
    check(raw.opened==17 and not raw.seen.persona and raw.persona.met[id],"persona has a separate world ledger")
end
book(30,{spiffy=true,duty=true}) pc.kind="clinic" claimOkay=false
local noClaim=state(seeds.ellis) local priorLock,priorTheme=noClaim.lock,noClaim.theme
check(not D.settle(noClaim,player,pc,false) and noClaim.lock==priorLock and noClaim.theme==priorTheme
    and raw.persona.boots==31 and not raw.persona.met.ellis and raw.persona.lastAt==nil,
    "failed physical claim restores the original computer and unique-personality allowance")
claimOkay=true
book(0,{}) pc.kind="clinic"
for i=1,6 do check(not D.settle(state(seeds.ellis),player,pc,false),"first-six tour boot "..i) end
check(raw.persona.boots==6,"all first boots count toward the tour")
book(30,{spiffy=true,duty=true},27)
check(not D.settle(state(seeds.ellis),player,pc,false),"eight-computer spacing applies through integration")
book(30,{spiffy=true,ellis=true}) pc.kind="office"
local underground=T.computer(T.square(5555,12484,-13,true)) underground.kind="office"
local duty=state(123)
check(D.settle(duty,player,underground,false) and duty.lock.persona.id=="duty" and duty.lock.home.z==-13,
    "real deep coordinates guarantee Duty regardless of ordinary probability")
book(0,{}) day=22
check(not D.settle(state(123),player,underground,false),"deep guarantee still requires August")
day=23 book(0,{})
check(D.settle(state(123),player,underground,false),"deep guarantee is the deliberate tour exception")
book(30,{}) SandboxVars.LivingFellows.RareComputers=1
check(not D.settle(state(123),player,underground,false),"Off also suppresses deep guarantee")
SandboxVars.LivingFellows.RareComputers=2
-- Natural uniqueness and spacing survive serialized ledger copies/reloads.
book(0,{}) local found,last={},nil
for i=1,1200 do
    pc.kind=i%3==0 and "clinic" or i%3==1 and "security" or "retail"
    local s=state(i*53,i%3==2 and "Spiffos" or nil)
    if D.settle(s,player,pc,false) then
        local id=s.lock.persona.id
        check(not found[id],"a personality is unique across natural discoveries")
        if last then check(raw.persona.boots-last>=8,"natural discoveries keep eight-computer spacing") end
        found[id]=true last=raw.persona.boots
        local restored={boots=raw.persona.boots,lastAt=raw.persona.lastAt,met={}}
        for k,v in pairs(raw.persona.met) do restored.met[k]=v end
        raw.persona=restored L.reset() L.ledger()
    end
end
check(found.spiffy and found.ellis and found.duty,"natural sequence can discover all three")
local malformed={persona={boots=15.9,lastAt=900,met={ellis=true,spiffy="yes",other=true},extra=true}}
D.normalizeLedger(malformed)
check(malformed.persona.boots==15 and malformed.persona.lastAt==15 and malformed.persona.met.ellis
    and not malformed.persona.met.spiffy and not malformed.persona.met.other and not malformed.persona.extra,
    "world ledger normalizes bounded numbers and only three boolean identities")
-- Debug IDs deliberately bypass dates/rarity, but cannot invent a deep site or drawer.
isDebugEnabled=function() return true end SandboxVars.LivingFellows.RareComputers=1 day=0
for _,id in ipairs(P.ORDER) do
    SCConfig.debugPersona=id book()
    local s=state()
    check(D.settle(s,player,pc,true) and s.lock.persona.id==id and SCConfig.debugPersona==nil,
        "single-use debug override supports "..id)
end
SCConfig.debugPersona="deep" book()
check(not D.settle(state(),player,pc,false) and SCConfig.debugPersona=="deep","deep debug cannot invent coordinates")
check(D.settle(state(),player,underground,false) and SCConfig.debugPersona==nil,"deep debug resolves only at actual deep site")
SCConfig.debugPersona="ellis" SandboxVars.LivingFellows.LockRealItems=false
check(not D.settle(state(),player,pc,false) and SCConfig.debugPersona=="ellis","debug cannot bypass disabled physical rewards")
SandboxVars.LivingFellows.LockRealItems=true
local original=S.create(1,"home",false,false,"factory-clean") original.locked=false
original.lock={kind="persona",persona=P.new("ellis",1)}
local reset=S.factoryReset(original)
check(reset and reset.archive=="_factory" and not reset.fresh and reset.lock==nil,"factory reset strips every persona extension permanently")
ModData,SandboxVars,isDebugEnabled,SCConfig,SC.Config=saved.mod,saved.options,saved.debug,saved.config,saved.nativeConfig
Drawers.find,Drawers.claim=saved.find,saved.claim
SC.TerminalPayoff.daysSinceOutbreak=saved.days SC.TerminalWorld.new,SC.TerminalWorld.computerKind=saved.world,saved.kind
L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Persona discovery: "..(T.checks-before).." checks passed"
