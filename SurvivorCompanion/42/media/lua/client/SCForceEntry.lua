-- SPDX-License-Identifier: MIT
-- On-demand forcing: native outcomes, exact tool loans and no update service.
require "SCGameplayUtil"
require "SCForceEntryState"
local SC = SurvivorCompanion
SC.ForceEntry = SC.ForceEntry or {}
local F = SC.ForceEntry
local MARKER = "LF_ForceEntryTool"
local PORTAL = "LF_ForceEntryAttempt"
local claims = setmetatable({}, { __mode = "k" })
local runtimes = setmetatable({}, { __mode = "k" })
local function U() return SC.GameplayUtil end
local function v(o, m, ...) return (U().call(o, m, ...)) end
local function now() return U().nowMs() end
local function data(o) return U().modData(o) end
local function changed()
    if SC.BaseLife and SC.BaseLife.noteWorkOwnershipMutation then SC.BaseLife.noteWorkOwnershipMutation() end
end
local function marker(item)
    local d = item and data(item)
    return d and type(d[MARKER]) == "table" and d[MARKER] or nil
end
local function runtime(actor)
    local r = runtimes[actor]
    if not r then r = {} runtimes[actor] = r end
    return r
end
local function owned(actor, item)
    local container = v(item, "getContainer")
    for _ = 1, 6 do
        if container == U().inventory(actor) then return true end
        local holder = v(container, "getContainingItem")
        if not holder then return false end
        container = v(holder, "getContainer")
    end
    return false
end
local function findItem(actor, predicate)
    local root = U().inventory(actor)
    local item = v(root, "getFirstEvalRecurse", predicate)
    if item then return item end
    for _, value in ipairs(U().inventoryItems(root, 128)) do
        if predicate(value) then return value end
    end
end
local function byId(actor, id)
    if type(id) ~= "string" then return nil end
    return findItem(actor, function(item) return U().itemStableId(item, false) == id end)
end
local function inCamp(actor)
    return SC.BaseLife and SC.BaseLife.active() ~= nil
        and SC.BaseLife.withinWorkReach(actor) == true
end
local function safe(actor, fallback)
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(U().idOf(actor))
    local snapshot = SC.Senses and SC.Senses.cached and SC.Senses.cached(actor, record and record.runtime)
        or fallback
    return snapshot and (tonumber(snapshot.immediateCount) or 0) == 0
        and (tonumber(snapshot.pressure) or 0) < 2.5
        and not (SC.NativeActions and SC.NativeActions.isDraggingCorpse(actor))
end
local function crowbar(item)
    return item ~= nil and ItemTag and ItemTag.CROWBAR
        and v(item, "hasTag", ItemTag.CROWBAR) == true and v(item, "isBroken") ~= true
end
local function clearMarker(item)
    local d = item and data(item)
    if d then d[MARKER] = nil changed() end
end

function F.protected(item)
    local m = marker(item)
    if not m then return false end
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(m.actorId)
    if record and record.actor and owned(record.actor, item) then
        local r = runtime(record.actor)
        r.pending = true r.returnRetryAt = math.max(r.returnRetryAt or 0, tonumber(m.retryAt) or 0)
    end
    -- A cancelled withdrawal may still be on its original shelf. Release only
    -- after proving that location; a missing/detached item is never replaced.
    if m.phase == "claimed" and (tonumber(m.untilMs) or math.huge) < now()
        and SC.BaseLife and m.sourceId then
        local row = SC.BaseLife.storage(m.sourceId)
        local container = row and SC.BaseLife.resolveContainer(row)
        if container and U().inventoryContains(container, item) then clearMarker(item) return false end
    end
    return true
end

function F.tool(actor)
    return findItem(actor, function(item)
        if not crowbar(item) then return false end
        local m = marker(item)
        if m then return m.actorId == U().idOf(actor) and owned(actor, item) end
        return not (SC.WorkTransport and SC.WorkTransport.isCargoProtected(item, actor, "force_open"))
            and not (SC.PersonalItems and SC.PersonalItems.isProtected(item, actor, "force_open"))
    end)
