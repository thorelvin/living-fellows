-- SPDX-License-Identifier: MIT
-- Disposable cloned-save visual and schedule check. Never shipped with LF.

local Probe = {}

local eightFacings = {
    { name = "N",  x =  0, y = -1 },
    { name = "NE", x =  0.70710678, y = -0.70710678 },
    { name = "E",  x =  1, y =  0 },
    { name = "SE", x =  0.70710678, y =  0.70710678 },
    { name = "S",  x =  0, y =  1 },
    { name = "SW", x = -0.70710678, y =  0.70710678 },
    { name = "W",  x = -1, y =  0 },
    { name = "NW", x = -0.70710678, y = -0.70710678 },
}

local function screenPoint(x, y, z)
    if type(isoToScreenX) ~= "function"
        or type(isoToScreenY) ~= "function" then return "unavailable" end
    local okX, sx = pcall(isoToScreenX, 0, x, y, z)
    local okY, sy = pcall(isoToScreenY, 0, x, y, z)
    if not okX or not okY then return "unavailable" end
    return string.format("%.1f,%.1f", tonumber(sx) or -1,
        tonumber(sy) or -1)
end

local function nativeSubmissionCount(actor, U)
    local count = U.call(actor, "getCompanionPeeStreamDepthSubmissionCount")
    return tonumber(count) or 0
end

local function turnAndRecord(H, facing, result)
    local actor = H.hygieneActor
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local x, y, z = U.position(actor)
    if not x then return false end
    local aimed, failure = pcall(actor.setTargetAndCurrentDirection, actor,
        facing.x, facing.y)
    if not aimed then
        result("FAIL", "hygiene_direction_turn_" .. facing.name,
            tostring(failure))
        return false
    end
    -- Snap both native angle fields for each visual pose. Setting only the
    -- forward vector makes getDir report the requested turn while the rendered
    -- model remains partway through its previous direction.
    return true
end

