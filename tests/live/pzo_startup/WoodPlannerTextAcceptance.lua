-- SPDX-License-Identifier: MIT
-- Read the production map overlay and the returned wood-trip preview in a
-- disposable native world with a recruited companion and a powered camp PC.
local SC = SurvivorCompanion
local state = {phase="menu", notes={}, modals={}}

local function write(name, value)
    local file = assert(getFileWriter("pzo-wood-text-" .. name .. ".txt", true, false))
    file:write(value .. "\n")
    file:close()
end

local function phase(name)
    state.phase, state.deadline = name, getTimestampMs() + 90000
    write("progress", name .. "\n" .. table.concat(state.notes, "\n"))
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. state.phase .. "\nreason="
        .. tostring(reason) .. "\n" .. table.concat(state.notes, "\n"))
    state.phase = "done"
end

local function floorNear(player, inside)
    local origin = player:getSquare()
    for radius = 1, 12 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local q = getCell():getGridSquare(origin:getX()+dx, origin:getY()+dy, origin:getZ())
                    if q and (not inside or q:getBuilding()) and q:isFree(false)
                        and SC.GameplayUtil.isClearActorSpawnSquare(q) then return q end
                end
            end
        end
    end
    error("no clear square near player")
end

local function campComputer(player)
    local q = floorNear(player, true)
    player:teleportTo(q:getX()+0.5, q:getY()+0.5, q:getZ())
    SC.BaseLife.reset()
    assert(SC.BaseLife.create(q, "Wood crew"))
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
    assert(SC.TerminalHardware.install(player, pc, "radio", inventory:AddItem("Base.WalkieTalkie5")))
    assert(SC.Terminal.powered(pc) and SC.BaseLife.isInside(pc))
    local lock = SC.Terminal.computerState(player, pc)
    if lock.locked then
        local puzzle = SC.TerminalSystem.ensurePuzzle(lock, SC.ControlUtil.skill(player))
        assert(SC.TerminalSystem.act(lock, puzzle.answer, SC.ControlUtil.hours()) == "success")
    end
    return pc
end

local function menu(window, action, value)
    local services = SC.TerminalServices
    for i = 1, 12 do
        local more
        for _,row in ipairs(services.menu(window)) do
            if row.serviceAction == action and row.serviceValue == value then
                assert(services.input(window,row.label,row))
                window:flush()
                return
            elseif row.serviceAction == "menu_next" then more = row end
        end
        if not more then break end
        assert(services.input(window,more.label,more))
    end
    error("missing option " .. action .. " " .. tostring(value) .. " in " .. tostring(window.menuPage))
end

local function matchText(text, expected)
    assert(text:find(expected, 1, true), "missing [" .. expected .. "] in " .. text)
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
        state.player, state.pc = player, campComputer(player)
        state.ticket = assert(SC.Actor.beginSpawn(floorNear(player), {recruited=true,
            identity={forename="Robin",surname="Forester",gender="woman",outfit="Generic01"}}))
        phase("spawn")
    elseif state.phase == "spawn" then
        local actor, reason = SC.Actor.pollSpawn(state.ticket)
        assert(actor or reason == "spawn_pending", tostring(reason))
        if not actor then return end
        local id = assert(SC.GameplayUtil.idOf(actor))
        assert(SC.BaseLife.assign(id, "generalist", true))
        actor:getInventory():AddItem("Base.Axe")
        assert(SC.Terminal.open(state.player,state.pc))
        local window = SC.Terminal.window
        state.window, state.actor = window, actor
        window:flush()
        assert(SC.TerminalServices.input(window,"expedition station"))
        menu(window,"page","expedition_plan")
        menu(window,"page","station_crew")
        menu(window,"crew",id)
        menu(window,"page","expedition_plan")
        menu(window,"map_pick")
        state.notes[#state.notes+1] = "crew=" .. id
        phase("open_map")
    elseif state.phase == "open_map" then
        local session = assert(SC.ExpeditionMap.session, "wood picker did not open")
        local map = session.map
        if not map or not map:isVisible() or not session.useButton then return end
        local api = map.mapAPI
        local wx, wy = math.floor(state.actor:getX())+65.5, math.floor(state.actor:getY())+10.5
        for _,at in ipairs({{wx,wy},{wx+39,wy+29}}) do
            assert(SC.ExpeditionMap.click(map, api:worldToUIX(at[1],at[2]), api:worldToUIY(at[1],at[2])))
        end
        assert(session.highlight, tostring(session.error))
        state.mapLines = {}
        local drawText = map.drawText
        state.drawText = drawText
        map.drawText = function(self, line, ...)
            state.mapLines[#state.mapLines+1] = line
            return drawText(self,line,...)
        end
        phase("read_map")
    elseif state.phase == "read_map" then
        local session = assert(SC.ExpeditionMap.session)
        local transcript = table.concat(state.mapLines, " ")
        if not transcript:find("to centre", 1, true) then return end
        session.map.drawText = state.drawText
        state.walkingText = transcript
        state.notes[#state.notes+1] = "walking_map=" .. transcript
        local window = state.window
        state.firstRow = #window.rows+1
        session.useButton.onclick(session.useButton.target,session.useButton)
        phase("read_preview")
    elseif state.phase == "read_preview" then
        local window, lines = state.window, {}
        window:flush()
        for i = state.firstRow, #window.rows do
            local line = window.rows[i].text
            if line and line ~= "" then lines[#lines+1] = line end
        end
        local transcript = table.concat(lines, " ")
        assert(window.menuPage == "station_review", "review refused: " .. transcript)
        state.notes[#state.notes+1] = "camp_terminal=" .. transcript
        for _,word in ipairs({"128 x 128 meters","1000 meters","200 meters","40 x 30 meters","meters to centre"}) do
            matchText(state.walkingText,word)
        end
        matchText(transcript,"Logging area: 40 x 30 meters.")
        matchText(transcript,"limited to 256 logs.")
        finish("PASS","read the on-foot logging map and the powered camp computer preview")
    end
end

Events.OnRenderTick.Add(function()
    if state.phase == "done" then return end
    local ok, why = pcall(step)
    if not ok then finish("FAIL",why) end
end)
