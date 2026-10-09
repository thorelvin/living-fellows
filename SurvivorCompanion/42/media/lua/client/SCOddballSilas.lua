-- SPDX-License-Identifier: MIT
-- Brother Silas Crane. The faction owns standing and combat; this module owns
-- the church story, one physical confession trade, and the leader's aftermath.

local SC = SurvivorCompanion
SC.OddballSilas = SC.OddballSilas or {}
local Silas = SC.OddballSilas

local ID = "cult_brother_silas"
local CHURCH_KILL_RADIUS = 30
local TALK_RANGE = 8
local REWARD_TYPES = { "Base.TinnedBeans", "Base.Candle" }
local JOIN_REQUEST = "Silas is gone. Could I come with you?"
local JOIN_PROMPT = "A surviving cultist asks to join your group."

local lines = {
    greet = "Lower your voice. The sleepers are resting.",
    history = "Meat fell from a clear sky in Bath County. We were warned.",
    creed = "You call them dead. We call them early.",
    confess = "Confess your iron at the altar, and you may break bread.",
    warning = "Do not strike another sleeper beside this church.",
    hostile = "You struck a sleeper. Now you'll sleep beside him.",
    traded = "Leave the iron there. Take these, and walk softly.",
    farewell = "His long sleep came before ours. Go while you can.",
}

local function U() return SC.GameplayUtil end

local function stateFor(group)
    local state = type(group) == "table" and group.oddball or nil
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    state.sleeperKills = math.max(0, math.min(2,
        math.floor(tonumber(state.sleeperKills) or 0)))
    state.equipmentSeeded = type(state.equipmentSeeded) == "table"
        and state.equipmentSeeded or {}
    state.joinRequestSpoken = type(state.joinRequestSpoken) == "table"
        and state.joinRequestSpoken or {}
    return state
end

local function memberFor(group, actor)
    local actorId = actor and U().idOf(actor)
    for index, member in ipairs(group.members or {}) do
        if actorId and member.actorId == actorId then return member, index end
    end
    return nil
end

function Silas.actor(group)
    local lead = group and group.members and group.members[1]
    local record = lead and lead.actorId and SC.Registry
        and SC.Registry.byId(lead.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, topic)
    local actor = Silas.actor(group)
    return actor ~= nil and lines[topic] ~= nil
        and U().say(actor, lines[topic]) == true
end

local function nearby(group, player)
    local actor = Silas.actor(group)
    return actor ~= nil and player ~= nil
        and U().distance(actor, player) <= TALK_RANGE
        and (not U().canSee or U().canSee(player, actor) == true)
end

local function churchAnchor(group, state)
    return state.site and (state.site.altar or state.site.spawn
        or state.site.anchor) or group.house and group.house.anchor
end

local function atChurch(group, state, value, radius)
    local anchor = churchAnchor(group, state)
    return anchor ~= nil and value ~= nil
        and U().distance(value, anchor) <= radius
end

local function isPartyKiller(attacker, player)
    if attacker == nil then return false end
    if attacker == player then return true end
    local id = U().idOf(attacker)
    local record = id and SC.Registry and SC.Registry.byId(id) or nil
    return record ~= nil and record.recruited == true
end

local function turnHostile(group, state, reason)
    if state.stage == "hostile" then return true, "already_hostile" end
    if state.stage == "aftermath" or state.stage == "leader_dead" then
        return false, "cult_has_disbanded"
    end
    if not SC.Factions or type(SC.Factions.forceStanding) ~= "function" then
        return false, "standing_unavailable"
    end
    local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
    if not changed then return false, why or "standing_change_failed" end
    group.permanentHostility = true
    state.stage = "hostile"
    state.hostileReason = reason
    speak(group, "hostile")
    return true, "cult_hostile"
end

-- Relayed from the existing OnZombieDead owner. This callback never infers a
-- kill merely because a zombie died nearby; the player or a recruited fellow
-- must actually be credited as attacker.
function Silas.onZombieDead(group, zombie, attacker, player)
    local state = stateFor(group)
    if not state or state.stage == "hostile" or state.stage == "aftermath"
        or state.stage == "leader_dead" then return false, "cult_inactive" end
    if not isPartyKiller(attacker, player) then return false, "not_party_kill" end
    if not atChurch(group, state, zombie, CHURCH_KILL_RADIUS) then
        return false, "outside_church_grounds"
    end
    local data = U().modData(zombie)
    local key = "LF_SilasWitnessed_" .. tostring(group.id)
    if type(data) ~= "table" then return false, "zombie_death_data_unavailable" end
    if data[key] == true then return false, "already_witnessed" end
    data[key] = true
    if state.sleeperKills == 0 then
        state.sleeperKills = 1
        state.stage = "warned"
        group.discovered = true
        speak(group, "warning")
        return true, "sermon_warning"
    end
    local hostile, why = turnHostile(group, state, "second_sleeper_killed")
    if not hostile then data[key] = nil return false, why end
    state.sleeperKills = 2
    return true, "second_kill_hostile"
