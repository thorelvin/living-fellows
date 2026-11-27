-- SPDX-License-Identifier: MIT
-- Camp stock only. Native washing replaces an item, so the saved receipt
-- follows the verified replacement rather than searching for a similar rag.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
SC.BandageWashing = SC.BandageWashing or {}
local W = SC.BandageWashing
local MARKER = 'LF_DressingWashJob'
local runtime = setmetatable({}, { __mode = 'k' })
local waterScans = setmetatable({}, { __mode = 'k' })
local function U() return SC.GameplayUtil end
local function call(value, name, ...) return U().call(value, name, ...) end
local function data(item) return select(1, call(item, 'getModData')) end
local function identity(item)
    local id, okay = call(item, 'getID')
    id = okay and tonumber(id) or nil
    return id and id ~= 0 and id == id and math.abs(id) ~= math.huge and id == math.floor(id) and id or nil
end
local function receipt(job)
    return job and job.type == 'wash_dressings' and type(job.target) == 'table'
        and job.target.dressingBatch or nil
end
local function changed()
    if SC.BaseLife.noteWorkOwnershipMutation then SC.BaseLife.noteWorkOwnershipMutation() end
end
local function current(job, actor)
    return job and SC.BaseLife.job(job.id) == job
        and job.reservedBy == U().idOf(actor)
        and (job.state == 'active' or job.state == 'reserved')
end
local function owned(actor, item)
    return U().inventoryContains(U().inventory(actor), item)
        or SC.PersonalItems and SC.PersonalItems.ownedBy(item, actor) == true
end
local function marked(item, job, batch, index)
    local fields = data(item)
    return batch.ids[index] ~= 0 and identity(item) == batch.ids[index]
        and U().itemType(item) == batch.types[index] and fields and fields[MARKER] == job.id
end
local function clearMarker(item, job)
    local fields = data(item)
    if fields and fields[MARKER] == job.id then fields[MARKER] = nil end
end
function W.reserved(item, exceptJobId)
    local fields = data(item)
    local id = fields and fields[MARKER]
    if not id then return false end
    local job = SC.BaseLife.job(id)
    local batch = receipt(job)
    if not batch or job.state == 'completed' or job.state == 'cancelled' then
        -- Items outside the worker and camp stores can surface after the
        -- receipt has closed. A missing job during world restoration is not
        -- proof that its exact marker is stale.
        if not job and not (SC.Persistence and SC.Persistence.restoreStatus
            and SC.Persistence.restoreStatus() == true) then return true end
        fields[MARKER] = nil
        return false
    end
    if job.id == exceptJobId then return false end
    if type(batch) ~= 'table' or type(batch.ids) ~= 'table' then return true end
    local itemId = identity(item)
    if not itemId then return false end
    for _, expected in ipairs(batch.ids) do if itemId == expected then return true end end
    fields[MARKER] = nil
    return false
end
function W.ownsInput(actor, item, jobId)
    local job = SC.BaseLife.job(jobId)
    local batch = receipt(job)
    local index = type(batch) == 'table' and batch.index or 1
    local fields = data(item)
    return type(batch) == 'table' and type(batch.ids) == 'table' and type(batch.types) == 'table'
        and type(batch.washed) == 'table' and index ~= nil
        and current(job, actor) and batch.owner == U().idOf(actor)
        and (batch.phase == 'wash' or batch.phase == 'washing')
        and batch.washed[index] ~= true and batch.ids[index] == identity(item)
        and batch.types[index] == U().itemType(item)
        and fields and fields[MARKER] == jobId and owned(actor, item) == true
