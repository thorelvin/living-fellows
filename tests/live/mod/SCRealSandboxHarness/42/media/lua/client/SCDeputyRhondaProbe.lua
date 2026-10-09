-- SPDX-License-Identifier: MIT
-- Disposable cloned-save smoke test at a real vanilla police station. Only
-- the observer is teleported; Rhonda and the captives use the native faction
-- spawn queue and their actual room squares.
local Probe = {}

local stations = {
    { name = "compact", observer = { x = 2348, y = 6994, z = 0 },
        x1 = 2336, x2 = 2348, y1 = 6992, y2 = 6996 },
    { name = "fallback", observer = { x = 9418, y = 13712, z = 0 },
        x1 = 9410, x2 = 9425, y1 = 13701, y2 = 13712 },
}

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function roomAt(square)
    local room = call(square, "getRoom")
    return room, call(room, "getName")
end

local function actorFor(SC, group, index)
    local member = group and SC.Factions.member(group.id,
        "member-" .. tostring(index))
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return member, record and record.actor or nil, record
end

local function moveObserver(H, station)
    local position = station.observer
    return pcall(function()
        H.player:teleportTo(position.x + 0.5, position.y + 0.5, position.z)
        H.player:setInvisible(true)
    end)
end

local function residentSite(SC, H, station, definition)
    local U = SC.GameplayUtil
    local lockerLoaded = false
    for y = station.y1, station.y2 do
        for x = station.x1, station.x2 do
            local square = U.gridSquare(x, y, 0)
            local _, name = roomAt(square)
            if name == "policelocker" or name == "policestorage" then
                lockerLoaded = true
                if U.isSafeSpawnSquare(square) then
                    local site = SC.Oddballs._siteForResidentForTests(
                        square, H.player, definition, name, true)
                    if site then return site, nil end
                end
            end
        end
    end
    return nil, lockerLoaded and "station_has_no_safe_checkpoint_or_cells"
        or "station_rooms_not_loaded"
end

