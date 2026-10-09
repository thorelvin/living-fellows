-- SPDX-License-Identifier: MIT
-- Earl sets his own fuel-lined room alight when a player takes a scene can.
local SC = SurvivorCompanion
SC.OddballPyromaniac = SC.OddballPyromaniac or {}
local Pyro = SC.OddballPyromaniac
local ID = "pyromaniac_earl_kessler"
local FUEL = "Base.PetrolCan"
local THREATS = {
    "Those cans stay where they are. Every one of them.",
    "I counted the cans twice. I'll know if one walks away.",
    "This place is full of old ghosts. The gasoline keeps them quiet.",
}
local CURSES = {
    "Thieving bastard! You want my fuel? Then watch it burn!",
    "You stole from me! Damn you. I'll light the whole bloody room!",
    "Hands off my cans! Too late now. Fire takes the lot of us!",
}
local LAUGHS = {
    "Ha! Ha! That's a fine bright ending!",
    "Look at it go! Ha ha ha!",
    "Burn, you miserable old walls! Ha!",
    "Ha ha! At least this house knows how to keep me warm!",
}
local AFTER = {
    "I thought the fire would finish me. Somehow it didn't.",
    "I can still smell the smoke when there isn't any.",
    "I don't feel much like laughing now.",
}

local function U() return SC.GameplayUtil end
local function story(group)
    local value = group and group.oddball
    return type(value) == "table" and value.id == ID and value or nil
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function postSquare(post)
    return post and U().gridSquare(post.x, post.y, post.z or 0) or nil
end
local function near(actor, player, radius)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function logFailure(group, detail)
    local value = story(group)
    if value and value.lastPyroFailure == detail then return end
    if value then value.lastPyroFailure = detail end
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("oddballs", group.id,
            "pyromaniac scene could not start", tostring(detail))
    end
end

local function seedFuel(group)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    value.fuelSpawned = value.fuelSpawned or {}
    local count = 0
    for index, post in ipairs(value.site.fuelPosts or {}) do
        if value.fuelSpawned[index] == true then
            count = count + 1
        else
            local square = postSquare(post)
            local worldItem = square and select(1, U().call(square,
                "AddWorldInventoryItem", FUEL, 0.45, 0.45, 0)) or nil
            local item = worldItem and select(1, U().call(worldItem, "getItem"))
            local data = item and U().modData(item)
            if data then
                data.lfPyroFuelGroupId = group.id
                data.lfPyroFuelIndex = index
                value.fuelSpawned[index] = true
                count = count + 1
            else
                logFailure(group, "fuel can " .. tostring(index) .. " unavailable")
            end
        end
    end
    return count >= 2, count >= 2 and "fuel_seeded" or "fuel_seed_failed"
end

local function players(player)
    local result, seen = {}, {}
    if player then result[1], seen[player] = player, true end
    if type(getSpecificPlayer) == "function" then
        local count = 1
        if type(getNumActivePlayers) == "function" then
            local okay, active = pcall(getNumActivePlayers)
            if okay then count = math.max(1, math.min(4, tonumber(active) or 1)) end
        end
        for index = 0, count - 1 do
            local okay, candidate = pcall(getSpecificPlayer, index)
            if okay and candidate and not seen[candidate] then
                result[#result + 1], seen[candidate] = candidate, true
            end
        end
    end
    return result
end

local function stolenCan(group, player)
    for _, candidate in ipairs(players(player)) do
        local inventory = U().inventory(candidate)
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 400, 24)) do
            if U().itemType(item) == FUEL then
                local data = U().modData(item)
                if data and data.lfPyroFuelGroupId == group.id then
                    return candidate, item
                end
            end
        end
    end
    return nil
end

local function houseFire(group)
    local value = story(group)
    local bounds = value and value.site and value.site.house
        and value.site.house.bounds or group.house and group.house.bounds
    if type(bounds) ~= "table" then return true end
    local x1, x2 = tonumber(bounds.x1), tonumber(bounds.x2)
    local y1, y2 = tonumber(bounds.y1), tonumber(bounds.y2)
    if not x1 or not x2 or not y1 or not y2 then return true end
    -- Bounded scan; a large commercial building cannot stall a frame.
    if (x2 - x1 + 1) * (y2 - y1 + 1) > 900 then return true end
    local floor = math.floor(tonumber(value.site.spawn.z) or 0)
    for z = math.max(0, floor - 1), math.min(7, floor + 1) do
        for x = x1, x2 do
            for y = y1, y2 do
                local square = U().gridSquare(x, y, z)
                if square and select(1, U().call(square, "haveFire")) == true then
                    return true
                end
            end
        end
    end
    return false
end

local function raiseUnhappiness(actor)
    if not actor or not CharacterStat or not CharacterStat.UNHAPPINESS then
        return false end
    local stats = select(1, U().call(actor, "getStats"))
    if not stats then return false end
    local level = select(1, U().call(stats, "get",
        CharacterStat.UNHAPPINESS))
    level = tonumber(level) or 0
    return select(2, U().call(stats, "set", CharacterStat.UNHAPPINESS,
        math.max(level, 70))) == true
end

