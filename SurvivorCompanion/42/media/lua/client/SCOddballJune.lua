-- SPDX-License-Identifier: MIT
-- June keeps ten real, individually named vanilla rabbits. Their native IDs
-- survive saves; a missing animal never turns into a replacement copy.

local SC = SurvivorCompanion
SC.OddballJune = SC.OddballJune or {}
local June = SC.OddballJune
local ID = "ranger_june_whitlock"
local RABBITS = {
    { kind = "rabbuck", name = "Sergeant Fluffington" },
    { kind = "rabdoe", name = "Biscuit" },
    { kind = "rabdoe", name = "Clover" },
    { kind = "rabdoe", name = "Dandelion" },
    { kind = "rabdoe", name = "Butterbean" },
    { kind = "rabdoe", name = "Pickles" },
    { kind = "rabkitten", name = "Juniper" },
    { kind = "rabkitten", name = "Nutmeg" },
    { kind = "rabkitten", name = "Waffles" },
    { kind = "rabkitten", name = "Cottonball" },
}
local GREENS = { ["Base.Carrots"] = true, ["Base.Lettuce"] = true,
    ["Base.Cabbage"] = true }
local GAME = { ["Base.Venison"] = true, ["Base.DeerHide"] = true }
local DANGER = { ["Base.Rabbitmeat"] = true }
local nextLineAt = {}

local lines = {
    greet = "State forest. You're in it. That makes you my problem.",
    babies = "Ten rabbits. Ten names. You'll learn them, or you'll leave.",
    feed = "Hands where I can see 'em. Sorry, Biscuit, Mama's working.",
    quiz = "The rabbit nearest your boots. What's that one's name?",
    correct = "Good. You paid attention. Sergeant, did you hear that?",
    wrong = "Wrong. That's a living creature, not a guessing game.",
    lost = "Juniper got out again. She's little, she's dumb and I love her. Find her.",
    found = "There you are, little fool. Come home. Thank you for finding her.",
    gone = "I kept calling. Nothing came back. Don't ask me about her.",
    rabbit = "You hurt one of mine. Start running. I'll count to ten.",
    meat = "Get out. Get out of my cabin, and take that with you.",
    trade = "Deer, not rabbit. I have rules, even now.",
    join = "Fine. But the babies ride in the back, and the back gets a blanket.",
    grief = "I know all ten names. I still say every one at night.",
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
    local actor = actorFor(group)
    return actor and U().say(actor, lines[beat]) == true or false
end

local function dayHour()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local hour = time and number(select(1,
        U().call(time, "getWorldAgeHours"))) or nil
    return hour and math.floor(hour / 24), hour
end

local function near(group, player, radius)
    local actor = actorFor(group)
    local ax, ay, az = U().position(actor)
    local px, py, pz = U().position(player)
    return ax and px and az == pz
        and (ax - px) ^ 2 + (ay - py) ^ 2 <= radius * radius
end

local function itemIn(actor, kinds)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 12)
        or {}) do
        if kinds[U().itemType(item)] then return item end
    end
    return nil
end

local function animalHunger(animal)
    local value = number(select(1, U().call(animal, "getHunger")))
    if value then return value end
    local stats = select(1, U().call(animal, "getStats"))
    return number(select(1, U().call(stats, "getHunger")))
end

local function hostile(group, value, beat)
    if value.stage == "hostile" then return true end
    value.stage = "hostile"
    SC.Factions.forceStanding(group.id, "Hostile")
    speak(group, beat or "rabbit")
    return true
end

local function allAlive(group)
    for slot = 1, #RABBITS do
        if not SC.OddballAnimals.find(group, slot) then
            return false, "rabbit_missing_" .. tostring(slot)
        end
    end
    return true, "all_ten_rabbits_present"
end

local function rabbitNearestPlayer(group, player)
    local px, py, pz = U().position(player)
    if not px then return nil end
    local closest, distance
    for slot = 1, #RABBITS do
        local animal = SC.OddballAnimals.find(group, slot)
        local x, y, z = U().position(animal)
        if x and z == pz then
            local squared = (x - px) ^ 2 + (y - py) ^ 2
            if squared <= 36 and (not distance or squared < distance) then
                closest, distance = slot, squared
            end
        end
    end
    return closest
end

local function seedAnimals(group, value)
    local points = value.site and value.site.animalSpawns
    if type(points) ~= "table" or #points ~= #RABBITS then
        return false, "rabbit_room_unavailable"
    end
    for slot, rabbit in ipairs(RABBITS) do
        local okay, reason = SC.OddballAnimals.spawn(group, slot,
            { kind = rabbit.kind, breed = "swamp", name = rabbit.name },
            points[slot])
        if not okay then return false, reason end
    end
    return true, "ten_rabbits_seeded"
end

