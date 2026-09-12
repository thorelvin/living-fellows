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
local worldStore = nil
local scheduledSave = nil
local scheduledSaveRetryAt = 0
local captureYieldHook = nil

local function captureYieldPoint()
    if captureYieldHook ~= nil then captureYieldHook() end
end
local quarantined = { companions = {}, factionActors = {}, subsystems = {} }
local targetedWorkKinds = { barricade = true, remove_barricade = true, dismantle = true }
local defaultDetachedMarkerKeys = {
    id = "LF_TradeRecoveryId",
    state = "LF_TradeRecoveryState",
    build = "LF_TradeRecoveryBuildId",
}
local itemFactsScratch = {}

local function detachedMarkerKeys(source)
    if source == nil then return defaultDetachedMarkerKeys end
    if type(source) ~= "table" then return nil end
    local result = { id = source.id, state = source.state, build = source.build }
    for _, key in ipairs({ "id", "state", "build" }) do
        if type(result[key]) ~= "string" or result[key] == "" or #result[key] > 96
            or not string.match(result[key], "^LF_[%w_]+$") then return nil end
    end
    return result
end

local function detachedIgnoredKeys(source)
    local keys = detachedMarkerKeys(source)
    if not keys then return nil end
    return { [keys.id] = true, [keys.state] = true, [keys.build] = true }
end

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

local function copiedPosition(value)
    if type(value) ~= "table" then return nil end
    local x, y, z = finite(value.x, nil), finite(value.y, nil), finite(value.z, nil)
    if x == nil or y == nil or z == nil then return nil end
    return { x = x, y = y, z = z }
end

-- Only a native actor that is still attached to its current square is allowed to
-- advance the durable position. OnSave may run after the world has begun removing
-- moving objects; getCurrentSquare()/coordinates can still return a plausible but
-- transient tile at that point. Keep the last position proven by the native health
-- contract so a shutdown membership dip cannot become a load-time relocation.
function persistence.noteStablePosition(record, current)
    if type(record) ~= "table" or record.actor == nil then
        return nil, "active actor is required"
    end
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    current = finite(current, nil) or (type(getTimestampMs) == "function"
        and select(2, pcall(getTimestampMs))) or 0
    current = finite(current, 0)
    if current < finite(record.runtime.positionUnstableUntil, 0) then
        return nil, "native position is settling"
    end
    if SC.Actor and type(SC.Actor.validateNative) == "function" then
        local called, healthy = pcall(SC.Actor.validateNative, record.actor)
        if not called or healthy ~= true then return nil, "native position is not healthy" end
    end
    local squareOk, square = invoke(record.actor, "getCurrentSquare")
    if not squareOk or square == nil then return nil, "native square is unavailable" end
    local position = positionOf(record.actor)
    if position == nil or position.x == nil or position.y == nil then
        return nil, "native position is unavailable"
    end
    record.runtime.lastStablePosition = copiedPosition(position)
    record.runtime.lastStablePositionAt = current
    return copiedPosition(position)
end

local function capturePosition(record, actor)
    local verified, reason = persistence.noteStablePosition(record)
    if verified ~= nil then return verified end
    local fallback = copiedPosition(type(record.runtime) == "table"
        and record.runtime.lastStablePosition or nil)
    if fallback ~= nil then return fallback, "last_verified_position" end
    return nil, reason or "actor has no verified stable position"
end
persistence._capturePositionForTests = capturePosition

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

-- InventoryItem exposes get/setCurrentUsesFloat even though those methods are
-- not an inverse pair for ordinary items (the base setter divides by useDelta).
-- Only DrainableComboItem implements the matching fractional-use contract.
local drainableItemFields = {
    { key = "currentUses", getter = "getCurrentUsesFloat", setter = "setCurrentUsesFloat", kind = "number" },
    { key = "usedDelta", getter = "getUsedDelta", setter = "setUsedDelta", kind = "number" },
}

-- Food carries mutable nutrition and portion data outside InventoryItem's
-- generic age/uses fields. Keep this codec explicit so a crafted or partly
-- eaten meal is not silently rebuilt with script defaults.
local foodItemFields = {
    { key = "baseHunger", getter = "getBaseHunger", setter = "setBaseHunger", kind = "number" },
    { key = "hungChange", getter = "getHungChange", setter = "setHungChange", kind = "number" },
    { key = "thirstChange", getter = "getThirstChangeUnmodified", setter = "setThirstChange", kind = "number" },
    { key = "boredomChange", getter = "getBoredomChangeUnmodified", setter = "setBoredomChange", kind = "number" },
    { key = "unhappyChange", getter = "getUnhappyChangeUnmodified", setter = "setUnhappyChange", kind = "number" },
    { key = "calories", getter = "getCalories", setter = "setCalories", kind = "number" },
    { key = "carbohydrates", getter = "getCarbohydrates", setter = "setCarbohydrates", kind = "number" },
    { key = "lipids", getter = "getLipids", setter = "setLipids", kind = "number" },
    { key = "proteins", getter = "getProteins", setter = "setProteins", kind = "number" },
    { key = "heat", getter = "getHeat", setter = "setHeat", kind = "number" },
    { key = "freezingTime", getter = "getFreezingTime", setter = "setFreezingTime", kind = "number" },
    { key = "poisonPower", getter = "getPoisonPower", setter = "setPoisonPower", kind = "integer" },
    { key = "poisonDetection", getter = "getPoisonDetectionLevel", setter = "setPoisonDetectionLevel", kind = "integer" },
    { key = "useForPoison", getter = "getUseForPoison", setter = "setUseForPoison", kind = "integer" },
    { key = "lastCookMinute", getter = "getLastCookMinute", setter = "setLastCookMinute", kind = "integer" },
    { key = "microwaved", getter = "isCookedInMicrowave", setter = "setCookedInMicrowave", kind = "boolean" },
    { key = "packaged", getter = "isPackaged", setter = "setPackaged", kind = "boolean" },
    { key = "dangerousUncooked", getter = "isbDangerousUncooked", setter = "setbDangerousUncooked", kind = "boolean" },
    { key = "removeNegativeWhenCooked", getter = "isRemoveNegativeEffectOnCooked", setter = "setRemoveNegativeEffectOnCooked", kind = "boolean" },
}

local function captureItemFields(item, fields)
    local result = {}
    for _, field in ipairs(fields) do
        local ok, value = false, nil
        if method(item, field.setter) ~= nil then ok, value = invoke(item, field.getter) end
        if ok then
            if field.kind == "boolean" and type(value) == "boolean" then
                result[field.key] = value
            elseif field.kind == "integer" and finite(value, nil) ~= nil then
                result[field.key] = math.floor(finite(value, 0))
            elseif field.kind == "number" and finite(value, nil) ~= nil then
                result[field.key] = finite(value, 0)
            end
        end
    end
    return hasEntries(result) and result or nil
