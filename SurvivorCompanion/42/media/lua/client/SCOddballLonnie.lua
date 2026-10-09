-- SPDX-License-Identifier: MIT
-- Lonnie Tackett's wedding. The bride is a real, tagged vanilla zombie.

local SC = SurvivorCompanion
SC.OddballLonnie = SC.OddballLonnie or {}
local Lonnie = SC.OddballLonnie

local ID = "wedding_lonnie_tackett"
local TALK_RANGE = 8
local BRIDE_MARKER = "LF_OddballBrideGroupId"
local brideReferences = {}

local lines = {
    greet = "She said yes on the fourth of July. Then she got sick.",
    plea = "Every bride's a little nervous. She'll calm down.",
    ceremony = "Do you take her? I do. I do. I do.",
    refuse = "I'll ask again tomorrow. The flowers can wait.",
    berserk = "You ruined my wedding!",
    bitten = "Till death. Well. Close enough.",
    interrupted = "She got loose. This isn't how it was meant to be.",
    fellow = "That's not a bride. That's a bride-shaped problem.",
    clergy = "At least somebody here remembers the words.",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    return value
end

function Lonnie.actor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, topic)
    local actor = Lonnie.actor(group)
    return actor and lines[topic] and U().say(actor, lines[topic]) == true or false
end

local function near(group, player)
    local actor = Lonnie.actor(group)
    return actor and player and U().distance(actor, player) <= TALK_RANGE
        and (not U().canSee or U().canSee(player, actor) == true)
end

local function day()
    if type(getGameTime) ~= "function" then return nil end
    local ok, clock = pcall(getGameTime)
    if not ok or not clock then return nil end
    local hours, called = U().call(clock, "getWorldAgeHours")
    return called and tonumber(hours) and math.floor(tonumber(hours) / 24) or nil
end

local function doorFor(value)
    local position = value.site and value.site.vestryDoor
    if type(position) ~= "table" then return nil end
    local square = U().gridSquare(position.x, position.y, position.z or 0)
    if not square then return nil end
    local found
    U().squareObjects(square, function(object)
        if U().instanceOf(object, "IsoDoor") then found = object return true end
    end, 24)
    if not found then
        U().squareSpecialObjects(square, function(object)
            if U().instanceOf(object, "IsoDoor") then found = object return true end
        end, 24)
    end
    return found
end

local function doorOpen(door)
    local value, called = U().call(door, "IsOpen")
    if not called then value, called = U().call(door, "isOpen") end
    if not called then return nil end
    return value == true
end

local function findBride(group)
    local reference = brideReferences[group.id]
    local referenceData = reference and U().modData(reference)
    if reference and U().isZombie(reference) and not U().isDead(reference)
        and type(referenceData) == "table"
        and referenceData[BRIDE_MARKER] == group.id then
        return reference
    end
    brideReferences[group.id] = nil
    local value = story(group)
    local point = value and value.site and value.site.vestry
    if type(point) ~= "table" then return nil end
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = U().gridSquare(point.x + dx, point.y + dy, point.z or 0)
            if square then
                U().squareMovingObjects(square, function(candidate)
                    if U().isZombie(candidate) and not U().isDead(candidate) then
                        local data = U().modData(candidate)
                        if type(data) == "table" and data[BRIDE_MARKER] == group.id then
                            brideReferences[group.id] = candidate
                            return true
                        end
                    end
                end, 20)
                if brideReferences[group.id] then return brideReferences[group.id] end
            end
        end
    end
    return nil
end

