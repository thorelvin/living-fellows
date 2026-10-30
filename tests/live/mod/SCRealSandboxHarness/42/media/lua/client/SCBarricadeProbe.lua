-- SPDX-License-Identifier: MIT
-- Isolated cloned-save probe for "Maintain this barricade". Seed it with a save
-- that has a barricade maintenance target. A job saved in the old shape, with no
-- object identity, must repair itself on load. The materials go into camp storage,
-- so a real worker has to fetch them and board the real window with native timed
-- actions until no further plank fits.
local Probe = {}
local LOAD_DEADLINE_MS = 60000
local WORK_DEADLINE_MS = 420000
local probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function boards(object)
    local planks, full = 0, false
    for _, method in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
        local barricade = call(object, method)
        if barricade then
            planks = math.max(planks, tonumber(call(barricade, "getNumPlanks")) or 0)
            -- Not through call(): its "ok and value or nil" turns this false into nil.
            local ok, room = pcall(function() return barricade:canAddPlank() end)
            if ok and room == false then full = true end
        end
    end
    return planks, full
end

local function openJob(base, targetId)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "barricade" and type(job.target) == "table"
            and job.target.maintenanceId == targetId then return job end
    end
    return nil
end

-- The nearest camp storage a worker may take from, within the supply search radius.
local function stockCamp(SC, base, target)
    local best, bestDistance, container
    for _, storage in ipairs(base.storages or {}) do
        local box = SC.BaseLife.withdrawable(storage) and SC.BaseLife.resolveContainer(storage) or nil
        local distance = math.abs(storage.x - target.x) + math.abs(storage.y - target.y)
        if box and storage.z == target.z and distance <= 24
            and (not best or distance < bestDistance) then
            best, bestDistance, container = storage, distance, box
        end
    end
    if not best then return nil end
    probe.stockedContainer = container
    for kind, count in pairs({ ["Base.Hammer"] = 1, ["Base.Plank"] = 8, ["Base.Nails"] = 16 }) do
        for _ = 1, count do container:AddItem(kind) end
    end
    return best, bestDistance
end

local function carried(SC, actor)
    local inventory = SC.GameplayUtil.inventory(actor)
    return "hammer=" .. tostring(call(inventory, "getCountTypeRecurse", "Base.Hammer"))
        .. " plank=" .. tostring(call(inventory, "getCountTypeRecurse", "Base.Plank"))
        .. " nails=" .. tostring(call(inventory, "getCountTypeRecurse", "Base.Nails"))
end

-- Where every hammer in camp storage is when the search says there is none.
local function dumpStorages(SC, actor)
    local U = SC.GameplayUtil
    local index = 0
    for _, storage in ipairs(SC.BaseLife.active().storages or {}) do
        local container = SC.BaseLife.resolveContainer(storage)
        local items = container and call(container, "getItems") or nil
        local total = items and U.listSize(items) or -1
        local position, hammer = -1, nil
        for i = 0, total - 1 do
            local item = U.listGet(items, i)
            if U.itemType(item) == "Base.Hammer" then position, hammer = i, item break end
        end
        if hammer or container == probe.stockedContainer then
            local access = SC.Encounter.baseStorageAccess(container, nil, true)
            index = index + 1
            print("[SCBarricadeProbe] storage " .. tostring(storage.id)
                .. " category=" .. tostring(storage.category) .. " at " .. tostring(storage.x)
                .. ":" .. tostring(storage.y) .. " items=" .. tostring(total)
                .. " hammerAt=" .. tostring(position) .. " access=" .. tostring(access)
                .. " available=" .. tostring(SC.BaseLife.availableCount(storage, "Base.Hammer"))
                .. " tagged=" .. tostring(hammer and U.itemHasTag(hammer, "Hammer"))
                .. " native=" .. tostring(hammer and call(hammer, "hasTag", ItemTag.HAMMER))
                .. " protected=" .. tostring(hammer and SC.PersonalItems.isProtected(hammer, actor, "camp_supply"))
                .. " broken=" .. tostring(hammer and call(hammer, "isBroken")))
        end
    end
    print("[SCBarricadeProbe] storages holding a hammer or the stock: " .. tostring(index))
end