local function escapeTarget(value, animal, player)
    local ax, ay, az = U().position(animal)
    if not ax or az ~= 0 then return nil end
    local bounds = value.site and value.site.house and value.site.house.bounds
    for radius = 40, 80, 8 do
        for _, direction in ipairs({ {1,0}, {0,1}, {-1,0}, {0,-1},
                {1,1}, {-1,1}, {-1,-1}, {1,-1} }) do
            local x = math.floor(ax + direction[1] * radius)
            local y = math.floor(ay + direction[2] * radius)
            if not bounds or x < bounds.x1 - 8 or x > bounds.x2 + 8
                or y < bounds.y1 - 8 or y > bounds.y2 + 8 then
                local square = U().gridSquare(x, y, 0)
                if square and U().isSafeSpawnSquare(square)
                    and select(1, U().call(square, "getRoom")) == nil
                    and U().canSee(player, square) ~= true then
                    return { x = x, y = y, z = 0 }
                end
            end
        end
    end
    return nil
end

local function startEscape(group, value, player, hour)
    if value.juniper or not hour or hour < (value.spawnHour or hour) + 48
        or value.stage == "hostile" or value.stage == "recruited" then
        return false, "escape_not_due"
    end
    local animal = SC.OddballAnimals.find(group, 7)
    if not animal then return false, "juniper_unavailable" end
    local point = escapeTarget(value, animal, player)
    if not point then return false, "no_loaded_woodland" end
    -- A native path request is required. If this build cannot path animals to
    -- a world tile, the escape does not begin or claim to have happened.
    local _, requested = U().call(animal, "pathToLocation",
        point.x, point.y, 0)
    if not requested then return false, "animal_path_unavailable" end
    value.juniper = { stage = "escaping", target = point,
        startedHour = hour, deadlineHour = hour + 72 }
    return true, "juniper_escape_started"
end

local function updateEscape(group, value, player, hour)
    local quest = value.juniper
    if type(quest) ~= "table" then return end
    if quest.stage == "home" or quest.stage == "gone" then return end
    local animal = SC.OddballAnimals.find(group, 7)
    if not animal then
        if hour and hour >= (quest.deadlineHour or math.huge) then
            quest.stage = "gone"
            speak(group, "gone")
        end
        return
    end
    local ax, ay, az = U().position(animal)
    local home = value.site and value.site.spawn
    if quest.stage == "escaping" and ax and home and az == 0
        and (ax - home.x) ^ 2 + (ay - home.y) ^ 2 >= 35 * 35 then
        quest.stage = "lost"
        speak(group, "lost")
    end
    if quest.stage == "escaping" and hour
        and hour - (quest.startedHour or hour) >= 3 then
        -- The native animal path could not get through a closed door. No
        -- escape happened, so allow a later attempt when the room opens.
        value.juniper = nil
        value.spawnHour = hour - 42
        return
    end
    if quest.stage ~= "lost" and quest.stage ~= "found" then return end
    if quest.stage == "lost" and hour
        and hour >= (quest.deadlineHour or math.huge) then
        quest.stage = "gone"
        speak(group, "gone")
        return
    end
    local px, py, pz = U().position(player)
    if quest.stage == "lost" and px and ax and pz == az
        and (px - ax) ^ 2 + (py - ay) ^ 2 <= 16 then
        quest.stage = "found"
        SC.Factions.adjustStanding(group.id, 30, "juniper_found")
        speak(group, "found")
    end
    if quest.stage == "found" then
        local keeper = actorFor(group)
        local kx, ky, kz = U().position(keeper)
        if kx and ax and kz == az and SC.Navigation
            and type(SC.Navigation.request) == "function" then
            local square = U().gridSquare(math.floor(ax), math.floor(ay), az)
            if square and (kx - ax) ^ 2 + (ky - ay) ^ 2 > 9 then
                SC.Navigation.request(keeper, square, "walk", {
                    action = "faction_juniper_rescue", arrivalDistance = 2.5 })
            else
                SC.OddballAnimals.follow(group, 7, keeper, U().nowMs())
            end
            if home and (ax - home.x) ^ 2 + (ay - home.y) ^ 2 <= 64 then
                quest.stage = "home"
            end
        end
    end
end

function June.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "june_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "june_inventory_unavailable" end
    local rifle = itemIn(actor, { ["Base.HuntingRifle"] = true })
    if not rifle and value.equipmentSeeded ~= true then
        rifle = U().addItem(inventory, "Base.HuntingRifle")
    end
    if rifle then U().call(actor, "setPrimaryHandItem", rifle) end
    if value.equipmentSeeded ~= true and rifle then
        U().addItem(inventory, "Base.HuntingKnife")
        U().addItem(inventory, "Base.Venison")
        U().addItem(inventory, "Base.DeerHide")
        U().addItem(inventory, "Base.308Box")
        value.equipmentSeeded = true
    end
    local _, hour = dayHour()
    value.spawnHour = value.spawnHour or hour
    return seedAnimals(group, value)
