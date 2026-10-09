-- SPDX-License-Identifier: MIT
-- Strange Folk: Clem Sutter's voluntary noon duel. The faction combat owner
-- fires the real revolver; this module only gates the duel and its first hit.

local SC = SurvivorCompanion
SC.OddballClem = SC.OddballClem or {}
local Clem = SC.OddballClem
local ID = "duelist_clem_sutter"
local SESSION = tostring({}) .. ":" .. tostring(os and os.time and os.time() or 0)
local SETUP_MS, COUNTDOWN_MS = 30000, 3000

local lines = {
    greet = { "This town ain't big enough for the two of us. Noon. Out front.",
        "This town isn't big enough for the two of us. Noon. Out front." },
    boast = { "Fastest gun in Louisville since the ninth of July.",
        "Fastest gun in Louisville since the ninth of July." },
    decline = { "Yellow as a school bus. Go on, then.",
        "Yellow as a school bus. Go on, then." },
    draw = { "Draw, you yellow-bellied son of a bitch!",
        "Draw, you yellow-bellied varmint!" },
    cap = { "Well. That's embarrassing. It's a cap gun.",
        "Well. That's embarrassing. It's a cap gun." },
    yield = { "All right! First blood. You win. Let me breathe.",
        "All right! First blood. You win. Let me breathe." },
    win = { "I drew first. That's the whole story.",
        "I drew first. That's the whole story." },
    offer = { "Take the hat and the gun. You earned them.",
        "Take the hat and the gun. You earned them." },
}

local function U() return SC.GameplayUtil end
local function stateFor(group)
    local state = type(group) == "table" and group.oddball or nil
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    return state
end

local function clock()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime then return nil end
    local hour, called = U().call(gameTime, "getTimeOfDay")
    return called and tonumber(hour) or nil
end

local function isNoon()
    local hour = clock()
    return hour ~= nil and hour >= 12 and hour < 13
end

function Clem.actor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, key)
    local actor, line = Clem.actor(group), lines[key]
    if not actor or not line then return false end
    return U().say(actor, line[U().config("profanityEnabled") == false and 2 or 1]) == true
end

local function near(group, player)
    local actor = Clem.actor(group)
    return actor and player and U().distance(actor, player) <= 10
end

local function atEightTiles(actor, player)
    if not actor or not player then return false end
    local _, _, az = U().position(actor)
    local _, _, pz = U().position(player)
    local distance = U().distance(actor, player)
    return az == pz and distance >= 7 and distance <= 9.5
end

local function gunType(state)
    return state.capGun == true and "Base.Revolver_CapGun" or "Base.Revolver"
end