local function spawnBride(group, value)
    if value.brideSpawned == true or value.brideDead == true then
        return true, "bride_already_seeded"
    end
    local point = value.site and value.site.vestry
    if type(point) ~= "table" then return false, "vestry_unavailable" end
    local door = doorFor(value)
    if not door or doorOpen(door) ~= false then
        return false, "vestry_not_closed"
    end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square or not U().isSafeSpawnSquare(square) then
        return false, "vestry_square_unavailable"
    end
    if type(addZombiesInOutfit) ~= "function" then
        return false, "zombie_spawn_api_unavailable"
    end
    local ok, zombies = pcall(addZombiesInOutfit, point.x, point.y,
        point.z or 0, 1, "WeddingDress", 100)
    local bride = ok and zombies and U().listGet(zombies, 0) or nil
    if not bride or not U().isZombie(bride) then
        return false, "bride_spawn_failed"
    end
    local data = U().modData(bride)
    if type(data) ~= "table" then
        value.brideSpawned = true -- never create a second zombie after a partial spawn
        value.brideIssue = "bride_marker_unavailable"
        return false, value.brideIssue
    end
    data[BRIDE_MARKER] = group.id
    data.LF_OddballBride = true
    brideReferences[group.id] = bride
    value.brideSpawned = true
    return true, "bride_in_vestry"
end

local function ringIn(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 200, 12)
        or {}) do
        if U().itemType(item) == "Base.Ring_Left_RingFinger_Gold" then
            return item
        end
    end
    return nil
end

local function clergyNearby(player)
    if not player or not SC.Registry or type(SC.Registry.living) ~= "function" then
        return nil
    end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        local identity = record and record.identity or nil
        local background = record and (record.background
            or record.personality and record.personality.background) or nil
        local profession = type(background) == "table"
            and (background.profession or background.occupation) or nil
        if record and record.recruited == true
            and U().distance(actor, player) <= 8
            and (identity and identity.outfit == "Priest"
                or profession == "priest" or profession == "clergy") then
            return actor
        end
    end
    return nil
end

local function makeHostile(group, value, cause)
    if value.stage == "hostile" then return true, "already_hostile" end
    if value.stage == "married" or value.stage == "widowed" then
        return false, "ceremony_finished"
    end
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
        if not changed then return false, why or "standing_change_failed" end
    else
        group.standing, group.lifecycle = "Hostile", "hostile"
    end
    group.permanentHostility = true
    value.stage, value.hostileCause = "hostile", cause
    speak(group, "berserk")
    return true, "lonnie_berserk"
end

local function giveReception(value, player)
    if value.receptionGiven == true then return true end
    local altar = value.site and value.site.altar
    if not player or type(altar) ~= "table"
        or U().distance(player, altar) > 8 then return false end
    local inventory = U().inventory(player)
    if not inventory then return false end
    local items = { "Base.Champagne", "Base.Wine", "Base.CakeChocolate" }
    local progress = tonumber(value.receptionItems) or 0
    for index = progress + 1, #items do
        local item = U().addItem(inventory, items[index])
        if not item then return false end
        value.receptionItems = index
    end
    value.receptionGiven = true
    return true
end

function Lonnie.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "lonnie_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "lonnie_inventory_unavailable" end
    if value.axeSeeded ~= true then
        local found
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 100, 5)) do
            if U().itemType(item) == "Base.WoodAxe" then found = item break end
        end
        if not found then found = U().addItem(inventory, "Base.WoodAxe") end
        if not found then return false, "wood_axe_unavailable" end
        U().call(actor, "setPrimaryHandItem", found)
        value.axeSeeded = true
    end
    return spawnBride(group, value)
end

function Lonnie.onZombieDead(zombie)
    local data = zombie and U().modData(zombie)
    local id = type(data) == "table" and data[BRIDE_MARKER] or nil
    local group = id and SC.Factions and SC.Factions.group(id) or nil
    local value = story(group)
    if not value or value.brideDead == true then return false end
    value.brideDead = true
    brideReferences[group.id] = nil
    if value.stage == "ceremony" then
        local actor = Lonnie.actor(group)
        if not actor or U().isDead(actor) then
            value.stage = "married"
            return true, "bride_died_after_lonnie"
        end
    end
    return makeHostile(group, value, "bride_killed")
