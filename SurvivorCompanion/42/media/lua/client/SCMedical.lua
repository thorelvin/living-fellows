-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Medical = SC.Medical or {}
local Medical = SC.Medical
local downed = setmetatable({}, { __mode = "k" })
local treatmentState = setmetatable({}, { __mode = "k" })
-- Companions the player is bandaging right now; they hold still until the
-- player's timed action ends or stops refreshing the hold.
local receivingCare = setmetatable({}, { __mode = "k" })
local helpRequestedAt = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function booleanMethod(value, names)
    local utility = U()
    for _, name in ipairs(names) do
        local result, ok = utility.call(value, name)
        if ok then return result == true end
    end
    return false
end

local function numberMethod(value, names, fallback)
    local utility = U()
    for _, name in ipairs(names) do
        local result, ok = utility.call(value, name)
        if ok and type(result) == "number" then return result end
    end
    return fallback or 0
end

-- Build 42's getApparentInfectionLevel() is max(ZOMBIE_FEVER, ZOMBIE_INFECTION,
-- FOOD_SICKNESS), so a companion with food poisoning reads as a rising Knox
-- infection and can trip the crisis escalation and turning thresholds while
-- perfectly free of the virus. Derive the real progress the way
-- BodyDamage.update() does -- (now - infectionTime) / infectionMortalityDuration
-- -- and keep the apparent value separately for anything that means "looks ill".
-- The engine measures an IsoPlayer (which companions are) against
-- getHoursSurvived() and everything else against world age; mirror that, and
-- fall back to the apparent value only when the native numbers are unusable.
local function knoxInfectionLevel(character, body, infected, apparent)
    if not infected or body == nil then return 0 end
    local duration = numberMethod(body, { "getInfectionMortalityDuration" }, -1)
    local started = numberMethod(body, { "getInfectionTime" }, -1)
    if duration <= 0 or started < 0 then return apparent end
    local current = numberMethod(character, { "getHoursSurvived" }, -1)
    if current < 0 and type(getGameTime) == "function" then
        local ok, time = pcall(getGameTime)
        if ok and time ~= nil then
            current = numberMethod(time, { "getWorldAgeHours" }, -1)
        end
    end
    if current < 0 then return apparent end
    local progress = (current - started) / duration
    -- NaN guard: a corrupted duration must not publish a nonsense percentage.
    if progress ~= progress then return apparent end
    return math.max(0, math.min(100, progress * 100))
end

local function bodyDamage(character)
    local body, ok = U().call(character, "getBodyDamage")
    if ok then return body end
    return nil
end

local function partName(part, index)
    local utility = U()
    local partType, ok = utility.call(part, "getType")
    if ok and partType then return tostring(partType) end
    return "part_" .. tostring(index)
end

local function inspectPart(part, index)
    local bleeding = booleanMethod(part, { "bleeding", "isBleeding" })
        or numberMethod(part, { "getBleedingTime" }, 0) > 0
    local bitten = booleanMethod(part, { "bitten", "isBitten" })
    -- Local, treatable WOUND infection only -- never the character's Knox (zombie)
    -- infection. BodyPart.IsInfected() returns the Knox flag, which the engine
    -- propagates to EVERY body part, so a Knox-infected companion read every part as
    -- infected (severity 30 each) and tried to change bandages over its whole body
    -- forever, filling its work queue and locking it in place. Knox is assessed
    -- separately at the character level (knoxInfected).
    local infected = booleanMethod(part, { "isInfectedWound" })
    local bandaged = booleanMethod(part, { "bandaged", "isBandaged" })
    -- Native isBandageDirty() only checks bandageLife <= 0, which is also
    -- true for every completely unbandaged healthy body part.
    local dirtyBandage = bandaged and booleanMethod(part, { "isBandageDirty" })
    local scratched = booleanMethod(part, { "scratched", "isScratched" })
    local cut = booleanMethod(part, { "isCut" })
    local deep = booleanMethod(part, { "deepWounded", "isDeepWounded" })
    local burned = numberMethod(part, { "getBurnTime" }, 0) > 0
    local fracture = numberMethod(part, { "getFractureTime" }, 0) > 0
    local bullet = booleanMethod(part, { "haveBullet" })
    local glass = booleanMethod(part, { "haveGlass" })
    local lodged = bullet or glass
    local severity = 0
    if bleeding then severity = severity + 28 end
    if bitten then severity = severity + 35 end
    if infected then severity = severity + 30 end
    if deep then severity = severity + 22 end
    if fracture then severity = severity + 18 end
    if burned then severity = severity + 12 end
    if scratched or cut then severity = severity + 8 end
    if lodged then severity = severity + 10 end
    if bandaged and not dirtyBandage then severity = severity - 18 end
    -- A wound that stopped bleeding before anyone dressed it: it heals slowly
    -- and can get infected until it is covered. A bite is Knox's business.
    local openWound = not bandaged and not bleeding and not bitten
        and (scratched or cut or deep or burned)
    return {
        part = part,
        index = index,
        name = partName(part, index),
        bleeding = bleeding,
        bitten = bitten,
        infected = infected,
        bandaged = bandaged,
        dirtyBandage = dirtyBandage,
        openWound = openWound,
        scratched = scratched,
        cut = cut,
        deepWound = deep,
        burned = burned,
        fractured = fracture,
        lodged = lodged,
        bullet = bullet,
        glass = glass,
        severity = severity,
    }
end

