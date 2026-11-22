-- SPDX-License-Identifier: MIT
-- Create a real clearing in a disposable world, save it and check the same
-- faction after starting a second game process.
local SC = SurvivorCompanion
local state = { phase="menu", modals={}, cursor=0 }

local function write(name, text)
    local file = assert(getFileWriter("pzo-faction-camp-" .. name .. ".txt", true, false))
    file:write(text .. "\n")
    file:close()
end

local function read(path)
    local file = assert(getFileReader(path, false))
    local line = file:readLine()
    file:close()
    return line
end

local function phase(name)
    state.phase, state.deadline = name, getTimestampMs() + 120000
    write("progress", name)
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. state.phase .. "\nreason=" .. tostring(reason)
        .. "\ngroup=" .. tostring(state.id) .. "\nmember=" .. tostring(state.actorId))
    state.phase = "done"
end

local function inspectSave()
    local quarantine = SC.Persistence.quarantineSnapshot()
    local entry = quarantine.subsystems.factions
    assert(not entry, entry and entry.reason)
    local faction = assert(SC.Factions.group(state.id), "saved faction missing")
    assert(faction.oddball.id == "family_pyre_caleb_hensley" and faction.oddball.site.kind == "family_pyre")
    assert(#faction.oddball.site.familySpawns == 3 and faction.members[1].actorId == state.actorId)
    assert(not quarantine.factionActors[state.actorId], "saved member quarantined")
    if not SC.Registry.byId(state.actorId) then return end
    finish("PASS", "clearing reloaded with its three posts and original living faction member")
end

local function step()
    if state.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not state.modals[modal] then
            state.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    assert(getTimestampMs() < state.deadline, "phase timed out")
    if state.phase == "start" then
        state.player = getSpecificPlayer(0)
        if not state.player or not state.player:getSquare() or not SC.Persistence.restoreStatus() then return end
        if read("pzo-world-mode.txt") == "disk-restored" then
            state.id, state.actorId = read("pzo-faction-camp-ids.txt"):match("^(%S+) (%S+)$")
            phase("inspect_saved_group")
        else
            phase("find_clearing")
        end
    elseif state.phase == "find_clearing" then
        local x, y = math.floor(state.player:getX()), math.floor(state.player:getY())
        for i = 1, 12 do
            local index = state.cursor
            assert(index < 41*41, "no loaded clearing near the seed player")
            state.cursor = index+1
            local at = getCell():getGridSquare(x+(index%41-20)*3, y+(math.floor(index/41)-20)*3, 0)
            local site = at and SC.OddballCaleb.siteFor(at, state.player, true)
            if site then
                local definition = assert(SC.Oddballs.definition("family_pyre_caleb_hensley"))
                local group, why = SC.Factions.createOddballGroup(site, definition, true)
                assert(group, tostring(why))
                state.id = group.id
                phase("save_group")
                return
            end
        end
    elseif state.phase == "save_group" then
        local group = assert(SC.Factions.group(state.id))
        state.actorId = group.members[1].actorId
        if not state.actorId or not SC.Registry.byId(state.actorId) then return end
        local saved, reason = SC.Persistence.save(state.player)
        assert(saved, tostring(reason))
        save(false)
        local doc = assert(ModData.getOrCreate(SC.Identity.worldSaveKey).document)
        assert(doc.factions.groups[state.id].oddball.site.kind == "family_pyre")
        assert(doc.factionActors[state.actorId], "member missing from disk document")
        write("ids", state.id .. " " .. state.actorId)
        assert(SCSplitScreenProbe.flushGlobalModDataForWorldExit())
        finish("PASS", "saved native faction member and authored clearing")
    elseif state.phase == "inspect_saved_group" then
        inspectSave()
    end
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start") end)
Events.OnRenderTick.Add(function()
    if state.phase == "done" then return end
    local okay, reason = pcall(step)
    if not okay then finish("FAIL", reason) end
end)
