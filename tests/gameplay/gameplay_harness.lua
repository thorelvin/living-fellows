-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local clock = 100000
function getTimestampMs() return clock end
local worldHour = 12
function getGameTime()
    return {
        getHour = function() return worldHour end,
        getTimeOfDay = function() return worldHour end,
        getWorldAgeHours = function() return 240 + clock / 3600000 end,
    }
end
local worldSoundCount = 0
function addSound(source, x, y, z, radius, volume) worldSoundCount = worldSoundCount + 1 end
function instanceof(value, className)
    return type(value) == "table" and (value.__class == className or value.className == className)
end

CharacterStat = {
    HUNGER = { name = "HUNGER" },
    THIRST = { name = "THIRST" },
    ENDURANCE = { name = "ENDURANCE" },
    STRESS = { name = "STRESS" },
}
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
IsoFlagType = { canBeCut = { name = "canBeCut" } }

local function item(itemType, category, options)
    local value = options or {}
    value.__class = value.__class or (category == "Weapon" and "HandWeapon" or "InventoryItem")
    value.itemType = itemType
    value.category = category or "Item"
    if value.uses == nil then value.uses = 1 end
    function value:getFullType() return self.itemType end
    function value:getType() return string.gsub(self.itemType, "Base%.", "") end
    function value:getDisplayName() return self.itemType end
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
    function value:getSwingTime() return self.swing or 1 end
    function value:getEnduranceMod() return self.enduranceMod or 1 end
    function value:getSharpness() return self.sharpness == nil and 1 or self.sharpness end
    function value:isTwoHandWeapon() return self.twoHanded == true end
    function value:getCategories() return self.weaponCategories or {} end
    function value:isRanged() return self.ranged == true end
    function value:getCurrentAmmoCount() return self.ammo or 0 end
    function value:getMaxAmmo() return self.maxAmmo or 0 end
    function value:getAmmoType() return self.ammoType end
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
    function value:getActualWeight() return self.weight or 1 end
    function value:getWeight() return self.weight or 1 end
    function value:getHungerChange() return self.hungerChange or 0 end
    function value:getHungChange() return self.hungerChange or 0 end
    function value:getBaseHunger() return self.baseHunger or self.hungerChange or 0 end
    function value:isRotten() return self.rotten == true end
    function value:isBurnt() return self.burnt == true end
    function value:isbDangerousUncooked() return self.dangerousUncooked == true end
    function value:isCooked() return self.cooked == true end
    function value:getPoisonPower() return self.poisonPower or 0 end
    function value:getScriptItem()
        return { isCantEat = function() return value.cantEat == true end }
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
        if self.rejectAdd or self.rejectAddType == addedType then return nil end
        if type(added) ~= "table" then added = item(added, "Item") end
        self.items[#self.items + 1] = added
        added.container = self
        return added
    end
    function value:Remove(removed)
        self.removeCalls = (self.removeCalls or 0) + 1
        if self.rejectRemove or self.rejectRemoveItem == removed
            or (self.rejectRemoveNth and self.removeCalls == self.rejectRemoveNth) then return false end
        for index, candidate in ipairs(self.items) do
            if candidate == removed then table.remove(self.items, index) candidate.container = nil return end
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
    function value:getEffectiveCapacity(character) return self.capacity end
    function value:getMaxWeight() return self.capacity end
    function value:getCapacity() return self.capacity end
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
    return value
end

local function bodyDamage(health, parts)
    local value = { health = health or 100, parts = parts or {} }
    function value:getHealth() return self.health end
    function value:getBodyParts() return self.parts end
    function value:IsInfected() return self.infected == true end
    function value:getApparentInfectionLevel() return self.infectionLevel or 0 end
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
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    function value:isSafeToSpawn() return self.spawnUnsafe ~= true end
    function value:getChunk() return self.chunk or {} end
    function value:getCell() return cell end
    function value:getMovingObjects() return self.moving end
    function value:getStaticMovingObjects() return self.staticMoving end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.specialObjects end
    function value:AddWorldInventoryItem(added, xOffset, yOffset, zOffset, transmit)
        local worldItem = { item = added, square = self, xOffset = xOffset, yOffset = yOffset,
            zOffset = zOffset }
        self.worldItems[#self.worldItems + 1] = worldItem
        return worldItem
    end
    function value:isBlockedTo(other) return self.blocked[other] == true end
    function value:isDoorTo(other) return false end
    function value:isWindowTo(other) return false end
    function value:isHoppableTo(other) return false end
    function value:getDoor(north) return nil end
    function value:getWindow(north) return nil end
    function value:getRoom() return self.room end
    function value:HasTree() return self.hasTree == true end
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
    function value:getModData() return self.modDataProxy or self.modData end
    function value:isDead() return self.dead end
    function value:getHealth() return self.body.health end
    function value:getPrimaryHandItem() return self.primary end
    function value:getSecondaryHandItem() return self.secondary end
    function value:getVehicle() return self.vehicle end
    function value:isCollidedWithVehicle() return self.collidedVehicle == true end
    function value:isCollidedWithDoor() return self.collidedDoor == true end
    function value:isCollidedThisFrame() return self.collidedThisFrame == true end
    function value:getCollidedObject() return self.collidedObject end
    function value:isKnockedDown() return self.knockedDown == true end
    function value:isClimbing() return self.climbing == true end
    function value:isBlockMovement() return self.blockMovement == true end
    function value:getCurrentState() return self.currentState end
    function value:getForwardDirectionX() return self.forwardX end
    function value:getForwardDirectionY() return self.forwardY end
    function value:isMoving() return self.moving == true end
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
                if stat == CharacterStat.ENDURANCE then return owner.endurance or 1 end
                if stat == CharacterStat.STRESS then return owner.nativeStress or 0 end
                return 0
            end,
            set = function(_, stat, amount)
                if stat == CharacterStat.HUNGER then owner.hunger = amount return true end
                if stat == CharacterStat.THIRST then owner.thirst = amount return true end
                if stat == CharacterStat.ENDURANCE then owner.endurance = amount return true end
                if stat == CharacterStat.STRESS then owner.nativeStress = amount return true end
                return false
            end,
        }
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
    end
    function value:setCompanionSpeechDisplayMillis(milliseconds)
        self.speechDisplayMillis = milliseconds
        return true
    end
    function value:Say(text)
        self.lastSpeech = text
        self.speechMethod = "player_chat_fallback"
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
        dead = false,
        target = settings.target,
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
    function value:isAttacking() return settings.attacking == true end
    function value:getTarget() return self.target end
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
    isValidId = function(id)
        return type(id) == "string" and #id >= 3 and #id <= 96
    end,
    living = function()
        local result = {}
        for _, value in pairs(registry) do result[#result + 1] = value end
        return result
    end,
}

SurvivorCompanion.Config = {
    values = {
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
    },
    get = function(key) return SurvivorCompanion.Config.values[key] end,
}

SurvivorCompanion.UI = {
    showStatus = function(summary) SurvivorCompanion.UI.lastStatus = summary return true end,
    openInventory = function() return SurvivorCompanion.UI.inventoryResult == true end,
    openHealth = function() return SurvivorCompanion.UI.healthResult == true end,
}

local helperBandage = item("Base.AlcoholBandage", "Medical", { alcoholic = true, bandagePower = 14 })
local bat = item("Base.BaseballBat", "Weapon", { damage = 1.4, range = 1.5, condition = 8, conditionMax = 10 })
local fellow = actor("sc-fellow", 0, 0, { inventory = inventory({ helperBandage, bat }) })
fellow.primary = bat
registry[fellow.id] = fellow
local woundedPart = bodyPart({ name = "ForeArm_L", isBleeding = true, isScratched = true })
local player = actor("player", 0, 1, { className = "IsoPlayer", recruited = false, body = bodyDamage(42, { woundedPart }) })
player.modData.SC_Recruited = false

do
    local Targeting = SurvivorCompanion.ZombieTargeting
    local closeCompanion = actor("sc-zombie-target-close", 3, 0, {})
    local closeZombie = zombie(4, 0, {})
    local scanned, scanReason, scanDetail = Targeting.scan(
        closeCompanion, clock, { closeZombie })
    check(scanned and scanReason == "zombies_targeted_companion"
            and scanDetail.checked == 1 and scanDetail.targeted == 1
            and closeZombie:getTarget() == closeCompanion
            and closeZombie.spottedCalls == 1 and closeZombie.lastSpottedForced == true,
        "a nearby zombie runs its native spotted contract against a visible companion")

    local normalCompanion = actor("sc-zombie-target-normal", 8, 0, {})
    local normalZombie = zombie(3, 0, {})
    local normalAccepted, normalReason = Targeting.consider(normalZombie, normalCompanion)
    check(normalAccepted and normalReason == "companion_spotted"
            and normalZombie:getTarget() == normalCompanion
            and normalZombie.lastSpottedForced == false,
        "normal-range targeting preserves the zombie's ordinary sight calculation")

    local closerPlayer = actor("targeting-player", 1, 3,
        { className = "IsoPlayer", recruited = false })
    closerPlayer.modData.SC_Recruited = false
    local distantCompanion = actor("sc-zombie-target-distant", 7, 3, {})
    local occupiedZombie = zombie(0, 3, { target = closerPlayer })
    local challenged, challengeReason = Targeting.consider(occupiedZombie, distantCompanion)
    check(not challenged and challengeReason == "closer_target_retained"
            and occupiedZombie:getTarget() == closerPlayer
            and occupiedZombie.spottedCalls == nil,
        "companion targeting never steals a zombie from a materially closer player")

    local blockedCompanion = actor("sc-zombie-target-blocked", 8, 4, {})
    local blockedZombie = zombie(3, 4, {})
    blockedCompanion.square.losBlocked = true
    local blocked, blockedReason = Targeting.consider(blockedZombie, blockedCompanion)
    blockedCompanion.square.losBlocked = false
    check(not blocked and blockedReason == "line_of_sight_blocked"
            and blockedZombie:getTarget() == nil and blockedZombie.spottedCalls == nil,
        "walls still prevent a zombie from acquiring a companion through the adapter")

    closeZombie.dead = true
    normalZombie.dead = true
    occupiedZombie.dead = true
    blockedZombie.dead = true
    Targeting.reset()
end

do
    local neutralRestore = actor("sc-neutral-restore", -8, -8, { recruited = true })
    local neutralRecord = {
        id = neutralRestore.id,
        recruited = false,
        order = "wander",
        scavenge = false,
        state = { order = { current = "wander", scavenge = false } },
    }
    check(SurvivorCompanion.Commands.restore(neutralRestore, neutralRecord),
        "neutral encounter command state restores")
    local neutralState = SurvivorCompanion.Commands.peek(neutralRestore)
    check(neutralState.recruited == false and neutralState.order == "wander"
            and neutralState.scavenge == false and neutralRestore.modData.SC_Recruited == false,
        "explicit neutral registry state overrides actor ownership metadata")

    local recruitedRestore = actor("sc-recruited-restore", -9, -8, { recruited = false })
    local recruitedRecord = {
        id = recruitedRestore.id,
        recruited = true,
        order = "follow",
        state = { order = { current = "follow", scavenge = true } },
    }
    check(SurvivorCompanion.Commands.restore(recruitedRestore, recruitedRecord)
            and SurvivorCompanion.Commands.peek(recruitedRestore).recruited == true
            and SurvivorCompanion.Commands.peek(recruitedRestore).rideWithPlayer == true
            and recruitedRestore.modData.SC_Recruited == true,
        "explicit recruited save state remains authoritative and old saves default Ride with player on")
end

local zed = zombie(1, 0, { attacking = true, target = fellow })

local defaultsChanged = pcall(function() SurvivorCompanion.GameplayUtil.Defaults.perceptionRadius = 999 end)
check(not defaultsChanged, "gameplay defaults must be immutable")

do
    local explicitNilCount = -1
    local explicitNilResult, explicitNilCalled = SurvivorCompanion.GameplayUtil.call({
        acceptNil = function(self, ...)
            explicitNilCount = select("#", ...)
            return explicitNilCount == 1 and select(1, ...) == nil
        end,
    }, "acceptNil", nil)
    check(explicitNilCalled and explicitNilResult == true and explicitNilCount == 1,
        "Java-call wrapper must preserve one explicit nil argument")
    check(not SurvivorCompanion.GameplayUtil.say(player, "wrong actor") and player.lastSpeech == nil,
        "speech executor must reject the local player")
    check(SurvivorCompanion.GameplayUtil.say(fellow, "companion actor")
            and fellow.lastSpeech == "companion actor" and fellow.speechMethod == "actor_chat"
            and fellow.speechDisplayMillis >= 8000 and fellow.speechDisplayMillis <= 15000,
        "speech executor anchors chat to the companion and requests a readable display duration")
    local strictSquare = cell:getGridSquare(4, 4, 0)
    check(SurvivorCompanion.GameplayUtil.isSafeSpawnSquare(strictSquare),
        "native spawn-square helper accepts a fully loaded unobstructed square")
    strictSquare.spawnUnsafe = true
    local strictSafe, strictReason = SurvivorCompanion.GameplayUtil.isSafeSpawnSquare(strictSquare)
    check(not strictSafe and strictReason == "unsafe_to_spawn",
        "native spawn-square helper rejects a square refused by isSafeToSpawn")
    strictSquare.spawnUnsafe = false

    local legacyHasTagCalls = 0
    local javaTag = {
        getTranslationName = function() return "WeldingMask" end,
    }
    local javaTags = {
        iterator = function()
            local cursor = 0
            return {
                hasNext = function() return cursor == 0 end,
                next = function()
                    cursor = cursor + 1
                    return javaTag
                end,
            }
        end,
    }
    local javaStyleItem = {
        getTags = function() return javaTags end,
        hasTag = function()
            legacyHasTagCalls = legacyHasTagCalls + 1
            error("Build 42 ItemTag overload must not receive a string")
        end,
    }
    check(SurvivorCompanion.GameplayUtil.itemHasTag(javaStyleItem, "Base:WeldingMask")
            and not SurvivorCompanion.GameplayUtil.itemHasTag(javaStyleItem, "Hammer")
            and legacyHasTagCalls == 0,
        "Build 42 tag lookup must iterate ItemTag objects without probing hasTag(String)")
end

local sensesRuntime = {}
local snapshot = SurvivorCompanion.Senses.snapshot(fellow, player, sensesRuntime)
check(snapshot.valid and snapshot.threatCount == 1, "bounded senses should detect the nearby standing zombie")
check(snapshot.scannedSquares <= SurvivorCompanion.Config.values.perceptionSquareBudget, "sense scan must honor its square budget")
check(snapshot.outerSampled > 0, "rotating outer-band coverage runs within the configured budget")
check(snapshot.immediateCount == 1 and snapshot.lastKnownDanger ~= nil, "immediate and last-known danger should be populated")
check(snapshot.closeThreatCount == 1 and snapshot.closeImmediateCount == 1 and snapshot.occupiedThreatSectors == 1
    and type(snapshot.threatSectors) == "table",
    "perception exposes directional close-threat pressure for overrun decisions")
local blockedLosSquare = squares[squareKey(2, 0, 0)]
blockedLosSquare.losBlocked = true
check(not SurvivorCompanion.GameplayUtil.canSee(fellow, blockedLosSquare), "square LOS fails closed on a blocked B42 raycast")
blockedLosSquare.losBlocked = false
check(SurvivorCompanion.GameplayUtil.canSee(fellow, blockedLosSquare), "square LOS accepts a clear B42 raycast")
blockedLosSquare.losResult = "ClearThroughClosedDoor"
check(not SurvivorCompanion.GameplayUtil.canSee(fellow, blockedLosSquare),
    "square LOS treats a closed-door raycast result as obstructed")
blockedLosSquare.losResult = "ClearThroughWindow"
check(SurvivorCompanion.GameplayUtil.canSee(fellow, blockedLosSquare),
    "square LOS accepts the validated clear-through-window result")
blockedLosSquare.losResult = nil
check(not SurvivorCompanion.GameplayUtil.canSee(fellow, cell:getGridSquare(0, 0, 1)), "square LOS rejects a different floor")

local zedIndex
for index, value in ipairs(zed.square.moving) do if value == zed then zedIndex = index end end
table.remove(zed.square.moving, zedIndex)
clock = clock + 100
local rememberedSnapshot = SurvivorCompanion.Senses.snapshot(fellow, player, sensesRuntime)
check(rememberedSnapshot.threatCount == 0 and rememberedSnapshot.lastKnownDanger ~= nil,
    "last-known danger survives a brief loss of contact")
zed.square.moving[#zed.square.moving + 1] = zed
SurvivorCompanion.Senses.hear(player, 0, 1, 0, 12, 8, "test_sound")
local soundSnapshot = SurvivorCompanion.Senses.snapshot(fellow, player, sensesRuntime)
check(soundSnapshot.strongestSound and soundSnapshot.strongestSound.kind == "test_sound", "recent bounded sound memory")
local stealthCrawler = zombie(3, 2, { onFloor = true })
clock = clock + 100
local crawlerSnapshot = SurvivorCompanion.Senses.snapshot(fellow, player, sensesRuntime)
local crawlerAvoided = false
for _, threat in ipairs(crawlerSnapshot.stealthThreats or {}) do
    if threat.actor == stealthCrawler and threat.prone == true then crawlerAvoided = true break end
end
check(crawlerAvoided,
    "stealth navigation senses living crawlers without promoting them to standing combat threats")
for index = #stealthCrawler.square.moving, 1, -1 do
    if stealthCrawler.square.moving[index] == stealthCrawler then
        table.remove(stealthCrawler.square.moving, index)
    end
end

do
    local sliceClock = clock
    SurvivorCompanion.Performance.reset()
    local slicedRuntime = {}
    local slicedSnapshot
    local completed = false
    for pass = 1, 8 do
        SurvivorCompanion.Performance.beginFrame(2, clock)
        slicedSnapshot = SurvivorCompanion.Senses.snapshot(fellow, player, slicedRuntime)
        if pass == 1 then
            check(slicedSnapshot.scanComplete == false
                and slicedSnapshot.scannedSquares
                    <= SurvivorCompanion.Config.values.performancePerceptionUnitsPerFrame,
                "production perception yields after its shared per-frame quota")
        end
        clock = clock + 16
        SurvivorCompanion.Performance.endFrame(1, false)
        if slicedSnapshot.scanComplete == true then completed = true break end
    end
    check(completed and slicedSnapshot.scanProgress == 1,
        "resumable perception completes a full bounded scan across frames")
    SurvivorCompanion.Performance.reset()
    clock = sliceClock
end

local path, pathReason, expanded = SurvivorCompanion.Navigation.findPath(fellow.square, squares[squareKey(3, 0, 0)])
check(path ~= nil and #path >= 4 and expanded <= SurvivorCompanion.Config.values.navigationNodeBudget, "bounded navigation path")
do
    local pathJob = SurvivorCompanion.Navigation.beginPathSearch(
        fellow.square, squares[squareKey(3, 0, 0)], nil,
        { nodeBudget = SurvivorCompanion.Config.values.navigationNodeBudget })
    local status, slicedPath = SurvivorCompanion.Navigation.resumePathSearch(pathJob, 1)
    check(status == "pending" and slicedPath == nil,
        "production path search yields after a bounded node slice")
    local passes = 1
    while status == "pending" and passes < 100 do
        status, slicedPath = SurvivorCompanion.Navigation.resumePathSearch(pathJob, 4)
        passes = passes + 1
    end
    check(status == "complete" and slicedPath and #slicedPath >= 4,
        "resumable path search continues from its prior frontier")
end

do
local routeSource = cell:getGridSquare(0, 6, 0)
local routeGoal = cell:getGridSquare(6, 6, 0)
local routeWall = {}
for routeX = 1, 5 do
    local wallSquare = cell:getGridSquare(routeX, 6, 0)
    wallSquare.solid = true
    routeWall[#routeWall + 1] = wallSquare
end
local lowerRouteThreat = zombie(3, 7, {})
local routeReport = SurvivorCompanion.Navigation.evaluateRoutes(routeSource, routeGoal, {
    threats = { { actor = lowerRouteThreat } }, allies = {}, player = { available = false },
})
check(routeReport.path and routeReport.candidateCount >= 2
    and routeReport.expandedNodes <= (SurvivorCompanion.Config.values.navigationNodeBudget or 100) + 160,
    "follow routing finds multiple bounded ways around an obstacle")
local routeScoresValid = true
for _, candidate in ipairs(routeReport.routes or {}) do
    if candidate.score < routeReport.selectedScore or candidate.traversal == nil
        or candidate.danger == nil or candidate.crowding == nil or candidate.turns == nil then
        routeScoresValid = false
    end
end
check(routeScoresValid,
    "follow routing evaluates traversal, danger, congestion, and turns before selecting")
for _, wallSquare in ipairs(routeWall) do wallSquare.solid = false end
end

do
local stealthSource = cell:getGridSquare(-4, 12, 0)
local stealthGoal = cell:getGridSquare(18, 12, 0)
local stealthZombie = zombie(7, 17, {})
local stealthSnapshot = {
    threats = { {
        actor = stealthZombie, square = stealthZombie.square, visible = true,
        obstructed = false, attacking = false,
    } },
    allies = {}, player = { available = false },
}
local ordinaryReport = SurvivorCompanion.Navigation.evaluateRoutes(
    stealthSource, stealthGoal, stealthSnapshot)
local stealthReport = SurvivorCompanion.Navigation.evaluateRoutes(
    stealthSource, stealthGoal, stealthSnapshot, { stealthAvoidance = true })
local function nearestRouteDistance(path, target)
    local nearest = math.huge
    for _, routeSquare in ipairs(path or {}) do
        nearest = math.min(nearest,
            math.sqrt(SurvivorCompanion.GameplayUtil.distanceSq(routeSquare, target)))
    end
    return nearest
end
local ordinaryNearest = nearestRouteDistance(ordinaryReport.path, stealthZombie)
local stealthNearest = nearestRouteDistance(stealthReport.path, stealthZombie)
check(stealthReport.path and stealthReport.stealthAvoidance
        and stealthNearest > ordinaryNearest and stealthNearest >= 7,
    "stealth routing pays for a longer corridor that preserves zombie separation"
        .. " ordinary=" .. tostring(ordinaryNearest)
        .. " stealth=" .. tostring(stealthNearest)
        .. " reason=" .. tostring(stealthReport.reason))

local quietActor = actor("sc-stealth-policy", 0, 13, {})
registry[quietActor.id] = quietActor
quietActor.modData.SC_CombatDoctrine = "stealth"
quietActor.modData.SC_WeaponPriority = "quiet"
SurvivorCompanion.Commands.reset(quietActor)
local quietAccepted = SurvivorCompanion.Navigation.request(
    quietActor, stealthGoal, "walk", { snapshot = stealthSnapshot })
local quietState = SurvivorCompanion.Navigation.peek(quietActor)
check(quietAccepted and quietState and quietState.stealthAvoidance == true
        and quietState.stealthRouteExposure ~= nil,
    "quiet or stealth command policy automatically enables threat-buffered navigation")
SurvivorCompanion.Navigation.reset(quietActor)
SurvivorCompanion.Commands.reset(quietActor)
registry[quietActor.id] = nil
end

do
local vegetationSource = cell:getGridSquare(0, 4, 0)
local vegetationGoal = cell:getGridSquare(6, 4, 0)
local bushes = {}
for vegetationX = 1, 5 do
    local bushSquare = cell:getGridSquare(vegetationX, 4, 0)
    local properties = {}
    function properties:has(flag) return flag == IsoFlagType.canBeCut end
    local sprite = { getProperties = function() return properties end }
    local bush = { getSprite = function() return sprite end }
    bushSquare.objects[#bushSquare.objects + 1] = bush
    bushes[bushSquare] = true
end
local vegetationPath = SurvivorCompanion.Navigation.findPath(vegetationSource, vegetationGoal)
local crossedVegetation = false
for _, pathSquare in ipairs(vegetationPath or {}) do
    if bushes[pathSquare] then crossedVegetation = true break end
end
check(vegetationPath ~= nil and crossedVegetation == false,
    "ordinary pathing detours around cuttable bushes instead of pushing through them")

local corridorWalls = {}
for vegetationX = -8, 8 do
    for _, wallY in ipairs({ 3, 5 }) do
        local wallSquare = cell:getGridSquare(vegetationX, wallY, 0)
        wallSquare.solid = true
        corridorWalls[#corridorWalls + 1] = wallSquare
    end
end
local emergencyPath = SurvivorCompanion.Navigation.findPath(
    vegetationSource, vegetationGoal, { vegetationScale = 0.2 })
local emergencyCrossedBush = false
for _, pathSquare in ipairs(emergencyPath or {}) do
    if bushes[pathSquare] then emergencyCrossedBush = true break end
end
local bushEscapeActor = actor("sc-bush-escape", 0, 4, {})
registry[bushEscapeActor.id] = bushEscapeActor
local bushEscapeAccepted = SurvivorCompanion.Navigation.request(
    bushEscapeActor, vegetationGoal, "jog", {
        action = "combat_retreat", urgent = true,
        snapshot = { threats = {}, allies = {}, immediateCount = 0,
            player = { available = false } },
    })
check(emergencyPath ~= nil and emergencyCrossedBush
        and bushEscapeAccepted and bushEscapeActor.lastIntent.emergencyVegetation == true
        and bushEscapeActor.lastIntent.enginePath == true
        and bushEscapeActor.lastIntent.mode == "walk"
        and bushEscapeActor.lastIntent.weaponReady == false,
    "an overgrown only-exit route crosses a cuttable bush under engine steering instead of declaring no escape")
SurvivorCompanion.Navigation.reset(bushEscapeActor)
registry[bushEscapeActor.id] = nil
for _, wallSquare in ipairs(corridorWalls) do wallSquare.solid = false end
for bushSquare in pairs(bushes) do bushSquare.objects = {} end
end

do
local tacticalActor = actor("sc-tactical-retreat", 0, -8, {})
local tacticalThreat = zombie(2, -8, { attacking = false, target = tacticalActor })
registry[tacticalActor.id] = tacticalActor
local tacticalRetreat = SurvivorCompanion.Navigation.request(
    tacticalActor, cell:getGridSquare(-3, -8, 0), "jog", {
        action = "combat_retreat", urgent = true, awayFrom = tacticalThreat,
        snapshot = {
            threats = { { actor = tacticalThreat, visible = true, distanceSq = 4 } },
            allies = {}, immediateCount = 1, closeImmediateCount = 1,
            encircled = false, player = { available = false },
        },
    })
check(tacticalRetreat and tacticalActor.lastIntent.tacticalRetreat == true
        and tacticalActor.lastIntent.tacticalStrafe == true
        and tacticalActor.lastIntent.keepFacing == true
        and tacticalActor.lastIntent.facingTarget == tacticalThreat
        and tacticalActor.lastIntent.mode == "walk",
    "safe open-ground retreat keeps the threat forward and requests backward player locomotion")
SurvivorCompanion.Navigation.reset(tacticalActor)
registry[tacticalActor.id] = nil
tacticalThreat.dead = true
end

do
local roadsideTree = cell:getGridSquare(3, -5, 0)
roadsideTree.hasTree = true
local treeRoute = SurvivorCompanion.Navigation.findPath(
    cell:getGridSquare(0, -6, 0), cell:getGridSquare(6, -6, 0))
local enteredTreeClearance = false
for _, pathSquare in ipairs(treeRoute or {}) do
    if math.abs(pathSquare.x - roadsideTree.x) <= 1
        and math.abs(pathSquare.y - roadsideTree.y) <= 1 then
        enteredTreeClearance = true
        break
    end
end
check(treeRoute ~= nil and enteredTreeClearance == false,
    "ordinary travel prefers the lower-cost route with clearance around a tree")
roadsideTree.hasTree = false
end

do
local corridorTree = cell:getGridSquare(1, 5, 0)
corridorTree.hasTree = true
local corridorWalls = {}
for x = -1, 3 do
    corridorWalls[#corridorWalls + 1] = cell:getGridSquare(x, 4, 0)
    corridorWalls[#corridorWalls + 1] = cell:getGridSquare(x, 6, 0)
end
corridorWalls[#corridorWalls + 1] = cell:getGridSquare(-1, 5, 0)
corridorWalls[#corridorWalls + 1] = cell:getGridSquare(3, 5, 0)
for _, square in ipairs(corridorWalls) do square.solid = true end
local corridorRoute = SurvivorCompanion.Navigation.findPath(
    cell:getGridSquare(0, 5, 0), cell:getGridSquare(2, 5, 0))
check(corridorRoute ~= nil and corridorRoute[2] == corridorTree,
    "a tree is costly terrain rather than an absolute wall when it is the only exit")
for _, square in ipairs(corridorWalls) do square.solid = false end
corridorTree.hasTree = false
end

do
local furnitureSquare = cell:getGridSquare(2, -8, 0)
local furniture = { __class = "IsoThumpable" }
function furniture:isThumpable() return true end
function furniture:isBlockAllTheSquare() return true end
function furniture:isStairsObject() return false end
furnitureSquare.objects[#furnitureSquare.objects + 1] = furniture
furnitureSquare.specialObjects[#furnitureSquare.specialObjects + 1] = furniture
local furnitureRoute = SurvivorCompanion.Navigation.findPath(
    cell:getGridSquare(0, -8, 0), cell:getGridSquare(4, -8, 0))
local enteredFurniture = false
for _, square in ipairs(furnitureRoute or {}) do
    if square == furnitureSquare then enteredFurniture = true end
end
check(furnitureRoute ~= nil and enteredFurniture == false,
    "full-square player-built thumpables are excluded from Lua routes")
furnitureSquare.objects, furnitureSquare.specialObjects = {}, {}
end

do
local formationTree = cell:getGridSquare(3, -3, 0)
formationTree.hasTree = true
local treeGoalActor = actor("sc-tree-goal", 0, -3, {})
registry[treeGoalActor.id] = treeGoalActor
check(SurvivorCompanion.Navigation.request(treeGoalActor, formationTree, "walk", {
        action = "follow_formation", followRecovery = true, snapshot = { allies = {} },
    }) and treeGoalActor.lastIntent.goalAdjustedForObstacle == true
    and SurvivorCompanion.Navigation.peek(treeGoalActor).goalSquare ~= formationTree,
    "a follow slot that lands on a tree is shifted to a nearby navigable formation square")
formationTree.hasTree = false
SurvivorCompanion.Navigation.reset(treeGoalActor)
registry[treeGoalActor.id] = nil
end

local navigationOK = SurvivorCompanion.Navigation.request(fellow, squares[squareKey(3, 0, 0)], "walk", { snapshot = snapshot })
check(navigationOK and fellow.lastIntent and fellow.lastIntent.humanAnimationOnly, "navigation uses the actor bridge with human animation intent")
check(fellow.lastIntent.nextSquare and fellow.lastIntent.targetSquare and fellow.lastIntent.direction,
    "navigation emits normalized target, next-square, and direction intent fields")

do
local nearestStartClock = clock
local nearestActor = actor("sc-native-nearest", -7, 2, {})
registry[nearestActor.id] = nearestActor
local interactionObject = { square = cell:getGridSquare(-3, 2, 0) }
function interactionObject:getSquare() return self.square end
local targets = SurvivorCompanion.Navigation.interactionTargets(
    nearestActor, interactionObject, { maximum = 4 })
local previousNativeActions = SurvivorCompanion.NativeActions
local starts = 0
SurvivorCompanion.NativeActions = {
    pathToNearest = function(owner, requested, mode)
        starts = starts + 1
        return owner == nearestActor and #requested >= 2 and mode == "walk",
            "nearest_path_started"
    end,
    pathTelemetry = function()
        return { available = true, active = true, shouldBeMoving = true,
            hasStartedMoving = false, pending = true }
    end,
    stopDirect = function() return true end,
}
local nearestStarted = SurvivorCompanion.Navigation.requestAny(
    nearestActor, targets, "walk", { action = "test_nearest", arrivalDistance = 0.8 })
clock = clock + 2500
local nearestRetained, nearestStatus = SurvivorCompanion.Navigation.requestAny(
    nearestActor, targets, "walk", { action = "test_nearest", arrivalDistance = 0.8 })
check(nearestStarted and nearestRetained and starts == 1
        and (nearestStatus == "native_path_pending" or nearestStatus == "native_path_owned"),
    "native nearest-of-many routing retains ownership while the asynchronous path is pending")
nearestActor.square = targets[2]
local nearestArrived, nearestArrivalStatus = SurvivorCompanion.Navigation.requestAny(
    nearestActor, targets, "walk", { action = "test_nearest", arrivalDistance = 0.8 })
check(nearestArrived and nearestArrivalStatus == "arrived"
        and SurvivorCompanion.Navigation.peek(nearestActor).nativeLease == nil,
    "nearest-of-many routing accepts any candidate and releases native ownership on arrival")
SurvivorCompanion.Navigation.reset(nearestActor)
SurvivorCompanion.NativeActions = previousNativeActions
registry[nearestActor.id] = nil
clock = nearestStartClock
end

do
local driftingGoalActor = actor("sc-drifting-goal", -8, 8, {})
registry[driftingGoalActor.id] = driftingGoalActor
for targetX = -5, -2 do
    check(SurvivorCompanion.Navigation.request(
        driftingGoalActor, cell:getGridSquare(targetX, 8, 0), "walk", {
            action = "follow_formation", followRecovery = true, snapshot = { allies = {} },
        }), "a slowly moving follow target remains routable")
end
local driftingState = SurvivorCompanion.Navigation.peek(driftingGoalActor)
check(driftingState.pathGoalSquare
        and driftingState.pathGoalSquare:getX() == -2,
    "cumulative small follow-goal shifts eventually rebuild the route for the current destination")
SurvivorCompanion.Navigation.reset(driftingGoalActor)
registry[driftingGoalActor.id] = nil
end

do
local failedEdgeActor = actor("sc-failed-edge", -7, -7, {})
registry[failedEdgeActor.id] = failedEdgeActor
failedEdgeActor.rejectMovement = true
local accepted, reason = SurvivorCompanion.Navigation.request(
    failedEdgeActor, cell:getGridSquare(-5, -7, 0), "walk", {})
local failedState = SurvivorCompanion.Navigation.peek(failedEdgeActor)
local failedKey = SurvivorCompanion.GameplayUtil.squareKey(cell:getGridSquare(-7, -7, 0))
    .. ">" .. SurvivorCompanion.GameplayUtil.squareKey(cell:getGridSquare(-6, -7, 0))
check(not accepted and reason == "movement_rejected"
        and failedState.blockedEdges[failedKey] ~= nil
        and failedState.routeMemory[failedKey]
        and failedState.routeMemory[failedKey].success == false
        and failedState.lastBlocker.type == "unknown",
    "a rejected native step blacklists its exact edge and records short-lived route memory")
failedEdgeActor.rejectMovement = false
check(SurvivorCompanion.Navigation.request(
        failedEdgeActor, cell:getGridSquare(-5, -7, 0), "walk", {})
        and failedEdgeActor.lastIntent.nextSquare ~= cell:getGridSquare(-6, -7, 0),
    "immediate replanning cannot select the same failed edge")
SurvivorCompanion.Navigation.reset(failedEdgeActor)
registry[failedEdgeActor.id] = nil
end

do
local vehicleActor = actor("sc-vehicle-blocker", -7, -5, {})
registry[vehicleActor.id] = vehicleActor
vehicleActor.rejectMovement = true
vehicleActor.collidedVehicle = true
local accepted = SurvivorCompanion.Navigation.request(
    vehicleActor, cell:getGridSquare(-5, -5, 0), "walk", {})
local vehicleState = SurvivorCompanion.Navigation.peek(vehicleActor)
check(not accepted and vehicleState.lastBlocker.type == "vehicle"
        and vehicleState.lastBlocker.recoveryResult == "direct_replan",
    "vehicle collision evidence selects dedicated vehicle recovery diagnostics")
SurvivorCompanion.Navigation.reset(vehicleActor)
registry[vehicleActor.id] = nil
end

do
local stateActor = actor("sc-state-blocker", -7, -3, {})
registry[stateActor.id] = stateActor
stateActor.blockMovement = true
SurvivorCompanion.Config.values.navigationStuckMs = 0
local accepted, reason = SurvivorCompanion.Navigation.request(
    stateActor, cell:getGridSquare(-5, -3, 0), "walk", {})
local movementState = SurvivorCompanion.Navigation.peek(stateActor)
check(accepted and reason == "waiting_movement_locked"
        and movementState.lastBlocker.type == "actor_state"
        and movementState.lastBlocker.actorState == "movement_locked",
    "a stuck animation state waits safely instead of being misclassified as map geometry")
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = 100
SurvivorCompanion.Config.values.navigationActorStateGraceMs = 1
clock = clock + 101
local timedOutState, timedOutReason = SurvivorCompanion.Navigation.request(
    stateActor, cell:getGridSquare(-5, -3, 0), "walk", {})
check(not timedOutState and timedOutReason == "actor_state_timeout:movement_locked",
    "a native state that never clears reaches a visible bounded failure instead of waiting forever")
stateActor.blockMovement = false
clock = clock + 1
check(SurvivorCompanion.Navigation.request(
        stateActor, cell:getGridSquare(-5, -3, 0), "walk", {})
        and SurvivorCompanion.Navigation.peek(stateActor).actorStateName == nil,
    "clearing a native movement state resumes routing without an immediate false stuck recovery")
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = nil
SurvivorCompanion.Config.values.navigationActorStateGraceMs = nil
SurvivorCompanion.Config.values.navigationStuckMs = 5000
SurvivorCompanion.Navigation.reset(stateActor)
registry[stateActor.id] = nil
end

do
local wallStateActor = actor("sc-wall-state-blocker", -7, -2, {})
registry[wallStateActor.id] = wallStateActor
wallStateActor.currentState = { __class = "CollideWithWallState" }
SurvivorCompanion.Config.values.navigationActorStateGraceMs = 100
check(SurvivorCompanion.Navigation.request(
        wallStateActor, cell:getGridSquare(-5, -2, 0), "walk", {}),
    "a fresh wall-collision animation receives a short native grace period")
clock = clock + 2001
check(SurvivorCompanion.Navigation.request(
        wallStateActor, cell:getGridSquare(-5, -2, 0), "walk", {})
        and SurvivorCompanion.Navigation.peek(wallStateActor).lastBlocker.recoveryResult
            == "cancelled_stale_wall_collision",
    "a stale wall-collision animation cancels its old movement owner instead of waiting forever")
SurvivorCompanion.Config.values.navigationActorStateGraceMs = nil
SurvivorCompanion.Navigation.reset(wallStateActor)
registry[wallStateActor.id] = nil
end

do
local cornerSource = squares[squareKey(5, 5, 0)]
local cornerStep = squares[squareKey(6, 5, 0)]
local cornerGoal = squares[squareKey(6, 6, 0)]
local cornerBlocker = squares[squareKey(5, 6, 0)]
cornerBlocker.solid = true
cornerGoal.losBlocked = true
local cornerActor = actor("sc-corner", 5, 5, {})
registry[cornerActor.id] = cornerActor
local cornerHeld, cornerHeldReason = SurvivorCompanion.Navigation.request(cornerActor, cornerGoal, "walk", {
    snapshot = { threats = {}, allies = {}, player = { available = false } },
})
check(cornerHeld and cornerHeldReason == "checking_blind_corner"
        and cornerActor.lastIntent and cornerActor.lastIntent.action == "ready_weapon",
    "blind inner turn pauses and readies an equipped weapon before committing")
clock = clock + 400
check(SurvivorCompanion.Navigation.request(cornerActor, cornerGoal, "walk", {
    snapshot = { threats = {}, allies = {}, player = { available = false } },
}) and cornerActor.lastIntent.tacticalCorner and cornerActor.lastIntent.tacticalStrafe
    and cornerActor.lastIntent.facingTarget == cornerGoal and cornerActor.lastIntent.mode == "sneak",
    "blind corner advances as a slow sidestep while facing the unseen landing square")
cornerBlocker.solid = false
cornerGoal.losBlocked = false

local stairSource = squares[squareKey(7, 5, 0)]
local stairLanding = cell:getGridSquare(7, 5, 1)
function stairSource:HasStairs() return true end
function stairLanding:HasStairs() return true end
local stairActor = actor("sc-stair", 7, 5, {})
registry[stairActor.id] = stairActor
local stairHeld, stairHeldReason = SurvivorCompanion.Navigation.request(stairActor, stairLanding, "jog", {
    snapshot = { threats = {}, allies = {}, player = { available = false } },
})
check(stairHeld and stairHeldReason == "checking_stair_landing"
        and stairActor.lastIntent and stairActor.lastIntent.action == "ready_weapon",
    "stair transition checks the blind landing with a ready weapon before moving")
clock = clock + 500
check(SurvivorCompanion.Navigation.request(stairActor, stairLanding, "jog", {
    snapshot = { threats = {}, allies = {}, player = { available = false } },
}) and stairActor.lastIntent.tacticalStair and stairActor.lastIntent.mode == "walk"
    and stairActor.lastIntent.facingTarget == stairLanding,
    "stairs force a spaced walking step that keeps attention on the landing")

local spacedSource = squares[squareKey(8, 5, 0)]
local spacedLanding = cell:getGridSquare(8, 5, 1)
function spacedSource:HasStairs() return true end
function spacedLanding:HasStairs() return true end
local stairLeader = actor("sc-stair-leader", 8, 5, { z = 1 })
local stairFollower = actor("sc-stair-follower", 8, 5, {})
registry[stairLeader.id], registry[stairFollower.id] = stairLeader, stairFollower
SurvivorCompanion.Navigation.request(stairFollower, spacedLanding, "walk", {
    snapshot = { threats = {}, allies = { { actor = stairLeader } }, player = { available = false } },
})
clock = clock + 500
local spacedHeld, spacedReason = SurvivorCompanion.Navigation.request(stairFollower, spacedLanding, "walk", {
    snapshot = { threats = {}, allies = { { actor = stairLeader } }, player = { available = false } },
})
check(spacedHeld and spacedReason == "holding_stair_spacing",
    "a follower waits instead of crowding a teammate on the stair landing")
registry[stairLeader.id], registry[stairFollower.id] = nil, nil

local entrySource = cell:getGridSquare(13, 0, 0)
local entryStep = cell:getGridSquare(14, 0, 0)
local entryGoal = cell:getGridSquare(15, 0, 0)
local entryRoom = { name = "entry-test-room" }
entryStep.room, entryGoal.room = entryRoom, entryRoom
local entryActor = actor("sc-room-entry", 13, 0, {})
registry[entryActor.id] = entryActor
local entryHeld, entryHeldReason = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", { action = "house_entry_test", snapshot = { allies = {} } })
check(entryHeld and entryHeldReason == "checking_room_entry"
        and entryActor.lastIntent and entryActor.lastIntent.action == "ready_weapon",
    "entering a new room pauses at the threshold with a ready weapon")
clock = clock + 500
local leftChecked, leftReason = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", { action = "house_entry_test", snapshot = { allies = {} } })
check(leftChecked and leftReason == "checking_room_entry_left"
    and entryActor.lastIntent.action == "room_sweep" and entryActor.lastIntent.sweepSide == "left",
    "room entry explicitly checks the left corner from the approach heading")
local rightChecked, rightReason = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", { action = "house_entry_test", snapshot = { allies = {} } })
check(rightChecked and rightReason == "checking_room_entry_right"
    and entryActor.lastIntent.action == "room_sweep" and entryActor.lastIntent.sweepSide == "right",
    "room entry explicitly checks the right corner before advancing")
entryActor.lastIntent = nil
local entryAdvanced = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", { action = "house_entry_test", snapshot = { allies = {} } })
check(entryAdvanced and entryActor.lastIntent and entryActor.lastIntent.roomEntryChecked == true,
    "room-entry movement advances only after both corner checks")
entryStep.room, entryGoal.room = nil, nil
SurvivorCompanion.Navigation.reset(entryActor)
registry[entryActor.id] = nil

local routeRoom = { name = "route-test" }
for routeX = 24, 40 do
    for routeY = -8, 8 do cell:getGridSquare(routeX, routeY, 0).room = routeRoom end
end
local routeOutside = cell:getGridSquare(30, 0, 0)
local routeInside = cell:getGridSquare(31, 0, 0)
local routeDeep = cell:getGridSquare(32, 0, 0)
routeOutside.room = nil
local routeActor = actor("sc-egress", 30, 0, {})
registry[routeActor.id] = routeActor
check(SurvivorCompanion.Navigation.rememberPosition(routeActor), "outdoor threshold is observed")
routeActor.square = routeInside
check(SurvivorCompanion.Navigation.rememberPosition(routeActor), "indoor threshold is observed")
routeActor.square = routeDeep
check(SurvivorCompanion.Navigation.rememberPosition(routeActor), "deep indoor breadcrumb is observed")
routeActor.square = cell:getGridSquare(32, 1, 0)
SurvivorCompanion.Navigation.rememberPosition(routeActor)
routeActor.square = routeDeep
SurvivorCompanion.Navigation.rememberPosition(routeActor)
check(#SurvivorCompanion.Navigation.peek(routeActor).indoorTrail == 3,
    "breadcrumb memory erases loops instead of growing an oscillating route")
local rememberedExit, egressPlan = SurvivorCompanion.Navigation.retreatTarget(routeActor, { threats = {} })
check(rememberedExit == routeOutside and egressPlan.outdoors
    and (egressPlan.source == "shortest_outdoor" or egressPlan.source == "entry_route"),
    "retreat planning selects the shortest verified exterior route or the known entry trail")
end

do
local positioningLeader = actor("positioning-player", 20, 20, {
    className = "IsoPlayer", recruited = false, forwardX = 1, forwardY = 0,
})
positioningLeader.modData.SC_Recruited = false
local formationLeft = actor("000-formation-left", 15, 20, {})
local formationRight = actor("001-formation-right", 15, 21, {})
registry[formationLeft.id], registry[formationRight.id] = formationLeft, formationRight
check(SurvivorCompanion.Commands.issue(formationLeft.id, "follow", nil, positioningLeader)
    and SurvivorCompanion.Commands.issue(formationRight.id, "follow", nil, positioningLeader),
    "formation fixtures enter the persistent follow order")
local formationSnapshot = { threats = {}, allies = {}, player = { actor = positioningLeader, danger = 0 } }
local leftTarget = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, SurvivorCompanion.Commands.peek(formationLeft), formationSnapshot)
local rightTarget = SurvivorCompanion.Positioning.formationTarget(
    formationRight, positioningLeader, SurvivorCompanion.Commands.peek(formationRight), formationSnapshot)
check(leftTarget and leftTarget.x == 19 and leftTarget.y == 19
    and rightTarget and rightTarget.x == 19 and rightTarget.y == 21,
    "stable identity slots rotate behind an east-facing player instead of using world axes")

positioningLeader.forwardX, positioningLeader.forwardY = 0, 1
clock = clock + 100
local aimTurnTarget = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, SurvivorCompanion.Commands.peek(formationLeft), formationSnapshot)
check(aimTurnTarget == leftTarget,
    "a stationary aim turn does not make companions orbit around the player")
clock = clock + 3000
local settledHeadingTarget = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, SurvivorCompanion.Commands.peek(formationLeft), formationSnapshot)
check(settledHeadingTarget and settledHeadingTarget ~= leftTarget,
    "a sustained leader heading eventually rotates the travel formation")

formationLeft.square = settledHeadingTarget
check(SurvivorCompanion.Positioning.shouldHold(formationLeft, settledHeadingTarget),
    "formation arrival enters a stable hold band")
formationLeft.square = cell:getGridSquare(settledHeadingTarget.x + 2, settledHeadingTarget.y, 0)
check(not SurvivorCompanion.Positioning.shouldHold(formationLeft, settledHeadingTarget),
    "formation hold releases only after the wider hysteresis boundary")
local guardedMode, guardedPosture = SurvivorCompanion.Positioning.followMode("walk", 80, 4)
check(guardedMode == "sneak" and guardedPosture == "guarded",
    "high stress selects guarded human locomotion without a zombie animation")

SurvivorCompanion.Config.values.rearScanIntervalMs = 1
SurvivorCompanion.Config.values.rearScanHoldMs = 1
formationLeft.square = settledHeadingTarget
SurvivorCompanion.Positioning.shouldHold(formationLeft, settledHeadingTarget)
formationLeft.lastIntent = nil
check(SurvivorCompanion.Positioning.updateHoldAwareness(
        formationLeft, positioningLeader, formationSnapshot) == nil,
    "rear awareness uses a phased per-actor timer instead of scanning every frame")
clock = clock + 2
check(SurvivorCompanion.Positioning.updateHoldAwareness(
        formationLeft, positioningLeader, formationSnapshot)
    and formationLeft.lastIntent.action == "rear_scan"
    and positioningLeader.lastIntent == nil,
    "a formation holder periodically checks the route behind without controlling the player")
clock = clock + 2
check(SurvivorCompanion.Positioning.updateHoldAwareness(
        formationLeft, positioningLeader, formationSnapshot)
    and formationLeft.lastIntent.action == "face_formation",
    "formation-facing is restored after the bounded rear observation")
SurvivorCompanion.Config.values.rearScanIntervalMs = nil
SurvivorCompanion.Config.values.rearScanHoldMs = nil

formationLeft.square = cell:getGridSquare(20, 18, 0)
formationLeft.lastIntent = nil
check(SurvivorCompanion.Positioning.beginConversation(formationLeft, positioningLeader, {
        action = "status", emote = "yes", stress = 25,
    }) and SurvivorCompanion.Positioning.updateConversation(formationLeft, formationSnapshot)
    and formationLeft.lastIntent.action == "conversation_pose"
    and formationLeft.lastIntent.targetPosition == positioningLeader
    and positioningLeader.lastIntent == nil,
    "conversation positioning stops, faces, and gestures only through the companion actor")
formationLeft.lastIntent = nil
check(SurvivorCompanion.Positioning.updateConversation(formationLeft, formationSnapshot)
    and formationLeft.lastIntent.action == "face_conversation"
    and formationLeft.lastIntent.emote == nil,
    "conversation gesture is one-shot while stable partner-facing continues")
formationLeft.lastIntent = nil
check(not SurvivorCompanion.Positioning.updateConversation(formationLeft, {
        threatCount = 1, immediateCount = 0, threats = {}, allies = {},
    }) and formationLeft.lastIntent == nil,
    "danger interrupts social positioning before it can own another movement intent")

local socialApproach = actor("social-approach", 20, 12, {})
registry[socialApproach.id] = socialApproach
check(SurvivorCompanion.Positioning.beginConversation(socialApproach, positioningLeader, {
        action = "opinion", emote = "shrug", stress = 50,
    }) and SurvivorCompanion.Positioning.updateConversation(socialApproach, formationSnapshot)
    and socialApproach.lastIntent.action == "conversation_approach",
    "a distant speaker approaches a reserved social ring instead of talking from the horizon")
local socialDistance = SurvivorCompanion.GameplayUtil.distance(
    socialApproach.lastIntent.targetSquare, positioningLeader)
check(socialDistance >= 1.2 and socialDistance <= 2.8,
    "conversation approach target remains inside the configured minimum/maximum ring")

local spaceActor = actor("space-yielding", 10, 10, {})
local spaceBlocker = actor("space-blocker", 11, 10, {})
registry[spaceActor.id], registry[spaceBlocker.id] = spaceActor, spaceBlocker
local spaceCorridorWalls = {
    cell:getGridSquare(10, 9, 0), cell:getGridSquare(10, 11, 0),
    cell:getGridSquare(11, 9, 0), cell:getGridSquare(11, 11, 0),
    cell:getGridSquare(12, 9, 0), cell:getGridSquare(12, 11, 0),
}
for _, square in ipairs(spaceCorridorWalls) do square.solid = true end
local spaceSnapshot = { threats = {}, allies = { { actor = spaceBlocker } }, player = { available = false } }
local spaceHeld, spaceHeldReason = SurvivorCompanion.Navigation.request(
    spaceActor, cell:getGridSquare(12, 10, 0), "walk", { snapshot = spaceSnapshot })
check(spaceHeld and spaceHeldReason == "moving" and spaceActor.lastIntent ~= nil
        and not (spaceActor.lastIntent.nextSquare.x == 11
            and spaceActor.lastIntent.nextSquare.y == 10),
    "the planner treats an occupied ally square as costly and selects another route")
clock = clock + 1000
for _, square in ipairs(spaceCorridorWalls) do square.solid = false end
local spaceYielded, spaceYieldReason = SurvivorCompanion.Navigation.request(
    spaceActor, cell:getGridSquare(12, 10, 0), "walk", { snapshot = spaceSnapshot })
check(spaceYielded and spaceYieldReason == "moving",
    "crowd-aware movement remains stable after the temporary passage clears")

local priorityFirst = actor("right-of-way-a", -10, 10, {})
local prioritySecond = actor("right-of-way-b", -10, 10, {})
registry[priorityFirst.id], registry[prioritySecond.id] = priorityFirst, prioritySecond
local sharedGoal = cell:getGridSquare(-8, 10, 0)
check(SurvivorCompanion.Navigation.request(priorityFirst, sharedGoal, "walk", { snapshot = { allies = {} } }),
    "first movement claimant reserves a shared next step")
local yielded, yieldedReason = SurvivorCompanion.Navigation.request(
    prioritySecond, sharedGoal, "walk", { snapshot = { allies = {} } })
check(yielded and yieldedReason == "yielding_right_of_way" and prioritySecond.lastIntent == nil,
    "deterministic right-of-way prevents two companions claiming one step")

for _, value in ipairs({ formationLeft, formationRight, socialApproach, spaceActor, spaceBlocker,
        priorityFirst, prioritySecond }) do
    SurvivorCompanion.Positioning.reset(value)
    SurvivorCompanion.Navigation.reset(value)
    SurvivorCompanion.Commands.reset(value)
    registry[value.id] = nil
end
end
local rejectedNavigator = actor("sc-nav-reject", -5, 0, {})
registry[rejectedNavigator.id] = rejectedNavigator
rejectedNavigator.rejectMovement = true
local rejectedNavigation = SurvivorCompanion.Navigation.request(
    rejectedNavigator,
    squares[squareKey(-3, 0, 0)],
    "walk",
    {}
)
check(not rejectedNavigation, "navigation never reports movement success when Actor rejects the step")

do
local supervisedRouteActor = actor("sc-nav-supervised", -5, 1, {})
registry[supervisedRouteActor.id] = supervisedRouteActor
local supervisedRouteToken = assert(SurvivorCompanion.ActionSupervisor.begin(
    supervisedRouteActor, {
        owner = "test", action = "supervised_route", targetKey = "-2:1:0",
        priority = SurvivorCompanion.ActionSupervisor.Priority.WORK,
        allowedActions = { supervised_route = true },
    }))
local supervisedMoved = SurvivorCompanion.Navigation.request(
    supervisedRouteActor, squares[squareKey(-2, 1, 0)], "walk", {
        action = "supervised_route", supervisorToken = supervisedRouteToken,
    })
local supervisedRouteStatus = SurvivorCompanion.Navigation.status(supervisedRouteActor)
check(supervisedMoved and supervisedRouteStatus.actionTokenSerial == supervisedRouteToken.serial
        and supervisedRouteActor.lastIntent.supervisorToken == supervisedRouteToken,
    "route state and every emitted movement retain the owning action token")
SurvivorCompanion.Navigation.reset(supervisedRouteActor)
SurvivorCompanion.ActionSupervisor.cancel(supervisedRouteActor, "fixture_done", nil, true)
registry[supervisedRouteActor.id] = nil
end

do
local stuckClock = clock
local stuckActor = actor("sc-stuck", -5, 2, {})
registry[stuckActor.id] = stuckActor
SurvivorCompanion.Config.values.navigationStuckMs = 0
check(SurvivorCompanion.Navigation.request(stuckActor, squares[squareKey(-2, 2, 0)], "walk", {}),
    "first bounded stuck recovery is accepted")
check(SurvivorCompanion.Navigation.request(stuckActor, squares[squareKey(-2, 2, 0)], "walk", {}),
    "second bounded stuck recovery is accepted")
local terminalRecovery, terminalReason = SurvivorCompanion.Navigation.request(
    stuckActor,
    squares[squareKey(-2, 2, 0)],
    "walk",
    {}
)
local terminalStatus = SurvivorCompanion.Navigation.status(stuckActor)
check(not terminalRecovery
        and string.find(terminalReason or "", "recovery_exhausted:", 1, true) == 1
        and terminalStatus.phase == "failed" and terminalStatus.terminalRetryMs > 0
        and terminalStatus.blockerType ~= nil,
    "stuck recovery reaches one visible bounded failure episode")
local terminalHeld, terminalHeldReason = SurvivorCompanion.Navigation.request(
    stuckActor, squares[squareKey(-2, 2, 0)], "walk", {})
check(not terminalHeld and terminalHeldReason == terminalReason,
    "unchanged terminal route cannot restart on every AI tick")
clock = clock + SurvivorCompanion.Config.values.navigationTerminalRetryMs + 1
local terminalRetried, terminalRetryReason = SurvivorCompanion.Navigation.request(
    stuckActor, squares[squareKey(-2, 2, 0)], "walk", {})
check(terminalRetried and terminalRetryReason ~= terminalReason,
    "terminal route receives one explicit timed retry instead of a permanent lock")
SurvivorCompanion.Navigation.reset(stuckActor)
registry[stuckActor.id] = nil
clock = stuckClock
end

do
local topologyActor = actor("sc-stuck-topology", -5, 3, {})
registry[topologyActor.id] = topologyActor
local topologyGoal = squares[squareKey(-2, 3, 0)]
check(SurvivorCompanion.Navigation.request(topologyActor, topologyGoal, "walk", {})
        and SurvivorCompanion.Navigation.request(topologyActor, topologyGoal, "walk", {}),
    "topology retry fixture exhausts its bounded recovery attempts")
local topologyTerminal = SurvivorCompanion.Navigation.request(
    topologyActor, topologyGoal, "walk", {})
check(not topologyTerminal and SurvivorCompanion.Navigation.status(topologyActor).phase == "failed",
    "topology retry fixture records its terminal episode")
local changedTopologySquare = squares[squareKey(-2, 4, 0)]
changedTopologySquare.solid = true
local topologyRetried, topologyRetryReason = SurvivorCompanion.Navigation.request(
    topologyActor, topologyGoal, "walk", {})
check(topologyRetried and topologyRetryReason ~= "recovery_exhausted:unknown"
        and SurvivorCompanion.Navigation.status(topologyActor).phase ~= "failed",
    "a material topology change clears the prior terminal episode immediately")
changedTopologySquare.solid = false
SurvivorCompanion.Navigation.reset(topologyActor)
registry[topologyActor.id] = nil
end

do
    local treeStuckActor = actor("sc-tree-stuck", -5, 6, {})
    registry[treeStuckActor.id] = treeStuckActor
    local blockingTree = cell:getGridSquare(-4, 6, 0)
    blockingTree.hasTree = true
    SurvivorCompanion.Config.values.navigationObstacleStuckMs = 0
    check(SurvivorCompanion.Navigation.request(
        treeStuckActor, cell:getGridSquare(-2, 6, 0), "walk", {}),
        "tree collision recovery first cancels the blocked movement")
    check(SurvivorCompanion.Navigation.request(
        treeStuckActor, cell:getGridSquare(-2, 6, 0), "walk", {})
        and treeStuckActor.lastIntent.action == "collision_recovery"
        and treeStuckActor.lastIntent.treeRecovery == true
        and treeStuckActor.lastIntent.nextSquare.x == -6
        and treeStuckActor.lastIntent.nextSquare.y == 6,
        "tree collision recovery steps away from the trunk before repathing")
    SurvivorCompanion.Config.values.navigationObstacleStuckMs = 900
    blockingTree.hasTree = false
    SurvivorCompanion.Navigation.reset(treeStuckActor)
    registry[treeStuckActor.id] = nil
end

do
    local movingGoalActor = actor("sc-moving-goal-stuck", -5, 4, {})
    registry[movingGoalActor.id] = movingGoalActor
    check(SurvivorCompanion.Navigation.request(
        movingGoalActor,
        squares[squareKey(-2, 4, 0)],
        "walk",
        { action = "follow_formation", followRecovery = true }
    ), "first recovery survives a moving formation goal")
    check(SurvivorCompanion.Navigation.request(
        movingGoalActor,
        squares[squareKey(-1, 4, 0)],
        "walk",
        { action = "follow_formation", followRecovery = true }
    ), "small formation-goal changes preserve bounded recovery progress")
    local movingGoalRecovered, movingGoalReason = SurvivorCompanion.Navigation.request(
        movingGoalActor,
        squares[squareKey(-2, 4, 0)],
        "walk",
        { action = "follow_formation", followRecovery = true }
    )
    check(not movingGoalRecovered
            and string.find(movingGoalReason or "", "recovery_exhausted:", 1, true) == 1,
        "moving formation goals cannot reset the stuck guard forever")
    local movingGoalState = SurvivorCompanion.Navigation.peek(movingGoalActor)
    check(movingGoalState.roomEntryKey == nil and movingGoalState.cornerObserveKey == nil,
        "stuck recovery clears stale doorway and corner observations")
    SurvivorCompanion.Navigation.reset(movingGoalActor)
    registry[movingGoalActor.id] = nil
end

local rejectedRecoveryActor = actor("sc-recovery-reject", -5, 3, {})
registry[rejectedRecoveryActor.id] = rejectedRecoveryActor
rejectedRecoveryActor.rejectStop = true
local rejectedRecovery = SurvivorCompanion.Navigation.request(
    rejectedRecoveryActor,
    squares[squareKey(-2, 3, 0)],
    "walk",
    {}
)
check(not rejectedRecovery, "navigation propagates a rejected recovery action")
SurvivorCompanion.Config.values.navigationStuckMs = 5000

local doorFrom = squares[squareKey(0, 2, 0)]
local doorTo = squares[squareKey(1, 2, 0)]
local testDoor = { open = false, locked = false }
function testDoor:IsOpen() return self.open end
function testDoor:isLocked() return self.locked end
function testDoor:ToggleDoor(character)
    if self.noopToggle then return true end
    self.open = not self.open
end
function doorFrom:isDoorTo(other) return other == doorTo end
function doorTo:isDoorTo(other) return other == doorFrom end
function doorTo:getDoor(north) if north == false then return testDoor end end
local doorActor = actor("sc-door", 0, 2, {})
registry[doorActor.id] = doorActor
check(SurvivorCompanion.Navigation.request(doorActor, doorTo, "walk", {}), "door interaction begins")
clock = clock + 350
check(SurvivorCompanion.Navigation.request(doorActor, doorTo, "walk", {}) and testDoor.open
        and doorActor.lastIntent.enginePath == true
        and doorActor.lastIntent.nativeAffordance == "door",
    "required unlocked door opens and hands the whole threshold crossing to native pathing")
local queuedDoorActor = actor("sc-door-queued", 0, 2, {})
registry[queuedDoorActor.id] = queuedDoorActor
local queuedDoor, queuedDoorReason = SurvivorCompanion.Navigation.request(
    queuedDoorActor, doorTo, "walk", {})
check(queuedDoor and queuedDoorReason == "holding_choke_queue"
        and queuedDoorActor.lastIntent
        and queuedDoorActor.lastIntent.action == "ready_weapon"
        and queuedDoorActor.lastIntent.nextSquare == nil
        and SurvivorCompanion.Navigation.peek(queuedDoorActor).chokeQueueOwner == doorActor
        and #(SurvivorCompanion.Locomotion.snapshot(queuedDoorActor).events or {}) >= 1,
    "a second companion queues outside the reserved door corridor instead of crowding it"
        .. " status=" .. tostring(queuedDoorReason)
        .. " action=" .. tostring(queuedDoorActor.lastIntent
            and queuedDoorActor.lastIntent.action))
SurvivorCompanion.Navigation.reset(queuedDoorActor)
registry[queuedDoorActor.id] = nil
doorActor.square = doorTo
doorActor.worldX, doorActor.worldY = 1.08, 2.5
clock = clock + 800
SurvivorCompanion.Config.values.navigationStuckMs = 0
check(SurvivorCompanion.Navigation.request(doorActor, squares[squareKey(2, 2, 0)], "walk", {})
    and testDoor.open, "an owned door stays open while its companion still overlaps the threshold")
check(SurvivorCompanion.Navigation.request(doorActor, squares[squareKey(2, 2, 0)], "walk", {})
    and testDoor.open and doorActor.lastIntent.action == "collision_recovery"
    and doorActor.lastIntent.doorwayRecovery == true
    and doorActor.lastIntent.nextSquare.x == 1 and doorActor.lastIntent.nextSquare.y ~= 2,
    "doorway recovery sidesteps the door plane instead of running into the same edge")
SurvivorCompanion.Config.values.navigationStuckMs = 5000
doorActor.worldX, doorActor.worldY = 1.5, 2.5
clock = clock + 701
testDoor.noopToggle = true
SurvivorCompanion.Navigation.request(doorActor, squares[squareKey(2, 2, 0)], "walk", {})
check(testDoor.open and #SurvivorCompanion.Navigation.peek(doorActor).openedDoors == 1,
    "no-op close keeps an open door owned for safe retry")
testDoor.noopToggle = false
clock = clock + 1
SurvivorCompanion.Navigation.request(doorActor, squares[squareKey(2, 2, 0)], "walk", {})
check(not testDoor.open, "owned door releases only after verified native closure")

local windowFrom = squares[squareKey(3, 2, 0)]
local windowTo = squares[squareKey(4, 2, 0)]
local windowBlockers = {
    squares[squareKey(3, 1, 0)], squares[squareKey(3, 3, 0)], squares[squareKey(2, 2, 0)],
}
for _, blocker in ipairs(windowBlockers) do blocker.solid = true end
local testWindow = { open = false, locked = false, smashed = false, glassRemoved = false }
function testWindow:IsOpen() return self.open end
function testWindow:isLocked() return self.locked end
function testWindow:isSmashed() return self.smashed end
function testWindow:isGlassRemoved() return self.glassRemoved end
function testWindow:isBarricaded() return false end
function testWindow:removeBrokenGlass() if not self.noopRemoveGlass then self.glassRemoved = true end end
function windowFrom:isWindowTo(other) return other == windowTo end
function windowTo:isWindowTo(other) return other == windowFrom end
function windowTo:getWindow(north) if north == false then return testWindow end end
local windowActor = actor("sc-window", 3, 2, {})
registry[windowActor.id] = windowActor
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", { snapshot = { threats = {} } })
check(windowActor.lastIntent.action == "open_window", "safe window route chooses opening over smashing")
clock = clock + 1400
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", { snapshot = { threats = {} } })
clock = clock + 1
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", { snapshot = { threats = {} } })
check(testWindow.open and windowActor.lastIntent.action == "climb_window", "opened window advances to a climb action")

SurvivorCompanion.Navigation.reset(windowActor)
windowActor.square = windowFrom
windowActor.noopOpenWindow = true
testWindow.open, testWindow.smashed, testWindow.glassRemoved = false, false, false
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", { snapshot = { threats = {} } })
clock = clock + 1400
local noOpOpen, noOpOpenReason = SurvivorCompanion.Navigation.request(
    windowActor,
    windowTo,
    "walk",
    { snapshot = { threats = {} } }
)
check(not noOpOpen and noOpOpenReason == "window_open_failed" and not testWindow.open,
    "no-op native window opening fails its authoritative postcondition")

SurvivorCompanion.Navigation.reset(windowActor)
windowActor.noopOpenWindow = false
windowActor.noopSmashWindow = true
testWindow.open, testWindow.smashed, testWindow.glassRemoved = false, false, false
local timedThreat = { x = 6.2, y = 2, z = 0 }
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", {
    snapshot = { threats = { { actor = timedThreat } } },
})
clock = clock + 1000
local noOpSmash, noOpSmashReason = SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", {
    snapshot = { threats = { { actor = timedThreat } } },
})
check(not noOpSmash and noOpSmashReason == "window_smash_failed" and not testWindow.smashed,
    "no-op native window smashing fails its authoritative postcondition")

SurvivorCompanion.Navigation.reset(windowActor)
windowActor.noopSmashWindow = false
testWindow.open, testWindow.smashed, testWindow.glassRemoved = false, true, false
testWindow.noopRemoveGlass = true
SurvivorCompanion.Navigation.request(windowActor, windowTo, "walk", { snapshot = { threats = {} } })
clock = clock + 1500
local noOpGlass, noOpGlassReason = SurvivorCompanion.Navigation.request(
    windowActor,
    windowTo,
    "walk",
    { snapshot = { threats = {} } }
)
check(not noOpGlass and noOpGlassReason == "glass_removal_failed" and not testWindow.glassRemoved,
    "no-op broken-glass removal fails its authoritative postcondition")
testWindow.noopRemoveGlass = false
for _, blocker in ipairs(windowBlockers) do blocker.solid = false end

local orderBefore = fellow.modData.SC_Order
local description = SurvivorCompanion.Commands.describe(fellow.id, player)
check(fellow.modData.SC_Order == orderBefore, "describe must not write command state or mod data")
check(description.id == fellow.id and description.actor == fellow and description.health == 100, "describe core identity and native health")
check(description.supplies.bandages == 1 and description.personality ~= nil, "describe optional UI summaries")
check(type(description.background) == "table" and description.relationshipTier == "cautious"
    and description.mood ~= nil and description.currentNeed ~= nil,
    "describe exposes persistent relationship, mood, need, and background summaries")
local invalidDistance = SurvivorCompanion.Commands.issue(fellow.id, "set_follow_distance", 4, player)
check(not invalidDistance, "invalid follow distance is rejected")
local validDistance = SurvivorCompanion.Commands.issue(fellow.id, "set_follow_distance", 5, player)
check(validDistance and fellow.modData.SC_FollowDistance == 5, "valid follow distance is persisted")

do
    local strongRifle = item("Base.AssaultRifle", "Weapon", {
        ranged = true, damage = 8, range = 15, ammo = 20, maxAmmo = 30,
    })
    local commandAxe = item("Base.Axe", "Weapon", {
        ranged = false, damage = 1.5, range = 1.5,
    })
    local armedCompanion = actor("sc-command-equip", -6, 6, {
        inventory = inventory({ strongRifle, commandAxe }),
    })
    armedCompanion.primary = strongRifle
    registry[armedCompanion.id] = armedCompanion
    local priorityAccepted, priorityReason, priorityDetails = SurvivorCompanion.Commands.issue(
        armedCompanion.id, "set_weapon_priority", { priority = "melee" }, player)
    check(priorityAccepted and priorityReason == "weapon_equipped"
        and type(priorityDetails) == "table" and priorityDetails.weaponName == "Base.Axe"
        and armedCompanion.lastIntent and armedCompanion.lastIntent.action == "equip_weapon"
        and armedCompanion.lastIntent.item == commandAxe
        and armedCompanion.primary == commandAxe
        and SurvivorCompanion.ActionSupervisor.snapshot(armedCompanion).phase == "idle"
        and SurvivorCompanion.ActionSupervisor.reservationCount(armedCompanion) == 0,
        "melee preference immediately equips an available axe instead of retaining a stronger firearm")
    check(SurvivorCompanion.Commands.peek(armedCompanion).weaponPriority == "melee",
        "immediate weapon equip also persists the requested preference")
    SurvivorCompanion.Commands.reset(armedCompanion)
    SurvivorCompanion.Combat.reset(armedCompanion)
    registry[armedCompanion.id] = nil
end

local statusOK = SurvivorCompanion.Commands.issue(fellow.id, "status", nil, player)
check(statusOK and fellow.lastSpeech and SurvivorCompanion.UI.lastStatus.id == fellow.id, "status speaks on the companion and emits readable UI data")
check(SurvivorCompanion.Commands.conversation(fellow.id, "needs", player)
    and SurvivorCompanion.Commands.conversation(fellow.id, "opinion", player),
    "contextual needs and opinion conversations speak successfully")
do
    local doingToken = assert(SurvivorCompanion.ActionSupervisor.begin(fellow, {
        owner = "scavenge", action = "scavenge", targetKey = "shelf:test",
        targetLabel = "grocery shelves", phase = "approaching",
        priority = SurvivorCompanion.ActionSupervisor.Priority.WORK,
    }))
    fellow.lastSpeech, player.lastSpeech = nil, nil
    local doingAccepted, doingSentence = SurvivorCompanion.Commands.conversation(
        fellow.id, "doing", player)
    check(doingAccepted and type(doingSentence) == "string" and #doingSentence > 10
            and fellow.lastSpeech == doingSentence and player.lastSpeech == nil
            and string.find(string.lower(doingSentence), "shel", 1, true) ~= nil,
        "What are you doing reports the supervised target over the selected companion")
    SurvivorCompanion.ActionSupervisor.cancel(fellow, "fixture_done", nil, true)
end
local bondBeforeBackground = SurvivorCompanion.Commands.peek(fellow).bond
check(SurvivorCompanion.Commands.conversation(fellow.id, "background", player)
    and SurvivorCompanion.Commands.peek(fellow).bond > bondBeforeBackground,
    "asking about background reveals one persistent personal detail without a generic health response")
SurvivorCompanion.Commands.peek(fellow).stress = 80
check(SurvivorCompanion.Commands.conversation(fellow.id, "encourage", player)
    and SurvivorCompanion.Commands.peek(fellow).stress < 80,
    "contextual reassurance reduces high stress and persists relationship state")
check(SurvivorCompanion.Commands.noteDowntime(fellow, { activity = "repair" }),
    "useful downtime work is available to the relationship memory")
local bondBeforePraise = SurvivorCompanion.Commands.peek(fellow).bond
check(SurvivorCompanion.Commands.conversation(fellow.id, "praise", player)
    and SurvivorCompanion.Commands.peek(fellow).bond > bondBeforePraise,
    "earned praise acknowledges recent useful work and strengthens the bond")
check(SurvivorCompanion.Commands.conversation(fellow.id, "relationship", player),
    "companion can describe the current relationship tier")
check(SurvivorCompanion.Commands.issue(fellow.id, "emote", { emote = "thankyou" }, player)
    and fellow.lastIntent.emote == "thankyou"
    and not SurvivorCompanion.Commands.issue(fellow.id, "emote", { emote = "ZombieWalk" }, player),
    "direct companion emotes accept only validated human Build 42 emotes")
check(not SurvivorCompanion.Commands.issue(fellow.id, "open_inventory", nil, player),
    "inventory command fails when the dedicated UI adapter does not confirm success")
check(not SurvivorCompanion.Commands.issue(fellow.id, "open_health", nil, player),
    "health command fails when the dedicated UI adapter does not confirm success")
SurvivorCompanion.UI.inventoryResult = true
SurvivorCompanion.UI.healthResult = true
check(SurvivorCompanion.Commands.issue(fellow.id, "open_inventory", nil, player)
    and SurvivorCompanion.Commands.issue(fellow.id, "open_health", nil, player),
    "inventory and health commands accept only explicit dedicated UI success")

local commandReject = actor("sc-command-reject", -6, -1, {})
registry[commandReject.id] = commandReject
commandReject.modData.SC_Order = "follow"
commandReject.rejectMovement = true
local commandSerialBefore = commandReject.modData.SC_CommandSerial
check(not SurvivorCompanion.Commands.issue(commandReject.id, "move_to", {
    square = squares[squareKey(-3, -1, 0)],
}, player) and SurvivorCompanion.Commands.peek(commandReject).order == "follow"
    and commandReject.modData.SC_CommandSerial == commandSerialBefore,
    "rejected ordered movement leaves order and persistence unchanged")
check(not SurvivorCompanion.Commands.issue(commandReject.id, "board_vehicle", { vehicle = {} }, player)
    and SurvivorCompanion.Commands.peek(commandReject).order == "follow",
    "rejected vehicle action is not reported or persisted")
check(not SurvivorCompanion.Commands.issue(commandReject.id, "dismiss", nil, player)
    and SurvivorCompanion.Commands.peek(commandReject).recruited,
    "rejected dismissal restores recruited state exactly")
local livePlayerVehicle = { id = "test-player-vehicle" }
player.vehicle = livePlayerVehicle
check(SurvivorCompanion.Commands.issue(fellow.id, "board_vehicle", nil, player)
    and fellow.lastIntent.vehicle == livePlayerVehicle,
    "individual nil-payload boarding resolves the player's live vehicle")
player.vehicle = nil

local treated, treatmentReason = SurvivorCompanion.Medical.treat(fellow, player, { snapshot = { threats = {}, immediateCount = 0, escapeSquares = { { square = fellow.square } } } })
check(treated and woundedPart.isBandaged and helperBandage.used, "native body part bandaging consumes a real supply")

local lowActor = actor("sc-downed", 6, 0, { body = bodyDamage(10) })
registry[lowActor.id] = lowActor
local becameDowned = SurvivorCompanion.Medical.update(lowActor, player, { snapshot = { threats = {}, immediateCount = 0 } })
check(becameDowned and SurvivorCompanion.Medical.isDowned(lowActor) and lowActor.lastIntent.action == "downed",
    "critical nonzero native health enters an immobile downed state")
lowActor.body.health = 30
local recovered = SurvivorCompanion.Medical.update(lowActor, player, { snapshot = { threats = {}, immediateCount = 0 } })
check(recovered and not SurvivorCompanion.Medical.isDowned(lowActor), "native recovery threshold leaves downed state")

local emergencyPart = bodyPart({ name = "UpperArm_R", isBleeding = true })
local spareShirt = item("Base.Tshirt_White", "Clothing")
local emergencyActor = actor("sc-emergency", 7, 0, {
    body = bodyDamage(60, { emergencyPart }), inventory = inventory({ spareShirt }),
})
registry[emergencyActor.id] = emergencyActor
local emergencyTreated = SurvivorCompanion.Medical.treat(emergencyActor, emergencyActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
})
check(emergencyTreated and emergencyPart.isBandaged and not emergencyActor.inventory:contains(spareShirt),
    "recruited helper tears expendable clothing for an emergency bandage")

do
local glassPart = bodyPart({ name = "Hand_L", glass = true, bullet = false })
local glassActor = actor("sc-glass", 7, 1, { body = bodyDamage(80, { glassPart }) })
local glassAssessment = SurvivorCompanion.Medical.assess(glassActor)
check(glassAssessment.wounds[1].lodged and glassAssessment.wounds[1].glass
    and not glassAssessment.wounds[1].bullet, "glass and bullet flags are assessed independently")
glassActor.body.infected = true
glassActor.body.infectionLevel = 37
check(SurvivorCompanion.Medical.assess(glassActor).infectionLevel == 37,
    "medical assessment uses the B42 apparent infection level")

local rejectedBandage = item("Base.Bandage", "Medical")
local rejectedPart = bodyPart({ name = "Hand_R", isBleeding = true })
local rejectedMedic = actor("sc-medical-reject", 7, 2, {
    body = bodyDamage(70, { rejectedPart }), inventory = inventory({ rejectedBandage }),
})
registry[rejectedMedic.id] = rejectedMedic
rejectedMedic.rejectActions = { kneel_treat = true }
local rejectedTreatment = SurvivorCompanion.Medical.treat(rejectedMedic, rejectedMedic, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
})
check(not rejectedTreatment and not rejectedPart.isBandaged and rejectedBandage.uses == 1,
    "rejected medical action neither mutates the wound nor consumes a bandage")

local failingBandage = item("Base.Bandage", "Medical", { rejectUse = true })
local dirtyPart = bodyPart({
    name = "LowerLeg_L", isBandaged = true, dirty = true, bandageLife = 0,
    bandageType = "Base.DirtyBandage",
})
local rollbackMedic = actor("sc-medical-rollback", 7, 3, {
    body = bodyDamage(70, { dirtyPart }), inventory = inventory({ failingBandage }),
})
registry[rollbackMedic.id] = rollbackMedic
local failedReplacement = SurvivorCompanion.Medical.replaceDirtyBandage(rollbackMedic)
check(not failedReplacement and dirtyPart.isBandaged and dirtyPart.dirty and failingBandage.uses == 1,
    "failed replacement restores the dirty native bandage and keeps the clean supply")

local failedRagPart = bodyPart({ name = "UpperLeg_R", isBleeding = true })
local restoredShirt = item("Base.Tshirt_Black", "Clothing")
local ragInventory = inventory({ restoredShirt })
ragInventory.rejectAddType = "Base.RippedSheets"
local ragFailureActor = actor("sc-rag-failure", 7, 4, {
    body = bodyDamage(70, { failedRagPart }), inventory = ragInventory,
})
registry[ragFailureActor.id] = ragFailureActor
check(not SurvivorCompanion.Medical.treat(ragFailureActor, ragFailureActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
}) and ragInventory:contains(restoredShirt), "failed rag creation restores the original clothing")

local wornPart = bodyPart({ name = "Torso_Upper", isBleeding = true })
local wornShirt = item("Base.Tshirt_DefaultTEXTURE_TINT", "Clothing")
local wornActor = actor("sc-worn-clothing", 7, 5, {
    body = bodyDamage(70, { wornPart }), inventory = inventory({ wornShirt }),
})
wornActor.equippedClothing = { [wornShirt] = true }
registry[wornActor.id] = wornActor
check(SurvivorCompanion.Medical.treat(wornActor, wornActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
}) and not wornActor.inventory:contains(wornShirt) and not wornActor:isEquippedClothing(wornShirt),
    "recruited companion may transactionally tear whitelisted nonessential worn clothing")

local wornRollbackPart = bodyPart({ name = "Torso_Lower", isBleeding = true })
local wornRollbackShirt = item("Base.Tshirt_IndieStoneDECAL", "Clothing", { bodyLocation = "Torso1Legs1" })
local wornRollbackInventory = inventory({ wornRollbackShirt })
wornRollbackInventory.rejectAddType = "Base.RippedSheets"
local wornRollbackActor = actor("sc-worn-rollback", 7, 6, {
    body = bodyDamage(70, { wornRollbackPart }), inventory = wornRollbackInventory,
})
wornRollbackActor.equippedClothing = { [wornRollbackShirt] = true }
registry[wornRollbackActor.id] = wornRollbackActor
check(not SurvivorCompanion.Medical.treat(wornRollbackActor, wornRollbackActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
}) and wornRollbackInventory:contains(wornRollbackShirt)
    and wornRollbackActor:isEquippedClothing(wornRollbackShirt),
    "failed rag creation restores a worn item to its verified body location")

