-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.LogYard = SC.LogYard or {}
local Yard = SC.LogYard

local function U() return SC.GameplayUtil end

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
    local units, logs, bundles = 0, {}, {}
    for _, row in ipairs(rows) do
        local kind = U().itemType(row.item)
        if kind == "Base.Log" then
            units = units + 1
            logs[#logs + 1] = row
        elseif kind == "Base.LogStacks4" then
            units = units + 4
            bundles[#bundles + 1] = row
        elseif kind == "Base.LogStacks3" then units = units + 3
        elseif kind == "Base.LogStacks2" then units = units + 2 end
    end
    return { units = units, logs = logs, bundles = bundles }
end

local function unclaimed(item)
    local data, readable = U().call(item, "getModData")
    if not readable or type(data) ~= "table" then return false end
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
                if contents and contents.units < 4 then
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

local function ropeSources(actor)
    local result, selected = {}, {}
    for _, category in ipairs({ "crafting", "general", "tools" }) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
            local container = SC.BaseLife.resolveContainer(storage)
            local available = container and SC.BaseLife.availableCountExact(storage, "Base.Rope") or 0
            if container and available > 0 then
                for _, item in ipairs(U().inventoryItems(container, 64)) do
                    if U().itemType(item) == "Base.Rope" and not selected[item]
                        and available > 0
                        and not (SC.PersonalItems and SC.PersonalItems.isProtected
                            and SC.PersonalItems.isProtected(item, actor, "base_build")) then
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
        if not U().inventoryContains(inventory, row.item) then U().addItem(inventory, row.item) end
        if U().inventoryContains(inventory, row.item) then
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
        local moved = U().transferItemVerified(row.container, inventory, row.item)
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
    for _, zone in ipairs(zones(preferredId)) do
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                inspected = inspected + 1
                if inspected > 1024 then return best end
                local square = Yard.tile(x, y, zone.z, zone.id)
                local contents = square and Yard.contents(square) or nil
                if contents and (#looseAvailable(contents) > 0
                    or bundleAvailable(contents) ~= nil) then
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

-- Return one exact loose log to the worker. A tied stack is opened using the
-- vanilla four-log output and the other three logs are left on the same tile.
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
    local loose = looseAvailable(contents)[1]
    if loose then
        local taken, reason = U().takeWorldItemVerified(loose.world, inventory, loose.item)
        return taken == true, taken and "log_yard_log_taken" or reason, loose.item
    end
    local tied = bundleAvailable(contents)
    if not tied then return false, "log_yard_empty" end
    local taken, reason = U().takeWorldItemVerified(tied.world, inventory, tied.item)
    if taken ~= true then return false, reason end
    local data = select(1, U().call(tied.item, "getModData"))
    local ropeTypes = type(data) == "table" and data.ropeItems or nil
    local logs = {}
    for _ = 1, 4 do
        local log = U().addItem(inventory, "Base.Log")
        if not log then
            for _, created in ipairs(logs) do removeExact(inventory, created) end
            U().dropItem(inventory, square, tied.item)
            return false, "log_yard_unbundle_failed"
        end
        logs[#logs + 1] = log
    end
    local returnedRopes = {}
    if type(ropeTypes) == "table" then
        for index = 0, 1 do
            local ropeType = ropeTypes[index]
            if type(ropeType) == "string" and ropeType ~= "" then
                local rope = U().addItem(inventory, ropeType)
                if not rope then
                    for _, created in ipairs(logs) do removeExact(inventory, created) end
                    for _, created in ipairs(returnedRopes) do
                        removeExact(inventory, created)
                    end
                    U().dropItem(inventory, square, tied.item)
                    return false, "log_yard_unbundle_failed"
                end
                returnedRopes[#returnedRopes + 1] = rope
            end
        end
    end
    if not removeExact(inventory, tied.item) then
        for _, created in ipairs(logs) do removeExact(inventory, created) end
        for _, created in ipairs(returnedRopes) do removeExact(inventory, created) end
        U().dropItem(inventory, square, tied.item)
        return false, "log_yard_unbundle_failed"
    end
    for index = 2, 4 do
        local dropped = U().dropItem(inventory, square, logs[index])
        if dropped ~= true then return false, "log_yard_unbundle_drop_failed" end
    end
    return true, "log_yard_log_taken", logs[1]
end

return Yard
