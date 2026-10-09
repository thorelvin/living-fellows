-- SPDX-License-Identifier: MIT
-- A brief scene grace period: cancel ordinary zombies' thump targets on the
-- actual openings of a resident's room. No map object is changed or saved.

local SC = SurvivorCompanion
SC.OddballRoomGuard = SC.OddballRoomGuard or {}
local Guard = SC.OddballRoomGuard

local DURATION_MS = 300000
local NEAR_DISTANCE_SQ = 18 * 18
local RESCAN_INTERVAL_MS = 30000
-- The faction pulse normally runs once per second. A long gap is usually a
-- pause, loading screen, or suspended window rather than active play.
local MAX_PULSE_DELTA_MS = 2500
local MAX_HOUSE_SPAN = 42

local active = {}
local finished = {}
local targetOwners = {}
local targetCount = 0
local retryAfter = {}
local reportedEmpty = {}
local knownStories = {}
local installed = false

local function U() return SC.GameplayUtil end

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge
        and value ~= -math.huge and value or nil
end

local function elapsedFrom(story)
    return math.max(0, math.min(DURATION_MS,
        math.floor(finite(story and story.roomGuardElapsedMs) or 0)))
end

local function storyFor(groupId)
    local guard = active[groupId]
    if guard and guard.story then return guard.story end
    local factions = SC.Factions
    if type(factions) == "table" and type(factions.group) == "function" then
        local ok, group = pcall(factions.group, groupId)
        if ok and type(group) == "table"
            and type(group.oddball) == "table" then
            return group.oddball
        end
    end
    return knownStories[groupId]
end

local function point(value)
    if type(value) ~= "table" then return nil end
    local x, y, z = finite(value.x), finite(value.y), finite(value.z or 0)
    if not x or not y or not z then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

local function houseBounds(site)
    local bounds = site.house and site.house.bounds
    if type(bounds) ~= "table" then return nil end
    local x1, x2 = finite(bounds.x1), finite(bounds.x2)
    local y1, y2 = finite(bounds.y1), finite(bounds.y2)
    if not x1 or not x2 or not y1 or not y2 then return nil end
    x1, x2 = math.floor(x1), math.floor(x2)
    y1, y2 = math.floor(y1), math.floor(y2)
    if x1 > x2 or y1 > y2 or x2 - x1 > MAX_HOUSE_SPAN
        or y2 - y1 > MAX_HOUSE_SPAN then return nil end
    return { x1 = x1, x2 = x2, y1 = y1, y2 = y2 }
end

