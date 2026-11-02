-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local L,S,W,C=SC.TerminalLocks,SC.TerminalSystem,SC.TerminalLockWords,SC.TerminalLockCrack
local check,before=T.check,T.checks
local oldMod,oldSandbox=ModData,SandboxVars
do
    local previous=SC.TerminalServices
    local duration
    SC.TerminalServices={install=function(_,_,_,ticks) duration=ticks return true end}
    check(SC.TerminalLockCase.queue({}, {},true) and duration==1050,
        "battery recovery passes its full duration before the native action is queued")
    check(SC.TerminalLockCase.queue({}, {},false) and duration==300,
        "jumper recovery passes its base duration before queueing")
    SC.TerminalServices=previous
end
local book={}
ModData={getOrCreate=function(key) check(key=="LF_LockLedger","lock ledger has its own world bucket") return book end}
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
L.reset()
local p=T.player(101,100,0) local pc=T.computer(T.square(100,100,0,true))
local first=S.create(101,"office",false,false,"first")
check(first.lock.kind=="pending","new locks wait until first actual use")
L.settle(first,p,pc)
check(first.lock.kind=="remember" and book.opened==1,"first discovered lock is Remembers")
local answer=first.puzzle.answer
L.settle(first,p,pc)
check(book.opened==1 and first.puzzle.answer==answer,"reopening never rerolls or advances the Director")
local second=S.create(201,"office",false,false,"second") L.settle(second,p,pc)
check(second.lock.kind=="word" and book.opened==2,"second discovered lock preserves the classic puzzle")
local used={}
book.usedArchives={} book.opened=0
for i=1,29 do
    local state=S.create(1,"office",false,false,"owner:"..i) L.settle(state,p,pc)
    check(not used[state.archive],"all 29 office/general owners are used before repeating") used[state.archive]=true
end
local opened=book.opened
local legacy=S.create(1,"office",false,false,"legacy") legacy.lock=nil
legacy=S.normalize(legacy) L.settle(legacy,p,pc)
check(legacy.lock.legacy and legacy.lock.kind=="word" and book.opened==opened,"old locked saves retain their puzzle without joining the Director")
legacy.locked=false legacy.lock=nil
check(S.normalize(legacy).lock==nil,"old unlocked computers stay unlocked without a new payoff")
local classic=S.create(301,"office",false,false,"classic")
SandboxVars.LivingFellows.ClassicLocksOnly=true L.settle(classic,p,pc)
check(classic.lock.kind=="word" and book.opened==opened,"classic-only skips Director progression")
SandboxVars.LivingFellows.ClassicLocksOnly=false
SandboxVars.LivingFellows.LockedComputerPercent=0
check(not S.create(1,"office",false,false,"none").locked,"zero percent creates no new locks")
SandboxVars.LivingFellows.LockedComputerPercent=100
local remembered=0
for _,profile in ipairs(SC.TerminalFiles.all()) do for skill=0,10 do
    local state=S.create(1,profile.kind,false,false,"archive:"..profile.id..":"..skill)
    state.archive=profile.id state.lock.kind="remember"
    local puzzle=W.ensure(state,skill) local count=S.settings(skill)
    check(#puzzle.words==count and puzzle.skill==skill,"archive vocabulary exactly fills each Electrical board size")
    check(S.normalize(state)~=nil,"every archive board survives strict schema-one normalization")
    local seen={}
    for _,word in ipairs(puzzle.words) do check(not seen[word] and #word==6,"archive words and decoys are unique six-letter candidates") seen[word]=true end
    check(seen[puzzle.answer],"answer is always a displayed candidate")
    if state.lock.kind=="remember" then
        remembered=remembered+1
        check(W.sentence(state,puzzle.answer)~=nil,"Remembers answer comes from actual entry text")
    end
end end
check(remembered>1700,"all ordinary owner archives have usable memory vocabulary")
local malformed=S.create(1,"office",false,false,"bad-extension")
malformed.lock={kind="future-unknown",stash={committed=true,items={{id="already-added",type="Base.Battery"}}}}
local clean=S.normalize(malformed)
check(clean and clean.identity==malformed.identity and clean.lock.kind=="word" and clean.lock.stash.committed,
    "unknown lock extensions preserve the computer and prevent ambiguous reward replay")
local state=S.create(1,"office",false,false,"crack-clock") state.archive="dispatch_morrow"
state.lock.kind="word" state.lock.crack={doneHours=2,requiredHours=12,lastHours=100,powered=true}
C.catchUp(state,104,true) check(state.lock.crack.doneHours==6,"powered return catches up lazily")
C.catchUp(state,109,false) check(state.lock.crack.doneHours==6,"currently unpowered machine earns no interval")
C.catchUp(state,112,true) check(state.lock.crack.doneHours==6,"a last-known outage earns no interval")
C.catchUp(state,113,true) check(state.lock.crack.doneHours==7,"power restored starts a new credited interval")
C.catchUp(state,110,true) C.catchUp(state,113,true)
check(state.lock.crack.doneHours==7,"backward clocks cannot replay previously credited hours")
check(C.password(state)=="MORROW93","slow crack uses the actual owner's surname")
local welcome=SC.TerminalPayoff.welcome(state)
check(welcome.name=="WELCOME BACK, HELEN." and #welcome.document>=10,"payoff uses the real owner and a substantial final sentence")
local curated=0
for id,row in pairs(SC.TerminalLockStashes) do
    local profile=SC.TerminalFiles.get(id) local found=false
    for _,entry in ipairs(profile and profile.entries or {}) do if entry.text:find(row.quote,1,true) then found=true end end
    check(profile and found and #row.items>0,"each curated promise quotes a real file and has concrete native items") curated=curated+1
end
check(curated==36,"all supplied item promises are covered")
local w={system=state}
state.lock.crewHint=false
check(SC.TerminalLockCase.risk(state,0,false)==60 and SC.TerminalLockCase.risk(state,10,false)==10,"hardware reset risk shows its exact bounded skill effect")
check(SC.TerminalLockCase.risk(state,0,true)==30,"battery path halves reset risk")
local distribution={}
local tested={}
for _,kind in ipairs(L.KINDS) do distribution[kind]={total=0,slips=0} tested[kind]=true end
for seed=1,50000 do
    local kind=L.choose(seed,{opened=100,seen=tested,beaten=tested})
    local row=distribution[kind] row.total=row.total+1
    if SC.TerminalLockCase.roll({seed=seed})<=35 then row.slips=row.slips+1 end
end
for _,row in pairs(distribution) do
    check(row.slips/row.total>.29 and row.slips/row.total<.41,"hardware risk is independent of the selected lock type")
end
local broken=S.create(1,"police",false,false,"bad-crack")
broken.lock={kind="word",crack={doneHours="not a clock"},stash={committed=true,items={}}}
check(S.normalize(broken).lock.stash.committed,"a malformed sub-record cannot recreate previously committed cargo")
ModData,SandboxVars=oldMod,oldSandbox L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Locked computers: "..(T.checks-before).." data, progression and persistence checks passed"
