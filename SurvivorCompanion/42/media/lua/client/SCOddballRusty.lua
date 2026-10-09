-- SPDX-License-Identifier: MIT
-- Rusty Pell's theatre. The show is a bounded real-time encounter. Standing,
-- recruitment and human combat remain with the faction systems.

local SC = SurvivorCompanion
SC.OddballRusty = SC.OddballRusty or {}
local Rusty = SC.OddballRusty

local ID = "ringmaster_rusty_pell"
local SHOW_MS = 60000
local AUDIENCE_RANGE = 8
local SESSION_KEY = tostring({}) .. ":" .. tostring(os and os.time and os.time() or 0)
local PRIZES = { "Base.Bandage", "Base.TinnedBeans", "Base.WaterBottle" }

local lines = {
    welcome = "Ladies and gentlemen, and whatever you are now, welcome!",
    midpoint = "Sit down. The show isn't over until I say it's over.",
    hostile = "Nobody walks out on Rusty Pell. Nobody walks anywhere, after.",
    prize = "For the finest audience in Kentucky. All three of you.",
    alone = "Used to be four hundred seats. Now it's just me and the echo.",
    recruit = "Maybe I should come along. The audience is gone.",
}

local function U() return SC.GameplayUtil end

local function stateFor(group)
    local state = type(group) == "table" and group.oddball or nil
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    state.completedShows = math.max(0, math.min(3,
        math.floor(tonumber(state.completedShows) or 0)))
    state.applaudedShows = type(state.applaudedShows) == "table"
        and state.applaudedShows or {}
    return state
end

function Rusty.actor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, topic)
    local actor = Rusty.actor(group)
    return actor ~= nil and lines[topic] ~= nil
        and U().say(actor, lines[topic]) == true
end

local function inTheatre(state, player)
    if not player then return false end
    local bounds = state.site and state.site.house and state.site.house.bounds
    if type(bounds) ~= "table" then return true end
    local x, y, z = U().position(player)
    local targetZ = state.site.spawn and state.site.spawn.z or 0
    return x ~= nil and y ~= nil and z == targetZ
        and x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
end

local function audiencePresent(group, player, state)
    local actor = Rusty.actor(group)
    return actor ~= nil and player ~= nil and inTheatre(state, player)
        and U().distance(actor, player) <= AUDIENCE_RANGE
end

local function turnHostile(group, state, reason)
    if state.stage == "hostile" then return true, "already_hostile" end
    if state.stage == "recruited" then return false, "rusty_recruited" end
    if not SC.Factions or type(SC.Factions.forceStanding) ~= "function" then
        return false, "standing_unavailable"
    end
    local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
    if not changed then return false, why or "standing_change_failed" end
    group.permanentHostility = true
    state.stage = "hostile"
    state.hostileReason = reason
    state.showDeadlineAt = nil
    speak(group, "hostile")
    return true, "rusty_hostile"
end

local function findItem(actor, fullType)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == fullType then return item end
    end
    return nil
end

function Rusty.onSpawn(group, actor)
    local state = stateFor(group)
    if not state or actor == nil then return false, "wrong_oddball" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "rusty_inventory_unavailable" end
    -- Once seeded, a missing item may have been traded or dropped. Never
    -- mint a replacement on save/load merely because it cannot be found.
    for _, fullType in ipairs({ "Base.Sledgehammer", "Base.Revolver_CapGun",
        "Base.Whistle" }) do
        if state.equipmentSeeded ~= true and not findItem(actor, fullType) then
            local item, reason = U().addItem(inventory, fullType)
            if not item then return false, reason or "rusty_gear_unavailable" end
        end
    end
    state.equipmentSeeded = true
    if not select(1, U().call(actor, "getPrimaryHandItem")) then
        local mallet = findItem(actor, "Base.Sledgehammer")
        if mallet then U().call(actor, "setPrimaryHandItem", mallet) end
    end
    return true, "rusty_ready"
end