end

local function isItemClass(item, className)
    if type(instanceof) ~= "function" then return false end
    local ok, result = pcall(instanceof, item, className)
    return ok and result == true
end

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

local function maskHas(mask, flag)
    return math.floor((tonumber(mask) or 0) / flag) % 2 >= 1
end

local function copiedFactGroup(prefix, fields)
    local result = {}
    for _, field in ipairs(fields) do
        local value = itemFactsScratch[prefix .. field.key]
        if value ~= nil then result[field.key] = value end
    end
    return hasEntries(result) and result or nil
end

local function captureNativeItemFacts(item)
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if bridge == nil then return nil end
    local tracing = SC.Performance and type(SC.Performance.isTracing) == "function"
        and SC.Performance.isTracing() == true
    local started = tracing and (type(getTimestampMs) == "function"
        and tonumber(getTimestampMs()) or 0) or nil
    local scope = tracing and SC.Performance.beginScope("persistence.item-native") or nil
    local called, mask = staticInvoke(bridge, "captureItemFacts", item, itemFactsScratch)
    if scope then
        SC.Performance.endScope(scope)
        SC.Performance.record("persistence.item-native", nil,
            math.max(0, (type(getTimestampMs) == "function"
                and tonumber(getTimestampMs()) or started) - started), 1, false)
    end
    mask = called and tonumber(mask) or nil
    if mask == nil or mask < 0 or itemFactsScratch.type == nil then return nil end
    local result = {
        type = text(itemFactsScratch.type, "", 128),
        condition = math.floor(finite(itemFactsScratch.condition, 0)),
        favorite = itemFactsScratch.favorite == true,
        scalar = copiedFactGroup("scalar_", scalarItemFields),
    }
    if maskHas(mask, 2) then
        result.drainable = copiedFactGroup("drainable_", drainableItemFields)
    end
    if maskHas(mask, 1) then
        result.food = copiedFactGroup("food_", foodItemFields)
    end
    if maskHas(mask, 16) and finite(itemFactsScratch.key_id, nil) ~= nil then
        result.key = { id = math.floor(finite(itemFactsScratch.key_id, -1)) }
    end
    if maskHas(mask, 4) then
        result.firearm = {
            currentAmmo = itemFactsScratch.firearm_currentAmmo,
            containsClip = itemFactsScratch.firearm_containsClip,
            roundChambered = itemFactsScratch.firearm_roundChambered,
            jammed = itemFactsScratch.firearm_jammed,
            fireMode = itemFactsScratch.firearm_fireMode,
        }
    elseif maskHas(mask, 8) then
        result.magazine = {
            currentAmmo = math.max(0, math.floor(finite(
                itemFactsScratch.magazine_currentAmmo, 0))),
        }
    end
    return result
end

local function captureItemCore(item)
    local entry = captureNativeItemFacts(item)
    local ok, value
    if entry == nil then
        local typeOk, fullType = invoke(item, "getFullType")
        if not typeOk or fullType == nil then return nil end
        entry = { type = text(fullType, "", 128) }
        ok, value = invoke(item, "getCondition")
        if ok then entry.condition = math.floor(finite(value, 0)) end
        ok, value = invoke(item, "isFavorite")
        if ok then entry.favorite = value == true end
        -- Persist only properties the concrete item can also accept.
        entry.scalar = captureItemFields(item, scalarItemFields)
        if isItemClass(item, "DrainableComboItem") then
            entry.drainable = captureItemFields(item, drainableItemFields)
        end
        local keyOk, keyId = invoke(item, "getKeyId")
        if keyOk and method(item, "setKeyId") ~= nil and finite(keyId, nil) ~= nil
            and math.floor(finite(keyId, -1)) >= 0 then
            entry.key = { id = math.floor(finite(keyId, -1)) }
        end
        -- Calling every Food getter on ordinary InventoryItem was both noisy
        -- and expensive. Only a verified Food object owns this state.
        if isItemClass(item, "Food") then
            entry.food = captureItemFields(item, foodItemFields)
        end
    end
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
    local firearm = entry.firearm ~= nil
    if entry.firearm == nil and entry.magazine == nil and type(instanceof) == "function" then
        local instanceOk, instanceResult = pcall(instanceof, item, "HandWeapon")
        firearm = instanceOk and instanceResult == true
    end
    if firearm and entry.firearm == nil then
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
    elseif entry.magazine == nil and method(item, "getCurrentAmmoCount") ~= nil
        and method(item, "setCurrentAmmoCount") ~= nil then
        -- A spare magazine is an InventoryItem (not a HandWeapon) but still tracks
        -- its loaded rounds. Persist them via a verified getter/setter so a saved
        -- magazine keeps its ammunition and stays usable reload supply after load
        -- (hasReloadAmmo checks the current count), instead of rebuilding empty (LF-02).
        local ammoOk, ammoCount = invoke(item, "getCurrentAmmoCount")
        if ammoOk and type(ammoCount) == "number" then
            entry.magazine = { currentAmmo = math.max(0, math.floor(ammoCount)) }
        end
    end
    local fluid, fluidReason = captureFluid(item)
    if fluidReason then return nil, fluidReason end
    if fluid then entry.fluid = fluid end
    entry.visual = captureItemVisual(item)
    return entry
end

local function captureItem(item)
    local performance = SC.Performance
    if not performance or type(performance.isTracing) ~= "function"
        or performance.isTracing() ~= true then return captureItemCore(item) end
    local started = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    local scope = performance.beginScope("persistence.item-capture")
    local values = SC.Call.pack(pcall(captureItemCore, item))
    performance.endScope(scope)
    local finished = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or started
    performance.record("persistence.item-capture", nil,
        math.max(0, finished - started), 1, false)
    if values[1] ~= true then error(values[2], 0) end
    return SC.Call.unpack(values, 2, values.n)
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
                captureYieldPoint()
            end
        end
        captureYieldPoint()
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