-- A refused supply check only reaches the job as "build_supplies_unavailable".
local function traceSupplies(SC)
    local original = SC.Logistics.prepareBuild
    SC.Logistics.prepareBuild = function(actor, ...)
        local ready, handled, reason = original(actor, ...)
        if not ready then
            local line = SC.GameplayUtil.idOf(actor) .. " ready=" .. tostring(ready)
                .. " handled=" .. tostring(handled) .. " reason=" .. tostring(reason)
                .. " " .. carried(SC, actor)
            if line ~= probe.lastSupply then
                probe.lastSupply = line
                print("[SCBarricadeProbe] prepareBuild " .. line)
                if not probe.dumped then
                    probe.dumped = true
                    pcall(dumpStorages, SC, actor)
                end
            end
        end
        return ready, handled, reason
    end
end

-- What stands on each side of the window, as the game and as Navigation see it.
local function dumpSides(SC, object, actor)
    local U = SC.GameplayUtil
    local square = U.squareOf(object)
    local x, y, z = U.position(square)
    local north = call(object, "getNorth")
    local sides = { same = square,
        opposite = U.gridSquare(x + (north and 0 or -1), y + (north and -1 or 0), z) }
    for side, tile in pairs(sides) do
        local clear, why = SC.Navigation.standingSquareClear(actor, tile)
        print("[SCBarricadeProbe] side " .. side .. " " .. tostring(call(tile, "getX")) .. ":"
            .. tostring(call(tile, "getY")) .. " clear=" .. tostring(clear) .. " why=" .. tostring(why)
            .. " canStand=" .. tostring(call(tile, "canStand"))
            .. " solid=" .. tostring(call(tile, "isSolid")) .. " solidTrans=" .. tostring(call(tile, "isSolidTrans"))
            .. " room=" .. tostring(call(tile, "getRoom") ~= nil)
            .. " admitted=" .. tostring(SC.Navigation._workSquareAdmitted(tile, { workCampOnly = true, workReach = true })))
        U.squareObjects(tile, function(thing)
            local sprite = call(thing, "getSprite")
            local properties = call(sprite, "getProperties")
            print("[SCBarricadeProbe]   object " .. tostring(call(sprite, "getName"))
                .. " name=" .. tostring(call(thing, "getObjectName"))
                .. " moveable=" .. tostring(call(thing, "isMoveAble"))
                .. " surface=" .. tostring(call(thing, "getSurfaceOffset"))
                .. " propSurface=" .. tostring(call(properties, "get", "Surface"))
                .. " container=" .. tostring(call(thing, "getContainer") ~= nil))
        end, 16)
    end
end

