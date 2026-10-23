-- SPDX-License-Identifier: MIT
-- Isolated cloned-save probe for the camp alarm. A resident sleeps in a real
-- bed by an outside wall; another stands in the yard just outside that wall
-- and a third further off. A zombie walks into the camp in front of the one
-- in the yard. The real decision loop must raise a stand-to from that sight,
-- the shout must wake the sleeper through the wall, the third must come to
-- the one who saw it, and the alarm must clear once the zombie is gone.
local Probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function position(object)
    return tonumber(call(object, "getX")), tonumber(call(object, "getY")),
        tonumber(call(object, "getZ"))
end

local function key(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function distance(a, b)
    local ax, ay = position(a)
    local bx, by = position(b)
    if not ax or not bx then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function outdoor(U, square)
    return square ~= nil and call(square, "getRoom") == nil
        and call(square, "getBuilding") == nil and U.isSquareFree(square)
end

local function campOutdoor(SC, square)
    return outdoor(SC.GameplayUtil, square) and SC.BaseLife.isInside(square) == true
end

local function bedsInCamp(SC, base)
    local U = SC.GameplayUtil
    local furnitureKind = SC.Downtime._furnitureForTests()
    local beds = {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and math.floor(tonumber(zone.z) or 0) == 0 then
            for x = zone.x1, zone.x2 do
                for y = zone.y1, zone.y2 do
                    local square = U.gridSquare(x, y, 0)
                    if square then
                        U.squareObjects(square, function(object)
                            if furnitureKind(object) == "rest_bed" then
                                beds[#beds + 1] = object
                                return false
                            end
                        end, 32)
                    end
                end
            end
        end
    end
    return beds
end

-- A yard tile within four tiles of the bed (a shout through one wall reaches
-- a sleeper five tiles off), a tile five further out for the zombie, and a
-- yard tile about eight to the side for the one who comes.
local function layoutFor(SC, bedSquare)
    local U = SC.GameplayUtil
    local bx, by = position(bedSquare)
    if not bx then return nil end
    for radius = 2, 4 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local yard = U.gridSquare(bx + dx, by + dy, 0)
                    if campOutdoor(SC, yard) and math.sqrt(dx * dx + dy * dy) <= 4.2 then
                        local length = math.sqrt(dx * dx + dy * dy)
                        local ux, uy = dx / length, dy / length
                        local zombie = U.gridSquare(math.floor(bx + dx + ux * 5 + 0.5),
                            math.floor(by + dy + uy * 5 + 0.5), 0)
                        local zx, zy = position(zombie)
                        if outdoor(U, zombie) and zx and SC.BaseAlert._distanceToCampForTests(
                                SC.BaseLife.active(), zx, zy, 0) <= 6 then
                            for _, side in ipairs({ 1, -1 }) do
                                for _, reach in ipairs({ 8, 7, 9, 6, 10 }) do
                                    local helper = U.gridSquare(
                                        math.floor(bx + dx - uy * side * reach + 0.5),
                                        math.floor(by + dy + ux * side * reach + 0.5), 0)
                                    if campOutdoor(SC, helper) then
                                        return { yard = yard, zombie = zombie, helper = helper }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function besideBed(SC, bed)
    local U = SC.GameplayUtil
    local square = call(bed, "getSquare")
    local x, y = position(square)
    if not x then return nil end
    local room = call(square, "getRoom")
    -- A resident on base duty rests only inside the camp, and a bed on the
    -- camp's edge can have its free side just beyond it.
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
            { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        local spot = U.gridSquare(x + step[1], y + step[2], 0)
        if spot and U.isSquareFree(spot) and SC.BaseLife.isInside(spot) == true
            and (room == nil or call(spot, "getRoom") == room) then
            return spot
        end
    end
    return nil
end

local function sleeping(SC, actor)
    local state = SC.Downtime.peek(actor)
    local active = state and state.active
    return actor:isAsleep() == true and active ~= nil and active.kind == "rest_bed"
        and active.sleepStarted == true, active
end

-- The save's own residents would hear the shout too. Send them well out of
-- earshot and leave them there on Stay for the length of the probe.
local function sendResidentsAway(SC, H, keep)
    local U = SC.GameplayUtil
    local base = SC.BaseLife.active()
    local moved, spots = 0, {}
    local west = (base.core and tonumber(base.core.x) or 0) - 45
    local north = base.core and tonumber(base.core.y) or 0
    for dx = 0, 12 do
        for dy = -6, 6 do
            local square = U.gridSquare(math.floor(west) - dx, math.floor(north) + dy, 0)
            if outdoor(U, square) and SC.BaseLife.isInside(square) ~= true then
                spots[#spots + 1] = square
            end
        end
    end
    for _, record in ipairs(SC.Registry.records() or {}) do
        if record.actor and not keep[record.id] and call(record.actor, "isDead") ~= true
            and #spots > 0 then
            local spot = table.remove(spots, 1)
            local ok = pcall(function()
                record.actor:teleportTo(spot:getX() + 0.5, spot:getY() + 0.5, 0)
            end)
            if ok then
                SC.Commands.issue(record.id, "stay", nil, H.player)
                moved = moved + 1
            end
        end
    end
    return moved, #spots
end

local function spawnCompanion(SC, square, forename)
    return SC.Actor.beginSpawn(square, {
        recruited = true,
        identity = { forename = forename, surname = "Alarm",
            gender = "woman", outfit = "Generic01" },
    })
end

local function screenshot(H, check, suffix)
    local name = tostring(H.config.run_id) .. "-base-alert-" .. suffix
    local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
    check("base_alert_screenshot_" .. suffix, ok, name .. ".png " .. tostring(failure))
end

local function setup(H, SC, check, result, setPhase, current)
    local base = SC.BaseLife.active()
    local roster = SC.Registry.snapshot() or {}
    if (not base or #roster == 0) and current - H.phaseStartedAt < 15000 then return end
    if not check("base_alert_base", base ~= nil, base and base.name or "none") then
        setPhase("finish", current) return
    end
    pcall(function() getGameTime():setTimeOfDay(12.0) end)
    local beds = bedsInCamp(SC, base)
    local chosen, layout
    for _, bed in ipairs(beds) do
        local found = layoutFor(SC, call(bed, "getSquare"))
        if found and besideBed(SC, bed) then chosen, layout = bed, found break end
    end
    if not check("base_alert_layout", chosen ~= nil, "beds=" .. tostring(#beds)
        .. (chosen and "" or "; none within four tiles of a free camp yard tile")) then
        setPhase("finish", current) return
    end
    local bedSquare = call(chosen, "getSquare")
    result("PASS", "base_alert_layout_detail",
        "bed=" .. key(position(bedSquare)) .. " yard=" .. key(position(layout.yard))
            .. " zombie=" .. key(position(layout.zombie))
            .. " helper=" .. key(position(layout.helper)) .. " beds=" .. tostring(#beds))
    local tickets = {}
    for _, row in ipairs({ { "sleeper", besideBed(SC, chosen), "Sleepy" },
            { "spotter", layout.yard, "Lookout" }, { "helper", layout.helper, "Helper" } }) do
        local ticket, reason = spawnCompanion(SC, row[2], row[3])
        if not check("base_alert_spawn_" .. row[1], ticket ~= nil, tostring(reason)) then
            setPhase("finish", current) return
        end
        tickets[row[1]] = ticket
    end
    H.baseAlert = { bed = chosen, layout = layout, tickets = tickets, actors = {},
        ids = {}, events = {}, traceAt = 0 }
    setPhase("base_alert_spawn", current)
end

local function spawn(H, SC, check, result, setPhase, current)
    local fixture = H.baseAlert
    for name, ticket in pairs(fixture.tickets) do
        if not fixture.actors[name] then
            local actor, reason = SC.Actor.pollSpawn(ticket)
            if actor then
                fixture.actors[name] = actor
                fixture.ids[name] = SC.Registry.idOf(actor)
            elseif reason ~= "spawn_pending" or current - H.phaseStartedAt > 15000 then
                result("FAIL", "base_alert_spawn_" .. name, tostring(reason))
                setPhase("finish", current) return
            end
        end
    end
    if not (fixture.actors.sleeper and fixture.actors.spotter and fixture.actors.helper) then return end
    local keep = {}
    for _, id in pairs(fixture.ids) do keep[id] = true end
    local moved, spots = sendResidentsAway(SC, H, keep)
    result("PASS", "base_alert_residents_away", "moved=" .. tostring(moved)
        .. " spots=" .. tostring(spots))
    for name, role in pairs({ sleeper = "generalist", spotter = "guard", helper = "generalist" }) do
        -- New recruits scavenge when safe; a bounded search would keep the
        -- sleeper from its bed for the length of the probe.
        SC.Commands.issue(fixture.ids[name], "set_scavenge", false, H.player)
        pcall(SC.Encounter.cancelScavenge, fixture.actors[name], "base_alert_fixture")
        local ordered, reason = SC.Commands.issue(fixture.ids[name], "set_base_role",
            { role = role }, H.player)
        if not check("base_alert_duty_" .. name, ordered == true, tostring(reason)) then
            setPhase("finish", current) return
        end
    end
    for _, name in ipairs({ "spotter", "helper" }) do
        pcall(function() fixture.actors[name]:getStats():set(CharacterStat.FATIGUE, 0.0) end)
    end
    -- Going to bed is not what this probe tests: hold the sleeper's own
    -- decisions and walk it into bed the way the sleep probe does, then hand
    -- it back to the ordinary loop once it is asleep.
    local sleeper = fixture.actors.sleeper
    local original = SC.Decision.update
    fixture.originalDecisionUpdate, fixture.holdSleeper = original, true
    SC.Decision.update = function(actor, ...)
        if actor == sleeper and fixture.holdSleeper then return true, "base_alert_probe_bed" end
        return original(actor, ...)
    end
    pcall(SC.BaseWork.cancel, sleeper, "base_alert_fixture")
    setPhase("base_alert_bed", current)
end

local calm = { snapshot = { immediateCount = 0, threatCount = 0, threats = {},
    heardThreats = {}, player = { danger = 0 }, indoors = true } }

local function bed(H, SC, check, result, setPhase, current)
    local fixture = H.baseAlert
    local sleeper = fixture.actors.sleeper
    local asleep, active = sleeping(SC, sleeper)
    if not asleep and fixture.holdSleeper then
        pcall(function() sleeper:getStats():set(CharacterStat.FATIGUE, 0.85) end)
        local ok, accepted, reason = pcall(SC.Downtime.update, sleeper, H.player, calm, "rest_bed")
        local senses = SC.GameplayUtil.actorState(sleeper, calm)
        local seen = senses and (senses.senses and senses.senses.current or senses.snapshot) or {}
        fixture.bedReason = (ok and tostring(reason) or tostring(accepted))
            .. " at=" .. key(position(sleeper))
            .. " inside=" .. tostring(SC.BaseLife.isInside(sleeper))
            .. " order=" .. tostring((SC.Commands.peek(sleeper) or {}).order)
            .. " threats=" .. tostring(seen.threatCount) .. "/" .. tostring(seen.immediateCount)
            .. " playerDanger=" .. tostring(seen.player and seen.player.danger)
        asleep, active = sleeping(SC, sleeper)
        if current >= (fixture.bedTraceAt or 0) then
            fixture.bedTraceAt = current + 5000
            print("SC_REAL_SANDBOX|BED_TRACE|t=" .. tostring(current - H.phaseStartedAt)
                .. " " .. tostring(fixture.bedReason)
                .. " target=" .. key(position(active and call(active.object, "getSquare"))))
        end
    end
    if asleep then
        -- In a real bed the downtime owner keeps it asleep under the
        -- ordinary loop from here.
        fixture.holdSleeper = false
        local square = call(active.object, "getSquare")
        local layout = layoutFor(SC, square) or fixture.layout
        fixture.layout, fixture.bedSquare = layout, square
        result("PASS", "base_alert_sleeper_in_bed", "real bed=" .. key(position(square))
            .. " yardToBed=" .. string.format("%.1f", distance(layout.yard, square))
            .. " after " .. tostring(current - H.phaseStartedAt) .. " ms")
        setPhase("base_alert_stage", current)
        return
    end
    if current - H.phaseStartedAt < 45000 then return end
    -- The real walk to a bed did not finish here. Lay the sleeper down beside
    -- the chosen bed instead and keep its decisions held until the alarm
    -- wakes it; the wake itself still goes through Downtime.wakeForAlarm.
    pcall(SC.Downtime.cancel, sleeper, "base_alert_fixture")
    local spot = besideBed(SC, fixture.bed)
    local laid = spot and pcall(function()
        sleeper:teleportTo(spot:getX() + 0.5, spot:getY() + 0.5, 0)
        SC.Downtime._sleepStateForTests(sleeper, { kind = "rest_bed", sleepStarted = true })
        sleeper:setAsleep(true)
    end)
    if not check("base_alert_sleeper_in_bed", laid and sleeper:isAsleep() == true,
        "emulated beside the bed after the real walk stalled: " .. tostring(fixture.bedReason)) then
        SC.Decision.update = fixture.originalDecisionUpdate
        setPhase("finish", current) return
    end
    fixture.emulatedSleep, fixture.bedSquare = true, call(fixture.bed, "getSquare")
    setPhase("base_alert_stage", current)
end

local function stage(H, SC, check, result, setPhase, current)
    local fixture = H.baseAlert
    local layout = fixture.layout
    local placed, reason = pcall(function()
        fixture.actors.spotter:teleportTo(layout.yard:getX() + 0.5, layout.yard:getY() + 0.5, 0)
        fixture.actors.helper:teleportTo(layout.helper:getX() + 0.5, layout.helper:getY() + 0.5, 0)
    end)
    if not check("base_alert_staged", placed, tostring(reason)) then
        setPhase("finish", current) return
    end
    if type(createZombie) ~= "function" then
        result("FAIL", "base_alert_zombie", "createZombie unavailable")
        setPhase("finish", current) return
    end
    local zx, zy = position(layout.zombie)
    local zombie = createZombie(zx + 0.5, zy + 0.5, 0, nil, 0, IsoDirections.S)
    if not check("base_alert_zombie", zombie ~= nil, "at=" .. key(zx, zy, 0)) then
        setPhase("finish", current) return
    end
    fixture.zombie, fixture.spawnedAt = zombie, current
    SC.BaseAlert.reset()
    screenshot(H, check, "staged")
    setPhase("base_alert_run", current)
end

local function trace(SC, fixture, current)
    local alert = SC.BaseAlert.peek()
    local parts = { "t=" .. tostring(current - fixture.spawnedAt),
        "level=" .. tostring(alert and alert.level),
        "spotter=" .. tostring(alert and alert.spotterId) }
    for _, name in ipairs({ "spotter", "helper", "sleeper" }) do
        local actor = fixture.actors[name]
        local decision = SC.Decision.peek(actor) or {}
        local directive = SC.BaseAlert.directiveFor(actor, current)
        parts[#parts + 1] = name .. "=" .. key(position(actor))
            .. ":" .. tostring(decision.current) .. "/" .. tostring(decision.intent)
            .. ":" .. tostring(directive and directive.mode)
            .. ":asleep=" .. tostring(actor:isAsleep())
    end
    parts[#parts + 1] = "helperToSpotter=" .. string.format("%.1f",
        distance(fixture.actors.helper, fixture.actors.spotter))
    parts[#parts + 1] = "zombie=" .. key(position(fixture.zombie))
        .. ":dead=" .. tostring(call(fixture.zombie, "isDead"))
    print("SC_REAL_SANDBOX|ALERT_TRACE|" .. table.concat(parts, " "))
end

local function run(H, SC, check, result, setPhase, current)
    local fixture = H.baseAlert
    local events = fixture.events
    local alert = SC.BaseAlert.peek()
    if current >= fixture.traceAt then
        fixture.traceAt = current + 1000
        trace(SC, fixture, current)
    end
    local sleeper = fixture.actors.sleeper
    if not events.raisedAt and alert then
        events.raisedAt = current
        local fromFixture = alert.spotterId == fixture.ids.spotter
            or alert.spotterId == fixture.ids.helper
        check("base_alert_raised", alert.level == "stand_to" and fromFixture,
            "level=" .. tostring(alert.level) .. " spotter=" .. tostring(alert.spotterId)
                .. " after " .. tostring(current - fixture.spawnedAt) .. " ms")
        screenshot(H, check, "raised")
    end
    if not events.raisedAt and current - fixture.spawnedAt > 15000 then
        result("FAIL", "base_alert_raised", "no alarm 15 s after the zombie came into the camp")
        setPhase("finish", current) return
    end
    if events.raisedAt and not events.wokeAt then
        if sleeper:isAsleep() ~= true then
            events.wokeAt = current
            fixture.holdSleeper = false
            local state = SC.Downtime.peek(sleeper) or {}
            local told = alert and alert.told[fixture.ids.sleeper]
            check("base_alert_sleeper_woken", told ~= nil and told.woken == true
                    and state.alarmInterruptedSleep == true and state.active == nil,
                "after " .. tostring(current - events.raisedAt) .. " ms told="
                    .. tostring(told ~= nil) .. " woken=" .. tostring(told and told.woken)
                    .. " interrupted=" .. tostring(state.alarmInterruptedSleep))
        elseif current - events.raisedAt > 10000 then
            events.wokeAt = current
            result("FAIL", "base_alert_sleeper_woken", "still asleep 10 s after the shout; told="
                .. tostring(alert and alert.told[fixture.ids.sleeper] ~= nil))
        end
    end
    if events.raisedAt and not events.arrivedAt and alert then
        local helperIsSpotter = alert.spotterId == fixture.ids.helper
        local comer = helperIsSpotter and fixture.actors.spotter or fixture.actors.helper
        local seen = SC.GameplayUtil.resolveActor(alert.spotterId)
        local responder = alert.responders[SC.Registry.idOf(comer)]
        local fighting = (SC.Decision.peek(comer) or {}).current == "combat"
        if (responder and responder.arrived) or (seen and distance(comer, seen) <= 3.5) then
            events.arrivedAt = current
            check("base_alert_responder_came", true, "after " .. tostring(current - events.raisedAt)
                .. " ms distance=" .. string.format("%.1f", seen and distance(comer, seen) or -1)
                .. " toZombie=" .. string.format("%.1f", distance(comer, fixture.zombie))
                .. " caller=" .. (helperIsSpotter and "helper" or "yard")
                .. " fighting=" .. tostring(fighting))
            screenshot(H, check, "answered")
        elseif current - events.raisedAt > 60000 then
            events.arrivedAt = current
            result("FAIL", "base_alert_responder_came", "not beside the spotter 60 s after the call; distance="
                .. string.format("%.1f", seen and distance(comer, seen) or -1))
        end
    end
    -- Once answered, or after 45 s, take the zombie away so the camp can clear.
    if events.raisedAt and not events.goneAt and (events.arrivedAt
            or current - events.raisedAt > 45000 or call(fixture.zombie, "isDead") == true) then
        events.goneAt = current
        if call(fixture.zombie, "isDead") ~= true then
            pcall(function() fixture.zombie:removeFromWorld() end)
            pcall(function() fixture.zombie:removeFromSquare() end)
        end
    end
    if events.goneAt and not alert then
        local cleared = SC.BaseAlert.lastCleared or {}
        check("base_alert_cleared", cleared.reason == "clear",
            "reason=" .. tostring(cleared.reason) .. " after "
                .. tostring(current - events.goneAt) .. " ms")
        setPhase("finish", current) return
    end
    if events.goneAt and current - events.goneAt > 90000 then
        result("FAIL", "base_alert_cleared", "alarm still up 90 s after the zombie was gone")
        setPhase("finish", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "base_alert_setup" then return setup(H, SC, check, result, setPhase, current) end
    if H.phase == "base_alert_spawn" then return spawn(H, SC, check, result, setPhase, current) end
    if H.phase == "base_alert_bed" then return bed(H, SC, check, result, setPhase, current) end
    if H.phase == "base_alert_stage" then return stage(H, SC, check, result, setPhase, current) end
    if H.phase == "base_alert_run" then return run(H, SC, check, result, setPhase, current) end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBaseAlertProbe = Probe
return Probe