end

function F.eligible(object, actor, allowUnlocked)
    if not object or not U().instanceOf(object, "IForceablePortal") then return false, "force_open_unsupported" end
    local invalid, known = U().call(object, "isNotValidForForcing")
    local index = tonumber(v(object, "getObjectIndex"))
    if not known or invalid ~= false or not index or index < 0 or not U().loadedSquare(object) then
        return false, "force_open_not_forceable"
    end
    if not allowUnlocked and v(object, "isLocked") ~= true then return false, "force_open_not_locked" end
    if actor and not U().sameFloor(actor, object) then return false, "force_open_wrong_floor" end
    if SC.Oddballs and SC.Oddballs.sealedDoorGroup then
        local okay, group = pcall(SC.Oddballs.sealedDoorGroup, object, actor)
        if not okay or group then return false, "force_open_protected" end
    end
    return true
end

function F.canBorrow(actor) return inCamp(actor) == true end

function F.pendingReturn(actor)
    local r = runtimes[actor]
    return r ~= nil and r.pending == true and (r.returnRetryAt or 0) <= now()
        and inCamp(actor) == true
end

function F.failed(actor, object)
    local d = object and data(object)
    local attempt = d and d[PORTAL]
    return type(attempt) == "table" and attempt.actorId == U().idOf(actor)
        and attempt.phase ~= "succeeded"
end

function F.copy(value)
    return SC.ForceEntryState.copy(value)
end

local function restoreHands(actor, item, m)
    if v(actor, "isDead") == true then return end
    local primary, secondary = v(actor, "getPrimaryHandItem"), v(actor, "getSecondaryHandItem")
    if primary == item then v(actor, "setPrimaryHandItem", byId(actor, m.primaryId)) end
    if secondary == item then v(actor, "setSecondaryHandItem", byId(actor, m.secondaryId)) end
    if not m.sourceId and m.bagId and v(item, "getContainer") == U().inventory(actor) then
        local bag = byId(actor, m.bagId)
        local destination = bag and v(bag, "getInventory")
        if destination and U().containerHasRoom(destination, actor, item) then
            U().transferItemVerified(U().inventory(actor), destination, item)
        end
    end
end

function F.cancel(actor, reason)
    local kind = SC.NativeActions and SC.NativeActions.workKind(actor)
    if kind == "force_open" or kind == "force_tool_transfer" then
        local ok, why = SC.NativeActions.cancelWork(actor, reason or "force_open_cancelled")
        if ok ~= true then return false, why end
    end
    local r = runtimes[actor]
    if r and r.object and claims[r.object] and claims[r.object].actor == actor then claims[r.object] = nil end
    local item = findItem(actor, function(candidate)
        local m = marker(candidate)
        return m and m.actorId == U().idOf(actor)
    end)
    if item then runtime(actor).pending = true restoreHands(actor, item, marker(item)) end
    return true
end