function Medical.assess(character, runtime)
    local utility = U()
    local body = bodyDamage(character)
    local health = body and numberMethod(body, { "getHealth" }, utility.nativeHealth(character))
        or utility.nativeHealth(character)
    local wounds, bleedingCount, dirtyBandages, bites, openWounds = {}, 0, 0, 0, 0
    local bodyParts = body and select(1, utility.call(body, "getBodyParts")) or nil
    utility.each(bodyParts, 32, function(part, index)
        local wound = inspectPart(part, index)
        if wound.severity > 0 or wound.bandaged then wounds[#wounds + 1] = wound end
        if wound.bleeding and not wound.bandaged then bleedingCount = bleedingCount + 1 end
        if wound.dirtyBandage then dirtyBandages = dirtyBandages + 1 end
        if wound.bitten then bites = bites + 1 end
        if wound.openWound then openWounds = openWounds + 1 end
    end)
    table.sort(wounds, function(a, b) return a.severity > b.severity end)

    local infected = body and booleanMethod(body, { "IsInfected", "isInfected" }) or false
    local apparentInfectionLevel = body
        and numberMethod(body, { "getApparentInfectionLevel" }, 0) or 0
    local infectionLevel = knoxInfectionLevel(character, body, infected, apparentInfectionLevel)
    local terminalKnox = infected and infectionLevel >= 99.5
    local state = downed[character]
    return {
        actor = character,
        bodyDamage = body,
        health = health,
        alive = health > 0 and not utility.isDead(character),
        wounds = wounds,
        woundCount = #wounds,
        bleedingCount = bleedingCount,
        dirtyBandages = dirtyBandages,
        bites = bites,
        knoxInfected = infected,
        infectionLevel = infectionLevel,
        apparentInfectionLevel = apparentInfectionLevel,
        terminalKnox = terminalKnox,
        -- Only an explicit legacy state requires recovery. Low body health is
        -- not a downed state and cannot be healed by an empty bandage action.
        downed = state ~= nil or type(runtime) == "table" and runtime.downed == true,
        critical = health > 0 and health <= (utility.config("medicalCriticalHealth") or 35),
        needsBandage = bleedingCount > 0,
        needsBandageChange = dirtyBandages > 0,
        openWounds = openWounds,
        needsDressing = openWounds > 0,
    }
end

function Medical.isLivingPatient(character, assessment)
    if character == nil or U().isDead(character) then return false end
    assessment = assessment or Medical.assess(character)
    return type(assessment) == "table" and assessment.alive ~= false
        and (tonumber(assessment.health) or U().nativeHealth(character)) > 0
        and assessment.terminalKnox ~= true
end

function Medical.hasActionableNeed(character, assessment, allowRecovery)
    assessment = assessment or Medical.assess(character)
    if not Medical.isLivingPatient(character, assessment) then return false end
    -- Recovery belongs to the downed actor; a helper cannot stand another actor
    -- up by calling treat(). Dirty-bandage replacement normally remains downtime
    -- work, but a critical patient may prioritize replacing a genuinely worn one.
    return allowRecovery == true and assessment.downed == true
        or assessment.needsBandage == true or (tonumber(assessment.bleedingCount) or 0) > 0
        or assessment.critical == true and (assessment.needsBandageChange == true
            or (tonumber(assessment.dirtyBandages) or 0) > 0)
end

local inventoryContains

local function inventoryRemove(inventory, item)
    local utility = U()
    local result, ok = utility.call(inventory, "Remove", item)
    if ok then return result ~= false and not inventoryContains(inventory, item) end
    if type(inventory) == "table" and type(inventory.items) == "table" then
        for index, value in ipairs(inventory.items) do
            if value == item then table.remove(inventory.items, index) return true end
        end
    end
    return false
end

inventoryContains = function(inventory, item)
    if not inventory or not item then return false end
    local contains, ok = U().call(inventory, "contains", item)
    if ok then return contains == true end
    for _, value in ipairs(U().inventoryItems(inventory, 160)) do
        if value == item then return true end
    end
    return false
end

local function restoreInventoryItem(inventory, item)
    if not inventory or not item then return false end
    if inventoryContains(inventory, item) then return true end
    return U().addItem(inventory, item) ~= nil
end

-- Vanilla lets a dirty rag or bandage dress a wound: it stops the bleeding but
-- goes on already soiled (ISApplyBandage gives it no bandage life).
local function dirtyDressing(item)
    local itemType = string.lower(U().itemType(item))
    return booleanMethod(item, { "isDirty", "isBloody" })
        or string.find(itemType, "dirty", 1, true) ~= nil
end

local function bandageRank(item, allowDirty)
    local utility = U()
    local itemType = string.lower(utility.itemType(item))
    local dirty = dirtyDressing(item)
    if dirty and allowDirty ~= true then return nil end
    -- Eligibility BEFORE quality (LF-05): the item must actually be a dressing. An
    -- isAlcoholic() flag (whiskey, disinfectant) or a "steril" substring in an
    -- unrelated name is NOT proof of a dressing, so those only modify the ranking
    -- of an item already shown to be bandage-capable -- they never make one
    -- eligible on their own.
    local isBandageType = string.find(itemType, "bandage", 1, true) ~= nil
    local isRippedSheet = string.find(itemType, "rippedsheet", 1, true) ~= nil
        or string.find(itemType, "ripped_sheet", 1, true) ~= nil
    -- CanBandage is an item property in Build 42 (denim and leather strips
    -- carry it), not a tag.
    local canBandage = utility.itemHasTag(item, "CanBandage") == true
        or booleanMethod(item, { "isCanBandage" })
    if not (isBandageType or isRippedSheet or canBandage) then return nil end
    -- A dirty dressing is the last resort, after every clean one.
    if dirty then return 6 end
    -- Quality among eligible dressings (lower rank = preferred): sterile, then
    -- alcohol-treated, then a plain bandage, then a tagged dressing, then a ripped
    -- sheet.
    if string.find(itemType, "steril", 1, true) then return 1 end
    if booleanMethod(item, { "isAlcoholic" }) then return 2 end
    if isBandageType then return 3 end
    if canBandage then return 4 end
    return 5
end

-- Bounded recursive bandage search (LF-06). The old scan looked only at the first
-- 100 items of the actor's root inventory, so a bandage carried in a bag or a
-- first-aid container -- or past the 100th root item -- was invisible, making a
-- companion tear clothing (or the player-care preflight report no_bandage) despite
-- carrying supplies. This descends into nested containers up to a depth/item
-- budget, detects container cycles, and returns the item together with its ACTUAL
-- source container so consumption and rollback operate where the bandage lives.
local function findBandage(character, allowDirty)
    local utility = U()
    local rootInventory = utility.inventory(character)
    local maxDepth = tonumber(utility.config("medicalBandageSearchDepth")) or 3
    local maxItems = tonumber(utility.config("medicalBandageSearchLimit")) or 400
    local best, bestRank, bestContainer
    local scanned = 0
    local seen = {}
    local function scan(inventory, depth)
        if inventory == nil or seen[inventory] or depth > maxDepth or bestRank == 1 then return end
        seen[inventory] = true
        for _, item in ipairs(utility.inventoryItems(inventory, maxItems)) do
            if bestRank == 1 or scanned >= maxItems then return end
            scanned = scanned + 1
            local protected = SC.PersonalItems and SC.PersonalItems.isProtected(
                item, character, "medical_consume")
            if not protected then
                local rank = bandageRank(item, allowDirty)
                if rank and (not bestRank or rank < bestRank) then
                    best, bestRank, bestContainer = item, rank, inventory
                end
                -- Only a real InventoryContainer item exposes getInventory(); a
                -- plain item returns an error string through SCCall, which must not
                -- be mistaken for a nested container.
                if bestRank ~= 1 then
                    local nested, ok = utility.call(item, "getInventory")
                    if ok and (type(nested) == "userdata" or type(nested) == "table") then
                        scan(nested, depth + 1)
                    end
                end
            end
        end
    end
    scan(rootInventory, 1)
    return best, bestContainer or rootInventory
end
Medical._bandageRankForTests = bandageRank
Medical._findBandageForTests = findBandage

local essentialClothingTerms = {
    "coat", "jacket", "parka", "trouser", "pants", "shoe", "boot",
    "underwear", "bullet", "firefighter", "hazmat",
    "belt", "holster", "helmet", "armor", "armour",
}

local expendableWornTerms = { "tshirt", "shirt_", "socks", "scarf" }

local function isRecruitedTeam(character)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, character)
        if ok and type(state) == "table" then return state.recruited == true end
    end
    local data = U().modData(character)
    return type(data) == "table" and data.SC_Recruited == true
end

local function isWorn(character, item)
    local utility = U()
    local equipped, equippedOk = utility.call(character, "isEquippedClothing", item)
    if equippedOk and equipped then return true end
    local wornItems, wornOk = utility.call(character, "getWornItems")
    if wornOk and wornItems then
        local contains, containsOk = utility.call(wornItems, "contains", item)
        if containsOk and contains then return true end
    end
    return false
end

local function restoreWornItem(character, item, location)
    if not location then return false end
    -- setWornItem needs the ItemBodyLocation object; the item carries its own, so
    -- resolve it from the item rather than passing a location string (which finds
    -- no matching native overload and silently leaves the item in inventory).
    local bodyLocation = select(1, U().call(item, "getBodyLocation")) or location
    local result, called = U().call(character, "setWornItem", bodyLocation, item)
    if not called or result == false then return false end
    return isWorn(character, item)
end

-- Build 42 rules: cotton tears into ripped sheets by hand; denim and leather
-- need scissors or a sharp knife and give denim or leather strips. All three
-- dress a wound.
local fabricMaterials = {
    cotton = "Base.RippedSheets", denim = "Base.DenimStrips", leather = "Base.LeatherStrips",
}
local cuttingToolCache = setmetatable({}, { __mode = "k" })

-- Fabric of a clothing item, and whether the game reported one at all. An
-- object without the fabric API falls back to the conservative name rules.
local function clothingFabric(item)
    local fabric, ok = U().call(item, "getFabricType")
    if not ok then return nil, false end
    fabric = fabric ~= nil and string.lower(tostring(fabric)) or nil
    if fabric and fabricMaterials[fabric] then return fabric, true end
    return nil, true
end

local function carriesCuttingTool(character)
    local utility = U()
    local current = utility.nowMs()
    local cached = cuttingToolCache[character]
    if cached and current - cached.at >= 0 and current - cached.at < 5000 then
        return cached.value
    end
    local found = false
    for _, item in ipairs(utility.inventoryItems(utility.inventory(character), 100)) do
        if utility.itemHasTag(item, "Scissors") or utility.itemHasTag(item, "SharpKnife") then
            found = true
            break
        end
    end
    cuttingToolCache[character] = { value = found, at = current }
    return found
end

local function isExpendableClothing(character, item, context)
    local utility = U()
    if SC.PersonalItems and SC.PersonalItems.isProtected(item, character, "clothing_tear") then
        return false
    end
    local category, categoryOk = utility.call(item, "getCategory")
    local itemType = string.lower(utility.itemType(item))
    if (not categoryOk or tostring(category) ~= "Clothing")
        and not string.find(itemType, "shirt", 1, true)
        and not string.find(itemType, "socks", 1, true)
        and not string.find(itemType, "scarf", 1, true) then return false end
    for _, term in ipairs(essentialClothingTerms) do
        if string.find(itemType, term, 1, true) then return false end
    end
    local primary, primaryOk = utility.call(character, "getPrimaryHandItem")
    local secondary, secondaryOk = utility.call(character, "getSecondaryHandItem")
    if (primaryOk and primary == item) or (secondaryOk and secondary == item) then return false end
    local fabric, fabricKnown = clothingFabric(item)
    local material = "Base.RippedSheets"
    if fabricKnown then
        if not fabric then return false end
        if fabric ~= "cotton" then
            if not (type(context) == "table" and type(context.hasCuttingTool) == "function"
                and context.hasCuttingTool()) then
                if type(context) == "table" then context.neededTool = true end
                return false
            end
        end
        material = fabricMaterials[fabric]
    end
    local worn = isWorn(character, item)
    if worn then
        if not isRecruitedTeam(character) then return false end
        if not fabricKnown then
            -- Without a fabric type only the conservative worn whitelist applies.
            local whitelisted = false
            for _, term in ipairs(expendableWornTerms) do
                if string.find(itemType, term, 1, true) then whitelisted = true break end
            end
            if not whitelisted then return false end
        end
        local location, locationOk = utility.call(item, "getBodyLocation")
        if not locationOk or location == nil then return false end
        return true, true, location, material
    end
    return true, false, nil, material
