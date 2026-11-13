-- SPDX-License-Identifier: MIT
-- Stock wardrobe action, including its deferred logistics effect and isolation.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local N, actor = SC.NativeActions, f.actor("native-wardrobe",3,3,{})
local root, owned, changes = actor:getInventory(), true, 0
local worn = {}
function actor:getWornItem(slot) return worn[slot] end
function actor:setWornItem(slot,item) worn[slot]=item; changes=changes+1 end
function actor:reportEvent() end
function actor:setIsAiming() end
function actor:isTimedActionInstant() return false end
function actor:playSound() return 1 end
function actor:getEmitter() return {isPlaying=function() return false end,stopSound=function() end,playSound=function() return 1 end} end
function actor:removeFromHands() end
actor.characterActions={}
function actor.characterActions:add(value) self[#self+1]=value end
function actor.characterActions:remove(value) for i,x in ipairs(self) do if x==value then table.remove(self,i); return end end end
function actor.characterActions:contains(value) for _,x in ipairs(self) do if x==value then return true end end return false end
function actor.characterActions:size() return #self end
function actor:getCharacterActions() return self.characterActions end
ItemTag=ItemTag or {}; ItemTag.REPLACE_PRIMARY="REPLACE_PRIMARY"; ItemTag.WEARABLE="WEARABLE"
local function bag()
    local item=f.item("Base.Bag_Schoolbag","Container",{__class="InventoryContainer",nestedInventory=f.inventory({}),equipLocation=ItemBodyLocation.BACK})
    function item:getClothingItem() end
    function item:setJobDelta() end
    function item:setJobType() end
    function item:getOutermostContainer() return root end
    function item:getUnequipSound() end
    return item
end
local item=bag(); local nested=f.inventory({}); nested:AddItem(item)
local provider={directNative=true}
local function start()
    local okay,why=N.dispatch(actor,"walk",{action="wear_clothing",item=item,validate=function() return owned end},provider)
    assert(okay,tostring(why))
    return assert(N.visualToken(actor,"wear_clothing"))
end
local action=start(); action:start(); action:complete(); action:perform()
assert(changes==0,"stock pose must not escape the logistics commit boundary")
assert(not N.commitClothingVisual(f.player,action,item),"cannot equip on the main player")
nested:Remove(item); root:AddItem(item)
assert(N.commitClothingVisual(actor,action,item) and worn[ItemBodyLocation.BACK]==item,"stock action equips the exact staged bag")
assert(N.commitClothingVisual(actor,action,item) and changes==1,"duplicate commit cannot equip twice")
N.clearVisual(actor); worn[ItemBodyLocation.BACK]=nil; item=bag(); root:AddItem(item)
action=start(); action:start(); owned=false; action:stop()
assert(not N.commitClothingVisual(actor,action,item) and changes==1,"cancelled owner cannot apply a late equipment effect")
N.clearVisual(actor)
-- The stock unequip constructor and attachment callbacks must not touch UI.
function getPlayerHotbar() error("NPC tried to borrow the player hotbar") end
function getPlayerInventory() error("NPC tried to refresh the player inventory") end
function isForceDropHeavyItem() return false end
function actor:getWornItems()
    local rows={}
    for slot,value in pairs(worn) do
        local entry={location=slot,item=value}
        function entry:getLocation() return self.location end
        function entry:getItem() return self.item end
        rows[#rows+1]=entry
    end
    function rows:size() return #self end
    function rows:get(i) return self[i+1] end
    function rows:contains(candidate) for _,r in ipairs(self) do if r.item==candidate then return true end end return false end
    return rows
end
function actor:isEquippedClothing(item) return self:getWornItems():contains(item) end
function actor:removeWornItem(item) for slot,value in pairs(worn) do if value==item then worn[slot]=nil end end end
function actor:getHumanVisual() return {getHairModel=function() return {contains=function() return false end} end} end
owned=true; worn[ItemBodyLocation.BACK]=item
assert(N.startClothing(actor,item,true,function() return owned end))
action=N.visualToken(actor,"wear_clothing")
assert(action.Type=="ISUnequipAction" and not action.fromHotbar,"stock NPC unequip instance")
action:animEvent("attachConnect"); action:complete(); action:perform()
assert(worn[ItemBodyLocation.BACK]==item,"unequip effect waits for its owner")
assert(N.commitClothingVisual(actor,action,item,true) and not actor:isEquippedClothing(item),"native unequip removes only the exact bag")
N.clearVisual(actor)
assert(N.restoreClothingNow(actor,item,ItemBodyLocation.SATCHEL,function() return owned end)
    and worn[ItemBodyLocation.SATCHEL]==item,"emergency stock wear restores the original slot rather than its preferred slot")
item.activatable,item.activated=true,true
function item:playDeactivateSound() end
function syncItemActivated(who) assert(who==actor,"activation belongs to the companion") end
assert(N.startClothing(actor,item,true,function() return owned end) and not item.activated)
action=N.visualToken(actor,"wear_clothing"); assert(N.cancelVisualOwned(actor,action,"combat"))
assert(item.activated and worn[ItemBodyLocation.SATCHEL]==item,"cancelled native undress restores an activated wearable")
local D=SC.Downtime
local _,undress,restore=D._showerForTests()
local stateFor=select(12,D._furnitureForTests())
local shirt=f.item("Base.Shirt_FormalWhite","Clothing",{bodyLocation=ItemBodyLocation.SHIRT})
function shirt:setJobDelta() end
function shirt:setJobType() end
function shirt:getClothingItem() return {} end
function shirt:getUnequipSound() end
function shirt:getOutermostContainer() return root end
root:AddItem(shirt); worn[ItemBodyLocation.SHIRT]=shirt
local function receipt()
    local a={kind="shower",square=actor:getSquare(),fact={},commandSerial=SC.Commands.peek(actor).commandSerial or 0}
    stateFor(actor).active=a
    return a
end
local function pump(fn,a)
    for _=1,12 do
        local ready,why=fn(actor,a)
        if ready~=nil then assert(ready,tostring(why)); return end
        local action=assert(N.visualToken(actor,"wear_clothing")); action:complete(); action:perform()
        f.clock=f.clock+100
    end
    error("wardrobe did not finish")
end
local a=receipt(); pump(undress,a)
assert(not actor:isEquippedClothing(item) and not actor:isEquippedClothing(shirt),"all shower clothes remain owned but are natively removed")
pump(restore,a)
assert(worn[ItemBodyLocation.SATCHEL]==item and worn[ItemBodyLocation.SHIRT]==shirt and not a.showerClothes,"normal dressing restores exact items and slots")
a=receipt(); assert(undress(actor,a)==nil)
action=N.visualToken(actor,"wear_clothing"); action:complete(); action:perform(); assert(undress(actor,a)==nil)
assert(restore(actor,a,true) and worn[ItemBodyLocation.SATCHEL]==item and worn[ItemBodyLocation.SHIRT]==shirt,"interruption mid-undress releases the current native action and immediately restores gear")
a=receipt(); pump(undress,a)
local replacement=f.item("Base.Tshirt_DefaultTEXTURE_TINT","Clothing",{bodyLocation=ItemBodyLocation.SHIRT}); root:AddItem(replacement)
worn[ItemBodyLocation.SHIRT]=replacement
root:Remove(item)
assert(restore(actor,a,true) and worn[ItemBodyLocation.SHIRT]==replacement and not actor:isEquippedClothing(item)
    and a.fact.outfitChanged,"new player clothing choices and items transferred away are preserved without recreation")
root:AddItem(item); worn[ItemBodyLocation.SATCHEL]=item; worn[ItemBodyLocation.SHIRT]=shirt
a=receipt(); pump(undress,a); assert(restore(actor,a)==nil)
local cancelOwned=N.cancelVisualOwned
N.cancelVisualOwned=function(who,...) if who==actor then return false,"native_removal_pending" end return cancelOwned(who,...) end
assert(D.reset(actor)==false and D.peek(actor).active==a and a.showerClothes,
    "pending reset reports incomplete and retains the only outfit receipt")
N.cancelVisualOwned=cancelOwned
assert(D.prepareForSave(actor) and D.peek(actor).active==a and #D.showerOutfitForSave(actor).worn>0,
    "snapshots retain the logical outfit without cancelling or finishing live clothing actions")
assert(D.cancel(actor,"new_order") and not a.showerClothes and worn[ItemBodyLocation.SATCHEL]==item
    and worn[ItemBodyLocation.SHIRT]==shirt,"cancel retries cleanup and restores the exact outfit before release")
stateFor(actor).active=nil
print("PASS native clothing: wear, unequip, exact-slot shower restoration, cancellation and player isolation")