-- Called only by the owning order or normal safe logistics. A blocked return
-- leaves the original tool protected and waits three minutes before checking.
function F.returnPending(actor, snapshot)
    local r = runtimes[actor]
    if not r or r.pending ~= true then return false end
    if safe(actor, snapshot) ~= true then return false, "force_tool_return_pending" end
    local kind = SC.NativeActions and SC.NativeActions.workKind(actor)
    if kind == "force_tool_transfer" then
        if SC.NativeActions.isWorkActive(actor) then return true, "force_tool_returning" end
        local settled, why = SC.NativeActions.finishWork(actor)
        if settled ~= true then return true, why end
    elseif kind ~= nil then return false, "force_tool_actor_busy" end
    local item = findItem(actor, function(candidate)
        local m = marker(candidate)
        return m and m.actorId == U().idOf(actor)
    end)
    if not item then r.pending, r.returnRetryAt = nil, nil return false end
    local m = marker(item)
    restoreHands(actor, item, m)
    if not m.sourceId then clearMarker(item) r.pending = nil return false, "force_tool_restored" end
    if not inCamp(actor) or (tonumber(m.retryAt) or 0) > now() then return false, "force_tool_return_pending" end
    local function defer()
        m.retryAt = now() + 180000 r.returnRetryAt = m.retryAt r.returnAt = nil
        return false, "force_tool_return_pending"
    end
    local row = SC.BaseLife.storage(m.sourceId)
    local container, object
    if row then container, object = SC.BaseLife.resolveContainer(row) end
    if not container or not object or not SC.BaseLife.storageAcceptsDeposit(row, container)
        or U().containerHasRoom(container, actor, item) ~= true then
        return defer()
    end
    local access, targets = U().directInteractionAccess(actor, object, { snapshot = snapshot })
    if access ~= true then
        if not targets or #targets == 0 then return defer() end
        local r = runtime(actor)
        r.returnAt = r.returnAt or now()
        if now() - r.returnAt > 30000 then
            return defer()
        end
        local accepted, why = SC.Navigation.requestAny(actor, targets, "walk", {
            action = "return_force_tool", snapshot = snapshot, requireSameSquare = true, arrivalDistance = .35,
        })
        if accepted ~= true then return defer() end
        return accepted, why
    end
    runtime(actor).returnAt = nil
    local source = v(item, "getContainer")
    local accepted, why = SC.NativeActions.startForceToolTransfer(actor, item, source, container, function()
        return marker(item) == m and m.actorId == U().idOf(actor) and owned(actor, item)
            and SC.BaseLife.storage(m.sourceId) == row
            and SC.BaseLife.storageAcceptsDeposit(row, container)
    end, function() clearMarker(item) end)
    if accepted ~= true then return defer() end
    return accepted, why
end

local function sourceFor(r, container)
    for _ = 1, 6 do
        local row = r.storages[container]
        if row then return row end
        local holder = v(container, "getContainingItem")
        if not holder then return nil end
        container = v(holder, "getContainer")
    end
end

local function borrow(actor, state, ctx, r)
    if not r.storages then
        r.storages = {}
        for _, row in ipairs(SC.BaseLife.storageRows(nil, true)) do
            local container = SC.BaseLife.resolveContainer(row)
            if container then r.storages[container] = row end
        end
    end
    return SC.Encounter.takePlayerSupply(actor, "force_crowbar", function(item)
        local row = sourceFor(r, v(item, "getContainer"))
        local weight, capacity = U().projectedCarryLoad(actor, false)
        return crowbar(item) and row ~= nil and SC.BaseLife.withdrawable(row)
            and not F.protected(item) and weight + U().itemWeight(item) <= capacity
    end, {
        snapshot = ctx.snapshot, origin = actor, campFloors = true, completeSearch = true,
        revalidatePredicate = true,
        beforeTransfer = function(item, source)
            local row = sourceFor(r, source)
            if not ctx.current() or not row or not SC.BaseLife.withdrawable(row)
                or SC.BaseLife.storage(row.id) ~= row or F.protected(item) then return false end
            local id = U().itemStableId(item, true)
            if type(id) ~= "string" then return false end
            state.toolId, state.sourceId = id, row.id
            data(item)[MARKER] = { actorId = U().idOf(actor), itemId = id, sourceId = row.id,
                useId = state.useId, phase = "claimed", untilMs = now() + 30000 }
            r.pending = true
            changed() ctx.persist()
            return true
        end,
    })
end