end
function W.acceptResult(actor, job, result)
    local batch = receipt(job)
    local index = type(batch) == 'table' and batch.index or 1
    local input, output = result and result.input, result and result.output
    if not current(job, actor) or type(batch) ~= 'table' or type(batch.ids) ~= 'table'
        or type(batch.types) ~= 'table' or type(batch.washed) ~= 'table' or not index
        or type(result) ~= 'table' or result.verified ~= true
        or batch.washed[index] == true or identity(input) ~= batch.ids[index]
        or U().itemType(input) ~= batch.types[index]
        or not data(input) or data(input)[MARKER] ~= job.id or batch.phase ~= 'washing'
        or not SC.BandageWash or SC.BandageWash.cleanType(input) ~= U().itemType(output)
        or identity(output) == nil or identity(output) == identity(input)
        or owned(actor, input) or not owned(actor, output) then return false end
    local fields = data(output)
    if not fields or fields[MARKER] ~= nil and fields[MARKER] ~= job.id then return false end
    -- Protect output before releasing the consumed input's claim. The native
    -- effect already committed; failure here must never reconstruct input.
    fields[MARKER] = job.id
    if fields[MARKER] ~= job.id then return false end
    batch.ids[index], batch.types[index], batch.washed[index] =
        identity(output), U().itemType(output), true
    batch.phase = 'wash'
    clearMarker(input, job)
    local state = runtime[job]
    if state and state.items then state.items[index] = output end
    changed()
    return true
end

local function campWater(object, base)
    if not base or not SC.BandageWash.worldSourceValid(object) then return false end
    local x, y, z = U().position(U().squareOf(object))
    if not x then return false end
    for index, zone in ipairs(base.zones or {}) do
        if index > 64 then break end
        if zone.kind == 'area' and z == zone.z and x >= zone.x1 and x <= zone.x2
            and y >= zone.y1 and y <= zone.y2 then return true end
    end
    return false
end
function W.claim(actor, job)
    if not receipt(job) then return nil end
    return {
        jobId = job.id,
        ownsInput = function(item) return W.ownsInput(actor, item, job.id) end,
        validate = function() return current(job, actor) end,
        onAttempt = function(activity)
            if not W.ownsInput(actor, activity.item, job.id) then return false end
            receipt(job).phase = 'washing'; changed(); return true
        end,
        onResult = function(result) return W.acceptResult(actor, job, result) end,
    }
end

