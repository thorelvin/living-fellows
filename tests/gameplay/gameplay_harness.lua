-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local clock = 100000
function getTimestampMs() return clock end
local worldHour = 12
local rainIntensity, fogIntensity = 0, 0
function getGameTime()
    return {
        getHour = function() return worldHour end,
        getTimeOfDay = function() return worldHour end,
        getWorldAgeHours = function() return 240 + clock / 3600000 end,
    }
end
function getClimateManager()
    return {
        getPrecipitationIntensity = function() return rainIntensity end,
        getFogIntensity = function() return fogIntensity end,
    }
end
local worldSoundCount = 0
function addSound(source, x, y, z, radius, volume) worldSoundCount = worldSoundCount + 1 end
local uiSounds = {}
function getSoundManager()
    return {
        playUISound = function(_, soundName)
            uiSounds[#uiSounds + 1] = tostring(soundName)
        end,
    }
end
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
    function value:getMinRange() return self.minRange or 0 end
    function value:getSwingTime() return self.swing or 1 end
    function value:getEnduranceMod() return self.enduranceMod or 1 end
    function value:getSharpness() return self.sharpness == nil and 1 or self.sharpness end
    function value:isTwoHandWeapon() return self.twoHanded == true end
    function value:getCategories() return self.weaponCategories or {} end
    function value:isRanged() return self.ranged == true end
    function value:isJammed() return self.jammed == true end
    function value:getCurrentAmmoCount() return self.ammo or 0 end
    function value:getMaxAmmo() return self.maxAmmo or 0 end
    function value:getMagazineType() return self.magazineType end
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
    function value:getKeyId() return self.keyId or -1 end
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
    function value:isSolidTrans() return self.solidTrans == true end
    function value:TreatAsSolidFloor() return self.hasFloor ~= false end
    function value:isSafeToSpawn() return self.spawnUnsafe ~= true end
    function value:getChunk() return self.chunk or {} end
    function value:getCell() return cell end
    function value:getMovingObjects() return self.moving end
    function value:getStaticMovingObjects() return self.staticMoving end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.specialObjects end
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
        local worldItem = { item = added, square = self, xOffset = xOffset, yOffset = yOffset,
            zOffset = zOffset }
        self.worldItems[#self.worldItems + 1] = worldItem
        return worldItem
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

    registry[recruitedRestore.id] = recruitedRestore
    local stableOrder = SurvivorCompanion.Commands.peek(recruitedRestore).order
    local stableDataOrder = recruitedRestore.modData.SC_Order
    local stayToken = SurvivorCompanion.Commands.beginTemporaryStay(
        recruitedRestore, "inventory_test")
    local effectiveStay = SurvivorCompanion.Commands.effective(recruitedRestore)
    check(type(stayToken) == "table" and effectiveStay.order == "stay"
            and effectiveStay.scavenge == false
            and SurvivorCompanion.Commands.peek(recruitedRestore).order == stableOrder
            and recruitedRestore.modData.SC_Order == stableDataOrder,
        "temporary inventory Stay changes only the effective order, never saved command state")
    check(SurvivorCompanion.Commands.issue(
            recruitedRestore.id, "set_scavenge", false, player)
            and SurvivorCompanion.Commands.isTemporaryStay(recruitedRestore),
        "a non-movement setting does not accidentally release the inventory hold")
    local releasedStay, releasedStayReason = SurvivorCompanion.Commands.endTemporaryStay(
        recruitedRestore, stayToken)
    check(releasedStay and releasedStayReason == "temporary_stay_released"
            and SurvivorCompanion.Commands.effective(recruitedRestore).order == stableOrder,
        "closing inventory releases the hold back to the unchanged original order")
    local supersededToken = SurvivorCompanion.Commands.beginTemporaryStay(
        recruitedRestore, "inventory_test")
    check(SurvivorCompanion.Commands.issue(recruitedRestore.id, "stay", nil, player),
        "a real Stay command can supersede a temporary inventory hold")
    local superseded, supersededReason = SurvivorCompanion.Commands.endTemporaryStay(
        recruitedRestore, supersededToken)
    check(superseded and supersededReason == "superseded_by_command"
            and SurvivorCompanion.Commands.peek(recruitedRestore).order == "stay",
        "closing inventory never overwrites an order issued while the pane was open")
    SurvivorCompanion.Commands.reset(recruitedRestore)
    registry[recruitedRestore.id] = nil
end

local zed = zombie(1, 0, { attacking = true, target = fellow })

local defaultsChanged = pcall(function() SurvivorCompanion.GameplayUtil.Defaults.perceptionRadius = 999 end)
check(not defaultsChanged, "gameplay defaults must be immutable")

do
    -- A zombie that already targets a non-local companion must accumulate the
    -- stock target-seen grace period. Resetting this value to zero every frame held
    -- the zombie forever in the arms-out grace pose and applied invisible damage.
    local seenRefreshZombie = zombie(0.5, 0, { target = fellow })
    local originalSCBridge = SCBridge
    local bridgeAttackCalls = 0
    SCBridge = {
        startZombieAttack = function(candidate, target)
            bridgeAttackCalls = bridgeAttackCalls + 1
            check(candidate == seenRefreshZombie and target == fellow,
                "native zombie attack bridge receives the selected pair")
            if bridgeAttackCalls == 1 then return "not_facing_target" end
            return bridgeAttackCalls == 2 and "attack_started" or "attack_active"
        end,
    }
    local resolveOk = pcall(SurvivorCompanion.ZombieAttack.resolve, fellow, 100000, { seenRefreshZombie })
    -- Simulate IsoZombie.update() clearing the non-local visibility slot between
    -- every Lua decision. Continuous adapter time must still cross 0.5 seconds.
    seenRefreshZombie.target = nil
    seenRefreshZombie.targetSeenTimeSet = 0
    SurvivorCompanion.ZombieAttack.resolve(fellow, 100200, { seenRefreshZombie })
    seenRefreshZombie.target = nil
    seenRefreshZombie.targetSeenTimeSet = 0
    SurvivorCompanion.ZombieAttack.resolve(fellow, 100400, { seenRefreshZombie })
    seenRefreshZombie.target = nil
    seenRefreshZombie.targetSeenTimeSet = 0
    SurvivorCompanion.ZombieAttack.resolve(fellow, 100600, { seenRefreshZombie })
    check(resolveOk
            and seenRefreshZombie.targetSeenCalls == 4
            and seenRefreshZombie.targetSeenTimeSet >= 0.6
            and seenRefreshZombie.pathToCharacterCalls == 1
            and seenRefreshZombie.pathTarget == fellow
            and bridgeAttackCalls == 1
            and seenRefreshZombie.spottedCalls == 3,
        "incoming-attack resolve reacquires a dropped close target, preserves its bite timer, and wakes native pathing")
    seenRefreshZombie.target = nil
    SurvivorCompanion.ZombieAttack.resolve(fellow, 100700, { seenRefreshZombie })
    check(seenRefreshZombie.pathToCharacterCalls == 1 and bridgeAttackCalls == 2,
        "path refresh is throttled while target visibility is sustained every resolver tick")
    seenRefreshZombie.attacking = true
    seenRefreshZombie.currentState = "AttackState"
    seenRefreshZombie.target = nil
    SurvivorCompanion.ZombieAttack.resolve(fellow, 101500, { seenRefreshZombie })
    check(seenRefreshZombie.pathToCharacterCalls == 1 and bridgeAttackCalls == 3,
        "an active native attack keeps visibility alive without restarting pathing or attack state")
    SCBridge = originalSCBridge
    seenRefreshZombie.dead = true
end

do
    -- 4.7: incoming zombie attacks are edge-triggered -- one wound per swing
    -- episode. A zombie's attack state (and its "success" outcome afterwards) stays
    -- true across many frames, so the old level check re-applied the same swing
    -- every tick, bounded only by a time cooldown that in turn swallowed a genuine
    -- fast second swing. Each distinct swing must now land exactly one wound.
    local function woundableBody()
        local part = { health = 100 }
        function part:getHealth() return self.health end
        function part:SetHealth(value) self.health = value return true end
        function part:setBleeding(value) self.bleeding = value == true end
        function part:SetBitten(value) self.bitten = value == true end
        function part:setScratched(...)
            self.scratchArgumentCount = select("#", ...)
            self.scratched = select(1, ...) == true
            self.scratchFromWeapon = select(2, ...)
        end
        function part:setDeepWounded(value) self.deep = value == true end
        function part:setWoundInfectionLevel(value) self.infection = value end
        local parts = { part }
        local partList = {}
        function partList:size() return #parts end
        function partList:get(index) return parts[index + 1] end
        local body = {}
        function body:getBodyParts() return partList end
        return body, part
    end
    SurvivorCompanion.ZombieAttack.reset()
    local edgeBody, edgePart = woundableBody()
    local edgeVictim = actor("sc-edge-victim", 20, 20, { body = edgeBody })
    local edgeZombie = zombie(21, 20, {
        target = edgeVictim, attacking = true, attackOutcome = "success",
    })
    local clockE = 500000
    local originalZombRand = ZombRand
    ZombRand = function(maximum)
        -- 0.300 is above the 0.25 bite threshold and inside the scratch band.
        return maximum == 1000 and 300 or 0
    end
    local _, _, s1 = SurvivorCompanion.ZombieAttack.resolve(edgeVictim, clockE, { edgeZombie })
    check(s1.landed == 1 and s1.applied == 1
            and edgePart.scratched == true and edgePart.scratchArgumentCount == 2
            and edgePart.scratchFromWeapon == false,
        "the rising edge applies a scratch with Build 42's two-argument setter")
    clockE = clockE + 50
    local _, _, s2 = SurvivorCompanion.ZombieAttack.resolve(edgeVictim, clockE, { edgeZombie })
    check(s2.landed == 1 and s2.applied == 0,
        "the same ongoing swing does not re-apply while the zombie stays committed")
    edgeZombie.attacking = false
    clockE = clockE + 50
    SurvivorCompanion.ZombieAttack.resolve(edgeVictim, clockE, { edgeZombie })
    edgeZombie.attacking = true
    clockE = clockE + 400
    local _, _, s4 = SurvivorCompanion.ZombieAttack.resolve(edgeVictim, clockE, { edgeZombie })
    check(s4.applied == 1,
        "a fresh swing after the zombie leaves and re-enters its attack lands another wound")
    edgeZombie.attacking = false
    edgeZombie.attackOutcome = nil
    SurvivorCompanion.ZombieAttack.resolve(edgeVictim, clockE + 50, { edgeZombie })
    edgeZombie.attacking = true
    edgeZombie.attackOutcome = "success"
    edgeZombie.attackDidDamage = true
    local healthBeforeNative = edgePart.health
    local _, _, nativeSwing = SurvivorCompanion.ZombieAttack.resolve(
        edgeVictim, clockE + 400, { edgeZombie })
    check(nativeSwing.landed == 1 and nativeSwing.applied == 0
            and edgePart.health == healthBeforeNative,
        "a native Build 42 attack collision is not followed by a duplicate fallback wound")
    SurvivorCompanion.ZombieAttack.reset()
    ZombRand = originalZombRand
    edgeZombie.dead = true
end

do
    -- A committed pile must visibly pull the companion down, keep the runtime's
    -- grabbed gate active, and release every native flag when the pile is gone.
    -- This is deterministic coverage for the companion-specific part after the
    -- stock zombie attack animation has brought the attackers into grab range.
    SurvivorCompanion.ZombieAttack.reset()
    local grappleVictim = actor("sc-grapple-victim", 24, 24, {})
    local firstGrabber = zombie(25, 24, { target = grappleVictim })
    local secondGrabber = zombie(24, 25, { target = grappleVictim })
    local values = SurvivorCompanion.Config.values
    local priorThreshold = values.zombieGrabThreshold
    local priorChance = values.zombieGrabChance
    local priorEscape = values.zombieGrabEscapeChance
    local priorGrace = values.zombieGrabGraceMs
    local priorFarewellDelay = values.lastWordsDeathDelayMs
    values.zombieGrabThreshold = 2
    values.zombieGrabChance = 1
    values.zombieGrabEscapeChance = 0
    values.zombieGrabGraceMs = 100
    values.lastWordsDeathDelayMs = 200
    local originalZombRand = ZombRand
    ZombRand = function() return 0 end

    local _, _, grabbed = SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 600000, { firstGrabber, secondGrabber })
    check(grabbed.attackers == 2 and grabbed.grapple == "grabbed_now"
            and grappleVictim.knockedDown == true
            and grappleVictim.stopped == true
            and SurvivorCompanion.ZombieAttack.isGrabbed(grappleVictim),
        "two committed adjacent zombies pull a companion down and gate its decisions")

    firstGrabber.dead = true
    secondGrabber.dead = true
    local _, _, released = SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 600100, { firstGrabber, secondGrabber })
    check(released.attackers == 0 and released.grapple == "grab_broken"
            and grappleVictim.knockedDown == false
            and grappleVictim.deathDragDown == false
            and not SurvivorCompanion.ZombieAttack.isGrabbed(grappleVictim),
        "removing the zombie pile releases the companion and clears native grapple flags")

    firstGrabber.dead, secondGrabber.dead = false, false
    SurvivorCompanion.ZombieAttack.reset(grappleVictim)
    SurvivorCompanion.Dialogue.reset(grappleVictim)
    local originalEndLife = SurvivorCompanion.Actor.endLife
    SurvivorCompanion.Actor.endLife = function(victim)
        victim.dead = true
        victim.fatalInjuryApplied = true
        return true
    end
    SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 601000, { firstGrabber, secondGrabber })
    local _, _, farewell = SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 601100, { firstGrabber, secondGrabber })
    check(farewell.grapple == "grab_farewell" and grappleVictim.dead == false
            and grappleVictim.knockedDown == true
            and SurvivorCompanion.Dialogue.lastSpokenTopic(grappleVictim)
                == "lastwords.zombies",
        "an unrecoverable drag-down speaks through the still-living companion before cleanup")
    firstGrabber.dead, secondGrabber.dead = true, true
    local _, _, farewellHeld = SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 601299, { firstGrabber, secondGrabber })
    check(farewellHeld.grapple == "grab_farewell" and grappleVictim.dead == false,
        "the fatal farewell beat cannot become a false rescue when the pile thins")
    local _, _, killed = SurvivorCompanion.ZombieAttack.resolve(
        grappleVictim, 601300, { firstGrabber, secondGrabber })
    check(killed.grapple == "grab_killed" and grappleVictim.dead == true
            and grappleVictim.fatalInjuryApplied == true,
        "fatal injury is committed only after the configured last-words display delay")
    SurvivorCompanion.Actor.endLife = originalEndLife

    ZombRand = originalZombRand
    values.zombieGrabThreshold = priorThreshold
    values.zombieGrabChance = priorChance
    values.zombieGrabEscapeChance = priorEscape
    values.zombieGrabGraceMs = priorGrace
    values.lastWordsDeathDelayMs = priorFarewellDelay
    SurvivorCompanion.ZombieAttack.reset()
end

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

do
local function verifyPerceptionCoverage(radius, budget, label)
    local state, horizontal, vertical = {}, {}, {}
    local horizontalWrapped, verticalWrapped = false, false
    local maximumScans = 256
    for _ = 1, maximumScans do
        local offsets, meta = SurvivorCompanion.Senses._nextScanOffsetsForTests(
            state, radius, budget)
        if #offsets > budget then break end
        for _, offset in ipairs(offsets) do
            local key = tostring(offset.x) .. ":" .. tostring(offset.y)
            if (offset.z or 0) == 0 then
                horizontal[key] = true
            else
                vertical[key .. ":" .. tostring(offset.z)] = true
            end
        end
        horizontalWrapped = horizontalWrapped or meta.horizontalWrapped == true
        verticalWrapped = verticalWrapped or meta.verticalWrapped == true
        if horizontalWrapped and verticalWrapped then break end
    end
    local complete = horizontalWrapped and verticalWrapped
    for dx = -radius, radius do
        for dy = -radius, radius do
            complete = complete and horizontal[tostring(dx) .. ":" .. tostring(dy)] == true
        end
    end
    for dx = -2, 2 do
        for dy = -2, 2 do
            for _, dz in ipairs({ -1, 1 }) do
                complete = complete and vertical[tostring(dx) .. ":" .. tostring(dy)
                    .. ":" .. tostring(dz)] == true
            end
        end
    end
    check(complete and horizontal["13:-1"] == true,
        label .. " advances a persistent frontier until every horizontal and vertical offset is sampled")
end

verifyPerceptionCoverage(18, 240, "production perception budget")
verifyPerceptionCoverage(18, 80, "load-shed perception budget")
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

