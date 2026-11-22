-- SPDX-License-Identifier: MIT
-- A drawer held by a locked computer must not stay shut while EMMA is off:
-- the computer cannot be used then, so the furniture behaves normally.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local D,L,S=SC.TerminalDrawers,SC.TerminalLocks,SC.TerminalSystem
local check=T.check
local book={} ModData={getOrCreate=function() return book end}
local settings={LockRealItems=true,LockedComputerPercent=100}
SandboxVars={LivingFellows=settings}
L.reset()
local square=T.square(100,100,0,true) local computer=T.computer(square)
local player=T.player(101,100,0)
local playerSquare=T.square(101,100,0,true)
function player:getSquare() return playerSquare end
local desk={data={}} local container={}
function desk:getSquare() return square end
function desk:getSprite() return {getName=function() return "test_desk" end} end
function desk:getContainer() return container end
function desk:getModData() return self.data end
function container:getType() return "desk" end
function container:getParent() return desk end
function container:getItems() return {} end
square.objects={computer,desk}
function square:getObjects() return self.objects end
getCell=function() return {getGridSquare=function(_,x,y,z) if x==100 and y==100 and z==0 then return square end end} end

local state=S.create(1,"police",false,false,"drawer-access")
state.archive="dispatch_bell" state.lock.kind="word" state.lock.legacy=true
computer.data.movableData={LF_LarchOS=state}
L.settle(state,player,computer)
check(state.lock.drawer and D.locked(container),"fixture: the locked computer holds the desk drawer")

local click=function() return "click" end
local inherited=function() return "inherited drop" end
local button=setmetatable({inventory=container,onclick=click,onmousedown=click},{__index={onMouseUp=inherited}})
local page={player=0,onCharacter=false,backpacks={button},inventoryPane={inventory=nil}}
function page:setNewContainer(c) self.inventoryPane.inventory=c end
D.refresh(page,"buttonsAdded")
check(button.onclick==nil and button.onMouseUp==D.blockedPointer,"fixture: the inventory button is interlocked")

settings.EmmaEnabled=false
check(not D.locked(container),"with EMMA off the drawer opens like ordinary furniture")
D.refresh(page,"buttonsAdded")
check(button.onclick==click and button.onMouseUp==inherited and button.tooltip==nil,
    "with EMMA off the inventory button loses its padlock and callbacks return")
local blocked=0 for _ in pairs(D.snapshot()) do blocked=blocked+1 end
check(blocked==0,"with EMMA off no drawer is reported as blocked")
check(book.drawers["drawer-access"]~=nil and state.lock.drawer and not state.lock.drawer.open
    and not state.lock.drawer.forced,"the claim and its unopened drawer are kept for later")

settings.EmmaEnabled=true
check(D.locked(container),"turning EMMA back on restores the interlock")
D.refresh(page,"buttonsAdded")
check(button.onclick==nil and button.onMouseUp==D.blockedPointer,"the inventory button is interlocked again")
SC_TEST_REPORT="EMMA_DRAWER_ACCESS_PASS checks="..T.checks
