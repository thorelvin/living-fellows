-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCStableValue"
require "SCNativeList"
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
local restoreCommitted = false
local restoreFailureReason = "restore has not committed"
local quarantined = { companions = {}, factionActors = {}, subsystems = {} }
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

local function stableCopy(value, depth, maximum, path)
    return SC.StableValue.copyStrict(value, {
        maxDepth = depth, maxEntries = maximum, path = path or "$",
    })
end

local function documentEntryLimit()
    return math.max(1, math.floor(tonumber(
        SC.Config.get("persistence", "maxDocumentEntries")) or 2000000))
end

local function documentDepthLimit()
    -- Each nested inventory node adds both a node table and a children list
    -- below the document envelope. Honour the configured inventory depth at
    -- its exact boundary rather than imposing a shallower generic copy limit.
    local inventoryDepth = math.max(1, math.floor(tonumber(
        SC.Config.get("persistence", "maxSavedInventoryDepth")) or 12))
    return math.max(32, 10 + inventoryDepth * 2)
end

local function sortedKeys(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key in pairs(source) do result[#result + 1] = key end
    table.sort(result, function(left, right)
        local leftType, rightType = type(left), type(right)
        if leftType ~= rightType then return leftType < rightType end
        if leftType == "number" then return left < right end
        return tostring(left) < tostring(right)
    end)
    return result
end

local function blockSave(document, reason)
    lastDocument = document
    saveBlockedReason = tostring(reason or "save document restore did not commit")
    restoreCommitted = false
    restoreFailureReason = saveBlockedReason
    return false, saveBlockedReason
end

local function cancelEntryTicket(id, entry, context)
    if type(entry) ~= "table" or entry.spawnTicket == nil then return true end
    if SC.Actor == nil or type(SC.Actor.cancelSpawn) ~= "function" then
        return false, tostring(context or "pending replacement")
            .. " cannot cancel spawn ticket for " .. tostring(id)
            .. ": actor cancellation API is unavailable"
    end
    local called, cancelled, reason = SC.Call.protected(
        SC.Actor.cancelSpawn, entry.spawnTicket)
    if not called or cancelled ~= true then
        return false, tostring(context or "pending replacement")
            .. " cannot cancel spawn ticket for " .. tostring(id) .. ": "
            .. tostring(called and (reason or cancelled) or cancelled)
    end
    -- Only release the Lua ticket reference after its owner confirmed that the
    -- native/deferred request no longer exists. The record remains pending
    -- until the caller commits its larger transaction.
    entry.spawnTicket = nil
    entry.status = "pending"
    entry.failureClass = nil
    entry.nextAt = 0
    return true
end

local function preparePendingCancellation(context)
    for _, id in ipairs(sortedKeys(pending)) do
        local cancelled, reason = cancelEntryTicket(id, pending[id], context)
        if not cancelled then return false, reason end
    end
    return true
end

local function copyList(source, limit, path)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    limit = math.max(0, math.floor(tonumber(limit) or 0))
    path = tostring(path or "$")
    local indices = {}
    for index in pairs(source) do
        if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
            return nil, path .. " has an unsupported list key: " .. tostring(index)
        end
        if index > limit then
            return nil, path .. " index " .. tostring(index)
                .. " exceeds the configured maximum " .. tostring(limit)
        end
        indices[#indices + 1] = index
        if #indices > limit then
            return nil, path .. " contains more than the configured maximum "
                .. tostring(limit) .. " entries"
        end
    end
    table.sort(indices)
    for _, index in ipairs(indices) do
        local copy, reason = stableCopy(source[index], 4, 128,
            path .. "[" .. tostring(index) .. "]")
        if reason ~= nil then return nil, reason end
        result[index] = copy
    end
    return result, nil, #indices
end

local function hasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local listSize = SC.NativeList.size
local listGet = SC.NativeList.get

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
        local copied, copyReason = stableCopy(modData, 5,
            SC.Config.get("persistence", "maxItemModDataEntries") or 256,
            "$.inventory[].modData")
        if copyReason ~= nil then return nil, copyReason end
        if hasEntries(copied) then entry.modData = copied end
    end
    if SC.PersonalItems and type(SC.PersonalItems.personalRecord) == "function" then
        local personal = SC.PersonalItems.personalRecord(item)
        if personal then
            local copied, copyReason = stableCopy(personal, 3, 48,
                "$.inventory[].personal")
            if copyReason ~= nil then return nil, copyReason end
            entry.personal = copied
        end
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
        if nestedOk and nested ~= nil then
            local childListOk, childList = invoke(nested, "getItems")
            if not childListOk or childList == nil then
                return nil, "nested inventory item list is unavailable for "
                    .. tostring(entry.type) .. ": " .. tostring(childList)
            end
            entry.children = {}
            for index = 0, listSize(childList) - 1 do
                local child = listGet(childList, index)
                local captured, reason = captureNode(child, depth + 1, "i")
                if not captured then return nil, reason end
                entry.children[#entry.children + 1] = captured
            end
        elseif isContainerOk and isContainer == true then
            return nil, "inventory container has no nested inventory: "
                .. tostring(entry.type) .. ": " .. tostring(nested)
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
    local possessions, copyReason = stableCopy(source or {}, 6, 256, "$.possessions")
    if copyReason ~= nil then return nil, copyReason end
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
        if depth and depth > 0 then
            local nested, nestedReason = captureItem(item)
            if nested == nil then return nil, nestedReason end
            keepsake.nestedCarried = nested
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
    local possessions, possessionsReason = capturePossessions(actor, state.possessions, record.id)
    if possessions == nil then return nil, possessionsReason end
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
    local profile, copyReason = stableCopy(personality.profile, 3, 64,
        "$.personality.profile")
    if copyReason ~= nil then return nil, copyReason end
    local memories
    memories, copyReason = copyList(personality.memories,
        SC.Config.get("maxMemories"), "$.personality.memories")
    if copyReason ~= nil then return nil, copyReason end
    local background
    background, copyReason = stableCopy(personality.background, 4, 128,
        "$.personality.background")
    if copyReason ~= nil then return nil, copyReason end
    local care
    care, copyReason = stableCopy(personality.care, 4, 192, "$.personality.care")
    if copyReason ~= nil then return nil, copyReason end
    local reveals
    reveals, copyReason = stableCopy(personality.reveals, 4, 128,
        "$.personality.reveals")
    if copyReason ~= nil then return nil, copyReason end
    local objectiveCopy
    objectiveCopy, copyReason = stableCopy(objectives, 6, 512, "$.objectives")
    if copyReason ~= nil then return nil, copyReason end
    local downtimeFacts
    downtimeFacts, copyReason = copyList(downtime.facts,
        SC.Config.get("maxDowntimeFacts"), "$.downtime.facts")
    if copyReason ~= nil then return nil, copyReason end
    local vehicleCopy
    vehicleCopy, copyReason = stableCopy(vehicleState, 4, 96, "$.vehicle")
    if copyReason ~= nil then return nil, copyReason end

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
            profile = profile,
            trust = finite(personality.trust, 0),
            bond = finite(personality.bond, 0),
            morale = finite(personality.morale, 55),
            stress = finite(personality.stress, 12),
            memories = memories,
            background = background,
            care = care,
            reveals = reveals,
            timeTogetherMs = math.max(0, finite(personality.timeTogetherMs, 0)),
            lastEncouragedAt = math.max(0, finite(personality.lastEncouragedAt, 0)),
        },
        objectives = objectiveCopy,
        possessions = possessions,
        inventory = inventorySnapshot,
        skills = captureSkills(actor),
        vitals = vitals,
        knox = vitals.infected == true,
        downtime = {
            lastCompleted = downtime.lastCompleted ~= nil
                and text(downtime.lastCompleted, "", 64) or nil,
            facts = downtimeFacts,
        },
        vehicle = vehicleCopy,
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
    }
    local subsystemDefinitions = {
        { field = "factions", owner = SC.Factions, depth = 12, entries = 131072 },
        { field = "factionWorld", owner = SC.FactionWorld, depth = 8, entries = 16384 },
        { field = "baseLife", owner = SC.BaseLife, depth = 10, entries = 16384 },
        { field = "infectionCrisis", owner = SC.InfectionCrisis,
            depth = 10, entries = 16384 },
        { field = "community", owner = SC.Community, depth = 10, entries = 32768 },
    }
    for _, definition in ipairs(subsystemDefinitions) do
        local source
        local quarantine = quarantined.subsystems[definition.field]
        if quarantine ~= nil then
            source = quarantine.raw
        elseif definition.owner ~= nil and type(definition.owner.export) == "function" then
            local called, value, exportReason = pcall(definition.owner.export)
            if not called then
                return false, definition.field .. " export failed: " .. tostring(value)
            end
            if value == nil and exportReason ~= nil then
                return false, definition.field .. " export failed: "
                    .. tostring(exportReason)
            end
            source = value
        end
        local copied, reason = stableCopy(source, definition.depth, definition.entries,
            "$." .. definition.field)
        if reason ~= nil then
            return false, definition.field .. " cannot be preserved completely: "
                .. tostring(reason)
        end
        document[definition.field] = copied
    end
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
                    or (pending[record.id]
                        and (pending[record.id].raw or pending[record.id].record))
                    or (type(priorDocument) == "table"
                        and type(priorDocument[priorBucket]) == "table"
                        and priorDocument[priorBucket][record.id])
                    or (type(lastDocument) == "table"
                        and type(lastDocument[priorBucket]) == "table"
                        and lastDocument[priorBucket][record.id])
                local preserved, preserveReason = stableCopy(previous,
                    documentDepthLimit(), documentEntryLimit(),
                    "$." .. priorBucket .. "[" .. tostring(record.id) .. "]")
                if type(preserved) ~= "table" then
                    SC.Diagnostics.report("persistence", record.id,
                        "save transaction aborted; quarantined actor has no stable snapshot")
                    return false, "quarantined companion has no prior stable snapshot: "
                        .. tostring(record.id) .. ": " .. tostring(preserveReason)
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
        -- Activation works from the validated/normalized record, but a record
        -- that has not activated yet is still caller-owned save data. Re-emit
        -- the accepted raw copy so retries, backoff and terminal quarantine do
        -- not silently migrate legacy fields or discard forward-compatible
        -- values. Keep the original bucket as well: normalization must never
        -- move a record between companions and factionActors.
        local source = type(entry.raw) == "table" and entry.raw or entry.record
        if type(source) == "table" then
            local bucket = entry.bucket
            if bucket ~= "companions" and bucket ~= "factionActors" then
                bucket = entry.record and entry.record.recruited == true
                    and "companions" or "factionActors"
            end
            local destination = document[bucket]
            if destination[id] == nil then
                local copied, reason = stableCopy(source,
                    documentDepthLimit(), documentEntryLimit(),
                    "$.pending[" .. tostring(id) .. "]")
                if copied == nil then
                    return false, "pending companion cannot be preserved: " .. tostring(id)
                        .. ": " .. tostring(reason)
                end
                destination[id] = copied
            end
        end
    end
    for _, bucket in ipairs({ "companions", "factionActors" }) do
        for id, entry in pairs(quarantined[bucket]) do
            if document[bucket][id] == nil then
                local copied, reason = stableCopy(entry.raw,
                    documentDepthLimit(), documentEntryLimit(),
                    "$." .. bucket .. "[" .. tostring(id) .. "]")
                if copied == nil then
                    return false, "quarantined record cannot be preserved: "
                        .. tostring(id) .. ": " .. tostring(reason)
                end
                document[bucket][id] = copied
            end
        end
    end
    local outgoing, outgoingReason = stableCopy(document, documentDepthLimit(),
        documentEntryLimit(), "$")
    if outgoing == nil then
        return false, "outgoing save validation failed: " .. tostring(outgoingReason)
    end
    local assigned, assignmentReason = pcall(function()
        data[SC.Identity.saveKey] = outgoing
    end)
    if not assigned then
        local rolledBack, rollbackReason = pcall(function()
            data[SC.Identity.saveKey] = priorDocument
        end)
        if not rolledBack then
            return false, "save assignment failed: " .. tostring(assignmentReason)
                .. "; rollback failed: " .. tostring(rollbackReason)
        end
        return false, "save assignment failed: " .. tostring(assignmentReason)
    end
    lastDocument = outgoing
    return true, outgoing
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
    local copyReason
    clean.scalar, copyReason = stableCopy(source.scalar, 3, 64,
        "$.inventory[].scalar")
    if copyReason ~= nil then return nil, copyReason end
    clean.personal, copyReason = stableCopy(source.personal, 4, 64,
        "$.inventory[].personal")
    if copyReason ~= nil then return nil, copyReason end
    clean.modData, copyReason = stableCopy(source.modData, 5,
        SC.Config.get("persistence", "maxItemModDataEntries") or 256,
        "$.inventory[].modData")
    if copyReason ~= nil then return nil, copyReason end
    clean.firearm, copyReason = stableCopy(source.firearm, 3, 64,
        "$.inventory[].firearm")
    if copyReason ~= nil then return nil, copyReason end
    clean.fluid, copyReason = stableCopy(source.fluid, 4, 128,
        "$.inventory[].fluid")
    if copyReason ~= nil then return nil, copyReason end
    clean.visual, copyReason = stableCopy(source.visual, 5, 512,
        "$.inventory[].visual")
    if copyReason ~= nil then return nil, copyReason end
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
    local clean, copyReason = stableCopy(sourceWithoutInventory, 12, 65536,
        "$.records[" .. tostring(id) .. "]")
    if copyReason ~= nil then return nil, copyReason end
    local inventory, inventoryReason = normalizeInventorySnapshot(source.inventory)
    if inventory == nil then return nil, inventoryReason end
    clean.id = id
    clean.recruited = source.recruited == true
    clean.factionId = type(source.factionId) == "string" and text(source.factionId, "", 96) or nil
    clean.factionRole = type(source.factionRole) == "string" and text(source.factionRole, "", 32) or nil
    clean.factionLeader = source.factionLeader == true
    clean.inventory = inventory
    clean.skills, copyReason = copyList(clean.skills, 128,
        "$.records[" .. tostring(id) .. "].skills")
    if copyReason ~= nil then return nil, copyReason end
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
        local copy, copyReason = stableCopy(entry.modData, 5,
            SC.Config.get("persistence", "maxItemModDataEntries") or 256,
            "$.inventory[].modData")
        if copy == nil then return false, copyReason end
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

local function reportEquipmentFallback(companionId, kind, location, reason)
    if SC.Diagnostics == nil or type(SC.Diagnostics.report) ~= "function" then return end
    pcall(SC.Diagnostics.report, "persistence", companionId,
        "saved " .. tostring(kind) .. " item left in inventory",
        "location=" .. tostring(location) .. "; reason=" .. tostring(reason))
end

local function applyEquipment(actor, equipment, byId, companionId)
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
        if item == nil then
            return false, "worn item reference is missing at " .. tostring(worn.location)
        end
        -- Build 42's setWornItem takes an ItemBodyLocation object, not the
        -- location string we persist (that string is the location's toString,
        -- e.g. "base:pants"). The item carries its own canonical body location, so
        -- resolve it from the item; without this the call finds no matching
        -- overload and every companion (and faction member) reloads naked.
        local locOk, bodyLocation = invoke(item, "getBodyLocation")
        local location = (locOk and bodyLocation ~= nil) and bodyLocation or worn.location
        local equipped, equipReason = invoke(actor, "setWornItem", location, item)
        if not equipped then
            -- Body-location names can disappear when Build 42 or a clothing mod
            -- changes. The item tree is already restored exactly; retaining the
            -- item in inventory is safer than rolling back the entire actor.
            reportEquipmentFallback(companionId, "worn", worn.location, equipReason)
        end
    end
    for _, attached in ipairs(type(equipment.attached) == "table" and equipment.attached or {}) do
        local item = byId[attached.id]
        if item == nil then
            return false, "attached item reference is missing at " .. tostring(attached.location)
        end
        local equipped, equipReason = invoke(actor, "setAttachedItem", attached.location, item)
        if not equipped then
            reportEquipmentFallback(companionId, "attached", attached.location, equipReason)
        end
    end
    return true
end

local function applyInventory(actor, entries, companionId)
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
    local equipped, equipReason = applyEquipment(
        actor, snapshot.equipment, context.byId, companionId)
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
    local entry, copyReason = stableCopy(keepsake.nestedCarried, 5, 128,
        "$.possessions.keepsake.nestedCarried")
    if type(entry) ~= "table" then
        return false, "nested personal snapshot is invalid: " .. tostring(copyReason)
    end
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
    local inventoryOk, contextOrReason = applyInventory(actor, saved.inventory, saved.id)
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

local permanentRestoreTokens = {
    "unknown perk", "invalid", "unsupported", "missing from inventory",
    "saved fluid type", "could not be restored", "has no stable type",
    "api is unavailable", "adapter is unavailable",
}

local transientRestoreTokens = {
    "provider is unavailable", "provider unavailable", "provider is still starting",
    "bridge bootstrap has not run", "bridge is still starting",
    "world is unavailable", "cell is unavailable", "square is not currently loaded",
    "vehicle is not loaded", "spawn_pending",
}

local function classifyRestoreFailure(reason)
    local lowered = string.lower(tostring(reason or "unknown restore failure"))
    for _, token in ipairs(transientRestoreTokens) do
        if string.find(lowered, token, 1, true) then return "transient" end
    end
    for _, token in ipairs(permanentRestoreTokens) do
        if string.find(lowered, token, 1, true) then return "permanent" end
    end
    return "retryable"
end

local function restoreDelay(attempts)
    local base = math.max(1, tonumber(SC.Config.get("persistence", "restoreIntervalMs")) or 5000)
    local maximum = math.max(base,
        tonumber(SC.Config.get("persistence", "restoreMaximumBackoffMs")) or 300000)
    return math.min(maximum, base * (2 ^ math.max(0, (attempts or 1) - 1)))
end

local function failRestore(id, entry, reason, current, failureClass)
    entry.reason = tostring(reason or "unknown restore failure")
    entry.failureClass = failureClass or classifyRestoreFailure(entry.reason)
    if entry.failureClass == "transient" then
        -- Provider/bootstrap/world availability is not a destructive restore
        -- attempt. Keep probing at the base cadence so a bridge that finishes
        -- starting can resume without exhausting the actor's retry budget.
        entry.status = "waiting_environment"
        entry.nextAt = current + restoreDelay(1)
        return true
    end
    entry.attempts = (entry.attempts or 0) + 1
    entry.firstAttemptAt = entry.firstAttemptAt or current
    local maximumAttempts = math.max(1,
        tonumber(SC.Config.get("persistence", "restoreMaximumAttempts")) or 6)
    if entry.failureClass == "permanent" or entry.attempts >= maximumAttempts then
        entry.status = "quarantined"
        entry.nextAt = nil
        entry.quarantinedAt = current
        SC.Diagnostics.report("persistence", id, "restore record quarantined", entry.reason)
        return false
    end
    entry.status = "retrying"
    entry.nextAt = current + restoreDelay(entry.attempts)
    return true
end

function persistence.restorePulse(player)
    local current = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    local processed = 0
    local maximum = SC.Config.get("restorePerPulse")
    for _, id in ipairs(pendingOrder) do
        local entry = pending[id]
        if entry ~= nil and entry.status ~= "quarantined" and processed < maximum
            and current >= (entry.nextAt or 0) then
            if SC.Registry.byId(id) ~= nil then
                pending[id] = nil
            elseif entry.vehicle == true then
                processed = processed + 1
                local imported, reason = importVehicleRecord(entry.record)
                if imported then
                    pending[id] = nil
                else
                    failRestore(id, entry, reason, current)
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
                        entry.failureClass = "transient"
                    else
                        entry.spawnTicket = nil
                        failRestore(id, entry, result, current)
                    end
                else
                    local square = squareFor(entry.record)
                    if square == nil then
                        entry.nextAt = current + SC.Config.get("restoreIntervalMs")
                        entry.reason = "saved square is not currently loaded"
                        entry.failureClass = "transient"
                        entry.status = "waiting_environment"
                    else
                        local saved = entry.record
                        local actor, result, ticket = persistence.restoreAt(saved, square)
                        if actor ~= nil then
                            pending[id] = nil
                        elseif result == "spawn_pending" and ticket ~= nil then
                            entry.spawnTicket = ticket
                            entry.reason = result
                            entry.failureClass = "transient"
                            entry.status = "spawn_pending"
                        else
                            failRestore(id, entry, result, current)
                        end
                    end
                end
            end
        end
    end
    return processed, persistence.pendingCount()
end

function persistence.restore(player)
    restoreCommitted = false
    restoreFailureReason = "restore is in progress"
    local data, dataReason = playerData(player)
    if data == nil then
        restoreFailureReason = dataReason
        return false, dataReason
    end
    local readOk, document = pcall(function() return data[SC.Identity.saveKey] end)
    if not readOk then
        restoreFailureReason = "save document cannot be read: " .. tostring(document)
        return false, restoreFailureReason
    end
    if document == nil then
        local cancelled, cancelReason = preparePendingCancellation("empty-document restore")
        if not cancelled then
            saveBlockedReason = cancelReason
            restoreFailureReason = cancelReason
            return false, cancelReason
        end
        pending, pendingOrder = {}, {}
        quarantined = { companions = {}, factionActors = {}, subsystems = {} }
        lastDocument = nil
        saveBlockedReason = nil
        restoreCommitted = true
        restoreFailureReason = nil
        return true, "no SurvivorCompanion save document"
    end
    if type(document) ~= "table"
        or (document.schema ~= SC.Identity.saveSchema and document.schema ~= 1)
        or type(document.companions) ~= "table" then
        return blockSave(document, "SC_SaveV1 has an unsupported or invalid schema")
    end

    -- Prove that the complete raw envelope is preservable before any subsystem
    -- receives state. Subsystem validators never see caller-owned save tables.
    local candidateDocument, documentReason = stableCopy(document,
        documentDepthLimit(), documentEntryLimit(), "$")
    if candidateDocument == nil then
        return blockSave(document, "SC_SaveV1 cannot be preserved completely: "
            .. tostring(documentReason))
    end
    if type(candidateDocument.companions) ~= "table" then
        return blockSave(document, "SC_SaveV1 companions bucket is malformed")
    end
    if candidateDocument.factionActors ~= nil
        and type(candidateDocument.factionActors) ~= "table" then
        return blockSave(document, "SC_SaveV1 factionActors bucket is malformed")
    end

    local current = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    local candidatePending, candidateOrder = {}, {}
    local candidateQuarantine = { companions = {}, factionActors = {}, subsystems = {} }
    local function quarantineRecord(bucket, id, raw, reason, path)
        candidateQuarantine[bucket][id] = {
            raw = raw, reason = tostring(reason), path = path,
            firstSeenAt = current,
        }
        SC.Diagnostics.report("persistence", id, "save record quarantined", reason)
    end

    -- Validate both actor buckets before invoking subsystem restore. Mixed
    -- string/numeric keys are deterministic and invalid keys enter quarantine
    -- instead of reaching table.sort's incomparable-key failure.
    local seenIds, factionCandidates = {}, {}
    for _, id in ipairs(sortedKeys(candidateDocument.companions)) do
        seenIds[id] = true
        local clean, reason = validateRecord(id, candidateDocument.companions[id])
        if clean ~= nil then
            candidatePending[id] = {
                record = clean, nextAt = 0, attempts = 0, status = "pending",
                vehicle = clean.vehicle ~= nil,
                raw = candidateDocument.companions[id], bucket = "companions",
            }
            candidateOrder[#candidateOrder + 1] = id
        else
            quarantineRecord("companions", id, candidateDocument.companions[id], reason,
                "$.companions[" .. tostring(id) .. "]")
        end
    end
    local factionActors = candidateDocument.factionActors or {}
    for _, id in ipairs(sortedKeys(factionActors)) do
        if not seenIds[id] then
            local clean, reason = validateRecord(id, factionActors[id])
            if clean ~= nil and type(clean.factionId) == "string" then
                factionCandidates[#factionCandidates + 1] = {
                    id = id, record = clean, raw = factionActors[id],
                }
            else
                quarantineRecord("factionActors", id, factionActors[id],
                    reason or "faction actor has no valid faction reference",
                    "$.factionActors[" .. tostring(id) .. "]")
            end
        else
            quarantineRecord("factionActors", id, factionActors[id],
                "duplicate companion id across save buckets",
                "$.factionActors[" .. tostring(id) .. "]")
        end
    end

    -- Replacing pending work is a checked cancellation boundary. A failed or
    -- throwing cancellation keeps its ticket/record reachable, and no
    -- subsystem restore has run yet.
    local cancelled, cancelReason = preparePendingCancellation("document restore")
    if not cancelled then return blockSave(document, cancelReason) end

    local subsystemDefinitions = {
        { field = "factions", owner = SC.Factions, diagnostic = "factions" },
        { field = "factionWorld", owner = SC.FactionWorld, diagnostic = "faction-world" },
        { field = "baseLife", owner = SC.BaseLife, diagnostic = "base-life" },
        { field = "infectionCrisis", owner = SC.InfectionCrisis,
            diagnostic = "infection-crisis" },
        { field = "community", owner = SC.Community, diagnostic = "community" },
    }
    for _, definition in ipairs(subsystemDefinitions) do
        local raw = candidateDocument[definition.field]
        if raw ~= nil then
            local called, ok, reason
            local restoreInput, inputReason = stableCopy(raw,
                documentDepthLimit(), documentEntryLimit(),
                "$." .. definition.field)
            if restoreInput == nil then
                called, ok, reason = true, false, inputReason
            elseif definition.owner ~= nil and type(definition.owner.restore) == "function" then
                -- Give the subsystem a disposable working copy. A hostile or
                -- legacy restore adapter may mutate its argument before it
                -- rejects it; quarantine must still retain the accepted raw
                -- envelope byte-for-value.
                called, ok, reason = SC.Call.protected(
                    definition.owner.restore, restoreInput)
            else
                called, ok, reason = true, false, "subsystem restore adapter is unavailable"
            end
            if not called or ok ~= true then
                local failure = tostring(called and (reason or ok) or ok)
                candidateQuarantine.subsystems[definition.field] = {
                    raw = raw, reason = failure,
                    path = "$." .. definition.field, firstSeenAt = current,
                }
                SC.Diagnostics.report(definition.diagnostic, nil,
                    "subsystem save quarantined", failure)
            end
        end
    end

    -- Faction cross-references are checked only after the faction subsystem's
    -- transactional restore has published its accepted groups.
    for _, candidate in ipairs(factionCandidates) do
        local clean, id = candidate.record, candidate.id
        local groupCalled, group = false, nil
        if SC.Factions ~= nil and type(SC.Factions.group) == "function" then
            groupCalled, group = SC.Call.protected(SC.Factions.group, clean.factionId)
        end
        local available = groupCalled and group ~= nil
        if available then
            candidatePending[id] = {
                record = clean, nextAt = 0, attempts = 0, status = "pending",
                raw = candidate.raw, bucket = "factionActors",
            }
            candidateOrder[#candidateOrder + 1] = id
        else
            quarantineRecord("factionActors", id, factionActors[id],
                "faction actor references an unavailable faction",
                "$.factionActors[" .. tostring(id) .. "]")
        end
    end

    -- Vehicle import happens only after the full envelope/bucket preflight. A
    -- failed import remains pending and can be re-emitted without loss.
    for _, id in ipairs(candidateOrder) do
        local entry = candidatePending[id]
        if entry ~= nil and entry.vehicle == true then
            local called, imported, importReason = SC.Call.protected(
                importVehicleRecord, entry.record)
            if called and imported == true then
                candidatePending[id] = nil
            else
                entry.reason = tostring(called and importReason or imported)
                entry.status = "pending"
            end
        end
    end

    pending, pendingOrder, quarantined = candidatePending, candidateOrder, candidateQuarantine
    lastDocument = candidateDocument
    saveBlockedReason = nil
    restoreCommitted = true
    restoreFailureReason = nil

    -- Activation is deliberately outside the import transaction. A pulse
    -- exception cannot turn an accepted raw document into a destructive load
    -- failure or discard its pending records.
    local pulsed, pulseReason = pcall(persistence.restorePulse, player)
    if not pulsed then
        SC.Diagnostics.report("persistence", nil,
            "initial restore pulse failed; imported records retained", pulseReason)
    end
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
            status = entry.status or "pending",
            hasSpawnTicket = entry.spawnTicket ~= nil,
            failureClass = entry.failureClass,
            firstAttemptAt = entry.firstAttemptAt,
            quarantinedAt = entry.quarantinedAt,
        }
    end
    return result
end

function persistence.quarantineSnapshot()
    local result = { companions = {}, factionActors = {}, subsystems = {} }
    for _, bucket in ipairs({ "companions", "factionActors", "subsystems" }) do
        for id, entry in pairs(quarantined[bucket]) do
            result[bucket][id] = {
                reason = entry.reason, path = entry.path, firstSeenAt = entry.firstSeenAt,
            }
        end
    end
    for id, entry in pairs(pending) do
        if entry.status == "quarantined" then
            local bucket = entry.bucket
            if bucket ~= "companions" and bucket ~= "factionActors" then
                bucket = entry.record and entry.record.recruited == true
                    and "companions" or "factionActors"
            end
            result[bucket][id] = {
                reason = entry.reason,
                path = "$." .. bucket .. "[" .. tostring(id) .. "]",
                firstSeenAt = entry.quarantinedAt or entry.firstAttemptAt,
                attempts = entry.attempts,
                failureClass = entry.failureClass,
            }
        end
    end
    return result
end

function persistence.retry(id)
    if type(id) ~= "string" then return false, "companion id is required" end
    local entry = pending[id]
    if entry ~= nil then
        local cancelled, cancelReason = cancelEntryTicket(id, entry, "manual retry")
        if not cancelled then return false, cancelReason end
        entry.attempts = 0
        entry.firstAttemptAt = nil
        entry.quarantinedAt = nil
        entry.failureClass = nil
        entry.reason = "manual retry"
        entry.status = "pending"
        entry.nextAt = 0
        return true, "retry_scheduled"
    end
    for _, bucket in ipairs({ "companions", "factionActors" }) do
        local quarantine = quarantined[bucket][id]
        if quarantine ~= nil then
            local clean, reason = validateRecord(id, quarantine.raw)
            if clean == nil then return false, reason end
            if bucket == "factionActors" and (type(clean.factionId) ~= "string"
                or not SC.Factions or not SC.Factions.group(clean.factionId)) then
                return false, "faction actor references an unavailable faction"
            end
            pending[id] = {
                record = clean, raw = quarantine.raw, bucket = bucket,
                nextAt = 0, attempts = 0,
                status = "pending", reason = "manual retry",
            }
            pendingOrder[#pendingOrder + 1] = id
            quarantined[bucket][id] = nil
            return true, "retry_scheduled"
        end
    end
    return false, "quarantined companion is unavailable"
end

function persistence.retrySubsystem(field)
    local entry = type(field) == "string" and quarantined.subsystems[field] or nil
    if entry == nil then return false, "quarantined subsystem is unavailable" end
    local owners = {
        factions = SC.Factions, factionWorld = SC.FactionWorld, baseLife = SC.BaseLife,
        infectionCrisis = SC.InfectionCrisis, community = SC.Community,
    }
    local owner = owners[field]
    if owner == nil or type(owner.restore) ~= "function" then
        return false, "subsystem restore adapter is unavailable"
    end
    local restoreInput, copyReason = stableCopy(entry.raw,
        documentDepthLimit(), documentEntryLimit(),
        "$.quarantine.subsystems[" .. tostring(field) .. "]")
    if restoreInput == nil then
        return false, "quarantined subsystem cannot be copied for retry: "
            .. tostring(copyReason)
    end
    -- A retry adapter receives disposable data just like the initial import.
    -- A mutating adapter that rejects or throws must not corrupt the raw value
    -- which remains responsible for lossless passthrough on the next save.
    local called, ok, reason = SC.Call.protected(owner.restore, restoreInput)
    if not called or ok ~= true then
        return false, tostring(called and (reason or ok) or ok)
    end
    quarantined.subsystems[field] = nil
    return true, "subsystem_restored"
end

function persistence.lastDocument()
    return lastDocument
end

function persistence.restoreStatus()
    return restoreCommitted, restoreFailureReason, saveBlockedReason
end

function persistence.prepareReset()
    return preparePendingCancellation("persistence reset")
end

function persistence.reset()
    local cancelled, cancelReason = persistence.prepareReset()
    if not cancelled then return false, cancelReason end
    pending = {}
    pendingOrder = {}
    quarantined = { companions = {}, factionActors = {}, subsystems = {} }
    lastDocument = nil
    saveBlockedReason = nil
    restoreCommitted = false
    restoreFailureReason = "restore has not committed"
    return true
end

return persistence
