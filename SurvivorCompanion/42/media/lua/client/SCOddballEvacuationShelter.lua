-- SPDX-License-Identifier: MIT
-- The Evacuation's shelter, from unseen placement to the first approach.

local SC = SurvivorCompanion
SC.OddballEvacuationShelter = SC.OddballEvacuationShelter or {}
local Shelter = SC.OddballEvacuationShelter

local ID = "evacuation"
local DOOR_MARKER = "LF_EvacuationDoor"
local DOOR_RESERVE = 4000
local PROTECTION_RADIUS = 12
local TALK_RADIUS = 3.5
local CLEAR_RADIUS = 15
local MAX_CLEAR = 512
local MAX_BUILDING_SPAN = 42
local CARDINAL = { { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 } }
local ROOM_NAMES = { bedroom = true, bathroom = true, storage = true,
    utility = true, livingroom = true, kitchen = true }

local deferredDoors = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function read(value, method, ...)
    return (U().call(value, method, ...))
end

local function story(group)
    return SC.OddballKit.story(group, ID)
end

local function squareAt(position)
    return position and U().gridSquare(position.x, position.y, position.z or 0)
end

local function point(square)
    local x, y, z = U().position(square)
    if x ~= nil then return { x = x, y = y, z = z } end
end

local function doorLocator(door)
    local position = point(U().squareOf(door))
    local index, north = read(door, "getObjectIndex"), read(door, "getNorth")
    if not position or type(index) ~= "number" or index < 0
        or type(north) ~= "boolean" then return nil end
    position.objectIndex, position.kind, position.north = index, "door", north
    return position
end

local function doorAt(position)
    local square = squareAt(position)
    local objects = read(square, "getObjects")
    local door = objects and SC.NativeList.get(objects, position.objectIndex)
    if U().instanceOf(door, "IsoDoor")
        and (position.north == nil or read(door, "getNorth") == position.north) then
        return door
    end
end

local function sameDoorPost(first, second)
    return first and second and U().sameSquare(first, second)
        and first.objectIndex == second.objectIndex and first.north == second.north
end

local function soundDoor(door)
    local hp = read(door, "getHealth")
    return U().instanceOf(door, "IsoDoor") and type(hp) == "number" and hp > 0
        and read(door, "IsOpen") == false and read(door, "isDestroyed") ~= true
end

local function canLock(door)
    return soundDoor(door) and not SC.Topology.objectLocked(door)
        and not SC.Topology.objectBarricaded(door) and read(door, "isObstructed") ~= true
end

local function smallHouse(house)
    local bounds = house and house.bounds
    if not bounds or bounds.x2 - bounds.x1 > MAX_BUILDING_SPAN
        or bounds.y2 - bounds.y1 > MAX_BUILDING_SPAN then return nil end
    return bounds
end

local function roomAt(square) return read(square, "getRoom") end
local function buildingAt(square) return read(square, "getBuilding") end

local function squareSeen(square, player)
    local number = read(player, "getPlayerNum")
    return type(number) == "number" and read(square, "isCanSee", number) ~= false
        or U().canSee(player, square)
end

local function unseen(square, player, allowSeen)
    if not U().isClearActorSpawnSquare(square) then return false end
    if allowSeen then return true end
    return type(read(player, "getPlayerNum")) == "number" and not squareSeen(square, player)
end

