-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local C,L,S=SC.TerminalLockCard,SC.TerminalLocks,SC.TerminalSystem
local check,before=T.check,T.checks
local old={mod=ModData,sandbox=SandboxVars,cell=getCell,factory=InventoryItemFactory,instance=instanceItem,picker=ItemPicker,
    perks=Perks,clock=SC.Terminal._clock,contains=SC.GameplayUtil.containerContainsIdentity,free=SC.GameplayUtil.isSquareFree,
    registry=SC.Registry,locked=SC.TerminalDrawers.locked,physical=SC.TerminalLockPhysical.place,hours=T.hours,now=T.now}
local ledger={} ModData={getOrCreate=function() return ledger end} L.reset()
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
Perks={Electricity="Electricity"} SC.Terminal._clock=function() return T.now end
SC.Registry={living=function() return {} end,records=function() return {} end}
SC.GameplayUtil.containerContainsIdentity=function(container,item)
    for _,candidate in ipairs(container.items or {}) do if item==candidate then return true end end return false
end
SC.GameplayUtil.isSquareFree=function(square) return square.free~=false end
local skill,xp,serial,opens=0,0,0,0
local square=T.square(100,100,0,true) local room={getName=function() return "office" end}
square.room=room square.world={}
function square:getWorldObjects() return self.world end
function square:TreatAsSolidFloor() return true end
local neighbor=T.square(101,100,0,true) neighbor.room=room neighbor.world={}
function neighbor:getWorldObjects() return self.world end
function neighbor:TreatAsSolidFloor() return true end
getCell=function() return {getGridSquare=function(_,x,y,z)
    if z==0 and x==100 and y==100 then return square elseif z==0 and x==101 and y==100 then return neighbor end
end,getZombieList=function() return {size=function() return 0 end} end} end
local function inventory()
    local bag={items={}}
    function bag:getItems() return self.items end
    function bag:getFirstTypeRecurse(kind)
        for _,item in ipairs(self.items) do
            if item.kind==kind then return item end
            local found=item.bag and item.bag:getFirstTypeRecurse(kind) if found then return found end
        end
    end
    return bag
end
local bag=inventory() local player=T.player(101,100,0)
function player:getInventory() return bag end
function player:getSquare() return neighbor end
function player:getPerkLevel() return skill end
function player:getXp() return {AddXP=function(_,_,amount) xp=xp+amount end} end
local function item(kind)
    serial=serial+1 local result={kind=kind,id=serial,data={}}
    function result:getFullType() return self.kind end function result:getID() return self.id end
    function result:getContainer() return self.container end function result:getModData() return self.data end
    function result:getInventory() return self.bag end function result:getWorldItem() return self.world end
    function result:setName(value) self.name=value end function result:setCustomName(value) self.custom=value end
    return result
