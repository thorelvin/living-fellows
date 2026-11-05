-- SPDX-License-Identifier: MIT
-- Ruth Ann Sizemore thumbs a ride at dusk. When the player stops a car beside
-- her she really boards a passenger seat (SC.Vehicle.board), gives a real
-- address and rides along. At the house she gets out, walks inside and, once
-- nobody is watching, is gone through roamer hibernation. Inside, a body in
-- her clothes lies on the floor, a real corpse aged by the sandbox's own
-- rot clock, with her letter home on it. Nobody can explain it. Nobody tries.

local SC = SurvivorCompanion
SC.OddballHitchhiker = SC.OddballHitchhiker or {}
local Hitchhiker = SC.OddballHitchhiker

local ID = "hitchhiker_ruth_ann"
local OUTFIT = "Backpacker"
local THUMB_DISTANCE = 30
local TALK_DISTANCE = 10
local PICKUP_DISTANCE = 10
local ARRIVAL_DISTANCE = 18
local THUMB_MS = 15000
local RIDE_LINE_MS = 30000
local BOARD_TIMEOUT_MS = 60000
local UNSEEN_MS = 2000
local CORPSE_SEARCH_MS = 60000
local FOUND_DISTANCE = 4
-- Rot only runs while corpse removal is on, and a body older than the
-- removal age is deleted. Two thirds of it reads as long dead and stays.
local ROT_FRACTION = 0.66

local LINES = {
    thumb = {
        "Evening. You wouldn't have a car, would you?",
        "Just need a ride home. It's not far.",
        "I don't hitch, usually. Mama says it's how girls disappear.",
    },
    board = { "Oh, thank you. Thank you. I've been out here a while." },
    directions = { "It's %s. I'll show you." },
    ride = {
        "Mama's going to be so mad I'm late.",
        "Funny. I don't remember the road being this quiet.",
        "Do you smell that? Never mind.",
        "I've been trying to get home for a while now.",
        "You're the first one who stopped. Everybody else just drove through me.",
        "Is it cold in here, or is it me?",
        "I used to wave at every car. Now I just stand there.",
    },
    arrive = { "This is me. Thank you. Don't come in. It's a mess." },
    walkOff = { "Never mind. I'll walk. I always do." },
    fellowRide = { "Anybody else notice she doesn't blink?" },
    fellowFound = {
        "We all saw her get in the car. Right?",
        "Nobody says anything. Nobody says anything about this.",
    },
}
Hitchhiker.LINES = LINES
Hitchhiker.LETTER = "Mama, I'm coming home Thursday. Don't wait up. I'll find my way. Ruth Ann."

local runtimeByGroup = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function call(object, method, ...)
    return object and select(1, U().call(object, method, ...)) or nil
end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "thumbing" end
    value.lines = type(value.lines) == "table" and value.lines or {}
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    local actor = record and record.actor
    return actor and U().isValidActor(actor) and not U().isDead(actor) and actor or nil
end

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = number(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return list[index]
end

local function runtimeFor(group)
    local entry = runtimeByGroup[group]
    if not entry then
        entry = {}
        runtimeByGroup[group] = entry
    end
    return entry
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    return number((U().call(time, "getWorldAgeHours")))
end

local function fellowLine(group, player, value, pool, flag)
    if value[flag] == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local ruth = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= ruth and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, pool))
                value[flag] = true
                return true
            end
        end
    end
    return false
end

local function playerCar(player)
    local car = call(player, "getVehicle")
    if not car then return nil end
    if call(car, "getDriver") ~= player then return nil end
    return car
end

local function roomOf(square)
    local room = call(square, "getRoom")
    local name = room and call(room, "getName")
    return type(name) == "string" and string.lower(name) or nil
end

