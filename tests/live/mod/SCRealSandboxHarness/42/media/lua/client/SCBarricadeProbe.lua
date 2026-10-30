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
    if ok then return value end
    return nil
end

local function boards(object)
    local planks, full = 0, false
    for _, method in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
        local barricade = call(object, method)
        if barricade then
            planks = math.max(planks, tonumber(call(barricade, "getNumPlanks")) or 0)
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
        local openBefore = type(intent) == "table" and intent.action == "barricade"
            and call(intent.object, "IsOpen")
        local accepted, reason = original(actor, mode, intent, ...)
        if type(intent) == "table" and intent.action == "barricade" then
            local queue = ISTimedActionQueue.getTimedActionQueue(actor)
            print("[SCBarricadeProbe] move barricade accepted=" .. tostring(accepted)
                .. " reason=" .. tostring(reason)
                .. " at " .. string.format("%.2f:%.2f", tonumber(call(actor, "getX")) or -1, tonumber(call(actor, "getY")) or -1)
                .. " openBefore=" .. tostring(openBefore)
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
    probe.hardening = H.config.barricade_hardening == "true"
    probe.matrixOnly = H.config.barricade_matrix_only == "true"
    probe.runStartedAt, probe.firstPlankAt, probe.nextLogAt = current, nil, current
    if probe.hardening then
        probe.worker = actors[1]
        probe.discovery = { zone = 1, index = 0, resumeMain = true }
        setPhase("barricade_probe_matrix_discovery", current)
    else setPhase("barricade_probe_run", current) end
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

local function inventoryReceipt(SC, actor)
    local items = SC.GameplayUtil.inventoryItemsDeep(SC.GameplayUtil.inventory(actor), 4096, 64)
    if #items >= 4096 then return nil end
    local ids = {}
    for _, item in ipairs(items) do
        ids[#ids + 1] = tostring(call(item, "getID")) .. ":" .. SC.GameplayUtil.itemType(item)
    end
    table.sort(ids)
    return table.concat(ids, ";")
end

local function failMatrix(check, setPhase, current, name, detail)
    check(name, false, detail)
    setPhase("finish", current)
end

local function freezeMatrixWorker(SC)
    local id = SC.GameplayUtil.idOf(probe.worker)
    local stopped, reason = SC.BaseLife.setDuty(id, false)
    if stopped ~= true then return false, reason end
    stopped, reason = SC.Commands.issue(id, "stay")
    if stopped ~= true then return false, reason end
    return SC.Commands.issue(id, "set_work_mode", { mode = "idle" })
end

local function facePlanks(object, side)
    local b = call(object, side == "same" and "getBarricadeOnSameSquare" or "getBarricadeOnOppositeSquare")
    return b and tonumber(call(b, "getNumPlanks")) or 0
end

-- The main scenario proves camp fetching. The matrix isolates native boarding,
-- side selection and completion from repeated trips through the busy camp.
local function stockWorker(SC, actor, plankCount, crowbar)
    local U, bag = SC.GameplayUtil, nil
    local inventory = U.inventory(actor)
    for _, item in ipairs(U.inventoryItemsDeep(inventory, 256, 16)) do
        if U.instanceOf(item, "InventoryContainer") then
            bag = call(item, "getInventory")
            if bag then break end
        end
    end
    local supplies = { ["Base.Hammer"] = 1, ["Base.Plank"] = plankCount,
        ["Base.Nails"] = plankCount * 2, ["Base.Crowbar"] = crowbar and 1 or 0 }
    for kind, count in pairs(supplies) do
        for _ = 1, count do
            local item = inventory:AddItem(kind)
            if not item then return false, "fixture_item_missing:" .. kind end
            if bag and U.containerHasRoom(bag, actor, item) then
                inventory:Remove(item)
                bag:AddItem(item)
                if call(item, "getContainer") ~= bag then return false, "fixture_bag_transfer_failed" end
            end
        end
    end
    return true
end

local function beginMatrixStep(SC, check, setPhase, current)
    local step = probe.matrix[probe.matrixIndex]
    if not step then
        check("barricade_matrix_healthy", (tonumber(call(probe.worker, "getHealth")) or 0)
            >= probe.matrixHealth - 0.01, "native worker retained health")
        setPhase("finish", current)
        return
    end
    local id = SC.GameplayUtil.idOf(probe.worker)
    local stopped, reason = freezeMatrixWorker(SC)
    if stopped ~= true then return failMatrix(check, setPhase, current, "barricade_matrix_setup", tostring(reason)) end
    step.before = facePlanks(step.object, step.side)
    step.startedAt, step.nativeSeen = current, false
    local accepted, result
    if step.command == "plan" then
        -- Planning requires a closed target. Reopen the door after the plan
        -- exists to exercise the real saved-plan/native-close recovery path.
        if step.reopenAfterPlan and call(step.object, "IsOpen") == true then
            step.object:ToggleDoor(probe.worker)
        end
        accepted, result = SC.BaseLife.enqueueBarricadePlan(step.object, step.side)
        if accepted then
            step.jobId = result.id
            result.assignedId = id
            if step.reopenAfterPlan then
                step.object:ToggleDoor(probe.worker)
                if call(step.object, "IsOpen") ~= true then
                    return failMatrix(check, setPhase, current, "barricade_matrix_setup", "planned door did not reopen")
                end
            end
            SC.BaseLife.assign(id, "maintainer", true)
            accepted, result = SC.Commands.issue(id, "base_duty")
        end
    else
        local supplied, why = stockWorker(SC, probe.worker,
            step.command == "barricade" and 1 or 0, step.command == "remove_barricade")
        if not supplied then return failMatrix(check, setPhase, current, "barricade_matrix_supply", tostring(why)) end
        accepted, result = SC.Commands.issue(id, step.command,
            { object = step.object, barricadeSide = step.side })
    end
    if accepted ~= true then return failMatrix(check, setPhase, current,
        "barricade_matrix_order", step.name .. ":" .. tostring(result)) end
    print("[SCBarricadeProbe] matrix begin " .. step.name .. " before=" .. step.before)
    setPhase("barricade_probe_matrix_run", current)
end

local function discoverMatrix(SC, check, setPhase, current)
    local scan, U = probe.discovery, SC.GameplayUtil
    for _ = 1, 128 do
        local zone = probe.base.zones[scan.zone]
        if not zone then
            if not scan.west or not scan.door then return failMatrix(check, setPhase, current,
                "barricade_matrix_fixture", "west=" .. tostring(scan.west ~= nil)
                    .. " door=" .. tostring(scan.door ~= nil) .. " candidates=" .. tostring(scan.candidates or 0)) end
            probe.matrix = {
                { name = "west_plan_same", command = "plan", object = scan.west, side = "same", goal = 4 },
                { name = "door_plan_opposite", command = "plan", object = scan.door,
                    side = "opposite", goal = 4, reopenAfterPlan = true },
                { name = "west_one_shot_opposite", command = "barricade", object = scan.west, side = "opposite", goal = 1 },
                { name = "west_remove_opposite", command = "remove_barricade", object = scan.west, side = "opposite", goal = 0 },
            }
            probe.matrixIndex = 1
            if scan.resumeMain and not probe.matrixOnly then
                return setPhase("barricade_probe_run", current)
            end
            if probe.matrixOnly then
                local disabled, why = SC.BaseLife.setMaintenanceTargetEnabled(probe.target.id, false)
                if not disabled then return failMatrix(check, setPhase, current, "barricade_matrix_setup", tostring(why)) end
                local frozen, reason = freezeMatrixWorker(SC)
                if not frozen then return failMatrix(check, setPhase, current, "barricade_matrix_setup", tostring(reason)) end
                probe.matrixHealth = tonumber(call(probe.worker, "getHealth")) or 0
            end
            return beginMatrixStep(SC, check, setPhase, current)
        end
        if zone.kind ~= "area" then scan.zone, scan.index = scan.zone + 1, 0 else
            local width = zone.x2 - zone.x1 + 1
            if scan.index >= width * (zone.y2 - zone.y1 + 1) then
                scan.zone, scan.index = scan.zone + 1, 0
            else
                local offset = scan.index scan.index = offset + 1
                local square = U.gridSquare(zone.x1 + offset % width, zone.y1 + math.floor(offset / width), zone.z)
                U.squareObjects(square, function(object)
                    local window = not scan.west and U.instanceOf(object, "IsoWindow") and call(object, "getNorth") == false
                    local door = not scan.door and U.instanceOf(object, "IsoDoor")
                    if (window or door) and object ~= probe.object
                        and (door or call(object, "IsOpen") == false)
                        and call(object, "isBarricadeAllowed") == true
                        and facePlanks(object, "same") == 0 and facePlanks(object, "opposite") == 0 then
                        local options = { workCampOnly = true, workReach = true }
                        local a, whyA = SC.Navigation.barricadeWorkSquare(probe.worker, object, square, "same", options)
                        local b, whyB = SC.Navigation.barricadeWorkSquare(probe.worker, object, square, "opposite", options)
                        scan.candidates = (scan.candidates or 0) + 1
                        if scan.candidates <= 8 then
                            print("[SCBarricadeProbe] matrix candidate " .. (window and "west" or "door")
                                .. " at " .. tostring(call(square, "getX")) .. ":" .. tostring(call(square, "getY"))
                                .. " same=" .. tostring(a ~= nil) .. ":" .. tostring(whyA)
                                .. " opposite=" .. tostring(b ~= nil) .. ":" .. tostring(whyB)
                                .. " open=" .. tostring(call(object, "IsOpen")))
                        end
                        if a and b then if window then scan.west = object else scan.door = object end end
                    end
                end, 32)
            end
        end
    end
end

local function runMatrix(SC, check, setPhase, current)
    local step = probe.matrix[probe.matrixIndex]
    local md = SC.GameplayUtil.modData(probe.worker) or {}
    if step.jobId then
        traceWorker(SC, SC.BaseLife.job(step.jobId), current)
        if not step.kitAdded and md.SC_Order == "work" and md.SC_WorkBaseJobId == step.jobId then
            local supplied, why = stockWorker(SC, probe.worker, 4, false)
            if not supplied then return failMatrix(check, setPhase, current, "barricade_matrix_supply", tostring(why)) end
            step.kitAdded = true
        end
    end
    local kind = SC.NativeActions.workKind(probe.worker)
    if kind == (step.command == "remove_barricade" and "remove_barricade" or "barricade") then step.nativeSeen = true end
    local count = facePlanks(step.object, step.side)
    if count == step.goal and md.SC_Order ~= "work"
        and not SC.NativeActions.isWorkActive(probe.worker)
        and (not step.jobId or SC.BaseLife.job(step.jobId) == nil) then
        check("barricade_matrix_" .. step.name, step.nativeSeen and step.before ~= count,
            "before=" .. step.before .. " after=" .. count .. " native=" .. tostring(step.nativeSeen))
        probe.matrixIndex = probe.matrixIndex + 1
        return beginMatrixStep(SC, check, setPhase, current)
    end
    if current - step.startedAt > 240000 then return failMatrix(check, setPhase, current,
        "barricade_matrix_" .. step.name, "timeout count=" .. count .. " order=" .. tostring(md.SC_Order)) end
end

local function run(H, SC, check, result, setPhase, current)
    local job = openJob(probe.base, probe.target.id)
    if job and job.reservedBy then probe.worker = SC.GameplayUtil.resolveActor(job.reservedBy) end
    traceWorker(SC, job, current)
    local planks, full = boards(probe.object)
    if probe.hardening and not probe.cancelAt and probe.worker
        and SC.NativeActions.workKind(probe.worker) == "barricade"
        and SC.NativeActions.isWorkActive(probe.worker) then
        local receipt = inventoryReceipt(SC, probe.worker)
        local stopped, reason = SC.BaseLife.setMaintenanceTargetEnabled(probe.target.id, false)
        local md = SC.GameplayUtil.modData(probe.worker) or {}
        if not check("barricade_cancel_active", stopped == true and openJob(probe.base, probe.target.id) == nil
            and md.SC_WorkBaseJobId == nil and md.SC_Order ~= "work"
            and not SC.NativeActions.isWorkActive(probe.worker), tostring(reason)) then
            setPhase("finish", current) return
        end
        check("barricade_cancel_inventory", receipt ~= nil and inventoryReceipt(SC, probe.worker) == receipt,
            "all exact carried items survive native cancellation")
        probe.cancelAt, probe.cancelPlanks = current, planks
        return
    end
    if probe.cancelAt and not probe.resumed then
        if current - probe.cancelAt < 2000 then return end
        check("barricade_cancel_no_late_plank", planks == probe.cancelPlanks, "disabled target stayed unchanged")
        local removed, reason = SC.BaseLife.removeMaintenanceTarget(probe.target.id)
        if not check("barricade_remove_mark", removed == true, tostring(reason)) then setPhase("finish", current) return end
        local registered, target = SC.BaseLife.registerMaintenanceTarget(probe.object, "barricade")
        if not check("barricade_resume_mark", registered == true, tostring(target)) then setPhase("finish", current) return end
        probe.target, probe.resumed = target, true
        return
    end
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
        if probe.hardening then
            local md = probe.worker and SC.GameplayUtil.modData(probe.worker) or {}
            if not probe.worker or SC.NativeActions.isWorkActive(probe.worker)
                or md.SC_Order == "work" then return end
        end
        check("barricade_job_finished_full", true, "planks=" .. tostring(planks) .. " after "
            .. tostring(current - probe.runStartedAt) .. " ms")
        if probe.hardening then
            check("barricade_cancel_exercised", probe.resumed == true, "active cancellation and resumption occurred")
            local disabled, reason = SC.BaseLife.setMaintenanceTargetEnabled(probe.target.id, false)
            if not disabled then return failMatrix(check, setPhase, current, "barricade_matrix_setup", tostring(reason)) end
            local frozen, why = freezeMatrixWorker(SC)
            if not frozen then return failMatrix(check, setPhase, current, "barricade_matrix_setup", tostring(why)) end
            probe.matrixHealth = tonumber(call(probe.worker, "getHealth")) or 0
            beginMatrixStep(SC, check, setPhase, current)
        else setPhase("finish", current) end
        return
    end
    -- Hardening also cancels/recreates the mark and waits for the ordinary
    -- scheduler. Leave room for a real 90-second work timeout and auto retry;
    -- this does not change that production timeout or the runner's outer bound.
    local deadline = probe.hardening and 720000 or WORK_DEADLINE_MS
    if current - probe.runStartedAt > deadline then
        result("FAIL", "barricade_job_finished_full", "after "
            .. tostring(deadline) .. " ms: " .. line)
        setPhase("finish", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "barricade_probe_setup" then return setup(H, SC, check, result, setPhase, current) end
    if H.phase == "barricade_probe_run" then return run(H, SC, check, result, setPhase, current) end
    if H.phase == "barricade_probe_matrix_discovery" then return discoverMatrix(SC, check, setPhase, current) end
    if H.phase == "barricade_probe_matrix_run" then return runMatrix(SC, check, setPhase, current) end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBarricadeProbe = Probe
return Probe
