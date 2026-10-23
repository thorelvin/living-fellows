-- SPDX-License-Identifier: MIT
-- The camp alarm. A resident who sees zombies at the camp raises it, and the
-- word spreads only as far as a voice carries: walls and floors muffle a call,
-- a sleeper wakes only to a shout, and nobody learns of it by magic. Those who
-- answer gather beside the resident who saw the zombies; the rest stand to.
-- One alert per camp, rebuilt from fresh sightings, with a deadline on every
-- wait. Senses, combat and navigation stay authoritative; this only decides
-- who knows, who goes and where.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseAlert = SC.BaseAlert or {}
local Alert = SC.BaseAlert

local LEVELS = { contact = 1, stand_to = 2, fall_back = 3 }
local alert
local serial = 0
-- Per resident, kept across alerts: when it was last woken by one, how long
-- it stays groggy, and when it last spoke for the alarm.
local memory = {}

local function U() return SC.GameplayUtil end
local function cfg(key, fallback)
    local value = U().config(key)
    if value == nil then return fallback end
    return value
end
local function now() return U().nowMs() end
local function idOf(actor) return actor and U().idOf(actor) or nil end
local function memoryFor(id)
    local entry = memory[id]
    if not entry then
        entry = {}
        memory[id] = entry
    end
    return entry
end
local function position(value)
    local x, y, z = U().position(value)
    if x == nil or y == nil then return nil end
    return x, y, z or 0
end
local function floorOf(z) return math.floor(tonumber(z) or 0) end

-- Horizontal distance from a point to the camp's own floor rectangles. A
-- zombie on another floor is never "at the camp" for this purpose.
local function distanceToCamp(base, x, y, z)
    local best = math.huge
    local floor = floorOf(z)
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" and floorOf(zone.z) == floor then
            local dx = x < zone.x1 and zone.x1 - x or x > zone.x2 + 1 and x - zone.x2 - 1 or 0
            local dy = y < zone.y1 and zone.y1 - y or y > zone.y2 + 1 and y - zone.y2 - 1 or 0
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < best then best = distance end
        end
    end
    return best
end
Alert._distanceToCampForTests = distanceToCamp

