-- SPDX-License-Identifier: MIT
-- Four costumed players improvise a harmless Spiffo adventure until their
-- guest steps into the den. The reveal equips real shivs and hands combat to
-- the existing hostile-faction behavior.

local SC = SurvivorCompanion
SC.OddballFurryPack = SC.OddballFurryPack or {}
local Pack = SC.OddballFurryPack

local ID = "spiffo_dressup_ambush"
local COSTUME = {
    "Base.SpiffoSuit", "Base.Hat_Spiffo", "Base.SpiffoTail",
}
local SHIV = "Base.KnifeShiv"
local PROPS = { "Base.TissueBox", "Base.OilVegetable" }
local BANTER = {
    "Captain Fluff says the lost traveler must find the orange kingdom.",
    "The tail goes on the back, Noel. We have rehearsed this.",
    "I am the ranger of the den. The couch is my watchtower.",
    "Hush. I can hear footsteps outside the kingdom.",
    "The royal pantry has oil for supper and tissues for these dusty masks.",
    "No, a cardboard crown doesn't make you king. Stay in character.",
    "We used to do this for laughs. Now we do it to forget the street.",
    "Someone tell me the next line before the guest comes in.",
}
local INVITATIONS = {
    "Come in! The den needs one more lost traveler.",
    "Hey, stranger! We've got a part for you in our little adventure.",
    "Welcome to the orange kingdom. Just step inside and play along.",
}
local CLOSE_LINES = {
    "Stand by the couch. The ranger will tell you what happens next.",
    "A little closer. You can't hear the secret through that mask.",
    "The rules are simple: stay in the den until the story ends.",
}
local REVEAL = {
    "The story ends here. Shivs out!",
    "Enough pretending. Get the knives!",
    "Masks stay on. The guest doesn't leave!",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    value.gearSeeded = type(value.gearSeeded) == "table"
        and value.gearSeeded or {}
    return value
end

local function memberIndex(group, actor)
    local id = actor and U().idOf(actor)
    for index, member in ipairs(group.members or {}) do
        if id ~= nil and member.actorId == id then return index end
    end
    return nil
end

local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function ensureItem(actor, inventory, kind)
    return itemFor(actor, kind) or U().addItem(inventory, kind)
end

local function wear(actor, item)
    local location, called = U().call(item, "getBodyLocation")
    if not called or not location then return false, "costume_slot_unknown" end
    local current, checked = U().call(actor, "getWornItem", location)
    if not checked then return false, "costume_slot_unavailable" end
    if current == item then return true end
    local _, applied = U().call(actor, "setWornItem", location, item)
    if not applied or select(1, U().call(actor,
        "getWornItem", location)) ~= item then
        return false, "costume_wear_failed"
    end
    return true
end

local function bareHands(actor)
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local secondary = select(1, U().call(actor, "getSecondaryHandItem"))
    if primary then U().call(actor, "setPrimaryHandItem", nil) end
    if secondary then U().call(actor, "setSecondaryHandItem", nil) end
    return select(1, U().call(actor, "getPrimaryHandItem")) == nil
        and select(1, U().call(actor, "getSecondaryHandItem")) == nil
end

local function arm(actor)
    local shiv = itemFor(actor, SHIV)
    if not shiv then return false, "shiv_missing" end
    local secondary = select(1, U().call(actor, "getSecondaryHandItem"))
    if secondary then U().call(actor, "setSecondaryHandItem", nil) end
    local _, equipped = U().call(actor, "setPrimaryHandItem", shiv)
    if not equipped or select(1, U().call(actor,
        "getPrimaryHandItem")) ~= shiv
        or select(1, U().call(actor, "getSecondaryHandItem")) ~= nil then
        return false, "shiv_equip_failed"
    end
    return true
end

local function roomOf(actor)
    if not actor then return nil end
    local square = type(U().squareOf) == "function" and U().squareOf(actor)
        or nil
    if not square then
        local x, y, z = U().position(actor)
        square = x and U().gridSquare(math.floor(x), math.floor(y),
            math.floor(z or 0)) or nil
    end
    return square and select(1, U().call(square, "getRoom")) or nil
end

local function nearestVisibleMember(group, player, radius, requiredRoom)
    if not player then return nil end
    local nearest, nearestIndex, nearestDistance
    for index = 1, 4 do
        local actor = actorFor(group, index)
        local distance = actor and U().distance(actor, player) or nil
        if type(distance) == "number" and distance <= radius
            and (not requiredRoom or roomOf(actor) == requiredRoom)
            and U().canSee(player, actor) == true
            and (not nearestDistance or distance < nearestDistance) then
            nearest, nearestIndex, nearestDistance = actor, index, distance
        end
    end
    return nearest, nearestIndex, nearestDistance
end

local function inDen(group, player)
    local value = story(group)
    local post = value and value.site and value.site.spawn
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local den = square and select(1, U().call(square, "getRoom"))
    if not den or roomOf(player) ~= den then return false end
    local member, index = nearestVisibleMember(group, player, 2.8, den)
    return member ~= nil, index
end

local function speak(group, index, line)
    local actor = actorFor(group, index) or actorFor(group, 1)
    return actor and U().say(actor, line) == true or false
end

local function reveal(group, value, reason, speakerIndex)
    if value.stage == "hostile" then return true, "already_hostile" end
    local armed, missing = 0, 0
    for index = 1, 4 do
        local actor = actorFor(group, index)
        if actor then
            local ready = arm(actor)
            if ready then armed = armed + 1 else missing = missing + 1 end
        end
    end
    if group.standing ~= "Hostile" then
        if not SC.Factions or type(SC.Factions.forceStanding) ~= "function" then
            return false, "standing_unavailable"
        end
        local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
        if not changed then return false, why or "standing_change_failed" end
    end
    value.stage = "hostile"
    value.revealReason = reason
    value.armedCount = armed
    value.unarmedCount = missing
    group.permanentHostility = true
    group.discovered = true
    local line = REVEAL[(U().stableHash(group.id) % #REVEAL) + 1]
    speak(group, speakerIndex or 1, line)
    if actorFor(group, 3) then
        value.nextRangerShoutAt = U().nowMs() + 4500
    end
    return true, missing == 0 and "den_ambush" or "den_ambush_partly_unarmed"
end

function Pack.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "furry_pack_unavailable" end
    local index = memberIndex(group, actor)
    if not index or index > 4 then return false, "pack_member_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "pack_inventory_unavailable" end
    for _, kind in ipairs(COSTUME) do
        local item = value.gearSeeded[index] == true and itemFor(actor, kind)
            or ensureItem(actor, inventory, kind)
        if not item then return false, "pack_costume_unavailable:" .. kind end
        local dressed, reason = wear(actor, item)
        if not dressed then return false, reason end
    end
    if value.gearSeeded[index] ~= true then
        for _, kind in ipairs(PROPS) do
            if not ensureItem(actor, inventory, kind) then
                return false, "pack_prop_unavailable:" .. kind
            end
        end
        if not ensureItem(actor, inventory, SHIV) then
            return false, "pack_shiv_unavailable"
        end
        value.gearSeeded[index] = true
        U().call(actor, "resetModelNextFrame")
    end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return arm(actor)
    end
    -- Generic faction gear may have equipped a hammer before this story ran.
    -- An empty hand keeps the dress-up scene honest until the ambush.
    if not bareHands(actor) then return false, "pack_hands_not_clear" end
    local posts = value.site and value.site.memberSpawns or {}
    local other = posts[index % 4 + 1]
    if other then U().call(actor, "faceLocationF",
        other.x + 0.5, other.y + 0.5) end
    return true, "costumed_and_waiting"
end

function Pack.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    if group.standing == "Hostile" and value.stage ~= "hostile" then
        return reveal(group, value, "faction_became_hostile")
    end
    if value.stage == "hostile" or group.standing == "Hostile" then
        if value.nextRangerShoutAt
            and current >= value.nextRangerShoutAt then
            value.nextRangerShoutAt = nil
            speak(group, 3, "Ranger's orders. Nobody gets past us!")
        end
        return true, "hostile"
    end
    if not player or not (actorFor(group, 1) or actorFor(group, 2)
        or actorFor(group, 3) or actorFor(group, 4)) then
        return false, "pack_unloaded"
    end
    local member, speakerIndex, distance = nearestVisibleMember(group,
        player, 9)
    local visible = member ~= nil
    if visible and value.stage == "unmet" then
        value.stage = "luring"
        value.invitedAt = current
        value.nextBanterAt = current + 12000
        group.discovered = true
        speak(group, speakerIndex, INVITATIONS[(U().stableHash(group.id)
            % #INVITATIONS) + 1])
        value.lastStorySpeechAt = current
    end
    if value.stage ~= "luring" or not visible then
        return true, value.stage
    end
    if distance <= 5 and value.closeLineSpoken ~= true
        and current - (tonumber(value.lastStorySpeechAt)
            or tonumber(value.invitedAt) or current) >= 5000 then
        value.closeLineSpoken = true
        value.closeSpokenAt = current
        value.lastStorySpeechAt = current
        value.nextBanterAt = current + 30000
        speak(group, 2, CLOSE_LINES[(U().stableHash(group.id .. ":close")
            % #CLOSE_LINES) + 1])
        return true, "guest_invited_inside"
    end
    -- Saved scenes from an older build may have spoken the close line before
    -- this timestamp existed. Give those saves the same suspense beat.
    if value.closeLineSpoken == true and not value.closeSpokenAt then
        value.closeSpokenAt = current
    end
    local guestInside, guestSpeaker = inDen(group, player)
    if value.closeLineSpoken == true and guestInside
        and current - (tonumber(value.closeSpokenAt) or current) >= 4000
        and current - (tonumber(value.lastStorySpeechAt)
            or tonumber(value.closeSpokenAt) or current) >= 4000 then
        return reveal(group, value, "guest_entered_den", guestSpeaker)
    end
    if current >= (tonumber(value.nextBanterAt) or current + 1) then
        local index = ((tonumber(value.banterIndex) or 0) % #BANTER) + 1
        value.banterIndex = index
        value.nextBanterAt = current + 35000
        speak(group, (index - 1) % 4 + 1, BANTER[index])
        value.lastStorySpeechAt = current
    end
    return true, value.stage
end

function Pack.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" and value.stage ~= "hostile" then
        reveal(group, value, "faction_became_hostile")
    end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Pack.canRecruit()
    return false, "ambush_pack_not_recruitable"
end

function Pack.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage == "hostile"
        or not nearestVisibleMember(group, player, 7) then return {} end
    return {
        { id = "ask_costumes", label = "Ask about their Spiffo costumes",
            enabled = true },
        { id = "join_game", label = "Join their dress-up game",
            enabled = true },
    }
end

function Pack.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then return reveal(group, value, "player_attacked") end
    local options = Pack.menuOptions(group, player)
    if #options == 0 then return false, "pack_not_talking" end
    if action == "ask_costumes" then
        if value.stage == "unmet" then
            value.stage = "luring"
            value.invitedAt = U().nowMs()
            group.discovered = true
        end
        speak(group, 4,
            "We were going to a costume show. Now the den is all we have.")
        value.lastStorySpeechAt = U().nowMs()
        return true, "costumes_explained"
    end
    if action == "join_game" then
        if value.stage == "unmet" then
            value.stage = "luring"
            value.invitedAt = U().nowMs()
            group.discovered = true
        end
        speak(group, 1,
            "Then step into the den. Every story needs a lost traveler.")
        value.lastStorySpeechAt = U().nowMs()
        return true, "guest_invited"
    end
    return false, "unsupported_pack_action"
end

return Pack