end

local function emergencyClothing(character)
    local utility = U()
    if not utility.isCompanion(character) then return nil, nil, nil, "not_companion" end
    local inventory = utility.inventory(character)
    if not inventory then return nil, nil, nil, "inventory_unavailable" end
    local context = {
        hasCuttingTool = function() return carriesCuttingTool(character) end,
    }
    local items = utility.inventoryItems(inventory, 100)
    -- Spare clothes go first; worn clothes only when nothing else will do.
    for pass = 1, 2 do
        for _, item in ipairs(items) do
            if (pass == 1) ~= (isWorn(character, item) == true) then
                local expendable, worn, wornLocation, material =
                    isExpendableClothing(character, item, context)
                if expendable then
                    return item, inventory, {
                        character = character,
                        clothing = item,
                        worn = worn == true,
                        wornLocation = wornLocation,
                        material = material,
                    }, nil
                end
            end
        end
    end
    return nil, inventory, nil,
        context.neededTool and "no_cutting_tool" or "no_expendable_clothing"
end

-- Test seam: which clothing a companion would tear for a dressing, and why not.
Medical._emergencyClothingForTests = emergencyClothing

local function commitEmergencyBandage(inventory, candidate)
    if type(candidate) ~= "table" or not candidate.clothing then
        return nil, nil, "invalid_emergency_clothing"
    end
    local utility = U()
    local item = candidate.clothing
    if not inventoryContains(inventory, item) then return nil, nil, "clothing_missing" end
    if candidate.worn then
        local result, removed = utility.call(candidate.character, "removeWornItem", item, false)
        if not removed or result == false or isWorn(candidate.character, item) then
            return nil, nil, "clothing_unequip_failed"
        end
    end
    if not inventoryRemove(inventory, item) then
        local restored = not candidate.worn
            or restoreWornItem(candidate.character, item, candidate.wornLocation)
        return nil, nil, restored and "clothing_remove_failed"
            or "clothing_remove_rollback_failed"
    end
    local rag = utility.addItem(inventory, candidate.material or "Base.RippedSheets")
    if not rag then
        local restored = restoreInventoryItem(inventory, item)
        if candidate.worn then
            restored = restoreWornItem(candidate.character, item,
                candidate.wornLocation) and restored
        end
        return nil, nil, restored and "rag_creation_failed"
            or "rag_creation_rollback_failed"
    end
    return rag, {
        character = candidate.character,
        clothing = item,
        rag = rag,
        wornLocation = candidate.wornLocation,
    }, nil
end

local function rollbackEmergencyBandage(inventory, transaction)
    if type(transaction) ~= "table" then return true end
    local ok = true
    if transaction.rag and inventoryContains(inventory, transaction.rag) then
        ok = inventoryRemove(inventory, transaction.rag) and ok
    end
    if transaction.clothing then
        ok = restoreInventoryItem(inventory, transaction.clothing) and ok
        if transaction.wornLocation then
            ok = restoreWornItem(
                transaction.character,
                transaction.clothing,
                transaction.wornLocation
            ) and ok
        end
    end
    return ok
end

-- Bleeding first; with care included, then a wound that stopped bleeding
-- undressed, then a soiled dressing.
local function chooseWound(assessment, includeCare)
    for _, wound in ipairs(assessment.wounds) do
        if wound.bleeding and not wound.bandaged then return wound end
    end
    if includeCare then
        for _, wound in ipairs(assessment.wounds) do
            if wound.openWound then return wound end
        end
        for _, wound in ipairs(assessment.wounds) do
            if wound.dirtyBandage then return wound end
        end
    end
    return nil
end

local function bandageSnapshot(wound)
    local previous = {
        bandaged = wound.bandaged == true,
        dirty = wound.dirtyBandage == true,
        life = numberMethod(wound.part, { "getBandageLife" }, 0),
        alcoholic = booleanMethod(wound.part, { "isAlcoholicBandage" }),
        bandageType = nil,
    }
    local bandageType, typeOk = U().call(wound.part, "getBandageType")
    if typeOk then previous.bandageType = bandageType end
    return previous
end

local function restoreBandage(body, wound, previous)
    if not body or not wound or not previous then return false end
    local _, restored = U().call(
        body,
        "SetBandaged",
        wound.index,
        previous.bandaged,
        previous.life or 0,
        previous.alcoholic == true,
        previous.bandageType
    )
    return restored
end

-- How long a dressing lasts before it reads as dirty. Vanilla ISApplyBandage
-- is the dressing's own power PLUS a term for the First Aid of whoever applied
-- it: ZombRandFloat((doctor + 1) * 0.5, (doctor + 1) * 1.0). Only the item's
-- power was used here, so a companion's bandages went dirty two to four times
-- faster than the player's doing exactly the same thing with the same item,
-- and a trained medic got nothing at all for the training -- which is why they
-- spent their days re-dressing the same wounds. The midpoint of vanilla's
-- range is used rather than its roll: a deterministic result is worth more
-- here than reproducing the jitter.
local function bandageLifeFor(helper, bandage)
    local power = numberMethod(bandage, { "getBandagePower" }, 0)
    local doctor = 0
    local perks = type(_G) == "table" and rawget(_G, "Perks") or nil
    if perks ~= nil and helper ~= nil then
        local ok, value = pcall(function() return perks.Doctor end)
        if ok and value ~= nil then
            local level, called = U().call(helper, "getPerkLevel", value)
            if called then doctor = math.max(0, tonumber(level) or 0) end
        end
    end
    return math.max(1, (doctor + 1) * 0.75 + power)
end
Medical._bandageLifeForTests = bandageLifeFor

-- Vanilla's ISApplyBandage works on the BodyPart, and that setter stops the
-- bleed. This path goes through BodyDamage:SetBandaged, which only flips the
-- dressing flags, so the wound went on bleeding under a fresh bandage. Nothing
-- then ever finished: the part could not close while it bled, so it soiled its
-- dressing and was re-dressed, over and over, and Logistics read the same
-- untreated injury and scavenged medicine at urgent priority without end -- a
-- companion in the 25 September playtest re-bandaged all session and kept
-- refilling to five dressings. Produce vanilla's outcome explicitly.
local function stopBleeding(wound)
    local utility = U()
    local part = type(wound) == "table" and wound.part or nil
    if part == nil then return false end
    utility.call(part, "setBleeding", false)
    utility.call(part, "setBleedingTime", 0)
    return booleanMethod(part, { "bleeding", "isBleeding" }) ~= true
        and numberMethod(part, { "getBleedingTime" }, 0) <= 0
end
Medical._stopBleedingForTests = stopBleeding