local protectivePart = bodyPart({ name = "Neck", isBleeding = true })
local protectiveCoat = item("Base.Coat_Long", "Clothing", { bodyLocation = "Jacket" })
local protectiveActor = actor("sc-protective-worn", 7, 7, {
    body = bodyDamage(70, { protectivePart }), inventory = inventory({ protectiveCoat }),
})
protectiveActor.equippedClothing = { [protectiveCoat] = true }
registry[protectiveActor.id] = protectiveActor
check(not SurvivorCompanion.Medical.treat(protectiveActor, protectiveActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
}) and protectiveActor.inventory:contains(protectiveCoat)
    and protectiveActor:isEquippedClothing(protectiveCoat),
    "protective worn clothing remains outside the emergency tear whitelist")

local neutralWornPart = bodyPart({ name = "UpperArm_L", isBleeding = true })
local neutralWornShirt = item("Base.Tshirt_WhiteLongSleeve", "Clothing")
local neutralWornActor = actor("sc-neutral-worn", 8, 7, {
    recruited = false,
    body = bodyDamage(70, { neutralWornPart }),
    inventory = inventory({ neutralWornShirt }),
})
neutralWornActor.modData.SC_Recruited = false
neutralWornActor.equippedClothing = { [neutralWornShirt] = true }
registry[neutralWornActor.id] = neutralWornActor
local originalCompanionCheck = SurvivorCompanion.Actor.isCompanion
SurvivorCompanion.Actor.isCompanion = function(value)
    if value == neutralWornActor then return true end
    return originalCompanionCheck(value)
