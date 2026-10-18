-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.LogYard = SC.LogYard or {}
local Yard = SC.LogYard

local function U() return SC.GameplayUtil end
local SPLIT_MARK = "LF_LogYardSplit"
local LOG_WEIGHT = 9 -- Base.Log in the pinned Build 42.21 item script.
local splitSerial = 0
local ropeCursors = setmetatable({}, { __mode = "k" })

local function splitOf(item)
    local data = item and U().modData(item) or nil
    return type(data) == "table" and type(data[SPLIT_MARK]) == "table"
        and data[SPLIT_MARK] or nil
end

local function markSplit(item, receipt, role, index)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" then return false end
    data[SPLIT_MARK] = {
        v = 1, id = receipt.id, role = role, index = index,
        ownerId = receipt.ownerId, zoneId = receipt.zoneId,
        x = receipt.x, y = receipt.y, z = receipt.z,
        count = receipt.count, ropeCount = receipt.ropeCount,
    }
    return splitOf(item) and splitOf(item).id == receipt.id
end

local function clearSplit(item, id)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" or type(data[SPLIT_MARK]) ~= "table"
        or data[SPLIT_MARK].id ~= id then return false end
    data[SPLIT_MARK] = nil
    return data[SPLIT_MARK] == nil
end

local function worldItems(square)
    local list, readable = U().call(square, "getWorldObjects")
    if not readable and type(square) == "table" then list, readable = square.worldItems, true end
    if not readable or list == nil then return nil end
    local count = U().listSize(list)
    if type(count) ~= "number" or count > 64 then return nil end
    local rows = {}
    for index = 0, count - 1 do
        local world = U().listGet(list, index)
        local item = world and select(1, U().call(world, "getItem")) or nil
        if not item and type(world) == "table" then item = world.item end
        if item then rows[#rows + 1] = { world = world, item = item } end
    end
    return rows
end

function Yard.contents(square)
    local rows = worldItems(square)
    if not rows then return nil end
    local units, logs, bundles, splitPending = 0, {}, {}, false
    for _, row in ipairs(rows) do
        local kind = U().itemType(row.item)
        local split = splitOf(row.item)
        if split then splitPending = true end
        if kind == "Base.Log" and not split then
            units = units + 1
            logs[#logs + 1] = row
        elseif kind == "Base.LogStacks4" or kind == "Base.LogStacks3"
            or kind == "Base.LogStacks2" then
            row.count = tonumber(string.match(kind, "(%d+)$"))
            units = units + row.count
            bundles[#bundles + 1] = row
        end
    end
    return { units = units, logs = logs, bundles = bundles,
        splitPending = splitPending }
end

local function unclaimed(item)
    local data, readable = U().call(item, "getModData")
    if not readable or type(data) ~= "table" then return false end
    if splitOf(item) then return false end
    if SC.WorkTransport and SC.WorkTransport.marker then
        local marker, state = SC.WorkTransport.marker(item)
        return marker == nil and state == nil
    end
    return true
end

local function looseAvailable(contents)
    local result = {}
    for _, row in ipairs(contents and contents.logs or {}) do
        if unclaimed(row.item) then result[#result + 1] = row end
    end
    return result
end

local function bundleAvailable(contents)
    for _, row in ipairs(contents and contents.bundles or {}) do
        if unclaimed(row.item) then return row end
    end
    return nil
end

-- Sawing pauses above 85% effective capacity. Check the projected loose log
-- before touching a world wrapper, including when the source is a tied stack.
local function canCarryLog(actor, source, loose)
    local inventory = U().inventory(actor)
    if not inventory then return false, "worker_inventory_unavailable" end
    local weight, capacity = U().inventoryLoad(actor)
    if type(capacity) ~= "number" or capacity <= 0 then
        return false, "capacity_unavailable"
    end
    local logWeight = loose and U().itemWeight(source) or LOG_WEIGHT
    if type(logWeight) ~= "number" or logWeight <= 0 then
        return false, "capacity_unavailable"
    end
    local projected = (weight + logWeight + (loose and 0 or 1)) / capacity
    if projected > 0.85 then return false, "worker_overloaded" end
    if loose then
        local allowed, called = U().call(inventory, "hasRoomFor", actor, source)
        if called and allowed ~= true then return false, "worker_overloaded" end
    end
    return true
end

local function zones(preferredId)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active() or nil
    local rows = {}
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "log_yard" and (preferredId == nil or zone.id == preferredId) then
            rows[#rows + 1] = zone
        end
    end
    return rows
end

function Yard.hasZone() return #zones(nil) > 0 end

function Yard.tile(x, y, z, zoneId)
    local square = U().gridSquare(x, y, z)
    if not square or SC.BaseLife.isOutdoorSquare(square) ~= true then return nil end
    for _, zone in ipairs(zones(zoneId)) do
        if zone.z == z and x >= zone.x1 and x <= zone.x2
            and y >= zone.y1 and y <= zone.y2 then return square end
    end
    return nil
end

function Yard.select(actor, preferredId)
    local best, bestDistance
    local inspected = 0
    for _, zone in ipairs(zones(preferredId)) do
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                inspected = inspected + 1
                if inspected > 1024 then return best, best and nil or "log_yard_scan_limit" end
                local square = Yard.tile(x, y, zone.z, zone.id)
                local contents = square and Yard.contents(square) or nil
                if contents and contents.units < 4 and not contents.splitPending then
                    local distance = actor and U().distance(actor, square) or 0
                    if bestDistance == nil or distance < bestDistance then
                        best = { kind = "log_yard", zoneId = zone.id,
                            x = x, y = y, z = zone.z, square = square }
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best, best and nil or "log_yard_full"
end

function Yard.restoreDestination(receipt)
    if not receipt or type(receipt.destinationPoint) ~= "table" then return nil end
    local point = receipt.destinationPoint
    local square = Yard.tile(point.x, point.y, point.z, receipt.destinationZoneId)
    if not square then return nil end
    return { kind = "log_yard", zoneId = receipt.destinationZoneId,
        x = point.x, y = point.y, z = point.z, square = square }
end

function Yard.findMarked(receipt)
    local destination = Yard.restoreDestination(receipt)
    local rows = destination and worldItems(destination.square) or nil
    if not rows then return "unavailable" end
    for _, row in ipairs(rows) do
        local marker = SC.WorkTransport and SC.WorkTransport.marker
            and SC.WorkTransport.marker(row.item)
        if marker == receipt.id then return "found", row.item, row.world end
    end
    return "absent"
end

function Yard.deposit(actor, item, destination)
    local square = destination and Yard.tile(destination.x, destination.y,
        destination.z, destination.zoneId) or nil
    local contents = square and Yard.contents(square) or nil
    if not contents then return false, "log_yard_unloaded" end
    if contents.splitPending then return false, "log_yard_split_pending" end
    if contents.units >= 4 then return false, "destination_full" end
    local dropped, world = U().dropItem(U().inventory(actor), square, item)
    if dropped ~= true then return false, world end
    if U().worldItemPresent(square, world) ~= true then
        return false, "log_yard_drop_unverified"
    end
    return true, world
end

local function removeExact(inventory, item)
    if not U().inventoryContains(inventory, item) then return false end
    U().call(inventory, "Remove", item)
    return not U().inventoryContains(inventory, item)
end

local function splitRows(inventory, square, id)
    local result = { logs = {}, ropes = {}, source = nil, duplicate = false }
    local function append(item, world)
        local marker = splitOf(item)
        if not marker or marker.id ~= id then return end
        local row = { item = item, world = world, marker = marker }
        if marker.role == "source" then
            if result.source then result.duplicate = true end
            result.source = row
        elseif marker.role == "log" then
            if result.logs[marker.index] then
                result.duplicate = true
            end
            result.logs[marker.index] = row
        elseif marker.role == "rope" then
            if result.ropes[marker.index] then
                result.duplicate = true
            end
            result.ropes[marker.index] = row
        else result.duplicate = true end
    end
    for _, item in ipairs(U().inventoryItems(inventory, 4096)) do append(item, nil) end
    for _, row in ipairs(worldItems(square) or {}) do append(row.item, row.world) end
    return result
end

local function pendingSplit(actor, square, zoneId)
    local ownerId = tostring(U().idOf(actor) or "")
    local function eligible(item)
        local marker = splitOf(item)
        return marker and marker.ownerId == ownerId and marker.zoneId == zoneId
            and marker.x == select(1, U().position(square))
            and marker.y == select(2, U().position(square))
            and marker.z == select(3, U().position(square))
    end
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
        if eligible(item) then return splitOf(item) end
    end
    for _, row in ipairs(worldItems(square) or {}) do
        if eligible(row.item) then return splitOf(row.item) end
    end
    return nil
end

local function rollbackSplit(inventory, square, receipt)
    local rows = splitRows(inventory, square, receipt.id)
    if rows.duplicate or not rows.source then return false end
    for _, group in ipairs({ rows.logs, rows.ropes }) do
        for index = 1, receipt.count do
            local row = group[index]
            if row then
                if row.world and U().worldItemPresent(square, row.world) == true then
                    local taken = U().takeWorldItemVerified(row.world, inventory, row.item)
                    if taken ~= true and not U().inventoryContains(inventory, row.item) then
                        return false
                    end
                end
                if not removeExact(inventory, row.item) then return false end
            end
        end
    end
    local source = rows.source
    if U().inventoryContains(inventory, source.item) then
        local dropped, world = U().dropItem(inventory, square, source.item)
        if dropped ~= true or U().worldItemPresent(square, world) ~= true then
            return false
        end
    elseif not source.world or U().worldItemPresent(square, source.world) ~= true then
        return false
    end
    return clearSplit(source.item, receipt.id)
end

local function completeSplit(inventory, square, receipt)
    local rows = splitRows(inventory, square, receipt.id)
    if rows.duplicate then return false, "log_yard_split_recovery_pending" end
    local source = rows.source
    if source and (U().inventoryContains(inventory, source.item)
        or source.world and U().worldItemPresent(square, source.world) == true) then
        return false, "log_yard_split_source_present"
    end
    for index = 1, receipt.count do
        local row = rows.logs[index]
        if not row then return false, "log_yard_split_recovery_pending" end
        local owned = index == 1 and U().inventoryContains(inventory, row.item)
            or index > 1 and row.world
                and U().worldItemPresent(square, row.world) == true
        if not owned then return false, "log_yard_split_recovery_pending" end
    end
    for index = 1, receipt.ropeCount do
        local row = rows.ropes[index]
        if not row or not U().inventoryContains(inventory, row.item) then
            return false, "log_yard_split_recovery_pending"
        end
    end
    for index = 1, receipt.count do clearSplit(rows.logs[index].item, receipt.id) end
    for index = 1, receipt.ropeCount do clearSplit(rows.ropes[index].item, receipt.id) end
    return true, "log_yard_log_taken", rows.logs[1].item
end

local function abortSplit(inventory, square, receipt, reason)
    local rows = splitRows(inventory, square, receipt.id)
    if rows.source == nil then
        local completed, completedReason, item = completeSplit(inventory, square, receipt)
        if completed then return true, completedReason, item end
        return false, completedReason
    end
    if rollbackSplit(inventory, square, receipt) then return false, reason end
    return false, "log_yard_split_recovery_pending"
end

local function splitStack(actor, inventory, square, tied, zoneId)
    splitSerial = splitSerial + 1
    local sourceData = U().modData(tied.item)
    local ropeTypes = type(sourceData) == "table" and sourceData.ropeItems or nil
    local ropes = {}
    for index = 0, 1 do
        local ropeType = type(ropeTypes) == "table" and ropeTypes[index] or nil
        if type(ropeType) == "string" and ropeType ~= "" then
            ropes[#ropes + 1] = ropeType
        end
    end
    local receipt = {
        id = "yard:" .. tostring(U().nowMs()) .. ":" .. splitSerial,
        ownerId = tostring(U().idOf(actor) or ""), zoneId = zoneId,
        x = select(1, U().position(square)),
        y = select(2, U().position(square)),
        z = select(3, U().position(square)),
        count = tied.count, ropeCount = #ropes,
    }
    if not markSplit(tied.item, receipt, "source", 0) then
        return false, "log_yard_split_marker_failed"
    end
    -- Stage the three remainders while the original world stack remains the
    -- authoritative item. A failed stage can remove its exact provisional
    -- outputs and leave that same stack in place for a later retry.
    for index = 2, receipt.count do
        local log = U().addItem(inventory, "Base.Log")
        if not log then return abortSplit(inventory, square, receipt,
            "log_yard_unbundle_failed") end
        if not markSplit(log, receipt, "log", index) then
            removeExact(inventory, log)
            return abortSplit(inventory, square, receipt,
                "log_yard_split_marker_failed")
        end
        local dropped, world = U().dropItem(inventory, square, log)
        if dropped ~= true or U().worldItemPresent(square, world) ~= true then
            return abortSplit(inventory, square, receipt,
                "log_yard_unbundle_drop_failed")
        end
    end
    local selected = U().addItem(inventory, "Base.Log")
    if not selected then return abortSplit(inventory, square, receipt,
        "log_yard_unbundle_failed") end
    if not markSplit(selected, receipt, "log", 1) then
        removeExact(inventory, selected)
        return abortSplit(inventory, square, receipt,
            "log_yard_split_marker_failed")
    end
    for index, ropeType in ipairs(ropes) do
        local rope = U().addItem(inventory, ropeType)
        if not rope then return abortSplit(inventory, square, receipt,
            "log_yard_unbundle_failed") end
        if not markSplit(rope, receipt, "rope", index) then
            removeExact(inventory, rope)
            return abortSplit(inventory, square, receipt,
                "log_yard_split_marker_failed")
        end
    end
    local taken = U().takeWorldItemVerified(tied.world, inventory, tied.item)
    if taken ~= true and not U().inventoryContains(inventory, tied.item) then
        return abortSplit(inventory, square, receipt,
            "log_yard_unbundle_failed")
    end
    if U().inventoryContains(inventory, tied.item)
        and not removeExact(inventory, tied.item) then
        return abortSplit(inventory, square, receipt,
            "log_yard_unbundle_failed")
    end
    local completed, reason, item = completeSplit(inventory, square, receipt)
    if completed then return true, reason, item end
    return false, reason
end

local function ropeSources(actor)
    local result, selected = {}, {}
    local function slice(container)
        local list = select(1, U().call(container, "getItems"))
        if list == nil and type(container) == "table" then list = container.items end
        local size = U().listSize(list)
        if type(size) ~= "number" or size <= 0 then return {} end
        local count = math.min(size, 96)
        local start = (ropeCursors[container] or 0) % size
        local items = {}
        for offset = 0, count - 1 do
            local item = U().listGet(list, (start + offset) % size)
            if item then items[#items + 1] = item end
        end
        ropeCursors[container] = (start + count) % size
        return items
    end
    local function eligible(item)
        return U().itemType(item) == "Base.Rope" and not selected[item]
            and not (SC.PersonalItems and SC.PersonalItems.isProtected
                and SC.PersonalItems.isProtected(item, actor, "base_build"))
    end
    local carried = U().inventory(actor)
    for _, item in ipairs(slice(carried)) do
        if eligible(item) then
            result[#result + 1] = { item = item, container = carried }
            selected[item] = true
            if #result == 2 then return result end
        end
    end
    for _, category in ipairs({ "crafting", "general", "tools", "construction" }) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
            local container = SC.BaseLife.resolveContainer(storage)
            local reserve = container and SC.BaseLife.storageReserve(storage, "Base.Rope") or 0
            local available = not container and 0 or reserve == 0 and 2
                or SC.BaseLife.availableCountExact(storage, "Base.Rope")
            if container and available > 0 then
                for _, item in ipairs(slice(container)) do
                    if eligible(item) and available > 0 then
                        result[#result + 1] = { item = item, container = container }
                        selected[item], available = true, available - 1
                        if #result == 2 then return result end
                    end
                end
            end
        end
    end
    return result
end

local function restoreIngredients(inventory, square, logs, ropes)
    for _, row in ipairs(logs) do
        -- A failed ground pickup may still have the world wrapper as its
        -- recovery owner. Never create a second representation of that item.
        if U().worldItemPresent(square, row.world) ~= true then
            if not U().inventoryContains(inventory, row.item) then
                U().addItem(inventory, row.item)
            end
            if U().inventoryContains(inventory, row.item) then
                U().dropItem(inventory, square, row.item)
            end
        end
    end
    for _, row in ipairs(ropes) do
        if row.container ~= inventory and not U().inventoryContains(inventory, row.item) then
            U().addItem(inventory, row.item)
        end
        if row.container ~= inventory and U().inventoryContains(inventory, row.item) then
            U().transferItemVerified(inventory, row.container, row.item)
        end
    end
end

-- The Build 42 recipe MakeFourLogStack consumes exactly four Base.Log and
-- two Base.Rope for one Base.LogStacks4. Do the same verified exchange in one
-- update pulse; no save can interleave the component moves.
function Yard.bundleAt(actor, square)
    local contents = Yard.contents(square)
    if not contents or contents.units ~= 4 or #contents.logs ~= 4
        or #contents.bundles > 0
        or #looseAvailable(contents) ~= 4 then
        return false, "log_yard_bundle_not_ready"
    end
    local ropes = ropeSources(actor)
    if #ropes < 2 then return false, "log_yard_rope_missing" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "worker_inventory_unavailable" end
    local movedRopes, movedLogs = {}, {}
    for _, row in ipairs(ropes) do
        local moved = row.container == inventory and U().inventoryContains(inventory, row.item)
            or U().transferItemVerified(row.container, inventory, row.item)
        if moved ~= true then
            restoreIngredients(inventory, square, movedLogs, movedRopes)
            return false, "log_yard_rope_transfer_failed"
        end
        movedRopes[#movedRopes + 1] = row
    end
    for _, row in ipairs(contents.logs) do
        local taken = U().takeWorldItemVerified(row.world, inventory, row.item)
        if taken ~= true then
            if U().inventoryContains(inventory, row.item)
                and U().worldItemPresent(square, row.world) ~= true then
                movedLogs[#movedLogs + 1] = row
            end
            restoreIngredients(inventory, square, movedLogs, movedRopes)
            return false, "log_yard_log_pickup_failed"
        end
        movedLogs[#movedLogs + 1] = row
    end
    local bundle = U().addItem(inventory, "Base.LogStacks4")
    if not bundle or not U().inventoryContains(inventory, bundle) then
        restoreIngredients(inventory, square, movedLogs, movedRopes)
        return false, "log_yard_bundle_creation_failed"
    end
    -- RecipeCodeOnCreate.createLogStack writes these zero-based rope types to
    -- the output. Its splitLogStack callback expects the table to exist and
    -- returns the ropes when a player opens this bundle through vanilla UI.
    local data, readable = U().call(bundle, "getModData")
    if not readable or type(data) ~= "table" then
        removeExact(inventory, bundle)
        restoreIngredients(inventory, square, movedLogs, movedRopes)
        return false, "log_yard_bundle_metadata_unavailable"
    end
    data.ropeItems = {
        [0] = U().itemType(movedRopes[1].item),
        [1] = U().itemType(movedRopes[2].item),
    }
    for _, row in ipairs(movedLogs) do
        if not removeExact(inventory, row.item) then
            removeExact(inventory, bundle)
            restoreIngredients(inventory, square, movedLogs, movedRopes)
            return false, "log_yard_log_consumption_failed"
        end
    end
    for _, row in ipairs(movedRopes) do
        if not removeExact(inventory, row.item) then
            removeExact(inventory, bundle)
            restoreIngredients(inventory, square, movedLogs, movedRopes)
            return false, "log_yard_rope_consumption_failed"
        end
    end
    local dropped, worldOrReason = U().dropItem(inventory, square, bundle)
    if dropped == true and U().worldItemPresent(square, worldOrReason) == true then
        return true, "log_yard_bundled"
    end
    local linkedWorld = select(1, U().call(bundle, "getWorldItem"))
    if linkedWorld and U().worldItemPresent(square, linkedWorld) == true then
        return true, "log_yard_bundled"
    end
    if U().inventoryContains(inventory, bundle) and removeExact(inventory, bundle) then
        restoreIngredients(inventory, square, movedLogs, movedRopes)
    end
    return false, "log_yard_bundle_drop_failed"
end

function Yard.source(actor, preferredId)
    local best, bestDistance
    local inspected = 0
    local inventory = actor and U().inventory(actor) or nil
    for _, item in ipairs(U().inventoryItems(inventory, 4096)) do
        local marker = splitOf(item)
        if marker and marker.ownerId == tostring(U().idOf(actor) or "")
            and (preferredId == nil or marker.zoneId == preferredId) then
            local square = Yard.tile(marker.x, marker.y, marker.z, marker.zoneId)
            if square then
                return { kind = "log_yard", zoneId = marker.zoneId,
                    x = marker.x, y = marker.y, z = marker.z, square = square }
            end
        end
    end
    for _, zone in ipairs(zones(preferredId)) do
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                inspected = inspected + 1
                if inspected > 1024 then return best end
                local square = Yard.tile(x, y, zone.z, zone.id)
                local contents = square and Yard.contents(square) or nil
                local recovering = false
                for _, row in ipairs(contents and contents.bundles or {}) do
                    local marker = splitOf(row.item)
                    if marker and actor and marker.ownerId == tostring(U().idOf(actor) or "") then
                        recovering = true
                        break
                    end
                end
                if contents and (#looseAvailable(contents) > 0
                    or bundleAvailable(contents) ~= nil or recovering) then
                    local distance = actor and U().distance(actor, square) or 0
                    if bestDistance == nil or distance < bestDistance then
                        best = { kind = "log_yard", zoneId = zone.id,
                            x = x, y = y, z = zone.z, square = square }
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best
end

function Yard.pendingBundle(actor)
    if #ropeSources(actor) < 2 then return nil end
    local inspected = 0
    for _, zone in ipairs(zones(nil)) do
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                inspected = inspected + 1
                if inspected > 1024 then return nil end
                local square = Yard.tile(x, y, zone.z, zone.id)
                local contents = square and Yard.contents(square) or nil
                if contents and contents.units == 4 and #contents.logs == 4
                    and #contents.bundles == 0
                    and #looseAvailable(contents) == 4 then
                    return { kind = "log_yard", zoneId = zone.id,
                        x = x, y = y, z = zone.z, square = square }
                end
            end
        end
    end
    return nil
end

function Yard.updateBundle(actor)
    local destination = Yard.pendingBundle(actor)
    if not destination then return false, "log_yard_no_bundle_work" end
    if not U().sameSquare(actor, destination.square) then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local accepted, reason = SC.Navigation.requestAny(actor,
            { destination.square }, "walk", {
                action = "move_to_log_yard", targetSquare = destination.square,
                arrivalDistance = 0.45, workCampOnly = true, workReach = true,
            })
        return accepted == true, reason or "moving_to_log_yard"
    end
    return Yard.bundleAt(actor, destination.square)
end

-- Return one exact loose log. Tied stacks of two, three, or four are split
-- with their original world item retained until every output has been proved.
function Yard.takeOne(actor, destination)
    local square = destination and Yard.tile(destination.x, destination.y,
        destination.z, destination.zoneId) or nil
    if not square then return false, "log_yard_unloaded" end
    if not U().sameSquare(actor, square) then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local accepted, reason = SC.Navigation.requestAny(actor, { square }, "walk", {
            action = "move_to_log_yard", targetSquare = square,
            arrivalDistance = 0.45, workCampOnly = true, workReach = true,
        })
        return accepted == true, reason or "moving_to_log_yard"
    end
    local contents = Yard.contents(square)
    if not contents then return false, "log_yard_unloaded" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "worker_inventory_unavailable" end
    local pending = pendingSplit(actor, square, destination.zoneId)
    if pending then
        return abortSplit(inventory, square, pending, "log_yard_split_rolled_back")
    end
    local loose = looseAvailable(contents)[1]
    if loose then
        local room, roomReason = canCarryLog(actor, loose.item, true)
        if not room then return false, roomReason end
        local taken, reason = U().takeWorldItemVerified(loose.world, inventory, loose.item)
        return taken == true, taken and "log_yard_log_taken" or reason, loose.item
    end
    local tied = bundleAvailable(contents)
    if not tied then return false, "log_yard_empty" end
    local room, roomReason = canCarryLog(actor, tied.item, false)
    if not room then return false, roomReason end
    return splitStack(actor, inventory, square, tied, destination.zoneId)
end

return Yard
