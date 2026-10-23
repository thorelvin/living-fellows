-- SPDX-License-Identifier: MIT
-- Disposable real-engine intake and trash proof. Never shipped with the mod.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCFloorSortProbe = Probe

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...) return object[method](object, ...) end, ...)
    return okay and value or nil
end

local function candidateItem(kind, actor)
    local inventory = call(actor, "getInventory")
    for _, typeName in ipairs(kind == "trash"
        and { "Base.DirtyRag", "Base.BrokenGlass", "Base.BrokenBottle" }
        or { "Base.Hammer", "Base.Bandage", "Base.Nails", "Base.CannedBeans" }) do
        local item = call(inventory, "AddItem", typeName)
        if item then return item, typeName end
    end
    return nil
end

local function storageFor(SC, actor)
    local inventory = call(actor, "getInventory")
    for _, spec in ipairs({
        { "tools", "Base.Hammer" },
        { "medical", "Base.Bandage" },
        { "construction", "Base.Nails" },
        { "food", "Base.CannedBeans" },
    }) do
        local item = call(inventory, "AddItem", spec[2])
        if item then
            for _, storage in ipairs(SC.BaseLife.depositStorageRows(spec[1])) do
                local container = SC.BaseLife.resolveContainer(storage)
                if container and call(container, "hasRoomFor", actor, item) == true then
                    return item, storage, container
                end
            end
            call(inventory, "Remove", item)
        end
    end
    return nil
end