function F.step(actor, descriptor, state, ctx)
    local object = ctx.object or SC.BaseLife.resolveObject(descriptor)
    local r, current = runtime(actor), now()
    ctx.persist = ctx.persist or function() end
    r.snapshot = ctx.snapshot
    local function persist() if ctx.persist then ctx.persist() end end
    local function stop(reason)
        local stopped, why = F.cancel(actor, reason)
        if stopped ~= true then return true, why, false end
        state.result, state.stage = reason, "cleanup" persist()
        return true, reason, false
    end
    if not state.useId then
        r.storages, r.tool = nil, nil
        state.useId = tostring(ctx.useId) state.stage = "supplies"
        state.deadlineAt = current + 60000 persist()
    end
    if not object or v(actor, "isDead") == true or not ctx.current() then
        F.cancel(actor, "force_open_changed") return false, "force_open_changed", true
    end
    if safe(actor, ctx.snapshot) ~= true then
        local stopped, why = F.cancel(actor, "force_open_unsafe")
        if stopped ~= true then return true, why, false end
        state.result, state.stage = "force_open_unsafe", "cleanup" persist()
    end
    if state.stage == "cleanup" then
        local handled, why = F.returnPending(actor, ctx.snapshot)
        if handled then return true, why, false end
        if claims[object] and claims[object].actor == actor then claims[object] = nil end
        return true, state.result or "force_open_failed", true
    end
    if not state.attempted and current >= (state.deadlineAt or current + 1) then
        F.cancel(actor, "force_open_approach_timeout")
        state.result, state.stage = "force_open_approach_timeout", "cleanup" persist()
        return true, state.result, false
    end
    local activeKind = SC.NativeActions.workKind(actor)
    if state.attempted then
        if claims[object] and claims[object].actor == actor then claims[object].untilMs = current + 15000 end
        if activeKind == "force_open" and SC.NativeActions.isWorkActive(actor)
            and current < (state.deadlineAt or current) then return true, "force_open_working", false end
        local unlocked = v(object, "isLocked") == false
        local settled, why = F.cancel(actor, "force_open_settling")
        if settled ~= true then return true, why, false end
        state.result = unlocked and "force_open_succeeded" or "force_open_failed"
        local d = data(object)
        if d[PORTAL] and d[PORTAL].useId == state.useId then
            d[PORTAL].phase = unlocked and "succeeded" or "failed"
        end
        state.stage = "cleanup" persist()
        return true, state.result, false
    end
    if F.eligible(object, actor) ~= true then return stop("force_open_not_forceable") end
    local tool = r.tool
    if not tool or not owned(actor, tool) or not crowbar(tool) then tool = F.tool(actor) r.tool = tool end
    if not tool then
        if ctx.borrow ~= true or not inCamp(actor) then return stop("force_crowbar_missing") end
        local status, why = borrow(actor, state, ctx, r)
        if status == "taken" or status == "in_progress" then return true, "force_crowbar_finding", false end
        return stop(why == "camp_supply_missing" and "force_crowbar_missing" or why or "force_crowbar_missing")
    end
    local claim = claims[object]
    if claim and claim.actor ~= actor and claim.untilMs > current then return stop("force_open_busy") end
    claims[object] = { actor = actor, untilMs = current + 15000 }
    r.object = object
    local square, why = SC.Navigation.barricadeWorkSquare(actor, object, U().squareOf(object), nil, {})
    if not square then return stop(why or "force_open_no_approach") end
    if not U().sameSquare(U().squareOf(actor), square) then
        local accepted, reason = SC.Navigation.request(actor, square, "walk", {
            action = "approach_force_open", snapshot = ctx.snapshot, requireSameSquare = true, arrivalDistance = .35,
        })
        if accepted ~= true then return stop(reason or "force_open_no_approach") end
        return true, reason, false
    end
    if activeKind ~= nil then return true, "force_open_action_wait", false end
    local m = marker(tool) or { actorId = U().idOf(actor), itemId = U().itemStableId(tool, true) }
    local holder = v(v(tool, "getContainer"), "getContainingItem")
    m.primaryId = U().itemStableId(v(actor, "getPrimaryHandItem"), true)
    m.secondaryId = U().itemStableId(v(actor, "getSecondaryHandItem"), true)
    m.bagId = holder and U().itemStableId(holder, true) or nil
    m.useId, m.phase = state.useId, "carried"
    r.pending = true
    data(tool)[MARKER] = m changed()
    state.attempted, state.stage, state.deadlineAt = true, "forcing", current + 60000
    data(object)[PORTAL] = { useId = state.useId, missionId = ctx.missionId,
        actorId = U().idOf(actor), phase = "started" }
    persist()
    local accepted, reason = U().move(actor, "walk", {
        action = "force_open", object = object, tool = tool, transactional = true,
        validate = function()
            return ctx.current() and claims[object] and claims[object].actor == actor
                and owned(actor, tool) and crowbar(tool) and F.eligible(object, actor, true) == true
                and SC.BaseLife.resolveObject(descriptor) == object
                and safe(actor, r.snapshot) == true
        end,
    })
    if accepted ~= true then
        state.result, state.stage = reason or "force_open_failed", "cleanup" persist()
    end
    return accepted, reason or "force_open_working", false
