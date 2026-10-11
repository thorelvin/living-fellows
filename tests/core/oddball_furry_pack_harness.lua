-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Pack = SC.OddballFurryPack
local den, hall = {}, {}
local clock = 1000
local registry = {}
local standingChanges = 0

local function actor(id, x, y, room)
    return { id = id, x = x, y = y, z = 0,
        square = { room = room or den },
        inv = { items = {} }, worn = {}, lines = {} }
end

local function groupFor(tag)
    local members, actors, posts = {}, {}, {}
    for index = 1, 4 do
        local id = tag .. tostring(index)
        local value = actor(id, index - 1, 0)
        value.primary = { kind = "Base.Hammer" }
        actors[index] = value
        registry[id] = value
        members[index] = { actorId = id, alive = true,
            key = "member-" .. tostring(index) }
        posts[index] = { x = index - 1, y = 0, z = 0 }
    end
    return { id = tag, standing = "Wary", members = members,
        oddball = { id = "spiffo_dressup_ambush",
            site = { spawn = posts[1], memberSpawns = posts } } }, actors
end

local group, actors = groupFor("den")
local player = actor("player", -7, 0)
SC.Registry = { byId = function(id)
    return registry[id] and { actor = registry[id] } or nil
end }
SC.Factions = { forceStanding = function(id, standing)
    assert(id == group.id and standing == "Hostile")
    standingChanges = standingChanges + 1
    group.standing = standing
    return true, standing
end }
local slots = {
    ["Base.SpiffoSuit"] = "FullSuit",
    ["Base.Hat_Spiffo"] = "FullHat",
    ["Base.SpiffoTail"] = "Tail",
}
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value ~= nil end,
    nowMs = function() return clock end,
    stableHash = function() return 0 end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    itemType = function(item) return item.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind }
        inv.items[#inv.items + 1] = item
        return item
    end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    end,
    position = function(value) return value.x, value.y, value.z end,
    squareOf = function(value) return value.square end,
    gridSquare = function(x, y, z)
        return x == 0 and y == 0 and z == 0 and { room = den } or nil
    end,
    canSee = function(observer) return observer.sees ~= false end,
    say = function(value, line)
        value.lines[#value.lines + 1] = line
        return true
    end,
    call = function(value, method, first, second)
        if method == "getBodyLocation" then return slots[value.kind], true end
        if method == "getRoom" then return value.room, true end
        if method == "getWornItem" then return value.worn[first], true end
        if method == "setWornItem" then
            if not value.failWear then value.worn[first] = second end
            return true, true
        end
        if method == "getPrimaryHandItem" then return value.primary, true end
        if method == "getSecondaryHandItem" then return value.secondary, true end
        if method == "setPrimaryHandItem" then
            value.primary = first
            return true, true
        end
        if method == "setSecondaryHandItem" then
            value.secondary = first
            return true, true
        end
        if method == "faceLocationF" then
            value.facing = { first, second }
            return true, true
        end
        if method == "resetModelNextFrame" then
            value.modelResets = (value.modelResets or 0) + 1
            return true, true
        end
        return nil, false
    end,
}

local function count(value, kind)
    local result = 0
    for _, item in ipairs(value.inv.items) do
        if item.kind == kind then result = result + 1 end
    end
    return result
end

for index, value in ipairs(actors) do
    local ready, reason = Pack.onSpawn(group, value)
    assert(ready, tostring(reason))
    assert(value.primary == nil and value.secondary == nil,
        "no exposed weapons during costume play")
    assert(value.worn.FullSuit.kind == "Base.SpiffoSuit"
        and value.worn.FullHat.kind == "Base.Hat_Spiffo"
        and value.worn.Tail.kind == "Base.SpiffoTail",
        "every member actually wears the full costume")
    assert(count(value, "Base.KnifeShiv") == 1
        and count(value, "Base.TissueBox") == 1
        and count(value, "Base.OilVegetable") == 1,
        "each member carries a real shiv, tissues and cooking oil")
    assert(value.facing ~= nil and value.modelResets == 1,
        "dress-up actors face one another and refresh their models")
    assert(group.oddball.gearSeeded[index] == true)
    assert(Pack.onSpawn(group, value))
    assert(count(value, "Base.KnifeShiv") == 1
        and count(value, "Base.TissueBox") == 1,
        "reattachment does not duplicate props")
end

assert(Pack.canRecruit(group) == false)
assert(Pack.intentFor(actors[1], player, {}, group).mode == "oddball_idle")
assert(Pack.intentFor(actors[1], player,
    { threatCount = 1 }, group).mode == "zombie_defense")
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring" and group.discovered == true)
assert(#actors[1].lines == 1 and standingChanges == 0,
    "first sight is an invitation, not an immediate attack")
assert(#Pack.menuOptions(group, player) == 2)
assert(Pack.action(group, "ask_costumes", player))
assert(#actors[4].lines == 1)

clock = 2500
player.x = 2
player.square.room = hall
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring" and standingChanges == 0,
    "being near across a wall does not spring the trap")
player.square.room = den
player.sees = false
assert(Pack.pulse(group, player, clock))
assert(standingChanges == 0, "unseen player does not spring the trap")
player.sees = true
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring"
    and group.oddball.closeLineSpoken ~= true
    and #actors[2].lines == 0 and standingChanges == 0,
    "close line cannot overlap the invitation or an immediate player reply")
clock = 5999
assert(Pack.pulse(group, player, clock))
assert(group.oddball.closeLineSpoken ~= true and standingChanges == 0,
    "the first friendly line keeps a five-second speech gap")
clock = 6000
assert(Pack.pulse(group, player, clock))
assert(group.oddball.closeLineSpoken == true
    and group.oddball.closeSpokenAt == clock
    and #actors[2].lines == 1 and standingChanges == 0,
    "the close invitation gets its own speech beat")
clock = 9999
assert(Pack.pulse(group, player, clock))
assert(standingChanges == 0,
    "the pack waits four seconds after the close line")
clock = 10000
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "hostile"
    and group.standing == "Hostile"
    and group.permanentHostility == true
    and group.oddball.revealReason == "guest_entered_den"
    and standingChanges == 1,
    "entering the den springs one persistent ambush")