do
    local hearingActor = actor("sc-wall-hearing", 10, 10, {})
    local hiddenZombie = zombie(12, 10, { moving = true })
    hiddenZombie.square.losBlocked = true
    check(not SurvivorCompanion.GameplayUtil.canSee(hearingActor, hiddenZombie),
        "actor LOS rejects a zombie behind blocked native sight")

    local hearingRuntime = {}
    local hiddenSnapshot = SurvivorCompanion.Senses.snapshot(
        hearingActor, player, hearingRuntime)
    check(hiddenSnapshot.threatCount == 0 and hiddenSnapshot.immediateCount == 0
            and hiddenSnapshot.heardThreatCount == 1
            and hiddenSnapshot.lastHeardDanger
            and hiddenSnapshot.lastHeardDanger.kind == "zombie"
            and hiddenSnapshot.lastKnownDanger == nil,
        "a moving zombie behind a closed wall is heard but never promoted to a visual threat")
    check(#SurvivorCompanion.Combat.scoreTargets(hearingActor, player, {
            threats = { {
                actor = hiddenZombie, distanceSq = 4, visible = false,
                obstructed = true, attacking = true, score = 999,
            } },
            allies = {},
        }, nil) == 0,
        "combat rejects an unseen wall-obstructed zombie even when a stale snapshot scores it highly")

    hiddenZombie.square.losBlocked = false
    clock = clock + 100
    local visibleSnapshot = SurvivorCompanion.Senses.snapshot(
        hearingActor, player, hearingRuntime)
    local lastSeenX = visibleSnapshot.lastKnownDanger and visibleSnapshot.lastKnownDanger.x
    check(visibleSnapshot.threatCount == 1 and lastSeenX ~= nil
            and visibleSnapshot.lastKnownDanger.actor == nil,
        "visual contact creates a fixed last-seen position without exposing a live target reference")

    for index = #hiddenZombie.square.moving, 1, -1 do
        if hiddenZombie.square.moving[index] == hiddenZombie then
            table.remove(hiddenZombie.square.moving, index)
        end
    end
    local movedHiddenSquare = cell:getGridSquare(13, 10, 0)
    movedHiddenSquare.losBlocked = true
    hiddenZombie.square = movedHiddenSquare
    movedHiddenSquare.moving[#movedHiddenSquare.moving + 1] = hiddenZombie
    clock = clock + 100
    local lostSnapshot = SurvivorCompanion.Senses.snapshot(
        hearingActor, player, hearingRuntime)
    check(lostSnapshot.threatCount == 0 and lostSnapshot.lastKnownDanger
            and lostSnapshot.lastKnownDanger.x == lastSeenX,
        "last-seen memory stays at the observed square when the zombie moves behind a wall")

    local heardWarningActor = actor("sc-heard-warning", 10, 12, {})
    SurvivorCompanion.Decision.update(heardWarningActor, player, {
        snapshot = {
            threats = {}, immediateAttackers = {}, threatCount = 0, immediateCount = 0,
            pressure = 0, escapeSquares = {}, allies = {},
            heardThreats = lostSnapshot.heardThreats,
            heardThreatCount = lostSnapshot.heardThreatCount,
            lastHeardDanger = lostSnapshot.lastHeardDanger,
            player = { actor = player, danger = 0 },
        },
    })
    check(type(heardWarningActor.lastSpeech) == "string"
            and SurvivorCompanion.Dialogue.lastSpokenTopic(heardWarningActor) == "danger.heard",
        "an unseen audible walker produces uncertain heard-contact dialogue")

    hiddenZombie.dead = true
    for index = #movedHiddenSquare.moving, 1, -1 do
        if movedHiddenSquare.moving[index] == hiddenZombie then
            table.remove(movedHiddenSquare.moving, index)
        end
    end
end

do
    local reflexActor = actor("sc-reflex-senses", -6, -7, {})
    local reflexRuntime = {}
    local broadSnapshot = SurvivorCompanion.Senses.snapshot(
        reflexActor, player, reflexRuntime)
    local broadTime = broadSnapshot.time
    local reflexZombie = zombie(-5, -7, { moving = true })
    clock = clock + 101
    local reflexSnapshot = SurvivorCompanion.Senses.refreshImmediate(
        reflexActor, player, broadSnapshot, reflexRuntime)
    check(reflexSnapshot.time == broadTime and reflexSnapshot.reflexTime == clock
            and reflexSnapshot.threatCount == 1
            and reflexSnapshot.reflexAddedThreats == 1
            and reflexRuntime.senses.reflexCount == 1,
        "a zombie entering melee range is acquired by the reflex pass before the broad scan restarts")

    reflexZombie.square.losBlocked = true
    clock = clock + 101
    local heardReflex = SurvivorCompanion.Senses.refreshImmediate(
        reflexActor, player, reflexSnapshot, reflexRuntime)
    check(heardReflex.threatCount == 0 and heardReflex.heardThreatCount == 1
            and heardReflex.lastHeardDanger.actor == nil
            and heardReflex.lastHeardDanger.square == nil,
        "the reflex pass demotes a wall-hidden walker to uncertain sound instead of targeting it")
    reflexZombie.dead = true
    reflexZombie.square.losBlocked = false
    for index = #reflexZombie.square.moving, 1, -1 do
        if reflexZombie.square.moving[index] == reflexZombie then
            table.remove(reflexZombie.square.moving, index)
        end
    end
    SurvivorCompanion.Senses.reset(reflexActor)
    for index = #reflexActor.square.moving, 1, -1 do
        if reflexActor.square.moving[index] == reflexActor then
            table.remove(reflexActor.square.moving, index)
        end
    end
end

do
    local priorThreatLimit = SurvivorCompanion.Config.values.perceptionThreatLimit
    SurvivorCompanion.Config.values.perceptionThreatLimit = 3
    local cappedActor = actor("sc-reflex-cap", 8, 5, {})
    local oldContacts = {
        zombie(12, 5, {}), zombie(12, 6, {}), zombie(12, 7, {}),
    }
    local immediateContacts = {
        zombie(9, 5, { attacking = true, target = cappedActor }),
        zombie(7, 5, { attacking = true, target = cappedActor }),
        zombie(8, 6, { attacking = true, target = cappedActor }),
        zombie(8, 4, { attacking = true, target = cappedActor }),
    }
    local cappedPrior = { time = clock, threats = {}, stealthThreats = {} }
    for _, old in ipairs(oldContacts) do
        local prior = { actor = old }
        cappedPrior.threats[#cappedPrior.threats + 1] = prior
        cappedPrior.stealthThreats[#cappedPrior.stealthThreats + 1] = prior
    end
    clock = clock + 101
    local cappedReflex = SurvivorCompanion.Senses.refreshImmediate(
        cappedActor, player, cappedPrior, {})
    local retainedImmediateOnly = #cappedReflex.threats == 3
    for _, threat in ipairs(cappedReflex.threats or {}) do
        if (tonumber(threat.distanceSq) or math.huge) > 1.01 then
            retainedImmediateOnly = false
        end
    end
    check(retainedImmediateOnly and cappedReflex.threatCount == 3
            and #cappedReflex.immediateAttackers == 3
            and cappedReflex.immediateCount == 4
            and cappedReflex.immediateOverflow == 1
            and cappedReflex.threatOverflow == 4
            and cappedReflex.reflexAddedThreats == 4
            and cappedReflex.pressure > 6,
        "new adjacent attackers displace a full distant cache while bounded overflow preserves total immediate danger")
    SurvivorCompanion.Config.values.perceptionThreatLimit = priorThreatLimit
    SurvivorCompanion.Senses.reset(cappedActor)
    local cleanup = { cappedActor }
    for _, value in ipairs(oldContacts) do cleanup[#cleanup + 1] = value end
    for _, value in ipairs(immediateContacts) do cleanup[#cleanup + 1] = value end
    for _, value in ipairs(cleanup) do
        if value.square and value.square.moving then
            for index = #value.square.moving, 1, -1 do
                if value.square.moving[index] == value then
                    table.remove(value.square.moving, index)
                end
            end
        end
    end
end

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
local crawlerFlags = {}
for _, threat in ipairs(crawlerSnapshot.stealthThreats or {}) do
    if threat.actor == stealthCrawler and threat.prone == true then crawlerFlags.avoided = true break end
end
for _, threat in ipairs(crawlerSnapshot.threats or {}) do
    if threat.actor == stealthCrawler and threat.grounded == true
        and threat.posture ~= "standing" then crawlerFlags.targetable = true break end
end
for _, threat in ipairs(crawlerSnapshot.groundedThreats or {}) do
    if threat.actor == stealthCrawler then crawlerFlags.grounded = true break end
end
check(crawlerFlags.avoided and crawlerFlags.targetable and crawlerFlags.grounded,
    "living crawlers remain visible combat targets with explicit grounded posture")
for index = #stealthCrawler.square.moving, 1, -1 do
    if stealthCrawler.square.moving[index] == stealthCrawler then
        table.remove(stealthCrawler.square.moving, index)
    end
end

(function()
    local lockActor = actor("sc-target-lock-senses", 50, 50, {})
    local lockedZombie = zombie(53, 50, { target = lockActor, attacking = false })
    local lockedSnapshot = SurvivorCompanion.Senses.snapshot(lockActor, player, {})
    local record = lockedSnapshot.threats[1]
    check(record and record.actor == lockedZombie and record.targeting == true
            and record.attacking == false and lockedSnapshot.immediateCount == 0,
        "a distant zombie target lock is recorded without masquerading as an attack animation")
    lockedZombie.dead = true
    for index = #lockedZombie.square.moving, 1, -1 do
        if lockedZombie.square.moving[index] == lockedZombie then
            table.remove(lockedZombie.square.moving, index)
        end
    end
    for index = #lockActor.square.moving, 1, -1 do
        if lockActor.square.moving[index] == lockActor then
            table.remove(lockActor.square.moving, index)
        end
    end
end)()

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

(function()
    local rebaseClock = clock
    local movingActor = actor("sc-perception-rebase", 13, -8, {})
    local runtime = {}
    SurvivorCompanion.Performance.reset()
    SurvivorCompanion.Performance.beginFrame(2, clock)
    local initial = SurvivorCompanion.Senses.snapshot(movingActor, player, runtime)
    SurvivorCompanion.Performance.endFrame(1, false)
    check(initial.scanComplete == false,
        "moving-perception fixture begins with an unfinished bounded scan")

    for index = #movingActor.square.moving, 1, -1 do
        if movingActor.square.moving[index] == movingActor then
            table.remove(movingActor.square.moving, index)
        end
    end
    movingActor.square = cell:getGridSquare(10, -8, 0)
    movingActor.square.moving[#movingActor.square.moving + 1] = movingActor
    local newLocalThreat = zombie(5, -8, { moving = true })
    local discovered, latest, discoveryPass = false, nil, nil
    for pass = 1, 4 do
        clock = clock + 16
        SurvivorCompanion.Performance.beginFrame(2, clock)
        latest = SurvivorCompanion.Senses.snapshot(movingActor, player, runtime)
        SurvivorCompanion.Performance.endFrame(1, false)
        for _, threat in ipairs(latest.threats or {}) do
            if threat.actor == newLocalThreat then
                discovered, discoveryPass = true, pass
                break
            end
        end
        if discovered then break end
    end
    check(latest and latest.scanRebaseCount == 1
            and latest.lastScanRebaseDistance >= 3
            and latest.lastScanRebaseAt ~= nil,
        "an unfinished perception scan rebases after meaningful actor movement and records telemetry")
    check(discovered and discoveryPass <= 4,
        "the rebased scan discovers a new local threat within four bounded slices")

    newLocalThreat.dead = true
    for _, value in ipairs({ movingActor, newLocalThreat }) do
        for index = #value.square.moving, 1, -1 do
            if value.square.moving[index] == value then table.remove(value.square.moving, index) end
        end
    end
    SurvivorCompanion.Senses.reset(movingActor)
    SurvivorCompanion.Performance.reset()
    clock = rebaseClock
end)()

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
(function()
    local budgetJob = SurvivorCompanion.Navigation.beginPathSearch(
        fellow.square, squares[squareKey(3, 0, 0)], nil, { nodeBudget = 1 })
    local status, _, reason = SurvivorCompanion.Navigation.resumePathSearch(budgetJob, 8)
    check(status == "failed" and reason == "budget"
            and budgetJob.failure
            and budgetJob.failure.failureClass == "budget_exhausted"
            and budgetJob.failure.nativeFallbackAllowed == true,
        "an exhausted bounded search is classified for a native-path fallback")
end)()

do
    local routeActor = actor("sc-route-repair", 30, 28, {})
    local source = cell:getGridSquare(30, 28, 0)
    local oldGoal = cell:getGridSquare(34, 28, 0)
    local movedGoal = cell:getGridSquare(34, 30, 0)
    local oldPath = SurvivorCompanion.Navigation.findPath(source, oldGoal)
    local routeState = {
        path = oldPath, pathGoalSquare = oldGoal, pathIndex = 2,
        blockedEdges = {}, routeMemory = {},
    }
    local oldLength = #oldPath
    check(SurvivorCompanion.Navigation._repairMovingPathForTests(
            routeActor, routeState, source, movedGoal,
            { action = "follow_formation", followRecovery = true }, clock)
            and routeState.pathGoalSquare == movedGoal
            and #routeState.path == oldLength + 2
            and routeState.routeRepairCount == 1,
        "a nearby moving formation goal extends the valid A* route without a full replan")

    local suffixPath = SurvivorCompanion.Navigation.findPath(
        source, cell:getGridSquare(35, 28, 0))
    local suffixState = {
        path = suffixPath, pathGoalSquare = suffixPath[#suffixPath], pathIndex = 2,
        blockedEdges = {}, routeMemory = {},
    }
    local detourSquare = cell:getGridSquare(32, 29, 0)
    check(SurvivorCompanion.Navigation._reusePathSuffixForTests(
            routeActor, suffixState, detourSquare,
            { action = "follow_formation", followRecovery = true }, clock)
            and suffixState.pathIndex >= 3 and suffixState.routeReuseCount == 1,
        "a short native detour rejoins a validated later route edge instead of restarting A-star")
    local overshootState = {
        path = suffixPath, pathGoalSquare = suffixPath[#suffixPath], pathIndex = 2,
        blockedEdges = {}, routeMemory = {},
    }
    routeActor.worldX, routeActor.worldY = 31.7, 28.5
    check(SurvivorCompanion.Navigation._correctRouteProjectionForTests(
            routeActor, overshootState, source,
            { action = "follow_formation", followRecovery = true }, clock)
            and overshootState.pathIndex >= 3
            and overshootState.routeOvershootCount == 1
            and #overshootState.blockedEdges == 0,
        "passing a route segment advances to its suffix without blacklisting or rebuilding the path")
    for index = #routeActor.square.moving, 1, -1 do
        if routeActor.square.moving[index] == routeActor then
            table.remove(routeActor.square.moving, index)
        end
    end
end

do
    local savedUnits = SurvivorCompanion.Config.values.performanceNavigationNodesPerFrame
    local savedNativeActions = SurvivorCompanion.NativeActions
    local searchStops = 0
    SurvivorCompanion.Config.values.performanceNavigationNodesPerFrame = 1
    SurvivorCompanion.NativeActions = {
        stopDirect = function(value)
            searchStops = searchStops + 1
            value.moving = false
            return true
        end,
    }
    SurvivorCompanion.Performance.reset()
    SurvivorCompanion.Performance.beginFrame(2, clock)
    local responsiveFollower = actor("sc-responsive-follow-search", -10, 18,
        { moving = true })
    registry[responsiveFollower.id] = responsiveFollower
    local accepted, reason = SurvivorCompanion.Navigation.request(
        responsiveFollower, cell:getGridSquare(-4, 18, 0), "walk", {
            action = "follow_formation", followRecovery = true, player = player,
            snapshot = { threats = {}, allies = {} },
        })
    local searchState = SurvivorCompanion.Navigation.peek(responsiveFollower)
    check(accepted and reason == "path_searching" and searchStops == 1
            and responsiveFollower.moving == false and searchState.pathSearchHolding == true,
        "a yielded replacement route stops stale forward input exactly once")
    check(searchState.pathSearch and searchState.pathSearch.alternatives == false
            and searchState.pathSearch.route.alternatives == false,
        "a moving formation goal uses its primary route without waiting for alternatives")
    SurvivorCompanion.Performance.endFrame(1, false)
    SurvivorCompanion.Navigation.reset(responsiveFollower)
    registry[responsiveFollower.id] = nil
    SurvivorCompanion.NativeActions = savedNativeActions
    SurvivorCompanion.Config.values.performanceNavigationNodesPerFrame = savedUnits
    SurvivorCompanion.Performance.reset()
end

do
    -- Egress has no fixed destination, so it remains a weighted Dijkstra search.
    -- Verify the heap-backed implementation prefers two clean indoor steps over
    -- the geometrically nearer but expensive tree square.
    local egressStart = cell:getGridSquare(8, 6, 0)
    local egressEast = cell:getGridSquare(9, 6, 0)
    local egressGoal = cell:getGridSquare(10, 6, 0)
    local egressWest = cell:getGridSquare(7, 6, 0)
    local egressNorth = cell:getGridSquare(8, 5, 0)
    local egressSouth = cell:getGridSquare(8, 7, 0)
    local egressNorth2 = cell:getGridSquare(8, 4, 0)
    local egressSouth2 = cell:getGridSquare(8, 8, 0)
    local room = { name = "egress-test" }
    egressStart.room, egressEast.room = room, room
    egressNorth.room, egressSouth.room = room, room
    egressNorth2.room, egressSouth2.room = room, room
    egressGoal.room, egressWest.room = nil, nil
    egressWest.hasTree = true
    local outdoorPath, outdoorReason = SurvivorCompanion.Navigation.findOutdoorPath(egressStart)
    check(outdoorPath and outdoorReason == nil and #outdoorPath == 3
            and outdoorPath[2] == egressEast and outdoorPath[3] == egressGoal,
        "heap-backed Dijkstra egress selects the least-cost outdoor route")
    egressStart.room, egressEast.room = nil, nil
    egressNorth.room, egressSouth.room = nil, nil
    egressNorth2.room, egressSouth2.room = nil, nil
    egressWest.hasTree = false
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
local binSquare = cell:getGridSquare(2, -7, 0)
local rubbishBin = { __class = "IsoObject" }
function rubbishBin:isThumpable() return false end
function rubbishBin:isBlockAllTheSquare() return true end
function rubbishBin:isStairsObject() return false end
binSquare.objects[#binSquare.objects + 1] = rubbishBin
local binRoute = SurvivorCompanion.Navigation.findPath(
    cell:getGridSquare(0, -7, 0), cell:getGridSquare(4, -7, 0))
local enteredBin = false
for _, square in ipairs(binRoute or {}) do
    if square == binSquare then enteredBin = true end
end
check(binRoute ~= nil and enteredBin == false
        and select(2, SurvivorCompanion.GameplayUtil.squareStaticBlocker(binSquare))
            == "full_square_object",
    "non-thumpable full-square moveables such as rubbish bins are excluded from routes")
binSquare.objects = {}
end

do
local collisionActor = actor("sc-collision-memory", 6, -7, {})
registry[collisionActor.id] = collisionActor
local collisionFrom = cell:getGridSquare(6, -7, 0)
local collisionTile = cell:getGridSquare(7, -7, 0)
local collisionGoal = cell:getGridSquare(9, -7, 0)
collisionActor.collidedVehicle = true
local collisionState = { blockedEdges = {}, blockedSquares = {}, routeMemory = {} }
SurvivorCompanion.Navigation._rememberFailureForTests(collisionActor, collisionState,
    collisionFrom, collisionTile, "native_path_failed", clock, "native_edge_replan")
collisionActor.collidedVehicle = false
local collisionRoute = SurvivorCompanion.Navigation.findPath(
    collisionFrom, collisionGoal, { blockedSquares = collisionState.blockedSquares, now = clock })
local reusedCollisionTile = false
for _, square in ipairs(collisionRoute or {}) do
    if square == collisionTile then reusedCollisionTile = true end
end
check(collisionState.blockedSquares[SurvivorCompanion.GameplayUtil.squareKey(collisionTile)]
        and collisionRoute ~= nil and reusedCollisionTile == false,
    "a native vehicle collision blacklists the whole capsule tile for the next A-star route")
local diagnosticLine
local originalPrint = print
print = function(value) diagnosticLine = tostring(value) end
SurvivorCompanion.GameplayUtil.diagnostic(
    "actor-id-regression", collisionActor, "type=vehicle")
print = originalPrint
check(diagnosticLine and string.find(diagnosticLine,
        "actor=sc-collision-memory", 1, true) ~= nil,
    "navigation diagnostics identify the companion that hit the blocker")
registry[collisionActor.id] = nil
for index = #collisionActor.square.moving, 1, -1 do
    if collisionActor.square.moving[index] == collisionActor then
        table.remove(collisionActor.square.moving, index)
    end
end
end

do
local fenceFrom = cell:getGridSquare(5, -6, 0)
local fenceTo = cell:getGridSquare(6, -6, 0)
local priorHoppable = fenceFrom.isHoppableTo
local priorGetHoppable = fenceFrom.getHoppableTo
local lowFence = { tall = false }
function lowFence:isTallHoppable() return self.tall == true end
function fenceFrom:isHoppableTo(other) return other == fenceTo end
function fenceFrom:getHoppableTo(other) return other == fenceTo and lowFence or nil end
local fenceActor = actor("sc-fence-crossing", 5, -6, {})
registry[fenceActor.id] = fenceActor
local fenceAccepted = SurvivorCompanion.Navigation.request(
    fenceActor, fenceTo, "walk", { action = "follow_formation", followRecovery = true,
        snapshot = { allies = {} } })
check(fenceAccepted and fenceActor.lastIntent
        and fenceActor.lastIntent.action == "climb_fence"
        and fenceActor.lastIntent.object == lowFence
        and fenceActor.lastIntent.direction == "east",
    "a selected low-fence edge starts an explicit native player fence climb")
lowFence.tall = true
SurvivorCompanion.Navigation.reset(fenceActor)
fenceActor.lastIntent = nil
local wallAccepted, wallReason = SurvivorCompanion.Navigation._handleFenceForRequest(
    fenceActor, lowFence, fenceFrom, fenceTo, { action = "follow_formation" })
check(wallAccepted and fenceActor.lastIntent
        and fenceActor.lastIntent.action == "climb_wall",
    "a tall hoppable wall selects the native player wall-climb action: "
        .. tostring(wallReason) .. "/"
        .. tostring(fenceActor.lastIntent and fenceActor.lastIntent.action))
fenceActor.rejectWallClimb = true
local rejectedWall = SurvivorCompanion.Topology.classifyEdge(
    fenceActor, fenceFrom, fenceTo, {})
check(rejectedWall.traversable == false and rejectedWall.reason == "wall_not_climbable",
    "a tall wall is rejected when the stock character climb check says it is unsafe")
fenceActor.rejectWallClimb = nil
SurvivorCompanion.Navigation.reset(fenceActor)
registry[fenceActor.id] = nil
for index = #fenceActor.square.moving, 1, -1 do
    if fenceActor.square.moving[index] == fenceActor then
        table.remove(fenceActor.square.moving, index)
    end
end
fenceFrom.isHoppableTo = priorHoppable
fenceFrom.getHoppableTo = priorGetHoppable
end

do
local gateFrom = cell:getGridSquare(10, -6, 0)
local gateTo = cell:getGridSquare(11, -6, 0)
local openGate = { open = true, locked = false }
function openGate:IsOpen() return self.open end
function openGate:isLocked() return self.locked end
local priorDoorTo = gateFrom.getDoorTo
function gateFrom:getDoorTo(other) return other == gateTo and openGate or nil end
local gateObject, gateKind = SurvivorCompanion.Topology.barrierBetween(gateFrom, gateTo)
check(gateObject == openGate and gateKind == "door"
        and SurvivorCompanion.Topology.classifyEdge(nil, gateFrom, gateTo, {}).traversable,
    "an open gate remains a traversable door affordance instead of becoming a fence")
gateFrom.getDoorTo = priorDoorTo
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

local basicNavigationActor = actor("sc-basic-navigation", 8, -8, {})
registry[basicNavigationActor.id] = basicNavigationActor
local navigationOK = SurvivorCompanion.Navigation.request(basicNavigationActor,
    squares[squareKey(11, -8, 0)], "walk", { snapshot = { threats = {}, allies = {} } })
check(navigationOK and basicNavigationActor.lastIntent
        and basicNavigationActor.lastIntent.humanAnimationOnly,
    "navigation uses the actor bridge with human animation intent")
check(basicNavigationActor.lastIntent.nextSquare
        and basicNavigationActor.lastIntent.targetSquare
        and basicNavigationActor.lastIntent.direction,
    "navigation emits normalized target, next-square, and direction intent fields")
SurvivorCompanion.Navigation.reset(basicNavigationActor)
registry[basicNavigationActor.id] = nil

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
clock = clock + 1000
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
-- review 3.2: occupancy is a cost, not a hard rejection. Static traversability
-- (a solid/blocked square) and dynamic occupancy (a mover standing on the square)
-- are separate concerns: a mover-occupied goal the search allows is reachable,
-- while a statically blocked square is never traversable.
local passableEdge = SurvivorCompanion.Navigation._passableEdgeForTests
local fromSquare = cell:getGridSquare(45, 12, 0)
local openGoal = cell:getGridSquare(46, 12, 0)
local occupiedGoal = cell:getGridSquare(45, 13, 0)
local blockedGoal = cell:getGridSquare(44, 12, 0)
local mover = actor("sc-occupied-goal-mover", 45, 12, {})
local occupant = actor("sc-occupied-goal-occupant", 45, 13, {})
occupiedGoal.moving = { occupant }
blockedGoal.solid = true
local crowdPenalty = SurvivorCompanion.Config.values.navigationCrowdPenalty or 9

local openPassable, openCost = passableEdge(fromSquare, openGoal, 1, { actor = mover })
check(openPassable and openCost < crowdPenalty,
    "an unobstructed adjacent edge is cheaply passable")

local crowdPassable, crowdCost = passableEdge(fromSquare, occupiedGoal, 1, { actor = mover })
check(crowdPassable and crowdCost >= crowdPenalty,
    "a mover on the square adds crowd cost rather than blocking the edge")

local goalPassable, goalCost = passableEdge(fromSquare, occupiedGoal, 1,
    { actor = mover, allowOccupiedGoal = true })
check(goalPassable and goalCost < crowdCost,
    "an occupied goal the search allows is passable with no crowd penalty -- occupied goals stay reachable")

local blockedPassable = passableEdge(fromSquare, blockedGoal, 1,
    { actor = mover, allowOccupiedGoal = true })
check(not blockedPassable,
    "a statically blocked square stays impassable even when the goal is allowed to be occupied")

local vehicleBody = cell:getGridSquare(50, 12, 0)
local vehicleNearFrom = cell:getGridSquare(48, 12, 0)
local vehicleNear = cell:getGridSquare(49, 12, 0)
local vehicleFarFrom = cell:getGridSquare(48, 14, 0)
local vehicleFar = cell:getGridSquare(49, 14, 0)
vehicleBody.vehicleContainer = { id = "clearance-test-car" }
local nearPassable, nearCost = passableEdge(vehicleNearFrom, vehicleNear, 1, { actor = mover })
local farPassable, farCost = passableEdge(vehicleFarFrom, vehicleFar, 1, { actor = mover })
local footprintPassable = passableEdge(vehicleNear, vehicleBody, 1, { actor = mover })
check(nearPassable and farPassable and nearCost > farCost and not footprintPassable,
    "parked-car footprint is blocked while adjacent path edges carry bounded clearance cost")
vehicleBody.vehicleContainer = nil

occupiedGoal.moving = {}
blockedGoal.solid = nil
registry[mover.id] = nil
registry[occupant.id] = nil
end

do
-- review 3.3: the A* open set is a binary min-heap. It must drain in exact
-- (f, h, familiarity, seq) order. Familiarity may settle an exact priority tie,
-- but cannot lower a path's real G cost.
local heapPush = SurvivorCompanion.Navigation._heapPushForTests
local heapPop = SurvivorCompanion.Navigation._heapPopForTests
local heap = {}
for _, entry in ipairs({
    { key = "a", f = 5, h = 2, seq = 1 },
    { key = "b", f = 3, h = 9, seq = 2 },
    { key = "c", f = 3, h = 1, familiarity = 1, seq = 3 },
    { key = "d", f = 3, h = 1, seq = 0 },
    { key = "e", f = 5, h = 2, seq = 4 },
    { key = "f", f = 1, h = 7, seq = 5 },
    { key = "g", f = 5, h = 1, seq = 6 },
}) do heapPush(heap, entry) end
local drained = {}
while true do
    local top = heapPop(heap)
    if top == nil then break end
    drained[#drained + 1] = top.key
end
local expected = { "f", "c", "d", "b", "g", "a", "e" }
local ordered = #drained == #expected
for index = 1, #expected do if drained[index] ~= expected[index] then ordered = false end end
check(ordered, "the A* open-set heap drains in exact cost, heuristic, familiarity and sequence order")
check(heapPop({}) == nil, "popping an empty heap returns nil")

-- End-to-end: the heap search still produces optimal, contiguous, deterministic
-- paths, and resolves a forced straight route to its unique optimal path.
local findPath = SurvivorCompanion.Navigation.findPath
local openSource = cell:getGridSquare(50, 0, 0)
local openGoalSquare = cell:getGridSquare(53, 2, 0)
local pathA = findPath(openSource, openGoalSquare)
check(pathA ~= nil and #pathA == 4 and pathA[1] == openSource and pathA[#pathA] == openGoalSquare,
    "open-field heap search returns an optimal octile path with correct endpoints")
local contiguous, usedDiagonal = true, false
for index = 2, #pathA do
    local dx = math.abs(pathA[index]:getX() - pathA[index - 1]:getX())
    local dy = math.abs(pathA[index]:getY() - pathA[index - 1]:getY())
    if dx > 1 or dy > 1 or dx + dy == 0 then
        contiguous = false
    end
    if dx == 1 and dy == 1 then usedDiagonal = true end
end
check(contiguous and usedDiagonal,
    "the heap search uses safe diagonal steps instead of a four-direction zig-zag")
local pathB = findPath(openSource, openGoalSquare)
local deterministic = pathB ~= nil and #pathA == #pathB
for index = 1, #pathA do if pathA[index] ~= pathB[index] then deterministic = false end end
check(deterministic, "the heap search is deterministic across repeated calls")

local corridor = findPath(cell:getGridSquare(50, 5, 0), cell:getGridSquare(52, 5, 0))
check(corridor ~= nil and #corridor == 3
        and corridor[2]:getX() == 51 and corridor[2]:getY() == 5,
    "a forced straight shortest route resolves to its unique optimal path")

do
    local utility = SurvivorCompanion.GameplayUtil
    local passable = SurvivorCompanion.Navigation._passableEdgeForTests
    local source = cell:getGridSquare(50, 0, 0)
    local goal = cell:getGridSquare(54, 0, 0)
    local rememberedDetour = {
        source,
        cell:getGridSquare(51, -1, 0),
        cell:getGridSquare(52, -1, 0),
        cell:getGridSquare(53, -1, 0),
        goal,
    }
    local memory = {}
    for index = 2, #rememberedDetour do
        local from, to = rememberedDetour[index - 1], rememberedDetour[index]
        memory[utility.squareKey(from) .. ">" .. utility.squareKey(to)] = {
            success = true, object = nil, objectState = "none", expires = clock + 100000,
        }
    end
    local ordinaryPassable, ordinaryCost = passable(
        source, rememberedDetour[2], 1, { now = clock })
    local memoryPassable, rememberedCost, memoryRejection, memoryObject, familiarity = passable(
        source, rememberedDetour[2], 1, { routeMemory = memory, now = clock })

    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 },
    }
    local function dijkstraCost()
        local distance = { [utility.squareKey(source)] = 0 }
        local open, closed = { source }, {}
        while #open > 0 do
            local bestIndex, bestCost = 1, math.huge
            for index, square in ipairs(open) do
                local value = distance[utility.squareKey(square)] or math.huge
                if value < bestCost then bestIndex, bestCost = index, value end
            end
            local current = table.remove(open, bestIndex)
            local currentKey = utility.squareKey(current)
            if current == goal then return bestCost end
            if not closed[currentKey] then
                closed[currentKey] = true
                for _, direction in ipairs(directions) do
                    local x, y = current:getX() + direction[1], current:getY() + direction[2]
                    if x >= 50 and x <= 54 and y >= -2 and y <= 2 then
                        local nextSquare = cell:getGridSquare(x, y, 0)
                        local nextKey = utility.squareKey(nextSquare)
                        local okay, cost = passable(current, nextSquare, 1, { now = clock })
                        local candidate = bestCost + (okay and cost or math.huge)
                        if not closed[nextKey] and candidate < (distance[nextKey] or math.huge) then
                            distance[nextKey] = candidate
                            open[#open + 1] = nextSquare
                        end
                    end
                end
            end
        end
        return math.huge
    end
    local savedBonus = SurvivorCompanion.Config.values.navigationRouteMemorySuccessBonus
    SurvivorCompanion.Config.values.navigationRouteMemorySuccessBonus = 2
    local rememberedPath = findPath(source, goal, {
        routeMemory = memory, now = clock, nodeBudget = 220,
    })
    SurvivorCompanion.Config.values.navigationRouteMemorySuccessBonus = savedBonus
    local aStarCost = 0
    for index = 2, #(rememberedPath or {}) do
        local okay, cost = passable(rememberedPath[index - 1], rememberedPath[index], 1,
            { now = clock })
        aStarCost = aStarCost + (okay and cost or math.huge)
    end
    local referenceCost = dijkstraCost()
    check(ordinaryPassable and memoryPassable and rememberedCost == ordinaryCost
            and type(familiarity) == "number" and familiarity > 0
            and rememberedPath ~= nil and math.abs(aStarCost - referenceCost) < 0.0001,
        "successful route memory is a cost-neutral tie-breaker and A-star matches Dijkstra's shortest cost: "
            .. tostring(ordinaryPassable) .. "/" .. tostring(memoryPassable) .. "/"
            .. tostring(ordinaryCost) .. "/" .. tostring(rememberedCost) .. "/"
            .. tostring(familiarity) .. "/" .. tostring(rememberedPath ~= nil) .. "/"
            .. tostring(aStarCost) .. "/" .. tostring(referenceCost))
end

local walledGoal = cell:getGridSquare(48, 20, 0)
cell:getGridSquare(47, 20, 0).solid = true
cell:getGridSquare(49, 20, 0).solid = true
cell:getGridSquare(48, 19, 0).solid = true
cell:getGridSquare(48, 21, 0).solid = true
check(findPath(cell:getGridSquare(45, 20, 0), walledGoal) == nil,
    "a fully walled-off goal is unreachable and the heap search fails cleanly (no crash)")
cell:getGridSquare(47, 20, 0).solid = nil
cell:getGridSquare(49, 20, 0).solid = nil
cell:getGridSquare(48, 19, 0).solid = nil
cell:getGridSquare(48, 21, 0).solid = nil
end

do
-- review 3.5: a stealth search scores against a small refreshable overlay, not the
-- frozen request snapshot, so a threat that dies or leaves during a long
-- multi-frame search is pruned and stops bending the route.
local buildOverlay = SurvivorCompanion.Navigation._buildStealthOverlayForTests
local refreshOverlay = SurvivorCompanion.Navigation._refreshStealthOverlayForTests
local stealthPenalty = SurvivorCompanion.Navigation._stealthThreatPenaltyForTests
local scoreSquare = cell:getGridSquare(50, 0, 0)
local nearThreat = actor("sc-stealth-near", 51, 0, {})
local farThreat = actor("sc-stealth-far", 50, 30, {})
local overlay = buildOverlay({ threats = { { actor = nearThreat }, { actor = farThreat } } })
check(#overlay.threats == 2, "the stealth overlay copies the snapshot's threat list")
local penaltyBefore = stealthPenalty(scoreSquare, overlay)
check(penaltyBefore > 0, "a live nearby threat contributes a stealth penalty")

nearThreat.dead = true
local pruned = refreshOverlay(overlay, 100000)
check(pruned == true and #overlay.threats == 1 and overlay.threats[1].actor == farThreat,
    "refreshing the overlay drops a threat whose actor died mid-search")
check(stealthPenalty(scoreSquare, overlay) < penaltyBefore,
    "the pruned threat no longer bends the stealth route cost")

farThreat.dead = true
check(refreshOverlay(overlay, 100100) == false and #overlay.threats == 1,
    "an overlay refresh inside the throttle window does not re-prune")
check(refreshOverlay(overlay, 101000) == true and #overlay.threats == 0,
    "past the throttle window the overlay prunes newly departed threats")

registry[nearThreat.id] = nil
registry[farThreat.id] = nil
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
        and SurvivorCompanion.GameplayUtil.distance(driftingState.pathGoalSquare,
            cell:getGridSquare(-2, 8, 0))
            < SurvivorCompanion.Navigation._goalResetDistanceForTests(
                { followRecovery = true })
        and (driftingState.routeRepairCount or 0) >= 1,
    "each adjacent follow-goal shift repairs the current route instead of walking a stale endpoint")
SurvivorCompanion.Navigation.reset(driftingGoalActor)
registry[driftingGoalActor.id] = nil
end

do
    local doorwayArrival = SurvivorCompanion.Navigation._nativeLeaseArrivalForTests
    check(type(doorwayArrival) == "function",
        "navigation exposes the continuous doorway-arrival seam")
    local doorwayActor = actor("sc-doorway-clearance", 1, 10, {})
    local fromSquare = cell:getGridSquare(0, 10, 0)
    local toSquare = cell:getGridSquare(1, 10, 0)
    local lease = {
        targets = { toSquare }, fromSquare = fromSquare, toSquare = toSquare,
        affordance = "door",
    }
    doorwayActor.worldX, doorwayActor.worldY = 1.08, 10.5
    check(doorwayArrival(doorwayActor, lease) == nil,
        "entering the destination tile does not finish a door path while the collision capsule is still in the leaf")
    doorwayActor.worldX = 1.5
    check(doorwayArrival(doorwayActor, lease) == toSquare,
        "a door path finishes after continuous world position clears the doorway")
    for index = #doorwayActor.square.moving, 1, -1 do
        if doorwayActor.square.moving[index] == doorwayActor then
            table.remove(doorwayActor.square.moving, index)
        end
    end
end

do
    -- A moving (follow) target must re-plan its committed native path on a much
    -- smaller goal drift than a static goal, so a following companion turns with
    -- the leader instead of running its stale straight path into a wall. A native
    -- lease carries its own movingTarget flag; a request intent is moving when it
    -- is a follow/regroup (followRecovery or a bound player).
    local resetDistance = SurvivorCompanion.Navigation._goalResetDistanceForTests
    local followReset = resetDistance({ followRecovery = true })
    local leaseReset = resetDistance({ movingTarget = true })
    local staticReset = resetDistance({ action = "move" })
    check(followReset < staticReset and leaseReset < staticReset
            and followReset <= 1.5 and staticReset >= 3.0,
        "a moving follow target re-plans on a tighter goal drift than a static goal")
end

do
    -- Replanning a moving goal must cancel the engine's old PathFindBehavior2,
    -- not merely forget the Lua lease. Otherwise that native path keeps walking
    -- straight toward its stale endpoint while the new route search is pending.
    local maintainLease = SurvivorCompanion.Navigation._maintainNativeLeaseForTests
    check(type(maintainLease) == "function",
        "navigation exposes the native-lease maintenance seam")
    local leaseActor = actor("sc-native-replan-stop", -8, 9, {})
    local oldGoal = cell:getGridSquare(-5, 9, 0)
    local newGoal = cell:getGridSquare(-2, 9, 0)
    local leaseState = {
        nativeLease = {
            ultimateGoal = oldGoal,
            ultimateGoalKey = SurvivorCompanion.GameplayUtil.squareKey(oldGoal),
            movingTarget = true,
            startedAt = 1000,
            expires = 5000,
            targets = { oldGoal },
        },
    }
    local previousNativeActions = SurvivorCompanion.NativeActions
    local stopped = 0
    local stopOptions
    SurvivorCompanion.NativeActions = {
        stopDirect = function(value, options)
            check(value == leaseActor, "native replan stops the actor that owns the stale lease")
            stopped = stopped + 1
            stopOptions = options
            return true
        end,
    }
    local leaseResult, leaseReason = maintainLease(leaseActor, leaseState, newGoal, 2000)
    SurvivorCompanion.NativeActions = previousNativeActions
    check(leaseResult == "cancelled" and leaseReason == "native_goal_changed"
            and leaseState.nativeLease == nil and stopped == 1
            and type(stopOptions) == "table" and stopOptions.preservePosture == true,
        "moving-goal replanning stops and releases the stale native path before searching again")
end

(function()
    local maintainLease = SurvivorCompanion.Navigation._maintainNativeLeaseForTests
    local stalledActor = actor("sc-native-stall", -8, 11, {})
    local stalledGoal = cell:getGridSquare(-4, 11, 0)
    local stalledState = {
        nativeLease = {
            ultimateGoal = stalledGoal,
            ultimateGoalKey = SurvivorCompanion.GameplayUtil.squareKey(stalledGoal),
            fromSquare = stalledActor.square,
            toSquare = stalledGoal,
            targets = { stalledGoal },
            startedAt = 0,
            expires = 10000,
            positionProgressAt = 0,
            progressSquareKey = SurvivorCompanion.GameplayUtil.squareKey(stalledActor.square),
            lastWorldX = stalledActor:getX(),
            lastWorldY = stalledActor:getY(),
            lastWorldZ = stalledActor:getZ(),
            lastGoalDistance = SurvivorCompanion.GameplayUtil.distance(stalledActor, stalledGoal),
            leaseMs = 6500,
        },
    }
    local previousNativeActions = SurvivorCompanion.NativeActions
    local stopped = 0
    SurvivorCompanion.NativeActions = {
        pathTelemetry = function()
            return { available = true, active = true, shouldBeMoving = true }
        end,
        stopDirect = function() stopped = stopped + 1 return true end,
    }
    local result, reason = maintainLease(stalledActor, stalledState, stalledGoal, 2000)
    SurvivorCompanion.NativeActions = previousNativeActions
    check(result == "failed" and reason == "native_path_stalled"
            and stopped == 1 and stalledState.nativeLease == nil,
        "native active telemetry cannot hide a path with no world, tile, goal, or next-node progress")
end)()

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
        and failedState.blockedEdges[failedKey].evidenceClass == "unknown"
        and failedState.blockedSquares[
            SurvivorCompanion.GameplayUtil.squareKey(cell:getGridSquare(-6, -7, 0))] == nil
        and failedState.routeMemory[failedKey]
        and failedState.routeMemory[failedKey].success == false
        and failedState.lastBlocker.type == "unknown",
    "unknown collision evidence blacklists only its exact short-lived edge")
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
        and vehicleState.lastBlocker.evidenceClass == "dynamic_square"
        and vehicleState.lastBlocker.recoveryResult == "direct_replan",
    "vehicle collision evidence selects dedicated vehicle recovery diagnostics")
SurvivorCompanion.Navigation.reset(vehicleActor)
registry[vehicleActor.id] = nil
end

do
local vehicleFootprint = cell:getGridSquare(-6, 4, 0)
vehicleFootprint.vehicleContainer = { id = "parked-car" }
local vehicleRoute = SurvivorCompanion.Navigation.findPath(
    cell:getGridSquare(-7, 4, 0), cell:getGridSquare(-5, 4, 0))
local crossedVehicle = false
for _, routeSquare in ipairs(vehicleRoute or {}) do
    if routeSquare == vehicleFootprint then crossedVehicle = true break end
end
check(vehicleRoute ~= nil and crossedVehicle == false,
    "Lua path search routes around a parked vehicle footprint before collision")
vehicleFootprint.vehicleContainer = nil
end

do
local steeringActor = actor("sc-combat-micro-steer", 52, 10, {})
local steeringTarget = zombie(54, 10, {})
function steeringActor:isCompanionMovementClear(toX, toY, z)
    return math.abs(toY - self:getY()) > 0.05
end
local firstX, firstY, firstSteered = SurvivorCompanion.Navigation.combatVector(
    steeringActor, steeringTarget, "approach")
local secondX, secondY, secondSteered = SurvivorCompanion.Navigation.combatVector(
    steeringActor, steeringTarget, "approach")
check(firstSteered and secondSteered and math.abs(firstY) > 0.1
        and firstX == secondX and firstY == secondY,
    "combat micro-positioning chooses a stable clear side when the direct approach is blocked")
for index = #steeringTarget.square.moving, 1, -1 do
    if steeringTarget.square.moving[index] == steeringTarget then
        table.remove(steeringTarget.square.moving, index)
    end
end
for index = #steeringActor.square.moving, 1, -1 do
    if steeringActor.square.moving[index] == steeringActor then
        table.remove(steeringActor.square.moving, index)
    end
end
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
local climbStateActor = actor("sc-climb-state-blocker", -7, -1, {})
registry[climbStateActor.id] = climbStateActor
climbStateActor.climbing = true
local previousClimbNativeActions = SurvivorCompanion.NativeActions
SurvivorCompanion.NativeActions = {
    cancelStuckClimb = function(value)
        return value:cancelCompanionStuckClimb(), "stuck_climb_cancelled"
    end,
}
SurvivorCompanion.Config.values.navigationActorStateGraceMs = 100
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = 100
check(SurvivorCompanion.Navigation.request(
        climbStateActor, cell:getGridSquare(-5, -1, 0), "walk", {})
        and SurvivorCompanion.Navigation.peek(climbStateActor).lastBlocker.actorState
            == "climbing",
    "a fresh climb animation waits through its native grace period")
clock = clock + 2001
local staleClimbAccepted, staleClimbReason = SurvivorCompanion.Navigation.request(
    climbStateActor, cell:getGridSquare(-5, -1, 0), "walk", {})
check(staleClimbAccepted
        and climbStateActor.climbing == false
        and SurvivorCompanion.Navigation.peek(climbStateActor).lastBlocker.recoveryResult
            == "cancelled_stuck_climb",
    "a companion stuck climbing past the timeout leaves the native climb state and reroutes: "
        .. tostring(staleClimbAccepted) .. "/" .. tostring(staleClimbReason)
        .. "/" .. tostring(climbStateActor.climbing) .. "/"
        .. tostring(SurvivorCompanion.Navigation.peek(climbStateActor).lastBlocker
            and SurvivorCompanion.Navigation.peek(climbStateActor).lastBlocker.recoveryResult))
clock = clock + 1
local resumedClimb, resumedClimbReason = SurvivorCompanion.Navigation.request(
    climbStateActor, cell:getGridSquare(-5, -1, 0), "walk", {})
check(resumedClimb and resumedClimbReason ~= "waiting_climbing",
    "a cancelled stale climb cannot re-enter the actor-state wait loop")
SurvivorCompanion.Config.values.navigationActorStateGraceMs = nil
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = nil
SurvivorCompanion.Navigation.reset(climbStateActor)
SurvivorCompanion.NativeActions = previousClimbNativeActions
registry[climbStateActor.id] = nil
end

do
local rejectedClimbActor = actor("sc-climb-cancel-rejected", -7, 0, {})
registry[rejectedClimbActor.id] = rejectedClimbActor
rejectedClimbActor.climbing = true
rejectedClimbActor.rejectClimbCancel = true
local previousRejectedClimbNativeActions = SurvivorCompanion.NativeActions
local previousRecoveryAttempts = SurvivorCompanion.Config.values.navigationRecoveryAttempts
SurvivorCompanion.NativeActions = {
    cancelStuckClimb = function(value)
        return value:cancelCompanionStuckClimb(), "native_climb_cancel_rejected"
    end,
}
SurvivorCompanion.Config.values.navigationActorStateGraceMs = 1
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = 1
SurvivorCompanion.Config.values.navigationRecoveryAttempts = 2
SurvivorCompanion.Navigation.request(
    rejectedClimbActor, cell:getGridSquare(-5, 0, 0), "walk", {})
local rejectedReason
for _ = 1, 2 do
    clock = clock + 2
    local accepted
    accepted, rejectedReason = SurvivorCompanion.Navigation.request(
        rejectedClimbActor, cell:getGridSquare(-5, 0, 0), "walk", {})
end
check(rejectedReason == "recovery_exhausted:actor_state"
        and SurvivorCompanion.Navigation.peek(rejectedClimbActor).terminalGoalKey ~= nil,
    "a native climb that rejects cancellation enters bounded terminal recovery")
SurvivorCompanion.Config.values.navigationActorStateGraceMs = nil
SurvivorCompanion.Config.values.navigationActorStateTimeoutMs = nil
SurvivorCompanion.Config.values.navigationRecoveryAttempts = previousRecoveryAttempts
SurvivorCompanion.Navigation.reset(rejectedClimbActor)
SurvivorCompanion.NativeActions = previousRejectedClimbNativeActions
registry[rejectedClimbActor.id] = nil
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

do
local upperGoal = cell:getGridSquare(11, 5, 1)
local upperFloorActor = actor("sc-upper-floor", 7, 5, {})
registry[upperFloorActor.id] = upperFloorActor
local upperAccepted, upperReason = SurvivorCompanion.Navigation.request(
    upperFloorActor, upperGoal, "jog", {
        action = "follow_formation",
        movingTarget = true,
        snapshot = { threats = {}, allies = {}, player = { available = false } },
    })
local upperState = SurvivorCompanion.Navigation.peek(upperFloorActor)
check(upperAccepted and upperReason == "multi_level_path"
        and upperFloorActor.lastIntent and upperFloorActor.lastIntent.enginePath == true
        and upperFloorActor.lastIntent.multiLevelPath == true
        and upperFloorActor.lastIntent.nextSquare == upperGoal
        and upperState.path == nil and upperState.pathSearch == nil
        and upperState.nativeLease and upperState.nativeLease.affordance == "multi_level"
        and upperState.nativeLease.reason == "multi_level_goal",
    "an upper-floor goal bypasses synthetic Lua stair edges and gives the complete 3D route to PathFindBehavior2")
check(upperState.nativeLease.expires - clock == 30000,
    "a multi-floor route has a progress-refreshable lease long enough to reach a distant staircase")
local previousStairNativeActions = SurvivorCompanion.NativeActions
SurvivorCompanion.NativeActions = {
    pathTelemetry = function()
        return { available = true, active = true, shouldBeMoving = true,
            movingUsingPathFind = true, hasStartedMoving = true }
    end,
    stopDirect = function() return true end,
}
upperFloorActor.square = cell:getGridSquare(8, 5, 0)
clock = clock + 29900
local leaseState, leaseStatus = SurvivorCompanion.Navigation._maintainNativeLeaseForTests(
    upperFloorActor, upperState, upperGoal, clock)
check(leaseState == "active" and leaseStatus == "native_path_owned"
        and upperState.nativeLease.expires - clock == 30000,
    "real tile progress renews a long multi-floor route instead of timing it out halfway to the stairs")
SurvivorCompanion.NativeActions = previousStairNativeActions

local basementGoal = cell:getGridSquare(11, 6, -1)
local basementActor = actor("sc-basement", 7, 6, {})
registry[basementActor.id] = basementActor
local basementAccepted, basementReason = SurvivorCompanion.Navigation.request(
    basementActor, basementGoal, "walk", {
        action = "move_to",
        snapshot = { threats = {}, allies = {}, player = { available = false } },
    })
check(basementAccepted and basementReason == "multi_level_path"
        and basementActor.lastIntent.enginePath == true
        and basementActor.lastIntent.targetSquare == basementGoal
        and SurvivorCompanion.Navigation.peek(basementActor).nativeLease.affordance == "multi_level",
    "a loaded basement destination uses the same native 3D path contract as an upper floor or attic")

local ropeSquare = cell:getGridSquare(9, 7, 0)
ropeSquare.sheetRope = {}
local ropeActor = actor("sc-sheet-rope", 9, 7, {})
local ropeGoal = cell:getGridSquare(9, 7, 1)
registry[ropeActor.id] = ropeActor
local ropeAccepted, ropeReason = SurvivorCompanion.Navigation.request(
    ropeActor, ropeGoal, "walk", { action = "move_to" })
check(ropeAccepted and ropeReason == "sheet_rope_climb"
        and ropeActor.lastIntent.action == "climb_sheet_rope"
        and ropeActor.lastIntent.nativeAffordance == "sheet_rope",
    "a companion already at a sheet rope uses the stock player climb transition")
SurvivorCompanion.Navigation.reset(ropeActor)
registry[ropeActor.id] = nil
ropeSquare.sheetRope = nil
SurvivorCompanion.Navigation.reset(upperFloorActor)
SurvivorCompanion.Navigation.reset(basementActor)
registry[upperFloorActor.id], registry[basementActor.id] = nil, nil
end

(function()
    local stairFrom = cell:getGridSquare(20, 20, 0)
    local stairNext = cell:getGridSquare(21, 20, 0)
    local stairGoal = cell:getGridSquare(21, 20, 1)
    function stairFrom:HasStairs() return true end
    function stairNext:HasStairs() return true end
    local point = actor("sc-native-stair-point", 20, 20, {})
    local rear = actor("sc-native-stair-rear", 20, 20, {})
    registry[point.id], registry[rear.id] = point, rear
    local participants = {
        { actor = point, cqbRole = "point" },
        { actor = rear, cqbRole = "rear_guard" },
    }
    local cohort = "party:native-stair-admission"
    check(SurvivorCompanion.Navigation.request(point, stairGoal, "walk", {
            action = "follow_formation", cohortKey = cohort,
            cqbRole = "point", groupParticipants = participants,
        }), "point member starts a native multi-floor route")
    check(SurvivorCompanion.Navigation.request(rear, stairGoal, "walk", {
            action = "follow_formation", cohortKey = cohort,
            cqbRole = "rear_guard", groupParticipants = participants,
        }), "rear guard starts a native multi-floor route")
    local pointState = SurvivorCompanion.Navigation.peek(point)
    local rearState = SurvivorCompanion.Navigation.peek(rear)
    local previousNativeActions = SurvivorCompanion.NativeActions
    SurvivorCompanion.NativeActions = {
        pathTelemetry = function()
            return { available = true, active = true, shouldBeMoving = true,
                pathNextIsSet = true, pathNextX = 21, pathNextY = 20 }
        end,
        stopDirect = function() return true end,
    }
    local pointLease = SurvivorCompanion.Navigation._maintainNativeLeaseForTests(
        point, pointState, stairGoal, clock + 10)
    local rearLease, rearStatus =
        SurvivorCompanion.Navigation._maintainNativeLeaseForTests(
            rear, rearState, stairGoal, clock + 11)
    SurvivorCompanion.NativeActions = previousNativeActions
    check(pointLease == "active" and rearLease == "active"
            and rearStatus == "holding_group_passage"
            and rearState.nativeLease and rearState.nativeLease.nativePaused == true,
        "native next-edge telemetry applies single-file stair admission before crossing")
    SurvivorCompanion.Navigation.reset(point)
    SurvivorCompanion.Navigation.reset(rear)
    registry[point.id], registry[rear.id] = nil, nil
end)()

-- Same-floor travel that is already at a staircase retains the cautious choke
-- behavior; only discovery of the oriented cross-floor route is delegated.
local stairSource = squares[squareKey(7, 7, 0)]
local stairNext = cell:getGridSquare(8, 7, 0)
local stairGoal = cell:getGridSquare(9, 7, 0)
function stairSource:HasStairs() return true end
function stairNext:HasStairs() return true end
local stairActor = actor("sc-stair-choke", 7, 7, {})
registry[stairActor.id] = stairActor
local stairHeld, stairHeldReason = SurvivorCompanion.Navigation.request(
    stairActor, stairGoal, "jog", {
        snapshot = { threats = {}, allies = {}, player = { available = false } },
    })
check(stairHeld and stairHeldReason == "checking_stair_landing"
        and stairActor.lastIntent and stairActor.lastIntent.action == "ready_weapon",
    "an actor already entering a staircase still checks the landing before committing")
clock = clock + 500
check(SurvivorCompanion.Navigation.request(stairActor, stairGoal, "jog", {
        snapshot = { threats = {}, allies = {}, player = { available = false } },
    }) and stairActor.lastIntent.tacticalStair and stairActor.lastIntent.mode == "walk",
    "the local stair choke is crossed at a controlled walk under native steering")
SurvivorCompanion.Navigation.reset(stairActor)
registry[stairActor.id] = nil

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

-- A lower-priority decision pulse must not clear an owning route's threshold
-- timer before its eventual movement dispatch is rejected.  This is the exact
-- interleaving exercised by the live harness: the owner pauses at a doorway
-- while the ordinary follow/stay scheduler also asks Navigation for a route.
SurvivorCompanion.Navigation.reset(entryActor)
local ownedEntryClock = clock
local entryOwner = assert(SurvivorCompanion.ActionSupervisor.begin(entryActor, {
    owner = "test", action = "room_entry_owner",
    priority = SurvivorCompanion.ActionSupervisor.Priority.EXTERNAL,
    phase = "approaching", allowedMovementPhases = { approaching = true },
}))
local ownedEntryHeld, ownedEntryReason = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", {
        action = "room_entry_owner", snapshot = { allies = {} },
        supervisorToken = entryOwner,
    })
local ownedEntryState = SurvivorCompanion.Navigation.peek(entryActor)
local ownedEntryKey = ownedEntryState and ownedEntryState.roomEntryKey
local ownedEntryDeadline = ownedEntryState and ownedEntryState.roomEntryObserveUntil
local competingEntryMove, competingEntryReason = SurvivorCompanion.Navigation.request(
    entryActor, cell:getGridSquare(12, 0, 0), "walk", {
        action = "follow_formation", snapshot = { allies = {} },
    })
local protectedEntryState = SurvivorCompanion.Navigation.peek(entryActor)
check(ownedEntryHeld and ownedEntryReason == "checking_room_entry"
        and not competingEntryMove
        and string.find(tostring(competingEntryReason), "action_owned:", 1, true) ~= nil
        and protectedEntryState.roomEntryKey == ownedEntryKey
        and protectedEntryState.roomEntryObserveUntil == ownedEntryDeadline
        and protectedEntryState.roomEntrySweepPhase == 0,
    "a rejected competing route cannot restart an owned room-entry sweep")
clock = clock + 500
local ownedLeftChecked, ownedLeftReason = SurvivorCompanion.Navigation.request(
    entryActor, entryGoal, "walk", {
        action = "room_entry_owner", snapshot = { allies = {} },
        supervisorToken = entryOwner,
    })
check(ownedLeftChecked and ownedLeftReason == "checking_room_entry_left",
    "the owned room-entry sweep advances after a rejected scheduler interleave")
SurvivorCompanion.ActionSupervisor.cancel(entryActor, "fixture_done", nil, true)
clock = ownedEntryClock
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
check(SurvivorCompanion.Commands.issue(formationLeft.id, "set_group", "alpha", positioningLeader)
    and SurvivorCompanion.Commands.issue(formationRight.id, "set_group", "alpha", positioningLeader),
    "formation fixtures enter one named fireteam")
local formationLeftCommands = SurvivorCompanion.Commands.peek(formationLeft)
local formationRightCommands = SurvivorCompanion.Commands.peek(formationRight)
formationLeftCommands.personalityProfile = { courage = 95, caution = 25, practicality = 55 }
formationRightCommands.personalityProfile = { courage = 35, caution = 95, practicality = 65 }
local formationSnapshot = { threats = {}, allies = {}, player = { actor = positioningLeader, danger = 0 } }
local leftTarget = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, formationLeftCommands, formationSnapshot)
local rightTarget = SurvivorCompanion.Positioning.formationTarget(
    formationRight, positioningLeader, formationRightCommands, formationSnapshot)
check(leftTarget and leftTarget.x == 19 and leftTarget.y == 19
    and rightTarget and rightTarget.x == 17 and rightTarget.y == 20
    and SurvivorCompanion.Positioning.debug(formationLeft).cqbRole == "point"
    and SurvivorCompanion.Positioning.debug(formationRight).cqbRole == "rear_guard",
    "stable CQB roles place point and rear guard behind an east-facing player")

local formationAssault = actor("002-formation-assault", 15, 19, {})
local formationRanged = actor("003-formation-ranged", 15, 22, {})
formationRanged.primary = item("Base.CQBTestRifle", "Weapon", { ranged = true, ammo = 8 })
registry[formationAssault.id], registry[formationRanged.id] = formationAssault, formationRanged
check(SurvivorCompanion.Commands.issue(formationAssault.id, "follow", nil, positioningLeader)
    and SurvivorCompanion.Commands.issue(formationRanged.id, "follow", nil, positioningLeader),
    "additional CQB fixtures join the same fireteam")
check(SurvivorCompanion.Commands.issue(formationAssault.id, "set_group", "alpha", positioningLeader)
    and SurvivorCompanion.Commands.issue(formationRanged.id, "set_group", "alpha", positioningLeader),
    "additional CQB fixtures use the named fireteam")
local formationAssaultCommands = SurvivorCompanion.Commands.peek(formationAssault)
local formationRangedCommands = SurvivorCompanion.Commands.peek(formationRanged)
formationAssaultCommands.personalityProfile = { courage = 70, caution = 35, practicality = 55 }
formationRangedCommands.personalityProfile = { courage = 55, caution = 50, practicality = 70 }
formationRangedCommands.combatDoctrine = "ranged_support"
formationRangedCommands.weaponPriority = "firearm"
clock = clock + 300
local _, pointContext = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, formationLeftCommands, formationSnapshot)
local _, assaultContext = SurvivorCompanion.Positioning.formationTarget(
    formationAssault, positioningLeader, formationAssaultCommands, formationSnapshot)
local _, rangedContext = SurvivorCompanion.Positioning.formationTarget(
    formationRanged, positioningLeader, formationRangedCommands, formationSnapshot)
local rearTarget, rearContext = SurvivorCompanion.Positioning.formationTarget(
    formationRight, positioningLeader, formationRightCommands, formationSnapshot)
check(pointContext.cqbRole == "point" and pointContext.columnIndex == 1
        and rearContext.cqbRole == "rear_guard" and rearContext.columnIndex == 2
        and assaultContext.cqbRole == "assault" and assaultContext.columnIndex == 3
        and rangedContext.cqbRole == "ranged_support" and rangedContext.columnIndex == 4
        and rearContext.fireteamSize == 4
        and pointContext.participants[1].actor == formationLeft
        and pointContext.participants[2].actor == formationRight,
    "fireteam preserves existing roles while a changed roster settles"
        .. " got=" .. tostring(pointContext.cqbRole) .. ":" .. tostring(pointContext.columnIndex)
        .. "," .. tostring(assaultContext.cqbRole) .. ":" .. tostring(assaultContext.columnIndex)
        .. "," .. tostring(rangedContext.cqbRole) .. ":" .. tostring(rangedContext.columnIndex)
        .. "," .. tostring(rearContext.cqbRole) .. ":" .. tostring(rearContext.columnIndex)
        .. " size=" .. tostring(rearContext.fireteamSize))

clock = clock + 2100
leftTarget, pointContext = SurvivorCompanion.Positioning.formationTarget(
    formationLeft, positioningLeader, formationLeftCommands, formationSnapshot)
_, assaultContext = SurvivorCompanion.Positioning.formationTarget(
    formationAssault, positioningLeader, formationAssaultCommands, formationSnapshot)
_, rangedContext = SurvivorCompanion.Positioning.formationTarget(
    formationRanged, positioningLeader, formationRangedCommands, formationSnapshot)
rearTarget, rearContext = SurvivorCompanion.Positioning.formationTarget(
    formationRight, positioningLeader, formationRightCommands, formationSnapshot)
check(pointContext.columnIndex == 1 and assaultContext.columnIndex == 2
        and rangedContext.columnIndex == 3 and rearContext.columnIndex == 4
        and pointContext.participants[1].actor == formationLeft
        and pointContext.participants[2].actor == formationAssault
        and pointContext.participants[3].actor == formationRanged
        and pointContext.participants[4].actor == formationRight,
    "settled fireteam reflows once into point, assault, ranged support, rear guard order")

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

local predictionLeader = actor("prediction-player", 30, 20, {
    className = "IsoPlayer", recruited = false, forwardX = 1, forwardY = 0,
})
predictionLeader.modData.SC_Recruited = false
local predictionFollower = actor("sc-prediction-follower", 26, 20, {})
registry[predictionFollower.id] = predictionFollower
SurvivorCompanion.Commands.issue(predictionFollower.id, "follow", nil, predictionLeader)
SurvivorCompanion.Positioning.formationTarget(predictionFollower, predictionLeader,
    SurvivorCompanion.Commands.peek(predictionFollower), formationSnapshot)
predictionLeader.moving = true
predictionLeader.worldX = predictionLeader:getX() + 0.6
clock = clock + 100
local predictedTarget = SurvivorCompanion.Positioning.formationTarget(
    predictionFollower, predictionLeader, SurvivorCompanion.Commands.peek(predictionFollower),
    { threats = {}, allies = {}, player = { actor = predictionLeader, danger = 0 } })
local predictionDebug = SurvivorCompanion.Positioning.debug(predictionFollower)
check(predictedTarget and predictionDebug.predictionDistance > 0
        and predictionDebug.predictionDistance
            <= (SurvivorCompanion.GameplayUtil.config("formationPredictionMaxDistance") or 1.25),
    "moving formation targets lead the player's smoothed motion by a bounded distance")
SurvivorCompanion.Positioning.reset(predictionFollower)
SurvivorCompanion.Commands.reset(predictionFollower)
registry[predictionFollower.id] = nil
for _, value in ipairs({ predictionFollower, predictionLeader }) do
    for index = #value.square.moving, 1, -1 do
        if value.square.moving[index] == value then
            table.remove(value.square.moving, index)
        end
    end
end

local trailLeader = actor("trail-player", 50, 24, {
    className = "IsoPlayer", recruited = false, forwardX = 1, forwardY = 0,
})
trailLeader.modData.SC_Recruited = false
local trailFollower = actor("000-trail-follower", 42, 24, {})
registry[trailFollower.id] = trailFollower
SurvivorCompanion.Commands.issue(trailFollower.id, "follow", nil, trailLeader)
local trailSnapshot = {
    threats = {}, allies = {}, player = { actor = trailLeader, danger = 0 },
}
trailLeader.square.losBlocked = true
local bootstrapTarget, bootstrapContext = SurvivorCompanion.Positioning.formationTarget(
    trailFollower, trailLeader,
    SurvivorCompanion.Commands.peek(trailFollower), trailSnapshot)
check(bootstrapTarget and bootstrapContext and bootstrapContext.mode == "bootstrap"
        and bootstrapTarget ~= trailLeader.square,
    "a wall-blocked follower bootstraps to a free leader-adjacent square after reload")
trailLeader.square.losBlocked = false
local trailTarget, trailContext
for x = 51, 53 do
    trailLeader.square = cell:getGridSquare(x, 24, 0)
    clock = clock + 120
    trailTarget, trailContext = SurvivorCompanion.Positioning.formationTarget(
        trailFollower, trailLeader, SurvivorCompanion.Commands.peek(trailFollower), trailSnapshot)
end
check(trailTarget and trailContext and trailContext.mode == "trail"
        and trailContext.trailRevision >= 4 and trailTarget.x < trailLeader.square.x
        and trailContext.columnIndex >= 1,
    "a distant follower uses the shared leader breadcrumb column instead of cutting toward a side slot")
SurvivorCompanion.Positioning.reset(trailFollower)
SurvivorCompanion.Commands.reset(trailFollower)
registry[trailFollower.id] = nil


local stickyLeader = actor("sticky-player", 40, 20, {
    className = "IsoPlayer", recruited = false, forwardX = 1, forwardY = 0,
})
stickyLeader.modData.SC_Recruited = false
local stickyFollower = actor("sc-sticky-follower", 35, 20, {})
registry[stickyFollower.id] = stickyFollower
SurvivorCompanion.Commands.issue(stickyFollower.id, "follow", nil, stickyLeader)
local stickySnapshot = {
    threats = {}, allies = {}, player = { actor = stickyLeader, danger = 0 },
}
local stickyFirst = SurvivorCompanion.Positioning.formationTarget(
    stickyFollower, stickyLeader, SurvivorCompanion.Commands.peek(stickyFollower), stickySnapshot)
stickyLeader.worldX = stickyLeader:getX() + 0.65
clock = clock + 100
local stickyNeighbour = SurvivorCompanion.Positioning.formationTarget(
    stickyFollower, stickyLeader, SurvivorCompanion.Commands.peek(stickyFollower), stickySnapshot)
stickyLeader.worldX = stickyLeader.worldX + 1.1
clock = clock + 100
local stickyMoved = SurvivorCompanion.Positioning.formationTarget(
    stickyFollower, stickyLeader, SurvivorCompanion.Commands.peek(stickyFollower), stickySnapshot)
check(stickyFirst and stickyNeighbour == stickyFirst and stickyMoved ~= stickyFirst,
    "formation target hysteresis ignores one neighbouring tile of jitter but follows a material leader move")
SurvivorCompanion.Positioning.reset(stickyFollower)
SurvivorCompanion.Commands.reset(stickyFollower)
registry[stickyFollower.id] = nil
for _, value in ipairs({ stickyFollower, stickyLeader }) do
    for index = #value.square.moving, 1, -1 do
        if value.square.moving[index] == value then table.remove(value.square.moving, index) end
    end
end

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

SurvivorCompanion.Config.values.rearGuardRefreshMs = 1
formationRight.square = rearTarget
formationRight.lastIntent = nil
formationRight.stopped = false
local rearGuardMovementCalls = formationRight.movementCalls or 0
local rearWaiting, rearWaitingReason = SurvivorCompanion.Positioning.updateHoldAwareness(
    formationRight, positioningLeader, formationSnapshot)
check(rearWaiting == nil and rearWaitingReason == "rear_guard_watch_not_due"
        and (formationRight.movementCalls or 0) == rearGuardMovementCalls,
    "rear guard watch is paced instead of issuing a facing intent every frame")
clock = clock + 2
local rearX, rearY, rearZ = formationRight:getX(), formationRight:getY(), formationRight:getZ()
check(SurvivorCompanion.Positioning.updateHoldAwareness(
        formationRight, positioningLeader, formationSnapshot)
    and formationRight.lastIntent.action == "rear_guard_watch"
    and formationRight.lastIntent.cqbRole == "rear_guard"
    and formationRight.lastIntent.stableFacing == true
    and formationRight.lastIntent.awarenessMovement == true
    and math.abs(formationRight.lastIntent.targetPosition.x - rearX) < 0.001
    and math.abs(formationRight.lastIntent.targetPosition.y - (rearY - 2)) < 0.001
    and formationRight.lastIntent.targetPosition.z == rearZ
    and formationRight.stopped == true,
    "rear guard stops and holds exact coverage opposite the fireteam heading")
local rearGuardWatchCalls = formationRight.movementCalls or 0
local rearPaced, rearPacedReason = SurvivorCompanion.Positioning.updateHoldAwareness(
    formationRight, positioningLeader, formationSnapshot)
check(rearPaced == nil and rearPacedReason == "rear_guard_watch_not_due"
        and (formationRight.movementCalls or 0) == rearGuardWatchCalls,
    "rear guard does not restart the native facing action between refresh pulses")
clock = clock + 2
local rearDanger, rearDangerReason = SurvivorCompanion.Positioning.updateHoldAwareness(
    formationRight, positioningLeader, { threatCount = 1, immediateCount = 1 })
check(rearDanger == nil and rearDangerReason == "danger_present"
        and (formationRight.movementCalls or 0) == rearGuardWatchCalls,
    "combat danger preempts passive rear-guard facing without consuming a movement action")
SurvivorCompanion.Config.values.rearGuardRefreshMs = nil

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

for _, value in ipairs({ formationLeft, formationRight, formationAssault, formationRanged,
        socialApproach, spaceActor, spaceBlocker,
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
(function()
    testDoor.locked = true
    local lockedEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, doorFrom, doorTo, {})
    local reachable = SurvivorCompanion.Topology.reachableEscapeSquares(
        fellow, doorFrom, { radius = 1, nodeBudget = 8 })
    local crossedLockedDoor = false
    for _, node in ipairs(reachable or {}) do
        if node.square == doorTo then crossedLockedDoor = true break end
    end
    local diagonal = SurvivorCompanion.Topology.classifyEdge(
        fellow, doorFrom, cell:getGridSquare(1, 3, 0), {})
    check(lockedEdge.traversable == false and lockedEdge.reason == "door_locked"
            and crossedLockedDoor == false and diagonal.reason == "diagonal_corner",
        "escape topology blocks locked doors and diagonal corner cutting")
    testDoor.locked = false
end)()
;(function()
    local seen = {}
    for _, obstacle in ipairs(SurvivorCompanion.Topology.OBSTACLE_CATALOG) do
        check(type(obstacle.id) == "string" and not seen[obstacle.id],
            "the pathing obstacle catalogue has stable unique identifiers")
        seen[obstacle.id] = true
    end
    check(SurvivorCompanion.Topology.obstacleTypeCount() == 38,
        "Build 42 pathing coverage catalogues all 38 collision conditions")

    local transparentFrom = cell:getGridSquare(20, 9, 0)
    local transparentTo = cell:getGridSquare(21, 9, 0)
    transparentTo.solidTrans = true
    local transparentEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, transparentFrom, transparentTo, {})
    check(transparentEdge.traversable == false
            and transparentEdge.reason == "square_blocked",
        "transparent-solid glass and mod tiles are rejected before native collision")
    transparentTo.solidTrans = nil

    local concreteFrom = cell:getGridSquare(22, 9, 0)
    local concreteTo = cell:getGridSquare(23, 9, 0)
    local concreteWindow = { canClimbThrough = function() return true end }
    function concreteFrom:getWindowTo(other)
        return other == concreteTo and concreteWindow or nil
    end
    local object, kind = SurvivorCompanion.Topology.barrierBetween(concreteFrom, concreteTo)
    local concreteEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, concreteFrom, concreteTo, {})
    check(object == concreteWindow and kind == "window"
            and concreteEdge.traversable == true and concreteEdge.requiresNative == true,
        "concrete window getters detect opened and modded windows after collision flags clear")

    local keyedActor = actor("sc-keyed-door", 0, 2, {
        inventory = inventory({ item("Base.Key1", "Key", { keyId = 4102 }) }),
    })
    function testDoor:getKeyId() return 4102 end
    testDoor.locked = true
    local keyedEdge = SurvivorCompanion.Topology.classifyEdge(
        keyedActor, doorFrom, doorTo, {})
    check(keyedEdge.traversable == true and keyedEdge.requiresNative == true,
        "a key-locked door is planned only when the companion carries its real key id")
    testDoor.locked = false
    testDoor.getKeyId = nil
    for index = #keyedActor.square.moving, 1, -1 do
        if keyedActor.square.moving[index] == keyedActor then
            table.remove(keyedActor.square.moving, index)
        end
    end

    local slopeFrom = cell:getGridSquare(24, 9, 0)
    local slopeTo = cell:getGridSquare(25, 9, 0)
    slopeTo.sloped = true
    local slopeEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, slopeFrom, slopeTo, {})
    local slopeAffordance = SurvivorCompanion.Navigation.edgeAffordance(slopeFrom, slopeTo)
    check(slopeEdge.traversable == true and slopeEdge.affordance == "slope"
            and slopeEdge.requiresNative == true
            and slopeAffordance and slopeAffordance.kind == "slope",
        "sloped surfaces retain a native transition through planning and execution")

    local hazardFrom = cell:getGridSquare(26, 9, 0)
    local waterTo = cell:getGridSquare(27, 9, 0)
    waterTo.flags = { water = true }
    local waterEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, {})
    check(waterEdge.traversable == false and waterEdge.reason == "water_terrain",
        "water is never accepted as ordinary foot terrain")
    waterTo.flags = nil
    waterTo.fire = {}
    local safeFireEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, {})
    local emergencyFireEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, { allowHazards = true })
    check(safeFireEdge.traversable == false and safeFireEdge.reason == "fire_hazard"
            and emergencyFireEdge.traversable == true and emergencyFireEdge.cost >= 81,
        "fire is excluded from normal routes and heavily penalized during emergency escape")
    waterTo.fire = nil
    local liveTrap = { __class = "IsoTrap" }
    waterTo.objects[#waterTo.objects + 1] = liveTrap
    local safeTrapEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, {})
    local emergencyTrapEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, { allowHazards = true })
    check(safeTrapEdge.traversable == false
            and safeTrapEdge.reason == "explosive_trap_hazard"
            and emergencyTrapEdge.traversable == true and emergencyTrapEdge.cost >= 61,
        "live traps are avoided normally and receive an emergency-only path penalty")
    table.remove(waterTo.objects)
    waterTo.brokenGlass = {}
    local glassEdge = SurvivorCompanion.Topology.classifyEdge(
        fellow, hazardFrom, waterTo, {})
    check(glassEdge.traversable == true and glassEdge.cost >= 9,
        "broken glass remains passable but costs enough for A-star to prefer a safe detour")
    waterTo.brokenGlass = nil

    local pushable = { __class = "IsoPushableObject" }
    waterTo.moving[#waterTo.moving + 1] = pushable
    local pushablePassable, _, pushableReason =
        SurvivorCompanion.Navigation._passableEdgeForTests(
            hazardFrom, waterTo, 1, { actor = fellow })
    check(pushablePassable == false and pushableReason == "pushable_object",
        "bins and other IsoPushableObjects are detoured instead of causing collision loops")
    table.remove(waterTo.moving)
end)()
;(function()
    local windowFrom = cell:getGridSquare(8, 7, 0)
    local windowTo = cell:getGridSquare(9, 7, 0)
    local activeActor = fellow
    local actorTrue = { canClimbThrough = function(_, value) return value == activeActor end }
    local actorFalse = { canClimbThrough = function(_, value) return value == nil end }
    local nilFallback = { canClimbThrough = function(_, value)
        if value ~= nil then error("actor overload unavailable") end
        return true
    end }
    local unavailable = {}
    check(SurvivorCompanion.Topology.canClimbThrough(actorTrue, activeActor) == true
            and SurvivorCompanion.Topology.canClimbThrough(actorFalse, activeActor) == false
            and SurvivorCompanion.Topology.canClimbThrough(nilFallback, activeActor) == true
            and SurvivorCompanion.Topology.canClimbThrough(unavailable, activeActor) == false,
        "climbability honors explicit actor answers, verified nil fallback, and fail-closed absence")

    function windowFrom:isWindowTo(other) return other == windowTo end
    function windowTo:isWindowTo(other) return other == windowFrom end
    function windowTo:getWindow(north) if north == false then return unavailable end end
    local unknownWindow = SurvivorCompanion.Topology.classifyEdge(
        activeActor, windowFrom, windowTo, {})
    check(unknownWindow.traversable == false
            and unknownWindow.reason == "window_climbability_unknown",
        "an intact window with no verified climbability is not traversable")

    function windowTo:getWindow(north) return nil end
    function windowTo:getWindowFrame(north) if north == false then return unavailable end end
    local unsupportedFrame = SurvivorCompanion.Topology.classifyEdge(
        activeActor, windowFrom, windowTo, {})
    local reachable = SurvivorCompanion.Topology.reachableEscapeSquares(
        activeActor, windowFrom, { radius = 1, nodeBudget = 8 })
    local crossedFrame = false
    for _, node in ipairs(reachable or {}) do
        if node.square == windowTo then crossedFrame = true break end
    end
    check(unsupportedFrame.traversable == false
            and unsupportedFrame.reason == "window_frame_climbability_unknown"
            and crossedFrame == false,
        "unsupported window frames are excluded from traversal and escape BFS")
end)()
do
    local angledDoorActor = actor("sc-door-angled", 0, 2, {})
    angledDoorActor.worldX, angledDoorActor.worldY = 0.5, 2.9
    registry[angledDoorActor.id] = angledDoorActor
    local angledDoorAccepted, angledDoorReason = SurvivorCompanion.Navigation.request(
        angledDoorActor, doorTo, "walk", {})
    check(angledDoorAccepted and angledDoorReason == "aligning_door_approach"
            and angledDoorActor.lastIntent.action == "door_approach"
            and angledDoorActor.lastIntent.doorwayAlignment == true
            and math.abs(angledDoorActor.lastIntent.dx) < 0.001
            and angledDoorActor.lastIntent.dy < 0
            and math.abs(angledDoorActor.lastIntent.targetPosition.y - 2.5) < 0.001,
        "an angled doorway approach centres the capsule before native crossing")
    local classifiedDoor = SurvivorCompanion.Navigation._classifyMovementBlockerForTests(
        angledDoorActor, doorFrom, doorTo, "native_path_failed")
    check(classifiedDoor.type == "door" and classifiedDoor.object == testDoor,
        "a failed known door edge remains a door blocker without a transient collision flag")
    SurvivorCompanion.Navigation.reset(angledDoorActor)
    registry[angledDoorActor.id] = nil
    testDoor.open = false
