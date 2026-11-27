-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local U, Shelter = SC.GameplayUtil, SC.OddballEvacuationShelter
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local map, players, zombies, factions
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
function U.gridSquare(x, y, z) return map[key(x, y, z or 0)] end
function U.isClearActorSpawnSquare(square) return square ~= nil and not square.occupied end
function U.canSee(viewer, target) return target.visible == viewer end
function getPlayer() return players[1] end
function getNumActivePlayers() return #players end
function getSpecificPlayer(index) return players[index + 1] end
function U.cell()
    return { getZombieList = function() return zombies end }
end

local function square(x, y, z, room, building)
    local tile = { x = x, y = y, z = z, room = room, building = building,
        objects = {}, special = {}, visibleTo = {} }
    function tile:getRoom() return self.room end
    function tile:getBuilding() return self.building end
    function tile:isOutside() return self.building == nil end
    function tile:isCanSee(index) return self.visibleTo[index] == true end
    function tile:getObjects() return self.objects end
    function tile:getSpecialObjects() return self.special end
    map[key(x, y, z)] = tile
    return tile
end

local function door(owner, outside, health, open)
    local object = { __class = "IsoDoor", square = owner, health = health,
        open = open == true, locked = false, mods = {} }
    function object:getModData() return self.mods end
    function object:getObjectIndex()
        for index, candidate in ipairs(owner.objects) do
            if candidate == self then return index - 1 end
        end
        return -1
    end
    function object:getNorth() return true end
    function object:getHealth() return self.health end
    function object:setHealth(value) self.health = value end
    function object:IsOpen() return self.open end
    function object:ToggleDoorSilent() self.open = not self.open end
    function object:isLocked() return self.locked end
    function object:setLocked(value) self.locked = value end
    owner.objects[#owner.objects + 1] = object
    owner.special[#owner.special + 1] = object
    owner.edge, outside.edge = { [outside] = object }, { [owner] = object }
    return object
end

local function person(tile, index)
    local actor = { x = tile.x, y = tile.y, z = tile.z, square = tile }
    function actor:getPlayerNum() return index end
    return actor
end

local function zombie(tile)
    local walker = { __class = "IsoZombie", square = tile, mods = {} }
    function walker:getModData() return self.mods end
    function walker:getTarget() return self.target end
    function walker:getThumpTarget() return self.thump end
    function walker:removeFromWorld() self.removed = true end
    function walker:removeFromSquare() self.square = nil end
    zombies[#zombies + 1] = walker
    return walker
end

SC.Factions = {
    group = function(id) return factions[id] end,
    atPosition = function(position)
        if position.x == 108 then return factions.other end
    end,
}
SC.Topology = {
    objectLocked = function(object) return object.locked end,
    objectBarricaded = function() return false end,
    squareHasStairs = function() return false end,
    barrierBetween = function(a, b)
        local opening = a.edge and a.edge[b]
        if opening then return opening, "door" end
        if b.breach then return nil, "open" end
        return nil, "blocked"
    end,
    reachableEscapeSquares = function(actor, origin)
        -- Only a real actor may take the native door route from the inside.
        return actor and origin.nodes or {}
    end,
}

local function scene()
    map, players, zombies = {}, {}, {}
    factions = { other = { id = "other" } }
    local building, hall = {}, {}
    local room = { getName = function() return "bedroom" end }
    for x = 99, 106 do
        for y = 99, 104 do square(x, y, 0) end
    end
    local joy = square(101, 101, 0, room, building)
    local brock = square(102, 101, 0, room, building)
    local exit = square(101, 100, 0, hall, building)
    local insideDoor = door(joy, exit, 310)
    local exterior = door(square(104, 100, 0, hall, building), map[key(104, 99, 0)], 400, true)
    local corner = square(103, 100, 0, hall, building)
    local seenExterior = door(corner, map[key(103, 99, 0)], 290, true)
    corner.visibleTo[1] = true
    joy.nodes = { { square = brock, parent = { square = joy }, via = { affordance = "open" } } }
    exit.nodes = { { square = map[key(104, 99, 0)], parent = { square = exit }, via = { affordance = "door" } } }
    local house = { bounds = { x1 = 100, y1 = 100, x2 = 105, y2 = 103 },
        interior = { { x = joy.x, y = joy.y, z = 0 }, { x = brock.x, y = brock.y, z = 0 } },
        anchor = { x = joy.x, y = joy.y, z = 0 },
        openings = { { x = 104, y = 100, z = 0, objectIndex = 0, kind = "door" },
            { x = 103, y = 100, z = 0, objectIndex = 0, kind = "door" } } }
    players[1] = person(square(78, 101, 0), 0)
    players[2] = person(square(79, 101, 0), 1)
    local site = Shelter.siteFor(house, players[1], false)
    check(site and site.spawn.x == 101 and site.memberSpawns[2].x == 102,
        "the posts belong to the same safe room and Joy stands behind its sole door")
    local group = { id = "evac", house = house, oddball = { id = "evacuation", site = site } }
    factions[group.id] = group
    return group, building, insideDoor, exterior, seenExterior
end

local group, building, inside, exterior, seenExterior = scene()
check(Shelter.acceptSite(group.oddball.site),
    "creation accepts the layout without asking a nil actor to open the exterior door")
map[key(101, 102, 0)].breach = true
check(not Shelter.acceptSite(group.oddball.site), "an open boundary cannot be a safe room")
map[key(101, 102, 0)].breach = false

local sameBuilding = zombie(square(103, 102, 1, {}, building))
local byFootprint = zombie(square(120, 100, 0))
local tooFar = zombie(square(121, 100, 0))
local anotherBuilding = zombie(square(103, 103, 1, {}, {}))
local seen = zombie(square(109, 100, 0))
seen.visible = players[1]
local visibleToSecond = zombie(square(110, 100, 0))
visibleToSecond.square.visibleTo[1] = true
local fighting = zombie(square(111, 100, 0))
fighting.target = players[2]
local thumping = zombie(square(112, 100, 0))
thumping.thump = exterior
local authored = zombie(square(113, 100, 0))
authored.mods.lfElmerWifeGroupId = "other"
local territory = zombie(square(108, 100, 0))
local corpseProxy = zombie(square(114, 100, 0))
function corpseProxy:isReanimatedForGrappleOnly() return true end

check(Shelter.prepareFirstSpawn(group, nil) == "pending" and not sameBuilding.removed,
    "scene preparation waits for a real observer")
local joyPost = inside.square
joyPost.visibleTo[1] = true
check(Shelter.prepareFirstSpawn(group, players[1]) == "failed" and not sameBuilding.removed,
    "a second observer seeing a spawn post prevents all scene mutation")
joyPost.visibleTo[1] = false
check(Shelter.prepareFirstSpawn(group, players[1]) == "ready" and group.oddball.sceneSecured,
    "initial clearing records one completed preparation")
check(sameBuilding.removed and byFootprint.removed and not tooFar.removed and not anotherBuilding.removed,
    "clear loaded upper floor and outside within fifteen metres of the footprint")
check(not seen.removed and not visibleToSecond.removed and not fighting.removed
    and not thumping.removed and not authored.removed and not territory.removed and not corpseProxy.removed,
    "open fights, both viewers, authored sites, and corpse proxies survive preparation")
local later = zombie(map[key(114, 100, 0)])
check(Shelter.prepareFirstSpawn(group, players[1]) == "ready" and not later.removed,
    "later arrivals never get cleared again")

check(Shelter.onJoySpawn(group) and inside.locked and inside.health > 310
    and not exterior.open and exterior.health > 400 and seenExterior.open and seenExterior.health == 290,
    "Joy locks the room and quiet exterior doors gain reserve without closing a visible door")
local warmHealth = inside.health
inside.health = 330
check(not Shelter.pulse(group, players[1]) and inside.health == warmHealth and thumping.thump == exterior,
    "far-away native thumps use door reserve without changing a zombie's target")
local wrongFloor = person(square(100, 101, 1), 0)
check(not Shelter.pulse(group, wrongFloor) and inside.health == warmHealth and inside.locked,
    "an upstairs observer does not release the ground-floor shelter")
local near = person(square(90, 101, 0), 0)
check(not Shelter.pulse(group, near) and inside.health == 310 and exterior.health == 400 and inside.locked,
    "near approach restores exact door health while the safe-room lock remains")
inside.health = 280
check(not Shelter.pulse(group, near) and inside.health == 280,
    "native damage after protection releases survives subsequent pulses")
local reached = person(square(99, 101, 0), 0)
table.insert(inside.square.objects, 1, {})
check(Shelter.pulse(group, reached) and not inside.locked and inside.health == 280,
    "close approach unlocks the marked original despite a shifted object index")

local removedGroup, _, protected, otherDoor = scene()
check(Shelter.prepareFirstSpawn(removedGroup, players[1]) == "ready" and Shelter.onJoySpawn(removedGroup),
    "reload fixture owns both doors")
local removedSquare = protected.square
map[U.squareKey(removedSquare)] = nil
check(Shelter.release(removedGroup) and otherDoor.health == 400 and protected.locked,
    "terminal cleanup restores loaded doors and defers a streamed-out door")
local restored = { id = removedGroup.id, house = removedGroup.house, oddball = removedGroup.oddball }
SC.State.active = false
Shelter.onSquareLoaded(removedSquare)
check(protected.locked and protected.health > 310,
    "marked doors are not reconciled against an unrestored faction store")
factions[removedGroup.id] = restored
SC.State.active = true
Shelter.reconcileLoaded()
check(not protected.locked and protected.health == 310 and protected.mods.LF_EvacuationDoor == nil,
    "reconciling after persistence restores both native values and removes the marker")

SC_TEST_REPORT = "Evacuation shelter PASS: " .. checks .. " checks"