local function recordDirectionPhoto(H, facing, check, result)
    local actor = H.hygieneActor
    local U = SurvivorCompanion.GameplayUtil
    local x, y, z = U.position(actor)
    local bx = select(1, U.call(actor, "getCompanionPelvisWorldX"))
    local by = select(1, U.call(actor, "getCompanionPelvisWorldY"))
    local bz = select(1, U.call(actor, "getCompanionPelvisWorldZ"))
    local px, py, pz = U.position(H.player)
    local fx = select(1, U.call(actor, "getForwardDirectionX"))
    local fy = select(1, U.call(actor, "getForwardDirectionY"))
    local angle = select(1, U.call(actor, "getAnimAngleRadians"))
    local state = SurvivorCompanion.Needs.peek(actor)
    local task = state and state.pee
    local alpha = select(1, U.call(actor, "getTargetAlpha", 0))
    local nativeSubmitted = select(1, U.call(actor,
        "getCompanionPeeStreamDepthSubmissionCount"))
    local nativeReady = select(1, U.call(actor,
        "isCompanionPeeStreamDepthReady", 0))
    local nativeFailure = select(1, U.call(actor,
        "getCompanionPeeStreamDepthFailure"))
    local turnSubmission = H.hygieneDirectionBaseSubmission or 0
    local depthSuppressions = SurvivorCompanion.HygieneEffects
        and SurvivorCompanion.HygieneEffects.nativeDepthSuppressions or 0
    local uiFallbacks = SurvivorCompanion.HygieneEffects
        and SurvivorCompanion.HygieneEffects.uiStreamFallbacks or 0
    local listed = false
    for _, item in ipairs(SurvivorCompanion.Registry.living()) do
        if item == actor then listed = true end
    end
    result("PASS", "hygiene_render_gate_" .. facing.name,
        "phase=" .. tostring(task and task.phase)
            .. " sits=" .. tostring(task and task.sits)
            .. " toilet=" .. tostring(task and task.toilet ~= nil)
            .. " alpha=" .. tostring(alpha)
            .. " listed=" .. tostring(listed)
            .. " draws=" .. tostring(H.hygieneStreamCalls)
            .. " nativeSubmitted=" .. tostring(nativeSubmitted)
            .. " turnSubmission=" .. tostring(turnSubmission)
            .. " nativeReady=" .. tostring(nativeReady)
            .. " nativeFailure=" .. tostring(nativeFailure)
            .. " nativeSuppressions=" .. tostring(depthSuppressions)
            .. " uiFallbacks=" .. tostring(uiFallbacks))
    check("hygiene_native_depth_" .. facing.name,
        tonumber(nativeSubmitted) and tonumber(nativeSubmitted) > 0
            and tonumber(nativeSubmitted) >= turnSubmission + 2
            and nativeReady == true,
        "submissions=" .. tostring(nativeSubmitted)
            .. " sinceTurn="
                .. tostring((tonumber(nativeSubmitted) or 0) - turnSubmission)
            .. " ready=" .. tostring(nativeReady)
            .. " failure=" .. tostring(nativeFailure))
    local dir = tostring(actor:getDir())
    local alignment = (tonumber(fx) or 0) * facing.x
        + (tonumber(fy) or 0) * facing.y
    local visualAlignment = angle and math.cos(angle) * facing.x
        + math.sin(angle) * facing.y or 0
    check("hygiene_direction_orientation_" .. facing.name,
        dir == facing.name and alignment > 0.85 and visualAlignment > 0.85,
        "dir=" .. dir .. " vector=" .. tostring(fx) .. "," .. tostring(fy)
            .. " animAngle=" .. tostring(angle)
            .. " visualDot=" .. tostring(visualAlignment))
    local name = tostring(H.config.run_id) .. "-pee-" .. facing.name
    local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
    check("hygiene_direction_photo_" .. facing.name,
        ok, name .. " facing=" .. tostring(fx) .. "," .. tostring(fy)
            .. " dir=" .. dir
            .. " origin=" .. screenPoint(x, y, z)
            .. " pelvis=" .. tostring(bx) .. "," .. tostring(by)
                .. "," .. tostring(bz)
            .. " pelvisScreen=" .. screenPoint(bx, by, bz)
            .. " z+0.4=" .. screenPoint(x, y, z + 0.4)
            .. " z+0.5=" .. screenPoint(x, y, z + 0.5)
            .. " observerFeet=" .. screenPoint(px, py, pz)
            .. " observerHead=" .. screenPoint(px, py, pz + 0.62)
            .. " error=" .. tostring(failure))
    return ok
end

local function hour()
    return getGameTime():getWorldAgeHours()
end

local function openOutdoorSquare(U, player)
    local x, y, z = U.position(player)
    if not x then return nil end
    local best, bestScore
    for dx = -10, 10 do
        for dy = -10, 10 do
            local distance = math.max(math.abs(dx), math.abs(dy))
            if distance >= 6 then
                local square = U.gridSquare(x + dx, y + dy, z)
                if square and square:getRoom() == nil
                    and U.isSquareFree(square) then
                    local open = 0
                    for nx = -2, 2 do
                        for ny = -2, 2 do
                            local neighbor = U.gridSquare(x + dx + nx,
                                y + dy + ny, z)
                            if neighbor and neighbor:getRoom() == nil
                                and U.isSquareFree(neighbor) then
                                open = open + 1
                            end
                        end
                    end
                    -- On this cloned save, the open front lawn projects to
                    -- the left of the house; prefer it over narrow edge strips.
                    local score = open * 10 + (dy - dx) * 2 - distance
                    if not bestScore or score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
    end
    return best
end

