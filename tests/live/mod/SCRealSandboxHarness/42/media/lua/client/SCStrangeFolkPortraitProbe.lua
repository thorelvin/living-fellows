-- SPDX-License-Identifier: MIT
-- Disposable cloned-save portrait fixture. The real faction spawn queue and
-- native actor constructor dress each character; only the site is synthetic.
local Probe = {}

local portraits = {
    { label = "red", id = "gut_cloaked_red" },
    { label = "kevin", id = "window_spiffo_kevin" },
    { label = "wendell", id = "shotgun_farmer_wendell" },
}

local function portraitFor(H)
    local target = H.config and H.config.strange_folk_portrait_target
    if target and target ~= "all" then
        if H.strangePortraitIndex ~= 1 then return nil end
        for _, portrait in ipairs(portraits) do
            if portrait.label == target then return portrait end
        end
        return nil
    end
    return portraits[H.strangePortraitIndex]
end

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function safeOutdoor(U, square)
    if not square then return false end
    if call(square, "getRoom") ~= nil or call(square, "isOutside") ~= true then
        return false
    end
    return U.isSafeSpawnSquare(square) == true
end

local function approachPost(U, center, minimum, maximum)
    for radius = minimum, maximum do
        for _, offset in ipairs({ { radius, 0 }, { 0, radius },
            { -radius, 0 }, { 0, -radius } }) do
            local square = U.gridSquare(center.x + offset[1],
                center.y + offset[2], center.z)
            if safeOutdoor(U, square) then return square end
        end
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(center.x + dx,
                        center.y + dy, center.z)
                    if safeOutdoor(U, square) then return square end
                end
            end
        end
    end
    return nil
end

local function isWendellApproach(H)
    return H.config and H.config.wendell_approach_probe == "true"
end

local function movePlayerTo(H, square)
    return square and pcall(function()
        H.player:teleportTo(square:getX() + 0.5,
            square:getY() + 0.5, square:getZ())
    end) or false
end

local function portraitSiteScore(U, x, y, z)
    -- The loaded yard may have tufts of grass everywhere. Reject blocked
    -- performer tiles, then rank the surrounding frame by visual clutter.
    for dx = -1, 1 do
        if not safeOutdoor(U, U.gridSquare(x + dx, y, z)) then return nil end
    end
    if not safeOutdoor(U, U.gridSquare(x - 1, y - 1, z)) then return nil end
    if not safeOutdoor(U, U.gridSquare(x + 1, y + 2, z)) then return nil end
    local score = 0
    for dx = -3, 3 do
        for dy = -3, 3 do
            local square = U.gridSquare(x + dx, y + dy, z)
            if not square then return nil end
            if call(square, "getRoom") ~= nil or call(square, "isOutside") ~= true then
                score = score + 15
            else
                local objects = call(square, "getObjects")
                local floor = call(square, "getFloor")
                local count = tonumber(call(objects, "size")) or 0
                for index = 0, count - 1 do
                    if call(objects, "get", index) ~= floor then
                        score = score + (math.abs(dx) <= 1 and math.abs(dy) <= 1
                            and 12 or 2)
                    end
                end
            end
        end
    end
    return score
end

local function findPortraitSite(player, U)
    local px, py, pz = U.position(player)
    if px == nil then return nil, "observer_position_unavailable" end
    px, py, pz = math.floor(px), math.floor(py), math.floor(pz or 0)
    local best, bestScore
    for radius = 3, 30 do
        for dx = -radius, radius, 2 do
            for dy = -radius, radius, 2 do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local x, y = px + dx, py + dy
                    local score = portraitSiteScore(U, x, y, pz)
                    if score and (bestScore == nil or score < bestScore) then
                        best, bestScore = { x = x, y = y, z = pz }, score
                        if score == 0 then return best, nil end
                    end
                end
            end
        end
    end
    if best then return best, nil end
    return nil, "no_open_loaded_portrait_patch"
end

local function siteFor(position, portrait)
    -- Native group occupancy is retained after a prior actor moves away, so
    -- each portrait gets a distinct clear tile in the same camera frame.
    local x = position.x + (portrait.label == "kevin" and 0 or -1)
    local y = position.y + (portrait.label == "wendell" and -1 or 0)
    local z = position.z
    local spawn = { x = x, y = y, z = z }
    local house = {
        id = "strange-folk-portrait-" .. portrait.label,
        anchor = { x = x, y = y, z = z },
        bounds = { x1 = x - 1, y1 = y - 1, x2 = x + 1, y2 = y + 1, z = z },
        interior = { spawn }, openings = {}, roomGroup = "portrait_fixture",
    }
    return {
        kind = portrait.label == "red" and "roamer" or "resident",
        room = "portrait_fixture", house = house, anchor = spawn,
        spawn = spawn,
    }