local function ignite(group, actor, current)
    local value = story(group)
    if value.stage ~= "warning" then return false, "not_primed" end
    if not IsoFireManager or type(getCell) ~= "function" then
        logFailure(group, "native fire API unavailable")
        return false, "native_fire_unavailable"
    end
    local cell = getCell()
    local lit = 0
    for _, post in ipairs(value.site.fuelPosts or {}) do
        local square = postSquare(post)
        if square then
            local okay = pcall(function()
                IsoFireManager.StartFire(cell, square, true, 100, 500)
            end)
            if okay then lit = lit + 1 end
        end
    end
    if lit == 0 then
        logFailure(group, "fuel squares unloaded or fire start rejected")
        return false, "fuel_fire_unavailable"
    end
    value.stage = "burning"
    value.ignitedAt = current
    value.nextLaughAt = current
    value.clearSince = nil
    group.discovered = true
    U().say(actor, LAUGHS[1])
    value.laughIndex = 1
    value.nextLaughAt = current + 5500
    return true, "house_ignited"
end

function Pyro.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "pyromaniac_unavailable" end
    if value.stage == "survived" then
        raiseUnhappiness(actor)
        return true, "survivor_returned"
    end
    if value.stage == "burning" or value.stage == "warning" then
        return true, "scene_already_triggered"
    end
    SC.Factions.forceStanding(group.id, "Tolerated")
    return seedFuel(group)
end

function Pyro.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "pyromaniac_unloaded_or_dead" end
    if value.stage == "unmet" then
        if not value.fuelSpawned or #value.fuelSpawned < 2 then seedFuel(group) end
        if near(actor, player, 8)
            and current >= (tonumber(value.nextThreatAt) or 0) then
            local index = ((tonumber(value.threatIndex) or 0) % #THREATS) + 1
            value.threatIndex = index
            value.nextThreatAt = current + 38000
            group.discovered = true
            U().say(actor, THREATS[index])
        end
        local thief = stolenCan(group, player)
        if thief then
            value.stage = "warning"
            value.igniteAt = current + 1800
            group.discovered = true
            local index = (U().stableHash(group.id) % #CURSES) + 1
            U().say(actor, CURSES[index])
        end
    elseif value.stage == "warning" and current >= (value.igniteAt or 0) then
        local lit, reason = ignite(group, actor, current)
        if not lit then value.igniteAt = current + 5000 end
        return lit, reason
    elseif value.stage == "burning" then
        if current >= (tonumber(value.nextLaughAt) or 0) then
            local index = ((tonumber(value.laughIndex) or 0) % #LAUGHS) + 1
            U().say(actor, LAUGHS[index])
            value.laughIndex = index
            value.nextLaughAt = current + 6000
        end
        if current - (tonumber(value.ignitedAt) or current) >= 25000
            and current >= (tonumber(value.nextFireCheckAt) or 0) then
            value.nextFireCheckAt = current + 5000
            if houseFire(group) then
                value.clearSince = nil
            else
                value.clearSince = value.clearSince or current
                if current - value.clearSince >= 10000 then
                    value.stage = "survived"
                    value.depressed = true
                    raiseUnhappiness(actor)
                    SC.Factions.forceStanding(group.id, "Trusted")
                    U().say(actor, AFTER[1])
                    value.nextAfterAt = current + 90000
                    return true, "survived_the_fire"
                end
            end
        end
    elseif value.stage == "survived" and player and near(actor, player, 8)
        and current >= (tonumber(value.nextAfterAt) or 0) then
        local index = ((tonumber(value.afterIndex) or 0) % #AFTER) + 1
        U().say(actor, AFTER[index])
        value.afterIndex = index
        value.nextAfterAt = current + 90000
    end
    return true, value.stage
end

function Pyro.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "warning" or value.stage == "burning" then
        return { mode = "pyromaniac_stay", priority = 170 }
    end
    local threats = snapshot and (tonumber(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Pyro.update(actor, player, runtime, intent, group)
    if not story(group) or not intent or intent.mode ~= "pyromaniac_stay" then
        return false, "not_holding_room" end
    U().stop(actor)
    return true, "stays_with_the_fire"
end

function Pyro.canRecruit(group)
    local value = story(group)
    return value and value.stage == "survived" and value.depressed == true
        and group.standing == "Trusted" or false,
        "survive_the_fire_first"
end

function Pyro.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not near(actor, player, 7) then return {} end
    if value.stage == "survived" then
        return { { id = "recruit", label = "Ask Earl to leave the ashes with you",
            enabled = Pyro.canRecruit(group) == true } }
    end
    return { { id = "ask_cans", label = "Ask Earl about the gasoline",
        enabled = value.stage == "unmet" } }
end

function Pyro.action(group, action, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        if actor then U().say(actor, "Leave me alone with my fire!") end
        return true, "pyromaniac_not_chasing"
    end
    if not near(actor, player, 7) then return false, "pyromaniac_too_far" end
    if action == "ask_cans" and value.stage == "unmet" then
        U().say(actor, "Mine. You leave them alone and I leave you alone.")
        return true, "fuel_warning"
    elseif action == "recruit" and Pyro.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "pyromaniac_action_unavailable"
end

function Pyro.pulseRecruited(group, actor, player, current)
    local value = story(group)
    if not value or value.depressed ~= true then return false end
    if value.recruitedMoodApplied ~= true then
        value.recruitedMoodApplied = raiseUnhappiness(actor)
    end
    if player and current >= (tonumber(value.nextRecruitedLineAt) or 0) then
        value.nextRecruitedLineAt = current + 240000
        local index = ((tonumber(value.recruitedLineIndex) or 0) % #AFTER) + 1
        value.recruitedLineIndex = index
        U().say(actor, AFTER[index])
    end
    return true, "depressed_survivor"
end

return Pyro