for _, value in ipairs(actors) do
    assert(value.primary ~= nil
        and value.primary.kind == "Base.KnifeShiv"
        and Pack.intentFor(value, player, {}, group).mode == "hostile",
        "all four equip real shivs and receive native hostile intent")
end
assert(#Pack.menuOptions(group, player) == 0)
assert(Pack.pulse(group, player, clock))
assert(standingChanges == 1, "hostility is not repeatedly forced")
assert(#actors[3].lines == 1,
    "the nearby member gives the reveal before the ranger's later shout")
clock = 14499
assert(Pack.pulse(group, player, clock) and #actors[3].lines == 1)
clock = 14500
assert(Pack.pulse(group, player, clock) and #actors[3].lines == 2,
    "second attack shout waits until the first has cleared")
local restored = actor("den1", 0, 0)
restored.inv, restored.worn = actors[1].inv, actors[1].worn
registry.den1 = restored
assert(Pack.onSpawn(group, restored))
assert(restored.primary.kind == "Base.KnifeShiv"
    and count(restored, "Base.KnifeShiv") == 1,
    "restored hostile member re-equips its persisted shiv")

local attacked, attackedActors = groupFor("attacked")
group = attacked
for _, value in ipairs(attackedActors) do assert(Pack.onSpawn(group, value)) end
player.x = 20
assert(Pack.action(group, "hurt", player))
assert(group.oddball.revealReason == "player_attacked"
    and standingChanges == 2,
    "a player hit reveals the attack before the lure completes")
for _, value in ipairs(attackedActors) do
    assert(value.primary and value.primary.kind == "Base.KnifeShiv")
end

local oldSave, oldActors = groupFor("old_save")
group = oldSave
for _, value in ipairs(oldActors) do assert(Pack.onSpawn(group, value)) end
group.oddball.stage = "luring"
group.oddball.invitedAt = clock - 20000
group.oddball.closeLineSpoken = true
player.x, player.square.room, player.sees = 2, den, true
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring"
    and group.oddball.closeSpokenAt == clock,
    "old saves with an untimed close line receive a fresh suspense beat")
clock = clock + 4000
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "hostile",
    "the old save still resolves its ambush")

