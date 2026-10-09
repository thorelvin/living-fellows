-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local hour = 24
local player = { id = "player", x = 0, y = 0, z = 0 }
local corey = { id = "corey", x = 15, y = 0, z = 0,
    inv = { items = {} } }
local group = { id = "corey-group", standing = "Neutral",
    members = { { actorId = "corey" } }, oddball = {
        id = "fan_corey_biggs", stage = "unmet",
        initialTale = "the Battle of the Gas Station",
        site = { kind = "roamer", spawn = { x = 15, y = 0, z = 0 } } } }
local zombie = { id = "zombie", square = {
    room = { name = "gasstation" } } }
local navigationCount = 0
local hibernated = false
local visible = true
SC.GameplayUtil = {
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    canSee = function() return visible end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    addItem = function(inv, kind)
        local item = { kind = kind, data = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(item) return item.data end,
    squareOf = function(value) return { x = value.x, y = value.y, z = value.z } end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    say = function(value, line) value.lastLine = line return true end,
    call = function(value, method, ...)
        if method == "getWorldAgeHours" then return hour, true end
        if method == "getSquare" then return value.square, true end
        if method == "getRoom" then return value.room, true end
        if method == "getName" then return value.name, true end
        if method == "setName" then value.name = (...) return true, true end
        return nil, false
    end,
}
SC.Tales = { title = function(tale)
    assert(tale.place == "gasstation")
    return "the Battle of the Gas Station"
end }
SC.Registry = { byId = function(id)
    return id == "corey" and not hibernated and { actor = corey } or nil
end }
SC.Navigation = { request = function(actor, square, gait, options)
    assert(actor == corey and gait == "walk")
    navigationCount = navigationCount + 1
    return true, "moving"
end }
SC.Factions = { hibernateOddballRoamer = function(id)
    assert(id == group.id)
    hibernated = true
    return true
end, forceStanding = function() return true end }
SC.Oddballs = { retire = function(value, reason)
    assert(value == group and reason == "gave_up")
    return true
end }
getGameTime = function() return {} end

local Corey = SC.OddballCorey
assert(Corey.onSpawn(group, corey))
assert(corey.inv.items[1].kind == "Base.Notebook")
assert(corey.inv.items[1].data.lfCoreyTales[1]
    == "the Battle of the Gas Station")
assert(Corey.pulse(group, player))
assert(group.discovered == true)
assert(Corey.noteKill(group, player, zombie))
assert(#group.oddball.tales == 2)
local intent = Corey.intentFor(corey, player, {}, group)
assert(Corey.update(corey, player, {}, intent))
assert(navigationCount == 0, "15 tiles is the trailing hold distance")
corey.x = 20
assert(Corey.update(corey, player, {}, intent))
assert(navigationCount == 1)
player.x = 150
visible = false
assert(Corey.pulse(group, player))
hour = 24 * 5
assert(Corey.pulse(group, player))
assert(group.lifecycle == "destroyed" and hibernated)
print("Corey PASS: real tale, physical diary, wide trailing distance, three-day departure")
