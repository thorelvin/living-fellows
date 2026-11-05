-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local now = 5000000
local hours = 24 * 4 + 19
local player = { id = "player", x = 40, y = 0, z = 0 }
local ruth = { id = "ruth", x = 0, y = 0, z = 0, shelter = false }
local fellow = { id = "fellow", x = 41, y = 1, z = 0 }
local car = { id = "car", x = 6, y = 0, z = 0, stationary = false, driver = nil }
local doorSquare = { x = 5, y = 2, z = 0 }
local visibleRuth, floorSeen = true, false
local emotes, routes, boards, exits, marks, spawned = {}, {}, {}, {}, {}, {}
local hibernated, retiredReason = false, nil
local houseFound = true
local tiles = {}
local deadBody
SandboxVars = { HoursForCorpseRemoval = 216 }

local function tile(x, y, z)
    local key = x .. ":" .. y .. ":" .. (z or 0)
    if not tiles[key] then
        tiles[key] = { x = x, y = y, z = z or 0, room = nil }
    end
    return tiles[key]
end
tile(101, 50, 0).room = { getName = function() return "LivingRoom" end }
tile(104, 52, 0).room = { getName = function() return "Bedroom" end }

local house = { anchor = { x = 100, y = 50, z = 0 }, primaryEntry = { x = 99, y = 50, z = 0 },
    interior = { { x = 101, y = 50, z = 0 }, { x = 104, y = 52, z = 0 } } }