local function commitBandage(patient, assessment, wound, bandage, inventory,
        emergencyTransaction, helper)
    local utility = U()
    if not assessment.bodyDamage or not wound or not bandage then return false, "invalid_treatment" end
    if not inventoryContains(inventory, bandage) then
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction)
        return false, rolledBack and "bandage_missing" or "treatment_rollback_failed"
    end
    local bandageLife = bandageLifeFor(helper or patient, bandage)
    -- As in vanilla, a dirty dressing goes on already soiled.
    if dirtyDressing(bandage) then bandageLife = 0 end
    local alcoholic = booleanMethod(bandage, { "isAlcoholic" })
    local fullType = utility.itemType(bandage)
    local previous = bandageSnapshot(wound)
    local _, applied = utility.call(
        assessment.bodyDamage,
        "SetBandaged",
        wound.index,
        true,
        bandageLife,
        alcoholic,
        fullType
    )
    if not applied then
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction)
        return false, rolledBack and "native_bandage_failed" or "treatment_rollback_failed"
    end
    -- Read back the wound before consuming the dressing (R2-07). The call-success
    -- flag above only proves the native setter returned normally; a no-op setter
    -- would report success without actually bandaging the part, and consuming the
    -- item then would silently waste it. Verify the postcondition here -- in the
    -- shared commit -- so both the companion and player-care callers get one
    -- verified result, and roll back (never consume) when it is unmet.
    if booleanMethod(wound.part, { "bandaged", "isBandaged" }) ~= true then
        local nativeRestored = restoreBandage(assessment.bodyDamage, wound, previous)
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction) and nativeRestored
        return false, rolledBack and "native_bandage_unverified" or "treatment_rollback_failed"
    end
    if not utility.consumeItem(inventory, bandage) then
        local nativeRestored = restoreBandage(assessment.bodyDamage, wound, previous)
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction) and nativeRestored
        return false, rolledBack and "bandage_consume_failed" or "treatment_rollback_failed"
    end
    -- Last, after everything that can still fail. Stopping the bleed earlier
    -- meant a dressing whose consumption failed rolled back the bandage and the
    -- clothing but left the wound cured: the treatment reported failure while
    -- the patient kept the benefit and the item. The snapshot restores the
    -- dressing, not the injury, so the injury must not be touched until the
    -- transaction can no longer be undone.
    --
    -- A dressing that is on the wound has stopped the bleeding, dirty or not.
    -- If the body part will not take the setter the dressing is still real, so
    -- the treatment stands and says so in the log rather than silently
    -- returning to the loop this was written to end.
    local wasBleeding = wound.bleeding == true
    if not stopBleeding(wound) and wasBleeding then
        utility.diagnostic("medical", helper or patient,
            "action=bandage part=" .. tostring(wound.name)
            .. " bleeding=unstopped type=" .. tostring(fullType))
    end
    return true, "bandaged"
end

local function supportsVisualLifecycle()
    return type(SC.NativeActions) == "table"
        and type(SC.NativeActions.visualStatus) == "function"
        and type(SC.NativeActions.clearVisual) == "function"
end

local function supervisor()
    return type(SC.ActionSupervisor) == "table" and SC.ActionSupervisor or nil
end

