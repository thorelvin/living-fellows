-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local function actor(id, x, y)
    return { id = id, x = x, y = y or 0, z = 0, inv = { items = {} } }
end
local dorothy, evelyn, opal, player = actor("dorothy", 0),
    actor("evelyn", 2), actor("opal", 0, 2), actor("player", 2)
local actors = { dorothy = dorothy, evelyn = evelyn, opal = opal }
local clock = 1000
local squares = {}
local function square(x, y, objects)
    local value = { x = x, y = y, z = 0, objects = objects or {} }
    squares[x .. ":" .. y] = value
    return value
end
local function fixture(kind)
    return { container = { kind = kind } }
end
square(0, 0)
square(2, 0)
square(0, 2)
square(0, -1, { fixture("counter") })
square(3, 0, { fixture("stove") })
square(-1, 2, { fixture("counter") })
local group = { id = "auxiliary", standing = "Wary", members = {
    { actorId = "dorothy", alive = true },
    { actorId = "evelyn", alive = true },
    { actorId = "opal", alive = true } },
    oddball = { id = "rosewood_auxiliary", stage = "unmet",
        site = { memberSpawns = {
            { x = 0, y = 0, z = 0 }, { x = 2, y = 0, z = 0 },
            { x = 0, y = 2, z = 0 } } } } }
