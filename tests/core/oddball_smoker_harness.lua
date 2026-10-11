-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Smoker = SC.OddballSmoker
local clock = 1000
local room = {}
local tiles = {}
local function tile(x, y)
    local square = { x = x, y = y, z = 0, room = room, objects = {} }
    tiles[x .. ":" .. y] = square
    return square
end
local start = tile(9, 10)
local chairSquare = tile(10, 10)
local windowSquare = tile(10, 9)
local curtain = { open = false }
local window = { open = false, locked = true,
    curtain = curtain, kind = "window" }
windowSquare.objects[1] = window
local actor = { id = "mara", x = 9, y = 10, z = 0, square = start,
    inv = { items = {} }, worn = {}, lines = {} }
local player = { x = 11, y = 10, z = 0, square = chairSquare }
local group = { id = "smoker-scene", standing = "Neutral",
    members = { { actorId = "mara", alive = true } },
    oddball = { id = "window_smoker_mara_voss", site = {
        spawn = { x = 9, y = 10, z = 0 },
        chair = { x = 10, y = 10, z = 0,
            spriteName = "furniture_seating_indoor_01_43", create = true },
        window = { x = 10, y = 9, z = 0, objectIndex = 0 },
        lookOut = { x = 10, y = 9, z = 0 },
    } } }
local registryActor = actor
SC.Registry = { byId = function(id)
    return id == "mara" and { actor = registryActor } or nil
end }
SC.NativeList = {
    get = function(list, index) return list[index + 1] end,
    size = function(list) return #list end,
}
local styleSlots = {
    ["Base.Jacket_Black"] = "Jacket",
    ["Base.Glasses_Sun"] = "Eyes",
    ["Base.Necklace_Choker"] = "Neck",
}
local function count(kind)
    local total = 0
    for _, item in ipairs(actor.inv.items) do
        if item.kind == kind then total = total + 1 end
    end
    return total
