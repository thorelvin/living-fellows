-- SPDX-License-Identifier: MIT
-- Disposable native bed/table fixtures. No production object is removed.
local Probe = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBedExitTablesProbe = Probe
local function call(object, method, ...)
    if object == nil then return nil end
    local okay, value = pcall(function(...) return object[method](object, ...) end, ...)
    if okay then return value end
end
local function catalogue()
    local beds, manager, low = {}, SeatingManager.getInstance(), nil
    for sheet = 1, 4 do for index = 0, 127 do
        local name = "furniture_bedding_" .. string.format("%02d", sheet) .. "_" .. index
        local sprite = IsoSpriteManager.instance:getSprite(name)
        local grid = sprite and sprite:getSpriteGrid()
        if grid and grid:getWidth() * grid:getHeight() == 2 then
            local facing = manager:getFacingDirection(sprite)
            local sample = IsoObject.new(getCell(), getSpecificPlayer(0):getCurrentSquare(), name)
            local count = manager:getTilePositionCount(sample)
            local group = tostring(sprite:getProperties():get("GroupName") or "")
            if (facing == "N" or facing == "S" or facing == "E" or facing == "W")
                and (not beds[facing] or count > 0 and (beds[facing].count == 0
                    or group:lower():find("hospital", 1, true))) then
                beds[facing] = { grid = grid, facing = facing, sprite = name, count = count }
            end
        end
    end end
    for index = 0, 127 do
        local name = "furniture_tables_low_01_" .. index
        local sprite = IsoSpriteManager.instance:getSprite(name)
        if sprite and sprite:getProperties():getSurface() > 0 then low = name break end
    end
    local cases = {}
    for _, facing in ipairs({ "N", "S", "E", "W" }) do
        if beds[facing] then cases[#cases + 1] = beds[facing] end
    end
    return cases, low
end
local function contents(actor)
    local items = {}
    for _, item in ipairs(SurvivorCompanion.GameplayUtil.inventoryItemsDeep(actor:getInventory(), 512, 12)) do
        items[item] = true
    end
    return items
end
local function intact(f)
    local current = contents(f.actor)
    for item in pairs(f.items) do if not current[item] then return false end end
    for item in pairs(current) do if not f.items[item] then return false end end
    return SurvivorCompanion.Registry.byId(f.id).actor == f.actor and not f.actor:isDead()
        and f.table:getObjectIndex() >= 0
end
local function place(f)
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local case = f.cases[f.index]
    local origin, best, score = f.actor:getCurrentSquare(), nil, nil
    for dx = -12, 12 do for dy = -12, 12 do
        local x, y, z = origin:getX() + dx, origin:getY() + dy, origin:getZ()
        local tile = getCell():getGridSquare(x, y, z)
        local room, clear = tile and tile:getRoom(), tile ~= nil
        for gx = -2, case.grid:getWidth() + 1 do for gy = -2, case.grid:getHeight() + 1 do
            local square = getCell():getGridSquare(x + gx, y + gy, z)
            if not square or square:getRoom() ~= room or U.isClearActorSpawnSquare(square) ~= true then clear = false end
        end end
        if clear and (not score or dx * dx + dy * dy < score) then best, score = {x=x,y=y,z=z}, dx*dx+dy*dy end
    end end
    assert(best, "no loaded clear floor for the bed/table fixture")
    f.x, f.y, f.z = best.x, best.y, best.z
    assert(SC.Actor.recover(f.actor, getCell():getGridSquare(f.x - 1, f.y, f.z)), "fixture actor placement failed")
    f.objects = {}
    for gx = 0, case.grid:getWidth() - 1 do for gy = 0, case.grid:getHeight() - 1 do
        local tile = getCell():getGridSquare(f.x + gx, f.y + gy, f.z)
        local object = IsoObject.new(getCell(), tile, case.grid:getSprite(gx, gy):getName())
        tile:AddTileObject(object)
        f.objects[#f.objects + 1] = object
        U.invalidateSpatial(tile)
    end end
    local tx, ty = f.x, f.y
    if case.facing == "N" then ty = ty + case.grid:getHeight()
    elseif case.facing == "S" then ty = ty - 1
    elseif case.facing == "W" then tx = tx + case.grid:getWidth()
    else tx = tx - 1 end
    f.tableSquare = getCell():getGridSquare(tx, ty, f.z)
    f.table = IsoObject.new(getCell(), f.tableSquare, f.low)
    f.tableSquare:AddTileObject(f.table)
    U.invalidateSpatial(f.tableSquare)
    f.requested, f.sawGetup = nil, nil
    print("SC_REAL_SANDBOX|BED_TABLE_CASE|facing=" .. case.facing .. " bed=" .. case.sprite
        .. " table=" .. f.low .. " at=" .. tx .. "," .. ty .. "," .. f.z)
end
local function stageTableOverlap(f)
    local actor, tile, facing = f.actor, f.tableSquare, f.cases[f.index].facing
    local x, y = tile:getX() + 0.5, tile:getY() + 0.5
    if facing == "N" then y = tile:getY() + 0.05
    elseif facing == "S" then y = tile:getY() + 0.95
    elseif facing == "W" then x = tile:getX() + 0.05
    else x = tile:getX() + 0.95 end
    actor:getCurrentSquare():getMovingObjects():remove(actor)
    actor:setX(x) actor:setY(y) actor:setLastX(x) actor:setLastY(y)
    actor:setCurrent(tile) tile:getMovingObjects():add(actor)
    actor:setOnBed(false) actor:setSitOnFurnitureObject(nil)
    actor:setCollidable(true)
    SurvivorCompanion.GameplayUtil.invalidateSpatial(actor)
    f.exitState = { object = f.objects[1] }
end
function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "bed_exit_tables_setup" then
        if current - H.phaseStartedAt < 8000 then return end
        local row
        for _, record in ipairs(SC.Registry.snapshot()) do
            if record.recruited and record.actor and not record.actor:isDead() and record.actor:getCurrentSquare() then row = record break end
        end
        if not row then
            if current - H.phaseStartedAt > 22000 then check("bed_table_worker", false, "no restored living crew") setPhase("finish", current) end
            return
        end
        for _, record in ipairs(SC.Registry.snapshot()) do if record.actor then
            SC.Downtime.cancel(record.actor, "bed_table_fixture")
            SC.Decision.cancelWork(record.actor, "bed_table_fixture")
            SC.ActionSupervisor.cancel(record.actor, "bed_table_fixture", nil, true)
            SC.Commands.issue(record.id, "stay", {}, H.player)
        end end
        local decision = SC.Decision.update
        SC.Decision.update = function(actor, ...)
            if H.phase == "bed_exit_tables_run" then return true, "bed_table_fixture" end
            return decision(actor, ...)
        end
        local cases, low = catalogue()
        if not check("bed_table_catalogue", #cases == 4 and low ~= nil, "native facings=" .. #cases .. " low table=" .. tostring(low)) then setPhase("finish", current) return end
        local f = { actor = row.actor, id = row.id, items = contents(row.actor), cases = cases,
            low = low, index = 1, step = "enter", nextAt = current + 500, deadline = current + 45000 }
        H.bedTables = f
        place(f)
        if f.cases[f.index].count == 0 then stageTableOverlap(f) f.step = "table_overlap" end
        setPhase("bed_exit_tables_run", current)
        return
    end
    local f = H.bedTables
    if current < f.nextAt then return end
    f.nextAt = current + 100
    if current > f.deadline then
        check("bed_table_" .. f.index .. "_" .. f.step, false, "timeout owner=" .. tostring(call(f.actor,"getCompanionMovementOwner"))
            .. " native=" .. tostring(SCBridge.getLastFailure()) .. " context=" .. tostring(call(f.actor,"getCurrentActionContextStateName")))
        setPhase("finish", current) return
    end
    if f.step == "enter" then
        if not f.requested then f.requested = SC.GameplayUtil.move(f.actor, "walk", {action="rest_bed",object=f.objects[1]}) == true end
        if f.actor:isOnBed() and SC.NativeActions.bedStatus(f.actor) == "entered" then
            check("bed_table_" .. f.index .. "_entered", true, "native bed entry with low table present")
            SC.NativeActions.leaveSeating(f.actor)
            f.step, f.deadline = "getup", current + 16000
        end
    elseif f.step == "getup" then
        if tostring(call(f.actor,"getCurrentActionContextStateName")):lower() == "getup" then f.sawGetup = true end
        local left, why = SC.NativeActions.leaveSeating(f.actor)
        if left then
            check("bed_table_" .. f.index .. "_native_exit", f.sawGetup and intact(f) and f.actor:isCollidable(), tostring(why) .. " table intact; same actor/items")
            stageTableOverlap(f)
            f.step, f.deadline, f.nextAt = "table_overlap", current + 5000, current
        end
    elseif f.step == "table_overlap" then
        local targets, touching = SC.BedGeometry.exitTargets(f.objects[1], f.actor)
        local left, why = false, "no verified target"
        for _, target in ipairs(targets) do
            left, why = SC.Actor.recoverBedExit(f.actor, f.objects[1], target)
            if left then break end
        end
        if left then
            check("bed_table_" .. f.index .. "_overlap_exit", touching and #targets > 0 and intact(f)
                and f.actor:getCurrentSquare() ~= f.tableSquare, tostring(why) .. " table still present; targets=" .. #targets)
            for _, object in ipairs(f.objects) do local tile=object:getSquare() tile:RemoveTileObject(object) SC.GameplayUtil.invalidateSpatial(tile) end
            f.tableSquare:RemoveTileObject(f.table) SC.GameplayUtil.invalidateSpatial(f.tableSquare)
            f.index = f.index + 1
            if f.index > #f.cases then setPhase("finish", current) return end
            place(f)
            f.step, f.deadline, f.nextAt = "enter", current + 45000, current + 500
            if f.cases[f.index].count == 0 then stageTableOverlap(f) f.step = "table_overlap" end
        else
            print("SC_REAL_SANDBOX|BED_TABLE_OVERLAP|targets=" .. #targets .. " touching=" .. tostring(touching)
                .. " why=" .. tostring(why) .. " native=" .. tostring(SCBridge.getLastFailure()))
        end
    end
end
return Probe
