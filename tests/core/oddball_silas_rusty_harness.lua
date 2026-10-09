-- SPDX-License-Identifier: MIT
-- The church and theatre state machines, item ownership and death outcomes.

local SC = SurvivorCompanion
local Silas, Rusty = SC.OddballSilas, SC.OddballRusty
local checks, now = 0, 1000
local records, groups, worldDrops, releases = {}, {}, {}, {}
local failAdd

local function check(name, good)
    if not good then error("SILAS_RUSTY_FAIL " .. name, 2) end
    checks = checks + 1
end

local function inventory()
    local result = { items = {} }
    function result:AddItem(kind)
        local item = { kind = kind, container = self, data = {} }
        function item:getFullType() return self.kind end
        function item:getContainer() return self.container end
        function item:getModData() return self.data end
        function item:getMaxDamage() return self.weapon and 1 or nil end
        self.items[#self.items + 1] = item
        return item
    end
    function result:contains(item)
        for _, value in ipairs(self.items) do
            if value == item then return true end
        end
        return false
    end
    function result:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then
                table.remove(self.items, index)
                item.container = nil
                return
            end
        end
    end
    return result
end

local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0, inv = inventory(), alive = true }
    function value:getInventory() return self.inv end
    function value:getPrimaryHandItem() return self.primary end
    function value:getSecondaryHandItem() return self.secondary end
    function value:setPrimaryHandItem(item) self.primary = item end
    function value:setSecondaryHandItem(item) self.secondary = item end
    function value:playEmote(name) self.emote = name end
    function value:playSound(name) self.sound = name end
    function value:Say(line)
        self.lastLine = line
        self.sayCount = (self.sayCount or 0) + 1
    end
    return value
end

local player = actor("player", 12, 10)
local follower = actor("follower", 12, 11)
records.follower = { id = follower.id, actor = follower, recruited = true }