end

local function actorFor(SC, group)
    local member = group and SC.Factions.member(group.id, "member-1")
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function wornCount(actor)
    local worn = call(actor, "getWornItems")
    return tonumber(call(worn, "size")) or 0
end

local function wears(actor, fullType)
    local worn = call(actor, "getWornItems")
    for index = 0, (tonumber(call(worn, "size")) or 0) - 1 do
        local entry = call(worn, "get", index)
        local item = call(entry, "getItem")
        if call(item, "getFullType") == fullType then return true end
    end
    return false
end

local function signalName(label, suffix)
    return "SurvivorCompanionHarness/strange-folk-" .. label .. "-" .. suffix .. ".txt"
end

local function hidePrior(H)
    local actor = H.strangePortraitActor
    if not actor then return end
    pcall(function() actor:setInvisible(true) end)
    local site = H.strangePortraitSite
    local U = SurvivorCompanion.GameplayUtil
    for radius = 10, 18 do
        local remote = U.gridSquare(site.x + radius, site.y, site.z)
        if safeOutdoor(U, remote) then
            pcall(function()
                actor:teleportTo(remote:getX() + 0.5,
                    remote:getY() + 0.5, remote:getZ())
            end)
            break
        end
    end
    H.strangePortraitActor = nil
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "strange_folk_portrait_begin" then
        if current - H.phaseStartedAt < 2200 then return end
        if not H.strangePortraitSite then
            local site, reason = findPortraitSite(H.player, SC.GameplayUtil)
            if not check("strange_folk_portrait_site", site ~= nil,
                tostring(reason)) then
                setPhase("finish", current) return
            end
            H.strangePortraitSite = site
            -- A daylight portrait on the disposable clone only.
            pcall(function() getGameTime():setTimeOfDay(12.0) end)
            local view = SC.GameplayUtil.gridSquare(site.x + 1, site.y + 2, site.z)
            local moved = pcall(function()
                H.player:teleportTo(view:getX() + 0.5,
                    view:getY() + 0.5, view:getZ())
                H.player:setInvisible(true)
            end)
            if not check("strange_folk_portrait_observer", moved,
                "camera within three tiles of encounter") then
                setPhase("finish", current) return
            end
            if SC.Scheduler then SC.Scheduler.unregister("decision") end
            pcall(function() if SC.UI then SC.UI.close() end end)
            pcall(function() getPlayerInventory(0):setVisible(false) end)
            pcall(function() getPlayerLoot(0):setVisible(false) end)
            pcall(function()
                getCore():setAutoZoom(0, false)
                for _ = 1, 5 do getCore():doZoomScroll(0, -1) end
            end)
            H.strangePortraitIndex = 1
        end
        hidePrior(H)
        local portrait = portraitFor(H)
        if not portrait then setPhase("finish", current) return end
        local definition = SC.Oddballs.definition(portrait.id)
        if not check("strange_folk_definition_" .. portrait.label,
            definition ~= nil, portrait.id) then
            setPhase("finish", current) return
        end
        local group, reason = SC.Factions.createOddballGroup(
            siteFor(H.strangePortraitSite, portrait), definition, true)
        if not check("strange_folk_group_" .. portrait.label,
            group ~= nil, tostring(reason)) then
            setPhase("finish", current) return
        end
        -- Avoid the guard's warning shot while retaining his native shotgun
        -- loadout, which onSpawn skips for an already recruited character.
        if portrait.label == "wendell" then
            group.oddball.stage = "warned"
            group.oddball.shellDeliveries = 1
        end
        if portrait.label == "red" then group.oddball.stage = "met" end
        H.strangePortraitGroup = group
        setPhase("strange_folk_portrait_spawn", current)
        return
    end
    if H.phase == "strange_folk_portrait_spawn" then
        local portrait = portraitFor(H)
        local actor = actorFor(SC, H.strangePortraitGroup)
        if not actor then
            if current - H.phaseStartedAt > 15000 then
                result("FAIL", "strange_folk_actor_" .. portrait.label,
                    "native faction spawn did not complete")
                setPhase("finish", current)
            end
            return
        end
        local name = tostring(call(actor, "getFullName") or "")
        local worn = wornCount(actor)
        local expected = portrait.label == "red" and "Red"
            or portrait.label == "kevin" and "Kevin" or "Wendell"
        if not check("strange_folk_actor_" .. portrait.label,
            name:find(expected, 1, true) ~= nil and worn > 0,
            "name=" .. name .. " worn=" .. tostring(worn)) then
            setPhase("finish", current) return
        end
        if portrait.label == "kevin" and not check("strange_folk_spiffo_head",
            wears(actor, "Base.Hat_Spiffo"),
            "mascot head must be worn, not merely carried") then
            setPhase("finish", current) return
        end
        if portrait.label == "kevin" then
            local held, reason = SC.OddballSpiffo.update(actor, H.player, {},
                { mode = "spiffo_pose", zombieNearby = false },
                H.strangePortraitGroup)
            if not check("strange_folk_mannequin_request", held == true,
                tostring(reason)) then
                setPhase("finish", current) return
            end
        end
        if portrait.label == "wendell" then
            local U = SC.GameplayUtil
            local inventory = U.inventory(actor)
            local counts = {}
            for _, item in ipairs(inventory and U.inventoryItemsDeep(inventory, 200, 8) or {}) do
                local kind = U.itemType(item)
                if kind then counts[kind] = (counts[kind] or 0) + 1 end
            end
            local primary = call(actor, "getPrimaryHandItem")
            local suppliesReady = counts["Base.CannedCorn"] == 1
                and counts["Base.TinOpener"] == 1
                and counts["Base.WaterBottle"] == 1
            local shotgunReady = call(primary, "getFullType") == "Base.Shotgun"
            local seeded = H.strangePortraitGroup.oddball.kitSeeded == true
            if not check("strange_folk_wendell_kit",
                suppliesReady and shotgunReady and seeded,
                "corn=" .. tostring(counts["Base.CannedCorn"])
                    .. " opener=" .. tostring(counts["Base.TinOpener"])
                    .. " water=" .. tostring(counts["Base.WaterBottle"])
                    .. " primary=" .. tostring(call(primary, "getFullType"))
                    .. " seeded=" .. tostring(seeded)) then
                setPhase("finish", current) return
            end
        end
        H.strangePortraitActor = actor
        pcall(function() actor:setDir(IsoDirections.S) end)
        if isWendellApproach(H) then
            setPhase("wendell_approach_prepare", current)
            return
        end
        setPhase("strange_folk_portrait_settle", current)
        return
    end
    if H.phase == "wendell_approach_prepare" then
        local U = SC.GameplayUtil
        local group = H.strangePortraitGroup
        local far = approachPost(U, group.oddball.site.spawn, 21, 27)
        if not check("wendell_far_approach_post", movePlayerTo(H, far),
            "safe outdoor post beyond the warning radius") then
            setPhase("finish", current) return
        end
        local story = group.oddball
        -- The portrait setup suppresses warning fire while the native actor
        -- spawns. Re-arm this disposable scene only after moving the observer
        -- outside the farm's trigger radius.
        story.stage, story.shellDeliveries = "unmet", 0
        story.warningShotUsed, story.warningShotPending = nil, nil
        story.firstWarnedHour = nil
        group.discovered = false
        H.wendellSpeech = {}
        H.wendellOriginalSay = U.say
        U.say = function(speaker, line)
            local spoken = H.wendellOriginalSay(speaker, line)
            if spoken == true and speaker == H.strangePortraitActor then
                H.wendellSpeech[#H.wendellSpeech + 1] = tostring(line)
            end
            return spoken
        end
        local gun = call(H.strangePortraitActor, "getPrimaryHandItem")
        if not check("wendell_unmet_before_approach",
            story.stage == "unmet"
                and call(gun, "getCurrentAmmoCount") == 6,
            "stage=" .. tostring(story.stage)
                .. " shells=" .. tostring(call(gun, "getCurrentAmmoCount"))) then
            U.say = H.wendellOriginalSay
            setPhase("finish", current) return
        end
        setPhase("wendell_approach_warning", current)
        return
    end
    if H.phase == "wendell_approach_warning" then
        if current - H.phaseStartedAt < 500 then return end
        local U = SC.GameplayUtil
        local group = H.strangePortraitGroup
        local near = approachPost(U, group.oddball.site.spawn, 7, 9)
        if not check("wendell_safe_approach_post", movePlayerTo(H, near),
            "outside the porch but inside the warning radius") then
            U.say = H.wendellOriginalSay
            setPhase("finish", current) return
        end
        local handled, reason = SC.Oddballs.pulseGroup(group, H.player, current)
        local story = group.oddball
        local gun = call(H.strangePortraitActor, "getPrimaryHandItem")
        local spoken = H.wendellSpeech
        local warning = spoken[1] and spoken[1]:find("Back past the fence", 1, true)
        local shot = spoken[2] and spoken[2]:find(
            "Next one won't go into the sky", 1, true)
        if not check("wendell_warning_and_shot_trigger",
            handled == true and story.stage == "warned"
                and group.discovered == true and story.warningShotUsed == true
                and group.standing ~= "Hostile"
                and call(gun, "getCurrentAmmoCount") == 5
                and warning ~= nil and shot ~= nil,
            "pulse=" .. tostring(reason) .. " stage=" .. tostring(story.stage)
                .. " shells=" .. tostring(call(gun, "getCurrentAmmoCount"))
                .. " lines=" .. table.concat(spoken, " | ")) then
            U.say = H.wendellOriginalSay
            setPhase("finish", current) return
        end
        local x, y, z = U.position(H.strangePortraitActor)
        local signal = H.strangeFolkPortraitSignals.write(signalName("wendell", "ready"), {
            "ready=true", "phase=warning", "position=" .. tostring(x)
                .. "," .. tostring(y) .. "," .. tostring(z),
            "warning=" .. spoken[1], "shot=" .. spoken[2],
        })
        if not check("wendell_warning_capture_ready", signal,
            "warning and shot lines recorded on the actor") then
            U.say = H.wendellOriginalSay
            setPhase("finish", current) return
        end
        setPhase("strange_folk_portrait_capture", current)
        return
    end
    if H.phase == "wendell_approach_porch" then
        local U = SC.GameplayUtil
        local group = H.strangePortraitGroup
        local porch = approachPost(U, group.oddball.site.spawn, 2, 3)
        if not check("wendell_porch_post", movePlayerTo(H, porch),
            "safe outdoor tile within the critical trespass radius") then
            U.say = H.wendellOriginalSay
            setPhase("finish", current) return
        end
        local handled, reason = SC.Oddballs.pulseGroup(group, H.player, current)
        local line = H.wendellSpeech[#H.wendellSpeech]
        check("wendell_trespass_response",
            handled == true and group.oddball.stage == "hostile"
                and group.standing == "Hostile"
                and line ~= nil and line:find("You came for the hens", 1, true) ~= nil,
            "pulse=" .. tostring(reason) .. " stage="
                .. tostring(group.oddball.stage) .. " line=" .. tostring(line))
        U.say = H.wendellOriginalSay
        setPhase("finish", current)
        return
    end
    if H.phase == "strange_folk_portrait_settle" then
        if current - H.phaseStartedAt < 2200 then return end
        local portrait = portraitFor(H)
        local actor = H.strangePortraitActor
        local spoken = SC.GameplayUtil.say(actor,
            SC.GameplayUtil.nameOf(actor))
        if not check("strange_folk_portrait_actor_speech_" .. portrait.label,
            spoken == true, "name cue stays on the native encounter actor") then
            setPhase("finish", current) return
        end
        local x, y, z = SC.GameplayUtil.position(actor)
        local signal = H.strangeFolkPortraitSignals.write(signalName(portrait.label, "ready"), {
            "ready=true", "name=" .. tostring(call(actor, "getFullName")),
            "worn=" .. tostring(wornCount(actor)),
            "ext=" .. tostring(call(actor, "getVariableString", "Ext")),
            "action_context=" .. tostring(call(actor, "getCurrentActionContextStateName")),
            "position=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z),
        })
        if not check("strange_folk_ready_" .. portrait.label, signal,
            tostring(x) .. "," .. tostring(y) .. " worn=" .. tostring(wornCount(actor))) then
            setPhase("finish", current) return
        end
        setPhase("strange_folk_portrait_capture", current)
        return
    end
    if H.phase == "strange_folk_portrait_capture" then
        local portrait = portraitFor(H)
        if H.strangeFolkPortraitSignals.exists(signalName(portrait.label, "captured")) then
            result("PASS", "strange_folk_capture_" .. portrait.label,
                "native in-game portrait captured")
            if isWendellApproach(H) then
                setPhase("wendell_approach_porch", current)
                return
            end
            H.strangePortraitIndex = H.strangePortraitIndex + 1
            setPhase("strange_folk_portrait_begin", current)
        elseif current - H.phaseStartedAt > 30000 then
            result("FAIL", "strange_folk_capture_" .. portrait.label,
                "runner did not capture the ready frame")
            setPhase("finish", current)
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCStrangeFolkPortraitProbe = Probe
return Probe
