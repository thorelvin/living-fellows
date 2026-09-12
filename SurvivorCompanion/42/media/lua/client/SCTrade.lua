-- SPDX-License-Identifier: MIT

if type(require) == "function" then pcall(require, "SCNativeList") end

local SC = SurvivorCompanion
SC.Trade = SC.Trade or {}

local Trade = SC.Trade
local authorized = false
local authorizationSerial = 0
local pendingRecoveries = {}
local recoverySerial = 0
local recoveryCursorSerial = 0
local recoveryMarker = "LF_TradeRecoveryId"
local recoveryStateMarker = "LF_TradeRecoveryState"
local recoveryBuildMarker = "LF_TradeRecoveryBuildId"

local values = {
    ["Base.Plank"] = 4, ["Base.Nails"] = 1, ["Base.NailsBox"] = 20,
    ["Base.Hammer"] = 18, ["Base.HandAxe"] = 28, ["Base.Axe"] = 45,
    ["Base.Bandage"] = 6, ["Base.Disinfectant"] = 18, ["Base.FirstAidKit"] = 32,
    ["Base.WaterBottle"] = 10, ["Base.CannedSardines"] = 8,
    ["Base.CannedCornedBeef"] = 10, ["Base.Battery"] = 5, ["Base.Lighter"] = 7,
}
local categoryValues = {
    food = 6, water = 8, ammunition = 4, medicine = 8,
    weapon = 10, tools = 8, construction = 3, clothing = 2, other = 1,
}

local function U()
    return SC.GameplayUtil
end

local function recoverySetting(name, fallback, minimum, maximum)
    local value = tonumber(SC.Config and SC.Config.get and SC.Config.get(name)) or fallback
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function recoveryEntryLimit()
    return recoverySetting("tradeRecoveryMaxEntries", 256, 1, 4096)
end

local function pendingRecoveryCount()
    local count = 0
    for _ in pairs(pendingRecoveries) do count = count + 1 end
    return count
end

local function invoke(object, methodName, ...)
    local value, called, b, c = U().call(object, methodName, ...)
    return called, value, b, c
end

local function perceptionRuntime(actor)
    if actor == nil or not SC.Registry or type(SC.Registry.idOf) ~= "function"
        or type(SC.Registry.byId) ~= "function" then return nil end
    local id = SC.Registry.idOf(actor)
    local record = id and SC.Registry.byId(id) or nil
    return record and record.runtime or nil
end

local function safePerceptionComplete(snapshot)
    if SC.Senses and type(SC.Senses.isCompleteObservation) == "function" then
        local called, safe, reason = pcall(SC.Senses.isCompleteObservation, snapshot)
        if not called then return false, "danger_check_unavailable" end
        return safe == true, reason
    end
    if type(snapshot) ~= "table" or snapshot.valid ~= true then
        return false, "danger_check_unavailable"
    end
    if (tonumber(snapshot.threatCount) or 0) > 0 then return false, "danger_nearby" end
    if snapshot.scanComplete ~= true or snapshot.scanDiscoveryComplete ~= true
        or snapshot.scanVisualComplete ~= true then
        return false, "danger_check_pending"
    end
    if type(snapshot.nativeDiscovery) == "table"
        and (snapshot.nativeDiscovery.complete ~= true
            or snapshot.nativeDiscovery.freshComplete ~= true) then
        return false, "danger_check_pending"
    end
    return true
end

local listSize = SC.NativeList.size
local listGet = SC.NativeList.get

local function fullType(item)
    local ok, value = invoke(item, "getFullType")
    return ok and type(value) == "string" and value or ""
end

local function itemCategory(item)
    local ok, category = invoke(item, "getCategory")
    category = ok and string.lower(tostring(category or "")) or ""
    local itemType = string.lower(fullType(item))
    local foodOk, food = invoke(item, "isFood")
    if (foodOk and food == true) or category == "food" then return "food" end
    local waterOk, water = invoke(item, "isWaterSource")
    if (waterOk and water == true) or string.find(itemType, "water", 1, true) then return "water" end
    if string.find(category, "ammo", 1, true) or string.find(itemType, "ammo", 1, true)
        or string.find(itemType, "bullets", 1, true) then return "ammunition" end
    if string.find(itemType, "bandage", 1, true)
        or string.find(itemType, "disinfect", 1, true)
        or string.find(itemType, "rippedsheets", 1, true)
        or string.find(itemType, "alcoholwipes", 1, true)
        or string.find(itemType, "firstaid", 1, true)
        or string.find(category, "medical", 1, true) then return "medicine" end
    local weaponOk, weapon = invoke(item, "isWeapon")
    if weaponOk and weapon == true then return "weapon" end
    if string.find(itemType, "hammer", 1, true) or string.find(itemType, "saw", 1, true)
        or string.find(itemType, "screwdriver", 1, true) then return "tools" end
    if string.find(itemType, "plank", 1, true) or string.find(itemType, "nails", 1, true)
        or category == "material" then return "construction" end
    return category
end

