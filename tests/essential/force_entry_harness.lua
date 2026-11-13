-- SPDX-License-Identifier: MIT
-- Stock ISForceOpen, deterministic native outcomes, exact actor/item boundaries.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local F, N, U = SC.ForceEntry, SC.NativeActions, SC.GameplayUtil
local checks = 0
local function check(v, message) checks=checks+1; assert(v, "crowbar "..checks..": "..message) end
ItemTag = ItemTag or {}; ItemTag.CROWBAR="CROWBAR"
CharacterTrait.BURGLAR="BURGLAR"
local a,b=f.actor("force-a",3,3,{}),f.actor("force-b",3,3,{})
SC.Registry.byId=function(id) return id==U.idOf(a) and {actor=a} or id==U.idOf(b) and {actor=b} or nil end
local function actorSetup(actor)
    local actions={}
    function actions:add(x) self[#self+1]=x end
    function actions:remove(x) for i,v in ipairs(self) do if v==x then table.remove(self,i); break end end end
    function actions:size() return #self end
    function actor:getCharacterActions() return actions end
    actor.characterActions=actions
    function actor:forceOpenWindowOrDoor(portal) self.portal=portal end
    function actor:exertForForcing() self.exertions=(self.exertions or 0)+1 end
    function actor:hasTrait() return false end
    function actor:getPerkLevel() return 5 end
    function actor:getBaseForceOpenChance() return 20 end
end
actorSetup(a); actorSetup(b)
local tool=f.item("Base.Crowbar","Weapon",{tags={CROWBAR=true}})
local old=f.item("Base.FryingPan","Weapon",{})
a:getInventory():AddItem(tool); a:getInventory():AddItem(old); a:setPrimaryHandItem(old)
local door={__class="IForceablePortal",locked=true,data={},square=a:getSquare(),wear=0}
function door:getSquare() return self.square end
function door:getX() return self.square:getX() end
function door:getY() return self.square:getY() end
function door:getZ() return self.square:getZ() end
function door:getObjectIndex() return 1 end
function door:getModData() return self.data end
function door:isNotValidForForcing() return self.invalid==true or not self.locked end
function door:isLocked() return self.locked end
function door:IsOpen() return self.open==true end
function door:forceOpen(who) check(who==a,"native portal effect uses exact worker"); self.locked=false; self.applied=(self.applied or 0)+1 end
function door:ToggleDoor(who) check(who==a,"native opening uses exact worker"); self.open=true end
function door:forceStruggleDamage(who) check(who==a,"wear targets exact worker"); self.wear=self.wear+1 end
function door:failForceOpen(who) check(who==a,"native failure targets exact worker"); self.failed=true end
function door:getBaseForceOpenChance() return 30 end
ForceOpenState={instance=function() return {
    forceStopped=function(_,who) who.stopped=true end,
    forceSucceeded=function() end, -- the vanilla local-player gate excludes companions
} end}
IsoGridSquare={isWithinReachOfCharacter=function() return true end}
local roll=99
function ZombRand() return roll end
local quiet={immediateCount=0,pressure=0}
SC.Senses.cached=function() return quiet end
local row={id="tools",withdrawals=true}
local source=f.inventory(); local sourceObject={}
SC.BaseLife={active=function() return {} end,withinWorkReach=function() return true end,
    resolveObject=function() return door end,storage=function(id) return id==row.id and row end,
    resolveContainer=function() return source,sourceObject end,storageAcceptsDeposit=function() return true end,
    storageRows=function() return {row} end,withdrawable=function() return true end}
SC.Navigation.barricadeWorkSquare=function() return a:getSquare() end
SC.Oddballs=nil
U.move=function(actor,_,intent) return N.forceOpen(actor,intent,{directNative=true}) end
check(F.eligible(door,a),"ordinary native forceable portal admitted")
door.invalid=true; check(not F.eligible(door,a),"security/unsupported native portal rejected"); door.invalid=false
SC.Oddballs={sealedDoorGroup=function() return "authored" end}
check(not F.eligible(door,a),"authored Strange Folk lock remains protected"); SC.Oddballs=nil
local state={}
local ctx={object=door,snapshot=quiet,borrow=true,useId="manual:a:1",current=function() return true end}
check(F.step(a,{},state,ctx),"native action starts")
local action=ISTimedActionQueue.getTimedActionQueue(a).current
check(action and action.character==a and a:getPrimaryHandItem()==tool,"crowbar equipped on the intended actor")
check(action:attempt()=="struggle" and a.exertions==1 and not b.exertions,"native exertion is isolated")
local otherTool=f.item("Base.Crowbar","Weapon",{tags={CROWBAR=true}}); b:getInventory():AddItem(otherTool)
local _,why=F.step(b,{}, {},{object=door,snapshot=quiet,useId="manual:b:1",current=function() return true end})
check(why=="force_open_busy","two workers cannot force the same portal")
roll=0; check(action:attempt()=="fail" and door.failed,"stock failure retains tool wear/outcome")
action:stop(); F.step(a,{},state,ctx)
local _,reason,done=F.step(a,{},state,ctx)
check(done and reason=="force_open_failed" and a:getPrimaryHandItem()==old,"failure stops and restores prior weapon")
local exertions=a.exertions
F.step(a,{},state,ctx); check(a.exertions==exertions and not N.isWorkActive(a),"no automatic repeated attempt")
state={}; ctx.useId="manual:a:retry"
check(F.step(a,{},state,ctx),"explicit new order permits retry")
action=ISTimedActionQueue.getTimedActionQueue(a).current
roll=50; check(action:attempt()=="struggle","one action may have several native struggles")
roll=30; action.outcome=action:attempt(); check(action.outcome=="success" and door.locked,"stock success precedes native portal effect")
check(action:complete() and not door.locked and door.open,"NPC completion calls native forcing/opening after success")
action:complete(); check(door.applied==1,"repeated completion cannot apply the portal effect twice")
action:perform(); F.step(a,{},state,ctx); _,reason,done=F.step(a,{},state,ctx)
check(done and reason=="force_open_succeeded" and a:getPrimaryHandItem()==old,"native unlock completes and preserves equipment")
door.locked=true; door.open=false
state={attempted=true,stage="forcing",useId="saved",deadlineAt=f.clock+60000}
F.step(a,{},state,ctx); _,reason,done=F.step(a,{},state,ctx)
check(done and reason=="force_open_failed" and not N.isWorkActive(a),"reload never replays an ambiguous attempted effect")
-- A return remains pending if full; it cannot be sorted, lost or recreated.
tool:getModData().LF_ForceEntryTool={actorId=U.idOf(a),sourceId=row.id,phase="carried"}
check(F.protected(tool),"saved loan adopts pending return and protects the exact tool")
local room=U.containerHasRoom
U.containerHasRoom=function() return false end
F.returnPending(a,quiet)
check(not F.pendingReturn(a) and U.inventoryContains(a:getInventory(),tool),"full source waits three minutes without losing cargo")
f.clock=f.clock+180001
check(F.pendingReturn(a),"blocked return retries after its pause")
U.containerHasRoom=room
-- Borrowing installs its durable receipt before the exact item leaves storage.
local borrower=f.actor("force-c",3,3,{}); actorSetup(borrower)
local knownById=SC.Registry.byId
SC.Registry.byId=function(id) if id==U.idOf(borrower) then return {actor=borrower} end return knownById(id) end
local loan=f.item("Base.Crowbar","Weapon",{tags={CROWBAR=true}}); source:AddItem(loan)
SC.Encounter.takePlayerSupply=function(actor,kind,predicate,options)
    check(predicate(loan) and options.beforeTransfer(loan,source),"permitted usable stock can be claimed")
    check(F.protected(loan) and loan:getModData().LF_ForceEntryTool.sourceId==row.id,"receipt precedes transfer")
    check(U.transferItemVerified(source,actor:getInventory(),loan),"only the original loan item moves")
    return "taken"
end
F.step(borrower,{}, {},{object=door,snapshot=quiet,borrow=true,useId="borrow",current=function() return true end})
check(U.inventoryContains(borrower:getInventory(),loan) and not U.inventoryContains(source,loan),"camp borrowing preserves identity")
-- A loan settles once nobody can return it: the borrower died or was
-- dismissed, or the player took the tool off them. A load still under way
-- and a withdrawal still in flight keep it.
check(F.protected(loan),"the borrower's own carried loan stays protected")
local persistence=SC.Persistence
local loaded=false
SC.Persistence={restoreStatus=function() return loaded end,isPending=function() return false end}
local stray=f.item("Base.Crowbar","Weapon",{tags={CROWBAR=true}}); source:AddItem(stray)
stray:getModData().LF_ForceEntryTool={actorId="sc-force-gone",sourceId=row.id,phase="carried"}
check(F.protected(stray),"a borrower still restoring from the save keeps its loan")
loaded=true
check(not F.protected(stray) and stray:getModData().LF_ForceEntryTool==nil,"a dead or dismissed borrower's crowbar becomes ordinary stock")
stray:getModData().LF_ForceEntryTool={actorId=U.idOf(borrower),sourceId=row.id,phase="claimed",untilMs=f.clock+30000}
check(F.protected(stray),"a withdrawal still in flight stays protected")
stray:getModData().LF_ForceEntryTool={actorId=U.idOf(borrower),sourceId=row.id,phase="carried"}
source:Remove(stray); f.player:getInventory():AddItem(stray)
check(not F.protected(stray) and stray:getModData().LF_ForceEntryTool==nil,"a tool taken off its borrower is no longer held for them")
SC.Persistence=persistence
check(F.copy({attempted=true,stage="forcing",object=door}).object==nil,"save state excludes native references")
-- Discovery remains bounded, belongs to the chosen building, prefers doors,
-- and never offers an upper-floor window into a roof route.
local grid,oldInstance=U.gridSquare,instanceof
local window={}; for key,value in pairs(door) do window[key]=value end
window.__class="IsoWindow"; window.data={}
local doorSquare={x=8,y=3,z=0}; local windowSquare={x=5,y=3,z=0}
door.square=doorSquare; window.square=windowSquare
function door:getOppositeSquare() return {x=9,y=3,z=self.square.z} end
function window:getOppositeSquare() return {x=9,y=3,z=self.square.z} end
function doorSquare:getX() return self.x end; function doorSquare:getY() return self.y end; function doorSquare:getZ() return self.z end
windowSquare.getX,windowSquare.getY,windowSquare.getZ=doorSquare.getX,doorSquare.getY,doorSquare.getZ
function doorSquare:getObjects() return {door} end; function windowSquare:getObjects() return {window} end
instanceof=function(o,kind) return o==window and kind=="IForceablePortal" or oldInstance(o,kind) end
local reads=0
U.gridSquare=function(x,y,z)
    reads=reads+1
    if x==8 and y==3 then return doorSquare elseif x==5 and y==3 then return windowSquare end
end
SC.ExpeditionPlaces={siteContainsPoint=function(site,x) return site=="selected" and x<9 end}
local scan,found,done={},nil,false
while not done do
    reads=0; found,done=F.findSitePortal(a,"selected","trip",scan)
    check(reads<=32,"discovery visits at most 32 squares per slice")
end
check(found==door,"entry chooses a door before a nearer locked window")
local savedAttempt=door.data.LF_ForceEntryAttempt
door.data.LF_ForceEntryAttempt={missionId="trip"}; scan={}
repeat found,done=F.findSitePortal(a,"selected","trip",scan) until done
check(found==window,"a portal already attempted by this mission is excluded")
door.invalid=true; a.square.z=1; windowSquare.z=1; scan={}
repeat found,done=F.findSitePortal(a,"selected","trip",scan) until done
check(found==nil,"automatic entry excludes an upper-floor window")
U.gridSquare,instanceof=grid,oldInstance
print("FORCE_ENTRY_PASS checks="..checks)