local talking, talkingActors = groupFor("talking")
group = talking
for _, value in ipairs(talkingActors) do assert(Pack.onSpawn(group, value)) end
group.oddball.stage = "luring"
group.oddball.invitedAt = clock - 10000
group.oddball.closeLineSpoken = true
group.oddball.closeSpokenAt = clock - 6000
assert(Pack.action(group, "ask_costumes", player))
clock = clock + 3999
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring",
    "a player-triggered reply keeps the reveal from talking over it")
clock = clock + 1
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "hostile",
    "the conversation delay does not cancel the eventual ambush")

local stolen, stolenActors = groupFor("stolen")
group = stolen
for _, value in ipairs(stolenActors) do assert(Pack.onSpawn(group, value)) end
local beforeExternal = standingChanges
player.x = 30
group.standing = "Hostile" -- the faction's theft/offense path ran first
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "hostile"
    and group.oddball.revealReason == "faction_became_hostile"
    and group.permanentHostility == true
    and standingChanges == beforeExternal,
    "externally hostile standing reveals without re-forcing standing")
for _, value in ipairs(stolenActors) do
    assert(value.primary and value.primary.kind == "Base.KnifeShiv",
        "theft arms every loaded pack member")
end

local savedTheft, savedActors = groupFor("saved_theft")
group = savedTheft
for _, value in ipairs(savedActors) do assert(Pack.onSpawn(group, value)) end
group.oddball.stage = "luring"
group.standing = "Hostile"
for index, value in ipairs(savedActors) do
    local restoredActor = actor(value.id, value.x, value.y)
    restoredActor.inv, restoredActor.worn = value.inv, value.worn
    registry[value.id] = restoredActor
    savedActors[index] = restoredActor
    assert(Pack.onSpawn(group, restoredActor))
    assert(count(restoredActor, "Base.KnifeShiv") == 1
        and restoredActor.primary.kind == "Base.KnifeShiv",
        "load into hostile standing re-equips persisted shiv")
end
local intentBeforePulse = Pack.intentFor(savedActors[1], player, {}, group)
assert(intentBeforePulse.mode == "hostile"
    and group.oddball.stage == "hostile"
    and group.oddball.revealReason == "faction_became_hostile"
    and standingChanges == beforeExternal,
    "combat intent repairs hostile story state before the next pulse")
for _, value in ipairs(savedActors) do
    assert(value.primary.kind == "Base.KnifeShiv")
end

local retry, retryActors = groupFor("retry")
group = retry
retryActors[1].failWear = true
local ready = Pack.onSpawn(group, retryActors[1])
assert(ready == false and count(retryActors[1], "Base.SpiffoSuit") == 1,
    "unconfirmed clothing must not mark the actor ready")
retryActors[1].failWear = false
assert(Pack.onSpawn(group, retryActors[1]))
assert(count(retryActors[1], "Base.SpiffoSuit") == 1,
    "a native wear retry does not duplicate the costume")

local peripheral, peripheralActors = groupFor("peripheral")
group = peripheral
for _, value in ipairs(peripheralActors) do assert(Pack.onSpawn(group, value)) end
peripheralActors[1].x = -10
player.x, player.square.room, player.sees = 3, den, true
clock = 60000
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring"
    and #peripheralActors[4].lines == 1
    and #peripheralActors[1].lines == 0,
    "a visible nonleader invites the player even when the leader is distant")
assert(#Pack.menuOptions(group, player) == 2,
    "a nonleader can introduce the dress-up scene")
clock = 65000
assert(Pack.pulse(group, player, clock))
assert(group.oddball.closeLineSpoken == true
    and group.standing ~= "Hostile",
    "the nonleader still gives the close invitation before the ambush")
clock = 69000
player.square.room = hall
peripheralActors[4].square.room = hall
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "luring",
    "meeting a costumed member outside the original den does not spring it")
player.square.room = den
peripheralActors[4].square.room = den
assert(Pack.pulse(group, player, clock))
assert(group.oddball.stage == "hostile"
    and group.oddball.revealReason == "guest_entered_den"
    and #peripheralActors[4].lines == 2,
    "entering near a nonleader springs the ambush from that member")
for _, value in ipairs(peripheralActors) do
    assert(value.primary and value.primary.kind == "Base.KnifeShiv")
end

print("oddball furry pack harness passed")