end
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
do
    local passageLeader = actor("passage-leader", 1, 2,
        { className = "IsoPlayer", recruited = false })
    local firstFollower = actor("passage-01", 0, 2, {})
    local secondFollower = actor("passage-02", 0, 2, {})
    local edge = SurvivorCompanion.Navigation.edgeAffordance(doorFrom, doorTo)
    local cohort = "party:passage-test"
    local passage = SurvivorCompanion.Navigation.observeGroupPassage(
        passageLeader, edge, cohort,
        { { actor = firstFollower }, { actor = secondFollower } }, clock)
    local firstState, secondState = {}, {}
    local firstMayCross = SurvivorCompanion.Navigation._ensureGroupPassageForRequest(
        firstFollower, firstState, doorFrom, doorTo, "door", {
            cohortKey = cohort,
            groupParticipants = { { actor = firstFollower }, { actor = secondFollower } },
        }, clock)
    local secondMayCross, secondReason = SurvivorCompanion.Navigation._ensureGroupPassageForRequest(
        secondFollower, secondState, doorFrom, doorTo, "door", {
            cohortKey = cohort,
            groupParticipants = { { actor = firstFollower }, { actor = secondFollower } },
        }, clock)
    firstFollower.square = doorTo
    firstFollower.worldX, firstFollower.worldY = 1.5, 2.5
    SurvivorCompanion.Navigation._markActorPassageForRequest(firstFollower, firstState, clock + 100)
    local secondAfter = SurvivorCompanion.Navigation._ensureGroupPassageForRequest(
        secondFollower, secondState, doorFrom, doorTo, "door", {
            cohortKey = cohort,
            groupParticipants = { { actor = firstFollower }, { actor = secondFollower } },
        }, clock + 100)
    local activeBeforeFinal = SurvivorCompanion.Navigation.groupPassageActive(edge, cohort, clock + 100)
    secondFollower.square = doorTo
    secondFollower.worldX, secondFollower.worldY = 1.5, 2.5
    SurvivorCompanion.Navigation._markActorPassageForRequest(
        secondFollower, secondState, clock + 200)
    local activeAfterFinal = SurvivorCompanion.Navigation.groupPassageActive(edge, cohort, clock + 200)
    check(passage and firstMayCross == true and secondMayCross == nil
            and secondReason == "holding_group_passage" and secondAfter == true
            and activeBeforeFinal == true and activeAfterFinal == false,
        "a shared door passage admits followers in role order and stays active until final clearance")
    SurvivorCompanion.Navigation.cancel(firstFollower, "test_done")
    SurvivorCompanion.Navigation.cancel(secondFollower, "test_done")
