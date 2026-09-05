-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion

local function makeFluid(initial)
    local fluid = { values = {} }
    for kind, amount in pairs(initial or {}) do fluid.values[kind] = amount end
    function fluid:getAmount()
        local total = 0
        for _, amount in pairs(self.values) do total = total + amount end
        return total
    end
    function fluid:isMixture()
        local count = 0
        for _ in pairs(self.values) do count = count + 1 end
        return count > 1
    end
    function fluid:createFluidSample()
        local entries = {}
        local total = self:getAmount()
        for kind, amount in pairs(self.values) do
            entries[#entries + 1] = { kind = kind, amount = amount }
        end
        table.sort(entries, function(a, b) return a.kind < b.kind end)
        return {
            size = function() return #entries end,
            getFluid = function(_, index)
                local entry = entries[index + 1]
                return entry and {
                    key = entry.kind,
                    getFluidTypeString = function() return entry.kind end,
                } or nil
            end,
            getPercentage = function(_, index)
                local entry = entries[index + 1]
                return entry and entry.amount / total or 0
            end,
            release = function() fluid.sampleReleased = true end,
        }
    end
    function fluid:getSpecificFluidAmount(kind)
        return self.values[kind.key] or 0
    end
    function fluid:getPrimaryFluid()
        local kind
        for candidate in pairs(self.values) do kind = candidate break end
        return kind and { getFluidTypeString = function() return kind end } or nil
    end
    function fluid:Empty() self.values = {} end
    function fluid:addFluid(kind, amount)
        self.values[kind] = (self.values[kind] or 0) + amount
    end
    return fluid
end

local function makeItem(itemType, options)
    local item = options or {}
    item.itemType = itemType
    item.modData = item.modData or {}
    item.condition = item.condition or 10
    function item:getFullType() return self.itemType end
    function item:getType() return string.gsub(self.itemType, "Base%.", "") end
    function item:getCategory() return self.category or "Item" end
    function item:getDisplayCategory() return self.displayCategory or self:getCategory() end
    function item:getCondition() return self.condition end
    function item:getConditionMax() return self.conditionMax or 10 end
    function item:setCondition(value) self.condition = value end
    function item:getModData() return self.modData end
    function item:isFavorite() return self.favorite == true end
    function item:setFavorite(value) self.favorite = value == true end
    function item:getUses() return self.uses end
    function item:setUses(value) self.uses = value end
    function item:getUsedDelta() return self.usedDelta end
    function item:setUsedDelta(value) self.usedDelta = value end
    function item:getAge() return self.age end
    function item:setAge(value) self.age = value end
    function item:getBloodLevel() return self.bloodLevel end
    function item:setBloodLevel(value) self.bloodLevel = value end
    function item:getDirtiness() return self.dirtiness end
    function item:setDirtiness(value) self.dirtiness = value end
    function item:getWetness() return self.wetness end
    function item:setWetness(value) self.wetness = value end
    function item:getHaveBeenRepaired() return self.repairs end
    function item:setHaveBeenRepaired(value) self.repairs = value end
    function item:isCooked() return self.cooked end
    function item:setCooked(value) self.cooked = value == true end
    function item:getFluidContainer() return self.fluid end
    function item:getAllWeaponParts() return self.weaponParts or {} end
    function item:attachWeaponPart(part)
        self.weaponParts = self.weaponParts or {}
        self.weaponParts[#self.weaponParts + 1] = part
    end
    function item:getCurrentAmmoCount() return self.currentAmmo or 0 end
    function item:setCurrentAmmoCount(value) self.currentAmmo = value end
    function item:isContainsClip() return self.containsClip == true end
    function item:setContainsClip(value) self.containsClip = value == true end
    function item:isRoundChambered() return self.roundChambered == true end
    function item:setRoundChambered(value) self.roundChambered = value == true end
    function item:isJammed() return self.jammed == true end
    function item:setJammed(value) self.jammed = value == true end
    function item:getFireMode() return self.fireMode end
    function item:setFireMode(value) self.fireMode = value end
    function item:isMemento()
        return self.memento == true or self.itemType == "Base.Photo"
            or self.itemType == "Base.Locket"
    end
    function item:hasTag(tag) return self.tags and self.tags[tag] == true end
    function item:getInventory() return self.nestedInventory end
    return item
end

local function makeInventory(initial)
    local inventory = { items = initial or {} }
    for _, item in ipairs(inventory.items) do item.container = inventory end
    function inventory:getItems() return self.items end
    function inventory:AddItem(value)
        local item
        if type(value) == "table" then
            item = value
        elseif string.find(tostring(value), "Base.Bag_", 1, true) == 1 then
            item = makeItem(value, { nestedInventory = makeInventory() })
        elseif string.find(tostring(value), "WaterBottle", 1, true) ~= nil then
            item = makeItem(value, { fluid = makeFluid() })
        else
            item = makeItem(value)
        end
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function inventory:Remove(item)
        for index, candidate in ipairs(self.items) do
            if candidate == item then
                table.remove(self.items, index)
                item.container = nil
                return true
            end
        end
        return false
    end
    function inventory:contains(item)
        for _, candidate in ipairs(self.items) do if candidate == item then return true end end
        return false
    end
    return inventory
end

local function emptyList()
    local list = {}
    function list:size() return 0 end
    function list:get() return nil end
    return list
end

local function makeBody()
    local body = { health = 100, infected = false, parts = emptyList() }
    function body:getOverallBodyHealth() return self.health end
    function body:getHealth() return self.health end
    function body:isInfected() return self.infected end
    function body:getInfectionTime() return self.infectionTime or -1 end
    function body:getInfectionMortalityDuration() return self.mortality or -1 end
    function body:getApparentInfectionLevel() return 0 end
    function body:getBodyParts() return self.parts end
    function body:setInfected(value) self.infected = value == true end
    function body:setInfectionTime(value) self.infectionTime = value end
    function body:setInfectionMortalityDuration(value) self.mortality = value end
    function body:setOverallBodyHealth(value) self.health = value end
    return body
end

local function makeActor(square, inventory)
    local actor = {
        __class = "IsoPlayer",
        owned = true,
        square = square,
        inventory = inventory or makeInventory(),
        data = {},
        body = makeBody(),
        health = 100,
        wornOrder = {}, wornByLocation = {}, wornLocations = {},
        attachedOrder = {}, attachedByLocation = {}, attachedLocations = {},
    }
    actor.stats = { hunger = 0.2, thirst = 0.2 }
    function actor.stats:get(stat)
        if stat == CharacterStat.HUNGER then return self.hunger end
        if stat == CharacterStat.THIRST then return self.thirst end
        return 0
    end
    function actor.stats:set(stat, value)
        if stat == CharacterStat.HUNGER then self.hunger = value return true end
        if stat == CharacterStat.THIRST then self.thirst = value return true end
        return false
    end
    function actor:getModData() return self.data end
    function actor:getCurrentSquare() return self.square end
    function actor:getSquare() return self.square end
    function actor:getX() return self.square:getX() + 0.5 end
    function actor:getY() return self.square:getY() + 0.5 end
    function actor:getZ() return self.square:getZ() end
    function actor:isDead() return false end
    function actor:getInventory() return self.inventory end
    function actor:getPrimaryHandItem() return self.primary end
    function actor:setPrimaryHandItem(item) self.primary = item end
    function actor:getSecondaryHandItem() return self.secondary end
    function actor:setSecondaryHandItem(item) self.secondary = item end
    function actor:getWornItems()
        local owner = self
        return {
            size = function() return #owner.wornOrder end,
            get = function(_, index)
                local item = owner.wornOrder[index + 1]
                if not item then return nil end
                return {
                    getItem = function() return item end,
                    getLocation = function() return owner.wornLocations[item] end,
                }
            end,
        }
    end
    function actor:getWornItem(location) return self.wornByLocation[location] end
    function actor:setWornItem(location, item)
        local prior = self.wornByLocation[location]
        if prior then self:removeWornItem(prior) end
        self.wornByLocation[location] = item
        self.wornLocations[item] = location
        self.wornOrder[#self.wornOrder + 1] = item
    end
    function actor:removeWornItem(item)
        local location = self.wornLocations[item]
        if location then self.wornByLocation[location] = nil end
        self.wornLocations[item] = nil
        for index = #self.wornOrder, 1, -1 do
            if self.wornOrder[index] == item then table.remove(self.wornOrder, index) end
        end
    end
    function actor:getAttachedItems()
        local owner = self
        return {
            size = function() return #owner.attachedOrder end,
            get = function(_, index)
                local item = owner.attachedOrder[index + 1]
                if not item then return nil end
                return {
                    getItem = function() return item end,
                    getLocation = function() return owner.attachedLocations[item] end,
                }
            end,
        }
    end
    function actor:getAttachedItem(location) return self.attachedByLocation[location] end
    function actor:setAttachedItem(location, item)
        local prior = self.attachedByLocation[location]
        if prior then self:removeAttachedItem(prior) end
        self.attachedByLocation[location] = item
        self.attachedLocations[item] = location
        self.attachedOrder[#self.attachedOrder + 1] = item
    end
    function actor:removeAttachedItem(item)
        local location = self.attachedLocations[item]
        if location then self.attachedByLocation[location] = nil end
        self.attachedLocations[item] = nil
        for index = #self.attachedOrder, 1, -1 do
            if self.attachedOrder[index] == item then table.remove(self.attachedOrder, index) end
        end
    end
    function actor:getBodyDamage() return self.body end
    function actor:getHealth() return self.health end
    function actor:setHealth(value) self.health = value end
    function actor:getStats() return self.stats end
    function actor:getPerkList() return {} end
    function actor:getXp() return {} end
    function actor:getMoodles() return {} end
    function actor:getEmitter() return {} end
    function actor:getVisual() return {} end
    function actor:getOutfitName() return "" end
    function actor:getDisplayName() return "Persistence Fellow" end
    return actor
end

local square = { x = 20, y = 30, z = 0 }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end

local provider = { testOnly = true, spawned = {} }
function provider:isActor(actor) return actor and actor.owned == true end
function provider:spawn(spawnSquare)
    local generated = makeItem("Base.GeneratedOutfit")
    local actor = makeActor(spawnSquare, makeInventory({ generated }))
    actor:setWornItem("TorsoExtra", generated)
    if self.rejectWornLocation ~= nil then
        local setWornItem = actor.setWornItem
        local rejectedLocation = self.rejectWornLocation
        function actor:setWornItem(location, item)
            if location == rejectedLocation then
                error("unsupported saved body location: " .. tostring(location))
            end
            return setWornItem(self, location, item)
        end
    end
    self.spawned[#self.spawned + 1] = actor
    return actor
end
function provider:remove(actor)
    actor.owned = false
    return true
end

check(SC.Actor._setProviderForTests(provider), "test provider installed")

local original = makeActor(square)
local oldMemory = { kind = "shared_escape", at = 500, impact = 1, praised = false }
local record, registerReason = SC.Registry.register(original, {
    id = "sc-character-migration",
    recruited = true,
    identity = { forename = "Morgan", surname = "Reed", gender = "female" },
    state = {
        order = { current = "follow", followDistance = 3, scavenge = true,
            movementMode = "walk", combatStance = "defensive" },
        personality = {
            archetype = "steady", trust = 37, bond = 24, morale = 61, stress = 18,
            memories = { oldMemory },
            background = { occupation = "mechanic", home = "rosewood" },
            care = { treatments = 2 }, reveals = { background = 2 },
            timeTogetherMs = 7200000, lastEncouragedAt = 321,
        },
        downtime = {},
    },
})
check(record ~= nil, registerReason)
check(SC.Commands.restore(original, record), "old 0.13.0-style command state normalizes")
local normalized = SC.Commands.peek(original)
local initialProfile = SC.Personality.copy(normalized.personalityProfile)
local initialObjectiveId = normalized.objectives.active and normalized.objectives.active.id
local initialObjectiveSerial = normalized.objectives.serial
local initialKeepsakeKey = normalized.possessions.keepsake.key
local initialCount = #original.inventory.items
check(normalized.trust == 37 and normalized.bond == 24 and normalized.morale == 61
    and normalized.stress == 18 and normalized.timeTogetherMs == 7200000
    and normalized.lastEncouragedAt == 321
    and #normalized.memories == 1 and normalized.memories[1].kind == "shared_escape",
    "0.13.0 relationship values and memories survive additive normalization")
check(initialProfile.version == 2 and normalized.personality ~= "steady"
    and initialObjectiveId ~= nil and initialObjectiveSerial == 1
    and initialKeepsakeKey == "sc-character-migration:keepsake:1",
    "old state receives one deterministic profile, objective, and keepsake")

check(SC.Commands.restore(original, record), "normalization may safely run again")
local normalizedAgain = SC.Commands.peek(original)
check(normalizedAgain.personalityProfile.archetype == initialProfile.archetype
    and normalizedAgain.personalityProfile.courage == initialProfile.courage
    and normalizedAgain.objectives.serial == initialObjectiveSerial
    and normalizedAgain.objectives.active.id == initialObjectiveId
    and normalizedAgain.possessions.keepsake.key == initialKeepsakeKey
    and #original.inventory.items == initialCount,
    "repeated migration is deterministic and idempotent")

local keepsakeItem, rootDepth = SC.PersonalItems.find(original, initialKeepsakeKey)
check(keepsakeItem ~= nil and rootDepth == 0, "migrated keepsake starts in root inventory")
local nested = makeInventory()
local bag = makeItem("Base.Bag_Schoolbag", {
    nestedInventory = nested, favorite = true, modData = { role = "medical", nested = { rank = 2 } },
})
original.inventory:AddItem(bag)
original.inventory:Remove(keepsakeItem)
nested:AddItem(keepsakeItem)
local bottle = makeItem("Base.WaterBottleFull", {
    fluid = makeFluid({ Water = 0.7, Coffee = 0.2 }), uses = 3, usedDelta = 0.65,
    age = 1.25, cooked = true,
})
nested:AddItem(bottle)
local scope = makeItem("Base.x4Scope", { condition = 7, modData = { zeroed = true } })
local weapon = makeItem("Base.VarmintRifle", {
    __class = "HandWeapon", condition = 4, repairs = 2, bloodLevel = 0.35,
    dirtiness = 0.6, wetness = 18, currentAmmo = 5, containsClip = true,
    roundChambered = true, jammed = false, fireMode = "Single", weaponParts = { scope },
})
local jacket = makeItem("Base.Jacket_Police", { condition = 6, bloodLevel = 0.45 })
local knife = makeItem("Base.HuntingKnife", { condition = 8 })
-- A loaded spare magazine (LF-02): not a HandWeapon, but it tracks its rounds via
-- getCurrentAmmoCount/setCurrentAmmoCount and must keep them across save/restore.
local magazine = makeItem("Base.556Clip", { currentAmmo = 15 })
-- Build 42's base InventoryItem does not expose getInventory(); only real
-- InventoryContainer items do. A failed method lookup returns an error string
-- through SCCall and must never be mistaken for a nested container object.
knife.getInventory = nil
original.inventory:AddItem(weapon)
original.inventory:AddItem(magazine)
original.inventory:AddItem(jacket)
original.inventory:AddItem(knife)
original:setPrimaryHandItem(weapon)
original:setSecondaryHandItem(weapon)
original:setWornItem("Back", bag)
original:setWornItem("Jacket", jacket)
original:setAttachedItem("Belt Left", knife)
local captured, captureReason = SC.Persistence.captureRecord(record)
check(captured ~= nil,
    "plain native items without getInventory still capture: " .. tostring(captureReason))
check(bottle.fluid.sampleReleased == true,
    "fluid persistence releases the pooled Build 42 sample after exact capture")
check(captured.possessions.keepsake.status == "carried"
    and type(captured.possessions.keepsake.nestedCarried) == "table"
    and captured.possessions.keepsake.nestedCarried.personal.key == initialKeepsakeKey,
    "save capture stores one narrow nested-carried keepsake snapshot")

do
-- LF-01: recoverable retirement. A still-living recruit whose native instance
-- fails the health gate must be preserved into the restore-pending queue (kept by
-- the next save, re-spawned by restorePulse) rather than silently deleted.
local retained, retainReason = SC.Persistence.retainForRecovery(record)
check(retained == true and type(SC.Persistence.pendingSnapshot()[record.id]) == "table",
    "a capturable recruit is retained for recovery in the restore-pending set: " .. tostring(retainReason))

-- Fallback: an actor too broken to capture is recovered from its last verified
-- snapshot instead. Reuse the known-good captured document under a fresh id.
local snapshotDoc = {}
for key, value in pairs(captured) do snapshotDoc[key] = value end
snapshotDoc.id = "sc-recovery-snapshot"
local snapRetained = SC.Persistence.retainForRecovery(
    { id = "sc-recovery-snapshot", recruited = true,
        runtime = { lastStableSnapshot = snapshotDoc } })
check(snapRetained == true
        and type(SC.Persistence.pendingSnapshot()["sc-recovery-snapshot"]) == "table",
    "an uncapturable recruit is recovered from its last verified snapshot")

-- Refusal: with neither a capture nor a snapshot, recovery refuses so the caller
-- blocks the destructive removal instead of losing the companion.
local bareRetained, bareReason = SC.Persistence.retainForRecovery(
    { id = "sc-recovery-none", recruited = true, runtime = {} })
check(bareRetained == false and bareReason == "no_recoverable_snapshot",
    "with no capture and no snapshot, recovery refuses so the caller blocks deletion")
end
check(captured.inventory.schema == 2 and captured.inventory.complete == true
    and captured.inventory.count == 8
    and captured.inventory.equipment.primary ~= nil
    and captured.inventory.equipment.primary == captured.inventory.equipment.secondary
    and #captured.inventory.equipment.worn == 2
    and #captured.inventory.equipment.attached == 1,
    "schema 2 captures a complete tree, shared hand reference, worn slots and weapon part: count="
        .. tostring(captured.inventory.count) .. " worn="
        .. tostring(#captured.inventory.equipment.worn) .. " primary="
        .. tostring(captured.inventory.equipment.primary) .. " secondary="
        .. tostring(captured.inventory.equipment.secondary))

do
    local originalMemories = record.state.personality.memories
    local memoryLimit = SC.Config.get("maxMemories")
    local boundaryMemories = {}
    for index = 1, memoryLimit do
        boundaryMemories[index] = { kind = "boundary", at = index, impact = 1 }
    end
    record.state.personality.memories = boundaryMemories
    local boundary, boundaryReason = SC.Persistence.captureRecord(record)
    check(boundary ~= nil and #boundary.personality.memories == memoryLimit,
        "configured memory boundary copies exactly without truncation: "
            .. tostring(boundaryReason))
    boundaryMemories[memoryLimit + 1] = { kind = "over-boundary", at = 999 }
    local oversized, oversizedReason = SC.Persistence.captureRecord(record)
    check(oversized == nil and string.find(tostring(oversizedReason),
        "exceeds the configured maximum", 1, true) ~= nil,
        "one-over memory list fails actor capture instead of silently truncating")
    record.state.personality.memories = originalMemories
end

do
    local originalInventory = original.inventory
    local originalPrimary = original:getPrimaryHandItem()
    local originalSecondary = original:getSecondaryHandItem()
    original:setPrimaryHandItem(nil)
    original:setSecondaryHandItem(nil)
    original:removeWornItem(bag)
    original:removeWornItem(jacket)
    original:removeAttachedItem(knife)
    local inventoryLimit = SC.Config.get("persistence", "maxSavedInventoryItems")
    local boundaryItems = {}
    for index = 1, inventoryLimit do
        boundaryItems[index] = makeItem("Base.InventoryBoundary" .. tostring(index))
    end
    original.inventory = makeInventory(boundaryItems)
    local boundary, boundaryReason = SC.Persistence.captureRecord(record)
    check(boundary ~= nil and boundary.inventory.count == inventoryLimit,
        "configured inventory boundary captures every item without truncation: "
            .. tostring(boundaryReason) .. " count="
            .. tostring(boundary and boundary.inventory and boundary.inventory.count)
            .. " expected=" .. tostring(inventoryLimit))

    original.inventory:AddItem(makeItem("Base.InventoryBoundaryOver"))
    local oversized, oversizedReason = SC.Persistence.captureRecord(record)
    check(oversized == nil and string.find(tostring(oversizedReason),
        "inventory exceeds the persistence item limit", 1, true) ~= nil,
        "one-over inventory fails actor capture instead of returning a partial tree: "
            .. tostring(oversizedReason))
    local priorDocument = { schema = SC.Identity.saveSchema,
        companions = { untouched = { marker = "keep" } } }
    local saveData = { [SC.Identity.saveKey] = priorDocument }
    local savePlayer = { getModData = function() return saveData end }
    local saved, saveReason = SC.Persistence.save(savePlayer)
    check(saved == false and saveData[SC.Identity.saveKey] == priorDocument
            and saveData[SC.Identity.saveKey].companions.untouched.marker == "keep",
        "one-over inventory aborts save and preserves the previous document: "
            .. tostring(saveReason))
    original.inventory = originalInventory
    original:setPrimaryHandItem(originalPrimary)
    original:setSecondaryHandItem(originalSecondary)
    original:setWornItem("Back", bag)
    original:setWornItem("Jacket", jacket)
    original:setAttachedItem("Belt Left", knife)
end

SC.Commands.reset(original)
SC.Registry.unregister(original)
local restored, restoreReason = SC.Persistence.restoreAt(captured, square)
check(restored ~= nil, restoreReason)
local restoredState = SC.Commands.peek(restored)
local restoredKeepsake, restoredDepth = SC.PersonalItems.find(restored, initialKeepsakeKey)
check(restoredKeepsake ~= nil and restoredDepth == 1 and restoredKeepsake:isFavorite()
    and restoredState.possessions.keepsake.status == "carried"
    and restoredState.possessions.keepsake.key == initialKeepsakeKey,
    "schema 2 restores the keepsake inside its original bag with marker and favourite state")
local function findType(inventory, itemType)
    for _, candidate in ipairs(inventory.items) do
        if candidate:getFullType() == itemType then return candidate end
        if candidate:getInventory() then
            local found = findType(candidate:getInventory(), itemType)
            if found then return found end
        end
    end
    return nil
end
local restoredBag = findType(restored.inventory, "Base.Bag_Schoolbag")
local restoredBottle = findType(restored.inventory, "Base.WaterBottleFull")
local restoredWeapon = findType(restored.inventory, "Base.VarmintRifle")
local restoredJacket = findType(restored.inventory, "Base.Jacket_Police")
local restoredKnife = findType(restored.inventory, "Base.HuntingKnife")
check(findType(restored.inventory, "Base.GeneratedOutfit") == nil
    and restoredBag and restoredBag:getModData().role == "medical"
    and restoredBag:getModData().nested.rank == 2,
    "restore removes generated outfit inventory and preserves nested item modData")
check(restored:getPrimaryHandItem() == restoredWeapon
    and restored:getSecondaryHandItem() == restoredWeapon
    and restored:getWornItem("Back") == restoredBag
    and restored:getWornItem("Jacket") == restoredJacket
    and restored:getAttachedItem("Belt Left") == restoredKnife,
    "restore reapplies exact hand, worn and attached equipment references")
check(restoredWeapon.condition == 4 and restoredWeapon.repairs == 2
    and math.abs(restoredWeapon.bloodLevel - 0.35) < 0.001
    and math.abs(restoredWeapon.dirtiness - 0.6) < 0.001
    and restoredWeapon.currentAmmo == 5 and restoredWeapon.containsClip == true
    and restoredWeapon.roundChambered == true and restoredWeapon.fireMode == "Single"
    and #restoredWeapon.weaponParts == 1
    and restoredWeapon.weaponParts[1]:getFullType() == "Base.x4Scope"
    and restoredWeapon.weaponParts[1]:getModData().zeroed == true,
    "weapon state and detached attachment items survive restore")
local restoredMagazine = findType(restored.inventory, "Base.556Clip")
check(restoredMagazine ~= nil and restoredMagazine.currentAmmo == 15,
    "a loaded spare magazine (not a HandWeapon) keeps its rounds across save/restore (LF-02)")
check(restoredBottle.uses == 3 and math.abs(restoredBottle.usedDelta - 0.65) < 0.001
    and math.abs(restoredBottle.age - 1.25) < 0.001 and restoredBottle.cooked == true
    and math.abs(restoredBottle.fluid:getAmount() - 0.9) < 0.001
    and math.abs(restoredBottle.fluid.values.Water - 0.7) < 0.001
    and math.abs(restoredBottle.fluid.values.Coffee - 0.2) < 0.001,
    "stack, drainable, food and exact mixed-fluid state survive restore")

SC.Commands.reset(restored)
SC.Registry.unregister(restored)
local compatibilityLocation = captured.inventory.equipment.worn[1].location
captured.inventory.equipment.worn[1].location = "eartop"
provider.rejectWornLocation = "eartop"
local compatible, compatibilityReason = SC.Persistence.restoreAt(captured, square)
local compatibilityItem = compatible and findType(
    compatible.inventory, "Base.Bag_Schoolbag") or nil
check(compatible ~= nil and compatibilityItem ~= nil
        and compatible:getWornItem("eartop") == nil,
    "obsolete saved body locations keep the exact item in inventory without aborting actor restore: "
        .. tostring(compatibilityReason))
if compatible ~= nil then
    SC.Commands.reset(compatible)
    SC.Registry.unregister(compatible)
end
provider.rejectWornLocation = nil
captured.inventory.equipment.worn[1].location = compatibilityLocation
local verifiedCount = captured.inventory.count
captured.inventory.count = verifiedCount + 1
local rejected, rejectionReason = SC.Persistence.restoreAt(captured, square)
local rejectedActor = provider.spawned[#provider.spawned]
check(rejected == nil and string.find(tostring(rejectionReason), "count", 1, true) ~= nil
    and rejectedActor.owned == false,
    "incomplete inventory documents fail closed and roll back the native actor")
captured.inventory.count = verifiedCount
local function duplicateSavedEntry(source, id)
    local duplicate = {}
    for key, value in pairs(source) do duplicate[key] = value end
    duplicate.id, duplicate.children, duplicate.weaponParts = id, {}, {}
    return duplicate
end
captured.inventory.roots[#captured.inventory.roots + 1] = duplicateSavedEntry(
    captured.possessions.keepsake.nestedCarried, "i-duplicate-1")
captured.inventory.roots[#captured.inventory.roots + 1] = duplicateSavedEntry(
    captured.possessions.keepsake.nestedCarried, "i-duplicate-2")
captured.inventory.count = captured.inventory.count + 2
local deduplicated, duplicateReason = SC.Persistence.restoreAt(captured, square)
check(deduplicated ~= nil, duplicateReason)
local duplicateItem, duplicateDepth = SC.PersonalItems.find(deduplicated, initialKeepsakeKey)
local duplicateCount = duplicateItem and 1 or 0
check(duplicateCount == 1 and duplicateDepth == 1,
    "duplicate saved personal keys retain one verified item during restore")

SC.Commands.reset(deduplicated)
SC.Registry.unregister(deduplicated)
local deferredProvider = { testOnly = true, polls = 0 }
function deferredProvider:isActor(actor) return actor and actor.owned == true end
function deferredProvider:requestSpawn(spawnSquare)
    self.square = spawnSquare
    return 91
end
function deferredProvider:pollSpawn(request)
    check(request == 91, "persistence polls the matching deferred native request")
    self.polls = self.polls + 1
    if self.polls == 1 then return nil, "spawn_pending" end
    return makeActor(self.square)
end
function deferredProvider:cancelSpawn() return true end
function deferredProvider:remove(actor)
    actor.owned = false
    return true
end
check(SC.Actor._setProviderForTests(deferredProvider),
    "deferred persistence provider installed")
local deferredRestore, deferredReason, deferredTicket = SC.Persistence.restoreAt(captured, square)
check(deferredRestore == nil and deferredReason == "spawn_pending"
    and deferredTicket ~= nil and SC.Registry.byId(captured.id) == nil,
    "persistence retains a ticket without registering a half-built native actor")
local completedRestore, completedRecord = SC.Actor.pollSpawn(deferredTicket)
check(completedRestore ~= nil and completedRecord.id == captured.id
    and SC.Registry.byId(captured.id).actor == completedRestore,
    "persistence finalizes a deferred native actor through the normal restore transaction")

print("CHARACTER_DEPTH_PERSISTENCE_PASS checks=" .. tostring(checks))
