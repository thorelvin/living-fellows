-- SPDX-License-Identifier: MIT
-- Small helpers the Strange Folk encounter modules share. Each module keeps
-- its own one-line wrapper (actorFor, story, near, ...) that calls these, so
-- a module that needs a different rule simply keeps its own version. The
-- wrappers look the kit up when they run, so load order does not matter.

local SC = LivingFellows
SC.OddballKit = SC.OddballKit or {}
local Kit = SC.OddballKit
local function U() return SC.GameplayUtil end

local function memberRecord(group, index)
    local member = group and group.members and group.members[index or 1]
    return member and member.actorId and SC.Registry and SC.Registry.byId(member.actorId) or nil
end

-- The actor of the group's member at index (the first by default) while the
-- game still holds it valid.
function Kit.actor(group, index)
    local record = memberRecord(group, index)
    return record and record.actor and U().isValidActor(record.actor) and record.actor or nil
end

-- The same member's actor when it is also alive.
function Kit.livingActor(group, index)
    local record = memberRecord(group, index)
    local actor = record and record.actor
    return actor and U().isValidActor(actor) and not U().isDead(actor) and actor or nil
end

-- Whatever actor the registry holds for that member, valid or not.
function Kit.recordActor(group, index)
    local record = memberRecord(group, index)
    return record and record.actor or nil
end

-- True when the player stands within radius tiles of the actor and can see it.
function Kit.seenWithin(actor, player, radius)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end

-- The group's story when it belongs to encounter id, with its stage set to
-- stage when it has none yet.
function Kit.story(group, id, stage)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= id then return nil end
    if stage ~= nil then value.stage = value.stage or stage end
    return value
end

-- The first item the actor carries, searched to limit items and depth
-- levels, whose full type is kind.
function Kit.itemOfType(actor, kind, limit, depth)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, limit, depth) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

-- The same search, for the first item where predicate(itemType, item) holds.
function Kit.itemWhere(actor, predicate, limit, depth)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, limit, depth) or {}) do
        if predicate(U().itemType(item), item) then return item end
    end
    return nil
end

-- The next entry of a line pool, in turn; the story remembers its place.
function Kit.nextLine(list, value, pool)
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return list[index]
end

-- A line entry's text: a plain string, or { profane, clean = radio edit }.
function Kit.lineText(entry)
    if type(entry) == "table" then
        return U().config("profanityEnabled") == false and entry.clean or entry[1]
    end
    return entry
end

-- A saved number that may have come back as text.
function Kit.number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

-- The game's world age in hours, or nil before the clock exists.
function Kit.ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(time and select(1, U().call(time, "getWorldAgeHours")))
end

return Kit