local function captureView(SC, H, group)
    local U = SC.GameplayUtil
    local site = group.oddball.site
    local point = site and site.spawn
    if point then
        -- A nearby hallway square lets the engine cut away this building's
        -- roof while keeping the checkpoint and both cells in one frame.
        for radius = 1, 5 do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = U.gridSquare(point.x + dx,
                            point.y + dy, point.z or 0)
                        local _, name = roomAt(square)
                        if name and name ~= "policelocker"
                            and name ~= "prisoncells" and name ~= "cells"
                            and U.isSafeSpawnSquare(square) then
                            pcall(function()
                                H.player:teleportTo(square:getX() + 0.5,
                                    square:getY() + 0.5, square:getZ())
                            end)
                            return
                        end
                    end
                end
            end
        end
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "deputy_rhonda_prepare" then
        if current - H.phaseStartedAt < 1500 then return end
        local definition = SC.Oddballs.definition("checkpoint_deputy_rhonda")
        if not check("deputy_definition", definition ~= nil,
            "checkpoint_deputy_rhonda") then
            setPhase("finish", current) return
        end
        H.deputyDefinition = definition
        H.deputyStationIndex = 1
        pcall(function() getGameTime():setTimeOfDay(12.0) end)
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        pcall(function() if SC.UI then SC.UI.close() end end)
        pcall(function() getPlayerInventory(0):setVisible(false) end)
        pcall(function() getPlayerLoot(0):setVisible(false) end)
        pcall(function()
            getCore():setAutoZoom(0, false)
            for _ = 1, 4 do getCore():doZoomScroll(0, -1) end
        end)
        if not check("deputy_observer_teleport",
            moveObserver(H, stations[1]), "compact police station") then
            setPhase("finish", current) return
        end
        setPhase("deputy_rhonda_site", current)
        return
    end
    if H.phase == "deputy_rhonda_site" then
        if current - H.phaseStartedAt < 2500 then return end
        local station = stations[H.deputyStationIndex]
        local site, reason = residentSite(SC, H, station,
            H.deputyDefinition)
        if not site then
            if current - H.phaseStartedAt < 12000 then return end
            H.deputyStationIndex = H.deputyStationIndex + 1
            local fallback = stations[H.deputyStationIndex]
            if fallback then
                result("PASS", "deputy_station_fallback",
                    station.name .. ": " .. tostring(reason))
                if not check("deputy_fallback_teleport",
                    moveObserver(H, fallback), fallback.name) then
                    setPhase("finish", current) return
                end
                setPhase("deputy_rhonda_site", current)
            else
                result("FAIL", "deputy_real_station_site",
                    station.name .. ": " .. tostring(reason))
                setPhase("finish", current)
            end
            return
        end
        if not check("deputy_real_station_site",
            type(site.captiveSpawns) == "table"
                and #site.captiveSpawns >= 1 and #site.captiveSpawns <= 2,
            station.name .. " captives=" .. tostring(site.captiveSpawns
                and #site.captiveSpawns)) then
            setPhase("finish", current) return
        end
        local group, createReason = SC.Factions.createOddballGroup(
            site, H.deputyDefinition, true)
        if not check("deputy_native_group_created", group ~= nil,
            tostring(createReason)) then
            setPhase("finish", current) return
        end
        H.deputyGroup = group
        H.deputyExpectedCount = 1 + #site.captiveSpawns
        setPhase("deputy_rhonda_spawn", current)
        return
    end
    if H.phase == "deputy_rhonda_spawn" then
        local group = H.deputyGroup
        local actors = {}
        for index = 1, H.deputyExpectedCount do
            local member, actor, record = actorFor(SC, group, index)
            if not member or not actor or not record then
                if current - H.phaseStartedAt > 30000 then
                    result("FAIL", "deputy_native_actors_loaded",
                        "waiting for member-" .. tostring(index))
                    setPhase("finish", current)
                end
                return
            end
            actors[index] = { member = member, actor = actor,
                record = record }
        end
        H.deputyActors = actors
        setPhase("deputy_rhonda_verify", current)
        return
    end
    if H.phase == "deputy_rhonda_verify" then
        if current - H.phaseStartedAt < 1500 then return end
        local group = H.deputyGroup
        local actors = H.deputyActors
        local deputy = actors[1]
        local name = tostring(call(deputy.actor, "getFullName") or "")
        if not check("deputy_identity_and_role",
            name:find("Rhonda", 1, true) ~= nil
                and deputy.member.role ~= "captive",
            "name=" .. name .. " role=" .. tostring(deputy.member.role)) then
            setPhase("finish", current) return
        end
        local deputyRoom = select(2, roomAt(call(deputy.actor,
            "getCurrentSquare")))
        if not check("deputy_checkpoint_room",
            deputyRoom == "policelocker" or deputyRoom == "policestorage",
            "room=" .. tostring(deputyRoom)) then
            setPhase("finish", current) return
        end
        local cellRooms = {}
        for index = 2, #actors do
            local row = actors[index]
            local square = call(row.actor, "getCurrentSquare")
            local room, roomName = roomAt(square)
            local x, y, z = SC.GameplayUtil.position(row.actor)
            local valid = row.member.role == "captive"
                and row.member.captive == true
                and row.record.recruited ~= true
                and (roomName == "prisoncells" or roomName == "cells"
                    or roomName == "policecells")
                and room ~= nil and cellRooms[room] ~= true
            if not check("deputy_captive_" .. tostring(index - 1), valid,
                "role=" .. tostring(row.member.role)
                    .. " room=" .. tostring(roomName)
                    .. " at=" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z)) then
                setPhase("finish", current) return
            end
            cellRooms[room] = true
        end
        captureView(SC, H, group)
        pcall(function() deputy.actor:Say("Deputy Rhonda Vance") end)
        if H.config.deputy_rhonda_screenshot == "true" then
            local signal = H.deputyRhondaSignals.write(
                "SurvivorCompanionHarness/deputy-rhonda-ready.txt",
                { "ready=true", "station=" .. stations[H.deputyStationIndex].name,
                    "members=" .. tostring(#actors) })
            if not check("deputy_capture_ready", signal,
                tostring(#actors) .. " native actors") then
                setPhase("finish", current) return
            end
            setPhase("deputy_rhonda_capture", current)
        else
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "deputy_rhonda_capture" then
        if H.deputyRhondaSignals.exists(
            "SurvivorCompanionHarness/deputy-rhonda-captured.txt") then
            result("PASS", "deputy_live_capture", "native checkpoint captured")
            setPhase("finish", current)
        elseif current - H.phaseStartedAt > 15000 then
            result("FAIL", "deputy_live_capture",
                "runner did not capture the ready frame")
            setPhase("finish", current)
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCDeputyRhondaProbe = Probe

return Probe