local function startShow(group, player, state, current)
    if state.stage == "show_running" then return false, "show_already_running" end
    if state.stage == "hostile" or state.stage == "recruited"
        or state.completedShows >= 3 then return false, "no_more_shows" end
    if not audiencePresent(group, player, state) then
        return false, "audience_not_in_theatre"
    end
    state.stage = "show_running"
    state.showStartedAt = current
    state.showDeadlineAt = current + SHOW_MS
    state.showSession = SESSION_KEY
    state.midpointSpoken = false
    state.autoShowUsed = true
    group.discovered = true
    local actor = Rusty.actor(group)
    if actor then
        -- Base.Whistle's verified ShoutType is BlowWhistle. Play its real
        -- sound without Callout's 60-tile world-noise pulse: a show should
        -- not summon a horde onto an audience locked into a minute's watch.
        if findItem(actor, "Base.Whistle") then
            U().call(actor, "playSound", "BlowWhistle")
        end
        if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
            SC.Relationship.playEmote(actor, "clap")
        end
    end
    speak(group, "welcome")
    if state.reactionSpoken ~= true and SC.Registry
        and type(SC.Registry.living) == "function" then
        for _, fellow in ipairs(SC.Registry.living()) do
            local record = SC.Registry.byId(U().idOf(fellow))
            if record and record.recruited == true
                and U().distance(fellow, player) <= 8 then
                U().say(fellow, "Clap. Just clap. Smile and clap.")
                state.reactionSpoken = true
                break
            end
        end
    end
    return true, "show_started"
end

local function awardPrize(group, player, state)
    local index = tonumber(state.prizePending)
    if not index or index < 1 or index > 3 then
        return false, "no_prize_pending"
    end
    local inventory = player and U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    local item, reason = U().addItem(inventory, PRIZES[index])
    if not item then return false, reason or "prize_delivery_pending" end
    local data = U().modData(item)
    if type(data) == "table" then
        data.LF_RustyPrizeGroup = group.id
        data.LF_RustyPrizeShow = index
    end
    state.prizePending = nil
    state.completedShows = index
    state.stage = index >= 3 and "ready" or "intermission"
    speak(group, "prize")
    if index >= 3 then
        state.trustPending = true
    end
    return true, "show_prize_awarded"
end

local function applyTrust(group, state)
    if not state.trustPending then return true end
    if not SC.Factions or type(SC.Factions.forceStanding) ~= "function" then
        return false, "standing_unavailable"
    end
    local changed, reason = SC.Factions.forceStanding(group.id, "Trusted")
    if not changed then return false, reason end
    state.trustPending = false
    if not state.aloneSpoken then
        state.aloneSpoken = true
        speak(group, "alone")
    end
    return true, "three_shows_trusted"
end

function Rusty.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if type(group.recruitment) == "table"
        and group.recruitment.status == "joined" then
        state.stage = "recruited"
        if SC.Oddballs and type(SC.Oddballs.retire) == "function"
            and state.retired ~= true then
            SC.Oddballs.retire(group, "recruited")
            state.retired = true
        end
    end
    local now = tonumber(current) or U().nowMs()
    if state.stage == "hostile" or state.stage == "recruited" then
        return true, state.stage
    end
    if state.prizePending and audiencePresent(group, player, state) then
        awardPrize(group, player, state)
    end
    if state.trustPending then applyTrust(group, state) end
    if state.stage == "unmet" and state.autoShowUsed ~= true then
        startShow(group, player, state, now)
    end
    if state.stage ~= "show_running" then return true, state.stage end
    local start = tonumber(state.showStartedAt) or now
    local deadline = tonumber(state.showDeadlineAt) or 0
    if state.showSession ~= SESSION_KEY or now < start
        or deadline < start or deadline > now + SHOW_MS then
        if audiencePresent(group, player, state) then
            state.showStartedAt, state.showDeadlineAt = now, now + SHOW_MS
            state.showSession, state.midpointSpoken = SESSION_KEY, false
            return true, "show_timer_restarted"
        end
        -- Loading into another place never turns Rusty hostile offscreen.
        state.stage, state.showDeadlineAt = "intermission", nil
        return true, "show_paused_after_load"
    end
    if not audiencePresent(group, player, state) then
        return turnHostile(group, state, "audience_walked_out")
    end
    if now >= deadline then
        state.stage = "prize_pending"
        state.prizePending = state.completedShows + 1
        local rewarded, why = awardPrize(group, player, state)
        if rewarded then applyTrust(group, state) end
        return rewarded, why
    end
    if state.midpointSpoken ~= true and now >= start + 30000 then
        state.midpointSpoken = true
        speak(group, "midpoint")
    end
    return true, "show_running"
end

function Rusty.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    if state.stage == "hostile" or group.standing == "Hostile" then
        return { priority = 110, kind = "faction", mode = "hostile" }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then
        return { priority = 18, kind = "faction", mode = "zombie_defense" }
    end
    return { priority = 30, kind = "faction", mode = "rusty_stage" }
end

