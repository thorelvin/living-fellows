-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

-- Private diaries have their own harness and one downtime integration block
-- at the end of this file. Keep them inert for every earlier scenario, so no
-- test companion unexpectedly receives a book.
SC_TEST_DIARIES_ENABLED = false
do
    local utility = SurvivorCompanion.GameplayUtil
    local baseConfig = utility.config
    utility.config = function(key)
        if key == "diaryEnabled" and SC_TEST_DIARIES_ENABLED ~= true then return false end
        return baseConfig(key)
    end
end

SC_TEST_CLOCK = SC_TEST_CLOCK or 100000
function getTimestampMs() return SC_TEST_CLOCK end
local worldHour = 12
local rainIntensity, fogIntensity = 0, 0
-- 1 is noon, 0 is night. Flashlight behaviour reads this before the clock.
local daylightStrength = 1
function getGameTime()
    return {
        getHour = function() return worldHour end,
        getTimeOfDay = function() return worldHour end,
        getWorldAgeHours = function() return 240 + SC_TEST_CLOCK / 3600000 end,
    }
end
function getClimateManager()
    return {
        getPrecipitationIntensity = function() return rainIntensity end,
        getFogIntensity = function() return fogIntensity end,
        getDayLightStrength = function() return daylightStrength end,
    }
