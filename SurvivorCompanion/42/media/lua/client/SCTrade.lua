-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.Trade = SC.Trade or {}

local Trade = SC.Trade
local authorized = false
local authorizationSerial = 0

local values = {
    ["Base.Plank"] = 4, ["Base.Nails"] = 1, ["Base.NailsBox"] = 20,
    ["Base.Hammer"] = 18, ["Base.HandAxe"] = 28, ["Base.Axe"] = 45,
    ["Base.Bandage"] = 6, ["Base.Disinfectant"] = 18, ["Base.FirstAidKit"] = 32,
    ["Base.WaterBottle"] = 10, ["Base.CannedSardines"] = 8,
    ["Base.CannedCornedBeef"] = 10, ["Base.Battery"] = 5, ["Base.Lighter"] = 7,
}

local function U()
    return SC.GameplayUtil
end

local function invoke(object, methodName, ...)
    local value, called, b, c = U().call(object, methodName, ...)
    return called, value, b, c
end

local function listSize(list)
    if type(list) == "table" then return #list end
    local ok, size = invoke(list, "size")
    return ok and tonumber(size) or 0
end

local function listGet(list, index)
    if type(list) == "table" then return list[index + 1] end
    local ok, value = invoke(list, "get", index)
    return ok and value or nil
end

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
    if container == nil or depth > 4 or budget.count <= 0 then return end
    local ok, items = invoke(container, "getItems")
    if not ok or items == nil then return end
    for index = 0, listSize(items) - 1 do
        if budget.count <= 0 then break end
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

local function protected(actor, item)
    if isEquipped(actor, item) then return true end
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
    return not ok or allowed == true
end

local function destinationAcceptsAll(container, owner, rows)
    -- A one-way delivery may move items out of an already-overloaded player.
    -- Capacity is relevant only when this destination actually receives rows.
    if type(rows) ~= "table" or #rows == 0 then return true end
    local weightOk, currentWeight = invoke(container, "getCapacityWeight")
    local capacityOk, capacity = invoke(container, "getEffectiveCapacity", owner)
    if not capacityOk then capacityOk, capacity = invoke(container, "getCapacity") end
    if weightOk and capacityOk and tonumber(currentWeight) and tonumber(capacity) then
        local incoming = 0
        for _, row in ipairs(rows or {}) do
            local itemWeightOk, itemWeight = invoke(row.item, "getActualWeight")
            incoming = incoming + (itemWeightOk and tonumber(itemWeight) or 0)
        end
        if tonumber(currentWeight) + incoming > tonumber(capacity) + 0.001 then return false end
    end
    for _, row in ipairs(rows or {}) do
        if not destinationAccepts(container, owner, row.item) then return false end
    end
    return true
end

local function rollback(transfers)
    local complete = true
    for index = #transfers, 1, -1 do
        local transfer = transfers[index]
        local currentOk, current = invoke(transfer.item, "getContainer")
        if not currentOk then
            complete = false
        elseif current ~= transfer.source then
            if current ~= nil then invoke(current, "Remove", transfer.item) end
            local addedOk, added = invoke(transfer.source, "AddItem", transfer.item)
            local verifyOk, after = invoke(transfer.item, "getContainer")
            if not addedOk or added == false or not verifyOk or after ~= transfer.source then
                complete = false
            end
        end
    end
    return complete
end

local function moveRows(rows, destination, destinationOwner, committed)
    for _, row in ipairs(rows or {}) do
        if not destinationAccepts(destination, destinationOwner, row.item) then
            return false, "destination_full"
        end
    end
    for _, row in ipairs(rows or {}) do
        local removedOk, removed = invoke(row.container, "Remove", row.item)
        if not removedOk or removed == false then return false, "source_remove_failed" end
        committed[#committed + 1] = {
            item = row.item, source = row.container, destination = destination,
        }
        local detachedOk, detachedFrom = invoke(row.item, "getContainer")
        if not detachedOk or detachedFrom == row.container then
            return false, "source_remove_unverified"
        end
        local addedOk, added = invoke(destination, "AddItem", row.item)
        local currentOk, current = invoke(row.item, "getContainer")
        if not addedOk or added == false or not currentOk or current ~= destination then
            return false, "destination_add_failed"
        end
    end
    return true
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
        local ok, snapshot = pcall(SC.Senses.snapshot, trader, player, {})
        if ok and type(snapshot) == "table" and (tonumber(snapshot.threatCount) or 0) > 0 then
            return false, "danger_nearby"
        end
    end
    return true
end

local function transaction(group, player, playerRows, factionRows, options)
    options = type(options) == "table" and options or {}
    local trader = actorForGroup(group)
    local ready, reason = proximityOkay(group, player, trader, options.allowHostile == true,
        options.maximumDistance)
    if not ready then return false, reason end
    local playerInventory, factionInventory = actorInventory(player), actorInventory(trader)
    if not playerInventory or not factionInventory then return false, "inventory_unavailable" end
    local valid, validationReason = validateRows(playerRows, player, playerInventory, false)
    if not valid then return false, validationReason end
    valid, validationReason = validateRows(factionRows, trader, factionInventory, false)
    if not valid then return false, validationReason end
    if not destinationAcceptsAll(factionInventory, trader, playerRows) then
        return false, "faction_inventory_full"
    end
    if not destinationAcceptsAll(playerInventory, player, factionRows) then
        return false, "player_inventory_full"
    end
    authorizationSerial = authorizationSerial + 1
    authorized = { serial = authorizationSerial, factionId = group.id }
    local committed = {}
    local ok, transferReason = moveRows(playerRows, factionInventory, trader, committed)
    if ok then ok, transferReason = moveRows(factionRows, playerInventory, player, committed) end
    if not ok then
        local restored = rollback(committed)
        authorized = false
        return false, restored and transferReason or "transaction_rollback_failed"
    end
    if type(options.finalize) == "function" then
        local finalized, finalReason = options.finalize()
        if finalized ~= true then
            local restored = rollback(committed)
            authorized = false
            return false, restored and (finalReason or "transaction_finalize_failed")
                or "transaction_rollback_failed"
        end
        transferReason = finalReason or transferReason
    end
    authorized = false
    return true, transferReason or "transaction_complete"
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

local function baseValue(item)
    local itemType = fullType(item)
    if values[itemType] then return values[itemType] end
    local weightOk, weight = invoke(item, "getActualWeight")
    local conditionOk, condition = invoke(item, "getCondition")
    local maximumOk, maximum = invoke(item, "getConditionMax")
    local ratio = conditionOk and maximumOk and tonumber(maximum) and tonumber(maximum) > 0
        and math.max(0.1, tonumber(condition) / tonumber(maximum)) or 1
    return math.max(1, math.floor(((weightOk and tonumber(weight)) or 1) * 6 * ratio + 0.5))
end

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

function Trade.reset()
    authorized = false
    authorizationSerial = 0
end

return Trade
