-- SPDX-License-Identifier: MIT
-- Isolated cloned-save probe: a body lies upstairs in one room of the camp
-- house and the only open window is in the next room. A Gravekeeper must drag
-- it through to that window, put it out over open ground, go down the stairs,
-- take hold of it where it fell and burn it on a ground-floor pyre.
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

local function roomOf(square)
    return square ~= nil and call(square, "getRoom") or nil
end

local function floorAt(square)
    return square ~= nil and call(square, "TreatAsSolidFloor") == true
end

local function gap(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- Build 42's edge getters take edge enums, so read the tile's objects. A
-- glass window sits in a frame on the same edge; the glass decides.
local function windowOn(square, north)
    local objects = call(square, "getObjects")
    local count = objects and tonumber(call(objects, "size")) or 0
    local frame
    for index = 0, count - 1 do
        local object = objects:get(index)
        local kind
        if instanceof(object, "IsoWindow") then kind = "window"
        elseif instanceof(object, "IsoThumpable") and call(object, "isWindow") == true then
            kind = "thumpable"
        elseif instanceof(object, "IsoWindowFrame") then kind = "frame" end
        -- call() turns false into nil, so read the orientation directly.
        local ok, facing = false, nil
        if kind then ok, facing = pcall(function() return object:getNorth() end) end
        if ok and facing == north then
            if kind ~= "frame" then return object, kind end
            frame = frame or object
        end
    end
    if frame then return frame, "frame" end
    return nil
end

-- One upper window: which side is indoors, what the game keeps outside it,
-- and where a body put out of it would come down.
local function describe(SC, square, x, y, z, north, object, kind, campCheck)
    local U = SC.GameplayUtil
    local ox, oy = x, y
    if north then oy = y - 1 else ox = x - 1 end
    local other = U.gridSquare(ox, oy, z)
    local ownerRoom, otherRoom = roomOf(square), roomOf(other)
    local row = { object = object, kind = kind, north = north, z = z }
    if ownerRoom ~= nil and otherRoom == nil then
        row.inside, row.room, row.ox, row.oy, row.outsideTile = square, ownerRoom, ox, oy, other
    elseif otherRoom ~= nil and ownerRoom == nil then
        row.inside, row.room, row.ox, row.oy, row.outsideTile = other, otherRoom, x, y, square
    else
        row.interior = true
        return row
    end
    row.outside = row.outsideTile == nil and "void"
        or (floorAt(row.outsideTile) and "floor" or "air")
    for level = z - 1, 1, -1 do
        if floorAt(U.gridSquare(row.ox, row.oy, level)) then row.roofBelow = level break end
    end
    local landing = U.gridSquare(row.ox, row.oy, 0)
    row.landing = landing
    if landing == nil then row.landingReason = "no_tile"
    elseif roomOf(landing) ~= nil then row.landingReason = "indoors"
    elseif not U.isSquareFree(landing) then row.landingReason = "blocked"
    elseif campCheck ~= false and SC.BaseLife.isInside(landing) ~= true then
        row.landingReason = "outside_camp"
    end
    if kind == "frame" then
        row.open, row.broken = true, false
    else
        row.open = call(object, "IsOpen") == true
        row.broken = call(object, "isDestroyed") == true or call(object, "isSmashed") == true
        row.barricaded = call(object, "isBarricaded") == true
        row.permaLocked = call(object, "isPermaLocked") == true
        row.locked = call(object, "isLocked") == true
    end
    row.safe = row.outside ~= "floor" and row.roofBelow == nil
        and row.landingReason == nil and row.barricaded ~= true
    return row
end

local function rowText(row)
    local ix, iy = position(row.inside)
    return key(ix, iy, row.z) .. (row.north and "N" or "W")
        .. " room=" .. tostring(call(row.room, "getName"))
        .. " out=" .. tostring(row.ox) .. "," .. tostring(row.oy) .. ":" .. tostring(row.outside)
        .. " roofBelow=" .. tostring(row.roofBelow)
        .. " landing=" .. tostring(row.landingReason or "ok")
        .. " kind=" .. tostring(row.kind) .. " open=" .. tostring(row.open)
        .. " broken=" .. tostring(row.broken) .. " barricaded=" .. tostring(row.barricaded)
        .. " locked=" .. tostring(row.locked) .. " perma=" .. tostring(row.permaLocked)
end

-- Every upper floor over the camp's ground: the camp's own upper areas, and
-- the floors above its ground areas in case the stair link is not made yet.
local function surveyBoxes(base)
    local boxes = {}
    for _, zone in ipairs(base.zones or {}) do
        local z = tonumber(zone.z) or 0
        if zone.kind == "area" then
            if z >= 1 then
                boxes[#boxes + 1] = { x1 = zone.x1, y1 = zone.y1, x2 = zone.x2, y2 = zone.y2, z = z }
            elseif z == 0 then
                for level = 1, 2 do
                    boxes[#boxes + 1] = { x1 = zone.x1, y1 = zone.y1, x2 = zone.x2,
                        y2 = zone.y2, z = level }
                end
            end
        end
    end
    return boxes
end

local function zoneText(base)
    local parts = {}
    for _, zone in ipairs(base.zones or {}) do
        parts[#parts + 1] = tostring(zone.kind) .. "@" .. tostring(zone.x1) .. "-"
            .. tostring(zone.x2) .. "," .. tostring(zone.y1) .. "-" .. tostring(zone.y2)
            .. ",z" .. tostring(zone.z) .. (zone.autoStair == true and "(stair)" or "")
    end
    return table.concat(parts, " ")
end

local function survey(SC, boxes, campCheck)
    local U, rows, seen = SC.GameplayUtil, {}, {}
    local stats = { squares = 0, indoor = 0, windows = 0 }
    for _, box in ipairs(boxes) do
        local z = box.z
        for y = box.y1 - 1, box.y2 + 1 do
            for x = box.x1 - 1, box.x2 + 1 do
                local square = U.gridSquare(x, y, z)
                if square and not seen[key(x, y, z)] then
                    seen[key(x, y, z)] = true
                    stats.squares = stats.squares + 1
                    if roomOf(square) ~= nil then stats.indoor = stats.indoor + 1 end
                    for _, north in ipairs({ true, false }) do
                        local object, kind = windowOn(square, north)
                        if object then
                            stats.windows = stats.windows + 1
                            local row = describe(SC, square, x, y, z, north, object, kind,
                                campCheck)
                            if not row.interior then rows[#rows + 1] = row end
                        end
                    end
                end
            end
        end
    end
    return rows, stats
end

local steps4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- A free indoor tile in another room than the window's, reached through
-- open floor or a door, within the hauler's window search radius of the
-- window. The route between them may wander further.
local function bodyTile(SC, row, campCheck)
    local U = SC.GameplayUtil
    local ix, iy, iz = position(row.inside)
    local start = key(ix, iy, iz)
    local dist, doors, squares = { [start] = 0 }, { [start] = 0 }, { [start] = row.inside }
    local queue, head = { start }, 1
    local best, bestScore
    local stats = { reached = 0, rooms = {}, nearest = nil, blocked = {} }
    while head <= #queue and head <= 1500 do
        local here = queue[head]
        head = head + 1
        local square = squares[here]
        local x, y = position(square)
        local d = dist[here]
        if d < 30 then
            for _, step in ipairs(steps4) do
                local nx, ny = x + step[1], y + step[2]
                local nk = key(nx, ny, iz)
                local nextSquare = U.gridSquare(nx, ny, iz)
                if dist[nk] == nil and nextSquare and roomOf(nextSquare) ~= nil
                    and U.isSquareFree(nextSquare) and gap(nx, ny, ix, iy) <= 14
                    and not SC.Topology.squareHasStairs(nextSquare) then
                    local _, kind = SC.Topology.barrierBetween(square, nextSquare)
                    if kind ~= "open" and kind ~= "door" then
                        stats.blocked[tostring(kind)] = (stats.blocked[tostring(kind)] or 0) + 1
                    end
                    if kind == "open" or kind == "door" then
                        stats.reached = stats.reached + 1
                        local roomName = tostring(call(roomOf(nextSquare), "getName"))
                        stats.rooms[roomName] = true
                        if roomOf(nextSquare) ~= row.room then
                            local away = gap(nx, ny, ix, iy)
                            if stats.nearest == nil or away < stats.nearest then stats.nearest = away end
                        end
                        dist[nk], squares[nk] = d + 1, nextSquare
                        doors[nk] = doors[here] + (kind == "door" and 1 or 0)
                        queue[#queue + 1] = nk
                        local room = roomOf(nextSquare)
                        if room ~= row.room and gap(nx, ny, ix, iy) <= 5
                            and (campCheck == false
                                or SC.BaseLife.isInside(nextSquare) == true) then
                            local score = math.abs(d + 1 - 6)
                            if bestScore == nil or score < bestScore then
                                best, bestScore = { square = nextSquare, steps = d + 1,
                                    doors = doors[nk], room = room }, score
                            end
                        end
                    end
                end
            end
        end
    end
    return best, stats
end

local function statsText(stats)
    local rooms, blocked = {}, {}
    for name in pairs(stats.rooms) do rooms[#rooms + 1] = name end
    for kind, count in pairs(stats.blocked) do blocked[#blocked + 1] = kind .. "=" .. tostring(count) end
    return "reached=" .. tostring(stats.reached) .. " rooms=" .. table.concat(rooms, "/")
        .. " nearestOtherRoom=" .. tostring(stats.nearest) .. " edges=" .. table.concat(blocked, "/")
end

-- A tile beside the body, in its room, for the hauler to stand on.
local function besideBody(SC, body)
    local U = SC.GameplayUtil
    local x, y, z = position(body.square)
    for _, step in ipairs(steps4) do
        local square = U.gridSquare(x + step[1], y + step[2], z)
        if square and roomOf(square) == body.room and U.isSquareFree(square) then
            local _, kind = SC.Topology.barrierBetween(body.square, square)
            if kind == "open" then return square end
        end
    end
    return nil
end

-- Choose the window and the body's room. Every other window that cannot be
-- shut and would also take a body counts against a layout.
local function chooseLayout(SC, rows, campCheck)
    local ordered = {}
    for _, row in ipairs(rows) do
        if row.safe and row.kind ~= "thumpable" then ordered[#ordered + 1] = row end
    end
    table.sort(ordered, function(a, b)
        if (a.outside == "air") ~= (b.outside == "air") then return a.outside == "air" end
        return (a.open or a.broken) and not (b.open or b.broken)
    end)
    local fallback
    for _, row in ipairs(ordered) do
        local body, stats = bodyTile(SC, row, campCheck)
        print("SC_REAL_SANDBOX|UPSTAIRS_BFS|" .. rowText(row) .. " " .. statsText(stats))
        if body then
            local bx, by = position(body.square)
            local rivals = 0
            for _, other in ipairs(rows) do
                local ox, oy = position(other.inside)
                if other ~= row and other.z == row.z and other.safe
                    and (other.broken or other.kind == "frame")
                    and gap(ox, oy, bx, by) <= 8 then
                    rivals = rivals + 1
                end
            end
            if rivals == 0 then return row, body, 0 end
            fallback = fallback or { row = row, body = body, rivals = rivals }
        end
    end
    if fallback then return fallback.row, fallback.body, fallback.rivals end
    return nil
end

-- Open the chosen window the way a player would, after lifting a lock the
-- map placed on it. Only a window that will not open is smashed.
local function openWindow(row)
    if row.open or row.broken or row.kind == "frame" then return true, "already_open" end
    pcall(function() row.object:setPermaLocked(false) end)
    pcall(function() row.object:setIsLocked(false) end)
    pcall(function() row.object:ToggleWindow(nil) end)
    if call(row.object, "IsOpen") == true then return true, "opened" end
    pcall(function() row.object:smashWindow(true, false) end)
    return call(row.object, "isDestroyed") == true, "smashed"
end

-- Shut every other open window near the body, so the throw has to use the
-- window in the next room.
local function shutOthers(rows, chosen, body)
    local bx, by = position(body.square)
    local shut = 0
    for _, row in ipairs(rows) do
        local ox, oy = position(row.inside)
        if row ~= chosen and row.z == chosen.z and row.kind == "window"
            and row.open and not row.broken and gap(ox, oy, bx, by) <= 8 then
            call(row.object, "ToggleWindow", nil)
            if call(row.object, "IsOpen") ~= true then shut = shut + 1 end
        end
    end
    return shut
end

-- Bodies already in the camp would be taken first; this probe wants only
-- its own. They are marked as burned in the disposable clone.
local function excludeOtherBodies(SC, base)
    local U, count = SC.GameplayUtil, 0
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" or zone.kind == "lumber" then
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local square = U.gridSquare(x, y, tonumber(zone.z) or 0)
                    if square then
                        U.squareStaticMovingObjects(square, function(object)
                            if U.instanceOf(object, "IsoDeadBody") then
                                local data = U.modData(object)
                                if type(data) == "table"
                                    and data[SC.Production.BURNED_TAG] == nil then
                                    data[SC.Production.BURNED_TAG] = "live_probe_excluded"
                                    count = count + 1
                                end
                            end
                        end, 16)
                    end
                end
            end
        end
    end
    return count
end

local directions = {
    { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
    { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
}

local function outdoorFree(U, square)
    return square ~= nil and U.isSquareFree(square) and roomOf(square) == nil
end

-- Where the observer watches from: near the landing, clear of the pyre so
-- it never counts as a bystander there.
local function chooseView(SC, lx, ly, pyre)
    local U = SC.GameplayUtil
    local px, py = position(pyre)
    for radius = 4, 8 do
        for _, direction in ipairs(directions) do
            local x, y = lx + direction[1] * radius, ly + direction[2] * radius
            local square = U.gridSquare(x, y, 0)
            if outdoorFree(U, square) and SC.BaseLife.isInside(square) == true
                and gap(x, y, px, py) >= 4 then
                return square
            end
        end
    end
    return nil
end

local function choosePyre(SC, lx, ly)
    local U, base = SC.GameplayUtil, SC.BaseLife.active()
    local lastReason
    for _, radius in ipairs({ 6, 8, 10, 12, 14, 16, 20 }) do
        for _, direction in ipairs(directions) do
            local x, y = lx + direction[1] * radius, ly + direction[2] * radius
            local square = U.gridSquare(x, y, 0)
            local zone = { kind = "pyre", x1 = x, y1 = y, x2 = x, y2 = y, z = 0 }
            if outdoorFree(U, square) and SC.BaseLife.lumberZoneReachable(zone, base.zones) then
                local safe, reason = SC.Production.validatePyreZone(zone)
                if safe == true then return square end
                lastReason = reason
            end
        end
    end
    return nil, lastReason or "no_safe_loaded_pyre_site"
end

-- Other residents stand frozen while the decision loop is off; move them
-- out of the house, well clear of the landing and the pyre, so none blocks
-- a doorway, the stairs or the drag.
local function clearHouse(SC, workerId, view, lx, ly, pyre)
    local U = SC.GameplayUtil
    local vx, vy = position(view)
    local px, py = position(pyre)
    local spots, moved = {}, 0
    for radius = 3, 12 do
        for _, direction in ipairs(directions) do
            local x, y = vx + direction[1] * radius, vy + direction[2] * radius
            local square = U.gridSquare(x, y, 0)
            if outdoorFree(U, square) and gap(x, y, lx, ly) >= 7 and gap(x, y, px, py) >= 7 then
                spots[#spots + 1] = square
            end
        end
    end
    for _, record in ipairs(SC.Registry.records() or {}) do
        if record.id ~= workerId and record.actor and call(record.actor, "isDead") ~= true
            and #spots > 0 then
            local spot = table.remove(spots, 1)
            local ok = pcall(function()
                record.actor:teleportTo(spot:getX() + 0.5, spot:getY() + 0.5, 0)
            end)
            if ok then moved = moved + 1 end
        end
    end
    return moved
end

local function makeCorpse(square)
    if type(createZombie) ~= "function" or IsoDeadBody == nil then
        return nil, "native_corpse_fixture_unavailable"
    end
    local x, y, z = position(square)
    local zombie = createZombie(x, y, z, nil, 0, IsoDirections.S)
    if not zombie then return nil, "zombie_fixture_failed" end
    local ok, body = pcall(IsoDeadBody.new, zombie, false)
    if not ok or not body then return nil, tostring(body) end
    return body
end

-- The probe's body, wherever it lies: it carries the haul tag once grabbed.
local function taggedBodyNear(SC, x, y, z, radius)
    local U = SC.GameplayUtil
    for dy = -radius, radius do
        for dx = -radius, radius do
            local square = U.gridSquare(x + dx, y + dy, z)
            local found
            if square then
                U.squareStaticMovingObjects(square, function(object)
                    local data = U.instanceOf(object, "IsoDeadBody") and U.modData(object) or nil
                    if type(data) == "table" and data[SC.Production.HAUL_TAG] ~= nil
                        and data[SC.Production.BURNED_TAG] ~= "live_probe_excluded" then
                        found = object
                        return false
                    end
                end, 16)
            end
            if found then return found, square end
        end
    end
    return nil
end

local function upperArea(base)
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" and (tonumber(zone.z) or 0) >= 1 then return zone end
    end
    return nil
end

-- Every loaded house with two or more rooms upstairs and stairs up from its
-- ground floor, nearest first.
local function findTwoStoryHouses(SC, cx, cy)
    local U = SC.GameplayUtil
    local houses, order = {}, {}
    for y = cy - 60, cy + 60 do
        for x = cx - 60, cx + 60 do
            local square = U.gridSquare(x, y, 1)
            local room = roomOf(square)
            if room ~= nil then
                local id = tostring(call(square, "getBuilding"))
                local house = houses[id]
                if not house then
                    house = { rooms = {}, roomCount = 0, tiles = 0, x1 = x, y1 = y, x2 = x, y2 = y }
                    houses[id] = house
                    order[#order + 1] = house
                end
                house.tiles = house.tiles + 1
                local roomKey = tostring(room)
                if not house.rooms[roomKey] then
                    house.rooms[roomKey] = true
                    house.roomCount = house.roomCount + 1
                end
                house.x1, house.y1 = math.min(house.x1, x), math.min(house.y1, y)
                house.x2, house.y2 = math.max(house.x2, x), math.max(house.y2, y)
            end
        end
    end
    local result = {}
    for _, house in ipairs(order) do
        if house.roomCount >= 2 and house.tiles >= 12 then
            local stairs = false
            for y = house.y1 - 1, house.y2 + 1 do
                for x = house.x1 - 1, house.x2 + 1 do
                    if not stairs and SC.Topology.squareHasStairs(U.gridSquare(x, y, 0)) then
                        stairs = true
                    end
                end
            end
            house.distance = gap((house.x1 + house.x2) / 2, (house.y1 + house.y2) / 2, cx, cy)
            if stairs then result[#result + 1] = house end
        end
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result, #order
end

-- This camp has no upper floor: mark the nearest two-story house's ground
-- as camp area in the disposable clone, and let the camp's own stair survey
-- link its upper floor.
local function adoptHouse(H, SC, check, result, setPhase, current)
    local base = SC.BaseLife.active()
    local px, py = position(H.player)
    local houses, buildings = findTwoStoryHouses(SC, math.floor(px), math.floor(py))
    local house, tried = nil, {}
    for _, candidate in ipairs(houses) do
        local rows = survey(SC, { { x1 = candidate.x1, y1 = candidate.y1,
            x2 = candidate.x2, y2 = candidate.y2, z = 1 } }, false)
        local window = chooseLayout(SC, rows, false)
        tried[#tried + 1] = tostring(candidate.x1) .. "-" .. tostring(candidate.x2) .. ","
            .. tostring(candidate.y1) .. "-" .. tostring(candidate.y2) .. ":windows="
            .. tostring(#rows) .. ":layout=" .. tostring(window ~= nil)
        if window then house = candidate break end
    end
    if not check("upstairs_haul_two_story_house", house ~= nil,
        "upper buildings=" .. tostring(buildings) .. " near=" .. key(math.floor(px), math.floor(py), 0)
            .. " tried=" .. table.concat(tried, " ")) then
        setPhase("finish", current) return
    end
    local margin = 5
    local x1, y1, x2, y2 = house.x1 - margin, house.y1 - margin, house.x2 + margin, house.y2 + margin
    local begun, beginReason = SC.BaseLife.beginZone("area", { x = x1, y = y1, z = 0 })
    local made, zone
    if begun then made, zone = SC.BaseLife.finishZone({ x = x2, y = y2, z = 0 }, "Harness two-story house")
    else made, zone = false, beginReason end
    if not check("upstairs_haul_house_area", made == true,
        tostring(made == true and zone.id or zone) .. " upper=" .. tostring(house.x1) .. "-"
            .. tostring(house.x2) .. "," .. tostring(house.y1) .. "-" .. tostring(house.y2)
            .. " rooms=" .. tostring(house.roomCount) .. " tiles=" .. tostring(house.tiles)) then
        SC.BaseLife.cancelZone()
        setPhase("finish", current) return
    end
    H.upstairsHouse = house
    setPhase("upstairs_haul_link", current)
end

-- A bounded walking route search between two ground tiles.
local function walkRoute(SC, actor, from, to)
    local started, job = pcall(SC.Navigation.beginPathSearch, from, to, nil, {
        actor = actor, alternatives = false, nodeBudget = 4000,
    })
    if not started or job == nil then return "unstarted:" .. tostring(job) end
    for _ = 1, 200 do
        local ok, status, path = pcall(SC.Navigation.resumePathSearch, job, 200)
        if not ok then return "error:" .. tostring(status) end
        if status ~= "pending" then
            return tostring(status) .. ":" .. tostring(type(path) == "table" and #path or 0)
        end
    end
    return "pending_after_budget"
end

local function setup(H, SC, check, result, setPhase, current)
    local base = SC.BaseLife.active()
    if not check("upstairs_haul_base", base ~= nil, "base=" .. tostring(base and base.name)) then
        setPhase("finish", current) return
    end
    local rows, stats = survey(SC, surveyBoxes(base), true)
    local safe = 0
    for _, row in ipairs(rows) do
        print("SC_REAL_SANDBOX|UPSTAIRS_WINDOW|" .. rowText(row))
        if row.safe then safe = safe + 1 end
    end
    result("PASS", "upstairs_haul_window_survey",
        "outer=" .. tostring(#rows) .. " safe=" .. tostring(safe)
            .. " windows=" .. tostring(stats.windows) .. " squares=" .. tostring(stats.squares)
            .. " indoor=" .. tostring(stats.indoor) .. " zones=" .. zoneText(base))
    local window, body, rivals = chooseLayout(SC, rows, true)
    if not check("upstairs_haul_layout", window ~= nil,
        "no safe upper window with another room beside it; see UPSTAIRS_WINDOW lines") then
        setPhase("finish", current) return
    end
    local bx, by, bz = position(body.square)
    local opened, openReason = openWindow(window)
    if not check("upstairs_haul_window_open", opened, rowText(window) .. " " .. openReason) then
        setPhase("finish", current) return
    end
    local shut = shutOthers(rows, window, body)
    local stand = besideBody(SC, body)
    result("PASS", "upstairs_haul_layout_detail",
        "window=" .. rowText(window) .. " body=" .. key(bx, by, bz)
            .. " bodyRoom=" .. tostring(call(body.room, "getName"))
            .. " steps=" .. tostring(body.steps) .. " doors=" .. tostring(body.doors)
            .. " rivals=" .. tostring(rivals) .. " shut=" .. tostring(shut)
            .. " stand=" .. tostring(stand and key(position(stand))))
    if not check("upstairs_haul_stand", stand ~= nil, "no free tile beside the body") then
        setPhase("finish", current) return
    end
    local lx, ly = window.ox, window.oy
    local pyre, pyreReason = choosePyre(SC, lx, ly)
    local view = pyre and chooseView(SC, lx, ly, pyre) or nil
    if not check("upstairs_haul_pyre_site", pyre ~= nil and view ~= nil,
        tostring(pyreReason) .. " view=" .. tostring(view ~= nil)) then
        setPhase("finish", current) return
    end
    result("PASS", "upstairs_haul_landing_route",
        "landing->view=" .. walkRoute(SC, H.player, window.landing, view)
            .. " landing->pyre=" .. walkRoute(SC, H.player, window.landing, pyre))
    local begun, beginReason = SC.BaseLife.beginZone("pyre", pyre)
    local made, zone
    if begun then made, zone = SC.BaseLife.finishZone(pyre, "Harness upstairs pyre")
    else made, zone = false, beginReason end
    if not check("upstairs_haul_pyre_zone", made == true,
        tostring(made == true and zone.id or zone) .. " at=" .. key(position(pyre))) then
        SC.BaseLife.cancelZone()
        setPhase("finish", current) return
    end
    pcall(function() getGameTime():setTimeOfDay(12.0) end)
    local excluded = excludeOtherBodies(SC, base)
    result("PASS", "upstairs_haul_other_bodies_excluded", "count=" .. tostring(excluded))
    local ticket, spawnReason = SC.Actor.beginSpawn(view, {
        recruited = true,
        identity = { forename = "Upstairs", surname = "Tester",
            gender = "man", outfit = "Generic01" },
    })
    if not check("upstairs_haul_worker_spawn_requested", ticket ~= nil, tostring(spawnReason)) then
        setPhase("finish", current) return
    end
    H.upstairsHaul = { rows = rows, window = window, body = body, stand = stand,
        pyre = pyre, view = view, zone = zone, ticket = ticket, observed = {} }
    setPhase("upstairs_haul_spawn", current)
end

local function spawn(H, SC, check, result, setPhase, current)
    local fixture = H.upstairsHaul
    local actor, spawnReason = SC.Actor.pollSpawn(fixture.ticket)
    if actor == nil then
        if spawnReason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
            result("FAIL", "upstairs_haul_worker_spawn", tostring(spawnReason))
            setPhase("finish", current)
        end
        return
    end
    local worker = { actor = actor, id = SC.Registry.idOf(actor) }
    if not check("upstairs_haul_worker_spawn", worker.id ~= nil, "id=" .. tostring(worker.id)) then
        setPhase("finish", current) return
    end
    if SC.Scheduler then SC.Scheduler.unregister("decision") end
    local corpse, corpseReason = makeCorpse(fixture.body.square)
    local cx, cy, cz = position(corpse)
    if not check("upstairs_haul_corpse_upstairs", corpse ~= nil and cz ~= nil and cz >= 0.95,
        tostring(corpseReason) .. " at=" .. key(cx, cy, cz)) then
        setPhase("finish", current) return
    end
    local inventory = call(worker.actor, "getInventory")
    local petrol = inventory and call(inventory, "AddItem", "Base.PetrolCan")
    local matchbox = inventory and call(inventory, "AddItem", "Base.Matchbox")
    if not check("upstairs_haul_supplies", petrol ~= nil and matchbox ~= nil,
        "petrol=" .. tostring(petrol ~= nil) .. " matchbox=" .. tostring(matchbox ~= nil)) then
        setPhase("finish", current) return
    end
    if SC.Downtime then SC.Downtime.cancel(worker.actor, "upstairs_haul_fixture") end
    if SC.BaseWork then SC.BaseWork.cancel(worker.actor, "upstairs_haul_fixture") end
    local ordered, orderReason = SC.Commands.issue(worker.id, "set_base_role",
        { role = "corpsekeeper" }, H.player)
    if not check("upstairs_haul_worker_on_duty", ordered == true, tostring(orderReason)) then
        setPhase("finish", current) return
    end
    local moved = clearHouse(SC, worker.id, fixture.view, fixture.window.ox,
        fixture.window.oy, fixture.pyre)
    local placed, placeReason = pcall(function()
        local stand, view = fixture.stand, fixture.view
        worker.actor:teleportTo(stand:getX() + 0.5, stand:getY() + 0.5, stand:getZ())
        H.player:teleportTo(view:getX() + 0.5, view:getY() + 0.5, 0)
    end)
    if not check("upstairs_haul_fixture_positioned", placed,
        tostring(placeReason) .. " residentsMoved=" .. tostring(moved)) then
        setPhase("finish", current) return
    end
    local created, order = SC.BaseLife.createProductionOrder({
        operation = "collect_bodies", zoneId = fixture.zone.id, requested = 1,
        workers = { worker.id },
        settings = { fromCamp = true, withBelongings = true, requireDry = false },
    })
    if not check("upstairs_haul_order", created == true, tostring(created and order.id or order)) then
        setPhase("finish", current) return
    end
    fixture.worker, fixture.order, fixture.startedAt = worker, order, current
    fixture.counterBefore = SC.BaseLife.productionCounters().pyresLit or 0
    setPhase("upstairs_haul_wait", current)
end

-- The production window checks, one by one, for every safe window the
-- hauler's search could see, read with the real hauler.
local function diagnoseWindows(SC, fixture)
    local U = SC.GameplayUtil
    local actor = fixture.worker.actor
    local ax, ay, az = position(actor)
    local lines = {}
    for _, row in ipairs(fixture.rows or {}) do
        local ix, iy, iz = position(row.inside)
        if row.safe and gap(ix, iy, ax, ay) <= 7 then
            local outside = U.gridSquare(row.ox, row.oy, row.z)
            local edge = outside and SC.Navigation.edgeAffordance(row.inside, outside) or nil
            local okClimb, climb = pcall(function() return row.object:canClimbThrough(actor) end)
            local landing = U.gridSquare(row.ox, row.oy, 0)
            lines[#lines + 1] = key(ix, iy, iz) .. (row.north and "N" or "W")
                .. " edge=" .. tostring(edge and edge.kind) .. "/" .. tostring(edge and edge.object == row.object)
                .. " climb=" .. tostring(okClimb) .. "/" .. tostring(climb)
                .. " insideFree=" .. tostring(U.isSquareFree(row.inside))
                .. " insideBlocker=" .. tostring(select(2, U.squareStaticBlocker(row.inside)))
                .. " outsideFloor=" .. tostring(floorAt(outside))
                .. " landingFree=" .. tostring(U.isSquareFree(landing))
                .. " landingRoom=" .. tostring(roomOf(landing) ~= nil)
                .. " admits=" .. tostring(SC.BaseLife.admitsWork(landing, { workReach = false }))
                .. "/" .. tostring(SC.BaseLife.admitsWork(landing, { workReach = true }))
        end
    end
    return "hauler=" .. key(ax, ay, az) .. " room=" .. tostring(call(roomOf(U.squareOf(actor)), "getName"))
        .. " windows: " .. table.concat(lines, " | ")
end

-- What the hauler's body and navigation are doing, for a stalled leg.
local function actorDetail(SC, actor)
    local U = SC.GameplayUtil
    local nav = SC.Navigation.status(actor) or {}
    local state = SC.Navigation.peek(actor) or {}
    local lease = state.nativeLease
    local function flag(method)
        local ok, value = pcall(function() return actor[method](actor) end)
        return ok and tostring(value) or "n/a"
    end
    return "fsm=" .. tostring(U.objectLabel(call(actor, "getCurrentState")))
        .. " action=" .. tostring(call(actor, "getCompanionActionStateName"))
        .. " anim=" .. string.sub(tostring(call(actor, "getCompanionActiveAnimationNames")), 1, 120)
        .. " blocker=" .. tostring(U.movementStateBlocker(actor))
        .. " nav=" .. tostring(nav.phase) .. "/" .. tostring(nav.pathReason)
        .. "/" .. tostring(nav.lastMovementReason) .. " target=" .. tostring(nav.target)
        .. " stuck=" .. tostring(nav.stuckAttempts) .. " terminal=" .. tostring(nav.terminalReason)
        .. " lease=" .. tostring(lease and lease.affordance) .. ":" .. tostring(lease and lease.reason)
        .. " throwOut=" .. flag("isGrappleThrowOutWindow") .. " grappling=" .. flag("isGrappling")
        .. " dragging=" .. flag("isDraggingCorpse") .. " blockMove=" .. flag("isBlockMovement")
end

-- Where the hauler stands and faces, and every body within two tiles of the
-- pyre, at one moment of a placement.
local function placementDetail(SC, fixture, actor)
    local U = SC.GameplayUtil
    local ax, ay = position(actor)
    local forward = call(actor, "getForwardDirection")
    local fx, fy = tonumber(call(forward, "getX")), tonumber(call(forward, "getY"))
    local px, py = position(fixture.pyre)
    local bodies = {}
    for dy = -2, 2 do
        for dx = -2, 2 do
            local square = U.gridSquare(px + dx, py + dy, 0)
            if square then
                U.squareStaticMovingObjects(square, function(object)
                    if U.instanceOf(object, "IsoDeadBody") then
                        local bx, by = position(object)
                        bodies[#bodies + 1] = string.format("%.2f,%.2f", bx or -1, by or -1)
                    end
                end, 16)
            end
        end
    end
    return string.format("hauler=%.2f,%.2f facing=%.2f,%.2f", ax or -1, ay or -1, fx or 0, fy or 0)
        .. " pyre=" .. key(px, py, 0) .. " bodies=" .. table.concat(bodies, ";")
end

-- Every body and every zombie object within six tiles of the window's
-- outer tile, on both floors: where a thrown body went when it is not found.
local function thrownBodyDetail(SC, fixture)
    local U = SC.GameplayUtil
    local wx, wy = fixture.window.ox, fixture.window.oy
    local parts = {}
    for _, level in ipairs({ 0, fixture.window.z }) do
        for dy = -6, 6 do
            for dx = -6, 6 do
                local square = U.gridSquare(wx + dx, wy + dy, level)
                if square then
                    U.squareStaticMovingObjects(square, function(object)
                        if U.instanceOf(object, "IsoDeadBody") then
                            local data = U.modData(object)
                            local bx, by, bz = position(object)
                            parts[#parts + 1] = string.format("body@%.2f,%.2f,%.2f", bx or -1, by or -1, bz or -1)
                                .. ":tag=" .. tostring(type(data) == "table" and data[SC.Production.HAUL_TAG] ~= nil)
                        end
                    end, 16)
                end
            end
        end
    end
    local zombies = call(getCell(), "getZombieList")
    local count = zombies and tonumber(call(zombies, "size")) or 0
    for index = 0, count - 1 do
        local zombie = zombies:get(index)
        local zx, zy, zz = position(zombie)
        if zx and gap(zx, zy, wx, wy) <= 6 then
            local data = U.modData(zombie)
            parts[#parts + 1] = string.format("zombie@%.2f,%.2f,%.2f", zx, zy, zz or -1)
                .. ":state=" .. tostring(U.objectLabel(call(zombie, "getCurrentState")))
                .. ":dead=" .. tostring(call(zombie, "isDead"))
                .. ":onFloor=" .. tostring(call(zombie, "isOnFloor"))
                .. ":falling=" .. tostring(call(zombie, "isbFalling"))
                .. ":ragdoll=" .. tostring(call(zombie, "isRagdoll"))
                .. ":tag=" .. tostring(type(data) == "table" and data[SC.Production.HAUL_TAG] ~= nil)
        end
    end
    return table.concat(parts, " ")
end

local function fail(fixture, result, setPhase, current, name, detail)
    result("FAIL", name, tostring(detail) .. " seen=" .. table.concat(fixture.sequence or {}, ","))
    setPhase("finish", current)
end

local function wait(H, SC, check, result, setPhase, current)
    local fixture = H.upstairsHaul
    local actor = fixture.worker.actor
    if current - H.phaseStartedAt > 300000 then
        fail(fixture, result, setPhase, current, "upstairs_haul_pyre_lit", "timeout order="
            .. tostring(fixture.order.state) .. "/" .. tostring(fixture.order.blocker)
            .. " afterDrop=" .. table.concat(fixture.afterDrop or {}, ","))
        return
    end
    if current < (fixture.nextUpdate or 0) then return end
    fixture.nextUpdate = current + 250
    local handled, reason = SC.Production.update(actor, {},
        { type = "production", state = "active", target = { orderId = fixture.order.id } }, {})
    reason = tostring(reason)
    local x, y, z = position(actor)
    local square = SC.GameplayUtil.squareOf(actor)
    fixture.sequence = fixture.sequence or {}
    if reason ~= fixture.lastReason then
        fixture.lastReason = reason
        fixture.sequence[#fixture.sequence + 1] = reason .. "@" .. tostring(z and math.floor(z + 0.05))
        if #fixture.sequence > 40 then table.remove(fixture.sequence, 1) end
    end
    if current >= (fixture.nextTrace or 0) then
        fixture.nextTrace = current + 3000
        print("SC_REAL_SANDBOX|UPSTAIRS_HAUL_TRACE|handled=" .. tostring(handled)
            .. " reason=" .. reason .. " phase="
            .. tostring(SC.Production.workerPhase(fixture.order.id, fixture.worker.id))
            .. " order=" .. tostring(fixture.order.state) .. "/" .. tostring(fixture.order.blocker)
            .. " at=" .. key(x, y, z)
            .. (fixture.landedAt and (" " .. actorDetail(SC, actor)) or ""))
    end
    local upstairs = z ~= nil and z >= 0.95
    -- Every change of reason or route target on the way down, in order.
    if fixture.landedAt and not fixture.downAt then
        local nav = SC.Navigation.status(actor) or {}
        local step = reason .. ">" .. tostring(nav.target) .. "@"
            .. string.format("%.2f", tonumber(z) or -1)
        local last = fixture.descent and fixture.descent[#fixture.descent]
        local base = reason .. ">" .. tostring(nav.target)
        if last == nil or string.sub(last, 1, #base + 1) ~= base .. "@" then
            fixture.descent = fixture.descent or {}
            if #fixture.descent < 30 then fixture.descent[#fixture.descent + 1] = step end
        end
    end
    -- A walk down the stairs that sits between floors for half a minute
    -- has stalled; say how, rather than wait out the whole run.
    local between = z ~= nil and z > 0.05 and z < 0.95
    if fixture.landedAt and not fixture.downAt and between then
        fixture.betweenSince = fixture.betweenSince or current
        if current - fixture.betweenSince > 30000 then
            fail(fixture, result, setPhase, current, "upstairs_haul_hauler_came_down",
                "stalled on the stairs at " .. key(x, y, z) .. " " .. actorDetail(SC, actor)
                    .. " descent=" .. table.concat(fixture.descent or {}, ","))
            return
        end
    else
        fixture.betweenSince = nil
    end
    if reason == "production_dragging" and upstairs and not fixture.dragAt then
        fixture.dragAt = current
        result("PASS", "upstairs_haul_grabbed_upstairs", "at=" .. key(x, y, z))
    end
    if string.find(reason, "drag_route_replanning", 1, true) == 1 and upstairs
        and not fixture.thrownAt then
        fixture.replanned = true
    end
    if reason == "no_safe_window_upstairs" then
        fail(fixture, result, setPhase, current, "upstairs_haul_window_used",
            "the drag gave up upstairs; window=" .. rowText(fixture.window)
                .. " " .. diagnoseWindows(SC, fixture))
        return
    end
    if reason == "production_throwing_body" and not fixture.throwAt then
        fixture.throwAt = current
        local room = roomOf(square)
        local wx, wy = position(fixture.window.inside)
        check("upstairs_haul_dragged_to_next_room",
            room ~= nil and room == fixture.window.room and room ~= fixture.body.room,
            "thrower=" .. key(x, y, z) .. " room=" .. tostring(call(room, "getName"))
                .. " windowInside=" .. key(wx, wy, fixture.window.z)
                .. " bodyRoom=" .. tostring(call(fixture.body.room, "getName")))
        check("upstairs_haul_window_sought_at_once", fixture.replanned ~= true,
            "drag " .. tostring(fixture.dragAt and (current - fixture.dragAt)) .. " ms before the throw")
    end
    -- How far the hauler is from the body it starts to take hold of.
    if reason == "production_grabbing" and fixture.lastGrabReason ~= reason then
        local nearest
        for dy = -2, 2 do
            for dx = -2, 2 do
                SC.GameplayUtil.squareStaticMovingObjects(
                    SC.GameplayUtil.gridSquare(x + dx, y + dy, z), function(object)
                        if SC.GameplayUtil.instanceOf(object, "IsoDeadBody") then
                            local bx, by = position(object)
                            local d = math.sqrt((bx - x) ^ 2 + (by - y) ^ 2)
                            if nearest == nil or d < nearest then nearest = d end
                        end
                    end, 16)
            end
        end
        print("SC_REAL_SANDBOX|UPSTAIRS_GRAB|hauler=" .. key(x, y, z) .. " nearestBody="
            .. string.format("%.2f", nearest or -1))
        fixture.grabDistances = fixture.grabDistances or {}
        fixture.grabDistances[#fixture.grabDistances + 1] = string.format("%.2f", nearest or -1)
        local shot = tostring(H.config.run_id) .. "-grab-" .. tostring(#fixture.grabDistances)
        pcall(function() getCore():TakeFullScreenshot(shot) end)
    end
    fixture.lastGrabReason = reason
    if reason == "production_throw_missed" then
        result("PASS", "upstairs_haul_throw_missed_recovered", "the throw left the body indoors at "
            .. key(x, y, z) .. "; settled and tried again")
    end
    if reason == "thrown_body_lost" then
        local wx, wy = fixture.window.ox, fixture.window.oy
        local roof, roofSquare = taggedBodyNear(SC, wx, wy, fixture.window.z, 3)
        fail(fixture, result, setPhase, current, "upstairs_haul_body_landed",
            "lost; upstairs copy=" .. tostring(roof ~= nil) .. " at="
                .. tostring(roofSquare and key(position(roofSquare)))
                .. " near: " .. thrownBodyDetail(SC, fixture))
        return
    end
    if reason == "production_body_thrown_out" and not fixture.landedAt then
        fixture.landedAt = current
        local body, landed = taggedBodyNear(SC, fixture.window.ox, fixture.window.oy, 0, 3)
        local lx, ly, lz = position(landed)
        check("upstairs_haul_body_landed", body ~= nil and lz ~= nil and lz < 0.5,
            "landed=" .. key(lx, ly, lz) .. " expected=" .. key(fixture.window.ox,
                fixture.window.oy, 0) .. " after " .. tostring(current - (fixture.throwAt or current)) .. " ms")
        pcall(function() getCore():TakeFullScreenshot(tostring(H.config.run_id)
            .. "-upstairs-landed") end)
    end
    if fixture.landedAt and not upstairs and z ~= nil and z < 0.05 and not fixture.downAt then
        fixture.downAt = current
        result("PASS", "upstairs_haul_hauler_came_down", "at=" .. key(x, y, z)
            .. " after " .. tostring(current - fixture.landedAt) .. " ms")
    end
    if fixture.landedAt and reason == "production_dragging" and not upstairs
        and not fixture.regrabAt then
        fixture.regrabAt = current
        result("PASS", "upstairs_haul_regrabbed_below", "at=" .. key(x, y, z))
    end
    if fixture.regrabAt and reason == "production_placing" and not fixture.placedAt then
        fixture.placedAt = current
        result("PASS", "upstairs_haul_placed_on_pyre", "at=" .. key(x, y, z))
    end
    -- Every reason after the drop, in order, to see why a pyre stays unlit.
    if fixture.placedAt then
        fixture.afterDrop = fixture.afterDrop or {}
        local phase = tostring(SC.Production.workerPhase(fixture.order.id, fixture.worker.id))
        local step = reason .. "/" .. phase
        if fixture.afterDrop[#fixture.afterDrop] ~= step and #fixture.afterDrop < 30 then
            fixture.afterDrop[#fixture.afterDrop + 1] = step
            if reason == "production_placing" or reason == "production_replacing_body"
                or reason == "production_burning" then
                print("SC_REAL_SANDBOX|UPSTAIRS_PLACEMENT|" .. reason .. " "
                    .. placementDetail(SC, fixture, actor))
            end
        end
        if current - fixture.placedAt > 60000 then
            fail(fixture, result, setPhase, current, "upstairs_haul_pyre_lit",
                "no fire a minute after the drop; afterDrop=" .. table.concat(fixture.afterDrop, ","))
            return
        end
    end
    if fixture.order.state == "blocked" then
        fail(fixture, result, setPhase, current, "upstairs_haul_pyre_lit",
            "blocked: " .. tostring(fixture.order.blocker) .. " "
                .. placementDetail(SC, fixture, actor)
                .. " afterDrop=" .. table.concat(fixture.afterDrop or {}, ","))
        return
    end
    local counters = SC.BaseLife.productionCounters()
    if call(fixture.pyre, "haveFire") == true and (counters.pyresLit or 0) > fixture.counterBefore then
        check("upstairs_haul_pyre_lit", fixture.landedAt ~= nil and fixture.regrabAt ~= nil,
            "grab distances " .. table.concat(fixture.grabDistances or {}, "/")
                .. " fire at " .. key(position(fixture.pyre)) .. " total "
                .. tostring(current - fixture.startedAt) .. " ms seen="
                .. table.concat(fixture.sequence, ","))
        setPhase("upstairs_haul_capture", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "upstairs_haul_setup" then
        if current - H.phaseStartedAt < 4000 then return end
        if (not SC.BaseLife.active() or #(SC.Registry.records() or {}) == 0)
            and current - H.phaseStartedAt < 12000 then return end
        if upperArea(SC.BaseLife.active()) then
            setup(H, SC, check, result, setPhase, current)
        else
            adoptHouse(H, SC, check, result, setPhase, current)
        end
        return
    end
    if H.phase == "upstairs_haul_link" then
        -- The camp's rolling stair survey, run faster than its runtime pulse.
        for _ = 1, 8 do SC.BaseLife.autoExtendFloors(24) end
        local upper = upperArea(SC.BaseLife.active())
        if upper then
            result("PASS", "upstairs_haul_floor_linked", "area@" .. tostring(upper.x1) .. "-"
                .. tostring(upper.x2) .. "," .. tostring(upper.y1) .. "-" .. tostring(upper.y2)
                .. ",z" .. tostring(upper.z) .. " after " .. tostring(current - H.phaseStartedAt) .. " ms")
            setup(H, SC, check, result, setPhase, current)
        elseif current - H.phaseStartedAt > 60000 then
            result("FAIL", "upstairs_haul_floor_linked", "the stair survey found no stairs to link")
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "upstairs_haul_spawn" then
        spawn(H, SC, check, result, setPhase, current)
        return
    end
    if H.phase == "upstairs_haul_wait" then
        wait(H, SC, check, result, setPhase, current)
        return
    end
    if H.phase == "upstairs_haul_capture" then
        if current - H.phaseStartedAt < 750 then return end
        local name = tostring(H.config.run_id) .. "-upstairs-pyre-lit"
        local ok, failure = pcall(function() getCore():TakeFullScreenshot(name) end)
        check("upstairs_haul_screenshot", ok, name .. ".png " .. tostring(failure))
        setPhase("upstairs_haul_finish", current)
        return
    end
    if H.phase == "upstairs_haul_finish" and current - H.phaseStartedAt > 1800 then
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCUpstairsHaulProbe = Probe
return Probe