local function gear(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function setStanding(group, standing)
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        return SC.Factions.forceStanding(group.id, standing)
    end
    group.standing = standing
    group.lifecycle = standing == "Hostile" and "hostile" or "settled"
    return true, standing
end

local function finish(group, winner, reason)
    local state = stateFor(group)
    if not state or state.stage == "won" or state.stage == "lost"
        or state.stage == "embarrassed" then return false end
    state.stage = winner
    state.duelEnded = true
    state.duelResult = reason
    state.drawAt, state.firstShotAt, state.setupDeadlineAt = nil, nil, nil
    state.duelSession = nil
    local actor = Clem.actor(group)
    if actor then U().stop(actor) end
    setStanding(group, winner == "won" and "Trusted" or "Wary")
    speak(group, winner == "won" and "yield"
        or winner == "embarrassed" and "cap" or "win")
    return true
end

function Clem.onSpawn(group, actor)
    local state = stateFor(group)
    if not state or not actor then return false, "wrong_oddball" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    if state.capGun == nil then
        local hash = U().stableHash and U().stableHash(group.id .. ":clem-gun") or 0
        state.capGun = hash % 2 == 0
    end
    local kind = gunType(state)
    local gun = gear(actor, kind)
    if not gun and state.gearSeeded ~= true then
        gun = U().addItem(inventory, kind)
        if not gun then return false, "duel_gun_unavailable" end
    end
    if not gun then return false, "duel_gun_missing" end
    if state.gearSeeded ~= true then
        U().call(gun, "setCurrentAmmoCount", state.capGun and 0 or 6)
        state.gearSeeded = true
    end
    if not select(1, U().call(actor, "getPrimaryHandItem")) then
        U().call(actor, "setPrimaryHandItem", gun)
    end
    return true, "clem_ready"
end

function Clem.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if state.stage == "won" or state.stage == "lost"
        or state.stage == "embarrassed" or state.stage == "recruited"
        or state.stage == "hostile" then return true, state.stage end
    local now = tonumber(current) or U().nowMs()
    local actor = Clem.actor(group)
    if not actor then return true, "clem_unloaded" end
    if state.stage == "unmet" and near(group, player) then
        group.discovered = true
        state.stage = "challenged"
        speak(group, "greet")
    end
    if state.stage == "duel_setup" then
        if state.duelSession ~= SESSION or now < (state.setupStartedAt or now) then
            state.setupStartedAt = now
            state.setupDeadlineAt = now + SETUP_MS
            state.duelSession = SESSION
        end
        if now >= (state.setupDeadlineAt or now + SETUP_MS) then
            state.stage = "challenged"
            state.setupDeadlineAt = nil
            return true, "duel_setup_expired"
        end
        local ground = state.site and state.site.duelGround
        if ground and U().distance(actor, ground) > 1.75 then
            return true, "clem_approaching_duel_ground"
        end
        if atEightTiles(actor, player) then
            state.stage = "duel_countdown"
            state.drawAt = now + COUNTDOWN_MS
            state.countdownStep = 0
            state.clemHealthAtDraw = U().nativeHealth(actor)
            state.playerHealthAtDraw = U().nativeHealth(player)
            return true, "duel_countdown_started"
        end
    elseif state.stage == "duel_countdown" or state.stage == "duel_draw_wait"
        or state.stage == "duel_active" then
        if state.duelSession ~= SESSION or now < (state.setupStartedAt or now) then
            state.stage = "challenged"
            setStanding(group, "Wary")
            return true, "duel_interrupted_by_load"
        end
        if U().nativeHealth(actor) < (tonumber(state.clemHealthAtDraw) or 0) - 0.01 then
            finish(group, "won", "clem_wounded")
            return true, "duel_first_hit_clem"
        end
        if U().nativeHealth(player) < (tonumber(state.playerHealthAtDraw) or 0) - 0.01 then
            finish(group, "lost", "player_wounded")
            return true, "duel_first_hit_player"
        end
        if state.stage == "duel_countdown" then
            local drawAt = tonumber(state.drawAt) or now
            local elapsed = COUNTDOWN_MS - math.max(0, drawAt - now)
            local step = math.min(3, math.floor(elapsed / 1000) + 1)
            if step > (tonumber(state.countdownStep) or 0) and step <= 3 then
                state.countdownStep = step
                U().say(actor, ({ "Three.", "Two.", "One." })[step])
            end
            if now >= drawAt then
                state.stage = "duel_draw_wait"
                speak(group, "draw")
                -- Stable for one duel, bounded to 1.5-3 seconds. No clock or
                -- process-local random state is stored in the save.
                local hash = U().stableHash and U().stableHash(group.id .. ":duel") or 0
                state.firstShotAt = now + 1500 + hash % 1501
                if not state.capGun then setStanding(group, "Hostile") end
            end
        elseif state.stage == "duel_draw_wait" and now >= (state.firstShotAt or now) then
            if state.capGun then
                U().call(actor, "playSound", "RevolverShoot")
                local x, y, z = U().position(actor)
                if type(addSound) == "function" and x then
                    pcall(addSound, actor, math.floor(x), math.floor(y),
                        math.floor(z or 0), 30, 30)
                end
                finish(group, "embarrassed", "cap_gun_fired")
                return true, "cap_gun_no_damage"
            end
            state.stage = "duel_active"
        end
    end
    return true, state.stage
end

function Clem.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    if state.stage == "hostile" or state.stage == "duel_active" then
        return { priority = 110, kind = "faction", mode = "hostile",
            factionId = group.id }
    end
    return { priority = 35, kind = "faction", mode = "clem_wait",
        factionId = group.id }
end

function Clem.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if intent and intent.mode == "hostile" then
        return false, "delegate_native_human_combat"
    end
    if state.stage == "duel_setup" then
        local ground = state.site and state.site.duelGround
        if ground and U().distance(actor, ground) > 1.75 then
            local square = U().gridSquare(ground.x, ground.y, ground.z or 0)
            if square and SC.Navigation and type(SC.Navigation.request) == "function" then
                return SC.Navigation.request(actor, square, "walk", {
                    action = "clem_approach_duel_ground", targetSquare = square,
                    arrivalDistance = 1.25 })
            end
            return false, "duel_ground_unavailable"
        end
    end
    if player and near(group, player) then
        return U().move(actor, "walk", { action = "face_alert", target = player,
            facingTarget = player, stableFacing = true,
            humanAnimationOnly = true })
    end
    U().stop(actor)
    return true, "clem_waiting"
end

function Clem.canRecruit(group)
    local state = stateFor(group)
    return state ~= nil and state.stage == "won"
        and group.members and group.members[1]
        and group.members[1].alive ~= false
end

function Clem.menuOptions(group, player)
    local state = stateFor(group)
    if not state then return {} end
    local nearby = near(group, player)
    if state.stage == "hostile" or state.stage == "recruited" then return {} end
    if state.stage == "challenged" then
        return {
            { id = "accept_duel", label = "Accept Clem's noon duel",
                enabled = nearby and isNoon(),
                detail = "Meet him outside, eight tiles apart. First hit ends it." },
            { id = "decline_duel", label = "Decline the duel", enabled = nearby },
        }
    elseif state.stage == "duel_setup" then
        return { { id = "cancel_duel", label = "Call off the duel",
            enabled = nearby, detail = "No hostility before the draw" } }
    elseif state.stage == "won" then
        return {
            { id = "claim_gear", label = "Accept Clem's hat and gun",
                enabled = nearby and state.gearClaimed ~= true },
            { id = "recruit", label = "Ask Clem to join", enabled = nearby },
        }
    end
    return {}
end

local function claimGear(group, player, state)
    if state.gearClaimed then return false, "gear_already_claimed" end
    local actor = Clem.actor(group)
    local source, destination = actor and U().inventory(actor), U().inventory(player)
    if not source or not destination then return false, "inventory_unavailable" end
    local moved = 0
    for _, entry in ipairs({ { "Base.Hat_Cowboy", "hatClaimed" },
        { gunType(state), "gunClaimed" } }) do
        local kind, flag = entry[1], entry[2]
        local item = state[flag] ~= true and gear(actor, kind) or nil
        if item then
            if flag == "hatClaimed" then
                local worn = select(1, U().call(actor, "getWornItem", "Hat"))
                if worn == item then U().call(actor, "setWornItem", "Hat", nil) end
            end
            if select(1, U().call(actor, "getPrimaryHandItem")) == item then
                U().call(actor, "setPrimaryHandItem", nil)
            end
            local owner = select(1, U().call(item, "getContainer")) or source
            local okay = U().transferItemVerified(owner, destination, item)
            if okay then
                state[flag] = true
                moved = moved + 1
            end
        end
    end
    if moved == 0 and not state.hatClaimed and not state.gunClaimed then
        return false, "duel_gear_unavailable"
    end
    state.gearClaimed = state.hatClaimed == true and state.gunClaimed == true
    speak(group, "offer")
    return true, state.gearClaimed and "duel_gear_transferred"
        or "duel_gear_partially_transferred"
end

function Clem.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hit_player" then
        if state.stage ~= "duel_active" or state.capGun == true then
            return false, "no_live_duel_hit"
        end
        finish(group, "lost", "player_wounded")
        return true, "duel_first_hit_player"
    elseif action == "hurt" then
        if state.stage == "duel_active" or state.stage == "duel_draw_wait"
            or state.stage == "duel_countdown" then
            finish(group, "won", "clem_wounded")
            return true, "duel_first_hit_clem"
        end
        if state.stage == "won" or state.stage == "lost" then return true, "duel_over" end
        state.stage = "hostile"
        setStanding(group, "Hostile")
        return true, "clem_attacked_outside_duel"
    end
    if action == "accept_duel" then
        if state.stage ~= "challenged" then return false, "duel_not_offered" end
        if not isNoon() then return false, "noon_required" end
        if not near(group, player) then return false, "too_far_away" end
        if not (state.site and state.site.duelGround) then
            return false, "duel_ground_unavailable"
        end
        local now = U().nowMs()
        state.stage = "duel_setup"
        state.setupStartedAt = now
        state.setupDeadlineAt = now + SETUP_MS
        state.duelSession = SESSION
        speak(group, "boast")
        return true, "duel_setup_started"
    elseif action == "decline_duel" or action == "cancel_duel" then
        if state.stage ~= "challenged" and state.stage ~= "duel_setup" then
            return false, "duel_not_waiting"
        end
        if not near(group, player) then return false, "too_far_away" end
        state.stage = "declined"
        speak(group, "decline")
        return true, "duel_declined"
    elseif action == "claim_gear" then
        if state.stage ~= "won" then return false, "duel_not_won" end
        if not near(group, player) then return false, "too_far_away" end
        return claimGear(group, player, state)
    elseif action == "recruit" then
        if not Clem.canRecruit(group) then return false, "duel_win_required" end
        if not near(group, player) then return false, "too_far_away" end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, reason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "unsupported_clem_action"
end

return Clem