local function locations(SC, actor, storage)
    local utility = SC.GameplayUtil
    local function admissible(square)
        return square and utility.isSquareFree(square)
            and SC.BaseLife.isInside(square, "area") == true
            and SC.BaseLife.isInside(square, "sorting_floor") ~= true
            and SC.BaseLife.isInside(square, "trash_pile") ~= true
    end
    if storage and tonumber(storage.x) and tonumber(storage.y) then
        local nearby = {}
        for radius = 0, 3 do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = utility.gridSquare(storage.x + dx,
                            storage.y + dy, storage.z)
                        if admissible(square) then nearby[#nearby + 1] = square end
                    end
                end
            end
        end
        for _, first in ipairs(nearby) do
            local firstRoom = call(first, "getRoom")
            for _, second in ipairs(nearby) do
                if second ~= first and call(second, "getRoom") == firstRoom
                    and utility.distance(first, second) <= 1.5 then
                    return first, second
                end
            end
        end
    end
    local x, y, z = utility.position(actor)
    if not x then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local rows = {}
    for radius = 0, 10 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if admissible(square) then
                        rows[#rows + 1] = square
                        if #rows >= 2 then return rows[1], rows[2] end
                    end
                end
            end
        end
    end
    return nil
end

local function markZone(SC, kind, square)
    local started, startReason = SC.BaseLife.beginZone(kind, square)
    if not started then return nil, startReason end
    local finished, result = SC.BaseLife.finishZone(square, kind)
    if not finished then SC.BaseLife.cancelZone() return nil, result end
    return result
end

local function onGround(SC, square, item)
    local wrapper = call(item, "getWorldItem")
    return wrapper and SC.GameplayUtil.worldItemPresent(square, wrapper) == true
end

local function prepare(H, SC, check, result, setPhase, current)
    local base = SC.BaseLife.active()
    local roster = SC.Registry.snapshot() or {}
    if (not base or #roster == 0) and current - H.phaseStartedAt < 15000 then return end
    if not check("floor_sort_base", base ~= nil, base and base.name or "none") then
        setPhase("finish", current) return
    end
    local chosen, chosenId, source, trashSquare, item, storage, container
    local preferred = {}
    local roleRank = { quartermaster = 0, generalist = 1, farmer = 2,
        chef = 3, angler = 4, corpsekeeper = 10 }
    for _, record in ipairs(roster) do
        if record.recruited == true and record.actor
            and not SC.GameplayUtil.isDead(record.actor) then
            preferred[#preferred + 1] = record
        end
    end
    table.sort(preferred, function(a, b)
        local roleA = (SC.BaseLife.resident(SC.GameplayUtil.idOf(a.actor)) or {}).role
        local roleB = (SC.BaseLife.resident(SC.GameplayUtil.idOf(b.actor)) or {}).role
        return (roleRank[roleA] or 5) < (roleRank[roleB] or 5)
    end)
    for _, record in ipairs(preferred) do
        if record.recruited == true and record.actor and not SC.GameplayUtil.isDead(record.actor)
            and SC.BaseLife.isInside(record.actor, "area") == true then
            local candidate, shelf, bin = storageFor(SC, record.actor)
            local first, second = locations(SC, record.actor, shelf)
            if first and second and candidate and shelf and bin then
                chosen, chosenId, source, trashSquare = record.actor,
                    SC.GameplayUtil.idOf(record.actor), first, second
                item, storage, container = candidate, shelf, bin
                break
            end
        end
    end
    if not check("floor_sort_fixture", chosen ~= nil,
        "recruited actor, two free camp tiles and marked storage required") then
        setPhase("finish", current) return
    end
    local intake, reason = markZone(SC, "sorting_floor", source)
    if not check("floor_sort_intake_zone", intake ~= nil, tostring(reason)) then
        setPhase("finish", current) return
    end
    local pile, pileReason = markZone(SC, "trash_pile", trashSquare)
    if not check("floor_sort_trash_zone", pile ~= nil, tostring(pileReason)) then
        setPhase("finish", current) return
    end
    local garbage, garbageType = candidateItem("trash", chosen)
    if not check("floor_sort_trash_item", garbage and SC.Logistics.isTrash(garbage),
        tostring(garbageType)) then setPhase("finish", current) return end
    local sourceItem = SC.GameplayUtil.dropItem(chosen:getInventory(), source,
        item, 0.45, 0.45, 0)
    local trashItem = SC.GameplayUtil.dropItem(chosen:getInventory(), source,
        garbage, 0.55, 0.55, 0)
    if not check("floor_sort_native_drops", sourceItem and trashItem
        and onGround(SC, source, item) and onGround(SC, source, garbage),
        "two exact native items must be on intake square") then
        setPhase("finish", current) return
    end
    -- This disposable probe owns only the chosen worker's decisions. The
    -- source save has unscripted mental episodes and downtime that can hold
    -- its action supervisor longer than a short test, unrelated to intake.
    local cancelled, cancelReason = SC.BaseWork.cancel(chosen, "floor_sort_probe")
    if not check("floor_sort_worker_available", cancelled == true,
        tostring(cancelReason)) then setPhase("finish", current) return end
    local duty, dutyReason = SC.BaseLife.setDuty(chosenId, true)
    if not check("floor_sort_worker_duty", duty == true,
        tostring(dutyReason)) then setPhase("finish", current) return end
    if SC.Navigation and SC.Navigation.cancel then
        SC.Navigation.cancel(chosen, "floor_sort_probe")
    end
    local originalDecisionUpdate = SC.Decision.update
    SC.Decision.update = function(actor, ...)
        if actor == chosen then return true, "floor_sort_probe_owned" end
        return originalDecisionUpdate(actor, ...)
    end
    local queued, job = SC.BaseLife.enqueueJob({ type = "sort_floor",
        priority = 5, assignedId = chosenId,
        target = { zoneId = intake.id, x = source:getX(), y = source:getY(),
            z = source:getZ() } })
    if not check("floor_sort_job", queued == true, tostring(job)) then
        setPhase("finish", current) return
    end
    H.floorSort = { actor = chosen, source = source, trash = trashSquare,
        item = item, garbage = garbage, storage = storage,
        container = container, job = job, state = {}, stored = false,
        trashed = false, nextAt = current, lastReportAt = current,
        originalDecisionUpdate = originalDecisionUpdate }
    result("PASS", "floor_sort_fixture_detail", tostring(call(chosen, "getFullName"))
        .. " role=" .. tostring((SC.BaseLife.resident(chosenId) or {}).role)
        .. " shelf=" .. tostring(storage.category)
        .. " shelfAt=" .. tostring(storage.x) .. "," .. tostring(storage.y)
        .. " source=" .. tostring(source:getX()) .. "," .. tostring(source:getY()))
    setPhase("floor_sort_run", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "floor_sort_setup" then
        return prepare(H, SC, check, result, setPhase, current)
    end
    if H.phase ~= "floor_sort_run" then return end
    local fixture = H.floorSort
    if not fixture then setPhase("finish", current) return end
    if current - H.phaseStartedAt > 90000 then
        result("FAIL", "floor_sort_timeout", "last=" .. tostring(fixture.lastReason)
            .. " stored=" .. tostring(fixture.stored)
            .. " trashed=" .. tostring(fixture.trashed))
        SC.Decision.update = fixture.originalDecisionUpdate
        setPhase("finish", current) return
    end
    if current < fixture.nextAt then return end
    fixture.nextAt = current + 250
    local okay, handled, reason, terminal, completed = pcall(SC.FloorSort.update,
        fixture.actor, fixture.state, fixture.job)
    if not okay then
        result("FAIL", "floor_sort_runtime", tostring(handled))
        SC.Decision.update = fixture.originalDecisionUpdate
        setPhase("finish", current) return
    end
    fixture.lastReason = tostring(reason)
    if terminal == true then
        result("FAIL", "floor_sort_terminal", fixture.lastReason)
        SC.Decision.update = fixture.originalDecisionUpdate
        setPhase("finish", current) return
    end
    if current - fixture.lastReportAt >= 10000 then
        fixture.lastReportAt = current
        local x, y = SC.GameplayUtil.position(fixture.actor)
        local navigation = SC.Navigation and SC.Navigation.status
            and SC.Navigation.status(fixture.actor) or {}
        local commands = SC.Commands and SC.Commands.peek
            and SC.Commands.peek(fixture.actor) or {}
        local decision = SC.Decision and SC.Decision.peek
            and SC.Decision.peek(fixture.actor) or {}
        local token = SC.ActionSupervisor and SC.ActionSupervisor.current
            and SC.ActionSupervisor.current(fixture.actor) or {}
        result("PASS", "floor_sort_progress", "job=" .. fixture.lastReason
            .. " actor=" .. tostring(x) .. "," .. tostring(y)
            .. " cargo=" .. tostring(fixture.job.target.floorCargo ~= nil)
            .. " order=" .. tostring(commands.order)
            .. " decision=" .. tostring(decision.current)
            .. " token=" .. tostring(token.owner)
            .. " nav=" .. tostring(navigation.phase)
            .. ":" .. tostring(navigation.action)
            .. ":" .. tostring(navigation.target)
            .. ":" .. tostring(navigation.lastMovementReason)
            .. " path=" .. tostring(navigation.pathReason)
            .. " nodes=" .. tostring(navigation.expandedNodes))
    end
    fixture.stored = SC.GameplayUtil.inventoryContains(
        fixture.container, fixture.item) == true
    fixture.trashed = onGround(SC, fixture.trash, fixture.garbage)
    if fixture.stored and fixture.trashed then
        check("floor_sort_native_storage", not onGround(SC, fixture.source,
            fixture.item) and not SC.GameplayUtil.inventoryContains(
                fixture.actor:getInventory(), fixture.item),
            "exact item deposited once")
        check("floor_sort_native_trash", not onGround(SC, fixture.source,
            fixture.garbage), "trash moved to visible pile")
        SC.Decision.update = fixture.originalDecisionUpdate
        setPhase("finish", current)
    end
end

return Probe
