-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local camera = { id = "skeeter", x = 0, y = 0, z = 0,
    inv = { items = {} } }
local player = { id = "player", x = 2, y = 0, z = 0,
    inv = { items = {} } }
local pan = { kind = "Base.Pan" }
local golf = { kind = "Base.Golfclub" }
local weapon = pan
local group = { id = "camera", standing = "Wary",
    members = { { actorId = "skeeter" } },
    oddball = { id = "cameraman_skeeter_bowles", stage = "pitch" } }
SC.Registry = { byId = function(id)
    return id == "skeeter" and { actor = camera } or nil
end }
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b) return math.abs(a.x - b.x) end,
    canSee = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    squareOf = function(value) return value end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(value, method, ...)
        if method == "getContainer" then return value.container, true end
        if method == "getPrimaryHandItem" then
            return value == player and weapon or nil, true
        end
        if method == "setName" then value.name = (...) end
        return true, true
    end,
    transferItemVerified = function(source, destination, item)
        for index, existing in ipairs(source.items) do
            if existing == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
}
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
local Skeeter = SC.OddballSkeeter
assert(Skeeter.onSpawn(group, camera))
assert(camera.inv.items[1].kind == "Base.Camera")
assert(camera.inv.items[2].kind == "Base.VHS_Home")
assert(Skeeter.action(group, "accept_pan", player))
for index = 1, 3 do
    local zombie = { x = 2, y = 1, z = 0 }
    assert(Skeeter.onZombieDead(group, zombie, player, player))
    assert(not Skeeter.onZombieDead(group, zombie, player, player),
        "same zombie death never double-counts")
end
assert(group.oddball.stage == "prize_ready")
assert(Skeeter.action(group, "claim_prize", player))
assert(#player.inv.items == 2 and player.inv.items[1].kind == "Base.VHS_Home")
group.oddball.stage = "pitch"
assert(Skeeter.action(group, "accept_golf", player))
weapon = golf
assert(Skeeter.onZombieDead(group, {}, player, player))
assert(group.oddball.stage == "prize_ready")
print("Skeeter PASS: verified weapon kills, dedupe, exact tape prize")