end

function F.attemptedFor(object, missionId)
    local attempt = object and data(object)[PORTAL]
    return type(attempt) == "table" and attempt.missionId == missionId
end

-- Bounded, retained discovery only after ordinary expedition entry failed.
-- Never force an upper-floor window into an unverified roof route.
function F.findSitePortal(actor, siteId, missionId, scan)
    local x, y, z = U().position(actor)
    if not x then return nil, true end
    if not scan.width then
        local bounds = scan.bounds or {}
        scan.x, scan.y, scan.z = math.max(math.floor(x)-14, (bounds.x or math.floor(x)-13)-1),
            math.max(math.floor(y)-14, (bounds.y or math.floor(y)-13)-1), z
        scan.width = math.max(0, math.min(math.floor(x)+14, (bounds.x2 or math.floor(x)+13)+1)-scan.x+1)
        scan.height = math.max(0, math.min(math.floor(y)+14, (bounds.y2 or math.floor(y)+13)+1)-scan.y+1)
        scan.index = 0
    end
    local total = math.min(1024, scan.width * scan.height)
    local count = 0
    while scan.index < total and count < 32 do
        local index = scan.index scan.index = index + 1 count = count + 1
        local square = U().gridSquare(scan.x + index % scan.width,
            scan.y + math.floor(index / scan.width), scan.z)
        local objects = v(square, "getObjects")
        for i = 0, math.min(U().listSize(objects), 32) - 1 do
            local object = U().listGet(objects, i)
            if F.eligible(object, actor) and not F.attemptedFor(object, missionId)
                and (z == 0 or not U().instanceOf(object, "IsoWindow")) then
                local other = v(object, "getOppositeSquare")
                local a, b, c = U().position(square)
                local d, e, f = U().position(other)
                local places = SC.ExpeditionPlaces
                local inside = places and a and places.siteContainsPoint(siteId, a, b, c) == true
                local otherInside = places and d and places.siteContainsPoint(siteId, d, e, f) == true
                if a and d and inside ~= otherInside and other then
                    local score = U().distanceSq(actor, square)
                        + (U().instanceOf(object, "IsoWindow") and 10000 or 0)
                    if not scan.bestScore or score < scan.bestScore then scan.best, scan.bestScore = object, score end
                end
            end
        end
    end
    local done = scan.index >= total
    return done and scan.best or nil, done
end

function F.copyTrip(value)
    if type(value) ~= "table" or type(value.operatorId) ~= "string" or type(value.target) ~= "table" then return nil end
    local target = {}
    for _, key in ipairs({ "x", "y", "z", "objectIndex", "objectId", "objectSignature" }) do
        local v = value.target[key]
        if type(v) == "number" or type(v) == "string" and #v <= 512 then target[key] = v end
    end
    if not target.x or not target.y or not target.z or not target.objectId then return nil end
    return { operatorId = value.operatorId, target = target, state = F.copy(value.state) or {},
        startedAt = tonumber(value.startedAt),
        failed = value.failed == true, reason = type(value.reason) == "string" and string.sub(value.reason, 1, 160) or nil }
end

return F
