-- SPDX-License-Identifier: MIT
-- Belle is a native cow; feeding is vanilla. Tommy's race is resolved from
-- two actual positions on a loaded road, not a simulated timer.

local SC = SurvivorCompanion
SC.OddballTommy = SC.OddballTommy or {}
local Tommy = SC.OddballTommy
local ID = "tommy_two_lengths"
local BELLE = { kind = "cow", breed = "simmental",
    name = "Bourbon Belle" }

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "training_belle"
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function ageDay()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local raw = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(raw) and math.floor(raw / 24) or nil
end
local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        120, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function hunger(animal)
    local value = select(1, U().call(animal, "getHunger"))
    if tonumber(value) then return tonumber(value) end
    local stats = select(1, U().call(animal, "getStats"))
    local fallback = stats and select(1, U().call(stats, "getHunger"))
    return tonumber(fallback)
end

function Tommy.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "tommy_unavailable" end
    local inventory = U().inventory(actor)
    if value.gearSeeded ~= true and inventory then
        local bat = itemFor(actor, "Base.ShortBat")
            or U().addItem(inventory, "Base.ShortBat")
        local bourbon = U().addItem(inventory, "Base.Whiskey")
        if bat and bourbon then
            U().call(actor, "setPrimaryHandItem", bat)
            value.gearSeeded = true
        end
    end
    if SC.OddballAnimals.status(group, 1) == "unseeded" then
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, BELLE, post) end
    end
    return true, "tommy_and_belle_ready"
end

function Tommy.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "jockey_unloaded" end
    if SC.OddballAnimals.status(group, 1) == "unseeded"
        and current >= (tonumber(value.nextBelleRetryAt) or 0) then
        value.nextBelleRetryAt = current + 30000
        local post = value.site and value.site.animalSpawns
            and value.site.animalSpawns[1]
        if post then SC.OddballAnimals.spawn(group, 1, BELLE, post) end
    end
    if near(group, player, 8) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "Seen a horse? Any horse? Fourteen years a jockey, and I'm training Belle instead.")
    end
    local cow = SC.OddballAnimals.find(group, 1)
    if cow then
        local amount = hunger(cow)
        local day = ageDay()
        if amount and value.lastHunger and day
            and amount < value.lastHunger - 0.08
            and day ~= value.lastFedDay then
            value.feedStreak = value.lastFedDay == day - 1
                and (tonumber(value.feedStreak) or 0) + 1 or 1
            value.lastFedDay = day
            SC.Factions.adjustStanding(group.id, 12, "belle_really_fed")
            U().say(actor,
                "That's it, girl. Three good meals and she'll run like a thoroughbred. Spiritually.")
            if value.feedStreak >= 3 and value.derbyComplete ~= true then
                value.derbyComplete = true
                value.stage = "derby_day"
                SC.Factions.forceStanding(group.id, "Trusted")
                U().say(actor,
                    "And down the stretch comes Bourbon Belle! Eventually! Any minute now!")
                U().say(actor,
                    "Derby's done. I'll come with you, if Belle gets the good seat.")
            end
        end
        if amount then value.lastHunger = amount end
        SC.OddballAnimals.follow(group, 1, actor, current)
    end
    if value.race and value.race.active then
        local post = value.site and value.site.racePost
        if post then
            local runnerDistance = U().distance(actor, post)
            local playerDistance = player and U().distance(player, post)
            if playerDistance and playerDistance <= 2.5 then
                value.race.active = false
                value.race.winner = "player"
                U().say(actor,
                    "Beat by a civilian. Don't you dare tell Belle. Fine run, though.")
                SC.Factions.adjustStanding(group.id, 10, "real_race_won")
            elseif runnerDistance and runnerDistance <= 2.5 then
                value.race.active = false
                value.race.winner = "tommy"
                U().say(actor,
                    "Two lengths! Told you. Belle's got the real talent, though.")
            elseif current - value.race.startedAt > 300000 then
                value.race.active = false
                value.race.winner = "no_finish"
                U().say(actor, "Road's no good today. We'll try again tomorrow.")
            end
        end
    end
    return true, value.stage
end

function Tommy.pulseRecruited(group, actor, player, current)
    return SC.OddballAnimals.follow(group, 1, actor, current)
end

function Tommy.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.race and value.race.active then
        return { mode = "tommy_race", priority = 65 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Tommy.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "tommy_race" then
        return false, "jockey_idle"
    end
    local post = story(group).site.racePost
    local destination = U().gridSquare(post.x, post.y, post.z or 0)
    if not destination or not SC.Navigation then
        return false, "race_road_unloaded"
    end
    return SC.Navigation.request(actor, destination, "run", {
        action = "jockey_footrace", arrivalDistance = 1.5 })
end

function Tommy.canRecruit(group)
    local value = story(group)
    return value and value.derbyComplete == true
        and group.standing == "Trusted" or false,
        "feed_belle_three_days_running"
end

function Tommy.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7) then return {} end
    local day = ageDay()
    return {
        { id = "ask_horse", label = "Ask Tommy about horses",
            enabled = true },
        { id = "race", label = "Race Tommy to the road marker",
            enabled = day ~= nil and value.lastRaceDay ~= day
                and not (value.race and value.race.active),
            detail = value.site.racePost and
                (value.site.racePost.x .. ", " .. value.site.racePost.y) or nil },
        { id = "recruit", label = "Ask Tommy and Belle to join",
            enabled = Tommy.canRecruit(group) == true },
    }
end

function Tommy.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player, 7) then return false, "jockey_too_far" end
    local actor = actorFor(group)
    if action == "ask_horse" then
        U().say(actor,
            "Not one horse left in Kentucky. Belle's a thoroughbred. Spiritually.")
        return true, "horse_tale_told"
    end
    if action == "race" then
        local day = ageDay()
        local post = value.site and value.site.racePost
        if not day or value.lastRaceDay == day or not post
            or not U().gridSquare(post.x, post.y, post.z or 0) then
            return false, "race_not_available_today"
        end
        value.lastRaceDay = day
        value.race = { active = true, startedAt = U().nowMs() }
        U().say(actor, "Race you to the road. Loser buys the bourbon. Go!")
        return true, "real_footrace_started"
    end
    if action == "recruit" and Tommy.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        local started, startReason = SC.FactionRecruitment.startTrial(
            group.id, player, false)
        if started and value.leashGiven ~= true then
            local leash = U().addItem(U().inventory(player), "Base.Leash")
            if leash then value.leashGiven = true end
        end
        return started, startReason
    end
    return false, "jockey_choice_unavailable"
end

return Tommy
