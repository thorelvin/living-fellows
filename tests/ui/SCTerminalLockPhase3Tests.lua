-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local L,S,P,R,V=SC.TerminalLocks,SC.TerminalSystem,SC.TerminalLockPhone,SC.TerminalLockRadio,SC.TerminalLockRival
local check,before=T.check,T.checks
local old={mod=ModData,cell=getCell,time=getGameTime,paused=isGamePaused,world=getWorld,sound=addSound,
    factions=SC.Factions,oddballs=SC.Oddballs,radio=getZomboidRadio,specific=getSpecificPlayer,perks=Perks,contains=SC.GameplayUtil.containerContainsIdentity}
local ledger={} ModData={getOrCreate=function() return ledger end} L.reset()
local paused=false local tod=2.9
isGamePaused=function() return paused end
getGameTime=function() return {getWorldAgeHours=function() return T.hours end,getTimeOfDay=function() return tod end} end
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
Perks={Electricity="Electricity"}
local groups={} SC.Factions={list=function() return groups end,group=function(id) for _,g in ipairs(groups) do if g.id==id then return g end end end}
SC.Oddballs={definition=function(id) return id=="real" and {recruitment=true,identity={forename="June"}} or {recruitment=false} end}
local group={id="native-shaped-group",oddball={id="real"},location={coordinates={x=900,y=950,z=0}},lifecycle="active",members={{}}}
check(#V.candidates()==0,"no group means no fictional USER2")
groups={group}
check(V.eligible(group) and V.candidates()[1]==group,"real recruitable group coordinates are recognized")
for _,field in ipairs({"discovered","destroyed","joined"}) do
    group.discovered=field=="discovered" group.lifecycle=field=="destroyed" and "destroyed" or "active"
    group.recruitment=field=="joined" and {joinedActorId="companion"} or nil
    check(not V.eligible(group),"discovered, dead or recruited groups cannot become USER2")
end
group.discovered=false group.lifecycle="active" group.recruitment=nil
local seen={} for _,kind in ipairs(L.KINDS) do seen[kind]=true end
local counts={} for _,kind in ipairs(L.KINDS) do counts[kind]=0 end
for seed=1,100000 do local kind=L.choose(seed,{opened=99,seen=seen,beaten=seen},"general",{phone=true,rival=true}) counts[kind]=counts[kind]+1 end
for kind,count in pairs(counts) do check(math.abs(count/1000-L.WEIGHTS[kind]/100*100)<1,"Phase 3 normalized rates: "..kind) end
local nonword=0
for seed=1,10000 do
    local kind=L.choose(seed,{opened=99,seen={},beaten={}},"office",{phone=false,rival=false})
    check(kind~="phone" and kind~="rival","unavailable locks stay absent")
    if kind~="word" and kind~="remember" then nonword=nonword+1 end
end
check(nonword>4000 and nonword<6500,"missing prerequisites never leave the Director stuck on words")
for _,kind in ipairs({"radio","phone","rival","story"}) do
    for seed=1,500 do check(L.choose(seed,{opened=99,seen=seen,beaten=seen,lastRare=kind},"general")~=kind,"post-tour rare locks never repeat") end
end
local square=T.square(100,100,0,true) local stand=T.square(101,100,0,true)
local building={getX=function() return 100 end,getY=function() return 100 end,getX2=function() return 110 end,getY2=function() return 110 end}
function square:getBuildingDef() return building end function stand:getBuildingDef() return building end
function stand:canReachTo() return true end
local phone=T.computer(stand,"Telephone") phone.index=2
function phone:getSprite() return {getName=function() return "location_business_office_generic_02_8" end} end
function stand:getRoom() return {getName=function() return "reception" end} end
getCell=function() return {getGridSquare=function(_,x,y,z) if z==0 and x==100 and y==100 then return square elseif z==0 and x==101 and y==100 then return stand end end,getZombieList=function() return {size=function() return 0 end} end} end
local player=T.player(101,100,0) local inv={items={}}
function inv:getItems() return self.items end
SC.GameplayUtil.containerContainsIdentity=function(container,item)
    for _,candidate in ipairs(container.items or {}) do if candidate==item then return true end end return false
end
function player:getSquare() return stand end function player:getInventory() return inv end
local skill,xp=5,0 function player:getPerkLevel() return skill end
function player:getXp() return {AddXP=function(_,_,amount) xp=xp+amount end} end
getSpecificPlayer=function() return player end
SC.Terminal._clock=function() return T.now end
local function open(kind,seed)
    if SC.Terminal.window then SC.Terminal.window:close() end
    local pc=T.computer(square) local state=S.create(seed or 731,"police",false,false,"phase3:"..kind..":"..T.checks)
    state.lock.kind=kind state.lock.settled=true state.archive="dispatch_bell"
    if kind=="rival" then state.lock.rivalGroup=group.id end
    pc.data.movableData={LF_LarchOS=state}
    check(SC.Terminal.open(player,pc),"real terminal opens Phase 3 "..kind)
    local w=SC.Terminal.window w:flush() return w,pc
end
local function input(w,text) w:setFocusMode("chat") w:setEntryText(text) w:submit() end
local w,pc=open("phone",731)
P.search(w) check(w.system.lock.phone and not w.lockPhoneSearch and ledger.seen.phone,"bounded phone search commits a genuine same-building location")
local normalized=S.normalize(w.system)
check(normalized.lock.phone.room=="reception" and normalized.lock.kind=="phone","telephone coordinates survive normalization")
local calls,stops,noises=0,0,0
local emitter={playSound=function() calls=calls+1 return calls end,stopAll=function() stops=stops+1 end}
getWorld=function() return {getFreeEmitter=function() return emitter end,takeOwnershipOfEmitter=function() end,returnOwnershipOfEmitter=function() end} end
addSound=function(_,_,_,_,radius,volume) check(radius==18 and volume==60,"ring has a bounded native attraction radius") noises=noises+1 end
input(w,P.code(w.system)) check(w.system.locked,"unheard phone code cannot unlock")
w.lockCodeVerified=true L.finishUnlock(w,"phone") w.lockCodeVerified=nil
check(w.system.locked,"unheard phone code cannot unlock through the completion boundary")
input(w,"1") T.now=T.now+100 P.pulse(T.now)
check(P.ringing() and calls==1 and noises==1,"explicit Place call starts one native ring and noise")
w:close() for _=1,10 do T.now=T.now+100 P.pulse(T.now) end
check(P.ringing(),"ring survives leaving the CRT")
check(P.answer(player,phone),"exact nearby phone can be answered")
check(not P.ringing() and pc.data.movableData.LF_LarchOS.lock.heard,"answer cancels ring and records a heard code")
check(SC.Terminal.open(player,pc),"return to callback computer") w=SC.Terminal.window w:flush()
local paid=xp input(w,P.code(w.system))
check(not w.system.locked and xp-paid==60,"typed heard phone key awards tier-three XP once")
L.finishUnlock(w,"phone") check(xp-paid==60,"callback XP cannot replay")
w,pc=open("phone",733) P.search(w) input(w,"1")
for _=1,5 do T.now=T.now+100 P.pulse(T.now) end
paused=true local n=noises for _=1,100 do T.now=T.now+100 P.pulse(T.now) end
check(noises==n,"paused telephone never advances cadence") paused=false
square.generatorPower=false T.now=T.now+100 P.pulse(T.now) check(not P.ringing(),"phone stops immediately on power loss") square.generatorPower=true
w,pc=open("phone",734) P.search(w)
local nativeSound=emitter.playSound emitter.playSound=function() return 0 end
input(w,"1") T.now=T.now+100 P.pulse(T.now)
check(P.ringing() and P.answer(player,phone),"muted audio does not prevent answering the telephone")
emitter.playSound=nativeSound
local definition=square.getBuildingDef square.getBuildingDef=function() return {} end
check(not P.dial(w),"a moved computer cannot call a different building's internal line") square.getBuildingDef=definition
w,pc=open("phone",735) phone.index=-1 stand.objects={}
for _=1,100 do if not w.lockPhoneSearch then break end P.search(w) end
check(w.system.lock.kind=="word" and w.system.puzzle and not w.lockPhoneSearch,"missing phone safely falls back after bounded search")
phone.index=2 stand.objects={phone}
do
    local bx,by,bx2,by2=building.getX,building.getY,building.getX2,building.getY2
    building.getX=function() return 60 end building.getY=function() return 60 end
    building.getX2=function() return 140 end building.getY2=function() return 140 end
    stand.objects={} w,pc=open("phone",736)
    local original=getCell local reads=0
    getCell=function() local cell=original() local get=cell.getGridSquare
        cell.getGridSquare=function(...) reads=reads+1 return get(...) end return cell end
    for _=1,100 do
        if not w.lockPhoneSearch then break end
        local prior=reads P.search(w) check(reads-prior<=128,"phone discovery never reads more than 128 squares per update")
    end
    check(reads==4096 and not w.lockPhoneSearch and w.system.lock.kind=="word","phone discovery stops at the hard 4096-square bound")
    getCell=original stand.objects={phone}
    building.getX,building.getY,building.getX2,building.getY2=bx,by,bx2,by2
end

-- Native-shaped receipt transport. A sent key is not proof it was heard.
do
    local history={}
    for i=1,100 do history[string.format("%08d",10000000+i)]={identity="old-radio-"..i,at=i} end
    local saved={heard=history} R.normalize(saved) local retained=0
    for _ in pairs(saved.heard) do retained=retained+1 end
    check(retained==100,"heard recovery keys survive beyond sixty four computers")
end
local radio={container=inv} local data={}
inv.items={radio}
function radio:getContainer() return self.container end function radio:getDeviceData() return data end
function player:getEquipedRadio() return radio end function player:getPrimaryHandItem() return radio end
function data:getIsTelevision() return false end function data:getChannel() return R.CHANNEL end
function data:getIsTurnedOn() return true end function data:getHasBattery() return true end
function data:getPower() return 1 end function data:getDeviceVolume() return 1 end
local sent={}
getZomboidRadio=function() return {SendTransmission=function(_,x,y,ch,text,guid,code,r,g,b,range)
    check(x==12000 and y==9000 and range==100000,"escrow always uses fixed long-range tower")
    sent[#sent+1]={guid=guid,code=code,text=text}
end} end
R.reset() ledger={} L.reset() T.hours=50.9 tod=2.9
w,pc=open("radio",737)
local state=w.system local serial=state.lock.serial
check(serial and #ledger.pending==1 and not R.heard(state),"radio registers one bounded pending serial")
R.register(state) check(#ledger.pending==1,"reopening never duplicates a pending serial")
T.now=T.now+1000 R.pulse(T.now) check(#sent==0,"recovery station never starts before crossing 03:00")
input(w,R.code(state.seed,serial)) check(state.locked,"unheard broadcast key never unlocks")
ledger.radioHeardCount=2
tod=3.01 T.hours=51.01 T.now=T.now+1000 R.pulse(T.now)
check(#sent==1,"crossing 03:00 starts exactly one nightly broadcast")
T.now=T.now+6000 R.pulse(T.now) local keyLine=sent[#sent]
check(not R.heard(state),"sending a key does not manufacture reception")
R.onDeviceText(keyLine.guid,"WRONG",-1,-1,-1,keyLine.text,radio)
check(not R.heard(state),"unrelated radio events cannot create a receipt")
R.onDeviceText(keyLine.guid,keyLine.code,-1,-1,-1,keyLine.text,radio)
check(R.heard(state) and ledger.radioHeardCount==3 and #ledger.pending==0,"native matching receipt records key once and releases queue slot")
R.onDeviceText(keyLine.guid,keyLine.code,-1,-1,-1,keyLine.text,radio)
check(ledger.radioHeardCount==3,"duplicate callbacks cannot replay the third call")
T.now=T.now+6000 R.pulse(T.now) T.now=T.now+6000 R.pulse(T.now)
check(sent[#sent].text=="GO TO BED, THOR." and ledger.radioNamed,"third heard call uses real forename exactly once")
paid=xp input(w,"999999") check(table.concat(R.lines(w)," "):find(R.code(state.seed,serial),1,true),"heard key is shown after one wrong entry")
input(w,R.code(state.seed,serial)) check(not state.locked and xp-paid==60,"heard typed radio key completes normal tier-three payoff")
check(S.normalize(state).lock.serial==serial,"radio identity and heard receipt survive reload")
local oldSent=#sent for _=1,20 do T.now=T.now+1000 R.pulse(T.now) end check(#sent==oldSent,"empty queue has no radio work")
R.reset() ledger={} L.reset() sent={} T.hours=74.9 tod=2.9
local pendingStates={}
for i=1,5 do
    local os=S.create(10000+i,"police",false,false,"queued-"..i) os.lock.kind="radio"
    R.register(os) pendingStates[i]=os
end
T.hours=75.01 tod=3.01 T.now=T.now+1000 R.pulse(T.now)
for _=1,20 do T.now=T.now+6000 R.pulse(T.now) end
check(#sent==12 and #ledger.pending==5,"station sends at most three calls in one night, retaining unheard entries")
local first=sent[1].text paused=true
for _=1,10 do T.now=T.now+1000 R.pulse(T.now) end
check(#sent==12,"paused station cannot send or catch up lines") paused=false
T.hours=T.hours+24 T.now=T.now+1000 R.pulse(T.now)
check(#sent==13 and sent[13].text~=first,"unheard serials rotate fairly on the next night")
R.reset() T.hours=T.hours+24*14 T.now=T.now+1000 R.pulse(T.now)
check(#ledger.pending==0,"fourteen unheard nights release stale serials")
check(R.register(pendingStates[1]) and #ledger.pending==1,"opening an expired machine registers it again")
for i=1,20 do local os=S.create(20000+i,"police",false,false,"bounded-queue-"..i) os.lock.kind="radio" R.register(os) end
check(#ledger.pending==16,"escrow queue never exceeds sixteen machines")
R.reset()

-- Timed rival uses observations without spending the player's attempts.
for seed=1,30 do
    group.discovered=false group.lifecycle="active"
    w,pc=open("rival",800+seed)
    local r=w.system.lock.rival local tries=w.system.puzzle.tries
    V.update(w,T.now) T.now=T.now+250 V.update(w,T.now)
    check(#r.guesses==0,"USER2 waits a full fifteen seconds before guessing")
    paused=true local remaining=r.remainingMs T.now=T.now+5000 V.update(w,T.now)
    check(r.remainingMs==remaining,"paused rival never advances") paused=false
    for i=1,4 do
        r.remainingMs=0 T.now=T.now+250 V.update(w,T.now)
        check(r.guesses[i] and r.guesses[i].likeness<6,"USER2 cannot choose the answer before its fifth guess")
        check(r.remainingMs>=15000 and r.remainingMs<=25000,"subsequent guesses wait fifteen to twenty-five seconds")
    end
    check(w.system.puzzle.tries==tries,"rival guesses never spend player attempts")
    local save=S.normalize(w.system) check(#save.lock.rival.guesses==4,"rival observations and remaining delay persist")
    local guard=0 paid=xp
    while w.system.locked and guard<16 do guard=guard+1 r.remainingMs=0 T.now=T.now+250 V.update(w,T.now) end
    check(not w.system.locked and r.winner=="user2" and group.discovered and xp-paid==30,"USER2 win discovers the actual group and pays half tier-three XP")
    check(SC.TerminalPayoff.rewardTier(w.system)==2,"USER2 win lowers the physical reward one tier")
end
group.discovered=false w,pc=open("rival",999)
input(w,"other ways in") check(not w.lockConfirm and not w.system.lock.bypass,"race must finish before alternative recovery")
paid=xp input(w,w.system.puzzle.answer)
check(not w.system.locked and w.system.lock.rival.winner=="player" and group.discovered and xp-paid==60,"player win reveals correct real group and full reward")
group.discovered=false w,pc=open("rival",1001) group.lifecycle="destroyed"
T.now=T.now+250 V.update(w,T.now)
check(not w.system.locked and w.system.lock.rival.lost,"destroyed rival group cannot strand the computer")
for _,kind in ipairs({"phone","radio","rival"}) do
    local s=S.create(1,"police",false,false,"malformed") s.lock.kind=kind s.lock.rival={remainingMs="broken",guesses={}}
    check(S.normalize(s).lock.kind=="word","malformed rare extension conservatively keeps the machine")
end
local core=getCore
for _,resolution in ipairs({{800,600},{1280,720},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return resolution[1] end,getScreenHeight=function() return resolution[2] end} end
    for _,kind in ipairs({"phone","radio","rival"}) do
        group.lifecycle="active" group.discovered=false
        w,pc=open(kind,1101) if kind=="phone" then P.search(w) end
        w:drawSecurity()
        local dial=false
        for _,hit in ipairs(w.securityHits) do
            check(hit.x>=w.layout.left-1 and hit.x+hit.width<=w.layout.right+1,"rare-lock hit regions stay within screen width")
            check(hit.y>=w:viewTop()-1 and hit.y+w.rowHeight<=w:viewBottom()+1,"rare-lock choices do not overlap input")
            if hit.value=="1" then dial=true end
        end
        if kind=="phone" then check(dial,"Place call remains clickable at compact and large resolutions") end
    end
end
getCore=core
P.reset() R.reset() if SC.Terminal.window then SC.Terminal.window:close() end
ModData,getCell,getGameTime,isGamePaused,getWorld,addSound=old.mod,old.cell,old.time,old.paused,old.world,old.sound
SC.Factions,SC.Oddballs,getZomboidRadio,getSpecificPlayer,Perks=old.factions,old.oddballs,old.radio,old.specific,old.perks
SC.GameplayUtil.containerContainsIdentity=old.contains
L.reset()
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Phase 3 rare-lock checks: "..(T.checks-before).." passed"