-- Her house: a real, unclaimed house in loaded range, with a floor tile
-- for what waits inside (a bedroom when there is one).
local function chooseHome(player, value)
    if not SC.Factions or type(SC.Factions.findHouse) ~= "function" then return nil end
    local house = SC.Factions.findHouse(player, { purpose = "oddball",
        minimumDistance = 60, maximumDistance = 160, sampleBudget = 48 })
    if not house or type(house.interior) ~= "table" or #house.interior == 0 then return nil end
    local floor, fallback
    for index = 1, math.min(#house.interior, 256) do
        local position = house.interior[index]
        local square = U().gridSquare(position.x, position.y, position.z or 0)
        if square and U().isSafeSpawnSquare(square) then
            fallback = fallback or position
            if roomOf(square) == "bedroom" then floor = position break end
        end
    end
    floor = floor or fallback
    if not floor then return nil end
    local location = SC.Factions.describeLocation and SC.Factions.describeLocation(house.anchor)
    value.home = { anchor = { x = house.anchor.x, y = house.anchor.y, z = house.anchor.z or 0 },
        entry = house.primaryEntry and { x = house.primaryEntry.x, y = house.primaryEntry.y,
            z = house.primaryEntry.z or 0 } or nil,
        floor = { x = floor.x, y = floor.y, z = floor.z or 0 },
        address = location and location.address
            or (tostring(house.anchor.x) .. ", " .. tostring(house.anchor.y)) }
    return value.home
end

local function navigate(actor, point, gait, action)
    local square = point and U().gridSquare(point.x, point.y, point.z or 0)
    if not square or not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "hitchhiker_route_unavailable"
    end
    return SC.Navigation.request(actor, square, gait or "walk", {
        action = action or "faction_home", arrivalDistance = 1.2 })
end

local function departUnseen(group, value, player, current, nextStage)
    local actor = actorFor(group)
    if actor and player and U().canSee(player, actor) == true then
        value.unseenSince = nil
        return false
    end
    value.unseenSince = number(value.unseenSince) or current
    if current - value.unseenSince < UNSEEN_MS then return false end
    local member = group.members and group.members[1]
    local gone = member and member.hibernated == true
    if not gone and SC.Factions and type(SC.Factions.hibernateOddballRoamer) == "function" then
        gone = SC.Factions.hibernateOddballRoamer(group.id, player) == true
    end
    if gone then
        value.stage = nextStage
        value.unseenSince = nil
    end
    return gone
end

-- A walker in her clothes, put down out of sight, leaves the real body.
local function leaveBody(group, value, player)
    local floor = value.home and value.home.floor
    local square = floor and U().gridSquare(floor.x, floor.y, floor.z or 0)
    if not square or type(addZombiesInOutfit) ~= "function" or not SC.NativeList then
        return false
    end
    local index = call(player, "getPlayerNum")
    if number(index) and call(square, "isCanSee", math.floor(number(index))) == true then
        return false
    end
    local okay, list = pcall(addZombiesInOutfit, floor.x, floor.y, floor.z or 0, 1, OUTFIT, 100)
    local zombie = okay and list and SC.NativeList.get(list, 0) or nil
    if not zombie then return false end
    local data = U().modData(zombie)
    if data then data.lfHitchhikerGroupId = group.id end
    U().call(zombie, "Kill", nil)
    value.bodyPlaced = true
    return true
end

local function findBody(value)
    local floor = value.home and value.home.floor
    if not floor then return nil end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = U().gridSquare(floor.x + dx, floor.y + dy, floor.z or 0)
            local body = square and call(square, "getDeadBody")
            if body then return body end
        end
    end
    return nil
end

local function ageBody(value, body)
    local removal = type(SandboxVars) == "table" and number(SandboxVars.HoursForCorpseRemoval) or nil
    local hours = worldHours()
    if removal and removal > 0 and hours then
        U().call(body, "setDeathTime", hours - removal * ROT_FRACTION)
    end
    local container = call(body, "getContainer")
    local letter = container and U().addItem(container, "Base.LetterHandwritten")
    if letter then
        U().call(letter, "setName", "Ruth Ann's letter home")
        U().call(letter, "addPage", 1, Hitchhiker.LETTER)
    end
    value.bodyReady = true
end

function Hitchhiker.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = number(current) or U().nowMs()
    local entry = runtimeFor(group)
    local actor = actorFor(group)
    -- The dead never notice her. It is the first thing anyone should wonder about.
    if actor and SC.Oddballs and type(SC.Oddballs.setZombieShelter) == "function"
        and select(1, U().call(actor, "isZombiesDontAttack")) ~= true then
        SC.Oddballs.setZombieShelter(actor, true)
    end
    if value.stage == "thumbing" then
        if not actor or not player then return true, "ruth_unloaded" end
        local distance = U().distance(actor, player)
        if distance <= THUMB_DISTANCE and U().canSee(player, actor) == true
            and current >= (number(entry.nextThumbAt) or 0) then
            entry.nextThumbAt = current + THUMB_MS
            group.discovered = true
            if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
                SC.Relationship.playEmote(actor, "thumbsup")
            end
            if distance <= TALK_DISTANCE and not playerCar(player) then
                U().say(actor, nextLine(value, "thumb"))
            end
        end
        local car = playerCar(player)
        if car and distance <= PICKUP_DISTANCE and SC.Vehicle
            and SC.Vehicle.isStationary and SC.Vehicle.isStationary(car) == true then
            value.stage = "boarding"
            value.boardingSince = current
            U().say(actor, LINES.board[1])
        end
        return true, value.stage
    elseif value.stage == "riding" then
        if actor and not value.home and current >= (number(entry.nextHomeSearchAt) or 0) then
            entry.nextHomeSearchAt = current + RIDE_LINE_MS
            local home = chooseHome(player, value)
            if home then
                U().say(actor, string.format(LINES.directions[1], home.address))
                if SC.FactionLife and type(SC.FactionLife.addMapAnnotation) == "function" then
                    SC.FactionLife.addMapAnnotation("[LF] Ruth Ann's house",
                        home.anchor.x, home.anchor.y, { 0.8, 0.8, 0.85, 1.0 })
                end
                return true, "ruth_gave_directions"
            end
        end
        if actor and current >= (number(entry.nextRideLineAt) or 0) then
            entry.nextRideLineAt = current + RIDE_LINE_MS
            U().say(actor, nextLine(value, "ride"))
            fellowLine(group, player, value, "fellowRide", "fellowSawRide")
        end
        local car = actor and call(actor, "getVehicle")
        local home = value.home and value.home.anchor
        if car and home and SC.Vehicle and SC.Vehicle.isStationary(car) == true then
            local x, y = U().position(car)
            if x and (x - home.x) ^ 2 + (y - home.y) ^ 2 <= ARRIVAL_DISTANCE ^ 2 then
                local exited = SC.Vehicle.exit(actor, car, value.seat)
                if exited == true then
                    value.stage = "walking_home"
                    U().say(actor, LINES.arrive[1])
                end
            end
        end
        return true, value.stage
    elseif value.stage == "walking_home" then
        departUnseen(group, value, player, current, "gone_inside")
        return true, value.stage
    elseif value.stage == "walking_off" then
        if departUnseen(group, value, player, current, "walked_off") then
            group.lifecycle = "destroyed"
            if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "walked_off")
            end
        end
        return true, value.stage
    elseif value.stage == "gone_inside" then
        if value.bodyPlaced ~= true then
            value.bodySince = number(value.bodySince) or current
            leaveBody(group, value, player)
            return true, "ruth_body_pending"
        end
        local body = findBody(value)
        if body then
            ageBody(value, body)
            value.stage = "waiting_to_be_found"
        elseif current - (number(value.bodySince) or current) > CORPSE_SEARCH_MS then
            value.stage = "waiting_to_be_found"
        end
        return true, value.stage
    elseif value.stage == "waiting_to_be_found" then
        local floor = value.home and value.home.floor
        if player and floor then
            local x, y, z = U().position(player)
            if x and math.floor(z or 0) == (floor.z or 0)
                and (x - floor.x) ^ 2 + (y - floor.y) ^ 2 <= FOUND_DISTANCE ^ 2 then
                fellowLine(group, player, value, "fellowFound", "fellowSawBody")
                value.stage = "found"
                group.lifecycle = "destroyed"
                if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                    SC.Oddballs.retire(group, "found_home")
                end
            end
        end
        return true, value.stage
    end
    return true, value.stage