-- One bounded slice over marked camp area tiles; the clean-only world policy
-- is shared with personal washing and is never relaxed for showers.
function W.findWater(actor, state)
    local base = SC.BaseLife.active()
    if not base or not SC.BandageWash then return nil, 'no_water_for_bandages' end
    local scan = waterScans[base]
    if not scan or scan.done and U().nowMs() - scan.finishedAt >= 30000 then
        scan = { zones = {}, zone = 1, index = 0, sources = {}, seen = {} }
        for i, zone in ipairs(base.zones or {}) do
            if i > 64 then break end
            if zone.kind == 'area' then scan.zones[#scan.zones + 1] = zone end
        end
        waterScans[base] = scan
    end
    if not scan.done then
        for _ = 1, 128 do
            local area = scan.zones[scan.zone]
            if not area then scan.done, scan.finishedAt = true, U().nowMs(); break end
            local width, height = area.x2 - area.x1 + 1, area.y2 - area.y1 + 1
            if width <= 0 or height <= 0 or scan.index >= width * height then
                scan.zone, scan.index = scan.zone + 1, 0
            else
                local offset = scan.index; scan.index = offset + 1
                local square = U().gridSquare(area.x1 + offset % width,
                    area.y1 + math.floor(offset / width), area.z)
                if square and #scan.sources < 32 then
                    U().squareObjects(square, function(object)
                        if not scan.seen[object] and SC.BandageWash.worldSourceValid(object) then
                            scan.seen[object] = true
                            scan.sources[#scan.sources + 1] = object
                        end
                    end, 48)
                end
            end
        end
    end
    if not scan.done then return nil, 'dressing_water_scanning' end
    local choices = {}
    for _, object in ipairs(scan.sources) do
        if campWater(object, base) then
            choices[#choices + 1] = { id = tostring(object), object = object }
        end
    end
    if #choices == 0 then return nil, 'no_water_for_bandages' end
    if actor then
        if not SC.Navigation or not SC.Navigation.selectInteraction then
            return nil, 'navigation_unavailable'
        end
        state.waterSurvey = state.waterSurvey or {}
        local selected, reason = SC.Navigation.selectInteraction(actor, state.waterSurvey,
            'dressing_water', choices, { nodeBudget = 1600, workCampOnly = true, workReach = true })
        if selected then return selected.object end
        return nil, (reason == 'pending' or reason == 'unknown')
            and 'dressing_water_scanning' or 'no_water_for_bandages'
    end
    return choices[1].object
end
local function stockAllowed(item, actor, job)
    if not item or not SC.BandageWash.cleanType(item) or not data(item) or not identity(item) then return false end
    if SC.PersonalItems and SC.PersonalItems.personalRecord(item) then return false end
    if SC.WorkTransport and SC.WorkTransport.foreignProtected(item, actor, job and job.id) then return false end
    local fields = data(item)
    for key, value in pairs(fields) do
        if value ~= nil and value ~= false and type(key) == 'string'
            and (string.sub(key, 1, 3) == 'LF_' or string.sub(key, 1, 3) == 'SC_') then
            local lower = string.lower(key)
            if string.find(lower, 'loan', 1, true) or string.find(lower, 'borrow', 1, true) then return false end
        end
    end
    return true
end
-- At most 128 identities per pulse. Selection never withdraws from a pack.
local function findStock(actor, state)
    local scan = state.stockScan
    if not scan then
        scan = { rows = SC.BaseLife.storageRows(nil, true), row = 1, index = 0 }
        state.stockScan = scan
    end
    local budget = 128
    while budget > 0 do
        local storage = scan.rows[scan.row]
        if not storage then state.stockScan = nil; return nil, 'dressing_stock_missing' end
        local container = SC.BaseLife.resolveContainer(storage)
        if storage.category == 'memorial' or not SC.BaseLife.withdrawable(storage) or not container then
            scan.row, scan.index = scan.row + 1, 0
            budget = budget - 1
        else
            local items = select(1, call(container, 'getItems'))
            local size = U().listSize(items)
            if scan.index >= size then
                scan.row, scan.index, budget = scan.row + 1, 0, budget - 1
            else
                local item = U().listGet(items, scan.index)
                scan.index, budget = scan.index + 1, budget - 1
                if stockAllowed(item, actor) then
                    local available = SC.BaseLife.availableCountExact or SC.BaseLife.availableCount
                    local count = available and available(storage, U().itemType(item)) or 0
                    if count > 0 then
                        state.stockScan = nil
                        return storage, container, item, scan.index - 1
                    end
                end
            end
        end
    end
    return nil, 'dressing_stock_scanning'
end
function W.audit(base, _, scan)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == 'wash_dressings' and job.state ~= 'completed' and job.state ~= 'cancelled' then
            return false, 'dressing_wash_already_queued'
        end
    end
    local source, reason = W.findWater(nil, scan)
    if not source then return false, reason, reason == 'dressing_water_scanning' end
    local storage, container = findStock(nil, scan)
    if not storage then return false, container, container == 'dressing_stock_scanning' end
    local x, y, z = U().position(U().squareOf(source))
    return SC.BaseLife.enqueueJob({ type = 'wash_dressings', priority = 4,
        target = { x = x, y = y, z = z, sourceId = storage.id } })
end

local function beginBatch(actor, state, job)
    local storage, container, first, start = findStock(actor, state)
    if not storage then return false, container, container ~= 'dressing_stock_scanning' end
    local batch = { owner = U().idOf(actor), sourceId = storage.id,
        ids = {}, types = {}, washed = {}, phase = 'take', index = 1 }
    local chosen, allowances = {}, {}
    local items = select(1, call(container, 'getItems'))
    if U().listGet(items, start) ~= first then return false, 'base_supply_moved', true end
    for i = start, math.min(U().listSize(items) - 1, start + 127) do
        local item = U().listGet(items, i)
        if #chosen >= 8 then break end
        if stockAllowed(item, actor) then
            local kind = U().itemType(item)
            if allowances[kind] == nil then
                allowances[kind] = (SC.BaseLife.availableCountExact or SC.BaseLife.availableCount)(storage, kind)
            end
            if allowances[kind] > 0 then
                chosen[#chosen + 1] = item
                batch.ids[#chosen], batch.types[#chosen], batch.washed[#chosen] = identity(item), kind, false
                allowances[kind] = allowances[kind] - 1
            end
        end
    end
    if #chosen == 0 then return false, 'dressing_stock_missing', true end
    local previousAssignment = job.assignedId
    job.target = job.target or {}; job.target.dressingBatch = batch
    job.assignedId = batch.owner
    state.items = chosen
    for _, item in ipairs(chosen) do
        local fields = data(item)
        local okay = fields and pcall(function() fields[MARKER] = job.id end)
        if not okay or fields[MARKER] ~= job.id then
            local cleared = true
            for _, selected in ipairs(chosen) do
                local marks = data(selected)
                if marks and marks[MARKER] == job.id then
                    local removed = pcall(function() marks[MARKER] = nil end)
                    if not removed or marks[MARKER] == job.id then cleared = false end
                end
            end
            if cleared then
                job.target.dressingBatch, job.assignedId, state.items = nil, previousAssignment, nil
            end
            changed()
            return false, 'dressing_wash_uncertain', true
        end
    end
    changed()
    return true
end
local function restoreItems(actor, state, job)
    local batch = receipt(job)
    if type(batch) ~= 'table' or batch.owner ~= U().idOf(actor) or type(batch.ids) ~= 'table'
        or #batch.ids == 0 or #batch.ids > 8 or type(batch.types) ~= 'table'
        or type(batch.washed) ~= 'table' or type(batch.index) ~= 'number'
        or batch.index < 1 or batch.index > #batch.ids + 1 or batch.index ~= math.floor(batch.index)
        or not ({ take = true, wash = true, washing = true, deposit = true, returning = true })[batch.phase] then
        return false, 'dressing_wash_uncertain'
    end
    local ids = {}
    for index, id in ipairs(batch.ids) do
        if type(id) ~= 'number' or id ~= id or math.abs(id) == math.huge or id ~= math.floor(id)
            or type(batch.types[index]) ~= 'string' or type(batch.washed[index]) ~= 'boolean'
            or id ~= 0 and (ids[id] or batch.types[index] == '') then return false, 'dressing_wash_uncertain' end
        if id ~= 0 and not batch.washed[index] and (batch.phase == 'deposit'
            or (batch.phase == 'wash' or batch.phase == 'washing') and index < batch.index) then
            return false, 'dressing_wash_uncertain'
        end
        if id ~= 0 then ids[id] = true end
    end
    -- onAttempt persisted this slot before calling the game. After a restart
    -- the original might already be consumed. All other slots still require
    -- exact, marked identities and their ordinary ownership checks.
    local uncertain = batch.phase == 'washing' and batch.index
    if uncertain and (not batch.ids[uncertain] or batch.ids[uncertain] == 0
        or batch.washed[uncertain]) then return false, 'dressing_wash_uncertain' end
    if state.items then
        for index, id in ipairs(batch.ids) do
            if index ~= uncertain and id ~= 0 and not marked(state.items[index], job, batch, index) then
                return false, 'dressing_wash_uncertain'
            end
        end
        return true
    end
    if state.restoreAfter and U().nowMs() < state.restoreAfter then return nil, 'base_storage_unloaded' end
    state.found = state.found or {}
    local ambiguous = false
    local function remember(item)
        for index, id in ipairs(batch.ids) do
            local fields = index == uncertain and id == identity(item) and data(item)
            if id ~= 0 and (fields and fields[MARKER] == job.id or marked(item, job, batch, index)) then
                if state.found[index] and state.found[index] ~= item then ambiguous = true end
                state.found[index] = item
            end
        end
    end
    local source = SC.BaseLife.storage(batch.sourceId)
    local sourceContainer = source and SC.BaseLife.resolveContainer(source)
    -- Include committed destinations: a save can happen after the exact move
    -- but before its receipt slot is cleared. Only marked identities count.
    state.restoreStores = state.restoreStores or { source }
    if not state.restoreStoresReady then
        state.restoreStores = source and { source } or {}
        for _, row in ipairs(SC.BaseLife.depositStorageRows('medical')) do
            if row ~= source then state.restoreStores[#state.restoreStores + 1] = row end
        end
        state.restoreStoresReady = true
    end
    local budget = 128
    while budget > 0 and (state.restoreStore or 1) <= #state.restoreStores do
        local row = state.restoreStores[state.restoreStore or 1]
        local container = SC.BaseLife.storage(row.id) == row and SC.BaseLife.resolveContainer(row)
        if not container then state.restoreStoreUnavailable = true end
        if container then
            local items = select(1, call(container, 'getItems'))
            local index = state.sourceCursor or 0
            if index < U().listSize(items) then
                remember(U().listGet(items, index))
                state.sourceCursor, budget = index + 1, budget - 1
            else container = nil end
        end
        if not container then
            state.restoreStore, state.sourceCursor, budget = (state.restoreStore or 1) + 1, 0, budget - 1
        end
    end
    if ambiguous then return false, 'dressing_wash_uncertain' end
    if (state.restoreStore or 1) <= #state.restoreStores then return nil, 'dressing_stock_scanning' end
    if not SC.PersonalItems or not SC.PersonalItems.walkActorInventory then return false, 'dressing_wash_uncertain' end
    local _, complete = SC.PersonalItems.walkActorInventory(actor, remember,
        { budget = 256, skip = state.restoreCursor or 0 })
    if ambiguous then return false, 'dressing_wash_uncertain' end
    if not complete then
        state.restoreCursor = (state.restoreCursor or 0) + 256; return nil, 'dressing_stock_scanning'
    end
    for index, id in ipairs(batch.ids) do
        local item = state.found[index]
        if index == uncertain then state.found[index] = item or false
        elseif id == 0 then state.found[index] = false
        elseif not item and state.restoreStoreUnavailable then
            -- A sibling may already be on a shelf whose square was unloaded.
            -- Revisit those stores on a later pulse before giving up its claim.
            state.found, state.restoreStore, state.restoreCursor, state.sourceCursor = nil, nil, nil, nil
            state.restoreStoresReady, state.restoreStoreUnavailable = nil, nil
            state.restoreAfter = U().nowMs() + 1000
            return nil, 'base_storage_unloaded'
        elseif not item or not marked(item, job, batch, index) then
            return false, 'dressing_wash_uncertain'
        elseif not owned(actor, item) then
            local delivered = sourceContainer and U().inventoryContains(sourceContainer, item)
            if batch.washed[index] then
                delivered = false
                for _, row in ipairs(state.restoreStores) do
                    local container = SC.BaseLife.storage(row.id) == row and SC.BaseLife.resolveContainer(row)
                    if row.category == 'medical' and container and U().inventoryContains(container, item)
                        and SC.BaseLife.storageAcceptsDeposit(row, container) == true then delivered = true end
                end
            end
            if not delivered then return false, 'dressing_wash_uncertain' end
        end
    end
    state.items = state.found
    return true
end
local function medicalDestination(actor, item)
    for _, storage in ipairs(SC.BaseLife.depositStorageRows('medical')) do
        local container = SC.BaseLife.resolveContainer(storage)
        if storage.category == 'medical' and container
            and SC.BaseLife.storageAcceptsDeposit(storage, container)
            and (U().inventoryContains(container, item)
                or SC.WorkTransport.hasRoom(container, actor, item) == true) then return storage, container end
    end
end
local function settled(item, job, batch, index)
    clearMarker(item, job)
    batch.ids[index], batch.types[index], batch.washed[index] = 0, '', false
    changed()
end
local function semiSafe(actor, context)
    local snapshot = type(context) == 'table' and (context.senses and context.senses.current or context.snapshot)
    return type(snapshot) == 'table' and SC.Medical and SC.Medical.canTreatNow
        and SC.Medical.canTreatNow(actor, snapshot) == true
end
local transient = { base_storage_unloaded = true, destination_full = true,
    native_care_busy = true, work_action_still_active = true, settling_after_action = true }
local function failed(reason)
    return transient[reason] == true, reason, transient[reason] ~= true
end
local function nativeOwner(actor, state)
    local native = SC.NativeActions
    local tracked = native.workKind and native.workKind(actor) ~= nil
        or native.isWorkActive and native.isWorkActive(actor) == true
    if not tracked then return 'none' end
    if state.activity and native.ownsDowntimeAction
        and native.ownsDowntimeAction(actor, state.activity) == true then return 'owned' end
    return 'foreign'
end
function W.update(actor, workState, job, context)
    local state = runtime[job] or {}; runtime[job] = state
    if not current(job, actor) then return false, 'dressing_wash_uncertain', true end
    local owner = nativeOwner(actor, state)
    if owner == 'foreign' then return true, 'dressing_native_owner_busy', false end
    local batch = receipt(job)
    if batch ~= nil and type(batch) ~= 'table' then return false, 'dressing_wash_uncertain', true end
    if not batch then
        local ready, why, terminal = beginBatch(actor, state, job)
        if not ready then return terminal ~= true, why, terminal end
        batch = receipt(job)
    end
    if batch.phase == 'washing' or batch.phase == 'returning' then
        if owner == 'owned' and SC.NativeActions.isWorkActive(actor) then return true, 'washing_bandages' end
        local done, why = W.cancel(actor, job)
        if done then return true, why, false, true end
        if why == 'dressing_stock_scanning' then return true, why end
        return failed(why)
    end
    local restored, reason = restoreItems(actor, state, job)
    if restored ~= true then return restored == nil, reason, restored == false end
    if batch.phase == 'take' then
        local storage = SC.BaseLife.storage(batch.sourceId)
        local container = storage and SC.BaseLife.resolveContainer(storage)
        if not container then return failed('base_storage_unloaded') end
        for index, item in ipairs(state.items) do
            if batch.ids[index] ~= 0 and not owned(actor, item) then
                local okay, why = SC.BaseWork.withdrawFromStorage(actor, workState, storage, container, item, {
                    validate = function() return current(job, actor) and batch.phase == 'take'
                        and marked(item, job, batch, index) and batch.washed[index] ~= true
                        and stockAllowed(item, actor, job) end,
                })
                if not okay then return failed(why) end
                if why ~= 'base_supply_taken' then return true, why end
            end
        end
        batch.phase, batch.index = 'wash', 1; changed()
    end
    local activity = state.activity
    if activity then
        if owner == 'owned' then
            if SC.NativeActions.isWorkActive(actor) then return true, 'washing_bandages' end
            local finished, why = SC.NativeActions.finishWork(actor)
            if not finished then return true, why end
        end
        if not activity.nativeCompleted and not batch.washed[batch.index] then
            return false, 'dressing_wash_uncertain', true
        end
        state.activity = nil
        changed()
    end
    if batch.phase == 'wash' then
        while batch.index <= #batch.ids and (batch.washed[batch.index] or batch.ids[batch.index] == 0) do
            batch.index = batch.index + 1; changed()
        end
        if batch.index > #batch.ids then batch.phase, batch.index = 'deposit', 1; changed() end
    end
    if batch.phase == 'wash' then
        if SC.NativeActions.pacingStatus and SC.NativeActions.pacingStatus(actor) then return true, 'settling_after_action' end
        if not semiSafe(actor, context) then return false, 'unsafe_area', true end
        local source, why = W.findWater(actor, state)
        if not source then return why == 'dressing_water_scanning', why, why ~= 'dressing_water_scanning' end
        local access, targets = U().directInteractionAccess(actor, source)
        if access ~= true then
            if not targets or #targets == 0 or not SC.Navigation.requestAny then return false, 'no_water_for_bandages', true end
            local accepted, reason = SC.Navigation.requestAny(actor, targets, 'walk', { action = 'move_to_water_source',
                object = source, workCampOnly = true, workReach = true, arrivalDistance = 0.35 })
            return accepted == true, reason
        end
        local item = state.items[batch.index]
        local act, makeReason = SC.BandageWash.makeActivity(actor, item,
            { object = source, square = U().squareOf(source), claim = W.claim(actor, job) })
        if not act then return false, makeReason or 'dressing_wash_uncertain', true end
        local prepared, prepReason = SC.NativeCareActions.prepare(actor, act)
        if not prepared then return false, prepReason, true end
        local started, startReason = SC.NativeActions.startDowntimeAction(actor, act, function()
            return current(job, actor) and campWater(source, SC.BaseLife.active())
                and U().directInteractionAccess(actor, source) == true
                and semiSafe(actor, context)
        end)
        if not started then return false, startReason, true end
        state.activity = act
        return true, 'washing_bandages'
    end
    if batch.phase == 'deposit' then
        for index, item in ipairs(state.items) do
            if batch.ids[index] ~= 0 then
                local storage, container = medicalDestination(actor, item)
                if not storage then return false, 'dressing_storage_missing', true end
                local done, why = SC.BaseWork.depositToStorage(actor, workState, storage, container, item,
                    { storageCategory = 'medical' })
                if not done then return failed(why) end
                if why ~= 'base_supply_returned' then return true, why end
                if not U().inventoryContains(container, item) then return false, 'dressing_wash_uncertain', true end
                settled(item, job, batch, index)
            end
        end
        job.target.dressingBatch, runtime[job] = nil, nil
        changed()
        return true, 'dressings_washed', false, true
    end
    return false, 'dressing_wash_uncertain', true
end
function W.cancel(actor, job)
    local batch = receipt(job)
    if not batch then return true end
    if type(batch) ~= 'table' then return false, 'dressing_wash_uncertain' end
    local state = runtime[job] or {}; runtime[job] = state
    if not actor or batch.owner ~= U().idOf(actor) then return false, 'dressing_wash_uncertain' end
    local owner = nativeOwner(actor, state)
    if owner == 'foreign' then return false, 'dressing_native_owner_busy' end
    if owner == 'owned' and not SC.NativeActions.cancelWork(actor, 'dressing_wash_cancelled') then
        return false, 'dressing_wash_uncertain'
    end
    local restored, why = restoreItems(actor, state, job)
    if restored ~= true then return false, why end
    state.activity = nil
    if batch.phase == 'washing' then
        local index = batch.index
        local input = state.items[index]
        -- Leave any remaining original where the game put it. Never infer
        -- the replacement from a matching type or attempt the wash again.
        if input and identity(input) == batch.ids[index] then clearMarker(input, job) end
        batch.ids[index], batch.types[index], batch.washed[index] = 0, '', false
        batch.phase = 'returning'
        changed()
        if SC.Diagnostics and SC.Diagnostics.report then
            SC.Diagnostics.report('dressing_wash', batch.owner, 'unverified wash retired', job.id)
        end
    end
    if batch.phase ~= 'returning' then batch.phase = 'returning'; changed() end
    local source = SC.BaseLife.storage(batch.sourceId)
    local sourceContainer = source and SC.BaseLife.resolveContainer(source)
    for index, item in ipairs(state.items) do
        if batch.ids[index] ~= 0 then
            local storage, container = source, sourceContainer
            if batch.washed[index] then storage, container = medicalDestination(actor, item) end
            if not storage or not container then return false, 'dressing_storage_missing' end
            if not U().inventoryContains(container, item) then
                if not owned(actor, item) then return false, 'dressing_wash_uncertain' end
                local done, reason
                if batch.washed[index] then
                    if storage.category ~= 'medical' then return false, 'dressing_storage_missing' end
                    done, reason = SC.BaseWork.restoreDepositToStorage(actor, storage, container, item)
                else done, reason = SC.BaseWork.restoreToStorage(actor, storage, container, item) end
                if not done then return false, reason end
            end
            if not U().inventoryContains(container, item) then return false, 'dressing_wash_uncertain' end
            settled(item, job, batch, index)
        end
    end
    job.target.dressingBatch, runtime[job] = nil, nil
    if job.assignedId == batch.owner then job.assignedId = nil end
    changed()
    return true, 'dressings_returned'
end
function W.reconcileExpiredJob(job, ownerId)
    local batch = receipt(job)
    if not batch then return true, 'expired_dressing_job_settled' end
    if type(batch) ~= 'table' or batch.owner ~= ownerId then return false, 'dressing_wash_uncertain' end
    if SC.BaseWork.workerUnregistered(ownerId) == true then
        -- Death/removal ends the worker affinity, not native item existence.
        -- Old markers become stale once this receipt no longer names them.
        job.target.dressingBatch, job.assignedId, runtime[job] = nil, nil, nil
        changed()
        return true, 'expired_job_worker_gone'
    end
    local actor = U().resolveActor(ownerId)
    if not actor then return false, 'expired_job_actor_missing' end
    if SC.NativeActions.isWorkActive(actor) then return false, 'expired_job_native_active' end
    local route = SC.Navigation and SC.Navigation.peek and SC.Navigation.peek(actor)
    if route and route.goalSquare then return false, 'expired_job_navigation_active' end
    return W.cancel(actor, job)
end
function W.cancelActor(actor)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        local batch = receipt(job)
        if type(batch) == 'table' and batch.owner == U().idOf(actor) then
            local okay, why = W.cancel(actor, job)
            if not okay then return false, why end
        end
    end
    return true
end
function W.reset()
    runtime, waterScans = setmetatable({}, { __mode = 'k' }), setmetatable({}, { __mode = 'k' })
end
return W
