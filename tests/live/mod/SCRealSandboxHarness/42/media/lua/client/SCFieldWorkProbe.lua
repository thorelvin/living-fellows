-- SPDX-License-Identifier: MIT
-- Disposable cloned-save proof of a native, no-car tree trip.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCFieldWorkProbe = Probe

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...) return object[method](object, ...) end, ...)
    return okay and value or nil
end
local function position(value)
    local x, y, z = call(value, "getX"), call(value, "getY"), call(value, "getZ")
    return tonumber(x), tonumber(y), tonumber(z) or 0
end
local function safeSquare(SC, x, y, z)
    local square = SC.GameplayUtil.gridSquare(x, y, z)
    return square and SC.GameplayUtil.isSquareFree(square)
        and SC.GameplayUtil.safehouseBlocker(square) ~= true and square or nil
end
local function baseOwned(SC, square)
    return SC.BaseLife.isInside(square, "area") == true
        or SC.BaseLife.isInside(square, "lumber") == true
        or SC.BaseLife.isInside(square, "farm") == true
end
local function adjacent(SC, x, y, z)
    local options = {}
    for _, offset in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
        local square = safeSquare(SC, x + offset[1], y + offset[2], z)
        if square then options[#options + 1] = square end
    end
    return options
end
local function treeAt(SC, x, y, z)
    local square = SC.GameplayUtil.gridSquare(x, y, z)
    if not square or baseOwned(SC, square) then return nil end
    local tree = call(square, "getTree")
    return tree and (tonumber(call(tree, "getObjectIndex")) or -1) >= 0
        and (tonumber(call(tree, "getSize")) or 2) >= 2 and tree or nil
end
local function chooseTree(SC, player)
    local px, py, pz = position(player)
    if not px then return nil end
    px, py, pz = math.floor(px), math.floor(py), math.floor(pz)
    for radius = 3, 40 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                local x, y = px + dx, py + dy
                local tree = treeAt(SC, x, y, pz)
                local stands = tree and adjacent(SC, x, y, pz) or {}
                if #stands >= 2 then
                    return { x = x, y = y, z = pz, tree = tree,
                        playerSquare = stands[1], workerSquare = stands[2] }
                end
            end
        end end
    end
    return nil
end
local function standingCount(SC, center)
    local count = 0
    for dx = -8, 8 do for dy = -8, 8 do
        if dx * dx + dy * dy <= 64 and treeAt(SC,
            center.x + dx, center.y + dy, center.z) then count = count + 1 end
    end end
    return count
end
local function woodCount(SC, actor)
    local count = 0
    for _, item in ipairs(SC.GameplayUtil.inventoryItems(actor:getInventory(), 512)) do
        local kind = SC.GameplayUtil.itemType(item)
        if kind == "Base.Log" or kind == "Base.TreeBranch"
            or kind == "Base.Twigs" then count = count + 1 end
    end
    return count
end
local function clearZombies(SC, center)
    local list = call(getCell(), "getZombieList")
    local size = math.min(1024, tonumber(call(list, "size")) or 0)
    local removed = 0
    for index = size - 1, 0, -1 do
        local zombie = call(list, "get", index)
        local x, y, z = position(zombie)
        if x and math.floor(z) == center.z
            and (x - center.x)^2 + (y - center.y)^2 <= 25 * 25 then
            pcall(function()
                zombie:setTarget(nil)
                zombie:removeFromWorld()
                zombie:removeFromSquare()
            end)
            removed = removed + 1
        end
    end
    return removed
end
function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "field_work_setup" then
        if current - H.phaseStartedAt < 6000 then return end
        local worker
        for _, record in ipairs(SC.Registry.records() or {}) do
            if record.actor and record.recruited == true
                and call(record.actor, "isDead") ~= true then
                worker = record
                break
            end
        end
        if not worker then
            result("SKIP", "field_work_worker", "cloned save has no recruited companion")
            setPhase("finish", current)
            return
        end
        local site = chooseTree(SC, H.player)
        if not site then
            result("SKIP", "field_work_tree", "no loaded standing tree outside base")
            setPhase("finish", current)
            return
        end
        H.fieldWork = { worker = worker, site = site }
        clearZombies(SC, site)
        H.player:teleportTo(site.playerSquare:getX() + 0.5,
            site.playerSquare:getY() + 0.5, site.z)
        local placed, reason = H.placeCombatActor(worker.actor, {
            x = site.workerSquare:getX() + 0.5,
            y = site.workerSquare:getY() + 0.5, z = site.z })
        if not check("field_work_worker_staged", placed == true,
            tostring(reason)) then setPhase("finish", current) return end
        local ordered, orderReason = SC.Commands.issue(worker.id, "follow", nil,
            H.player)
        if not check("field_work_follow", ordered == true,
            tostring(orderReason)) then setPhase("finish", current) return end
        if type(worker.actor.setMaxWeightBase) == "function" then
            worker.actor:setMaxWeightBase(200)
            worker.actor:setMaxWeight(200)
        end
        local axe = call(worker.actor:getInventory(), "AddItem", "Base.Axe")
        if not check("field_work_axe", axe ~= nil
            and SC.GameplayUtil.itemHasTag(axe, "CHOP_TREE"),
            tostring(axe)) then setPhase("finish", current) return end
        H.fieldWork.initialWood = woodCount(SC, worker.actor)
        H.fieldWork.initialTrees = standingCount(SC, site)
        setPhase("field_work_stage", current)
        return
    end
    local work = H.fieldWork
    if H.phase == "field_work_stage" then
        if current - H.phaseStartedAt < 2000 then return end
        SC.FieldWork.restore(nil)
        local started, reason = SC.FieldWork.start("chop", {
            x = work.site.x, y = work.site.y, z = work.site.z }, H.player)
        if not check("field_work_start", started == true
            and (SC.FieldWork.status() or {}).carId == nil,
            tostring(reason)) then setPhase("finish", current) return end
        result("PASS", "field_work_fixture",
            "trees=" .. tostring(work.initialTrees)
                .. " zombies_cleared=true no_car=true")
        setPhase("field_work_native", current)
        return
    end
    if H.phase == "field_work_native" then
        local status = SC.FieldWork.status() or {}
        local currentWood = woodCount(SC, work.worker.actor)
        local currentTrees = standingCount(SC, work.site)
        if current - (work.lastLogAt or 0) > 7000 then
            result("PASS", "field_work_progress",
                "phase=" .. tostring(status.phase)
                    .. " completed=" .. tostring(status.completed)
                    .. " trees=" .. tostring(currentTrees)
                    .. " wood=" .. tostring(currentWood)
                    .. " blocker=" .. tostring(status.blocker))
            work.lastLogAt = current
        end
        if status.phase == "stopped" or status.phase == "paused" then
            check("field_work_no_blocker", false, tostring(status.blocker))
            setPhase("finish", current)
            return
        end
        if (status.completed or 0) >= 1
            and currentTrees < work.initialTrees
            and currentWood > work.initialWood then
            result("PASS", "field_work_native_tree_and_cargo",
                "trees=" .. tostring(work.initialTrees) .. "->"
                    .. tostring(currentTrees) .. " wood="
                    .. tostring(work.initialWood) .. "->" .. tostring(currentWood))
            SC.FieldWork.stop("live_probe_complete")
            setPhase("finish", current)
            return
        end
        if current - H.phaseStartedAt > 120000 then
            check("field_work_native_timeout", false,
                "phase=" .. tostring(status.phase)
                    .. " completed=" .. tostring(status.completed)
                    .. " trees=" .. tostring(currentTrees)
                    .. " wood=" .. tostring(currentWood)
                    .. " blocker=" .. tostring(status.blocker))
            SC.FieldWork.stop("live_probe_timeout")
            setPhase("finish", current)
        end
    end
end