addZombiesInOutfit = function(x, y, z, count, outfit, female)
    local zombie = { x = x, y = y, z = z, outfit = outfit, female = female, data = {}, killed = false }
    spawned[#spawned + 1] = zombie
    return { zombie }
end
getGameTime = function() return {} end
SC.NativeList = {
    size = function(list) return #list end,
    get = function(list, index) return list[index + 1] end,
}

SC.GameplayUtil = {
    nowMs = function() return now end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value == nil or value.dead == true end,
    idOf = function(value) return value and value.id end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    sameFloor = function(a, b) return (a.z or 0) == (b.z or 0) end,
    canSee = function(observer, target)
        if target == ruth then return visibleRuth end
        return true
    end,
    gridSquare = function(x, y, z) return tile(x, y, z) end,
    isSafeSpawnSquare = function(square) return square ~= nil end,
    modData = function(value) return value.data end,
    addItem = function(container, kind)
        local item = { kind = kind, pages = {} }
        container.items[#container.items + 1] = item
        return item
    end,
    say = function(actor, line) actor.lastLine = line return true end,
    call = function(value, method, a, b)
        if method == "getWorldAgeHours" then return hours, true end
        if value == ruth then
            if method == "isZombiesDontAttack" then return ruth.shelter, true end
            if method == "getVehicle" then return ruth.vehicle, true end
        end
        if value == player then
            if method == "getVehicle" then return player.vehicle, true end
            if method == "getPlayerNum" then return 0, true end
        end
        if value == car and method == "getDriver" then return car.driver, true end
        if type(value) == "table" and value.room ~= nil and method == "getRoom" then
            return value.room, true
        end
        if type(value) == "table" and value.x and method == "isCanSee" then
            return floorSeen and value.x == 104, true
        end
        if type(value) == "table" and value.x and method == "getDeadBody" then
            if deadBody and value.x == 104 and value.y == 52 then return deadBody, true end
            return nil, true
        end
        if method == "getName" and type(value) == "table" and value.getName then
            return value.getName(), true
        end
        if method == "Kill" then value.killed = true return nil, true end
        if method == "setDeathTime" then value.deathTime = a return nil, true end
        if method == "getContainer" and value == deadBody then return deadBody.container, true end
        if method == "setName" then value.name = a return nil, true end
        if method == "addPage" then value.pages[a] = b return nil, true end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        if id == "ruth" and not hibernated then return { actor = ruth } end
        if id == "fellow" then return { actor = fellow, recruited = true } end
        return nil
    end,
    living = function() return { ruth, fellow } end,
}
SC.Oddballs = {
    setZombieShelter = function(actor, wanted) actor.shelter = wanted return true end,
    retire = function(group, reason) retiredReason = reason return true end,
}
SC.Relationship = { playEmote = function(actor, emote)
    emotes[#emotes + 1] = emote
    return true
end }
SC.Navigation = { request = function(actor, square, gait, options)
    routes[#routes + 1] = { square = square, gait = gait, action = options.action }
    return true, "moving"
end }
SC.Vehicle = {
    isStationary = function(vehicle) return vehicle.stationary == true end,
    boardingSquare = function(actor, vehicle) return doorSquare, 2 end,
    board = function(actor, vehicle, seat, intent)
        assert(intent.allowVirtualSeat == false, "never a virtual seat")
        boards[#boards + 1] = { seat = seat }
        actor.vehicle = vehicle
        return true
    end,
    exit = function(actor, vehicle, seat)
        exits[#exits + 1] = { seat = seat }
        actor.vehicle = nil
        return true
    end,
}
SC.Factions = {
    findHouse = function(_, options)
        assert(options.purpose == "oddball" and options.minimumDistance == 60)
        return houseFound and house or nil
    end,
    describeLocation = function(position)
        assert(position == house.anchor)
        return { address = "27 Locust Street" }
    end,
    hibernateOddballRoamer = function()
        if visibleRuth then return false end
        hibernated = true
        return true
    end,
}
SC.FactionLife = { addMapAnnotation = function(text, x, y)
    marks[#marks + 1] = { text = text, x = x, y = y }
    return true
end }

local H = SC.OddballHitchhiker
local LINES = H.LINES

local function newGroup()
    return { id = "ruth-group", standing = "Neutral", lifecycle = "active",
        members = { { actorId = "ruth" } },
        oddball = { id = "hitchhiker_ruth_ann", stage = "unmet",
            site = { kind = "roamer", spawn = { x = 0, y = 0, z = 0 } } } }
end
local group = newGroup()
local function contains(pool, line)
    for _, entry in ipairs(LINES[pool]) do if entry == line then return true end end
    return false
end
local function said()
    local line = ruth.lastLine
    ruth.lastLine = nil
    return line
end
local function tick()
    local intent = H.intentFor(ruth, player, {}, group)
    return H.update(ruth, player, {}, intent, group)
end

-- Lines and the letter: ASCII, short, no game words.
do
    local banned = { "tile", "player", "save", "mod", "moodle", "reload", "game" }
    local function lint(line, label)
        assert(not string.find(line, "[^\032-\126]"), label .. " is printable ASCII: " .. line)
        local words = 0
        for _ in string.gmatch(line, "%S+") do words = words + 1 end
        assert(words <= 18, label .. " stays at eighteen words or fewer: " .. line)
        for _, word in ipairs(banned) do
            assert(not string.find(string.lower(line), "%f[%a]" .. word .. "s?%f[%A]"),
                label .. " avoids the game word '" .. word .. "': " .. line)
        end
    end
    for pool, list in pairs(LINES) do
        for index, line in ipairs(list) do lint(line, pool .. "[" .. index .. "]") end
    end
    lint(H.LETTER, "letter")
end

-- The dead never notice her, from the first moment.
H.pulse(group, player, now)
assert(ruth.shelter == true, "zombies ignore her")
assert(#emotes == 0 and group.discovered ~= true, "forty meters out, nothing yet")

-- Thumbing: an emote at thirty meters, words at ten, not every pulse.
player.x = 25
H.pulse(group, player, now)
assert(emotes[1] == "thumbsup" and group.discovered == true and said() == nil)
player.x = 8
H.pulse(group, player, now + 1000)
assert(#emotes == 1, "the thumb waits its turn")
now = now + 16000
H.pulse(group, player, now)
assert(#emotes == 2 and contains("thumb", said()), "close by on foot, she asks")

-- A moving car is not a ride; a stopped one is.
player.vehicle, car.driver = car, player
player.x = 6
now = now + 1000
H.pulse(group, player, now)
assert(group.oddball.stage == "thumbing", "she waits for the car to stop")
car.stationary = true
H.pulse(group, player, now)
assert(group.oddball.stage == "boarding" and said() == LINES.board[1])

-- She walks to the passenger door, then really boards.
assert(tick())
assert(routes[#routes].square.x == doorSquare.x and routes[#routes].square.y == doorSquare.y
        and #boards == 0, "first the walk to the door")
ruth.x, ruth.y = 5, 2
assert(tick())
assert(#boards == 1 and boards[1].seat == 2 and group.oddball.stage == "riding"
        and ruth.vehicle == car, "a real passenger seat")
assert(said() == "It's 27 Locust Street. I'll show you.", "a real address")
assert(marks[1].text == "[LF] Ruth Ann's house" and marks[1].x == 100)
assert(group.oddball.home.floor.x == 104 and group.oddball.home.floor.y == 52,
    "what waits inside waits in the bedroom")

-- The ride: one unsettling line every thirty seconds; a companion notices once.
car.stationary = false
fellow.x, fellow.y = 6, 1
now = now + 31000
H.pulse(group, player, now)
assert(contains("ride", said()) and fellow.lastLine == LINES.fellowRide[1])
fellow.lastLine = nil
now = now + 5000
H.pulse(group, player, now)
assert(said() == nil)
now = now + 26000
H.pulse(group, player, now)
assert(contains("ride", said()) and fellow.lastLine == nil)

-- Stopping short of the house is not arriving.
car.x, car.stationary = 50, true
now = now + 1000
H.pulse(group, player, now)
assert(group.oddball.stage == "riding" and #exits == 0)
car.x, car.y = 95, 52
H.pulse(group, player, now)
assert(group.oddball.stage == "walking_home" and #exits == 1 and exits[1].seat == 2
        and said() == LINES.arrive[1], "at the house she gets out")

-- She walks in to the bedroom, and goes when nobody is looking.
assert(tick())
assert(routes[#routes].square.x == 104 and routes[#routes].square.y == 52)
ruth.x, ruth.y = 104, 52
H.pulse(group, player, now)
assert(not hibernated, "in plain sight she is still there")
visibleRuth = false
H.pulse(group, player, now)
assert(not hibernated, "a blink out of view is not enough")
now = now + 2100
H.pulse(group, player, now)
assert(hibernated and group.oddball.stage == "gone_inside", "unseen, she is gone")

-- The body is placed only where the player cannot see.
floorSeen = true
now = now + 1000
H.pulse(group, player, now)
assert(#spawned == 0, "no body appears in view")
floorSeen = false
H.pulse(group, player, now)
assert(#spawned == 1 and spawned[1].outfit == "Backpacker" and spawned[1].female == 100
        and spawned[1].killed == true and spawned[1].data.lfHitchhikerGroupId == group.id,
    "a walker in her clothes, put down out of sight")
now = now + 1000
H.pulse(group, player, now)
assert(group.oddball.stage == "gone_inside", "the body takes a moment")
deadBody = { container = { items = {} } }
H.pulse(group, player, now)
assert(group.oddball.stage == "waiting_to_be_found")
assert(math.abs(deadBody.deathTime - (hours - 216 * 0.66)) < 0.001,
    "aged by the sandbox's own rot clock, short of removal")
local letter = deadBody.container.items[1]
assert(letter and letter.kind == "Base.LetterHandwritten" and letter.name == "Ruth Ann's letter home"
        and letter.pages[1] == H.LETTER, "her letter home is on her")

-- Found: a companion says what everyone is thinking, and it ends.
player.x, player.y = 110, 52
fellow.x, fellow.y = 111, 52
H.pulse(group, player, now)
assert(group.oddball.stage == "waiting_to_be_found")
player.x = 106
fellow.x = 107
H.pulse(group, player, now)
assert(group.oddball.stage == "found" and contains("fellowFound", fellow.lastLine)
        and retiredReason == "found_home" and group.lifecycle == "destroyed")

-- Corpse removal off: no rot to borrow, so the body stays as it fell.
SandboxVars.HoursForCorpseRemoval = 0
local quiet = newGroup()
quiet.oddball.stage = "gone_inside"
quiet.oddball.bodyPlaced = true
quiet.oddball.home = { anchor = house.anchor, floor = { x = 104, y = 52, z = 0 } }
deadBody = { container = { items = {} } }
H.pulse(quiet, player, now)
assert(deadBody.deathTime == nil and quiet.oddball.stage == "waiting_to_be_found")
SandboxVars.HoursForCorpseRemoval = 216

-- The driver pulls away while she walks over: she gives up and walks off.
H._resetForTests()
hibernated, retiredReason = false, nil
visibleRuth = true
ruth.x, ruth.y, ruth.vehicle = 0, 0, nil
group = newGroup()
player.x, player.y = 6, 0
player.vehicle, car.driver, car.stationary, car.x, car.y = car, player, true, 6, 0
H.pulse(group, player, now)
assert(group.oddball.stage == "boarding")
player.vehicle = nil
tick()
assert(group.oddball.stage == "walking_off" and said() == LINES.walkOff[1])
assert(tick() and routes[#routes].action == "faction_retreat")
visibleRuth = false
H.pulse(group, player, now)
now = now + 2100
H.pulse(group, player, now)
assert(hibernated and retiredReason == "walked_off" and group.lifecycle == "destroyed")

-- No house in reach at pickup: she rides on and names it when one loads.
H._resetForTests()
hibernated, retiredReason = false, nil
visibleRuth = true
ruth.x, ruth.y, ruth.vehicle = 5, 2, nil
houseFound = false
group = newGroup()
player.vehicle, car.driver, car.stationary, car.x, car.y = car, player, true, 6, 0
H.pulse(group, player, now)
tick()
assert(group.oddball.stage == "riding" and group.oddball.home == nil, "she gets in anyway")
houseFound = true
now = now + 31000
H.pulse(group, player, now)
assert(group.oddball.home and said() == "It's 27 Locust Street. I'll show you.")

-- Taking too long to stop for her ends it.
H._resetForTests()
group = newGroup()
ruth.x, ruth.y, ruth.vehicle = 0, 0, nil
car.x, car.stationary = 6, true
H.pulse(group, player, now)
now = now + 61000
car.stationary = false
tick()
assert(group.oddball.stage == "walking_off", "a minute is long enough to wait")
assert(select(1, H.canRecruit()) == false and H.avoidsZombieCombat() == true)

print("Hitchhiker PASS: ghost shelter, thumbing, stopped-car pickup, real boarding, address, ride lines, arrival, unseen exit, hidden body, rot within removal, letter, found")
