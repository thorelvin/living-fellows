-- SPDX-License-Identifier: MIT
-- SCOddballKit: the helpers the Strange Folk encounter modules share.

local SC = SurvivorCompanion
local Kit = SC.OddballKit
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "oddball kit check " .. tostring(checks) .. ": " .. tostring(message))
end

local actors = {
    live = { x = 0, y = 0, z = 0, valid = true, dead = false },
    dead = { x = 0, y = 0, z = 0, valid = true, dead = true },
    gone = { x = 0, y = 0, z = 0, valid = false, dead = false },
}
local profanity = true
SC.Registry = { byId = function(id) return actors[id] and { actor = actors[id] } or nil end }
SC.GameplayUtil = {
    isValidActor = function(actor) return actor.valid == true end,
    isDead = function(actor) return actor.dead == true end,
    distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
    canSee = function(player) return player.blind ~= true end,
    inventory = function(actor) return actor.items end,
    inventoryItemsDeep = function(items, limit, depth)
        local result = {}
        for index = 1, math.min(#items, limit) do
            if (items[index].depth or 0) <= depth then result[#result + 1] = items[index] end
        end
        return result
    end,
    itemType = function(item) return item.kind end,
    config = function(key) if key == "profanityEnabled" then return profanity end end,
    call = function(object, method)
        if object and type(object[method]) == "function" then return object[method](object), true end
        return nil, false
    end,
}
local function group(...)
    local members = {}
    for index, id in ipairs({ ... }) do members[index] = { actorId = id } end
    return { members = members }
end

-- Actors: valid, living, or whatever the registry holds.
check(Kit.actor(group("live")) == actors.live, "the first member's valid actor")
check(Kit.actor(group("gone")) == nil, "an actor the game no longer holds is not returned")
check(Kit.actor(group("dead")) == actors.dead, "a valid but dead actor is still the member's actor")
check(Kit.actor(group("gone", "live"), 2) == actors.live, "the member at an index")
check(Kit.actor(group("live"), 2) == nil and Kit.actor(nil) == nil and Kit.actor({}) == nil,
    "a missing member, group or member list has no actor")
check(Kit.actor(group("nobody")) == nil, "a member the registry does not know has no actor")
check(Kit.livingActor(group("live")) == actors.live and Kit.livingActor(group("dead")) == nil
    and Kit.livingActor(group("gone")) == nil, "living actors are valid and not dead")
check(Kit.recordActor(group("gone")) == actors.gone and Kit.recordActor(group("dead")) == actors.dead,
    "the registry's actor is returned even when invalid")
check(Kit.recordActor(group("nobody")) == nil, "no record, no actor")

-- Seen within a distance.
local player = { x = 3, y = 4, z = 0 }
check(Kit.seenWithin(actors.live, player, 5) == true, "seen at exactly the distance")
check(Kit.seenWithin(actors.live, player, 4) == false, "too far")
local blind = { x = 3, y = 4, z = 0, blind = true }
check(Kit.seenWithin(actors.live, blind, 9) == false, "close but not seen")
check(Kit.seenWithin(nil, player, 9) == nil and Kit.seenWithin(actors.live, nil, 9) == nil,
    "no actor or no player is not seen")

-- Stories.
local mine = { oddball = { id = "kit_story" } }
check(Kit.story(mine, "kit_story", "unmet") == mine.oddball and mine.oddball.stage == "unmet",
    "a story of this encounter gets its first stage")
mine.oddball.stage = "talking"
check(Kit.story(mine, "kit_story", "unmet").stage == "talking", "a stage already set is kept")
local plain = { oddball = { id = "kit_story" } }
check(Kit.story(plain, "kit_story") == plain.oddball and plain.oddball.stage == nil,
    "without a first stage none is set")
check(Kit.story(mine, "other_story", "unmet") == nil and Kit.story({}, "kit_story") == nil
    and Kit.story(nil, "kit_story") == nil, "another encounter's story or none is nil")

-- Inventory searches.
local carrier = { items = { { kind = "Base.Apple" }, { kind = "Base.Axe", depth = 3 },
    { kind = "Base.Axe" } } }
check(Kit.itemOfType(carrier, "Base.Axe", 10, 8) == carrier.items[2], "the first item of a type")
check(Kit.itemOfType(carrier, "Base.Axe", 10, 2) == carrier.items[3], "the depth limit is honoured")
check(Kit.itemOfType(carrier, "Base.Axe", 1, 8) == nil, "the item limit is honoured")
check(Kit.itemOfType(nil, "Base.Axe", 10, 8) == nil and Kit.itemOfType(carrier, "Base.Pan", 10, 8) == nil,
    "no carrier or no such item")
local asked = {}
local found = Kit.itemWhere(carrier, function(kind, item)
    asked[#asked + 1] = kind
    return kind == "Base.Axe" and item.depth == nil
end, 10, 8)
check(found == carrier.items[3] and #asked == 3 and asked[1] == "Base.Apple",
    "the predicate sees each type and item until one fits")

-- Lines.
local story = { lines = {} }
local pool = { "one", "two" }
check(Kit.nextLine(pool, story, "greet") == "one" and Kit.nextLine(pool, story, "greet") == "two"
    and Kit.nextLine(pool, story, "greet") == "one", "lines come in turn and wrap round")
story.lines.greet = "bad"
check(Kit.nextLine(pool, story, "greet") == "one", "a damaged place starts the pool again")
story.lines.greet = 1.5
check(Kit.nextLine(pool, story, "greet") == "one", "a fractional place starts the pool again")
check(Kit.lineText("plain") == "plain", "a plain line is its own text")
check(Kit.lineText({ "Damn it.", clean = "Darn it." }) == "Damn it.", "the profane line by default")
profanity = false
check(Kit.lineText({ "Damn it.", clean = "Darn it." }) == "Darn it.", "the clean line with profanity off")
profanity = true

-- Numbers and the clock.
check(Kit.number(4) == 4 and Kit.number("4.5") == 4.5, "numbers and numeric text")
check(Kit.number("four") == nil and Kit.number(nil) == nil and Kit.number({}) == nil,
    "anything else is not a number")
getGameTime = nil
check(Kit.ageHours() == nil, "no clock, no age")
getGameTime = function() return { getWorldAgeHours = function() return 72.5 end } end
check(Kit.ageHours() == 72.5, "the world age in hours")
getGameTime = nil

print("ODDBALL_KIT_PASS checks=" .. tostring(checks))