end

function Lonnie.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "married" then
        if giveReception(value, player) and SC.Oddballs
            and type(SC.Oddballs.retire) == "function" then
            SC.Oddballs.retire(group, "married")
        end
        return true, "wedding_concluded"
    end
    if value.stage == "ceremony" then
        local lead = group.members and group.members[1]
        local actor = Lonnie.actor(group)
        if lead and lead.alive == false or actor and U().isDead(actor) then
            value.stage = "married"
            if giveReception(value, player) and SC.Oddballs
                and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "married")
            end
            return true, "lonnie_died_happy"
        end
        local now = tonumber(current) or U().nowMs()
        local started = tonumber(value.ceremonyStartedAt) or now
        if not actor or now < started then
            value.ceremonyStartedAt = now
        elseif now - started >= 180000 then
            value.stage = "interrupted"
            for _, item in ipairs(U().inventoryItemsDeep(U().inventory(actor), 120, 6)) do
                if U().itemType(item) == "Base.WoodAxe" then
                    U().call(actor, "setPrimaryHandItem", item)
                    break
                end
            end
            speak(group, "interrupted")
            return true, "ceremony_interrupted_by_pathing"
        end
        local bride = findBride(group)
        if bride and actor then
            U().call(bride, "spotted", actor, true)
        end
        return true, "ceremony_in_progress"
    end
    if value.brideSpawned ~= true and value.brideDead ~= true
        and (tonumber(value.brideSpawnAttempts) or 0) < 3 then
        local spawned, reason = spawnBride(group, value)
        if not spawned and reason ~= "vestry_not_closed" then
            value.brideSpawnAttempts = (tonumber(value.brideSpawnAttempts) or 0) + 1
        end
    end
    local today = day()
    if today and value.stage == "refused"
        and today > (tonumber(value.refusedDay) or today) then
        value.stage = "invited"
        value.refusedDay = nil
        speak(group, "plea")
    end
    return true, value.stage
end

function Lonnie.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { priority = 110, kind = "faction", mode = "hostile",
            factionId = group.id }
    end
    if value.stage == "ceremony" then
        return { priority = 48, kind = "faction", mode = "lonnie_ceremony",
            factionId = group.id }
    end
    return { priority = 30, kind = "faction", mode = "lonnie_altar",
        factionId = group.id }
end

function Lonnie.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if intent and intent.mode == "hostile" then
        return false, "delegate_human_combat"
    end
    local target = value.stage == "ceremony" and findBride(group)
        or value.site and value.site.altar
    if target and U().distance(actor, target) > 1.5
        and SC.Navigation and type(SC.Navigation.request) == "function" then
        local square = U().squareOf(target)
            or U().gridSquare(target.x, target.y, target.z or 0)
        if square then
            return SC.Navigation.request(actor, square, "walk", {
                action = "lonnie_wedding", arrivalDistance = 1.2,
                targetSquare = square })
        end
    end
    U().stop(actor)
    return true, value.stage == "ceremony" and "awaiting_bride"
        or "waiting_at_altar"
end

function Lonnie.canRecruit(group)
    return false, story(group) and "lonnie_not_recruitable" or "wrong_oddball"
end

function Lonnie.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage == "hostile" or value.stage == "married" then
        return {}
    end
    local nearby = near(group, player)
    local today = day()
    local mayAsk = value.stage ~= "refused" or today
        and today > (tonumber(value.refusedDay) or today)
    local options = {
        { id = "greet", label = "Speak to Lonnie", enabled = nearby },
    }
    if value.stage == "interrupted" then
        options[#options + 1] = { id = "ceremony_interrupted",
            label = "The wedding was interrupted", enabled = false }
        return options
    end
    options[#options + 1] = { id = "ask_ceremony",
        label = "Ask about the ceremony", enabled = nearby and mayAsk }
    local altar = value.site and value.site.altar
    local inPlace = altar and player and U().distance(player, altar) <= 4
        and Lonnie.actor(group) and U().distance(Lonnie.actor(group), altar) <= 4
    if value.stage == "invited" or value.stage == "refused" and mayAsk then
        options[#options + 1] = { id = "perform_ceremony",
            label = "Say the vows and give Lonnie the ring",
            enabled = nearby and inPlace and ringIn(player) ~= nil
                and value.brideSpawned == true and value.brideDead ~= true,
            detail = "Requires a gold ring and both of you at the altar" }
        options[#options + 1] = { id = "refuse", label = "Decline for today",
            enabled = nearby }
    end
    return options
