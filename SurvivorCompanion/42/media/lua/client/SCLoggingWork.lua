-- SPDX-License-Identifier: MIT
-- Physical logging primitives shared by field clearing and wood expeditions.
-- Controllers own their order/state; this module owns only short tree claims.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.LoggingWork = SC.LoggingWork or {}
local Logging = SC.LoggingWork
local claims = {}

local function U() return SC.GameplayUtil end
local function call(object, name, ...)
    local value, okay = U().call(object, name, ...)
    if okay then return value end
end
local function now() return U().nowMs() end
function Logging.point(value)
    local x, y, z = U().position(value)
    if x == nil or y == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
end
function Logging.key(point)
    return point and (point.x .. ":" .. point.y .. ":" .. point.z) or nil
end
function Logging.tree(square)
    local tree = call(square, "getTree")
    if not tree or (tonumber(call(tree, "getObjectIndex")) or -1) < 0
        or (tonumber(call(tree, "getSize")) or 0) < 2 then return nil end
    return tree
end
local function activeChop(actor)
    return SC.NativeActions and SC.NativeActions.workKind
        and SC.NativeActions.workKind(actor) == "chop_tree"
        and SC.NativeActions.isWorkActive(actor) == true
end
function Logging.claimTree(ownerId, workerId, square, actor)
    local key = Logging.key(Logging.point(square))
    if not key or ownerId == nil or workerId == nil then return false end
    local held = claims[key]
    if held and (held.ownerId ~= ownerId or held.workerId ~= workerId)
        and (held.untilMs > now() or held.actor and activeChop(held.actor)) then return false end
    claims[key] = { ownerId = ownerId, workerId = workerId,
        actor = actor, untilMs = now() + 10000 }
    return true
end
function Logging.releaseTree(ownerId, workerId, point)
    local selected = point and Logging.key(point) or nil
    for key, held in pairs(claims) do
        if held.ownerId == ownerId and (workerId == nil or held.workerId == workerId)
            and (selected == nil or selected == key) then
            -- Cancellation can be refused while a native timed action settles.
            -- Releasing its controller must not invite a second cutter yet.
            if held.actor and activeChop(held.actor) then held.untilMs = now() + 10000
            else claims[key] = nil end
        end
    end
end
function Logging.reset() claims = {} end

