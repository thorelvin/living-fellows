-- SPDX-License-Identifier: MIT
-- Exercise native filled buckets, warmed camp inventory discovery and the
-- regular cleaning job in a disposable Project Zomboid world.
local SC = LivingFellows
local state = { phase = "menu", notes = {}, modals = {} }

local function write(name, value)
    local file = assert(getFileWriter("pzo-stored-mixture-" .. name .. ".txt", true, false))
    file:write(value .. "\n")
    file:close()
end

local function note(key, value)
    state.notes[#state.notes + 1] = key .. "=" .. tostring(value)
end

local function phase(name)
    state.phase, state.at = name, getTimestampMs()
    write("progress", name .. "\n" .. table.concat(state.notes, "\n"))
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. state.phase .. "\nreason=" .. tostring(reason)
        .. "\n" .. table.concat(state.notes, "\n"))
    state.phase = "done"
end

local function stocked(container, fullType, volume, fraction, water, cleaner)
    local item = assert(container:AddItem(fullType))
    local fc = assert(item:getFluidContainer())
    fc:Empty()
    if water then fc:addFluid(water, volume * (1 - fraction)) end
    fc:addFluid(cleaner, volume * fraction)
    item:syncItemFields()
    return item
end

local function twoBuckets(volume)
    return stocked(state.container, "Base.BucketEmpty", volume, 0.05, Fluid.Water, Fluid.Bleach),
        stocked(state.container, "Base.BucketWood", volume, 0.05, Fluid.TaintedWater, Fluid.CleaningLiquid)
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister("decision")
    state.player = assert(getSpecificPlayer(0))
    state.player:teleportTo(6428.5, 5449.5, 0)
    phase("load")
end)

