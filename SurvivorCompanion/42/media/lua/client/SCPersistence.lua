-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"
require "SCRegistry"
require "SCVitals"
require "SCDiagnostics"

local SC = SurvivorCompanion
SC.Persistence = SC.Persistence or {}

local persistence = SC.Persistence
local pending = {}
local pendingOrder = {}
local lastDocument = nil
local saveBlockedReason = nil
local targetedWorkKinds = { barricade = true, remove_barricade = true, dismantle = true }

local function method(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if not ok or type(value) ~= "function" then
        return nil
    end
    return value
end

local function invoke(object, name, ...)
    return SC.Call.method(object, name, ...)
end

local function staticInvoke(object, name, ...)
    return SC.Call.static(object, name, ...)
end

local function fieldValue(object, name)
    if object == nil then return false, nil end
    local ok, value = pcall(function() return object[name] end)
    return ok, value
end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function text(value, fallback, limit)
    value = value ~= nil and tostring(value) or tostring(fallback or "")
    value = string.gsub(value, "[%c]", "")
    if #value > limit then
        value = string.sub(value, 1, limit)
    end
    return value
end

local function boundedStableCopy(value, depth, remaining)
    if value == nil or type(value) == "boolean" or type(value) == "string" then
        return value
    end
    if type(value) == "number" then
        return finite(value, 0)
    end
    if type(value) ~= "table" or depth <= 0 or remaining.count <= 0 then
        return nil
    end
    local result = {}
    for key, child in pairs(value) do
        if remaining.count <= 0 then
            break
        end
        if type(key) == "string" or (type(key) == "number" and finite(key, nil) ~= nil) then
            remaining.count = remaining.count - 1
            local copy = boundedStableCopy(child, depth - 1, remaining)
            if copy ~= nil then
                result[key] = copy
            end
        end
    end
    return result
end

local function copyList(source, limit)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for index = 1, math.min(#source, limit) do
        local copy = boundedStableCopy(source[index], 3, { count = 32 })
        if copy ~= nil then
            result[#result + 1] = copy
        end
    end
    return result
end

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function listSize(list)
    if list == nil then
        return 0
    end
    if type(list) == "table" then
        if type(list.size) == "function" then
            local ok, count = pcall(list.size, list)
            if ok and tonumber(count) then return tonumber(count) end
        end
        return #list
    end
    local ok, count = invoke(list, "size")
    return ok and tonumber(count) or 0
end

local function listGet(list, index)
    if type(list) == "table" then
        if type(list.get) == "function" then
            local ok, value = pcall(list.get, list, index)
            if ok then return value end
        end
        return list[index + 1]
    end
    local ok, value = invoke(list, "get", index)
    return ok and value or nil
end

local function positionOf(actor)
    local squareOk, square = invoke(actor, "getCurrentSquare")
    local source = squareOk and square or actor
    local xOk, x = invoke(source, "getX")
    local yOk, y = invoke(source, "getY")
    local zOk, z = invoke(source, "getZ")
    if not xOk or not yOk then
        return nil
    end
    return {
        x = finite(x, nil),
        y = finite(y, nil),
        z = zOk and finite(z, 0) or 0,
    }
end

local function captureIdentity(record, actor)
    local source = type(record.identity) == "table" and record.identity or {}
    local female = source.gender == "female" or source.gender == "woman"
    local result = {
        forename = text(source.forename, "Fellow", 48),
        surname = text(source.surname, "Survivor", 48),
        gender = female and "female" or "male",
        visualSeed = math.floor(finite(source.visualSeed, 0)),
        outfit = text(source.outfit, "", 96),
    }
    local descriptorOk, descriptor = invoke(actor, "getDescriptor")
    if descriptorOk and descriptor ~= nil then
        local ok, value = invoke(descriptor, "getForename")
        if ok and value ~= nil then result.forename = text(value, result.forename, 48) end
        ok, value = invoke(descriptor, "getSurname")
        if ok and value ~= nil then result.surname = text(value, result.surname, 48) end
        ok, value = invoke(descriptor, "isFemale")
        if ok then result.gender = value == true and "female" or "male" end
    end
    local outfitOk, outfit = invoke(actor, "getOutfitName")
    if outfitOk and outfit ~= nil and tostring(outfit) ~= "" then
        result.outfit = text(outfit, result.outfit, 96)
    end
    return result
end

local scalarItemFields = {
    { key = "uses", getter = "getUses", setter = "setUses", kind = "integer" },
    { key = "usedDelta", getter = "getUsedDelta", setter = "setUsedDelta", kind = "number" },
    { key = "age", getter = "getAge", setter = "setAge", kind = "number" },
    { key = "offAge", getter = "getOffAge", setter = "setOffAge", kind = "integer" },
    { key = "offAgeMax", getter = "getOffAgeMax", setter = "setOffAgeMax", kind = "integer" },
    { key = "bloodLevel", getter = "getBloodLevel", setter = "setBloodLevel", kind = "number" },
    { key = "dirtiness", getter = "getDirtiness", setter = "setDirtiness", kind = "number" },
    { key = "wetness", getter = "getWetness", setter = "setWetness", kind = "number" },
    { key = "repairs", getter = "getHaveBeenRepaired", setter = "setHaveBeenRepaired", kind = "integer" },
    { key = "cooked", getter = "isCooked", setter = "setCooked", kind = "boolean" },
    { key = "burnt", getter = "isBurnt", setter = "setBurnt", kind = "boolean" },
    { key = "frozen", getter = "isFrozen", setter = "setFrozen", kind = "boolean" },
    { key = "activated", getter = "isActivated", setter = "setActivated", kind = "boolean" },
}

local function captureFluid(item)
    local fluidOk, fluid = invoke(item, "getFluidContainer")
    if not fluidOk or fluid == nil then return nil end
    local amountOk, amount = invoke(fluid, "getAmount")
    amount = amountOk and math.max(0, finite(amount, 0)) or 0
    local result = { amount = amount, fluids = {} }
    if amount <= 0 then return result end

    local sampleOk, sample = invoke(fluid, "createFluidSample")
    local sizeOk, size = false, nil
    if sampleOk then
        sizeOk, size = invoke(sample, "size")
    end
    if sizeOk and tonumber(size) then
        size = math.floor(tonumber(size))
        if size > 8 then
            invoke(sample, "release")
            return nil, "fluid mixture exceeds the persistence component limit"
        end
        for index = 0, size - 1 do
            local kindOk, kind = invoke(sample, "getFluid", index)
            local typeOk, fluidType = false, nil
            local partOk, partAmount = false, nil
            if kindOk and kind ~= nil then typeOk, fluidType = invoke(kind, "getFluidTypeString") end
            -- FluidInstance.getAmount() is public Java API but is not exposed
            -- to Kahlua in Build 42.20.4.  Asking the container for this known
            -- Fluid is both exact and Lua-exposed. Percentage is a compatible
            -- fallback for method-minimal test doubles and future API reshapes.
            if kindOk and kind ~= nil then
                partOk, partAmount = invoke(fluid, "getSpecificFluidAmount", kind)
            end
            if not partOk then
                local percentageOk, percentage = invoke(sample, "getPercentage", index)
                percentage = percentageOk and finite(percentage, nil) or nil
                if percentage ~= nil then
                    if percentage > 1 and percentage <= 100 then percentage = percentage / 100 end
                    partOk, partAmount = true, amount * math.max(0, percentage)
                end
            end
            if not typeOk or fluidType == nil or not partOk then
                invoke(sample, "release")
                return nil, "fluid mixture could not be represented"
            end
            result.fluids[#result.fluids + 1] = {
                type = text(fluidType, "", 96),
                amount = math.max(0, finite(partAmount, 0)),
            }
        end
        invoke(sample, "release")
        if #result.fluids > 0 then return result end
    elseif sampleOk and sample ~= nil then
        invoke(sample, "release")
    end

    local mixedOk, mixed = invoke(fluid, "isMixture")
    if mixedOk and mixed == true then
        return nil, "fluid mixture API is unavailable"
    end
    local primaryOk, primary = invoke(fluid, "getPrimaryFluid")
    local typeOk, fluidType = false, nil
    if primaryOk and primary ~= nil then typeOk, fluidType = invoke(primary, "getFluidTypeString") end
    if not typeOk or fluidType == nil then
        return nil, "non-empty fluid type is unavailable"
    end
    result.fluids[1] = { type = text(fluidType, "", 96), amount = amount }
    return result
end

local function captureItemVisual(item)
    local visualOk, visual = invoke(item, "getVisual")
    local enum = type(_G) == "table" and rawget(_G, "BloodBodyPartType") or nil
    if not visualOk or visual == nil or enum == nil then return nil end
    local maxOk, maximum = fieldValue(enum, "MAX")
    local indexOk, count = false, nil
    if maxOk and maximum ~= nil then indexOk, count = invoke(maximum, "index") end
    if not indexOk or not tonumber(count) then return nil end
    local result = { parts = {} }
    for index = 0, math.min(math.floor(tonumber(count)), 32) - 1 do
        local partOk, part = staticInvoke(enum, "FromIndex", index)
        if partOk and part ~= nil then
            local entry = { index = index }
            local any = false
            for key, getter in pairs({
                blood = "getBlood", dirt = "getDirt", hole = "getHole",
                basicPatch = "getBasicPatch", denimPatch = "getDenimPatch",
                leatherPatch = "getLeatherPatch",
            }) do
                local valueOk, value = invoke(visual, getter, part)
                if valueOk and finite(value, 0) > 0 then
                    entry[key], any = finite(value, 0), true
                end
            end
            local patchOk, patch = invoke(item, "getPatchType", part)
            if patchOk and patch ~= nil then
                local fabricOk, fabric = invoke(patch, "getFabricType")
                local tailorOk, tailor = fieldValue(patch, "tailorLvl")
                local holeOk, hadHole = fieldValue(patch, "hasHole")
                if fabricOk and tailorOk and holeOk then
                    entry.patch = {
                        fabricType = math.floor(finite(fabric, 0)),
                        tailorLevel = math.floor(finite(tailor, 1)),
                        hadHole = hadHole == true,
                    }
                    any = true
                end
            end
            if any then result.parts[#result.parts + 1] = entry end
        end
    end
    return #result.parts > 0 and result or nil
end

local function captureItem(item)
    local typeOk, fullType = invoke(item, "getFullType")
    if not typeOk or fullType == nil then return nil end
    local entry = { type = text(fullType, "", 128) }
    local ok, value = invoke(item, "getCondition")
    if ok then entry.condition = math.floor(finite(value, 0)) end
    ok, value = invoke(item, "isFavorite")
    if ok then entry.favorite = value == true end
    local scalar = {}
    for _, field in ipairs(scalarItemFields) do
        ok, value = false, nil
        -- Some base classes expose a placeholder getter but no corresponding
        -- setter (InventoryItem.getWetness() is one example).  Persist only a
        -- property the concrete item can also accept during restore.
        if method(item, field.setter) ~= nil then ok, value = invoke(item, field.getter) end
        if ok then
            if field.kind == "boolean" and type(value) == "boolean" then
                scalar[field.key] = value
            elseif field.kind == "integer" and finite(value, nil) ~= nil then
                scalar[field.key] = math.floor(finite(value, 0))
            elseif field.kind == "number" and finite(value, nil) ~= nil then
                scalar[field.key] = finite(value, 0)
            end
        end
    end
    if hasEntries(scalar) then entry.scalar = scalar end
    local dataOk, modData = invoke(item, "getModData")
    if dataOk and type(modData) == "table" then
        local copied = boundedStableCopy(modData, 5, {
            count = SC.Config.get("persistence", "maxItemModDataEntries") or 256,
        })
        if hasEntries(copied) then entry.modData = copied end
    end
    if SC.PersonalItems and type(SC.PersonalItems.personalRecord) == "function" then
        local personal = SC.PersonalItems.personalRecord(item)
        if personal then entry.personal = boundedStableCopy(personal, 2, { count = 12 }) end
    end
    local firearm = false
    if type(instanceof) == "function" then
        local instanceOk, instanceResult = pcall(instanceof, item, "HandWeapon")
        firearm = instanceOk and instanceResult == true
    end
    if firearm then
        entry.firearm = {}
        local fields = {
            currentAmmo = "getCurrentAmmoCount",
            containsClip = "isContainsClip",
            roundChambered = "isRoundChambered",
            jammed = "isJammed",
            fireMode = "getFireMode",
        }
        for key, getter in pairs(fields) do
            ok, value = invoke(item, getter)
            if ok and (type(value) == "number" or type(value) == "boolean" or type(value) == "string") then
                entry.firearm[key] = value
            end
        end
    end
    local fluid, fluidReason = captureFluid(item)
    if fluidReason then return nil, fluidReason end
    if fluid then entry.fluid = fluid end
    entry.visual = captureItemVisual(item)
    return entry
end

local function captureInventory(actor)
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then
        return nil, "native inventory is unavailable"
    end
    local itemsOk, items = invoke(inventory, "getItems")
    if not itemsOk or items == nil then
        return nil, "native inventory item list is unavailable"
    end

    local context = {
        count = 0,
        maximum = SC.Config.get("persistence", "maxSavedInventoryItems") or 2048,
        maxDepth = SC.Config.get("persistence", "maxSavedInventoryDepth") or 12,
        seen = {},
        itemIds = {},
    }
    local roots = {}
    local captureNode

    local function nextId(prefix)
        context.count = context.count + 1
        if context.count > context.maximum then
            return nil, "inventory exceeds the persistence item limit"
        end
        return tostring(prefix or "i") .. tostring(context.count)
    end

    captureNode = function(item, depth, prefix)
        if item == nil then return nil, "inventory contains a nil item" end
        if context.seen[item] then return nil, "inventory container cycle detected" end
        if depth > context.maxDepth then return nil, "inventory exceeds the persistence depth limit" end
        local id, idReason = nextId(prefix)
        if not id then return nil, idReason end
        context.seen[item] = true
        local entry, entryReason = captureItem(item)
        if not entry then return nil, entryReason or "inventory item has no stable type" end
        entry.id = id
        context.itemIds[item] = id

        local nestedOk, nested = invoke(item, "getInventory")
        local isContainerOk, isContainer = invoke(item, "IsInventoryContainer")
        if nested ~= nil then
            local childListOk, childList = invoke(nested, "getItems")
            if not childListOk or childList == nil then
                return nil, "nested inventory item list is unavailable"
            end
            entry.children = {}
            for index = 0, listSize(childList) - 1 do
                local child = listGet(childList, index)
                local captured, reason = captureNode(child, depth + 1, "i")
                if not captured then return nil, reason end
                entry.children[#entry.children + 1] = captured
            end
        elseif isContainerOk and isContainer == true then
            return nil, "inventory container has no nested inventory"
        end

        local partsOk, parts = invoke(item, "getAllWeaponParts")
        if partsOk and parts ~= nil and listSize(parts) > 0 then
            entry.weaponParts = {}
            for index = 0, listSize(parts) - 1 do
                local part = listGet(parts, index)
                local partId, partIdReason = nextId("p")
                if not partId then return nil, partIdReason end
                local partEntry, partReason = captureItem(part)
                if not partEntry then return nil, partReason or "weapon part has no stable type" end
                partEntry.id = partId
                entry.weaponParts[#entry.weaponParts + 1] = partEntry
            end
        end
        return entry
    end

    local function ensureRoot(item)
        if item == nil then return nil end
        if context.itemIds[item] then return context.itemIds[item] end
        local entry, reason = captureNode(item, 1, "i")
        if not entry then return nil, reason end
        roots[#roots + 1] = entry
        return entry.id
    end

    for index = 0, listSize(items) - 1 do
        local item = listGet(items, index)
        local _, reason = ensureRoot(item)
        if reason then return nil, reason end
    end

    local equipment = { worn = {}, attached = {} }
    local primaryOk, primary = invoke(actor, "getPrimaryHandItem")
    if primaryOk and primary ~= nil then
        local id, reason = ensureRoot(primary)
        if not id then return nil, reason or "primary hand item could not be captured" end
        equipment.primary = id
    end
    local secondaryOk, secondary = invoke(actor, "getSecondaryHandItem")
    if secondaryOk and secondary ~= nil then
        local id, reason = ensureRoot(secondary)
        if not id then return nil, reason or "secondary hand item could not be captured" end
        equipment.secondary = id
    end
    local wornOk, worn = invoke(actor, "getWornItems")
    if wornOk and worn ~= nil then
        for index = 0, math.min(listSize(worn), 128) - 1 do
            local wornEntry = listGet(worn, index)
            local itemOk, item = invoke(wornEntry, "getItem")
            local locationOk, location = invoke(wornEntry, "getLocation")
            if itemOk and item ~= nil and locationOk and location ~= nil then
                local id, reason = ensureRoot(item)
                if not id then return nil, reason or "worn item could not be captured" end
                equipment.worn[#equipment.worn + 1] = {
                    location = text(location, "", 96), id = id,
                }
            end
        end
    end
    local attachedOk, attached = invoke(actor, "getAttachedItems")
    if attachedOk and attached ~= nil then
        for index = 0, math.min(listSize(attached), 64) - 1 do
            local attachedEntry = listGet(attached, index)
            local itemOk, item = invoke(attachedEntry, "getItem")
            local locationOk, location = invoke(attachedEntry, "getLocation")
            if itemOk and item ~= nil and locationOk and location ~= nil then
                local id, reason = ensureRoot(item)
                if not id then return nil, reason or "attached item could not be captured" end
                equipment.attached[#equipment.attached + 1] = {
                    location = text(location, "", 96), id = id,
                }
            end
        end
    end
    table.sort(equipment.worn, function(a, b)
        if a.location == b.location then return a.id < b.id end
        return a.location < b.location
    end)
    table.sort(equipment.attached, function(a, b)
        if a.location == b.location then return a.id < b.id end
        return a.location < b.location
    end)
    return {
        schema = 2,
        complete = true,
        count = context.count,
        roots = roots,
        equipment = equipment,
    }
end

local function capturePossessions(actor, source, ownerId)
    local possessions = boundedStableCopy(source, 4, { count = 96 }) or {}
    possessions.version = 1
    local keepsake = type(possessions.keepsake) == "table" and possessions.keepsake or nil
    if not keepsake or type(keepsake.key) ~= "string" or keepsake.key == "" then return possessions end
    local item, depth
    if SC.PersonalItems and type(SC.PersonalItems.find) == "function" then
        item, depth = SC.PersonalItems.find(actor, keepsake.key)
    end
    if item then
        keepsake.status = "carried"
        keepsake.lastSeenAt = math.max(0, finite(keepsake.lastSeenAt, 0))
        if depth and depth > 0 then keepsake.nestedCarried = captureItem(item)
        else keepsake.nestedCarried = nil end
    else
        keepsake.status = "not_carried"
        keepsake.nestedCarried = nil
    end
    keepsake.ownerId = text(keepsake.ownerId, ownerId, 80)
    possessions.keepsake = keepsake
    return possessions
end

local function captureSkills(actor)
    local result = {}
    local listOk, list = invoke(actor, "getPerkList")
    local xpOk, xp = invoke(actor, "getXp")
    if not listOk or list == nil then
        return result
    end
    for index = 0, math.min(listSize(list), 128) - 1 do
        local info = listGet(list, index)
        local perk = info and info.perk or nil
        if perk ~= nil then
            local idOk, id = invoke(perk, "getId")
            if idOk and id ~= nil then
                local levelOk, level = invoke(actor, "getPerkLevel", perk)
                local entry = {
                    id = text(id, "", 96),
                    level = levelOk and math.max(0, math.floor(finite(level, 0))) or 0,
                }
                local valueOk, value = false, nil
                if xpOk then
                    valueOk, value = invoke(xp, "getXP", perk)
                end
                if valueOk then entry.xp = math.max(0, finite(value, 0)) end
                result[#result + 1] = entry
            end
        end
    end
    return result
end

function persistence.captureRecord(record, vehicleState)
    if type(record) ~= "table" or not SC.Registry.isValidId(record.id) then
        return nil, "valid registry record is required"
    end
    local actor = record.actor
    if actor == nil then
        return nil, "active actor is required"
    end
    if type(record.runtime) == "table" and record.runtime.inactive == true then
        return nil, "inactive/unrecoverable actor cannot be captured"
    end
    local deadOk, dead = invoke(actor, "isDead")
    if not deadOk or dead == true or (record.recruited ~= true
        and type(record.factionId) ~= "string") then
        return nil, "only recruited or faction living companions are persistent"
    end
    local position = positionOf(actor)
    if position == nil or position.x == nil or position.y == nil then
        return nil, "actor has no stable position"
    end
    local state = type(record.state) == "table" and record.state or {}
    local order = type(state.order) == "table" and state.order or {}
    local personality = type(state.personality) == "table" and state.personality or {}
    local objectives = type(state.objectives) == "table" and state.objectives or {}
    local possessions = capturePossessions(actor, state.possessions, record.id)
    local downtime = type(state.downtime) == "table" and state.downtime or {}
    local vitals, vitalsReason = SC.Vitals.capture(actor)
    if vitals == nil then
        return nil, vitalsReason
    end
    local inventorySnapshot, inventoryReason = captureInventory(actor)
    if inventorySnapshot == nil then return nil, inventoryReason end
    local workTarget
    if type(order.workTarget) == "table" and finite(order.workTarget.x, nil) ~= nil
        and finite(order.workTarget.y, nil) ~= nil
        and finite(order.workTarget.objectIndex, nil) ~= nil then
        workTarget = {
            x = finite(order.workTarget.x, 0),
            y = finite(order.workTarget.y, 0),
            z = finite(order.workTarget.z, 0),
            objectIndex = math.floor(finite(order.workTarget.objectIndex, -1)),
            initialPlanks = math.max(0,
                math.floor(finite(order.workTarget.initialPlanks, 0))),
            baseJobId = type(order.workTarget.baseJobId) == "string"
                and text(order.workTarget.baseJobId, "", 64) or nil,
            barricadeSide = order.workTarget.barricadeSide == "same" and "same"
                or order.workTarget.barricadeSide == "opposite" and "opposite" or nil,
            kind = targetedWorkKinds[order.workTarget.kind]
                and order.workTarget.kind or "barricade",
        }
    end
    return {
        id = record.id,
        recruited = record.recruited == true,
        factionId = type(record.factionId) == "string" and text(record.factionId, "", 96) or nil,
        factionRole = type(record.factionRole) == "string" and text(record.factionRole, "", 32) or nil,
        factionLeader = record.factionLeader == true,
        identity = captureIdentity(record, actor),
        position = position,
        order = {
            current = text(order.current, SC.Config.get("defaultOrder"), 32),
            followDistance = finite(order.followDistance, SC.Config.get("defaultFollowDistance")),
            scavenge = order.scavenge ~= false,
            allowOverload = order.allowOverload == true,
            rideWithPlayer = order.rideWithPlayer ~= false,
            movementMode = text(order.movementMode,
                record.recruited == true and "copy" or "walk", 16),
            movementModeVersion = math.max(0,
                math.floor(finite(order.movementModeVersion, 0))),
            combatStance = text(order.combatStance, SC.Config.get("defaultCombatStance"), 32),
            combatDoctrine = text(order.combatDoctrine,
                SC.Config.get("defaultCombatDoctrine") or "close_defense", 32),
            holdFire = order.holdFire == true,
            weaponPriority = text(order.weaponPriority, SC.Config.get("defaultWeaponPriority"), 48),
            workMode = text(order.workMode, "auto", 16),
            workTarget = workTarget,
            returnOrder = order.returnOrder ~= nil and text(order.returnOrder, "stay", 32) or nil,
            returnWorkMode = order.returnWorkMode ~= nil
                and text(order.returnWorkMode, "auto", 16) or nil,
        },
        group = state.group ~= nil and text(state.group, "", 64) or nil,
        personality = {
            archetype = personality.archetype ~= nil and text(personality.archetype, "", 48) or nil,
            profile = boundedStableCopy(personality.profile, 2, { count = 16 }),
            trust = finite(personality.trust, 0),
            bond = finite(personality.bond, 0),
            morale = finite(personality.morale, 55),
            stress = finite(personality.stress, 12),
            memories = copyList(personality.memories, SC.Config.get("maxMemories")),
            background = boundedStableCopy(personality.background, 2, { count = 24 }),
            care = boundedStableCopy(personality.care, 2, { count = 32 }),
            reveals = boundedStableCopy(personality.reveals, 2, { count = 16 }),
            timeTogetherMs = math.max(0, finite(personality.timeTogetherMs, 0)),
            lastEncouragedAt = math.max(0, finite(personality.lastEncouragedAt, 0)),
        },
        objectives = boundedStableCopy(objectives, 4, { count = 160 }),
        possessions = possessions,
        inventory = inventorySnapshot,
        skills = captureSkills(actor),
        vitals = vitals,
        knox = vitals.infected == true,
        downtime = {
            lastCompleted = downtime.lastCompleted ~= nil
                and text(downtime.lastCompleted, "", 64) or nil,
            facts = copyList(downtime.facts, SC.Config.get("maxDowntimeFacts")),
        },
        vehicle = boundedStableCopy(vehicleState, 3, { count = 24 }),
    }
end

local function currentPlayer(player)
    if player ~= nil then
        return player
    end
    if type(getPlayer) ~= "function" then
        return nil
    end
    local ok, value = pcall(getPlayer)
    return ok and value or nil
end

local function playerData(player)
    player = currentPlayer(player)
    local ok, data = invoke(player, "getModData")
    if not ok or type(data) ~= "table" then
        return nil, "player mod data is unavailable"
    end
    return data
end

function persistence.save(player)
    local data, dataReason = playerData(player)
    if data == nil then
        return false, dataReason
    end
    if saveBlockedReason ~= nil then
        return false, "save document is preserved without overwrite: " .. saveBlockedReason
    end
    local document = {
        schema = SC.Identity.saveSchema,
        protocol = SC.Identity.bridgeProtocol,
        savedAt = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0,
        companions = {},
        factionActors = {},
        factions = SC.Factions ~= nil and type(SC.Factions.export) == "function"
            and boundedStableCopy(SC.Factions.export(), 10, { count = 65536 }) or nil,
        factionWorld = SC.FactionWorld ~= nil and type(SC.FactionWorld.export) == "function"
            and boundedStableCopy(SC.FactionWorld.export(), 6, { count = 8192 }) or nil,
        baseLife = SC.BaseLife ~= nil and type(SC.BaseLife.export) == "function"
            and boundedStableCopy(SC.BaseLife.export(), 8, { count = 8192 }) or nil,
        infectionCrisis = SC.InfectionCrisis ~= nil
            and type(SC.InfectionCrisis.export) == "function"
            and boundedStableCopy(SC.InfectionCrisis.export(), 8, { count = 8192 }) or nil,
        community = SC.Community ~= nil and type(SC.Community.export) == "function"
            and boundedStableCopy(SC.Community.export(), 8, { count = 16384 }) or nil,
    }
    local priorDocument = data[SC.Identity.saveKey]
    for _, record in ipairs(SC.Registry.records()) do
        if (record.recruited == true or type(record.factionId) == "string")
            and record.actor ~= nil then
            local destination = record.recruited == true
                and document.companions or document.factionActors
            local priorBucket = record.recruited == true and "companions" or "factionActors"
            local deadOk, dead = invoke(record.actor, "isDead")
            local inactive = type(record.runtime) == "table" and record.runtime.inactive == true
            if deadOk and dead == true then
                -- Death is permanent as soon as native health reaches zero. Do
                -- not retain a prior snapshot while the corpse animation is
                -- still finishing, or the companion would return after load.
            elseif inactive then
                local previous = record.runtime.lastStableSnapshot
                    or (pending[record.id] and pending[record.id].record)
                    or (type(priorDocument) == "table"
                        and type(priorDocument[priorBucket]) == "table"
                        and priorDocument[priorBucket][record.id])
                    or (type(lastDocument) == "table"
                        and type(lastDocument[priorBucket]) == "table"
                        and lastDocument[priorBucket][record.id])
                local preserved = boundedStableCopy(previous, 7, { count = 4096 })
                if type(preserved) ~= "table" then
                    SC.Diagnostics.report("persistence", record.id,
                        "save transaction aborted; quarantined actor has no stable snapshot")
                    return false, "quarantined companion has no prior stable snapshot: "
                        .. tostring(record.id)
                end
                destination[record.id] = preserved
            else
                local vehicleState = SC.Vehicle ~= nil and type(SC.Vehicle.stateFor) == "function"
                    and SC.Vehicle.stateFor(record.actor) or nil
                local captured, reason = persistence.captureRecord(record, vehicleState)
                if captured ~= nil then
                    destination[record.id] = captured
                else
                    SC.Diagnostics.report("persistence", record.id,
                        "save transaction aborted; prior snapshot retained", reason)
                    return false, "active companion capture failed: " .. tostring(record.id)
                        .. ": " .. tostring(reason)
                end
            end
        end
    end
    if SC.Vehicle ~= nil and type(SC.Vehicle.exportStored) == "function" then
        for id, stored in pairs(SC.Vehicle.exportStored()) do
            document.companions[id] = stored
        end
    end
    for id, entry in pairs(pending) do
        if type(entry.record) == "table" then
            local destination = entry.record.recruited == true
                and document.companions or document.factionActors
            if destination[id] == nil then
                destination[id] = boundedStableCopy(entry.record, 6, { count = 2048 })
            end
        end
    end
    data[SC.Identity.saveKey] = document
    lastDocument = document
    return true, document
end

local function copyInventoryNode(source, context, depth)
    if type(source) ~= "table" or type(source.type) ~= "string" or source.type == "" then
        return nil, "invalid inventory node"
    end
    if context.seen[source] then return nil, "cyclic inventory save node" end
    if depth > context.maxDepth then return nil, "saved inventory exceeds the depth limit" end
    context.seen[source] = true
    context.count = context.count + 1
    if context.count > context.maximum then return nil, "saved inventory exceeds the item limit" end
    local id = type(source.id) == "string" and text(source.id, "", 48)
        or "i" .. tostring(context.count)
    if id == "" or context.ids[id] then return nil, "duplicate or empty inventory node id" end
    context.ids[id] = true
    local clean = { id = id, type = text(source.type, "", 128) }
    if source.condition ~= nil then clean.condition = math.floor(finite(source.condition, 0)) end
    if source.favorite ~= nil then clean.favorite = source.favorite == true end
    clean.scalar = boundedStableCopy(source.scalar, 2, { count = 32 })
    clean.personal = boundedStableCopy(source.personal, 3, { count = 24 })
    clean.modData = boundedStableCopy(source.modData, 5, {
        count = SC.Config.get("persistence", "maxItemModDataEntries") or 256,
    })
    clean.firearm = boundedStableCopy(source.firearm, 2, { count = 24 })
    clean.fluid = boundedStableCopy(source.fluid, 3, { count = 64 })
    clean.visual = boundedStableCopy(source.visual, 4, { count = 256 })
    clean.children = {}
    for _, child in ipairs(type(source.children) == "table" and source.children or {}) do
        local copied, reason = copyInventoryNode(child, context, depth + 1)
        if not copied then return nil, reason end
        clean.children[#clean.children + 1] = copied
    end
    clean.weaponParts = {}
    for _, part in ipairs(type(source.weaponParts) == "table" and source.weaponParts or {}) do
        local copied, reason = copyInventoryNode(part, context, depth + 1)
        if not copied then return nil, reason end
        if #copied.children > 0 or #copied.weaponParts > 0 then
            return nil, "weapon part save node cannot contain nested items"
        end
        clean.weaponParts[#clean.weaponParts + 1] = copied
    end
    context.seen[source] = nil
    return clean
end

local function normalizeInventorySnapshot(source)
    local context = {
        count = 0,
        maximum = SC.Config.get("persistence", "maxSavedInventoryItems") or 2048,
        maxDepth = SC.Config.get("persistence", "maxSavedInventoryDepth") or 12,
        ids = {}, seen = {},
    }
    local rootsSource, equipmentSource, legacy
    if type(source) == "table" and source.schema == 2 then
        if source.complete ~= true or type(source.roots) ~= "table" then
            return nil, "inventory snapshot is incomplete"
        end
        rootsSource = source.roots
        equipmentSource = type(source.equipment) == "table" and source.equipment or {}
    elseif type(source) == "table" then
        -- Schema 1 stored a flat root list.  It remains readable, but its
        -- limitations are not propagated after the next successful save.
        rootsSource = source
        equipmentSource = {}
        legacy = true
    else
        rootsSource, equipmentSource, legacy = {}, {}, true
    end
    local result = {
        schema = 2, complete = true, roots = {},
        equipment = { worn = {}, attached = {} }, legacy = legacy == true,
    }
    for _, node in ipairs(rootsSource) do
        local copied, reason = copyInventoryNode(node, context, 1)
        if not copied then return nil, reason end
        result.roots[#result.roots + 1] = copied
    end
    if type(source) == "table" and source.schema == 2
        and source.count ~= nil and math.floor(finite(source.count, -1)) ~= context.count then
        return nil, "inventory snapshot item count does not match its tree"
    end
    if type(equipmentSource.primary) == "string" then
        result.equipment.primary = text(equipmentSource.primary, "", 48)
    end
    if type(equipmentSource.secondary) == "string" then
        result.equipment.secondary = text(equipmentSource.secondary, "", 48)
    end
    for _, worn in ipairs(type(equipmentSource.worn) == "table" and equipmentSource.worn or {}) do
        if type(worn) ~= "table" or type(worn.id) ~= "string"
            or type(worn.location) ~= "string" then
            return nil, "invalid worn-item reference"
        end
        result.equipment.worn[#result.equipment.worn + 1] = {
            id = text(worn.id, "", 48), location = text(worn.location, "", 96),
        }
    end
    for _, attached in ipairs(type(equipmentSource.attached) == "table"
        and equipmentSource.attached or {}) do
        if type(attached) ~= "table" or type(attached.id) ~= "string"
            or type(attached.location) ~= "string" then
            return nil, "invalid attached-item reference"
        end
        result.equipment.attached[#result.equipment.attached + 1] = {
            id = text(attached.id, "", 48), location = text(attached.location, "", 96),
        }
    end
    local function validReference(value)
        return value == nil or (value ~= "" and context.ids[value] == true)
    end
    if not validReference(result.equipment.primary)
        or not validReference(result.equipment.secondary) then
        return nil, "hand-item reference is missing from inventory"
    end
    for _, worn in ipairs(result.equipment.worn) do
        if worn.location == "" or not validReference(worn.id) then
            return nil, "worn-item reference is missing from inventory"
        end
    end
    for _, attached in ipairs(result.equipment.attached) do
        if attached.location == "" or not validReference(attached.id) then
            return nil, "attached-item reference is missing from inventory"
        end
    end
    result.count = context.count
    return result
end

local function validateRecord(id, source)
    if not SC.Registry.isValidId(id) or type(source) ~= "table" or source.id ~= id
        or (source.recruited ~= true and type(source.factionId) ~= "string")
        or type(source.identity) ~= "table" then
        return nil, "invalid companion save record"
    end
    if source.vehicle == nil then
        if type(source.position) ~= "table" or finite(source.position.x, nil) == nil
            or finite(source.position.y, nil) == nil or finite(source.position.z, nil) == nil then
            return nil, "save record has no valid position"
        end
    end
    local sourceWithoutInventory = {}
    for key, value in pairs(source) do
        if key ~= "inventory" then sourceWithoutInventory[key] = value end
    end
    local clean = boundedStableCopy(sourceWithoutInventory, 10, { count = 16384 })
    local inventory, inventoryReason = normalizeInventorySnapshot(source.inventory)
    if inventory == nil then return nil, inventoryReason end
    clean.id = id
    clean.recruited = source.recruited == true
    clean.factionId = type(source.factionId) == "string" and text(source.factionId, "", 96) or nil
    clean.factionRole = type(source.factionRole) == "string" and text(source.factionRole, "", 32) or nil
    clean.factionLeader = source.factionLeader == true
    clean.inventory = inventory
    clean.skills = copyList(clean.skills, 128)
    return clean
end

local function applyFluid(item, saved)
    if type(saved) ~= "table" then return true end
    local fluidOk, fluid = invoke(item, "getFluidContainer")
    if not fluidOk or fluid == nil then return false, "saved fluid container is unavailable" end
    if not invoke(fluid, "Empty") then return false, "fluid container could not be emptied" end
    local expected = 0
    for _, entry in ipairs(type(saved.fluids) == "table" and saved.fluids or {}) do
        local amount = math.max(0, finite(entry.amount, 0))
        if type(entry.type) ~= "string" or entry.type == "" then
            return false, "saved fluid type is invalid"
        end
        if amount > 0 then
            local called = invoke(fluid, "addFluid", entry.type, amount)
            if not called then return false, "saved fluid could not be restored: " .. entry.type end
            expected = expected + amount
        end
    end
    local amountOk, actual = invoke(fluid, "getAmount")
    if amountOk and math.abs(finite(actual, 0) - expected) > 0.001 then
        return false, "restored fluid amount did not verify"
    end
    return true
end

local function applyItemVisual(item, saved)
    if type(saved) ~= "table" or type(saved.parts) ~= "table" then return true end
    local visualOk, visual = invoke(item, "getVisual")
    local enum = type(_G) == "table" and rawget(_G, "BloodBodyPartType") or nil
    if not visualOk or visual == nil or enum == nil then
        return false, "saved clothing visual API is unavailable"
    end
    for _, entry in ipairs(saved.parts) do
        local index = math.floor(finite(entry.index, -1))
        local partOk, part = staticInvoke(enum, "FromIndex", index)
        if not partOk or part == nil then return false, "saved clothing body part is unavailable" end
        if type(entry.patch) == "table" then
            if not invoke(item, "addPatchForSync", index,
                math.max(1, math.floor(finite(entry.patch.tailorLevel, 1))),
                math.max(0, math.floor(finite(entry.patch.fabricType, 0))),
                entry.patch.hadHole == true) then
                return false, "saved clothing protection patch could not be restored"
            end
        end
        if finite(entry.hole, 0) > 0 and not invoke(visual, "setHole", part) then
            return false, "saved clothing hole could not be restored"
        end
        if finite(entry.basicPatch, 0) > 0 then invoke(visual, "setBasicPatch", part) end
        if finite(entry.denimPatch, 0) > 0 then invoke(visual, "setDenimPatch", part) end
        if finite(entry.leatherPatch, 0) > 0 then invoke(visual, "setLeatherPatch", part) end
        if entry.blood ~= nil then invoke(visual, "setBlood", part, finite(entry.blood, 0)) end
        if entry.dirt ~= nil then invoke(visual, "setDirt", part, finite(entry.dirt, 0)) end
    end
    invoke(item, "synchWithVisual")
    return true
end

local function applyItemState(item, entry, restoredKeys)
    if entry.condition ~= nil and not invoke(item, "setCondition",
        math.floor(finite(entry.condition, 0))) then
        return false, "item condition could not be restored"
    end
    if entry.favorite ~= nil and not invoke(item, "setFavorite", entry.favorite == true) then
        return false, "item favourite state could not be restored"
    end
    for _, field in ipairs(scalarItemFields) do
        local value = type(entry.scalar) == "table" and entry.scalar[field.key] or nil
        if value ~= nil then
            if field.kind == "boolean" then value = value == true
            elseif field.kind == "integer" then value = math.floor(finite(value, 0))
            else value = finite(value, 0) end
            if not invoke(item, field.setter, value) then
                return false, "item field could not be restored: " .. field.key
            end
        end
    end
    if type(entry.modData) == "table" then
        local dataOk, data = invoke(item, "getModData")
        if not dataOk or type(data) ~= "table" then return false, "item modData is unavailable" end
        local copy = boundedStableCopy(entry.modData, 5, {
            count = SC.Config.get("persistence", "maxItemModDataEntries") or 256,
        }) or {}
        for key, value in pairs(copy) do data[key] = value end
    end
    if type(entry.firearm) == "table" then
        local firearm = entry.firearm
        if firearm.currentAmmo ~= nil then invoke(item, "setCurrentAmmoCount", math.floor(finite(firearm.currentAmmo, 0))) end
        if firearm.containsClip ~= nil then invoke(item, "setContainsClip", firearm.containsClip == true) end
        if firearm.roundChambered ~= nil then invoke(item, "setRoundChambered", firearm.roundChambered == true) end
        if firearm.jammed ~= nil then invoke(item, "setJammed", firearm.jammed == true) end
        if firearm.fireMode ~= nil then invoke(item, "setFireMode", tostring(firearm.fireMode)) end
    end
    local fluidApplied, fluidReason = applyFluid(item, entry.fluid)
    if not fluidApplied then return false, fluidReason end
    local visualApplied, visualReason = applyItemVisual(item, entry.visual)
    if not visualApplied then return false, visualReason end
    local personal = type(entry.personal) == "table" and entry.personal or nil
    local key = personal and text(personal.key, "", 128) or ""
    if personal and SC.PersonalItems and type(SC.PersonalItems.restoreMarker) == "function" then
        local marked, reason = SC.PersonalItems.restoreMarker(item, personal, entry.favorite)
        if not marked then return false, "personal inventory marker could not be restored: " .. tostring(reason) end
        restoredKeys[key] = item
    end
    return true
end

local function clearActorInventory(actor, inventory)
    invoke(actor, "setPrimaryHandItem", nil)
    invoke(actor, "setSecondaryHandItem", nil)
    local wornOk, worn = invoke(actor, "getWornItems")
    if wornOk and worn ~= nil then
        local wornItems = {}
        for index = 0, math.min(listSize(worn), 128) - 1 do
            local entry = listGet(worn, index)
            local itemOk, item = invoke(entry, "getItem")
            if itemOk and item ~= nil then wornItems[#wornItems + 1] = item end
        end
        for index = #wornItems, 1, -1 do invoke(actor, "removeWornItem", wornItems[index], false) end
    end
    local attachedOk, attached = invoke(actor, "getAttachedItems")
    if attachedOk and attached ~= nil then
        local attachedItems = {}
        for index = 0, math.min(listSize(attached), 64) - 1 do
            local entry = listGet(attached, index)
            local itemOk, item = invoke(entry, "getItem")
            if itemOk and item ~= nil then attachedItems[#attachedItems + 1] = item end
        end
        for index = #attachedItems, 1, -1 do invoke(actor, "removeAttachedItem", attachedItems[index]) end
    end
    local itemsOk, items = invoke(inventory, "getItems")
    if not itemsOk or items == nil then return false, "native inventory item list is unavailable" end
    local roots = {}
    for index = 0, listSize(items) - 1 do roots[#roots + 1] = listGet(items, index) end
    for index = #roots, 1, -1 do
        if not invoke(inventory, "Remove", roots[index]) then
            return false, "generated inventory item could not be removed"
        end
    end
    local verifyOk, verifyItems = invoke(inventory, "getItems")
    if not verifyOk or listSize(verifyItems) ~= 0 then
        return false, "generated inventory did not clear completely"
    end
    return true
end

local function addInventoryNode(parentInventory, entry, context, depth)
    local personal = type(entry.personal) == "table" and entry.personal or nil
    local personalKey = personal and text(personal.key, "", 128) or ""
    if personalKey ~= "" and context.restoredKeys[personalKey] then
        context.byId[entry.id] = context.restoredKeys[personalKey]
        SC.Diagnostics.report("personal-item", personal.ownerId,
            "duplicate personal key ignored during restore", personalKey)
        return true, context.restoredKeys[personalKey]
    end
    local addedOk, item = invoke(parentInventory, "AddItem", entry.type)
    if not addedOk or item == nil then return false, "inventory item could not be restored: " .. entry.type end
    context.byId[entry.id] = item
    local stateOk, stateReason = applyItemState(item, entry, context.restoredKeys)
    if not stateOk then return false, stateReason end
    if #entry.children > 0 then
        local nestedOk, nested = invoke(item, "getInventory")
        if not nestedOk or nested == nil then return false, "nested inventory could not be restored: " .. entry.type end
        for _, child in ipairs(entry.children) do
            local childOk, childReason = addInventoryNode(nested, child, context, depth + 1)
            if not childOk then return false, childReason end
        end
    end
    for _, partEntry in ipairs(entry.weaponParts) do
        local partOk, part = invoke(context.rootInventory, "AddItem", partEntry.type)
        if not partOk or part == nil then return false, "weapon part could not be created: " .. partEntry.type end
        context.byId[partEntry.id] = part
        local partStateOk, partStateReason = applyItemState(part, partEntry, context.restoredKeys)
        if not partStateOk then return false, partStateReason end
        if not invoke(context.rootInventory, "Remove", part) then
            return false, "weapon part could not leave the root inventory"
        end
        if not invoke(item, "attachWeaponPart", part, false) then
            return false, "weapon part could not be attached: " .. partEntry.type
        end
    end
    return true, item
end

local function applyEquipment(actor, equipment, byId)
    equipment = type(equipment) == "table" and equipment or {}
    if equipment.primary ~= nil then
        local item = byId[equipment.primary]
        if item == nil or not invoke(actor, "setPrimaryHandItem", item) then
            return false, "primary hand item could not be equipped"
        end
    end
    if equipment.secondary ~= nil then
        local item = byId[equipment.secondary]
        if item == nil or not invoke(actor, "setSecondaryHandItem", item) then
            return false, "secondary hand item could not be equipped"
        end
    end
    for _, worn in ipairs(type(equipment.worn) == "table" and equipment.worn or {}) do
        local item = byId[worn.id]
        if item == nil or not invoke(actor, "setWornItem", worn.location, item) then
            return false, "worn item could not be equipped at " .. tostring(worn.location)
        end
    end
    for _, attached in ipairs(type(equipment.attached) == "table" and equipment.attached or {}) do
        local item = byId[attached.id]
        if item == nil or not invoke(actor, "setAttachedItem", attached.location, item) then
            return false, "attached item could not be equipped at " .. tostring(attached.location)
        end
    end
    return true
end

local function applyInventory(actor, entries)
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then
        return false, "native inventory is unavailable"
    end
    local snapshot, snapshotReason = normalizeInventorySnapshot(entries)
    if not snapshot then return false, snapshotReason end
    local cleared, clearReason = clearActorInventory(actor, inventory)
    if not cleared then return false, clearReason end
    local context = { rootInventory = inventory, byId = {}, restoredKeys = {} }
    for _, entry in ipairs(snapshot.roots) do
        local applied, reason = addInventoryNode(inventory, entry, context, 1)
        if not applied then return false, reason end
    end
    local equipped, equipReason = applyEquipment(actor, snapshot.equipment, context.byId)
    if not equipped then return false, equipReason end
    context.snapshot = snapshot
    return true, context
end

local function applyNestedKeepsake(actor, possessions, context)
    if type(context) ~= "table" or type(context.snapshot) ~= "table"
        or context.snapshot.legacy ~= true then return true end
    local keepsake = type(possessions) == "table" and possessions.keepsake or nil
    if type(keepsake) ~= "table" or keepsake.status ~= "carried"
        or type(keepsake.nestedCarried) ~= "table" then return true end
    local key = text(keepsake.key, "", 128)
    if key == "" or context.restoredKeys[key] then return true end
    local entry = boundedStableCopy(keepsake.nestedCarried, 3, { count = 48 })
    if type(entry) ~= "table" then return false, "nested personal snapshot is invalid" end
    entry.personal = {
        version = 1,
        ownerId = text(keepsake.ownerId, "", 80),
        key = key,
        kind = text(keepsake.kind, "memento", 48),
    }
    entry.id = "legacy-keepsake"
    entry.children = type(entry.children) == "table" and entry.children or {}
    entry.weaponParts = type(entry.weaponParts) == "table" and entry.weaponParts or {}
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return false, "native inventory is unavailable" end
    return addInventoryNode(inventory, entry, context, 1)
end

local function applySkills(actor, skills)
    skills = type(skills) == "table" and skills or {}
    local factory = type(_G) == "table" and rawget(_G, "PerkFactory") or nil
    local xpOk, xp = invoke(actor, "getXp")
    if factory == nil or not xpOk or xp == nil then
        return #skills == 0, #skills == 0 and nil or "native skill API is unavailable"
    end
    for _, entry in ipairs(skills) do
        if type(entry) == "table" and type(entry.id) == "string" then
            local perkOk, perk = pcall(function()
                return factory.getPerkFromName(entry.id)
            end)
            if not perkOk or perk == nil then
                return false, "unknown perk in save record: " .. entry.id
            end
            local level = math.max(0, math.min(10, math.floor(finite(entry.level, 0))))
            local setOk = invoke(xp, "setXPToLevel", perk, level)
            if not setOk then
                return false, "perk level could not be restored: " .. entry.id
            end
            if entry.xp ~= nil then
                local currentOk, current = invoke(xp, "getXP", perk)
                local delta = finite(entry.xp, 0) - (currentOk and finite(current, 0) or 0)
                if delta > 0 then invoke(xp, "AddXPNoMultiplier", perk, delta) end
            end
        end
    end
    return true
end

local function initializeRestoredActor(actor, input, saved)
    local inventoryOk, contextOrReason = applyInventory(actor, saved.inventory)
    local context = inventoryOk and contextOrReason or nil
    local inventoryReason = inventoryOk and nil or contextOrReason
    if not inventoryOk then return false, inventoryReason end
    local nestedOk, nestedReason = applyNestedKeepsake(actor, saved.possessions, context)
    if not nestedOk then return false, nestedReason end
    local skillsOk, skillsReason = applySkills(actor, saved.skills or {})
    if not skillsOk then return false, skillsReason end
    local vitalsOk, vitalsReason = SC.Vitals.apply(actor, saved.vitals)
    if not vitalsOk then return false, vitalsReason end
    return true
end

function persistence.restoreAt(saved, square)
    if type(saved) ~= "table" or not SC.Registry.isValidId(saved.id) or square == nil then
        return nil, "valid saved record and loaded square are required"
    end
    local profile = {
        id = saved.id,
        recruited = saved.recruited == true,
        factionId = saved.factionId,
        factionRole = saved.factionRole,
        factionLeader = saved.factionLeader == true,
        restored = true,
        identity = saved.identity,
        state = {
            order = saved.order,
            group = saved.group,
            personality = saved.personality,
            objectives = saved.objectives,
            possessions = saved.possessions,
            downtime = saved.downtime,
        },
        initialize = function(actorValue, input)
            input.factionId = saved.factionId
            input.factionRole = saved.factionRole
            input.factionLeader = saved.factionLeader == true
            return initializeRestoredActor(actorValue, input, saved)
        end,
    }
    if type(SC.Actor.beginSpawn) ~= "function" then
        return SC.Actor.spawn(square, profile)
    end
    local ticket, reason = SC.Actor.beginSpawn(square, profile)
    if ticket == nil then return nil, reason end
    local actor, result = SC.Actor.pollSpawn(ticket)
    if actor ~= nil then return actor, result end
    if result == "spawn_pending" then return nil, result, ticket end
    return nil, result
end

local function squareFor(record)
    if type(getCell) ~= "function" then return nil end
    local ok, cell = pcall(getCell)
    if not ok or cell == nil then return nil end
    local position = record.position
    if type(position) ~= "table" or finite(position.x, nil) == nil
        or finite(position.y, nil) == nil or finite(position.z, nil) == nil then
        return nil
    end
    local squareOk, square = invoke(cell, "getGridSquare",
        math.floor(position.x), math.floor(position.y), math.floor(position.z))
    return squareOk and square or nil
end

local function importVehicleRecord(record)
    if type(record) ~= "table" or type(record.vehicle) ~= "table"
        or SC.Vehicle == nil then
        return false, "vehicle persistence adapter is unavailable"
    end
    if record.vehicle.stored == true and type(SC.Vehicle.importStored) == "function" then
        return SC.Vehicle.importStored(record)
    end
    if record.vehicle.stored == false and type(SC.Vehicle.importNativeSeat) == "function" then
        return SC.Vehicle.importNativeSeat(record)
    end
    return false, "vehicle save record has an unsupported seating state"
end

function persistence.restorePulse(player)
    local current = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    local processed = 0
    local maximum = SC.Config.get("restorePerPulse")
    for _, id in ipairs(pendingOrder) do
        local entry = pending[id]
        if entry ~= nil and processed < maximum and current >= (entry.nextAt or 0) then
            if SC.Registry.byId(id) ~= nil then
                pending[id] = nil
            elseif entry.vehicle == true then
                processed = processed + 1
                local imported, reason = importVehicleRecord(entry.record)
                if imported then
                    pending[id] = nil
                else
                    entry.attempts = (entry.attempts or 0) + 1
                    entry.reason = tostring(reason)
                    entry.nextAt = current + SC.Config.get("restoreIntervalMs")
                end
            else
                processed = processed + 1
                if entry.spawnTicket ~= nil then
                    local actor, result = SC.Actor.pollSpawn(entry.spawnTicket)
                    if actor ~= nil then
                        entry.spawnTicket = nil
                        pending[id] = nil
                    elseif result == "spawn_pending" then
                        entry.reason = result
                    else
                        entry.spawnTicket = nil
                        entry.attempts = (entry.attempts or 0) + 1
                        entry.reason = tostring(result)
                        entry.nextAt = current + SC.Config.get("restoreIntervalMs")
                    end
                else
                    local square = squareFor(entry.record)
                    if square == nil then
                        entry.nextAt = current + SC.Config.get("restoreIntervalMs")
                        entry.reason = "saved square is not currently loaded"
                    else
                        local saved = entry.record
                        local actor, result, ticket = persistence.restoreAt(saved, square)
                        if actor ~= nil then
                            pending[id] = nil
                        elseif result == "spawn_pending" and ticket ~= nil then
                            entry.spawnTicket = ticket
                            entry.reason = result
                        else
                            entry.attempts = (entry.attempts or 0) + 1
                            entry.reason = tostring(result)
                            entry.nextAt = current + SC.Config.get("restoreIntervalMs")
                        end
                    end
                end
            end
        end
    end
    return processed, persistence.pendingCount()
end

function persistence.restore(player)
    local data, dataReason = playerData(player)
    if data == nil then return false, dataReason end
    local document = data[SC.Identity.saveKey]
    for _, entry in pairs(pending) do
        if entry.spawnTicket ~= nil and SC.Actor ~= nil
            and type(SC.Actor.cancelSpawn) == "function" then
            pcall(SC.Actor.cancelSpawn, entry.spawnTicket)
        end
    end
    pending = {}
    pendingOrder = {}
    if document == nil then
        lastDocument = nil
        saveBlockedReason = nil
        return true, "no SurvivorCompanion save document"
    end
    if type(document) ~= "table"
        or (document.schema ~= SC.Identity.saveSchema and document.schema ~= 1)
        or type(document.companions) ~= "table" then
        lastDocument = document
        saveBlockedReason = "SC_SaveV1 has an unsupported or invalid schema"
        return false, saveBlockedReason
    end
    saveBlockedReason = nil
    if SC.Factions ~= nil and type(SC.Factions.restore) == "function" then
        local ok, reason = SC.Factions.restore(document.factions)
        if ok ~= true then
            SC.Diagnostics.report("factions", nil, "invalid faction state ignored", reason)
        end
    end
    if SC.FactionWorld ~= nil and type(SC.FactionWorld.restore) == "function" then
        local ok, reason = SC.FactionWorld.restore(document.factionWorld)
        if ok ~= true then
            SC.Diagnostics.report("faction-world", nil,
                "invalid faction world state ignored", reason)
        end
    end
    if SC.BaseLife ~= nil and type(SC.BaseLife.restore) == "function" then
        local ok, reason = SC.BaseLife.restore(document.baseLife)
        if ok ~= true then
            SC.Diagnostics.report("base-life", nil, "invalid base state ignored", reason)
        end
    end
    if SC.InfectionCrisis ~= nil and type(SC.InfectionCrisis.restore) == "function" then
        local ok, reason = SC.InfectionCrisis.restore(document.infectionCrisis)
        if ok ~= true then
            SC.Diagnostics.report("infection-crisis", nil, "invalid crisis state ignored", reason)
        end
    end
    if SC.Community ~= nil and type(SC.Community.restore) == "function" then
        local ok, reason = SC.Community.restore(document.community)
        if ok ~= true then
            SC.Diagnostics.report("community", nil, "invalid community state ignored", reason)
        end
    end
    local ids = {}
    for id in pairs(document.companions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local clean, reason = validateRecord(id, document.companions[id])
        if clean ~= nil then
            if clean.vehicle ~= nil then
                local imported, importReason = importVehicleRecord(clean)
                if not imported then
                    pending[id] = {
                        record = clean,
                        reason = importReason,
                        nextAt = 0,
                        attempts = 0,
                        vehicle = true,
                    }
                    pendingOrder[#pendingOrder + 1] = id
                end
            else
                pending[id] = { record = clean, nextAt = 0, attempts = 0 }
                pendingOrder[#pendingOrder + 1] = id
            end
        else
            SC.Diagnostics.report("persistence", id, "invalid save record ignored", reason)
        end
    end
    local factionActors = type(document.factionActors) == "table"
        and document.factionActors or {}
    local factionIds = {}
    for id in pairs(factionActors) do factionIds[#factionIds + 1] = id end
    table.sort(factionIds)
    for _, id in ipairs(factionIds) do
        if pending[id] == nil then
            local clean, reason = validateRecord(id, factionActors[id])
            if clean ~= nil and type(clean.factionId) == "string"
                and SC.Factions and SC.Factions.group(clean.factionId) then
                pending[id] = { record = clean, nextAt = 0, attempts = 0 }
                pendingOrder[#pendingOrder + 1] = id
            else
                SC.Diagnostics.report("persistence", id,
                    "invalid faction actor save record ignored", reason)
            end
        end
    end
    lastDocument = document
    persistence.restorePulse(player)
    return true, persistence.pendingCount()
end

function persistence.pendingCount()
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    return count
end

function persistence.isPending(id)
    return type(id) == "string" and pending[id] ~= nil
end

function persistence.pendingSnapshot()
    local result = {}
    for id, entry in pairs(pending) do
        result[id] = {
            attempts = entry.attempts or 0,
            reason = entry.reason,
            nextAt = entry.nextAt,
        }
    end
    return result
end

function persistence.lastDocument()
    return lastDocument
end

function persistence.reset()
    for _, entry in pairs(pending) do
        if entry.spawnTicket ~= nil and SC.Actor ~= nil
            and type(SC.Actor.cancelSpawn) == "function" then
            pcall(SC.Actor.cancelSpawn, entry.spawnTicket)
        end
    end
    pending = {}
    pendingOrder = {}
    lastDocument = nil
    saveBlockedReason = nil
end

return persistence