local function nearbyToilet(U, player)
    local x, y, z = U.position(player)
    if not x then return nil end
    for level = z, z + 1 do
        for dx = -22, 22 do
            for dy = -22, 22 do
                local square = U.gridSquare(x + dx, y + dy, level)
                local found
                U.squareObjects(square, function(object)
                    local sprite = select(1, U.call(object, "getSprite"))
                    local properties = select(1, U.call(sprite, "getProperties"))
                    local name = select(1, U.call(properties, "get", "CustomName"))
                    if type(name) == "string" and string.lower(name) == "toilet" then
                        found = object
                        return false
                    end
                end, 48)
                if found then return found end
            end
        end
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "hygiene_setup" then
        if current - H.phaseStartedAt < 2500 then return end
        -- This is a disposable cloned save. Daylight makes the authored
        -- arm/torso pose inspectable in the audit screenshot.
        pcall(function() getGameTime():setTimeOfDay(12) end)
        local toilet = nearbyToilet(U, H.player)
        H.hygieneToiletObject = toilet
        if toilet then
            local tx, ty, tz = U.position(toilet)
            result("PASS", "hygiene_toilet_fixture",
                tostring(tx) .. "," .. tostring(ty) .. "," .. tostring(tz)
                    .. " facing=" .. tostring(select(1, U.call(toilet, "getFacing"))))
        else
            result("PASS", "hygiene_toilet_fixture", "none loaded within 22 tiles")
        end
        local square = openOutdoorSquare(U, H.player)
        if not check("hygiene_outdoor_fixture", square ~= nil,
            "loaded free outdoor tile near observer") then
            setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "River", surname = "Tester",
                gender = "man", outfit = "Generic01" },
        })
        if not check("hygiene_spawn_request", ticket ~= nil, reason) then
            setPhase("finish", current) return
        end
        H.hygieneTicket = ticket
        setPhase("hygiene_spawn", current)
        return
    end
    if H.phase == "hygiene_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.hygieneTicket)
        if not actor then
            if current - H.phaseStartedAt > 12000 then
                result("FAIL", "hygiene_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        H.hygieneActor = actor
        local stableHash = U.stableHash
        U.stableHash = function(value)
            if string.find(tostring(value), ":pee_pose:", 1, true) then return 0 end
            return stableHash(value)
        end
        if SC.HygieneEffects and type(SC.HygieneEffects.renderStream) == "function" then
            local original = SC.HygieneEffects.renderStream
            H.hygieneStreamCalls = 0
            SC.HygieneEffects.renderStream = function(...)
                H.hygieneStreamCalls = H.hygieneStreamCalls + 1
                return original(...)
            end
        end
        SC.Scheduler.unregister("decision")
        local record = SC.Registry.byId(U.idOf(actor))
        if not check("hygiene_registered", record ~= nil,
            "recruited test companion has a persistence record") then
            setPhase("finish", current) return
        end
        record.state.personality = record.state.personality or {}
        record.state.personality.profile = record.state.personality.profile or {}
        record.state.personality.profile.archetype = "brave"
        record.state.downtime.nextPeeHour = hour() - 0.1
        local stats = actor:getStats()
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
        end)
        setPhase("hygiene_action", current)
        return
    end
    if H.phase == "hygiene_action" then
        if current - H.phaseStartedAt > 45000 then
            result("FAIL", "hygiene_action_timeout", "no verified relief animation")
            setPhase("finish", current) return
        end
        if current >= (H.hygieneNextUpdate or 0) then
            H.hygieneNextUpdate = current + 250
            local root = U.actorState(H.hygieneActor)
            root.senses = { current = { immediateCount = 0, pressure = 0 } }
            local handled, reason = SC.Needs.update(H.hygieneActor, H.player, root)
            if current >= (H.hygieneNextTrace or 0) then
                H.hygieneNextTrace = current + 2000
                local state = SC.Needs.peek(H.hygieneActor)
                local target = state and state.pee and state.pee.square
                local ax, ay = U.position(H.hygieneActor)
                local tx, ty = U.position(target)
                local nav = SC.Navigation.peek and SC.Navigation.peek(H.hygieneActor)
                result("PASS", "hygiene_progress", tostring(handled) .. ":" .. tostring(reason)
                    .. " actor=" .. tostring(ax) .. "," .. tostring(ay)
                    .. " target=" .. tostring(tx) .. "," .. tostring(ty)
                    .. " nav=" .. tostring(nav and nav.status)
                    .. " movement=" .. tostring(H.hygieneActor:getCompanionMovementOwner()))
            end
        end
        local peeState = SC.Needs.peek(H.hygieneActor)
        local style = peeState and peeState.pee and peeState.pee.style or "pee_stand"
        local status = SC.NativeActions.visualStatus(H.hygieneActor, style)
        if status == "active" then
            if not H.hygieneActiveAt then
                H.hygieneActiveAt = current
                local bx = select(1, U.call(H.hygieneActor,
                    "getCompanionPelvisWorldX"))
                local by = select(1, U.call(H.hygieneActor,
                    "getCompanionPelvisWorldY"))
                local bz = select(1, U.call(H.hygieneActor,
                    "getCompanionPelvisWorldZ"))
                check("hygiene_pelvis_api", type(bx) == "number"
                    and type(by) == "number" and type(bz) == "number"
                    and bx == bx and by == by and bz == bz,
                    tostring(bx) .. "," .. tostring(by) .. "," .. tostring(bz))
                local fx = select(1, U.call(H.hygieneActor, "getForwardDirectionX"))
                local fy = select(1, U.call(H.hygieneActor, "getForwardDirectionY"))
                result("PASS", "hygiene_actor_facing",
                    tostring(fx) .. "," .. tostring(fy)
                        .. " dir=" .. tostring(H.hygieneActor:getDir()))

                local ax, ay, az = U.position(H.hygieneActor)
                -- Bring the disposable observer beside the performer so the
                -- screenshot shows the actual pose rather than a distant roof.
                -- Keep the observer beside the performer in the eight-angle
                -- gallery. A directly foreground player hides the attachment
                -- point and makes the source impossible to inspect.
                if H.config.hygiene_eight_directions == "true" then
                    H.player:teleportTo(ax + 2.5, ay - 1.5, az)
                else
                    H.player:teleportTo(ax + 1.5, ay + 1.5, az)
                end
                if H.config.hygiene_eight_directions == "true" then
                    H.hygieneDirectionIndex = 1
                    -- Let nearby foliage fade after observer teleport before
                    -- the first picture; all eight still fit the action.
                    H.hygieneDirectionChangedAt = current + 1300
                else
                    pcall(H.hygieneActor.faceLocationF,
                        H.hygieneActor, ax, ay + 2)
                end
                pcall(function()
                    getCore():setAutoZoom(0, false)
                    for _ = 1, 4 do getCore():doZoomScroll(0, -1) end
                end)
            end
            if H.config.hygiene_eight_directions == "true" then
                local index = H.hygieneDirectionIndex or 1
                local direction = eightFacings[index]
                if direction then
                    if H.hygieneDirectionTurnedIndex ~= index then
                        if not turnAndRecord(H, direction, result) then
                            setPhase("finish", current) return
                        end
                        H.hygieneDirectionTurnedIndex = index
                        H.hygieneDirectionBaseSubmission =
                            nativeSubmissionCount(H.hygieneActor, U)
                        -- The first photo still waits for observer teleport
                        -- foliage to fade. Later turns start a fresh timer
                        -- after the preceding screenshot has returned.
                        H.hygieneDirectionChangedAt = math.max(U.nowMs(),
                            H.hygieneDirectionChangedAt or 0)
                        return
                    end
                    local submitted = nativeSubmissionCount(H.hygieneActor, U)
                    local angleValue = U.call(H.hygieneActor,
                        "getAnimAngleRadians")
                    local angle = tonumber(angleValue)
                    local angleSettled = angle ~= nil
                        and math.cos(angle) * direction.x
                            + math.sin(angle) * direction.y > 0.995
                    if U.nowMs() - H.hygieneDirectionChangedAt >= 300
                        and submitted >= H.hygieneDirectionBaseSubmission + 2
                        and angleSettled then
                        recordDirectionPhoto(H, direction, check, result)
                        H.hygieneDirectionIndex = index + 1
                        H.hygieneDirectionTurnedIndex = nil
                        H.hygieneDirectionChangedAt = U.nowMs()
                    end
                    return
                end
                check("hygiene_stream_rendered",
                    (H.hygieneStreamCalls or 0) > 0,
                    "local stream draws=" .. tostring(H.hygieneStreamCalls))
                setPhase("hygiene_finish", current)
                return
            end
            if current - H.hygieneActiveAt < 3000 then return end
            local name = tostring(H.config.run_id) .. "-" .. style
            local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
            check("hygiene_screenshot", ok, name .. ".png " .. tostring(failure))
            check("hygiene_stream_rendered", (H.hygieneStreamCalls or 0) > 0,
                "local stream draws=" .. tostring(H.hygieneStreamCalls))
            H.hygieneScreenshot = name
            setPhase("hygiene_finish", current)
        end
        if H.config.hygiene_eight_directions == "true"
            and H.hygieneDirectionIndex and status ~= "active" then
            check("hygiene_eight_directions_completed", false,
                "visual ended at direction "
                    .. tostring(H.hygieneDirectionIndex)
                    .. " status=" .. tostring(status))
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "hygiene_finish" then
        if current - H.phaseStartedAt > 20000 then
            result("FAIL", "hygiene_completion_timeout", "visual did not complete")
            setPhase("finish", current) return
        end
        if current < (H.hygieneNextUpdate or 0) then return end
        H.hygieneNextUpdate = current + 250
        SC.Needs.update(H.hygieneActor, H.player)
        local record = SC.Registry.byId(U.idOf(H.hygieneActor))
        if record and (record.state.downtime.nextPeeHour or 0) > hour() + 5.9 then
            check("hygiene_next_break_persisted",
                record.state.downtime.nextPeeHour <= hour() + 10.1,
                "next=" .. tostring(record.state.downtime.nextPeeHour)
                    .. " now=" .. tostring(hour()))
            setPhase("hygiene_female_setup", current)
        end
        return
    end
    if H.phase == "hygiene_female_setup" then
        local square = openOutdoorSquare(U, H.player)
        if not check("hygiene_female_outdoor_fixture", square ~= nil,
            "loaded free outdoor tile for seated outdoor pose") then
            setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "June", surname = "Tester",
                gender = "female", outfit = "Generic01" },
        })
        if not check("hygiene_female_spawn_request", ticket ~= nil, reason) then
            setPhase("finish", current) return
        end
        H.hygieneFemaleTicket = ticket
        setPhase("hygiene_female_spawn", current)
        return
    end
    if H.phase == "hygiene_female_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.hygieneFemaleTicket)
        if not actor then
            if current - H.phaseStartedAt > 12000 then
                result("FAIL", "hygiene_female_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        H.hygieneFemaleActor = actor
        check("hygiene_female_identity", actor:isFemale() == true,
            "spawned actor uses female stance routing")
        local record = SC.Registry.byId(U.idOf(actor))
        if not check("hygiene_female_registered", record ~= nil,
            "female test companion has a persistence record") then
            setPhase("finish", current) return
        end
        record.state.downtime.nextPeeHour = hour() - 0.1
        local stats = actor:getStats()
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
        end)
        setPhase("hygiene_female_action", current)
        return
    end
    if H.phase == "hygiene_female_action" then
        if current - H.phaseStartedAt > 45000 then
            result("FAIL", "hygiene_female_action_timeout",
                "no verified female relief animation")
            setPhase("finish", current) return
        end
        if current >= (H.hygieneNextUpdate or 0) then
            H.hygieneNextUpdate = current + 250
            local root = U.actorState(H.hygieneFemaleActor)
            root.senses = { current = { immediateCount = 0, pressure = 0 } }
            SC.Needs.update(H.hygieneFemaleActor, H.player, root)
        end
        if SC.NativeActions.visualStatus(H.hygieneFemaleActor,
            "pee_squat") == "active" then
            if not H.hygieneFemaleActiveAt then
                H.hygieneFemaleActiveAt = current
                local ax, ay, az = U.position(H.hygieneFemaleActor)
                H.player:teleportTo(ax + 1.5, ay + 1.5, az)
            end
            if current - H.hygieneFemaleActiveAt < 1600 then return end
            local name = tostring(H.config.run_id) .. "-pee-squat"
            local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
            check("hygiene_female_screenshot", ok, name .. ".png " .. tostring(failure))
            setPhase("hygiene_female_finish", current)
        end
        return
    end
    if H.phase == "hygiene_female_finish" then
        if current - H.phaseStartedAt > 20000 then
            result("FAIL", "hygiene_female_completion_timeout",
                "female visual did not complete")
            setPhase("finish", current) return
        end
        if current < (H.hygieneNextUpdate or 0) then return end
        H.hygieneNextUpdate = current + 250
        SC.Needs.update(H.hygieneFemaleActor, H.player)
        local record = SC.Registry.byId(U.idOf(H.hygieneFemaleActor))
        if record and (record.state.downtime.nextPeeHour or 0) > hour() + 5.9 then
            check("hygiene_female_next_break_persisted",
                record.state.downtime.nextPeeHour <= hour() + 10.1,
                "next=" .. tostring(record.state.downtime.nextPeeHour))
            setPhase("hygiene_toilet_setup", current)
        end
        return
    end
    if H.phase == "hygiene_toilet_setup" then
        local toilet = H.hygieneToiletObject
        if not check("hygiene_toilet_available", toilet ~= nil,
            "loaded toilet fixture is required for male seated use") then
            setPhase("finish", current) return
        end
        local targets = SC.Navigation.interactionTargets(H.player, toilet,
            { requireDirectAccess = true })
        local square
        for _, candidate in ipairs(targets) do
            if candidate:getRoom() ~= nil and U.isSquareFree(candidate) then
                square = candidate
                break
            end
        end
        if not check("hygiene_toilet_spawn_square", square ~= nil,
            "reachable interior tile beside fixture") then
            setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "Mason", surname = "Tester",
                gender = "man", outfit = "Generic01" },
        })
        if not check("hygiene_toilet_spawn_request", ticket ~= nil, reason) then
            setPhase("finish", current) return
        end
        H.hygieneToiletTicket = ticket
        setPhase("hygiene_toilet_spawn", current)
        return
    end
    if H.phase == "hygiene_toilet_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.hygieneToiletTicket)
        if not actor then
            if current - H.phaseStartedAt > 12000 then
                result("FAIL", "hygiene_toilet_spawn", reason)
                setPhase("finish", current)
            end
            return
        end
        H.hygieneToiletActor = actor
        check("hygiene_toilet_male_identity", actor:isFemale() ~= true,
            "fixture companion is male")
        local record = SC.Registry.byId(U.idOf(actor))
        if not check("hygiene_toilet_registered", record ~= nil,
            "male toilet test companion has persistence state") then
            setPhase("finish", current) return
        end
        record.state.downtime.nextPeeHour = hour() - 0.1
        local stableHash = U.stableHash
        U.stableHash = function(value)
            if string.find(tostring(value), ":toilet_style", 1, true) then
                return H.hygieneStandMode and 99 or 0
            end
            return stableHash(value)
        end
        local isInside = SC.BaseLife.isInside
        SC.BaseLife.isInside = function(candidate, ...)
            if candidate == actor then return true end
            return isInside(candidate, ...)
        end
        local stats = actor:getStats()
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
        end)
        setPhase("hygiene_toilet_action", current)
        return
    end
    if H.phase == "hygiene_toilet_action" then
        if current - H.phaseStartedAt > 50000 then
            result("FAIL", "hygiene_toilet_action_timeout",
                "male companion did not complete seated toilet use")
            setPhase("finish", current) return
        end
        if current >= (H.hygieneNextUpdate or 0) then
            H.hygieneNextUpdate = current + 250
            local root = U.actorState(H.hygieneToiletActor)
            root.senses = { current = { immediateCount = 0, pressure = 0 } }
            local handled, reason = SC.Needs.update(H.hygieneToiletActor,
                H.player, root)
            if current >= (H.hygieneNextTrace or 0) then
                H.hygieneNextTrace = current + 2000
                local state = SC.Needs.peek(H.hygieneToiletActor)
                result("PASS", "hygiene_toilet_progress",
                    tostring(handled) .. ":" .. tostring(reason)
                        .. " phase=" .. tostring(state and state.pee
                            and state.pee.phase)
                        .. " furniture=" .. tostring(
                            SC.NativeActions.furnitureStatus(H.hygieneToiletActor)))
            end
        end
        local state = SC.Needs.peek(H.hygieneToiletActor)
        if state and state.pee and state.pee.phase == "seated"
            and not H.hygieneToiletSeated then
            H.hygieneToiletSeated = true
            check("hygiene_male_seated_on_toilet",
                H.hygieneToiletActor:isSittingOnFurniture() == true,
                "native furniture seat entered")
        end
        local record = SC.Registry.byId(U.idOf(H.hygieneToiletActor))
        if H.hygieneToiletSeated and state and state.pee == nil
            and record and (record.state.downtime.nextPeeHour or 0) > hour() + 5.9 then
            check("hygiene_male_toilet_completed",
                H.hygieneToiletActor:isSittingOnFurniture() ~= true,
                "finished and stood through native get-up")
            H.hygieneStandMode = true
            record.state.downtime.nextPeeHour = hour() - 0.1
            setPhase("hygiene_toilet_stand_action", current)
        end
        return
    end
    if H.phase == "hygiene_toilet_stand_action" then
        if current - H.phaseStartedAt > 30000 then
            result("FAIL", "hygiene_toilet_stand_timeout",
                "male did not use the standing front approach")
            setPhase("finish", current) return
        end
        if current >= (H.hygieneNextUpdate or 0) then
            H.hygieneNextUpdate = current + 250
            local root = U.actorState(H.hygieneToiletActor)
            root.senses = { current = { immediateCount = 0, pressure = 0 } }
            local handled, reason = SC.Needs.update(H.hygieneToiletActor,
                H.player, root)
            if current >= (H.hygieneNextTrace or 0) then
                H.hygieneNextTrace = current + 2000
                local state = SC.Needs.peek(H.hygieneToiletActor)
                local task = state and state.pee
                local ax, ay = U.position(H.hygieneToiletActor)
                local tx, ty = task and task.toilet
                    and U.position(task.toilet.targets[1])
                result("PASS", "hygiene_toilet_stand_progress",
                    tostring(handled) .. ":" .. tostring(reason)
                        .. " phase=" .. tostring(task and task.phase)
                        .. " toilet=" .. tostring(task and task.toilet ~= nil)
                        .. " actor=" .. tostring(ax) .. "," .. tostring(ay)
                        .. " target=" .. tostring(tx) .. "," .. tostring(ty))
            end
        end
        local state = SC.Needs.peek(H.hygieneToiletActor)
        local task = state and state.pee
        if task and task.phase == "animating" and task.toilet ~= nil
            and not H.hygieneToiletStood then
            H.hygieneToiletStood = true
            local square = task.toilet.targets[1]
            check("hygiene_male_stands_in_front_of_toilet",
                U.sameSquare(H.hygieneToiletActor, square),
                "actor occupies the fixture's front approach square")
        end
        local record = SC.Registry.byId(U.idOf(H.hygieneToiletActor))
        if H.hygieneToiletStood and task == nil and record
            and (record.state.downtime.nextPeeHour or 0) > hour() + 5.9 then
            check("hygiene_male_standing_toilet_completed", true,
                "standing front approach finished")
            setPhase("finish", current)
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCHygieneProbe = Probe
return Probe