end
local neutralWornTreatment = SurvivorCompanion.Medical.treat(neutralWornActor, neutralWornActor, {
    snapshot = { threats = {}, immediateCount = 0, escapeSquares = {} },
})
SurvivorCompanion.Actor.isCompanion = originalCompanionCheck
check(not neutralWornTreatment and neutralWornActor.inventory:contains(neutralWornShirt)
    and neutralWornActor:isEquippedClothing(neutralWornShirt),
    "registered neutral cannot tear worn clothing without recruited team state")
end

do
local originalNativeActions = SurvivorCompanion.NativeActions
local originalActorMovement = SurvivorCompanion.Actor.setMovement
local visualStates = setmetatable({}, { __mode = "k" })
local pacingRecords = setmetatable({}, { __mode = "k" })
local resultNotes = {}
SurvivorCompanion.NativeActions = {
    visualStatus = function(value, expected)
        local current = visualStates[value]
        if not current then return "none" end
        if expected and current.action ~= expected then return "different", current.action end
        return current.status, current.action
    end,
    clearVisual = function(value) visualStates[value] = nil return true end,
    cancelVisual = function(value) visualStates[value] = nil return true end,
    noteResult = function(value, source, result, options)
        resultNotes[#resultNotes + 1] = { actor = value, source = source, result = result }
        return true, "pacing_started"
    end,
    activityStatus = function() return "none" end,
    pacingStatus = function(value)
        local current = pacingRecords[value]
        return current ~= nil, current
    end,
    cancelPacing = function(value, reason)
        pacingRecords[value] = nil
        return true, reason
    end,
    stopDirect = function(value)
        value.stopped = true
        value.moving = false
        return true
    end,
}
SurvivorCompanion.Actor.setMovement = function(value, mode, intent)
    local accepted, reason = originalActorMovement(value, mode, intent)
    if accepted and intent and (intent.action == "kneel_treat"
        or intent.action == "replace_bandage"
        or intent.action == "rip_clothing_for_bandage"
        or intent.action == "read" or intent.action == "repair"
        or intent.action == "craft_supply" or intent.action == "wash_self"
        or intent.action == "wash_equipment" or intent.action == "wear_clothing"
        or intent.action == "loot_container") then
        visualStates[value] = { action = intent.action, status = "active" }
    end
    return accepted, reason
end

local stagedPart = bodyPart({ name = "ForeArm_R", isBleeding = true })
local stagedBandage = item("Base.Bandage", "Medical")
local stagedMedic = actor("sc-staged-medical", 9, 7, {
    body = bodyDamage(75, { stagedPart }), inventory = inventory({ stagedBandage }),
})
local stagedStarted, stagedStartReason = SurvivorCompanion.Medical.treat(
    stagedMedic, stagedMedic, { snapshot = { threats = {}, immediateCount = 0 } })
check(stagedStarted and stagedStartReason == "treatment_animation_started"
        and not stagedPart.isBandaged and not stagedBandage.used,
    "medical effects remain unchanged while the verified bandage animation is active")
local stagedActive, stagedActiveReason = SurvivorCompanion.Medical.treat(
    stagedMedic, stagedMedic, {})
check(stagedActive and stagedActiveReason == "treatment_animation_active"
        and not stagedPart.isBandaged and not stagedBandage.used,
    "polling an active treatment cannot commit its result early")
visualStates[stagedMedic].status = "completed"
local stagedFinished, stagedFinishReason = SurvivorCompanion.Medical.treat(
    stagedMedic, stagedMedic, {})
check(stagedFinished and stagedFinishReason == "bandaged"
        and stagedPart.isBandaged and stagedBandage.used
        and resultNotes[#resultNotes].source == "medical_treatment",
    "completed medical animation commits and verifies exactly one bandage result")

local unavailableDirtyPart = bodyPart({
    name = "LowerLeg_R", isBandaged = true, dirty = true, bandageLife = 0,
    bandageType = "Base.DirtyBandage",
})
local unavailableDirtyActor = actor("sc-dirty-no-supply", 9, 4, {
    body = bodyDamage(80, { unavailableDirtyPart }), inventory = inventory({}),
})
unavailableDirtyActor.square.room = { name = "safe_room" }
unavailableDirtyActor.modData.SC_Order = "stay"
unavailableDirtyActor.modData.SC_WorkMode = "idle"
local replacementReady, replacementReason =
    SurvivorCompanion.Medical.canReplaceDirtyBandage(unavailableDirtyActor)
check(not replacementReady and replacementReason == "no_clean_bandage",
    "dirty-bandage capability probe rejects work before animation when no supply exists")
SurvivorCompanion.Downtime.reset(unavailableDirtyActor)
local unavailableDowntime = SurvivorCompanion.Downtime.update(
    unavailableDirtyActor, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
            player = { danger = 0 }, indoors = true },
    }, "replace_bandage")
check(not unavailableDowntime
        and SurvivorCompanion.Downtime.peek(unavailableDirtyActor).active == nil
        and SurvivorCompanion.Medical.peek(unavailableDirtyActor) == nil
        and visualStates[unavailableDirtyActor] == nil,
    "downtime cannot create a duplicate dirty-bandage visual without a clean supply")

local ownedDirtyPart = bodyPart({
    name = "UpperLeg_L", isBandaged = true, dirty = true, bandageLife = 0,
    bandageType = "Base.DirtyBandage",
})
local ownedCleanBandage = item("Base.Bandage", "Medical")
local ownedDirtyActor = actor("sc-dirty-medical-owner", 9, 3, {
    body = bodyDamage(80, { ownedDirtyPart }),
    inventory = inventory({ ownedCleanBandage }),
})
ownedDirtyActor.square.room = { name = "safe_room" }
ownedDirtyActor.modData.SC_Order = "stay"
ownedDirtyActor.modData.SC_WorkMode = "idle"
SurvivorCompanion.Downtime.reset(ownedDirtyActor)
local ownedReplacement, ownedReplacementReason = SurvivorCompanion.Downtime.update(
    ownedDirtyActor, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
            player = { danger = 0 }, indoors = true },
    }, "replace_bandage")
local ownedSupervisor = SurvivorCompanion.ActionSupervisor.snapshot(ownedDirtyActor)
check(ownedReplacement and ownedReplacementReason == "treatment_animation_started"
        and SurvivorCompanion.Downtime.peek(ownedDirtyActor).active == nil
        and SurvivorCompanion.Medical.peek(ownedDirtyActor) ~= nil
        and ownedSupervisor.owner == "medical"
        and ownedSupervisor.action == "replace_dirty_bandage",
    "Medical exclusively owns a dirty-bandage action proposed by downtime")
visualStates[ownedDirtyActor].status = "completed"
local ownedFinished, ownedFinishedReason = SurvivorCompanion.Downtime.update(
    ownedDirtyActor, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
            player = { danger = 0 }, indoors = true },
    }, "replace_bandage")
check(ownedFinished and ownedFinishedReason == "bandaged"
        and ownedDirtyPart.isBandaged and not ownedDirtyPart.dirty
        and ownedCleanBandage.used
        and SurvivorCompanion.ActionSupervisor.snapshot(ownedDirtyActor).phase == "idle",
    "Medical completes and verifies the sole dirty-bandage transaction")

local interruptedPart = bodyPart({ name = "Hand_L", isBleeding = true })
local interruptedBandage = item("Base.Bandage", "Medical")
local interruptedMedic = actor("sc-interrupted-medical", 9, 6, {
    body = bodyDamage(75, { interruptedPart }),
    inventory = inventory({ interruptedBandage }),
})
check(SurvivorCompanion.Medical.treat(interruptedMedic, interruptedMedic, {}),
    "interruption regression starts a tracked medical action")
visualStates[interruptedMedic].status = "stopped"
local interruptedResult = SurvivorCompanion.Medical.treat(
    interruptedMedic, interruptedMedic, {})
check(not interruptedResult and not interruptedPart.isBandaged
        and interruptedBandage.uses == 1,
    "an interrupted bandage animation changes neither body state nor inventory")

local stagedRagPart = bodyPart({ name = "UpperArm_L", isBleeding = true })
local stagedShirt = item("Base.Tshirt_White", "Clothing")
local stagedRagMedic = actor("sc-staged-rag", 9, 5, {
    body = bodyDamage(75, { stagedRagPart }), inventory = inventory({ stagedShirt }),
})
check(SurvivorCompanion.Medical.treat(stagedRagMedic, stagedRagMedic, {})
        and stagedRagMedic.inventory:contains(stagedShirt)
        and not stagedRagMedic.inventory:contains("Base.RippedSheets"),
    "clothing stays intact until the rip animation completes")
visualStates[stagedRagMedic].status = "completed"
local ripFinished, ripReason = SurvivorCompanion.Medical.treat(
    stagedRagMedic, stagedRagMedic, {})
check(ripFinished and ripReason == "treatment_animation_started"
        and not stagedRagMedic.inventory:contains(stagedShirt)
        and stagedRagMedic.inventory:contains("Base.RippedSheets")
        and not stagedRagPart.isBandaged,
    "completed ripping commits the rag then chains into a separate treatment animation")
visualStates[stagedRagMedic].status = "stopped"
local ragInterrupted = SurvivorCompanion.Medical.treat(
    stagedRagMedic, stagedRagMedic, {})
check(not ragInterrupted and stagedRagMedic.inventory:contains(stagedShirt)
        and not stagedRagMedic.inventory:contains("Base.RippedSheets")
        and not stagedRagPart.isBandaged,
    "interrupting chained treatment rolls emergency clothing conversion back exactly")

local stagedBook = item("Base.BookStaged", "Literature", { pages = 180 })
local stagedReader = actor("sc-staged-reader", 8, 4,
    { inventory = inventory({ stagedBook }) })
stagedReader.square.room = { name = "safe_room" }
stagedReader.modData.SC_Order = "stay"
stagedReader.modData.SC_WorkMode = "idle"
SurvivorCompanion.Downtime.reset(stagedReader)
local stagedReadStarted = SurvivorCompanion.Downtime.update(stagedReader, player,
    { snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        player = { danger = 0 }, indoors = true } }, "read")
check(stagedReadStarted and SurvivorCompanion.Downtime.peek(stagedReader).lastFact == nil,
    "downtime does not record a result when its visual action merely starts")
local stagedReadActive = SurvivorCompanion.Downtime.update(stagedReader, player,
    { snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        player = { danger = 0 }, indoors = true } }, "read")
check(stagedReadActive and SurvivorCompanion.Downtime.peek(stagedReader).lastFact == nil,
    "active downtime animation remains result-free regardless of wall-clock duration")
visualStates[stagedReader].status = "completed"
local stagedReadFinished = SurvivorCompanion.Downtime.update(stagedReader, player,
    { snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        player = { danger = 0 }, indoors = true } }, "read")
check(stagedReadFinished
        and SurvivorCompanion.Downtime.peek(stagedReader).lastFact.activity == "read",
    "downtime records its result only after verified animation completion")

local stagedVestInventory = inventory()
stagedVestInventory.capacity = 16
local stagedBag = item("Base.Bag_Schoolbag", "Container", {
    nestedInventory = stagedVestInventory, bagCapacity = 16,
    weightReduction = 70, bodyLocation = "Back", equipLocation = "Back",
})
local stagedVest = item("Base.Vest_BulletCivilian", "Item", {
    __class = "Clothing", bodyLocation = "TorsoExtraVest", condition = 10,
    conditionMax = 10, biteDefense = 30, scratchDefense = 40,
    bulletDefense = 100, weight = 2,
})
stagedVestInventory:AddItem(stagedVest)
local stagedWearer = actor("sc-staged-wearable", 8, 3,
    { inventory = inventory({ stagedBag }) })