end
SC.GameplayUtil = {
    nowMs = function() return clock end,
    stableHash = function() return 0 end,
    isValidActor = function(value) return value ~= nil end,
    gridSquare = function(x, y) return tiles[x .. ":" .. y] end,
    isClearActorSpawnSquare = function(square)
        return square == chairSquare and #square.objects == 0,
            "chair_tile_occupied"
    end,
    squareOf = function(value) return value.square end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind }
        inv.items[#inv.items + 1] = item
        return item
    end,
    modData = function(value)
        value.data = value.data or {}
        return value.data
    end,
    instanceOf = function(value, kind)
        return value.kind == "window" and kind == "IsoWindow"
    end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    end,
    canSee = function() return true end,
    directInteractionAccess = function() return true, {} end,
    move = function(value, _, intent)
        assert(intent.action == "sit")
        value.seated = true
        value.seatObject = intent.object
        value.square = chairSquare
        value.x, value.y = 10, 10
        return true, "native_chair_entered"
    end,
    say = function(value, line)
        value.lines[#value.lines + 1] = line
        return true
    end,
    call = function(value, method, ...)
        if value == nil then return nil, false end
        local first, second = ...
        if method == "getObjects" then return value.objects, true end
        if method == "getRoom" then return value.room, true end
        if method == "AddSpecialObject" then
            assert(second == #value.objects)
            value.objects[#value.objects + 1] = first
            first.square = value
            return nil, true
        end
        if method == "RecalcProperties" then
            value.recalcProperties = (value.recalcProperties or 0) + 1
            return nil, true
        end
        if method == "RecalcAllWithNeighbours" then
            assert(first == true)
            value.recalcNeighbours = (value.recalcNeighbours or 0) + 1
            return nil, true
        end
        if method == "getObjectIndex" then
            for index, item in ipairs(value.square.objects) do
                if item == value then return index - 1, true end
            end
            return -1, true
        end
        if method == "getSprite" then return value.sprite, true end
        if method == "getName" and value.spriteName then
            return value.spriteName, true end
        if method == "HasCurtains" then return value.curtain, true end
        if method == "isLocked" then return value.locked == true, true end
        if method == "setIsLocked" then
            value.locked = first == true
            return nil, true
        end
        if method == "isSmashed" or method == "isBarricaded"
            or method == "isPermaLocked" then return false, true end
        if method == "IsOpen" then return value.open, true end
        if method == "openCloseCurtain" then
            value.curtain.open = true
            return nil, true
        end
        if method == "ToggleWindow" then
            if not value.jammed then value.open = true end
            return nil, true
        end
        if method == "getTilePositionCount" then return 1, true end
        if method == "getFacingDirection" then return "N", true end
        if method == "getPrimaryHandItem" then return value.primary, true end
        if method == "getSecondaryHandItem" then return value.secondary, true end
        if method == "setPrimaryHandItem" then
            value.primary = first
            return nil, true
        end
        if method == "setSecondaryHandItem" then
            value.secondary = first
            return nil, true
        end
        if method == "getBodyLocation" then
            return styleSlots[value.kind], true
        end
        if method == "getWornItem" then
            return value.worn[first], true
        end
        if method == "setWornItem" then
            value.worn[first] = second
            return nil, true
        end
        if method == "resetModelNextFrame" then
            value.modelResets = (value.modelResets or 0) + 1
            return nil, true
        end
        if method == "setName" then value.name = first return nil, true end
        if method == "isSittingOnFurniture" then
            return value.seated == true, true
        end
        if method == "getSitOnFurnitureObject" then
            return value.seatObject, true
        end
        return nil, false
    end,
}
IsoObject = { new = function(square, spriteName, name)
    assert(square == chairSquare and name == "Chair")
    return { kind = "chair", spriteName = spriteName,
        sprite = { spriteName = spriteName } }
end }
SeatingManager = { getInstance = function() return {} end }
SC.NativeActions = { leaveSeating = function(value)
    value.seated, value.seatObject, value.ground = false, nil, false
    return true
end, seatingStatus = function(value)
    return value.ground and "ground"
        or value.seated and "furniture" or "standing"
end }
local forcedStanding = 0
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id)
    forcedStanding = forcedStanding + 1
    group.standing = standing
    return true
end }
local trials = 0
SC.FactionRecruitment = {
    ask = function(id, guest)
        assert(id == group.id and guest == player)
        return true
    end,
    startTrial = function(id, guest)
        assert(id == group.id and guest == player)
        trials = trials + 1
        return true, "trial_started"
    end,
}
local queue = { current = nil, queue = {} }
local originalFlameLookup = function()
    error("native local-player inventory pane is unavailable")
end
ISInventoryPaneContextMenu = { hasOpenFlame = originalFlameLookup }
ISEatFoodAction = { new = function(_, value, item, portion)
    assert(value == actor and item.kind == "Base.CigaretteSingle"
        and portion == 1)
    assert(ISInventoryPaneContextMenu.hasOpenFlame(actor) == nil,
        "constructor uses safe fire lookup for this companion")
    return {
        isValidStart = function() return true end,
        isValid = function() return true end,
        forceCancel = function(self)
            self.cancelled = true
            queue.current = nil
            queue.queue = {}
        end,
    }
end }
ISTimedActionQueue = {
    getTimedActionQueue = function(value)
        assert(value == actor)
        return queue
    end,
    add = function(action)
        queue.current = action
        queue.queue[1] = action
    end,
}

local ready, why = Smoker.onSpawn(group, actor)
assert(ready, tostring(why))
assert(window.open and curtain.open and not window.locked,
    "indoor occupant unlocks window and opens both curtain and window")
assert(#chairSquare.objects == 1,
    "a real furniture object was placed on the window tile")
assert(chairSquare.recalcProperties == 1
    and chairSquare.recalcNeighbours == 1,
    "chair placement refreshes native square properties and neighbours")
local chair = chairSquare.objects[1]
assert(chair.data.lfSmokerChairGroupId == group.id)
assert(count("Base.MeatCleaver") == 1
    and count("Base.CigaretteSingle") == 3
    and count("Base.Lighter") == 1
    and count("Base.CigarettePack") == 1
    and count("Base.Book_Philosophy") == 1
    and count("Base.Lipstick") == 1)
assert(actor.worn.Jacket.kind == "Base.Jacket_Black"
    and actor.worn.Eyes.kind == "Base.Glasses_Sun"
    and actor.worn.Neck.kind == "Base.Necklace_Choker"
    and actor.modelResets == 1,
    "style pieces are native worn items with model refresh")
assert(actor.primary == nil and actor.secondary == nil,
    "cleaver stays out of both hands")
assert(Smoker.onSpawn(group, actor))
assert(#chairSquare.objects == 1 and count("Base.MeatCleaver") == 1
    and count("Base.CigaretteSingle") == 3,
    "scene and inventory are idempotent across save/load attachment")

local intent = Smoker.intentFor(actor, player, {}, group)
assert(intent.mode == "smoker_chair")
assert(Smoker.update(actor, player, nil, intent, group))
assert(actor.seated and actor.seatObject == chair,
    "native furniture pose is used")
local smoking, smokeReason = Smoker.update(actor, player, nil, intent, group)
assert(smoking and smokeReason == "smoker_native_cigarette_started")
assert(queue.current ~= nil and group.oddball.smokeCount == 1
    and actor.seated and actor.primary == nil,
    "stock smoking action starts without leaving chair or drawing cleaver")
assert(ISInventoryPaneContextMenu.hasOpenFlame == originalFlameLookup,
    "local-player fire lookup is restored after action creation")
assert(Smoker.update(actor, player, nil, intent, group))
assert(group.oddball.smokeCount == 1,
    "active action is not stacked")

assert(Smoker.pulse(group, player, clock))
assert(group.discovered == true and #actor.lines == 1)
assert(#Smoker.menuOptions(group, player) == 3)
assert(Smoker.action(group, "ask_view", player))
assert(Smoker.action(group, "ask_past", player))
assert(Smoker.action(group, "ask_belief", player))
assert(string.find(actor.lines[#actor.lines], "went to shit", 1, true),
    "the belief response says plainly what happened to her world")
assert(group.oddball.stage == "open" and group.standing == "Trusted"
    and Smoker.canRecruit(group) == true)
assert(#Smoker.menuOptions(group, player) == 4)
assert(Smoker.action(group, "recruit", player) and trials == 1)
assert(actor.primary == nil, "dialogue never arms the cleaver")

local active = queue.current
assert(Smoker.action(group, "hurt", player))
assert(active.cancelled and not actor.seated
    and actor.primary and actor.primary.kind == "Base.MeatCleaver"
    and actor.secondary == nil,
    "actual attack cancels smoke, exits seat, and equips exact cleaver")
assert(group.standing == "Hostile" and forcedStanding == 2
    and group.permanentHostility == true)
assert(Smoker.intentFor(actor, player, {}, group).mode == "hostile")
assert(#Smoker.menuOptions(group, player) == 0)
assert(Smoker.onSpawn(group, actor))
assert(count("Base.MeatCleaver") == 1,
    "hostile reattachment does not duplicate her knife")

-- A window blocked from opening must never be reported as a valid scene.
group.oddball.stage = "watching"
window.open, window.jammed = false, true
local opened, blocked = Smoker.onSpawn(group, actor)
assert(not opened and blocked == "smoker_window_cannot_open")

window.open, window.jammed = true, false
actor.ground, actor.seated, actor.seatObject = true, false, nil
local recovered, recoverReason = Smoker.update(actor, player, nil,
    { mode = "smoker_chair" }, group)
assert(not recovered and recoverReason == "smoker_native_seat_fell_to_ground"
    and actor.ground == false and group.oddball.seatFailures == 1,
    "ground-seat fallback is recognized, logged once and exited")
local waiting, waitReason = Smoker.update(actor, player, nil,
    { mode = "smoker_chair" }, group)
assert(waiting and waitReason == "smoker_chair_retry_backoff",
    "failed native chair entry has a bounded retry delay")
clock = clock + 6000
assert(Smoker.update(actor, player, nil,
    { mode = "smoker_chair" }, group))
assert(actor.seated and actor.seatObject == chair,
    "retry reaches the exact native chair")
group.oddball.nextSmokeAt = 0
ISEatFoodAction.new = function(_, value)
    assert(value == actor)
    assert(ISInventoryPaneContextMenu.hasOpenFlame(actor) == nil)
    error("simulated_constructor_failure")
end
local failed, failureReason = Smoker.update(actor, player, nil,
    { mode = "smoker_chair" }, group)
assert(not failed and string.find(failureReason,
    "simulated_constructor_failure", 1, true)
    and ISInventoryPaneContextMenu.hasOpenFlame == originalFlameLookup,
    "fire lookup is restored even if vanilla action creation throws")

print("oddball smoker harness passed")