local function collect(container, rows, depth, budget)
    if container == nil then return end
    if depth > 4 or budget.count <= 0 then
        budget.complete = false
        return
    end
    local ok, items = invoke(container, "getItems")
    if not ok or items == nil then
        budget.complete = false
        return
    end
    for index = 0, listSize(items) - 1 do
        if budget.count <= 0 then budget.complete = false break end
        budget.count = budget.count - 1
        local item = listGet(items, index)
        if item ~= nil then
            rows[#rows + 1] = { item = item, container = container }
            local nestedOk, nested = invoke(item, "getInventory")
            if nestedOk and nested ~= nil and nested ~= container then
                collect(nested, rows, depth + 1, budget)
            end
        end
    end
end

local function actorInventory(actor)
    local ok, inventory = invoke(actor, "getInventory")
    return ok and inventory or nil
end

local function actorForGroup(group)
    if type(group) ~= "table" then return nil end
    local fallback
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true
            and member.actorId then
            local record = SC.Registry and SC.Registry.byId(member.actorId) or nil
            if record and record.actor then
                if member.role == "leader" then return record.actor end
                fallback = fallback or record.actor
            end
        end
    end
    return fallback
end

local function isEquipped(actor, item)
    local ok, primary = invoke(actor, "getPrimaryHandItem")
    if ok and primary == item then return true end
    ok, primary = invoke(actor, "getSecondaryHandItem")
    if ok and primary == item then return true end
    local wornOk, worn = invoke(actor, "getWornItems")
    if wornOk and worn ~= nil then
        local containsOk, contains = invoke(worn, "contains", item)
        if containsOk and contains == true then return true end
    end
    return false
end

local function clearQuestTags(item)
    local data = U().modData(item)
    if type(data) ~= "table" then return end
    data.LF_QuestItem, data.LF_QuestReward = nil, nil
    data.LF_QuestId, data.LF_QuestInstanceId = nil, nil
    data.LF_QuestFactionId, data.LF_QuestRewardChoice = nil, nil
end

local function existingModData(item)
    if type(item) == "table" then return item.modData or item.__modData end
    local hasData, called = invoke(item, "hasModData")
    if called and hasData ~= true then return nil end
    return U().modData(item)
end

local function protected(actor, item)
    if isEquipped(actor, item) then return true end
    local data = existingModData(item)
    if type(data) == "table" and (data[recoveryMarker] ~= nil
        or data[recoveryBuildMarker] ~= nil) then return true end
    if type(data) == "table" and (data.LF_QuestItem == true or data.LF_QuestReward == true) then
        local group = data.LF_QuestFactionId and SC.Factions
            and type(SC.Factions.group) == "function"
            and SC.Factions.group(data.LF_QuestFactionId) or nil
        local active = group and group.social and group.social.contract
            and group.social.contract.active or nil
        if active and active.id == data.LF_QuestId and active.status == "active" then return true end
        -- A withdrawn/expired quest must not leave permanent protected junk in
        -- a world or resident inventory. Unknown factions stay protected.
        if group then clearQuestTags(item) else return true end
    end
    if SC.PersonalItems and type(SC.PersonalItems.isProtected) == "function" then
        local ok, result = pcall(SC.PersonalItems.isProtected, item, actor, "trade")
        if ok and result == true then return true end
    end
    return false
end

local function hasContents(item)
    local ok, nested = invoke(item, "getInventory")
    if not ok or nested == nil then return false end
    local itemsOk, items = invoke(nested, "getItems")
    return itemsOk and items ~= nil and listSize(items) > 0
end

local function containerBelongsTo(container, root, depth)
    if container == root then return true end
    if container == nil or root == nil or (depth or 0) > 5 then return false end
    local itemOk, containingItem = invoke(container, "getContainingItem")
    if not itemOk or containingItem == nil then return false end
    local parentOk, parent = invoke(containingItem, "getContainer")
    if not parentOk or parent == container then return false end
    return containerBelongsTo(parent, root, (depth or 0) + 1)
end

local function validateRows(rows, actor, root, allowProtected)
    local seen = {}
    for _, row in ipairs(rows or {}) do
        if type(row) ~= "table" or row.item == nil or row.container == nil then
            return false, "invalid_trade_selection"
        end
        if seen[row.item] then return false, "duplicate_trade_selection" end
        seen[row.item] = true
        local currentOk, current = invoke(row.item, "getContainer")
        if not currentOk or current ~= row.container
            or not containerBelongsTo(row.container, root, 0) then
            return false, "trade_selection_changed"
        end
        if hasContents(row.item) then return false, "container_must_be_empty" end
        if not allowProtected and protected(actor, row.item) then
            return false, "protected_trade_item"
        end
    end
    return true
end

local function matches(row, requirement)
    if requirement.type then return fullType(row.item) == requirement.type end
    if requirement.category then return itemCategory(row.item) == requirement.category end
    local rowType, rowCategory = fullType(row.item), itemCategory(row.item)
    for _, value in ipairs(type(requirement.types) == "table" and requirement.types or {}) do
        if rowType == value then return true end
    end
    for _, value in ipairs(type(requirement.categories) == "table"
        and requirement.categories or {}) do
        if rowCategory == value then return true end
    end
    return false
end

local function requirementLabel(requirement)
    if type(requirement.label) == "string" and requirement.label ~= "" then
        return requirement.label
    end
    if requirement.type then return requirement.type end
    if requirement.category then return requirement.category end
    if type(requirement.types) == "table" and #requirement.types > 0 then
        return table.concat(requirement.types, " or ")
    end
    if type(requirement.categories) == "table" and #requirement.categories > 0 then
        return table.concat(requirement.categories, " or ")
    end
    return "item"
end

local function selectRequirements(actor, requirements, allowProtected)
    local inventory = actorInventory(actor)
    if not inventory then return nil, "inventory_unavailable" end
    local rows = {}
    collect(inventory, rows, 0, {
        count = tonumber(SC.Config.get("factionTradeInventoryScanLimit")) or 4096,
    })
    local selected, used, progress, firstMissing = {}, {}, {}, nil
    for index, requirement in ipairs(requirements or {}) do
        local remaining = math.max(0, math.floor(tonumber(requirement.count) or 0))
        local required, available, chosen, matched, protectedMatches = remaining, 0, 0, 0, 0
        local observedTypes = {}
        for _, row in ipairs(rows) do
            if not used[row.item] and matches(row, requirement) then
                matched = matched + 1
                local rowType = fullType(row.item)
                if #observedTypes < 8 then observedTypes[#observedTypes + 1] = rowType end
                if allowProtected or not protected(actor, row.item) then
                    available = available + 1
                else protectedMatches = protectedMatches + 1 end
            end
        end
        for _, row in ipairs(rows) do
            if remaining <= 0 then break end
            if not used[row.item] and matches(row, requirement)
                and (allowProtected or not protected(actor, row.item)) then
                used[row.item] = true
                selected[#selected + 1] = row
                remaining = remaining - 1
                chosen = chosen + 1
            end
        end
        progress[#progress + 1] = {
            index = index, label = requirementLabel(requirement), required = required,
            available = available, selected = chosen, remaining = remaining,
            ready = remaining <= 0, matched = matched,
            protected = protectedMatches, observedTypes = observedTypes,
        }
        if remaining > 0 then
            firstMissing = firstMissing or ("missing_" .. requirementLabel(requirement)
                .. ":" .. tostring(remaining))
        end
    end
    if firstMissing then return nil, firstMissing, progress end
    return selected, nil, progress
end

function Trade.previewRequirements(actor, requirements, allowProtected)
    if actor == nil or type(requirements) ~= "table" or #requirements == 0 then
        return nil, "delivery_unavailable"
    end
    local selected, reason, progress = selectRequirements(actor, requirements,
        allowProtected == true)
    return progress, selected ~= nil, reason
end

local function destinationAccepts(container, owner, item)
    local ok, allowed = invoke(container, "hasRoomFor", owner, item)
    if not ok then return false, "capacity_check_unavailable" end
    if allowed ~= true then return false, "destination_full" end
    return true
end

local function destinationAcceptsAll(container, owner, rows)
    -- A one-way delivery may move items out of an already-overloaded player.
    -- Capacity is relevant only when this destination actually receives rows.
    if type(rows) ~= "table" or #rows == 0 then return true end
    local weightOk, currentWeight = invoke(container, "getCapacityWeight")
    local capacityOk, capacity = invoke(container, "getEffectiveCapacity", owner)
    if not capacityOk then capacityOk, capacity = invoke(container, "getCapacity") end
    if not weightOk or not capacityOk or tonumber(currentWeight) == nil
        or tonumber(capacity) == nil then
        return false, "capacity_check_unavailable"
    end
    local incoming = 0
    for _, row in ipairs(rows or {}) do
        local itemWeightOk, itemWeight = invoke(row.item, "getActualWeight")
        if not itemWeightOk or tonumber(itemWeight) == nil then
            return false, "capacity_check_unavailable"
        end
        incoming = incoming + math.max(0, tonumber(itemWeight))
    end
    if tonumber(currentWeight) + incoming > tonumber(capacity) + 0.001 then
        return false, "destination_full"
    end
    for _, row in ipairs(rows or {}) do
        local accepted, reason = destinationAccepts(container, owner, row.item)
        if not accepted then return false, reason end
    end
    return true
end

-- Membership in getItems() is authoritative. getContainer() is checked as a
-- second invariant because native fault paths can update only one side.
local function containerMembership(container, item)
    if container == nil or item == nil then return nil end
    local itemsOk, items = invoke(container, "getItems")
    if not itemsOk or items == nil then return nil end
    local count
    if type(items) == "table" then
        count = #items
    else
        local sizeOk, size = invoke(items, "size")
        if not sizeOk or tonumber(size) == nil then return nil end
        count = math.max(0, math.floor(tonumber(size)))
    end
    if count > 8192 then return nil end
    for index = 0, count - 1 do
        local candidate, available = listGet(items, index)
        if not available then return nil end
        if candidate == item then return true end
    end
    return false
end

local function verifiedOwner(item, expected, other)
    local expectedMember = containerMembership(expected, item)
    local otherMember = containerMembership(other, item)
    local ownerOk, owner = invoke(item, "getContainer")
    return expectedMember == true and otherMember == false
        and ownerOk and owner == expected
end

local function detachedIdentityVerified(transfer)
    local item = transfer and transfer.item or nil
    if item == nil then return false end
    if containerMembership(transfer.source, item) ~= false
        or containerMembership(transfer.destination, item) ~= false then return false end
    local ownerOk, owner = invoke(item, "getContainer")
    local worldOk, worldItem = invoke(item, "getWorldItem")
    return ownerOk and owner == nil and worldOk and worldItem == nil
end

local function removeIdentity(container, item)
    local present = containerMembership(container, item)
    if present == nil then return false end
    if present == false then return true end
    invoke(container, "Remove", item)
    return containerMembership(container, item) == false
end

local function addIdentity(container, item)
    local present = containerMembership(container, item)
    local ownerOk, owner = invoke(item, "getContainer")
    if present == nil or not ownerOk then return false end
    if present == true and ownerOk and owner == container then return true end
    if present == true and not removeIdentity(container, item) then return false end
    if owner ~= nil and owner ~= container then
        local ownerMember = containerMembership(owner, item)
        if ownerMember == nil then return false end
        if ownerMember == true and not removeIdentity(owner, item) then return false end
    end
    local addedOk, added = invoke(container, "AddItem", item)
    if not addedOk or added == false then return false end
    local afterOk, after = invoke(item, "getContainer")
    return containerMembership(container, item) == true
        and afterOk and after == container
end

local function rollback(transfers)
    local complete, failures = true, {}
    for index = #transfers, 1, -1 do
        local transfer = transfers[index]
        if transfer.resolved ~= true then
            local destinationMember = containerMembership(transfer.destination, transfer.item)
            local destinationCleared = destinationMember == false
            if destinationMember == true then
                destinationCleared = removeIdentity(transfer.destination, transfer.item)
            end
            if destinationMember == nil or not destinationCleared then
                complete = false
                failures[#failures + 1] = "destination_remove_unverified"
            end
            if destinationCleared then
                if not addIdentity(transfer.source, transfer.item)
                    or not verifiedOwner(transfer.item, transfer.source, transfer.destination) then
                    complete = false
                    failures[#failures + 1] = "source_restore_unverified"
                else
                    transfer.resolved = true
                end
            end
        end
    end
    return complete, #failures > 0 and table.concat(failures, ";") or nil
end

local function ownerDescriptor(actor, player)
    if actor == nil then return nil end
    if actor == player then return { kind = "player" } end
    local id = U().idOf(actor)
    if type(id) == "string" and id ~= "" then
        return { kind = "actor", id = id }
    end
    return nil
end

local function primaryPlayer(candidate)
    if candidate ~= nil then return candidate end
    if type(getSpecificPlayer) == "function" then
        local ok, value = pcall(getSpecificPlayer, 0)
        if ok and value ~= nil then return value end
    end
    if type(getPlayer) == "function" then
        local ok, value = pcall(getPlayer)
        if ok then return value end
    end
    return nil
end

local function resolveOwner(descriptor, player)
    if type(descriptor) ~= "table" then return nil end
    if descriptor.kind == "player" then return primaryPlayer(player) end
    if descriptor.kind ~= "actor" or type(descriptor.id) ~= "string" then return nil end
    return select(1, U().resolveActor(descriptor.id))
end

local function markerOf(item)
    local data = existingModData(item)
    return type(data) == "table" and data[recoveryMarker] or nil
end

local function recoveryStateOf(item, recoveryId)
    local data = existingModData(item)
    if type(data) ~= "table" or data[recoveryMarker] ~= recoveryId then return nil end
    local state = data[recoveryStateMarker]
    -- Recovery records created before the reconstruction state marker existed
    -- always refer to the original native item, never a generated partial.
    return state == nil and "original" or state
end

local function recoveryBuildOf(item)
    local data = existingModData(item)
    return type(data) == "table" and data[recoveryBuildMarker] or nil
end

local function nativeItemId(item)
    local ok, value = invoke(item, "getID")
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function recoveryStateReady(item, recoveryId)
    local state = recoveryStateOf(item, recoveryId)
    return state == "original" or state == "verified"
end

local function scanRecovery(actor, recoveryId, partialNativeId)
    local inventory = actorInventory(actor)
    if inventory == nil then return nil, 0, false, nil, {}, {} end
    local rows, budget = {}, { count = 8192, complete = true }
    collect(inventory, rows, 0, budget)
    local found, count, container, matches, artifacts = nil, 0, nil, {}, {}
    for _, row in ipairs(rows) do
        if markerOf(row.item) == recoveryId then
            found, container, count = found or row.item, container or row.container, count + 1
            matches[#matches + 1] = row.item
        end
        if recoveryBuildOf(row.item) == recoveryId
            or (partialNativeId ~= nil
                and nativeItemId(row.item) == tostring(partialNativeId)) then
            artifacts[#artifacts + 1] = { item = row.item, container = row.container }
        end
    end
    return found, count, budget.complete ~= false, container, matches, artifacts
end

local function clearMarker(item, recoveryId)
    local data = existingModData(item)
    if type(data) == "table" and data[recoveryMarker] == recoveryId then
        data[recoveryMarker] = nil
        data[recoveryStateMarker] = nil
    end
    if type(data) == "table" and data[recoveryBuildMarker] == recoveryId then
        data[recoveryBuildMarker] = nil
    end
end

local function placementVerifiedIn(container, item, recoveryId)
    if not recoveryStateReady(item, recoveryId)
        or containerMembership(container, item) ~= true then return false end
    local ownerOk, owner = invoke(item, "getContainer")
    return ownerOk and owner == container
end

local function currentPlacementVerified(item, recoveryId)
    if item == nil or not recoveryStateReady(item, recoveryId) then return false end
    local ownerOk, owner = invoke(item, "getContainer")
    if ownerOk and owner ~= nil and containerMembership(owner, item) == true then
        return true, "current_container_verified", owner
    end
    local worldOk, worldItem = invoke(item, "getWorldItem")
    if ownerOk and owner == nil and worldOk and worldItem ~= nil then
        return true, "current_world_item_verified", worldItem
    end
    return false
end

local function finishRecovery(transfer, item, matches, artifacts)
    transfer.resolved = true
    clearMarker(item or transfer.item, transfer.recoveryId)
    for _, candidate in ipairs(matches or {}) do
        clearMarker(candidate, transfer.recoveryId)
    end
    for _, artifact in ipairs(artifacts or {}) do
        clearMarker(artifact.item or artifact, transfer.recoveryId)
    end
    transfer.reconstructionPartial = nil
    transfer.partialNativeId = nil
    pendingRecoveries[transfer.recoveryId] = nil
end

local function discardBuildArtifacts(transfer, artifacts)
    local rows, seen = {}, {}
    for _, artifact in ipairs(artifacts or {}) do
        local item = artifact.item or artifact
        if item ~= nil and not seen[item] then
            seen[item] = true
            rows[#rows + 1] = { item = item, container = artifact.container }
        end
    end
    local candidate = transfer.item
    if candidate ~= nil and (transfer.reconstructionPartial == true
        or recoveryBuildOf(candidate) == transfer.recoveryId)
        and not seen[candidate] then
        local ownerOk, owner = invoke(candidate, "getContainer")
        if not ownerOk then return false, "partial_reconstruction_owner_unavailable" end
        rows[#rows + 1] = { item = candidate, container = owner }
        seen[candidate] = true
    end
    if #rows == 0 and (transfer.reconstructionPartial == true
        or transfer.partialNativeId ~= nil) then
        -- A persisted partial flag says an earlier native object may still
        -- exist. Failure to locate it in these two inventories is not proof
        -- that it vanished from the world, a corpse, or a third container.
        return false, "partial_reconstruction_not_located"
    end
    for index = #rows, 1, -1 do
        local row = rows[index]
        local inventory = row.container
        if inventory ~= nil and containerMembership(inventory, row.item) == true
            and not removeIdentity(inventory, row.item) then
            return false, "partial_reconstruction_cleanup_failed"
        end
        local ownerOk, owner = invoke(row.item, "getContainer")
        if not ownerOk or owner ~= nil then
            return false, "partial_reconstruction_cleanup_unverified"
        end
        local worldOk, worldItem = invoke(row.item, "getWorldItem")
        if not worldOk or worldItem ~= nil then
            return false, "partial_reconstruction_world_ownership_unverified"
        end
    end
    for _, row in ipairs(rows) do clearMarker(row.item, transfer.recoveryId) end
    if candidate ~= nil and seen[candidate] then transfer.item = nil end
    return true, nil, #rows
end

local function rememberRecovery(transfers, group, reason, rollbackReason, player)
    local retained, captureFailure = 0, nil
    for _, transfer in ipairs(transfers) do
        if transfer.resolved ~= true then
            recoverySerial = recoverySerial + 1
            transfer.serial = recoverySerial
            transfer.recoveryId = "lf-trade:" .. tostring(U().nowMs())
                .. ":" .. tostring(recoverySerial)
            transfer.factionId = group and group.id or nil
            transfer.reason = tostring(reason or "transaction_failed")
            transfer.rollbackReason = tostring(rollbackReason or "ownership_unverified")
            transfer.recordedAt = U().nowMs()
            transfer.attempts = 0
            transfer.nextAttemptAt = transfer.recordedAt
            transfer.phase = "recovery_pending"
            transfer.reconstructionPartial, transfer.partialNativeId = nil, nil
            transfer.detachedProof = detachedIdentityVerified(transfer)
            transfer.sourceOwner = ownerDescriptor(transfer.sourceActor, player)
            transfer.destinationOwner = ownerDescriptor(transfer.destinationActor, player)
            local data = U().modData(transfer.item)
            if type(data) ~= "table" or transfer.sourceOwner == nil
                or transfer.destinationOwner == nil then
                captureFailure = captureFailure or "trade recovery identity is unavailable"
            elseif pendingRecoveryCount() >= recoveryEntryLimit() then
                captureFailure = captureFailure or "trade recovery capacity is exhausted"
            else
                data[recoveryMarker] = transfer.recoveryId
                data[recoveryStateMarker] = "original"
                data[recoveryBuildMarker] = nil
                pendingRecoveries[transfer.recoveryId] = transfer
                retained = retained + 1
                local capture = SC.Persistence
                    and type(SC.Persistence.captureDetachedItem) == "function"
                    and SC.Persistence.captureDetachedItem or nil
                local snapshot, snapshotReason
                if capture then
                    snapshot, snapshotReason = capture(transfer.item)
                else
                    snapshotReason = "detached item persistence is unavailable"
                end
                if snapshot == nil then
                    captureFailure = captureFailure or snapshotReason
                else
                    transfer.itemState = snapshot
                end
            end
        end
    end
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("trade-transaction", group and group.id or nil,
            "item ownership retained for recovery",
            tostring(reason) .. "; " .. tostring(rollbackReason)
                .. (captureFailure and "; " .. tostring(captureFailure) or ""))
    end
    return retained > 0 and captureFailure == nil, captureFailure
end

local function recoverTransfer(transfer, player)
    local sourceActor = resolveOwner(transfer.sourceOwner, player) or transfer.sourceActor
    local destinationActor = resolveOwner(transfer.destinationOwner, player)
        or transfer.destinationActor
    if sourceActor == nil or destinationActor == nil then return false, "owner_unavailable" end
    local sourceInventory = actorInventory(sourceActor)
    if sourceInventory == nil then return false, "source_inventory_unavailable" end
    local sourceItem, sourceCount, sourceComplete, sourceContainer, sourceMatches,
        sourceArtifacts = scanRecovery(sourceActor, transfer.recoveryId,
            transfer.partialNativeId)
    local destinationItem, destinationCount, destinationComplete, destinationContainer,
        destinationMatches, destinationArtifacts
    if destinationActor == sourceActor then
        destinationItem, destinationCount, destinationComplete, destinationContainer,
            destinationMatches, destinationArtifacts = nil, 0, sourceComplete, nil, {}, {}
    else
        destinationItem, destinationCount, destinationComplete, destinationContainer,
            destinationMatches, destinationArtifacts = scanRecovery(
                destinationActor, transfer.recoveryId, transfer.partialNativeId)
    end
    if not sourceComplete or not destinationComplete then return false, "inventory_scan_pending" end
    if sourceCount + destinationCount > 1 then return false, "duplicate_recovery_identity" end
    if sourceCount + destinationCount == 1 then
        local item = sourceItem or destinationItem
        local container = sourceCount == 1 and sourceContainer or destinationContainer
        if recoveryStateReady(item, transfer.recoveryId)
            and placementVerifiedIn(container, item, transfer.recoveryId) then
            if sourceCount ~= 1 then
                -- A safe item at the transaction recipient is still an
                -- uncompensated half trade. Move the same identity back to the
                -- original source before closing its recovery record.
                if not addIdentity(sourceInventory, item)
                    or not placementVerifiedIn(sourceInventory, item,
                        transfer.recoveryId) then
                    return false, "source_compensation_unverified"
                end
                container, sourceMatches, sourceArtifacts = sourceInventory,
                    destinationMatches, destinationArtifacts
            end
            finishRecovery(transfer, item,
                sourceCount == 1 and sourceMatches or destinationMatches,
                sourceCount == 1 and sourceArtifacts or destinationArtifacts)
            return true, sourceCount == 1 and "source_owner_verified"
                or "source_owner_compensated"
        end
        if recoveryStateOf(item, transfer.recoveryId) ~= "building" then
            return false, "reconstruction_state_unverified"
        end
    end

    local artifacts = {}
    for _, artifact in ipairs(sourceArtifacts or {}) do artifacts[#artifacts + 1] = artifact end
    for _, artifact in ipairs(destinationArtifacts or {}) do artifacts[#artifacts + 1] = artifact end
    if #artifacts > 0 or transfer.reconstructionPartial == true
        or recoveryBuildOf(transfer.item) == transfer.recoveryId then
        local expectedPartialNativeId = transfer.partialNativeId
        local discarded, discardReason, discardedCount =
            discardBuildArtifacts(transfer, artifacts)
        if not discarded then return false, discardReason end
        sourceItem, sourceCount, sourceComplete = scanRecovery(
            sourceActor, transfer.recoveryId, expectedPartialNativeId)
        if destinationActor == sourceActor then
            destinationItem, destinationCount, destinationComplete = nil, 0, sourceComplete
        else
            destinationItem, destinationCount, destinationComplete = scanRecovery(
                destinationActor, transfer.recoveryId, expectedPartialNativeId)
        end
        if not sourceComplete or not destinationComplete
            or sourceCount + destinationCount ~= 0 then
            return false, "partial_reconstruction_cleanup_unverified"
        end
        if (discardedCount or 0) < 1 then
            return false, "partial_reconstruction_cleanup_unproven"
        end
        transfer.reconstructionPartial, transfer.partialNativeId = nil, nil
        transfer.detachedProof = true
    end

    local candidate = transfer.item
    if candidate ~= nil and markerOf(candidate) ~= transfer.recoveryId then candidate = nil end
    if candidate ~= nil then
        local placed, placementReason = currentPlacementVerified(
            candidate, transfer.recoveryId)
        if placementReason == "current_world_item_verified" then
            return false, "world_item_compensation_pending"
        end
        if not placed and transfer.detachedProof ~= true then
            return false, "current_item_placement_unverified"
        end
        if not addIdentity(sourceInventory, candidate) then return false, "source_restore_unverified" end
    else
        if transfer.detachedProof ~= true then return false, "detached_absence_unproven" end
        local restore = SC.Persistence
            and type(SC.Persistence.restoreDetachedItem) == "function"
            and SC.Persistence.restoreDetachedItem or nil
        if restore == nil then return false, "detached_item_restore_unavailable" end
        local restored, restoreReason, partial, partialNativeId, cleanupVerified = restore(
            sourceActor, transfer.itemState, transfer.recoveryId)
        if restored == nil then
            if partial ~= nil then
                transfer.item = partial
                transfer.reconstructionPartial = true
                transfer.partialNativeId = partialNativeId or nativeItemId(partial)
                transfer.detachedProof = false
            elseif cleanupVerified == true then
                transfer.detachedProof = true
            end
            return false, restoreReason
        end
        candidate, transfer.item = restored, restored
    end

    sourceItem, sourceCount, sourceComplete, sourceContainer, sourceMatches,
        sourceArtifacts = scanRecovery(sourceActor, transfer.recoveryId,
            transfer.partialNativeId)
    if destinationActor == sourceActor then
        destinationItem, destinationCount, destinationComplete = nil, 0, sourceComplete
    else
        destinationItem, destinationCount, destinationComplete = scanRecovery(
            destinationActor, transfer.recoveryId, transfer.partialNativeId)
    end
    if sourceComplete and destinationComplete and sourceCount == 1
        and destinationCount == 0 and recoveryStateReady(sourceItem, transfer.recoveryId)
        and placementVerifiedIn(sourceContainer, sourceItem, transfer.recoveryId) then
        finishRecovery(transfer, sourceItem or candidate, sourceMatches, sourceArtifacts)
        return true
    end
    return false, "source_restore_unverified"
end

local function reportRecoveryTerminal(transfer, reason, settled)
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("trade-recovery", transfer.factionId,
            settled and "bounded recovery settled at current owner"
                or "bounded recovery quarantined without creating a copy",
            tostring(reason) .. "; attempts=" .. tostring(transfer.attempts or 0)
                .. "; recovery=" .. tostring(transfer.recoveryId))
    end
end

local function quarantineRecovery(transfer, reason)
    transfer.phase = "recovery_quarantined"
    transfer.quarantineReason = tostring(reason or "recovery_limit_reached")
    transfer.quarantinedAt = U().nowMs()
    transfer.nextAttemptAt = nil
    reportRecoveryTerminal(transfer, transfer.quarantineReason, false)
    return false
end

local function pruneQuarantined(current)
    current = tonumber(current) or U().nowMs()
    local retention = recoverySetting("tradeRecoveryQuarantineRetentionMs",
        600000, 10000, 86400000)
    local maximum = recoverySetting("tradeRecoveryMaxQuarantinedEntries", 64, 1, 1024)
    local rows = {}
    for id, transfer in pairs(pendingRecoveries) do
        if transfer.phase == "recovery_quarantined" then
            rows[#rows + 1] = { id = id, transfer = transfer,
                at = tonumber(transfer.quarantinedAt) or current }
        end
    end
    table.sort(rows, function(left, right)
        if left.at == right.at then return tostring(left.id) < tostring(right.id) end
        return left.at < right.at
    end)
    local excess = math.max(0, #rows - maximum)
    for index, row in ipairs(rows) do
        if index <= excess or current - row.at >= retention then
            clearMarker(row.transfer.item, row.transfer.recoveryId)
            pendingRecoveries[row.id] = nil
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                SC.Diagnostics.report("trade-recovery", row.transfer.factionId,
                    "expired terminal quarantine record",
                    "recovery=" .. tostring(row.transfer.recoveryId))
            end
        end
    end
end

function Trade.recoverPending(player, maximum, force)
    pruneQuarantined()
    local records = {}
    for _, record in pairs(pendingRecoveries) do
        if record.phase == "recovery_pending"
            or (force == true and record.phase == "recovery_quarantined") then
            records[#records + 1] = record
        end
    end
    table.sort(records, function(left, right)
        return (tonumber(left.serial) or 0) < (tonumber(right.serial) or 0)
    end)
    if #records == 0 then return true end
    local start = 1
    for index, record in ipairs(records) do
        if (tonumber(record.serial) or 0) > recoveryCursorSerial then
            start = index
            break
        end
        if index == #records then start = 1 end
    end
    local processed, visited, now = 0, 0, U().nowMs()
    local limit = math.max(0, math.floor(tonumber(maximum) or #records))
    local maximumAttempts = recoverySetting("tradeRecoveryMaxAttempts", 8, 1, 64)
    local maximumAge = recoverySetting("tradeRecoveryMaxAgeMs", 30000, 1000, 3600000)
    local retryBase = recoverySetting("tradeRecoveryRetryBaseMs", 500, 50, 60000)
    local retryMaximum = recoverySetting("tradeRecoveryRetryMaximumMs", 5000,
        retryBase, 300000)
    while visited < #records and processed < limit do
        local index = ((start + visited - 1) % #records) + 1
        local record = records[index]
        visited = visited + 1
        recoveryCursorSerial = math.max(0, math.floor(tonumber(record.serial) or 0))
        local age = math.max(0, now - (tonumber(record.recordedAt) or now))
        if force == true or age >= maximumAge
            or now >= (tonumber(record.nextAttemptAt) or 0) then
            processed = processed + 1
            record.attempts = math.max(0, math.floor(tonumber(record.attempts) or 0)) + 1
            record.lastAttemptAt = now
            local restored, reason = recoverTransfer(record, player)
            if not restored then
                record.rollbackReason = tostring(reason or record.rollbackReason)
                local unavailable = reason == "owner_unavailable"
                    or reason == "source_inventory_unavailable"
                    or reason == "destination_inventory_unavailable"
                if unavailable and force ~= true and age < maximumAge then
                    -- Dormant companions commonly spawn after persistence is
                    -- restored. Missing runtime owners are not failed item
                    -- reconstruction attempts while the restored bounded
                    -- availability window is still open.
                    record.attempts = math.max(0, record.attempts - 1)
                    record.nextAttemptAt = now + retryMaximum
                elseif record.attempts >= maximumAttempts or age >= maximumAge then
                    quarantineRecovery(record, reason or "recovery_limit_reached")
                else
                    local delay = math.min(retryMaximum,
                        retryBase * (2 ^ math.min(10, record.attempts - 1)))
                    record.nextAttemptAt = now + delay
                end
            end
        end
    end
    local pending = false
    for _, record in pairs(pendingRecoveries) do
        if record.phase == "recovery_pending" then pending = true break end
    end
    return not pending, pending and "trade_recovery_pending" or nil
end

function Trade.pendingRecoveryCount()
    return pendingRecoveryCount()
end

function Trade.hasPendingFaction(factionId)
    if type(factionId) ~= "string" or factionId == "" then return false end
    for _, transfer in pairs(pendingRecoveries) do
        if transfer.factionId == factionId and transfer.phase == "recovery_pending" then
            return true
        end
    end
    return false
end

function Trade.hasPendingActor(actor)
    local id = type(actor) == "string" and actor or U().idOf(actor)
    for _, transfer in pairs(pendingRecoveries) do
        if transfer.phase == "recovery_pending" then
        for _, descriptor in ipairs({ transfer.sourceOwner, transfer.destinationOwner }) do
            if type(descriptor) == "table"
                and ((descriptor.kind == "player" and actor == primaryPlayer())
                    or (descriptor.kind == "actor" and descriptor.id == id)) then return true end
        end
        end
    end
    return false
end

function Trade.prepareActorLifecycle(actor, player)
    Trade.recoverPending(player, 32, true)
    if Trade.hasPendingActor(actor) then return false, "trade_recovery_pending" end
    return true
end

local function descriptorReferencesActor(descriptor, actorId)
    return type(descriptor) == "table" and descriptor.kind == "actor"
        and descriptor.id == actorId
end

function Trade.prepareActorDeath(actor, player)
    local actorId = U().idOf(actor)
    if type(actorId) ~= "string" or actorId == "" then
        return false, "dead trade owner identity is unavailable"
    end
    local records = {}
    for _, transfer in pairs(pendingRecoveries) do
        if descriptorReferencesActor(transfer.sourceOwner, actorId)
            or descriptorReferencesActor(transfer.destinationOwner, actorId) then
            records[#records + 1] = transfer
        end
    end
    table.sort(records, function(left, right)
        return (tonumber(left.serial) or 0) < (tonumber(right.serial) or 0)
    end)
    for _, transfer in ipairs(records) do
        local recovered, reason = recoverTransfer(transfer, player)
        if not recovered and pendingRecoveries[transfer.recoveryId] ~= nil then
            local retired = { kind = "retired", id = actorId }
            if descriptorReferencesActor(transfer.sourceOwner, actorId) then
                transfer.sourceOwner, transfer.sourceActor = retired, nil
            end
            if descriptorReferencesActor(transfer.destinationOwner, actorId) then
                transfer.destinationOwner, transfer.destinationActor = retired, nil
            end
            quarantineRecovery(transfer, "owner_retired:" .. tostring(reason))
        end
    end
    return true
end

local function journalRows(rows, sourceActor, destination, destinationActor, journal)
    for _, row in ipairs(rows or {}) do
        journal[#journal + 1] = {
            item = row.item,
            source = row.container,
            destination = destination,
            sourceActor = sourceActor,
            destinationActor = destinationActor,
            phase = "planned",
        }
    end
end

local function detachJournal(journal)
    for _, transfer in ipairs(journal) do
        local removedOk, removed = invoke(transfer.source, "Remove", transfer.item)
        transfer.phase = "detach_attempted"
        local member = containerMembership(transfer.source, transfer.item)
        local ownerOk, owner = invoke(transfer.item, "getContainer")
        if not removedOk or removed == false or member ~= false
            or not ownerOk or owner == transfer.source then
            return false, "source_remove_failed"
        end
        transfer.phase = "detached"
    end
    return true
end

local function attachJournal(journal)
    for _, transfer in ipairs(journal) do
        local accepted, reason = destinationAccepts(
            transfer.destination, transfer.destinationActor, transfer.item)
        if not accepted then return false, reason end
        local addedOk, added = invoke(transfer.destination, "AddItem", transfer.item)
        transfer.phase = "attach_attempted"
        if not addedOk or added == false
            or not verifiedOwner(transfer.item, transfer.destination, transfer.source) then
            return false, "destination_add_failed"
        end
        transfer.phase = "attached"
    end
    return true
end

local function snapshotGroup(group)
    if not SC.StableValue or type(SC.StableValue.copyStrict) ~= "function" then
        return nil, "stable group snapshot unavailable"
    end
    return SC.StableValue.copyStrict(group, {
        maxDepth = 20, maxEntries = 200000, path = "$.trade.finalize.group",
    })
end

local function restoreGroup(group, snapshot)
    if type(group) ~= "table" or type(snapshot) ~= "table" then return false end
    local ok = pcall(function()
        for key in pairs(group) do group[key] = nil end
        for key, value in pairs(snapshot) do group[key] = value end
    end)
    return ok
end

local function proximityOkay(group, player, trader, allowHostile, maximumDistance)
    if player == nil or trader == nil then return false, "trade_actor_unavailable" end
    maximumDistance = tonumber(maximumDistance)
        or (tonumber(SC.Config.get("factionTradeDistance")) or 6)
    if U().distance(player, trader) > maximumDistance then
        return false, "too_far_to_trade"
    end
    if U().canSee and U().canSee(player, trader) ~= true then return false, "line_of_sight_lost" end
    if allowHostile ~= true and (group.standing == "Hostile" or group.lifecycle == "hostile") then
        return false, "faction_hostile"
    end
    if SC.Senses and type(SC.Senses.snapshot) == "function" then
        -- Reuse the actor's real runtime. A fresh table restarted the global
        -- zombie cursor at every click and could authorize trade after seeing
        -- only the first bounded chunk.
        local ok, snapshot = pcall(SC.Senses.snapshot, trader, player,
            perceptionRuntime(trader))
        if not ok then return false, "danger_check_unavailable" end
        local safe, reason = safePerceptionComplete(snapshot)
        if not safe then return false, reason or "danger_check_unavailable" end
    end
    return true
end

local function transaction(group, player, playerRows, factionRows, options)
    options = type(options) == "table" and options or {}
    Trade.recoverPending(player)
    if Trade.hasPendingFaction(group.id) then return false, "trade_recovery_pending" end
    local possibleRecoveries = #(playerRows or {}) + #(factionRows or {})
    if pendingRecoveryCount() + possibleRecoveries > recoveryEntryLimit() then
        return false, "trade_recovery_capacity_exhausted"
    end
    local trader = actorForGroup(group)
    local ready, reason = proximityOkay(group, player, trader, options.allowHostile == true,
        options.maximumDistance)
    if not ready then return false, reason end
    local playerInventory, factionInventory = actorInventory(player), actorInventory(trader)
    if not playerInventory or not factionInventory then return false, "inventory_unavailable" end
    local valid, validationReason = validateRows(playerRows, player, playerInventory,
        options.allowProtectedPlayer == true)
    if not valid then return false, validationReason end
    valid, validationReason = validateRows(factionRows, trader, factionInventory,
        options.allowProtectedFaction == true)
    if not valid then return false, validationReason end
    local groupSnapshot
    if type(options.finalize) == "function" then
        groupSnapshot, reason = snapshotGroup(group)
        if groupSnapshot == nil then
            return false, "transaction_finalize_snapshot_failed:" .. tostring(reason)
        end
    end
    local journal = {}
    journalRows(playerRows, player, factionInventory, trader, journal)
    journalRows(factionRows, trader, playerInventory, player, journal)
    authorizationSerial = authorizationSerial + 1
    authorized = { serial = authorizationSerial, factionId = group.id }
    local finalizeStarted = false
    local function execute()
        local ok, transferReason = detachJournal(journal)
        if not ok then return false, transferReason end
        local accepted, capacityReason = destinationAcceptsAll(
            factionInventory, trader, playerRows)
        if not accepted then
            return false, capacityReason == "capacity_check_unavailable"
                and "faction_capacity_check_unavailable" or "faction_inventory_full"
        end
        accepted, capacityReason = destinationAcceptsAll(
            playerInventory, player, factionRows)
        if not accepted then
            return false, capacityReason == "capacity_check_unavailable"
                and "player_capacity_check_unavailable" or "player_inventory_full"
        end
        ok, transferReason = attachJournal(journal)
        if not ok then return false, transferReason end
        if type(options.finalize) == "function" then
            finalizeStarted = true
            local finalized, finalReason = options.finalize()
            if finalized ~= true then
                return false, finalReason or "transaction_finalize_failed"
            end
            transferReason = finalReason or transferReason
        end
        return true, transferReason or "transaction_complete"
    end

    local called, ok, transferReason = pcall(execute)
    authorized = false
    if not called then
        ok, transferReason = false, "transaction_exception:" .. tostring(ok)
    end
    if ok == true then return true, transferReason or "transaction_complete" end

    local finalizeRestored = true
    if finalizeStarted then
        finalizeRestored = restoreGroup(group, groupSnapshot)
        if type(options.compensate) == "function" then
            local compensated, result = pcall(options.compensate)
            finalizeRestored = finalizeRestored and compensated and result ~= false
        end
    end
    local restored, rollbackReason = rollback(journal)
    if not restored then
        local retained, retainReason = rememberRecovery(
            journal, group, transferReason, rollbackReason, player)
        if not retained then
            return false, "transaction_recovery_capture_failed:" .. tostring(retainReason)
        end
        return false, "transaction_rollback_failed"
    end
    if not finalizeRestored then return false, "transaction_finalize_recovery_failed" end
    return false, transferReason or "transaction_failed"
end

function Trade.isAuthorizedTransfer(factionId)
    return type(authorized) == "table" and authorized.factionId == factionId
end

function Trade.completeRequest(group, player)
    if type(group) ~= "table" or type(group.request) ~= "table" then
        return false, "request_unavailable"
    end
    local trader = actorForGroup(group)
    local ready, reason = proximityOkay(group, player, trader)
    if not ready then return false, reason end
    local offered, offeredReason = selectRequirements(player, group.request.required, false)
    if not offered then return false, offeredReason end
    local reward, rewardReason = selectRequirements(trader, group.request.reward, true)
    if not reward then return false, "reserved_reward_missing:" .. tostring(rewardReason) end
    return transaction(group, player, offered, reward)
end

function Trade.deliverRequirements(group, player, requirements)
    if type(group) ~= "table" or type(requirements) ~= "table" or #requirements == 0 then
        return false, "delivery_unavailable"
    end
    local trader = actorForGroup(group)
    local ready, reason = proximityOkay(group, player, trader)
    if not ready then return false, reason end
    local offered, offeredReason, progress = selectRequirements(player, requirements, false)
    if not offered then return false, offeredReason end
    local delivered, reason = transaction(group, player, offered, {})
    if not delivered then return false, reason end
    local receipt, counts = { requirements = progress, items = {} }, {}
    for _, row in ipairs(offered) do
        local itemType = fullType(row.item)
        counts[itemType] = (counts[itemType] or 0) + 1
    end
    for itemType, count in pairs(counts) do
        receipt.items[#receipt.items + 1] = { type = itemType, count = count }
    end
    table.sort(receipt.items, function(left, right) return left.type < right.type end)
    return true, reason, receipt
end

local function matchingQuestRows(actor, contractId, rewardChoice)
    local inventory = actorInventory(actor)
    if not inventory then return nil, "inventory_unavailable" end
    local rows, selected = {}, {}
    collect(inventory, rows, 0, {
        count = tonumber(SC.Config.get("factionQuestInventoryScanLimit")) or 4096,
    })
    for _, row in ipairs(rows) do
        local data = existingModData(row.item)
        if type(data) == "table" and data.LF_QuestId == contractId then
            if rewardChoice == nil and data.LF_QuestItem == true then
                selected[#selected + 1] = row
            elseif rewardChoice ~= nil and data.LF_QuestReward == true
                and tonumber(data.LF_QuestRewardChoice) == tonumber(rewardChoice) then
                selected[#selected + 1] = row
            end
        end
    end
    return selected
end

function Trade.questItemProgress(player, contractId)
    if player == nil or type(contractId) ~= "string" then return 0, nil end
    local rows, reason = matchingQuestRows(player, contractId, nil)
    return rows and #rows or 0, reason
end

function Trade.prepareQuestRewards(group, contract)
    if type(group) ~= "table" or type(contract) ~= "table"
        or type(contract.rewardChoices) ~= "table" then return false, "reward_plan_unavailable" end
    local trader = actorForGroup(group)
    local inventory = actorInventory(trader)
    if not inventory then return false, "trader_inventory_unavailable" end
    local existing = matchingQuestRows(trader, contract.id, 1) or {}
    local second = matchingQuestRows(trader, contract.id, 2) or {}
    if #existing > 0 and #second > 0 then
        contract.rewardMaterialization = { state = "ready", itemCount = #existing + #second }
        return true, "quest_rewards_already_ready"
    end
    if #existing > 0 or #second > 0 then return false, "partial_quest_reward_materialization" end
    local created = {}
    for choiceIndex, choice in ipairs(contract.rewardChoices) do
        for _, spec in ipairs(choice.items or {}) do
            local count = math.max(1, math.floor(tonumber(spec.count) or 1))
            for itemIndex = 1, count do
                local item, reason = U().addItem(inventory, spec.type)
                if item == nil then
                    for _, createdItem in ipairs(created) do invoke(inventory, "Remove", createdItem) end
                    return false, "quest_reward_add_failed:" .. tostring(reason)
                end
                local data = U().modData(item)
                if type(data) ~= "table" then
                    invoke(inventory, "Remove", item)
                    for _, createdItem in ipairs(created) do invoke(inventory, "Remove", createdItem) end
                    return false, "quest_reward_metadata_unavailable"
                end
                data.LF_QuestReward, data.LF_QuestId = true, contract.id
                data.LF_QuestFactionId = group.id
                data.LF_QuestRewardChoice = choiceIndex
                data.LF_QuestInstanceId = contract.id .. ":reward:" .. tostring(choiceIndex)
                    .. ":" .. tostring(itemIndex)
                created[#created + 1] = item
            end
        end
    end
    contract.rewardMaterialization = { state = "ready", itemCount = #created }
    return true, "quest_rewards_ready"
end

function Trade.releaseQuestRewards(group, contract)
    local trader = actorForGroup(group)
    if not trader or type(contract) ~= "table" then return false, "trader_unavailable" end
    for choiceIndex = 1, 2 do
        for _, row in ipairs(matchingQuestRows(trader, contract.id, choiceIndex) or {}) do
            clearQuestTags(row.item)
        end
    end
    return true, "quest_rewards_released"
end

function Trade.completeQuest(group, player, contract, choiceIndex, finalize)
    choiceIndex = math.floor(tonumber(choiceIndex) or 0)
    if type(group) ~= "table" or type(contract) ~= "table" then
        return false, "quest_unavailable"
    end
    local choice = type(contract.rewardChoices) == "table" and contract.rewardChoices[choiceIndex] or nil
    if choiceIndex < 1 or choiceIndex > 2 or type(choice) ~= "table" then
        return false, "select_quest_reward"
    end
    local trader = actorForGroup(group)
    local playerRows = {}
    if contract.kind == "retrieve_item" then
        local found, reason = matchingQuestRows(player, contract.id, nil)
        if not found or #found == 0 then return false, reason or "quest_item_missing" end
        playerRows[1] = found[1]
    end
    local factionRows, rewardReason = matchingQuestRows(trader, contract.id, choiceIndex)
    local expected = 0
    for _, spec in ipairs(choice.items or {}) do
        expected = expected + math.max(1, math.floor(tonumber(spec.count) or 1))
    end
    if not factionRows or #factionRows ~= expected then
        return false, rewardReason or "selected_quest_reward_missing"
    end
    local completed, reason = transaction(group, player, playerRows, factionRows, {
        allowProtectedPlayer = true,
        allowProtectedFaction = true,
        finalize = finalize,
    })
    if not completed then return false, reason end
    for _, row in ipairs(playerRows) do clearQuestTags(row.item) end
    for _, row in ipairs(factionRows) do clearQuestTags(row.item) end
    Trade.releaseQuestRewards(group, contract)
    return true, reason or "quest_complete"
end

function Trade.itemValue(item)
    local itemType = fullType(item)
    if itemType == "" then return 0 end
    local brokenOk, broken = invoke(item, "isBroken")
    local rottenOk, rotten = invoke(item, "isRotten")
    local burntOk, burnt = invoke(item, "isBurnt")
    if (brokenOk and broken == true) or (rottenOk and rotten == true)
        or (burntOk and burnt == true) then return 0 end

    local nominal = values[itemType]
    local weightOk, weight = invoke(item, "getActualWeight")
    if nominal == nil then
        local category = itemCategory(item)
        nominal = categoryValues[category] or categoryValues.other
        local numericWeight = weightOk and tonumber(weight) or 0
        nominal = nominal + math.floor(math.min(2, math.max(0, numericWeight)) * 2)
    end

    local factor = 1
    local conditionOk, condition = invoke(item, "getCondition")
    local maximumOk, maximum = invoke(item, "getConditionMax")
    if conditionOk and maximumOk and tonumber(condition) and tonumber(maximum)
        and tonumber(maximum) > 0 then
        factor = factor * U().clamp(tonumber(condition) / tonumber(maximum), 0, 1)
    end
    local currentOk, currentUses = invoke(item, "getCurrentUses")
    local usesOk, maximumUses = invoke(item, "getMaxUses")
    if currentOk and usesOk and tonumber(currentUses) and tonumber(maximumUses)
        and tonumber(maximumUses) > 1 then
        factor = factor * U().clamp(tonumber(currentUses) / tonumber(maximumUses), 0, 1)
    else
        local usedOk, usedDelta = invoke(item, "getUsedDelta")
        if usedOk and tonumber(usedDelta) then
            factor = factor * U().clamp(tonumber(usedDelta), 0, 1)
        end
    end
    local fluidOk, fluid = invoke(item, "getFluidContainer")
    if fluidOk and fluid ~= nil then
        local amountOk, amount = invoke(fluid, "getAmount")
        local capacityOk, fluidCapacity = invoke(fluid, "getCapacity")
        if not amountOk or not capacityOk or tonumber(amount) == nil
            or tonumber(fluidCapacity) == nil or tonumber(fluidCapacity) <= 0 then
            return 0
        end
        local ratio = U().clamp(tonumber(amount) / tonumber(fluidCapacity), 0, 1)
        factor = factor * math.max(0.1, ratio)
    end
    return math.max(0, math.floor(nominal * factor + 0.5))
end

local baseValue = Trade.itemValue

function Trade.reserveSummary(groupId)
    local group = type(groupId) == "table" and groupId
        or SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return nil, "faction_unavailable" end
    local living, firstPassOpen, finalPassOpen = 0, 0, 0
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            living = living + 1
        end
    end
    for _, job in ipairs(group.jobs or {}) do
        if job.phase == "first" and job.status ~= "completed" then
            firstPassOpen = firstPassOpen + 1
        end
        if job.phase == "final" and job.status ~= "completed"
            and job.status ~= "cancelled" then finalPassOpen = finalPassOpen + 1 end
    end
    local rows = {
        { category = "food", count = math.max(2, living * 4), reason = "household meals" },
        { category = "water", count = math.max(2, living * 2), reason = "household water" },
        { category = "medicine", count = math.max(2, living), reason = "emergency treatment" },
    }
    local planks = math.min(48, math.max(firstPassOpen * 2, finalPassOpen * 4))
    local nails = math.min(96, math.max(firstPassOpen * 4, finalPassOpen * 8))
    if planks > 0 then rows[#rows + 1] = {
        category = "planks", count = planks, reason = "open barricade jobs",
    } end
    if nails > 0 then rows[#rows + 1] = {
        category = "nails", count = nails, reason = "open barricade jobs",
    } end
    local policy = SC.FactionContracts
        and type(SC.FactionContracts.tradePolicy) == "function"
        and SC.FactionContracts.tradePolicy(group) or nil
    for category, refused in pairs(policy and policy.refused or {}) do
        if refused == true then rows[#rows + 1] = {
            category = category, count = -1,
            reason = policy.refusedReasons and policy.refusedReasons[category]
                or "household policy",
        } end
    end
    table.sort(rows, function(left, right)
        if left.category == right.category then return left.count < right.count end
        return left.category < right.category
    end)
    return rows
end

function Trade.catalog(groupId)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return nil, "faction_unavailable" end
    if group.barterUnlocked ~= true then return nil, "barter_locked" end
    local trader = actorForGroup(group)
    if not trader then return nil, "trader_unavailable" end
    local inventory = actorInventory(trader)
    local rows = {}
    local policy = SC.FactionContracts
        and type(SC.FactionContracts.tradePolicy) == "function"
        and SC.FactionContracts.tradePolicy(group) or nil
    collect(inventory, rows, 0, { count = 512 })
    local result = {}
    local living = 0
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.away == nil and member.departed ~= true then
            living = living + 1
        end
    end
    local firstPassOpen, finalPassOpen = 0, 0
    for _, job in ipairs(group.jobs or {}) do
        if job.phase == "first" and job.status ~= "completed" then firstPassOpen = firstPassOpen + 1 end
        if job.phase == "final" and job.status ~= "completed"
            and job.status ~= "cancelled" then finalPassOpen = finalPassOpen + 1 end
    end
    local reserveFood, reserveWater, reserveMedical = math.max(2, living * 4),
        math.max(2, living * 2), math.max(2, living)
    local reservePlanks = math.min(48, math.max(firstPassOpen * 2, finalPassOpen * 4))
    local reserveNails = math.min(96, math.max(firstPassOpen * 4, finalPassOpen * 8))
    local reservedRewards = {}
    if type(group.request) == "table" and group.request.status == "available"
        and group.request.rewardReserved == true then
        local selected = selectRequirements(trader, group.request.reward, true)
        for _, row in ipairs(selected or {}) do reservedRewards[row.item] = true end
    end
    for _, row in ipairs(rows) do
        local category = itemCategory(row.item)
        local reserve = reservedRewards[row.item] == true
            or policy and policy.refused and policy.refused[category] == true
        if not reserve and category == "food" and reserveFood > 0 then reserveFood, reserve = reserveFood - 1, true
        elseif not reserve and category == "water" and reserveWater > 0 then reserveWater, reserve = reserveWater - 1, true
        elseif not reserve and (fullType(row.item) == "Base.Bandage" or fullType(row.item) == "Base.FirstAidKit")
            and reserveMedical > 0 then reserveMedical, reserve = reserveMedical - 1, true
        elseif not reserve and fullType(row.item) == "Base.Plank" and reservePlanks > 0 then
            reservePlanks, reserve = reservePlanks - 1, true
        elseif not reserve and fullType(row.item) == "Base.Nails" and reserveNails > 0 then
            reserveNails, reserve = reserveNails - 1, true
        end
        if not reserve and not protected(trader, row.item) and not hasContents(row.item) then
            result[#result + 1] = {
                item = row.item, container = row.container, type = fullType(row.item),
                category = category, value = baseValue(row.item),
            }
        end
    end
    return result
end

function Trade.playerCatalog(player)
    local inventory = actorInventory(player)
    if not inventory then return nil, "inventory_unavailable" end
    local rows, result = {}, {}
    collect(inventory, rows, 0, { count = 512 })
    for _, row in ipairs(rows) do
        if not protected(player, row.item) and not hasContents(row.item) then
            result[#result + 1] = {
                item = row.item, container = row.container, type = fullType(row.item),
                category = itemCategory(row.item), value = baseValue(row.item),
            }
        end
    end
    return result
end

function Trade.canOpen(groupId, player)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return false, "faction_unavailable" end
    if group.barterUnlocked ~= true then return false, "barter_locked" end
    return proximityOkay(group, player, actorForGroup(group))
end

function Trade.canOfferRestitution(groupId, player)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return false, "faction_unavailable" end
    local ready, reason = SC.Factions.canReconcile(groupId)
    if ready ~= true then return false, reason end
    return proximityOkay(group, player, actorForGroup(group), true,
        tonumber(SC.Config.get("factionWarningOuterRadius")) or 18)
end

function Trade.selectionValue(rows)
    local result = 0
    for _, row in ipairs(rows or {}) do result = result + baseValue(row.item or row) end
    return result
end

function Trade.payRestitution(groupId, player, offeredRows)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return false, "faction_unavailable" end
    local ready, reason = SC.Factions.canReconcile(groupId)
    if ready ~= true then return false, reason end
    if type(offeredRows) ~= "table" or #offeredRows == 0 then
        return false, "select_restitution_items"
    end
    local required = SC.Factions.restitutionRequired(groupId) or math.huge
    local offeredValue = Trade.selectionValue(offeredRows)
    if offeredValue < required then return false, "restitution_too_small" end
    return transaction(group, player, offeredRows, {}, {
        allowHostile = true,
        maximumDistance = tonumber(SC.Config.get("factionWarningOuterRadius")) or 18,
        finalize = function() return SC.Factions.reconcile(groupId, offeredValue) end,
    })
end

function Trade.quote(groupId, offeredRows, requestedRows)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group then return nil, "faction_unavailable" end
    local offer, request = 0, 0
    for _, row in ipairs(offeredRows or {}) do offer = offer + baseValue(row.item or row) end
    for _, row in ipairs(requestedRows or {}) do request = request + baseValue(row.item or row) end
    local policy = SC.FactionContracts
        and type(SC.FactionContracts.tradePolicy) == "function"
        and SC.FactionContracts.tradePolicy(group) or nil
    local markup = policy and tonumber(policy.markup)
        or (group.standing == "Trusted" and 1.0 or 1.25)
    local required = math.ceil(request * markup)
    return {
        offerValue = offer, requestValue = request, requiredOffer = required,
        markup = markup, accepted = offer >= required,
        counterOffer = math.max(0, required - offer),
        refusedText = policy and policy.refusalText or "none",
    }
end

function Trade.barter(groupId, player, offeredRows, requestedRows)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group or group.barterUnlocked ~= true then return false, "barter_locked" end
    if type(offeredRows) ~= "table" or #offeredRows == 0
        or type(requestedRows) ~= "table" or #requestedRows == 0 then
        return false, "select_both_sides"
    end
    local quote = Trade.quote(groupId, offeredRows, requestedRows)
    if not quote or quote.accepted ~= true then return false, "offer_too_low" end
    local trader = actorForGroup(group)
    if not trader then return false, "trader_unavailable" end
    local policy = SC.FactionContracts
        and type(SC.FactionContracts.tradePolicy) == "function"
        and SC.FactionContracts.tradePolicy(group) or nil
    for _, row in ipairs(requestedRows or {}) do
        if policy and policy.refused and policy.refused[itemCategory(row.item)] == true then
            return false, "household_reserve_refused"
        end
        if protected(trader, row.item) then return false, "protected_faction_item" end
    end
    local traded, reason = transaction(group, player, offeredRows, requestedRows)
    if traded and SC.FactionContracts and type(SC.FactionContracts.noteAction) == "function" then
        pcall(SC.FactionContracts.noteAction, group, "fair_trade", "A fair barter was completed.")
    end
    if traded and SC.FactionWorld and type(SC.FactionWorld.notePlayerAction) == "function" then
        pcall(SC.FactionWorld.notePlayerAction, group.id, "fair_trade", 1)
    end
    return traded, reason
end

local function copyOwnerDescriptor(source)
    if type(source) ~= "table" then return nil end
    if source.kind == "player" then return { kind = "player" } end
    if (source.kind == "actor" or source.kind == "retired")
        and type(source.id) == "string"
        and source.id ~= "" and #source.id <= 96 then
        return { kind = source.kind, id = source.id }
    end
    return nil
end

function Trade.export()
    -- Opportunistically close live cases first; anything still unresolved is a
    -- durable ownership record and is saved independently of both inventories.
    Trade.recoverPending(primaryPlayer(), 32)
    local entries = {}
    for _, transfer in pairs(pendingRecoveries) do
        if type(transfer.itemState) ~= "table" then
            return nil, "pending trade item has no durable state"
        end
        entries[#entries + 1] = {
            recoveryId = transfer.recoveryId,
            serial = transfer.serial,
            factionId = transfer.factionId,
            reason = transfer.reason,
            rollbackReason = transfer.rollbackReason,
            recordedAt = transfer.recordedAt,
            attempts = transfer.attempts,
            phase = transfer.phase == "recovery_quarantined"
                and "recovery_quarantined" or "recovery_pending",
            quarantineReason = transfer.quarantineReason,
            quarantinedAt = transfer.quarantinedAt,
            reconstructionPartial = transfer.reconstructionPartial == true,
            partialNativeId = transfer.partialNativeId ~= nil
                and tostring(transfer.partialNativeId) or nil,
            detachedProof = transfer.detachedProof == true,
            sourceOwner = copyOwnerDescriptor(transfer.sourceOwner),
            destinationOwner = copyOwnerDescriptor(transfer.destinationOwner),
            itemState = transfer.itemState,
        }
    end
    table.sort(entries, function(left, right)
        return (tonumber(left.serial) or 0) < (tonumber(right.serial) or 0)
    end)
    return {
        version = 1, serial = recoverySerial,
        cursorSerial = recoveryCursorSerial, entries = entries,
    }
end

function Trade.restore(source)
    if type(source) ~= "table" or source.version ~= 1
        or type(source.entries) ~= "table" or #source.entries > recoveryEntryLimit() then
        return false, "invalid trade recovery envelope"
    end
    local restoredAt = U().nowMs()
    local candidate, seen, maximumSerial = {}, {}, math.max(0,
        math.floor(tonumber(source.serial) or 0))
    for _, entry in ipairs(source.entries) do
        local recoveryId = type(entry) == "table" and entry.recoveryId or nil
        local serial = type(entry) == "table" and math.floor(tonumber(entry.serial) or -1) or -1
        local sourceOwner = type(entry) == "table" and copyOwnerDescriptor(entry.sourceOwner) or nil
        local destinationOwner = type(entry) == "table"
            and copyOwnerDescriptor(entry.destinationOwner) or nil
        local phase = type(entry) == "table" and entry.phase or nil
        local partialNativeId = type(entry) == "table" and entry.partialNativeId or nil
        if type(recoveryId) ~= "string" or recoveryId == "" or #recoveryId > 128
            or seen[recoveryId] or serial < 1 or sourceOwner == nil
            or destinationOwner == nil or (phase ~= "recovery_pending"
                and phase ~= "recovery_quarantined")
            or (partialNativeId ~= nil and (#tostring(partialNativeId) > 64
                or tostring(partialNativeId) == "")) then
            return false, "invalid trade recovery entry"
        end
        local validate = SC.Persistence
            and type(SC.Persistence.validateDetachedItem) == "function"
            and SC.Persistence.validateDetachedItem or nil
        local itemState, stateReason
        if validate then
            itemState, stateReason = validate(entry.itemState)
        else
            stateReason = "detached item validation is unavailable"
        end
        if itemState == nil then
            return false, "invalid detached trade item: " .. tostring(stateReason)
        end
        local root = itemState.roots[1]
        if type(root.modData) ~= "table" or root.modData[recoveryMarker] ~= recoveryId then
            return false, "detached trade item identity does not match its recovery"
        end
        seen[recoveryId] = true
        candidate[recoveryId] = {
            recoveryId = recoveryId, serial = serial,
            factionId = type(entry.factionId) == "string" and entry.factionId or nil,
            reason = tostring(entry.reason or "transaction_failed"),
            rollbackReason = tostring(entry.rollbackReason or "ownership_unverified"),
            recordedAt = phase == "recovery_pending" and restoredAt
                or (tonumber(entry.recordedAt) or restoredAt),
            attempts = math.max(0, math.floor(tonumber(entry.attempts) or 0)),
            nextAttemptAt = 0, phase = phase,
            quarantineReason = phase == "recovery_quarantined"
                and tostring(entry.quarantineReason or "restored_quarantine") or nil,
            quarantinedAt = phase == "recovery_quarantined"
                and restoredAt or nil,
            reconstructionPartial = entry.reconstructionPartial == true,
            partialNativeId = partialNativeId ~= nil and tostring(partialNativeId) or nil,
            detachedProof = entry.detachedProof == true,
            sourceOwner = sourceOwner,
            destinationOwner = destinationOwner, itemState = itemState,
        }
        maximumSerial = math.max(maximumSerial, serial)
    end
    pendingRecoveries, recoverySerial = candidate, maximumSerial
    recoveryCursorSerial = math.max(0, math.min(maximumSerial,
        math.floor(tonumber(source.cursorSerial) or 0)))
    pruneQuarantined(restoredAt)
    return true
end

function Trade.reset()
    authorized = false
    authorizationSerial = 0
    -- Runtime teardown has already persisted the durable envelope and disposed
    -- native actors. Never retry against those obsolete containers or carry an
    -- old world's recovery ledger into the next world.
    pendingRecoveries = {}
    recoverySerial = 0
    recoveryCursorSerial = 0
    return true
end

return Trade
