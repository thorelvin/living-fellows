-- SPDX-License-Identifier: MIT
-- Hollis keeps a real sow. Feeding remains vanilla; he notices when Duchess's
-- hunger falls, remembers the help, and never asks the engine to respawn her.

local SC = SurvivorCompanion
SC.OddballHollis = SC.OddballHollis or {}
local Hollis = SC.OddballHollis
local ID = "duchess_hollis_burkett"
local DUCHESS = { kind = "sow", breed = "landrace", name = "Duchess" }

local lines = {
    greet = { "Mind your manners. Duchess don't like loud voices.",
        "Mind your manners. Duchess doesn't like loud voices." },
    ribbons = { "Three blue ribbons. Smartest animal in Kentucky, Governor included.",
        "Three blue ribbons. Smartest animal in Kentucky, Governor included." },
    hungry = { "She ain't eaten since the screaming started. You any good with pigs?",
        "She hasn't eaten since the screaming started. You any good with pigs?" },
    fed = { "That's my girl. You have a kind hand, stranger.",
        "That's my girl. You have a kind hand, stranger." },
    harmed = { "You touched my girl. Now you deal with me.",
        "You touched my girl. Now you deal with me." },
    recruit = { "I'll walk with you. Duchess comes too. That's the deal.",
        "I'll walk with you. Duchess comes too. That's the deal." },
    grief = { "Three blue ribbons. Now I have an empty stall.",
        "Three blue ribbons. Now I have an empty stall." },
}

local function U() return SC.GameplayUtil end

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

local function speak(group, beat)
    local actor, choice = actorFor(group), lines[beat]
    if not actor or not choice then return false end
    return U().say(actor, choice[U().config("profanityEnabled") == false
        and 2 or 1]) == true
end

local function near(group, player, radius)
    local actor = actorFor(group)
    local ax, ay, az = U().position(actor)
    local px, py, pz = U().position(player)
    if not ax or not px or az ~= pz then return false end
    return (ax - px) ^ 2 + (ay - py) ^ 2 <= radius * radius
end

local function worldDay()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local hour = time and number(select(1,
        U().call(time, "getWorldAgeHours"))) or nil
    return hour and math.floor(hour / 24) or nil
end

local function ensureDuchess(group, value)
    local pen = value.site and value.site.coop
    if not pen or pen.enclosed ~= true then return false, "pen_not_enclosed" end
    local records = value.animals and value.animals.slots
    if records and records[1] then return true, "duchess_already_seeded" end
    return SC.OddballAnimals.spawn(group, 1, DUCHESS, pen)
end

local function animalHunger(animal)
    local amount = number(select(1, U().call(animal, "getHunger")))
    if amount ~= nil then return amount end
    local stats = select(1, U().call(animal, "getStats"))
    return number(select(1, U().call(stats, "getHunger")))
end

local function hostile(group, value)
    if value.stage == "hostile" then return true end
    value.stage = "hostile"
    SC.Factions.forceStanding(group.id, "Hostile")
    speak(group, "harmed")
    return true
end

function Hollis.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "hollis_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "hollis_inventory_unavailable" end
    local bat
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == "Base.BaseballBat" then bat = item break end
    end
    if not bat and value.equipmentSeeded ~= true then
        bat = U().addItem(inventory, "Base.BaseballBat")
    end
    if bat then U().call(actor, "setPrimaryHandItem", bat) end
    value.equipmentSeeded = bat ~= nil or value.equipmentSeeded
    ensureDuchess(group, value)
    return true, "hollis_ready"
end

function Hollis.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "unmet" and near(group, player, 12) then
        value.stage = "met"
        group.discovered = true
        speak(group, "greet")
    end
    local animalState, duchess = SC.OddballAnimals.status(group, 1, player)
    if animalState == "unseeded" then
        local day = worldDay() or 0
        if day >= (number(value.nextPenRetryDay) or 0) then
            value.nextPenRetryDay = day + 1
            ensureDuchess(group, value)
        end
    elseif animalState == "dead" and value.stage ~= "hostile" then
        value.stage = "hostile"
        SC.Factions.forceStanding(group.id, "Hostile")
        speak(group, "grief")
    elseif animalState == "alive" and value.stage ~= "hostile" then
        local hunger = animalHunger(duchess)
        local day = worldDay()
        if hunger and value.lastHunger and hunger < value.lastHunger - 0.08
            and day and value.lastFedDay ~= day
            and near(group, player, 12) then
            value.lastFedDay = day
            SC.Factions.adjustStanding(group.id, 15, "duchess_fed")
            speak(group, "fed")
        end
        if hunger then value.lastHunger = hunger end
        SC.OddballAnimals.follow(group, 1, actorFor(group), current)
    end
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id)
    if recruitment and recruitment.status == "joined" then
        value.stage = "recruited"
    end
    return true, value.stage
end

function Hollis.pulseRecruited(group, actor, player, current)
    return SC.OddballAnimals.follow(group, 1, actor, current)
end

function Hollis.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value or value.stage == "recruited" then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "hollis_stall", priority = 30 }
end

function Hollis.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "hollis_stall" then return false end
    local pen = story(group).site and story(group).site.coop
    if not pen then return true, "stall_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (pen.z or 0) and (x - pen.x) ^ 2
        + (y - pen.y) ^ 2 <= 6.25 then
        return true, "watching_duchess"
    end
    local square = U().gridSquare(pen.x, pen.y, pen.z or 0)
    if not square then return true, "stall_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_animal_keeper", arrivalDistance = 2.5 })
end

function Hollis.canRecruit(group)
    local value = story(group)
    if not value or group.standing ~= "Trusted" then
        return false, "earn_hollis_trust"
    end
    local alive = SC.OddballAnimals.find(group, 1)
    return alive ~= nil, alive and "duchess_comes_too" or "duchess_missing"
end

function Hollis.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local nearby = near(group, player, 5)
    local canJoin, reason = Hollis.canRecruit(group)
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id) or nil
    if recruitment and recruitment.status == "joined" then return {} end
    local options = {
        { id = "ask_duchess", label = "Ask about Duchess", enabled = nearby,
            detail = "Hollis's prize sow lives in the barn" },
        { id = "recruit", label = "Ask Hollis and Duchess to come along",
            enabled = nearby and canJoin and value.stage ~= "hostile",
            detail = canJoin and "Duchess follows Hollis through the vanilla animal path"
                or reason },
    }
    if recruitment and recruitment.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Ask Hollis for his decision",
            enabled = nearby and recruitment.canDecide == true }
    end
    return options
end

function Hollis.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        hostile(group, value)
        return true, "hollis_defends_duchess"
    end
    if action == "ask_duchess" then
        if not near(group, player, 5) then return false, "too_far_away" end
        speak(group, "ribbons")
        return true, "duchess_introduced"
    end
    if action == "recruit" then
        if not near(group, player, 5) then return false, "too_far_away" end
        local allowed, reason = Hollis.canRecruit(group)
        if not allowed then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = SC.FactionRecruitment.summary(group.id)
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, askReason end
        end
        local started, startReason = SC.FactionRecruitment.startTrial(
            group.id, player, false)
        if not started then return false, startReason end
        value.recruitmentStarted = true
        speak(group, "recruit")
        return true, startReason or "trial_started"
    end
    if action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unsupported_hollis_action"
end

return Hollis