local function scenePoints(group)
    local story = group.oddball
    local site = story and story.site
    if type(site) ~= "table" or (site.kind ~= "resident"
        and not (story.id == "mien_ward" and site.kind == "roamer")) then
        return nil end
    local spawn = point(site.spawn)
    local bounds = houseBounds(site)
    if not spawn or not bounds then return nil end
    local points = {}
    local seen = {}
    local function addPosition(value)
        if #points >= 32 then return end
        local position = point(value)
        if not position or position.x < bounds.x1 or position.x > bounds.x2
            or position.y < bounds.y1 or position.y > bounds.y2
            or position.z < -1 or position.z > 2 then return end
        local key = position.x .. ":" .. position.y .. ":" .. position.z
        if not seen[key] then
            seen[key] = true
            points[#points + 1] = position
        end
    end
    if story.id == "survivalist_locked_horde" then
        -- Caleb stands outside. Protect the room holding the real horde.
        points = {}
        addPosition(site.sealedRoom)
    else
        addPosition(spawn)
    end
    if #points == 0 then return nil end
    -- Other residents and Deputy's captives occupy real scene rooms too.
    -- Room identity is resolved and deduplicated in refresh(), so shared
    -- church or barn rooms are scanned only once.
    for _, position in ipairs(type(site.memberSpawns) == "table"
        and site.memberSpawns or {}) do addPosition(position) end
    for _, position in ipairs(type(site.captiveSpawns) == "table"
        and site.captiveSpawns or {}) do addPosition(position) end
    if story.id == "wedding_lonnie_tackett" then
        addPosition(site.vestry)
    elseif story.id == "man_in_the_chair" then
        addPosition(site.bedroom)
    end
    return points, bounds
end

local function roomAt(position)
    local square = U().gridSquare(position.x, position.y, position.z)
    local room, called = U().call(square, "getRoom")
    return called and room or nil
end

local function openingNorth(object)
    local door = U().instanceOf(object, "IsoDoor")
    local window = U().instanceOf(object, "IsoWindow")
    local thumpable = U().instanceOf(object, "IsoThumpable")
    if not door and not window and not thumpable then return nil end
    if thumpable then
        local isDoor = select(1, U().call(object, "isDoor"))
        if isDoor ~= true then
            -- Build 42 thumpable windows expose these edge flags, not a
            -- thumpable-specific isWindow() method.
            local northWindow = select(1, U().call(object, "isWindowN"))
            local westWindow = select(1, U().call(object, "isWindowW"))
            if northWindow == true and westWindow ~= true then return true end
            if westWindow == true and northWindow ~= true then return false end
            return nil
        end
    end
    local north, called = U().call(object, "getNorth")
    if not called and window then
        north, called = U().call(object, "isNorth")
    end
    if called and type(north) == "boolean" then return north end
    return nil
end

local function relinquish(object)
    local owners = targetOwners[object]
    if owners == nil then return end
    if owners <= 1 then
        targetOwners[object] = nil
        targetCount = targetCount - 1
    else targetOwners[object] = owners - 1 end
end

local function refresh(guard)
    local rooms, levels = {}, {}
    for _, position in ipairs(guard.points) do
        local room = roomAt(position)
        if room ~= nil then
            rooms[room] = true
            levels[position.z] = true
        end
    end

    local found, tiles, seenObjects = {}, {}, {}
    local bounds = guard.bounds
    -- A one-tile margin catches an opening published on the exterior side of
    -- the wall. The original house descriptor limits this to a small scan.
    for z in pairs(levels) do
        for x = bounds.x1 - 1, bounds.x2 + 1 do
            for y = bounds.y1 - 1, bounds.y2 + 1 do
                local square = U().gridSquare(x, y, z)
                if square ~= nil then
                    local squareRoom = select(1, U().call(square, "getRoom"))
                    if rooms[squareRoom] then
                        tiles[#tiles + 1] = { x = x, y = y }
                    end
                    local function inspect(object)
                        if object == nil or seenObjects[object] then return end
                        seenObjects[object] = true
                        local north = openingNorth(object)
                        if north == nil then return end
                        local objectSquare, squareCalled = U().call(object, "getSquare")
                        if not squareCalled or objectSquare == nil
                            or objectSquare ~= square then return end
                        local ox, oy, oz = U().position(objectSquare)
                        if ox == nil or oy == nil then return end
                        -- B42's door/window classes have no getOppositeSquare.
                        -- North-facing openings sit on this tile's north edge;
                        -- all other supported openings sit on its west edge.
                        local opposite = U().gridSquare(math.floor(ox)
                            - (north and 0 or 1), math.floor(oy)
                            - (north and 1 or 0), math.floor(oz or z))
                        if opposite == nil then return end
                        local here = select(1, U().call(objectSquare, "getRoom"))
                        local there = select(1, U().call(opposite, "getRoom"))
                        -- The opening must divide one protected room from a
                        -- distinct room or the outside. This also covers the
                        -- interior door between Lonnie's church and vestry.
                        if here ~= there and (rooms[here] or rooms[there]) then
                            found[object] = true
                        end
                    end
                    U().squareObjects(square, inspect, 256)
                    U().squareSpecialObjects(square, inspect, 256)
                end
            end
        end
    end

    for object in pairs(guard.objects) do
        if not found[object] then relinquish(object) end
    end
    for object in pairs(found) do
        if not guard.objects[object] then
            if targetOwners[object] == nil then targetCount = targetCount + 1 end
            targetOwners[object] = (targetOwners[object] or 0) + 1
        end
    end
    guard.objects = found
    guard.tiles = tiles
end

local function openingBreached(guard)
    for object in pairs(guard.objects) do
        if select(1, U().call(object, "IsOpen")) == true
            or select(1, U().call(object, "isSmashed")) == true then
            return true
        end
    end
    return false
end

local function withinRoom(guard, player)
    local px, py = U().position(player)
    if px == nil or py == nil then return false end
    for _, tile in ipairs(guard.tiles) do
        local dx, dy = px - (tile.x + 0.5), py - (tile.y + 0.5)
        if dx * dx + dy * dy <= NEAR_DISTANCE_SQ then return true end
    end
    return false
end

local function playerNear(guard, fallback)
    local found = false
    if type(getSpecificPlayer) == "function" then
        local maximum = 4
        if type(getNumActivePlayers) == "function" then
            local ok, count = pcall(getNumActivePlayers)
            if ok and finite(count) then
                maximum = math.max(0, math.min(4, math.floor(count)))
            end
        end
        for index = 0, maximum - 1 do
            local ok, player = pcall(getSpecificPlayer, index)
            if ok and player ~= nil then
                found = true
                if withinRoom(guard, player) then return true end
            end
        end
    end
    return not found and fallback ~= nil and withinRoom(guard, fallback)
        or false
end

local function playerInProtectedRoom(guard, fallback)
    local protected = roomAt(guard.points[1])
    if not protected then return false end
    local function entered(player)
        local square = player and type(U().squareOf) == "function"
            and U().squareOf(player) or nil
        return square ~= nil
            and select(1, U().call(square, "getRoom")) == protected
    end
    if type(getSpecificPlayer) == "function" then
        local maximum = 4
        if type(getNumActivePlayers) == "function" then
            local ok, count = pcall(getNumActivePlayers)
            if ok and finite(count) then
                maximum = math.max(0, math.min(4, math.floor(count)))
            end
        end
        for index = 0, maximum - 1 do
            local ok, player = pcall(getSpecificPlayer, index)
            if ok and entered(player) then return true end
        end
    end
    return entered(fallback)
end

local function gamePaused()
    if type(getGameTime) ~= "function" then return false end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return false end
    local multiplier, called = U().call(gameTime, "getMultiplier")
    return called and finite(multiplier) and multiplier <= 0 or false
end

function Guard.register(group, player, nowMs)
    if type(group) ~= "table" or group.id == nil then
        return false, "group_unavailable"
    end
    local id = group.id
    local story = type(group.oddball) == "table" and group.oddball or nil
    if story == nil then return false, "resident_site_unavailable" end
    knownStories[id] = story
    local sealed = story.id == "survivalist_locked_horde"
    local protectedVoice = story.id == "voice_actor_vera_quill"
    local persistent = sealed or protectedVoice
    local elapsed = elapsedFrom(story)
    if finished[id] or story.roomGuardDone == true
        or (not persistent and elapsed >= DURATION_MS) then
        if active[id] then Guard.abort(id) end
        story.roomGuardElapsedMs = elapsed
        story.roomGuardDone = true
        finished[id] = true
        return false, "already_finished"
    end
    if active[id] then
        active[id].story = story
        story.roomGuardElapsedMs = math.max(elapsed, active[id].elapsedMs)
        story.roomGuardDone = false
        return true, "already_registered"
    end
    local now = finite(nowMs) or U().nowMs()
    if retryAfter[id] and now < retryAfter[id] then
        return false, "room_openings_retry_wait"
    end
    local points, bounds = scenePoints(group)
    if not points then return false, "resident_site_unavailable" end
    if roomAt(points[1]) == nil then return false, "spawn_room_unavailable" end
    local guard = { points = points, bounds = bounds, objects = {}, tiles = {},
        story = story, elapsedMs = elapsed, lastNowMs = now,
        nextScanAt = now + RESCAN_INTERVAL_MS }
    active[id] = guard
    refresh(guard)
    local hasOpening = false
    for _ in pairs(guard.objects) do hasOpening = true break end
    if not hasOpening then
        Guard.abort(id)
        retryAfter[id] = now + 10000
        if not reportedEmpty[id] and SC.Diagnostics
            and type(SC.Diagnostics.report) == "function" then
            pcall(SC.Diagnostics.report, "oddballs", id,
                "encounter room has no live door or window openings",
                "room_openings_unavailable")
            reportedEmpty[id] = true
        end
        return false, "room_openings_unavailable"
    end
    retryAfter[id] = nil
    reportedEmpty[id] = nil
    if persistent and openingBreached(guard) then
        Guard.release(id)
        return false, "room_opening_breached"
    end
    -- Persist only scalar grace state. Native door/window references stay in
    -- this module's runtime tables and are rediscovered after a reload.
    story.roomGuardElapsedMs = elapsed
    story.roomGuardDone = false
    if (not persistent and playerNear(guard, player))
        or (protectedVoice and playerInProtectedRoom(guard, player)) then
        Guard.release(id)
        return false, "player_near_room"
    end
    return true, "registered"
end

function Guard.pulse(group, player, nowMs)
    local id = type(group) == "table" and group.id or nil
    local guard = id ~= nil and active[id] or nil
    local story = type(group) == "table" and type(group.oddball) == "table"
        and group.oddball or nil
    local sealed = story and story.id == "survivalist_locked_horde"
    local protectedVoice = story and story.id == "voice_actor_vera_quill"
    local persistent = sealed or protectedVoice
    if id ~= nil and story ~= nil then knownStories[id] = story end
    if not guard then
        if id == nil then return false, "not_registered" end
        if finished[id] then return false, "already_finished" end
        local story = group.oddball
        if group.lifecycle == "destroyed" or type(story) ~= "table"
            or story.spawned ~= true then return false, "not_registered" end
        local registered, reason = Guard.register(group, player, nowMs)
        if not registered then return false, reason end
        guard = active[id]
    end
    if story and (story.roomGuardDone == true
        or story.sealBroken == true
        or (protectedVoice and story.confronted == true)
        or (not persistent and elapsedFrom(story) >= DURATION_MS)) then
        Guard.release(id)
        return false, "already_finished"
    end
    if story then
        guard.story = story
        guard.elapsedMs = math.max(guard.elapsedMs, elapsedFrom(story))
    end
    if group.lifecycle == "destroyed" then
        Guard.release(id)
        return false, "group_destroyed"
    end
    local now = finite(nowMs) or U().nowMs()
    local delta = now - guard.lastNowMs
    guard.lastNowMs = now
    if not gamePaused() and delta > 0 then
        guard.elapsedMs = guard.elapsedMs
            + math.min(delta, MAX_PULSE_DELTA_MS)
    end
    if guard.story then
        guard.story.roomGuardElapsedMs = math.min(DURATION_MS,
            math.floor(guard.elapsedMs))
    end
    if not persistent and guard.elapsedMs >= DURATION_MS then
        Guard.release(id)
        return false, "time_elapsed"
    end
    if now >= guard.nextScanAt or delta < 0 then
        refresh(guard)
        guard.nextScanAt = now + RESCAN_INTERVAL_MS
    end
    if persistent and openingBreached(guard) then
        Guard.release(id)
        return false, "room_opening_breached"
    end
    if (not persistent and playerNear(guard, player))
        or (protectedVoice and playerInProtectedRoom(guard, player)) then
        Guard.release(id)
        return false, "player_near_room"
    end
    return true, "active"
end

function Guard.abort(groupId)
    if groupId == nil then return false, "group_unavailable" end
    local guard = active[groupId]
    if guard then
        for object in pairs(guard.objects) do relinquish(object) end
        active[groupId] = nil
    end
    retryAfter[groupId] = nil
    return true, guard and "aborted" or "not_registered"
end

function Guard.release(groupId)
    if groupId == nil then return false, "group_unavailable" end
    local guard = active[groupId]
    local story = storyFor(groupId)
    local wasActive = guard ~= nil
    if story then
        story.roomGuardElapsedMs = math.max(elapsedFrom(story),
            guard and math.min(DURATION_MS, math.floor(guard.elapsedMs)) or 0)
        story.roomGuardDone = true
    end
    Guard.abort(groupId)
    finished[groupId] = true
    reportedEmpty[groupId] = nil
    return true, wasActive and "released" or "already_released"
end

function Guard.reset()
    active, finished, targetOwners, retryAfter, reportedEmpty, knownStories =
        {}, {}, {}, {}, {}, {}
    targetCount = 0
    return true
end

function Guard.onZombieUpdate(zombie)
    if zombie == nil or targetCount == 0 then return false end
    local target, called = U().call(zombie, "getThumpTarget")
    if not called or target == nil or not targetOwners[target] then return false end
    if not U().isZombie(zombie) then return false end
    local _, cleared = U().call(zombie, "setThumpTarget", nil)
    return cleared == true
end

function Guard.install()
    if installed then return true, "already_installed" end
    if type(Events) ~= "table" or type(Events.OnZombieUpdate) ~= "table"
        or type(Events.OnZombieUpdate.Add) ~= "function"
        or type(Events.OnZombieUpdate.Remove) ~= "function" then
        return false, "zombie_event_unavailable"
    end
    local ok, reason = pcall(Events.OnZombieUpdate.Add, Guard.onZombieUpdate)
    if not ok then return false, tostring(reason) end
    installed = true
    return true, "installed"
end

function Guard.remove()
    if not installed then
        Guard.reset()
        return true, "not_installed"
    end
    if type(Events) ~= "table" or type(Events.OnZombieUpdate) ~= "table"
        or type(Events.OnZombieUpdate.Remove) ~= "function" then
        return false, "zombie_event_unavailable"
    end
    local ok, reason = pcall(Events.OnZombieUpdate.Remove, Guard.onZombieUpdate)
    if not ok then return false, tostring(reason) end
    installed = false
    Guard.reset()
    return true, "removed"
end

function Guard.isInstalled()
    return installed
end

return Guard