stagedWearer:setWornItem("Back", stagedBag)
SurvivorCompanion.Logistics.reset(stagedWearer)
local stagedWearStarted = SurvivorCompanion.Logistics.update(stagedWearer, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(stagedWearStarted and stagedVestInventory:contains(stagedVest)
        and stagedWearer:getWornItem("TorsoExtraVest") == nil,
    "wearable inventory and clothing state wait for the native wear animation")
visualStates[stagedWearer].status = "completed"
local stagedWearFinished = SurvivorCompanion.Logistics.update(stagedWearer, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(stagedWearFinished and not stagedVestInventory:contains(stagedVest)
        and stagedWearer:getWornItem("TorsoExtraVest") == stagedVest,
    "completed wear animation commits the verified equipment upgrade")

player.sneaking, player.running, player.sprinting = true, false, false
check(SurvivorCompanion.Positioning.resolveMoveMode("copy", player) == "sneak",
    "Copy player resolves crouched player movement to companion sneak")
player.sneaking, player.running = false, true
check(SurvivorCompanion.Positioning.resolveMoveMode("copy", player) == "jog",
    "Copy player resolves a running player to companion run")
player.running = false
check(SurvivorCompanion.Positioning.resolveMoveMode("copy", player) == "walk",
    "Copy player resolves ordinary player travel to walk")

local pacingLeader = actor("sc-pacing-leader", 40, 40, { recruited = false })
local pacingActor = actor("sc-pacing-actor", 41, 40)
local pacingCommands = SurvivorCompanion.Commands.peek(pacingActor)
pacingRecords[pacingActor] = {
    commandSerial = pacingCommands.commandSerial, untilAt = clock + 1200,
    shouldLook = false, stopped = false, source = "verified_test",
}
local originalNavigationRequest = SurvivorCompanion.Navigation.request
local pacingPathCalls = 0
SurvivorCompanion.Navigation.request = function(...)
    pacingPathCalls = pacingPathCalls + 1
    return originalNavigationRequest(...)
end
local pacedDecision, pacedReason = SurvivorCompanion.Decision.update(
    pacingActor, pacingLeader, {
        snapshot = { threats = {}, immediateAttackers = {}, escapeSquares = {},
            allies = {}, threatCount = 0, immediateCount = 0, pressure = 0,
            player = { danger = 0 } },
    })
SurvivorCompanion.Navigation.request = originalNavigationRequest
check(pacedDecision and pacedReason == "thinking" and pacingPathCalls == 0
        and pacingActor.stopped,
    "human pacing suppresses repeated path requests while preserving a stopped thinking pose")

SurvivorCompanion.Medical.reset(stagedMedic)
SurvivorCompanion.Medical.reset(interruptedMedic)
SurvivorCompanion.Medical.reset(stagedRagMedic)
SurvivorCompanion.Downtime.reset(stagedReader)
SurvivorCompanion.Logistics.reset(stagedWearer)
SurvivorCompanion.Decision.reset(pacingActor)
SurvivorCompanion.Actor.setMovement = originalActorMovement
SurvivorCompanion.NativeActions = originalNativeActions
end

movementLog = {}
local combatRuntime = { snapshot = snapshot }
local fought, combatAction = SurvivorCompanion.Combat.update(fellow, player, combatRuntime)
check(fought and fellow.lastIntent and (fellow.lastIntent.action == "shove" or fellow.lastIntent.action == "attack_melee"), "combat selects a close self-preservation action")

do
local stompStartClock = clock
local stompActor = actor("sc-shove-stomp", 8, -7, { inventory = inventory() })
local stompZed = zombie(9, -7, { attacking = true, target = stompActor })
registry[stompActor.id] = stompActor
local stompSnapshot = {
    threats = { { actor = stompZed, square = stompZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true, score = 90 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 1,
    closeImmediateCount = 1, pressure = 1, encircled = false,
    player = { danger = 0, immediateThreats = 0 },
}
local shoved = SurvivorCompanion.Combat.update(
    stompActor, player, { snapshot = stompSnapshot })
check(shoved and stompActor.lastIntent and stompActor.lastIntent.action == "shove",
    "an unarmed companion shoves a single close zombie")
clock = clock + 350
stompZed.onFloor = true
local stomped, stompReason = SurvivorCompanion.Combat.update(
    stompActor, player, { snapshot = stompSnapshot })
check(stomped and stompReason == "stomp_after_shove"
        and stompActor.lastIntent.action == "stomp"
        and stompActor.lastIntent.target == stompZed
        and stompActor.lastIntent.shoveFollowUp == true,
    "a safe companion stomps the zombie it just knocked to the floor")
SurvivorCompanion.Combat.reset(stompActor)
registry[stompActor.id] = nil
stompZed.dead = true
clock = stompStartClock
end

do
local barkStartClock = clock
local barkConfig = SurvivorCompanion.Config.values
local savedActorGap = barkConfig.combatBarkActorGapMs
local savedGroupGap = barkConfig.combatBarkGroupGapMs
local savedStruggleDelay = barkConfig.combatBarkStruggleDelayMs
local savedStruggleActions = barkConfig.combatBarkStruggleActionCount
barkConfig.combatBarkActorGapMs = 0
barkConfig.combatBarkGroupGapMs = 0
barkConfig.combatBarkStruggleDelayMs = 500
barkConfig.combatBarkStruggleActionCount = 4
SurvivorCompanion.Combat.reset()
local barkBat = item("Base.Axe", "Weapon", { damage = 1.6, range = 1.5 })
local barkActor = actor("sc-combat-barks", 5, -7, { inventory = inventory({ barkBat }) })
barkActor.primary = barkBat
registry[barkActor.id] = barkActor
local barkZed = zombie(6, -7, { attacking = true, target = barkActor })
local barkSnapshot = {
    threats = { { actor = barkZed, square = barkZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true, score = 90 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 1,
    closeImmediateCount = 1, pressure = 1, encircled = false,
    player = { danger = 0, immediateThreats = 0 },
}
local soundsBeforeBarks = worldSoundCount
local barkFought = SurvivorCompanion.Combat.update(
    barkActor, player, { snapshot = barkSnapshot })
local engageLine = barkActor.lastSpeech
local barkState = SurvivorCompanion.Combat.peek(barkActor)
check(barkFought and type(engageLine) == "string"
        and barkState.combatBarkAt["combat.engage"] == clock
        and SurvivorCompanion.Dialogue.lastSpokenTopic(barkActor) == "combat.engage.one"
        and SurvivorCompanion.Dialogue.lastSpokenAt(barkActor) == clock
        and worldSoundCount == soundsBeforeBarks + 1,
    "the first accepted offensive action emits one audible engage bark from the companion")
clock = clock + 50
barkZed.dead = true
local killObserved, killObserveReason = SurvivorCompanion.Combat.observe(barkActor)
check(killObserved and killObserveReason == "recent_kill_confirmed"
        and barkActor.lastSpeech ~= engageLine
        and SurvivorCompanion.Combat.peek(barkActor).combatBarkAt["combat.kill"] == clock
        and worldSoundCount == soundsBeforeBarks + 2,
    "the ordinary AI observer emits one credited kill bark after Senses drops the dead target")

local struggleZed = zombie(6, -7, { attacking = true, target = barkActor })
barkSnapshot.threats[1].actor = struggleZed
barkSnapshot.threats[1].square = struggleZed.square
local killLine = barkActor.lastSpeech
for index = 1, 4 do
    if index > 1 then clock = clock + 350 end
    SurvivorCompanion.Combat.update(barkActor, player, { snapshot = barkSnapshot })
end
barkState = SurvivorCompanion.Combat.peek(barkActor)
check(barkState.engagementActionCount >= 4
        and barkState.combatBarkAt["combat.struggle"] == clock
        and barkActor.lastSpeech ~= killLine
        and worldSoundCount == soundsBeforeBarks + 3,
    "sustained work against the same living target emits one delayed struggle bark")
local struggleLine = barkActor.lastSpeech
clock = clock + 350
SurvivorCompanion.Combat.update(barkActor, player, { snapshot = barkSnapshot })
check(barkActor.lastSpeech == struggleLine and worldSoundCount == soundsBeforeBarks + 3,
    "the same combat episode cannot repeat its struggle bark every decision tick")

struggleZed.dead = true
registry[barkActor.id] = nil
SurvivorCompanion.Dialogue.reset(barkActor)
SurvivorCompanion.Combat.reset()
barkConfig.combatBarkActorGapMs = savedActorGap
barkConfig.combatBarkGroupGapMs = savedGroupGap
barkConfig.combatBarkStruggleDelayMs = savedStruggleDelay
barkConfig.combatBarkStruggleActionCount = savedStruggleActions
clock = barkStartClock
end

local rejectBat = item("Base.Crowbar", "Weapon", { damage = 1.2, range = 1.5 })
local rejectFighter = actor("sc-combat-reject", -1, -7, { inventory = inventory({ rejectBat }) })
rejectFighter.primary = rejectBat
rejectFighter.rejectMovement = true
registry[rejectFighter.id] = rejectFighter
local rejectZed = zombie(0, -7, { attacking = true, target = rejectFighter })
local rejectCombatSnapshot = {
    threats = { { actor = rejectZed, square = rejectZed.square, distanceSq = 1, visible = true, obstructed = false, attacking = true, score = 80 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 1, pressure = 1.5,
    player = { danger = 0, immediateThreats = 0 },
}
check(not SurvivorCompanion.Combat.update(rejectFighter, player, { snapshot = rejectCombatSnapshot })
    and not SurvivorCompanion.Combat.peek(rejectFighter).active,
    "combat does not claim an action when the Actor executor rejects it")

do
local overrunBat = item("Base.Axe", "Weapon", { damage = 1.5, range = 1.5 })
local overrunActor = actor("sc-overrun", -4, -5, { inventory = inventory({ overrunBat }) })
overrunActor.primary = overrunBat
registry[overrunActor.id] = overrunActor
local overrunZedEast = zombie(-3, -5, { attacking = true, target = overrunActor })
local overrunZedWest = zombie(-5, -5, { attacking = true, target = overrunActor })
local overrunZedNorth = zombie(-4, -6, { attacking = true, target = overrunActor })
local overrunSnapshot = {
    threats = {
        { actor = overrunZedEast, square = overrunZedEast.square, distanceSq = 1, visible = true, attacking = true, score = 90 },
        { actor = overrunZedWest, square = overrunZedWest.square, distanceSq = 1, visible = true, attacking = true, score = 89 },
        { actor = overrunZedNorth, square = overrunZedNorth.square, distanceSq = 1, visible = true, attacking = true, score = 88 },
    },
    immediateAttackers = {}, allies = {}, threatCount = 3, immediateCount = 3,
    closeThreatCount = 3, occupiedThreatSectors = 3, pressure = 4.5, directionalPressure = 7.2,
    encircled = true,
    escapeSquares = { { square = squares[squareKey(-4, -4, 0)], danger = 0, score = 20 } },
    player = { available = false, danger = 0, immediateThreats = 0 },
}
local overrunAssessment = SurvivorCompanion.Combat.assessOverrun(overrunActor, overrunSnapshot, nil, {
    combatMode = "aggressive",
})
check(overrunAssessment.overrun and overrunAssessment.occupiedSectors == 3,
    "three-sided close pressure crosses the self-preservation threshold even in aggressive mode")
local distantAttackers = SurvivorCompanion.Combat.assessOverrun(overrunActor, {
    immediateCount = 3, closeThreatCount = 0, closeImmediateCount = 0,
    directionalPressure = 0, occupiedThreatSectors = 0, escapeSquares = { { square = overrunActor.square } },
    allies = {}, player = { available = false },
}, nil, { combatMode = "defensive" })
check(not distantAttackers.overrun,
    "targeting zombies outside the close-threat radius do not masquerade as a surrounding grab group")
SurvivorCompanion.Combat.reset()
local soundsBeforeRetreatBark = worldSoundCount
local overrunHandled, overrunAction = SurvivorCompanion.Combat.update(overrunActor, player, {
    snapshot = overrunSnapshot,
})
check(overrunHandled and overrunAction == "overrun_retreat"
    and overrunActor.lastIntent.action == "combat_retreat"
    and overrunActor.lastIntent.survivalCritical == true
    and overrunActor.lastIntent.tacticalRetreat ~= true
    and overrunActor.lastIntent.weaponReady == false,
    "an outnumbered companion breaks contact instead of continuing a doomed attack")
local retreatLine = overrunActor.lastSpeech
check(type(retreatLine) == "string"
        and SurvivorCompanion.Combat.peek(overrunActor).combatBarkAt["combat.retreat"] == clock
        and SurvivorCompanion.Dialogue.lastSpokenTopic(overrunActor) == "combat.retreat.group"
        and worldSoundCount == soundsBeforeRetreatBark + 1,
    "entering a survival-critical retreat emits one audible fall-back bark")
clock = clock + 100
SurvivorCompanion.Combat.update(overrunActor, player, { snapshot = overrunSnapshot })
check(overrunActor.lastSpeech == retreatLine and worldSoundCount == soundsBeforeRetreatBark + 1,
    "continuing the same retreat episode does not repeat the fall-back bark")
local fallbackOverrunActor = actor("sc-overrun-native-fallback", -4, -5, {
    inventory = inventory({ overrunBat }),
})
fallbackOverrunActor.primary = overrunBat
registry[fallbackOverrunActor.id] = fallbackOverrunActor
local savedNavigation = SurvivorCompanion.Navigation
SurvivorCompanion.Navigation = nil
local fallbackHandled = SurvivorCompanion.Combat.update(fallbackOverrunActor, player, {
    snapshot = overrunSnapshot,
})
SurvivorCompanion.Navigation = savedNavigation
check(fallbackHandled and fallbackOverrunActor.lastIntent
        and fallbackOverrunActor.lastIntent.action == "combat_retreat"
        and fallbackOverrunActor.lastIntent.enginePath == true
        and fallbackOverrunActor.lastIntent.targetSquare == overrunSnapshot.escapeSquares[1].square,
    "combat escape keeps a concrete native destination when the Lua navigator is unavailable")
SurvivorCompanion.Combat.reset(fallbackOverrunActor)
registry[fallbackOverrunActor.id] = nil
overrunZedEast.dead, overrunZedWest.dead, overrunZedNorth.dead = true, true, true
registry[overrunActor.id] = nil
end

do
local tacticalBat = item("Base.BaseballBat", "Weapon", {
    damage = 1.4, range = 1.55, weight = 2.0, enduranceMod = 1,
    weaponCategories = { "Blunt" },
})
local readyActor = actor("sc-ready-fighter", -7, 4, { inventory = inventory({ tacticalBat }) })
readyActor.primary = tacticalBat
readyActor.endurance = 0.92
readyActor.perks = { Strength = 7, Fitness = 7, Nimble = 5, Blunt = 6 }
local readyCommands = SurvivorCompanion.Commands.peek(readyActor)
readyCommands.stress, readyCommands.morale = 8, 72
local frontZed = zombie(-7, 3, { attacking = true, target = readyActor })
local readySnapshot = {
    threats = { { actor = frontZed, square = frontZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true } },
    immediateAttackers = { frontZed }, allies = {}, threatCount = 1,
    immediateCount = 1, closeImmediateCount = 1, closeThreatCount = 1,
    occupiedThreatSectors = 1, directionalPressure = 1.8, pressure = 1,
    escapeSquares = { { square = squares[squareKey(-7, 5, 0)], danger = 0,
        nearestThreatSq = 4 } },
    player = { available = false, danger = 0, immediateThreats = 0 },
}
local readyProfile = SurvivorCompanion.Combat.readiness(
    readyActor, readySnapshot, nil, readyCommands)

local spentAxe = item("Base.WoodAxe", "Weapon", {
    damage = 2.2, range = 1.6, weight = 4.0, enduranceMod = 1.4,
    twoHanded = true, weaponCategories = { "Axe" }, condition = 2, conditionMax = 10,
})
local spentActor = actor("sc-spent-fighter", -5, 4, { inventory = inventory({ spentAxe }) })
spentActor.primary = spentAxe
spentActor.endurance = 0.08
spentActor.moodles = { PANIC = 3, PAIN = 2, TIRED = 2, HEAVY_LOAD = 2 }
spentActor.perks = { Strength = 3, Fitness = 2, Nimble = 1, Axe = 1 }
local spentCommands = SurvivorCompanion.Commands.peek(spentActor)
spentCommands.stress, spentCommands.morale = 82, 28
local spentZed = zombie(-5, 3, { attacking = true, target = spentActor })
local spentSnapshot = {
    threats = { { actor = spentZed, square = spentZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true } },
    immediateAttackers = { spentZed }, allies = {}, threatCount = 1,
    immediateCount = 1, closeImmediateCount = 1, closeThreatCount = 1,
    occupiedThreatSectors = 1, directionalPressure = 1.8, pressure = 1,
    escapeSquares = { { square = squares[squareKey(-5, 5, 0)], danger = 0,
        nearestThreatSq = 4 } },
    player = { available = false, danger = 0, immediateThreats = 0 },
}
local spentWeapon = {
    item = spentAxe, type = spentAxe:getFullType(), ranged = false,
    conditionRatio = 0.2, sharpness = 1, weight = 4,
    staminaCost = 4 * 1.4 * 1.08, damage = 2.2, range = 1.6,
}
local spentProfile = SurvivorCompanion.Combat.readiness(
    spentActor, spentSnapshot, spentWeapon, spentCommands)
check(readyProfile.confidence > spentProfile.confidence
        and not readyProfile.staminaCritical and spentProfile.staminaCritical
        and spentProfile.enduranceReserve > readyProfile.enduranceReserve,
    "combat readiness combines skill and morale with panic, load, wounds, weapon cost and stamina")
local spentAssessment = SurvivorCompanion.Combat.assessOverrun(
    spentActor, spentSnapshot, spentWeapon, spentCommands)
check(spentAssessment.overrun and spentAssessment.staminaCritical,
    "a spent fighter preserves enough endurance to disengage before a final swing traps them")
registry[spentActor.id] = spentActor
local spentHandled, spentReason = SurvivorCompanion.Combat.update(
    spentActor, player, { snapshot = spentSnapshot })
check(spentHandled and spentReason == "overrun_retreat"
        and spentActor.lastIntent.action == "combat_retreat",
    "critical internal condition overrides an otherwise manageable one-zombie fight")

local rearZed = zombie(-7, 5, { attacking = false })
local bearingScores = SurvivorCompanion.Combat.scoreTargets(readyActor, player, {
    threats = {
        { actor = frontZed, square = frontZed.square, distanceSq = 1,
            visible = true, obstructed = false, attacking = false },
        { actor = rearZed, square = rearZed.square, distanceSq = 1,
            visible = true, obstructed = false, attacking = false },
    },
    allies = {},
}, nil)
check(bearingScores[1].actor == rearZed and bearingScores[1].bearing == "rear",
    "combat turns on an equally close rear threat before continuing a frontal exchange")

local claimActor = actor("sc-claim-fighter", 8, 6, { inventory = inventory({ tacticalBat }) })
claimActor.primary = tacticalBat
local claimZedA = zombie(9, 6, { attacking = true, target = claimActor })
local claimZedB = zombie(8, 5, { attacking = true, target = claimActor })
local claimSnapshot = {
    threats = {
        { actor = claimZedA, square = claimZedA.square, distanceSq = 1,
            visible = true, obstructed = false, attacking = true },
        { actor = claimZedB, square = claimZedB.square, distanceSq = 1,
            visible = true, obstructed = false, attacking = true },
    },
    immediateAttackers = {}, allies = {}, threatCount = 2, immediateCount = 0,
    closeImmediateCount = 0, closeThreatCount = 2, occupiedThreatSectors = 2,
    directionalPressure = 1, pressure = 0.5,
    escapeSquares = { { square = squares[squareKey(7, 6, 0)], danger = 0,
        nearestThreatSq = 4 } },
    player = { available = false, danger = 0, immediateThreats = 0 },
}
SurvivorCompanion.Combat.update(claimActor, player, { snapshot = claimSnapshot })
local wingActor = actor("sc-wing-fighter", 8, 7, { inventory = inventory({ tacticalBat }) })
local splitScores = SurvivorCompanion.Combat.scoreTargets(
    wingActor, player, claimSnapshot, nil)
check(#splitScores == 2 and splitScores[1].claimedByAlly ~= true,
    "a squad fighter prefers an unclaimed zombie instead of dogpiling one target")

frontZed.dead, spentZed.dead, rearZed.dead = true, true, true
claimZedA.dead, claimZedB.dead = true, true
registry[spentActor.id] = nil
SurvivorCompanion.Combat.reset(readyActor)
SurvivorCompanion.Combat.reset(spentActor)
SurvivorCompanion.Combat.reset(claimActor)
SurvivorCompanion.Combat.reset(wingActor)
end

local upperZed = zombie(1, 0, { z = 1, attacking = true, target = fellow })
local upperScored = SurvivorCompanion.Combat.scoreTargets(fellow, player, {
    threats = { { actor = upperZed, square = upperZed.square, distanceSq = 1, visible = true, score = 999 } },
}, nil)
check(#upperScored == 0, "combat target selection excludes threats on another floor")

local rifle = item("Base.HuntingRifle", "Weapon", { ranged = true, damage = 2, range = 12, ammo = 3, maxAmmo = 5, condition = 10, conditionMax = 10 })
local shooter = actor("sc-shooter", 0, -3, { inventory = inventory({ rifle }) })
shooter.primary = rifle
registry[shooter.id] = shooter
local lineFriendly = actor("line-player", 2, -3, { className = "IsoPlayer", recruited = false })
lineFriendly.modData.SC_Recruited = false
local distantZed = zombie(4, -3, {})
local shotSnapshot = {
    threats = { { actor = distantZed, square = distantZed.square, distanceSq = 16, visible = true, obstructed = false, attacking = false, score = 30 } },
    allies = {}, escapeSquares = { { square = squares[squareKey(-1, -3, 0)], score = 5 } },
    threatCount = 1, immediateCount = 0, pressure = 0, player = { danger = 0, immediateThreats = 0 },
}
local shotHandled = SurvivorCompanion.Combat.update(shooter, lineFriendly, { snapshot = shotSnapshot })
check(shotHandled and shooter.lastIntent.action ~= "attack_firearm", "friendly fire corridor blocks a shot through the player")
local upperFriendly = actor("upper-player", 2, -3, { z = 1, className = "IsoPlayer", recruited = false })
upperFriendly.modData.SC_Recruited = false
do
shooter.perks = { Aiming = 8, Fitness = 6, Strength = 5, Nimble = 3 }
local shooterCommands = SurvivorCompanion.Commands.peek(shooter)
shooterCommands.stress, shooterCommands.morale = 0, 70
local clearFloorShot = SurvivorCompanion.Combat.update(shooter, upperFriendly, { snapshot = shotSnapshot })
check(clearFloorShot and shooter.lastIntent.action == "ready_weapon"
        and shooter.lastIntent.deliberateAim == true,
    "a clear firing lane begins a deliberate Build 42 aiming pause")
local skilledAimMs = SurvivorCompanion.Combat.peek(shooter).aimRequiredMs
local rookieRifle = item("Base.VarmintRifle", "Weapon", {
    ranged = true, damage = 1.5, range = 10, ammo = 3, maxAmmo = 5,
})
local rookieShooter = actor("sc-panicked-shooter", 0, -1, {
    inventory = inventory({ rookieRifle }),
})
rookieShooter.primary = rookieRifle
rookieShooter.perks = { Aiming = 0, Fitness = 4, Strength = 4, Nimble = 0 }
rookieShooter.moodles = { PANIC = 3 }
local rookieCommands = SurvivorCompanion.Commands.peek(rookieShooter)
rookieCommands.stress, rookieCommands.morale = 80, 35
local rookieZed = zombie(4, -1, {})
local rookieSnapshot = {
    threats = { { actor = rookieZed, square = rookieZed.square, distanceSq = 16,
        visible = true, obstructed = false, attacking = false, score = 30 } },
    allies = {}, escapeSquares = { { square = squares[squareKey(-1, -1, 0)],
        danger = 0, nearestThreatSq = 25 } },
    threatCount = 1, immediateCount = 0, closeImmediateCount = 0,
    closeThreatCount = 1, occupiedThreatSectors = 1, pressure = 0,
    player = { danger = 0, immediateThreats = 0 },
}
local rookieAiming = SurvivorCompanion.Combat.update(
    rookieShooter, upperFriendly, { snapshot = rookieSnapshot })
local rookieAimMs = SurvivorCompanion.Combat.peek(rookieShooter).aimRequiredMs
check(rookieAiming and rookieShooter.lastIntent.action == "ready_weapon"
        and rookieAimMs > skilledAimMs + 700,
    "panic, stress and low Aiming skill require a materially longer sight picture")
clock = clock + 2000
local settledFloorShot = SurvivorCompanion.Combat.update(
    shooter, upperFriendly, { snapshot = shotSnapshot })
check(settledFloorShot and shooter.lastIntent.action == "attack_firearm",
    "a settled shooter fires when the friendly is on another floor")
local crossFloorShot = SurvivorCompanion.Combat.update(shooter, upperFriendly, {
    snapshot = {
        threats = { { actor = upperZed, square = upperZed.square, distanceSq = 1, visible = true, obstructed = false, score = 999 } },
        allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 0, pressure = 0,
        player = { danger = 0, immediateThreats = 0 },
    },
})
check(not crossFloorShot, "shooting never targets through a floor")
rookieZed.dead = true
SurvivorCompanion.Combat.reset(rookieShooter)
end

local emptyRifle = item("Base.VarmintRifle", "Weapon", {
    ranged = true, damage = 1.5, range = 10, ammo = 0, maxAmmo = 5, ammoType = "Base.223Bullets",
})
local rifleAmmo = item("Base.223Bullets", "Ammo")
local reloader = actor("sc-reloader", 0, -5, { inventory = inventory({ emptyRifle, rifleAmmo }) })
reloader.primary = emptyRifle
registry[reloader.id] = reloader
local reloadZed = zombie(4, -5, {})
local reloadSnapshot = {
    threats = { { actor = reloadZed, square = reloadZed.square, distanceSq = 16, visible = true, obstructed = false, score = 30 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 0, pressure = 0,
    player = { danger = 0, immediateThreats = 0 },
}
check(SurvivorCompanion.Combat.update(reloader, player, { snapshot = reloadSnapshot })
    and reloader.lastIntent.action == "reload", "firearm combat chooses a valid reload")

check(SurvivorCompanion.Commands.issue(fellow.id, "set_group", "Alpha", player), "first group assignment")
check(SurvivorCompanion.Commands.issue(shooter.id, "set_group", "Alpha", player), "second group assignment")
local groupFollow = SurvivorCompanion.Commands.issue(fellow.id, "follow", { scope = "group", group = "Alpha" }, player)
check(groupFollow and SurvivorCompanion.Commands.peek(fellow).order == "follow"
    and SurvivorCompanion.Commands.peek(shooter).order == "follow", "group payload targets a fixed member snapshot")
player.vehicle = livePlayerVehicle
shooter.rejectActions = { board_vehicle = true }
local groupBoarded, groupBoardReason, groupBoardResults = SurvivorCompanion.Commands.issue(
    fellow.id,
    "board_vehicle",
    { scope = "group", group = "Alpha" },
    player
)
check(not groupBoarded and groupBoardReason == "group_partial_nonrollback"
    and #groupBoardResults == 2 and groupBoardResults[1].ok
    and not groupBoardResults[2].ok and groupBoardResults[1].rollback == false,
    "group boarding truthfully reports accepted partial non-rollback execution")
shooter.rejectActions = nil
player.vehicle = nil

fellow.vehicle = livePlayerVehicle
shooter.vehicle = nil
local fellowMovementBeforeExitPrevalidation = fellow.movementCalls
local groupExitPrevalidated, groupExitReason = SurvivorCompanion.Commands.issue(
    fellow.id,
    "exit_vehicle",
    { scope = "group", group = "Alpha" },
    player
)
check(not groupExitPrevalidated and string.find(groupExitReason, "member_not_in_vehicle", 1, true)
    and fellow.movementCalls == fellowMovementBeforeExitPrevalidation,
    "group vehicle exit validates every fixed member before starting physical actions")
fellow.vehicle = nil
local fellowDistanceBefore = SurvivorCompanion.Commands.peek(fellow).followDistance
local shooterDistanceBefore = SurvivorCompanion.Commands.peek(shooter).followDistance
local invalidGroupDistance = SurvivorCompanion.Commands.issue(
    fellow.id,
    "set_follow_distance",
    { scope = "group", group = "Alpha", distance = 4 },
    player
)
check(not invalidGroupDistance and SurvivorCompanion.Commands.peek(fellow).followDistance == fellowDistanceBefore
    and SurvivorCompanion.Commands.peek(shooter).followDistance == shooterDistanceBefore,
    "group payload is prevalidated before any mutation")
local groupMove = SurvivorCompanion.Commands.issue(
    fellow.id,
    "move_to",
    { scope = "group", group = "Alpha", square = squares[squareKey(5, 0, 0)] },
    player
)
check(not groupMove and SurvivorCompanion.Commands.peek(fellow).order == "follow"
    and SurvivorCompanion.Commands.peek(shooter).order == "follow",
    "immediate navigation commands are explicitly non-groupable")

local backingModData = shooter.modData
shooter.modDataProxy = setmetatable({}, {
    __index = backingModData,
    __newindex = function(target, key, value)
        if key == "SC_Order" then error("injected second-member persistence failure") end
        rawset(target, key, value)
    end,
})
local failedNthGroup = SurvivorCompanion.Commands.issue(
    fellow.id,
    "stay",
    { scope = "group", group = "Alpha" },
    player
)
shooter.modDataProxy = nil
check(not failedNthGroup and SurvivorCompanion.Commands.peek(fellow).order == "follow"
    and SurvivorCompanion.Commands.peek(shooter).order == "follow"
    and fellow.modData.SC_Order == "follow" and shooter.modData.SC_Order == "follow",
    "failure on the second group member rolls every state and persistence record back exactly")

local openedFood = item("Base.CannedSoup", "Food")
local safeFood = item("Base.CannedBeans", "Food")
local function containerObject(square, contents)
    local container = inventory(contents)
    function container:getParent() return self.owner end
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
local openedContainer = containerObject(fellow.square, { openedFood })
local safeContainer = containerObject(fellow.square, { safeFood })
check(SurvivorCompanion.Encounter.onPlayerContainerOpened(openedContainer)
    and SurvivorCompanion.Encounter.wasPlayerOpened(openedContainer),
    "production player-container-opened adapter marks the exclusion flag")
do
    local sliceClock = clock
    local slicedFood = item("Base.CannedBolognese", "Food")
    local slicedActor = actor("sc-sliced-looter", 0, 4, {})
    registry[slicedActor.id] = slicedActor
    slicedActor.hunger = 0.95
    containerObject(slicedActor.square, { slicedFood })
    SurvivorCompanion.Commands.issue(slicedActor.id, "set_scavenge", true, player)
    local runtime = {
        snapshot = { threats = {}, immediateCount = 0, threatCount = 0,
            pressure = 0, escapeSquares = {} },
    }
    SurvivorCompanion.Performance.reset()
    SurvivorCompanion.Performance.beginFrame(2, clock)
    local started, startReason = SurvivorCompanion.Encounter.tryScavenge(
        slicedActor, player, runtime)
    clock = clock + 16
    SurvivorCompanion.Performance.endFrame(1, false)
    check(started and startReason == "searching_for_supplies"
        and SurvivorCompanion.Encounter.peek(slicedActor).containerSearch ~= nil,
        "scavenging container discovery yields instead of scanning every square in one frame")
    local acquired = false
    for _ = 1, 20 do
        SurvivorCompanion.Performance.beginFrame(2, clock)
        SurvivorCompanion.Encounter.tryScavenge(slicedActor, player, runtime)
        clock = clock + 16
        SurvivorCompanion.Performance.endFrame(1, false)
        if SurvivorCompanion.GameplayUtil.inventoryContains(slicedActor.inventory, slicedFood) then
            acquired = true
            break
        end
    end
    check(acquired, "resumable scavenging completes selection and verified transfer across frames")
    SurvivorCompanion.Encounter.reset(slicedActor)
    registry[slicedActor.id] = nil
    SurvivorCompanion.Performance.reset()
    clock = sliceClock
end
SurvivorCompanion.Commands.issue(fellow.id, "set_scavenge", true, player)
fellow.hunger = 0.9
local scavenged = SurvivorCompanion.Encounter.tryScavenge(fellow, player, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0, escapeSquares = {} },
})
check(scavenged and not openedFood.used, "scavenging ignores player-opened containers")
local foundSafeFood = false
for _, value in ipairs(fellow.inventory.items) do if value == safeFood then foundSafeFood = true end end
check(foundSafeFood, "scavenging transfers a needed item from an unvisited reserved container")

do
local stagedFood = item("Base.CannedChili", "Food")
local stagedLootActor = actor("sc-loot-transaction", -20, 4, {})
registry[stagedLootActor.id] = stagedLootActor
SurvivorCompanion.Commands.issue(stagedLootActor.id, "set_scavenge", true, player)
stagedLootActor.hunger = 0.95
local stagedContainer = containerObject(stagedLootActor.square, { stagedFood })
local stagedVisualState = "active"
local stagedClears = 0
SurvivorCompanion.NativeActions = {
    visualStatus = function(_, expected)
        return stagedVisualState, expected
    end,
    clearVisual = function()
        stagedClears = stagedClears + 1
        stagedVisualState = "none"
    end,
}
local stagedRuntime = {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0, escapeSquares = {} },
}
local stagedStarted, stagedStartReason = SurvivorCompanion.Encounter.tryScavenge(
    stagedLootActor, nil, stagedRuntime)
local movementCountAtStart = stagedLootActor.movementCalls
local stagedAction = SurvivorCompanion.ActionSupervisor.snapshot(stagedLootActor)
check(stagedStarted and stagedStartReason == "looting"
        and stagedContainer:contains(stagedFood)
        and not stagedLootActor.inventory:contains(stagedFood)
        and stagedAction.owner == "encounter" and stagedAction.action == "scavenge"
        and stagedAction.phase == "animating" and stagedAction.reservationCount == 2,
    "scavenging owns its animation and exact resources before mutating inventory")
local stagedWaiting, stagedWaitReason = SurvivorCompanion.Encounter.tryScavenge(
    stagedLootActor, nil, stagedRuntime)
check(stagedWaiting and stagedWaitReason == "looting"
        and stagedLootActor.movementCalls == movementCountAtStart,
    "active rummage transaction does not restart the animation every decision tick")
stagedVisualState = "completed"
local stagedFinished, stagedFinishReason = SurvivorCompanion.Encounter.tryScavenge(
    stagedLootActor, nil, stagedRuntime)
local stagedCompleted = SurvivorCompanion.ActionSupervisor.snapshot(stagedLootActor)
check(stagedFinished and stagedFinishReason == "looted" and stagedClears == 1
        and stagedLootActor.inventory:contains(stagedFood)
        and not stagedContainer:contains(stagedFood)
        and stagedCompleted.phase == "idle" and stagedCompleted.reservationCount == 0
        and stagedCompleted.last and stagedCompleted.last.event == "completed",
    "completed rummage commits once and releases supervisor ownership and reservations")
SurvivorCompanion.NativeActions = nil
end

do
local safeScavengeSnapshot = {
    threats = {}, immediateCount = 0, threatCount = 0, pressure = 0, escapeSquares = {},
}
local testScavengers = {}
local function recruitedScavenger(id, x, y, options)
    local value = actor(id, x, y, options or {})
    registry[value.id] = value
    testScavengers[#testScavengers + 1] = value
    SurvivorCompanion.Commands.issue(value.id, "set_scavenge", true, player)
    value.hunger = 0.95
    return value
end
local visualStates = setmetatable({}, { __mode = "k" })
local visualCancels = setmetatable({}, { __mode = "k" })
SurvivorCompanion.NativeActions = {
    visualStatus = function(value, expected)
        return visualStates[value] or "none", expected
    end,
    clearVisual = function(value)
        visualStates[value] = "none"
    end,
    cancelVisual = function(value)
        visualStates[value] = "cancelled"
        visualCancels[value] = (visualCancels[value] or 0) + 1
        return true
    end,
    stopDirect = function(value)
        value.moving = false
        return true
    end,
}

local dangerFood = item("Base.CannedPotato", "Food")
local dangerActor = recruitedScavenger("sc-loot-danger-cancel", -45, -45)
local dangerSource = containerObject(dangerActor.square, { dangerFood })
visualStates[dangerActor] = "active"
local dangerStarted = SurvivorCompanion.Encounter.tryScavenge(dangerActor, nil,
    { snapshot = safeScavengeSnapshot })
local dangerCancelled, dangerReason = SurvivorCompanion.Encounter.tryScavenge(
    dangerActor, nil, { snapshot = {
        threats = { { target = dangerActor } }, immediateCount = 1,
        threatCount = 1, pressure = 3, escapeSquares = {},
    } })
check(dangerStarted and not dangerCancelled
        and dangerReason == "scavenge_disabled_or_unsafe"
        and dangerSource:contains(dangerFood)
        and not dangerActor.inventory:contains(dangerFood)
        and visualCancels[dangerActor] == 1
        and SurvivorCompanion.Encounter.peek(dangerActor).task == nil
        and SurvivorCompanion.ActionSupervisor.snapshot(dangerActor).phase == "idle"
        and SurvivorCompanion.ActionSupervisor.reservationCount(dangerActor) == 0,
    "danger cancels the supervised Loot action before mutation and releases resources")

local commandFood = item("Base.CannedTomato", "Food")
local commandActor = recruitedScavenger("sc-loot-command-cancel", -35, -45)
local commandSource = containerObject(commandActor.square, { commandFood })
visualStates[commandActor] = "active"
check(SurvivorCompanion.Encounter.tryScavenge(commandActor, nil,
        { snapshot = safeScavengeSnapshot }),
    "command-cancel fixture owns an active Loot action")
check(SurvivorCompanion.Commands.issue(commandActor.id, "stay", nil, player),
    "command-cancel fixture accepts a new persistent order")
check(commandSource:contains(commandFood)
        and not commandActor.inventory:contains(commandFood)
        and visualCancels[commandActor] == 1
        and SurvivorCompanion.Encounter.peek(commandActor).task == nil,
    "a new command immediately cancels the transaction and prevents a late commit")

local removedFood = item("Base.CannedMushroomSoup", "Food")
local removedActor = recruitedScavenger("sc-loot-source-removed", -25, -45)
local removedSource = containerObject(removedActor.square, { removedFood })
visualStates[removedActor] = "active"
check(SurvivorCompanion.Encounter.tryScavenge(removedActor, nil,
        { snapshot = safeScavengeSnapshot }),
    "removed-source fixture owns an active Loot action")
removedSource:Remove(removedFood)
local removedContinued, removedReason = SurvivorCompanion.Encounter.tryScavenge(
    removedActor, nil, { snapshot = safeScavengeSnapshot })
check(not removedContinued and removedReason == "source_changed"
        and not removedActor.inventory:contains(removedFood)
        and visualCancels[removedActor] == 1
        and SurvivorCompanion.Encounter.peek(removedActor).task == nil,
    "an item removed during Loot cancels cleanly and is never recreated")

local rollbackFood = item("Base.CannedCornedBeef", "Food")
local rollbackInventory = inventory()
rollbackInventory.rejectAddType = rollbackFood.itemType
local rollbackActor = recruitedScavenger("sc-loot-rollback", -15, -45,
    { inventory = rollbackInventory })
local rollbackSource = containerObject(rollbackActor.square, { rollbackFood })
visualStates[rollbackActor] = "completed"
local rollbackLooted, rollbackReason = SurvivorCompanion.Encounter.tryScavenge(
    rollbackActor, nil, { snapshot = safeScavengeSnapshot })
check(not rollbackLooted and rollbackReason == "destination_add_failed_rolled_back"
        and rollbackSource:contains(rollbackFood)
        and not rollbackActor.inventory:contains(rollbackFood),
    "a rejected destination restores the exact item to its source and reports verified rollback")

local heavyInventory = inventory({ item("Base.HeavyJunkScavenge", "Item", {
    weight = 4, favorite = true,
}) })
heavyInventory.capacity = 5
local fullActor = recruitedScavenger("sc-loot-full-policy", -5, -45,
    { inventory = heavyInventory })
local fullFood = item("Base.CannedFruitCocktail", "Food", { weight = 1 })
local fullSource = containerObject(fullActor.square, { fullFood })
visualStates[fullActor] = "completed"
local fullLooted, fullReason = SurvivorCompanion.Encounter.tryScavenge(
    fullActor, nil, { snapshot = safeScavengeSnapshot })
check(not fullLooted and fullReason == "nothing_needed"
        and fullSource:contains(fullFood) and not fullActor.inventory:contains(fullFood),
    "role load ceiling rejects scavenging before animation or transfer")

local wornBagInventory = inventory()
wornBagInventory.capacity = 18
local wornBag = item("Base.Bag_SurvivorBag", "Container", {
    nestedInventory = wornBagInventory, bagCapacity = 18, weightReduction = 80,
    bodyLocation = "Back", equipLocation = "Back", weight = 1,
})
local bagActor = recruitedScavenger("sc-loot-worn-bag", 5, -45,
    { inventory = inventory({ wornBag }) })
bagActor:setWornItem("Back", wornBag)
local bagFood = item("Base.CannedSardinesScavenge", "Food", { weight = 1 })
local bagSource = containerObject(bagActor.square, { bagFood })
visualStates[bagActor] = "completed"
local bagLooted, bagReason = SurvivorCompanion.Encounter.tryScavenge(
    bagActor, nil, { snapshot = safeScavengeSnapshot })
local bagStatus = SurvivorCompanion.Encounter.status(bagActor)
local bagSummary = SurvivorCompanion.Commands.describe(bagActor.id, player)
check(bagLooted and bagReason == "looted"
        and wornBagInventory:contains(bagFood)
        and not bagActor.inventory:contains(bagFood)
        and not bagSource:contains(bagFood)
        and bagStatus.lastLoot.destination == "worn_bag"
        and bagStatus.lastLoot.verified == true
        and string.find(bagSummary.activity, "Picked up", 1, true) ~= nil,
    "role supplies transfer directly into a worn bag and expose a verified UI receipt")

local upgradeActor = recruitedScavenger("sc-loot-bag-upgrade-root", 15, -45)
local upgradeInventory = inventory()
upgradeInventory.capacity = 24
local upgradeBag = item("Base.Bag_BigHikingBagScavenge", "Container", {
    nestedInventory = upgradeInventory, bagCapacity = 24, weightReduction = 85,
    bodyLocation = "Back", equipLocation = "Back", weight = 1,
})
local upgradeSource = containerObject(upgradeActor.square, { upgradeBag })
visualStates[upgradeActor] = "completed"
local upgradeLooted = SurvivorCompanion.Encounter.tryScavenge(
    upgradeActor, nil, { snapshot = safeScavengeSnapshot })
check(upgradeLooted and upgradeActor.inventory:contains(upgradeBag)
        and not upgradeInventory:contains(upgradeBag)
        and not upgradeSource:contains(upgradeBag),
    "a bag upgrade enters inventory root so the later native equip action can own it")

local sharedFood = item("Base.CannedMilkShared", "Food")
local reserveFirst = recruitedScavenger("sc-loot-reserve-first", 25, -45)
local reserveSecond = recruitedScavenger("sc-loot-reserve-second", 25, -45)
local sharedSource = containerObject(reserveFirst.square, { sharedFood })
visualStates[reserveFirst] = "active"
visualStates[reserveSecond] = "active"
local firstReserved = SurvivorCompanion.Encounter.tryScavenge(
    reserveFirst, nil, { snapshot = safeScavengeSnapshot })
local secondReserved, secondReserveReason = SurvivorCompanion.Encounter.tryScavenge(
    reserveSecond, nil, { snapshot = safeScavengeSnapshot })
check(firstReserved and not secondReserved and secondReserveReason == "nothing_needed"
        and sharedSource:contains(sharedFood)
        and SurvivorCompanion.Encounter.peek(reserveFirst).task.container == sharedSource
        and SurvivorCompanion.Encounter.peek(reserveSecond).task == nil,
    "two companions cannot own the same scavenging container concurrently")
visualStates[reserveFirst] = "completed"
local firstCommitted = SurvivorCompanion.Encounter.tryScavenge(
    reserveFirst, nil, { snapshot = safeScavengeSnapshot })
check(firstCommitted and reserveFirst.inventory:contains(sharedFood)
        and not reserveSecond.inventory:contains(sharedFood),
    "the reservation owner alone commits the shared item")

local resetFood = item("Base.CannedCarrotsReset", "Food")
local resetActor = recruitedScavenger("sc-loot-reset-boundary", 35, -45)
local resetSource = containerObject(resetActor.square, { resetFood })
visualStates[resetActor] = "active"
check(SurvivorCompanion.Encounter.tryScavenge(resetActor, nil,
        { snapshot = safeScavengeSnapshot }),
    "reset boundary fixture owns an uncommitted Loot action")
SurvivorCompanion.Encounter.reset(resetActor)
check(resetSource:contains(resetFood) and not resetActor.inventory:contains(resetFood)
        and visualCancels[resetActor] == 1
        and SurvivorCompanion.Encounter.peek(resetActor) == nil,
    "save/world reset discards only transient scavenging state without duplication or deletion")

local memoryActor = recruitedScavenger("sc-loot-container-memory", 45, -45)
local unwanted = item("Base.UnwantedMemoryItem", "Item")
local memorySource = containerObject(memoryActor.square, { unwanted })
local categoryReads = 0
local originalCategory = unwanted.getCategory
function unwanted:getCategory()
    categoryReads = categoryReads + 1
    return originalCategory(self)
end
local noNeedFirst, noNeedFirstReason = SurvivorCompanion.Encounter.tryScavenge(
    memoryActor, nil, { snapshot = safeScavengeSnapshot })
local readsAfterFirst = categoryReads
local noNeedSecond, noNeedSecondReason = SurvivorCompanion.Encounter.tryScavenge(
    memoryActor, nil, { snapshot = safeScavengeSnapshot })
check(not noNeedFirst and noNeedFirstReason == "nothing_needed"
        and not noNeedSecond and noNeedSecondReason == "nothing_needed"
        and categoryReads == readsAfterFirst,
    "unchanged unhelpful containers are remembered instead of rescored every decision tick")
local changedFood = item("Base.CannedBeansMemoryChanged", "Food")
memorySource:AddItem(changedFood)
visualStates[memoryActor] = "completed"
local changedLooted = SurvivorCompanion.Encounter.tryScavenge(
    memoryActor, nil, { snapshot = safeScavengeSnapshot })
check(changedLooted and memoryActor.inventory:contains(changedFood)
        and not memorySource:contains(changedFood),
    "a changed container signature immediately invalidates no-useful memory")

for _, value in ipairs(testScavengers) do
    SurvivorCompanion.Encounter.reset(value)
    SurvivorCompanion.Commands.reset(value)
    registry[value.id] = nil
end
SurvivorCompanion.NativeActions = nil
end

local rejectedLoot = item("Base.CannedCorn", "Food")
local lootRejectActor = actor("sc-loot-reject", -3, 3, {})
registry[lootRejectActor.id] = lootRejectActor
SurvivorCompanion.Commands.issue(lootRejectActor.id, "set_scavenge", true, player)
lootRejectActor.hunger = 0.95
lootRejectActor.rejectActions = { loot_container = true }
local rejectedContainer = containerObject(lootRejectActor.square, { rejectedLoot })
local rejectedScavenge = SurvivorCompanion.Encounter.tryScavenge(lootRejectActor, player, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0, escapeSquares = {} },
})
check(not rejectedScavenge and rejectedContainer:contains(rejectedLoot)
    and not lootRejectActor.inventory:contains(rejectedLoot),
    "rejected loot action transfers nothing and reports failure")

local function testLoadoutAndCorpseLogistics()
local overloadWeapon = item("Base.HandAxe", "Weapon", { weight = 2 })
local overloadFoodA = item("Base.CannedPeas", "Food", { weight = 1 })
local overloadFoodB = item("Base.CannedCarrots", "Food", { weight = 1 })
local overloadJunk = item("Base.BrokenGlass", "Item", { weight = 5 })
local overloadInventory = inventory({ overloadWeapon, overloadFoodA, overloadFoodB, overloadJunk })
overloadInventory.capacity = 10
local overloadActor = actor("sc-loadout-drop", 8, 0,
    { inventory = overloadInventory })
overloadActor.primary = overloadWeapon
registry[overloadActor.id] = overloadActor
local loadStatus = SurvivorCompanion.Logistics.status(overloadActor)
local loadManaged = SurvivorCompanion.Logistics.update(overloadActor, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(loadStatus.shouldUnload and loadManaged
    and overloadInventory:contains(overloadWeapon) and overloadInventory:contains(overloadFoodA)
    and not overloadInventory:contains(overloadJunk)
    and overloadActor.square.worldItems[#overloadActor.square.worldItems].item == overloadJunk,
    "load management preserves equipped and reserve gear while dropping low-value surplus transactionally")

local nestedJunk = item("Base.UnusableMetal", "Item", { weight = 7 })
local carriedBag = item("Base.Duffelbag", "Container", {
    weight = 9, nestedInventory = inventory({ nestedJunk }),
})
local nestedLoad = inventory({ carriedBag })
nestedLoad.capacity = 10
local nestedActor = actor("sc-loadout-nested", 8, 1, { inventory = nestedLoad })
registry[nestedActor.id] = nestedActor
local nestedManaged = SurvivorCompanion.Logistics.update(nestedActor, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(nestedManaged and nestedLoad:contains(carriedBag)
    and not carriedBag.nestedInventory:contains(nestedJunk)
    and nestedActor.square.worldItems[#nestedActor.square.worldItems].item == nestedJunk,
    "load management removes nested surplus without discarding the companion's bag")

local fullInventory = inventory({ item("Base.HeavyJunk", "Item", { weight = 4 }) })
fullInventory.capacity = 5
local fullActor = actor("sc-loadout-full", 9, 0, { inventory = fullInventory })
registry[fullActor.id] = fullActor
local tooHeavyFood = item("Base.CannedChili", "Food", { weight = 1 })
check(not SurvivorCompanion.Logistics.canTake(fullActor, tooHeavyFood, "food"),
    "scavenging refuses a needed item when it would cross the role's hard load ceiling")
check(SurvivorCompanion.Commands.issue(fullActor.id, "set_allow_overload", true, player)
    and SurvivorCompanion.Logistics.canTake(fullActor, tooHeavyFood, "food")
    and fullActor.modData.SC_AllowOverload == true,
    "per-companion overload approval persists and relaxes the bounded hard load ceiling")
SurvivorCompanion.Commands.issue(fullActor.id, "set_allow_overload", false, player)

local bagFood = item("Base.CannedBeans", "Food", { weight = 2 })
local bagMedical = item("Base.Bandage", "Medical", { weight = 1 })
local bagInventory = inventory()
bagInventory.capacity = 16
local backpack = item("Base.Bag_ALICEpack", "Container", {
    weight = 1.5, nestedInventory = bagInventory, bagCapacity = 16,
    weightReduction = 85, bodyLocation = "Back", equipLocation = "Back",
})
local bagCarrierInventory = inventory({ backpack, bagFood, bagMedical })
bagCarrierInventory.capacity = 20
local bagCarrier = actor("sc-bag-carrier", 9, 1, { inventory = bagCarrierInventory })
local woreBag, woreBagReason = SurvivorCompanion.Logistics.update(bagCarrier, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
local packedBag, packedBagReason = SurvivorCompanion.Logistics.update(bagCarrier, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
local nestedAudit = SurvivorCompanion.Logistics.audit(bagCarrier)
check(woreBag and bagCarrier:getWornItem("Back") == backpack
    and packedBag and (#bagInventory.items == 1)
    and (nestedAudit.counts.food or 0) == 1 and (nestedAudit.counts.medicine or 0) == 1,
    "companions equip a useful backpack, pack role gear into it, and retain a recursive view of nested contents: "
        .. tostring(woreBagReason) .. ", " .. tostring(packedBagReason))

do
local phasedBagInventory = inventory()
phasedBagInventory.capacity = 18
local phasedBag = item("Base.Bag_PhasedPack", "Container", {
    nestedInventory = phasedBagInventory, bagCapacity = 18, weightReduction = 80,
    bodyLocation = "Back", equipLocation = "Back", weight = 1,
})
local phasedFood = item("Base.CannedBeansPhasedPack", "Food", { weight = 1 })
local phasedActor = actor("sc-logistics-phased-pack", 9, 3,
    { inventory = inventory({ phasedBag, phasedFood }) })
phasedActor:setWornItem("Back", phasedBag)
local phasedState = "active"
local phasedStarts, phasedCancels = 0, 0
local priorMovementCalls = phasedActor.movementCalls
SurvivorCompanion.NativeActions = {
    visualStatus = function(_, expected) return phasedState, expected end,
    clearVisual = function() phasedState = "none" end,
    cancelVisual = function() phasedState = "cancelled" phasedCancels = phasedCancels + 1 return true end,
    stopDirect = function(value) value.moving = false return true end,
}
local originalSetMovement = SurvivorCompanion.Actor.setMovement
SurvivorCompanion.Actor.setMovement = function(value, mode, intent)
    if value == phasedActor and intent and intent.action == "loot_container" then
        phasedStarts = phasedStarts + 1
    end
    return originalSetMovement(value, mode, intent)
end
local packStarted, packStartReason = SurvivorCompanion.Logistics.update(
    phasedActor, nil, { snapshot = {
        threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
    } })
local packWaiting, packWaitReason = SurvivorCompanion.Logistics.update(
    phasedActor, nil, { snapshot = {
        threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
    } })
check(packStarted and packWaiting and phasedStarts == 1
        and phasedActor.inventory:contains(phasedFood)
        and not phasedBagInventory:contains(phasedFood)
        and SurvivorCompanion.ActionSupervisor.snapshot(phasedActor).owner == "logistics"
        and SurvivorCompanion.ActionSupervisor.snapshot(phasedActor).phase == "animating"
        and SurvivorCompanion.ActionSupervisor.reservationCount(phasedActor) == 1,
    "post-loot packing waits under one supervised Loot action without restarting it: "
        .. tostring(packStartReason) .. "/" .. tostring(packWaitReason))
phasedState = "completed"
local packFinished, packFinishReason = SurvivorCompanion.Logistics.update(
    phasedActor, nil, { snapshot = {
        threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
    } })
check(packFinished and packFinishReason == "item_packed"
        and not phasedActor.inventory:contains(phasedFood)
        and phasedBagInventory:contains(phasedFood) and phasedStarts == 1
        and SurvivorCompanion.ActionSupervisor.snapshot(phasedActor).phase == "idle"
        and SurvivorCompanion.ActionSupervisor.reservationCount(phasedActor) == 0,
    "post-loot packing commits exactly once and releases transaction ownership")

local cancelFood = item("Base.CannedPeachesPackCancel", "Food", { weight = 1 })
phasedActor.inventory:AddItem(cancelFood)
phasedState = "active"
check(SurvivorCompanion.Logistics.update(phasedActor, nil, { snapshot = {
        threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
    } }), "danger-cancelled pack fixture starts")
local cancelledPack, cancelledPackReason = SurvivorCompanion.Logistics.update(
    phasedActor, nil, { snapshot = {
        threats = { {} }, immediateCount = 1, threatCount = 1, pressure = 2,
    } })
check(not cancelledPack and cancelledPackReason == "logistics_unsafe"
        and phasedCancels == 1 and phasedActor.inventory:contains(cancelFood)
        and not phasedBagInventory:contains(cancelFood)
        and SurvivorCompanion.ActionSupervisor.snapshot(phasedActor).phase == "idle"
        and SurvivorCompanion.ActionSupervisor.reservationCount(phasedActor) == 0,
    "danger cancels post-loot packing before mutation and releases its reservation")
SurvivorCompanion.Actor.setMovement = originalSetMovement
SurvivorCompanion.NativeActions = nil
SurvivorCompanion.Logistics.reset(phasedActor)
check((phasedActor.movementCalls or 0) >= (priorMovementCalls or 0),
    "phased logistics fixture restores actor adapters")
end

local function zombieCorpseObject(square, contents)
    local container = inventory(contents)
    local corpse = { __class = "IsoDeadBody", square = square, modData = {} }
    function corpse:getSquare() return self.square end
    function corpse:getX() return self.square.x end
    function corpse:getY() return self.square.y end
    function corpse:getZ() return self.square.z end
    function corpse:getContainer() return container end
    function corpse:getModData() return self.modData end
    function corpse:isAnimal() return false end
    function corpse:isZombie() return true end
    container.owner = corpse
    square.staticMoving[#square.staticMoving + 1] = corpse
    return container, corpse
end

local corpseFood = item("Base.CannedBolognese", "Food", { weight = 1 })
local corpseLooter = actor("sc-corpse-looter", 10, 0, {})
registry[corpseLooter.id] = corpseLooter
SurvivorCompanion.Commands.issue(corpseLooter.id, "set_scavenge", true, player)
local corpseContainer = zombieCorpseObject(corpseLooter.square, { corpseFood })
local corpseLooted = SurvivorCompanion.Encounter.tryScavenge(corpseLooter, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
local corpseState = SurvivorCompanion.Encounter.peek(corpseLooter)
check(corpseLooted and corpseLooter.inventory:contains(corpseFood)
    and not corpseContainer:contains(corpseFood)
    and corpseState.lastLoot.source == "zombie_corpse",
    "companions freely loot useful gear from zombie corpses when combat is clear")

local wornShirt = item("Base.Shirt_FormalWhite", "Clothing", {
    bodyLocation = "Shirt", condition = 5, conditionMax = 10,
    biteDefense = 2, scratchDefense = 4,
})
local betterShirt = item("Base.Shirt_Denim", "Clothing", {
    bodyLocation = "Shirt", condition = 10, conditionMax = 10,
    biteDefense = 18, scratchDefense = 30, combatSpeedModifier = 0.98,
    bloodLevel = 10, dirtiness = 8, weight = 1,
})
local clothingLooter = actor("sc-corpse-clothing", 10, 1,
    { inventory = inventory({ wornShirt }) })
clothingLooter:setWornItem("Shirt", wornShirt)
clothingLooter.modData.SC_Scavenge = true
local clothingCorpse = zombieCorpseObject(clothingLooter.square, { betterShirt })
local clothingLooted = SurvivorCompanion.Encounter.tryScavenge(clothingLooter, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
local clothingEquipped, clothingReason = SurvivorCompanion.Logistics.update(clothingLooter, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(clothingLooted and not clothingCorpse:contains(betterShirt)
    and clothingEquipped and clothingLooter:getWornItem("Shirt") == betterShirt,
    "outside combat, companions loot and equip a materially better zombie garment: "
        .. tostring(clothingReason))

local protectiveCoat = item("Base.Coat_Long", "Clothing", {
    bodyLocation = "JacketSuit", condition = 10, conditionMax = 10,
    biteDefense = 35, scratchDefense = 45, combatSpeedModifier = 0.97,
    weight = 2,
})
local weakExclusiveJacket = item("Base.Jacket_WhiteTINT", "Clothing", {
    bodyLocation = "Jacket", condition = 10, conditionMax = 10,
    biteDefense = 4, scratchDefense = 8, weight = 1,
})
local exclusiveClothingActor = actor("sc-exclusive-clothing", 10, 2,
    { inventory = inventory({ protectiveCoat, weakExclusiveJacket }) })
exclusiveClothingActor.exclusiveLocations = { ["Jacket:JacketSuit"] = true }
exclusiveClothingActor:setWornItem("JacketSuit", protectiveCoat)
local exclusiveUpgrade, exclusiveDifference = SurvivorCompanion.Logistics.clothingUpgrade(
    exclusiveClothingActor, weakExclusiveJacket)
check(not exclusiveUpgrade and exclusiveDifference < 0
    and exclusiveClothingActor:getWornItem("JacketSuit") == protectiveCoat,
    "clothing upgrades account for mutually exclusive body locations and preserve stronger armor")

local vestInventory = inventory()
vestInventory.capacity = 16
local wornVestBag = item("Base.Bag_Schoolbag", "Container", {
    weight = 1, nestedInventory = vestInventory, bagCapacity = 16,
    weightReduction = 70, bodyLocation = "Back", equipLocation = "Back",
})
local bulletproofVest = item("Base.Vest_BulletCivilian", "Item", {
    __class = "Clothing", bodyLocation = "TorsoExtraVest", condition = 10,
    conditionMax = 10, biteDefense = 30, scratchDefense = 40,
    bulletDefense = 100, weight = 2,
})
vestInventory:AddItem(bulletproofVest)
local vestActor = actor("sc-bulletproof-vest", 10, 4,
    { inventory = inventory({ wornVestBag }) })
vestActor:setWornItem("Back", wornVestBag)
local vestAudit = SurvivorCompanion.Logistics.status(vestActor)
local vestEquipped, vestReason = SurvivorCompanion.Logistics.update(vestActor, nil, {
    snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
})
check(SurvivorCompanion.Logistics.itemCategory(bulletproofVest) == "clothing"
    and vestAudit.clothingUpgrade and vestAudit.clothingUpgrade.item == bulletproofVest
    and (not vestAudit.packMove or vestAudit.packMove.item ~= bulletproofVest)
    and vestEquipped and vestActor:getWornItem("TorsoExtraVest") == bulletproofVest
    and not vestInventory:contains(bulletproofVest),
    "protective Clothing subclasses are equipped from a backpack before generic packing: "
        .. tostring(vestReason))

local rollbackShirt = item("Base.Shirt_FormalWhite", "Clothing", {
    bodyLocation = "Shirt", condition = 4, conditionMax = 10,
    biteDefense = 1, scratchDefense = 2,
})
local rejectedUpgradeShirt = item("Base.Shirt_Denim", "Clothing", {
    bodyLocation = "Shirt", condition = 10, conditionMax = 10,
    biteDefense = 20, scratchDefense = 30,
})
local rollbackClothingActor = actor("sc-clothing-rollback", 10, 3,
    { inventory = inventory({ rollbackShirt, rejectedUpgradeShirt }) })
rollbackClothingActor:setWornItem("Shirt", rollbackShirt)
local normalSetWornItem = rollbackClothingActor.setWornItem
function rollbackClothingActor:setWornItem(location, candidate)
    normalSetWornItem(self, location, candidate)
    return candidate ~= rejectedUpgradeShirt
end
local rejectedClothingUpdate, rejectedClothingReason = SurvivorCompanion.Logistics.update(
    rollbackClothingActor, nil, {
        snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
    })
check(not rejectedClothingUpdate and rejectedClothingReason == "wearable_equip_failed"
    and rollbackClothingActor:getWornItem("Shirt") == rollbackShirt
    and not rollbackClothingActor:isEquippedClothing(rejectedUpgradeShirt)
    and SurvivorCompanion.ActionSupervisor.snapshot(rollbackClothingActor).phase == "idle"
    and SurvivorCompanion.ActionSupervisor.reservationCount(rollbackClothingActor) == 0,
    "failed clothing mutation rolls back exactly and releases action ownership")
local rejectedClothingRetry, rejectedClothingRetryReason =
    SurvivorCompanion.Logistics.update(rollbackClothingActor, nil, {
        snapshot = { threats = {}, immediateCount = 0, threatCount = 0, pressure = 0 },
    })
check(not rejectedClothingRetry and rejectedClothingRetryReason == "retry_cooldown"
    and rollbackClothingActor:getWornItem("Shirt") == rollbackShirt,
    "an unchanged failed wearable transaction cannot restart on the next AI tick")

local unsafeCorpseFood = item("Base.CannedSardines", "Food", { weight = 1 })
local unsafeCorpseLooter = actor("sc-corpse-unsafe", 11, 0, {})
registry[unsafeCorpseLooter.id] = unsafeCorpseLooter
SurvivorCompanion.Commands.issue(unsafeCorpseLooter.id, "set_scavenge", true, player)
local unsafeCorpseContainer = zombieCorpseObject(unsafeCorpseLooter.square, { unsafeCorpseFood })
local corpseLootDuringCombat = SurvivorCompanion.Encounter.tryScavenge(unsafeCorpseLooter, nil, {
    snapshot = { threats = { { actor = zed } }, immediateCount = 0,
        threatCount = 1, pressure = 0 },
})
check(not corpseLootDuringCombat and unsafeCorpseContainer:contains(unsafeCorpseFood)
    and not unsafeCorpseLooter.inventory:contains(unsafeCorpseFood),
    "zombie corpses are never looted while any combat threat is present")
end
testLoadoutAndCorpseLogistics()

local neutralReject = actor("sc-neutral-reject", -4, 4, { recruited = false })
neutralReject.modData.SC_Recruited = false
neutralReject.rejectMovement = true
registry[neutralReject.id] = neutralReject
local neutralFallback = SurvivorCompanion.Encounter.update(neutralReject, player, {
    snapshot = {
        threats = { { actor = zed } }, immediateAttackers = { { actor = zed } },
        threatCount = 1, immediateCount = 1, pressure = 1.5, escapeSquares = {}, allies = {},
    },
})
check(not neutralFallback, "encounter fallback movement propagates Actor rejection")
local spawnSquare = SurvivorCompanion.Encounter.chooseSpawnSquare(player, {})
check(spawnSquare ~= nil and spawnSquare.hidden == true and SurvivorCompanion.GameplayUtil.isSquareFree(spawnSquare),
    "production spawn chooser returns a loaded, unseen, valid square")

local book = item("Base.BookFirstAid1", "Literature", { pages = 220 })
local idleActor = actor("sc-idle", -2, 0, { inventory = inventory({ book }) })
idleActor.modData.SC_Order = "stay"
idleActor.modData.SC_WorkMode = "idle"
registry[idleActor.id] = idleActor
local safeRuntime = { snapshot = { threats = {}, threatCount = 0, immediateCount = 0, player = { danger = 0 } } }
local downtimeStarted = SurvivorCompanion.Downtime.update(idleActor, player, safeRuntime)
clock = clock + 1
local downtimeFinished = SurvivorCompanion.Downtime.update(idleActor, player, safeRuntime)
check(downtimeStarted and downtimeFinished and SurvivorCompanion.Downtime.peek(idleActor).lastFact.activity == "read", "safe idle actor completes grounded reading downtime")
clock = clock + 1
SurvivorCompanion.Downtime.update(idleActor, player, safeRuntime)
check(SurvivorCompanion.Downtime.peek(idleActor).active == nil,
    "ambient cooldown prevents immediately rereading the same book forever")
local dangerRuntime = { snapshot = { threats = { { actor = zed } }, threatCount = 1, immediateCount = 1, player = { danger = 0 } } }
SurvivorCompanion.Downtime.update(idleActor, player, dangerRuntime)
check(SurvivorCompanion.Downtime.peek(idleActor).active == nil, "downtime cancels immediately on danger")

local outdoorBook = item("Base.BookOutdoors", "Literature", { pages = 120 })
local outdoorFollower = actor("sc-outdoor-follow-idle", -1, 1,
    { inventory = inventory({ outdoorBook }) })
outdoorFollower.modData.SC_Order = "follow"
local outdoorRuntime = { snapshot = {
    threats = {}, threatCount = 0, immediateCount = 0,
    indoors = false, player = { danger = 0 },
} }
local outdoorDowntime = SurvivorCompanion.Downtime.update(
    outdoorFollower, player, outdoorRuntime)
check(not outdoorDowntime and SurvivorCompanion.Downtime.peek(outdoorFollower).active == nil,
    "a close follow companion never starts reading, crafting, washing, or sitting outdoors")

function SurvivorCompanion.__testCompanionWashing()
BloodBodyPartType = {
    MAX = { index = function() return 2 end },
    FromIndex = function(index) return index end,
}
local dirtyVisual = { blood = { [0] = 0.8, [1] = 0 }, dirt = { [0] = 0.2, [1] = 0 } }
function dirtyVisual:getBlood(part) return self.blood[part] or 0 end
function dirtyVisual:getDirt(part) return self.dirt[part] or 0 end
function dirtyVisual:setBlood(part, amount) self.blood[part] = amount end
function dirtyVisual:setDirt(part, amount) self.dirt[part] = amount end
local washSquare = cell:getGridSquare(-2, 5, 0)
local sink = { square = washSquare, fluid = 40 }
function sink:getSquare() return self.square end
function sink:getX() return self.square.x + 0.5 end
function sink:getY() return self.square.y + 0.5 end
function sink:getZ() return self.square.z end
function sink:getFluidAmount() return self.fluid end
function sink:isTaintedWater() return false end
function sink:useFluid(amount) self.fluid = self.fluid - amount end
function sink:transmitModData() self.transmitted = true end
washSquare.objects[#washSquare.objects + 1] = sink
local washActor = actor("sc-wash-self", -2, 5, { humanVisual = dirtyVisual })
washActor.modData.SC_Order = "stay"
local washStarted = SurvivorCompanion.Downtime.update(washActor, player, safeRuntime)
local washFinished = SurvivorCompanion.Downtime.update(washActor, player, safeRuntime)
check(washStarted and washFinished and dirtyVisual:getBlood(0) == 0
    and dirtyVisual:getDirt(0) == 0 and sink.fluid == 39,
    "safe idle companions wash their body at a nearby clean water source and consume water")

local dirtyJacket = item("Base.Jacket_LeatherWildRacoons", "Clothing", {
    bodyLocation = "Jacket", bloodLevel = 50, dirtiness = 25,
})
local washBagInventory = inventory({ dirtyJacket })
local washBag = item("Base.Bag_DuffelBag", "Container", {
    nestedInventory = washBagInventory, bagCapacity = 18, weightReduction = 65,
    bodyLocation = "Back", equipLocation = "Back",
})
local gearWashActor = actor("sc-wash-gear", -2, 5,
    { inventory = inventory({ washBag }) })
gearWashActor.modData.SC_Order = "stay"
local gearWashStarted = SurvivorCompanion.Downtime.update(gearWashActor, player, safeRuntime)
local gearWashFinished = SurvivorCompanion.Downtime.update(gearWashActor, player, safeRuntime)
check(gearWashStarted and gearWashFinished and dirtyJacket:getBloodLevel() == 0
    and dirtyJacket:getDirtiness() == 0 and sink.fluid < 39,
    "downtime inventory inspection reaches inside bags and washes dirty equipment")
end
SurvivorCompanion.__testCompanionWashing()
SurvivorCompanion.__testCompanionWashing = nil

local rejectedBook = item("Base.BookCarpentry1", "Literature", { pages = 220 })
local rejectedIdle = actor("sc-idle-reject", -3, 0, { inventory = inventory({ rejectedBook }) })
rejectedIdle.modData.SC_Order = "stay"
rejectedIdle.rejectActions = { read = true }
registry[rejectedIdle.id] = rejectedIdle
check(not SurvivorCompanion.Downtime.update(rejectedIdle, player, safeRuntime)
    and SurvivorCompanion.Downtime.peek(rejectedIdle).active == nil
    and SurvivorCompanion.Downtime.peek(rejectedIdle).lastFact == nil,
    "rejected downtime start records neither an active action nor completion")

local damagedTool = item("Base.Crowbar", "Weapon", { condition = 2, conditionMax = 10 })
local repairGlue = item("Base.Woodglue", "Item")
local repairInventory = inventory({ damagedTool, repairGlue })
repairInventory.rejectRemoveItem = repairGlue
local repairActor = actor("sc-repair-rollback", -3, 1, { inventory = repairInventory })
repairActor.modData.SC_Order = "stay"
registry[repairActor.id] = repairActor
check(SurvivorCompanion.Downtime.update(repairActor, player, safeRuntime), "repair downtime action starts")
local repairFinished = SurvivorCompanion.Downtime.update(repairActor, player, safeRuntime)
check(not repairFinished and damagedTool.condition == 2 and repairInventory:contains(repairGlue),
    "failed repair material consumption restores item condition and loses no material")

local craftSheet = item("Base.Sheet", "Item")
local craftInventory = inventory({ craftSheet })
craftInventory.rejectRemoveItem = craftSheet
local craftActor = actor("sc-craft-rollback", -3, 2, { inventory = craftInventory })
craftActor.modData.SC_Order = "stay"
craftActor.modData.SC_WorkMode = "craft"
registry[craftActor.id] = craftActor
check(SurvivorCompanion.Downtime.update(craftActor, player, safeRuntime), "craft downtime action starts")
local craftFinished = SurvivorCompanion.Downtime.update(craftActor, player, safeRuntime)
check(not craftFinished and craftInventory:contains(craftSheet)
    and not craftInventory:contains("Base.SheetRope"),
    "failed sheet-rope crafting rolls its output back and retains the sheet")

local successfulSheet = item("Base.Sheet", "Item")
local successfulCraftInventory = inventory({ successfulSheet })
local successfulCraftActor = actor("sc-craft-success", -4, 2,
    { inventory = successfulCraftInventory })
successfulCraftActor.modData.SC_Order = "stay"
successfulCraftActor.modData.SC_WorkMode = "craft"
registry[successfulCraftActor.id] = successfulCraftActor
check(SurvivorCompanion.Downtime.update(successfulCraftActor, player, safeRuntime),
    "explicit craft work mode starts the real sheet-rope recipe")
check(SurvivorCompanion.Downtime.update(successfulCraftActor, player, safeRuntime)
    and not successfulCraftInventory:contains(successfulSheet)
    and successfulCraftInventory:contains("Base.SheetRope"),
    "one sheet becomes one sheet rope after the verified craft action")

local seatSquare = squares[squareKey(-2, 5, 0)]
local testSeat = { square = seatSquare }
function testSeat:getSquare() return self.square end
function testSeat:getX() return self.square.x end
function testSeat:getY() return self.square.y end
function testSeat:getZ() return self.square.z end
function testSeat:getName() return "Chair" end
seatSquare.objects[#seatSquare.objects + 1] = testSeat
local seatActor = actor("sc-seat-reject", -5, 5, {})
seatActor.modData.SC_Order = "stay"
registry[seatActor.id] = seatActor
local originalSeatRequest = SurvivorCompanion.Navigation.request
SurvivorCompanion.Navigation.request = function() return true, "moving" end
check(SurvivorCompanion.Downtime.update(seatActor, player, safeRuntime), "seat approach can be reserved and started")
SurvivorCompanion.Navigation.request = function() return false, "mock_approach_rejected" end
local rejectedSeatApproach = SurvivorCompanion.Downtime.update(seatActor, player, safeRuntime)
SurvivorCompanion.Navigation.request = originalSeatRequest
check(not rejectedSeatApproach and SurvivorCompanion.Downtime.peek(seatActor).active == nil,
    "ongoing seat approach propagates navigation rejection and releases the activity")

function SurvivorCompanion.__testCurtainHabits()
local curtainSquare = squares[squareKey(-4, 7, 0)]
curtainSquare.room = { name = "bedroom" }
local testCurtain = { __class = "IsoCurtain", square = curtainSquare, open = true }
function testCurtain:getSquare() return self.square end
function testCurtain:getX() return self.square.x end
function testCurtain:getY() return self.square.y end
function testCurtain:getZ() return self.square.z end
function testCurtain:IsOpen() return self.open end
function testCurtain:ToggleDoor(character)
    if self.noopToggle then return true end
    self.open = not self.open
end
curtainSquare.objects[#curtainSquare.objects + 1] = testCurtain
local curtainActor = actor("sc-curtain", -4, 7, {})
curtainActor.modData.SC_Order = "stay"
curtainActor.modData.SC_CombatDoctrine = "stealth"
registry[curtainActor.id] = curtainActor
local curtainThreat = { threatCount = 1, immediateCount = 1 }
local attemptedCurtain = SurvivorCompanion.Downtime.considerCurtain(
    curtainActor, curtainThreat, clock)
check(not attemptedCurtain and testCurtain.open,
    "curtain habit never outranks an active zombie threat")

worldHour = 12
local stealthClosed = false
for _ = 1, 20 do
    clock = clock + 12001
    local closeAttempted, closeAccepted = SurvivorCompanion.Downtime.considerCurtain(
        curtainActor, { threatCount = 0, immediateCount = 0 }, clock)
    if closeAttempted and closeAccepted and not testCurtain.open then stealthClosed = true break end
end
check(stealthClosed, "safe stealth downtime sometimes closes an open indoor curtain")

check(SurvivorCompanion.Commands.issue(curtainActor.id, "set_combat_doctrine",
        { doctrine = "close_defense" }, player),
    "curtain fixture can leave stealth doctrine")
local openedCurtain = false
for _ = 1, 100 do
    clock = clock + 12001
    local openAttempted, openAccepted = SurvivorCompanion.Downtime.considerCurtain(
        curtainActor,
        { threatCount = 0, immediateCount = 0 },
        clock
    )
    if openAttempted and openAccepted and testCurtain.open then openedCurtain = true break end
end
check(openedCurtain, "safe daylight cadence occasionally opens a nearby indoor curtain")
worldHour = 22
clock = clock + 45001
local nightAttempted, nightAccepted = SurvivorCompanion.Downtime.considerCurtain(
    curtainActor,
    { threatCount = 0, immediateCount = 0 },
    clock
)
check(nightAttempted and nightAccepted and not testCurtain.open,
    "nighttime indoor curtain decision closes for concealment")
worldHour = 12

local farRoom = { name = "warehouse" }
local farActorSquare = squares[squareKey(-4, 6, 0)]
local farCurtainSquare = squares[squareKey(-1, 6, 0)]
farActorSquare.room, farCurtainSquare.room = farRoom, farRoom
local farCurtain = { __class = "IsoCurtain", square = farCurtainSquare, open = true }
function farCurtain:getSquare() return self.square end
function farCurtain:getX() return self.square.x end
function farCurtain:getY() return self.square.y end
function farCurtain:getZ() return self.square.z end
function farCurtain:IsOpen() return self.open end
function farCurtain:ToggleDoor(character) self.open = not self.open end
farCurtainSquare.objects[#farCurtainSquare.objects + 1] = farCurtain
local farCurtainActor = actor("sc-curtain-approach", -4, 6, {})
farCurtainActor.modData.SC_Order = "stay"
farCurtainActor.modData.SC_CombatDoctrine = "stealth"
registry[farCurtainActor.id] = farCurtainActor
local approachStarted = false
for _ = 1, 20 do
    clock = clock + 12001
    local attempted, accepted, reason = SurvivorCompanion.Downtime.considerCurtain(
        farCurtainActor, { threatCount = 0, immediateCount = 0 }, clock)
    if attempted and accepted and reason == "approaching_curtain" then
        approachStarted = true
        break
    end
end
check(approachStarted and SurvivorCompanion.Downtime.peek(farCurtainActor).curtainTask ~= nil
        and farCurtain.open,
    "a stealth companion reserves and walks toward an open curtain in the same building")
farCurtainActor.square, farCurtainActor.worldX, farCurtainActor.worldY = farCurtainSquare, nil, nil
local arrivedAttempted, arrivedAccepted = SurvivorCompanion.Downtime.considerCurtain(
    farCurtainActor, { threatCount = 0, immediateCount = 0 }, clock + 100)
check(arrivedAttempted and arrivedAccepted and not farCurtain.open
        and SurvivorCompanion.Downtime.peek(farCurtainActor).curtainTask == nil,
    "the reserved curtain is closed only after the companion physically arrives")

local noOpCurtainSquare = squares[squareKey(-5, 7, 0)]
noOpCurtainSquare.room = { name = "bedroom" }
local noOpCurtain = { __class = "IsoCurtain", square = noOpCurtainSquare, open = true, noopToggle = true }
function noOpCurtain:getSquare() return self.square end
function noOpCurtain:getX() return self.square.x end
function noOpCurtain:getY() return self.square.y end
function noOpCurtain:getZ() return self.square.z end
function noOpCurtain:IsOpen() return self.open end
function noOpCurtain:ToggleDoor(character) return true end
noOpCurtainSquare.objects[#noOpCurtainSquare.objects + 1] = noOpCurtain
local noOpCurtainActor = actor("sc-curtain-noop", -5, 7, {})
noOpCurtainActor.modData.SC_Order = "stay"
registry[noOpCurtainActor.id] = noOpCurtainActor
worldHour = 22
SurvivorCompanion.Downtime.considerCurtain(
    noOpCurtainActor, { threatCount = 0, immediateCount = 0 }, clock)
clock = clock + 12001
local noOpCurtainAttempted, noOpCurtainAccepted = SurvivorCompanion.Downtime.considerCurtain(
    noOpCurtainActor,
    { threatCount = 0, immediateCount = 0 },
    clock
)
check(noOpCurtainAttempted and not noOpCurtainAccepted and noOpCurtain.open,
    "curtain decision propagates a native no-op postcondition failure")
worldHour = 12

end
SurvivorCompanion.__testCurtainHabits()
SurvivorCompanion.__testCurtainHabits = nil

clock = clock + 10
local decisionRuntime = { snapshot = snapshot }
local soundsBeforeThreatWarning = worldSoundCount
check(not SurvivorCompanion.Decision.update(fellow, player, decisionRuntime),
    "decision cadence staggers the first per-actor combat deadline")
check(worldSoundCount == soundsBeforeThreatWarning,
    "immediate contact reserves the overhead line for the selected combat action")
clock = clock + 101
local decided = SurvivorCompanion.Decision.update(fellow, player, decisionRuntime)
local decision = SurvivorCompanion.Decision.peek(fellow)
check(decided and decision and decision.current == "combat", "utility arbitration prioritizes an immediate combat threat")
local describedAfterDecision = SurvivorCompanion.Commands.describe(fellow.id, player)
check(describedAfterDecision.intent == decision.intent, "read-only description exposes decision intent")
check(type(fellow.lastSpeech) == "string" and worldSoundCount == soundsBeforeThreatWarning + 1,
    "the accepted close-combat choice emits one action-specific bark and bounded local sound")

function SurvivorCompanion.__testSharedThreatAlert()
    local alertListener = actor("sc-alert-listener", 0, 3, {})
    local alertTestPlayer = actor("alert-test-player", 0, 4,
        { className = "IsoPlayer", recruited = false })
    alertTestPlayer.modData.SC_Recruited = false
    registry[alertListener.id] = alertListener
    local alertRuntime = {
        snapshot = {
            threats = {}, threatCount = 0, immediateCount = 0, pressure = 0,
            escapeSquares = {}, allies = {}, player = { danger = 0 },
            sounds = { {
                kind = "companion_alert", source = fellow,
                x = 1.5, y = 0.5, z = 0, time = clock, distanceSq = 8,
            } },
        },
    }
    local previousPerceptionInterval = SurvivorCompanion.Config.values.perceptionIntervalMs
    SurvivorCompanion.Config.values.perceptionIntervalMs = 1000000
    SurvivorCompanion.Decision.update(alertListener, alertTestPlayer, alertRuntime)
    for _ = 1, 3 do
        clock = clock + 201
        SurvivorCompanion.Decision.update(alertListener, alertTestPlayer, alertRuntime)
        if alertListener.lastIntent and alertListener.lastIntent.action == "face_alert" then break end
    end
    SurvivorCompanion.Config.values.perceptionIntervalMs = previousPerceptionInterval
    check(alertListener.lastIntent and alertListener.lastIntent.action == "face_alert"
        and SurvivorCompanion.Decision.peek(alertListener).intent == "shared_threat_alert",
        "a companion warning causes nearby companions to face the reported danger without blindly charging")
end
SurvivorCompanion.__testSharedThreatAlert()
SurvivorCompanion.__testSharedThreatAlert = nil
clock = clock + 8001 -- expire the synthetic alert before unrelated role/work tests

local cadenceOne = actor("sc-cadence-one", -7, 6, {})
local cadenceTwo = actor("sc-cadence-two", -6, 6, {})
check(not SurvivorCompanion.GameplayUtil.isDue(cadenceOne, "stable_phase", 1000, clock)
    and not SurvivorCompanion.GameplayUtil.isDue(cadenceTwo, "stable_phase", 1000, clock)
    and SurvivorCompanion.GameplayUtil.peekActorState(cadenceOne).timers.stable_phase
        ~= SurvivorCompanion.GameplayUtil.peekActorState(cadenceTwo).timers.stable_phase,
    "cadence uses stable hashed staggering rather than an all-actor first-frame burst")

local function decisionAfterDue(testActor, testPlayer, runtime, delay)
    SurvivorCompanion.Decision.update(testActor, testPlayer, runtime)
    clock = clock + (delay or 201)
    return SurvivorCompanion.Decision.update(testActor, testPlayer, runtime)
end

local guardActor = actor("sc-guard-patrol", -7, -6, {})
local originalRoleTestMedical = SurvivorCompanion.Medical
SurvivorCompanion.Medical = nil
local guardTestPlayer = actor("guard-test-player", -7, -2,
    { className = "IsoPlayer", recruited = false })
guardTestPlayer.modData.SC_Recruited = false
guardActor.modData.SC_Order = "guard"
guardActor.modData.SC_AnchorX = guardActor.square.x
guardActor.modData.SC_AnchorY = guardActor.square.y
guardActor.modData.SC_AnchorZ = guardActor.square.z
registry[guardActor.id] = guardActor
local originalGuardNavigation = SurvivorCompanion.Navigation.request
local guardPatrolIntent
SurvivorCompanion.Navigation.request = function(targetActor, target, mode, intent)
    if targetActor == guardActor then guardPatrolIntent = intent return true, "moving" end
    return originalGuardNavigation(targetActor, target, mode, intent)
end
local guardRuntime = {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}
local guardHandled = false
SurvivorCompanion.Decision.update(guardActor, guardTestPlayer, guardRuntime)
for _ = 1, 5 do
    clock = clock + 201
    guardHandled = SurvivorCompanion.Decision.update(guardActor, guardTestPlayer, guardRuntime)
    if guardPatrolIntent then break end
end
SurvivorCompanion.Navigation.request = originalGuardNavigation
check(guardHandled and guardPatrolIntent and guardPatrolIntent.action == "guard_patrol"
    and SurvivorCompanion.GameplayUtil.distance(guardActor, guardPatrolIntent.targetSquare) <= 5,
    "base guard chooses a bounded patrol point inside its permanent guard radius: handled="
        .. tostring(guardHandled) .. " intent=" .. tostring(guardPatrolIntent and guardPatrolIntent.action)
        .. " decision=" .. tostring(SurvivorCompanion.Decision.peek(guardActor).intent))

local buildActor = actor("sc-build-work", -7, -4, { inventory = inventory(buildKit()) })
registry[buildActor.id] = buildActor
check(SurvivorCompanion.Commands.issue(buildActor.id, "stay", nil, guardTestPlayer)
    and SurvivorCompanion.Commands.issue(buildActor.id, "set_work_mode", { mode = "idle" }, guardTestPlayer),
    "build fixture starts from a permanent idle/stay role")
local buildObject = { square = buildActor.square, objectIndex = #buildActor.square.objects, built = false }
function buildObject:getSquare() return self.square end
function buildObject:getX() return self.square.x + 0.5 end
function buildObject:getY() return self.square.y + 0.5 end
function buildObject:getZ() return self.square.z end
function buildObject:getObjectIndex() return self.objectIndex end
function buildObject:isBarricadeAllowed() return true end
function buildObject:getBarricadeForCharacter()
    if not self.built then return nil end
    return { getNumPlanks = function() return 1 end, canAddPlank = function() return true end }
end
buildActor.square.objects[#buildActor.square.objects + 1] = buildObject
check(SurvivorCompanion.Commands.issue(buildActor.id, "barricade", { object = buildObject }, guardTestPlayer),
    "targeted barricade command enters one-shot build work")
check(decisionAfterDue(buildActor, guardTestPlayer, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and buildActor.lastIntent.action == "barricade",
    "one-shot build decision starts the native barricade intent")
buildObject.built = true
check(SurvivorCompanion.Commands.peek(buildActor).workTarget.initialPlanks == 0,
    "one-shot build persists the pre-work plank baseline")
SurvivorCompanion.Decision.reset(buildActor)
SurvivorCompanion.Commands.reset(buildActor)
buildActor.lastIntent = nil
local buildCompletionRuntime = {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}
for _ = 1, 5 do
    clock = clock + 201
    SurvivorCompanion.Decision.update(buildActor, guardTestPlayer, buildCompletionRuntime)
    if SurvivorCompanion.Commands.peek(buildActor).order ~= "work" then break end
end
local returnedBuildState = SurvivorCompanion.Commands.peek(buildActor)
check(returnedBuildState.order == "stay" and returnedBuildState.workMode == "idle"
    and returnedBuildState.workTarget == nil and buildActor.lastIntent == nil,
    "save/load after construction detects completion without applying another plank and returns role: order="
        .. tostring(returnedBuildState.order) .. " mode=" .. tostring(returnedBuildState.workMode)
        .. " target=" .. tostring(returnedBuildState.workTarget)
        .. " decision=" .. tostring(SurvivorCompanion.Decision.peek(buildActor).intent))

function SurvivorCompanion.__testDestructiveTargetWork()
local removeActor = actor("sc-remove-work", -8, -4, {})
registry[removeActor.id] = removeActor
local removeBarricade = {
    planks = 2,
    square = removeActor.square,
    objectIndex = #removeActor.square.objects,
}
local barricade = { getNumPlanks = function() return removeBarricade.planks end }
function removeBarricade:getSquare() return self.square end
function removeBarricade:getX() return self.square.x + 0.5 end
function removeBarricade:getY() return self.square.y + 0.5 end
function removeBarricade:getZ() return self.square.z end
function removeBarricade:getObjectIndex() return self.objectIndex end
function removeBarricade:isBarricaded() return self.planks > 0 end
function removeBarricade:getBarricadeForCharacter() return self.planks > 0 and barricade or nil end
function removeBarricade:getBarricadeOnSameSquare() return self.planks > 0 and barricade or nil end
function removeBarricade:getBarricadeOnOppositeSquare() return nil end
function removeBarricade:getNorth() return true end
removeActor.square.objects[#removeActor.square.objects + 1] = removeBarricade
check(SurvivorCompanion.Commands.issue(removeActor.id, "remove_barricade", {
        object = removeBarricade, barricadeSide = "same",
    }, guardTestPlayer),
    "targeted remove-barricade command enters one-shot work")
check(SurvivorCompanion.Commands.peek(removeActor).workTarget.kind == "remove_barricade"
        and SurvivorCompanion.Commands.peek(removeActor).workTarget.barricadeSide == "same",
    "remove-barricade work retains the player-selected side")
check(decisionAfterDue(removeActor, guardTestPlayer, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and removeActor.lastIntent and removeActor.lastIntent.action == "remove_barricade",
    "remove-barricade decision starts the real destructive work intent")

local dismantleActor = actor("sc-dismantle-work", -9, -4, {})
registry[dismantleActor.id] = dismantleActor
local dismantleObject = {
    __class = "IsoThumpable",
    square = dismantleActor.square,
    objectIndex = #dismantleActor.square.objects,
}
function dismantleObject:getSquare() return self.square end
function dismantleObject:getX() return self.square.x + 0.5 end
function dismantleObject:getY() return self.square.y + 0.5 end
function dismantleObject:getZ() return self.square.z end
function dismantleObject:getObjectIndex() return self.objectIndex end
function dismantleObject:isDismantable() return true end
dismantleActor.square.objects[#dismantleActor.square.objects + 1] = dismantleObject
check(SurvivorCompanion.Commands.issue(dismantleActor.id, "dismantle", {
        object = dismantleObject,
    }, guardTestPlayer),
    "targeted dismantle command enters one-shot work")
check(decisionAfterDue(dismantleActor, guardTestPlayer, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and dismantleActor.lastIntent and dismantleActor.lastIntent.action == "dismantle",
    "dismantle decision starts the real destructive work intent")
registry[removeActor.id], registry[dismantleActor.id] = nil, nil
end
SurvivorCompanion.__testDestructiveTargetWork()
SurvivorCompanion.__testDestructiveTargetWork = nil

function SurvivorCompanion.__testExclusiveWorkReservation()
local reserveActorOne = actor("sc-build-reserve-one", -7, -7, { inventory = inventory(buildKit()) })
local reserveActorTwo = actor("sc-build-reserve-two", -7, -7, { inventory = inventory(buildKit()) })
registry[reserveActorOne.id] = reserveActorOne
registry[reserveActorTwo.id] = reserveActorTwo
local sharedBuildObject = {
    square = reserveActorOne.square,
    objectIndex = #reserveActorOne.square.objects,
}
function sharedBuildObject:getSquare() return self.square end
function sharedBuildObject:getX() return self.square.x + 0.5 end
function sharedBuildObject:getY() return self.square.y + 0.5 end
function sharedBuildObject:getZ() return self.square.z end
function sharedBuildObject:getObjectIndex() return self.objectIndex end
function sharedBuildObject:isBarricadeAllowed() return true end
function sharedBuildObject:getBarricadeForCharacter() return nil end
reserveActorOne.square.objects[#reserveActorOne.square.objects + 1] = sharedBuildObject
check(SurvivorCompanion.Commands.issue(
        reserveActorOne.id, "barricade", { object = sharedBuildObject }, guardTestPlayer)
    and SurvivorCompanion.Commands.issue(
        reserveActorTwo.id, "barricade", { object = sharedBuildObject }, guardTestPlayer),
    "two companions may queue sequential work on one stable target")
local sharedWorkSnapshot = { threats = {}, threatCount = 0, immediateCount = 0,
    escapeSquares = {}, allies = {}, player = { danger = 0 } }
local sharedWorkRuntimeOne = { snapshot = sharedWorkSnapshot }
local sharedWorkRuntimeTwo = { snapshot = sharedWorkSnapshot }
SurvivorCompanion.GameplayUtil.actorState(reserveActorOne).timers = {
    perception = clock + 1000000,
}
SurvivorCompanion.GameplayUtil.actorState(reserveActorTwo).timers = {
    perception = clock + 1000000,
}
for _ = 1, 5 do
    clock = clock + 201
    SurvivorCompanion.Decision.update(reserveActorOne, guardTestPlayer, sharedWorkRuntimeOne)
    if reserveActorOne.lastIntent then break end
end
check(reserveActorOne.lastIntent and reserveActorOne.lastIntent.action == "barricade",
    "first companion acquires the exclusive target reservation: intent="
        .. tostring(SurvivorCompanion.Decision.peek(reserveActorOne).intent)
        .. " action=" .. tostring(reserveActorOne.lastIntent and reserveActorOne.lastIntent.action))
reserveActorTwo.lastIntent = nil
for _ = 1, 4 do
    clock = clock + 201
    SurvivorCompanion.Decision.update(reserveActorTwo, guardTestPlayer, sharedWorkRuntimeTwo)
    if SurvivorCompanion.Decision.peek(reserveActorTwo).intent == "work_reserved_by_companion" then break end
end
check(reserveActorTwo.lastIntent == nil
    and SurvivorCompanion.Decision.peek(reserveActorTwo).intent == "work_reserved_by_companion",
    "second companion waits without starting a conflicting native work action: intent="
        .. tostring(SurvivorCompanion.Decision.peek(reserveActorTwo).intent)
        .. " action=" .. tostring(reserveActorTwo.lastIntent and reserveActorTwo.lastIntent.action))
local cancelledBuildActions = 0
SurvivorCompanion.NativeActions = {
    cancelWork = function(targetActor)
        if targetActor == reserveActorOne then cancelledBuildActions = cancelledBuildActions + 1 end
        return true, "cancelled"
    end,
}
check(SurvivorCompanion.Commands.issue(reserveActorOne.id, "stay", nil, guardTestPlayer)
    and cancelledBuildActions == 1,
    "a new command cancels the previous native build action before role transition")
reserveActorTwo.lastIntent = nil
for _ = 1, 5 do
    clock = clock + 201
    SurvivorCompanion.Decision.update(reserveActorTwo, guardTestPlayer, sharedWorkRuntimeTwo)
    if reserveActorTwo.lastIntent then break end
end
check(reserveActorTwo.lastIntent and reserveActorTwo.lastIntent.action == "barricade",
    "released work reservation lets the waiting companion continue")
SurvivorCompanion.Decision.reset(reserveActorOne)
SurvivorCompanion.Decision.reset(reserveActorTwo)
SurvivorCompanion.NativeActions = nil
end
SurvivorCompanion.__testExclusiveWorkReservation()
SurvivorCompanion.__testExclusiveWorkReservation = nil
SurvivorCompanion.Medical = originalRoleTestMedical

local boardActor = actor("sc-decision-board", -6, -4, {})
registry[boardActor.id] = boardActor
boardActor.rejectActions = { board_vehicle = true }
local testVehicle = {}
player.vehicle = testVehicle
check(not decisionAfterDue(boardActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201), "decision board-vehicle path propagates executor rejection")
player.vehicle = nil

local exitActor = actor("sc-decision-exit", -6, -3, {})
registry[exitActor.id] = exitActor
exitActor.vehicle = testVehicle
exitActor.rejectActions = { exit_vehicle = true }
check(not decisionAfterDue(exitActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201), "decision exit-vehicle path propagates executor rejection")

function SurvivorCompanion.__testSafeVehiclePolicyExit()
    local previousVehicleAdapter = SurvivorCompanion.Vehicle
    local previousMedicalAdapter = SurvivorCompanion.Medical
    local previousSensesAdapter = SurvivorCompanion.Senses
    local safeExitVehicle = { speed = 30 }
    SurvivorCompanion.Vehicle = {
        isStationary = function(candidate)
            return candidate.speed <= 0.5,
                candidate.speed <= 0.5 and nil or "vehicle is moving"
        end,
    }
    SurvivorCompanion.Medical = {
        assess = function()
            return { health = 100, alive = true, critical = false,
                needsBandage = false, downed = false, bleedingCount = 0 }
        end,
    }
    SurvivorCompanion.Senses = {
        snapshot = function()
            return { threats = {}, threatCount = 0, immediateCount = 0,
                escapeSquares = {}, allies = {}, sounds = {}, player = { danger = 0 } }
        end,
    }
    local safeExitActor = actor("sc-decision-safe-exit", -6, -2, {})
    local safeExitPlayer = actor("sc-decision-safe-player", -6, -1, {
        recruited = false, body = bodyDamage(100),
    })
    safeExitPlayer.modData.SC_Recruited = false
    registry[safeExitActor.id] = safeExitActor
    safeExitActor.vehicle = safeExitVehicle
    safeExitPlayer.vehicle = safeExitVehicle
    check(SurvivorCompanion.Commands.issue(safeExitActor.id, "stay", nil, safeExitPlayer)
            and SurvivorCompanion.Commands.issue(safeExitActor.id, "set_ride_with_player",
                { enabled = false }, safeExitPlayer),
        "Ride with player can be disabled while a non-following companion is seated")
    local safeExitRuntime = {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
            escapeSquares = {}, allies = {}, player = { danger = 0 } },
    }
    local movingHandled = false
    for _ = 1, 5 do
        movingHandled = SurvivorCompanion.Decision.update(safeExitActor, safeExitPlayer, safeExitRuntime)
        if SurvivorCompanion.Decision.peek(safeExitActor).intent == "waiting_for_safe_exit" then break end
        clock = clock + 301
    end
    check(movingHandled and safeExitActor.lastIntent == nil
            and SurvivorCompanion.Decision.peek(safeExitActor).intent == "waiting_for_safe_exit",
        "disabling Ride while moving waits without issuing an unsafe exit: handled="
            .. tostring(movingHandled) .. " action="
            .. tostring(safeExitActor.lastIntent and safeExitActor.lastIntent.action)
            .. " intent=" .. tostring(SurvivorCompanion.Decision.peek(safeExitActor).intent))
    safeExitVehicle.speed = 0
    local stoppedHandled = false
    for _ = 1, 5 do
        clock = clock + 301
        stoppedHandled = SurvivorCompanion.Decision.update(safeExitActor, safeExitPlayer, safeExitRuntime)
        if safeExitActor.lastIntent and safeExitActor.lastIntent.action == "exit_vehicle" then break end
    end
    check(stoppedHandled and safeExitActor.lastIntent
            and safeExitActor.lastIntent.action == "exit_vehicle",
        "the disabled Ride policy exits automatically once the vehicle is stationary")
    safeExitPlayer.vehicle = nil
    registry[safeExitActor.id] = nil
    SurvivorCompanion.Decision.reset(safeExitActor)
    SurvivorCompanion.Commands.reset(safeExitActor)
    SurvivorCompanion.Vehicle = previousVehicleAdapter
    SurvivorCompanion.Medical = previousMedicalAdapter
    SurvivorCompanion.Senses = previousSensesAdapter
end
SurvivorCompanion.__testSafeVehiclePolicyExit()
SurvivorCompanion.__testSafeVehiclePolicyExit = nil

local retreatActor = actor("sc-decision-retreat", -6, -2, {})
retreatActor.modData.SC_Order = "retreat"
retreatActor.rejectActions = { ordered_retreat = true }
registry[retreatActor.id] = retreatActor
check(not decisionAfterDue(retreatActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 101), "decision fallback retreat never masks a rejected movement action")

local roomActor = actor("sc-room-sweep", -6, 1, {})
registry[roomActor.id] = roomActor
check(SurvivorCompanion.Commands.issue(roomActor.id, "check_room", { square = roomActor.square }, player),
    "room-check command is accepted before sweep rejection test")
roomActor.rejectActions = { room_sweep = true }
check(not decisionAfterDue(roomActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and not SurvivorCompanion.Decision.peek(roomActor).roomCheckAt,
    "room sweep records no start time when its executor action is rejected")

local fallbackPart = bodyPart({ name = "ForeArm_R", isBleeding = true })
local fallbackActor = actor("sc-decision-gates", -6, 4, { body = bodyDamage(65, { fallbackPart }) })
registry[fallbackActor.id] = fallbackActor
local fallbackZed = zombie(-5, 4, { attacking = true, target = fallbackActor })
local fallbackRuntime = {
    snapshot = {
        threats = { { actor = fallbackZed, square = fallbackZed.square, distanceSq = 1, visible = true, obstructed = false, attacking = true, score = 80 } },
        immediateAttackers = { { actor = fallbackZed } }, allies = {}, escapeSquares = {},
        threatCount = 1, immediateCount = 1, pressure = 1.5, player = { danger = 0, immediateThreats = 0 },
    },
}
check(not SurvivorCompanion.Decision.update(fallbackActor, player, fallbackRuntime),
    "medical emergency is initially deadline-staggered")
clock = clock + 101
local gatedFallback = SurvivorCompanion.Decision.update(fallbackActor, player, fallbackRuntime)
check(not gatedFallback and fallbackActor.lastIntent == nil,
    "failed medical work does not bypass the combat fallback deadline in the same frame")

local function testDecisionReturnPropagation()
local transitionPlayer = actor("transition-player", 21, 21, { className = "IsoPlayer", recruited = false })
transitionPlayer.modData.SC_Recruited = false
local moveStayActor = actor("sc-move-stay-reject", 20, 20, {})
registry[moveStayActor.id] = moveStayActor
check(SurvivorCompanion.Commands.issue(moveStayActor.id, "move_to", { square = moveStayActor.square }, transitionPlayer),
    "arrived move-to order is staged for automatic stay transition")
local moveStayState = SurvivorCompanion.Commands.peek(moveStayActor)
moveStayState.recruited = true
moveStayState.order = "move_to"
moveStayState.tacticalTarget = {
    x = moveStayActor.square.x,
    y = moveStayActor.square.y,
    z = moveStayActor.square.z,
    square = moveStayActor.square,
}
local originalCommandIssue = SurvivorCompanion.Commands.issue
local originalTransitionNavigation = SurvivorCompanion.Navigation.request
local moveStayCalls = 0
SurvivorCompanion.Commands.issue = function(id, command, payload, issuingPlayer)
    if command == "stay" then moveStayCalls = moveStayCalls + 1 return false, "mock_stay_rejected" end
    return originalCommandIssue(id, command, payload, issuingPlayer)
end
SurvivorCompanion.Navigation.request = function(targetActor, target, mode, intent)
    if targetActor == moveStayActor then return true, "arrived" end
    return originalTransitionNavigation(targetActor, target, mode, intent)
end
local moveStayRuntime = {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}
local moveStayMedical = SurvivorCompanion.Medical.assess(moveStayActor)
local transitionPlayerMedical = SurvivorCompanion.Medical.assess(transitionPlayer)
check(not moveStayMedical.critical and not moveStayMedical.needsBandage and not moveStayMedical.downed
    and not transitionPlayerMedical.critical and transitionPlayerMedical.bleedingCount == 0,
    "stay-transition fixtures have no medical utility")
SurvivorCompanion.Decision.update(moveStayActor, transitionPlayer, moveStayRuntime)
SurvivorCompanion.GameplayUtil.peekActorState(moveStayActor).timers.perception = clock + 100000
local moveStayAccepted, moveStayReason
for _ = 1, 4 do
    clock = clock + 201
    moveStayAccepted, moveStayReason = SurvivorCompanion.Decision.update(moveStayActor, transitionPlayer, moveStayRuntime)
    if moveStayReason ~= "deferred" then break end
end
SurvivorCompanion.Commands.issue = originalCommandIssue
SurvivorCompanion.Navigation.request = originalTransitionNavigation
check(not moveStayAccepted and moveStayReason == "stay_transition_rejected:mock_stay_rejected"
    and SurvivorCompanion.Commands.peek(moveStayActor).order == "move_to"
    and moveStayCalls == 1,
    "move-to arrival propagates a rejected automatic stay command: accepted="
        .. tostring(moveStayAccepted) .. " reason=" .. tostring(moveStayReason)
        .. " order=" .. tostring(SurvivorCompanion.Commands.peek(moveStayActor).order)
        .. " recruited=" .. tostring(SurvivorCompanion.Commands.peek(moveStayActor).recruited)
        .. " current=" .. tostring(SurvivorCompanion.Decision.peek(moveStayActor).current)
        .. " calls=" .. tostring(moveStayCalls))

local roomStayActor = actor("sc-room-stay-reject", 22, 20, {})
registry[roomStayActor.id] = roomStayActor
check(SurvivorCompanion.Commands.issue(roomStayActor.id, "check_room", { square = roomStayActor.square }, transitionPlayer),
    "room check is staged for automatic stay transition")
local roomStayState = SurvivorCompanion.Commands.peek(roomStayActor)
roomStayState.recruited = true
roomStayState.order = "check_room"
roomStayState.tacticalTarget = {
    x = roomStayActor.square.x,
    y = roomStayActor.square.y,
    z = roomStayActor.square.z,
    square = roomStayActor.square,
}
SurvivorCompanion.Commands.issue = function(id, command, payload, issuingPlayer)
    if command == "stay" then return false, "mock_room_stay_rejected" end
    return originalCommandIssue(id, command, payload, issuingPlayer)
end
SurvivorCompanion.Navigation.request = function(targetActor, target, mode, intent)
    if targetActor == roomStayActor then return true, "arrived" end
    return originalTransitionNavigation(targetActor, target, mode, intent)
end
local roomStayRuntime = {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}
SurvivorCompanion.Decision.update(roomStayActor, transitionPlayer, roomStayRuntime)
SurvivorCompanion.GameplayUtil.peekActorState(roomStayActor).timers.perception = clock + 100000
local roomSweepStarted = false
for _ = 1, 4 do
    clock = clock + 201
    local handled, reason = SurvivorCompanion.Decision.update(roomStayActor, transitionPlayer, roomStayRuntime)
    if handled and SurvivorCompanion.Decision.peek(roomStayActor).roomCheckAt then
        roomSweepStarted = true
        break
    end
    if reason ~= "deferred" then break end
end
check(roomSweepStarted and SurvivorCompanion.Decision.peek(roomStayActor).roomCheckAt,
    "room sweep starts before its delayed stay transition")
clock = clock + 1601
local roomStayAccepted, roomStayReason = SurvivorCompanion.Decision.update(roomStayActor, transitionPlayer, roomStayRuntime)
SurvivorCompanion.Commands.issue = originalCommandIssue
SurvivorCompanion.Navigation.request = originalTransitionNavigation
check(not roomStayAccepted and roomStayReason == "stay_transition_rejected:mock_room_stay_rejected"
    and SurvivorCompanion.Commands.peek(roomStayActor).order == "check_room"
    and SurvivorCompanion.Decision.peek(roomStayActor).roomCheckAt ~= nil,
    "room-check completion propagates stay rejection and retains retry state")

local terminalBody = bodyDamage(60)
terminalBody.infected = true
terminalBody.infectionLevel = 100
local terminalStopActor = actor("sc-dead-stop-reject", 24, 20, { body = terminalBody })
terminalStopActor.rejectStop = true
registry[terminalStopActor.id] = terminalStopActor
local terminalStopped, terminalStopReason = SurvivorCompanion.Decision.update(terminalStopActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
})
check(not terminalStopped and terminalStopReason == "dead_stop_rejected",
    "dead-terminal path propagates stop rejection explicitly")

local idleStopActor = actor("sc-idle-stop-reject", 26, 20, {})
idleStopActor.modData.SC_Order = "unknown"
idleStopActor.rejectStop = true
registry[idleStopActor.id] = idleStopActor
local idleStopped, idleStopReason = SurvivorCompanion.Decision.update(idleStopActor, player, {
    snapshot = { threats = {}, threatCount = -1, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
})
check(not idleStopped and idleStopReason == "idle_stop_rejected",
    "no-candidate path propagates stop rejection explicitly")
end
testDecisionReturnPropagation()

function SurvivorCompanion.__testNeedsAndCamp()
local rateActor = actor("sc-needs-rate", 28, 20, {})
registry[rateActor.id] = rateActor
rateActor.hunger, rateActor.thirst = 0.40, 0.30
local rateRuntime = {}
check(SurvivorCompanion.Needs.updateRates(rateActor, rateRuntime, clock),
    "needs-rate sampler accepts its initial native baseline")
clock = clock + 1001
rateActor.hunger, rateActor.thirst = 0.50, 0.40
check(SurvivorCompanion.Needs.updateRates(rateActor, rateRuntime, clock)
    and math.abs(rateActor.hunger - 0.45) < 0.001
    and math.abs(rateActor.thirst - 0.35) < 0.001,
    "positive native hunger and thirst deltas are rebated to exactly half speed")
rateActor.hunger = 0.20
clock = clock + 1001
check(SurvivorCompanion.Needs.updateRates(rateActor, rateRuntime, clock)
    and math.abs(rateActor.hunger - 0.20) < 0.001,
    "native food reductions remain fully applied instead of being scaled")
rateActor.hunger = 1.0
clock = clock + 1001
check(SurvivorCompanion.Needs.updateRates(rateActor, rateRuntime, clock)
    and math.abs(rateActor.hunger - 0.60) < 0.001,
    "accelerated-time positive hunger deltas are still halved")

local meal = item("Base.TestMeal", "Food", { hungerChange = -0.35 })
local rottenMeal = item("Base.RottenMeal", "Food", { hungerChange = -0.35, rotten = true })
local poisonedMeal = item("Base.PoisonMeal", "Food", { hungerChange = -0.35, poisonPower = 10 })
local eater = actor("sc-needs-eat", 30, 20,
    { inventory = inventory({ rottenMeal, poisonedMeal, meal }) })
eater.hunger = 0.72
registry[eater.id] = eater
check(SurvivorCompanion.Needs.update(eater, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
    }) and eater.lastIntent and eater.lastIntent.action == "eat_food"
    and eater.lastIntent.item == meal,
    "hungry companion selects a safe carried meal through a native eat intent")

local cleanFluid = { amount = 0.72 }
function cleanFluid:isEmpty() return self.amount <= 0 end
function cleanFluid:getAmount() return self.amount end
function cleanFluid:contains(kind) return kind == Fluid.Water end
local bottle = item("Base.WaterBottle", "Item", { fluidContainer = cleanFluid })
local taintedFluid = { amount = 0.72 }
function taintedFluid:isEmpty() return false end
function taintedFluid:getAmount() return self.amount end
function taintedFluid:contains(kind) return kind == Fluid.TaintedWater or kind == Fluid.Water end
local taintedBottle = item("Base.TaintedBottle", "Item", { fluidContainer = taintedFluid })
local drinker = actor("sc-needs-drink", 32, 20,
    { inventory = inventory({ taintedBottle, bottle }) })
drinker.thirst = 0.68
registry[drinker.id] = drinker
check(SurvivorCompanion.Needs.update(drinker, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
    }) and drinker.lastIntent and drinker.lastIntent.action == "drink_item"
    and drinker.lastIntent.uses >= 1,
    "thirsty companion uses a clean carried bottle through the native drink intent")

local sourceDrinker = actor("sc-needs-source", 34, 20, {})
sourceDrinker.thirst = 0.70
registry[sourceDrinker.id] = sourceDrinker
local cleanSink = { square = sourceDrinker.square, amount = 4 }
function cleanSink:getSquare() return self.square end
function cleanSink:getX() return self.square.x + 0.5 end
function cleanSink:getY() return self.square.y + 0.5 end
function cleanSink:getZ() return self.square.z end
function cleanSink:hasFluid() return self.amount > 0 end
function cleanSink:getFluidAmount() return self.amount end
function cleanSink:isTaintedWater() return false end
sourceDrinker.square.objects[#sourceDrinker.square.objects + 1] = cleanSink
check(SurvivorCompanion.Needs.update(sourceDrinker, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
    }) and sourceDrinker.lastIntent and sourceDrinker.lastIntent.action == "drink_source"
    and sourceDrinker.lastIntent.object == cleanSink,
    "thirsty companion discovers a bounded clean sink/well source")

local campActor = actor("sc-camp-supply", 36, 20, {})
registry[campActor.id] = campActor
local campFood = item("Base.CampMeal", "Food", { hungerChange = -0.25 })
local campContainer = containerObject(campActor.square, { campFood })
check(SurvivorCompanion.Encounter.markPlayerOpened(campContainer),
    "player-opened camp storage is explicitly recorded")
local campStatus = SurvivorCompanion.Encounter.takePlayerSupply(
    campActor, "test_food", function(candidate) return candidate == campFood end,
    { snapshot = { immediateCount = 0, pressure = 0 } })
check(campStatus == "taken" and campActor.inventory:contains(campFood)
    and not campContainer:contains(campFood),
    "reserved camp-storage transfer is transactional and limited to the selected item")

local unknownStorageActor = actor("sc-unknown-storage", -50, -50, {})
registry[unknownStorageActor.id] = unknownStorageActor
local unknownFood = item("Base.UnknownMeal", "Food", { hungerChange = -0.25 })
local unknownContainer = containerObject(unknownStorageActor.square, { unknownFood })
local unknownStatus = SurvivorCompanion.Encounter.takePlayerSupply(
    unknownStorageActor, "unknown_test", function(candidate) return candidate == unknownFood end,
    { snapshot = { immediateCount = 0, pressure = 0 } })
check(unknownStatus == "missing" and unknownContainer:contains(unknownFood)
    and not unknownStorageActor.inventory:contains(unknownFood),
    "companions never reinterpret an unopened world container as player camp storage")

local builder = actor("sc-camp-builder", 38, 20, {})
registry[builder.id] = builder
local sharedKit = buildKit()
local workshopContainer = containerObject(builder.square, sharedKit)
SurvivorCompanion.Encounter.markPlayerOpened(workshopContainer)
for _ = 1, 4 do
    SurvivorCompanion.Logistics.prepareBuild(builder, builder.square,
        { immediateCount = 0, pressure = 0 }, "walk")
end
local buildReady = SurvivorCompanion.Logistics.prepareBuild(builder, builder.square,
    { immediateCount = 0, pressure = 0 }, "walk")
check(buildReady and #builder.inventory.items == 4 and #workshopContainer.items == 0,
    "build order gathers one hammer, plank, and two nails from visited camp storage")

clock = clock + 4000
local signalActor = actor("sc-silent-warning", 40, 20, {})
local signalPlayer = actor("signal-player", 40, 21, { className = "IsoPlayer", recruited = false })
signalPlayer.modData.SC_Recruited = false
registry[signalActor.id] = signalActor
local distantThreat = zombie(46, 20, {})
local soundsBeforeSignal = worldSoundCount
SurvivorCompanion.Decision.update(signalActor, signalPlayer, {
    snapshot = {
        threats = { { actor = distantThreat, distanceSq = 36, visible = true, score = 20 } },
        immediateAttackers = {}, threatCount = 1, immediateCount = 0, pressure = 0.35,
        escapeSquares = {}, allies = {}, player = { actor = signalPlayer, danger = 0 },
    },
})
check(signalActor.lastIntent and signalActor.lastIntent.action == "hand_signal"
    and worldSoundCount == soundsBeforeSignal
    and type(signalActor.lastSpeech) == "string"
    and string.sub(signalActor.lastSpeech, 1, 1) == "*"
    and SurvivorCompanion.Dialogue.lastSpokenTopic(signalActor) == "signal.one",
    "visible distant danger displays an emoted freeze signal without attracting zombies")
SurvivorCompanion.Decision.update(signalActor, signalPlayer, {
    snapshot = {
        threats = { { actor = distantThreat, distanceSq = 36, visible = true, score = 90 } },
        immediateAttackers = {}, threatCount = 12, immediateCount = 0, pressure = 1.2,
        escapeSquares = {}, allies = {}, player = { actor = signalPlayer, danger = 0 },
    },
})
check(SurvivorCompanion.Dialogue.lastSpokenTopic(signalActor) == "signal.horde"
        and worldSoundCount == soundsBeforeSignal,
    "a contact escalating from one zombie to a horde bypasses the stale warning cooldown silently")
end
SurvivorCompanion.__testNeedsAndCamp()
SurvivorCompanion.__testNeedsAndCamp = nil

do
local caredPart = bodyPart({ name = "Hand_L", isBleeding = true, isScratched = true })
local caredActor = actor("sc-relationship-care", 0, 2, { body = bodyDamage(50, { caredPart }) })
registry[caredActor.id] = caredActor
check(not SurvivorCompanion.Commands.observeRelationship(caredActor, player, {
    pressure = 0, immediateCount = 0, player = { danger = 0 },
}), "first relationship observation establishes a baseline without inventing an event")
clock = clock + 1000
caredActor.body.health = 65
caredActor.body.parts = {}
check(SurvivorCompanion.Commands.observeRelationship(caredActor, player, {
    pressure = 0, immediateCount = 0, player = { danger = 0 },
}) and SurvivorCompanion.Commands.peek(caredActor).trust >= 5
    and SurvivorCompanion.Commands.peek(caredActor).memories[#SurvivorCompanion.Commands.peek(caredActor).memories].kind == "treatment",
    "nearby native health improvement becomes a bounded care memory and grows trust")
check(SurvivorCompanion.Commands.conversation(caredActor.id, "memory", player)
    and string.find(caredActor.lastSpeech, "patched", 1, true) ~= nil,
    "structured care memory is rendered as human dialogue")
end

function SurvivorCompanion.__testCharacterDepth()
local Background = SurvivorCompanion.Background
local Personality = SurvivorCompanion.Personality
local PersonalItems = SurvivorCompanion.PersonalItems
local Objectives = SurvivorCompanion.Objectives
local Journal = SurvivorCompanion.Journal

local backgroundA = Background.initialize("sc-background-deterministic", {})
local backgroundB = Background.initialize("sc-background-deterministic", {})
check(backgroundA.profession == backgroundB.profession
    and backgroundA.aptitude == backgroundB.aptitude
    and backgroundA.professionId == "base:" .. backgroundA.profession,
    "companion background is deterministic and uses a vanilla Build 42 profession id")
local lumberjackJogger = Background.initialize("explicit-background", {
    profession = "lumberjack", aptitude = "jogger",
})
check(Background.professionLabel(lumberjackJogger) == "Lumberjack"
    and Background.aptitudeLabel(lumberjackJogger) == "Jogger"
    and Background.preferredRole(lumberjackJogger) == "builder"
    and Background.decisionModifier(lumberjackJogger, "combat") == 2
    and Background.decisionModifier(lumberjackJogger, "retreat") == 2
    and Background.objectiveModifier(lumberjackJogger, "improve_shelter") == 26
    and Background.baseJobModifier(lumberjackJogger, "build") == 5
    and string.find(Background.historyText(lumberjackJogger), "logging crews", 1, true) ~= nil,
    "profession and aptitude independently influence role, choices, goals, work, and history")

local oldResourceLocation, oldCharacterProfession = ResourceLocation, CharacterProfession
local oldProfessionDefinition, oldCharacterTrait, oldPerks = CharacterProfessionDefinition,
    CharacterTrait, Perks
local professionObject = { id = "base:lumberjack" }
local professionTrait, aptitudeTrait = { id = "base:axeman" }, { id = "base:jogger" }
local grantedTraits = { professionTrait }
function grantedTraits:size() return #self end
function grantedTraits:get(index) return self[index + 1] end
ResourceLocation = { of = function(id) return id end }
CharacterProfession = { get = function(id) return id == "base:lumberjack" and professionObject or nil end }
CharacterTrait = { get = function(id) return id == "base:jogger" and aptitudeTrait or nil end }
CharacterProfessionDefinition = { getCharacterProfessionDefinition = function(profession)
    if profession ~= professionObject then return nil end
    return {
        getGrantedTraits = function() return grantedTraits end,
    }
end }
Perks = { Axe = "Axe", Strength = "Strength", Maintenance = "Maintenance",
    Sprinting = "Sprinting" }
local descriptor = { profession = nil }
function descriptor:setCharacterProfession(profession) self.profession = profession end
function descriptor:getCharacterProfession() return self.profession end
function descriptor:setProfessionSkills() self.skillsSet = true end
local known = { rows = {}, set = {} }
function known:add(trait) self.rows[#self.rows + 1] = trait; self.set[trait] = true; return true end
local nativeBackgroundActor = { levels = {}, traits = known }
function nativeBackgroundActor:getDescriptor() return descriptor end
function nativeBackgroundActor:getCharacterTraits()
    return { getKnownTraits = function() return known end }
end
function nativeBackgroundActor:hasTrait(trait) return known.set[trait] == true end
function nativeBackgroundActor:modifyTraitXPBoost() return true end
function nativeBackgroundActor:getPerkLevel(perk) return self.levels[perk] or 0 end
function nativeBackgroundActor:setPerkLevelDebug(perk, level) self.levels[perk] = level end
function nativeBackgroundActor:applyProfessionRecipes() self.professionRecipes = true end
function nativeBackgroundActor:applyCharacterTraitsRecipes() self.traitRecipes = true end
local nativeApplied, nativeReason = Background.applyNative(nativeBackgroundActor, lumberjackJogger)
check(nativeApplied and nativeReason == "native_background_applied"
    and descriptor.profession == professionObject and descriptor.skillsSet == true
    and nativeBackgroundActor:hasTrait(professionTrait)
    and nativeBackgroundActor:hasTrait(aptitudeTrait)
    and nativeBackgroundActor.levels.Axe == 2
    and nativeBackgroundActor.levels.Strength == 6
    and nativeBackgroundActor.levels.Sprinting == 1
    and nativeBackgroundActor.professionRecipes and nativeBackgroundActor.traitRecipes,
    "native background application assigns profession, traits, recipes, and conservative skills")
ResourceLocation, CharacterProfession = oldResourceLocation, oldCharacterProfession
CharacterProfessionDefinition, CharacterTrait, Perks = oldProfessionDefinition,
    oldCharacterTrait, oldPerks

local profileA = Personality.initialize("sc-depth-deterministic",
    { occupation = "mechanic", home = "rosewood" })
local profileB = Personality.initialize("sc-depth-deterministic",
    { occupation = "mechanic", home = "rosewood" })
check(profileA.archetype == profileB.archetype
    and profileA.courage == profileB.courage
    and profileA.caution == profileB.caution
    and profileA.compassion == profileB.compassion
    and profileA.practicality == profileB.practicality,
    "personality profile is deterministic for a stable identity and background")
local primaryValues = {
    brave = profileA.courage,
    cautious = profileA.caution,
    caring = profileA.compassion,
    practical = profileA.practicality,
}
local primary = primaryValues[profileA.archetype]
check(primary >= 76 and primary > math.max(
    profileA.archetype == "brave" and -1 or profileA.courage,
    profileA.archetype == "cautious" and -1 or profileA.caution,
    profileA.archetype == "caring" and -1 or profileA.compassion,
    profileA.archetype == "practical" and -1 or profileA.practicality),
    "generated personality has a bounded deterministic primary lead")

local brave = { version = 1, archetype = "brave", courage = 100, caution = 0,
    compassion = 50, practicality = 50 }
local cautious = { version = 1, archetype = "cautious", courage = 0, caution = 100,
    compassion = 50, practicality = 50 }
local braveCombat = Personality.adjustDecision(brave, { kind = "combat" }, {})
local cautiousCombat = Personality.adjustDecision(cautious, { kind = "combat" }, {})
local braveRetreat = Personality.adjustDecision(brave, { kind = "retreat" }, {})
local cautiousRetreat = Personality.adjustDecision(cautious, { kind = "retreat" }, {})
check(braveCombat > cautiousCombat and cautiousRetreat > braveRetreat
    and math.abs(braveCombat) <= 8 and math.abs(cautiousRetreat) <= 8,
    "brave/cautious soft preferences are monotonic and capped")
check(Personality.overrunThresholdDelta(brave, { escapeCount = 2, support = 1 }) <= 4
    and Personality.overrunThresholdDelta(cautious, { escapeCount = 2, support = 1 }) >= -4
    and Personality.overrunThresholdDelta(brave, { escapeCount = 0, support = 1 }) <= 0,
    "personality overrun threshold delta is capped and cannot reward a missing exit")

local satisfiedActor = actor("sc-objective-filter", 1, 4, { inventory = inventory({
    item("Base.Bandage", "Item"), item("Base.RippedSheets", "Item"),
    item("Base.Book", "Literature", { pages = 200 }),
    item("Base.Axe", "Weapon", { condition = 9, conditionMax = 10 }),
}) })
registry[satisfiedActor.id] = satisfiedActor
local satisfiedPossessions = PersonalItems.ensure(satisfiedActor, nil)
local satisfiedState = {
    personalityProfile = { archetype = "practical", courage = 50, caution = 50,
        compassion = 50, practicality = 100 },
    background = { occupation = "mechanic" }, possessions = satisfiedPossessions,
    objectives = { version = 1, serial = 0, history = {}, nextEligibleAt = 0 },
}
Objectives.initialize(satisfiedActor, satisfiedState)
check(satisfiedState.objectives.active.kind ~= "keep_medical_ready"
    and satisfiedState.objectives.active.kind ~= "find_something_to_read"
    and satisfiedState.objectives.active.kind ~= "put_gear_in_order"
    and satisfiedState.objectives.active.kind ~= "recover_keepsake",
    "objective generation filters inventory and keepsake goals that are already satisfied")
registry[satisfiedActor.id] = nil

local depthActor = actor("sc-character-depth", 2, 4, { inventory = inventory() })
registry[depthActor.id] = depthActor
local possessions, assignmentReason = PersonalItems.ensure(depthActor, nil)
local keepsake = possessions and possessions.keepsake
local keepsakeItem = keepsake and PersonalItems.find(depthActor, keepsake.key) or nil
check(possessions ~= nil and assignmentReason == "personal_item_assigned"
    and keepsakeItem ~= nil and keepsakeItem:isFavorite()
    and PersonalItems.personalRecord(keepsakeItem).ownerId == depthActor.id,
    "personal item assignment creates and verifies one favourite owned keepsake")
local beforeEnsureCount = #depthActor.inventory.items
local possessionsAgain = PersonalItems.ensure(depthActor, possessions)
check(possessionsAgain ~= nil and #depthActor.inventory.items == beforeEnsureCount,
    "personal item normalization is idempotent and does not duplicate the keepsake")
local rejectingInventory = inventory()
function rejectingInventory:AddItem() error("injected item-script rejection") end
local optionalKeepsakeActor = actor("sc-optional-keepsake", 2, 5, {
    inventory = rejectingInventory,
})
registry[optionalKeepsakeActor.id] = optionalKeepsakeActor
local optionalPossessions, optionalReason = PersonalItems.ensure(optionalKeepsakeActor, nil)
check(optionalPossessions ~= nil and optionalPossessions.keepsake == nil
    and string.find(optionalReason, "personal_item_deferred:", 1, true) == 1,
    "optional keepsake rejection cannot roll back an otherwise healthy companion")
registry[optionalKeepsakeActor.id] = nil
check(PersonalItems.isProtected(keepsakeItem, depthActor, "craft_material")
    and PersonalItems.isProtected(keepsakeItem, depthActor, "medical_consume")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "read")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "repair")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "transactional_move"),
    "personal item protection blocks automated consumption but permits reading, repair, and manual movement")
local rejectedMarker = item("Base.RejectedMemento", "Item", { rejectSetFavorite = true })
local rejected, rejectedReason = PersonalItems.restoreMarker(rejectedMarker, {
    ownerId = depthActor.id, key = depthActor.id .. ":keepsake:rejected", kind = "memento",
}, true)
check(not rejected and rejectedReason == "personal_favorite_not_retained"
    and PersonalItems.personalRecord(rejectedMarker) == nil,
    "failed favourite verification rolls back a partially written personal marker")

local absoluteSnapshot = {
    threats = {}, immediateAttackers = {}, immediateCount = 3, closeImmediateCount = 3,
    closeThreatCount = 3, occupiedThreatSectors = 3, pressure = 0,
    escapeSquares = { { square = depthActor.square } }, allies = {},
}
check(SurvivorCompanion.Combat.assessOverrun(depthActor, absoluteSnapshot, nil,
        { combatMode = "defensive", personalityProfile = brave }).overrun
    and SurvivorCompanion.Combat.assessOverrun(depthActor, absoluteSnapshot, nil,
        { combatMode = "defensive", personalityProfile = cautious }).overrun,
    "absolute three-attacker/sector overrun remains true for every personality")

local depthState = {
    personality = profileA.archetype,
    personalityProfile = profileA,
    trust = 0, bond = 0, morale = 55, stress = 12,
    memories = {}, care = {},
    background = { occupation = "mechanic", home = "rosewood", value = "loyalty",
        fear = "being_trapped", habit = "checks_tools" },
    reveals = { background = 0, keepsake = false },
    timeTogetherMs = 0,
    possessions = possessions,
    objectives = {
        version = 1, serial = 1, history = {}, nextEligibleAt = 0,
        active = { version = 1, id = depthActor.id .. ":objective:1",
            kind = "share_a_proper_meal", status = "active", revealed = false,
            progress = 0, createdAt = 1 },
    },
}
SurvivorCompanion.Relationship.initialize(depthActor, depthState)
local hiddenJournal = Journal.build(depthActor, depthState, { name = "Depth Fellow" })
check(hiddenJournal.objective.known == false and hiddenJournal.keepsake.known == false
    and #hiddenJournal.background == 0 and depthState.objectives.active.revealed == false,
    "Journal is mutation-free and does not reveal hidden objective, keepsake, or background data")
local reservedSentence, _, reservedChanged = Objectives.respondPlans(depthState)
check(type(reservedSentence) == "string" and reservedChanged == false
    and depthState.objectives.active.revealed == false,
    "plans conversation respects its trust threshold without revealing early")
depthState.trust = 10
local planSentence, _, planChanged = Objectives.respondPlans(depthState)
check(type(planSentence) == "string" and planChanged == true
    and depthState.objectives.active.revealed == true
    and string.find(planSentence, "proper meal", 1, true) ~= nil,
    "plans conversation reveals exactly the existing objective with personality wording")
local revealedJournal = Journal.build(depthActor, depthState, { name = "Depth Fellow" })
check(revealedJournal.objective.known == true
    and revealedJournal.objective.kind == "share_a_proper_meal",
    "Journal reflects an already revealed objective without advancing it")
check(Objectives.noteEvent(depthState, "meal", {})
    and not Objectives.noteEvent(depthState, "meal", {})
    and depthState.objectives.active == nil and #depthState.objectives.history == 1
    and depthState.memories[#depthState.memories].kind == "goal_completed"
    and depthState.care.goalsCompleted == 1,
    "objective completion memory and bounded reward commit exactly once")
local cooldownUntil = depthState.objectives.nextEligibleAt
local _, generatedDuringCooldown = Objectives.initialize(depthActor, depthState)
check(not generatedDuringCooldown and depthState.objectives.active == nil,
    "completed objective cannot regenerate during its six-hour in-game cooldown")
clock = clock + 21600001
local _, generatedAfterCooldown = Objectives.initialize(depthActor, depthState)
check(generatedAfterCooldown and depthState.objectives.active ~= nil
    and depthState.objectives.active.kind ~= "share_a_proper_meal"
    and depthState.objectives.active.createdAt >= cooldownUntil,
    "objective generation resumes after six in-game hours and filters recent repeats")
for serial = 2, 10 do
    depthState.objectives.active = {
        version = 1, id = depthActor.id .. ":objective:" .. tostring(serial),
        kind = "share_a_proper_meal", status = "active", revealed = true,
        progress = 0, createdAt = serial,
    }
    check(Objectives.noteEvent(depthState, "meal", {}),
        "objective history accepts a distinct verified completion")
end
check(#depthState.objectives.history == 8,
    "objective completion history remains capped at eight rows")

depthState.reveals.background = 2
local publicSummary = SurvivorCompanion.Relationship.summary(depthActor, depthState, {})
check(publicSummary.background.occupation == "Mechanic"
    and string.find(publicSummary.background.history, "old cars", 1, true) ~= nil
    and publicSummary.background.home == nil
    and publicSummary.profession == "Mechanic"
    and type(publicSummary.backgroundLabel) == "string",
    "relationship summary returns only staged revealed background facts")

depthActor.inventory:Remove(keepsakeItem)
local absentPossessions, leftInventory = PersonalItems.observe(depthActor, depthState.possessions)
depthState.possessions = absentPossessions
check(leftInventory and depthState.possessions.keepsake.status == "not_carried",
    "manual keepsake removal remains allowed and is observed as not carried")
local countWhileMissing = #depthActor.inventory.items
local stillMissing = PersonalItems.ensure(depthActor, depthState.possessions)
check(stillMissing.keepsake.status == "not_carried"
    and #depthActor.inventory.items == countWhileMissing,
    "a genuinely absent keepsake is never silently replaced")
depthState.objectives = {
    version = 1, serial = 11, history = {}, nextEligibleAt = 0,
    active = { version = 1, id = depthActor.id .. ":objective:11",
        kind = "recover_keepsake", status = "active", revealed = true,
        progress = 0, createdAt = 11 },
}
local unrelatedPhoto = item("Base.Photo", "Item", { memento = true })
check(Objectives.itemBonus(depthState.objectives, unrelatedPhoto) == 0,
    "same-type unmarked item cannot satisfy the recover-keepsake preference")
depthActor.inventory:AddItem(keepsakeItem)
PersonalItems.reset(depthActor)
depthState.possessions = PersonalItems.observe(depthActor, depthState.possessions)
Objectives.reset(depthActor)
check(Objectives.update(depthActor, depthState)
    and depthState.objectives.active == nil and #depthState.objectives.history == 1,
    "returning the exact marked keepsake completes its objective once")

local privateMeal = item("Base.PrivateMeal", "Food", { hungerChange = -0.4 })
check(PersonalItems.restoreMarker(privateMeal, {
        ownerId = depthActor.id, key = depthActor.id .. ":keepsake:test-meal", kind = "memento",
    }, true), "test personal meal marker is verified")
local hungryActor = actor("sc-protected-needs", 3, 4,
    { inventory = inventory({ privateMeal }) })
hungryActor.hunger = 0.8
registry[hungryActor.id] = hungryActor
local consumedPrivate, privateReason = SurvivorCompanion.Needs.update(hungryActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
})
check(not consumedPrivate and privateReason == "safe_food_unavailable" and not privateMeal.used,
    "needs automation refuses to consume a marked personal item")
local normalMeal = item("Base.NormalMeal", "Food", { hungerChange = -0.4 })
hungryActor.inventory:AddItem(normalMeal)
check(SurvivorCompanion.Needs.update(hungryActor, player, {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
    }) and hungryActor.lastIntent.item == normalMeal,
    "needs automation still selects an ordinary safe item beside a protected one")

registry[depthActor.id] = nil
registry[hungryActor.id] = nil
end
SurvivorCompanion.__testCharacterDepth()
SurvivorCompanion.__testCharacterDepth = nil

local soundsBeforeWhistle = worldSoundCount
check(SurvivorCompanion.Commands.whistle(player) and worldSoundCount == soundsBeforeWhistle + 1,
    "audible whistle command creates exactly one additional world sound")
check(SurvivorCompanion.Commands.handSign(player, "hold") and player.lastEmote == "freeze",
    "visible silent hand sign plays the real player emote")
check(SurvivorCompanion.Commands.handSign(player, "cautious") and player.lastEmote == "followbehind",
    "expanded cautious hand sign uses a validated player emote and command")
check(not SurvivorCompanion.Commands.handSign(player, "invented_signal"),
    "unknown hand sign is rejected instead of guessing an animation")

-- Persistent Base Life contract: zones, classified storage, role-aware jobs
-- and infection restrictions survive a complete export/restore cycle.
function SurvivorCompanion.__testBaseLifeAndCrisis()
local BaseLife = SurvivorCompanion.BaseLife
BaseLife.reset()
local campSquare = cell:getGridSquare(2, 2, 0)
check(BaseLife.create(campSquare, "Test Camp") and BaseLife.active().name == "Test Camp",
    "base core creates one bounded default camp area")
check(BaseLife.beginZone("quarantine", cell:getGridSquare(1, 1, 0))
    and BaseLife.finishZone(cell:getGridSquare(3, 3, 0), "Quiet room"),
    "two-corner quarantine zoning commits inside the camp boundary")
local store = { square = campSquare, objectIndex = #campSquare.objects,
    container = inventory({ item("Base.Plank", "Material") }) }
function store:getSquare() return self.square end
function store:getX() return self.square.x end
function store:getY() return self.square.y end
function store:getZ() return self.square.z end
function store:getObjectIndex() return self.objectIndex end
function store:getContainer() return self.container end
campSquare.objects[#campSquare.objects + 1] = store
check(BaseLife.registerStorage(store, "construction"),
    "world container can be designated as classified camp storage")
check(BaseLife.assign(fellow.id, "builder", true),
    "recruited resident receives a persistent base role and duty state")
check(BaseLife.policies().defense == "rotation"
    and BaseLife.policies().workload == "balanced",
    "new camps default to rotating watch and balanced work")
local carriedPlankA = item("Base.Plank", "Material", { weight = 4 })
local carriedPlankB = item("Base.Plank", "Material", { weight = 4 })
local carriedPlankC = item("Base.Plank", "Material", { weight = 4 })
local builderLoad = inventory({ carriedPlankA, carriedPlankB, carriedPlankC })
builderLoad.capacity = 10
local loadedBuilder = actor("sc-loaded-builder", 2, 2, { inventory = builderLoad })
registry[loadedBuilder.id] = loadedBuilder
BaseLife.assign(loadedBuilder.id, "builder", true)
local storedSurplus, storedReason = SurvivorCompanion.Logistics.update(loadedBuilder, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 },
})
check(SurvivorCompanion.Logistics.roleOf(loadedBuilder) == "builder"
    and storedSurplus and #builderLoad.items == 2 and #store.container.items == 2,
    "builder loadout keeps a role reserve and deposits excess materials in classified base storage: "
        .. tostring(storedReason) .. ", carried=" .. tostring(#builderLoad.items)
        .. ", stored=" .. tostring(#store.container.items))
local queued, baseJob = BaseLife.enqueueJob({ type = "build", priority = 4,
    recipeId = "ES_Wood_Wallframe", target = { x = 3, y = 2, z = 0 } })
local claimed = queued and BaseLife.claimJob(fellow.id)
check(claimed and claimed.id == baseJob.id and claimed.reservedBy == fellow.id,
    "role-aware work queue gives a base worker a leased job")
local operations = BaseLife.auditOperations(true)
local constructionStock
for _, stock in ipairs(operations.stock or {}) do
    if stock.category == "construction" then constructionStock = stock break end
end
check(operations and constructionStock and constructionStock.count == 2
    and constructionStock.target == 4 and #operations.alerts > 0,
    "bounded base audit reports real classified stock against resident-scaled targets")
check(BaseLife.setPolicy("defense", "role_based")
    and BaseLife.setPolicy("workload", "continuous")
    and BaseLife.setPolicy("routines", false)
    and BaseLife.policies().routines == false,
    "base policies expose explicit defense, workload and downtime controls")
BaseLife.assign(fellow.id, "guard", true)
check(BaseLife.guardStatus(fellow.id, clock),
    "role-based defense marks an on-duty guard as the active watch")
check(BaseLife.setRestriction(fellow.id, "quarantine")
    and BaseLife.restriction(fellow.id) == "quarantine",
    "infection restrictions are represented in base state")
local baseSave = BaseLife.export()
BaseLife.reset()
check(BaseLife.restore(baseSave) and BaseLife.active().name == "Test Camp"
    and BaseLife.restriction(fellow.id) == "quarantine"
    and #BaseLife.storageRows("construction", true) == 1
    and BaseLife.policies().defense == "role_based"
    and BaseLife.policies().workload == "continuous"
    and BaseLife.policies().routines == false,
    "base zones, storage, policies and quarantine rules round-trip transactionally")
BaseLife.setRestriction(fellow.id, nil)

-- Infection Crisis starts from a real medical bite assessment, records nearby
-- witnesses, accepts player influence, and persists without authorizing harm.
local bittenPart = bodyPart({ name = "ForeArm_R", isBitten = true })
local bitten = actor("sc-crisis-test", 2, 3, {
    inventory = inventory({ item("Base.Photo", "Item", { memento = true }) }),
    body = bodyDamage(88, { bittenPart }),
})
bitten.body.infected, bitten.body.infectionLevel = true, 35
registry[bitten.id] = bitten
local Crisis = SurvivorCompanion.InfectionCrisis
Crisis.reset()
check(Crisis.pulse(player, clock) and Crisis.summary().active >= 1,
    "new companion bite creates a persistent social crisis")
local crisisRow
for _, row in ipairs(Crisis.summary().rows) do
    if row.subjectId == bitten.id then crisisRow = row break end
end
check(crisisRow and crisisRow.subjectId == bitten.id and crisisRow.finalAuthorized == false,
    "bite crisis identifies its subject and begins behind the irreversible safety gate; first="
        .. tostring(Crisis.summary().rows[1] and Crisis.summary().rows[1].subjectId))
check(Crisis.choose(crisisRow.id, "quarantine")
    and BaseLife.restriction(bitten.id) == "quarantine",
    "player can resolve a known crisis as quarantine without lethal side effects")
local crisisSave = Crisis.export()
Crisis.reset()
local crisisRestored = Crisis.restore(crisisSave)
local restoredCrisis
for _, row in ipairs(Crisis.summary().rows) do
    if row.id == crisisRow.id then restoredCrisis = row break end
end
check(crisisRestored and restoredCrisis and restoredCrisis.outcome == "quarantine"
    and restoredCrisis.finalAuthorized == false,
    "crisis evidence and chosen nonlethal outcome survive save restoration")
registry[bitten.id] = nil
end
SurvivorCompanion.__testBaseLifeAndCrisis()
SurvivorCompanion.__testBaseLifeAndCrisis = nil

-- Living-survivor psychology: stable temperament, bounded memories, symmetric
-- social state, player-addressable requests, and persistence.
function SurvivorCompanion.__testCommunityLife()
local Community = SurvivorCompanion.Community
local LifeEvents = SurvivorCompanion.LifeEvents
local Autonomy = SurvivorCompanion.Autonomy
local Dialogue = SurvivorCompanion.Dialogue
local peerId = "sc-community-peer"
Community.reset()
LifeEvents.reset()
Dialogue.reset(fellow)
local oneBand, oneRank = Dialogue.threatBand(1)
local pairBand, pairRank = Dialogue.threatBand(2)
local groupBand, groupRank = Dialogue.threatBand(4)
local crowdBand, crowdRank = Dialogue.threatBand(7)
local hordeBand, hordeRank = Dialogue.threatBand(12)
check(oneBand == "one" and oneRank == 1
        and pairBand == "pair" and pairRank == 2
        and groupBand == "group" and groupRank == 3
        and crowdBand == "crowd" and crowdRank == 4
        and hordeBand == "horde" and hordeRank == 5,
    "contact dialogue distinguishes one, two, three-to-four, a crowd, and a horde")
check(Dialogue.poolSize("danger.one", fellow, {}) >= 12
        and Dialogue.poolSize("danger.pair", fellow, {}) >= 12
        and Dialogue.poolSize("danger.group", fellow, {}) >= 12
        and Dialogue.poolSize("danger.crowd", fellow, {}) >= 12
        and Dialogue.poolSize("danger.horde", fellow, {}) >= 12
        and Dialogue.poolSize("signal.horde", fellow, {}) >= 6,
    "every contact scale has a broad spoken pool and several silent hand-sign variants")
local variedLines = {}
local dialogueDetail
for index = 1, 4 do
    local line, detail = Dialogue.choose(fellow, "status.ready", nil, nil, {
        state = { personalityProfile = { archetype = "practical" }, stress = 8, morale = 58 },
    })
    variedLines[line] = true
    dialogueDetail = detail
end
local variedCount = 0
for _ in pairs(variedLines) do variedCount = variedCount + 1 end
check(variedCount == 4 and dialogueDetail.poolSize >= 6
    and dialogueDetail.voice == "practical",
    "dialogue pools avoid recent lines and include personality-specific wording")
local namedGriefLine = Dialogue.choose(fellow, "grief.mourn", nil, { "Glenn Rhee" }, {
    state = { personalityProfile = { archetype = "caring" }, stress = 55, morale = 30 },
})
check(type(namedGriefLine) == "string"
    and string.find(namedGriefLine, "Glenn Rhee", 1, true) ~= nil,
    "dialogue variation safely substitutes named context")
local responseState = {
    trust = 35, bond = 30, stress = 8, morale = 58,
    personality = "cautious",
    personalityProfile = { version = 2, archetype = "cautious",
        courage = 35, caution = 80, compassion = 50, practicality = 55 },
    weaponPriority = "best", memories = {}, care = {}, reveals = {},
}
local responseDescription = {
    health = 100, woundCount = 0, hunger = 0, thirst = 0,
    supplies = { bandages = 2 }, ammunition = 1,
}
local statusLines = {}
for index = 1, 4 do
    local sentence = SurvivorCompanion.Relationship.respond(
        "status", fellow, player, responseState, responseDescription)
    statusLines[sentence] = true
end
local statusCount = 0
for _ in pairs(statusLines) do statusCount = statusCount + 1 end
check(statusCount >= 3,
    "repeated player conversation actions produce varied companion answers")
local mindState = SurvivorCompanion.Commands.peek(fellow)
local firstMind = Community.mindFor(fellow, mindState)
local stableResponse, stableJoy = firstMind.stressResponse, firstMind.joyResponse
Community.reset()
local regeneratedMind = Community.mindFor(fellow, mindState)
check(regeneratedMind.stressResponse == stableResponse and regeneratedMind.joyResponse == stableJoy,
    "survivor stress and positive-response profiles are deterministic")
for index = 1, 20 do
    Community.addThought(fellow, { key = "bounded:" .. tostring(index), kind = "test",
        text = "Bounded thought " .. tostring(index), stress = index, morale = 0,
        at = clock + index, expiresAt = clock + 999999 })
end
check(#Community.mindFor(fellow).thoughts <= 12,
    "survivor thought memory remains bounded")
LifeEvents.emit("shared_escape", {
    participants = { fellow.id, peerId }, sourceId = fellow.id,
})
check(Community.processEvents(8) == 1,
    "community event queue processes a shared escape once")
local forwardPair = Community.relation(fellow.id, peerId, false)
local reversePair = Community.relation(peerId, fellow.id, false)
check(forwardPair ~= nil and forwardPair == reversePair and #forwardPair.memories == 1
    and forwardPair.trust > 0,
    "companion relationships are symmetric and retain bounded shared memories")
local request = Community.createSupplyRequest(fellow,
    { "soon", "come_with_me", "not_now", "cannot_spare" })
check(request and Autonomy.requestFor(fellow).kind == "supply_run",
    "bored companion request becomes available to the player UI")
check(Autonomy.respond(fellow, "soon", player)
    and Autonomy.requestFor(fellow) == nil
    and Community.summary(fellow).currentExpectation == "supply_run",
    "player response clears the request and records the supply-run promise")
local communitySave = Community.export()
Community.reset()
check(Community.restore(communitySave)
    and Community.summary(fellow).currentExpectation == "supply_run"
    and Community.relation(fellow.id, peerId, false) ~= nil,
    "community minds, promises, and relationships survive save restoration")
for index = 1, 70 do
    Community.adjustRelation(fellow.id, "sc-bounded-pair-" .. tostring(index),
        { familiarity = 1 })
end
local pairCount = 0
for _, _ in pairs(Community.export().pairs) do pairCount = pairCount + 1 end
check(pairCount <= 64, "community relationship storage remains bounded")
local beforeUnknown = Community.export()
check(Community.summary("sc-never-seen") == nil
    and Community.export().minds["sc-never-seen"] == nil
    and beforeUnknown.version == Community.export().version,
    "read-only summaries do not create state for unknown companions")

-- A recruited death creates one persistent, relationship-weighted loss. The
-- response waits for safety, uses the dead survivor's real identity, and never
-- repeats when the runtime observes the same terminal actor again.
local lost = actor("sc-community-lost", 1, 0)
local closeFriend = actor("sc-community-close", 0, 0)
local newFriend = actor("sc-community-new", 20, 0)
    local priorGriefMaximum = SurvivorCompanion.Config.values.maxCompanions
SurvivorCompanion.Config.values.maxCompanions = 256
closeFriend.square.room, newFriend.square.room = { name = "safe-room" }, { name = "safe-room" }
registry[lost.id], registry[closeFriend.id], registry[newFriend.id] = lost, closeFriend, newFriend
check(SurvivorCompanion.Commands.restore(closeFriend, { id = closeFriend.id, recruited = true })
    and SurvivorCompanion.Commands.restore(newFriend, { id = newFriend.id, recruited = true })
    and SurvivorCompanion.Commands.restore(lost, { id = lost.id, recruited = true }),
    "grief fixture restores three recruited team records")
Community.adjustRelation(closeFriend.id, lost.id,
    { familiarity = 90, trust = 75, opinion = 70 })
lost.dead = true
local notedDeath, deathResult = Community.noteCompanionDeath({
    id = lost.id, actor = lost, recruited = true,
    identity = { forename = "Glenn", surname = "Rhee" },
})
local closeGrief, newGrief = Community.activeGrief(closeFriend), Community.activeGrief(newFriend)
check(notedDeath and deathResult.affected >= 2 and closeGrief and newGrief
    and closeGrief.subjectName == "Glenn Rhee"
    and closeGrief.currentIntensity > newGrief.currentIntensity,
    "team death creates stronger grief for a close relationship than a new teammate")
local closeState = SurvivorCompanion.Commands.peek(closeFriend)
local lastMemory = closeState.memories[#closeState.memories]
check(lastMemory and lastMemory.kind == "companion_died"
    and lastMemory.subjectId == lost.id and lastMemory.subjectName == "Glenn Rhee"
    and string.find(SurvivorCompanion.Relationship.memoryText(lastMemory), "Glenn Rhee", 1, true),
    "death remains a named permanent relationship memory")
local griefDescription = SurvivorCompanion.Commands.describe(closeFriend.id, player)
local griefAnswer = SurvivorCompanion.Relationship.respond(
    "status", closeFriend, player, closeState, griefDescription)
check(type(griefAnswer) == "string"
    and string.find(griefAnswer, "Glenn Rhee", 1, true),
    "How are you reports the active named grief instead of a generic good mood")
local griefCount = #Community.mindFor(closeFriend).grief
local duplicateDeath, duplicateReason = Community.noteCompanionDeath({
    id = lost.id, actor = lost, recruited = true,
    identity = { forename = "Glenn", surname = "Rhee" },
})
check(not duplicateDeath and duplicateReason == "death_already_recorded"
    and #Community.mindFor(closeFriend).grief == griefCount,
    "repeated terminal updates cannot duplicate grief or mood penalties")
local griefDocument = Community.export()
Community.reset()
check(Community.restore(griefDocument) and Community.activeGrief(closeFriend)
    and Community.activeGrief(closeFriend).subjectName == "Glenn Rhee",
    "grief intensity, recovery and pending response survive save restoration")
Community.mindFor(closeFriend).grief[1].nextReactionAt = 0
local griefIntent = Autonomy.intentFor(closeFriend, player, { threatCount = 0 }, closeState)
check(griefIntent and griefIntent.kind == "grief_response"
    and Autonomy.update(closeFriend, player, { snapshot = { threatCount = 0 } }, griefIntent)
    and string.find(tostring(closeFriend.lastSpeech), "Glenn Rhee", 1, true)
    and Community.summary(closeFriend).activeEpisode == "mourning",
    "safe autonomy visibly acknowledges the named death and starts mourning")
local activeGriefIntent = Autonomy.intentFor(closeFriend, player, { threatCount = 1 }, closeState)
check(activeGriefIntent and activeGriefIntent.kind == "mental_episode"
    and Autonomy.update(closeFriend, player, { snapshot = { threatCount = 1 } }, activeGriefIntent)
    and Community.summary(closeFriend).activeEpisode == nil
    and Community.mindFor(closeFriend).grief[1].reactionPending == false,
    "danger immediately interrupts mourning and returns control to survival AI")
local originalClock = clock
clock = clock + 20 * 24 * 3600000
Community.updateMind(closeFriend, closeState, { threatCount = 0 }, { idle = true })
check(Community.activeGrief(closeFriend) == nil
    and lastMemory.kind == "companion_died",
    "acute grief decays after enough game time while the death memory remains")
clock = originalClock
Autonomy.reset(closeFriend)
registry[lost.id], registry[closeFriend.id], registry[newFriend.id] = nil, nil, nil
SurvivorCompanion.Config.values.maxCompanions = priorGriefMaximum
end
SurvivorCompanion.__testCommunityLife()
SurvivorCompanion.__testCommunityLife = nil

-- Persistent faction domain: strict restore, discovery, standings, offenses,
-- trade markup and debug gating are exercised without a fake world spawn.
function SurvivorCompanion.__testFactionDomain()
local Factions = SurvivorCompanion.Factions
local Trade = SurvivorCompanion.Trade
local Life = SurvivorCompanion.FactionLife
local Contracts = SurvivorCompanion.FactionContracts
local World = SurvivorCompanion.FactionWorld
Factions.reset()
do
    local sliceClock = clock
    SurvivorCompanion.Performance.reset()
    SurvivorCompanion.Performance.beginFrame(2, clock)
    local status, _, _, searchJob = Factions.pollHouseSearch(
        player, { allowSeen = false, minimumDistance = 8,
            maximumDistance = 20, sampleBudget = 24 }, nil)
    clock = clock + 16
    SurvivorCompanion.Performance.endFrame(1, false)
    check(status == "pending" and searchJob ~= nil,
        "faction house discovery yields after its shared sample quota")
    local passes = 1
    while status == "pending" and passes < 8 do
        SurvivorCompanion.Performance.beginFrame(2, clock)
        status, _, _, searchJob = Factions.pollHouseSearch(
            player, nil, searchJob)
        clock = clock + 16
        SurvivorCompanion.Performance.endFrame(1, false)
        passes = passes + 1
    end
    check(status == "complete" or status == "failed",
        "resumable faction house discovery reaches a terminal result")
    SurvivorCompanion.Performance.reset()
    clock = sliceClock
end
local document = {
    schema = 1, sequence = 4, lastWorldSpawnDay = 7, lastProductionCheckDay = 8,
    order = { "faction-test" },
    groups = {
        ["faction-test"] = {
            id = "faction-test", archetype = "barricaded_household",
            name = "Test household", lifecycle = "settled", standing = "Tolerated",
            reputation = 10, discovered = true, barterUnlocked = true,
            permanentHostility = false,
            house = {
                id = "1:1:4:4", bounds = { x1 = 1, y1 = 1, x2 = 4, y2 = 4, z = 0 },
                anchor = { x = 2, y = 2, z = 0 }, interior = {
                    { x = 2, y = 2, z = 0 }, { x = 3, y = 2, z = 0 },
                },
                openings = { { x = 1, y = 2, z = 0, objectIndex = 0, kind = "door" } },
                primaryEntry = { x = 1, y = 2, z = 0, objectIndex = 0, kind = "door" },
            },
            members = {
                { key = "member-1", role = "leader", identity = {
                    forename = "Test", surname = "Resident", gender = "male",
                }, alive = true, hibernated = false },
                { key = "member-2", role = "builder", identity = {
                    forename = "Second", surname = "Resident", gender = "female",
                }, alive = true, hibernated = false },
            },
            jobs = {}, offenses = {}, history = {},
            request = { kind = "materials", status = "available", rewardReserved = true,
                required = { { type = "Base.Plank", count = 4 } },
                reward = { { type = "Base.Bandage", count = 1 } } },
        },
    },
}
local restoredFactions, factionCount = Factions.restore(document)
check(restoredFactions and factionCount == 1 and #Factions.list(true) == 1,
    "persistent faction document restores one discovered household")
local secondHousehold = {}
for key, value in pairs(document.groups["faction-test"]) do secondHousehold[key] = value end
secondHousehold.id, secondHousehold.name = "faction-test-two", "Second test household"
document.groups[secondHousehold.id] = secondHousehold
document.order[2] = secondHousehold.id
    local priorHouseholdMaximum = SurvivorCompanion.Config.values.factionMaxHouseholds
    SurvivorCompanion.Config.values.factionMaxHouseholds = 1
local preservedFactions, preservedCount = Factions.restore(document)
check(preservedFactions and preservedCount == 2 and #Factions.list(true) == 2,
    "lowering the sandbox household maximum never prunes existing saved groups")
World.reset()
check(World.reconcile() and World.relation("faction-test", "faction-test-two") ~= nil,
    "faction world deterministically connects persistent living households")
local worldRelation = World.relation("faction-test", "faction-test-two")
worldRelation.score, worldRelation.status = 30, "Cooperative"
local secondStandingBefore = Factions.summary("faction-test-two").reputation
check(Factions.adjustStanding("faction-test", 20, "test_help")
    and Factions.summary("faction-test-two").reputation == secondStandingBefore + 4,
    "known cooperative households hear about meaningful player actions")
local worldDocument = World.export()
worldDocument.nextEventHour = 0
check(World.restore(worldDocument) and World.pulse(100),
    "a due bounded faction-world event executes between living households")
local worldSummary = World.summary("faction-test")
check(worldSummary and #worldSummary.relations == 1 and #worldSummary.news >= 1,
    "faction-world summaries expose known relations and recent world news")
local persistedWorld = World.export()
World.reset()
check(World.restore(persistedWorld)
    and World.relation("faction-test", "faction-test-two").contactCount >= 1,
    "faction-world relations and event history survive restoration")
document.groups[secondHousehold.id], document.order[2] = nil, nil
    SurvivorCompanion.Config.values.factionMaxHouseholds = priorHouseholdMaximum
check(Factions.restore(document), "single-household fixture restores after preservation test")
check(World.relation("faction-test", "faction-test-two") == nil,
    "faction-world reconciliation removes only orphaned relations")
local summary = Factions.summary("faction-test")
check(summary and summary.alive == 2 and summary.standing == "Tolerated"
    and summary.barterUnlocked == true,
    "faction summary exposes life, standing and barter state")
check(summary.life and summary.life.personalityPrimary and #summary.life.members == 2
    and #summary.life.relations == 1 and summary.life.rumoursTotal == 3,
    "faction life initializes persistent personalities, relationships and imperfect rumours")
check(summary.social and summary.social.offer and summary.social.completedContracts == 0,
    "social-contract state initializes one persistent household offer")

local originalConfigGet = SurvivorCompanion.Config.get
SurvivorCompanion.Config.get = function(key)
    if key == "debugSpawnEnabled" then return true end
    return originalConfigGet(key)
end
for _, personality in ipairs({ "Paranoid", "Generous", "Militarized", "Desperate",
    "Isolationist", "Resourceful" }) do
    local changed, selected = Life.debugSetPersonality("faction-test", personality)
    check(changed and selected == personality
        and Factions.summary("faction-test").life.personalityPrimary == personality,
        "debug personality control selects " .. personality)
end
check(Life.debugAdvanceRoutine("faction-test")
    and Factions.summary("faction-test").life.routines["member-1"] ~= nil,
    "debug routine control advances visible household activity")
for _, crisisKind in ipairs({ "supply_collapse", "illness", "internal_dispute" }) do
    local started = Life.debugTriggerCrisis("faction-test", crisisKind)
    check(started and Factions.summary("faction-test").life.crisis.kind == crisisKind,
        "debug crisis control starts " .. crisisKind)
    check(Life.debugResolveCrisis("faction-test")
        and Factions.summary("faction-test").life.crisis == nil,
        "debug crisis control resolves " .. crisisKind)
end

local nestedFoodBag = item("Base.Bag_Schoolbag", "Container", {
    nestedInventory = inventory({ item("Base.CannedBeans", "Food") }),
})
local residentOne = actor("faction-resident-1", 2, 2, {
    inventory = inventory({ nestedFoodBag, item("Base.WaterBottleFull", "Item"),
        item("Base.Bandage", "Medical") }),
})
local residentTwo = actor("faction-resident-2", 3, 2, {
    inventory = inventory({ item("Base.Hammer", "Tool", { tags = { Hammer = true } }),
        item("Base.Plank", "Material"), item("Base.Bullets9mmBox", "Ammunition") }),
})
local group = Factions.group("faction-test")
group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
registry[residentOne.id], registry[residentTwo.id] = { actor = residentOne }, { actor = residentTwo }
local audited = Life.debugAuditResources("faction-test")
local auditedSummary = Factions.summary("faction-test").life.resources
check(audited and auditedSummary.source == "inventory"
    and group.life.resources.counts.food == 1 and group.life.resources.counts.tools == 1,
    "bounded faction resource audit includes supplies inside carried bags")

for _, contractKind in ipairs({ "supply", "medical", "local_threat" }) do
    local offered, offeredKind = Contracts.debugOffer("faction-test", contractKind)
    check(offered and offeredKind == contractKind
        and Factions.summary("faction-test").social.offer.revealed == true,
        "debug controls produce a revealed " .. contractKind .. " contract")
    local accepted = Contracts.accept("faction-test", player, true)
    local duplicate, duplicateReason = Contracts.accept("faction-test", player, true)
    check(accepted and not duplicate and duplicateReason == "one_contract_already_active",
        "a household can hold only one active social contract")
    group.members[1].actorId, group.members[2].actorId = nil, nil
    local midwayDocument = Factions.export()
    check(Factions.restore(midwayDocument)
        and Factions.summary("faction-test").social.active.kind == contractKind
        and type(Factions.summary("faction-test").social.active.marker) == "table"
        and #Factions.summary("faction-test").social.notifications > 0,
        "mid-contract save and load preserves the active " .. contractKind .. " contract")
    group = Factions.group("faction-test")
    group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
    if contractKind == "local_threat" then
        local threat = group.social.contract.active
        local originalThreatSquare = player.square
        player.square = cell:getGridSquare(threat.target.x, threat.target.y, threat.target.z)
        local originalThreatConfig = SurvivorCompanion.Config.get
        SurvivorCompanion.Config.get = function(key)
            if key == "factionContractThreatMinLoadedSquares" then return 1000 end
            return originalThreatConfig(key)
        end
        local partial, partialReason = Contracts.fulfill("faction-test", player, false)
        SurvivorCompanion.Config.get = originalThreatConfig
        player.square = originalThreatSquare
        check(not partial and partialReason == "reported_area_not_fully_loaded",
            "partially loaded threat areas cannot produce a false contract completion")
    end
    check(Contracts.debugComplete("faction-test")
        and Factions.summary("faction-test").social.active == nil,
        "forced harness completion resolves " .. contractKind .. " without inventory side effects")
end
local firstMilestone = Factions.summary("faction-test").social
check(firstMilestone.futureRecruitConsideration == true,
    "successful help records later recruitment consideration")

-- A faction resident must become a trial companion without cloning or losing
-- identity, possessions, affiliation history, or save continuity.
local Recruitment = SurvivorCompanion.FactionRecruitment
local Commands = SurvivorCompanion.Commands
group = Factions.group("faction-test")
local recruitmentBaseline = Factions.export()
local function installFactionRecord(member, resident)
    resident.modData.SC_Recruited = false
    resident.modData.SC_FactionId = group.id
    resident.modData.SC_FactionRole = member.role
    local record = {
        id = resident.id, actor = resident, recruited = false,
        factionId = group.id, factionRole = member.role,
        identity = member.identity,
        state = { order = {
            current = "faction_duty", scavenge = false, movementMode = "walk",
            combatStance = "defensive", combatDoctrine = "close_defense",
            weaponPriority = "best", workMode = "build",
        } },
    }
    registry[resident.id] = record
    check(Commands.restore(resident, record),
        "faction recruitment fixture restores resident command state")
    return record
end
local residentRecords = {
    [residentOne.id] = installFactionRecord(group.members[1], residentOne),
    [residentTwo.id] = installFactionRecord(group.members[2], residentTwo),
}
local prepared, preparedReason = Recruitment.debugPrepare(group)
local named, namedReason = Recruitment.debugCandidate(group, player)
local namedSummary = Recruitment.summary(group)
check(prepared and named and namedSummary.status == "candidate"
    and type(namedSummary.candidateName) == "string",
    "trusted household names one loaded, nonessential recruitment candidate: "
        .. tostring(preparedReason) .. "/" .. tostring(namedReason))
local candidateMember = Factions.member(group, namedSummary.candidateKey)
local candidateRecord = residentRecords[candidateMember.actorId]
local candidateActor = candidateRecord.actor
local candidateInventory = candidateActor.inventory
local candidateIdentity = candidateRecord.identity
local trialStarted, trialReason = Recruitment.debugTrial(group, player)
local trialSummary = Recruitment.summary(group)
check(trialStarted and trialSummary.status == "trial"
    and candidateMember.away == "recruitment_trial"
    and candidateRecord.recruited == true and candidateRecord.factionId == nil,
    "field trial atomically detaches the resident and makes the same actor a recruited follower: "
        .. tostring(trialReason))
check(candidateRecord.actor == candidateActor and candidateRecord.id == candidateActor.id
    and candidateRecord.actor.inventory == candidateInventory
    and candidateRecord.identity == candidateIdentity,
    "field trial preserves actor identity, inventory object, and identity record")
local savedTrial = Factions.export()
local restoredTrial, restoredTrialReason = Factions.restore(savedTrial)
local restoredTrialSummary = Recruitment.summary("faction-test")
check(savedTrial.groups["faction-test"].recruitment.status == "trial"
    and restoredTrial and restoredTrialSummary and restoredTrialSummary.status == "trial"
    and Factions.member("faction-test", namedSummary.candidateKey).away == "recruitment_trial",
    "trial status and away-member ownership survive faction save restoration: "
        .. tostring(restoredTrialReason))
group = Factions.group("faction-test")
local extended, extensionReason = Recruitment.debugDecision(group, player, "more_time")
local extendedSummary = Recruitment.summary(group)
check(extended and extendedSummary.status == "trial"
    and extendedSummary.extensions == 1 and extendedSummary.decision == "more_time",
    "candidate can request more time without being cloned, returned, or auto-recruited: "
        .. tostring(extensionReason))
local returned, returnReason = Recruitment.debugDecision(group, player, "return")
local returnedMember = Factions.member(group, namedSummary.candidateKey)
check(returned and returnedMember.away == nil and returnedMember.departed ~= true
    and candidateRecord.recruited == false and candidateRecord.factionId == group.id,
    "return decision restores the same actor to its household and faction behavior: "
        .. tostring(returnReason))

check(Recruitment.debugPrepare(group) and Recruitment.debugCandidate(group, player)
    and Recruitment.debugTrial(group, player),
    "a returned candidate can begin a later debug trial after cooldown reset")
local joinedCandidate = Recruitment.summary(group)
local joinedKey, joinedActorId = joinedCandidate.candidateKey, joinedCandidate.actorId
local joinedRecord = registry[joinedActorId]
local joinedActor, joinedInventory = joinedRecord.actor, joinedRecord.actor.inventory
local joined, joinReason = Recruitment.debugDecision(group, player, "join")
local joinedMember = Factions.member(group, joinedKey)
check(joined and joinedMember.departed == true and joinedMember.actorId == nil
    and joinedMember.departedActorId == joinedActorId
    and joinedRecord.recruited == true and joinedRecord.factionId == nil,
    "permanent decision removes the resident from household duties without deleting the companion: "
        .. tostring(joinReason))
check(joinedRecord.actor == joinedActor and joinedRecord.actor.inventory == joinedInventory
    and Recruitment.originForActor(joinedActorId).status == "joined",
    "permanent recruitment preserves the actor and a persistent former-household origin")
local joinedDocument = Factions.export()
check(Factions.restore(joinedDocument)
    and Recruitment.summary("faction-test").status == "joined"
    and Factions.presentCount("faction-test") == 1,
    "permanent recruitment and reduced household staffing survive save restoration")

-- Death on a field trial is permanent and updates the origin household even
-- though the active actor record is temporarily classified as a companion.
check(Factions.restore(recruitmentBaseline),
    "trial-death fixture restores the original household")
group = Factions.group("faction-test")
group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
residentRecords[residentOne.id] = installFactionRecord(group.members[1], residentOne)
residentRecords[residentTwo.id] = installFactionRecord(group.members[2], residentTwo)
check(Recruitment.debugPrepare(group) and Recruitment.debugCandidate(group, player)
    and Recruitment.debugTrial(group, player),
    "trial-death fixture starts one real candidate trial")
local deathTrial = Recruitment.summary(group)
local deathRecord = registry[deathTrial.actorId]
check(Factions.memberDied({ id = deathRecord.id, factionId = nil })
    and Recruitment.summary(group).status == "dead"
    and Factions.member(group, deathTrial.candidateKey).alive == false
    and Factions.summary(group.id).life.mourning ~= nil
    and Factions.summary(group.id).life.mourning.subjectName
        == Recruitment.summary(group).candidateName,
    "trial companion death is reconciled to the origin household and cannot respawn")

-- Force storage failure after household detachment. The recruitment operation
-- must restore the member and leave the candidate state retryable.
check(Factions.restore(recruitmentBaseline),
    "recruitment rollback fixture restores its pre-trial household")
group = Factions.group("faction-test")
group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
residentRecords[residentOne.id] = installFactionRecord(group.members[1], residentOne)
residentRecords[residentTwo.id] = installFactionRecord(group.members[2], residentTwo)
check(Recruitment.debugPrepare(group) and Recruitment.debugCandidate(group, player),
    "rollback fixture names a candidate")
local rollbackSummary = Recruitment.summary(group)
local rollbackMember = Factions.member(group, rollbackSummary.candidateKey)
local rollbackActor = registry[rollbackMember.actorId].actor
rollbackActor.modDataProxy = setmetatable({ SC_Id = rollbackActor.id }, {
    __newindex = function() error("simulated stable-storage failure") end,
})
local rejectedTrial, rejectedReason = Recruitment.startTrial(group, player, true)
rollbackActor.modDataProxy = nil
check(not rejectedTrial
    and string.find(tostring(rejectedReason), "faction_transition_rollback", 1, true) ~= nil
    and rollbackMember.away == nil and rollbackMember.departed ~= true
    and registry[rollbackMember.actorId].recruited == false
    and Recruitment.summary(group).status == "candidate",
    "failed command persistence rolls faction detachment back without losing the candidate: "
        .. tostring(rejectedTrial) .. "/" .. tostring(rejectedReason)
        .. "/away=" .. tostring(rollbackMember.away)
        .. "/recruited=" .. tostring(registry[rollbackMember.actorId]
            and registry[rollbackMember.actorId].recruited)
        .. "/status=" .. tostring(Recruitment.summary(group).status))

-- Continue the older faction-domain scenarios from a clean resident state.
check(Factions.restore(recruitmentBaseline),
    "post-recruitment fixture restores the original household")
group = Factions.group("faction-test")
group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
residentRecords[residentOne.id] = installFactionRecord(group.members[1], residentOne)
residentRecords[residentTwo.id] = installFactionRecord(group.members[2], residentTwo)

for _, complication in ipairs({ "hidden_severity", "diverted_delivery",
    "rival_objection", "broken_reward", "private_dissent" }) do
    check(Contracts.debugOffer("faction-test", "supply")
        and Contracts.debugComplication("faction-test", complication)
        and Contracts.debugComplete("faction-test"),
        "debug harness resolves social complication " .. complication)
end
local complicated = Factions.summary("faction-test").social
check(complicated.contractHistoryCount >= 8 and complicated.householdDebt == 25,
    "contract history retains bounded complications and unpaid household debt")
check(Contracts.debugOffer("faction-test", "medical")
    and Contracts.accept("faction-test", player, true)
    and Contracts.debugExpire("faction-test")
    and Factions.summary("faction-test").social.brokenPromises >= 1,
    "expired promises become persistent broken agreements")

player.aiming = true
local armedAccess, armedReason = Contracts.requestAccess("faction-test", player, false)
check(not armedAccess and armedReason == "lower_weapon_required",
    "household entry refuses an aimed weapon")
player.aiming = false
check(Contracts.debugAccess("faction-test", "guest")
    and Contracts.hasAccess("faction-test", player),
    "guest policy grants time-bounded house access")
local outsideRest, outsideRestReason = Contracts.safeRestStatus("faction-test", player)
local originalPlayerSquare = player.square
player.square = cell:getGridSquare(2, 2, 0)
local insideRest, insideRestReason = Contracts.safeRestStatus("faction-test", player)
player.square = originalPlayerSquare
check(not outsideRest and outsideRestReason == "enter_house_to_rest"
    and insideRest and insideRestReason == "safe_rest_available",
    "safe-rest permission distinguishes an armed boundary from a valid interior resting position")
check(Contracts.noteAction("faction-test", "theft", "test theft")
    and not Contracts.hasAccess("faction-test", player),
    "theft is remembered and immediately revokes guest access")

check(Life.debugSetPersonality("faction-test", "Militarized"),
    "trade policy fixture selects a militarized household")
local tradePolicy = Contracts.tradePolicy("faction-test")
check(tradePolicy and tradePolicy.refused.ammunition and tradePolicy.refused.weapon,
    "trade policy explicitly reserves weapons and ammunition")
local counter = Trade.quote("faction-test", {},
    { { item = item("Base.Bandage", "Medical") } })
check(counter and counter.accepted == false and counter.counterOffer == counter.requiredOffer,
    "trade quote reports an explicit numeric counteroffer")

local deepInventoryJunk = {}
for index = 1, 600 do
    deepInventoryJunk[index] = item("Base.DeepInventoryJunk" .. tostring(index), "Item")
    player.inventory:AddItem(deepInventoryJunk[index])
end
local cleanSheetA, cleanSheetB = item("Base.RippedSheets", "Medical"),
    item("Base.RippedSheets", "Medical")
local alcoholWipes = item("Base.AlcoholWipes", "Medical")
player.inventory:AddItem(cleanSheetA)
player.inventory:AddItem(cleanSheetB)
player.inventory:AddItem(alcoholWipes)
check(Contracts.debugOffer("faction-test", "medical")
    and Contracts.accept("faction-test", player, true),
    "alternative medical-delivery fixture accepts one active promise")
local deliveryProgress = Contracts.progress("faction-test", player, false)
check(deliveryProgress and deliveryProgress.ready and #deliveryProgress.requirements == 2
    and deliveryProgress.requirements[1].available >= 2,
    "contract progress previews eligible alternative goods in the player inventory")
local originalSnapshot = SurvivorCompanion.Senses.snapshot
SurvivorCompanion.Senses.snapshot = function() return { threatCount = 0 } end
local deliveredAlternative, deliveryOutcome = Contracts.fulfill("faction-test", player, false)
SurvivorCompanion.Senses.snapshot = originalSnapshot
check(deliveredAlternative and not player.inventory:contains(cleanSheetA)
    and not player.inventory:contains(cleanSheetB) and not player.inventory:contains(alcoholWipes)
    and residentOne.inventory:contains(cleanSheetA) and residentOne.inventory:contains(alcoholWipes),
    "real delivery transaction accepts clean ripped sheets and alcohol wipes, removes them from the player, and transfers them to the household: "
        .. tostring(deliveryOutcome))
for _, junk in ipairs(deepInventoryJunk) do player.inventory:Remove(junk) end
local reserves = Trade.reserveSummary("faction-test")
check(type(reserves) == "table" and #reserves >= 5
    and Contracts.tradePolicy("faction-test").refusedReasons.ammunition ~= nil,
    "trade UI data exposes baseline reserves and a reason for refused militarized stock")

check(Contracts.debugOffer("faction-test", "local_threat")
    and Contracts.accept("faction-test", player, true),
    "persistence fixture starts one active local-threat promise")
group.members[1].actorId, group.members[2].actorId = nil, nil
local socialDocument = Factions.export()
local exportedSocialGroup = socialDocument.groups["faction-test"]
check(Life.validate(exportedSocialGroup) and Contracts.validate(exportedSocialGroup),
    "exported faction life and social-contract documents pass their bounded validators")
do
    local priorGet = SurvivorCompanion.Config.get
    local limits = {
        factionContractHistoryLimit = 3,
        factionContractMemoryLimit = 4,
        factionContractPromiseLimit = 2,
        factionNotificationLimit = 3,
        factionNotificationFlagLimit = 5,
    }
    SurvivorCompanion.Config.get = function(key)
        if limits[key] ~= nil then return limits[key] end
        return priorGet(key)
    end
    local social = exportedSocialGroup.social
    social.contract.history, social.memories, social.promises = {}, {}, {}
    social.notifications, social.notificationFlagOrder, social.notificationFlags = {}, {}, {}
    for index = 1, 3 do social.contract.history[index] = { id = "history-" .. index } end
    for index = 1, 4 do social.memories[index] = { detail = "memory-" .. index } end
    for index = 1, 2 do social.promises[index] = { id = "promise-" .. index } end
    for index = 1, 3 do social.notifications[index] = { message = "notice-" .. index } end
    for index = 1, 5 do
        social.notificationFlagOrder[index] = "flag-" .. index
        social.notificationFlags["flag-" .. index] = true
    end
    check(Contracts.validateConfiguration() and Contracts.validate(exportedSocialGroup),
        "faction validator accepts the exact configured writer limits")
    social.promises[3] = { id = "one-over" }
    check(not Contracts.validate(exportedSocialGroup),
        "faction validator rejects one entry beyond the configured promise limit")
    social.promises[3] = nil
    SurvivorCompanion.Config.get = priorGet
end
local socialRestored, socialCount = Factions.restore(socialDocument)
local socialRestoredSummary = Factions.summary("faction-test")
check(socialRestored and socialCount == 1 and socialRestoredSummary
    and socialRestoredSummary.social and socialRestoredSummary.social.active
    and socialRestoredSummary.social.active.kind == "local_threat",
    "active social contract, access, memories and promises survive faction restoration: count="
        .. tostring(socialCount) .. " exported="
        .. tostring(socialDocument.groups["faction-test"] and
            socialDocument.groups["faction-test"].social and
            socialDocument.groups["faction-test"].social.contract and
            socialDocument.groups["faction-test"].social.contract.active and
            socialDocument.groups["faction-test"].social.contract.active.status))
group = Factions.group("faction-test")
Contracts.debugComplete("faction-test")

do
    local priorGroup = Factions.group("faction-test")
    local invalidFactionDocument = Factions.export()
    invalidFactionDocument.order = {}
    local invalidFactionRestored, invalidFactionReason = Factions.restore(invalidFactionDocument)
    check(not invalidFactionRestored
            and string.find(tostring(invalidFactionReason), "unordered", 1, true)
            and Factions.group("faction-test") == priorGroup,
        "invalid faction restore leaves the complete prior in-memory state untouched")
    priorGroup.__cycle = priorGroup
    local cyclicExport, cyclicExportReason = Factions.export()
    priorGroup.__cycle = nil
    check(cyclicExport == nil and string.find(tostring(cyclicExportReason),
            "cyclic", 1, true),
        "faction export rejects a cycle instead of returning a partial group")
end

local mapSaved = false
local symbols = { rows = {} }
function symbols:getDefaultTextLayerID() return "text" end
function symbols:getSymbolCount() return #self.rows end
function symbols:getSymbolByIndex(index) return self.rows[index + 1] end
function symbols:addTranslatedText(text, layer, x, y, r, g, b, a)
    local symbol = { text = text, layer = layer, x = x, y = y }
    function symbol:getTranslatedText() return self.text end
    function symbol:getUntranslatedText() return self.text end
    function symbol:setAnchor() end
    function symbol:setRGBA() end
    function symbol:setScale() end
    function symbol:setCollide() end
    function symbol:setUserDefined() end
    function symbol:setPrivate() end
    self.rows[#self.rows + 1] = symbol
    return symbol
end
function symbols:removeSymbol(symbol)
    for index, candidate in ipairs(self.rows) do
        if candidate == symbol then table.remove(self.rows, index) return end
    end
end
function symbols:removeSymbolByIndex(index) table.remove(self.rows, index + 1) end
local originalMapItem, originalWorldMapSymbols, originalUIWorldMap =
    MapItem, WorldMapSymbols, UIWorldMap
MapItem = {
    getSingleton = function() return {} end,
    SaveWorldMap = function() mapSaved = true end,
}
WorldMapSymbols = { getDefaultTextLayerID = function() return "text" end }
UIWorldMap = {
    new = function(owner)
        local mapApi = {}
        function mapApi:setMapItem(value) self.mapItem = value end
        function mapApi:getSymbolsAPIv2() return symbols end
        return { getAPIv3 = function() return mapApi end }
    end,
}
local sharedRumour = Life.debugShareRumour("faction-test", player)
check(sharedRumour and #symbols.rows == 1 and mapSaved
    and Factions.summary("faction-test").life.rumoursShared == 1,
    "debug rumour control writes one persistent annotation to the real world-map API")
check(Contracts.debugOffer("faction-test", "local_threat")
    and Contracts.accept("faction-test", player, true)
    and #symbols.rows == 2
    and Factions.summary("faction-test").social.active.marker.added == true,
    "accepting a contract adds one persistent, de-duplicated world-map marker")
check(Contracts.debugComplete("faction-test") and #symbols.rows == 1,
    "completing a contract removes its marker without touching rumour annotations")
MapItem, WorldMapSymbols, UIWorldMap = originalMapItem, originalWorldMapSymbols, originalUIWorldMap

check(Contracts.debugOffer("faction-test", "local_threat")
    and Contracts.accept("faction-test", player, true),
    "deadline warning fixture begins with one active contract")
local deadlineContract = Factions.group("faction-test").social.contract.active
deadlineContract.deadlineHour = getGameTime():getWorldAgeHours() + 10
Factions.group("faction-test").social.nextPulseAt = 0
Contracts.pulseGroup(Factions.group("faction-test"), player, clock)
local soonSocial = Factions.summary("faction-test").social
local sawSoon = soonSocial.notifications[#soonSocial.notifications].message
    == "Contract deadline is under 12 hours away."
deadlineContract.deadlineHour = getGameTime():getWorldAgeHours() + 2
Factions.group("faction-test").social.nextPulseAt = 0
Contracts.pulseGroup(Factions.group("faction-test"), player, clock + 1)
local deadlineSocial = Factions.summary("faction-test").social
check(sawSoon and #deadlineSocial.notifications > 0
    and deadlineSocial.notifications[#deadlineSocial.notifications].kind == "deadline"
    and deadlineSocial.notifications[#deadlineSocial.notifications].message
        == "Contract deadline is under 3 hours away.",
    "twelve-hour and three-hour transitions each record one persistent player-facing notification")
Contracts.withdraw("faction-test", player, true)

check(Contracts.debugOffer("faction-test", "medical")
    and Contracts.accept("faction-test", player, true),
    "patient-death cleanup fixture begins with one medical promise")
local deathGroup = Factions.group("faction-test")
local patientKey = deathGroup.social.contract.active.targetMemberKey
local patient
for _, member in ipairs(deathGroup.members) do
    if member.key == patientKey then patient = member break end
end
local brokenBeforeDeath = deathGroup.social.trade.brokenPromises
patient.alive = false
Contracts.memberDied(deathGroup, patientKey)
local patientDeathSocial = Factions.summary("faction-test").social
check(patientDeathSocial.active == nil
    and patientDeathSocial.brokenPromises == brokenBeforeDeath
    and patientDeathSocial.notifications[#patientDeathSocial.notifications].message
        == "The patient died before medical help could arrive.",
    "patient death closes a medical contract without blaming the player")
patient.alive = true

local beforeHouseholdDeath = Factions.export()
deathGroup = Factions.group("faction-test")
for _, member in ipairs(deathGroup.members) do member.alive = false end
deathGroup.lifecycle = "destroyed"
Contracts.memberDied(deathGroup, deathGroup.members[1].key)
local destroyedSocial = Factions.summary("faction-test").social
check(destroyedSocial.active == nil and destroyedSocial.offer == nil
    and destroyedSocial.access.reason == "household_destroyed",
    "destroyed household removes offers, access, and live contracts without creating a broken promise")
check(Factions.restore(beforeHouseholdDeath),
    "household-death cleanup fixture restores the pre-death document")
group = Factions.group("faction-test")
group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id

group.members[1].actorId, group.members[2].actorId = nil, nil
registry[residentOne.id], registry[residentTwo.id] = nil, nil
SurvivorCompanion.Config.get = originalConfigGet
check(Factions.forceStanding("faction-test", "Tolerated"),
    "trade comparison resets the social-contract fixture to tolerated")
local toleratedQuote = Trade.quote("faction-test",
    { { item = item("Base.Hammer", "Weapon") } },
    { { item = item("Base.Bandage", "Medical") } })
check(toleratedQuote and toleratedQuote.markup > 1.0 and toleratedQuote.accepted,
    "tolerated household trade markup reflects standing, character and remembered favor")
check(Factions.forceStanding("faction-test", "Trusted"),
    "debug standing adapter accepts a valid test standing")
local trustedQuote = Trade.quote("faction-test",
    { { item = item("Base.Bandage", "Medical") } },
    { { item = item("Base.Bandage", "Medical") } })
check(trustedQuote and trustedQuote.markup == 1.0 and trustedQuote.accepted,
    "trusted households never charge below equal value")
check(Factions.noteOffense("faction-test", "damage", 1)
    and Factions.restitutionRequired("faction-test") == 110,
    "injuring a resident records the documented double-value restitution")
local earlyRepair, earlyRepairReason = Factions.canReconcile("faction-test")
check(not earlyRepair and string.find(earlyRepairReason, "wait_", 1, true) == 1,
    "injury reconciliation enforces the seven-day cooling-off period")
local repairDocument = Factions.export()
repairDocument.groups["faction-test"].offenses[1].day = -10
check(Factions.restore(repairDocument),
    "reconciliation fixture restores after its cooling-off period")
check(Factions.canReconcile("faction-test"),
    "expired nonlethal offense becomes eligible for restitution")
local underpaid, underpaidReason = Factions.reconcile("faction-test", 109)
check(not underpaid and underpaidReason == "restitution_too_small"
    and Factions.reconcile("faction-test", 110)
    and Factions.summary("faction-test").standing == "Wary",
    "reconciliation rejects underpayment and reopens relations only at full value")
check(Factions.forceStanding("faction-test", "Trusted"),
    "murder boundary resets the reconciled fixture to trusted")
check(Factions.noteOffense("faction-test", "murder", 1)
    and Factions.summary("faction-test").standing == "Hostile",
    "member murder creates permanent faction hostility")
local canRepair, repairReason = Factions.canReconcile("faction-test")
check(not canRepair and repairReason == "murder_is_not_forgiven",
    "permanent hostility cannot be erased by a reconciliation parcel")
local exported = Factions.export()
check(exported.schema == 1 and exported.groups["faction-test"].standing == "Hostile",
    "faction standing and territory export transactionally")
local debugSpawned, debugReason = Factions.debugSpawnHousehold(player, 2)
check(not debugSpawned and debugReason == "debug_tools_disabled",
    "manual faction spawning remains fail-closed outside debug builds")
Factions.reset()
Trade.reset()
end
SurvivorCompanion.__testFactionDomain()
SurvivorCompanion.__testFactionDomain = nil

check(SurvivorCompanion.Decision.resetAll(), "central gameplay runtime reset")
check(SurvivorCompanion.Decision.peek(fellow) == nil and SurvivorCompanion.Combat.peek(fellow) == nil,
    "runtime reset clears transient Java-object state")

print("Gameplay harness PASS: " .. tostring(checks) .. " checks")