end

local function findItem(actor, fullType)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == fullType then return item end
    end
    return nil
end

function Silas.onSpawn(group, actor)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local member, index = memberFor(group, actor)
    if not member then return false, "cult_member_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "cult_inventory_unavailable" end
    local weaponType = index == 1 and "Base.Sword" or "Base.Machete"
    local weapon = findItem(actor, weaponType)
    if not weapon and state.equipmentSeeded[member.key] ~= true then
        weapon = U().addItem(inventory, weaponType)
        if not weapon then return false, "cult_weapon_unavailable" end
    end
    state.equipmentSeeded[member.key] = true
    if weapon and not select(1, U().call(actor, "getPrimaryHandItem")) then
        U().call(actor, "setPrimaryHandItem", weapon)
    end
    return true, "cult_member_ready"
end

local function chooseConfessionWeapon(player)
    local held = select(1, U().call(player, "getPrimaryHandItem"))
    if held and (U().instanceOf(held, "HandWeapon")
        or U().hasMethod(held, "getMaxDamage")) then return held end
    return nil
end

local function deliverReward(group, player)
    local state = stateFor(group)
    if not state or state.confessionPending ~= true then
        return false, "no_confession_due"
    end
    local inventory = player and U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    local nextReward = math.max(1, math.min(#REWARD_TYPES + 1,
        math.floor(tonumber(state.nextReward) or 1)))
    for index = nextReward, #REWARD_TYPES do
        local item, reason = U().addItem(inventory, REWARD_TYPES[index])
        if not item then
            state.nextReward = index
            return false, reason or "confession_reward_pending"
        end
        state.nextReward = index + 1
    end
    state.confessionPending = false
    state.confessionCompleted = true
    state.stage = state.sleeperKills > 0 and "warned" or "traded"
    speak(group, "traded")
    return true, "confession_trade_complete"
end

local function confess(group, player)
    local state = stateFor(group)
    if state.confessionCompleted == true then return false, "already_confessed" end
    if state.confessionPending == true then return deliverReward(group, player) end
    local weapon = chooseConfessionWeapon(player)
    if not weapon then return false, "weapon_required" end
    local source = select(1, U().call(weapon, "getContainer"))
    if not source or U().containerContainsIdentity(source, weapon) ~= true then
        return false, "weapon_owner_unavailable"
    end
    local anchor = churchAnchor(group, state)
    local square = anchor and U().gridSquare(anchor.x, anchor.y, anchor.z or 0)
    if not square then return false, "altar_unloaded" end
    local primary = select(1, U().call(player, "getPrimaryHandItem"))
    local secondary = select(1, U().call(player, "getSecondaryHandItem"))
    if primary == weapon then U().call(player, "setPrimaryHandItem", nil) end
    if secondary == weapon then U().call(player, "setSecondaryHandItem", nil) end
    local dropped, reason = U().dropItem(source, square, weapon)
    if not dropped then
        if primary == weapon then U().call(player, "setPrimaryHandItem", weapon) end
        if secondary == weapon then U().call(player, "setSecondaryHandItem", weapon) end
        return false, reason or "altar_drop_failed"
    end
    state.confessionPending = true
    state.nextReward = 1
    return deliverReward(group, player)
end