-- Walk actual nested inventory containers; retained entries always include
-- their real owner, so moving a bag item never substitutes another item.
function Logging.inventoryEntries(actor)
    local root = U().inventory(actor)
    if not root then return nil, "inventory_unavailable" end
    local entries, containers, seen = {}, { root }, {}
    local examined = 0
    while #containers > 0 do
        local container = table.remove(containers)
        if not seen[container] then
            seen[container] = true
            local list = call(container, "getItems")
            if list == nil then return nil, "inventory_unreadable" end
            local size = U().listSize(list)
            if type(size) ~= "number" or examined + size > 4096 then
                return nil, "inventory_scan_limit"
            end
            for index = 0, size - 1 do
                local item = U().listGet(list, index)
                examined = examined + 1
                if item then
                    entries[#entries + 1] = { item = item, source = container }
                    local nested = call(item, "getInventory")
                    if nested and nested ~= container then containers[#containers + 1] = nested end
                end
            end
        end
    end
    return entries
end
function Logging.findItem(actor, id)
    local entries, reason = Logging.inventoryEntries(actor)
    if not entries then return nil, nil, reason end
    for _, entry in ipairs(entries) do
        if U().itemStableId(entry.item, true) == id then return entry.item, entry.source end
    end
    return nil, nil, "item_not_carried"
end
function Logging.axe(actor, permits)
    local entries, reason = Logging.inventoryEntries(actor)
    if not entries then return nil, reason end
    local best, score
    for _, entry in ipairs(entries) do
        local item = entry.item
        if U().itemHasTag(item, "CHOP_TREE") and call(item, "isBroken") == false
            and (not permits or permits(item)) then
            local damage = tonumber(call(item, "getTreeDamage")) or 0
            if best == nil or damage > score then best, score = item, damage end
        end
    end
    return best, best and nil or "wood_axe_missing"
end
function Logging.stageTool(actor, item)
    local inventory = U().inventory(actor)
    local source = call(item, "getContainer")
    if source == inventory then return true end
    if not source or not inventory then return false, "tool_inventory_unavailable" end
    local moved, reason = U().transferItemVerified(source, inventory, item)
    return moved == true, reason
end

local function groundEntries(point)
    local rows = {}
    for dx = -1, 1 do for dy = -1, 1 do
        local square = U().gridSquare(point.x + dx, point.y + dy, point.z)
        if not square then return nil, "wood_ground_unloaded" end
        local list = square and call(square, "getWorldObjects") or nil
        if square and list == nil then return nil, "wood_ground_unreadable" end
        local size = list and U().listSize(list) or 0
        if type(size) ~= "number" or size > 96 then return nil, "wood_ground_scan_limit" end
        for index = 0, size - 1 do
            local wrapper = U().listGet(list, index)
            local item = wrapper and call(wrapper, "getItem")
            if item then
                local id = U().itemStableId(item, true)
                if not id then return nil, "wood_item_identity_unavailable" end
                rows[#rows + 1] = { id = id, item = item, wrapper = wrapper,
                    square = square, source = Logging.point(square), sourceObjectIndex = index }
            end
        end
    end end
    return rows
end
function Logging.groundIds(point)
    local rows, reason = groundEntries(point)
    if not rows then return nil, reason end
    local ids = {}
    for _, row in ipairs(rows) do ids[row.id] = true end
    return ids
end
function Logging.newLogs(point, before)
    local rows, reason = groundEntries(point)
    if not rows then return nil, reason end
    local result = {}
    for _, row in ipairs(rows) do
        if U().itemType(row.item) == "Base.Log" and not (before or {})[row.id] then
            result[#result + 1] = row
        end
    end
    return result
end
function Logging.groundLog(point, id)
    local rows, reason = groundEntries(point)
    if not rows then return nil, reason end
    for _, row in ipairs(rows) do if row.id == id and U().itemType(row.item) == "Base.Log" then return row end end
    return nil, "wood_log_missing"
end

function Logging.approach(actor, square, action, onSquare, options)
    if not SC.Navigation or not SC.Navigation.requestAny then return false, "navigation_unavailable" end
    local targets = {}
    if onSquare and U().isSquareFree(square) then targets[1] = square end
    if #targets == 0 and SC.Navigation.interactionTargets then
        targets = SC.Navigation.interactionTargets(actor, square, { requireDirectAccess = true }) or {}
    end
    if #targets == 0 then return false, "no_interaction_targets" end
    options = options or {}
    local accepted, reason, reached = SC.Navigation.requestAny(actor, targets, "walk", {
        action = action, targetSquare = square, arrivalDistance = onSquare and 0.45 or 0.5,
        requireSameSquare = not onSquare,
        workCampOnly = options.workCampOnly, workReach = options.workReach,
        movementPriority = options.movementPriority,
    })
    if not accepted then return false, reason end
    return true, reason == "arrived" and reached and U().sameSquare(actor, reached)
        and "arrived" or "wood_approaching"
end
function Logging.startChop(actor, point, tool, options)
    local square = U().gridSquare(point.x, point.y, point.z)
    local tree = square and Logging.tree(square)
    if not tree then return false, "wood_tree_missing" end
    local staged, reason = Logging.stageTool(actor, tool)
    if not staged then return false, reason end
    options = options or {}
    if options.cancelReason ~= false and SC.Navigation and SC.Navigation.cancel then
        SC.Navigation.cancel(actor, options.cancelReason or "wood_chopping")
    end
    local accepted, why = U().move(actor, "walk", {
        action = "chop_tree", tree = tree, tool = tool, targetSquare = square,
    })
    if not accepted or not options.deferActiveCheck and not activeChop(actor) then
        return false, why or "wood_chop_not_started"
    end
    return true, "wood_chopping"
end
function Logging.chopProgress(actor, tree, work)
    local health = tree and tonumber(call(tree, "getHealth"))
    if health and work.lastHealth and health < work.lastHealth then
        work.nativeHit, work.progressAt = true, now()
    end
    work.lastHealth = health or work.lastHealth
    if tree and not work.nativeHit and now() - (work.progressAt or work.startedAt or 0) >= 6000
        and now() - (work.emulatedAt or 0) >= 1500 and SC.NativeActions.emulateWorkEvent then
        work.emulatedAt = now()
        SC.NativeActions.emulateWorkEvent(actor, "chop_tree", "ChopTree")
        local after = tonumber(call(tree, "getHealth"))
        if after and health and after < health then work.progressAt = now() end
        work.lastHealth = after or health
    end
end
function Logging.pollChop(actor, work)
    local square = U().gridSquare(work.point.x, work.point.y, work.point.z)
    if not square then return false, "wood_tree_unloaded" end
    local tree = Logging.tree(square)
    if activeChop(actor) then
        Logging.chopProgress(actor, tree, work)
        if now() - work.startedAt > 180000 then
            SC.NativeActions.cancelWork(actor, "wood_chop_timeout")
            return false, "wood_chop_timeout"
        end
        return true, "wood_chopping"
    end
    local kind = SC.NativeActions and SC.NativeActions.workKind and SC.NativeActions.workKind(actor)
    if kind == "chop_tree" and SC.NativeActions.finishWork then
        local finished, why = SC.NativeActions.finishWork(actor)
        if not finished then return false, why or "wood_chop_settling" end
    end
    if tree then return false, "wood_chop_interrupted" end
    return true, "wood_tree_felled", true
end
function Logging.carSquares(actor, vehicle, part)
    local area = call(part, "getArea")
    local center = area and Logging.point(call(vehicle, "getAreaCenter", area))
    if not center then return {} end
    center.z = (Logging.point(vehicle) or center).z
    local square = U().gridSquare(center.x, center.y, center.z)
    if not square or not SC.Navigation or not SC.Navigation.interactionTargets then return {} end
    return SC.Navigation.interactionTargets(actor, square,
        { requireDirectAccess = true, maximum = 8 }) or {}
end
function Logging.atCar(actor, vehicle, part, options)
    options = options or {}
    local squares = Logging.carSquares(actor, vehicle, part)
    if #squares == 0 then return false, options.accessReason or "wood_trunk_access_unavailable" end
    local okay, reason, reached = SC.Navigation.requestAny(actor, squares, "walk", {
        action = options.action or "wood_car_cargo", targetSquare = Logging.point(vehicle),
        requireSameSquare = true, arrivalDistance = 0.5,
        workCampOnly = options.workCampOnly, workReach = options.workReach,
        movementPriority = options.movementPriority,
    })
    if not okay then return false, reason end
    if reason == "arrived" and reached and U().sameSquare(actor, reached) then
        for _, current in ipairs(Logging.carSquares(actor, vehicle, part)) do
            if U().sameSquare(actor, current) then return true, "arrived" end
        end
    end
    return true, "approaching"
end
function Logging.cargo(actor, carId, state, snapshot, options)
    local vehicle = SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(carId)
    if not vehicle then return nil, nil, "wood_car_unloaded" end
    if SC.Vehicle.isStationary(vehicle) ~= true then return nil, nil, "wood_car_moved" end
    if call(vehicle, "isTrunkLocked") == true then
        if not SC.FieldWork or not SC.FieldWork.unlockTrunkFor then return nil, nil, "wood_trunk_locked" end
        state.unlock = state.unlock or {}
        local handled, why = SC.FieldWork.unlockTrunkFor(actor, vehicle, state.unlock, snapshot)
        return nil, nil, handled and (why or "wood_unlocking_trunk") or why, handled == true
    end
    state.unlock = nil
    local part, container, why = SC.Vehicle.cargoPart(vehicle)
    if not part or not container then return nil, nil, why or "wood_trunk_missing" end
    local approached, reason = Logging.atCar(actor, vehicle, part, options)
    if not approached or reason ~= "arrived" then return nil, nil,
        reason == "approaching" and "wood_approaching" or reason, approached == true end
    return vehicle, container
end
function Logging.transferVerified(source, destination, item)
    local moved, reason = U().transferItemVerified(source, destination, item)
    if call(item, "getContainer") == destination
        and U().inventoryContains(source, item) == false
        and U().inventoryContains(destination, item) == true then return true end
    return false, reason or (moved and "wood_transfer_unverified" or "wood_transfer_failed")
end
function Logging.transfer(source, destination, actor, item)
    if not SC.WorkTransport then return false, "capacity_unavailable" end
    local room, roomReason = SC.WorkTransport.hasRoom(destination, actor, item)
    if room ~= true then return false, roomReason or "capacity_unavailable" end
    return Logging.transferVerified(source, destination, item)
end
return Logging