end
do
    -- Full CQB integration: an open formation follows the leader's door edge,
    -- collapses into its role-ordered column, advances exactly one member at a
    -- time, and does not fan out while the rear guard is still outside.
    local columnLeader = actor("column-leader", 0, 2,
        { className = "IsoPlayer", recruited = false, forwardX = 1, forwardY = 0 })
    columnLeader.modData.SC_Recruited = false
    -- All members are inside the 2.5-tile portal admission radius. Distant
    -- followers no longer reserve the head of a doorway queue.
    local columnPoint = actor("column-point", -2, 2, {})
    local columnAssault = actor("column-assault", -2, 2, {})
    local columnRanged = actor("column-ranged", -2, 2, {})
    local columnRear = actor("column-rear", -2, 2, {})
    columnRanged.primary = item("Base.ColumnTestRifle", "Weapon", { ranged = true, ammo = 8 })
    local columnMembers = { columnPoint, columnAssault, columnRanged, columnRear }
    for _, member in ipairs(columnMembers) do
        registry[member.id] = member
        check(SurvivorCompanion.Commands.issue(member.id, "follow", nil, columnLeader)
                and SurvivorCompanion.Commands.issue(
                    member.id, "set_group", "column-test", columnLeader),
            "single-file fixture joins the test fireteam")
    end
    local pointCommands = SurvivorCompanion.Commands.peek(columnPoint)
    local assaultCommands = SurvivorCompanion.Commands.peek(columnAssault)
    local rangedCommands = SurvivorCompanion.Commands.peek(columnRanged)
    local rearCommands = SurvivorCompanion.Commands.peek(columnRear)
    pointCommands.personalityProfile = { courage = 98, caution = 20, practicality = 55 }
    assaultCommands.personalityProfile = { courage = 72, caution = 30, practicality = 55 }
    rangedCommands.personalityProfile = { courage = 50, caution = 50, practicality = 70 }
    rangedCommands.combatDoctrine = "ranged_support"
    rangedCommands.weaponPriority = "firearm"
    rearCommands.personalityProfile = { courage = 35, caution = 98, practicality = 65 }
    local columnSnapshot = {
        threats = {}, allies = {}, player = { actor = columnLeader, danger = 0 },
    }

    -- Seed the leader trail outside, then cross the actual harness door edge.
    SurvivorCompanion.Positioning.formationTarget(
        columnPoint, columnLeader, pointCommands, columnSnapshot)
    columnLeader.square = doorTo
    columnLeader.worldX, columnLeader.worldY = 1.5, 2.5
    clock = clock + 300
    local _, pointColumn = SurvivorCompanion.Positioning.formationTarget(
        columnPoint, columnLeader, pointCommands, columnSnapshot)
    local _, assaultColumn = SurvivorCompanion.Positioning.formationTarget(
        columnAssault, columnLeader, assaultCommands, columnSnapshot)
    local _, rangedColumn = SurvivorCompanion.Positioning.formationTarget(
        columnRanged, columnLeader, rangedCommands, columnSnapshot)
    local _, rearColumn = SurvivorCompanion.Positioning.formationTarget(
        columnRear, columnLeader, rearCommands, columnSnapshot)
    check(pointColumn.mode == "trail" and assaultColumn.mode == "trail"
            and rangedColumn.mode == "trail" and rearColumn.mode == "trail"
            and pointColumn.columnIndex == 1 and assaultColumn.columnIndex == 2
            and rangedColumn.columnIndex == 3 and rearColumn.columnIndex == 4,
        "all four CQB roles collapse into one ordered column at the door")

    local columnEdge = SurvivorCompanion.Navigation.edgeAffordance(doorFrom, doorTo)
    local columnStates = { {}, {}, {}, {} }
    for index, member in ipairs(columnMembers) do
        local accepted, reason = SurvivorCompanion.Navigation._ensureGroupPassageForRequest(
            member, columnStates[index], doorFrom, doorTo, "door", {
                cohortKey = pointColumn.cohortKey,
                groupParticipants = pointColumn.participants,
            }, clock + index)
        check((index == 1 and accepted == true)
                or (index > 1 and accepted == nil and reason == "holding_group_passage"),
            "only the point member initially owns the single-file doorway")
    end
    for index, member in ipairs(columnMembers) do
        member.square = doorTo
        member.worldX, member.worldY = 1.5, 2.5
        SurvivorCompanion.Navigation._markActorPassageForRequest(
            member, columnStates[index], clock + index * 100)
        if index < #columnMembers then
            local nextMember = columnMembers[index + 1]
            local nextAccepted = SurvivorCompanion.Navigation._ensureGroupPassageForRequest(
                nextMember, columnStates[index + 1], doorFrom, doorTo, "door", {
                    cohortKey = pointColumn.cohortKey,
                    groupParticipants = pointColumn.participants,
                }, clock + index * 100)
            check(nextAccepted == true,
                "single-file doorway ownership advances to the next CQB role")
        end
        local active = SurvivorCompanion.Navigation.groupPassageActive(
            columnEdge, pointColumn.cohortKey, clock + index * 100)
        check(active == (index < #columnMembers),
            "doorway column remains active until the rear guard clears it")
    end

    clock = clock + #columnMembers * 100
    local _, clearing = SurvivorCompanion.Positioning.formationTarget(
        columnPoint, columnLeader, pointCommands, columnSnapshot)
    check(clearing and clearing.mode == "trail",
        "fireteam remains in column on the pulse that observes rear-guard clearance")
    clock = clock + (SurvivorCompanion.GameplayUtil.config("formationPortalHoldMs") or 1200)
        + (SurvivorCompanion.GameplayUtil.config("formationReflowDelayMs") or 650) + 10
    local _, reopened = SurvivorCompanion.Positioning.formationTarget(
        columnPoint, columnLeader, pointCommands, columnSnapshot)
    check(reopened and reopened.mode == "open",
        "fireteam fans back out only after final clearance and the reflow delay")

    for _, member in ipairs(columnMembers) do
        SurvivorCompanion.Positioning.reset(member)
        SurvivorCompanion.Navigation.reset(member)
        SurvivorCompanion.Commands.reset(member)
        registry[member.id] = nil
    end
    SurvivorCompanion.Positioning.reset(columnLeader)
    for _, value in ipairs({ columnLeader, columnPoint, columnAssault,
            columnRanged, columnRear }) do
        for index = #value.square.moving, 1, -1 do
            if value.square.moving[index] == value then table.remove(value.square.moving, index) end
        end
    end
end
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
function testWindow:canClimbThrough(character) return true end
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
do
    -- Playtest 4: every companion had wounds on all body parts at severity 30 and
    -- tried to change bandages over its whole body forever. BodyPart.IsInfected()
    -- reports the character's Knox (zombie) infection, which the engine propagates
    -- to every part; wound assessment must read only the local, treatable wound
    -- infection (isInfectedWound) and leave Knox to the character-level check.
    local knoxParts = {}
    for index = 1, 6 do knoxParts[index] = bodyPart({ name = "knoxpart" .. index }) end
    local knoxBody = bodyDamage(80, knoxParts)
    knoxBody.infected = true
    local knoxActor = actor("sc-knox-body", 40, 40, { body = knoxBody })
    local knoxAssessment = SurvivorCompanion.Medical.assess(knoxActor)
    check(knoxAssessment.knoxInfected == true and knoxAssessment.woundCount == 0
            and knoxAssessment.needsBandage == false,
        "a Knox-infected companion does not read its whole body as wounded (playtest 4)")
    knoxParts[1].infectedWound = true
    local woundedAssessment = SurvivorCompanion.Medical.assess(knoxActor)
    check(woundedAssessment.woundCount == 1 and woundedAssessment.wounds[1].infected == true,
        "a local treatable wound infection is still assessed as a wound needing care")
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

do
-- Navigation legitimately selects diagonal interaction squares. Medical's
-- acceptance range must include sqrt(2), otherwise requestAny reports "arrived"
-- forever while treatment never leaves its approach phase.
local diagonalWound = bodyPart({ name = "UpperArm_L", isBleeding = true })
local diagonalPatient = actor("sc-diagonal-patient", 14, 14, {
    body = bodyDamage(70, { diagonalWound }),
})
local diagonalBandage = item("Base.Bandage", "Medical")
local diagonalMedic = actor("sc-diagonal-medic", 13, 13, {
    inventory = inventory({ diagonalBandage }),
})
local diagonalTreated = SurvivorCompanion.Medical.treat(diagonalMedic,
    diagonalPatient, { snapshot = { threats = {}, immediateCount = 0,
        escapeSquares = { { square = diagonalMedic.square } } } })
check(diagonalTreated and diagonalWound.isBandaged and diagonalBandage.used,
    "a medic arrived on a diagonal interaction square begins treatment")
end

do
-- Player-initiated care: the local player hand-bandages a companion using a
-- bandage from the player's own inventory (feature: "I can bandage them too").
local patientWound = bodyPart({ name = "ForeArm_R", isBleeding = true })
local woundedCompanion = actor("sc-hand-bandage-patient", 12, 12, {
    body = bodyDamage(70, { patientWound }),
})
local playerBandage = item("Base.Bandage", "Medical")
local caretaker = actor("sc-hand-bandage-player", 12, 13, { inventory = inventory({ playerBandage }) })
local ready, readyReason, context = SurvivorCompanion.Medical.playerBandagePreflight(
    woundedCompanion, caretaker)
check(ready and readyReason == "ready" and context.wound.part == patientWound
        and context.bandage == playerBandage,
    "player-bandage preflight resolves the companion's wound and a bandage from the player's inventory")
local applied, applyReason = SurvivorCompanion.Medical.applyPlayerBandage(woundedCompanion, caretaker)
check(applied and applyReason == "bandaged" and patientWound.isBandaged and playerBandage.used,
    "the player's bandage is applied to the companion's wound and consumed from the player's inventory")
local healedOk, healedReason = SurvivorCompanion.Medical.playerBandagePreflight(woundedCompanion, caretaker)
check(not healedOk and healedReason == "no_treatable_wound",
    "a companion with no treatable wound cannot be hand-bandaged")

local secondWound = bodyPart({ name = "Hand_L", isBleeding = true })
local secondCompanion = actor("sc-hand-bandage-patient2", 12, 12, {
    body = bodyDamage(70, { secondWound }),
})
local emptyHanded = actor("sc-hand-bandage-empty", 12, 13, { inventory = inventory({}) })
local noBandageOk, noBandageReason = SurvivorCompanion.Medical.playerBandagePreflight(
    secondCompanion, emptyHanded)
check(not noBandageOk and noBandageReason == "no_bandage",
    "a player with no bandage cannot hand-bandage a companion")

local farPlayer = actor("sc-hand-bandage-far", 40, 40, {
    inventory = inventory({ item("Base.Bandage", "Medical") }),
})
local farOk, farReason = SurvivorCompanion.Medical.playerBandagePreflight(secondCompanion, farPlayer)
check(not farOk and farReason == "out_of_range",
    "a player out of reach cannot hand-bandage a companion")
end

do
-- LF-05: a dressing's eligibility is proven before its quality is ranked. An
-- isAlcoholic() flag (whiskey) or a "steril" substring in an unrelated name must
-- not make a non-dressing outrank a real bandage.
local rank = SurvivorCompanion.Medical._bandageRankForTests
check(rank(item("Base.Bandage", "Medical")) ~= nil, "a real bandage is an eligible dressing")
check(rank(item("Base.WhiskeyFull", "Food", { alcoholic = true })) == nil,
    "an alcoholic non-dressing (whiskey) is not selectable as a bandage")
check(rank(item("Base.SterileWipe", "Item")) == nil,
    "an unrelated item whose name merely contains 'steril' is not selectable as a bandage")
check(rank(item("Base.MysteryDressing", "Item", { tags = { CanBandage = true } })) ~= nil,
    "an item tagged CanBandage is an eligible dressing")
check(rank(item("Base.SterilizedBandage", "Medical")) == 1,
    "a sterile dressing ranks best among eligible dressings")
check(rank(item("Base.Bandage", "Medical", { alcoholic = true }))
        < rank(item("Base.Bandage", "Medical")),
    "an alcohol-treated bandage outranks a plain one, but only because it is already a dressing")
end

do
-- LF-06: bandages carried in a bag, or past the first 100 root items, must be
-- found -- and returned with their actual source container so consumption operates
-- where the bandage lives, not blindly on the root inventory.
local findBandage = SurvivorCompanion.Medical._findBandageForTests

local rootBandage = item("Base.Bandage", "Medical")
local rootCarrier = actor("sc-find-root", 0, 0, { inventory = inventory({ rootBandage }) })
local rootFound, rootContainer = findBandage(rootCarrier)
check(rootFound == rootBandage and rootContainer == rootCarrier.inventory,
    "a bandage in the root inventory is found with the root as its container")

local bagBandage = item("Base.Bandage", "Medical")
local bagInventory = inventory({ bagBandage })
local bag = item("Base.Bag_Schoolbag", "Container", { nestedInventory = bagInventory })
local bagCarrier = actor("sc-find-bag", 0, 0, { inventory = inventory({ bag }) })
local bagFound, bagContainer = findBandage(bagCarrier)
check(bagFound == bagBandage and bagContainer == bagInventory,
    "a bandage inside a carried bag is found and its source container is the bag, not the root")

local deepBandage = item("Base.Bandage", "Medical")
local manyItems = {}
for index = 1, 120 do manyItems[index] = item("Base.Junk" .. tostring(index), "Item") end
manyItems[121] = deepBandage
local deepCarrier = actor("sc-find-deep", 0, 0, { inventory = inventory(manyItems) })
check(findBandage(deepCarrier) == deepBandage,
    "a bandage past the first 100 root items is still found")

local emptyCarrier = actor("sc-find-none", 0, 0, { inventory = inventory({ item("Base.Junk", "Item") }) })
check(findBandage(emptyCarrier) == nil, "no bandage anywhere returns nil")
end

do
-- R2-07: the shared bandage commit verifies the wound actually changed before
-- consuming the dressing. A no-op native setter (returns success without bandaging)
-- must fail verification and leave the item unspent; an effectful setter applies
-- and consumes exactly once.
local noopWound = bodyPart({ name = "ForeArm_R", isBleeding = true })
local noopBody = bodyDamage(70, { noopWound })
function noopBody:SetBandaged(index, enabled, life, alcoholic, itemType) return true end
local noopCompanion = actor("sc-verify-noop-patient", 12, 12, { body = noopBody })
local noopBandage = item("Base.Bandage", "Medical")
local noopPlayer = actor("sc-verify-noop-player", 12, 13, { inventory = inventory({ noopBandage }) })
local noopOk, noopReason = SurvivorCompanion.Medical.applyPlayerBandage(noopCompanion, noopPlayer)
check(not noopOk and noopReason == "native_bandage_unverified"
        and not noopWound.isBandaged and not noopBandage.used,
    "a no-op native setter fails read-back verification and the dressing is not consumed")

local goodWound = bodyPart({ name = "Hand_L", isBleeding = true })
local goodCompanion = actor("sc-verify-good-patient", 12, 12, { body = bodyDamage(70, { goodWound }) })
local goodBandage = item("Base.Bandage", "Medical")
local goodPlayer = actor("sc-verify-good-player", 12, 13, { inventory = inventory({ goodBandage }) })
local goodOk, goodReason = SurvivorCompanion.Medical.applyPlayerBandage(goodCompanion, goodPlayer)
check(goodOk and goodReason == "bandaged" and goodWound.isBandaged and goodBandage.used,
    "an effectful native setter applies the bandage and consumes the dressing once")
end

do
-- The "bandage" command preflights the hand-bandage, then hands off to
-- SC.PlayerCare (the native timed-action layer) which is absent in the harness.
local careWound = bodyPart({ name = "UpperArm_R", isBleeding = true })
local careCompanion = actor("sc-care-cmd", 0, 2, { body = bodyDamage(70, { careWound }) })
registry[careCompanion.id] = careCompanion
local careBandage = item("Base.Bandage", "Medical")
player.inventory:AddItem(careBandage)

local noCareOk, noCareReason = SurvivorCompanion.Commands.issue(careCompanion.id, "bandage", nil, player)
check(not noCareOk and noCareReason == "ui_unavailable",
    "the bandage command fails closed when the native timed-action layer is unavailable")

local queuedWith = nil
SurvivorCompanion.PlayerCare = {
    queueBandage = function(p, c) queuedWith = { p = p, c = c } return true, "bandage_started" end,
}
local careOk, careReason = SurvivorCompanion.Commands.issue(careCompanion.id, "bandage", nil, player)
check(careOk and careReason == "bandage_started"
        and queuedWith and queuedWith.p == player and queuedWith.c == careCompanion,
    "the bandage command preflights then queues the player's timed action via SC.PlayerCare")
SurvivorCompanion.PlayerCare = nil

careWound.isBandaged = true
local healedOk, healedReason = SurvivorCompanion.Commands.issue(careCompanion.id, "bandage", nil, player)
check(not healedOk and healedReason == "no_treatable_wound",
    "the bandage command refuses a companion with no treatable wound")

player.inventory:Remove(careBandage)
registry[careCompanion.id] = nil
end

-- Knox and injuries drop health but never immobilize a companion: like a player it
-- stays mobile (and bandageable) as its health falls, and only stops when it dies
-- at zero health or turns at terminal Knox.
local lowActor = actor("sc-downed", 6, 0, { body = bodyDamage(10) })
registry[lowActor.id] = lowActor
SurvivorCompanion.Medical.update(lowActor, player, { snapshot = { threats = {}, immediateCount = 0 } })
check(not SurvivorCompanion.Medical.isDowned(lowActor)
    and not (lowActor.lastIntent and lowActor.lastIntent.action == "downed"),
    "critical nonzero native health never immobilizes a companion")
registry[lowActor.id] = nil

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
-- Auto-bandaging is low priority: it must hold off in active combat and only run
-- once the companion is at least semi-safe.
local combatWound = bodyPart({ name = "ForeArm_R", isBleeding = true })
local combatShirt = item("Base.Tshirt_White", "Clothing")
local combatActor = actor("sc-combat-medic", 8, 0, {
    body = bodyDamage(60, { combatWound }), inventory = inventory({ combatShirt }),
})
registry[combatActor.id] = combatActor
local inCombat = SurvivorCompanion.Medical.update(combatActor, player, {
    snapshot = { threats = { { actor = player } }, immediateCount = 1, escapeSquares = {} },
})
check(not inCombat and SurvivorCompanion.Medical.peek(combatActor) == nil
    and combatWound.isBandaged ~= true,
    "self-bandaging holds off while an attacker is in melee range")
local whenSafe = SurvivorCompanion.Medical.update(combatActor, player, {
    snapshot = { threats = {}, immediateCount = 0,
        escapeSquares = { { square = combatActor.square } } },
})
check(whenSafe and combatWound.isBandaged,
    "self-bandaging resumes once the companion is semi-safe")
registry[combatActor.id] = nil
end

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
check(SurvivorCompanion.Decision._ownerNeedsImmediatePreemptionForTests(
        "medical", { immediateCount = 0, pressure = 0, player = { danger = 0 } },
        { bleedingCount = 1, critical = false, downed = false }, {}, { order = "stay" }) == false
        and SurvivorCompanion.Decision._ownerNeedsImmediatePreemptionForTests(
            "downtime", { immediateCount = 0, pressure = 0, player = { danger = 0 } },
            { bleedingCount = 1, critical = false, downed = false }, {}, { order = "stay" }) == true
        and SurvivorCompanion.Decision._ownerNeedsImmediatePreemptionForTests(
            "medical", { immediateCount = 1, pressure = 0, player = { danger = 0 } },
            { bleedingCount = 1, critical = false, downed = false }, {}, { order = "stay" }) == true
        and SurvivorCompanion.Decision._ownerNeedsImmediatePreemptionForTests(
            "medical", { immediateCount = 0, pressure = 0, player = { danger = 0 } },
            { bleedingCount = 1, critical = false, downed = false }, {}, { order = "stay" },
            true) == true,
    "an active medical owner ignores its own wound urgency but still yields to external danger")
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

do
-- A treatment that can never settle within medical range must give up after the
-- approach budget instead of navigating forever. In the live sandbox an
-- unavailable patient position made the distance read math.huge, so the treatment
-- returned "arrived" every tick (observed x529) and never bandaged.
local approachTimeoutClock = clock
local strandedPart = bodyPart({ name = "ForeArm_L", isBleeding = true })
local strandedPatient = actor("sc-approach-timeout-patient", 5, 5, {
    body = bodyDamage(70, { strandedPart }),
})
registry[strandedPatient.id] = strandedPatient
local strandedBandage = item("Base.Bandage", "Medical")
local strandedMedic = actor("sc-approach-timeout-medic", 0, 0, {
    inventory = inventory({ strandedBandage }),
})
registry[strandedMedic.id] = strandedMedic
local previousNativeActions = SurvivorCompanion.NativeActions
SurvivorCompanion.NativeActions = {
    pathToNearest = function() return true, "stranded_path_started" end,
    pathTelemetry = function()
        return { available = true, active = true, shouldBeMoving = true,
            hasStartedMoving = false, pending = true }
    end,
    stopDirect = function() return true end,
}
local approachSnapshot = { threats = {}, immediateCount = 0,
    escapeSquares = { { square = strandedMedic.square } } }
local approachStart = SurvivorCompanion.Medical.treat(
    strandedMedic, strandedPatient, { snapshot = approachSnapshot })
local approachPeek = SurvivorCompanion.Medical.peek(strandedMedic)
check(approachStart and approachPeek ~= nil and approachPeek.phase == "approaching",
    "a distant rescue treatment enters the approach phase while the path stays pending")
clock = clock + 4000
local approachMid = SurvivorCompanion.Medical.treat(strandedMedic, strandedPatient, {})
check(approachMid and SurvivorCompanion.Medical.peek(strandedMedic) ~= nil
        and not strandedPart.isBandaged,
    "an in-budget approach keeps navigating without abandoning the treatment")
clock = clock + SurvivorCompanion.Config.values.medicalApproachTimeoutMs + 1
local approachDone, approachDoneReason =
    SurvivorCompanion.Medical.treat(strandedMedic, strandedPatient, {})
check(not approachDone and approachDoneReason == "approach_timeout"
        and SurvivorCompanion.Medical.peek(strandedMedic) == nil
        and not strandedPart.isBandaged and not strandedBandage.used,
    "an approach that never settles times out, clears the treatment, and spends no supply")
SurvivorCompanion.NativeActions = previousNativeActions
registry[strandedPatient.id] = nil
registry[strandedMedic.id] = nil
clock = approachTimeoutClock
end

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
local cleaver = item("Base.MeatCleaver", "Weapon", {
    damage = 1.6, range = 1.0, minRange = 0.61, sharpness = 1,
    weaponCategories = { "SmallBlade" },
})
local cleaverActor = actor("sc-cleaver-primary", 30, 30, {
    inventory = inventory({ cleaver }),
})
cleaverActor.primary = cleaver
registry[cleaverActor.id] = cleaverActor
local cleaverZed = zombie(31, 30, { attacking = true, target = cleaverActor })
local cleaverSnapshot = {
    threats = { { actor = cleaverZed, square = cleaverZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true, score = 90 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 1,
    closeImmediateCount = 1, closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 1, encircled = false, player = { danger = 0, immediateThreats = 0 },
}
local cleaverActed, cleaverReason = SurvivorCompanion.Combat.update(
    cleaverActor, player, { snapshot = cleaverSnapshot })
check(cleaverActed and cleaverReason == "melee"
        and cleaverActor.lastIntent.action == "attack_melee"
        and cleaverActor.lastIntent.weapon == cleaver,
    "an equipped meat cleaver attacks instead of losing the close-range choice to shove")
cleaverZed.onFloor = true
local cleaverFloored, cleaverFloorReason = SurvivorCompanion.Combat.update(
    cleaverActor, player, { snapshot = cleaverSnapshot })
check(cleaverFloored and cleaverFloorReason == "melee"
        and cleaverActor.lastIntent.action == "attack_melee"
        and cleaverActor.lastIntent.weapon == cleaver
        and cleaverActor.lastIntent.floorAttack == true,
    "a healthy equipped melee weapon uses the native player floor attack on a grounded zombie")
cleaver.condition = 1
local preservedWeapon, preservedWeaponReason = SurvivorCompanion.Combat.update(
    cleaverActor, player, { snapshot = cleaverSnapshot })
check(preservedWeapon and preservedWeaponReason == "stomp"
        and cleaverActor.lastIntent.action == "stomp",
    "a nearly broken melee weapon is plausibly preserved by choosing a stomp")
cleaver.condition = 10
cleaverZed.onFloor = false
cleaverActor.worldX = 31.25
cleaverSnapshot.threats[1].distanceSq = 0.25 * 0.25
local cleaverContact, cleaverContactReason = SurvivorCompanion.Combat.update(
    cleaverActor, player, { snapshot = cleaverSnapshot })
check(cleaverContact and cleaverContactReason == "shove"
        and cleaverActor.lastIntent.action == "shove",
    "a melee wielder only uses the defensive shove inside the weapon's true minimum reach")
SurvivorCompanion.Combat.reset(cleaverActor)
registry[cleaverActor.id] = nil
cleaverZed.dead = true
end

(function()
local vectorWeaponItem = item("Base.VectorAxe", "Weapon", {
    damage = 2.2, range = 1.5, minRange = 0.3, sharpness = 1,
})
local vectorActor = actor("sc-vector-preflight", 34, 30, {
    inventory = inventory({ vectorWeaponItem }),
})
vectorActor.primary = vectorWeaponItem
local vectorTarget = zombie(37, 30, {})
local vectorThreat = { actor = vectorTarget, square = vectorTarget.square,
    distanceSq = 9, visible = true, obstructed = false, score = 80 }
local vectorSnapshot = { threats = { vectorThreat }, immediateCount = 0,
    closeImmediateCount = 0, closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 0, allies = {}, escapeSquares = {
        { square = cell:getGridSquare(33, 30, 0), danger = 0, nearestThreatSq = 16 },
    } }
local vectorWeapon = { item = vectorWeaponItem, ranged = false, damage = 2.2,
    range = 1.5, conditionRatio = 1, sharpness = 1, staminaCost = 1, weight = 1.5 }
local priorCombatVector = SurvivorCompanion.Navigation.combatVector
SurvivorCompanion.Navigation.combatVector = function() return nil, nil, false,
    "no_clear_alternative" end
local vectorActions = SurvivorCompanion.Combat._actionUtilitiesForTests(
    vectorActor, player, vectorSnapshot, vectorThreat, vectorWeapon,
    vectorActor.inventory, { combatDoctrine = "close_defense", morale = 70 }, nil)
SurvivorCompanion.Navigation.combatVector = priorCombatVector
local unsafeMovementOffered = false
for _, action in ipairs(vectorActions or {}) do
    if action.kind == "approach" or action.kind == "backstep" or action.kind == "kite" then
        unsafeMovementOffered = true break
    end
end
check(not unsafeMovementOffered,
    "combat removes movement actions when every collision-validated vector is blocked")

local pairGrounded = zombie(35, 35, { onFloor = true })
local pairStanding = zombie(36, 36, {})
local pairActor = actor("sc-target-action-pair", 35, 36, {
    inventory = inventory({ vectorWeaponItem }),
})
pairActor.primary = vectorWeaponItem
local groundedThreat = { actor = pairGrounded, square = pairGrounded.square,
    distanceSq = 1, visible = true, obstructed = false, grounded = true, score = 100 }
local standingThreat = { actor = pairStanding, square = pairStanding.square,
    distanceSq = 1, visible = true, obstructed = false, grounded = false, score = 90 }
local pairSnapshot = { threats = { groundedThreat, standingThreat },
    immediateCount = 2, closeImmediateCount = 2, closeThreatCount = 2,
    occupiedThreatSectors = 1, pressure = 0, allies = {}, encircled = false,
    escapeSquares = { { square = cell:getGridSquare(34, 36, 0), danger = 0,
        nearestThreatSq = 9 } } }
local pair = SurvivorCompanion.Combat._selectViablePairForTests(
    pairActor, player, pairSnapshot, { groundedThreat, standingThreat },
    { combatDoctrine = "close_defense", morale = 75 },
    { target = pairGrounded, targetCommitUntil = clock + 1000 },
    clock, "best", groundedThreat)
check(pair and pair.target.actor == pairStanding and pair.action.kind == "melee",
    "target commitment cannot let an unsafe grounded finisher suppress a viable standing melee target")
for _, value in ipairs({ vectorActor, vectorTarget, pairActor, pairGrounded, pairStanding }) do
    if value.square and value.square.moving then
        for index = #value.square.moving, 1, -1 do
            if value.square.moving[index] == value then table.remove(value.square.moving, index) end
        end
    end
end
pairGrounded.dead, pairStanding.dead, vectorTarget.dead = true, true, true
end)()

;(function()
    local scanWeapon = item("Base.TargetScanAxe", "Weapon", {
        damage = 2.1, range = 1.5, minRange = 0.2, sharpness = 1,
    })
    local scanActor = actor("sc-target-action-scan", 6, 10, {
        inventory = inventory({ scanWeapon }),
    })
    scanActor.primary = scanWeapon
    local scanTargets, scanThreats = {}, {}
    for index = 1, 4 do
        local target = zombie(7, 9 + index, { onFloor = index <= 3 })
        scanTargets[index] = target
        scanThreats[index] = {
            actor = target, square = target.square, distanceSq = 1,
            visible = true, obstructed = false, grounded = index <= 3,
            score = 110 - index,
        }
    end
    local scanSnapshot = {
        threats = scanThreats, immediateCount = 4, closeImmediateCount = 4,
        closeThreatCount = 4, occupiedThreatSectors = 1, pressure = 0,
        allies = {}, encircled = false, escapeSquares = {},
    }
    local selected = SurvivorCompanion.Combat._selectViablePairForTests(
        scanActor, player, scanSnapshot, scanThreats,
        { combatDoctrine = "close_defense", morale = 75 }, {}, clock,
        "best", scanThreats[1])
    check(selected and selected.target.actor == scanTargets[4]
            and selected.action.kind == "melee",
        "target/action search widens past three unusable targets to the fourth viable melee target")
    for _, value in ipairs({ scanActor, scanTargets[1], scanTargets[2],
            scanTargets[3], scanTargets[4] }) do
        if value.square and value.square.moving then
            for index = #value.square.moving, 1, -1 do
                if value.square.moving[index] == value then table.remove(value.square.moving, index) end
            end
        end
        if value ~= scanActor then value.dead = true end
    end
end)()

do
local roleWeapon = item("Base.Axe", "Weapon", { damage = 2, range = 1.4, sharpness = 1 })
local roleActors = {
    actor("sc-role-01", 10, 10, { inventory = inventory({ roleWeapon }) }),
    actor("sc-role-02", 10, 11, { inventory = inventory({ roleWeapon }) }),
    actor("sc-role-03", 10, 9, { inventory = inventory({ roleWeapon }) }),
}
local roleTarget = zombie(12, 10, { attacking = false })
local roleSnapshot = {
    threats = { { actor = roleTarget, square = roleTarget.square, distanceSq = 4,
        visible = true, obstructed = false, attacking = false, score = 70 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 0,
    closeImmediateCount = 0, closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 0, encircled = false, player = { danger = 0, immediateThreats = 0 },
    time = clock,
}
for _, roleActor in ipairs(roleActors) do
    roleActor.primary = roleWeapon
    registry[roleActor.id] = roleActor
    SurvivorCompanion.Combat.update(roleActor, player, { snapshot = roleSnapshot })
end
check(SurvivorCompanion.Combat.peek(roleActors[1]).combatRole == "primary"
        and SurvivorCompanion.Combat.peek(roleActors[2]).combatRole == "support"
        and SurvivorCompanion.Combat.peek(roleActors[3]).combatRole == "reserve"
        and roleActors[3].lastIntent.action == "ready_weapon",
    "one cohort assigns one primary, one support, and a guarding reserve per target")
roleTarget.square = cell:getGridSquare(11, 10, 0)
clock = clock + 100
roleSnapshot.time = clock
local impactScored = SurvivorCompanion.Combat.scoreTargets(
    roleActors[1], player, roleSnapshot, roleTarget)
check(impactScored[1] and impactScored[1].closingSpeed > 0
        and impactScored[1].timeToImpactMs <= 6000
        and impactScored[1].impactScore > 0,
    "live radial closing speed adds bounded time-to-impact urgency before contact")
for _, roleActor in ipairs(roleActors) do
    SurvivorCompanion.Combat.reset(roleActor)
    registry[roleActor.id] = nil
end
roleTarget.dead = true
end

do
local approachClock = clock
local approachConfig = SurvivorCompanion.Config.values
local savedShoveDistance = approachConfig.combatShoveDistance
approachConfig.combatShoveDistance = 0.5
local sword = item("Base.Katana", "Weapon", {
    damage = 3, range = 1.7, sharpness = 1,
    weaponCategories = { "LongBlade" },
})
local swordActor = actor("sc-melee-approach", 20, 20, {
    inventory = inventory({ sword }),
})
swordActor.primary = sword
registry[swordActor.id] = swordActor
local swordZed = zombie(23, 20, { attacking = true, target = swordActor })
local approachSnapshot = {
    threats = { { actor = swordZed, square = swordZed.square, distanceSq = 9,
        visible = true, obstructed = false, attacking = true, score = 90 } },
    allies = {},
    escapeSquares = { { square = cell:getGridSquare(19, 20, 0), danger = 0,
        nearestThreatSq = 16 } },
    threatCount = 1, immediateCount = 0, closeImmediateCount = 0,
    closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 0, encircled = false,
    player = { danger = 0, immediateThreats = 0 },
}
local approached, approachReason = SurvivorCompanion.Combat.update(
    swordActor, player, { snapshot = approachSnapshot })
check(approached and approachReason == "approach"
        and swordActor.lastIntent.action == "combat_approach"
        and swordActor.lastIntent.weaponReady == true
        and swordActor.lastIntent.target == swordZed,
    "an equipped melee companion closes a safe gap instead of kiting forever")

-- Spacing is keyed to the weapon's own reach: at the exact gap a long blade
-- swings from, a short weapon must close first rather than swing out of range
-- and miss. Same snapshot/distance as the sword test above, shorter weapon.
local knife = item("Base.HuntingKnife", "Weapon", {
    damage = 2, range = 0.9, sharpness = 1, weaponCategories = { "SmallBlade" },
})
local knifeActor = actor("sc-melee-shortreach", 40, 40, { inventory = inventory({ knife }) })
knifeActor.primary = knife
registry[knifeActor.id] = knifeActor
local knifeZed = zombie(41, 40, { attacking = true, target = knifeActor })
local shortSnapshot = {
    threats = { { actor = knifeZed, square = knifeZed.square, distanceSq = 1.4 * 1.4,
        visible = true, obstructed = false, attacking = true, score = 90 } },
    allies = {},
    escapeSquares = { { square = cell:getGridSquare(39, 40, 0), danger = 0,
        nearestThreatSq = 16 } },
    threatCount = 1, immediateCount = 0, closeImmediateCount = 0,
    closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 0, encircled = false,
    player = { danger = 0, immediateThreats = 0 },
}
local shortActed, shortReason = SurvivorCompanion.Combat.update(
    knifeActor, player, { snapshot = shortSnapshot })
check(shortActed and shortReason == "approach"
        and knifeActor.lastIntent.action == "combat_approach",
    "a short-reach weapon closes to its own swing range instead of swinging from a long blade's distance")
registry[knifeActor.id] = nil

-- Once inside weapon range the same engagement must produce a real attack
-- request. A rejected pulse remains inspectable, then clears after a retry.
swordActor.worldX = 21.6
approachSnapshot.threats[1].distanceSq = 1.4 * 1.4
swordActor.rejectActions = { attack_melee = true }
local rejectedRuntime = { snapshot = approachSnapshot }
local rejectedAttack, rejectedReason = SurvivorCompanion.Combat.update(
    swordActor, player, rejectedRuntime)
check(not rejectedAttack and rejectedReason == "melee_rejected"
        and rejectedRuntime.combatRejectedAction == "melee"
        and rejectedRuntime.combatRejectedReason == "melee_rejected",
    "a rejected native melee pulse is retained in combat diagnostics")
swordActor.rejectActions = nil
local attacked, attackReason = SurvivorCompanion.Combat.update(
    swordActor, player, rejectedRuntime)
check(attacked and attackReason == "melee"
        and swordActor.lastIntent.action == "attack_melee"
        and rejectedRuntime.combatRejectedReason == nil,
    "the companion retries and attacks with its equipped melee weapon once ready")
function swordActor:isAttackStarted() return self.attackStarted == true end
function swordActor:isPerformingAttackAnimation() return self.attackStarted == true end
swordActor.attackStarted = true
local callsBeforeLease = swordActor.movementCalls
approachSnapshot.threats[1].distanceSq = 0.25 * 0.25
local leased, leaseReason = SurvivorCompanion.Combat.update(
    swordActor, player, rejectedRuntime)
check(leased and leaseReason == "attack_in_progress"
        and swordActor.movementCalls == callsBeforeLease,
    "an active native swing leases the actor and suppresses approach/backstep reevaluation")
swordActor.attackStarted = false
SurvivorCompanion.Combat.reset(swordActor)
registry[swordActor.id] = nil
swordZed.dead = true
approachConfig.combatShoveDistance = savedShoveDistance
clock = approachClock
end

do
local liveConfig = SurvivorCompanion.Config.values
local savedLiveShoveDistance = liveConfig.combatShoveDistance
liveConfig.combatShoveDistance = 0.1
local responsiveBlade = item("Base.ResponsiveBlade", "Weapon", {
    damage = 2, range = 1.0, minRange = 0.61, sharpness = 1,
    weaponCategories = { "SmallBlade" },
})
local responsiveFighter = actor("sc-live-combat-geometry", 51, 24, {
    inventory = inventory({ responsiveBlade }),
})
responsiveFighter.primary = responsiveBlade
responsiveFighter.worldX = 51.5
responsiveFighter.worldY = 24.5
registry[responsiveFighter.id] = responsiveFighter
local responsiveZed = zombie(53, 24, { attacking = true, target = responsiveFighter })
local liveSnapshot = {
    time = clock,
    -- Deliberately stale contact distance: timestamped production snapshots must
    -- refresh it from the actors before choosing close-combat spacing.
    threats = { { actor = responsiveZed, square = responsiveZed.square,
        distanceSq = 0.2 * 0.2, visible = true, obstructed = false,
        attacking = true, score = 90 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 0,
    closeImmediateCount = 0, closeThreatCount = 1, occupiedThreatSectors = 1,
    pressure = 0, encircled = false,
    player = { danger = 0, immediateThreats = 0 },
}
local liveApproach, liveApproachReason = SurvivorCompanion.Combat.update(
    responsiveFighter, player, { snapshot = liveSnapshot })
check(liveApproach and liveApproachReason == "approach"
        and responsiveFighter.lastIntent.action == "combat_approach",
    "timestamped combat snapshots use live target distance instead of stale spacing data")

responsiveFighter.worldX = 53.3
local closeLiveScore = SurvivorCompanion.Combat.scoreTargets(
    responsiveFighter, player, liveSnapshot, responsiveZed)[1]
local backed, backReason = SurvivorCompanion.Combat.update(
    responsiveFighter, player, { snapshot = liveSnapshot })
check(backed and backReason == "backstep"
        and responsiveFighter.lastIntent.action == "backstep",
    "live geometry permits an immediate safety backstep when contact becomes too close: "
        .. tostring(backReason) .. "/"
        .. tostring(responsiveFighter.lastIntent and responsiveFighter.lastIntent.action)
        .. " d2=" .. tostring(closeLiveScore and closeLiveScore.distanceSq))
responsiveFighter.worldX = 51.5
clock = clock + 50
local held, heldReason = SurvivorCompanion.Combat.update(
    responsiveFighter, player, { snapshot = liveSnapshot })
check(held and heldReason == "hold_range"
        and responsiveFighter.lastIntent.action == "ready_weapon",
    "combat spacing holds aim briefly instead of reversing a backstep into an approach loop")
SurvivorCompanion.Combat.reset(responsiveFighter)
registry[responsiveFighter.id] = nil
responsiveZed.dead = true
liveConfig.combatShoveDistance = savedLiveShoveDistance
end

do
local stompStartClock = clock
local stompActor = actor("sc-shove-stomp", 8, -7, { inventory = inventory() })
-- Keep this fixture genuinely unarmed; normal command initialization may assign
-- a keepsake, and the deliberately broad table mock gives every item weapon-like
-- accessors even though the live Photo/Journal classes are not HandWeapons.
local savedPersonalEnsure = SurvivorCompanion.PersonalItems.ensure
SurvivorCompanion.PersonalItems.ensure = function(_, source) return source or {} end
SurvivorCompanion.Commands.peek(stompActor)
SurvivorCompanion.PersonalItems.ensure = savedPersonalEnsure
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
stompZed.square = cell:getGridSquare(10, -7, 0)
local approachedStomp, approachedStompReason = SurvivorCompanion.Combat.update(
    stompActor, player, { snapshot = stompSnapshot })
check(approachedStomp and approachedStompReason == "approach_stomp_after_shove"
        and stompActor.lastIntent.action == "combat_approach"
        and stompActor.lastIntent.stompFollowUp == true,
    "a shove-displaced grounded zombie is approached instead of losing the stomp follow-up")
clock = clock + 100
stompZed.square = cell:getGridSquare(9, -7, 0)
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
local retreatOne = actor("sc-shared-retreat-1", -10, 10, {})
local retreatTwo = actor("sc-shared-retreat-2", -10, 11, {})
local retreatSnapshot = {
    escapeSquares = {
        { square = cell:getGridSquare(-7, 10, 0), danger = 0 },
        { square = cell:getGridSquare(-7, 11, 0), danger = 1 },
        { square = cell:getGridSquare(-13, 10, 0), danger = 2 },
    },
}
local firstEscape, sharedPlan = SurvivorCompanion.Combat._sharedRetreatSquareForTests(
    retreatOne, { cohortKey = "party:shared-retreat" }, retreatSnapshot, nil, clock)
local secondEscape, samePlan = SurvivorCompanion.Combat._sharedRetreatSquareForTests(
    retreatTwo, { cohortKey = "party:shared-retreat" }, retreatSnapshot, nil, clock)
check(firstEscape and secondEscape and firstEscape ~= secondEscape
        and sharedPlan == samePlan and sharedPlan.directionX > 0,
    "a retreating cohort shares an escape direction while reserving distinct safe squares")
end

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
do
    -- Report 5: a combat retreat must break contact locally and never sprint to a
    -- distant remembered egress (its far map-entry route), which ran companions
    -- clean off the map when retreating. Beyond the cap it falls back to the nearby
    -- escape square.
    local capActor = actor("sc-retreat-cap", -4, -5, { inventory = inventory({ overrunBat }) })
    capActor.primary = overrunBat
    registry[capActor.id] = capActor
    local nearEscape = squares[squareKey(-4, -4, 0)]
    local farEgress = cell:getGridSquare(60, 60, 0)
    local capSnapshot = {
        threats = overrunSnapshot.threats,
        immediateAttackers = {}, allies = {}, threatCount = 3, immediateCount = 3,
        closeThreatCount = 3, occupiedThreatSectors = 3, pressure = 4.5,
        directionalPressure = 7.2, encircled = true,
        escapeSquares = { { square = nearEscape, danger = 0, score = 20 } },
        player = { available = false, danger = 0, immediateThreats = 0 },
    }
    local savedRetreatTarget = SurvivorCompanion.Navigation.retreatTarget
    local savedRequest = SurvivorCompanion.Navigation.request
    local requestedTarget
    SurvivorCompanion.Navigation.retreatTarget = function()
        return farEgress, { source = "entry_route", danger = 0 }
    end
    SurvivorCompanion.Navigation.request = function(_, target)
        requestedTarget = target
        return true, "retreating"
    end
    SurvivorCompanion.Combat.reset()
    SurvivorCompanion.Combat.update(capActor, player, { snapshot = capSnapshot })
    SurvivorCompanion.Navigation.retreatTarget = savedRetreatTarget
    SurvivorCompanion.Navigation.request = savedRequest
    check(requestedTarget == nearEscape,
        "a combat retreat caps its distance and falls back to the nearby escape square instead of a far egress")
    SurvivorCompanion.Combat.reset(capActor)
    registry[capActor.id] = nil
end
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

do
    -- 4.4: the combat engagement lease spans the worst-case gap between an actor's
    -- combat decisions so a large party stops oscillating targets, is refreshed on
    -- every offensive action, and is released when the owner disengages.
    local leaseClock = 900000
    local leaseOwner = actor("sc-lease-owner", 30, 30, { inventory = inventory({ tacticalBat }) })
    leaseOwner.primary = tacticalBat
    local leaseZed = zombie(31, 30, { attacking = true, target = leaseOwner })
    local leaseSnapshot = {
        threats = { { actor = leaseZed, square = leaseZed.square, distanceSq = 1,
            visible = true, obstructed = false, attacking = true } },
        immediateAttackers = {}, allies = {}, threatCount = 1, immediateCount = 0,
        closeImmediateCount = 0, closeThreatCount = 1, occupiedThreatSectors = 1,
        directionalPressure = 1, pressure = 0.5,
        escapeSquares = { { square = squares[squareKey(29, 30, 0)], danger = 0,
            nearestThreatSq = 4 } },
        player = { available = false, danger = 0, immediateThreats = 0 },
    }
    local emptyLeaseSnapshot = {
        threats = {}, immediateAttackers = {}, allies = {}, threatCount = 0,
        immediateCount = 0, closeThreatCount = 0, pressure = 0,
        player = { available = false, danger = 0, immediateThreats = 0 },
    }
    local leasePeer = actor("sc-lease-peer", 30, 31, { inventory = inventory({ tacticalBat }) })

    clock = leaseClock
    SurvivorCompanion.Combat.update(leaseOwner, player, { snapshot = leaseSnapshot })
    clock = leaseClock + 1000
    local heldScores = SurvivorCompanion.Combat.scoreTargets(leasePeer, player, leaseSnapshot, nil)
    check(#heldScores == 1 and heldScores[1].claimedByAlly == true,
        "the engagement lease still holds the target 1s after the owner last engaged (would lapse at 450ms)")

    clock = leaseClock + 2100
    local lapsedScores = SurvivorCompanion.Combat.scoreTargets(leasePeer, player, leaseSnapshot, nil)
    check(#lapsedScores == 1 and lapsedScores[1].claimedByAlly ~= true,
        "an unrefreshed engagement lease lapses after its window so the target frees up")

    clock = leaseClock + 3000
    SurvivorCompanion.Combat.update(leaseOwner, player, { snapshot = leaseSnapshot })
    local reheldScores = SurvivorCompanion.Combat.scoreTargets(leasePeer, player, leaseSnapshot, nil)
    check(reheldScores[1].claimedByAlly == true,
        "re-engaging refreshes the lease")
    -- The lease is released when its owner is gone, so a peer reclaims the target
    -- instead of avoiding it for the rest of the lease window.
    leaseOwner.dead = true
    local freedScores = SurvivorCompanion.Combat.scoreTargets(leasePeer, player, leaseSnapshot, nil)
    check(freedScores[1].claimedByAlly ~= true,
        "the engagement lease is released when its owner is gone so a peer can take the target")

    leaseZed.dead = true
    SurvivorCompanion.Combat.reset(leaseOwner)
    SurvivorCompanion.Combat.reset(leasePeer)
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

-- Incompatible ammunition must never trigger a reload: a 9mm box in the pack does
-- not reload a .223 rifle just because its type also contains "Bullets".
local wrongRifle = item("Base.VarmintRifle", "Weapon", {
    ranged = true, damage = 1.5, range = 10, ammo = 0, maxAmmo = 5, ammoType = "Base.223Bullets",
})
local wrongAmmo = item("Base.Bullets9mm", "Ammo")
local wrongReloader = actor("sc-wrong-reloader", 0, -6, { inventory = inventory({ wrongRifle, wrongAmmo }) })
wrongReloader.primary = wrongRifle
registry[wrongReloader.id] = wrongReloader
local wrongZed = zombie(4, -6, {})
SurvivorCompanion.Combat.update(wrongReloader, player, { snapshot = {
    threats = { { actor = wrongZed, square = wrongZed.square, distanceSq = 16, visible = true, obstructed = false, score = 30 } },
    allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 0, pressure = 0,
    player = { danger = 0, immediateThreats = 0 },
} })
check(not (wrongReloader.lastIntent and wrongReloader.lastIntent.action == "reload"),
    "incompatible ammunition never triggers a reload attempt")
registry[wrongReloader.id] = nil

(function()
    local function combatSnapshot(target)
        return {
            threats = { { actor = target, square = target.square, distanceSq = 1,
                visible = true, obstructed = false, attacking = true, score = 80 } },
            allies = {}, escapeSquares = {}, threatCount = 1, immediateCount = 1,
            closeImmediateCount = 1, closeThreatCount = 1,
            occupiedThreatSectors = 1, pressure = 1, encircled = false,
            player = { danger = 0, immediateThreats = 0 },
        }
    end
    local function rangedDoctrine(value)
        local commands = SurvivorCompanion.Commands.peek(value)
        commands.combatDoctrine = "ranged_support"
        commands.weaponPriority = "firearm"
        commands.holdFire = false
    end

    local fallbackAxe = item("Base.OperationalAxe", "Weapon", {
        damage = 2, range = 1.5, condition = 10, conditionMax = 10, sharpness = 1,
    })
    local dryRifle = item("Base.DryRifle", "Weapon", {
        ranged = true, damage = 2, range = 10, ammo = 0, maxAmmo = 5,
        ammoType = "Base.308Bullets", condition = 10, conditionMax = 10,
    })
    local fallbackActor = actor("sc-operational-fallback", 8, -2, {
        inventory = inventory({ dryRifle, fallbackAxe }),
    })
    fallbackActor.primary = dryRifle
    rangedDoctrine(fallbackActor)
    local fallbackZed = zombie(9, -2, { attacking = true, target = fallbackActor })
    local fallbackHandled = SurvivorCompanion.Combat.update(
        fallbackActor, player, { snapshot = combatSnapshot(fallbackZed) })
    check(fallbackHandled and fallbackActor.lastIntent.action == "equip_weapon"
            and fallbackActor.lastIntent.item == fallbackAxe,
        "an empty firearm without compatible ammunition falls back to usable melee")

    local brokenRifle = item("Base.BrokenRifle", "Weapon", {
        ranged = true, damage = 2, range = 10, ammo = 5, maxAmmo = 5,
        condition = 0, conditionMax = 10,
    })
    local brokenAxe = item("Base.BrokenFallbackAxe", "Weapon", {
        damage = 1.8, range = 1.5, condition = 10, conditionMax = 10,
    })
    local brokenActor = actor("sc-broken-fallback", 8, -4, {
        inventory = inventory({ brokenRifle, brokenAxe }),
    })
    brokenActor.primary = brokenRifle
    rangedDoctrine(brokenActor)
    local brokenZed = zombie(9, -4, { attacking = true, target = brokenActor })
    local brokenHandled = SurvivorCompanion.Combat.update(
        brokenActor, player, { snapshot = combatSnapshot(brokenZed) })
    check(brokenHandled and brokenActor.lastIntent.action == "equip_weapon"
            and brokenActor.lastIntent.item == brokenAxe,
        "a broken firearm cannot suppress a usable melee fallback")

    local jammedRifle = item("Base.JammedRifle", "Weapon", {
        ranged = true, damage = 2, range = 10, ammo = 0, maxAmmo = 5,
        jammed = true, condition = 10, conditionMax = 10,
    })
    local jamAxe = item("Base.JamFallbackAxe", "Weapon", {
        damage = 1.8, range = 1.5, condition = 10, conditionMax = 10,
    })
    local jamActor = actor("sc-jammed-operational", 8, -6, {
        inventory = inventory({ jammedRifle, jamAxe }),
    })
    jamActor.primary = jammedRifle
    rangedDoctrine(jamActor)
    local jamZed = zombie(9, -6, { attacking = true, target = jamActor })
    local jamHandled = SurvivorCompanion.Combat.update(
        jamActor, player, { snapshot = combatSnapshot(jamZed) })
    check(jamHandled and jamActor.lastIntent.action == "unjam",
        "a jammed firearm remains operational so combat can clear the jam; got "
            .. tostring(jamActor.lastIntent and jamActor.lastIntent.action))

    local loneDryRifle = item("Base.LoneDryRifle", "Weapon", {
        ranged = true, damage = 2, range = 10, ammo = 0, maxAmmo = 5,
        ammoType = "Base.308Bullets", condition = 10, conditionMax = 10,
    })
    local unarmedActor = actor("sc-firearm-only-dry", 8, -8, {
        inventory = inventory({ loneDryRifle }),
    })
    unarmedActor.primary = loneDryRifle
    rangedDoctrine(unarmedActor)
    -- Commands.initialize may add a keepsake; the firearm-only fixture must keep
    -- its inventory definition literal for this operational-weapon regression.
    for index = #unarmedActor.inventory.items, 1, -1 do
        if unarmedActor.inventory.items[index] ~= loneDryRifle then
            table.remove(unarmedActor.inventory.items, index)
        end
    end
    local unarmedZed = zombie(9, -8, { attacking = true, target = unarmedActor })
    local defended = SurvivorCompanion.Combat.update(
        unarmedActor, player, { snapshot = combatSnapshot(unarmedZed) })
    check(defended and unarmedActor.lastIntent.action == "shove",
        "a firearm-only actor with no ammunition chooses unarmed close defense; got "
            .. tostring(unarmedActor.lastIntent and unarmedActor.lastIntent.action)
            .. ":" .. tostring(unarmedActor.lastIntent and unarmedActor.lastIntent.item
                and unarmedActor.lastIntent.item.itemType))

    for _, value in ipairs({ fallbackActor, fallbackZed, brokenActor, brokenZed,
            jamActor, jamZed, unarmedActor, unarmedZed }) do
        if value.square and value.square.moving then
            for index = #value.square.moving, 1, -1 do
                if value.square.moving[index] == value then table.remove(value.square.moving, index) end
            end
        end
        if value.__class == "IsoZombie" then value.dead = true
        else SurvivorCompanion.Combat.reset(value) end
    end
end)()

do
-- Doctrine controls target eligibility and positioning; explicit weapon priority
-- remains independent. Ranged Support with a melee priority must not silently
-- draw a firearm behind the player's back.
local doctrineRifle = item("Base.HuntingRifle", "Weapon", {
    ranged = true, damage = 2, range = 12, ammo = 5, maxAmmo = 5,
    condition = 10, conditionMax = 10,
})
local doctrineAxe = item("Base.Axe", "Weapon", {
    damage = 2, range = 1.5, condition = 10, conditionMax = 10, sharpness = 1,
})
local doctrineFighter = actor("sc-ranged-doctrine", 0, 12, {
    inventory = inventory({ doctrineRifle, doctrineAxe }),
})
doctrineFighter.primary = doctrineAxe
registry[doctrineFighter.id] = doctrineFighter
local doctrineCommands = SurvivorCompanion.Commands.peek(doctrineFighter)
doctrineCommands.combatDoctrine = "ranged_support"
doctrineCommands.weaponPriority = "melee"
doctrineCommands.holdFire = false
local doctrineZed = zombie(0, 13, { attacking = true, target = doctrineFighter })
local doctrineSnapshot = {
    threats = { { actor = doctrineZed, square = doctrineZed.square, distanceSq = 1,
        visible = true, obstructed = false, attacking = true, score = 60 } },
    allies = {}, escapeSquares = {},
    threatCount = 1, immediateCount = 0, closeImmediateCount = 0,
    closeThreatCount = 1, occupiedThreatSectors = 1, pressure = 0,
    player = { danger = 0, immediateThreats = 0 },
}
local doctrineHandled = SurvivorCompanion.Combat.update(
    doctrineFighter, player, { snapshot = doctrineSnapshot })
check(doctrineHandled and doctrineFighter.lastIntent.action == "attack_melee"
        and doctrineFighter.lastIntent.weapon == doctrineAxe,
    "Ranged Support respects an explicit melee weapon priority instead of drawing a firearm")
doctrineZed.dead = true
SurvivorCompanion.Combat.reset(doctrineFighter)
end

check(SurvivorCompanion.Commands.issue(fellow.id, "set_group", "Alpha", player), "first group assignment")
check(SurvivorCompanion.Commands.issue(shooter.id, "set_group", "Alpha", player), "second group assignment")
local groupFollow = SurvivorCompanion.Commands.issue(fellow.id, "follow", { scope = "group", group = "Alpha" }, player)
check(groupFollow and SurvivorCompanion.Commands.peek(fellow).order == "follow"
    and SurvivorCompanion.Commands.peek(shooter).order == "follow", "group payload targets a fixed member snapshot")

do
-- R2-04: a group command that fails mid-commit must roll back completely -- command
-- state AND work-target metadata (SC_WorkKind/SC_WorkBarricadeSide) -- and must not
-- apply the cross-subsystem base-duty release for any member (that release now runs
-- only after every member has persisted).
SurvivorCompanion.BaseLife.reset()
SurvivorCompanion.BaseLife.create(cell:getGridSquare(0, 0, 0), "Rollback Camp")
check(SurvivorCompanion.Commands.issue(fellow.id, "base_duty", nil, player)
        and SurvivorCompanion.Commands.peek(fellow).order == "base_duty",
    "fellow is placed on base duty for the rollback fixture")
fellow.modData.SC_WorkKind = "barricade"
fellow.modData.SC_WorkBarricadeSide = "same"
shooter.modDataProxy = setmetatable({}, {
    __newindex = function() error("injected stable write failure") end,
    __index = function(_, key) return shooter.modData[key] end,
})
local dutyReleases = 0
local realSetDuty = SurvivorCompanion.BaseLife.setDuty
SurvivorCompanion.BaseLife.setDuty = function(...)
    dutyReleases = dutyReleases + 1
    return realSetDuty(...)
end
local rolledOk, rolledReason = SurvivorCompanion.Commands.issue(fellow.id, "follow",
    { scope = "group", group = "Alpha" }, player)
SurvivorCompanion.BaseLife.setDuty = realSetDuty
shooter.modDataProxy = nil
check(not rolledOk and string.find(tostring(rolledReason), "rollback", 1, true) ~= nil
        and SurvivorCompanion.Commands.peek(fellow).order == "base_duty"
        and fellow.modData.SC_WorkKind == "barricade"
        and fellow.modData.SC_WorkBarricadeSide == "same"
        and dutyReleases == 0,
    "a failed group commit rolls back command state and work metadata and releases no base duty")
fellow.modData.SC_WorkKind = nil
fellow.modData.SC_WorkBarricadeSide = nil
SurvivorCompanion.BaseLife.reset()
SurvivorCompanion.Commands.issue(fellow.id, "follow", nil, player)
end

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
    local decisionScavenger = actor("sc-decision-scavenger", 0, 2, {})
    registry[decisionScavenger.id] = decisionScavenger
    SurvivorCompanion.Commands.issue(decisionScavenger.id, "set_scavenge", true, player)
    local commandView = SurvivorCompanion.Commands.peek(decisionScavenger)
    local safeSnapshot = {
        threats = {}, immediateAttackers = {}, allies = {}, escapeSquares = {},
        threatCount = 0, immediateCount = 0, pressure = 0, indoors = false,
        player = { danger = 0, immediateThreats = 0 },
    }
    local savedAutonomy = SurvivorCompanion.Autonomy
    SurvivorCompanion.Autonomy = nil
    player.moving = false
    local stoppedCandidates = SurvivorCompanion.Decision._evaluateForTests(
        decisionScavenger, player, safeSnapshot, commandView,
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    check(stoppedCandidates[1] and stoppedCandidates[1].kind == "scavenge",
        "checked scavenging beats a no-op formation hold while the player is stopped")
    player.moving = true
    local movingCandidates = SurvivorCompanion.Decision._evaluateForTests(
        decisionScavenger, player, safeSnapshot, commandView,
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    check(movingCandidates[1] and movingCandidates[1].kind == "follow",
        "opportunistic scavenging never pulls a companion away from a moving leader")
    player.moving = false
    local originalEncounterPeek = SurvivorCompanion.Encounter.peek
    SurvivorCompanion.Encounter.peek = function(subject)
        if subject == decisionScavenger then return { containerSearch = {} } end
        return originalEncounterPeek(subject)
    end
    local activeCandidates = SurvivorCompanion.Decision._evaluateForTests(
        decisionScavenger, player, safeSnapshot, commandView,
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    SurvivorCompanion.Encounter.peek = originalEncounterPeek
    SurvivorCompanion.Autonomy = savedAutonomy
    check(activeCandidates[1] and activeCandidates[1].kind == "scavenge"
            and activeCandidates[1].score >= 76,
        "an active bounded scavenging search retains enough priority to finish")
    SurvivorCompanion.Commands.reset(decisionScavenger)
    registry[decisionScavenger.id] = nil
end


do
    local formationClock = clock
    local formationFood = item("Base.CannedCarrots2", "Food")
    local formationLooter = actor("sc-formation-looter", 1, 3, {})
    registry[formationLooter.id] = formationLooter
    formationLooter.hunger = 0.95
    containerObject(formationLooter.square, { formationFood })
    SurvivorCompanion.Commands.issue(formationLooter.id, "set_scavenge", true, player)
    SurvivorCompanion.Performance.reset()
    SurvivorCompanion.Performance.beginFrame(2, clock)
    SurvivorCompanion.Encounter.tryScavenge(formationLooter, player, {
        snapshot = { threats = {}, immediateCount = 0, threatCount = 0,
            pressure = 0, escapeSquares = {} },
    })
    clock = clock + 16
    SurvivorCompanion.Performance.endFrame(1, false)
    local searching = SurvivorCompanion.Encounter.peek(formationLooter)
    player.moving = true
    local rejoin, rejoinReason = SurvivorCompanion.Encounter.formationRejoinRequired(
        formationLooter, player, SurvivorCompanion.Commands.peek(formationLooter))
    SurvivorCompanion.Encounter.cancelScavenge(formationLooter, rejoinReason)
    searching = SurvivorCompanion.Encounter.peek(formationLooter)
    check(rejoin and rejoinReason == "formation_leader_moving"
            and searching.task == nil and searching.selectionJob == nil
            and searching.containerSearch == nil,
        "a moving formation leader immediately cancels an in-progress scavenging search")
    player.moving = false
    SurvivorCompanion.Encounter.reset(formationLooter)
    SurvivorCompanion.Commands.reset(formationLooter)
    registry[formationLooter.id] = nil
    SurvivorCompanion.Performance.reset()
    clock = formationClock
end

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
local weaponBagInventory = inventory()
weaponBagInventory.capacity = 18
local weaponBag = item("Base.Bag_WeaponRoot", "Container", {
    nestedInventory = weaponBagInventory, bagCapacity = 18, weightReduction = 80,
    bodyLocation = "Back", equipLocation = "Back", weight = 1,
})
local giftedBreadKnife = item("Base.BreadKnife", "Weapon", { weight = 0.3 })
local weaponCarrier = actor("sc-logistics-weapon-root", 8, 3, {
    inventory = inventory({ weaponBag, giftedBreadKnife }),
})
weaponCarrier:setWornItem("Back", weaponBag)
local weaponAudit = SurvivorCompanion.Logistics.status(weaponCarrier)
check(weaponAudit.packMove == nil
        and weaponCarrier.inventory:contains(giftedBreadKnife)
        and not weaponBagInventory:contains(giftedBreadKnife),
    "newly gifted weapons remain at inventory root instead of entering a packing loop")
SurvivorCompanion.Logistics.reset(weaponCarrier)
end

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

local stalledBagInventory = inventory()
stalledBagInventory.capacity = 18
local stalledBag = item("Base.Bag_StalledPack", "Container", {
    nestedInventory = stalledBagInventory, bagCapacity = 18, weightReduction = 80,
    bodyLocation = "Back", equipLocation = "Back", weight = 1,
})
local stalledFood = item("Base.CannedCornStalledPack", "Food", { weight = 1 })
local stalledActor = actor("sc-logistics-stalled-pack", 10, 3, {
    inventory = inventory({ stalledBag, stalledFood }),
})
stalledActor:setWornItem("Back", stalledBag)
phasedState = "active"
local stalledStarted = SurvivorCompanion.Logistics.update(stalledActor, nil, { snapshot = {
    threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
} })
stalledActor.worldX = stalledActor:getX() + 1
local stalledContinued, stalledReason = SurvivorCompanion.Logistics.update(
    stalledActor, nil, { snapshot = {
        threats = {}, immediateCount = 0, threatCount = 0, pressure = 0,
    } })
check(stalledStarted and not stalledContinued and stalledReason == "logistics_action_cancelled"
        and stalledActor.inventory:contains(stalledFood)
        and not stalledBagInventory:contains(stalledFood)
        and SurvivorCompanion.ActionSupervisor.snapshot(stalledActor).phase == "idle"
        and SurvivorCompanion.ActionSupervisor.reservationCount(stalledActor) == 0,
    "packing cancels and rolls back as soon as its protected pose moves")
SurvivorCompanion.Logistics.reset(stalledActor)
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

local redDigitalWatch = item("Base.WristWatch_Left_DigitalRed", "Clothing", {
    bodyLocation = "LeftWrist", condition = 10, conditionMax = 10,
})
local watchScore = SurvivorCompanion.Logistics.itemNeedScore(
    clothingLooter, redDigitalWatch)
local watchAccepted, watchReason = SurvivorCompanion.Logistics.canTake(
    clothingLooter, redDigitalWatch, "clothing")
check(SurvivorCompanion.Logistics.clothingScore(redDigitalWatch) == -math.huge
        and watchScore == 0 and not watchAccepted and watchReason == "cosmetic_wearable",
    "cosmetic watches never become clothing-upgrade scavenging targets")

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

do
    local recruit = actor("sc-recruit-sound", -3, 4, { recruited = false })
    recruit.modData.SC_Recruited = false
    local record = { id = recruit.id, actor = recruit, recruited = false,
        state = { order = { current = "wander" } } }
    registry[recruit.id] = record
    check(SurvivorCompanion.Commands.restore(recruit, record),
        "recruitment-sound fixture restores a neutral survivor")
    local before = #uiSounds
    local accepted, reason = SurvivorCompanion.Commands.issue(
        recruit.id, "recruit", nil, player)
    check(accepted and reason == "recruited" and #uiSounds == before + 1
            and uiSounds[#uiSounds] == "UIAchievement",
        "successful permanent recruitment plays one vanilla UI achievement cue")
    local again, againReason = SurvivorCompanion.Commands.issue(
        recruit.id, "recruit", nil, player)
    check(again and againReason == "already_recruited" and #uiSounds == before + 1,
        "an already-recruited survivor cannot replay the recruitment cue")
    SurvivorCompanion.Commands.reset(recruit)
    registry[recruit.id] = nil
end

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

do
    -- 2.4: self-medicine and rescue-medicine share kind "medical" but must be
    -- distinct decision identities, so hysteresis and fallback treat them as
    -- separate decisions (self-medicine with no action can now fall back to a
    -- rescue instead of being blocked as the same kind).
    local savedAssess = SurvivorCompanion.Medical.assess
    local rescuePatient = { __rescuePatient = true }
    SurvivorCompanion.Medical.assess = function(target)
        if target == rescuePatient then
            return { critical = true, bleedingCount = 2, downed = true, wounds = {} }
        end
        return { wounds = {} }
    end
    local identityCandidates = SurvivorCompanion.Decision._evaluateForTests(
        fellow, rescuePatient,
        { threats = {}, threatCount = 0, immediateCount = 0, allies = {} },
        { recruited = true },
        { downed = true, health = 8, wounds = {} }, {}, {}, 1000)
    SurvivorCompanion.Medical.assess = savedAssess
    local selfKey, rescueKey, medicalCount = nil, nil, 0
    for _, candidate in ipairs(identityCandidates) do
        if candidate.kind == "medical" then
            medicalCount = medicalCount + 1
            if candidate.detail and candidate.detail.rescue then rescueKey = candidate.key
            else selfKey = candidate.key end
        end
    end
    check(medicalCount == 2 and selfKey == "medical"
            and rescueKey ~= nil and rescueKey ~= selfKey
            and string.sub(rescueKey, 1, 14) == "medical:rescue",
        "self-medicine and rescue-medicine share a kind but are distinct decision keys (review 2.4)")
end

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
check(decisionAfterDue(retreatActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 101) and string.find(tostring(SurvivorCompanion.Decision.peek(retreatActor).intent),
        "safety_guarded_hold:retreat", 1, true) ~= nil,
    "a rejected survival retreat becomes a stationary safety hold instead of routine work")

local roomActor = actor("sc-room-sweep", -6, 1, {})
roomActor.square.room = { name = "rejected-sweep-room" }
registry[roomActor.id] = roomActor
check(SurvivorCompanion.Commands.issue(roomActor.id, "check_room", { square = roomActor.square }, player),
    "room-check command is accepted before sweep rejection test")
roomActor.rejectActions = { room_sweep = true }
check(not decisionAfterDue(roomActor, player, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0, escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and not SurvivorCompanion.Decision.peek(roomActor).roomCheckAt,
    "room sweep records no start time when its executor action is rejected")
local outdoorRoomActor = actor("sc-room-outdoor-reject", -7, 1, {})
outdoorRoomActor.square.room = nil
registry[outdoorRoomActor.id] = outdoorRoomActor
local outdoorRoomAccepted, outdoorRoomReason = SurvivorCompanion.Commands.issue(
    outdoorRoomActor.id, "check_room", { square = outdoorRoomActor.square }, player)
check(not outdoorRoomAccepted and outdoorRoomReason == "room_check_requires_room",
    "Check Room is rejected outside instead of becoming a generic move order")
registry[outdoorRoomActor.id] = nil

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
check(gatedFallback
        and string.find(tostring(SurvivorCompanion.Decision.peek(fallbackActor).intent),
            "safety_guarded_hold:medical", 1, true) ~= nil,
    "failed emergency medicine holds defensively until the combat fallback is due")

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
roomStayActor.square.room = { name = "return-order-room" }
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
    if command == "finish_room_check" then return false, "mock_room_finish_rejected" end
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
    "room sweep starts before its delayed return-order transition")
clock = clock + 1601
local roomStayAccepted, roomStayReason = SurvivorCompanion.Decision.update(roomStayActor, transitionPlayer, roomStayRuntime)
local roomReportCalls = roomStayActor.speechCalls or 0
local roomDecisionState = SurvivorCompanion.Decision.peek(roomStayActor)
SurvivorCompanion.Commands.issue = originalCommandIssue
SurvivorCompanion.Navigation.request = originalTransitionNavigation
check(not roomStayAccepted and roomStayReason == "room_check_finish_rejected:mock_room_finish_rejected"
    and SurvivorCompanion.Commands.peek(roomStayActor).order == "check_room"
    and roomDecisionState.roomCheckAt ~= nil and roomDecisionState.roomCheckReported == true,
    "room-check completion propagates return-order rejection and retains one-shot report state")
local roomReturned, roomReturnedReason
for _ = 1, 4 do
    clock = clock + 201
    roomReturned, roomReturnedReason = SurvivorCompanion.Decision.update(
        roomStayActor, transitionPlayer, roomStayRuntime)
    if roomReturnedReason ~= "deferred" then break end
end
check(roomReturned and SurvivorCompanion.Commands.peek(roomStayActor).order == "follow"
        and SurvivorCompanion.Decision.peek(roomStayActor).roomCheckAt == nil
        and (roomStayActor.speechCalls or 0) == roomReportCalls,
    "completed room checks report once and restore the companion's prior stable order: "
        .. tostring(roomReturnedReason))

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
clock = clock + 4000
signalActor.lastEmote = nil
local alternateDistantThreat = zombie(46, 21, {})
SurvivorCompanion.Decision.update(signalActor, signalPlayer, {
    snapshot = {
        threats = { { actor = alternateDistantThreat, distanceSq = 37,
            visible = true, score = 21 } },
        immediateAttackers = {}, threatCount = 1, immediateCount = 0, pressure = 0.35,
        escapeSquares = {}, allies = {}, player = { actor = signalPlayer, danger = 0 },
    },
})
check(signalActor.lastEmote == nil
        and SurvivorCompanion.Dialogue.lastSpokenTopic(signalActor) == "signal.one",
    "a different top-ranked zombie cannot restart the same warning hand signal during cooldown")
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
local protectedArea = BaseLife.active().zones[1]
do
    local fourCorners = {
        { kind = "area", x1 = 0, y1 = 0, x2 = 1, y2 = 1, z = 0 },
        { kind = "area", x1 = 4, y1 = 0, x2 = 5, y2 = 1, z = 0 },
        { kind = "area", x1 = 0, y1 = 4, x2 = 1, y2 = 5, z = 0 },
        { kind = "area", x1 = 4, y1 = 4, x2 = 5, y2 = 5, z = 0 },
    }
    local adjacent = {
        { kind = "area", x1 = 0, y1 = 0, x2 = 2, y2 = 5, z = 0 },
        { kind = "area", x1 = 3, y1 = 0, x2 = 5, y2 = 5, z = 0 },
    }
    local lShape = {
        { kind = "area", x1 = 0, y1 = 0, x2 = 5, y2 = 1, z = 0 },
        { kind = "area", x1 = 0, y1 = 2, x2 = 1, y2 = 5, z = 0 },
    }
    local target = { x1 = 0, y1 = 0, x2 = 5, y2 = 5, z = 0 }
    check(not BaseLife.zoneInsideAreaUnion(target, fourCorners)
            and BaseLife.zoneInsideAreaUnion(target, adjacent)
            and not BaseLife.zoneInsideAreaUnion(target, lShape),
        "zone containment accepts a complete adjacent union and rejects corner islands or an L-shaped hole")
end
local areaStarted = BaseLife.beginZone("area", cell:getGridSquare(1, 1, 0))
local areaFinished, removableArea = BaseLife.finishZone(
    cell:getGridSquare(2, 2, 0), "Temporary extension")
local areaRemoved = areaFinished and BaseLife.removeZone(removableArea.id)
local lastAreaRemoved, lastAreaReason = BaseLife.removeZone(protectedArea.id)
check(areaStarted and areaFinished and areaRemoved
        and not lastAreaRemoved and lastAreaReason == "last_base_area",
    "base zone management can remove an extension but protects the last camp area: "
        .. tostring(areaStarted) .. "/" .. tostring(areaFinished) .. "/"
        .. tostring(areaRemoved) .. "/" .. tostring(lastAreaRemoved) .. "/"
        .. tostring(lastAreaReason))
check(BaseLife.beginZone("quarantine", cell:getGridSquare(1, 1, 0))
    and BaseLife.finishZone(cell:getGridSquare(3, 3, 0), "Quiet room"),
    "two-corner quarantine zoning commits inside the camp boundary")
do
    local extensionX = protectedArea.x2 + 1
    local addedArea, extension = BaseLife.beginZone("area",
        cell:getGridSquare(extensionX, 2, 0))
    if addedArea then addedArea, extension = BaseLife.finishZone(
        cell:getGridSquare(extensionX + 1, 3, 0), "Workshop extension") end
    local addedWork, workZone = BaseLife.beginZone("work",
        cell:getGridSquare(extensionX, 2, 0))
    if addedWork then addedWork, workZone = BaseLife.finishZone(
        cell:getGridSquare(extensionX + 1, 3, 0), "Edge workshop") end
    local removedInUse, inUseReason = false, "missing_extension"
    if extension then removedInUse, inUseReason = BaseLife.removeZone(extension.id) end
    local cleaned = workZone and BaseLife.removeZone(workZone.id)
        and BaseLife.removeZone(extension.id)
    check(addedArea and addedWork and not removedInUse
            and inUseReason == "base_area_in_use" and cleaned,
        "an area cannot be removed while a configured child zone depends on its coverage: "
            .. tostring(addedArea) .. "/" .. tostring(addedWork) .. "/"
            .. tostring(removedInUse) .. "/" .. tostring(inUseReason) .. "/"
            .. tostring(cleaned))
end
local store = { square = campSquare, objectIndex = #campSquare.objects, modData = {},
    container = inventory({ item("Base.Plank", "Material") }) }
function store:getSquare() return self.square end
function store:getX() return self.square.x end
function store:getY() return self.square.y end
function store:getZ() return self.square.z end
function store:getObjectIndex() return self.objectIndex end
function store:getContainer() return self.container end
function store:getModData() return self.modData end
campSquare.objects[#campSquare.objects + 1] = store
check(BaseLife.registerStorage(store, "construction"),
    "world container can be designated as classified camp storage")
local storageRow = BaseLife.storageRows()[1]
do
    local originalIndex, originalListIndex = store.objectIndex, nil
    for index, object in ipairs(campSquare.objects) do
        if object == store then originalListIndex = index break end
    end
    local lookalike = {
        square = campSquare, objectIndex = originalIndex, modData = {},
        container = inventory({ item("Base.Plank", "Material") }),
    }
    function lookalike:getSquare() return self.square end
    function lookalike:getX() return self.square.x end
    function lookalike:getY() return self.square.y end
    function lookalike:getZ() return self.square.z end
    function lookalike:getObjectIndex() return self.objectIndex end
    function lookalike:getContainer() return self.container end
    function lookalike:getModData() return self.modData end
    table.insert(campSquare.objects, originalListIndex, lookalike)
    store.objectIndex = originalIndex + 1
    local reboundAfterInsert = BaseLife.resolveObject(storageRow)
    table.remove(campSquare.objects, originalListIndex + 1)
    local replacement, replacementReason = BaseLife.resolveObject(storageRow)
    table.insert(campSquare.objects, originalListIndex + 1, store)
    table.remove(campSquare.objects, originalListIndex)
    store.objectIndex = originalIndex
    local restoredObject = BaseLife.resolveObject(storageRow)
    local legacyObject, legacyReason = BaseLife.resolveObject({
        x = storageRow.x, y = storageRow.y, z = storageRow.z,
        objectIndex = storageRow.objectIndex,
    })
    check(type(storageRow.objectId) == "string" and reboundAfterInsert == store
            and replacement == nil and replacementReason == "object_identity_mismatch"
            and restoredObject == store and legacyObject == nil
            and legacyReason == "legacy_object_identity_unavailable",
        "base objects retain persistent identity across index shifts and fail closed for replacements or legacy index-only records")
end
check(BaseLife.setReserve(storageRow.id, "*", 2)
        and BaseLife.setStorageCategory(storageRow.id, "tools")
        and BaseLife.summary().storageRows[1].category == "tools"
        and BaseLife.summary().storageRows[1].reserve == 2
        and BaseLife.setStorageCategory(storageRow.id, "construction"),
    "base storage management changes category and general withdrawal reserve")
local visualRows = BaseLife.visualRows()
check(visualRows.configured == true and #visualRows.zoneRows == 2
        and #visualRows.storageRows == 1
        and visualRows.storageRows[1].category == "construction"
        and visualRows.storageRows[1].objectIndex == store.objectIndex,
    "base visualization gets a lightweight object-reference read model")
local visualStorage = visualRows.storageRows[1]
local resolvedVisualStorage, resolvedVisualReason = BaseLife.resolveObject(visualStorage)
check(visualStorage.objectId == storageRow.objectId
        and visualStorage.objectSignature == storageRow.objectSignature
        and resolvedVisualStorage == store and resolvedVisualReason == nil,
    "base visualization preserves the registered storage identity required by the real resolver")
local maintenanceObject = { square = campSquare, objectIndex = #campSquare.objects, modData = {} }
function maintenanceObject:getSquare() return self.square end
function maintenanceObject:getX() return self.square.x end
function maintenanceObject:getY() return self.square.y end
function maintenanceObject:getZ() return self.square.z end
function maintenanceObject:getObjectIndex() return self.objectIndex end
function maintenanceObject:getModData() return self.modData end
campSquare.objects[#campSquare.objects + 1] = maintenanceObject
local maintenanceRegistered, maintenanceRow = BaseLife.registerMaintenanceTarget(
    maintenanceObject, "maintain")
check(maintenanceRegistered
        and BaseLife.setMaintenanceTargetEnabled(maintenanceRow.id, false)
        and BaseLife.summary().maintenanceRows[1].enabled == false,
    "maintenance targets can be disabled without deleting their world object")
local removableMaintenance = { square = campSquare, objectIndex = #campSquare.objects, modData = {} }
function removableMaintenance:getSquare() return self.square end
function removableMaintenance:getX() return self.square.x end
function removableMaintenance:getY() return self.square.y end
function removableMaintenance:getZ() return self.square.z end
function removableMaintenance:getObjectIndex() return self.objectIndex end
function removableMaintenance:getModData() return self.modData end
campSquare.objects[#campSquare.objects + 1] = removableMaintenance
local secondMaintenance, removableMaintenanceRow = BaseLife.registerMaintenanceTarget(
    removableMaintenance, "barricade")
check(secondMaintenance and BaseLife.removeMaintenanceTarget(removableMaintenanceRow.id)
        and #BaseLife.summary().maintenanceRows == 1,
    "maintenance management can remove one tracked target without altering the object")
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
local blockedJob, blockedReason = BaseLife.blockJob(
    baseJob.id, fellow.id, "fixture_blocker", 1000)
local retriedJob, retryReason = BaseLife.retryJob(baseJob.id)
check(blockedJob and retriedJob and baseJob.state == "pending"
        and baseJob.blocker == nil and baseJob.reservedBy == nil,
    "blocked base jobs expose a retry operation that clears their blocker: "
        .. tostring(blockedReason) .. "/" .. tostring(retryReason))
local queuedCancel, cancelledJob = BaseLife.enqueueJob({
    type = "repair", priority = 1, target = { x = 2, y = 2, z = 0 },
})
check(queuedCancel and BaseLife.cancelJob(cancelledJob.id)
        and cancelledJob.state == "cancelled",
    "queued base jobs can be cancelled explicitly")
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
check(BaseLife.setStorageCategory(storageRow.id, "tools"),
    "managed storage category is staged for persistence")
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
    and #BaseLife.storageRows("tools", true) == 1
    and BaseLife.summary().storageRows[1].reserve == 2
    and #BaseLife.summary().maintenanceRows == 1
    and BaseLife.summary().maintenanceRows[1].enabled == false
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
do
    -- Playtest 6: a companion whose infection crisis ends in death must drop out of
    -- the active infection-crisis list instead of lingering as a dead entry.
    local dyingBitten = actor("sc-crisis-dead", 4, 3, {
        body = bodyDamage(70, { bodyPart({ name = "Torso", isBitten = true }) }),
    })
    dyingBitten.body.infected, dyingBitten.body.infectionLevel = true, 40
    registry[dyingBitten.id] = dyingBitten
    Crisis.pulse(player, clock)
    local before = 0
    for _, row in ipairs(Crisis.summary().rows) do
        if row.subjectId == dyingBitten.id then before = before + 1 end
    end
    dyingBitten.dead = true
    Crisis.pulse(player, clock)
    local after = 0
    for _, row in ipairs(Crisis.summary().rows) do
        if row.subjectId == dyingBitten.id then after = after + 1 end
    end
    check(before == 1 and after == 0,
        "a dead companion's resolved infection crisis drops out of the active list")
    registry[dyingBitten.id] = nil
end
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
Dialogue.reset()
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
do
    local savedHour, savedRain, savedFog, savedClock = worldHour,
        rainIntensity, fogIntensity, clock
    local settings = SurvivorCompanion.Config.values
    local savedPulse, savedActorCooldown, savedGroupCooldown =
        settings.ambientDialoguePulseMs, settings.ambientDialogueActorCooldownMs,
        settings.ambientDialogueGroupCooldownMs
    settings.ambientDialoguePulseMs = 1
    settings.ambientDialogueActorCooldownMs = 0
    settings.ambientDialogueGroupCooldownMs = 0
    local quiet = { threats = {}, immediateAttackers = {}, threatCount = 0,
        immediateCount = 0, pressure = 0, player = { danger = 0 } }
    local commands = SurvivorCompanion.Commands.peek(fellow)
    local function speakAmbient()
        local spoken, topic, line = Dialogue.ambientPulse(
            fellow, player, quiet, commands, clock)
        if not spoken and topic == "ambient_not_due" then
            clock = clock + 2
            spoken, topic, line = Dialogue.ambientPulse(
                fellow, player, quiet, commands, clock)
        end
        return spoken, topic, line
    end
    worldHour, rainIntensity, fogIntensity = 7, 0, 0
    local morning, morningTopic = speakAmbient()
    clock, worldHour = clock + 2, 19
    local dusk, duskTopic = speakAmbient()
    clock, worldHour, rainIntensity = clock + 2, 12, 0.5
    local rain, rainTopic = speakAmbient()
    clock, fogIntensity = clock + 2, 0.7
    local fog, fogTopic = speakAmbient()
    clock = clock + 2
    local duplicate, duplicateReason = speakAmbient()
    check(morning and morningTopic == "ambient.morning"
            and dusk and duskTopic == "ambient.dusk"
            and rain and rainTopic == "ambient.rain"
            and fog and fogTopic == "ambient.fog"
            and not duplicate and duplicateReason == "ambient_nothing_new"
            and Dialogue.poolSize("ambient.morning", fellow, commands) >= 7
            and Dialogue.poolSize("ambient.dusk", fellow, commands) >= 7
            and Dialogue.poolSize("ambient.rain", fellow, commands) >= 7
            and Dialogue.poolSize("ambient.fog", fellow, commands) >= 7,
        "safe companions make varied once-per-event morning, dusk, rain, and fog observations")
    settings.ambientDialoguePulseMs = savedPulse
    settings.ambientDialogueActorCooldownMs = savedActorCooldown
    settings.ambientDialogueGroupCooldownMs = savedGroupCooldown
    worldHour, rainIntensity, fogIntensity, clock = savedHour, savedRain, savedFog, savedClock
    Dialogue.reset()
end
do
    local savedHealth = fellow.body.health
    local savedInfected = fellow.body.infected
    local savedInfectionLevel = fellow.body.infectionLevel
    local mortalityCommands = SurvivorCompanion.Commands.peek(fellow)
    local savedTrust, savedBond = mortalityCommands.trust, mortalityCommands.bond
    mortalityCommands.trust, mortalityCommands.bond = 100, 100
    check(Dialogue.poolSize("lastwords.pinned", fellow, {}) >= 25
            and Dialogue.poolSize("lastwords.zombies", fellow, {}) >= 25
            and Dialogue.poolSize("lastwords.health", fellow, {}) >= 25
            and Dialogue.poolSize("lastwords.turning", fellow, {}) >= 25,
        "every mortality circumstance has at least twenty-five voice-matched lines")

    Dialogue.reset(fellow)
    local pinned, pinnedLine, pinnedDetail = Dialogue.sayLastWords(fellow, "pinned", player)
    local pinnedAgain, pinnedReason = Dialogue.sayLastWords(fellow, "pinned", player)
    check(pinned and type(pinnedLine) == "string"
            and Dialogue.lastSpokenTopic(fellow) == "lastwords.pinned"
            and pinnedDetail.relationshipTier == "family" and pinnedDetail.poolSize >= 28
            and not pinnedAgain and pinnedReason == "pinned_words_on_cooldown",
        "a pinned companion uses relationship-specific pleas without repeating every combat tick")

    Dialogue.reset(fellow)
    fellow.body.health, fellow.body.infected, fellow.body.infectionLevel = 10, false, 0
    local failing, failingLine = Dialogue.monitorMortality(fellow, player)
    local failingAgain, failingReason = Dialogue.monitorMortality(fellow, player)
    check(failing and type(failingLine) == "string"
            and string.find(failingLine, "%1", 1, true) == nil
            and Dialogue.lastSpokenTopic(fellow) == "lastwords.health"
            and not failingAgain and failingReason == "critical_words_already_spoken",
        "terminal non-zombie health loss receives one personalized farewell per episode")

    fellow.body.health = 50
    Dialogue.monitorMortality(fellow, player)
    fellow.body.health = 10
    clock = clock + 1
    local bitten, bittenLine = Dialogue.monitorMortality(fellow, player, "zombie")
    check(bitten and type(bittenLine) == "string"
            and Dialogue.lastSpokenTopic(fellow) == "lastwords.zombies",
        "a recent zombie wound selects the distinct zombie-death farewell pool")

    Dialogue.reset(fellow)
    fellow.body.health, fellow.body.infected, fellow.body.infectionLevel = 100, true, 98
    local turning, turningLine = Dialogue.monitorMortality(fellow, player)
    local turningAgain, turningReason = Dialogue.monitorMortality(fellow, player)
    check(turning and type(turningLine) == "string"
            and Dialogue.lastSpokenTopic(fellow) == "lastwords.turning"
            and not turningAgain and turningReason == "turning_words_already_spoken",
        "terminal Knox conversion has its own one-time goodbye while identity remains intact")

    fellow.body.health = savedHealth
    fellow.body.infected = savedInfected
    fellow.body.infectionLevel = savedInfectionLevel
    mortalityCommands.trust, mortalityCommands.bond = savedTrust, savedBond
    Dialogue.reset(fellow)
end
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
do
    -- A companion that has accumulated many relationship memories must still produce
    -- a roster summary. The old summary copied the whole memories array, nested past
    -- the summary depth budget, so it threw "stable value limit exceeded" on every UI
    -- refresh once ~13 memories built up -- breaking that companion's roster entry.
    local memoryHeavy = SurvivorCompanion.Commands.peek(closeFriend)
    memoryHeavy.memories = type(memoryHeavy.memories) == "table" and memoryHeavy.memories or {}
    for index = 1, 20 do
        memoryHeavy.memories[#memoryHeavy.memories + 1] = {
            kind = "event", impact = index, subjectName = "friend-" .. index,
            text = "shared moment " .. index,
        }
    end
    local expectedCount = #memoryHeavy.memories
    local describedOk, memoryRich = pcall(SurvivorCompanion.Commands.describe, closeFriend.id, player)
    check(describedOk and type(memoryRich) == "table"
            and memoryRich.memoryCount == expectedCount
            and memoryRich.memories == nil,
        "a companion with many memories still yields a valid roster summary via a bounded memory count")
end
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
    and SurvivorCompanion.Decision._delegateForTests(
        { kind = griefIntent.kind, detail = griefIntent }, closeFriend, player,
        { snapshot = { threatCount = 0 } }, closeState, { threatCount = 0 }, {})
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
    local pristine = Factions.export()
    local serializable, serialReason = SurvivorCompanion.StableValue.copyStrict(pristine, {
        maxDepth = 16, maxEntries = 131072, path = "$.factions",
    })
    check(type(pristine) == "table"
            and pristine.lastWorldSpawnDay == nil
            and pristine.lastProductionCheckDay == nil
            and serializable ~= nil,
        "a fresh faction export omits internal infinite day sentinels: "
            .. tostring(serialReason))
end
do
    local function fakeStreet(name, points)
        local street = { name = name, points = points }
        function street:getTranslatedText() return self.name end
        function street:getUntranslatedText() return self.name end
        function street:getNumPoints() return #self.points end
        function street:getPointX(index) return self.points[index + 1].x end
        function street:getPointY(index) return self.points[index + 1].y end
        function street:getMinX()
            local result = math.huge
            for _, point in ipairs(self.points) do result = math.min(result, point.x) end
            return result
        end
        function street:getMinY()
            local result = math.huge
            for _, point in ipairs(self.points) do result = math.min(result, point.y) end
            return result
        end
        function street:getMaxX()
            local result = -math.huge
            for _, point in ipairs(self.points) do result = math.max(result, point.x) end
            return result
        end
        function street:getMaxY()
            local result = -math.huge
            for _, point in ipairs(self.points) do result = math.max(result, point.y) end
            return result
        end
        return street
    end
    local data = { streets = {
        fakeStreet("Far Road", { { x = 50, y = 50 }, { x = 100, y = 50 } }),
        fakeStreet("Knox Avenue", { { x = 0, y = 5 }, { x = 10, y = 5 } }),
    } }
    function data:getStreetCount() return #self.streets end
    function data:getStreetByIndex(index) return self.streets[index + 1] end
    local api = { data = { data } }
    function api:getStreetDataCount() return #self.data end
    function api:getStreetDataByIndex(index) return self.data[index + 1] end
    local nearest = Factions._nearestStreetFromApiForTests(api, 2, 2)
    check(nearest and nearest.name == "Knox Avenue" and nearest.distance == 3
        and nearest.x == 2 and nearest.y == 5,
        "faction locations select the nearest named map street by polyline distance")
end
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
            name = "Household near 2, 2", lifecycle = "settled", standing = "Tolerated",
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
local migratedIdentity = Factions.summary("faction-test")
local migratedName = migratedIdentity and migratedIdentity.name
check(type(migratedName) == "string" and string.sub(migratedName, 1, 4) == "The "
    and not string.find(migratedName, "2, 2", 1, true)
    and migratedIdentity.location.coordinates.x == 2
    and migratedIdentity.location.coordinates.y == 2
    and migratedIdentity.location.coordinates.z == 0,
    "legacy coordinate names migrate to thematic names with separate coordinates")
local exportedIdentity = Factions.export().groups["faction-test"]
check(exportedIdentity.name == migratedName
    and exportedIdentity.location.coordinates.x == 2,
    "migrated faction identity and location persist in the save document")
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
check(Factions.summary("faction-test").name == migratedName
    and Factions.summary("faction-test-two").name == "Second test household",
    "generated faction names are deterministic and custom names remain untouched")
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
registry[residentOne.id] = { id = residentOne.id, actor = residentOne,
    factionId = group.id, factionRole = group.members[1].role }
registry[residentTwo.id] = { id = residentTwo.id, actor = residentTwo,
    factionId = group.id, factionRole = group.members[2].role }

do
    local entrySquare = cell:getGridSquare(1, 2, 0)
    local outsideSquare = cell:getGridSquare(0, 2, 0)
    local previousObjects = entrySquare.objects
    local entryDoor = { square = entrySquare }
    function entryDoor:getOppositeSquare() return outsideSquare end
    entrySquare.objects = { entryDoor }
    local previousStanding, previousLifecycle = group.standing, group.lifecycle
    local previousPersonality = group.life.personality.primary
    group.standing, group.lifecycle = "Wary", "settled"
    group.life.personality.primary = "Paranoid"
    group.life.nextPulseAt = 0
    local meetingPoint = Life._entryPositionForTests(group)
    local pulsed = Life.pulseGroup(group, player, clock)
    local representativeIntent = Life.intentFor(residentOne, group, player, {})
    local previousSquare = residentOne.square
    residentOne.square = outsideSquare
    local heldAtEntry = Life.updateActor(residentOne, player, {}, representativeIntent,
        group, Factions.affiliation(residentOne))
    local canTalk, representativeActor = Life.canTalk(group, player)
    check(pulsed and meetingPoint and meetingPoint.x == 0 and meetingPoint.y == 2
        and representativeIntent and representativeIntent.mode == "life_representative"
        and heldAtEntry and group.life.representative.state == "at_entry"
        and canTalk and representativeActor == residentOne,
        "even a wary paranoid faction sends a reachable representative outside its primary door")
    residentOne.square = previousSquare
    entrySquare.objects = previousObjects
    group.standing, group.lifecycle = previousStanding, previousLifecycle
    group.life.personality.primary = previousPersonality
    group.life.representative.requested = false
    group.life.representative.state = "inside"
    group.life.representative.memberKey = nil
end

do
    local hostileCleaver = item("Base.MeatCleaver", "Weapon", {
        damage = 1.6, range = 1.0, minRange = 0.61, sharpness = 1,
    })
    residentOne.primary = hostileCleaver
    residentOne.square = cell:getGridSquare(3, 1, 0)
    residentOne.worldX, residentOne.worldY, residentOne.lastIntent = nil, nil, nil
    SurvivorCompanion.Navigation.reset(residentOne)
    local approached = SurvivorCompanion.FactionBehavior.update(
        residentOne, player, { snapshot = {} }, { mode = "hostile" })
    check(approached and residentOne.lastIntent
            and residentOne.lastIntent.action ~= "attack_melee",
        "a hostile faction resident at three tiles approaches instead of playing a phantom melee attack")

    SurvivorCompanion.Navigation.reset(residentOne)
    residentOne.square = cell:getGridSquare(1, 1, 0)
    residentOne.lastIntent = nil
    local attacked = SurvivorCompanion.FactionBehavior.update(
        residentOne, player, { snapshot = {} }, { mode = "hostile" })
    check(attacked and residentOne.lastIntent
            and residentOne.lastIntent.action == "attack_melee"
            and residentOne.lastIntent.weapon == hostileCleaver,
        "the same hostile resident attacks only after entering the cleaver's real swing range")
    SurvivorCompanion.Navigation.reset(residentOne)
    residentOne.square = cell:getGridSquare(2, 2, 0)
    residentOne.primary = nil
end
do
    local factionWalker = zombie(3, 2)
    local previousStanding, previousLifecycle = group.standing, group.lifecycle
    local previousSustainedThreatAt, previousLastThreatAt =
        group.sustainedThreatAt, group.lastThreatAt
    group.standing, group.lifecycle = "Hostile", "hostile"
    local threatSnapshot = {
        threats = { { actor = factionWalker, distance = 1 } }, threatCount = 1,
        immediateAttackers = {}, immediateCount = 0, closeThreatCount = 1,
        pressure = 0.35, allies = {}, player = { danger = 0 },
    }
    local commands = { recruited = false, combatDoctrine = "close_defense" }
    local candidates = SurvivorCompanion.Decision._evaluateForTests(
        residentOne, player, threatSnapshot, commands,
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    local originalCombatUpdate = SurvivorCompanion.Combat.update
    local delegatedActor, delegatedPlayer
    SurvivorCompanion.Combat.update = function(combatActor, combatPlayer)
        delegatedActor, delegatedPlayer = combatActor, combatPlayer
        return true, "shared_faction_zombie_combat"
    end
    local delegated, delegateReason = SurvivorCompanion.Decision._delegateForTests(
        candidates[1], residentOne, player, {}, commands, threatSnapshot, {})
    SurvivorCompanion.Combat.update = originalCombatUpdate
    local calmIntent = SurvivorCompanion.FactionBehavior.intentFor(
        residentOne, player, { threats = {}, threatCount = 0 })
    check(candidates[1] and candidates[1].kind == "combat"
        and delegated and delegateReason == "shared_faction_zombie_combat"
        and delegatedActor == residentOne and delegatedPlayer == player
        and calmIntent and calmIntent.mode == "hostile",
        "faction residents yield player hostility to the shared companion zombie-combat engine and resume afterward")
    group.standing, group.lifecycle = previousStanding, previousLifecycle
    group.sustainedThreatAt, group.lastThreatAt =
        previousSustainedThreatAt, previousLastThreatAt
end
local audited = Life.debugAuditResources("faction-test")
local auditedSummary = Factions.summary("faction-test").life.resources
check(audited and auditedSummary.source == "inventory"
    and group.life.resources.counts.food == 1 and group.life.resources.counts.tools == 1,
    "bounded faction resource audit includes supplies inside carried bags")

do
    -- Faction builders carry intentionally heavy household stock. That must not
    -- create the generic logistics candidate which outranks their faction work.
    local previousCapacity = residentTwo.inventory.capacity
    residentTwo.inventory.capacity = 1
    local candidates = SurvivorCompanion.Decision._evaluateForTests(
        residentTwo, player,
        { threats = {}, threatCount = 0, immediateCount = 0, allies = {},
            player = { danger = 0 } },
        { recruited = false },
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    residentTwo.inventory.capacity = previousCapacity
    local factionCandidate, logisticsCandidate = false, false
    for _, candidate in ipairs(candidates) do
        if candidate.kind == "faction" then factionCandidate = true end
        if candidate.kind == "logistics" then logisticsCandidate = true end
    end
    check(factionCandidate and not logisticsCandidate,
        "faction residents retain heavy construction stock for household policy")
end

do
    local brokenBefore = tonumber(group.social.trade.brokenPromises) or 0
    local standingBefore = group.standing
    check(Contracts.debugOffer("faction-test", "supply"),
        "decline fixture creates a real pending offer")
    local declinedId = group.social.contract.offer.id
    local declined, declineReason = Contracts.declineOffer(
        "faction-test", player, true)
    local declinedRow = group.social.contract.history[#group.social.contract.history]
    check(declined and declineReason == "offer_declined"
            and group.social.contract.offer == nil
            and declinedRow and declinedRow.id == declinedId
            and declinedRow.status == "declined"
            and (tonumber(group.social.trade.brokenPromises) or 0) == brokenBefore
            and group.standing == standingBefore
            and tonumber(group.social.contract.cooldownUntilHour) > 240,
        "Decline records the dismissed offer and a short cooldown without a broken-promise penalty")
    local declinedDocument = Factions.export()
    check(Factions.restore(declinedDocument),
        "declined faction offers survive save and restore")
    group = Factions.group("faction-test")
    group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
    local restoredDecline = group.social.contract.history[#group.social.contract.history]
    check(restoredDecline and restoredDecline.id == declinedId
            and restoredDecline.status == "declined"
            and group.social.contract.offer == nil,
        "restored decline history cannot reappear as an active offer: id="
            .. tostring(restoredDecline and restoredDecline.id) .. "/" .. tostring(declinedId)
            .. " status=" .. tostring(restoredDecline and restoredDecline.status)
            .. " offer=" .. tostring(group.social.contract.offer))
end

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

do
    check(Contracts.debugOffer("faction-test", "local_threat")
            and Contracts.accept("faction-test", player, true),
        "party-kill fixture accepts a local-threat contract")
    group = Factions.group("faction-test")
    local localThreat = group.social.contract.active
    localThreat.requiredKills = 2
    localThreat.progress.kills = 0
    localThreat.progress.lastScanCount = 0
    localThreat.progress.loadedSquares = 1000
    local partyKiller = actor("sc-contract-party-killer", localThreat.target.x,
        localThreat.target.y, {})
    registry[partyKiller.id] = {
        id = partyKiller.id, actor = partyKiller, recruited = true,
        factionId = nil,
    }
    local neutralKiller = actor("sc-contract-neutral-killer", localThreat.target.x,
        localThreat.target.y, { recruited = false })
    neutralKiller.modData.SC_Recruited = false
    registry[neutralKiller.id] = {
        id = neutralKiller.id, actor = neutralKiller, recruited = false,
        factionId = nil,
    }
    local originalGetPlayer = getPlayer
    getPlayer = function() return player end
    local neutralVictim = zombie(localThreat.target.x, localThreat.target.y,
        { attackedBy = neutralKiller })
    Contracts.onZombieDead(neutralVictim)
    local partyVictim = zombie(localThreat.target.x, localThreat.target.y,
        { attackedBy = partyKiller })
    Contracts.onZombieDead(partyVictim)
    Contracts.onZombieDead(partyVictim)
    local playerVictim = zombie(localThreat.target.x, localThreat.target.y,
        { attackedBy = player })
    Contracts.onZombieDead(playerVictim)
    Contracts.onZombieDead(playerVictim)
    getPlayer = originalGetPlayer
    local partyProgress = Contracts.progress(group, player, false)
    check(localThreat.progress.kills == 2 and partyProgress and partyProgress.ready,
        "local-threat progress counts player and active companion kills once, but rejects neutral killers")
    group.members[1].actorId, group.members[2].actorId = nil, nil
    local partyKillDocument = Factions.export()
    check(Factions.restore(partyKillDocument)
            and Factions.group("faction-test").social.contract.active.progress.kills == 2,
        "confirmed local-threat party kills survive save and restore")
    group = Factions.group("faction-test")
    group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
    check(Contracts.debugComplete("faction-test"),
        "party-kill fixture completes without leaking an active contract")
    registry[partyKiller.id], registry[neutralKiller.id] = nil, nil
end

do
    local questSquare = cell:getGridSquare(10, 6, 0)
    local questChest = inventory()
    function questChest:getType() return "crate" end
    local questChestObject = {}
    function questChestObject:getContainer() return questChest end
    questSquare.objects = { questChestObject }

    check(Contracts.debugOffer("faction-test", "retrieve_item"),
        "debug controls create a generated-item retrieval quest")
    group = Factions.group("faction-test")
    local offer = group.social.contract.offer
    offer.preparation = "ready"
    offer.target = { x = 10, y = 6, z = 0 }
    offer.targetBounds = { x1 = 9, y1 = 5, x2 = 11, y2 = 7 }
    offer.location = { address = "House 4 tiles NE of Harness Road",
        coordinates = "10, 6, 0" }
    offer.container = { x = 10, y = 6, z = 0, objectIndex = 0, containerType = "crate" }
    offer.objective = "Recover the marked quest item from the test chest."
    check(Contracts.accept("faction-test", player, true),
        "accepting a retrieval quest reserves rewards and materializes its exact item")
    local activeQuest = group.social.contract.active
    local questObject = questChest.items[1]
    local questData = questObject and questObject:getModData() or nil
    local rewardChoiceOne, rewardChoiceTwo = {}, {}
    for _, reward in ipairs(residentOne.inventory.items) do
        local data = reward:getModData()
        if data.LF_QuestId == activeQuest.id and data.LF_QuestRewardChoice == 1 then
            rewardChoiceOne[#rewardChoiceOne + 1] = reward
        elseif data.LF_QuestId == activeQuest.id and data.LF_QuestRewardChoice == 2 then
            rewardChoiceTwo[#rewardChoiceTwo + 1] = reward
        end
    end
    check(questData and questData.LF_QuestItem == true and questData.LF_QuestId == activeQuest.id
            and #rewardChoiceOne > 0 and #rewardChoiceTwo > 0,
        "quest objective and both reward choices carry collision-safe persistent identities")
    group.members[1].actorId, group.members[2].actorId = nil, nil
    local questDocument = Factions.export()
    check(Factions.restore(questDocument),
        "an accepted retrieval quest survives faction save and restore")
    group = Factions.group("faction-test")
    group.members[1].actorId, group.members[2].actorId = residentOne.id, residentTwo.id
    activeQuest = group.social.contract.active
    check(activeQuest and activeQuest.kind == "retrieve_item"
            and activeQuest.progress.spawn.state == "spawned"
            and activeQuest.location.address == "House 4 tiles NE of Harness Road"
            and #activeQuest.rewardChoices == 2,
        "quest restore keeps the exact target, item receipt, address, and immutable rewards")
    group.social.nextPulseAt = 0
    Contracts.pulseGroup(group, player, clock)
    check(#questChest.items == 1,
        "a persisted spawn receipt prevents duplicate quest items on later pulses")
    local questCatalog = Trade.playerCatalog(player)
    questChest:Remove(questObject)
    player.inventory:AddItem(questObject)
    local protectedCatalog = Trade.playerCatalog(player)
    local questTradable = false
    for _, row in ipairs(protectedCatalog or {}) do
        if row.item == questObject then questTradable = true end
    end
    local retrieveProgress = Contracts.progress(group, player, false)
    check(type(questCatalog) == "table" and not questTradable and retrieveProgress
            and retrieveProgress.ready and retrieveProgress.questItemCount == 1,
        "the uniquely tagged retrieved item completes progress but stays out of ordinary barter")
    local originalQuestSnapshot = SurvivorCompanion.Senses.snapshot
    SurvivorCompanion.Senses.snapshot = function() return { threatCount = 0 } end
    local completedRetrieve, completedRetrieveReason = Contracts.chooseReward(
        group, player, 2, false)
    local selectedReceived = true
    for _, reward in ipairs(rewardChoiceTwo) do
        selectedReceived = selectedReceived and player.inventory:contains(reward)
            and reward:getModData().LF_QuestReward == nil
    end
    local unselectedReleased = true
    for _, reward in ipairs(rewardChoiceOne) do
        unselectedReleased = unselectedReleased and residentOne.inventory:contains(reward)
            and reward:getModData().LF_QuestReward == nil
    end
    check(completedRetrieve and selectedReceived and unselectedReleased
            and residentOne.inventory:contains(questObject)
            and questObject:getModData().LF_QuestItem == nil
            and group.social.contract.history[#group.social.contract.history].selectedReward == 2,
        "turn-in atomically exchanges the quest item for only the chosen reward and releases the other: "
            .. tostring(completedRetrieveReason))
    for _, reward in ipairs(rewardChoiceOne) do residentOne.inventory:Remove(reward) end
    for _, reward in ipairs(rewardChoiceTwo) do player.inventory:Remove(reward) end

    check(Contracts.debugOffer("faction-test", "clear_horde"),
        "debug controls create a persistent horde-clearing quest")
    offer = group.social.contract.offer
    offer.preparation = "ready"
    offer.target = { x = 5, y = 5, z = 0 }
    offer.targetBounds = { x1 = 4, y1 = 4, x2 = 6, y2 = 6 }
    offer.location = { address = "House 2 tiles E of Harness Road",
        coordinates = "5, 5, 0" }
    offer.objective = "Clear the tagged test horde."
    offer.horde.total = 3
    check(Contracts.accept("faction-test", player, true),
        "accepting a horde quest reserves two reward choices")
    local spawnedHorde = {}
    local originalAddZombies = addZombiesInOutfit
    addZombiesInOutfit = function(x, y, z, count)
        local candidate = zombie(x, y, { z = z })
        spawnedHorde[#spawnedHorde + 1] = candidate
        return { candidate }
    end
    group.social.nextPulseAt = 0
    Contracts.pulseGroup(group, player, clock + 1)
    addZombiesInOutfit = originalAddZombies
    activeQuest = group.social.contract.active
    check(activeQuest.horde.state == "active" and activeQuest.horde.spawned == 3
            and #spawnedHorde == 3,
        "the horde materializes once only after the player enters its activation radius")
    for _, candidate in ipairs(spawnedHorde) do
        candidate.dead = true
        Contracts.onZombieDead(candidate)
        Contracts.onZombieDead(candidate)
    end
    local hordeProgress = Contracts.progress(group, player, false)
    check(hordeProgress and hordeProgress.ready and hordeProgress.kills == 3
            and activeQuest.horde.state == "cleared",
        "tagged horde deaths count once regardless of attacker and unlock faction turn-in")
    local hordeRewards = {}
    for _, reward in ipairs(residentOne.inventory.items) do
        if reward:getModData().LF_QuestId == activeQuest.id then
            hordeRewards[#hordeRewards + 1] = reward
        end
    end
    check(Contracts.chooseReward(group, player, 1, false)
            and group.social.contract.active == nil,
        "a cleared horde returns through the same two-choice reward transaction")
    for _, reward in ipairs(hordeRewards) do
        if player.inventory:contains(reward) then player.inventory:Remove(reward)
        elseif residentOne.inventory:contains(reward) then residentOne.inventory:Remove(reward) end
    end
    SurvivorCompanion.Senses.snapshot = originalQuestSnapshot
    questSquare.objects = {}
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
local joinSoundBaseline = #uiSounds
local joined, joinReason = Recruitment.debugDecision(group, player, "join")
local joinedMember = Factions.member(group, joinedKey)
check(joined and joinedMember.departed == true and joinedMember.actorId == nil
    and joinedMember.departedActorId == joinedActorId
    and joinedRecord.recruited == true and joinedRecord.factionId == nil
    and #uiSounds == joinSoundBaseline + 1
    and uiSounds[#uiSounds] == "UIAchievement",
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
check(exported.schema == 2 and exported.groups["faction-test"].standing == "Hostile",
    "faction standing and territory export transactionally")
do
    local banditGroup = SurvivorCompanion.StableValue.copyStrict(
        exported.groups["faction-test"], {
            maxDepth = 16, maxEntries = 131072, path = "$.banditFixture",
        })
    banditGroup.id = "faction-bandit-test"
    banditGroup.name = "The Ash Creek Jackals"
    banditGroup.archetype = "bandit_camp"
    banditGroup.lifecycle = "settled"
    banditGroup.standing = "Hostile"
    banditGroup.reputation = -100
    banditGroup.permanentHostility = true
    banditGroup.discovered = true
    banditGroup.bandit = {
        schema = 1, threatTier = "melee", armed = false,
        nextPatrolHour = getGameTime():getWorldAgeHours() + 1,
        patrolSerial = 0, engagement = "unaware",
    }
    for _, member in ipairs(banditGroup.members) do member.actorId = nil end
    local banditDocument = {
        schema = 2, sequence = 5, order = { banditGroup.id },
        groups = { [banditGroup.id] = banditGroup },
    }
    local restoredBandits, restoredBanditCount = Factions.restore(banditDocument)
    local banditSummary = Factions.summary(banditGroup.id)
    check(restoredBandits and restoredBanditCount == 1 and banditSummary
            and banditSummary.archetype == "bandit_camp"
            and banditSummary.capabilities.patrol == true
            and banditSummary.capabilities.social == false
            and banditSummary.social == nil and banditSummary.recruitment == nil
            and banditSummary.bandit.engagement == "unaware",
        "bandit camps persist as a distinct permanently-hostile faction archetype without social services")
    local earlyTier, earlyArmed = Factions._banditTierForDayForTests(5)
    local middleTier = Factions._banditTierForDayForTests(20)
    local forcedTier, forcedArmed = Factions._banditTierForDayForTests(5, "armed")
    local earlyCount = Factions._banditMemberCountForTests(5)
    local lateCount = Factions._banditMemberCountForTests(35)
    check(earlyTier == "melee" and earlyArmed == false and middleTier == "mixed"
            and forcedTier == "armed" and forcedArmed == true
            and earlyCount >= 1 and earlyCount <= 2
            and lateCount >= 2 and lateCount <= 3,
        "bandit population and firearms scale within the intended day-based bounds")

    local savedPlayerSquare = player.square
    player.square = cell:getGridSquare(0, 0, 0)
    player.aiming = false
    local banditActor = actor("bandit-test-actor", 2, 0, { recruited = false })
    local companionActor = actor("bandit-test-companion", 0, 1, { recruited = true })
    local liveBanditGroup = Factions.group(banditGroup.id)
    liveBanditGroup.members[1].actorId = banditActor.id
    registry[banditActor.id] = {
        id = banditActor.id, actor = banditActor,
        factionId = liveBanditGroup.id, factionRole = liveBanditGroup.members[1].role,
    }
    registry[companionActor.id] = {
        id = companionActor.id, actor = companionActor,
        recruited = true, factionId = nil,
    }
    SurvivorCompanion.FactionBehavior.reset()
    local banditIntent = SurvivorCompanion.FactionBehavior.intentFor(
        banditActor, player, { threats = {}, threatCount = 0, sounds = {} })
    local challenged = SurvivorCompanion.FactionBehavior.update(
        banditActor, player, {}, banditIntent)
    check(banditIntent and banditIntent.mode == "bandit_human" and challenged
            and liveBanditGroup.bandit.engagement == "challenging"
            and banditActor.lastIntent and banditActor.lastIntent.action == "face_alert",
        "a bandit with direct sight warns the player before escalating to combat")

    local nearbyPlayerSquare = player.square
    player.square = cell:getGridSquare(40, 40, 0)
    local banditPartyTarget = Factions.hostileTargetFor(banditActor, player)
    local partyBanditTarget = Factions.hostileTargetFor(companionActor, player)
    check(banditPartyTarget and banditPartyTarget.actor == companionActor
            and partyBanditTarget and partyBanditTarget.actor == banditActor,
        "production actor-returning registry selects companion-to-bandit and bandit-to-companion targets without a nearby player")

    local savedArchetype, savedStanding, savedLifecycle, savedBandit =
        liveBanditGroup.archetype, liveBanditGroup.standing,
        liveBanditGroup.lifecycle, liveBanditGroup.bandit
    liveBanditGroup.archetype, liveBanditGroup.standing = "household", "Hostile"
    liveBanditGroup.lifecycle, liveBanditGroup.bandit = "hostile", nil
    local householdPartyTarget = Factions.hostileTargetFor(banditActor, player)
    local partyHouseholdTarget = Factions.hostileTargetFor(companionActor, player)
    check(householdPartyTarget and householdPartyTarget.actor == companionActor
            and partyHouseholdTarget and partyHouseholdTarget.actor == banditActor,
        "hostile households and the player party discover each other through the same hostility predicate")
    liveBanditGroup.standing, liveBanditGroup.lifecycle = "Trusted", "settled"
    check(Factions.hostileTargetFor(banditActor, player) == nil
            and Factions.hostileTargetFor(companionActor, player) == nil,
        "a friendly household is never admitted as a hostile human target")

    liveBanditGroup.archetype, liveBanditGroup.standing = savedArchetype, savedStanding
    liveBanditGroup.lifecycle, liveBanditGroup.bandit =
        savedLifecycle, savedBandit
    liveBanditGroup.bandit.engagement = "unaware"
    check(Factions.hostileTargetFor(companionActor, player) == nil,
        "an unaware bandit camp is not yet a companion attack target")
    liveBanditGroup.bandit.engagement = "challenging"
    banditActor.dead = true
    check(Factions.hostileTargetFor(companionActor, player) == nil,
        "dead faction actors are excluded by the production registry contract")
    banditActor.dead = false
    registry[banditActor.id].runtime = { inactive = true }
    check(Factions.hostileTargetFor(companionActor, player) == nil,
        "inactive faction records are excluded by the production registry contract")
    registry[banditActor.id].runtime = nil

    local partyFriend = actor("bandit-test-party-friend", 1, 1, { recruited = true })
    local factionWingman = actor("bandit-test-wingman", 3, 0, { recruited = false })
    registry[partyFriend.id] = {
        id = partyFriend.id, actor = partyFriend, recruited = true, factionId = nil,
    }
    registry[factionWingman.id] = {
        id = factionWingman.id, actor = factionWingman, recruited = false,
        factionId = liveBanditGroup.id, factionRole = "guard",
    }
    local function containsRelationship(rows, candidate)
        for _, row in ipairs(rows or {}) do
            if row.actor == candidate then return row.relationship end
        end
        return nil
    end
    local partyAllies, partyProtected =
        SurvivorCompanion.Senses._collectRelationshipsForTests(companionActor, player)
    local factionAllies, factionProtected =
        SurvivorCompanion.Senses._collectRelationshipsForTests(banditActor, player)
    check(containsRelationship(partyAllies, partyFriend) == "party_ally"
            and containsRelationship(partyAllies, banditActor) == nil
            and containsRelationship(partyProtected, banditActor) == nil
            and containsRelationship(factionAllies, factionWingman) == "faction_ally"
            and containsRelationship(factionAllies, companionActor) == nil
            and containsRelationship(factionProtected, companionActor) == nil,
        "mixed rosters expose only party or same-faction actors as support allies and exclude current hostiles")

    liveBanditGroup.archetype, liveBanditGroup.standing = "household", "Trusted"
    liveBanditGroup.lifecycle, liveBanditGroup.bandit = "settled", nil
    local neutralAllies, neutralProtected =
        SurvivorCompanion.Senses._collectRelationshipsForTests(companionActor, player)
    check(containsRelationship(neutralAllies, banditActor) == nil
            and containsRelationship(neutralProtected, banditActor) == "neutral",
        "a neutral household is protected from friendly fire without contributing combat support")
    liveBanditGroup.archetype, liveBanditGroup.standing = savedArchetype, savedStanding
    liveBanditGroup.lifecycle, liveBanditGroup.bandit = savedLifecycle, savedBandit
    liveBanditGroup.bandit.engagement = "challenging"

    local partyFriendRow
    for _, row in ipairs(partyAllies) do
        if row.actor == partyFriend then partyFriendRow = row break end
    end
    local supportBefore = SurvivorCompanion.Combat.readiness(companionActor, {
        allies = { partyFriendRow }, immediateCount = 0, closeThreatCount = 0,
        occupiedThreatSectors = 0, escapeSquares = {}, pressure = 0,
        player = { available = false },
    }, nil, { morale = 55, stress = 0 })
    registry[partyFriend.id].recruited = false
    local supportAfter = SurvivorCompanion.Combat.readiness(companionActor, {
        allies = { partyFriendRow }, immediateCount = 0, closeThreatCount = 0,
        occupiedThreatSectors = 0, escapeSquares = {}, pressure = 0,
        player = { available = false },
    }, nil, { morale = 55, stress = 0 })
    check(supportBefore.support == 1 and supportAfter.support == 0,
        "combat revalidates a cached ally relationship before counting support")
    registry[partyFriend.id], registry[factionWingman.id] = nil, nil
    for _, value in ipairs({ partyFriend, factionWingman }) do
        for index = #value.square.moving, 1, -1 do
            if value.square.moving[index] == value then
                table.remove(value.square.moving, index)
            end
        end
    end
    player.square = nearbyPlayerSquare

    local heardAttack
    local originalHear = SurvivorCompanion.Senses.hear
    SurvivorCompanion.Senses.hear = function(source, x, y, z, radius, volume, kind)
        heardAttack = { source = source, x = x, y = y, z = z,
            radius = radius, volume = volume, kind = kind }
        return true
    end
    local firearm = {
        isRanged = function() return true end,
        getSoundRadius = function() return 40 end,
    }
    local originalGetPlayer = getPlayer
    getPlayer = function() return player end
    Factions.onWeaponSwingHitPoint(player, firearm)
    getPlayer = originalGetPlayer
    SurvivorCompanion.Senses.hear = originalHear
    check(heardAttack and heardAttack.source == player and heardAttack.radius == 40
            and heardAttack.kind == "player_attack",
        "player weapon swings enter the bounded sound memory used by bandit hearing")

    player.square.losBlocked = true
    companionActor.square.losBlocked = true
    SurvivorCompanion.FactionBehavior.reset(banditActor)
    local heardIntent = SurvivorCompanion.FactionBehavior.intentFor(
        banditActor, player, { threats = {}, threatCount = 0, sounds = {
            { source = player, x = player:getX(), y = player:getY(), z = player:getZ(),
                radius = 20, volume = 20, time = clock },
        } })
    player.square.losBlocked = false
    companionActor.square.losBlocked = false
    check(heardIntent and heardIntent.mode == "bandit_investigate"
            and heardIntent.sound.source == player,
        "a wall-hidden hostile sound produces investigation without target acquisition: "
            .. tostring(heardIntent and heardIntent.mode))

    banditActor.square.losBlocked = true
    SurvivorCompanion.FactionBehavior.reset(companionActor)
    check(SurvivorCompanion.FactionBehavior.humanThreatFor(companionActor, player) == nil,
        "companions never acquire a wall-hidden bandit without prior visual contact")
    banditActor.square.losBlocked = false
    local visibleBandit = SurvivorCompanion.FactionBehavior.humanThreatFor(
        companionActor, player)
    local seenX, seenY = visibleBandit and visibleBandit.x, visibleBandit and visibleBandit.y
    banditActor.square = cell:getGridSquare(4, 0, 0)
    banditActor.square.losBlocked = true
    local rememberedBandit = SurvivorCompanion.FactionBehavior.humanThreatFor(
        companionActor, player)
    check(visibleBandit and visibleBandit.visible == true and rememberedBandit
            and rememberedBandit.visible == false
            and rememberedBandit.x == seenX and rememberedBandit.y == seenY,
        "human-threat memory keeps the last seen square instead of tracking a bandit through walls")

    banditActor.square.losBlocked = false
    SurvivorCompanion.FactionBehavior.reset(companionActor)
    local reacquiredBandit = SurvivorCompanion.FactionBehavior.humanThreatFor(
        companionActor, player)
    local combatCandidates = SurvivorCompanion.Decision._evaluateForTests(
        companionActor, player,
        { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0,
            allies = {}, player = { danger = 0 }, humanThreat = reacquiredBandit },
        { recruited = true, combatDoctrine = "close_defense" },
        { alive = true, health = 100, wounds = {} }, {}, {}, clock)
    check(combatCandidates[1] and combatCandidates[1].kind == "combat"
            and combatCandidates[1].detail
            and combatCandidates[1].detail.humanThreat.actor == banditActor,
        "an engaged visible bandit enters the companion combat decision at survival priority")

    local savedBandits = Factions.export()
    check(savedBandits.schema == 2
            and savedBandits.groups[banditGroup.id].bandit.engagement == "challenging",
        "bandit engagement state survives the faction persistence boundary")
    player.square = savedPlayerSquare
    registry[banditActor.id], registry[companionActor.id] = nil, nil
    SurvivorCompanion.FactionBehavior.reset()
end
do
    -- Report 6: a faction member's gear-add must tolerate an item that cannot
    -- instantiate, so the member still spawns
    -- with the gear it could get instead of aborting the whole household.
    local addedTypes = {}
    local gearInventory = {}
    function gearInventory:AddItem(itemType)
        if itemType == "Base.Notebook" then return nil end
        addedTypes[#addedTypes + 1] = itemType
        return { __type = itemType }
    end
    local gearActor = actor("sc-faction-gear", 30, 30, {})
    gearActor.getInventory = function() return gearInventory end
    local geared = Factions._addGearForTests(gearActor, "leader", {})
    check(geared == true and #addedTypes > 0,
        "a faction leader still equips when one gear item cannot instantiate")
    registry[gearActor.id] = nil
end
local debugSpawned, debugReason = Factions.debugSpawnHousehold(player, 2)
check(not debugSpawned and debugReason == "debug_tools_disabled",
    "manual faction spawning remains fail-closed outside debug builds")
Factions.reset()
Trade.reset()
end
SurvivorCompanion.__testFactionDomain()
SurvivorCompanion.__testFactionDomain = nil

-- A faction restore spans the persistent group graph, transient spawn work,
-- and the derived faction-world relation graph.  Any late failure must put all
-- three back exactly where they were before the restore began.
function SurvivorCompanion.__testFactionRestoreTransactions()
local Factions = SurvivorCompanion.Factions
local World = SurvivorCompanion.FactionWorld
local Actor = SurvivorCompanion.Actor
local baseline = {
    schema = 1, sequence = 7, lastWorldSpawnDay = 3, lastProductionCheckDay = 4,
    order = { "faction-transaction-a" },
    groups = {
        ["faction-transaction-a"] = {
            id = "faction-transaction-a", archetype = "barricaded_household",
            name = "Transaction household A", lifecycle = "settled",
            standing = "Tolerated", reputation = 5, discovered = true,
            barterUnlocked = false, permanentHostility = false,
            shortageKind = "food",
            house = {
                id = "1:1:4:4", bounds = { x1 = 1, y1 = 1, x2 = 4, y2 = 4, z = 0 },
                anchor = { x = 2, y = 2, z = 0 },
                interior = { { x = 2, y = 2, z = 0 } }, openings = {},
            },
            members = { { key = "member-a", role = "leader", identity = {
                forename = "Ada", surname = "Test", gender = "female",
            }, alive = true, hibernated = false } },
            jobs = {}, offenses = {}, history = {},
            request = { kind = "food", status = "available", rewardReserved = true,
                required = { { category = "food", count = 1 } }, reward = {} },
        },
    },
}

local function candidateDocument()
    local candidate = SurvivorCompanion.StableValue.copyStrict(baseline, {
        maxDepth = 16, maxEntries = 131072, path = "$.transactionCandidate",
    })
    local second = SurvivorCompanion.StableValue.copyStrict(
        baseline.groups["faction-transaction-a"], {
            maxDepth = 16, maxEntries = 131072, path = "$.transactionGroup",
        })
    second.id, second.name = "faction-transaction-b", "Transaction household B"
    second.house.id = "5:1:8:4"
    second.house.anchor = { x = 6, y = 2, z = 0 }
    second.house.bounds = { x1 = 5, y1 = 1, x2 = 8, y2 = 4, z = 0 }
    second.house.interior = { { x = 6, y = 2, z = 0 } }
    second.members[1].key = "member-b"
    candidate.sequence = 99
    candidate.order[2] = second.id
    candidate.groups[second.id] = second
    return candidate
end

local function relationCount(document)
    local amount = 0
    for _ in pairs(document and document.relations or {}) do amount = amount + 1 end
    return amount
end

local function sameWorldState(left, right)
    return relationCount(left) == relationCount(right)
        and left.serial == right.serial and left.version == right.version
        and left.nextEventHour == right.nextEventHour
        and #(left.news or {}) == #(right.news or {})
end

Factions.reset()
check(Factions.restore(baseline), "transaction fixture restores its baseline household")
World.reset()
check(World.reconcile(), "transaction fixture starts with a reconciled world graph")
World.pulse(10)

do
    local beforeFaction, beforeWorld = Factions.export(), World.export()
    local originalReconcile = World.reconcile
    World.reconcile = function()
        originalReconcile()
        error("forced reconcile exception after mutation")
    end
    local accepted, reason = Factions.restore(candidateDocument())
    World.reconcile = originalReconcile
    local afterFaction, afterWorld = Factions.export(), World.export()
    check(not accepted
        and string.find(tostring(reason), "forced reconcile exception", 1, true) ~= nil
        and #afterFaction.order == 1 and afterFaction.order[1] == beforeFaction.order[1]
        and afterFaction.sequence == beforeFaction.sequence
        and Factions.group("faction-transaction-b") == nil
        and sameWorldState(afterWorld, beforeWorld),
        "a reconcile exception rolls back faction globals and world mutations")
end

do
    local beforeWorld = World.export()
    local originalReconcile = World.reconcile
    World.reconcile = function()
        originalReconcile()
        return false, "forced reconcile rejection after mutation"
    end
    local accepted, reason = Factions.restore(candidateDocument())
    World.reconcile = originalReconcile
    local afterWorld = World.export()
    check(not accepted
        and string.find(tostring(reason), "forced reconcile rejection", 1, true) ~= nil
        and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-b") == nil
        and sameWorldState(afterWorld, beforeWorld),
        "a reconcile false result is a transactional failure, not a partial restore")
end

do
    local beforeWorld = World.export()
    local replacement = SurvivorCompanion.StableValue.copyStrict(beforeWorld, {
        maxDepth = 8, maxEntries = 8192, path = "$.worldReplacement",
    })
    replacement.serial, replacement.version = 41, 73
    replacement.nextEventHour = 999
    local originalReconcile = World.reconcile
    World.reconcile = function() return false, "forced world restore rejection" end
    local accepted, reason = World.restore(replacement)
    World.reconcile = originalReconcile
    check(not accepted and reason == "forced world restore rejection"
        and sameWorldState(World.export(), beforeWorld),
        "faction-world restore rolls back when reconciliation returns false")
end

do
    local originalBegin = Actor.beginSpawn
    local originalPoll = Actor.pollSpawn
    local originalCancel = Actor.cancelSpawn
    local activeTicket = { id = "faction-transaction-ticket" }
    local beginCalls, pollCalls, cancelCalls = 0, 0, 0
    Actor.beginSpawn = function()
        beginCalls = beginCalls + 1
        return activeTicket, "spawn_pending"
    end
    Actor.pollSpawn = function(ticket)
        if ticket == activeTicket then pollCalls = pollCalls + 1 end
        return nil, "spawn_pending"
    end
    Actor.cancelSpawn = function(ticket)
        if ticket == activeTicket then cancelCalls = cancelCalls + 1 end
        return false, "forced cancellation rejection"
    end
    Factions._nextProductionAt = math.huge
    Factions.pulse(player, clock)
    Factions.pulse(player, clock + 1)
    check(beginCalls == 1 and Factions.group("faction-transaction-a").members[1].spawnQueued == true,
        "transaction fixture owns one active faction spawn before restore")

    local beforeWorld = World.export()
    local cleared, clearReason = Factions.restore(nil)
    check(not cleared
        and string.find(tostring(clearReason), "forced cancellation rejection", 1, true) ~= nil
        and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-a").members[1].spawnQueued == true,
        "nil faction restore preserves live state when spawn cancellation fails")

    local accepted, reason = Factions.restore(candidateDocument())
    local afterWorld = World.export()
    check(not accepted
        and string.find(tostring(reason), "forced cancellation rejection", 1, true) ~= nil
        and cancelCalls == 2 and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-b") == nil
        and Factions.group("faction-transaction-a").members[1].spawnQueued == true
        and sameWorldState(afterWorld, beforeWorld),
        "late spawn cancellation failure rolls back candidate groups, queue state and world relations")
    Factions.pulse(player, clock + 2)
    check(pollCalls == 1 and beginCalls == 1,
        "the original active spawn ticket remains owned after restore rollback")

    Actor.cancelSpawn = function(ticket)
        if ticket == activeTicket then cancelCalls = cancelCalls + 1 end
        return true
    end
    check(Factions.restore(baseline) and cancelCalls == 3,
        "a verified cancellation commits the replacement and clears transient spawn work")
    Actor.beginSpawn, Actor.pollSpawn, Actor.cancelSpawn = originalBegin, originalPoll, originalCancel
end

Factions.reset()
end
SurvivorCompanion.__testFactionRestoreTransactions()
SurvivorCompanion.__testFactionRestoreTransactions = nil

check(SurvivorCompanion.Decision.resetAll(), "central gameplay runtime reset")
check(SurvivorCompanion.Decision.peek(fellow) == nil and SurvivorCompanion.Combat.peek(fellow) == nil,
    "runtime reset clears transient Java-object state")

print("Gameplay harness PASS: " .. tostring(checks) .. " checks")