local function step()
    local C = SC.CleaningSupplies
    if state.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not state.modals[modal] then
            state.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    local age = getTimestampMs() - state.at
    assert(age < 110000, "phase timed out: " .. tostring(state.work))
    if state.phase == "load" then
        if age < 12000 or not SC.Persistence.restoreStatus() then return end
        SC.BaseLife.reset()
        local centre = assert(getCell():getGridSquare(6428, 5449, 0))
        assert(SC.BaseLife.create(centre, "Cleaning supplies"))
        local base = SC.BaseLife.active()
        base.settings.autoMaintenance, base.settings.routines, base.settings.workload = false, false, "essential"
        local square = assert(getCell():getGridSquare(6433, 5452, 0))
        local crate = IsoThumpable.new(getCell(), square, "carpentry_01_16", false, {})
        crate:setIsContainer(true)
        state.container = ItemContainer.new("crate", square, crate)
        state.container:setCapacity(100)
        state.container:setExplored(true)
        crate:setContainer(state.container)
        square:AddSpecialObject(crate)
        square:RecalcAllWithNeighbours(true)
        local marked, storage = SC.BaseLife.registerStorage(crate, "tools")
        assert(marked, tostring(storage))
        local spawn = assert(getCell():getGridSquare(6432, 5452, 0))
        state.ticket = assert(SC.Actor.beginSpawn(spawn, { recruited = true,
            identity = { forename = "Robin", surname = "Cleaner", gender = "woman", outfit = "Generic01" } }))
        phase("spawn")
    elseif state.phase == "spawn" then
        local actor, reason = SC.Actor.pollSpawn(state.ticket)
        assert(actor or reason == "spawn_pending", tostring(reason))
        if not actor then return end
        state.actor, state.id = actor, assert(SC.GameplayUtil.idOf(actor))
        assert(SC.BaseLife.assign(state.id, "maintainer", true))
        assert(SC.Commands.issue(state.id, "base_duty", {}, state.player))
        assert(actor:getInventory():AddItem("Base.Mop"))
        state.bleach = stocked(state.container, "Base.Bleach", 1, 1, nil, Fluid.Bleach)
        state.bucket1, state.bucket2 = twoBuckets(2)
        phase("cold")
    elseif state.phase == "cold" then
        local plan, why = C.plan(state.actor)
        if why == "cleaning_supplies_scanning" then return end
        assert(plan and plan.mode == "mixed", "a normal stored bucket: " .. tostring(plan and plan.mode or why))
        note("cold_plan", plan.mode)
        local load, capacity = SC.GameplayUtil.carryLoad(state.actor)
        note("base_carry", load .. "/" .. capacity)
        state.bucket1:getFluidContainer():adjustAmount(10)
        state.bucket2:getFluidContainer():adjustAmount(10)
        state.bucket1:syncItemFields()
        state.bucket2:syncItemFields()
        phase("full")
    elseif state.phase == "full" then
        local inspect = assert(C.inspect(state.bucket1))
        local plan, why = C.plan(state.actor)
        if why == "cleaning_supplies_scanning" then return end
        note("full_plan", plan and plan.mode or why)
        note("full_bucket", inspect.amount .. "/" .. state.bucket1:getUnequippedWeight())
        state.container:Remove(state.bucket1)
        state.container:Remove(state.bucket2)
        C.reset()
        phase("empty_shelf")
    elseif state.phase == "empty_shelf" then
        local plan, why = C.plan(state.actor)
        if why == "cleaning_supplies_scanning" then return end
        assert(plan and plan.mode == "undiluted", tostring(plan and plan.mode or why))
        state.bucket1, state.bucket2 = twoBuckets(2)
        phase("restocked_shelf")
    elseif state.phase == "restocked_shelf" then
        local plan, why = C.plan(state.actor)
        if why == "cleaning_supplies_scanning" then return end
        note("restocked_plan", plan and plan.mode or why)
        assert(plan and plan.mode == "mixed"
            and (plan.liquid.item == state.bucket1 or plan.liquid.item == state.bucket2),
            "recently stored mixtures must be preferred")
        state.selected = plan.liquid.item
        state.other = state.selected == state.bucket1 and state.bucket2 or state.bucket1
        state.amount = C.inspect(state.selected).amount
        state.bleachAmount = C.inspect(state.bleach).amount
        state.target = assert(state.actor:getSquare())
        addBloodSplat(state.target, 20)
        assert(state.target:haveStains())
        local accepted, job = SC.BaseLife.requestCleaning(state.target)
        assert(accepted, tostring(job))
        job.assignedId = state.id
        state.job = job.id
        phase("clean")
    elseif state.phase == "clean" then
        SC.ActionSupervisor.update(state.actor)
        if SC.NativeActions.pacingStatus(state.actor) then return end
        local okay, reason = SC.BaseWork.update(state.actor, state.player,
            { snapshot = { threatCount = 0, immediateCount = 0 } })
        state.work = tostring(okay) .. "/" .. tostring(reason)
        local job = SC.BaseLife.job(state.job)
        if job then
            assert(job.state ~= "blocked", tostring(job.blocker) .. "/" .. state.work)
            if job.target.cleanPreparation then
                assert(job.target.cleanPreparation.mode == "mixed", "prepared bucket was bypassed")
            end
            return
        end
        assert(not state.target:haveStains(), "native clean did not clear the stains")
        local spent = state.amount - C.inspect(state.selected).amount
        assert(math.abs(spent - C.dose()) < 0.002, "selected bucket did not pay a single dose")
        assert(math.abs(C.inspect(state.other).amount - 2) < 0.002, "alternate mixture changed")
        assert(math.abs(C.inspect(state.bleach).amount - state.bleachAmount) < 0.002, "straight cleaner used")
        assert(state.selected:getContainer() == state.container and not state.selected:getModData()[C.MARKERS.liquid],
            "exact bucket was not repaid")
        note("dose_spent", spent)
        note("bucket_returned", state.selected:getID())
        finish("PASS", "cleaned with one prepared bucket and returned it to the same marked shelf")
    end
end

Events.OnRenderTick.Add(function()
    if state.phase == "done" then return end
    local okay, reason = pcall(step)
    if not okay then finish("FAIL", reason) end
end)