SC.Registry = {
    byId = function(id) return records[id] end,
    living = function() return { follower } end,
}
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local okay, result = pcall(object[method], object, ...)
        return okay and result or nil, okay
    end,
    idOf = function(value) return value and value.id end,
    position = function(value)
        return value and value.x, value and value.y, value and value.z or 0
    end,
    isValidActor = function(value) return value and value.alive == true end,
    distance = function(a, b)
        if not a or not b then return math.huge end
        local dx, dy = a.x - b.x, a.y - b.y
        return math.sqrt(dx * dx + dy * dy)
    end,
    canSee = function() return true end,
    say = function(value, line)
        if value.failSay == true then return false end
        value.lastLine = line
        value.sayCount = (value.sayCount or 0) + 1
        return true
    end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(container) return container and container.items or {} end,
    itemType = function(item) return item and item.kind end,
    instanceOf = function(item) return item and item.weapon == true end,
    hasMethod = function(item, method)
        return item and item.weapon == true and type(item[method]) == "function"
    end,
    containerContainsIdentity = function(container, item)
        return container:contains(item)
    end,
    addItem = function(container, kind)
        if kind == failAdd then return nil, "injected_add_failure" end
        return container:AddItem(kind)
    end,
    dropItem = function(source, square, item)
        if not source:contains(item) or not square then
            return false, "invalid_drop"
        end
        source:Remove(item)
        worldDrops[#worldDrops + 1] = { item = item, square = square }
        return true, item
    end,
    modData = function(value)
        if not value then return nil end
        value.data = value.data or {}
        return value.data
    end,
    nowMs = function() return now end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    stop = function() return true end,
    move = function() return true, "posed" end,
}
SC.Oddballs = {
    retire = function(group, reason)
        group.oddball.stage, group.oddball.retired = reason, true
        return true
    end,
}
SC.Relationship = { playEmote = function(a, name)
    a.emote = name
    return true
end }
SC.Factions = {
    forceStanding = function(id, standing)
        local group = groups[id]
        if not group then return false, "missing_group" end
        if group.permanentHostility and standing ~= "Hostile" then
            return false, "permanent_hostility"
        end
        group.standing = standing
        group.lifecycle = standing == "Hostile" and "hostile" or "settled"
        return true, standing
    end,
    adjustStanding = function(id, delta)
        local group = groups[id]
        group.reputation = group.reputation + delta
        return true, group.standing
    end,
    releaseOddballMember = function(id, key, order)
        local group = groups[id]
        for _, member in ipairs(group.members) do
            if member.key == key and member.alive ~= false
                and member.departed ~= true then
                local record = records[member.actorId]
                if not record then return false, "unloaded" end
                releases[#releases + 1] = { key = key, order = order }
                record.factionId = nil
                member.departed, member.actorId = true, nil
                return true, record.id
            end
        end
        return false, "missing_member"
    end,
}
SC.FactionRecruitment = {
    summary = function() return { status = "available" } end,
    ask = function() return true, "asked" end,
    startTrial = function() return true, "trial_started" end,
}

local function group(id, oddballId, memberCount)
    local members = {}
    for index = 1, memberCount do
        local identifier = id .. "-member-" .. tostring(index)
        local person = actor(identifier, 14 + index - 1, 10)
        records[identifier] = { id = identifier, actor = person,
            factionId = id, recruited = false }
        members[index] = { key = "member-" .. tostring(index),
            actorId = identifier, role = index == 1 and "leader" or "member",
            alive = true }
    end
    local result = {
        id = id, standing = "Wary", lifecycle = "settled",
        reputation = -20, members = members,
        oddball = { id = oddballId, stage = "unmet",
            site = { spawn = { x = 14, y = 10, z = 0 },
                altar = { x = 13, y = 11, z = 0 },
                house = { bounds = { x1 = 9, y1 = 8,
                    x2 = 20, y2 = 18 } } } },
    }
    groups[id] = result
    return result, records[members[1].actorId].actor
end

local cult, leader = group("cult", "cult_brother_silas", 3)
local silasSpawned, silasReason = Silas.onSpawn(cult, leader)
check("cult_gear_leader", silasSpawned == true
    and leader.primary.kind == "Base.Sword")
check("cult_gear_member", Silas.onSpawn(cult,
    records["cult-member-2"].actor) == true
    and records["cult-member-2"].actor.primary.kind == "Base.Machete")
Silas.onSpawn(cult, leader)
check("cult_loadout_idempotent", #leader.inv.items == 1)
Silas.pulse(cult, player, now)
check("cult_greets_once", cult.oddball.stage == "met"
    and follower.lastLine:find("praying", 1, true) ~= nil)
check("cult_never_hunts_sleepers", Silas.avoidsZombieCombat(leader, cult)
    == true and Silas.zombiesIgnore == nil
    and Silas.intentFor(leader, player, { threatCount = 2 }, cult).mode
        == "silas_church_guard")

local distant = { x = 80, y = 80, z = 0, data = {} }
check("distant_kill_ignored", Silas.onZombieDead(cult, distant, player, player)
    == false and cult.oddball.sleeperKills == 0)
local sleeper1 = { x = 16, y = 12, z = 0, data = {} }
check("nonparty_kill_ignored", Silas.onZombieDead(cult, sleeper1,
    actor("stranger", 16, 12), player) == false)
check("first_kill_warns", Silas.onZombieDead(cult, sleeper1, player,
    player) == true and cult.oddball.sleeperKills == 1
    and cult.standing == "Wary")
check("same_zombie_once", Silas.onZombieDead(cult, sleeper1, player,
    player) == false and cult.oddball.sleeperKills == 1)

local weapon = player.inv:AddItem("Base.Axe")
weapon.weapon = true
player.primary = weapon
failAdd = "Base.Candle"
check("confession_pending_on_reward_failure", Silas.action(cult,
    "confess", player) == false and #worldDrops == 1
    and player.primary == nil and cult.oddball.confessionPending == true
    and cult.oddball.nextReward == 2)
failAdd = nil
Silas.pulse(cult, player, now)
check("confession_reward_recovers_once", cult.oddball.confessionCompleted == true
    and #player.inv.items == 2
    and player.inv.items[1].kind == "Base.TinnedBeans"
    and player.inv.items[2].kind == "Base.Candle")
check("confession_cannot_duplicate", Silas.action(cult, "confess", player)
    == false and #worldDrops == 1 and #player.inv.items == 2)

local sleeper2 = { x = 17, y = 12, z = 0, data = {} }
check("second_kill_hostile", Silas.onZombieDead(cult, sleeper2,
    follower, player) == true and cult.standing == "Hostile"
    and cult.permanentHostility == true)
check("cult_still_avoids_sleepers_when_hostile",
    Silas.avoidsZombieCombat(leader, cult) == true
    and Silas.intentFor(leader, player, { threatCount = 2 }, cult).mode
        == "hostile")
check("cult_not_recruitable", Silas.canRecruit(cult) == false)

local aftermath = group("aftermath", "cult_brother_silas", 3)
aftermath.members[1].alive = false
check("leader_death_releases_both", Silas.pulse(aftermath, player, now) == true
    and aftermath.lifecycle == "destroyed" and #releases == 2)
check("split_flee_and_ask_join", releases[1].order == "wander"
    and releases[2].order == "stay")
local joinedCultist = records["aftermath-member-3"].actor
check("neutral_cultist_asks_once", joinedCultist.lastLine
    == "Silas is gone. Could I come with you?"
    and joinedCultist.sayCount == 1
    and aftermath.oddball.joinRequestSpoken["member-3"] == true)
Silas.pulse(aftermath, player, now)
check("death_release_idempotent", #releases == 2
    and joinedCultist.sayCount == 1)

local quiet = group("quiet", "cult_brother_silas", 2)
quiet.members[1].alive = false
records["quiet-member-2"].actor.failSay = true
local playerSaysBefore = player.sayCount or 0
Silas.pulse(quiet, player, now)
check("failed_survivor_voice_has_prompt", player.sayCount == playerSaysBefore + 1
    and player.lastLine == "A surviving cultist asks to join your group."
    and quiet.oddball.joinRequestSpoken["member-2"] == true)

local theatre, rusty = group("theatre", "ringmaster_rusty_pell", 1)
check("rusty_gear", Rusty.onSpawn(theatre, rusty) == true
    and rusty.primary.kind == "Base.Sledgehammer"
    and #rusty.inv.items == 3)
Rusty.onSpawn(theatre, rusty)
check("rusty_loadout_idempotent", #rusty.inv.items == 3)
player.x = 25
Rusty.pulse(theatre, player, now)
check("outside_theatre_no_show", theatre.oddball.stage == "unmet")
player.x = 12
Rusty.pulse(theatre, player, now)
check("first_show_starts", theatre.oddball.stage == "show_running"
    and theatre.oddball.showDeadlineAt == now + 60000
    and rusty.sound == "BlowWhistle")
check("applause_once", Rusty.action(theatre, "clap", player) == true
    and Rusty.action(theatre, "clap", player) == false
    and theatre.reputation == -10 and player.emote == "clap")
Rusty.pulse(theatre, player, now + 30000)
check("midpoint_line", rusty.lastLine:find("show isn't over", 1, true) ~= nil)
Rusty.pulse(theatre, player, now + 60000)
check("first_prize_once", theatre.oddball.completedShows == 1
    and theatre.oddball.stage == "intermission"
    and player.inv.items[3].kind == "Base.Bandage")
Rusty.pulse(theatre, player, now + 60001)
check("no_auto_second_show", theatre.oddball.completedShows == 1
    and theatre.oddball.stage == "intermission")

now = 62000
check("second_show_opt_in", Rusty.action(theatre, "show_again", player)
    == true and theatre.oddball.stage == "show_running")
failAdd = "Base.TinnedBeans"
Rusty.pulse(theatre, player, now + 60000)
check("failed_prize_is_pending", theatre.oddball.stage == "prize_pending"
    and theatre.oddball.completedShows == 1
    and theatre.oddball.prizePending == 2)
failAdd = nil
player.x = 25
Rusty.pulse(theatre, player, now + 60001)
check("prize_waits_for_return", theatre.oddball.completedShows == 1
    and theatre.oddball.prizePending == 2)
player.x = 12
Rusty.pulse(theatre, player, now + 60001)
check("second_prize_recovers_once", theatre.oddball.completedShows == 2
    and player.inv.items[4].kind == "Base.TinnedBeans")

now = 123000
Rusty.action(theatre, "show_again", player)
Rusty.pulse(theatre, player, now + 60000)
check("third_show_trusted", theatre.oddball.completedShows == 3
    and theatre.standing == "Trusted" and Rusty.canRecruit(theatre) == true
    and player.inv.items[5].kind == "Base.WaterBottle")
check("recruitment_offer", Rusty.action(theatre, "recruit", player)
    == true)
theatre.recruitment = { status = "joined" }
Rusty.pulse(theatre, player, now + 60001)
check("joining_retires_stage", theatre.oddball.stage == "recruited"
    and Rusty.canRecruit(theatre) == false)

local walked, walkedActor = group("walkout", "ringmaster_rusty_pell", 1)
Rusty.pulse(walked, player, now)
player.x = 25
Rusty.pulse(walked, player, now + 1000)
check("walking_out_hostile", walked.standing == "Hostile"
    and walked.oddball.stage == "hostile")
player.x = 12

local loaded = group("loaded", "ringmaster_rusty_pell", 1)
Rusty.pulse(loaded, player, now)
loaded.oddball.showSession = "previous-game"
now = now + 90000
Rusty.pulse(loaded, player, now)
check("load_restarts_show_not_hostile", loaded.standing ~= "Hostile"
    and loaded.oddball.showDeadlineAt == now + 60000)

print("Silas/Rusty contracts PASS: " .. tostring(checks) .. " checks")