-- Trade recovery may temporarily own an item that is in neither actor
-- inventory. Capture it with the same state schema as ordinary inventories so
-- a save during recovery never degrades to an unpersisted native reference.
function persistence.captureDetachedItem(item)
    if item == nil then return nil, "detached inventory item is required" end
    local entry, reason = captureItem(item)
    if entry == nil then return nil, reason or "detached item has no stable type" end
    entry.id, entry.children, entry.weaponParts = "recovery-item", {}, {}
    local count = 1
    local nestedOk, nested = invoke(item, "getInventory")
    if nestedOk and nested ~= nil then
        local itemsOk, items = invoke(nested, "getItems")
        if not itemsOk or items == nil then
            return nil, "detached container contents are unavailable"
        end
        if listSize(items) > 0 then
            return nil, "detached trade container must remain empty"
        end
    end
    local partsOk, parts = invoke(item, "getAllWeaponParts")
    if partsOk and parts ~= nil then
        for index = 0, listSize(parts) - 1 do
            local partEntry, partReason = captureItem(listGet(parts, index))
            if partEntry == nil then
                return nil, partReason or "detached weapon part has no stable type"
            end
            count = count + 1
            partEntry.id, partEntry.children, partEntry.weaponParts =
                "recovery-part-" .. tostring(count - 1), {}, {}
            entry.weaponParts[#entry.weaponParts + 1] = partEntry
        end
    end
    return {
        schema = 2, complete = true, count = count, roots = { entry },
        equipment = { worn = {}, attached = {} },
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

-- Canonical bounded schema for the latest-downtime record (R2-06). The command
-- layer stores a structured fact {kind, label, detail, at}; capturing it as text()
-- turned the table into an opaque "table: ..." address. Preserve the structured
-- fields, keep a legacy plain string, and drop anything else.
local function captureLastDowntime(value)
    if type(value) == "string" then
        return value ~= "" and text(value, "", 64) or nil
    end
    if type(value) ~= "table" then return nil end
    local at = tonumber(value.at)
    local downtimeRecord = {
        kind = type(value.kind) == "string" and text(value.kind, "", 32) or nil,
        label = type(value.label) == "string" and text(value.label, "", 64) or nil,
        detail = type(value.detail) == "string" and text(value.detail, "", 64) or nil,
        at = at ~= nil and finite(at, nil) or nil,
    }
    if downtimeRecord.kind == nil and downtimeRecord.label == nil
        and downtimeRecord.detail == nil and downtimeRecord.at == nil then
        return nil
    end
    return downtimeRecord
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
    local position = capturePosition(record, actor)
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
            objectId = type(order.workTarget.objectId) == "string"
                and string.sub(order.workTarget.objectId, 1, 7) == "object:"
                and text(order.workTarget.objectId, "", 96) or nil,
            objectSignature = type(order.workTarget.objectSignature) == "string"
                and text(order.workTarget.objectSignature, "", 192) or nil,
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
    -- The guard/stay post lives in the actor's SC_Anchor* mod-data (kept current by
    -- the command writeStable), separate from the actor's current world position.
    -- Persist it as order.anchor so a reloaded guard returns to its post rather than
    -- to wherever it happened to be standing when saved (R2-03).
    local orderAnchor
    local anchorDataOk, anchorData = invoke(actor, "getModData")
    if anchorDataOk and type(anchorData) == "table"
        and finite(anchorData.SC_AnchorX, nil) ~= nil
        and finite(anchorData.SC_AnchorY, nil) ~= nil then
        orderAnchor = {
            x = finite(anchorData.SC_AnchorX, 0),
            y = finite(anchorData.SC_AnchorY, 0),
            z = finite(anchorData.SC_AnchorZ, 0),
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
    local ritual
    ritual, copyReason = stableCopy(personality.ritual, 5, 96,
        "$.personality.ritual")
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
            anchor = orderAnchor,
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
            ritual = ritual,
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
            lastCompleted = captureLastDowntime(downtime.lastCompleted),
            facts = downtimeFacts,
        },
        vehicle = vehicleCopy,
    }
end

function persistence.bindWorldStore(_)
    if type(ModData) ~= "table" or type(ModData.getOrCreate) ~= "function" then
        worldStore = nil
        return false, "global ModData adapter is unavailable"
    end
    local ok, store = pcall(ModData.getOrCreate, SC.Identity.worldSaveKey)
    if not ok or type(store) ~= "table" then
        worldStore = nil
        return false, "global ModData store is unavailable: " .. tostring(store)
    end
    worldStore = store
    return true, store
end

local function worldData()
    if type(worldStore) == "table" then return worldStore end
    local bound, store = persistence.bindWorldStore(false)
    if not bound then return nil, store end
    return store
end

local function scheduledSubsystemDefinitions()
    return {
        { field = "factions", owner = SC.Factions, depth = 12, entries = 131072 },
        { field = "factionWorld", owner = SC.FactionWorld, depth = 8, entries = 16384 },
        { field = "baseLife", owner = SC.BaseLife, depth = 24, entries = 65536 },
        { field = "infectionCrisis", owner = SC.InfectionCrisis,
            depth = 10, entries = 16384 },
        { field = "community", owner = SC.Community, depth = 10, entries = 32768 },
        { field = "tradeRecovery", owner = SC.Trade, depth = 14, entries = 16384 },
    }
end

