-- SPDX-License-Identifier: MIT
-- A camera crew for exact, credited pan or golf-club kills. Companion kills
-- enter through Tales.noteKill; player kills use the existing zombie-death hook.

local SC = SurvivorCompanion
SC.OddballSkeeter = SC.OddballSkeeter or {}
local Skeeter = SC.OddballSkeeter
local ID = "cameraman_skeeter_bowles"
local seenKills = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "pitch"
    value.kills = math.max(0, math.min(3,
        math.floor(tonumber(value.kills) or 0)))
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

function Skeeter.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "skeeter_unavailable" end
    if value.stockSeeded == true then return true, "camera_ready" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "camera_inventory_unavailable" end
    local camera = U().addItem(inventory, "Base.Camera")
    local tape = U().addItem(inventory, "Base.VHS_Home")
    local prize = U().addItem(inventory, "Base.MoneyBundle")
    if not camera or not tape or not prize then
        return false, "camera_or_prize_unavailable"
    end
    U().call(actor, "setPrimaryHandItem", camera)
    U().call(tape, "setName", "America's Funniest Zombies: Knox Cut")
    value.stockSeeded = true
    return true, "camera_crew_ready"
end

function Skeeter.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "Ten grand, man. Ten grand and a trip to California. You're on camera.")
    end
    return true, value.stage
end

function Skeeter.noteKill(group, killer, zombie)
    local value = story(group)
    if not value or not killer or not zombie
        or value.stage ~= "filming" or seenKills[zombie] then
        return false, "challenge_not_filming"
    end
    local camera = actorFor(group)
    if not camera or U().distance(camera, killer) > 18
        or U().canSee(camera, killer) ~= true then
        return false, "cameraman_missed_the_kill"
    end
    local weapon = select(1, U().call(killer, "getPrimaryHandItem"))
    local kind = weapon and U().itemType(weapon)
    if value.challenge == "pan" and kind ~= "Base.Pan"
        or value.challenge == "golf" and kind ~= "Base.Golfclub" then
        return false, "wrong_stunt_weapon"
    end
    seenKills[zombie] = true
    value.kills = value.kills + 1
    if value.kills >= (value.challenge == "golf" and 1 or 3) then
        value.stage = "prize_ready"
        U().say(camera,
            "That's the shot! California can wait. Come get your tape.")
    else
        U().say(camera,
            "Do the pan thing again. I didn't get the angle.")
    end
    return true, "verified_challenge_kill"
end

function Skeeter.onZombieDead(group, zombie, attacker, player)
    if attacker ~= nil and attacker == player then
        return Skeeter.noteKill(group, attacker, zombie)
    end
    return false
end

function Skeeter.avoidsZombieCombat()
    return true
end

function Skeeter.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then
        return { mode = "skeeter_flee", priority = 82,
            target = snapshot.threats and snapshot.threats[1]
                and snapshot.threats[1].actor }
    end
    if value.stage == "filming" then
        return { mode = "skeeter_follow", priority = 40 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Skeeter.update(actor, player, runtime, intent)
    if not intent or (intent.mode ~= "skeeter_follow"
        and intent.mode ~= "skeeter_flee") then
        return false, "camera_idle"
    end
    local destination = player
    if intent.mode == "skeeter_flee" and intent.target then
        local ax, ay, az = U().position(actor)
        local zx, zy = U().position(intent.target)
        if ax and zx then
            local dx, dy = ax - zx, ay - zy
            local length = math.max(1, math.sqrt(dx * dx + dy * dy))
            destination = U().gridSquare(
                math.floor(ax + dx / length * 6),
                math.floor(ay + dy / length * 6), az or 0)
        end
    end
    if not destination then return false, "camera_route_missing" end
    if intent.mode == "skeeter_follow" and U().distance(actor, player) <= 5 then
        return true, "filming_at_range"
    end
    local square = U().squareOf(destination) or destination
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square,
        intent.mode == "skeeter_flee" and "run" or "walk", {
            action = "faction_camera_crew",
            arrivalDistance = intent.mode == "skeeter_flee" and 2 or 5 })
end

function Skeeter.canRecruit()
    return false, "skeeter_chases_the_next_shot"
end

function Skeeter.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "prize_ready" then
        return { { id = "claim_prize",
            label = "Take Skeeter's tape and prize", enabled = true } }
    end
    if value.stage == "filming" then
        return { { id = "ask_progress", label = "Ask about the shot",
            enabled = true,
            detail = tostring(value.kills) .. " verified kill(s)" } }
    end
    if value.stage == "finished" then return {} end
    return {
        { id = "accept_pan", label = "Film three frying-pan kills",
            enabled = true },
        { id = "accept_golf", label = "Film one golf-club kill",
            enabled = true },
    }
end

function Skeeter.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "camera_crew_too_far" end
    local actor = actorFor(group)
    if (action == "accept_pan" or action == "accept_golf")
        and (value.stage == "pitch" or value.stage == "unmet") then
        value.stage, value.challenge, value.kills = "filming",
            action == "accept_pan" and "pan" or "golf", 0
        U().say(actor, action == "accept_pan"
            and "Three with a frying pan. Give the camera something to love."
            or "One with a golf club. Make it a clean swing.")
        return true, "camera_challenge_started"
    end
    if action == "ask_progress" and value.stage == "filming" then
        U().say(actor, "Keep that weapon out. I need the whole kill on tape.")
        return true, tostring(value.kills) .. "_kills_filmed"
    end
    if action ~= "claim_prize" or value.stage ~= "prize_ready" then
        return false, "camera_choice_unavailable"
    end
    local tape = itemFor(actor, "Base.VHS_Home")
    local money = itemFor(actor, "Base.MoneyBundle")
    local tapeSource = tape and select(1, U().call(tape, "getContainer"))
    local moneySource = money and select(1, U().call(money,
        "getContainer"))
    local destination = U().inventory(player)
    if not tape or not money or not tapeSource or not moneySource
        or not destination then return false, "camera_prize_missing" end
    if not U().transferItemVerified(tapeSource, destination, tape) then
        return false, "camera_tape_transfer_failed"
    end
    if not U().transferItemVerified(moneySource, destination, money) then
        U().transferItemVerified(destination, tapeSource, tape)
        return false, "camera_money_transfer_failed"
    end
    value.stage = "finished"
    U().say(actor, "We got the shot. Tell California we survived.")
    return true, "exact_camera_prize_received"
end

return Skeeter
