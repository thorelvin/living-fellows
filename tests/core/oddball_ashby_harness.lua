-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour = 200
local squares, actors = {}, {}
local function square(x, y, z)
    local key = x .. ":" .. y .. ":" .. z
    squares[key] = squares[key] or { x = x, y = y, z = z, bodies = {} }
    return squares[key]
end
local function actor(id, x)
    local value = { id = id, x = x, y = 0, z = 0,
        inv = { items = {} }, medical = { bites = 0, knoxInfected = false } }
    actors[id] = value
    return value
end
local doctor, player, fellow = actor("doctor", 0), actor("player", 1),
    actor("fellow", 1)
local group = { id = "ashby-test", standing = "Neutral",
    members = { { actorId = "doctor" } }, oddball = {
        id = "doctor_vernon_ashby", stage = "unmet",
        site = { spawn = { x = 0, y = 0, z = 0 } } } }

SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return true end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = square,
    squareStaticMovingObjects = function(sq, callback)
        for _, body in ipairs(sq.bodies) do callback(body) end
    end,
    instanceOf = function(value, name)
        return name == "IsoDeadBody" and value.corpse == true
    end,
    modData = function(value) return value.data end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind, inv = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    transferItemVerified = function(source, destination, item)
        for index, current in ipairs(source.items) do
            if current == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.inv = destination
                return true
            end
        end
        return false
    end,
    say = function(value, line) value.lastLine = line return true end,
    call = function(value, name, ...)
        if not value then return nil, false end
        if name == "getWorldAgeHours" then return hour, true end
        if name == "getPrimaryHandItem" then return value.primary, true end
        if name == "setPrimaryHandItem" then value.primary = (...) return true, true end
        if name == "setName" then value.name = (...) return true, true end
        if name == "isZombie" then return value.zombie, true end
        if name == "isAnimal" then return value.animal, true end
        if name == "isFakeDead" then return value.fake, true end
        if name == "getDeathTime" then return value.deathTime, true end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id)
        return actors[id] and { id = id, actor = actors[id],
            recruited = id == "fellow" }
    end,
    living = function() return { fellow } end,
}
SC.Medical = { assess = function(value) return value.medical end }
SC.Factions = { forceStanding = function(id, standing)
    group.standing = standing
    return true
end }
local stayed
SC.Commands = { issue = function(id, command)
    stayed = id == "fellow" and command == "stay"
    return stayed
end }
getGameTime = function() return {} end

local Ashby = SC.OddballAshby
assert(Ashby.onSpawn(group, doctor))
assert(#doctor.inv.items == 4, "the doctor must hold one real stock set")
assert(Ashby.onSpawn(group, doctor))
assert(#doctor.inv.items == 4, "re-spawn must not duplicate stock")
local bin = square(2, 0, 0)
local function corpse(zombie, deathTime, animal)
    local value = { corpse = true, zombie = zombie, animal = animal,
        fake = false, deathTime = deathTime, data = {} }
    bin.bodies[#bin.bodies + 1] = value
    return value
end
corpse(false, 199, false)
corpse(true, 10, false)
corpse(true, 199, true)
assert(not Ashby.action(group, "deliver_specimen", player),
    "human, stale and animal corpses are not eligible")
local fresh = { corpse(true, 199, false), corpse(true, 199, false),
    corpse(true, 199, false) }
for count = 1, 3 do
    assert(Ashby.action(group, "deliver_specimen", player))
    assert(group.oddball.specimens == count)
    assert(fresh[count].data.lfAshbyAcceptedId == group.id)
end
assert(not Ashby.action(group, "deliver_specimen", player),
    "the same bodies must not earn another payment")
assert(Ashby.action(group, "claim_medicine", player))
assert(group.oddball.rewardClaimed == true)
assert(player.inv.items[1].kind == "Base.Antibiotics")
assert(player.inv.items[2].kind == "Base.Pills")
assert(not Ashby.action(group, "claim_medicine", player))
assert(Ashby.action(group, "take_vaccine", player))
assert(player.inv.items[3].kind == "Base.PillsVitamins")
assert(not Ashby.action(group, "take_vaccine", player))
fellow.medical.knoxInfected = true
assert(Ashby.action(group, "refuse_study", player))
assert(Ashby.action(group, "leave_for_study", player))
assert(stayed == true and group.oddball.studyActorId == "fellow")
print("Ashby PASS: fresh specimens, distinct bodies, exact medicine, trial vitamins, study choice")
