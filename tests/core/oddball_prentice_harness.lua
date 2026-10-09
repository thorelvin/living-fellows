-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour, visible, current = 100, true, 1000
local squares = {}
local function square(x, y, z)
    local key = x .. ":" .. y .. ":" .. z
    squares[key] = squares[key] or { x = x, y = y, z = z,
        worldObjects = {} }
    return squares[key]
end
local prentice = { id = "prentice", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local player = { id = "player", x = 1, y = 0, z = 0,
    inv = { items = {} } }
local group = { id = "prentice-group", standing = "Neutral",
    members = { { actorId = "prentice", hibernated = false } },
    oddball = { id = "dewey_prentice_hollowell", stage = "unmet",
        site = { kind = "roamer", spawn = { x = 0, y = 0, z = 0 },
            house = { id = "town1", anchor = { x = 2, y = 1, z = 0 },
                bounds = {} } } } }
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    canSee = function() return visible end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    gridSquare = square,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    modData = function(value)
        value.data = value.data or {}
        return value.data
    end,
    say = function(value, line) value.lastLine = line return true end,
    call = function(value, name, ...)
        if not value then return nil, false end
        if name == "getWorldAgeHours" then return hour, true end
        if name == "getWorldObjects" then return value.worldObjects, true end
        if name == "getItem" then return value.item, true end
        if name == "setName" then value.name = (...) return true, true end
        if name == "AddWorldInventoryItem" then
            local item = (...)
            local world = { item = item }
            value.worldObjects[#value.worldObjects + 1] = world
            return world, true
        end
        return nil, false
    end,
}
SC.NativeList = { size = function(value) return #value end,
    get = function(value, index) return value[index + 1] end }
SC.Registry = { byId = function(id)
    return id == "prentice" and not group.members[1].hibernated
        and { actor = prentice } or nil
end, living = function() return {} end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    group.members[1].hibernated = true
    group.oddball.site.wake = { x = prentice.x, y = prentice.y, z = 0 }
    return true
end, forceStanding = function() return true end }
local townSerial = 1
SC.Oddballs = { findRoamerLandmark = function()
    townSerial = townSerial + 1
    local x = (townSerial - 1) * 400
    return { spawn = { x = x, y = 0, z = 0 },
        house = { id = "town" .. townSerial,
            anchor = { x = x + 2, y = 1, z = 0 }, bounds = {} } }
end }
getGameTime = function() return {} end
instanceItem = function(kind)
    assert(kind == "Base.LetterHandwritten")
    return { kind = kind, data = {} }
end

local Prentice = SC.OddballPrentice
assert(Prentice.onSpawn(group, prentice))
for meeting = 1, 5 do
    visible = true
    assert(Prentice.pulse(group, player, current))
    assert(group.oddball.meetings == meeting)
    if meeting < 5 then
        visible = false
        current = current + 1000
        Prentice.pulse(group, player, current)
        current = current + 61000
        assert(Prentice.pulse(group, player, current))
        assert(group.members[1].hibernated == true)
        hour = hour + 48
        current = current + 1000
        assert(Prentice.pulse(group, player, current))
        assert(group.oddball.site.wake.x == meeting * 400)
        group.members[1].hibernated = false
        prentice.x = meeting * 400
        player.x = prentice.x + 1
        assert(Prentice.onSpawn(group, prentice))
        current = current + 1000
    end
end
assert(group.oddball.notePlaced == true)
local notePoint = group.oddball.site.house.anchor
local world = square(notePoint.x, notePoint.y, 0).worldObjects
assert(#world == 1 and world[1].item.data.lfDeweyGroupId == group.id)
assert(Prentice.action(group, "lie", player))
assert(group.oddball.stage == "searching")
player.inv.items[1] = world[1].item
assert(Prentice.action(group, "tell_truth", player))
assert(Prentice.canRecruit(group))
Prentice.pulse(group, player, current + 1000)
assert(#world == 1, "the real note must not duplicate")
print("Prentice PASS: five distant meetings, contradictory clues, one note, truth or lie")