end
InventoryItemFactory={CreateItem=item} instanceItem=nil
local function carry(seed,service,kind)
    local result=item(kind or C.ITEM) result.container=bag bag.items[#bag.items+1]=result
    if result.kind==C.ITEM then result.data.LF_LarchKey={seed=seed,service=service==true} end
    return result
end
local function fresh(seed)
    local state=S.create(seed or 71,"office",false,false,"card-test:"..opens..":"..serial..":"..T.checks)
    state.archive="dispatch_morrow" state.lock.kind="card" state.lock.settled=true
    C.ensure(state,player) return state
end
local function open(seed)
    if SC.Terminal.window then SC.Terminal.window:close() end
    opens=opens+1 skill=0 bag.items={} player.dead=false player.x=101 square.generatorPower=true
    local pc=T.computer(square) local state=fresh(seed)
    state.lock.card.spawned=true
    pc.data.movableData={LF_LarchOS=state}
    check(SC.Terminal.open(player,pc),"LARCH/KEY real terminal opens")
    local w=SC.Terminal.window w:flush() w.headless=true
    return w,pc
end
local function submit(w,text) w:setFocusMode("chat") w.entry:setText(text) w:submit() end
local function gaps(state)
    local result={} for pos=1,7 do if not C.known(state,pos) then result[#result+1]=pos end end return result
end
local function wrong(w,pos)
    local answer=C.board(w.system).digits:sub(pos,pos)
    for _,digit in ipairs(C.candidates(w.system,pos,skill)) do
        if digit~=answer and not w.system.lock.card.tried[pos]:find(digit,1,true) then return digit end
    end
end

-- 10,000 immutable boards, nested read prefixes and nested Electrical decoys.
local absent=0
for seed=1,10000 do
    local state={seed=seed,archive="dispatch_morrow",lock={kind="card"}}
    skill=0 C.ensure(state,player)
    local board=C.board(state) local sum=0
    for digit in board.badge:gmatch("%d") do sum=sum+tonumber(digit) end
    check(#board.rawStripe==10 and #board.stripe==12 and #board.digits==7 and tonumber(board.check)==sum,
        "card stripe has ten symbols, two display hyphens and a real badge checksum")
    local seen,checkDigits={},0
    for index,pos in ipairs(board.gapOrder) do
        check(not seen[pos] and pos>=1 and pos<=7,"card gap order is a permutation") seen[pos]=true
        if index<=4 and pos>=6 then checkDigits=checkDigits+1 end
    end
    check(checkDigits<=1,"card first four gaps never hide both check digits")
    for pos=1,7 do
        local previous
        for _,level in ipairs({0,3,6,8,10}) do
            local candidates=C.candidates(state,pos,level,board) local unique,count,answer={},0,0
            for index,digit in ipairs(candidates) do
                check(digit:match("^%d$") and not unique[digit] and (index==1 or candidates[index-1]<digit),
                    "card candidates are distinct sorted digits")
                unique[digit]=true count=count+1
                if digit==board.digits:sub(pos,pos) then answer=answer+1 end
                if previous then check(previous[digit],"raising Electrical only removes card decoys") end
            end
            check(count==(level<3 and 4 or level<8 and 3 or 2) and answer==1,"card candidate curve includes its answer exactly once")
            previous=unique
        end
    end
    for _,read in ipairs({"none","owner","service"}) do
        state.lock.card.read=read
        for _,level in ipairs({0,6,10}) do
            skill=level C.ensure(state,player)
            local target=C.gapCount(state,level)
            check(state.lock.card.gapsShown<=target,"card visibility is a monotonically shrinking read prefix")
            for index,pos in ipairs(board.gapOrder) do
                check(C.known(state,pos,board)==(index>state.lock.card.gapsShown),"card gaps are precisely a prefix of the stable order")
            end
        end
    end
    local clean=SC.TerminalLockState.normalize(state.lock,true)
    local reload=C.board({seed=seed,archive=state.archive,lock=clean})
    check(clean.kind=="card" and reload.rawStripe==board.rawStripe and table.concat(reload.gapOrder)==table.concat(board.gapOrder),
        "card seed and archive regenerate the same board after normalized reload")
    if C.random(state,32143)(5)==1 then absent=absent+1 end
end
check(absent>1850 and absent<2150,"card seed selection leaves about one machine in five without its owner card")
skill=0

local w,pc=open(101)
check(L.read(w,"4 7")=="47" and L.read(w,"4-7")=="47","card reader preserves multi-digit answers through command normalization")
local other=fresh(102) other.lock.kind="word"
check(L.read({system=other},"4-7")=="4-7","card digit normalization does not change word password evidence")
local order=gaps(w.system) local board=C.board(w.system)
local first,second,third=order[1],order[2],order[3]
submit(w,board.digits:sub(first,first)..wrong(w,second)..board.digits:sub(third,third))
check(w.system.lock.card.solved:sub(first,first)=="1" and not C.known(w.system,second) and not C.known(w.system,third)
    and w.system.lock.card.mismatches==1,"typing fills open gaps left to right and stops at the first mismatch")
local mistakes=w.system.lock.card.mismatches local repeated=w.system.lock.card.tried[second]:sub(1,1)
submit(w,repeated)
check(w.system.lock.card.mismatches==mistakes and w.securityMessage:find("ALREADY REJECTED",1,true),"repeating a rejected card digit costs no mismatch")
local listed={} for _,digit in ipairs(C.candidates(w.system,second,skill)) do listed[digit]=true end
for digit=0,9 do if not listed[tostring(digit)] then submit(w,tostring(digit)) break end end
check(w.system.lock.card.mismatches==mistakes and w.securityMessage=="THE HEAD NEVER READ THAT.","a digit outside the reader candidates costs nothing")
submit(w,"gap "..third)
check(C.cursor(w)==third,"click-style gap commands select an open stripe position through the real dispatcher")
local solved=w.system.lock.card.solved skill=10 C.update(w) local smallest=w.system.lock.card.gapsShown
skill=0 C.update(w)
check(w.system.lock.card.solved==solved and w.system.lock.card.gapsShown==smallest,"Electrical changes never reopen solved or revealed stripe positions")

w,pc=open(109)
local digit,pos=C.hint(w,false) local beforeHint=w.system.lock.card.solved
check(digit and pos and beforeHint=="0000000" and not w.system.lock.card.hinted,"companion hint peeking does not consume progress or the reader hint")
C.hint(w,true,pos)
check(C.known(w.system,pos) and not w.system.lock.card.hinted,"spoken companion hint fills exactly its gap without spending the reader hint")

do
    local previousCandidates,previousDialogue,previousBanter=SC.TerminalLockCrew.candidates,SC.Dialogue,SC.Banter
    local helper=T.player(101,100,0) local permitted=false local spoken,spokenValue=0,nil local topics={}
    SC.TerminalLockCrew.candidates=function() return {helper} end
    SC.Banter={budgetAllows=function() return true end,spendBudget=function() end}
    SC.Dialogue={has=function(topic) return topics[topic]~=nil end,
        register=function(topic,lines) topics[topic]=lines end,
        say=function(_,topic,_,args)
            if topic=="terminal.lock.hint.card" then spoken=spoken+1 spokenValue=args[1] return permitted end
            return false
        end}
    w,pc=open(111)
    local chosen=gaps(w.system)[#gaps(w.system)] submit(w,"gap "..chosen)
    local clue=C.board(w.system).digits:sub(chosen,chosen) local footer
    for _,row in ipairs(SC.TerminalLockUI.footer(w)) do if row.label:match("^Ask ") then footer=row end end
    check(footer~=nil,"higher trained nearby companion exposes an Ask footer option")
    local unchanged=w.system.lock.card.solved
    submit(w,footer.value)
    check(spoken==1 and not w.system.lock.crewHint and w.system.lock.card.solved==unchanged,
        "Ask footer uses companion dispatch and refused speech cannot consume a stripe gap")
    permitted=true submit(w,footer.value)
    check(spoken==2 and spokenValue==clue and C.known(w.system,chosen) and w.system.lock.crewHint
        and w.system.lock.crewClue.kind=="card" and w.system.lock.crewClue.stage==chosen
        and w.system.lock.crewClue.value==clue and not w.system.lock.card.hinted,
        "successful Ask footer speaks and commits exactly the selected digit without consuming the reader hint")
    local saved=S.normalize(w.system)
    check(saved.lock.crewClue.stage==chosen and saved.lock.crewClue.value==clue and #topics["terminal.lock.hint.card"].common>=4,
        "spoken card clue persists its digit and seven-position stage with four original lines")
    submit(w,footer.value)
    check(spoken==2,"one machine grants only one spoken companion stripe hint")
    SC.TerminalLockCrew.candidates,SC.Dialogue,SC.Banter=previousCandidates,previousDialogue,previousBanter
end

w,pc=open(113)
while w.system.lock.card.mismatches<2 do
    local cursor=C.cursor(w) submit(w,wrong(w,cursor))
end
check(w.system.lock.card.hinted and w.system.lock.card.hintPos and C.known(w.system,w.system.lock.card.hintPos),
    "second card mismatch reveals one older clean read")
local hintPos=w.system.lock.card.hintPos
local normalized=S.normalize(w.system)
check(normalized.lock.kind=="card" and normalized.lock.card.hinted and normalized.lock.card.hintPos==hintPos
    and normalized.lock.card.solved==w.system.lock.card.solved,"reader hint and solved stripe persist together")
while not w.system.lock.card.lockedUntil do
    local found=false
    for _,cursor in ipairs(gaps(w.system)) do
        local candidate=wrong(w,cursor)
        if candidate then submit(w,"gap "..cursor) submit(w,candidate) found=true break end
    end
    check(found,"failure fixture retains an untried wrong reader candidate")
end
local card=w.system.lock.card local retained=card.solved local untilHours=card.lockedUntil
check(untilHours==T.hours+1 and card.mismatches==5 and w.system.lock.bypass and w.system.lock.attempts[1].result=="failed",
    "last card mismatch sets a 60 game minute lockout, bypass and failed login receipt")
submit(w,C.board(w.system).digits:sub(C.cursor(w),C.cursor(w)))
check(card.solved==retained,"locked card reader refuses even a correct typed digit")
carry(w.system.seed,false) C.swipe(w)
check(card.read=="owner" and card.lockedUntil==untilHours and w.system.locked,"owner swipes remain saved during reader lockout")
T.hours=untilHours-1/60 C.update(w)
check(card.lockedUntil==untilHours and card.mismatches==5,"reader stays locked through minute 59")
T.hours=untilHours C.update(w)
check(not card.lockedUntil and card.mismatches==0 and card.solved==retained and card.hintPos==hintPos,
    "reader expiry resets only mismatches and preserves solved positions and its one hint")

for _,case in ipairs({{kind="owner",gaps=2,skill=0},{kind="service",gaps=1,skill=0},{kind="owner",gaps=1,skill=6},
    {kind="foreign",gaps=4,skill=0},{kind="vanilla",gaps=4,skill=0},{kind="none",gaps=4,skill=0}}) do
    w,pc=open(127+opens) skill=case.skill
    if case.kind=="owner" then carry(w.system.seed,false)
    elseif case.kind=="service" then carry(17777,true)
    elseif case.kind=="foreign" then carry(w.system.seed+1,false)
    elseif case.kind=="vanilla" then carry(nil,false,"Base.IDcard_Female") end
    C.swipe(w)
    check(w.system.lock.card.gapsShown==case.gaps and w.system.lock.card.mismatches==0,
        "physical "..case.kind.." card read has the expected gaps without a mismatch")
end
w,pc=open(163)
local foreign=carry(w.system.seed+1,false) local owner=carry(w.system.seed,false) local service=carry(888,true)
check(C.carried(player,w.system)==service and C.carried(player,w.system,true)==owner,"generic swipes rank service before owner before other cards")
C.swipe(w,foreign)
check(w.system.lock.card.read=="none" and w.securityMessage=="CARDHOLDER NOT ENROLLED ON THIS MACHINE.",
    "explicit inventory swipe reads the clicked wrong card instead of silently substituting a service card")
C.swipe(w) C.swipe(w,owner)
check(w.system.lock.card.read=="service" and w.system.lock.card.gapsShown==1,"later owner swipes never downgrade an existing service read")
local view=C.view(w)
check(view.stripe:find("_",1,true) and view.ownerStripe:find("?",1,true) and view.swipeStripe:find("?",1,true)
    and not table.concat(C.lines(w)," "):find(view.board.stripe,1,true),"reader text exposes masked reads rather than the full internal stripe answer")

w,pc=open(173)
check(not C.canEncode(w) and not C.encode(w),"locked readers cannot encode a service card")
owner=carry(w.system.seed,false)
w.system.lock.card.solved="1111111"
local paid=xp
check(L.finishUnlock(w,"card") and xp-paid==30,"seven verified digits use the real tier two unlock and XP flow")
check(not L.finishUnlock(w,"card") and xp-paid==30,"replaying card completion cannot replay XP")
w.system.lock.slip=true
check(not C.canEncode(w) and not C.encode(w),"slipping the machine wipes permission to encode its owner profile")
w.system.lock.slip=false bag.items={}
check(not C.canEncode(w) and not C.encode(w),"encoding requires this machine's physical owner card")
bag.items={owner} owner.container=bag
local encodedBeforeMutation,encodedBeforeName=true,true
owner.data.LF_LarchKey=setmetatable({seed=w.system.seed},{__newindex=function(target,key,value)
    if key=="service" then encodedBeforeMutation=w.system.lock.card.encoded==true end
    rawset(target,key,value)
end})
function owner:setName(value)
    encodedBeforeName=w.system.lock.card.encoded==true self.name=value
end
check(C.canEncode(w) and C.encode(w) and owner.data.LF_LarchKey.service and owner.name=="LARCH/KEY Service Card",
    "unlocked owner card becomes a named reusable service card")
check(encodedBeforeMutation,"encode receipt precedes changing the native item's stripe data")
check(encodedBeforeName,"encode receipt precedes changing the native item's name")
check(not C.canEncode(w) and not C.encode(w),"one machine encodes at most one owner card")
local encoded=owner w,pc=open(179) bag.items={encoded} encoded.container=bag
C.swipe(w)
check(w.system.lock.card.read=="service" and w.system.lock.card.gapsShown==1,"a service card encoded on one computer works on another")

-- Every finish route keeps the existing physical presence, power and identity gates.
for _,guard in ipairs({"incomplete","kind","timer","power","far","dead","missing","ownership"}) do
    w,pc=open(181+opens) w.system.lock.card.solved="1111111"
    if guard=="incomplete" then w.system.lock.card.solved="0000000"
    elseif guard=="kind" then w.system.lock.kind="word"
    elseif guard=="timer" then w.system.lock.card.lockedUntil=T.hours+1
    elseif guard=="power" then square.generatorPower=false
    elseif guard=="far" then player.x=120
    elseif guard=="dead" then player.dead=true
    elseif guard=="missing" then pc.index=-1
    elseif guard=="ownership" then pc.data.movableData.LF_LarchOS={} end
    check(not L.finishUnlock(w,"card"),"card unlock rejects failed "..guard.." proof")
end
player.dead=false player.x=101 square.generatorPower=true
for _,damage in ipairs({"read","solved","tried","mismatches","gapsShown","lockedUntil","hintPos","spawned"}) do
    local state=fresh(223) local c=state.lock.card
    if damage=="read" then c.read="future"
    elseif damage=="solved" then c.solved="11111111"
    elseif damage=="tried" then c.tried[1]="112"
    elseif damage=="mismatches" then c.mismatches=21
    elseif damage=="gapsShown" then c.gapsShown=5
    elseif damage=="lockedUntil" then c.lockedUntil=-1
    elseif damage=="hintPos" then c.hinted=true c.hintPos=8
    elseif damage=="spawned" then c.spawned="yes" end
    local clean=S.normalize(state)
    check(clean.lock.kind=="word" and clean.lock.legacy and clean.lock.stash.committed,
        "malformed card "..damage.." follows the bounded legacy fallback without recreating loot")
end

-- Physical placement uses the real settle order and real drawer interlock.
if SC.Terminal.window then SC.Terminal.window:close() end
bag.items={} skill=0 ledger={} L.reset() SandboxVars.LivingFellows.LockRealItems=true
local adds,fills=0,0 local placedState local spawnReceipts,claimOrder=true,true
local function furniture(tile,kind,assertClaim)
    local object={data={},square=tile}
    function object:getSquare() return self.square end function object:getModData() return self.data end
    function object:getSurfaceOffsetNoTable() return 34 end
    function object:getSprite() return {getName=function() return "fixture_desk" end} end
    local container={items={},parent=object,explored=false}
    function container:getType() return kind end function container:getParent() return self.parent end
    function container:getItems() return self.items end function container:isExplored() return self.explored end
    function container:setExplored(value) self.explored=value end
    function container:AddItem(value)
        if type(value)=="string" then value=item(value) end
        if value.kind==C.ITEM then
            if not placedState.lock.card.spawned then spawnReceipts=false end
            if assertClaim and not placedState.lock.drawer then claimOrder=false end
            check(placedState.lock.card.spawned,"card spawn receipt precedes every native insertion")
            if assertClaim then check(placedState.lock.drawer and SC.TerminalDrawers.locked(container)==false,
                "card placement runs after the own drawer claim and skips the locked interlock") end
            adds=adds+1
        end
        self.items[#self.items+1]=value value.container=self return value
    end
    function object:getContainer() return container end
    tile.objects[#tile.objects+1]=object return container,object
end
local placementProfile
for _,profile in ipairs(SC.TerminalFiles.all()) do
    if not SC.TerminalPayoff.wantsNote({archive=profile.id}) then placementProfile=profile.id break end
end
local function seedWithCard(start)
    for seed=start,start+20 do if C.random({seed=seed},32143)(5)~=1 then return seed end end
end
square.objects={} neighbor.objects={}
local ownDrawer=furniture(square,"desk",true)
local freeDrawer=furniture(neighbor,"desk",true)
pc=T.computer(square) placedState=fresh(seedWithCard(301)) placedState.archive=placementProfile
placedState.lock.realItems=true pc.data.movableData={LF_LarchOS=placedState}
ItemPicker={fillContainer=function(container)
    fills=fills+1 container:AddItem("Base.Pencil")
end}
L.settle(placedState,player,pc)
check(spawnReceipts,"card spawn receipt is committed when native insertion begins")
check(claimOrder,"card placement sees the own drawer claim before native insertion")
check(placedState.lock.drawer and SC.TerminalDrawers.locked(ownDrawer) and #ownDrawer.items==0 and #freeDrawer.items==2
    and freeDrawer.items[1].kind=="Base.Pencil" and freeDrawer.items[2].kind==C.ITEM and fills==1,
    "card lands in a different unexplored same-room desk beside its normal native loot")
local count=adds L.settle(placedState,player,pc) C.place(placedState,player,pc)
check(adds==count,"reopening and repeated placement never add a second access card")
local oldLocked=SC.TerminalDrawers.locked
SC.TerminalDrawers.locked=function(container) return container==freeDrawer or oldLocked(container) end
function square:AddWorldInventoryItem(value,_,_,height)
    check(placedState.lock.card.spawned,"card world insertion also follows the spawn receipt")
    adds=adds+1 self.lastHeight=height value.world={getSquare=function() return square end} return value
end
placedState=fresh(seedWithCard(331)) placedState.lock.drawer={x=100,y=100,z=0,type="desk",sprite="fixture_desk"}
local placed=C.place(placedState,player,pc)
check(placed and placed:getWorldItem() and square.lastHeight==34/96 and #freeDrawer.items==2,
    "locked neighboring drawers are skipped and surface fallback matches the manual")
SC.TerminalDrawers.locked=oldLocked
square.objects={pc} neighbor.objects={} square.lastHeight=nil
function neighbor:AddWorldInventoryItem(value,_,_,height)
    self.lastHeight=height value.world={getSquare=function() return neighbor end} return value
end
placedState=fresh(seedWithCard(351)) placed=C.place(placedState,player,pc)
check(placed and placed:getWorldItem():getSquare()==neighbor and neighbor.lastHeight==0,
    "without a surface the access card uses the manual's free adjacent solid floor fallback")
neighbor.free=false placedState=fresh(seedWithCard(371))
check(not C.place(placedState,player,pc) and placedState.lock.card.spawned and placedState.lock.card.absent,
    "no eligible physical place becomes a committed absent card instead of retrying or duplicating")
neighbor.free=true
SC.TerminalLockPhysical.place=function(value) value.world={} return value.world end
local missing=0
for seed=1,1000 do
    placedState=fresh(seed) C.place(placedState,player,pc)
    if placedState.lock.card.absent then missing=missing+1 end
end
check(missing>170 and missing<230,"real placement honors the seeded one-in-five absent-card policy")
SandboxVars.LivingFellows.ClassicLocksOnly=true
for seed=1,40 do
    local state=S.create(seed,"office",false,false,"classic-card:"..seed) L.settle(state,player,pc)
    check(state.lock.kind=="word" and not state.lock.card,"ClassicLocksOnly never settles or places a card lock")
end

if SC.Terminal.window then SC.Terminal.window:close() end
ModData,SandboxVars,getCell,InventoryItemFactory,instanceItem,ItemPicker,Perks=old.mod,old.sandbox,old.cell,old.factory,old.instance,old.picker,old.perks
SC.Terminal._clock=old.clock SC.Registry=old.registry
SC.GameplayUtil.containerContainsIdentity,SC.GameplayUtil.isSquareFree=old.contains,old.free
SC.TerminalDrawers.locked,SC.TerminalLockPhysical.place=old.locked,old.physical
T.hours,T.now=old.hours,old.now L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; LARCH/KEY card: "..(T.checks-before).." generation, input, persistence and physical-card checks passed"
