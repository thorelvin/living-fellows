-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Search,Wheel,Emma,L,S=SC.TerminalLockSearch,SC.TerminalLockWheel,SC.TerminalLockEmma,SC.TerminalLocks,SC.TerminalSystem
local check,before=T.check,T.checks
local old={cell=getCell,mod=ModData,sandbox=SandboxVars,registry=SC.Registry,factory=InventoryItemFactory,
    perks=Perks,core=getCore,clock=SC.Terminal._clock}
local ledger={} ModData={getOrCreate=function() return ledger end} L.reset()
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
Perks=Perks or {Electricity="Electricity"}
SC.Registry={living=function() return {} end}
SC.Terminal._clock=function() return T.now end

-- Every owner has a purely clickable path, including the twenty new owners.
for _,profile in ipairs(SC.TerminalFiles.all()) do
    local state={archive=profile.id,lock={found={},search={misses=0}}}
    local words=Search.indexes(profile.id)
    for index=1,4 do
        check(Search.valid(words[index])~=nil,"every owner entry has a valid index: "..profile.id.."/"..index)
        for other,entry in ipairs(profile.entries) do
            if other~=index then check(not entry.text:lower():find(words[index],1,true),"index belongs to only one entry of that owner") end
        end
    end
    for _=1,4 do
        local word,index=Search.nextIndex(state)
        local rows=Search.query(state,word)
        check(rows and rows[1] and rows[1].own and rows[1].index==index,"owner hits precede every other owner, including common corpus hits")
        state.lock.found[#state.lock.found+1]=index
    end
    check(Search.nextIndex(state)==nil,"index-only player restores all four files")
    for _,query in ipairs({"%","(","[","","the","a very long query that exceeds thirty two letters"}) do
        local okay,rows=pcall(Search.query,state,query)
        check(okay and rows==nil,"junk input never becomes a Lua pattern")
    end
end

-- Director tours and the normalized active-phase weight table.
local seen={} local counts={}
for _,kind in ipairs(L.KINDS) do counts[kind]=0 end
for n=1,15 do
    local kind=L.choose(333+n,{opened=n-1,seen=seen})
    if n==1 then check(kind=="remember","tour begins with Remembers") end
    if n==2 then check(kind=="word","second tour lock is the original puzzle") end
    if n==3 then check(kind=="wheel" or kind=="emma" or kind=="search","third tour lock is medium") end
    if n%2==1 and n<=7 then check(not seen[kind],"medium tour never repeats while something is unseen") end
    seen[kind]=true
end
for _,kind in ipairs(L.KINDS) do check(seen[kind],"all five built locks appear during the first tour") end
for seed=1,100000 do counts[L.choose(seed,{opened=100,seen=seen,beaten=seen})]=counts[L.choose(seed,{opened=100,seen=seen,beaten=seen})]+1 end
local total=0 for _,weight in pairs(L.WEIGHTS) do total=total+weight end
for kind,count in pairs(counts) do check(math.abs(count/1000-L.WEIGHTS[kind]/total*100)<1,"normal-phase rates follow active weights: "..kind) end

-- Fixed wheel mapping: all marker/letter/window combinations round-trip.
for marker=1,4 do for letter=0,25 do for window=1,3 do
    local c={marker=marker,letter=letter,window=window}
    local rotation=Wheel.rotationFor(c)
    check((SC.TerminalLockWheelData.markers[marker].position+rotation)%26==letter,"symbol aligns to requested outer letter")
    check(#Wheel.read(rotation,window)==1,"each window returns exactly one printable letter")
end end end

local square=T.square(100,100,0,true) square.world={}
function square:TreatAsSolidFloor() return true end
function square:getWorldObjects() return self.world end
local room={getName=function() return "office" end}
function square:getRoom() return room end
local desk={getSurfaceOffsetNoTable=function() return 34 end}
square.objects[#square.objects+1]=desk
local neighbor=T.square(101,100,0,true)
getCell=function() return {getGridSquare=function(_,x,y,z)
    if x==100 and y==100 and z==0 then return square elseif x==101 and y==100 and z==0 then return neighbor end
end,getZombieList=function() return {size=function() return 0 end} end} end
local player=T.player(101,100,0) local bag={items={}}
function bag:getItems() return self.items end
function player:getInventory() return bag end
function player:getSquare() return neighbor end
local xp,skill,serial,adds=0,5,0,0
function player:getPerkLevel() return skill end
function player:getXp() return {AddXP=function(_,_,amount) xp=xp+amount end} end
function player:getPrimaryHandItem() return self.hand end
local currentPC
InventoryItemFactory={CreateItem=function(kind)
    serial=serial+1 local item={id=serial,kind=kind}
    function item:getFullType() return self.kind end function item:getID() return self.id end
    function item:getWorldItem() return self.world end
    function item:getContainer() return self.container end
    return item
end}
function square:AddWorldInventoryItem(item,x,y,z)
    check(currentPC.data.movableData.LF_LarchOS.lock.manualSpawned,"manual spawn receipt precedes native insertion")
    adds=adds+1 self.lastHeight=z item.world={getItem=function() return item end,getSquare=function() return square end}
    self.world[#self.world+1]=item.world return item
end
local function open(kind,seed,archive)
    if SC.Terminal.window then SC.Terminal.window:close() end
    local pc=T.computer(square) currentPC=pc
    local state=S.create(seed or 79,"office",false,false,"phase2:"..kind..":"..serial..":"..T.checks)
    state.archive=archive or "dispatch_bell" state.lock.kind=kind state.lock.settled=true
    pc.data.movableData={LF_LarchOS=state}
    check(SC.Terminal.open(player,pc),"real terminal opens the "..kind.." page")
    local w=SC.Terminal.window w:flush()
    return w,pc
end
local function submit(w,raw) w:setFocusMode("chat") w.entry:setText(raw) w:submit() end
local function bounds(w)
    w:drawSecurity()
    local footer={} for _,option in ipairs(SC.TerminalLockUI.footer(w)) do footer[option.value]=true end
    for _,hit in ipairs(w.securityHits) do
        check(hit.x>=w.layout.left-1 and hit.x+hit.width<=w.layout.right+1,"click targets stay inside the body width")
        check(hit.y>=w:viewTop()-1 and hit.y+(hit.height or w.rowHeight)<=w:viewBottom()+1,"click targets stay above the input area")
        if not footer[hit.value] then
            for _,button in ipairs(w.securityHits) do
                if footer[button.value] then
                    local overlap=hit.x<button.x+button.width-1 and hit.x+hit.width>button.x+1
                        and hit.y<button.y+w.rowHeight-1 and hit.y+(hit.height or w.rowHeight)>button.y+1
                    check(not overlap,"body choices never overlap the recovery footer")
                end
            end
        end
    end
end

local w,pc=open("search",401)
for _=1,4 do submit(w,Search.nextIndex(w.system)) end
check(not w.system.locked and w.system.xpAwarded and xp==30,"four restored files use the real tier-two unlock and XP flow")
local paid=xp L.finishUnlock(w,"search") check(xp==paid,"repeated medium unlock cannot replay XP")
w,pc=open("search",403)
for _=1,8 do submit(w,"zzzzunfindable") end
check(w.system.lock.search.misses==8 and w.system.lock.bypass and w.securityMessage:find("INDEX",1,true),"empty searches offer a real hint and the escape routes")
submit(w,Search.nextIndex(w.system))
local saved=S.normalize(w.system)
check(saved.lock.kind=="search" and #saved.lock.found==1,"search progress survives normalization")
local beforeBypass=xp
submit(w,"other ways in") submit(w,"yes") submit(w,"run crack.exe")
submit(w,SC.TerminalLockCrack.password(w.system))
check(not w.system.locked and xp-beforeBypass==30,"early medium crack uses one lower tier, then the early-answer multiplier")

local beforeWheel=xp
w,pc=open("wheel",405)
check(adds==1 and math.abs(square.lastHeight-34/96)<.0001 and w.system.lock.manualItemId,
    "manual is physically placed on the real desk surface once")
check(w.system.lock.wheel.required==3 and Wheel.nearby(player),"a newly found nearby manual keeps three challenges")
local firstManual=adds L.settle(w.system,player,pc)
check(adds==firstManual,"reopen and normalization do not duplicate the manual")
submit(w,"open manual") submit(w,"4")
check(w.lockPage=="manual" and w.lockManualPage==5,"manual can be reached without typing a password")
local rotation=w.system.lock.wheel.rotation w:onMouseWheel(1)
check(w.system.lock.wheel.rotation==(rotation+1)%26,"mouse wheel rotates the code wheel")
Keyboard.KEY_LEFT=203 Keyboard.KEY_RIGHT=205 w:otherKey(Keyboard.KEY_LEFT)
check(w.system.lock.wheel.rotation==rotation,"left arrow rotates the same live wheel")
for _=1,3 do
    local c=Wheel.challenge(w.system) w.system.lock.wheel.rotation=Wheel.rotationFor(c)
    submit(w,"answer "..Wheel.read(w.system.lock.wheel.rotation,c.window))
end
check(not w.system.locked and xp-beforeWheel==30,"three real wheel answers unlock once at tier two")
bag.items={InventoryItemFactory.CreateItem(Wheel.ITEM)}
bag.items[1].container=bag
w,pc=open("wheel",407)
check(w.system.lock.wheel.required==1 and adds==firstManual,"carried handbook gives one challenge and suppresses a new copy")
local wrong=Wheel.answer(w.system)=="A" and "B" or "A"
for _=1,3 do submit(w,wrong) end
check(w.system.lock.wheel.retryUntil==T.hours+1/6 and w.system.lock.bypass,"three wheel failures keep a ten-minute retry and bypass")
local correct=w.system.lock.wheel.correct submit(w,Wheel.answer(w.system))
check(w.system.lock.wheel.correct==correct,"wheel cooldown cannot be bypassed by a correct answer")
T.hours=T.hours+1/6+.001 submit(w,Wheel.answer(w.system))
check(not w.system.locked,"the original challenge remains usable after cooldown")

-- Supplied dialogue is compiled, bounded and interpolated without rewriting it.
local byKind={}
for _,a in ipairs(SC.TerminalLockEmmaData.arguments) do
    byKind[a.kind]=(byKind[a.kind] or 0)+1
    check(#a.text<=66 and #a.accepted<=140 and #a.rejected<=140,"supplied argument and response limits")
    check(not a.text:find("[^\032-\126]"),"argument text remains ASCII")
end
for _,kind in ipairs(Emma.KINDS) do check(byKind[kind]==6,"six original arguments of every kind") end
local function chooseTruthfully(window)
    local e=window.system.lock.emma local facts=Emma.facts(window) local weak,hard=Emma.temperament(window.system)
    local best,bestScore
    for i,offer in ipairs(e.offers) do
        local a=Emma.argument(offer.id) local actual=a.claim and facts[a.claim]
        local valid=not a.claim or type(actual)=="boolean" and actual or type(actual)=="number" and (offer.truthful or offer.number==actual)
        local score=valid and (a.kind==weak and 2 or a.kind==hard and -1 or 1) or -2
        if not bestScore or score>bestScore then best,bestScore=i,score end
    end
    return best
end
for seed=1,80 do
    w,pc=open("emma",seed)
    local used={}
    while w.system.locked and not w.system.lock.emma.retryUntil do
        for _,offer in ipairs(w.system.lock.emma.offers) do
            check(not used[offer.id],"an argument is never presented twice in the same attempt") used[offer.id]=true
        end
        local snapshot=S.normalize(w.system)
        check(snapshot.lock.kind=="emma" and #snapshot.lock.emma.offers==4,"current argument choices survive reload")
        submit(w,tostring(chooseTruthfully(w)))
    end
    check(not w.system.locked,"a player reading the replies can win with truthful arguments")
end

-- A recorded lie retains the original false and true numbers for later visits.
w,pc=open("emma",503)
local e=w.system.lock.emma
e.offers={{id="people_depend",number=9,truthful=false},{id="please"},{id="pull_plug"},{id="knock_knock"}}
submit(w,"1")
check(e.lie and e.lie.actual==0 and e.lie.claimed==9 and e.patience==1,"numeric lies are caught against real records")
e.conviction=3
local weak=Emma.temperament(w.system)
local id for _,a in ipairs(SC.TerminalLockEmmaData.arguments) do if a.kind==weak and not a.claim then id=a.id break end end
e.offers={{id=id},{id="please"},{id="pull_plug"},{id="knock_knock"}}
submit(w,"1")
check(not w.system.locked and e.won,"a later honest argument can still complete the discussion")
w:flush() w:close()
for i=1,4 do
    check(SC.Terminal.open(player,pc),"return to the same unlocked EMMA computer")
    w=SC.Terminal.window w:flush()
    local state=w.system.lock.emma
    check(state.lie.actual==0 and state.lie.claimed==9 and state.mentions==math.min(i,3),"EMMA quotes the actual recorded lie at most three times")
    w:close()
end
local reset=S.factoryReset(w.system)
check(reset and reset.archive=="_factory" and reset.xpAwarded and reset.lock.emma==nil,
    "factory reset clears EMMA's argument memory while retaining the once-only XP receipt")

w,pc=open("emma",509)
local originalFacts=Emma.facts local factReads=0
Emma.facts=function(window) factReads=factReads+1 return originalFacts(window) end
for _=1,20 do w:drawSecurity() end
check(factReads==0,"EMMA rendering never scans live records or threats")
Emma.facts=originalFacts
local round=w.system.lock.emma.round
local wrapped=SC.TerminalLockUI.wrapped(w,{"[1] A deliberately long argument which wraps across several short rows."},18)
for _,row in ipairs(wrapped) do check(row.spans[1] and row.spans[1].value=="1","every wrapped argument row remains clickable") end
w.entry:setText(tostring(chooseTruthfully(w))) w:entryChanged()
check(w.system.lock.emma.round==round+1,"pressing one number chooses an argument without Enter")

w,pc=open("emma",510)
e=w.system.lock.emma
e.offers={{id="days_truth",number=math.floor(T.hours/24)-1,truthful=true},{id="please"},{id="pull_plug"},{id="knock_knock"}}
submit(w,"1")
check(e.round==0 and e.patience==2 and e.offers[1].number==math.floor(T.hours/24),
    "a changed truthful record is updated for review instead of rewriting the chosen claim")

w,pc=open("emma",511)
e=w.system.lock.emma e.patience=1
e.offers={{id="people_depend",number=9,truthful=false},{id="county_order"},{id="pull_plug"},{id="knock_knock"}}
submit(w,"1")
check(e.retryUntil==T.hours+1 and w.system.lock.bypass,"failed argument route closes for one game hour")
local attempt=e.attempt submit(w,"1")
check(e.attempt==attempt and e.round==1,"EMMA cooldown preserves the completed attempt")
T.hours=T.hours+1.001 submit(w,"1")
check(w.system.lock.emma.attempt==attempt+1 and w.system.lock.emma.round==0 and #w.system.lock.emma.offers==4,
    "retry opens fresh choices instead of silently choosing the first argument")
check(w.system.lock.emma.lie and w.system.lock.emma.lie.actual==0 and w.system.lock.emma.lie.claimed==9,
    "an hour's pause resets the attempt but does not erase a real caught lie")
local malformed=S.normalize(w.system)
malformed.lock.emma.offers[1].id="not_a_supplied_argument"
check(S.normalize(malformed).lock.kind=="word" and S.normalize(malformed).lock.stash.committed,
    "malformed argument data falls back without inventing supplies")

do
    local oldDialogue,oldBanter,oldRegistry=SC.Dialogue,SC.Banter,SC.Registry
    local helper=T.player(101,100,0) function helper:getPerkLevel() return 10 end
    local record={id="phase2-helper",actor=helper,recruited=true}
    SC.Registry={records=function() return {record} end,living=function() return {helper} end,
        idOf=function() return record.id end,byId=function() return record end}
    local topics,spoken={},{}
    SC.Banter={availableSpeaker=function() return true end,budgetAllows=function() return true end,spendBudget=function() end}
    SC.Dialogue={has=function(topic) return topics[topic]~=nil end,register=function(topic,lines) topics[topic]=lines end,
        say=function(actor,topic,_,args) spoken[#spoken+1]={actor=actor,topic=topic,value=args[1]} return true end}
    for _,kind in ipairs({"wheel","search","emma"}) do
        w,pc=open(kind,601)
        local expected=kind=="wheel" and Wheel.answer(w.system) or kind=="search" and Search.nextIndex(w.system) or Emma.temperament(w.system)
        local n=#spoken SC.TerminalLockCrew.hint(w)
        check(#spoken==n+1 and spoken[#spoken].actor==helper and spoken[#spoken].value==expected,
            "each phase-two hint speaks its real clue through registered dialogue")
        check(w.system.lock.crewHint and w.system.lock.crewClue.value==expected and w.system.locked,
            "a hint is persisted and never solves the recovery itself")
        SC.TerminalLockCrew.hint(w)
        check(#spoken==n+1,"one companion hint remains one per physical machine")
    end
    SC.Dialogue,SC.Banter,SC.Registry=oldDialogue,oldBanter,oldRegistry
end

-- Compact, standard and large pages retain mouse access and input isolation.
for _,resolution in ipairs({{800,600},{1280,720},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return resolution[1] end,getScreenHeight=function() return resolution[2] end} end
    for _,kind in ipairs({"search","emma","wheel"}) do
        w,pc=open(kind,607)
        if kind=="wheel" then submit(w,"open manual")
            for page=1,5 do w.lockManualPage=page bounds(w) end
        else bounds(w) end
    end
end
if SC.Terminal.window then SC.Terminal.window:close() end
getCell,ModData,SandboxVars,SC.Registry,InventoryItemFactory,Perks,getCore,SC.Terminal._clock=
    old.cell,old.mod,old.sandbox,old.registry,old.factory,old.perks,old.core,old.clock
L.reset()
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Phase 2 locked computers: "..(T.checks-before).." corpus, dialogue, physical manual, persistence and layout checks passed"