function Rusty.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local mode = intent and intent.mode
    if mode == "hostile" or mode == "zombie_defense" then
        return false, "delegate_native_combat"
    end
    if mode ~= "rusty_stage" then return false, "wrong_rusty_intent" end
    local point = state.site and state.site.spawn
    if point and U().distance(actor, point) > 2.5 and SC.Navigation
        and type(SC.Navigation.request) == "function" then
        local square = U().gridSquare(point.x, point.y, point.z or 0)
        if square then
            return SC.Navigation.request(actor, square, "walk", {
                action = "rusty_return_stage", arrivalDistance = 1.5 })
        end
    end
    U().stop(actor)
    return true, "holding_stage"
end

function Rusty.canRecruit(group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if type(group.recruitment) == "table"
        and group.recruitment.status == "joined" then
        return false, "rusty_already_joined"
    end
    if state.stage == "hostile" or state.stage == "recruited"
        or group.permanentHostility == true then
        return false, "rusty_hostile_or_joined"
    end
    if state.completedShows < 3 then return false, "three_shows_required" end
    if group.standing ~= "Trusted" then return false, "trusted_standing_required" end
    return true, "rusty_ready"
end

function Rusty.menuOptions(group, player)
    local state = stateFor(group)
    if not state or state.stage == "hostile" then return {} end
    local nearby = audiencePresent(group, player, state)
    local options = {}
    if state.stage == "intermission" and state.completedShows < 3 then
        options[#options + 1] = { id = "show_again",
            label = "Stay for another show", enabled = nearby,
            detail = tostring(state.completedShows) .. "/3 shows completed" }
    end
    if state.stage == "show_running" then
        local remaining = math.max(0, math.ceil(((tonumber(state.showDeadlineAt)
            or U().nowMs()) - U().nowMs()) / 1000))
        options[#options + 1] = { id = "clap",
            label = "Clap for Rusty's show", enabled = nearby
                and state.applaudedShows[state.completedShows + 1] ~= true,
            detail = tostring(remaining) .. " seconds left" }
    end
    if state.stage == "prize_pending" then
        options[#options + 1] = { id = "claim_prize",
            label = "Claim Rusty's prize", enabled = nearby }
    end
    local eligible, reason = Rusty.canRecruit(group)
    if eligible and state.stage ~= "recruited" then
        options[#options + 1] = { id = "recruit",
            label = "Ask Rusty to come along", enabled = nearby,
            detail = reason }
    end
    local summary = SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function"
        and SC.FactionRecruitment.summary(group.id) or nil
    if summary and summary.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Ask Rusty for his decision", enabled = nearby
                and summary.canDecide == true, detail = summary.reason }
        options[#options + 1] = { id = "recruitment_return",
            label = "Tell Rusty to return to the theatre",
            enabled = summary.canReturn == true }
    end
    return options
end

function Rusty.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hurt" then return turnHostile(group, state, "player_attack") end
    if state.stage == "hostile" then return false, "rusty_hostile" end
    if action == "recruitment_return" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.returnNow(group.id, player, false)
    end
    if not audiencePresent(group, player, state) then
        return false, "audience_not_in_theatre"
    end
    if action == "show_again" then
        if state.stage ~= "intermission" then return false, "no_intermission" end
        return startShow(group, player, state, U().nowMs())
    elseif action == "clap" then
        if state.stage ~= "show_running" then return false, "show_not_running" end
        local index = state.completedShows + 1
        if state.applaudedShows[index] == true then return false, "already_clapped" end
        local _, played = U().call(player, "playEmote", "clap")
        if not played then return false, "clap_unavailable" end
        if not SC.Factions or type(SC.Factions.adjustStanding) ~= "function" then
            return false, "standing_unavailable"
        end
        local adjusted, why = SC.Factions.adjustStanding(group.id, 10,
            "rusty_applause")
        if not adjusted then return false, why or "standing_change_failed" end
        state.applaudedShows[index] = true
        return true, "audience_applauded"
    elseif action == "claim_prize" then
        if state.stage ~= "prize_pending" then return false, "no_prize_pending" end
        local granted, reason = awardPrize(group, player, state)
        if granted then applyTrust(group, state) end
        return granted, reason
    elseif action == "recruit" then
        local allowed, reason = Rusty.canRecruit(group)
        if not allowed then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, why = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, why end
        end
        local started, why = SC.FactionRecruitment.startTrial(group.id, player, false)
        if not started then return false, why end
        speak(group, "recruit")
        return true, why or "trial_started"
    elseif action == "recruitment_decide" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unsupported_rusty_action"
end

return Rusty
