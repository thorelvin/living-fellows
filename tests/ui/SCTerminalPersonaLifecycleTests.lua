-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local Terminal,S,D,L=SC.Terminal,SC.TerminalSystem,SC.TerminalDrawers,SC.TerminalLocks
local check,before=T.check,T.checks
local old={mod=ModData,cell=getCell,world=SC.TerminalWorld.new,options=SandboxVars,
    config=SCConfig,debug=isDebugEnabled,props=ISMoveableSpriteProps,hook=Terminal._moveHook,
    specific=getSpecificPlayer,tool=SC.ControlUtil.hasTool,picker=ItemPicker}
local raw={} ModData={getOrCreate=function() return raw end} L.reset()
SandboxVars={LivingFellows={LockRealItems=true,RareComputers=2,LockedComputerPercent=100}}
SCConfig={debugPersona="ellis"} isDebugEnabled=function() return true end
SC.TerminalWorld.new=function() return {camp=function() return {inside=false} end} end
local square=T.square(100,100,0,true) local pc=T.computer(square) local player=T.player(101,100,0)
function player:getSquare() return T.square(101,100,0,true) end
getSpecificPlayer=function() return player end
local stock,serial={},0 local desk={data={}} local c={explored=true}
function desk:getSquare() return square end
function desk:getSprite() return {getName=function() return "test_desk" end} end
function desk:getModData() return self.data end
function desk:getContainer() return c end
function c:getType() return "desk" end
function c:getParent() return desk end
function c:getItems() return stock end
function c:isExplored() return self.explored end
function c:setExplored(value) self.explored=value end
function c:AddItem(kind)
    serial=serial+1 local item={id=serial,kind=kind}
    function item:getID() return self.id end
    function item:getFullType() return self.kind end
    function item:getDisplayName() return self.kind end
    function item:getContainer() return c end
    stock[#stock+1]=item return item
end
square.objects={pc,desk}
getCell=function() return {getGridSquare=function(_,x,y,z) if x==100 and y==100 and z==0 then return square end end} end
ItemPicker={fillContainer=function() end}
local function program(id)
    pc.index=3
    local state=S.create(11,"home",false,false,id)
    for archive,row in pairs(SC.TerminalLockStashes) do
        if not row.drawer and SC.TerminalFiles.get(archive) then state.archive=archive break end
    end
    pc.data.movableData={LF_LarchOS=state} SCConfig.debugPersona="ellis"
    L.settle(state,player,pc,false) return state
end
local state=program("persona-physical")
check(state.lock.kind=="persona" and state.lock.drawer and D.locked(c),"note-style owner still gets a real persona drawer")
check(not D.open(player,pc,state,false),"ordinary drawer opening cannot bypass locked persona")
check(D.open(player,pc,state,false,true) and state.locked and #stock==3 and not D.locked(c),"granted persona opening uses actual item transaction while computer remains locked")
SC.TerminalPersona.confirmDrawer(state.lock.persona,true)
local persisted=S.normalize(state)
check(persisted.lock.persona.flags.drawer_done and #persisted.lock.stash.items==3,"save roundtrip retains drawer and exact receipts")
check(not D.open(player,pc,state,false,true) and #stock==3,"repeated grant cannot recreate physical rewards")
D.release(pc)
state=program("persona-forced")
SC.ControlUtil.hasTool=function(_,kind) return kind=="Base.Crowbar" end
local expected=SC.TerminalPayoff.items(state,true) local initial=#stock
check(D.open(player,pc,state,true) and state.locked and state.lock.drawer.forced
    and state.lock.persona.flags.forced,"actual crowbar path records forced entry without unlocking the computer")
check(#stock-initial==#expected,"forced entry uses ordinary tier contents")
for i=1,#expected do check(stock[initial+i].kind==expected[i],"forced item comes from ordinary reward selection") end
check(S.normalize(state).lock.persona.flags.forced,"forced flag survives save normalization")
D.release(pc) desk.data.movableData.LF_LarchDrawerBroken=nil
-- Run the actual pickup wrapper with a vanilla-shaped copy/remove callback.
local function copy(value)
    if type(value)~="table" then return value end
    local out={} for k,v in pairs(value) do out[k]=copy(v) end return out
end
ISMoveableSpriteProps={pickUpMoveableInternal=function(_,actor,at,object)
    local item={data={movableData=copy(object.data.movableData)}}
    function item:getModData() return self.data end
    object.index=-1 return item
end}
Terminal._moveHook=nil check(Terminal.installMoveHook(),"pickup wrapper installs for lifecycle fixture")
state=program("persona-move") state.lock.persona.met=true state.lock.persona.name="Ann"
state.lock.persona.spoken=28 state.lock.persona.gentleUntil=168
local inventoryBefore=#stock
local item=ISMoveableSpriteProps:pickUpMoveableInternal(player,square,pc)
local moved=item.data.movableData.LF_LarchOS
check(not D.locked(c) and moved.lock.drawer==nil and moved.lock.stash.committed
    and #stock==inventoryBefore,"pickup releases original interlock and cannot carry or clone drawer loot")
check(moved.lock.persona.id=="ellis" and moved.lock.persona.name=="Ann" and moved.lock.home.x==100
    and moved.lock.persona.spoken==28 and moved.lock.persona.gentleUntil==168,"native-shaped furniture transfer preserves exact conversation progress and home")
local campPC=T.computer(T.square(102,100,0,true)) campPC.data.movableData=copy(item.data.movableData)
SC.TerminalWorld.new=function() return {camp=function() return {inside=true} end} end
check(Terminal.open(player,campPC),"moved persona remains usable at home")
local w=Terminal.window
local facts=SC.TerminalPersonaUI.facts(w,T.now,true)
check(facts.atCamp and facts.moved and facts.drawer=="none" and w.system.lock.persona.gentleUntil==168,
    "home facts reflect actual move and preserve safeguard")
w:systemInput("hello")
check(w.system.lock.persona.flags.moved_seen,"supplied moved-to-camp return line is reached through the actual UI")
check(not w.system.lock.drawer and #stock==inventoryBefore,"return conversation cannot bind a replacement drawer or duplicate loot")
check(not SC.TerminalLamp.active(w),"a moved personality never enables the threat lamp")
w.healthBaseline={health=100,bites=0,scratches=0}
function player:getBodyDamage() return {getOverallBodyHealth=function() return 90 end} end
w.lastWatch=T.now-1000 w:watch(T.now)
check(w.closed and Terminal.window==nil,"incoming damage closes persona UI even though its lamp is disabled")
-- An unopened pickup receives a fresh access record but never rolls at pickup.
SC.TerminalWorld.new=function() return {camp=function() return {inside=false} end} end
local untouched=T.computer(T.square(100,100,0,false))
local boots=L.ledger().persona.boots
item=ISMoveableSpriteProps:pickUpMoveableInternal(player,untouched.square,untouched)
check(item.data.movableData.LF_LarchOS.fresh and L.ledger().persona.boots==boots,
    "unopened unpowered furniture pickup retains first-boot eligibility without rolling")
ModData,getCell,SandboxVars,SCConfig,isDebugEnabled,getSpecificPlayer,ItemPicker=old.mod,old.cell,old.options,old.config,old.debug,old.specific,old.picker
SC.TerminalWorld.new=old.world SC.ControlUtil.hasTool=old.tool
ISMoveableSpriteProps,Terminal._moveHook=old.props,old.hook L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Persona lifecycle: "..(T.checks-before).." checks passed"
