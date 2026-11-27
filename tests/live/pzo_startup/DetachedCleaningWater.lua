-- SPDX-License-Identifier: MIT
-- Run in a disposable world. The console also records whether the host logged
-- Java coordinate exceptions even when the Lua call returned normally.
local SC = LivingFellows
local state = { phase = "menu", modals = {}, notes = {} }

local function write(name, text)
    local f = assert(getFileWriter("pzo-sink-" .. name .. ".txt", true, false))
    f:write(text .. "\n")
    f:close()
end

local function phase(name)
    state.phase, state.deadline = name, getTimestampMs() + 120000
    print("SC_SINK_PHASE " .. name)
    write("progress", name)
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. state.phase .. "\nreason="
        .. tostring(reason) .. "\n" .. table.concat(state.notes, "\n"))
    state.phase = "done"
end

local function spawnSquare(player)
    local origin = player:getSquare()
    for r = 1, 12 do
        for x = -r, r do
            for y = -r, r do
                local sq = getCell():getGridSquare(origin:getX()+x, origin:getY()+y, origin:getZ())
                if sq and sq ~= origin and sq:isFree(false)
                    and SC.GameplayUtil.isClearActorSpawnSquare(sq) then return sq end
            end
        end
    end
    error("no nearby square for companion")
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start") end)
local function step()
    if state.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not state.modals[modal] then
            state.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    assert(getTimestampMs() < state.deadline, "timed out during " .. state.phase)
    local C = SC.CleaningSupplies
    if state.phase == "start" then
        local player = getSpecificPlayer(0)
        if not player or not player:getSquare() or not SC.Persistence.restoreStatus() then return end
        SC.BaseLife.reset()
        assert(SC.BaseLife.create(player:getSquare(), "Cleaning crew"))
        state.ticket = assert(SC.Actor.beginSpawn(spawnSquare(player), {recruited=true,
            identity={forename="Robin",surname="Cleaner",gender="woman",outfit="Generic01"}}))
        phase("spawn")
    elseif state.phase == "spawn" then
        local actor, why = SC.Actor.pollSpawn(state.ticket)
        assert(actor or why == "spawn_pending", tostring(why))
        if not actor then return end
        state.actor = actor
        local inv = assert(actor:getInventory())
        inv:AddItem("Base.Mop")
        assert(inv:AddItem("Base.BucketEmpty"):getFluidContainer()):Empty()
        local bleach = assert(inv:AddItem("Base.Bleach"):getFluidContainer())
        bleach:Empty()
        bleach:addFluid(Fluid.Bleach,1)
        C.reset()
        phase("select")
    elseif state.phase == "select" then
        local plan, why = C.plan(state.actor)
        if not plan and why == "cleaning_supplies_scanning" then return end
        assert(plan and plan.mode == "prepare" and plan.water and plan.water.object,
            "no live water fixture chosen: " .. tostring(plan and plan.mode or why))
        local source = plan.water.object
        local square = assert(source:getSquare())
        state.notes[#state.notes+1] = "source=" .. tostring(source:getSpriteName()) .. " @ "
            .. square:getX() .. "," .. square:getY() .. "," .. square:getZ()
        assert(C.sourceUsable(source), "mounted fixture has water")
        state.source = source
        square:RemoveTileObject(source)
        source:setSquare(nil)
        assert(source:getSquare() == nil, "removed fixture still has a square")
        phase("cached")
    elseif state.phase == "cached" then
        local plan, why = C.plan(state.actor)
        if not plan and why == "cleaning_supplies_scanning" then return end
        assert(plan and (plan.mode == "undiluted" or plan.water and plan.water.object ~= state.source),
            "removed fixture must give way to the next supply: " .. tostring(why))
        state.notes[#state.notes+1] = "next_plan=" .. plan.mode
        phase("cold")
    elseif state.phase == "cold" then
        C.reset()
        assert(not C.sourceUsable(state.source), "detached fixture is unusable")
        phase("complete")
        finish("PASS","cached plan recovered and cold check rejected the detached fixture")
    end
end

Events.OnRenderTick.Add(function()
    if state.phase == "done" then return end
    local ok, reason = pcall(step)
    if not ok then finish("FAIL",reason) end
end)