-- A room boundary may be a wall or intact shut glass. Its one exit must be a
-- real interior door. Reuse topology's edge getters for frames and open doors.
local function inspectRoom(origin, bounds)
    local room, building = roomAt(origin), buildingAt(origin)
    if not room or not building then return nil end
    local door, inside, outside
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            local square = U().gridSquare(x, y, 0)
            if roomAt(square) == room then
                if SC.Topology.squareHasStairs(square) then return nil end
                for _, offset in ipairs(CARDINAL) do
                    local other = U().gridSquare(x + offset[1], y + offset[2], 0)
                    if other == nil then return nil end
                    if roomAt(other) ~= room then
                        local opening, kind = SC.Topology.barrierBetween(square, other)
                        if kind == "door" then
                            if door or buildingAt(other) ~= building or not canLock(opening) then
                                return nil
                            end
                            door, inside, outside = opening, square, other
                        elseif kind == "window" then
                            if not U().instanceOf(opening, "IsoWindow")
                                or read(opening, "IsOpen") ~= false
                                or read(opening, "isSmashed") ~= false then return nil end
                        elseif kind ~= "blocked" then return nil end
                    end
                end
            end
        end
    end
    if door then return door, inside, outside, room, building end
end

local function ordinaryWalk(node)
    while node.parent do
        local kind = node.via and node.via.affordance
        if kind ~= "open" and kind ~= "door" then return false end
        node = node.parent
    end
    return true
end

local function walkableExit(player, outside, building)
    local nodes = SC.Topology.reachableEscapeSquares(player, outside,
        { radius = 18, nodeBudget = 160, exitLimit = 12 })
    for _, node in ipairs(nodes) do
        if buildingAt(node.square) ~= building and read(node.square, "isOutside") == true
            and ordinaryWalk(node) then return true end
    end
    return false
end

local function reachableRoomPosts(player, inside, room)
    local nodes = SC.Topology.reachableEscapeSquares(player, inside,
        { radius = 6, nodeBudget = 40, exitLimit = 8 })
    local posts = {}
    for _, node in ipairs(nodes) do
        if roomAt(node.square) == room and ordinaryWalk(node) then
            posts[U().squareKey(node.square)] = true
        end
    end
    return posts
end

function Shelter.siteFor(house, player, allowSeen)
    local bounds = smallHouse(house)
    if not bounds or not player then return nil end
    local rooms = {}
    for _, position in ipairs(house.interior or {}) do
        local square = squareAt(position)
        local room = roomAt(square)
        local name = read(room, "getName")
        if room and not rooms[room] and type(name) == "string"
            and ROOM_NAMES[string.lower(name)] then
            rooms[room] = true
            local door, inside, exit, _, building = inspectRoom(square, bounds)
            if door and unseen(inside, player, allowSeen)
                and walkableExit(player, exit, building) then
                local reachable = reachableRoomPosts(player, inside, room)
                local joy, brock = point(inside), nil
                for _, candidate in ipairs(house.interior) do
                    local post = squareAt(candidate)
                    if reachable[U().squareKey(post)] and unseen(post, player, allowSeen)
                        and (brock == nil or U().distance(joy, candidate) > U().distance(joy, brock)) then
                        brock = candidate
                    end
                end
                local locator = doorLocator(door)
                if brock and locator then
                    return { kind = "resident", room = name, house = house, anchor = house.anchor,
                        spawn = joy, memberSpawns = { joy, brock }, safeRoomDoor = locator }
                end
            end
        end
    end
end

local function siteLayout(site, house)
    local bounds = smallHouse(house)
    local posts = site.memberSpawns
    local joy, brock = squareAt(posts and posts[1]), squareAt(posts and posts[2])
    if not bounds or not U().isClearActorSpawnSquare(joy)
        or not U().isClearActorSpawnSquare(brock) then return false end
    local door, inside, exit, room, building = inspectRoom(joy, bounds)
    if not door or joy ~= inside or roomAt(brock) ~= room
        or not sameDoorPost(doorLocator(door), site.safeRoomDoor) then return nil end
    return { inside = inside, brock = brock, exit = exit, room = room, building = building }
end

function Shelter.acceptSite(site)
    if not siteLayout(site, site.house) then return false, "evacuation_shelter_unavailable" end
    return true
end