end

function Lonnie.action(group, action, player, payload)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then return makeHostile(group, value, "player_attack") end
    if value.stage == "hostile" or value.stage == "married" then
        return false, "story_finished"
    end
    if not near(group, player) then return false, "lonnie_too_far" end
    if action == "greet" then
        group.discovered = true
        speak(group, "greet")
        if value.reactionSpoken ~= true then
            value.reactionSpoken = true
            for _, fellow in ipairs(SC.Registry and SC.Registry.living
                and SC.Registry.living() or {}) do
                local record = SC.Registry.byId(U().idOf(fellow))
                if record and record.recruited and U().distance(fellow, player) <= 8 then
                    U().say(fellow, lines.fellow)
                    break
                end
            end
        end
        return true, "lonnie_greeted"
    elseif action == "ask_ceremony" then
        if value.stage == "interrupted" then
            return false, "ceremony_was_interrupted"
        end
        local today = day()
        if value.stage == "refused" and (not today
            or today <= (tonumber(value.refusedDay) or today)) then
            return false, "lonnie_waits_until_tomorrow"
        end
        value.stage = "invited"
        speak(group, "plea")
        return true, "vows_requested"
    elseif action == "refuse" then
        if value.stage ~= "invited" then return false, "no_invitation" end
        local today = day()
        if not today then return false, "game_time_unavailable" end
        value.stage, value.refusedDay = "refused", today
        speak(group, "refuse")
        return true, "lonnie_will_ask_tomorrow"
    elseif action == "perform_ceremony" then
        if value.stage ~= "invited" then return false, "ceremony_not_invited" end
        if value.brideDead == true or value.brideSpawned ~= true then
            return false, "bride_unavailable"
        end
        local actor = Lonnie.actor(group)
        local altar = value.site and value.site.altar
        if not altar or U().distance(player, altar) > 4
            or U().distance(actor, altar) > 4 then
            return false, "not_at_altar"
        end
        local ring = ringIn(player)
        if not ring then return false, "gold_ring_required" end
        local door = doorFor(value)
        if not door or doorOpen(door) ~= false then
            return false, "vestry_not_closed"
        end
        if not findBride(group) then return false, "bride_unloaded" end
        local source = select(1, U().call(ring, "getContainer"))
        local destination = U().inventory(actor)
        if not source or not destination then return false, "ring_container_unavailable" end
        local transferred, reason = U().transferItemVerified(source, destination, ring)
        if not transferred then return false, reason or "ring_transfer_failed" end
        local _, opened = U().call(door, "ToggleDoorActual", actor)
        if not opened or doorOpen(door) ~= true then
            U().transferItemVerified(destination, source, ring)
            return false, "vestry_door_would_not_open"
        end
        value.stage = "ceremony"
        value.ceremonyStartedAt = tonumber(U().nowMs()) or 0
        U().call(actor, "setPrimaryHandItem", nil)
        U().call(actor, "setSecondaryHandItem", nil)
        local priest = clergyNearby(player)
        if priest then U().say(priest, "Before us, and before God, let them make their vows.")
            speak(group, "clergy") end
        speak(group, "ceremony")
        return true, "ceremony_started"
    end
    return false, "unsupported_lonnie_action"
end

return Lonnie