end

function June.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local day, hour = dayHour()
    if value.stage == "unmet" and near(group, player, 12) then
        value.stage = "met"
        group.discovered = true
        speak(group, "greet")
    end
    if value.stage == "hostile" then return true, "june_hostile" end
    local slots = value.animals and value.animals.slots
    if not slots or #slots < #RABBITS then
        if day and day >= (value.nextSeedRetryDay or 0) then
            value.nextSeedRetryDay = day + 1
            seedAnimals(group, value)
        end
    end
    local last = value.lastHunger or {}
    value.lastHunger = last
    for slot = 1, #RABBITS do
        local status, rabbit = SC.OddballAnimals.status(group, slot, player)
        if status == "dead" and not value.grievedSlot then
            value.grievedSlot = slot
            value.griefDay = day
            speak(group, "grief")
        elseif status == "alive" then
            local hunger = animalHunger(rabbit)
            if hunger and last[slot] and hunger < last[slot] - 0.08
                and near(group, player, 12) and day
                and value.lastFedDay ~= day then
                value.lastFedDay = day
                SC.Factions.adjustStanding(group.id, 10, "june_rabbit_fed")
                speak(group, "feed")
            end
            if hunger then last[slot] = hunger end
        end
    end
    startEscape(group, value, player, hour)
    updateEscape(group, value, player, hour)
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id)
    if recruitment and recruitment.status == "joined" then
        value.stage = "recruited"
    end
    if near(group, player, 12) and current >= (nextLineAt[group.id] or 0) then
        nextLineAt[group.id] = current + 180000
        speak(group, "babies")
    end
    return true, value.stage
end

function June.pulseRecruited(group, actor, player, current)
    for slot = 1, #RABBITS do
        SC.OddballAnimals.follow(group, slot, actor, current)
    end
    return true, "rabbits_follow_june"
end

function June.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value or value.stage == "recruited" then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "june_keeper", priority = 30 }
end

function June.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "june_keeper" then return false end
    local value = story(group)
    local quest = value.juniper
    if quest and quest.stage == "found" then
        updateEscape(group, value, player, select(2, dayHour()))
        return true, "coaxing_juniper"
    end
    local home = value.site and value.site.spawn
    if not home then return true, "ranger_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (home.z or 0) and (x - home.x) ^ 2
        + (y - home.y) ^ 2 <= 16 then return true, "watching_rabbits" end
    local square = U().gridSquare(home.x, home.y, home.z or 0)
    if not square then return true, "ranger_post_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_animal_keeper", arrivalDistance = 4 })
end

function June.canRecruit(group)
    local value = story(group)
    if not value or group.standing ~= "Trusted"
        or value.stage == "hostile" then return false, "earn_june_trust" end
    local quest = value.juniper
    if quest and quest.stage ~= "home" then
        return false, "juniper_must_return_home"
    end
    return allAlive(group)
end

function June.menuOptions(group, player)
    local value = story(group)
    if not value then return {} end
    local nearby = near(group, player, 5)
    local day = dayHour()
    local options = {
        { id = "introduce_rabbits", label = "Ask June about her rabbits",
            enabled = nearby, detail = "Ten rabbits, ten names" },
        { id = "offer_greens", label = "Bring greens for the rabbits",
            enabled = nearby and itemIn(player, GREENS) ~= nil,
            detail = "Carrots, lettuce or cabbage" },
        { id = "trade_game", label = "Trade ammunition and greens for game",
            enabled = nearby and itemIn(player, GREENS) ~= nil
                and itemIn(player, { ["Base.308Box"] = true }) ~= nil
                and itemIn(actorFor(group), GAME) ~= nil },
    }
    if itemIn(player, DANGER) then
        options[#options + 1] = { id = "offer_rabbit_meat",
            label = "Offer June rabbit meat", enabled = nearby,
            detail = "June knows what you are carrying" }
    end
    if nearby and day and value.quizDay ~= day then
        if value.quizTargetDay ~= day or not value.quizSlot then
            value.quizTargetDay = day
            value.quizSlot = rabbitNearestPlayer(group, player)
            value.quizPrompted = false
        end
        local slot = value.quizSlot
        local animal = SC.OddballAnimals.find(group, slot)
        if animal then
            options[#options + 1] = { id = "quiz_prompt",
                label = "Name the rabbit nearest you", enabled = true,
                detail = "Inspect that rabbit's vanilla name first" }
            if value.quizPrompted == true then
                for offset = 0, 3 do
                    local answer = (slot + offset * 3 - 1) % #RABBITS + 1
                    options[#options + 1] = { id = "quiz_answer",
                        label = "Answer: " .. RABBITS[answer].name,
                        enabled = true, payload = { slot = slot, answer = answer } }
                end
            end
        end
    end
    local canJoin, reason = June.canRecruit(group)
    local recruitment = SC.FactionRecruitment
        and SC.FactionRecruitment.summary(group.id) or nil
    if not recruitment or recruitment.status ~= "joined" then
        options[#options + 1] = { id = "recruit",
            label = "Invite June and all ten rabbits",
            enabled = nearby and canJoin, detail = reason }
        if recruitment and recruitment.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask June for her decision",
                enabled = nearby and recruitment.canDecide == true }
        end
    end
    return options