-- The reason a refused barricade action gives never reaches the job.
local function traceMove(SC)
    local U = SC.GameplayUtil
    local original = U.move
    U.move = function(actor, mode, intent, ...)
        local accepted, reason = original(actor, mode, intent, ...)
        if type(intent) == "table" and intent.action == "barricade" then
            local queue = ISTimedActionQueue.getTimedActionQueue(actor)
            print("[SCBarricadeProbe] move barricade accepted=" .. tostring(accepted)
                .. " reason=" .. tostring(reason)
                .. " at " .. string.format("%.2f:%.2f", tonumber(call(actor, "getX")) or -1, tonumber(call(actor, "getY")) or -1)
                .. " queued=" .. tostring(queue and queue.current ~= nil) .. "/" .. tostring(queue and queue.queue and #queue.queue)
                .. " primary=" .. tostring(call(call(actor, "getPrimaryHandItem"), "getFullType"))
                .. " secondary=" .. tostring(call(call(actor, "getSecondaryHandItem"), "getFullType")))
        end
        return accepted, reason
    end
end

local function setup(H, SC, check, result, setPhase, current)
    probe.startedAt = probe.startedAt or current
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    local target
    for _, row in ipairs(base and base.maintenanceTargets or {}) do
        if row.kind == "barricade" then target = row break end
    end
    if not target then
        if current - probe.startedAt < LOAD_DEADLINE_MS then return end
        result("FAIL", "barricade_fixture", "the seed save has no barricade maintenance target")
        setPhase("finish", current)
        return
    end
    local object = SC.BaseLife.resolveObject(target)
    local residents = SC.BaseLife.dutyResidentIds()
    local actors = {}
    for _, id in ipairs(residents) do
        local actor = SC.GameplayUtil.resolveActor(id)
        if actor then actors[#actors + 1] = actor end
    end
    if not object or #actors == 0 then
        if current - probe.startedAt < LOAD_DEADLINE_MS then return end
        result("FAIL", "barricade_fixture", "object=" .. tostring(object ~= nil)
            .. " residents=" .. tostring(#residents) .. " loaded=" .. tostring(#actors))
        setPhase("finish", current)
        return
    end
    local job = openJob(base, target.id)
    if job then
        check("barricade_saved_job_repaired", job.target.objectId == target.objectId
                and (job.attempts or 0) == 0 and job.blocker == nil,
            "job=" .. tostring(job.id) .. " objectId=" .. tostring(job.target.objectId)
                .. " attempts=" .. tostring(job.attempts) .. " blocker=" .. tostring(job.blocker))
    end
    check("barricade_target_resolved", true, "objectId=" .. tostring(target.objectId)
        .. " at " .. tostring(target.x) .. ":" .. tostring(target.y)
        .. " signature=" .. tostring(target.objectSignature))
    local planks, full = boards(object)
    check("barricade_starts_unfinished", not full, "planks=" .. tostring(planks))
    traceSupplies(SC)
    traceMove(SC)
    pcall(dumpSides, SC, object, actors[1])
    local storage, distance = stockCamp(SC, base, target)
    if not storage then
        result("FAIL", "barricade_fixture", "no withdrawable camp storage within 24 tiles of the window")
        setPhase("finish", current)
        return
    end
    print("[SCBarricadeProbe] stocked " .. tostring(storage.id) .. " category="
        .. tostring(storage.category) .. " at " .. tostring(storage.x) .. ":" .. tostring(storage.y)
        .. " distance=" .. tostring(distance))
    probe.base, probe.target, probe.object, probe.lastLine = base, target, object, nil
    probe.runStartedAt, probe.firstPlankAt, probe.nextLogAt = current, nil, current
    setPhase("barricade_probe_run", current)
end

-- Where the worker is and what it thinks it is doing, for a job that goes quiet.
local function traceWorker(SC, job, current)
    if not job or not job.reservedBy or current < (probe.nextTraceAt or 0) then return end
    probe.nextTraceAt = current + 5000
    local actor = SC.GameplayUtil.resolveActor(job.reservedBy)
    if not actor then return end
    local decision = SC.Decision.peek(actor) or {}
    local navigation = SC.Navigation.peek(actor) or {}
    local goal = navigation.goalSquare
    local commands = SC.Commands.peek(actor) or {}
    print("[SCBarricadeProbe] worker " .. tostring(job.reservedBy)
        .. " at " .. string.format("%.1f:%.1f", tonumber(call(actor, "getX")) or -1, tonumber(call(actor, "getY")) or -1)
        .. " order=" .. tostring(commands.order) .. " decision=" .. tostring(decision.current)
        .. " intent=" .. tostring(decision.intent)
        .. " navGoal=" .. tostring(goal and call(goal, "getX")) .. ":" .. tostring(goal and call(goal, "getY"))
        .. " navAction=" .. tostring(navigation.intent and navigation.intent.action or navigation.action)
        .. " assignedAgo=" .. tostring(decision.workAssignedAt and SC.GameplayUtil.nowMs() - decision.workAssignedAt)
        .. " " .. carried(SC, actor))
end

local function run(H, SC, check, result, setPhase, current)
    local job = openJob(probe.base, probe.target.id)
    traceWorker(SC, job, current)
    local planks, full = boards(probe.object)
    if planks > 0 and not probe.firstPlankAt then
        probe.firstPlankAt = current
        check("barricade_first_plank", true, "after " .. tostring(current - probe.runStartedAt)
            .. " ms worker=" .. tostring(job and job.reservedBy))
    end
    local line = "job=" .. tostring(job and job.id) .. " state=" .. tostring(job and job.state)
        .. " worker=" .. tostring(job and job.reservedBy)
        .. " blocker=" .. tostring(job and job.blocker)
        .. " attempts=" .. tostring(job and job.attempts) .. " planks=" .. tostring(planks)
        .. " worker_has=" .. (job and job.reservedBy
            and carried(SC, SC.GameplayUtil.resolveActor(job.reservedBy)) or "-")
    if line ~= probe.lastLine and current >= probe.nextLogAt then
        print("[SCBarricadeProbe] " .. line)
        probe.lastLine, probe.nextLogAt = line, current + 2000
    end
    if full and job == nil then
        check("barricade_job_finished_full", true, "planks=" .. tostring(planks) .. " after "
            .. tostring(current - probe.runStartedAt) .. " ms")
        setPhase("finish", current)
        return
    end
    if current - probe.runStartedAt > WORK_DEADLINE_MS then
        result("FAIL", "barricade_job_finished_full", "after "
            .. tostring(WORK_DEADLINE_MS) .. " ms: " .. line)
        setPhase("finish", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "barricade_probe_setup" then return setup(H, SC, check, result, setPhase, current) end
    if H.phase == "barricade_probe_run" then return run(H, SC, check, result, setPhase, current) end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBarricadeProbe = Probe
return Probe
