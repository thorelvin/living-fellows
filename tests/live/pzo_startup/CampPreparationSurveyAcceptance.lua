-- SPDX-License-Identifier: MIT
-- Measure public expedition packing calls against the same loaded stock in
-- each release. Only the synchronous survey is timed, before withdrawal.
local SC = SurvivorCompanion
local state = { phase = "menu", modals = {}, trials = {} }

local function write(name, message)
    local file = assert(getFileWriter("pzo-shelf-survey-" .. name .. ".txt", true, false))
    file:write(message .. "\n")
    file:close()
end

local function phase(name)
    state.phase, state.started = name, getTimestampMs()
    write("progress", name)
end

local function setup()
    local square = assert(getCell():getGridSquare(6432,5449,0))
    local crateSquare = assert(getCell():getGridSquare(6433,5449,0))
    SC.BaseLife.reset()
    assert(SC.BaseLife.create(square,"Departure survey"))
    local crate = IsoThumpable.new(getCell(),crateSquare,"carpentry_01_16",false,{})
    crate:setIsContainer(true)
    crate:setContainer(ItemContainer.new("crate",crateSquare,crate))
    crateSquare:AddSpecialObject(crate)
    crateSquare:RecalcAllWithNeighbours(true)
    state.stock = crate:getContainer()
    state.stock:setCapacity(1000)
    state.stock:setExplored(true)
    assert(SC.BaseLife.registerStorage(crate,"tools"))
    for i=1,192 do assert(state.stock:AddItem("Base.Paperclip")) end
    state.axe = assert(state.stock:AddItem("Base.HandAxe"))
    state.ticket = assert(SC.Actor.beginSpawn(square,{recruited=true,
        identity={forename="Robin",surname="Packer",gender="woman",outfit="Generic01"}}))
    phase("spawn")
end

local function startTrial()
    local trial = {frames=0, peak=0, countCalls=0, checkedAxe=false}
    state.trials[#state.trials+1] = trial
    state.request = {key="native-shelf-survey-" .. #state.trials, atCamp=true, allowBagUpgrade=false,
        cargoRaw=1, requiredTools={{itemType="Base.HandAxe"}}}
    phase("survey")
end

local function releaseHooks()
    if state.exact then SC.BaseLife.availableCountExact=state.exact end
end

local function finish(result, why)
    releaseHooks()
    local lines = {"result=" .. result, "phase=" .. state.phase, "reason=" .. tostring(why)}
    for i,trial in ipairs(state.trials) do
        lines[#lines+1] = string.format("trial_%d=frames:%d peak_ms:%.3f unrelated_counts:%d",
            i,trial.frames,trial.peak,trial.countCalls)
    end
    write("result",table.concat(lines,"\n"))
    state.phase="done"
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister("decision")
    getSpecificPlayer(0):teleportTo(6428.5,5449.5,0)
    phase("load")
end)

local function step()
    if state.phase=="menu" then
        local modal=MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not state.modals[modal] then
            state.modals[modal]=true
            modal:onClick(modal.yes)
        end
        return
    end
    assert(getTimestampMs()-state.started<90000,"native survey timed out")
    if state.phase=="load" then
        if getTimestampMs()-state.started >= 10000 and SC.Persistence.restoreStatus() then setup() end
    elseif state.phase=="spawn" then
        local actor, why=SC.Actor.pollSpawn(state.ticket)
        assert(actor or why=="spawn_pending",tostring(why))
        if not actor then return end
        state.actor=actor
        assert(actor:getInventory():getCountType("Base.HandAxe")==0)
        state.exact=SC.BaseLife.availableCountExact
        SC.BaseLife.availableCountExact=function(storage,kind)
            local trial=state.trials[#state.trials]
            if kind=="Base.Paperclip" then trial.countCalls=trial.countCalls+1
            elseif kind=="Base.HandAxe" then trial.checkedAxe=true end
            return state.exact(storage,kind)
        end
        startTrial()
    elseif state.phase=="survey" then
        local trial=state.trials[#state.trials]
        local start=SC.Performance.preciseNowMs()
        local ok,why=SC.Logistics.prepareLoadout(state.actor,state.request,
            {snapshot={threats={},threatCount=0,immediateCount=0,pressure=0}})
        local elapsed=SC.Performance.preciseNowMs()-start
        assert(ok, tostring(why))
        trial.peak=math.max(trial.peak,elapsed)
        trial.frames=trial.frames+1
        if trial.checkedAxe then
            assert(why=="loadout_seeking_tool" and state.stock:contains(state.axe),tostring(why))
            assert(SC.Logistics.resetPreparation(state.actor,state.request.key))
            if #state.trials<4 then startTrial() else finish("PASS","identified exact axe in four native shelf surveys") end
        end
    end
end

Events.OnRenderTick.Add(function()
    if state.phase=="done" then return end
    local ok,why=pcall(step)
    if not ok then finish("FAIL",why) end
end)
