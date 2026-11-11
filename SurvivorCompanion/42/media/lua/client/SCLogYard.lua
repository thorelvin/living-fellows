-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.LogYard = SC.LogYard or {}
local Yard = SC.LogYard

local function U() return SC.GameplayUtil end
local SPLIT_MARK = "LF_LogYardSplit"
local LOG_WEIGHT = 9 -- Base.Log in the installed Build 42 item script.
local layoutCache = setmetatable({}, { __mode = "k" })
local arrangeContents

local function splitOf(item)
    local data = item and U().modData(item) or nil
    local marker = type(data) == "table" and data[SPLIT_MARK] or nil
    if type(marker) ~= "table" then return nil end
    if marker.v == 2 then
        local job = SC.BaseLife and SC.BaseLife.job and SC.BaseLife.job(marker.jobId)
        local receipt = job and job.target and job.target.yardUnstack
        if not receipt or receipt.id ~= marker.id or job.state == "cancelled" or job.state == "completed" then
            data[SPLIT_MARK] = nil
            return nil
        end
    end
    return marker
end

local function markSplit(item, receipt, role, index)
    local data = item and U().modData(item) or nil
    if type(data) ~= "table" then return false end
    data[SPLIT_MARK] = {
        v = receipt.v or 1, id = receipt.id, jobId = receipt.jobId, role = role, index = index,
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

function Yard.contents(square, skipLayout)
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
    local contents = { units = units, logs = logs, bundles = bundles,
        splitPending = splitPending }
    -- Normalize only this already-visited, loaded tile. Presentation never
    -- changes its inventory identities, claims or square membership.
    if arrangeContents and not skipLayout then arrangeContents(square, contents) end
    return contents
end

local function unclaimed(item)
    local data, readable = U().call(item, "getModData")
    if not readable or type(data) ~= "table" then return false end
    if splitOf(item) or data.LF_LogYardBundle ~= nil and Yard.reserved
        and Yard.reserved(item) then return false end
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

local function closeOffset(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 0.0001
end

local function arrangeRow(row, x, y, z, force)
    local item, world = row.item, row.world
    local cached = layoutCache[world]
    -- Repeated yard scans reuse verified poses. Membership changes alter the
    -- desired slots; reloaded wrappers and explicit deposits recheck natively.
    if not force and cached and row.layoutId ~= nil and cached.id == row.layoutId
        and cached.x == x and cached.y == y and cached.z == z then return true end
    if select(1, U().call(world, "getItem")) ~= item
        or select(1, U().call(item, "getWorldItem")) ~= world then return false end
    local rotation = select(1, U().call(item, "getWorldZRotation"))
    local rotated = closeOffset(rotation, 0)
    local rotationChanged = false
    if not rotated then
        local _, called = U().call(item, "setWorldZRotation", 0)
        rotated = called and closeOffset(select(1, U().call(item, "getWorldZRotation")), 0)
        rotationChanged = rotated
    end
    local positioned = closeOffset(select(1, U().call(world, "getOffX")), x)
        and closeOffset(select(1, U().call(world, "getOffY")), y)
        and closeOffset(select(1, U().call(world, "getOffZ")), z)
    if not positioned then
        -- Unlike individual offset setters, the native combined setter also
        -- invalidates the render chunk and synchronizes placement.
        U().call(world, "setOffset", x, y, z)
        positioned = closeOffset(select(1, U().call(world, "getOffX")), x)
            and closeOffset(select(1, U().call(world, "getOffY")), y)
            and closeOffset(select(1, U().call(world, "getOffZ")), z)
    end
    if rotationChanged then U().call(world, "syncExtendedPlacement") end
    if rotated and positioned then
        layoutCache[world] = { id = row.layoutId, x = x, y = y, z = z }
    else layoutCache[world] = nil end
    return rotated and positioned
end

local function stableRows(rows)
    local allIds = true
    for index, row in ipairs(rows) do
        row.layoutOrder = index
        local nativeId = select(1, U().call(row.item, "getID"))
        row.layoutId = tonumber(nativeId)
        if row.layoutId == nil then allIds = false end
    end
    table.sort(rows, function(a, b)
        if allIds and a.layoutId ~= b.layoutId then
            return a.layoutId < b.layoutId
        end
        return a.layoutOrder < b.layoutOrder
    end)
end

arrangeContents = function(square, contents, force)
    if not contents then return false, "log_yard_unloaded" end
    if contents.splitPending then return false, "log_yard_split_pending" end
    if contents.units > 4 then return false, "log_yard_overfilled" end
    if contents.units == 0 then return true, "log_yard_empty" end
    local x, y, z = U().position(square)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
        or not Yard.tile(x, y, z) then return false, "log_yard_unavailable" end
    stableRows(contents.logs)
    stableRows(contents.bundles)
    local arranged = true
    for index, row in ipairs(contents.bundles) do
        if not arrangeRow(row, 0.5, 0.5, (index - 1) * 0.10, force) then arranged = false end
    end
    local count = #contents.logs
    for index, row in ipairs(contents.logs) do
        local baseCount = math.min(3, count)
        local rowY = 0.5 + (index - (baseCount + 1) / 2) * 0.2
        local rowZ = #contents.bundles * 0.10
        if index == 4 then rowY, rowZ = 0.5, rowZ + 0.08 end
        if not arrangeRow(row, 0.5, rowY, rowZ, force) then arranged = false end
    end
    -- An unavailable presentation API never reverses a verified physical drop.
    return arranged, arranged and "log_yard_arranged" or "log_yard_layout_unavailable"
end

function Yard.arrange(square)
    local contents = Yard.contents(square, true)
    return arrangeContents(square, contents, true)
end

function Yard.select(actor, preferredId)
    local best, bestDistance
    local splitPending = false
    local inspected = 0
    for _, zone in ipairs(zones(preferredId)) do
        local partial, empty, zoneDistance
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                inspected = inspected + 1
                if inspected > 1024 then
                    local candidate = partial or empty
                    if candidate and (bestDistance == nil or zoneDistance < bestDistance) then
                        return candidate
                    end
                    if best then return best end
                    return nil, "log_yard_scan_limit"
                end
                local square = Yard.tile(x, y, zone.z, zone.id)
                local contents = square and Yard.contents(square) or nil
                local distance = square and (actor and U().distance(actor, square) or 0)
                if distance and (zoneDistance == nil or distance < zoneDistance) then
                    zoneDistance = distance
                end
                if contents and contents.splitPending then splitPending = true end
                if contents and contents.units < 4 and not contents.splitPending then
                    local candidate = { kind = "log_yard", zoneId = zone.id,
                        x = x, y = y, z = zone.z, square = square }
                    -- Finish a four-log stack before starting the next tile;
                    -- ties follow the yard's fixed row order, not worker feet.
                    if contents.units > 0 then partial = partial or candidate
                    else empty = empty or candidate end
                end
            end
        end
        local candidate = partial or empty
        if candidate and (bestDistance == nil or zoneDistance < bestDistance) then
            best, bestDistance = candidate, zoneDistance
        end
    end
    if best then return best end
    return nil, splitPending and "log_yard_split_pending" or "log_yard_full"
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
    Yard.arrange(square)
    Yard.bundleAt(actor, square)
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
        return marker and marker.zoneId == zoneId
            and marker.x == select(1, U().position(square))
            and marker.y == select(2, U().position(square))
            and marker.z == select(3, U().position(square))
    end
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
        if eligible(item) and splitOf(item).ownerId == ownerId then
            return splitOf(item)
        end
    end
    for _, row in ipairs(worldItems(square) or {}) do
        if eligible(row.item) then return splitOf(row.item) end
    end
    return nil
end

local rollbackSplit, completeSplit

local function recoverOrphanSplit(inventory, square, receipt)
    local rows = splitRows(inventory, square, receipt.id)
    if rows.duplicate then return false, "log_yard_split_orphaned" end
    -- A retired worker may still have marked items in a corpse or unloaded
    -- inventory. Take over only when every provisional output is visible on
    -- this tile, so clearing the original cannot duplicate missing cargo.
    for index = 1, receipt.count do
        local row = rows.logs[index]
        local held = row and U().inventoryContains(inventory, row.item)
        local grounded = row and row.world
            and U().worldItemPresent(square, row.world) == true
        if not row or not held and not grounded then
            return false, "log_yard_split_orphaned"
        end
    end
    for index = 1, receipt.ropeCount do
        local row = rows.ropes[index]
        if not row or not U().inventoryContains(inventory, row.item)
            and (not row.world or U().worldItemPresent(square, row.world) ~= true) then
            return false, "log_yard_split_orphaned"
        end
    end
    if rows.source then
        return false, rollbackSplit(inventory, square, receipt)
            and "log_yard_split_rolled_back" or "log_yard_split_recovery_pending"
    end
    -- With the source gone, all output identities are proved on the ground.
    -- Move the selected log and ropes to the new worker, then commit once.
    local selected = rows.logs[1]
    if not U().inventoryContains(inventory, selected.item) then
        local taken = U().takeWorldItemVerified(selected.world, inventory, selected.item)
        if taken ~= true then return false, "log_yard_split_recovery_pending" end
    end
    for index = 1, receipt.ropeCount do
        local row = rows.ropes[index]
        if not U().inventoryContains(inventory, row.item) then
            local taken = U().takeWorldItemVerified(row.world, inventory, row.item)
            if taken ~= true then return false, "log_yard_split_recovery_pending" end
        end
    end
    return completeSplit(inventory, square, receipt)
end

rollbackSplit = function(inventory, square, receipt)
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

completeSplit = function(inventory, square, receipt)
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

-- Version-one split receipts above remain recoverable for older saves. New
-- bundles are opened only by the native UnstackTwo/Three/FourLogs recipes.

-- A delivered fourth log requests ordinary camp work. Never craft inside a
-- delivery callback: that callback still belongs to the hauler's current job.
function Yard.bundleAt(actor, square)
    local contents = Yard.contents(square, true)
    if not contents or contents.units ~= 4 or #contents.logs ~= 4
        or #contents.bundles ~= 0 or #looseAvailable(contents) ~= 4 then
        return false, "log_yard_bundle_not_ready"
    end
    local x, y, z = U().position(square)
    local base = SC.BaseLife.active()
    if not base or not Yard.tile(x, y, z) then return false, "log_yard_unloaded" end
    local pending = 0
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "stack_logs" and job.state ~= "completed" and job.state ~= "cancelled"
            then
            pending = pending + 1
            if job.target.x == x and job.target.y == y and job.target.z == z then
                return true, "log_yard_bundle_queued"
            end
        end
    end
    if pending >= 8 then return false, "log_yard_jobs_pending" end
    local queued, job = SC.BaseLife.enqueueJob({ type = "stack_logs", priority = 3,
        target = { x = x, y = y, z = z } })
    return queued, queued and "log_yard_bundle_queued" or job, queued and job or nil
end

local function own(item, jobId)
    local data = item and U().modData(item)
    return type(data) == "table" and data.LF_LogYardBundle == jobId
end
local function mark(item, jobId)
    local data = item and U().modData(item)
    if type(data) ~= "table" then return false end
    data.LF_LogYardBundle = jobId
    return own(item, jobId)
end
local function unmark(item, jobId)
    if own(item, jobId) then U().modData(item).LF_LogYardBundle = nil end
end
function Yard.reserved(item)
    local data = item and U().modData(item)
    local id = data and data.LF_LogYardBundle
    if not id then return false end
    local job = SC.BaseLife.job(id)
    local token = U().itemStableId(item)
    if job and job.type == "stack_logs" and job.state ~= "cancelled" and job.state ~= "completed" then
        if job.target.outputId == token then return true end
        for _, wanted in ipairs(job.target.logs or {}) do if wanted == token then return true end end
        for _, rope in ipairs(job.target.ropes or {}) do if rope.id == token then return true end end
    end
    unmark(item, id)
    return false
end
local itemSearches = setmetatable({}, { __mode = "k" })
local function findItem(container, id, nativeId)
    if not container or not id then return nil, false end
    -- Native ids accelerate the current session; the persistent token remains
    -- authoritative after companion inventory reconstruction on reload.
    local searches = itemSearches[container] or {}
    itemSearches[container] = searches
    local scan = searches[id]
    if nativeId then
        local item = select(1, U().call(container, "getItemById", nativeId))
        if item and U().itemStableId(item) == id then scan = { found = item }; searches[id] = scan end
    end
    if scan and scan.found then
        local owner = select(1, U().call(scan.found, "getContainer"))
        local present = owner and U().inventoryContains(owner, scan.found)
        for _ = 1, 8 do
            if not owner or owner == container then break end
            local bag = select(1, U().call(owner, "getContainingItem"))
            owner = bag and select(1, U().call(bag, "getContainer"))
        end
        if present and owner == container and U().itemStableId(scan.found) == id then
            return scan.found, false
        end
        scan = nil
    end
    if scan and scan.missingAt and U().nowMs() - scan.missingAt < 2000 then return nil, false end
    if not scan or scan.missingAt then
        scan = { rows = { container }, seen = { [container] = true }, c = 1, i = 0 }
        searches[id] = scan
    end
    local budget, visited = 64, 0
    while scan.c <= #scan.rows and budget > 0 and visited < 4 do
        visited = visited + 1
        local items = select(1, U().call(scan.rows[scan.c], "getItems"))
        local count = (items and U().listSize(items)) or 0
        while scan.i < count and budget > 0 do
            local item = U().listGet(items, scan.i)
            scan.i, budget = scan.i + 1, budget - 1
            if U().itemStableId(item) == id then searches[id] = { found = item }; return item, false end
            local bag = item and select(1, U().call(item, "getItemContainer"))
            if bag and not scan.seen[bag] and #scan.rows < 24 then
                scan.rows[#scan.rows + 1], scan.seen[bag] = bag, true
            end
        end
        if scan.i >= count then scan.c, scan.i = scan.c + 1, 0 end
    end
    if scan.c <= #scan.rows then return nil, true end
    scan.missingAt = U().nowMs()
    return nil, false
end
local function sourceFor(receipt)
    local storage = receipt.sourceId and SC.BaseLife.storage(receipt.sourceId)
    return storage, storage and SC.BaseLife.resolveContainer(storage)
end
local function ropeFor(actor, receipt)
    local item, carriedPending
    if actor then item, carriedPending = findItem(U().inventory(actor), receipt.id, receipt.nativeId) end
    if item then return item, true, false end
    local _, container = sourceFor(receipt)
    local stored, sourcePending = findItem(container, receipt.id, receipt.nativeId)
    return stored, false, not stored and (carriedPending or sourcePending) == true
end
local bundleStates = setmetatable({}, { __mode = "k" })
local auditCursor = 0

-- Two workers must not each borrow the last single rope and wait forever for
-- the other one. Stack preparation/crafting is one bounded job at a time;
-- ordinary hauling, chopping and other camp work remain independent.
function Yard.canClaim(job)
    local base = SC.BaseLife.active()
    for _, other in ipairs(base and base.jobs or {}) do
        if other ~= job and other.type == "stack_logs"
            and other.state ~= "completed" and other.state ~= "cancelled"
            and (other.state == "reserved" or other.state == "active"
                or other.target.stage ~= nil) then return false end
    end
    return true
end

-- Retain the cursor between work ticks. At most 64 items in four containers
-- are inspected per tick; an unfinished search is never a rope shortage.
local function nextRope(actor, job, state)
    local scan = state.ropeScan
    if not scan then
        scan = { rows = {}, c = 1, i = 0 }
        local root, seen = U().inventory(actor), {}
        scan.rows[1], seen[root] = { container = root }, true
        for _, item in ipairs(U().inventoryItemsDeep(root, 128, 12)) do
            local bag = select(1, U().call(item, "getItemContainer"))
            if bag and not seen[bag] then
                scan.rows[#scan.rows + 1], seen[bag] = { container = bag }, true
            end
        end
        for _, category in ipairs({ "crafting", "general", "tools", "construction" }) do
            for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
                scan.rows[#scan.rows + 1] = { sourceId = storage.id }
            end
        end
        state.ropeScan = scan
    end
    local budget, visited = 64, 0
    while scan.c <= #scan.rows and budget > 0 and visited < 4 do
        visited = visited + 1
        local row = scan.rows[scan.c]
        local storage, container
        if row.sourceId then storage, container = sourceFor(row)
        else container = row.container end
        local items = container and select(1, U().call(container, "getItems"))
        local count = (items and U().listSize(items)) or 0
        while scan.i < count and budget > 0 do
            local item = U().listGet(items, scan.i)
            scan.i, budget = scan.i + 1, budget - 1
            if item and U().itemHasTag(item, "ROPE") and unclaimed(item)
                and not (SC.PersonalItems and SC.PersonalItems.isProtected
                    and SC.PersonalItems.isProtected(item, actor, "base_build"))
                and (not storage or SC.BaseLife.availableCountExact(storage,
                    U().itemType(item)) > 0) then
                local id = U().itemStableId(item, true)
                if id and mark(item, job.id) then
                    state.ropeScan = nil
                    return { id = id, nativeId = select(1, U().call(item, "getID")), sourceId = row.sourceId }, item
                end
            end
        end
        if scan.i >= count then scan.c, scan.i = scan.c + 1, 0 end
    end
    if scan.c <= #scan.rows then return nil, "log_yard_rope_search_pending" end
    state.ropeScan = nil
    return nil, "log_yard_rope_missing"
end

local function pinnedLogs(job, square)
    local found = {}
    for _, row in ipairs(worldItems(square) or {}) do
        local id = U().itemStableId(row.item)
        for _, wanted in ipairs(job.target.logs or {}) do
            if id == wanted and own(row.item, job.id) and U().itemType(row.item) == "Base.Log" then
                found[#found + 1] = row.item
            end
        end
    end
    return found
end
local function releaseLogs(job, square)
    for _, row in ipairs(worldItems(square) or {}) do unmark(row.item, job.id) end
    job.target.logs = nil
end
local function outputFor(actor, job, square)
    local id = job.target.outputId
    if not id then return nil end
    local item, pending
    if actor then item, pending = findItem(U().inventory(actor), id, job.target.outputNativeId) end
    if item then return item, true, false end
    for _, row in ipairs(worldItems(square) or {}) do
        if U().itemStableId(row.item) == id then return row.item, false, false end
    end
    return nil, false, pending
end
local function settleOutput(actor, job, square)
    local target = job.target
    local item, carried, pending = outputFor(actor, job, square)
    if pending then return true, "log_yard_rope_search_pending" end
    local data = item and U().modData(item)
    if target.nativeOK ~= true or not item or U().itemType(item) ~= "Base.LogStacks4"
        or type(data.ropeItems) ~= "table" or not data.ropeItems[0] or not data.ropeItems[1]
        or #pinnedLogs(job, square) ~= 0 then
        return false, "log_yard_craft_receipt_uncertain", true
    end
    for _, receipt in ipairs(target.ropes or {}) do
        local remaining, _, searching = ropeFor(actor, receipt)
        if searching then return true, "log_yard_rope_search_pending" end
        if remaining then return false, "log_yard_craft_receipt_uncertain", true end
    end
    if carried then
        local dropped, reason = U().dropItem(U().inventory(actor), square, item)
        if dropped ~= true then return true, reason or "log_yard_output_drop_pending" end
    end
    local world = select(1, U().call(item, "getWorldItem"))
    if not world or U().worldItemPresent(square, world) ~= true then
        return false, "log_yard_craft_receipt_uncertain", true
    end
    unmark(item, job.id)
    releaseLogs(job, square)
    target.ropes, target.outputId, target.outputNativeId = nil, nil, nil
    target.attempted, target.nativeOK = nil, nil
    target.stage, job.assignedId = nil, nil
    if actor then bundleStates[actor] = nil end
    itemSearches = setmetatable({}, { __mode = "k" })
    Yard.arrange(square)
    return true, "log_yard_bundled", false, true
end

function Yard.update(actor, baseState, job)
    local target, native = job.target, SC.NativeActions
    local square = Yard.tile(target.x, target.y, target.z)
    if not square then return false, "log_yard_unloaded", true end
    local state = bundleStates[actor]
    if not state or state.jobId ~= job.id then
        state = { jobId = job.id }
        bundleStates[actor] = state
    end
    job.assignedId = U().idOf(actor)
    target.stage = target.stage or "preparing"
    if target.stage == "crafting" then
        if native.workKind(actor) == "stack_logs" and native.workJobId(actor) == job.id then
            if native.isWorkActive(actor) then return true, "log_yard_tying" end
            local released, reason = native.finishWork(actor)
            if released ~= true then return true, reason end
        end
        if target.attempted then return settleOutput(actor, job, square) end
        target.stage = nil -- interrupted before consumption; exact inputs still exist
    end
    if not target.logs then
        local contents = Yard.contents(square)
        if not contents or contents.units ~= 4 or #contents.logs ~= 4
            or #looseAvailable(contents) ~= 4 then
            return true, "log_yard_bundle_not_ready", false, true
        end
        target.logs, target.ropes = {}, {}
        for _, row in ipairs(contents.logs) do
            local id = U().itemStableId(row.item, true)
            if not id or not mark(row.item, job.id) then
                releaseLogs(job, square)
                return false, "log_yard_claim_failed", true
            end
            target.logs[#target.logs + 1] = id
        end
    end
    local logs = pinnedLogs(job, square)
    if #logs ~= 4 then
        local okay, reason = Yard.cancel(actor, job)
        if okay ~= true then return true, reason end
        return true, "log_yard_inputs_changed", false, true
    end
    target.ropes = target.ropes or {}
    for index, receipt in ipairs(target.ropes) do
        local item, carried, pending = ropeFor(actor, receipt)
        if pending then return true, "log_yard_rope_search_pending" end
        if not item or not own(item, job.id) then
            local storage, container = sourceFor(receipt)
            if storage and not container then return false, "base_storage_unloaded", true end
            unmark(item, job.id)
            table.remove(target.ropes, index)
            return true, "log_yard_rope_reselecting"
        end
        if not carried then
            local storage, container = sourceFor(receipt)
            if not storage or not container then return false, "base_storage_unloaded", true end
            local taken, reason = SC.BaseWork.withdrawFromStorage(actor, baseState, storage, container, item)
            if U().inventoryContains(U().inventory(actor), item) then
                itemSearches[U().inventory(actor)] = nil
            end
            return taken == true, reason or "log_yard_fetching_rope", taken ~= true
        end
    end
    if #target.ropes < 2 then
        local receipt, itemOrReason = nextRope(actor, job, state)
        if not receipt then
            if itemOrReason == "log_yard_rope_missing" then
                local returned, why = Yard.cancel(actor, job)
                if returned ~= true then return true, why end
            end
            return itemOrReason ~= "log_yard_rope_missing", itemOrReason,
                itemOrReason == "log_yard_rope_missing"
        end
        target.ropes[#target.ropes + 1] = receipt
        return true, "log_yard_fetching_rope"
    end
    if not U().sameSquare(actor, square) then
        if not SC.Navigation then return false, "navigation_unavailable", true end
        local okay, reason = SC.Navigation.requestAny(actor, { square }, "walk", {
            action = "move_to_log_yard", targetSquare = square, arrivalDistance = 0.45,
            workCampOnly = true, workReach = true,
        })
        return okay == true, reason or "moving_to_log_yard", okay ~= true
    end
    local ropes = {}
    for _, receipt in ipairs(target.ropes) do ropes[#ropes + 1] = ropeFor(actor, receipt) end
    local started, reason = native.startLogStack(actor, {
        logs = logs, ropes = ropes, square = square, jobId = job.id,
        validate = function()
            local current = SC.BaseLife.job(job.id)
            if current ~= job or job.reservedBy ~= U().idOf(actor)
                or (job.state ~= "active" and job.state ~= "reserved")
                or U().isDead(actor) or not U().sameSquare(actor, square)
                or Yard.tile(target.x, target.y, target.z) ~= square
                then return false end
            -- This validation runs with the native action. Use its six pinned
            -- objects, not repeated inventory or yard searches every frame.
            for _, item in ipairs(logs) do
                local world = select(1, U().call(item, "getWorldItem"))
                if not own(item, job.id) or not world
                    or U().worldItemPresent(square, world) ~= true then return false end
            end
            for _, item in ipairs(ropes) do
                local container = select(1, U().call(item, "getContainer"))
                if not container or not own(item, job.id) then return false end
                for _ = 1, 8 do
                    if container == U().inventory(actor) then break end
                    local bag = select(1, U().call(container, "getContainingItem"))
                    container = bag and select(1, U().call(bag, "getContainer"))
                    if not container then return false end
                end
                if container ~= U().inventory(actor) then return false end
            end
            return true
        end,
        onAttempt = function() target.attempted = true end,
        onResult = function(item, okay)
            target.nativeOK = okay
            if item then
                target.outputId, target.outputNativeId = U().itemStableId(item, true), select(1, U().call(item, "getID"))
                mark(item, job.id)
            end
        end,
    })
    if started then target.stage = "crafting" end
    return started == true, reason or "log_yard_tying", started ~= true
end

function Yard.cancel(actor, job)
    if not job then return true end
    local native = SC.NativeActions
    if actor and native and native.workKind(actor) == "stack_logs"
        and native.workJobId(actor) == job.id then
        local stopped, reason = native.cancelWork(actor, "log_yard_cancelled")
        if stopped ~= true then return false, reason end
    end
    local target = job.target
    local square = U().gridSquare(target.x, target.y, target.z)
    if not actor and job.assignedId and not (SC.BaseFuel and SC.BaseFuel.workerGone(job)) then
        return false, "log_yard_worker_unavailable"
    end
    if target.attempted then
        if not square then return false, "log_yard_unloaded" end
        local _, reason, _, done = settleOutput(actor, job, square)
        if done then return true, reason end
        -- Cancellation may abandon an ambiguous receipt, never replay it.
        -- Preserve and release every real surviving item for the player.
        local output, _, pending = outputFor(actor, job, square)
        if pending then return false, "log_yard_rope_search_pending" end
        unmark(output, job.id)
        target.outputId, target.outputNativeId, target.attempted = nil, nil, nil
        target.nativeOK = nil
    end
    for _, receipt in ipairs(target.ropes or {}) do
        local item, carried, pending = ropeFor(actor, receipt)
        if pending then return false, "log_yard_rope_search_pending" end
        if item and carried and receipt.sourceId and not U().isDead(actor) then
            local storage, container = sourceFor(receipt)
            if not container then return false, "base_storage_unloaded" end
            local returned, reason = SC.BaseWork.restoreToStorage(actor, storage, container, item)
            if returned ~= true then return false, reason end
        end
        unmark(item, job.id) -- personal rope stays personal; dead workers keep their real items
    end
    if not square and target.logs then return false, "log_yard_unloaded" end
    releaseLogs(job, square)
    target.ropes, target.stage, job.assignedId = nil, nil, nil
    if actor then bundleStates[actor] = nil end
    itemSearches = setmetatable({}, { __mode = "k" })
    return true, "log_yard_cancelled"
end

function Yard.releaseAffinity(actor, job)
    if not job or not job.assignedId then return true end
    if not actor then return Yard.cancel(nil, job) end
    if job.target.logs or #(job.target.ropes or {}) > 0 or job.target.attempted then return false end
    job.assignedId, bundleStates[actor] = nil, nil
    return true
end

-- Share the maintenance round-robin; no independent tick or whole-yard scan.
function Yard.audit(maximumTiles)
    local rows, total = zones(nil), 0
    for _, zone in ipairs(rows) do total = total + (zone.x2-zone.x1+1)*(zone.y2-zone.y1+1) end
    if total == 0 then return false, "log_yard_missing" end
    local offset = auditCursor % total
    local limit = math.max(1, math.min(8, math.floor(tonumber(maximumTiles) or 8)))
    for _ = 1, math.min(limit, total) do
        local at = offset
        for _, zone in ipairs(rows) do
            local width, size = zone.x2-zone.x1+1, (zone.x2-zone.x1+1)*(zone.y2-zone.y1+1)
            if at < size then
                local square = Yard.tile(zone.x1 + at % width, zone.y1 + math.floor(at / width), zone.z, zone.id)
                if square then
                    local queued = Yard.bundleAt(nil, square)
                    if queued then auditCursor = (offset+1)%total; return true, "log_yard_bundle_queued" end
                end
                break
            end
            at = at-size
        end
        offset = (offset+1)%total
    end
    auditCursor = offset
    return false, "log_yard_no_bundle_work"
end

-- New unstack receipts belong to the existing build/production job. Output
-- tokens describe only items returned by the stock recipe, never replacements.
function Yard.splitReserved(item) return splitOf(item) ~= nil end

local function unstackRows(actor, square, receipt)
    local ground, rows, pending = {}, {}, false
    for _, row in ipairs(worldItems(square) or {}) do
        local id = U().itemStableId(row.item)
        if id then ground[id] = row end
    end
    for _, id in ipairs(receipt.outputs or {}) do
        local row = ground[id]
        if not row and actor then
            local item, searching = findItem(U().inventory(actor), id)
            if item then row = { item = item } end
            pending = pending or searching == true
        end
        if row then rows[#rows + 1] = row end
    end
    return rows, pending, ground[receipt.sourceId]
end

local function dropUnstackOutputs(actor, square, receipt)
    local rows, pending = unstackRows(actor, square, receipt)
    if pending then return false, "log_yard_unstack_reconciling" end
    if #rows ~= #(receipt.outputs or {}) then return false, "log_yard_unstack_receipt_uncertain" end
    for _, row in ipairs(rows) do
        if U().itemType(row.item) ~= "Base.Log" then return false, "log_yard_unstack_receipt_uncertain" end
        if not row.world then
            local dropped = actor and U().dropItem(U().inventory(actor), square, row.item)
            if dropped ~= true then return false, "log_yard_unstack_drop_pending" end
        end
    end
    return true
end

local function clearUnstack(actor, square, job)
    local receipt = job.target.yardUnstack
    if not receipt then return end
    for _, row in ipairs(worldItems(square) or {}) do clearSplit(row.item, receipt.id) end
    if actor then
        for _, item in ipairs(U().inventoryItemsDeep(U().inventory(actor), 1024, 24)) do
            clearSplit(item, receipt.id)
        end
    end
    -- Any item taken by the player loses its stale claim lazily in splitOf.
    job.target.yardUnstack = nil
    job.assignedId = receipt.previousAssignedId
    itemSearches = setmetatable({}, { __mode = "k" })
    if square then Yard.arrange(square) end
end

function Yard.cancelUnstack(actor, job)
    local receipt = job and job.target and job.target.yardUnstack
    if not receipt then return true end
    local native = SC.NativeActions
    if actor and native.workKind(actor) == "unstack_logs" and native.workJobId(actor) == job.id then
        local stopped, reason = native.cancelWork(actor, "log_yard_unstack_cancelled")
        if stopped ~= true then return false, reason end
    end
    if not actor and not (SC.BaseFuel and SC.BaseFuel.workerGone(job)) then
        return false, "log_yard_worker_unavailable"
    end
    local square = U().gridSquare(receipt.x, receipt.y, receipt.z)
    if not square then return false, "log_yard_unloaded" end
    if receipt.attempted and receipt.nativeOK == true and actor and not U().isDead(actor) then
        local dropped, reason = dropUnstackOutputs(actor, square, receipt)
        if dropped ~= true then return false, reason end
    end
    -- Interrupted/ambiguous work is never replayed on cancellation. Surviving
    -- items retain their real owners, including a retired worker's corpse.
    clearUnstack(actor, square, job)
    return true, "log_yard_unstack_cancelled"
end

function Yard.cancelActorUnstack(actor, jobType)
    local base, id = SC.BaseLife.active(), actor and U().idOf(actor)
    for _, job in ipairs(base and base.jobs or {}) do
        local receipt = job.target and job.target.yardUnstack
        if receipt and receipt.ownerId == id and (not jobType or job.type == jobType) then
            local stopped, reason = Yard.cancelUnstack(actor, job)
            if stopped ~= true then return false, reason end
        end
    end
    return true
end

function Yard.releaseUnstackAffinity(actor, job)
    if not job.target.yardUnstack then return true end
    if actor and not U().isDead(actor) then return false end
    return Yard.cancelUnstack(actor, job)
end

function Yard.updateUnstack(actor, square, job)
    local receipt, native = job.target.yardUnstack, SC.NativeActions
    if not receipt or receipt.ownerId ~= U().idOf(actor) then return false, "log_yard_split_owned" end
    local owned = native.workKind(actor) == "unstack_logs" and native.workJobId(actor) == job.id
    if owned then
        if native.isWorkActive(actor) then
            if U().nowMs() - (receipt.startedAt or U().nowMs()) < 120000 then
                return true, "log_yard_unstacking"
            end
            local stopped, reason = native.cancelWork(actor, "log_yard_unstack_timeout")
            if stopped ~= true then return true, reason end
        end
        local released, reason = native.finishWork(actor)
        if released ~= true then return true, reason end
    elseif native.workKind(actor) then return true, "log_yard_work_busy" end
    if receipt.attempted then
        if receipt.nativeOK ~= true or #(receipt.outputs or {}) ~= receipt.count then
            return false, "log_yard_unstack_receipt_uncertain", nil, true
        end
        local rows, pending, source = unstackRows(actor, square, receipt)
        if pending then return true, "log_yard_unstack_reconciling" end
        if source or #rows ~= receipt.count then return false, "log_yard_unstack_receipt_uncertain", nil, true end
        local carriedSource, searching = findItem(U().inventory(actor), receipt.sourceId)
        if searching then return true, "log_yard_unstack_reconciling" end
        if carriedSource then return false, "log_yard_unstack_receipt_uncertain", nil, true end
        local dropped, reason = dropUnstackOutputs(actor, square, receipt)
        if dropped ~= true then return true, reason end
        rows = unstackRows(actor, square, receipt)
        local selected = rows[1]
        local room, why = canCarryLog(actor, selected.item, true)
        if not room then return false, why end
        local taken, detail = U().takeWorldItemVerified(selected.world, U().inventory(actor), selected.item)
        if taken ~= true then return true, detail or "log_yard_unstack_pickup_pending" end
        clearSplit(selected.item, receipt.id)
        clearUnstack(actor, square, job)
        return true, "log_yard_log_taken", selected.item
    end
    local source
    for _, row in ipairs(worldItems(square) or {}) do
        if U().itemStableId(row.item) == receipt.sourceId then source = row; break end
    end
    if not source then
        clearUnstack(actor, square, job)
        return false, "log_yard_inputs_changed", nil, true
    end
    local started, reason = native.startLogUnstack(actor, {
        bundle = source.item, count = receipt.count, square = square, jobId = job.id,
        validate = function()
            return SC.BaseLife.job(job.id) == job and job.target.yardUnstack == receipt
                and job.reservedBy == U().idOf(actor) and (job.state == "active" or job.state == "reserved")
                and not U().isDead(actor) and U().sameSquare(actor, square)
                and Yard.tile(receipt.x, receipt.y, receipt.z, receipt.zoneId) == square
                and U().worldItemPresent(square, source.world) == true
                and splitOf(source.item) and splitOf(source.item).id == receipt.id
        end,
        onAttempt = function() receipt.attempted = true end,
        onResult = function(outputs, okay)
            receipt.nativeOK, receipt.outputs = okay, {}
            for index, item in ipairs(outputs) do
                local id = U().itemStableId(item, true)
                receipt.outputs[#receipt.outputs + 1] = id
                markSplit(item, receipt, "log", index)
                -- Native may put all four logs in root inventory. Return its
                -- actual outputs to the yard before another game tick runs.
                if U().inventoryContains(U().inventory(actor), item) then
                    U().dropItem(U().inventory(actor), square, item)
                end
            end
        end,
    })
    if started then receipt.startedAt = U().nowMs() end
    return started == true, started and "log_yard_unstacking" or reason, nil, started ~= true
end

function Yard.beginUnstack(actor, square, tied, zoneId, job)
    if not job or not job.target or SC.BaseLife.job(job.id) ~= job then
        return false, "log_yard_unstack_job_missing", nil, true
    end
    local data = U().modData(tied.item)
    local types = data and data.ropeItems
    if type(types) ~= "table" or type(types[0]) ~= "string" or types[0] == ""
        or type(types[1]) ~= "string" or types[1] == "" then
        return false, "log_yard_bundle_metadata_missing", nil, true
    end
    for key in pairs(types) do
        if key ~= 0 and key ~= 1 then return false, "log_yard_bundle_metadata_missing", nil, true end
    end
    local id = U().itemStableId(tied.item, true)
    if not id then return false, "log_yard_unstack_identity_missing", nil, true end
    local receipt = { v = 2, id = "unstack:" .. job.id, jobId = job.id,
        previousAssignedId = job.assignedId,
        ownerId = U().idOf(actor), zoneId = zoneId, count = tied.count,
        x = select(1, U().position(square)), y = select(2, U().position(square)),
        z = select(3, U().position(square)), sourceId = id }
    job.target.yardUnstack = receipt
    job.assignedId = receipt.ownerId
    if not markSplit(tied.item, receipt, "source", 0) then
        job.target.yardUnstack = nil
        job.assignedId = receipt.previousAssignedId
        return false, "log_yard_split_marker_failed", nil, true
    end
    return Yard.updateUnstack(actor, square, job)
end

function Yard.source(actor, preferredId, job)
    local receipt = job and job.target and job.target.yardUnstack
    if receipt then
        return { kind = "log_yard", zoneId = receipt.zoneId, x = receipt.x, y = receipt.y,
            z = receipt.z, square = Yard.tile(receipt.x, receipt.y, receipt.z, receipt.zoneId) }
    end
    local best, bestDistance, bestRank
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
                local recovering, ownRecovery = false, false
                for _, row in ipairs(square and worldItems(square) or {}) do
                    local marker = splitOf(row.item)
                    if marker then
                        recovering = true
                        if actor and marker.ownerId == tostring(U().idOf(actor) or "") then
                            ownRecovery = true
                            break
                        end
                    end
                end
                local available = contents and (#looseAvailable(contents) > 0
                    or bundleAvailable(contents) ~= nil)
                if contents and (available or recovering) then
                    local distance = actor and U().distance(actor, square) or 0
                    local rank = ownRecovery and 1 or available and 2 or 3
                    if bestRank == nil or rank < bestRank
                        or rank == bestRank and distance < bestDistance then
                        best = { kind = "log_yard", zoneId = zone.id,
                            x = x, y = y, z = zone.z, square = square }
                        bestDistance, bestRank = distance, rank
                    end
                end
            end
        end
    end
    return best
end

-- Return one exact loose log. Native unstacking runs inside the caller's job;
-- old version-one split receipts retain their conservative recovery path.
function Yard.takeOne(actor, destination, job)
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
    local inventory = U().inventory(actor)
    if job and job.target and job.target.yardUnstack then
        return Yard.updateUnstack(actor, square, job)
    end
    local contents = Yard.contents(square)
    if not contents then return false, "log_yard_unloaded" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "worker_inventory_unavailable" end
    local pending = pendingSplit(actor, square, destination.zoneId)
    if pending then
        if pending.v == 2 then return false, "log_yard_split_owned" end
        if pending.ownerId ~= tostring(U().idOf(actor) or "") then
            local owner = U().resolveActor(pending.ownerId)
            local restoring = SC.Persistence and SC.Persistence.restoreStatus
                and SC.Persistence.restoreStatus() == false
            local waiting = SC.Persistence and SC.Persistence.isPending
                and SC.Persistence.isPending(pending.ownerId) == true
            if owner or restoring or waiting then
                return false, "log_yard_split_owned"
            end
            return recoverOrphanSplit(inventory, square, pending)
        end
        return abortSplit(inventory, square, pending, "log_yard_split_rolled_back")
    end
    local loose = looseAvailable(contents)[1]
    if loose then
        local room, roomReason = canCarryLog(actor, loose.item, true)
        if not room then return false, roomReason end
        local taken, reason = U().takeWorldItemVerified(loose.world, inventory, loose.item)
        if taken == true then Yard.arrange(square) end
        return taken == true, taken and "log_yard_log_taken" or reason, loose.item
    end
    local tied = bundleAvailable(contents)
    if not tied then return false, "log_yard_empty" end
    local room, roomReason = canCarryLog(actor, tied.item, false)
    if not room then return false, roomReason end
    return Yard.beginUnstack(actor, square, tied, destination.zoneId, job)
end

return Yard