end

function Hitchhiker.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "boarding" then return { mode = "ruth_boarding", priority = 60 } end
    if value.stage == "riding" then return { mode = "oddball_idle", priority = 28 } end
    if value.stage == "walking_home" then return { mode = "ruth_home", priority = 60 } end
    if value.stage == "walking_off" then return { mode = "ruth_walking_off", priority = 60 } end
    return { mode = "ruth_roadside", priority = 30 }
end

local function board(group, value, actor, player, current)
    local car = playerCar(player)
    if not car or current - (number(value.boardingSince) or current) > BOARD_TIMEOUT_MS
        or not SC.Vehicle or type(SC.Vehicle.board) ~= "function" then
        value.stage = "walking_off"
        U().say(actor, LINES.walkOff[1])
        return true, "ruth_gives_up_on_the_ride"
    end
    if SC.Vehicle.isStationary(car) ~= true then return true, "ruth_waiting_for_the_car_to_stop" end
    local square, seat = SC.Vehicle.boardingSquare(actor, car)
    if not square then
        value.stage = "walking_off"
        U().say(actor, LINES.walkOff[1])
        return true, "ruth_no_seat"
    end
    if U().distance(actor, square) > 1.2 then
        local x, y, z = U().position(square)
        return navigate(actor, { x = x, y = y, z = z }, "walk", "faction_follow")
    end
    local boarded = SC.Vehicle.board(actor, car, seat, { allowVirtualSeat = false })
    if boarded ~= true then return true, "ruth_board_retry" end
    value.stage = "riding"
    value.seat = seat
    local home = value.home or chooseHome(player, value)
    if home then
        U().say(actor, string.format(LINES.directions[1], home.address))
        if SC.FactionLife and type(SC.FactionLife.addMapAnnotation) == "function" then
            SC.FactionLife.addMapAnnotation("[LF] Ruth Ann's house",
                home.anchor.x, home.anchor.y, { 0.8, 0.8, 0.85, 1.0 })
        end
    end
    runtimeFor(group).nextRideLineAt = current + RIDE_LINE_MS
    return true, "ruth_boarded"
end

function Hitchhiker.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent then return false end
    local current = U().nowMs()
    if intent.mode == "ruth_boarding" then return board(group, value, actor, player, current) end
    if intent.mode == "ruth_home" then
        -- She goes all the way in, to the spot where she will be found.
        return navigate(actor, value.home and value.home.floor, "walk", "faction_home")
    end
    if intent.mode == "ruth_walking_off" then
        local x, y, z = U().position(actor)
        if not x then return true end
        return navigate(actor, { x = x + 20, y = y, z = z }, "walk", "faction_retreat")
    end
    if intent.mode == "ruth_roadside" then return true, "ruth_by_the_road" end
    return false
end

function Hitchhiker.canRecruit()
    return false, "ruth_ann_is_going_home"
end

function Hitchhiker.avoidsZombieCombat()
    return true
end

function Hitchhiker.zombiesIgnore(actor, group)
    return story(group) ~= nil
end

function Hitchhiker._resetForTests()
    runtimeByGroup = setmetatable({}, { __mode = "k" })
end

return Hitchhiker
