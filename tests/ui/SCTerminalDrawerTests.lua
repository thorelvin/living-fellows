-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local D,P,L,S=SC.TerminalDrawers,SC.TerminalPayoff,SC.TerminalLocks,SC.TerminalSystem
local check,before=T.check,T.checks
local oldCell,oldMod,oldSandbox,oldPicker=getCell,ModData,SandboxVars,ItemPicker
local book={} ModData={getOrCreate=function() return book end}
SandboxVars={LivingFellows={LockRealItems=true,LockedComputerPercent=100}}
L.reset()
local square=T.square(100,100,0,true) local computer=T.computer(square)
local player=T.player(101,100,0)
local playerSquare=T.square(101,100,0,true)
function player:getSquare() return playerSquare end
local desk={data={}} local stock={} local serial,adds,fills=0,0,0
local container={explored=false}
function desk:getSquare() return square end
function desk:getSprite() return {getName=function() return "test_desk" end} end
function desk:getContainer() return container end
function desk:getModData() return self.data end
function container:getType() return "desk" end
function container:getParent() return desk end
function container:getItems() return stock end
function container:isExplored() return self.explored end
function container:setExplored(value) self.explored=value end
function container:AddItem(kind)
    check(self.explored,"native loot fill precedes custom stash items")
    adds,serial=adds+1,serial+1
    local item={id=serial,kind=kind}
    function item:getID() return self.id end
    function item:getFullType() return self.kind end
    function item:getDisplayName() return self.kind end
    function item:getContainer() return container end
    stock[#stock+1]=item
    if self.ambiguous then error("after native item insertion") end
    return item
end
ItemPicker={fillContainer=function(c,p) check(c==container and p==player,"normal loot belongs to the real selected container/operator") fills=fills+1 end}
square.objects={computer,desk}
function square:getObjects() return self.objects end
getCell=function() return {getGridSquare=function(_,x,y,z) if x==100 and y==100 and z==0 then return square end end} end
local function program(object,id)
    local state=S.create(1,"police",false,false,id)
    state.archive="dispatch_bell" state.lock.kind="word" state.lock.legacy=true
    object.data.movableData={LF_LarchOS=state}
    L.settle(state,player,object) return state
end
local state=program(computer,"desk-owner")
check(state.lock.drawer and D.locked(container),"a real desk claim creates the inventory interlock")
local second=T.computer(square) square.objects[#square.objects+1]=second
local other=program(second,"other-computer")
check(other.lock.drawer==nil,"two computers cannot claim the same physical drawer")
local used,why=D.open(player,computer,state,false)
check(not used and state.lock.stash==nil and adds==0,"locked computer cannot create its reward")
local click=function() return "click" end
local inherited=function() return "inherited drop" end
local button=setmetatable({inventory=container,onclick=click,onmousedown=click},{__index={onMouseUp=inherited}})
local ground={getType=function() return "floor" end}
local page={player=0,onCharacter=false,backpacks={button,{inventory=ground}},inventoryPane={inventory=container}}
function page:setNewContainer(c) self.inventoryPane.inventory=c end
D.refresh(page,"buttonsAdded")
check(button.onclick==nil and button.onMouseUp==D.blockedPointer and button:onMouseUp()==true,
    "interlock consumes inherited drag/drop callbacks explicitly")
check(page.inventoryPane.inventory==ground,"an already-selected locked desk falls back to Ground")
state.locked=false
used,why=D.open(player,computer,state,false)
check(used and state.lock.drawer.open and adds==3 and fills==1 and #state.lock.stash.items==3,
    "release creates exactly the promised three native batteries after normal loot")
check(state.lock.stash.note:find("The batteries are in the bottom drawer.",1,true)~=nil,"verified drawer reward shows its real owner sentence")
check(not D.open(player,computer,state,false) and adds==3,"repeated release cannot recreate items")
check(not P.place(player,computer,state,container,false) and adds==3,"the physical-item commit also blocks a duplicate lower-level callback")
D.refresh(page,"buttonsAdded")
check(button.onclick==click and button.onMouseUp==inherited,"releasing restores original inventory callbacks")
L.settle(other,player,second)
check(other.lock.drawer==nil,"a previously rejected computer does not suddenly take over an opened drawer")
local third=T.computer(square) square.objects[#square.objects+1]=third
local thirdState=program(third,"third-computer")
check(thirdState.lock.drawer==nil,"a released drawer remains owned by its original physical computer")
D.release(computer)
check(not desk.data.movableData.LF_LarchDrawerOwner,"moving/removing a computer releases its physical ownership")
local fourth=T.computer(square) square.objects[#square.objects+1]=fourth
local uncertain=program(fourth,"ambiguous-computer") uncertain.locked=false container.ambiguous=true
local beforeAdds=adds
check(D.open(player,fourth,uncertain,false),"an uncertain native transfer still releases access safely")
check(uncertain.lock.stash.committed and #uncertain.lock.stash.items==0 and adds==beforeAdds+1,
    "an exception after native insertion preserves the commit without inventing an item receipt")
check(not P.place(player,fourth,uncertain,container,false) and adds==beforeAdds+1,
    "ambiguous missing receipt is never replayed")
local persisted=S.normalize(uncertain)
check(persisted and persisted.lock.stash.committed,"uncertain transfer protection survives save normalization")
container.ambiguous=false
D.release(fourth)
local beforeClaim=book.drawers["other-computer"]
check(beforeClaim==nil,"failed competing claims leave no ledger reservations")
local sixth=T.computer(square) square.objects[#square.objects+1]=sixth
local disabled=program(sixth,"disabled-interlock")
check(disabled.lock.drawer~=nil,"fixture has a current interlock before disabling rewards")
SandboxVars.LivingFellows.LockRealItems=false D.refresh(page,"buttonsAdded")
check(not D.locked(container) and not book.drawers[disabled.identity] and disabled.lock.stash.committed,
    "turning off real items releases current interlocks without creating cargo")
SandboxVars.LivingFellows.LockRealItems=true
local seventh=T.computer(square) square.objects[#square.objects+1]=seventh
local once=program(seventh,"one-unlock")
local xpCalls=0
function player:getXp() return {AddXP=function()
    xpCalls=xpCalls+1 check(once.xpAwarded,"native XP receipt precedes the callback") error("after native XP application")
end} end
Perks=Perks or {Electricity="Electricity"}
check(S.act(once,once.puzzle.answer,T.hours)=="success","one-unlock fixture solves a genuine displayed answer")
local window={player=player,object=seventh,system=once,headless=true}
check(L.finishUnlock(window,"word") and once.lock.unlockApplied and xpCalls==1,
    "an exception after native XP still finishes the machine exactly once")
check(not L.finishUnlock(window,"word") and xpCalls==1,"a duplicate route callback cannot restart the payoff or XP")
D.release(seventh)
local eighth=T.computer(square) square.objects[#square.objects+1]=eighth
local missingId=program(eighth,"missing-native-id") missingId.locked=false
local normalAdd=container.AddItem
function container:AddItem(kind)
    local item=normalAdd(self,kind) item.id=nil return item
end
local beforeMissing=adds
check(D.open(player,eighth,missingId,false) and missingId.lock.stash.committed
        and #missingId.lock.stash.items==0 and adds==beforeMissing+1,
    "a native item without an identity is not assigned a fabricated receipt")
check(not P.place(player,eighth,missingId,container,false) and adds==beforeMissing+1,
    "an unverifiable native item never triggers a replacement")
container.AddItem=normalAdd
D.release(eighth)
local ninth=T.computer(square) square.objects[#square.objects+1]=ninth
local removed=program(ninth,"removed-desk")
check(removed.lock.drawer and book.drawers[removed.identity],"removed desk fixture owns a real claim")
local services=SC.TerminalServices local duration
SC.TerminalServices={install=function(_,_,_,maxTime) duration=maxTime;return true end}
local tool=SC.ControlUtil.hasTool SC.ControlUtil.hasTool=function() return true end
local force
D.context({addOption=function(_,_,who,fn) force=function() fn(who) end end},player,{desk})
check(force~=nil,"physical drawer offers crowbar forcing") force()
check(duration==300,"crowbar duration is passed before native queueing starts")
SC.TerminalServices=services SC.ControlUtil.hasTool=tool
local loaded=getCell;getCell=function() return {getGridSquare=function() return nil end} end
D.refresh(page,"buttonsAdded")
check(book.drawers[removed.identity] and removed.lock.drawer,"unloaded desk and computer retain their exact claim")
getCell=loaded
for index,object in ipairs(square.objects) do if object==desk then table.remove(square.objects,index) break end end
D.refresh(page,"buttonsAdded")
check(not book.drawers[removed.identity] and not removed.lock.drawer,"definitely removed desk clears both ledger and computer menu claim")
check(removed.lock.stash.committed,"missing desk cannot mint replacement drawer rewards")
L.settle(removed,player,ninth)
check(not removed.lock.drawer,"reopening cannot replace the lost drawer")
ModData,SandboxVars,getCell,ItemPicker=oldMod,oldSandbox,oldCell,oldPicker L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Drawer ownership and ambiguous native transfer: "..(T.checks-before).." checks passed"