-- What this resident's own eyes report, graded. Only visible, live contacts
-- reach snapshot.threats, so hearing alone never raises the alarm.
local function assess(base, snapshot)
    local threats = type(snapshot) == "table" and snapshot.threats or nil
    if type(threats) ~= "table" or #threats == 0 then return nil end
    local margin = tonumber(cfg("baseAlertContactMargin", 8)) or 8
    local count, inside, breach = 0, 0, false
    local nearest, nearestDistance
    for index = 1, math.min(#threats, 32) do
        local threat = threats[index]
        local tx, ty, tz = tonumber(threat and threat.x), tonumber(threat and threat.y),
            tonumber(threat and threat.z) or 0
        if tx and ty then
            local distance = distanceToCamp(base, tx, ty, tz)
            if distance <= margin then
                count = count + 1
                if distance <= 0 then inside = inside + 1 end
                if threat.breaching == true then breach = true end
                if not nearestDistance or distance < nearestDistance then
                    nearest, nearestDistance = threat, distance
                end
            end
        end
    end
    if count == 0 then return nil end
    local level = "contact"
    if count >= (tonumber(cfg("baseAlertFallBackCount", 8)) or 8) then
        level = "fall_back"
    elseif count >= (tonumber(cfg("baseAlertStandToCount", 3)) or 3)
        or inside > 0 or breach
        or (tonumber(snapshot.immediateCount) or 0) > 0 then
        level = "stand_to"
    end
    return level, {
        x = tonumber(nearest.x), y = tonumber(nearest.y), z = tonumber(nearest.z) or 0,
        count = count, inside = inside, breach = breach,
    }
end
Alert._assessForTests = assess

local function sleeping(actor)
    local state = SC.Downtime and type(SC.Downtime.peek) == "function"
        and SC.Downtime.peek(actor) or nil
    local active = type(state) == "table" and state.active or nil
    if type(active) == "table" and active.kind == "rest_bed"
        and active.sleepStarted == true then return true end
    return select(1, U().call(actor, "isAsleep")) == true
end

local function hasTrait(actor, name)
    if not CharacterTrait then return false end
    local ok, trait = pcall(function() return CharacterTrait[name] end)
    return ok and trait ~= nil and select(1, U().call(actor, "hasTrait", trait)) == true
end

local function hearing(actor)
    if hasTrait(actor, "DEAF") then return 0 end
    if hasTrait(actor, "HARD_OF_HEARING") then return 0.5 end
    if hasTrait(actor, "KEEN_HEARING") then return 1.5 end
    return 1
end

local function buildingOf(actor)
    local square = U().squareOf(actor)
    if not square then return false end
    return select(1, U().call(square, "getBuilding")) or false
end

-- Each wall between two people halves how far a voice carries, as does each
-- floor between them and being asleep. A deaf resident hears nothing.
local function audible(source, listener, radius, asleep)
    local sx, sy, sz = position(source)
    local lx, ly, lz = position(listener)
    if not sx or not lx then return false end
    local reach = radius * hearing(listener)
    if reach <= 0 then return false end
    local floors = math.abs(floorOf(sz) - floorOf(lz))
    reach = reach * (0.5 ^ floors)
    local sourceBuilding, listenerBuilding = buildingOf(source), buildingOf(listener)
    if sourceBuilding ~= listenerBuilding then
        reach = reach * 0.5
        if sourceBuilding and listenerBuilding then reach = reach * 0.5 end
    end
    if asleep then reach = reach * (tonumber(cfg("baseAlertSleepHearing", 0.5)) or 0.5) end
    local dx, dy = sx - lx, sy - ly
    return dx * dx + dy * dy <= reach * reach
end
Alert._audibleForTests = audible

-- Where, as the caller sees it: "on the north side", "on the southwest
-- side", or "right here" when it is on top of them.
local function direction(fromX, fromY, toX, toY)
    if not (fromX and fromY and toX and toY) then return "right here" end
    local dx, dy = toX - fromX, toY - fromY
    local horizontal = math.abs(dx) >= 1.5 and (dx > 0 and "east" or "west") or nil
    local vertical = math.abs(dy) >= 1.5 and (dy > 0 and "south" or "north") or nil
    local side = horizontal and vertical and vertical .. horizontal or horizontal or vertical
    return side and ("on the " .. side .. " side") or "right here"
end
Alert._directionForTests = direction

local function countWord(count)
    count = tonumber(count) or 1
    if count <= 1 then return "one" end
    if count == 2 then return "two" end
    if count <= 4 then return "three or four" end
    if count <= 7 then return "a handful" end
    return "a whole crowd"
end

local function residents()
    local result = {}
    if not SC.BaseLife or type(SC.BaseLife.dutyResidentIds) ~= "function" then return result end
    for _, id in ipairs(SC.BaseLife.dutyResidentIds()) do
        local actor = U().resolveActor(id)
        if actor and U().isValidActor(actor) and not U().isDead(actor) then
            result[#result + 1] = { id = id, actor = actor }
        end
        if #result >= 16 then break end
    end
    return result
end

-- An alarm call itself always gets out (force); acknowledgements and the
-- like wait four seconds between lines from the same resident.
local function speak(actor, topic, arguments, fallback, force)
    local id = idOf(actor)
    if not actor or not id then return false end
    local entry = memoryFor(id)
    local current = now()
    if force ~= true and current - (entry.spokeAt or -math.huge) < 4000 then return false end
    local spoken = false
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        spoken = SC.Dialogue.say(actor, topic, nil, arguments,
            { fallback = fallback }) == true
    elseif fallback then
        spoken = U().say(actor, fallback) == true
    end
    if spoken then entry.spokeAt = current end
    return spoken
end

local function capable(actor)
    if SC.Medical and type(SC.Medical.isDowned) == "function"
        and SC.Medical.isDowned(actor) == true then return false end
    local panic = U().moodleLevel and U().moodleLevel(actor, "PANIC", 0) or 0
    return (tonumber(panic) or 0) < 3
end

-- Who answers is the camp's own defence policy. Contact sends the resident on
-- watch and one backup; a stand-to sends whoever the policy names; anyone
-- else told stands to where they are. A fall-back moves everybody.
local function assignRoles(entries, spotterId, level, current)
    local base = SC.BaseLife.active()
    local policy = base and base.settings and base.settings.defense or "rotation"
    local function onWatch(id)
        return type(SC.BaseLife.guardStatus) == "function"
            and select(1, SC.BaseLife.guardStatus(id, current)) == true
    end
    local function isGuard(id)
        local resident = type(SC.BaseLife.resident) == "function"
            and SC.BaseLife.resident(id) or nil
        return type(resident) == "table" and resident.role == "guard"
    end
    local backups = level == "contact"
        and (tonumber(cfg("baseAlertContactBackups", 1)) or 1)
        or (tonumber(cfg("baseAlertRotationResponders", 2)) or 2)
    for _, entry in ipairs(entries) do
        local role
        if level == "fall_back" then
            role = "fall_back"
        elseif not capable(entry.actor) then
            role = "stand_to"
        elseif onWatch(entry.id) or (level ~= "contact" and policy == "role_based"
            and isGuard(entry.id)) or (level ~= "contact" and policy == "all_hands") then
            role = "respond"
        elseif backups > 0 and (level == "contact" or policy == "rotation") then
            role = "respond"
            backups = backups - 1
        else
            role = level == "contact" and "none" or "stand_to"
        end
        alert.told[entry.id].role = role
    end
end

local function wake(entry, current)
    local id = entry.id
    local remembered = memoryFor(id)
    if alert.level ~= "fall_back" and remembered.wokenAt
        and current - remembered.wokenAt
            < (tonumber(cfg("baseAlertWakeCooldownMs", 600000)) or 600000) then
        return false
    end
    if not SC.Downtime or type(SC.Downtime.wakeForAlarm) ~= "function" then return false end
    if SC.Downtime.wakeForAlarm(entry.actor) ~= true then return false end
    remembered.wokenAt = current
    local spread = math.max(0, tonumber(cfg("baseAlertGrogSpreadMs", 3000)) or 3000)
    local hash = math.abs(tonumber(U().stableHash(tostring(id) .. ":grog")) or 0)
    remembered.grogUntil = current + (tonumber(cfg("baseAlertGrogMinMs", 3000)) or 3000)
        + (spread > 0 and hash % spread or 0)
    remembered.wokeFor = alert.id
    alert.woken[id] = true
    return true
end

-- One call, heard only within reach. At a stand-to or fall-back, an awake
-- resident who heard the shout passes it on once; sleepers within reach of a
-- shout are woken. A quiet contact call wakes nobody.
local function spread(current)
    local spotter = U().resolveActor(alert.spotterId)
    if not spotter then return end
    local loud = LEVELS[alert.level] >= LEVELS.stand_to
    local radius = loud and (tonumber(cfg("baseAlertShoutRadius", 20)) or 20)
        or (tonumber(cfg("baseAlertCallRadius", 10)) or 10)
    local entries = residents()
    local sources = { { actor = spotter, hop = 0 } }
    local hops = loud and (tonumber(cfg("baseAlertRelayHops", 1)) or 1) or 0
    local relayed, newlyTold = 0, {}
    local index = 1
    while index <= #sources do
        local source = sources[index]
        index = index + 1
        for _, entry in ipairs(entries) do
            if entry.id ~= alert.spotterId and not alert.told[entry.id] then
                local asleep = sleeping(entry.actor)
                if audible(source.actor, entry.actor, radius, asleep) then
                    local woke = false
                    if asleep and loud then woke = wake(entry, current) end
                    if not asleep or woke then
                        alert.told[entry.id] = { at = current, hop = source.hop,
                            woken = woke }
                        newlyTold[#newlyTold + 1] = entry
                        if not asleep and source.hop < hops and relayed < 2 then
                            relayed = relayed + 1
                            sources[#sources + 1] = { actor = entry.actor,
                                hop = source.hop + 1, relay = true }
                        end
                    end
                end
            end
        end
        if source.relay then
            local tx, ty = alert.threat.x, alert.threat.y
            local x, y = position(source.actor)
            speak(source.actor, "camp_alert.relay",
                { direction(x, y, tx, ty) },
                "Up! They're at the camp!")
        end
    end
    local roleEntries = {}
    for _, entry in ipairs(entries) do
        if alert.told[entry.id] and entry.id ~= alert.spotterId then
            roleEntries[#roleEntries + 1] = entry
        end
    end
    -- Nearest first, so the backups are the ones closest to the spotter.
    local sx, sy = position(spotter)
    table.sort(roleEntries, function(a, b)
        local ax, ay = position(a.actor)
        local bx, by = position(b.actor)
        local da = ax and sx and (ax - sx) ^ 2 + (ay - sy) ^ 2 or math.huge
        local db = bx and sx and (bx - sx) ^ 2 + (by - sy) ^ 2 or math.huge
        if da ~= db then return da < db end
        return tostring(a.id) < tostring(b.id)
    end)
    assignRoles(roleEntries, alert.spotterId, alert.level, current)
    return newlyTold
end

local function call(spotter, current)
    local sx, sy, sz = position(spotter)
    local threat = alert.threat
    local words = { direction(sx, sy, threat.x, threat.y), countWord(threat.count) }
    local fallbacks = {
        contact = "Walker at the fence.",
        stand_to = "Everybody up! They're at the camp!",
        fall_back = "Too many! Fall back!",
    }
    alert.calledAt = current
    speak(spotter, "camp_alert." .. alert.level, words, fallbacks[alert.level], true)
    -- A call is a real noise. The quiet word at a contact barely carries; a
    -- shout reaches the dead as surely as the living.
    if sx and type(addSound) == "function" then
        local loud = LEVELS[alert.level] >= LEVELS.stand_to
        local radius = loud and (tonumber(cfg("baseAlertShoutSoundRadius", 20)) or 20)
            or (tonumber(cfg("baseAlertQuietSoundRadius", 5)) or 5)
        pcall(addSound, spotter, math.floor(sx), math.floor(sy), math.floor(sz), radius, loud and 20 or 5)
    end
    spread(current)
end

local function clear(current, reason)
    local finished = alert
    alert = nil
    if not finished then return end
    local spotter = U().resolveActor(finished.spotterId)
    local told = 0
    for _ in pairs(finished.told) do told = told + 1 end
    if reason == "clear" and spotter and told > 0 and not sleeping(spotter) then
        speak(spotter, "camp_alert.clear", nil, "All clear.")
    end
    for id in pairs(finished.woken) do
        if SC.Downtime and type(SC.Downtime.alarmOver) == "function" then
            local actor = U().resolveActor(id)
            if actor then SC.Downtime.alarmOver(actor) end
        end
    end
    Alert.lastCleared = { id = finished.id, at = current, reason = reason,
        level = finished.level }
end

function Alert.pulse(current)
    current = current or now()
    if not alert then return end
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base or base.id ~= alert.baseId then return clear(current, "camp_changed") end
    local quiet = alert.level == "contact"
        and (tonumber(cfg("baseAlertClearContactMs", 30000)) or 30000)
        or (tonumber(cfg("baseAlertClearMs", 60000)) or 60000)
    if current - alert.lastSeenAt >= quiet then return clear(current, "clear") end
    if current - alert.startedAt >= (tonumber(cfg("baseAlertMaxMs", 600000)) or 600000) then
        return clear(current, "timeout")
    end
end

local function spotterUsable(id)
    local actor = id and U().resolveActor(id) or nil
    return actor ~= nil and U().isValidActor(actor) and not U().isDead(actor)
        and not sleeping(actor)
end

-- A resident's own sighting raises a new alert, keeps one alive, or escalates
-- it. Whoever sees the escalation calls it, and becomes the one to rally to.
local function raise(actor, level, threat, current)
    local base = SC.BaseLife.active()
    local id = idOf(actor)
    local last = Alert.lastCleared
    -- An alert that ran out of time without clearing (a walker pacing behind
    -- the fence) is not raised again at once for the same or a lesser call.
    if not alert and last and last.reason == "timeout"
        and current - last.at < (tonumber(cfg("baseAlertTimeoutCooldownMs", 300000)) or 300000)
        and LEVELS[level] <= (LEVELS[last.level] or 0) then
        return false
    end
    if not alert then
        serial = serial + 1
        alert = { id = serial, baseId = base.id, level = level, spotterId = id,
            threat = threat, startedAt = current, lastSeenAt = current,
            told = {}, woken = {}, responders = {} }
        call(actor, current)
        return true
    end
    alert.lastSeenAt = current
    if LEVELS[level] > LEVELS[alert.level] then
        alert.level, alert.spotterId, alert.threat = level, id, threat
        -- The new call is heard afresh: spread re-tells and re-assigns.
        alert.told = {}
        call(actor, current)
        return true
    end
    if id == alert.spotterId then
        alert.threat = threat
    elseif not spotterUsable(alert.spotterId) then
        alert.spotterId, alert.threat = id, threat
    end
    return false
end

function Alert.observe(actor, player, snapshot, commands, current)
    current = current or now()
    if cfg("baseAlertEnabled", true) == false then return false end
    Alert.pulse(current)
    if type(commands) ~= "table" or commands.recruited ~= true
        or commands.order ~= "base_duty" then return false end
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base or not U().isValidActor(actor) or U().isDead(actor) then return false end
    -- Eyes shut: a sleeper learns of zombies from a shout, never by sight.
    if sleeping(actor) then return false end
    local level, threat = assess(base, snapshot)
    if not level then return false end
    return raise(actor, level, threat, current)
end

local function slots(spotter)
    local sx, sy, sz = position(spotter)
    if not sx then return {} end
    local tx, ty = alert.threat.x or sx, alert.threat.y or sy
    local vx, vy = sx - tx, sy - ty
    local length = math.sqrt(vx * vx + vy * vy)
    if length < 0.1 then vx, vy, length = 0, 1, 1 end
    vx, vy = vx / length, vy / length
    local px, py = -vy, vx
    local back = tonumber(cfg("baseAlertSlotDistance", 2.5)) or 2.5
    local offsets = { { back, 0 }, { back, 1.5 }, { back, -1.5 },
        { back + 1.5, 0.75 }, { back + 1.5, -0.75 }, { 1, 2 }, { 1, -2 } }
    local inside, any, seen = {}, {}, {}
    for _, offset in ipairs(offsets) do
        local x = math.floor(sx + vx * offset[1] + px * offset[2])
        local y = math.floor(sy + vy * offset[1] + py * offset[2])
        local key = x .. ":" .. y
        if not seen[key] then
            seen[key] = true
            local square = U().gridSquare(x, y, floorOf(sz))
            if square and U().isSquareFree(square) then
                any[#any + 1] = square
                if SC.BaseLife.isInside(square) == true then inside[#inside + 1] = square end
            end
        end
    end
    return #inside > 0 and inside or any
end
Alert._slotsForTests = function(spotter) return slots(spotter) end

local function scoreFor(role, level)
    if role == "fall_back" then return 96 end
    if role == "respond" then return level == "contact" and 70 or 88 end
    return 64
end

-- What the alarm asks of this resident now, or nil. Decision scores it as an
-- ordinary candidate, so immediate danger, critical care and the resident's
-- own combat still come first.
function Alert.directiveFor(actor, current)
    current = current or now()
    Alert.pulse(current)
    if not alert then return nil end
    local id = idOf(actor)
    if not id then return nil end
    local remembered = memory[id]
    if remembered and remembered.wokeFor == alert.id
        and current < (remembered.grogUntil or 0) then
        return { mode = "waking", score = 90, alertId = alert.id, level = alert.level }
    end
    if id == alert.spotterId then
        if alert.level == "fall_back" then
            return { mode = "fall_back", score = 96, alertId = alert.id,
                level = alert.level, threat = alert.threat, run = true }
        end
        -- Eyes on it while the others come, then back to work: the alert
        -- itself stays up until the camp has been quiet for a while.
        if current - (alert.calledAt or current)
            >= (tonumber(cfg("baseAlertWatchMs", 45000)) or 45000) then return nil end
        return { mode = "watch", score = 66, alertId = alert.id,
            level = alert.level, threat = alert.threat }
    end
    local told = alert.told[id]
    if not told or told.role == nil or told.role == "none" then return nil end
    if told.role == "stand_to" and current - told.at
        >= (tonumber(cfg("baseAlertStandToMs", 120000)) or 120000) then return nil end
    local directive = { mode = told.role, score = scoreFor(told.role, alert.level),
        alertId = alert.id, level = alert.level, threat = alert.threat,
        spotterId = alert.spotterId, run = LEVELS[alert.level] >= LEVELS.stand_to }
    if told.role == "respond" then
        local responder = alert.responders[id]
        if not responder then
            responder = { since = current, deadline = current
                + (tonumber(cfg("baseAlertRespondDeadlineMs", 60000)) or 60000) }
            alert.responders[id] = responder
        end
        if responder.arrived or current >= responder.deadline then
            responder.holdUntil = responder.holdUntil
                or current + (tonumber(cfg("baseAlertHoldMs", 60000)) or 60000)
            if current >= responder.holdUntil then return nil end
            directive.mode = "hold"
        end
    end
    return directive
end

-- True while the alarm should take this resident away from what it is doing.
function Alert.preempts(actor, current)
    local directive = Alert.directiveFor(actor, current)
    return directive ~= nil and (directive.mode == "respond"
        or directive.mode == "fall_back" or directive.mode == "stand_to"
        or directive.mode == "watch")
end

-- The spotter's alarm call replaces the generic "Zombie!" warning.
function Alert.voiced(actor, current)
    return alert ~= nil and idOf(actor) == alert.spotterId
        and (current or now()) - (alert.calledAt or -math.huge) < 30000
end

local function face(actor, threat)
    if type(threat) ~= "table" or not threat.x then return false end
    return U().move(actor, "walk", {
        action = "face_alert",
        targetPosition = { x = threat.x, y = threat.y, z = threat.z or 0 },
        stableFacing = true,
        sharedAlert = true,
    }) == true
end

function Alert.act(actor, player, directive, snapshot)
    if type(directive) ~= "table" or not alert or directive.alertId ~= alert.id then
        return false, "base_alert_stale"
    end
    local current = now()
    local id = idOf(actor)
    if directive.mode == "waking" then
        U().stop(actor)
        local remembered = memoryFor(id)
        if remembered.wokenSpokeFor ~= alert.id then
            remembered.wokenSpokeFor = alert.id
            speak(actor, "camp_alert.woken", nil, "I'm up.")
        end
        return true, "base_alert_waking"
    end
    if directive.mode == "watch" or directive.mode == "hold" or directive.mode == "stand_to" then
        if face(actor, directive.threat) then return true, "base_alert_" .. directive.mode end
        U().stop(actor)
        return true, "base_alert_" .. directive.mode
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    local targets, action
    if directive.mode == "fall_back" then
        local point = SC.BaseLife.zoneCenter("rally") or (SC.BaseLife.active() or {}).core
        targets, action = {}, "move_to_alert_fallback"
        local px, py, pz = point and tonumber(point.x), point and tonumber(point.y),
            point and tonumber(point.z) or 0
        if px and py then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local square = U().gridSquare(math.floor(px) + dx, math.floor(py) + dy,
                        floorOf(pz))
                    if square and U().isSquareFree(square) then targets[#targets + 1] = square end
                end
            end
        end
    else
        local spotter = U().resolveActor(alert.spotterId)
        if not spotter then return false, "base_alert_spotter_missing" end
        local ax, ay, az = position(actor)
        local sx, sy, sz = position(spotter)
        if ax and sx and floorOf(az) == floorOf(sz)
            and (ax - sx) ^ 2 + (ay - sy) ^ 2
                <= (tonumber(cfg("baseAlertArrivalRadius", 3.5)) or 3.5) ^ 2 then
            local responder = alert.responders[id]
            if responder then responder.arrived = true end
            face(actor, directive.threat)
            return true, "base_alert_arrived"
        end
        targets, action = slots(spotter), "move_to_alert_rally"
        local responder = alert.responders[id]
        if responder and not responder.acknowledged then
            responder.acknowledged = true
            local acknowledged = 0
            for _, other in pairs(alert.responders) do
                if other.spoke then acknowledged = acknowledged + 1 end
            end
            if acknowledged < 2 and speak(actor, "camp_alert.coming", nil, "Coming!") then
                responder.spoke = true
            end
        end
    end
    -- No square to stand on, or no route to it: hold here facing the threat.
    -- Each directive has its own deadline, so this never waits for ever.
    if #targets == 0 then
        face(actor, directive.threat)
        return true, "base_alert_no_rally_square"
    end
    local moving, reason = SC.Navigation.requestAny(actor, targets,
        directive.run and "run" or "walk", {
            action = action,
            -- Escaping a crowd may cut through hazards; answering a call
            -- keeps the ordinary route that steers clear of them.
            urgent = directive.mode == "fall_back",
            arrivalDistance = 1.0,
            snapshot = snapshot,
        })
    if moving == true and reason == "arrived" then
        local responder = alert.responders[id]
        if responder then responder.arrived = true end
        face(actor, directive.threat)
        return true, "base_alert_arrived"
    end
    if moving ~= true then
        face(actor, directive.threat)
        return true, reason or "base_alert_route_failed"
    end
    return true, reason or "base_alert_moving"
end

function Alert.peek()
    return alert
end

function Alert.reset()
    alert, memory, serial = nil, {}, 0
    Alert.lastCleared = nil
end

return Alert