end
local worldSoundCount = 0
function addSound(source, x, y, z, radius, volume) worldSoundCount = worldSoundCount + 1 end
local uiSounds = {}
SC_TEST_UI_SOUND_HANDLES = {}
function getSoundManager()
    return {
        playUISound = function(_, soundName)
            uiSounds[#uiSounds + 1] = tostring(soundName)
            if SC_TEST_UI_SOUND_HANDLES[soundName] ~= nil then
                return SC_TEST_UI_SOUND_HANDLES[soundName]
            end
            return #uiSounds
        end,
    }
end
function instanceof(value, className)
    return type(value) == "table" and (value.__class == className or value.className == className)
end

CharacterStat = {
    HUNGER = { name = "HUNGER" },
    THIRST = { name = "THIRST" },
    FATIGUE = { name = "FATIGUE" },
    ENDURANCE = { name = "ENDURANCE" },
    STRESS = { name = "STRESS" },
    WETNESS = { name = "WETNESS" },
    NICOTINE_WITHDRAWAL = { name = "NICOTINE_WITHDRAWAL" },
}
CharacterTrait = { DEAF = "DEAF", SMOKER = "SMOKER" }
SystemDisabler = { doCharacterStats = true }
MoodleType = {
    PANIC = "PANIC", PAIN = "PAIN", TIRED = "TIRED", HEAVY_LOAD = "HEAVY_LOAD",
}
Perks = {
    Strength = "Strength", Fitness = "Fitness", Nimble = "Nimble", Aiming = "Aiming",
    Axe = "Axe", Blunt = "Blunt", LongBlade = "LongBlade", LongBlunt = "LongBlunt",
    SmallBlade = "SmallBlade", SmallBlunt = "SmallBlunt", Spear = "Spear",
}
Fluid = {
    Water = { name = "Water" },
    TaintedWater = { name = "TaintedWater" },
}
IsoFlagType = {
    canBeCut = { name = "canBeCut" },
    water = { name = "water" },
    burning = { name = "burning" },
}
IsoDirections = { N = "N", S = "S", E = "E", W = "W" }

local function item(itemType, category, options)
    local value = options or {}
    value.__class = value.__class or (category == "Weapon" and "HandWeapon" or "InventoryItem")
    value.itemType = itemType
    value.category = category or "Item"
    if value.uses == nil then value.uses = 1 end
    function value:getFullType() return self.itemType end
    function value:getType() return string.gsub(self.itemType, "Base%.", "") end
    function value:getDisplayName() return self.itemType end
    function value:getName() return self.customName or self.itemType end
    function value:isCustomName() return self.customName ~= nil end
    function value:setName(name) self.customName = name end
    function value:getCategory() return self.category end
    function value:getDisplayCategory() return self.displayCategory or self.category end
    function value:hasTag(tag) return self.tags and self.tags[tag] == true end
    function value:isMemento()
        return self.memento == true or self.itemType == "Base.Photo"
            or self.itemType == "Base.Photo_VeryOld" or self.itemType == "Base.Locket"
    end
    function value:getModData()
        self.modData = self.modData or {}
        return self.modData
    end
    function value:isFavorite() return self.favorite == true end
    function value:setFavorite(enabled)
        if self.rejectSetFavorite then return false end
        self.favorite = enabled == true
    end
    function value:getInventory() return self.nestedInventory end
    function value:getContainer() return self.container end
    function value:getWorldItem() return self.worldItem end
    function value:setWorldItem(worldItem) self.worldItem = worldItem end
    function value:IsClothing() return self.category == "Clothing" end
    function value:IsInventoryContainer() return self.nestedInventory ~= nil end
    function value:canBeEquipped() return self.equipLocation or self.bodyLocation or "" end
    function value:getCapacity() return self.bagCapacity or 0 end
    function value:getWeightReduction() return self.weightReduction or 0 end
    function value:isDirty() return self.dirty == true end
    function value:isBloody() return self.bloody == true end
    function value:getCondition() return self.condition or 10 end
    function value:getConditionMax() return self.conditionMax or 10 end
    function value:setCondition(amount)
        if self.rejectSetCondition then return false end
        self.condition = amount
    end
    function value:getMaxDamage() return self.damage or 1 end
    function value:getMaxRange() return self.range or (self.ranged and 8 or 1.5) end
    function value:getMinRange() return self.minRange or 0 end
    function value:getSwingTime() return self.swing or 1 end
    function value:getEnduranceMod() return self.enduranceMod or 1 end
    function value:getSharpness() return self.sharpness == nil and 1 or self.sharpness end
    function value:isTwoHandWeapon() return self.twoHanded == true end
    -- Light sources and drainable charge. An ordinary item reports zero
    -- strength and no switch, so it is never mistaken for a torch.
    function value:getLightStrength() return self.lightStrength or 0 end
    function value:canBeActivated() return self.activatable == true end
    function value:canEmitLight()
        return (self.lightStrength or 0) > 0 and (self.usesFloat or 0) > 0
    end
    function value:isActivated() return self.activated == true end
    function value:setActivated(enabled) self.activated = enabled == true end
    function value:playActivateDeactivateSound()
        self.switchSounds = (self.switchSounds or 0) + 1
    end
    function value:isEmptyUses() return (self.usesFloat or 0) <= 0 end
    function value:getCurrentUsesFloat() return self.usesFloat or 0 end
    function value:setCurrentUsesFloat(amount) self.usesFloat = tonumber(amount) or 0 end
    function value:setCurrentUsesFrom(other)
        if self.rejectChargeTransfer then return end
        self.usesFloat = (type(other) == "table" and other.usesFloat) or 0
    end
    function value:getCategories() return self.weaponCategories or {} end
    function value:isRanged() return self.ranged == true end
    function value:isJammed() return self.jammed == true end
    function value:getCurrentAmmoCount() return self.ammo or 0 end
    function value:getMaxAmmo() return self.maxAmmo or 0 end
    function value:getMagazineType() return self.magazineType end
    -- The engine returns an AmmoType object whose tostring is a registry id, never the item type.
    function value:getAmmoType()
        local key = self.ammoType
        if key == nil then return nil end
        return setmetatable({ getItemKey = function() return key end },
            { __tostring = function() return "base:" .. string.lower(tostring(key)) end })
    end
    function value:getNumberOfPages() return self.pages or 0 end
    function value:isAlcoholic() return self.alcoholic == true end
    function value:getBandagePower() return self.bandagePower or 10 end
    function value:getBodyLocation() return self.bodyLocation or "Torso1Legs1" end
    function value:getBiteDefense() return self.biteDefense or 0 end
    function value:getScratchDefense() return self.scratchDefense or 0 end
    function value:getBulletDefense() return self.bulletDefense or 0 end
    function value:getInsulation() return self.insulation or 0 end
    function value:getWindresistance() return self.windResistance or 0 end
    function value:getCombatSpeedModifier() return self.combatSpeedModifier or 1 end
    function value:getRunSpeedModifier() return self.runSpeedModifier or 1 end
    function value:getBloodLevel() return self.bloodLevel or 0 end
    function value:setBloodLevel(amount) self.bloodLevel = amount end
    function value:getDirtiness() return self.dirtiness or 0 end
    function value:setDirtiness(amount) self.dirtiness = amount end
    function value:setWetness(amount) self.wetness = amount end
    function value:getUses() return self.uses end
    function value:getKeyId() return self.keyId or -1 end
    function value:getActualWeight() return self.weight or 1 end
    function value:getUnequippedWeight() return self:getActualWeight() end
    function value:getWeight() return self.weight or 1 end
    function value:getHungerChange() return self.hungerChange or 0 end
    function value:getHungChange() return self.hungerChange or 0 end
    function value:getBaseHunger() return self.baseHunger or self.hungerChange or 0 end
    function value:isRotten() return self.rotten == true end
    function value:isBurnt() return self.burnt == true end
    function value:isBroken() return self.broken == true end
    function value:getCurrentUses() return self.currentUses end
    function value:getMaxUses() return self.maxUses end
    function value:getUsedDelta() return self.usedDelta end
    function value:isbDangerousUncooked() return self.dangerousUncooked == true end
    function value:isCooked() return self.cooked == true end
    function value:getPoisonPower() return self.poisonPower or 0 end
    function value:getScriptItem()
        return {
            isCantEat = function() return value.cantEat == true end,
            -- Script-item flags the engine sets on things that are not gear.
            -- A zombie's visible injuries are hidden clothing worn in the
            -- `wound` slot, which is how a companion ended up looting
            -- Wound_Abdomen_Bite_Male off a corpse.
            isHidden = function() return value.hidden == true end,
            isCosmetic = function() return value.cosmetic == true end,
        }
    end
    function value:getFluidContainer() return self.fluidContainer end
    function value:isWaterSource()
        return self.fluidContainer and self.fluidContainer:contains(Fluid.Water) or false
    end
    function value:Use()
        if self.rejectUse then return false end
        self.used = true
        self.uses = math.max(0, self.uses - 1)
    end
    return value
end

local function inventory(initial)
    local value = { items = initial or {}, capacity = 50 }
    for _, existing in ipairs(value.items) do existing.container = value end
    function value:getItems() return self.items end
    function value:AddItem(added)
        local addedType = type(added) == "table" and added.itemType or added
        if self.throwBeforeAdd then error("injected add failure before mutation") end
        if self.rejectAdd or self.rejectAddType == addedType then return nil end
        if type(added) ~= "table" then added = item(added, "Item") end
        self.items[#self.items + 1] = added
        added.container = self
        if self.throwAfterAddItem == added then
            error("injected add failure after mutation")
        end
        return added
    end
    function value:Remove(removed)
        self.removeCalls = (self.removeCalls or 0) + 1
        if self.throwBeforeRemove then error("injected remove failure before mutation") end
        if self.rejectRemove or self.rejectRemoveItem == removed
            or (self.rejectRemoveNth and self.removeCalls == self.rejectRemoveNth) then return false end
        for index, candidate in ipairs(self.items) do
            if candidate == removed then
                table.remove(self.items, index)
                candidate.container = nil
                if self.throwAfterRemoveItem == removed then
                    error("injected remove failure after mutation")
                end
                return
            end
        end
    end
    function value:containsTypeRecurse(itemType)
        for _, candidate in ipairs(self.items) do
            if candidate:getType() == itemType or candidate:getFullType() == itemType then return true end
        end
        return false
    end
    function value:contains(itemType)
        if type(itemType) == "table" then
            for _, candidate in ipairs(self.items) do if candidate == itemType then return true end end
            return false
        end
        return self:containsTypeRecurse(itemType)
    end
    function value:getParent() return self.owner end
    function value:getCapacityWeight()
        local total = 0
        for _, candidate in ipairs(self.items) do total = total + candidate:getActualWeight() end
        return total
    end
    function value:getEffectiveCapacity(character) return self.effectiveCapacity or self.capacity end
    function value:getFreeCapacity(character)
        return math.max(0, self:getEffectiveCapacity(character) - self:getCapacityWeight())
    end
    function value:getMaxWeight() return self.capacity end
    function value:getCapacity() return self.capacity end
    function value:hasRoomFor(character, candidate)
        if self.capacityCheckThrows then error("injected capacity check failure") end
        self.lastCapacityOwner = character
        if self.rejectRoom then return false end
        if self.expectedCapacityOwner ~= nil and character ~= self.expectedCapacityOwner then
            self.capacityOwnerMismatch = true
            return false
        end
        return self:getCapacityWeight() + candidate:getUnequippedWeight()
            <= self:getEffectiveCapacity(character) + 0.001
    end
    function value:haveThisKeyId(keyId)
        for _, candidate in ipairs(self.items) do
            if type(candidate.getKeyId) == "function" and candidate:getKeyId() == keyId then
                return candidate
            end
        end
        return nil
    end
    return value
end

local function buildKit()
    return {
        item("Base.Hammer", "Tool", { tags = { Hammer = true } }),
        item("Base.Plank", "Material"),
        item("Base.Nails", "Material"),
        item("Base.Nails", "Material"),
    }
end

local function bodyPart(options)
    local value = options or {}
    function value:getType() return self.name or "ForeArm_L" end
    function value:bleeding() return self.isBleeding == true end
    function value:getBleedingTime() return self.isBleeding and 10 or 0 end
    function value:bitten() return self.isBitten == true end
    function value:IsInfected() return self.infected == true end
    function value:isInfectedWound() return self.infectedWound == true end
    function value:bandaged() return self.isBandaged == true end
    function value:isBandageDirty() return self.dirty == true end
    function value:scratched() return self.isScratched == true end
    function value:isCut() return self.cut == true end
    function value:deepWounded() return self.deep == true end
    function value:getBurnTime() return self.burn or 0 end
    function value:getFractureTime() return self.fracture or 0 end
    function value:haveBullet() return self.bullet == true end
    function value:haveGlass() return self.glass == true end
    function value:getBandageLife() return self.bandageLife or 0 end
    function value:isAlcoholicBandage() return self.bandageAlcoholic == true end
    function value:getBandageType() return self.bandageType end

    -- Wound mutation surface, mirroring the 42.20.4 BodyPart methods
    -- SCZombieAttack.applyWound drives. `failSetters[name] = true` makes that
    -- one setter throw, so a partial commit can be exercised: the health
    -- deduction lands and a later setter does not.
    value.health = value.health or 100
    value.woundInfectionLevel = value.woundInfectionLevel or 0
    value.failSetters = value.failSetters or {}
    value.setterCalls = value.setterCalls or {}
    local function record(part, name, ...)
        part.setterCalls[name] = (part.setterCalls[name] or 0) + 1
        part.lastArgs = part.lastArgs or {}
        part.lastArgs[name] = { ... }
        if part.failSetters[name] then error(name .. " rejected by fixture") end
    end
    function value:getHealth() return self.health end
    function value:SetHealth(amount)
        record(self, "SetHealth", amount)
        self.health = amount
    end
    function value:setBleeding(flag)
        record(self, "setBleeding", flag)
        self.isBleeding = flag == true
    end
    function value:SetBitten(flag)
        record(self, "SetBitten", flag)
        self.isBitten = flag == true
    end
    -- Signature verified against the pinned JAR:
    -- setScratched(scratched, forceNoInfection). When the second argument is
    -- false the engine rolls generateZombieInfection(7), so the fixture models
    -- that roll being *reachable* rather than its randomness.
    function value:setScratched(flag, forceNoInfection)
        record(self, "setScratched", flag, forceNoInfection)
        self.isScratched = flag == true
        self.infectionRollReachable = forceNoInfection ~= true
    end
    function value:setCut(flag)
        record(self, "setCut", flag)
        self.cut = flag == true
    end
    function value:setDeepWounded(flag)
        record(self, "setDeepWounded", flag)
        self.deep = flag == true
    end
    function value:getWoundInfectionLevel() return self.woundInfectionLevel end
    function value:setWoundInfectionLevel(level)
        record(self, "setWoundInfectionLevel", level)
        self.woundInfectionLevel = level
    end
    return value
end

local function bodyDamage(health, parts)
    local value = { health = health or 100, parts = parts or {} }
    function value:getHealth() return self.health end
    function value:getBodyParts() return self.parts end
    function value:IsInfected() return self.infected == true end
    -- max(ZOMBIE_FEVER, ZOMBIE_INFECTION, FOOD_SICKNESS) in Build 42, so this is
    -- deliberately allowed to read high with no zombie infection at all.
    function value:getApparentInfectionLevel() return self.infectionLevel or 0 end
    function value:getInfectionTime() return self.infectionTime or -1 end
    function value:getInfectionMortalityDuration() return self.infectionMortality or -1 end
    function value:SetBandaged(index, enabled, life, alcoholic, itemType)
        if self.rejectBandage then return false end
        local part = self.parts[index + 1]
        if part then
            part.isBandaged = enabled
            part.dirty = enabled and (life or 0) <= 0 or false
            part.bandageLife = life
            part.bandageAlcoholic = alcoholic
            part.bandageType = itemType
        end
    end
    return value
end

local squares = {}
local cell
local function squareKey(x, y, z) return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0) end
local function makeSquare(x, y, z)
    local value = { x = x, y = y, z = z or 0, moving = {}, staticMoving = {},
        objects = {}, specialObjects = {}, worldItems = {}, blocked = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:isFree() return not self.solid end
    function value:isSolid() return self.solid == true end
    function value:isSolidTrans() return self.solidTrans == true end
    function value:TreatAsSolidFloor() return self.hasFloor ~= false end
    function value:isSafeToSpawn() return self.spawnUnsafe ~= true end
    function value:getChunk() return self.chunk or {} end
    function value:getCell() return cell end
    function value:getMovingObjects() return self.moving end
    function value:getStaticMovingObjects() return self.staticMoving end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.specialObjects end
    function value:getWorldObjects() return self.worldItems end
    function value:getVehicleContainer() return self.vehicleContainer end
    function value:getFire() return self.fire end
    function value:getBrokenGlass() return self.brokenGlass end
    function value:getSheetRope() return self.sheetRope end
    function value:hasSlopedSurface() return self.sloped == true end
    function value:has(flag)
        local key = type(flag) == "table" and flag.name or tostring(flag)
        return self.flags and self.flags[key] == true or false
    end
    function value:AddWorldInventoryItem(added, xOffset, yOffset, zOffset, transmit)
        if type(added) ~= "table" then added = item(added, "Item") end
        local worldItem = { item = added, square = self, xOffset = xOffset, yOffset = yOffset,
            zOffset = zOffset }
        function worldItem:getItem() return self.item end
        function worldItem:getSquare() return self.square end
        function worldItem:setSquare(target) self.square = target end
        function worldItem:removeFromWorld() self.removedFromWorld = true end
        function worldItem:removeFromSquare()
            if not self.square then return end
            for index, candidate in ipairs(self.square.worldItems) do
                if candidate == self then table.remove(self.square.worldItems, index) break end
            end
            self.square = nil
        end
        self.worldItems[#self.worldItems + 1] = worldItem
        added.worldItem = worldItem
        return added
    end
    function value:isBlockedTo(other) return self.blocked[other] == true end
    function value:isDoorTo(other) return false end
    function value:getDoorTo(other) return nil end
    function value:isWindowTo(other) return false end
    function value:getWindowTo(other) return nil end
    function value:getWindowThumpableTo(other) return nil end
    function value:getWindowFrameTo(other) return nil end
    function value:isHoppableTo(other) return false end
    function value:getHoppableThumpableTo(other) return nil end
    function value:getHoppableTo(other) return nil end
    function value:getWallHoppableTo(other) return nil end
    function value:getDoor(north) return nil end
    function value:getWindow(north) return nil end
    function value:getRoom() return self.room end
    function value:isOutside() return self.outside ~= false end
    function value:getLightLevel(_) return self.lightLevel or 0 end
    function value:HasTree() return self.hasTree == true end
    function value:hasBush() return self.engineBush == true end
    function value:getProperties() return self.properties end
    squares[squareKey(x, y, z or 0)] = value
    return value
end

for x = -8, 12 do
    for y = -8, 8 do makeSquare(x, y, 0) end
end

cell = {}
function cell:getGridSquare(x, y, z)
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local key = squareKey(x, y, z)
    local value = squares[key]
    if not value and math.abs(z) <= 1 and math.abs(x) <= 55 and math.abs(y) <= 55 then
        value = makeSquare(x, y, z)
        if math.abs(x) > 15 or math.abs(y) > 15 then
            value.hidden = true
            if (math.abs(x) + math.abs(y)) % 5 == 0 then value.room = { name = "room" } end
        end
    end
    return value
end
function getCell() return cell end

LosUtil = {}
function LosUtil.lineClear(isoCell, ox, oy, oz, tx, ty, tz, ignoreDoors)
    if math.floor(oz) ~= math.floor(tz) then return "Blocked" end
    local target = isoCell:getGridSquare(tx, ty, tz)
    if not target or target.losBlocked or target.hidden then return "Blocked" end
    if target.losResult then return target.losResult end
    return "Clear"
end

-- Squares beyond 15 tiles start hidden, the fixture's unseen ground, and this
-- LosUtil stub reports Blocked for them. Melee scenes placed out there for
-- isolation mean open ground: strike clearance checks the same line.
function LosUtil.openGround(x, y, radius)
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = cell:getGridSquare(x + dx, y + dy, 0)
            if square then square.hidden = false end
        end
    end
end

local function actor(id, x, y, options)
    local settings = options or {}
    local z = settings.z or 0
    local value = {
        __class = settings.className or "IsoSurvivor",
        id = id,
        square = cell:getGridSquare(x, y, z),
        inventory = settings.inventory or inventory(),
        body = settings.body or bodyDamage(100),
        modData = { SC_Id = id, SC_Recruited = settings.recruited ~= false },
        dead = false,
        forwardX = settings.forwardX or 0,
        forwardY = settings.forwardY or -1,
        moving = settings.moving == true,
        humanVisual = settings.humanVisual,
    }
    function value:getX() return self.worldX or (self.square.x + 0.5) end
    function value:getY() return self.worldY or (self.square.y + 0.5) end
    function value:getZ() return self.square.z end
    function value:getSquare() return self.square end
    function value:getCurrentSquare() return self.square end
    function value:getInventory() return self.inventory end
    function value:getMaxWeight() return self.inventory.capacity end
    function value:getBodyDamage() return self.body end
    function value:getHoursSurvived() return self.hoursSurvived or -1 end
    function value:getModData() return self.modDataProxy or self.modData end
    function value:isDead() return self.dead end
    function value:getHealth() return self.body.health end
    function value:getPrimaryHandItem() return self.primary end
    function value:getSecondaryHandItem() return self.secondary end
    function value:setPrimaryHandItem(held) self.primary = held end
    function value:setSecondaryHandItem(held)
        if self.rejectOffHand then return end
        self.secondary = held
    end
    function value:getVehicle() return self.vehicle end
    function value:isCollidedWithVehicle() return self.collidedVehicle == true end
    function value:isCollidedWithDoor() return self.collidedDoor == true end
    function value:isCollidedThisFrame() return self.collidedThisFrame == true end
    function value:getCollidedObject() return self.collidedObject end
    function value:isKnockedDown() return self.knockedDown == true end
    function value:setFallOnFront(enabled) self.fallOnFront = enabled == true end
    function value:setKnockedDown(enabled) self.knockedDown = enabled == true end
    function value:setDeathDragDown(enabled) self.deathDragDown = enabled == true end
    function value:calculateGrappleEffectivenessFromTraits()
        return settings.grappleEffectiveness or 0.5
    end
    function value:getSurroundingAttackingZombies()
        return settings.surroundingAttackers or 0
    end
    function value:isClimbing() return self.climbing == true end
    function value:climbOverFence(direction)
        self.climbing = true
        self.climbDirection = direction
        self.climbKind = "fence"
    end
    function value:hopFence(direction, testOnly)
        if testOnly == true then return self.rejectFenceClimb ~= true end
        if self.rejectFenceClimb then return false end
        self.climbing = true
        self.climbDirection = direction
        self.climbKind = "fence"
        return true
    end
    function value:triggerContextualAction(action, object)
        self.contextualAction, self.contextualObject = action, object
        self.climbing = true
        self.climbKind = "contextual"
        return true
    end
    function value:canClimbOverWall(direction)
        return self.rejectWallClimb ~= true
    end
    function value:climbOverWall(direction)
        if self.rejectWallClimb then return false end
        self.climbing = true
        self.climbDirection = direction
        self.climbKind = "wall"
        return true
    end
    function value:canClimbSheetRope(square)
        return square == self.square and self.rejectSheetRopeClimb ~= true
    end
    function value:canClimbDownSheetRope(square)
        return square == self.square and self.rejectSheetRopeDescent ~= true
    end
    function value:climbSheetRope()
        self.climbing = true
        self.climbKind = "sheet_rope_up"
    end
    function value:climbDownSheetRope()
        self.climbing = true
        self.climbKind = "sheet_rope_down"
    end
    function value:isClimbingRope() return self.climbing == true end
    function value:cancelCompanionStuckClimb()
        if self.rejectClimbCancel then return false end
        self.climbing = false
        if type(self.currentState) == "string"
            and string.find(string.lower(self.currentState), "climb", 1, true) then
            self.currentState = nil
        end
        return true
    end
    function value:isBlockMovement() return self.blockMovement == true end
    function value:getCurrentState() return self.currentState end
    function value:getForwardDirectionX() return self.forwardX end
    function value:getForwardDirectionY() return self.forwardY end
    function value:isMoving() return self.moving == true end
    function value:isAsleep() return self.asleep == true end
    function value:isRunning() return self.running == true end
    function value:isSprinting() return self.sprinting == true end
    function value:isSneaking() return self.sneaking == true end
    function value:setRunning(enabled) self.running = enabled == true end
    function value:setSprinting(enabled) self.sprinting = enabled == true end
    function value:setSneaking(enabled) self.sneaking = enabled == true end
    function value:isAiming() return self.aiming == true end
    function value:CanSee(target)
        local targetSquare = target and target.getSquare and target:getSquare() or nil
        return targetSquare ~= nil and targetSquare.z == self.square.z and targetSquare.losBlocked ~= true
    end
    function value:openWindow(window) if not self.noopOpenWindow then window.open = true end end
    function value:smashWindow(window) if not self.noopSmashWindow then window.smashed = true end end
    function value:getDisplayName() return self.id end
    function value:getStats()
        local owner = self
        return {
            get = function(_, stat)
                if stat == CharacterStat.HUNGER then return owner.hunger or 0 end
                if stat == CharacterStat.THIRST then return owner.thirst or 0 end
                if stat == CharacterStat.FATIGUE then return owner.fatigue or 0 end
                if stat == CharacterStat.ENDURANCE then return owner.endurance or 1 end
                if stat == CharacterStat.STRESS then return owner.nativeStress or 0 end
                if stat == CharacterStat.WETNESS then return owner.wetness or 0 end
                if stat == CharacterStat.NICOTINE_WITHDRAWAL then
                    return owner.nicotineWithdrawal or 0
                end
                return 0
            end,
            getNicotineStress = function()
                return math.min(1, (owner.nativeStress or 0)
                    + (owner.nicotineWithdrawal or 0))
            end,
            set = function(_, stat, amount)
                if stat == CharacterStat.HUNGER then owner.hunger = amount return true end
                if stat == CharacterStat.THIRST then owner.thirst = amount return true end
                if stat == CharacterStat.FATIGUE then owner.fatigue = amount return true end
                if stat == CharacterStat.ENDURANCE then owner.endurance = amount return true end
                if stat == CharacterStat.STRESS then owner.nativeStress = amount return true end
                return false
            end,
        }
    end
    function value:hasTrait(nativeTrait)
        return type(self.traits) == "table" and self.traits[nativeTrait] == true
    end
    function value:getPerkLevel(perk)
        if self.perks and self.perks[perk] ~= nil then return self.perks[perk] end
        if perk == Perks.Strength or perk == Perks.Fitness then return 5 end
        return 0
    end
    function value:getMoodles()
        local owner = self
        return {
            getMoodleLevel = function(_, moodle)
                return owner.moodles and owner.moodles[moodle] or 0
            end,
        }
    end
    function value:isEquippedClothing(candidate)
        return self.equippedClothing and self.equippedClothing[candidate] == true or false
    end
    function value:getWornItems()
        local owner = self
        local function activeEntries()
            local entries = {}
            for _, candidate in ipairs(owner.wornOrder or {}) do
                if owner.equippedClothing and owner.equippedClothing[candidate] == true then
                    entries[#entries + 1] = {
                        item = candidate,
                        location = owner.wornLocations and owner.wornLocations[candidate] or nil,
                    }
                end
            end
            return entries
        end
        return {
            contains = function(_, candidate)
                return owner.equippedClothing and owner.equippedClothing[candidate] == true or false
            end,
            size = function() return #activeEntries() end,
            get = function(_, index)
                local entry = activeEntries()[(tonumber(index) or -1) + 1]
                if not entry then return nil end
                return {
                    getItem = function() return entry.item end,
                    getLocation = function() return entry.location end,
                }
            end,
            getBodyLocationGroup = function()
                return {
                    isExclusive = function(_, first, second)
                        local exclusions = owner.exclusiveLocations or {}
                        return exclusions[tostring(first) .. ":" .. tostring(second)] == true
                            or exclusions[tostring(second) .. ":" .. tostring(first)] == true
                    end,
                }
            end,
        }
    end
    function value:getWornItem(location)
        return self.wornByLocation and self.wornByLocation[tostring(location)] or nil
    end
    function value:removeWornItem(candidate, resetModel)
        if self.rejectUnequip then return false end
        self.equippedClothing = self.equippedClothing or {}
        self.equippedClothing[candidate] = nil
        local location = self.wornLocations and self.wornLocations[candidate] or nil
        if location ~= nil and self.wornByLocation
            and self.wornByLocation[tostring(location)] == candidate then
            self.wornByLocation[tostring(location)] = nil
        end
        if self.wornLocations then self.wornLocations[candidate] = nil end
        for index = #(self.wornOrder or {}), 1, -1 do
            if self.wornOrder[index] == candidate then table.remove(self.wornOrder, index) end
        end
    end
    function value:setWornItem(location, candidate)
        if self.rejectWear then return false end
        self.equippedClothing = self.equippedClothing or {}
        self.wornLocations = self.wornLocations or {}
        self.wornByLocation = self.wornByLocation or {}
        self.wornOrder = self.wornOrder or {}
        local key = tostring(location)
        local previous = self.wornByLocation[key]
        if previous and previous ~= candidate then self:removeWornItem(previous, false) end
        local previousLocation = self.wornLocations[candidate]
        if previousLocation ~= nil then self.wornByLocation[tostring(previousLocation)] = nil end
        self.equippedClothing[candidate] = true
        self.wornLocations[candidate] = location
        self.wornByLocation[key] = candidate
        local known = false
        for _, worn in ipairs(self.wornOrder) do
            if worn == candidate then known = true break end
        end
        if not known then self.wornOrder[#self.wornOrder + 1] = candidate end
    end
    function value:getHumanVisual() return self.humanVisual end
    function value:resetModelNextFrame() self.modelReset = true end
    function value:addLineChatElement(text)
        self.lastSpeech = text
        self.speechMethod = "actor_chat"
        self.speechCalls = (self.speechCalls or 0) + 1
    end
    function value:setCompanionSpeechDisplayMillis(milliseconds)
        self.speechDisplayMillis = milliseconds
        return true
    end
    function value:Say(text)
        self.lastSpeech = text
        self.speechMethod = "player_chat_fallback"
        self.speechCalls = (self.speechCalls or 0) + 1
    end
    function value:playEmote(emote) self.lastEmote = emote return true end
    value.square.moving[#value.square.moving + 1] = value
    return value
end

local function zombie(x, y, options)
    local settings = options or {}
    local z = settings.z or 0
    local value = {
        __class = "IsoZombie",
        square = cell:getGridSquare(x, y, z),
        onFloor = settings.onFloor == true,
        moving = settings.moving == true,
        dead = false,
        target = settings.target,
        attackedBy = settings.attackedBy,
        modData = {},
    }
    function value:getX() return self.square.x + 0.5 end
    function value:getY() return self.square.y + 0.5 end
    function value:getZ() return self.square.z end
    function value:getSquare() return self.square end
    function value:getCurrentSquare() return self.square end
    function value:isZombie() return true end
    function value:isDead() return self.dead end
    function value:isOnFloor() return self.onFloor end
    function value:isProne() return self.onFloor end
    function value:isMoving() return self.moving == true end
    value.attacking = settings.attacking == true
    function value:isAttacking() return self.attacking == true end
    function value:isZombieAttacking(target)
        if target ~= nil and target ~= self.target then return false end
        return self.attacking == true
    end
    function value:getTarget() return self.target end
    function value:getAttackedBy() return self.attackedBy end
    function value:getModData() return self.modData end
    function value:hasModData() return next(self.modData) ~= nil end
    function value:getTargetSeenTime() return self.targetSeenTimeSet or 0 end
    function value:setTargetSeenTime(seconds)
        self.targetSeenTimeSet = seconds
        self.targetSeenCalls = (self.targetSeenCalls or 0) + 1
    end
    function value:getAttackOutcome() return self.attackOutcome end
    function value:getAttackDidDamage() return self.attackDidDamage == true end
    -- Build 42 clears AttackDidDamage on AttackState.enter and writes it only
    -- from the collision handler, so presence -- not truth -- is the receipt
    -- that victim processing ran. ZombieBiteDone is set at the clip's end.
    value.animVariables = {}
    function value:getVariableString(name)
        local held = self.animVariables[name]
        return held == nil and "" or tostring(held)
    end
    function value:getVariableBoolean(name) return self.animVariables[name] == true end
    function value:setVariable(name, held) self.animVariables[name] = held end
    function value:clearVariable(name) self.animVariables[name] = nil end
    -- Drive one whole native episode the way AttackState does, so a fixture
    -- cannot accidentally assert on a half-formed one.
    function value:beginAttackEpisode()
        self.attackOutcome = "start"
        self.attackDidDamage = false
        self.animVariables.AttackDidDamage = nil
        self.animVariables.ZombieBiteDone = nil
        self.attacking = true
        self.currentState = "AttackState"
    end
    function value:swingOutcome(outcome) self.attackOutcome = outcome end
    function value:reportVictimProcessed(damaged)
        self.animVariables.AttackDidDamage = damaged and "true" or "false"
        self.attackDidDamage = damaged == true
    end
    function value:finishBiteClip() self.animVariables.ZombieBiteDone = true end
    function value:getCurrentState()
        return self.currentState or (self.attacking and "AttackState" or "ZombieIdleState")
    end
    function value:pathToCharacter(target)
        self.pathToCharacterCalls = (self.pathToCharacterCalls or 0) + 1
        self.pathTarget = target
        self.moving = true
    end
    value.attackOutcome = settings.attackOutcome
    value.attackDidDamage = settings.attackDidDamage == true
    function value:getSurroundingAttackingZombies() return 0 end
    function value:isUseless() return false end
    function value:spotted(target, forced)
        self.spottedCalls = (self.spottedCalls or 0) + 1
        self.lastSpottedForced = forced == true
        if forced or settings.spotRejected ~= true then self.target = target end
    end
    value.square.moving[#value.square.moving + 1] = value
    return value
end

local movementLog = {}
SurvivorCompanion.Actor = {
    isCompanion = function(value) return value and value.modData and value.modData.SC_Recruited == true end,
    setMovement = function(value, mode, intent)
        value.movementCalls = (value.movementCalls or 0) + 1
        local rejected = value.rejectMovement == true
            or (value.rejectActions and value.rejectActions[intent and intent.action] == true)
            or (value.rejectMovementNth and value.movementCalls == value.rejectMovementNth)
        movementLog[#movementLog + 1] = { actor = value, mode = mode, intent = intent, accepted = not rejected }
        if rejected then return false end
        value.lastIntent = intent
        if intent and intent.action == "equip_weapon" and intent.item ~= nil then
            value.primary = intent.item
            if intent.item.isTwoHandWeapon and intent.item:isTwoHandWeapon() then
                value.secondary = intent.item
            elseif value.secondary == intent.item then
                value.secondary = nil
            end
        end
        return true
    end,
    stop = function(value)
        if value.rejectStop then return false end
        value.stopped = true
        return true
    end,
    remove = function(value)
        if value.rejectRemoveActor then return false end
        value.removed = true
        return true
    end,
}

local registry = {}
SurvivorCompanion.Registry = {
    byId = function(id) return registry[id] end,
    idOf = function(candidate)
        if not candidate then return nil end
        local id = candidate.id
        if id and registry[id] ~= nil then return id end
        for key, value in pairs(registry) do
            if value == candidate or type(value) == "table" and value.actor == candidate then
                return key
            end
        end
        return nil
    end,
    isActive = function(candidate, id)
        local value = registry[id]
        return value == candidate or type(value) == "table" and value.actor == candidate
    end,
    isValidId = function(id)
        return type(id) == "string" and #id >= 3 and #id <= 96
    end,
    living = function()
        local result = {}
        -- Match production SCRegistry.living(): callers receive active, living
        -- actors rather than the registry records stored by this fixture.
        for _, value in pairs(registry) do
            local candidate = type(value) == "table" and value.actor or nil
            if candidate == nil and type(value) == "table"
                and type(value.isDead) == "function" then candidate = value end
            local inactive = type(value) == "table" and type(value.runtime) == "table"
                and value.runtime.inactive == true
            if candidate and not inactive and candidate:isDead() ~= true then
                result[#result + 1] = candidate
            end
        end
        return result
    end,
}

SurvivorCompanion.Config._canonicalTestGet = SurvivorCompanion.Config.get
SurvivorCompanion.Config.values = setmetatable({
        perceptionRadius = 8,
        perceptionSquareBudget = 160,
        perceptionThreatLimit = 12,
        perceptionIntervalMs = 1,
        performancePerceptionUnitsPerFrame = 48,
        performanceNavigationNodesPerFrame = 16,
        performanceScavengeSquaresPerFrame = 12,
        performanceScavengeContainersPerFrame = 1,
        performanceFactionSamplesPerFrame = 8,
        performanceUrgentUnitFloor = 24,
        performanceCacheTtlMs = 75,
        navigationNodeBudget = 100,
        navigationStuckMs = 5000,
        navigationObstacleStuckMs = 900,
        navigationRecoveryAttempts = 2,
        navigationTerminalRetryMs = 8000,
        navigationBushPenalty = 5.5,
        navigationTreePenalty = 12,
        navigationTreeClearancePenalty = 4,
        navigationEmergencyVegetationScale = 0.2,
        navigationWeaponReadyHoldMs = 1200,
        medicalRange = 1.5,
        medicalApproachTimeoutMs = 8000,
        encounterIntervalMs = 1,
        scavengeRadius = 6,
        scavengeSquareBudget = 70,
        scavengeSettleMs = 0,
        scavengeNoUsefulCooldownMs = 30000,
        scavengeSuccessCooldownMs = 4000,
        scavengeStatusHoldMs = 8000,
        scavengeMemoryLimit = 96,
        downtimeSafeMs = 0,
        downtimeActivityMs = 0,
        downtimeIntervalMs = 0,
        decisionMinStateMs = 0,
        movementRecorderEnabled = true,
        maxCompanions = 64,
    }, { __index = SurvivorCompanion.Config.defaults })
SurvivorCompanion.Config.get = function(section, key)
    local config = SurvivorCompanion.Config
    if key == nil then
        local override = rawget(config.values, section)
        if override ~= nil then return override end
    end
    return config._canonicalTestGet(section, key)
end

SurvivorCompanion.UI = {
    showStatus = function(summary) SurvivorCompanion.UI.lastStatus = summary return true end,
    openInventory = function() return SurvivorCompanion.UI.inventoryResult == true end,
    openHealth = function() return SurvivorCompanion.UI.healthResult == true end,
}

local function containerObject(square, contents, options)
    options = options or {}
    local container = inventory(contents)
    function container:getParent() return self.owner end
    function container:getType() return options.containerType or "counter" end
    local owner = { square = square, modData = {} }
    function owner:getSquare() return self.square end
    function owner:getX() return self.square.x end
    function owner:getY() return self.square.y end
    function owner:getZ() return self.square.z end
    function owner:getModData() return self.modData end
    function owner:getContainer() return container end
    container.owner = owner
    square.objects[#square.objects + 1] = owner
    return container, owner
end

local player = actor("player", 0, 1, { className = "IsoPlayer", recruited = false })
player.modData.SC_Recruited = false
local fixture = {
    check = check, item = item, inventory = inventory, buildKit = buildKit,
    bodyPart = bodyPart, bodyDamage = bodyDamage, actor = actor, zombie = zombie,
    cell = cell, squares = squares, makeSquare = makeSquare, squareKey = squareKey, registry = registry,
    movementLog = movementLog, player = player, containerObject = containerObject,
    checks = function() return checks end,
}
setmetatable(fixture, {
    __index = function(_, key)
        if key == "clock" then return SC_TEST_CLOCK end
        if key == "worldHour" then return worldHour end
        if key == "rainIntensity" then return rainIntensity end
        if key == "fogIntensity" then return fogIntensity end
        if key == "daylightStrength" then return daylightStrength end
        if key == "worldSoundCount" then return worldSoundCount end
        if key == "uiSounds" then return uiSounds end
    end,
    __newindex = function(self, key, value)
        if key == "clock" then SC_TEST_CLOCK = value
        elseif key == "worldHour" then worldHour = value
        elseif key == "rainIntensity" then rainIntensity = value
        elseif key == "fogIntensity" then fogIntensity = value
        elseif key == "daylightStrength" then daylightStrength = value
        elseif key == "worldSoundCount" then worldSoundCount = value
        elseif key == "uiSounds" then uiSounds = value
        else rawset(self, key, value) end
    end,
})
SurvivorCompanion.TestFixture = fixture