local function beginAftermath(group, state)
    if state.stage == "aftermath" or state.stage == "leader_dead" then return end
    state.stage = "aftermath"
    state.aftermath = {}
    local survivors = {}
    for index = 2, #(group.members or {}) do
        local member = group.members[index]
        if member.alive ~= false and member.departed ~= true then
            survivors[#survivors + 1] = member.key
        end
    end
    local fleeCount = math.floor(#survivors / 2)
    for index, key in ipairs(survivors) do
        state.aftermath[key] = index <= fleeCount and "flee" or "ask_join"
    end
    speak(group, "farewell")
end

local function askToJoin(group, state, memberKey, actorId, player)
    if state.joinRequestSpoken[memberKey] == true then return end
    local record = actorId and SC.Registry and SC.Registry.byId(actorId) or nil
    local actor = record and record.actor
    local spoken = actor and U().isValidActor(actor)
        and U().say(actor, JOIN_REQUEST) == true
    if not spoken and player then
        -- A busy native actor may refuse speech just after a fight. Leave a
        -- visible fallback instead of silently changing it to neutral.
        -- GameplayUtil.say deliberately rejects the local player, so use
        -- their native overhead bubble directly for this notification.
        local _, shown = U().call(player, "Say", JOIN_PROMPT)
        spoken = shown == true
    end
    if spoken then state.joinRequestSpoken[memberKey] = true end
end

local function finishAftermath(group, state, player)
    if not SC.Factions or type(SC.Factions.releaseOddballMember) ~= "function" then
        return false, "member_release_unavailable"
    end
    local pending = false
    for _, member in ipairs(group.members or {}) do
        local choice = state.aftermath and state.aftermath[member.key]
        if choice and member.alive ~= false and member.departed ~= true then
            local released, actorId = SC.Factions.releaseOddballMember(group.id,
                member.key, choice == "flee" and "wander" or "stay")
            if released then
                state.aftermath[member.key] = choice .. "_released"
                if choice == "ask_join" then
                    askToJoin(group, state, member.key, actorId, player)
                end
            else pending = true end
        end
    end
    if pending then return false, "cult_survivors_pending" end
    state.stage = "leader_dead"
    group.lifecycle = "destroyed"
    if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
        SC.Oddballs.retire(group, "leader_dead")
    end
    return true, "cult_survivors_released"
end

function Silas.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local leader = group.members and group.members[1]
    if leader and leader.alive == false then
        beginAftermath(group, state)
        return finishAftermath(group, state, player)
    end
    if state.confessionPending == true and nearby(group, player) then
        deliverReward(group, player)
    end
    if state.stage == "unmet" and nearby(group, player) then
        state.stage = "met"
        group.discovered = true
        speak(group, "greet")
        if SC.Registry and type(SC.Registry.living) == "function" then
            for _, fellow in ipairs(SC.Registry.living()) do
                local record = SC.Registry.byId(U().idOf(fellow))
                if record and record.recruited == true
                    and U().distance(fellow, player) <= 8 then
                    U().say(fellow,
                        "They're praying to them. They're actually praying to them.")
                    break
                end
            end
        end
    end
    return true, state.stage
end

function Silas.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    if state.stage == "aftermath" or state.stage == "leader_dead" then
        return { priority = 120, kind = "faction", mode = "silas_departure" }
    end
    if state.stage == "hostile" or group.standing == "Hostile" then
        return { priority = 110, kind = "faction", mode = "hostile" }
    end
    return { priority = 30, kind = "faction", mode = "silas_church_guard" }
end

-- The congregation refuses to strike its "sleepers". This is deliberately
-- separate from zombiesIgnore: zombies remain free to attack cultists.
function Silas.avoidsZombieCombat(actor, group)
    local state = stateFor(group)
    return state ~= nil and state.stage ~= "leader_dead"
end

function Silas.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local mode = intent and intent.mode
    if mode == "hostile" or mode == "zombie_defense" then
        return false, "delegate_native_combat"
    end
    if mode == "silas_departure" then U().stop(actor) return true, "disbanding" end
    if mode ~= "silas_church_guard" then return false, "wrong_cult_intent" end
    local _, index = memberFor(group, actor)
    local point = state.site and state.site.memberSpawns
        and state.site.memberSpawns[index] or nil
    point = point or churchAnchor(group, state)
    if point and U().distance(actor, point) > 2.5 and SC.Navigation
        and type(SC.Navigation.request) == "function" then
        local square = U().gridSquare(point.x, point.y, point.z or 0)
        if square then
            return SC.Navigation.request(actor, square, "walk", {
                action = "cult_return_church", arrivalDistance = 1.5 })
        end
    end
    U().stop(actor)
    return true, "keeping_church"
end

function Silas.canRecruit(group)
    return false, "silas_is_not_recruitable"
end

function Silas.menuOptions(group, player)
    local state = stateFor(group)
    if not state or state.stage == "hostile" or state.stage == "aftermath"
        or state.stage == "leader_dead" then return {} end
    local near = nearby(group, player)
    local offeredWeapon = chooseConfessionWeapon(player)
    local weaponName = offeredWeapon and select(1,
        U().call(offeredWeapon, "getDisplayName")) or nil
    if type(weaponName) ~= "string" or weaponName == "" then
        weaponName = offeredWeapon and U().itemType(offeredWeapon) or "weapon"
    end
    local options = {
        { id = "ask_creed", label = "Ask Brother Silas about the sleepers",
            enabled = near },
    }
    if state.confessionCompleted ~= true then
        options[#options + 1] = {
            id = "confess", label = state.confessionPending
                and "Claim food and candle"
                or ("Leave held " .. tostring(weaponName) .. " at the altar"),
            enabled = near and (state.confessionPending == true
                or offeredWeapon ~= nil),
            detail = "Trades the weapon in your primary hand for food and a candle",
        }
    end
    return options
end

function Silas.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hurt" then return turnHostile(group, state, "player_attack") end
    if state.stage == "hostile" or state.stage == "aftermath"
        or state.stage == "leader_dead" then return false, "cult_not_talking" end
    if not nearby(group, player) then return false, "too_far_away" end
    if action == "ask_creed" then
        speak(group, state.sleeperKills > 0 and "history" or "creed")
        return true, "creed_explained"
    elseif action == "confess" then
        speak(group, "confess")
        return confess(group, player)
    end
    return false, "unsupported_cult_action"
end

return Silas
