-- SPDX-License-Identifier: MIT
-- Native bite, camp panel and powered computer, followed by a historical
-- open-crisis document loaded in a second game process. Disposable worlds only.
local SC = SurvivorCompanion
local B, C, U = SC.BaseLife, SC.InfectionCrisis, SC.GameplayUtil
local state = { phase = "menu", notes = {}, modals = {} }

local function write(path, value)
    local file = assert(getFileWriter(path, true, false))
    file:write(value .. "\n")
    file:close()
end

local function read(path)
    local file = assert(getFileReader(path, false))
    local value = file:readLine()
    file:close()
    return value
end

local function note(key, value)
    state.notes[#state.notes + 1] = key .. "=" .. tostring(value)
end

local function phase(name)
    state.phase, state.deadline = name, getTimestampMs() + 90000
    write("pzo-crisis-progress.txt", name .. "\n" .. table.concat(state.notes, "\n"))
end

local function finish(result, why)
    write("pzo-crisis-result.txt", "result=" .. result .. "\nphase=" .. state.phase
        .. "\nreason=" .. tostring(why) .. "\n" .. table.concat(state.notes, "\n"))
    state.phase = "done"
end

local function floorNear(player, interior)
    local origin = player:getSquare()
    for radius = 0, 12 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local q = getCell():getGridSquare(origin:getX()+dx, origin:getY()+dy, origin:getZ())
                    if q and (not interior or q:getBuilding()) and U.isClearActorSpawnSquare(q)
                        and q:isFree(false) and q ~= origin then return q end
                end
            end
        end
    end
    error("no accessible square near the player")
end

local function unlock(lock, player)
    if lock.locked then
        local puzzle = SC.TerminalSystem.ensurePuzzle(lock, SC.ControlUtil.skill(player))
        assert(SC.TerminalSystem.act(lock, puzzle.answer, SC.ControlUtil.hours()) == "success")
    end
end

local function openCircuits(player)
    local q = floorNear(player, true)
    player:teleportTo(q:getX()+0.5, q:getY()+0.5, q:getZ())
    local pc = IsoObject.new(q, "appliances_com_01_72", "Computer")
    q:AddTileObject(pc)
    local inventory = player:getInventory()
    inventory:AddItem("Base.Screwdriver")
    for i = 1, 3 do inventory:AddItem("Base.ElectricWire") end
    for i = 1, 6 do inventory:AddItem("Base.ElectronicsScrap") end
    for i = SC.ControlUtil.skill(player)+1, 4 do player:LevelPerk(Perks.Electricity) end
    local battery = assert(inventory:AddItem("Base.CarBattery1"))
    SC.ControlUtil.setCharge(battery, 0.95)
    assert(SC.TerminalHardware.install(player, pc, "ups", battery))
    assert(SC.Terminal.powered(pc))
    unlock(SC.Terminal.computerState(player, pc), player)
    assert(SC.BuildingControls.connect(player, pc))
    unlock(SC.BuildingControls.panel(pc, false).security, player)
    assert(SC.Terminal.open(player, pc))
    local window, services = SC.Terminal.window, SC.TerminalServices
    window:flush()
    assert(services.input(window, "building services"))
    window:flush()
    for i = 1, 10 do
        local more
        for _, row in ipairs(services.menu(window)) do
            if row.serviceAction == "page" and row.serviceValue == "circuits" then
                local first = #window.rows + 1
                assert(services.input(window, row.label, row))
                window:flush()
                local expected = "Lighting relays and generator controls."
                local transcript = {}
                for index = first, #window.rows do
                    local line = window.rows[index]
                    if line.text and line.text ~= "" then transcript[#transcript+1] = line.text end
                end
                assert(window.menuPage == "circuits" and transcript[#transcript] == expected,
                    "unexpected Circuits page: " .. table.concat(transcript, " | "))
                note("powered_circuits", transcript[#transcript])
                window:close()
                return
            elseif row.serviceAction == "menu_next" then more = row end
        end
        assert(more and services.input(window, more.label, more), "Power circuits missing from building services")
    end
    error("Circuits menu did not resolve")
end

local function panel(wantOpen)
    local root = SC.UI.open("base", wantOpen and state.subjectId or nil)
    root.detail:rebuild(false)
    local hasAction, empty = false, false
    local emptyText = SC.UI.text("UI_SC_Base_NoCrisis")
    for _, child in pairs(root.detail.content.children or {}) do
        if child.scCrisisId == state.crisisId then hasAction = true end
        local text = child.tooltip
        if type(text) == "string" and text:find(emptyText, 1, true) then empty = true end
    end
    SC.UI.close()
    assert(hasAction == wantOpen and empty ~= wantOpen,
        "camp panel actions=" .. tostring(hasAction) .. " empty=" .. tostring(empty))
    note(wantOpen and "panel_before" or "panel_after", wantOpen and state.crisisId or emptyText)
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
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
    assert(getTimestampMs() < state.deadline, "native phase timed out")
    if state.phase == "start" then
        local player = getSpecificPlayer(0)
        if not player or not player:getSquare() or not SC.Persistence.restoreStatus() then return end
        state.player = player
        if read("pzo-world-mode.txt") == "disk-restored" then
            state.subjectId, state.crisisId = read("pzo-crisis-ids.txt"):match("^(%S+) (%S+)$")
            assert(state.crisisId)
            phase("reload")
            return
        end
        openCircuits(player)
        B.reset()
        C.reset()
        assert(B.create(player:getSquare(), "Crisis crew"))
        state.ticket = assert(SC.Actor.beginSpawn(floorNear(player), {recruited=true,
            identity={forename="Robin", surname="Watch", gender="woman", outfit="Generic01"}}))
        phase("spawn")
    elseif state.phase == "spawn" then
        local actor, why = SC.Actor.pollSpawn(state.ticket)
        assert(actor or why == "spawn_pending", tostring(why))
        if not actor then return end
        state.actor, state.subjectId = actor, assert(U.idOf(actor))
        assert(B.assign(state.subjectId, "generalist", true))
        local part = actor:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
        part:SetBitten(true, true)
        part:setBiteTime(9)
        SC.Medical.invalidate(actor)
        assert(SC.Medical.assess(actor).bites > 0, "native bite missing")
        phase("watch")
    elseif state.phase == "watch" then
        C.pulse(state.player, getTimestampMs())
        for _, row in ipairs(C.summary(state.player).rows) do
            if row.subjectId == state.subjectId and row.knownToViewer then
                assert(C.choose(row.id, "watch", row.decisionRevision))
                state.crisisId = row.id
                break
            end
        end
        if not state.crisisId then return end
        assert(B.restriction(state.subjectId) == "watch" and B.restrictionOwner(state.subjectId) == state.crisisId)
        panel(true)
        state.openDocument = assert(C.export())
        note("bitten_subject", state.subjectId)
        state.actor:setGodMod(false)
        state.actor:getBodyDamage():ReduceGeneralHealth(110)
        state.actor:setHealth(0)
        if not state.actor:isDead() then state.actor:Kill(nil) end
        assert(state.actor:isDead())
        phase("retire")
    elseif state.phase == "retire" then
        if SC.Registry.byId(state.subjectId) or B.resident(state.subjectId) then return end
        assert(C.export().crises[state.crisisId].phase == "terminal" and not B.restriction(state.subjectId),
            "ordinary death notification must already have closed the crisis")
        note("ordinary_death", "native actor retired and watch cleared")
        assert(SC.Persistence.save(state.player))
        save(false)
        local doc = assert(ModData.getOrCreate(SC.Identity.worldSaveKey).document)
        assert(not doc.baseLife.residents[state.subjectId] and not doc.companions[state.subjectId])
        -- Recreate the old-save defect using the genuine pre-death verdict.
        -- The saved roster and companion records still reflect the native death.
        doc.infectionCrisis = state.openDocument
        doc.baseLife.restrictions[state.subjectId] = "watch"
        doc.baseLife.restrictionOwners[state.subjectId] = state.crisisId
        assert(doc.infectionCrisis.crises[state.crisisId].phase == "resolved")
        write("pzo-crisis-ids.txt", state.subjectId .. " " .. state.crisisId)
        assert(SCSplitScreenProbe.flushGlobalModDataForWorldExit())
        note("disk_fixture", "open watch verdict and matching restriction, subject absent")
        finish("PASS", "powered Circuits, native bite and death, old crisis saved")
    elseif state.phase == "reload" then
        assert(not SC.Registry.byId(state.subjectId) and not SC.Persistence.isPending(state.subjectId))
        C.pulse(state.player, getTimestampMs())
        C.pulse(state.player, getTimestampMs())
        local data = C.export()
        local row = assert(data.crises[state.crisisId], "saved crisis missing")
        assert(row.phase == "terminal" and row.archivedAt and not row.finalAuthorized)
        assert(B.restriction(state.subjectId) == nil and B.restrictionOwner(state.subjectId) == nil)
        local count = 0
        for _, event in ipairs(C.summary(state.player).history) do
            if event.kind == "subject_gone" and event.crisisId == state.crisisId then count = count + 1 end
        end
        assert(count == 1, "expected one subject_gone history entry, found " .. tostring(count))
        panel(false)
        note("restored_crisis", "archived once, owned restriction cleared")
        finish("PASS", "fresh process repaired saved watch and removed crisis from camp panel")
    end
end

Events.OnRenderTick.Add(function()
    if state.phase == "done" then return end
    local ok, why = pcall(step)
    if not ok then finish("FAIL", why) end
end)