local function supervisedTransition(state, phase, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true, phase end
    return service.transition(state.supervisorToken, phase, detail)
end

local function supervisedCommit(state, operation, detail)
    local service = supervisor()
    if service and state and state.supervisorToken
        and type(service.commit) == "function" then
        return service.commit(state.supervisorToken, operation, detail)
    end
    if type(operation) ~= "function" then return true, "committed", operation end
    local ok, accepted, reason, receipt = pcall(operation, state and state.supervisorToken)
    if not ok then return false, "commit_callback_failed", { error = tostring(accepted) } end
    return accepted == true, reason, receipt
end

local function supervisedProgress(state, signature, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.progress(state.supervisorToken, signature, detail)
end

local function supervisedVisualExpected(state, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.expectVisual(state.supervisorToken, detail)
end

local function supervisedVisualVerified(state, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.markVisualVerified(state.supervisorToken, detail)
end

local function treatmentWound(assessment, state)
    for _, wound in ipairs(assessment.wounds or {}) do
        if wound.index == state.woundIndex then
            if state.dirtyOnly then
                if wound.dirtyBandage or wound.openWound then return wound end
            elseif (wound.bleeding and not wound.bandaged) or wound.dirtyBandage
                or wound.openWound then
                return wound
            end
        end
    end
    if state.dirtyOnly then
        for _, wound in ipairs(assessment.wounds or {}) do
            if wound.dirtyBandage then return wound end
        end
        for _, wound in ipairs(assessment.wounds or {}) do
            if wound.openWound then return wound end
        end
        return nil
    end
    return chooseWound(assessment, true)
end

local function releaseTreatmentResources(helper, state, reason)
    state = state or treatmentState[helper]
    if not state then return true, reason or "no_treatment" end
    local rolledBack = rollbackEmergencyBandage(state.inventory,
        state.emergencyTransaction)
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        local visual = state.phase == "ripping" and "rip_clothing_for_bandage"
            or state.phase == "bandaging" and (state.visualAction or "kneel_treat") or nil
        if visual then pcall(SC.NativeActions.cancelVisual, helper,
            reason or "medical_cancelled") end
    end
    if state.phase == "approaching" and SC.Navigation
        and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, helper, reason or "medical_cancelled")
    end
    if rolledBack then
        state.emergencyTransaction = nil
        treatmentState[helper] = nil
    end
    return rolledBack, rolledBack and (reason or "cancelled")
        or "treatment_rollback_failed"
end

local function clearTreatment(helper, state, reason, detail)
    local rolledBack, finalReason = releaseTreatmentResources(helper, state, reason)
    if not rolledBack then
        finalReason = "treatment_rollback_failed"
        if state then state.emergencyTransaction = nil end
        treatmentState[helper] = nil
    end
    local service = supervisor()
    local token = state and state.supervisorToken
    if service and token and service.isCurrent(token) then
        service.fail(token, finalReason or reason or "treatment_failed", detail)
    end
    return false, finalReason or reason or "treatment_failed"
end

local function startRipAnimation(helper, state)
    local expected, expectedReason = supervisedVisualExpected(state, {
        action = "rip_clothing_for_bandage",
        itemType = state.emergencyCandidate
            and U().itemType(state.emergencyCandidate.clothing) or nil,
    })
    if expected ~= true then return clearTreatment(helper, state,
        expectedReason or "visual_registration_failed") end
    local accepted, reason = U().move(helper, "walk", {
        action = "rip_clothing_for_bandage",
        item = state.emergencyCandidate and state.emergencyCandidate.clothing,
        emergency = state.emergency == true,
        durationTicks = 120,
        supervisorToken = state.supervisorToken,
    })
    if not accepted then return clearTreatment(helper, state,
        reason or "rip_action_rejected") end
    state.phase = "ripping"
    state.startedAt = U().nowMs()
    treatmentState[helper] = state
    local transitioned, transitionReason = supervisedTransition(state, "animating", {
        action = "rip_clothing_for_bandage",
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "animation_phase_rejected") end
    return true, "ripping_emergency_bandage"
end

local function startBandageAnimation(helper, state)
    local assessment = Medical.assess(state.patient)
    local wound = treatmentWound(assessment, state)
    if not wound then return clearTreatment(helper, state, "wound_no_longer_treatable") end
    if not inventoryContains(state.inventory, state.bandage) then
        return clearTreatment(helper, state, "bandage_missing")
    end
    local expected, expectedReason = supervisedVisualExpected(state, {
        action = state.visualAction or "kneel_treat", woundIndex = wound.index,
    })
    if expected ~= true then return clearTreatment(helper, state,
        expectedReason or "visual_registration_failed") end
    local accepted, reason = U().move(helper, "walk", {
        action = state.visualAction or "kneel_treat",
        patient = state.patient,
        bodyPartIndex = wound.index,
        bodyPart = wound.part,
        itemType = U().itemType(state.bandage),
        humanAnimationOnly = true,
        emergency = state.emergency == true,
        durationTicks = 100,
        supervisorToken = state.supervisorToken,
    })
    if not accepted then
        return clearTreatment(helper, state, reason or "treatment_action_rejected")
    end
    state.phase = "bandaging"
    state.woundIndex = wound.index
    state.startedAt = U().nowMs()
    treatmentState[helper] = state
    local transitioned, transitionReason = supervisedTransition(state, "animating", {
        action = state.visualAction or "kneel_treat",
        woundIndex = wound.index,
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "animation_phase_rejected") end
    return true, "treatment_animation_started"
end

local function beginEmergencyApplyToken(helper, state, parentSerial)
    local service = supervisor()
    if not service then return true, "unsupervised" end
    local token, reason, retry = service.begin(helper, {
        owner = "medical", action = state.supervisorAction or "treat_wound",
        targetKey = state.targetKey,
        targetLabel = tostring(U().nameOf(state.patient)) .. " "
            .. tostring(state.woundName),
        priority = state.supervisorPriority or service.Priority.COMBAT_RESCUE,
        interruptible = true, requiresVisual = false,
        allowedActions = {
            kneel_treat = true, replace_bandage = true,
        },
        onCancel = function(_, cancelReason)
            return releaseTreatmentResources(helper, state,
                cancelReason or "medical_cancelled")
        end,
        metadata = {
            woundIndex = state.woundIndex, emergencyStage = "apply",
            parentCommitSerial = parentSerial,
        },
    })
    if not token then
        if service.containsDeferredStatus and service.containsDeferredStatus(reason) then
            -- Urgent survival work was dispatched for this actor during begin(); the
    -- companion is committed to it this cycle.  That is the urgent succeeding,
    -- not this action failing, so report a deferral the decision layer can
    -- recognise instead of a refusal that would cool the target down.
            return false, "deferred:" .. tostring(reason)
        end
        return false, reason or "medical_apply_owner_rejected", retry
    end
    state.supervisorToken = token
    local reserved, reserveReason = service.reserve(token, state.bandage,
        "emergency_bandage")
    if reserved ~= true then
        service.fail(token, reserveReason or "reservation_lost")
        state.supervisorToken = nil
        return false, reserveReason or "reservation_lost"
    end
    return true, "emergency_apply_selected"
end

local function finishEmergencyRip(helper, state, startVisual)
    local committing, commitReason = supervisedTransition(state, "committing", {
        action = "rip_clothing_for_bandage",
    })
    if committing ~= true then return clearTreatment(helper, state,
        commitReason or "commit_rejected") end

    local rag, transaction
    local committed, reason = supervisedCommit(state, function()
        local failure
        rag, transaction, failure = commitEmergencyBandage(
            state.inventory, state.emergencyCandidate)
        if not rag then
            return false, failure or "rag_creation_failed", {
                stage = "emergency_rip",
            }
        end
        return true, "emergency_bandage_created", {
            stage = "emergency_rip", itemType = U().itemType(rag),
        }
    end)
    if committed ~= true then return clearTreatment(helper, state,
        reason or "rag_creation_failed") end

    -- The rip is finished and final: the rag is kept even if applying it is
    -- interrupted, so the next attempt uses it instead of tearing again.
    -- Putting the clothing back made an interrupted treatment tear the same
    -- clothing over and over while the wound kept bleeding.
    state.bandage = rag
    state.emergencyRag = true
    state.emergencyTransaction = nil
    state.emergencyCandidate = nil
    local verifying, verifyReason = supervisedTransition(state, "verifying", {
        itemType = U().itemType(rag), stage = "emergency_rip",
    })
    if verifying ~= true or not inventoryContains(state.inventory, rag) then
        return clearTreatment(helper, state,
            verifyReason or "rag_verification_failed")
    end

    local service = supervisor()
    local parentToken = state.supervisorToken
    local urgent = service and type(service.urgentStatus) == "function"
        and service.urgentStatus(helper) or nil
    if service and parentToken and service.isCurrent(parentToken) then
        local completed, completeReason = service.complete(parentToken,
            "emergency_bandage_created", {
                itemType = U().itemType(rag), stage = "emergency_rip",
            })
        if completed ~= true then return clearTreatment(helper, state,
            completeReason or "emergency_rip_completion_failed") end
    end
    state.supervisorToken = nil

    -- Completion releases a queued survival intent. Do not immediately claim a
    -- second token over that hand-off; the rag stays for the next attempt.
    if urgent and (urgent.state == "queued" or urgent.state == "waiting_external") then
        local rolledBack = releaseTreatmentResources(helper, state,
            "urgent_preempted_after_emergency_rip")
        return false, rolledBack and "urgent_preempted_after_emergency_rip"
            or "treatment_rollback_failed"
    end

    local began, beginReason = beginEmergencyApplyToken(helper, state,
        parentToken and parentToken.serial or nil)
    if began ~= true then
        local rolledBack = releaseTreatmentResources(helper, state,
            beginReason or "emergency_apply_owner_rejected")
        return false, rolledBack and (beginReason or "emergency_apply_owner_rejected")
            or "treatment_rollback_failed"
    end
    if startVisual ~= false then return startBandageAnimation(helper, state) end
    return true, "emergency_apply_selected"
end

local function finishTreatment(helper, state)
    local assessment = Medical.assess(state.patient)
    local wound = treatmentWound(assessment, state)
    if not wound then return clearTreatment(helper, state, "wound_no_longer_treatable") end
    local committing, commitReason = supervisedTransition(state, "committing", {
        woundIndex = wound.index, itemType = U().itemType(state.bandage),
    })
    if committing ~= true then return clearTreatment(helper, state,
        commitReason or "commit_rejected") end
    local applied, reason = supervisedCommit(state, function()
        local accepted, result = commitBandage(state.patient, assessment, wound,
            state.bandage, state.inventory, state.emergencyTransaction, helper)
        return accepted, result, {
            stage = "apply_bandage", woundIndex = wound.index,
            itemType = U().itemType(state.bandage),
        }
    end)
    if not applied then return clearTreatment(helper, state, reason) end
    state.emergencyTransaction = nil
    local verifying, verifyReason = supervisedTransition(state, "verifying", {
        woundIndex = wound.index,
    })
    if verifying ~= true then
        treatmentState[helper] = nil
        local service = supervisor()
        if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
            service.fail(state.supervisorToken, verifyReason or "verification_failed")
        end
        return false, verifyReason or "verification_failed"
    end
    local verifiedAssessment = Medical.assess(state.patient)
    local verifiedWound
    for _, candidate in ipairs(verifiedAssessment.wounds or {}) do
        if candidate.index == wound.index then verifiedWound = candidate break end
    end
    if not verifiedWound or verifiedWound.bandaged ~= true
        or (verifiedWound.dirtyBandage == true and not dirtyDressing(state.bandage)) then
        treatmentState[helper] = nil
        local service = supervisor()
        if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
            service.fail(state.supervisorToken, "verification_failed", {
                woundIndex = wound.index,
            })
        end
        return false, "verification_failed"
    end
    treatmentState[helper] = nil
    if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
        SC.NativeActions.noteResult(helper, "medical_treatment", "bandaged", {
            kind = "long",
        })
    end
    local service = supervisor()
    if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
        service.complete(state.supervisorToken, "bandaged", {
            woundIndex = wound.index, patientId = U().idOf(state.patient), verified = true,
        })
    end
    -- Only a verified dressing reaches a private diary, with its real helper.
    if SC.Diary and type(SC.Diary.noteBandage) == "function" then
        local player = type(getPlayer) == "function" and getPlayer() or nil
        pcall(SC.Diary.noteBandage, helper, state.patient, player, wound.name, {
            bleeding = wound.bleeding == true, tornClothing = state.emergencyRag == true,
        })
    end
    return true, "bandaged"
end

local continueTreatmentApproach

local function advanceTreatment(helper, state)
    if not Medical.isLivingPatient(state.patient) then
        return clearTreatment(helper, state, "patient_no_longer_alive")
    end
    if state.phase == "approaching" then
        return continueTreatmentApproach(helper, state)
    end
    local expected = state.phase == "ripping" and "rip_clothing_for_bandage"
        or state.visualAction or "kneel_treat"
    local visualState = SC.NativeActions.visualStatus(helper, expected)
    if visualState == "active" then
        supervisedProgress(state, "visual:" .. tostring(state.phase)
            .. ":" .. tostring(state.startedAt), { visual = expected })
        return true, state.phase == "ripping" and "ripping_emergency_bandage"
            or "treatment_animation_active"
    end
    if visualState ~= "completed" then
        if visualState ~= "different" then SC.NativeActions.clearVisual(helper) end
        -- Surface why a treatment animation ended without completing (e.g. a rip
        -- that never finishes), so a repeated failure is diagnosable instead of
        -- silent. Bounded by the diagnostics circuit breaker.
        if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("medical", U().idOf(helper),
                "treatment animation did not complete",
                tostring(state.phase) .. ":" .. tostring(visualState))
        end
        return clearTreatment(helper, state, "treatment_animation_" .. tostring(visualState))
    end
    SC.NativeActions.clearVisual(helper)
    local verified, verifyReason = supervisedVisualVerified(state, {
        action = expected,
    })
    if verified ~= true then return clearTreatment(helper, state,
        verifyReason or "animation_verification_failed") end
    if state.phase == "ripping" then
        return finishEmergencyRip(helper, state, true)
    end
    return finishTreatment(helper, state)
end

-- Compatibility path for the isolated gameplay harness. The shipping runtime
-- always loads SCNativeActions and therefore always uses the staged lifecycle.
local function immediateTreatment(helper, patient, assessment, wound, bandage,
        inventory, emergencyTransaction, visualAction, state)
    local accepted = U().move(helper, "walk", {
        action = visualAction or "kneel_treat", patient = patient,
        bodyPartIndex = wound.index, bodyPart = wound.part,
        itemType = U().itemType(bandage), humanAnimationOnly = true,
        emergency = wound.bleeding == true,
        supervisorToken = state and state.supervisorToken,
    })
    if not accepted then
        return clearTreatment(helper, state or {
            inventory = inventory, emergencyTransaction = emergencyTransaction,
        }, "treatment_action_rejected")
    end
    state = state or {
        patient = patient, woundIndex = wound.index, bandage = bandage,
        inventory = inventory, emergencyTransaction = emergencyTransaction,
        visualAction = visualAction,
    }
    state.bandage = bandage
    state.emergencyTransaction = emergencyTransaction
    return finishTreatment(helper, state)
end

local function treatmentSquare(helper, patient)
    local utility = U()
    local patientSquare = utility.squareOf(patient)
    local x, y, z = utility.position(patientSquare)
    if not x then return nil end
    local best, bestDistance = nil, math.huge
    for _, delta in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local square = utility.gridSquare(x + delta[1], y + delta[2], z)
        if square and utility.isSquareFree(square) and not utility.edgeBlocked(square, patientSquare) then
            local distance = utility.distanceSq(helper, square)
            if distance < bestDistance then best, bestDistance = square, distance end
        end
    end
    return best or patientSquare
end

local function rescueViable(helper, snapshot)
    if type(snapshot) ~= "table" then return true end
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    local escapeCount = #(snapshot.escapeSquares or {})
    if immediate >= 2 then return false end
    if escapeCount == 0 and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) >= 2 then return false end
    return true
end

-- Self-bandaging is low priority: the companion must not stop to patch itself in
-- active combat. Only allow it when at least semi-safe -- nothing attacking in
-- melee range and not pinned by a crowd with no way out -- so it fights or
-- repositions first and treats the wound once the danger eases. Low health alone
-- never creates a downed state or a treatment that cannot affect that health.
local function bandageSemiSafe(helper, snapshot)
    if not rescueViable(helper, snapshot) then return false end
    if type(snapshot) ~= "table" then return true end
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    if immediate >= 1 then return false end
    local threats = tonumber(snapshot.threatCount) or #(snapshot.threats or {})
    local escapeCount = #(snapshot.escapeSquares or {})
    if threats >= 1 and escapeCount == 0 then return false end
    return true
end

local function treatmentCapability(helper, patient, options)
    options = type(options) == "table" and options or {}
    local assessment = Medical.assess(patient)
    if not Medical.isLivingPatient(patient, assessment) then return nil, "invalid_patient" end
    local wound
    if options.dirtyOnly then
        -- Quiet-time wound care: change a soiled dressing first, then dress a
        -- wound that stopped bleeding before anyone covered it.
        for _, value in ipairs(assessment.wounds or {}) do
            if value.dirtyBandage then wound = value break end
        end
        if not wound then
            for _, value in ipairs(assessment.wounds or {}) do
                if value.openWound then wound = value break end
            end
        end
    else
        wound = chooseWound(assessment, true)
    end
    if not wound then return nil, "no_treatable_wound" end
    -- A dirty dressing may stop fresh bleeding, but never replaces a dressing
    -- or covers a wound that has already stopped bleeding.
    local bandage, inventory = findBandage(helper,
        options.dirtyOnly ~= true and wound.bleeding == true and wound.bandaged ~= true)
    local clothing, candidate, failure
    if not bandage then
        clothing, inventory, candidate, failure = emergencyClothing(helper)
        if not clothing then
            return {
                assessment = assessment, wound = wound, inventory = inventory,
                dirtyOnly = options.dirtyOnly == true,
            }, options.dirtyOnly and "no_clean_bandage"
                or (failure == "no_expendable_clothing" and "no_bandage" or failure or "no_bandage")
        end
    end
    return {
        assessment = assessment, wound = wound, inventory = inventory,
        bandage = bandage, emergencyCandidate = candidate,
        dirtyOnly = options.dirtyOnly == true,
        visualAction = options.visualAction,
        available = true,
    }
end

function Medical.canReplaceDirtyBandage(actor)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    local capability, reason = treatmentCapability(actor, actor, {
        dirtyOnly = true, visualAction = "replace_bandage",
    })
    return capability ~= nil and capability.available == true,
        reason or (capability and "ready" or "no_treatable_wound"), capability
end

local function beginTreatmentState(helper, patient, capability)
    local wound = capability.wound
    local action = capability.dirtyOnly and "replace_dirty_bandage" or "treat_wound"
    local targetKey = tostring(U().idOf(patient) or "patient") .. ":"
        .. tostring(wound.index)
    local service = supervisor()
    local priority = service and (wound.bleeding and service.Priority.COMBAT_RESCUE
        or service.Priority.NEEDS) or nil
    local state = {
        phase = "selected", patient = patient, woundIndex = wound.index,
        woundName = wound.name, dirtyOnly = capability.dirtyOnly == true,
        emergency = wound.bleeding == true,
        inventory = capability.inventory, bandage = capability.bandage,
        emergencyCandidate = capability.emergencyCandidate,
        visualAction = capability.visualAction,
        targetKey = targetKey,
        supervisorAction = action, supervisorPriority = priority,
    }
    if service then
        local priorRetry = capability.available == true
            and service.retryStatusAny(helper, action, targetKey) or nil
        if priorRetry and priorRetry.category == "resources"
            and type(service.resetRetry) == "function" then
            service.resetRetry(helper, "medical_resources_available", action, targetKey)
        end
        local token, reason, retry = service.begin(helper, {
            owner = "medical", action = action, targetKey = targetKey,
            targetLabel = tostring(U().nameOf(patient)) .. " " .. tostring(wound.name),
            priority = priority,
            interruptible = true, requiresVisual = false,
            -- With supplies present a repeatedly-failing treatment (e.g. a rip that
            -- never completes) previously had no retry cooldown, so it re-attempted
            -- every tick and locked the companion in a "trying to rip, never doing
            -- it" loop. Give it a bounded backoff so it gives up and clears instead
            -- of looping; the resources category still resets when supplies return.
            retryCategory = capability.available and "treatment" or "resources",
            allowedActions = {
                move_to_treat = true, kneel_treat = true, replace_bandage = true,
                rip_clothing_for_bandage = true,
            },
            onCancel = function(_, cancelReason)
                return releaseTreatmentResources(helper, state,
                    cancelReason or "medical_cancelled")
            end,
            metadata = { woundIndex = wound.index, dirtyOnly = capability.dirtyOnly == true },
        })
        if not token then
            if service.containsDeferredStatus and service.containsDeferredStatus(reason) then
                -- Urgent survival work was dispatched for this actor during begin(); the
        -- companion is committed to it this cycle.  That is the urgent succeeding,
        -- not this action failing, so report a deferral the decision layer can
        -- recognise instead of a refusal that would cool the target down.
                return nil, "deferred:" .. tostring(reason)
            end
            return nil, reason or "medical_owner_rejected", retry
        end
        state.supervisorToken = token
        if capability.available ~= true then
            service.fail(token, capability.dirtyOnly and "no_clean_bandage" or "no_supplies", {
                woundIndex = wound.index,
            })
            return nil, capability.dirtyOnly and "no_clean_bandage" or "no_bandage"
        end
        local resource = capability.bandage
            or capability.emergencyCandidate and capability.emergencyCandidate.clothing
        if resource then
            local reserved, reserveReason = service.reserve(token, resource, "medical_supply")
            if reserved ~= true then
                service.fail(token, reserveReason or "reservation_lost")
                return nil, reserveReason or "reservation_lost"
            end
        end
    elseif capability.available ~= true then
        return nil, capability.dirtyOnly and "no_clean_bandage" or "no_bandage"
    end
    treatmentState[helper] = state
    return state, "selected"
end

continueTreatmentApproach = function(helper, state, runtime)
    local utility = U()
    if not utility.isValidActor(state.patient) then
        return clearTreatment(helper, state, "invalid_target")
    end
    local rootRuntime = utility.actorState(helper, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    -- Self-treatment holds to the stricter semi-safe bar so a threat closing back
    -- in preempts a mid-combat self-bandage; rescuing another still uses the
    -- rescue viability bar.
    local selfTreatment = state.patient == helper
    local stillViable = selfTreatment and bandageSemiSafe(helper, snapshot)
        or (not selfTreatment and rescueViable(helper, snapshot))
    if not stillViable then
        return Medical.cancel(helper, "danger_preempted")
    end
    -- Bound the approach: if the helper can never settle within medical range (an
    -- unreachable or position-unavailable patient makes the distance read math.huge),
    -- the treatment would otherwise navigate forever, returning "arrived" every tick
    -- (observed in the sandbox as arrived x529). Give up after a budget so it clears
    -- instead of looping.
    if state.phase == "approaching" and state.approachStartedAt
        and utility.nowMs() - state.approachStartedAt
            > (utility.config("medicalApproachTimeoutMs") or 8000) then
        return clearTreatment(helper, state, "approach_timeout")
    end
    if utility.distance(helper, state.patient) <= (utility.config("medicalRange") or 1.35) then
        utility.stop(helper)
        local settled, settleReason = supervisedTransition(state, "settling", {
            patientId = U().idOf(state.patient),
        })
        if settled ~= true then return clearTreatment(helper, state,
            settleReason or "settle_rejected") end
        if state.emergencyCandidate then
            if supportsVisualLifecycle() then return startRipAnimation(helper, state) end
            local accepted = utility.move(helper, "walk", {
                action = "rip_clothing_for_bandage",
                item = state.emergencyCandidate.clothing,
                emergency = state.emergency,
                supervisorToken = state.supervisorToken,
            })
            if not accepted then return clearTreatment(helper, state, "rip_action_rejected") end
            local finished, finishReason = finishEmergencyRip(helper, state, false)
            if finished ~= true then return false, finishReason end
        end
        if supportsVisualLifecycle() then return startBandageAnimation(helper, state) end
        return immediateTreatment(helper, state.patient, Medical.assess(state.patient),
            treatmentWound(Medical.assess(state.patient), state), state.bandage,
            state.inventory, state.emergencyTransaction, state.visualAction, state)
    end
    local navigation = SC.Navigation
    if type(navigation) ~= "table" or type(navigation.requestAny) ~= "function" then
        return clearTreatment(helper, state, "navigation_unavailable")
    end
    local targets = navigation.interactionTargets(helper, state.patient, {
        snapshot = snapshot, maximum = 4,
    })
    local fallback = treatmentSquare(helper, state.patient)
    if #targets == 0 and fallback then targets[1] = fallback end
    if #targets == 0 then return clearTreatment(helper, state, "no_interaction_point") end
    local transitioned, transitionReason = supervisedTransition(state, "approaching", {
        patientId = U().idOf(state.patient), candidates = #targets,
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "approach_rejected") end
    state.phase = "approaching"
    state.approachStartedAt = state.approachStartedAt or utility.nowMs()
    local ok, status = navigation.requestAny(helper, targets, "walk", {
        action = "move_to_treat", patient = state.patient, snapshot = snapshot,
        arrivalDistance = 0.9, supervisorToken = state.supervisorToken,
    })
    if not ok then return clearTreatment(helper, state, status or "route_failed") end
    supervisedProgress(state, "approach:" .. tostring(status), {
        status = status, patientId = U().idOf(state.patient),
    })
    return true, status or "approaching_patient"
end

function Medical.treat(helper, patient, runtime, options)
    local utility = U()
    if not utility.isValidActor(helper) or not utility.isValidActor(patient) then return false, "invalid_patient" end
    local active = treatmentState[helper]
    if active then return advanceTreatment(helper, active, runtime) end
    options = type(options) == "table" and options or {}
    local capability, capabilityReason = treatmentCapability(helper, patient, options)
    if not capability then return false, capabilityReason or "no_treatable_wound" end
    local rootRuntime = utility.actorState(helper, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if not rescueViable(helper, snapshot) then return false, "unsafe_rescue" end
    local state, stateReason = beginTreatmentState(helper, patient, capability)
    if not state then return false, stateReason or capabilityReason or "medical_owner_rejected" end
    return continueTreatmentApproach(helper, state, rootRuntime)
end

-- Player-initiated care: the local player treats a companion's wound with a
-- bandage from the player's own inventory. Preflight validates a treatable wound,
-- an available bandage, and range without changing any state, so the context menu
-- can gate the option and a timed action can re-check on completion. Returns
-- (ok, reason, context) where context carries the resolved wound/bandage.
function Medical.playerBandagePreflight(companion, player)
    local utility = U()
    if not utility.isValidActor(companion) then return false, "invalid_companion" end
    if not utility.isValidActor(player) then return false, "invalid_player" end
    local assessment = Medical.assess(companion)
    if not Medical.isLivingPatient(companion, assessment) then return false, "invalid_companion" end
    local wound = chooseWound(assessment, true)
    if not wound then return false, "no_treatable_wound" end
    local bandage, inventory = findBandage(player,
        wound.bleeding == true and wound.bandaged ~= true)
    if not bandage then return false, "no_bandage" end
    local range = tonumber(utility.config("medicalPlayerBandageRange")) or 2.0
    if utility.distance(player, companion) > range then return false, "out_of_range" end
    return true, "ready", {
        assessment = assessment, wound = wound, bandage = bandage, inventory = inventory,
    }
end

-- Commit the player's bandage onto the companion's wound. Re-runs the preflight so
-- a timed action that started while valid still refuses if the wound was already
-- treated, the bandage was consumed, or the player walked away; then applies the
-- same transactional, verified bandage the companion's own care uses, consuming
-- the item from the player's inventory.
function Medical.applyPlayerBandage(companion, player)
    local ok, reason, context = Medical.playerBandagePreflight(companion, player)
    if not ok then return false, reason end
    local applied, applyReason = commitBandage(companion, context.assessment, context.wound,
        context.bandage, context.inventory, nil, player)
    if not applied then return false, applyReason or "bandage_failed" end
    if SC.Diary and type(SC.Diary.noteBandage) == "function" then
        pcall(SC.Diary.noteBandage, player, companion, player, context.wound.name, {
            bleeding = context.wound.bleeding == true,
        })
    end
    return true, "bandaged"
end

function Medical.noteReceivingCare(companion, player, current)
    if companion == nil then return false end
    current = tonumber(current) or U().nowMs()
    receivingCare[companion] = {
        player = player,
        untilAt = current + (tonumber(U().config("medicalReceivingCareHoldMs")) or 6000),
    }
    return true
end

function Medical.clearReceivingCare(companion)
    if companion ~= nil then receivingCare[companion] = nil end
end

function Medical.isReceivingCare(actor, current)
    local entry = actor and receivingCare[actor] or nil
    if not entry then return false end
    current = tonumber(current) or U().nowMs()
    if current > (tonumber(entry.untilAt) or 0) then
        receivingCare[actor] = nil
        return false
    end
    return true
end

-- Why this companion cannot dress its own wound right now, or nil when it can
-- (it carries a bandage, or clothing it can tear into one).
function Medical.selfCareBlocker(actor)
    if not U().isValidActor(actor) then return "invalid_actor" end
    local capability, reason = treatmentCapability(actor, actor, {})
    if type(capability) == "table" and capability.available == true then return nil end
    return reason or "no_bandage"
end

local HELP_LINES = {
    common = {
        "I'm bleeding and I've got nothing to wrap it with!",
        "I need a bandage. Anything clean. Now would be good.",
        "I'm hit and I'm leaking. Got a bandage?",
        "Somebody patch me up before I paint the floor.",
    },
    brave = { "Just a scratch. A big, bleeding scratch. Bandage?" },
    cautious = { "I'm losing blood. A bandage, please, before it gets worse." },
    caring = { "I hate asking, but I need a bandage. I'm bleeding." },
    practical = { "Bleeding, no dressing. I need a bandage or a clean rag." },
    stressed = { "I'm bleeding out here! Bandage! Please!" },
}

-- A bleeding companion that cannot treat itself asks the player for a bandage,
-- at most once per cooldown.
function Medical.requestHelp(actor, player, current)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    current = tonumber(current) or U().nowMs()
    if current - (helpRequestedAt[actor] or -math.huge)
        < (tonumber(U().config("medicalHelpRequestCooldownMs")) or 45000) then
        return false, "help_request_cooldown"
    end
    helpRequestedAt[actor] = current
    local assessment = Medical.assess(actor)
    U().diagnostic("medical", actor, "action=seek_care bleeding="
        .. tostring(assessment.bleedingCount or 0)
        .. " health=" .. tostring(math.floor(tonumber(assessment.health) or 0))
        .. " selfCare=" .. tostring(Medical.selfCareBlocker(actor) or "able"))
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        pcall(SC.Dialogue.say, actor, "medical.need_bandage", HELP_LINES)
    end
    return true, "help_requested"
end

-- One line describing a companion's body at death, for the log.
function Medical.deathSummary(actor)
    local assessment = Medical.assess(actor)
    local parts = {}
    for index, wound in ipairs(assessment.wounds or {}) do
        if index > 6 then break end
        local tags = {}
        if wound.bleeding then tags[#tags + 1] = "bleeding" end
        if wound.bitten then tags[#tags + 1] = "bite" end
        if wound.deepWound then tags[#tags + 1] = "deep" end
        if wound.scratched then tags[#tags + 1] = "scratch" end
        if wound.cut then tags[#tags + 1] = "cut" end
        if wound.lodged then tags[#tags + 1] = "lodged" end
        if wound.fractured then tags[#tags + 1] = "fracture" end
        if wound.burned then tags[#tags + 1] = "burn" end
        if wound.infected then tags[#tags + 1] = "infected" end
        if wound.bandaged then
            tags[#tags + 1] = wound.dirtyBandage and "dirty_bandage" or "bandaged"
        end
        parts[#parts + 1] = tostring(wound.name) .. ":" .. table.concat(tags, "+")
    end
    return "died health=" .. tostring(math.floor(tonumber(assessment.health) or 0))
        .. " bleeding=" .. tostring(assessment.bleedingCount or 0)
        .. " bites=" .. tostring(assessment.bites or 0)
        .. " knox=" .. tostring(assessment.knoxInfected == true)
        .. " infection=" .. tostring(math.floor(tonumber(assessment.infectionLevel) or 0))
        .. " wounds=" .. (#parts > 0 and table.concat(parts, ",") or "none")
end

local function leaveDowned(actor, runtime)
    local utility = U()
    if not utility.move(actor, "walk", { action = "recover_from_downed", immobile = false }) then
        return false, "recovery_action_rejected"
    end
    downed[actor] = nil
    if type(runtime) == "table" then
        runtime.downed = nil
        runtime.needsRescue = nil
    end
    return true, "recovered"
end

function Medical.isDowned(actor)
    return actor ~= nil and downed[actor] ~= nil
end

local function rescueCandidate(actor, player, snapshot)
    local utility = U()
    local best, bestScore
    local function consider(candidate, relationship)
        if not candidate or candidate == actor or not utility.isValidActor(candidate) then return end
        if relationship ~= nil and SC.Factions
            and type(SC.Factions.areAlliesBetween) == "function" then
            local ok, allied = pcall(SC.Factions.areAlliesBetween,
                actor, candidate, player)
            if not ok or allied ~= true then return end
        end
        local assessment = Medical.assess(candidate)
        if not Medical.hasActionableNeed(candidate, assessment, false) then return end
        local score = (assessment.downed and 80 or 0)
            + assessment.bleedingCount * 25
            + math.max(0, 50 - assessment.health)
            - utility.distance(actor, candidate) * 2
        if not bestScore or score > bestScore then best, bestScore = candidate, score end
    end
    consider(player)
    if snapshot and type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do
            consider(ally.actor, ally.relationship)
        end
    end
    return best
end

function Medical.update(actor, player, runtime)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local rootRuntime = utility.actorState(actor, runtime)
    local assessment = Medical.assess(actor, rootRuntime)
    rootRuntime.medicalAssessment = assessment

    if not assessment.alive or assessment.health <= 0 or assessment.terminalKnox then
        if treatmentState[actor] then Medical.cancel(actor,
            assessment.terminalKnox and "terminal_knox" or "death", true) end
        downed[actor] = nil
        rootRuntime.downed = nil
        return false, assessment.terminalKnox and "terminal_knox" or "dead"
    end

    if Medical.isReceivingCare(actor) then
        -- The player is bandaging this companion: stand still for it.
        utility.stop(actor)
        return true, "receiving_care"
    end
    if (tonumber(assessment.bleedingCount) or 0) > 0 then
        local names = {}
        for _, wound in ipairs(assessment.wounds or {}) do
            if wound.bleeding and not wound.bandaged and #names < 4 then
                names[#names + 1] = tostring(wound.name)
            end
        end
        utility.diagnostic("medical", actor, "bleeding=" .. tostring(assessment.bleedingCount)
            .. " health=" .. tostring(math.floor(tonumber(assessment.health) or 0))
            .. " parts=" .. table.concat(names, ","))
    end

    -- Knox and injuries lower a companion's health but never immobilize it. Like a
    -- player, it keeps acting -- fighting, fleeing, and being bandaged -- while its
    -- health drops, and only stops when it dies at zero health or turns at terminal
    -- Knox (handled above). Recover any companion still in a legacy health-downed
    -- state so it stands back up instead of lying frozen.
    if assessment.downed then
        return leaveDowned(actor, rootRuntime)
    end

    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if Medical.hasActionableNeed(actor, assessment, false) and bandageSemiSafe(actor, snapshot) then
        local ok, reason = Medical.treat(actor, actor, rootRuntime)
        if ok then return true, reason end
    end

    local explicitTarget = rootRuntime.rescueTarget
    local candidate = explicitTarget and Medical.hasActionableNeed(explicitTarget, nil, false)
        and explicitTarget or rescueCandidate(actor, player, snapshot)
    if candidate and rescueViable(actor, snapshot) then
        local ok, reason = Medical.treat(actor, candidate, rootRuntime)
        if ok then return true, reason end
    end
    -- Quiet-time wound care, also offered by the decision outside downtime:
    -- dress a wound that stopped bleeding undressed or change a soiled
    -- dressing, and carry on with one already under way.
    if ((tonumber(assessment.openWounds) or 0) > 0
            or (tonumber(assessment.dirtyBandages) or 0) > 0
            or treatmentState[actor] ~= nil)
        and bandageSemiSafe(actor, snapshot) then
        local ok, reason = Medical.replaceDirtyBandage(actor)
        if ok then return true, reason end
    end
    return false, "no_medical_action"
end

function Medical.replaceDirtyBandage(actor)
    return Medical.treat(actor, actor, nil, {
        dirtyOnly = true, visualAction = "replace_bandage",
    })
end

function Medical.replaceDirtyBandageAfterVisual(actor)
    -- Kept as a compatibility entry point, but it no longer commits after a
    -- foreign downtime visual. Medical owns selection, animation and commit.
    return Medical.replaceDirtyBandage(actor)
end

function Medical.cancel(actor, reason, force)
    local state = actor and treatmentState[actor] or nil
    if not state then return true, "no_active_treatment" end
    local service = supervisor()
    if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
        return service.cancel(actor, reason or "medical_cancelled", nil, force == true)
    end
    return releaseTreatmentResources(actor, state, reason or "medical_cancelled")
end

function Medical.peek(actor)
    local state = actor and treatmentState[actor] or nil
    if not state then return nil end
    return {
        phase = state.phase, patient = state.patient, woundIndex = state.woundIndex,
        woundName = state.woundName, dirtyOnly = state.dirtyOnly,
        emergency = state.emergency, startedAt = state.startedAt,
        supervisorToken = state.supervisorToken,
    }
end

function Medical.statusText(character)
    local utility = U()
    local assessment = Medical.assess(character)
    if not assessment.alive then return utility.text("UI_SC_Status_Dead", "Dead") end
    if assessment.terminalKnox then return utility.text("UI_SC_Status_TerminalKnox", "Terminal Knox infection") end
    if assessment.knoxInfected then
        return utility.text("UI_SC_Status_Knox", "Knox symptoms") .. " (" .. tostring(math.floor(assessment.infectionLevel)) .. "%)"
    end
    if assessment.downed then return utility.text("UI_SC_Status_Downed", "Downed") end
    if assessment.bleedingCount > 0 then
        return utility.text("UI_SC_Status_Bleeding", "Bleeding") .. " (" .. tostring(assessment.bleedingCount) .. ")"
    end
    if assessment.woundCount > 0 then return utility.text("UI_SC_Status_Wounded", "Wounded") end
    return utility.text("UI_SC_Status_Stable", "Stable")
end

function Medical.reset(actor)
    if actor then
        return Medical.releaseActor(actor)
    else
        for subject in pairs(receivingCare) do receivingCare[subject] = nil end
        for subject in pairs(helpRequestedAt) do helpRequestedAt[subject] = nil end
        local helpers = {}
        for helper in pairs(treatmentState) do helpers[#helpers + 1] = helper end
        for _, helper in ipairs(helpers) do
            local state = treatmentState[helper]
            local service = supervisor()
            if state and service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
                service.cancel(helper, "medical_reset_all", nil, true)
            elseif state then
                releaseTreatmentResources(helper, state, "medical_reset_all")
            end
        end
        downed = setmetatable({}, { __mode = "k" })
        treatmentState = setmetatable({}, { __mode = "k" })
    end
end

function Medical.releaseActor(actor)
    if actor == nil then return false end
    receivingCare[actor] = nil
    helpRequestedAt[actor] = nil
    local helpers = {}
    for helper, state in pairs(treatmentState) do
        if helper == actor or (state and state.patient == actor) then
            helpers[#helpers + 1] = helper
        end
    end
    for _, helper in ipairs(helpers) do
        local state = treatmentState[helper]
        local service = supervisor()
        if state and service and state.supervisorToken
            and service.isCurrent(state.supervisorToken) then
            service.cancel(helper, "medical_actor_released", nil, true)
        elseif state then
            releaseTreatmentResources(helper, state, "medical_actor_released")
        end
        treatmentState[helper] = nil
    end
    downed[actor] = nil
    return true
end

return Medical