local requested = {}
SC.Registry = { byId = function(id)
    return actors[id] and { actor = actors[id] } or nil
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    group.standing = standing
    return true
end }
SC.FactionRecruitment = {
    summary = function() return { status = "available" } end,
    ask = function() requested[#requested + 1] = "ask" return true end,
    startTrial = function() requested[#requested + 1] = "trial" return true end,
}
SC.GameplayUtil = {
    isValidActor = function(value) return value ~= nil end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    arrived = function(value, target, options)
        assert(options.targetKind == "square")
        local dx = value.x - (target.x + 0.5)
        local dy = value.y - (target.y + 0.5)
        return math.sqrt(dx * dx + dy * dy) <= options.distance
    end,
    nowMs = function() return clock end,
    gridSquare = function(x, y) return squares[x .. ":" .. y] end,
    squareObjects = function(value, callback)
        for _, object in ipairs(value.objects or {}) do callback(object) end
    end,
    instanceOf = function() return false end,
    idOf = function(value) return value.id end,
    stop = function(value) value.stops = (value.stops or 0) + 1; return true end,
    move = function(value, mode, intent)
        value.lastMove = { mode = mode, action = intent.action }
        value.visual = "active"
        return true, "visual_started"
    end,
    canSee = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    modData = function(item)
        item.data = item.data or {}
        return item.data
    end,
    addItem = function(inv, kind)
        local item = { kind = kind, container = inv }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(value, method, x, y)
        if method == "getContainer" then return value.container, true end
        if method == "getType" then return value.kind, true end
        if method == "isFavorite" then return false, true end
        if method == "getWornItem" then return value.wornHat, true end
        if method == "setWornItem" then
            assert(x == "Hat")
            value.wornHat = y
            return true, true
        end
        if method == "faceLocationF" then
            value.facing = { x = x, y = y }
            return true, true
        end
        return true, true
    end,
    transferItemVerified = function(source, destination, item)
        for index, current in ipairs(source.items) do
            if current == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false
    end,
}
SC.NativeActions = {
    visualStatus = function(value, expected)
        if value.visualAction and value.visualAction ~= expected then
            return "different"
        end
        return value.visual or "none"
    end,
    clearVisual = function(value)
        value.visual = nil
        value.visualAction = nil
    end,
}
SC.Navigation = { request = function(value, target, mode, intent)
    value.lastNavigation = { target = target, mode = mode, action = intent.action }
    return true, "navigation_requested"
end }
local Auxiliary = SC.OddballAuxiliary
local outfitHat = SC.GameplayUtil.addItem(evelyn.inv,
    "Base.Hat_BaseballCap")
evelyn.wornHat = outfitHat
assert(Auxiliary.onSpawn(group, dorothy))
assert(Auxiliary.onSpawn(group, evelyn))
assert(Auxiliary.onSpawn(group, opal))
local function countKind(value, kind)
    local total = 0
    for _, item in ipairs(value.inv.items) do
        if item.kind == kind then total = total + 1 end
    end
    return total
end
assert(countKind(dorothy, "Base.RollingPin") == 1)
assert(countKind(evelyn, "Base.Pan") == 1)
assert(countKind(dorothy, "Base.Flour2") == 1
    and countKind(dorothy, "Base.Sugar") == 1)
assert(countKind(evelyn, "Base.Egg") == 2
    and countKind(evelyn, "Base.Butter") == 1
    and countKind(evelyn, "Base.Hat_ChefHat") == 1
    and evelyn.wornHat.kind == "Base.Hat_ChefHat"
    and countKind(evelyn, "Base.Hat_BaseballCap") == 1,
    "chef hat replaces the outfit hat without destroying it")
assert(countKind(opal, "Base.Milk") == 1
    and countKind(opal, "Base.Yeast") == 1
    and countKind(opal, "Base.Salt") == 1)
local rewardCount = #dorothy.inv.items
assert(Auxiliary.onSpawn(group, dorothy)
    and Auxiliary.onSpawn(group, evelyn)
    and Auxiliary.onSpawn(group, opal))
assert(#dorothy.inv.items == rewardCount
    and countKind(evelyn, "Base.Egg") == 2
    and countKind(evelyn, "Base.Hat_ChefHat") == 1,
    "reviving a saved trio must not duplicate stock, props, or chef hat")
local giftedHat = SC.GameplayUtil.addItem(evelyn.inv, "Base.Hat_BaseballCap")
SC.GameplayUtil.modData(giftedHat).SC_ManualWearFor = evelyn.id
evelyn.wornHat = giftedHat
group.oddball.chefHatSeeded = nil
assert(Auxiliary.onSpawn(group, evelyn))
assert(evelyn.wornHat == giftedHat
    and countKind(evelyn, "Base.Hat_ChefHat") == 1,
    "a player-chosen hat remains worn")
assert(dorothy.facing.y < dorothy.y and evelyn.facing.x > evelyn.x
    and opal.facing.x < opal.x,
    "kitchen workers should initially face distinct work surfaces")
local northCounter = squares["0:-1"].objects
local eastStove = squares["3:0"].objects
local westCounter = squares["-1:2"].objects
squares["0:-1"].objects, squares["3:0"].objects,
    squares["-1:2"].objects = {}, {}, {}
assert(Auxiliary.onSpawn(group, dorothy)
    and Auxiliary.onSpawn(group, evelyn)
    and Auxiliary.onSpawn(group, opal))
assert(dorothy.facing.x > dorothy.x and evelyn.facing.x < evelyn.x
    and opal.facing.y < opal.y,
    "unfurnished kitchen still gives the trio different facing")
squares["0:-1"].objects, squares["3:0"].objects,
    squares["-1:2"].objects = northCounter, eastStove, westCounter
assert(Auxiliary.onSpawn(group, dorothy)
    and Auxiliary.onSpawn(group, evelyn)
    and Auxiliary.onSpawn(group, opal))
local kitchenIntent = Auxiliary.intentFor(dorothy, player, {}, group)
assert(kitchenIntent.mode == "auxiliary_kitchen")
assert(Auxiliary.update(dorothy, player, {}, kitchenIntent, group))
assert(dorothy.lastMove.action == "loot_container")
assert(Auxiliary.update(evelyn, player, {}, kitchenIntent, group))
assert(evelyn.lastMove == nil, "baker's preparation should be staggered")
clock = clock + 5500
assert(Auxiliary.update(evelyn, player, {}, kitchenIntent, group))
assert(evelyn.lastMove.action == "craft_supply")
assert(Auxiliary.update(dorothy, player, {}, kitchenIntent, group))
assert(dorothy.lastMove.action == "loot_container"
    and dorothy.visual == "active", "active kitchen visuals continue")
dorothy.visual = "completed"
assert(Auxiliary.update(dorothy, player, {}, kitchenIntent, group))
assert(dorothy.visual == nil, "finished visual releases its actor")
dorothy.x = 6
assert(Auxiliary.update(dorothy, player, {}, kitchenIntent, group))
assert(dorothy.lastNavigation.action == "auxiliary_return_to_kitchen"
    and dorothy.lastNavigation.target == squares["0:0"],
    "wandered worker returns through shared navigation")
dorothy.x = 0
local before = dorothy.lastNavigation
dorothy.x, dorothy.y = 1.3, 0.5
assert(Auxiliary.update(dorothy, player, {}, kitchenIntent, group))
assert(dorothy.lastNavigation == before,
    "arrival within 0.8 tiles of the square centre does not re-path")
dorothy.x, dorothy.y = 0, 0
assert(Auxiliary.intentFor(dorothy, player,
    { threatCount = 1 }, group).mode == "zombie_defense")
for _ = 1, 2 do
    local flour = SC.GameplayUtil.addItem(player.inv, "Base.Flour2")
    local sugar = SC.GameplayUtil.addItem(player.inv, "Base.Sugar")
    assert(Auxiliary.action(group, "buy_bake", player))
    assert(flour.container == dorothy.inv and sugar.container == dorothy.inv)
end
assert(#player.inv.items == 2 and player.inv.items[1].kind == "Base.Pie")
assert(group.standing == "Trusted" and Auxiliary.canRecruit(group))
assert(group.oddball.recruitmentCandidateKey == "member-3")
assert(Auxiliary.action(group, "recruit", player))
assert(requested[1] == "ask" and requested[2] == "trial")
assert(Auxiliary.action(group, "hurt", player))
assert(group.standing == "Hostile")
for _, value in ipairs({ dorothy, evelyn, opal }) do
    assert(value.lastLine:find("manners", 1, true))
end
print("Auxiliary PASS: real bake trade, Opal candidate, collective defense")