local function identityAppend(result, value)
    result[#result + 1] = value ~= nil and value or false
end

local function inventoryIdentitySequence(actor)
    local result, active, expanded, count = {}, {}, {}, 0
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then return nil, "inventory_unavailable" end
    identityAppend(result, inventory)
    local function appendItem(item, depth)
        if item == nil or depth > 12 then
            return item ~= nil and "inventory_cycle_or_depth" or "nil_inventory_item"
        end
        identityAppend(result, item)
        if active[item] then return "inventory_cycle_or_depth" end
        -- Equipment collections normally reference objects already present in
        -- the root inventory. Keep that reference in the identity sequence,
        -- but do not count or walk the same object graph a second time.
        if expanded[item] then return nil end
        active[item], expanded[item], count = true, true, count + 1
        if count > (SC.Config.get("persistence", "maxSavedInventoryItems") or 2048) then
            return "inventory_identity_limit"
        end
        local nestedOk, nested = invoke(item, "getInventory")
        identityAppend(result, nestedOk and nested or false)
        if nestedOk and nested ~= nil then
            local itemsOk, items = invoke(nested, "getItems")
            if not itemsOk or items == nil then return "nested_inventory_unavailable" end
            identityAppend(result, listSize(items))
            for index = 0, listSize(items) - 1 do
                local reason = appendItem(listGet(items, index), depth + 1)
                if reason then return reason end
            end
        end
        local partsOk, parts = invoke(item, "getAllWeaponParts")
        if partsOk and parts ~= nil then
            identityAppend(result, listSize(parts))
            for index = 0, listSize(parts) - 1 do identityAppend(result, listGet(parts, index)) end
        else identityAppend(result, false) end
        active[item] = nil
        captureYieldPoint()
        return nil
    end
    local itemsOk, items = invoke(inventory, "getItems")
    if not itemsOk or items == nil then return nil, "inventory_items_unavailable" end
    identityAppend(result, listSize(items))
    for index = 0, listSize(items) - 1 do
        local reason = appendItem(listGet(items, index), 1)
        if reason then return nil, reason end
    end
    for _, getter in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local ok, item = invoke(actor, getter)
        identityAppend(result, ok and item or false)
        if ok and item ~= nil then
            local reason = appendItem(item, 1)
            if reason then return nil, reason end
        end
    end
    for _, getter in ipairs({ "getWornItems", "getAttachedItems" }) do
        local ok, collection = invoke(actor, getter)
        if not ok or collection == nil then identityAppend(result, false)
        else
            identityAppend(result, listSize(collection))
            for index = 0, listSize(collection) - 1 do
                local wrapper = listGet(collection, index)
                local itemOk, item = invoke(wrapper, "getItem")
                local locationOk, location = invoke(wrapper, "getLocation")
                identityAppend(result, itemOk and item or false)
                identityAppend(result, locationOk and tostring(location) or false)
                if itemOk and item ~= nil then
                    local reason = appendItem(item, 1)
                    if reason then return nil, reason end
                end
            end
        end
    end
    return result
end

local function sameIdentitySequence(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
    for index = 1, #left do if left[index] ~= right[index] then return false end end
    return true
end

local function abortScheduledSave(job, reason, current)
    scheduledSave = nil
    scheduledSaveRetryAt = current + math.max(100,
        tonumber(SC.Config.get("persistenceRetryDelayMs")) or 5000)
    SC.Diagnostics.report("persistence", nil,
        "scheduled save staging aborted; prior complete document retained", reason)
    return "failed", reason
end

function persistence.cancelPendingSave(reason)
    if scheduledSave == nil then return false, "idle" end
    scheduledSave.cancelled = tostring(reason or "cancelled")
    scheduledSave = nil
    return true, "cancelled"
end

function persistence.requestScheduledSave(player)
    local current = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    if scheduledSave ~= nil then return true, "already_pending" end
    if current < scheduledSaveRetryAt then return false, "retry_delayed" end
    local store, reason = worldData()
    if store == nil or saveBlockedReason ~= nil then
        return false, reason or saveBlockedReason
    end
    local records = {}
    for _, record in ipairs(SC.Registry.records()) do records[#records + 1] = record end
    scheduledSave = {
        player = player, store = store, priorDocument = store.document,
        startedAt = current,
        deadline = current + math.max(250,
            tonumber(SC.Config.get("persistenceCaptureDeadlineMs")) or 5000),
        phase = "subsystems", index = 1,
        definitions = scheduledSubsystemDefinitions(), records = records,
        actorAttempts = {},
        document = {
            schema = SC.Identity.saveSchema,
            protocol = SC.Identity.bridgeProtocol,
            savedAt = current,
            companions = {}, factionActors = {},
        },
    }
    return true, "requested"
end

local function beginScheduledCopy(job, source, depth, entries, path, assign)
    job.copyJob = SC.StableValue.beginCopy(source, {
        maxDepth = depth, maxEntries = entries, path = path,
    })
    job.copyAssign = assign
end

local function resumeScheduledCopy(job, deadline)
    local status, copied, reason = SC.StableValue.resumeCopy(job.copyJob, {
        maxUnits = 256, minUnits = 1, deadline = deadline,
        clock = type(getTimestampMs) == "function" and getTimestampMs or nil,
    })
    if status == "failed" then return false, reason end
    if status == "complete" then
        job.copyAssign(copied)
        job.copyJob, job.copyAssign = nil, nil
        return true, "complete"
    end
    return true, "yielded"
end

local function scheduledActor(job, record)
    if (record.recruited ~= true and type(record.factionId) ~= "string")
        or record.actor == nil then return true end
    local destination = record.recruited == true
        and job.document.companions or job.document.factionActors
    local bucket = record.recruited == true and "companions" or "factionActors"
    local deadOk, dead = invoke(record.actor, "isDead")
    if deadOk and dead == true then return true end
    local inactive = type(record.runtime) == "table" and record.runtime.inactive == true
    if inactive then
        local previous = record.runtime.lastStableSnapshot
            or (pending[record.id] and (pending[record.id].raw or pending[record.id].record))
            or (type(job.priorDocument) == "table"
                and type(job.priorDocument[bucket]) == "table"
                and job.priorDocument[bucket][record.id])
            or (type(lastDocument) == "table" and type(lastDocument[bucket]) == "table"
                and lastDocument[bucket][record.id])
        local preserved, reason = stableCopy(previous, documentDepthLimit(),
            documentEntryLimit(), "$." .. bucket .. "[" .. tostring(record.id) .. "]")
        if type(preserved) ~= "table" then return false, reason or "no stable snapshot" end
        destination[record.id] = preserved
        return true
    end
    local before, beforeReason = inventoryIdentitySequence(record.actor)
    if before == nil then return false, beforeReason end
    local vehicleState = SC.Vehicle and type(SC.Vehicle.stateFor) == "function"
        and SC.Vehicle.stateFor(record.actor) or nil
    local captured, reason = persistence.captureRecord(record, vehicleState)
    local after, afterReason = inventoryIdentitySequence(record.actor)
    if captured ~= nil and after ~= nil and sameIdentitySequence(before, after) then
        destination[record.id] = captured
        return true
    end
    return false, reason or afterReason or "inventory changed during capture"
end

local function resumeScheduledActor(job, record, deadline, clock)
    if job.activeActor == nil or job.activeActor.record ~= record then
        job.activeActor = {
            record = record,
            coroutine = coroutine.create(function() return scheduledActor(job, record) end),
        }
    end
    local units = 0
    captureYieldHook = function()
        units = units + 1
        if units >= 1 and clock() >= deadline then coroutine.yield("capture_yielded") end
    end
    local values = SC.Call.pack(coroutine.resume(job.activeActor.coroutine))
    captureYieldHook = nil
    if values[1] ~= true then
        job.activeActor = nil
        return false, tostring(values[2]), true
    end
    if coroutine.status(job.activeActor.coroutine) ~= "dead" then
        return nil, "yielded", false
    end
    job.activeActor = nil
    return values[2] == true, values[3], true
end

local function commitScheduled(job, outgoing)
    local assigned, assignmentReason = pcall(function() job.store.document = outgoing end)
    if not assigned then
        local rolledBack, rollbackReason = pcall(function()
            job.store.document = job.priorDocument
        end)
        return false, "save assignment failed: " .. tostring(assignmentReason)
            .. (rolledBack and "" or "; rollback failed: " .. tostring(rollbackReason))
    end
    lastDocument = outgoing
    return true
end

function persistence.pulse()
    local job = scheduledSave
    if job == nil then return "idle" end
    local clock = type(getTimestampMs) == "function" and getTimestampMs
        or function() return math.floor((os.clock and os.clock() or 0) * 1000) end
    local current = tonumber(clock()) or 0
    if current >= job.deadline then return abortScheduledSave(job, "capture deadline exceeded", current) end
    local sliceDeadline = current + math.max(0.1,
        tonumber(SC.Config.get("persistenceSliceBudgetMs")) or 0.75)
    local progressed = false
    repeat
        progressed = true
        if job.copyJob ~= nil then
            local ok, status = resumeScheduledCopy(job, sliceDeadline)
            if not ok then return abortScheduledSave(job, status, current) end
            if status == "yielded" then return "yielded" end
        elseif job.phase == "subsystems" then
            local definition = job.definitions[job.index]
            if definition == nil then job.phase, job.index = "actors", 1
            else
                local source
                local quarantine = quarantined.subsystems[definition.field]
                if quarantine ~= nil then source = quarantine.raw
                elseif definition.owner and type(definition.owner.export) == "function" then
                    local called, value, reason = pcall(definition.owner.export)
                    if not called or value == nil and reason ~= nil then
                        return abortScheduledSave(job, definition.field .. " export failed: "
                            .. tostring(called and reason or value), current)
                    end
                    source = value
                end
                local field = definition.field
                beginScheduledCopy(job, source, definition.depth, definition.entries,
                    "$." .. field, function(copied) job.document[field] = copied end)
                job.index = job.index + 1
            end
        elseif job.phase == "actors" then
            local record = job.records[job.index]
            if record == nil then job.phase, job.index = "vehicle", 1
            else
                local ok, reason, complete = resumeScheduledActor(
                    job, record, sliceDeadline, clock)
                if complete ~= true then return "yielded", reason end
                if not ok then
                    local attempts = (job.actorAttempts[record.id] or 0) + 1
                    job.actorAttempts[record.id] = attempts
                    if attempts > math.max(0, math.floor(tonumber(
                        SC.Config.get("persistenceActorRetryLimit")) or 2)) then
                        return abortScheduledSave(job, "active companion capture failed: "
                            .. tostring(record.id) .. ": " .. tostring(reason), current)
                    end
                    return "yielded", "actor_retry"
                end
                job.index = job.index + 1
            end
        elseif job.phase == "vehicle" then
            local stored = SC.Vehicle and type(SC.Vehicle.exportStored) == "function"
                and SC.Vehicle.exportStored() or {}
            for id, entry in pairs(stored) do job.document.companions[id] = entry end
            job.phase, job.index = "pending", 1
            job.pendingKeys = sortedKeys(pending)
        elseif job.phase == "pending" then
            local id = job.pendingKeys[job.index]
            if id == nil then
                job.phase, job.index = "quarantine", 1
                job.quarantineEntries = {}
                for _, bucket in ipairs({ "companions", "factionActors" }) do
                    for key, entry in pairs(quarantined[bucket]) do
                        job.quarantineEntries[#job.quarantineEntries + 1] = {
                            bucket = bucket, id = key, source = entry.raw,
                        }
                    end
                end
            else
                local entry = pending[id]
                job.index = job.index + 1
                if entry ~= nil then
                    local bucket = entry.bucket == "factionActors" and "factionActors" or "companions"
                    local source = type(entry.raw) == "table" and entry.raw or entry.record
                    if type(source) == "table" and job.document[bucket][id] == nil then
                        beginScheduledCopy(job, source, documentDepthLimit(), documentEntryLimit(),
                            "$.pending[" .. tostring(id) .. "]", function(copied)
                                job.document[bucket][id] = copied
                            end)
                    end
                end
            end
        elseif job.phase == "quarantine" then
            local entry = job.quarantineEntries[job.index]
            if entry == nil then job.phase = "final"
            else
                job.index = job.index + 1
                if job.document[entry.bucket][entry.id] == nil then
                    beginScheduledCopy(job, entry.source, documentDepthLimit(),
                        documentEntryLimit(), "$." .. entry.bucket .. "["
                            .. tostring(entry.id) .. "]", function(copied)
                                job.document[entry.bucket][entry.id] = copied
                            end)
                end
            end
        elseif job.phase == "final" then
            job.phase = "commit"
            beginScheduledCopy(job, job.document, documentDepthLimit(), documentEntryLimit(),
                "$", function(copied) job.outgoing = copied end)
        elseif job.phase == "commit" then
            local ok, reason = commitScheduled(job, job.outgoing)
            if not ok then return abortScheduledSave(job, reason, current) end
            scheduledSave, scheduledSaveRetryAt = nil, 0
            return "complete", job.outgoing
        else
            return abortScheduledSave(job, "unknown staging phase", current)
        end
    until clock() >= sliceDeadline
    return progressed and "yielded" or "idle"
end

function persistence.save(player)
    persistence.cancelPendingSave("synchronous save")
    local store, storeReason = worldData()
    if store == nil then
        return false, storeReason
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
        -- Work receipts may contain one bounded schema-2 item snapshot. Preserve
        -- that evidence deeply enough for save/reload recovery instead of
        -- truncating it at the older base-only document budget.
        { field = "baseLife", owner = SC.BaseLife, depth = 24, entries = 65536 },
        { field = "infectionCrisis", owner = SC.InfectionCrisis,
            depth = 10, entries = 16384 },
        { field = "community", owner = SC.Community, depth = 10, entries = 32768 },
        { field = "tradeRecovery", owner = SC.Trade, depth = 14, entries = 16384 },
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
    local priorDocument = store.document
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
        store.document = outgoing
    end)
    if not assigned then
        local rolledBack, rollbackReason = pcall(function()
            store.document = priorDocument
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
    clean.drainable, copyReason = stableCopy(source.drainable, 3, 16,
        "$.inventory[].drainable")
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
    clean.magazine, copyReason = stableCopy(source.magazine, 3, 64,
        "$.inventory[].magazine")
    if copyReason ~= nil then return nil, copyReason end
    clean.key, copyReason = stableCopy(source.key, 2, 8,
        "$.inventory[].key")
    if copyReason ~= nil then return nil, copyReason end
    clean.food, copyReason = stableCopy(source.food, 3, 64,
        "$.inventory[].food")
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

function persistence.validateDetachedItem(source)
    local snapshot, reason = normalizeInventorySnapshot(source)
    if snapshot == nil then return nil, reason end
    if #snapshot.roots ~= 1 then
        return nil, "detached recovery must contain exactly one root item"
    end
    return snapshot
end

local function containsOnlyIgnoredState(value, depth, budget, ignoredKeys)
    if type(value) ~= "table" or depth > 20 or budget.count <= 0 then return false end
    budget.count = budget.count - 1
    for childKey, child in pairs(value) do
        if ignoredKeys[childKey] ~= true then
            if type(child) ~= "table"
                or not containsOnlyIgnoredState(child, depth + 1, budget, ignoredKeys) then
                return false
            end
        end
    end
    return true
end

local function detachedEquivalent(left, right, depth, budget, key, ignoredKeys)
    if ignoredKeys[key] == true then return true end
    if type(left) ~= type(right) then
        if left == nil and type(right) == "table" then
            return containsOnlyIgnoredState(right, depth + 1, budget, ignoredKeys)
        end
        if right == nil and type(left) == "table" then
            return containsOnlyIgnoredState(left, depth + 1, budget, ignoredKeys)
        end
        return false
    end
    if type(left) == "number" then return math.abs(left - right) <= 0.0001 end
    if type(left) ~= "table" then return left == right end
    if depth > 20 or budget.count <= 0 then return false end
    budget.count = budget.count - 1
    for childKey, value in pairs(left) do
        if ignoredKeys[childKey] ~= true
            and not detachedEquivalent(value, right[childKey], depth + 1, budget,
                childKey, ignoredKeys) then
            return false
        end
    end
    for childKey in pairs(right) do
        if ignoredKeys[childKey] ~= true and left[childKey] == nil
            and not (type(right[childKey]) == "table"
                and containsOnlyIgnoredState(right[childKey], depth + 1,
                    budget, ignoredKeys)) then return false end
    end
    return true
end

-- A successful setter call is not enough proof for native inventory state: a
-- modded item may reject a value without throwing. Recapture the finished item
-- and compare it with the durable snapshot before recovery may be committed.
function persistence.verifyDetachedItem(item, source, markerKeys)
    local expected, expectedReason = persistence.validateDetachedItem(source)
    if expected == nil then return false, expectedReason end
    local ignored = detachedIgnoredKeys(markerKeys)
    if ignored == nil then return false, "detached recovery marker contract is invalid" end
    local actual, actualReason = persistence.captureDetachedItem(item)
    if actual == nil then return false, actualReason end
    actual, actualReason = persistence.validateDetachedItem(actual)
    if actual == nil then return false, actualReason end
    if not detachedEquivalent(expected, actual, 0, { count = 65536 }, nil, ignored) then
        return false, "restored detached item state does not match its snapshot"
    end
    return true
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

local function applyItemState(item, entry, restoredKeys, reservedModData)
    if entry.condition ~= nil and not invoke(item, "setCondition",
        math.floor(finite(entry.condition, 0))) then
        return false, "item condition could not be restored"
    end
    if entry.favorite ~= nil and not invoke(item, "setFavorite", entry.favorite == true) then
        return false, "item favourite state could not be restored"
    end
    for _, field in ipairs(scalarItemFields) do
        local value, present = nil, false
        if type(entry.scalar) == "table" then
            value, present = entry.scalar[field.key], entry.scalar[field.key] ~= nil
        end
        if present then
            if field.kind == "boolean" then value = value == true
            elseif field.kind == "integer" then value = math.floor(finite(value, 0))
            else value = finite(value, 0) end
            if not invoke(item, field.setter, value) then
                return false, "item field could not be restored: " .. field.key
            end
        end
    end
    if type(entry.drainable) == "table" then
        if not isItemClass(item, "DrainableComboItem") then
            return false, "saved drainable state targets a non-drainable item"
        end
        for _, field in ipairs(drainableItemFields) do
            local value = entry.drainable[field.key]
            if value ~= nil and not invoke(item, field.setter, finite(value, 0)) then
                return false, "drainable field could not be restored: " .. field.key
            end
        end
    end
    if type(entry.key) == "table" and entry.key.id ~= nil then
        local keyId = math.floor(finite(entry.key.id, -1))
        if keyId < 0 or not invoke(item, "setKeyId", keyId) then
            return false, "native key identity could not be restored"
        end
    end
    for _, field in ipairs(foodItemFields) do
        local value, present = nil, false
        if type(entry.food) == "table" then
            value, present = entry.food[field.key], entry.food[field.key] ~= nil
        end
        if present then
            if field.kind == "boolean" then value = value == true
            elseif field.kind == "integer" then value = math.floor(finite(value, 0))
            else value = finite(value, 0) end
            if not invoke(item, field.setter, value) then
                return false, "food field could not be restored: " .. field.key
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
        for key, value in pairs(copy) do
            if type(reservedModData) ~= "table" or reservedModData[key] ~= true then
                data[key] = value
            end
        end
    end
    if type(entry.firearm) == "table" then
        local firearm = entry.firearm
        if firearm.currentAmmo ~= nil then invoke(item, "setCurrentAmmoCount", math.floor(finite(firearm.currentAmmo, 0))) end
        if firearm.containsClip ~= nil then invoke(item, "setContainsClip", firearm.containsClip == true) end
        if firearm.roundChambered ~= nil then invoke(item, "setRoundChambered", firearm.roundChambered == true) end
        if firearm.jammed ~= nil then invoke(item, "setJammed", firearm.jammed == true) end
        if firearm.fireMode ~= nil then invoke(item, "setFireMode", tostring(firearm.fireMode)) end
    end
    if type(entry.magazine) == "table" and entry.magazine.currentAmmo ~= nil then
        invoke(item, "setCurrentAmmoCount", math.max(0, math.floor(finite(entry.magazine.currentAmmo, 0))))
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

local function inventoryContainsIdentity(inventory, item)
    if inventory == nil or item == nil then return nil end
    local itemsOk, items = invoke(inventory, "getItems")
    if not itemsOk or items == nil then return nil end
    local count = listSize(items)
    if count > 8192 then return nil end
    for index = 0, count - 1 do
        if listGet(items, index) == item then return true end
    end
    return false
end

local function journalCreatedItem(item, context, inventory, root)
    local created = { item = item, inventory = inventory, nativeId = nil }
    if type(context.created) == "table" then
        context.created[#context.created + 1] = created
    end
    context.currentInventory = inventory
    if root == true then context.rootItem = item end
    return created
end

local function markCreatedItem(item, context, root, created)
    if context.recoveryId == nil then return true end
    -- Attach the durable build identity before asking for an optional native
    -- ID. A failed ID read must not turn an already inserted object into an
    -- unmarked partial that cannot be found after reload.
    local dataOk, data = invoke(item, "getModData")
    local markers = context.markerKeys
    if dataOk and type(data) == "table" then
        data[markers.build] = context.recoveryId
        if root == true then
            data[markers.id] = context.recoveryId
            data[markers.state] = "building"
        end
    end
    local nativeIdOk, nativeId = invoke(item, "getID")
    if created then created.nativeId = nativeIdOk and nativeId or nil end
    if root == true then context.rootNativeId = nativeIdOk and nativeId or nil end
    if not dataOk or type(data) ~= "table" then
        return false, "recovery reconstruction identity could not be attached"
    end
    if not nativeIdOk or nativeId == nil then
        return false, "recovery reconstruction native identity is unavailable"
    end
    return true
end

local function clearCreatedBuildMarkers(context)
    local markers = context.markerKeys
    for _, created in ipairs(context.created) do
        local dataOk, data = invoke(created.item, "getModData")
        if not dataOk or type(data) ~= "table" then
            return false, "recovery reconstruction marker could not be finalized"
        end
        if data[markers.build] == context.recoveryId then
            data[markers.build] = nil
        end
    end
    local dataOk, data = invoke(context.rootItem, "getModData")
    if not dataOk or type(data) ~= "table"
        or data[markers.id] ~= context.recoveryId then
        return false, "recovery reconstruction root identity changed"
    end
    data[markers.state] = "verified"
    return true
end

local function cleanupCreatedItems(context)
    local markers = context.markerKeys
    local complete = true
    for index = #context.created, 1, -1 do
        local created = context.created[index]
        local item, candidates, seen = created.item, {}, {}
        local itemComplete = true
        local function addCandidate(inventory)
            if inventory ~= nil and not seen[inventory] then
                seen[inventory] = true
                candidates[#candidates + 1] = inventory
            end
        end
        addCandidate(created.inventory)
        local ownerOk, owner = invoke(item, "getContainer")
        if ownerOk then addCandidate(owner) else itemComplete = false end
        for _, inventory in ipairs(candidates) do
            local present = inventoryContainsIdentity(inventory, item)
            if present == true then invoke(inventory, "Remove", item) end
            if inventoryContainsIdentity(inventory, item) ~= false then itemComplete = false end
        end
        local afterOk, afterOwner = invoke(item, "getContainer")
        if not afterOk or afterOwner ~= nil then itemComplete = false end
        local worldOk, worldItem = invoke(item, "getWorldItem")
        if not worldOk or worldItem ~= nil then itemComplete = false end
        if not itemComplete then
            complete = false
            -- Children and weapon parts are journaled after their root. Keep
            -- that root as a durable anchor when a later artifact cannot be
            -- removed, instead of cleaning the only object recovery can find.
            break
        end
    end
    if complete then
        for _, created in ipairs(context.created) do
            local dataOk, data = invoke(created.item, "getModData")
            if dataOk and type(data) == "table" then
                if data[markers.build] == context.recoveryId then
                    data[markers.build] = nil
                end
                if data[markers.id] == context.recoveryId then
                    data[markers.id] = nil
                    data[markers.state] = nil
                end
            end
        end
    end
    return complete
end

local function createRecoveryItem(itemType)
    local factory = type(_G) == "table" and rawget(_G, "InventoryItemFactory") or nil
    if factory == nil then
        return false, "recovery reconstruction item factory is unavailable"
    end
    local createdOk, item = staticInvoke(factory, "CreateItem", itemType)
    if not createdOk or item == nil then
        return false, "inventory item could not be created: " .. tostring(itemType)
    end
    return true, item
end

local function addCreatedItem(parentInventory, itemType, context, root)
    if context.recoveryId == nil then
        local addedOk, item = invoke(parentInventory, "AddItem", itemType)
        if not addedOk or item == nil then
            return false, "inventory item could not be restored: " .. tostring(itemType)
        end
        context.currentInventory = parentInventory
        return true, item
    end

    -- Create first so the exact native object can enter the attempt ledger
    -- before AddItem executes any re-entrant or throwing mutation.
    local createdOk, itemOrReason = createRecoveryItem(itemType)
    if not createdOk then return false, itemOrReason end
    local item = itemOrReason
    local created = journalCreatedItem(item, context, parentInventory, root)
    local addedOk, added = invoke(parentInventory, "AddItem", item)
    -- Even when AddItem threw after mutation, attach all identity evidence to
    -- the retained pointer before returning control to cleanup.
    local marked, markReason = markCreatedItem(item, context, root, created)
    if not marked then return false, markReason end
    if not addedOk or added ~= item then
        return false, "inventory item insertion was not acknowledged: " .. tostring(itemType)
    end
    local member = inventoryContainsIdentity(parentInventory, item)
    local ownerOk, owner = invoke(item, "getContainer")
    if member ~= true or not ownerOk or owner ~= parentInventory then
        return false, "inventory item insertion ownership is unverified: " .. tostring(itemType)
    end
    return true, item
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
    local addedOk, item = addCreatedItem(parentInventory, entry.type, context, depth == 1)
    if not addedOk then return false, item end
    context.byId[entry.id] = item
    local stateOk, stateReason = applyItemState(item, entry, context.restoredKeys,
        context.recoveryId and context.ignoredKeys or nil)
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
        local partOk, part = addCreatedItem(
            context.rootInventory, partEntry.type, context, false)
        if not partOk then return false, part end
        context.byId[partEntry.id] = part
        local partStateOk, partStateReason = applyItemState(part, partEntry,
            context.restoredKeys, context.recoveryId and context.ignoredKeys or nil)
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

function persistence.restoreDetachedItem(actor, source, recoveryId, markerContract)
    if actor == nil then return nil, "detached item owner is unavailable" end
    local snapshot, reason = persistence.validateDetachedItem(source)
    if snapshot == nil then return nil, reason end
    local inventoryOk, inventory = invoke(actor, "getInventory")
    if not inventoryOk or inventory == nil then
        return nil, "detached item owner inventory is unavailable"
    end
    local beforeOk, beforeItems = invoke(inventory, "getItems")
    if not beforeOk or beforeItems == nil then
        return nil, "detached item owner inventory list is unavailable"
    end
    if recoveryId ~= nil and (type(recoveryId) ~= "string"
        or recoveryId == "" or #recoveryId > 128) then
        return nil, "detached recovery identity is invalid"
    end
    local markers = detachedMarkerKeys(markerContract)
    local ignored = detachedIgnoredKeys(markerContract)
    if not markers or not ignored then return nil, "detached recovery marker contract is invalid" end
    local context = {
        rootInventory = inventory, byId = {}, restoredKeys = {}, created = {},
        recoveryId = recoveryId, markerKeys = markers, ignoredKeys = ignored,
    }
    local applied, item = addInventoryNode(inventory, snapshot.roots[1], context, 1)
    if applied then
        local verified, verifyReason = persistence.verifyDetachedItem(item, snapshot, markerContract)
        if verified and recoveryId ~= nil then
            verified, verifyReason = clearCreatedBuildMarkers(context)
        end
        if verified then return item end
        applied, item = false, verifyReason
    end

    -- addInventoryNode can fail after AddItem mutates the root. Roll back only
    -- identities introduced by this attempt and preserve every pre-existing item.
    local cleaned = cleanupCreatedItems(context)
    if not cleaned then
        return nil, item, context.rootItem, context.rootNativeId, false
    end
    return nil, item, nil, nil, true
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
        local location = (locOk and bodyLocation ~= nil) and bodyLocation or nil
        if location == nil then
            -- Bags and other equippable containers have no getBodyLocation() (that
            -- is for worn clothing); their worn slot comes from canBeEquipped().
            -- Without this a companion reloaded with its backpack (e.g. base:back)
            -- left in inventory instead of on its back, and setWornItem was handed
            -- the persisted location string, which finds no matching overload.
            local equipOk, equipLocation = invoke(item, "canBeEquipped")
            if equipOk and equipLocation ~= nil then location = equipLocation end
        end
        location = location or worn.location
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
            local active = SC.Registry.byId(id)
            if active ~= nil then
                -- A registered record only counts as recovered when it is a healthy
                -- active actor. An inactive/removal-pending record means native
                -- cleanup has not finished, so keep the recovery entry (and never
                -- spawn a duplicate) until the cleanup owner resolves it (R2-02).
                local awaitingCleanup = type(active.runtime) == "table"
                    and (active.runtime.inactive == true
                        or active.runtime.removalPending == true)
                if not awaitingCleanup then pending[id] = nil end
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
    local store, storeReason = worldData()
    if store == nil then
        restoreFailureReason = storeReason
        return false, storeReason
    end
    local readOk, document = pcall(function() return store.document end)
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
        or document.schema ~= SC.Identity.saveSchema
        or type(document.companions) ~= "table" then
        return blockSave(document, "SC_WorldV1 has an unsupported or invalid schema")
    end

    -- Prove that the complete raw envelope is preservable before any subsystem
    -- receives state. Subsystem validators never see caller-owned save tables.
    local candidateDocument, documentReason = stableCopy(document,
        documentDepthLimit(), documentEntryLimit(), "$")
    if candidateDocument == nil then
        return blockSave(document, "SC_WorldV1 cannot be preserved completely: "
            .. tostring(documentReason))
    end
    if type(candidateDocument.companions) ~= "table" then
        return blockSave(document, "SC_WorldV1 companions bucket is malformed")
    end
    if candidateDocument.factionActors ~= nil
        and type(candidateDocument.factionActors) ~= "table" then
        return blockSave(document, "SC_WorldV1 factionActors bucket is malformed")
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
        { field = "tradeRecovery", owner = SC.Trade, diagnostic = "trade-recovery" },
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

-- Recoverable retirement (LF-01): before the runtime health gate tears down a
-- still-living recruit whose native instance has failed validation past the grace
-- window, durably preserve the companion so a successful native removal cannot
-- silently delete it. A fresh capture is preferred; if the actor is already too
-- broken to capture, fall back to the last verified snapshot taken while it was
-- healthy. With neither available this refuses, so the caller blocks the
-- destructive step rather than reporting a false recovery. The preserved record is
-- placed in the restore-pending queue: the next save keeps it and restorePulse
-- re-spawns it once its square loads and the provider is ready (with the normal
-- attempt/backoff/quarantine ceiling preventing a respawn loop).
-- Repeated-retirement history keyed by stable companion id, independent of the
-- short-lived spawn ticket and NOT reset by a successful construction. It survives
-- the create -> native-failure -> retire cycle so a recurring native fault
-- eventually quarantines instead of respawning forever (R2-02). Cleared only by
-- sustained healthy activation (clearRecoveryHistory) or a game reload.
local recoveryHistory = {}

-- Ensure an id appears exactly once in the ordered pending queue, compacting any
-- stale duplicates a prior recovery cycle left behind.
local function pendingOrderEnsure(id)
    for index = #pendingOrder, 1, -1 do
        if pendingOrder[index] == id then table.remove(pendingOrder, index) end
    end
    pendingOrder[#pendingOrder + 1] = id
end

function persistence.retainForRecovery(record)
    if type(record) ~= "table" or not SC.Registry.isValidId(record.id) then
        return false, "valid_record_required"
    end
    local id = record.id
    local document = select(1, persistence.captureRecord(record))
    if type(document) ~= "table" then
        local snapshot = type(record.runtime) == "table" and record.runtime.lastStableSnapshot or nil
        if type(snapshot) == "table" then document = snapshot end
    end
    if type(document) ~= "table" then return false, "no_recoverable_snapshot" end
    local clean, cleanReason = validateRecord(id, document)
    if clean == nil then return false, cleanReason or "unrecoverable_snapshot" end
    local bucket = type(clean.factionId) == "string" and "factionActors" or "companions"
    local retirements = (recoveryHistory[id] or 0) + 1
    recoveryHistory[id] = retirements
    local maxRetirements = math.max(1,
        tonumber(SC.Config.get("recoveryMaxRetirements")) or 5)
    -- A companion that keeps failing its native health check shortly after each
    -- successful spawn is quarantined once it exceeds the retirement ceiling: it is
    -- still saved and manually retryable, but restorePulse stops auto-respawning it
    -- so the fault does not loop indefinitely.
    local quarantined = retirements > maxRetirements
    local now = type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
    pendingOrderEnsure(id)
    pending[id] = {
        record = clean, raw = document, bucket = bucket,
        nextAt = quarantined and nil or 0, attempts = 0,
        status = quarantined and "quarantined" or "pending",
        quarantinedAt = quarantined and now or nil,
        vehicle = clean.vehicle ~= nil, recovered = true, retirements = retirements,
    }
    SC.Diagnostics.report("persistence", id, quarantined
        and "recovery quarantined after repeated native retirement"
        or "recruit retained for recovery after health-gate retirement",
        quarantined and tostring(retirements) or cleanReason)
    return true, quarantined and "quarantined" or "retained"
end

-- Sustained healthy activation clears the repeated-retirement history so a single
-- transient dip does not accumulate toward the quarantine ceiling.
function persistence.clearRecoveryHistory(id)
    if type(id) == "string" then recoveryHistory[id] = nil end
end

function persistence.recoveryRetirements(id)
    return type(id) == "string" and (recoveryHistory[id] or 0) or 0
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
    persistence.cancelPendingSave("persistence reset")
    local cancelled, cancelReason = persistence.prepareReset()
    if not cancelled then return false, cancelReason end
    pending = {}
    pendingOrder = {}
    quarantined = { companions = {}, factionActors = {}, subsystems = {} }
    recoveryHistory = {}
    lastDocument = nil
    saveBlockedReason = nil
    restoreCommitted = false
    restoreFailureReason = "restore has not committed"
    worldStore = nil
    scheduledSaveRetryAt = 0
    return true
end

return persistence
