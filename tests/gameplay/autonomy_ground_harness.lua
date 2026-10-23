-- SPDX-License-Identifier: MIT
-- Standalone: partial furniture must not become a breakdown's ground seat.
local SC, checks = SurvivorCompanion, 0
local Autonomy = SC.Autonomy
local function check(value, message)
    checks = checks + 1
    if not value then error("autonomy ground check " .. checks .. ": " .. message) end
end
local tick, tiles, people, sits, requests = 1000, {}, {}, {}, {}
local rest, restZone, moveAccepted = nil, nil, true
local function tile(x, y, fields)
    local value = fields or {}
    value.x, value.y, value.z, value.room = x, y, 0, "quiet-room"
    function value:getRoom() return self.room end
    function value:isSolid() return self.solid == true end
    tiles[x .. ":" .. y] = value
    return value
end
local function actor(id, x, y, response)
    local value = { id = id, x = x, y = y, z = 0, seated = false,
        commands = { recruited = true, personalityProfile = {} },
        mind = { stressResponse = response or "shutdown", boredom = 10 } }
    function value:isSitOnGround() return self.seated end
    people[id] = value
    return value
end
local U = {
    config = function() return nil end,
    nowMs = function() return tick end,
    idOf = function(value) return value.id end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = function(x, y, z) return z == 0 and tiles[x .. ":" .. y] or nil end,
    loadedSquare = function(point) return tiles[point.x .. ":" .. point.y] end,
    squareOf = function(value) return tiles[math.floor(value.x) .. ":" .. math.floor(value.y)] end,
    isSquareFree = function(square) return square.free ~= false end,
    squareOccupyingObject = function(square) return square.furniture end,
    movingBlocker = function(square, value)
        return square.body ~= value and square.body or nil
    end,
    sameSquare = function(first, second)
        return math.floor(first.x) == math.floor(second.x)
            and math.floor(first.y) == math.floor(second.y) and first.z == second.z
    end,
    arrived = function(value, square, options)
        local dx, dy = value.x - square.x - 0.5, value.y - square.y - 0.5
        return dx * dx + dy * dy <= options.distance * options.distance
    end,
    distance = function(first, second)
        return math.sqrt((first.x - second.x)^2 + (first.y - second.y)^2)
    end,
    edgeBlocked = function(square) return square.besideWall == true end,
    nativeHealth = function() return 100 end,
    call = function(object, name, ...)
        if object and type(object[name]) == "function" then return object[name](object, ...), true end
        return nil, false
    end,
    say = function() return true end,
    stop = function() return true end,
    move = function(value, _, intent)
        if intent.action == "sit_ground" then
            sits[#sits + 1] = { actor = value, square = tiles[math.floor(value.x)
                .. ":" .. math.floor(value.y)] }
            value.seated = true
        elseif intent.action == "stand_ground" then value.seated = false end
        return true
    end,
}
SC.GameplayUtil = U
SC.Commands = { peek = function(value) return value.commands end, persist = function() end }
SC.Community = {
    mindFor = function(value) return value.mind end,
    reserve = function() return true end,
    release = function() end,
    beginMajor = function(value, kind) value.mind.activeEpisode = kind end,
    finishMajor = function(value) value.mind.activeEpisode = nil end,
    finishGriefReaction = function() end,
    addThought = function() end,
}
SC.LifeEvents = { now = function() return tick end, emit = function() end }
SC.BaseLife = { zoneCenter = function() return rest, restZone end }
SC.Topology = {
    squareHasStairs = function(square) return square.stairs == true end,
    squareHasSlope = function(square) return square.slope == true end,
    squareHazards = function(square) return square.hazards or {} end,
}
SC.Navigation = { doorThresholdSquare = function(square) return square.door == true end,
request = function(value, destination, _, intent)
    requests[#requests + 1] = { actor = value, destination = destination, intent = intent }
    return moveAccepted, moveAccepted and "moving" or "unreachable"
end }
SC.NativeActions = { cancelVisual = function() end }
local function update(value, detail)
    tick = tick + 100
    return Autonomy.update(value, nil, { snapshot = { threatCount = 0 } }, detail)
end
local function reset()
    Autonomy.reset()
    tiles, people, sits, requests, rest, restZone, moveAccepted = {}, {}, {}, {}, nil, nil, true
end
local function zone(x, y)
    rest = { x = x, y = y, z = 0 }
    restZone = { x1 = x - 2, y1 = y - 2, x2 = x + 2, y2 = y + 2 }
end

-- The centre itself is a chair; a partial object still reads native "free".
reset()
local chair = tile(10, 10, { furniture = "chair" })
local floor = tile(11, 10)
zone(10, 10)
local shutdown = actor("shutdown-chair", 10.5, 10.5)
update(shutdown)
check(#sits == 0, "a shutdown must never sit on the chair it is standing inside")
check(#requests == 1 and requests[1].destination == floor
        and requests[1].intent.requireSameSquare == true
        and requests[1].intent.arrivalDistance <= 0.35,
    "the shutdown selects nearby clear floor and requests an accurate approach")
update(shutdown)
check(#sits == 0, "being one tile from the clear destination does not permit sitting in the chair")
shutdown.x, shutdown.y = 11.05, 10.05
update(shutdown)
check(#sits == 0, "entering the destination tile at its edge still requires reaching the seat centre")
shutdown.x, shutdown.y = 11.5, 10.5
update(shutdown)
update(shutdown)
check(#sits == 1 and sits[1].square == floor and shutdown.seated,
    "the ground pose starts only after reaching clear floor")

-- Furniture moved onto an active seat must release the pose and replan.
floor.furniture = "new-chair"
local alternate = tile(12, 10)
update(shutdown)
check(shutdown.seated == false and #sits == 1,
    "furniture moved onto an active shutdown makes the companion stand")
update(shutdown)
check(requests[#requests].destination == alternate and #sits == 1,
    "the shutdown finds another clear seat instead of restoring the obstructed pose")
shutdown.x, shutdown.y = 12.5, 10.5
update(shutdown)
update(shutdown)
check(#sits == 2 and sits[2].square == alternate,
    "a shutdown resumes on the newly verified clear floor")

-- A moving body at the planned destination is just as unsuitable as furniture.
reset()
zone(20, 20)
local occupied = tile(20, 20)
local second = tile(21, 20)
tile(19, 20, { furniture = "chair" })
local blocked = actor("shutdown-body", 19.5, 20.5)
update(blocked)
occupied.body = { id = "other-companion" }
update(blocked)
check(#sits == 0 and requests[#requests].destination == second,
    "a companion entering the destination causes clear-floor reselection")

-- No clear floor is available: stand and withdraw without starting a pose.
reset()
zone(30, 30)
tile(30, 30, { furniture = "chair" })
local crowded = actor("shutdown-no-floor", 30.5, 30.5)
local _, fallback = update(crowded)
check(fallback == "shutdown_fallback_to_withdraw" and #sits == 0,
    "a shutdown falls back to standing withdrawal when all floor is occupied")
crowded.seated = true
Autonomy.reset()
update(crowded)
update(crowded)
check(crowded.seated == false and #sits == 0,
    "the no-place fallback also gets an existing invalid ground pose standing")

-- Route failure has a deadline even though a shutdown itself lasts hours.
reset()
zone(35, 35)
tile(35, 35)
tile(34, 35, { furniture = "chair" })
local unreachable = actor("shutdown-unreachable", 34.5, 35.5)
update(unreachable)
tick = tick + 37000
local _, timedOut = update(unreachable)
check(timedOut == "shutdown_fallback_to_withdraw" and #sits == 0,
    "an unreachable quiet seat eventually falls back to standing withdrawal")

-- The unzoned wall fallback also rejects chairs and moving bodies.
reset()
tile(40, 40)
tile(41, 40, { furniture = "chair", besideWall = true })
local wall = tile(42, 40, { besideWall = true })
local unzoned = actor("shutdown-wall", 40.5, 40.5)
update(unzoned)
check(#sits == 0 and requests[#requests].destination == wall,
    "an unzoned wall spot selects clear floor beyond the nearer chair")

-- Mourning shares the same exact approach and dynamic seat validation.
reset()
zone(50, 50)
tile(50, 50, { furniture = "chair" })
local mourningFloor = tile(51, 50)
local mourner = actor("mourning-chair", 50.5, 50.5)
local grief = { kind = "grief_response", grief = {
    subjectId = "lost", subjectName = "Lost Friend", witnessed = true, intensity = 70,
} }
update(mourner, grief)
update(mourner, grief)
check(#sits == 0 and requests[#requests].destination == mourningFloor,
    "mourning routes away from a chair rather than sitting next to its destination")
mourner.x, mourner.y = 51.5, 50.5
update(mourner, grief)
update(mourner, grief)
check(#sits == 1 and sits[1].square == mourningFloor, "mourning sits on verified clear floor")
mourningFloor.furniture = "moved-table"
tile(52, 50)
update(mourner, grief)
check(not mourner.seated and #sits == 1, "mourning releases its pose when furniture moves onto it")

-- A clear tile still cannot be a fire, broken glass, a stair or a doorway.
for _, hazard in ipairs({ "fire", "brokenGlass", "stairs", "slope", "door" }) do
    reset()
    zone(60, 60)
    local unsafe = tile(60, 60)
    if hazard == "fire" or hazard == "brokenGlass" then
        unsafe.hazards = { [hazard] = true }
    else unsafe[hazard] = true end
    local avoid = actor("shutdown-" .. hazard, 60.5, 60.5)
    local _, result = update(avoid)
    check(result == "shutdown_fallback_to_withdraw" and #sits == 0,
        "quiet ground excludes " .. hazard)
end

reset()
SC_TEST_REPORT = "AUTONOMY_GROUND_PASS checks=" .. checks