local function observers(player)
    local result = { player }
    if type(getSpecificPlayer) ~= "function" then return result end
    local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
    for index = 0, math.min(4, count) - 1 do
        local observer = getSpecificPlayer(index)
        if observer and observer ~= player and not U().isDead(observer) then
            result[#result + 1] = observer
        end
    end
    return result
end

local function inClearArea(square, building, bounds)
    local x, y, z = U().position(square)
    if not x then return false end
    local dx = math.max(bounds.x1 - x, 0, x - bounds.x2)
    local dy = math.max(bounds.y1 - y, 0, y - bounds.y2)
    if dx == 0 and dy == 0 and buildingAt(square) == building then return true end
    return z == 0 and dx * dx + dy * dy <= CLEAR_RADIUS * CLEAR_RADIUS
        and read(square, "isOutside") == true
end

local function canClear(zombie, viewers, group, square)
    if not SC.SpawnSafety.canClear(zombie, viewers[1], false) then return false end
    for index = 2, #viewers do
        if not SC.SpawnSafety.canClear(zombie, viewers[index], false) then return false end
    end
    if read(zombie, "getThumpTarget") ~= nil then return false end
    local owner = SC.Factions.atPosition(point(square))
    if owner and owner ~= group then return false end
    -- Authored walkers retain identifying LF modData outside their home.
    for key in pairs(U().modData(zombie) or {}) do
        if type(key) == "string" and (key:sub(1, 2) == "lf" or key:sub(1, 3) == "LF_") then
            return false
        end
    end
    return true
end

function Shelter.prepareFirstSpawn(group, player)
    local value = story(group)
    if not value then return "failed", "evacuation_story_missing" end
    if value.sceneSecured then return "ready", "evacuation_scene_ready" end
    if not player then return "pending", "evacuation_observer_unavailable" end
    local site = value.site
    local layout = siteLayout(site, group.house)
    if not layout or not reachableRoomPosts(player, layout.inside, layout.room)[U().squareKey(layout.brock)]
        or not walkableExit(player, layout.exit, layout.building) then
        return "failed", "evacuation_site_changed"
    end
    local building = layout.building
    local bounds = group.house.bounds
    local viewers = observers(player)
    for _, observer in ipairs(viewers) do
        if buildingAt(U().squareOf(observer)) == building
            or U().sameFloor(observer, site.spawn)
                and U().distance(observer, site.spawn) <= PROTECTION_RADIUS then
            return "failed", "evacuation_player_reached_site"
        end
        if not group.debugCreated and (squareSeen(squareAt(site.memberSpawns[1]), observer)
            or squareSeen(squareAt(site.memberSpawns[2]), observer)) then
            return "failed", "evacuation_posts_visible"
        end
    end
    local zombies = read(U().cell(), "getZombieList")
    if zombies == nil then return "pending", "evacuation_zombies_unavailable" end
    local doomed = {}
    local scanned, reason = SC.NativeList.each(zombies, function(zombie)
        local square = U().squareOf(zombie)
        if inClearArea(square, building, bounds) and canClear(zombie, viewers, group, square) then
            doomed[#doomed + 1] = zombie
            if #doomed > MAX_CLEAR then return false end
        end
    end)
    if not scanned then return "failed", reason end
    if #doomed > MAX_CLEAR then return "failed", "evacuation_population_limit" end
    for _, zombie in ipairs(doomed) do
        local square = U().squareOf(zombie)
        if inClearArea(square, building, bounds) and canClear(zombie, viewers, group, square) then
            local _, world = U().call(zombie, "removeFromWorld")
            local _, map = U().call(zombie, "removeFromSquare")
            if not world or not map then return "failed", "evacuation_zombie_removal_failed" end
        end
    end
    value.sceneSecured = true
    return "ready", "evacuation_scene_ready"
end

local function doorData(door)
    local data = U().modData(door)
    return data, data and data[DOOR_MARKER] or nil
end

local function markerFor(door, group)
    local data, marker = doorData(door)
    if not data then return nil end
    if marker then return type(marker) == "table" and marker.owner == group.id and marker or nil end
    marker = { owner = group.id }
    data[DOOR_MARKER] = marker
    return marker
end

local function protect(door, group)
    if not soundDoor(door) then return end
    local marker = markerFor(door, group)
    if not marker then return end
    local current = read(door, "getHealth")
    marker.health = marker.health or current
    if current < marker.health + DOOR_RESERVE / 2 then
        U().call(door, "setHealth", marker.health + DOOR_RESERVE)
    end
end

local function reconcileDoor(door, group)
    local data, marker = doorData(door)
    if type(marker) ~= "table" then return true end
    local value = story(group)
    local retired = value == nil or group.lifecycle == "destroyed"
    if marker.health ~= nil and (retired or value.shelterProtectionReleased == true
        or not soundDoor(door)) then
        local health = read(door, "getHealth")
        if type(health) == "number" and health > marker.health then
            U().call(door, "setHealth", marker.health)
            if read(door, "getHealth") ~= marker.health then return false end
        end
        marker.health = nil
    end
    if marker.locked == true and (retired or value.shelterDoorUnlocked == true) then
        U().call(door, "setLocked", false)
        if read(door, "isLocked") ~= false then return false end
        marker.locked = nil
    end
    if marker.health == nil and marker.locked ~= true then data[DOOR_MARKER] = nil end
    return true
end

local function markedDoors(square, callback)
    local list = read(square, "getSpecialObjects")
    if not list or SC.NativeList.size(list) == 0 then return end
    SC.NativeList.each(list, function(door)
        if not U().instanceOf(door, "IsoDoor") then return end
        local _, marker = doorData(door)
        if type(marker) == "table" and type(marker.owner) == "string" then
            callback(door, marker)
        end
    end)
end

local function forSceneDoors(group, value, callback)
    local seen = {}
    local function visit(post, shelterDoor)
        if not post or post.kind ~= "door" then return end
        local door = doorAt(post)
        if door and not seen[door] then
            seen[door] = true
            callback(door, shelterDoor)
        end
        -- Object indices may change when unrelated objects on a square are
        -- removed. Only the object's own marker can authorize restoration.
        markedDoors(squareAt(post), function(marked, marker)
            if marker.owner == group.id and not seen[marked] then
                seen[marked] = true
                callback(marked, shelterDoor)
            end
        end)
    end
    visit(value.site.safeRoomDoor, true)
    for _, post in ipairs(group.house.openings or {}) do visit(post, false) end
end

local function claimedRoomDoor(group, value)
    local claimed
    markedDoors(squareAt(value.site.safeRoomDoor), function(door, marker)
        if marker.owner == group.id and marker.locked == true then claimed = door end
    end)
    return claimed
end

local function belongsToExterior(door, building)
    local square = U().squareOf(door)
    local x, y, z = U().position(square)
    local north = read(door, "getNorth")
    if not x or type(north) ~= "boolean" or not building then return false end
    local opposite = U().gridSquare(x - (north and 0 or 1), y - (north and 1 or 0), z)
    if not opposite then return false end
    local here, there = buildingAt(square), buildingAt(opposite)
    return here == building and there == nil or there == building and here == nil
end

function Shelter.onJoySpawn(group)
    local value = story(group)
    if not value or not value.sceneSecured then return false, "evacuation_scene_unready" end
    if value.shelterDoorLocked or value.shelterDoorUnlocked then return true end
    local door = doorAt(value.site.safeRoomDoor)
    if not canLock(door) then return false, "evacuation_lock_unavailable" end
    local marker = markerFor(door, group)
    if not marker then return false, "evacuation_door_in_use" end
    marker.locked = true
    U().call(door, "setLocked", true)
    if read(door, "isLocked") ~= true then return false, "evacuation_lock_failed" end
    value.shelterDoorLocked = true
    local player = type(getPlayer) == "function" and getPlayer() or nil
    local viewers = observers(player)
    local building = buildingAt(squareAt(value.site.spawn))
    if not value.shelterProtectionReleased then
        forSceneDoors(group, value, function(opening, interior)
            if not interior and not belongsToExterior(opening, building) then return end
            if not interior and read(opening, "IsOpen") == true then
                local square = U().squareOf(opening)
                for _, viewer in ipairs(viewers) do
                    if squareSeen(square, viewer) then return end
                end
                U().call(opening, "ToggleDoorSilent")
            end
            protect(opening, group)
        end)
    end
    return true
end

local function near(post, viewer, radius)
    return viewer and U().sameFloor(post, viewer) and U().distance(post, viewer) <= radius
end

function Shelter.pulse(group, player)
    local value = story(group)
    if not value or not value.shelterDoorLocked then return false, "evacuation_lock_unavailable" end
    local post = value.site.safeRoomDoor
    if not value.shelterProtectionReleased then
        for _, observer in ipairs(observers(player)) do
            if near(post, observer, PROTECTION_RADIUS) then
                value.shelterProtectionReleased = true
                break
            end
        end
    end
    if value.shelterProtectionReleased then
        forSceneDoors(group, value, function(door)
            local _, marker = doorData(door)
            if marker and marker.owner == group.id then reconcileDoor(door, group) end
        end)
    else
        forSceneDoors(group, value, function(door)
            local _, marker = doorData(door)
            if marker and marker.owner == group.id and reconcileDoor(door, group)
                and marker.health then protect(door, group) end
        end)
    end
    if not near(post, player, TALK_RADIUS) then return false, "evacuation_player_distant" end
    if not value.shelterDoorUnlocked then
        if not squareAt(post) then return false, "evacuation_door_unloaded" end
        value.shelterDoorUnlocked = true
        local door = claimedRoomDoor(group, value)
        if door and not reconcileDoor(door, group) then
            value.shelterDoorUnlocked = nil
            return false, "evacuation_unlock_failed"
        end
    end
    return true, "evacuation_shelter_reached"
end

function Shelter.release(group)
    local value = story(group)
    if not value then return true end
    value.shelterProtectionReleased, value.shelterDoorUnlocked = true, true
    forSceneDoors(group, value, function(door)
        local _, marker = doorData(door)
        if marker and marker.owner == group.id then reconcileDoor(door, group) end
    end)
    return true
end

local function reconcileLoadedDoor(door)
    local _, marker = doorData(door)
    if marker then reconcileDoor(door, SC.Factions.group(marker.owner)) end
end

function Shelter.onSquareLoaded(square)
    markedDoors(square, function(door)
        if SC.State and SC.State.active == true then reconcileLoadedDoor(door)
        else deferredDoors[door] = true end
    end)
end

function Shelter.reconcileLoaded()
    for door in pairs(deferredDoors) do reconcileLoadedDoor(door) end
    Shelter.reset()
end

function Shelter.reset()
    deferredDoors = setmetatable({}, { __mode = "k" })
end

Shelter.siteFields = { { field = "safeRoomDoor", depth = 2, required = true } }
Shelter.claims = { safeRoomDoor = true }

function Shelter.validate(value, path, kit)
    local locator = value.site.safeRoomDoor
    local okay, reason = kit.opening(locator, path .. ".site.safeRoomDoor", "door", "expected safe-room door")
    if not okay then return false, reason end
    if locator.z ~= 0 or type(locator.north) ~= "boolean" then
        return kit.fail(path .. ".site.safeRoomDoor", "expected a ground-floor door with orientation")
    end
    for _, field in ipairs({ "shelterDoorLocked", "shelterDoorUnlocked", "shelterProtectionReleased" }) do
        if value[field] ~= nil and type(value[field]) ~= "boolean" then
            return kit.fail(path .. "." .. field, "expected optional boolean")
        end
    end
    return true
end

return Shelter