end

function June.action(group, action, player, payload)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "animal_hurt" then
        hostile(group, value, "rabbit")
        return true, "june_defends_rabbits"
    end
    if action == "introduce_rabbits" then
        if not near(group, player, 5) then return false, "too_far_away" end
        speak(group, "babies")
        return true, "rabbits_introduced"
    end
    if action == "offer_rabbit_meat" then
        if not near(group, player, 5) or not itemIn(player, DANGER) then
            return false, "rabbit_meat_offer_unavailable"
        end
        hostile(group, value, "meat")
        return true, "rabbit_meat_rejected"
    end
    if action == "quiz_prompt" then
        if not near(group, player, 5) then return false, "too_far_away" end
        local day = dayHour()
        if not day or value.quizDay == day then return false, "quiz_daily_limit" end
        if value.quizTargetDay ~= day or not value.quizSlot then
            value.quizTargetDay = day
            value.quizSlot = rabbitNearestPlayer(group, player)
        end
        if not value.quizSlot or not SC.OddballAnimals.find(group, value.quizSlot) then
            return false, "no_rabbit_nearby"
        end
        value.quizPrompted = true
        speak(group, "quiz")
        return true, "quiz_started"
    end
    if action == "quiz_answer" then
        local day = dayHour()
        local slot = number(payload and payload.slot)
        local answer = number(payload and payload.answer)
        if not near(group, player, 5) or not day
            or value.quizDay == day or value.quizTargetDay ~= day
            or value.quizPrompted ~= true
            or slot ~= value.quizSlot or not SC.OddballAnimals.find(group, slot)
            or not RABBITS[answer or 0] then
            return false, "quiz_not_ready"
        end
        value.quizPrompted = false
        value.quizDay = day
        local correct = answer == slot
        SC.Factions.adjustStanding(group.id,
            correct and 7 or -4, correct and "rabbit_name_known" or "rabbit_name_wrong")
        speak(group, correct and "correct" or "wrong")
        return true, correct and "rabbit_name_correct" or "rabbit_name_wrong"
    end
    if action == "offer_greens" or action == "trade_game" then
        if not near(group, player, 5) then return false, "too_far_away" end
        if itemIn(player, DANGER) then
            hostile(group, value, "meat")
            return true, "rabbit_meat_rejected"
        end
        local gift = itemIn(player, GREENS)
        local actor = actorFor(group)
        local seller = actor and U().inventory(actor)
        local buyer = player and U().inventory(player)
        local source = gift and select(1, U().call(gift, "getContainer"))
        if not source or not seller or not buyer then
            return false, "greens_unavailable"
        end
        local ammo, ammoSource, game
        if action == "trade_game" then
            ammo = itemIn(player, { ["Base.308Box"] = true })
            ammoSource = ammo and select(1, U().call(ammo, "getContainer"))
            game = itemIn(actor, GAME)
            if not ammoSource or not game then return false, "trade_stock_unavailable" end
        end
        if not U().transferItemVerified(source, seller, gift) then
            return false, "greens_transfer_failed"
        end
        if action == "trade_game" then
            if not U().transferItemVerified(ammoSource, seller, ammo) then
                U().transferItemVerified(seller, buyer, gift)
                return false, "ammo_transfer_failed"
            end
            if not U().transferItemVerified(seller, buyer, game) then
                U().transferItemVerified(seller, buyer, gift)
                U().transferItemVerified(seller, buyer, ammo)
                return false, "game_transfer_failed"
            end
            speak(group, "trade")
        else
            SC.Factions.adjustStanding(group.id, 12, "rabbit_greens_delivered")
            speak(group, "feed")
        end
        return true, action == "trade_game" and "game_traded"
            or "rabbit_greens_delivered"
    end
    if action == "recruit" then
        if not near(group, player, 5) then return false, "too_far_away" end
        local allowed, reason = June.canRecruit(group)
        if not allowed then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = SC.FactionRecruitment.summary(group.id)
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, askReason end
        end
        local started, startReason = SC.FactionRecruitment.startTrial(
            group.id, player, false)
        if started then speak(group, "join") end
        return started, startReason
    end
    if action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unsupported_june_action"
end

return June
