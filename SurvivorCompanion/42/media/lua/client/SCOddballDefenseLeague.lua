-- SPDX-License-Identifier: MIT
-- Four armed inspectors at a road junction. The player's explicit surrender
-- choice uses the same native final action as infection-crisis mercy killing.

local SC = SurvivorCompanion
SC.OddballDefenseLeague = SC.OddballDefenseLeague or {}
local League = SC.OddballDefenseLeague
local ID = "knox_defense_league"
local CHECK_RANGE = 8
local nextLineAt = {}

local lines = {
    challenge = "Line up. Sleeves up. Nobody's offended, nobody's shot.",
    clean = "You're clean. Wear this. Saves you the trouble next time.",
    infected = "That one's bit. Step away from them. Now.",
    lie = "We're not monsters. We're the reason there's still people. Let us look.",
    refusal = "You made your choice. I won't let a bite through this road.",
    surrender = "I'm sorry. This is the part nobody trained us for.",
    farewell = "Keep moving. Don't make me check you twice.",
    companion = "Let them look. We've got nothing to hide. Right? Right?",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    return value
end

local function leader(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function say(group, key)
    local actor = leader(group)
    return actor and lines[key] and U().say(actor, lines[key]) == true or false
end

local function near(group, player)
    local actor = leader(group)
    return actor and player and U().distance(actor, player) <= CHECK_RANGE
        and U().canSee(player, actor) == true
end

local function memberFor(group, actor)
    local id = U().idOf(actor)
    for index, member in ipairs(group.members or {}) do
        if member.actorId == id then return member, index end
    end
    return nil
end

local function party(player)
    local result = {}
    if not player or not SC.Registry or type(SC.Registry.living) ~= "function" then
        return result
    end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        if record and record.recruited == true and U().isValidActor(actor)
            and U().distance(actor, player) <= CHECK_RANGE then
            result[#result + 1] = { actor = actor, record = record }
        end
    end
    return result
end

local function infectedFellow(player)
    if not SC.Medical or type(SC.Medical.assess) ~= "function" then
        return nil, "medical_inspection_unavailable"
    end
    for _, fellow in ipairs(party(player)) do
        -- Fresh native body facts are required here, including a hidden bite
        -- or Knox infection. A stale presentation cache could condemn someone.
        local okay, assessment = pcall(SC.Medical.assess, fellow.actor)
        if not okay or type(assessment) ~= "table" then
            return nil, "medical_inspection_unavailable"
        end
        if assessment.knoxInfected == true or (assessment.bites or 0) > 0 then
            return fellow
        end
    end
    return false
end

local function hostile(group, value, reason)
    if value.stage == "hostile" then return true, "already_hostile" end
    local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
    if not changed then return false, why end
    group.permanentHostility = true
    value.stage, value.hostileReason = "hostile", reason
    say(group, "refusal")
    return true, "league_hostile"
end

local function inspect(group, value, player)
    local infected, reason = infectedFellow(player)
    if infected == nil then return false, reason end
    if infected then
        value.stage = "demand"
        value.infectedActorId = infected.record.id
        say(group, "infected")
        return true, "infected_fellow_found"
    end
    local inventory = U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    -- A successful check earns one real badge. It is never replaced on reload.
    if value.cleanPassIssued ~= true then
        local badge = U().addItem(inventory, "Base.Badge")
        if not badge then return false, "badge_unavailable" end
        U().call(badge, "setName", "Knox Defense League clean pass")
        value.cleanPassIssued = true
    end
    value.stage = "passed"
    say(group, "clean")
    return true, "league_clean_pass"
end

function League.onSpawn(group, actor)
    local value = story(group)
    local member = memberFor(group, actor)
    if not value or not member then return false, "league_member_unavailable" end
    value.armed = type(value.armed) == "table" and value.armed or {}
    if value.armed[member.key] then return true, "league_member_ready" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "league_inventory_unavailable" end
    local gunType = (member.role == "leader" or member.role == "rifleman")
        and "Base.AssaultRifle" or "Base.Shotgun"
    local gun
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == gunType then gun = item break end
    end
    gun = gun or U().addItem(inventory, gunType)
    if not gun then return false, "league_weapon_unavailable" end
    local ammo = gunType == "Base.AssaultRifle"
        and "Base.556Box" or "Base.ShotgunShellsBox"
    if not U().addItem(inventory, ammo) then
        return false, "league_ammunition_unavailable"
    end
    U().call(gun, "setCurrentAmmoCount",
        gunType == "Base.AssaultRifle" and 20 or 6)
    U().call(actor, "setPrimaryHandItem", gun)
    U().call(actor, "setSecondaryHandItem", gun)
    value.armed[member.key] = true
    return true, "league_member_armed"
end

function League.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "execution" then
        local record = value.infectedActorId and SC.Registry
            and SC.Registry.byId(value.infectedActorId) or nil
        local actor = record and record.actor
        local inspector = leader(group)
        if actor and U().isDead(actor)
            or value.executionApplied == true and not actor then
            value.stage = "passed"
            value.executedActorId = value.infectedActorId
            return true, "fellow_executed"
        end
        if value.executionApplied == true then
            return true, "awaiting_native_death_confirmation"
        end
        if not actor or not inspector or not U().isValidActor(actor) then
            value.stage = "demand"
            return false, "execution_target_unavailable"
        end
        if not SC.NativeActions
            or type(SC.NativeActions.performEndOfLife) ~= "function" then
            value.stage = "demand"
            return false, "native_execution_unavailable"
        end
        local accepted, reason = SC.NativeActions.performEndOfLife(
            inspector, "mercy", actor)
        if reason == "native_final_injury_applied" then
            value.executionApplied = true
        elseif accepted ~= true then
            value.stage = "demand"
        end
        return accepted, reason
    end
    if value.stage == "unmet" and near(group, player) then
        value.stage = "inspection"
        group.discovered = true
        say(group, "challenge")
        local fellows = party(player)
        if fellows[1] then U().say(fellows[1].actor, lines.companion) end
        return true, "league_stopped_party"
    end
    if value.stage == "demand" and near(group, player)
        and current >= (nextLineAt[group.id] or 0) then
        nextLineAt[group.id] = current + 90000
        say(group, "infected")
    end
    return true, value.stage
end

function League.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "league_checkpoint", priority = 30 }
end

function League.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "league_checkpoint" then return false end
    local member, index = memberFor(group, actor)
    local site = story(group).site
    local post = member and site and site.memberSpawns
        and site.memberSpawns[index] or nil
    if not post then return true, "checkpoint_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0) and (x - post.x) ^ 2
        + (y - post.y) ^ 2 <= 2.25 then
        return true, "holding_checkpoint"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return true, "checkpoint_post_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_checkpoint", arrivalDistance = 1.5 })
end

function League.canRecruit()
    return false, "league_does_not_join"
end

function League.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "inspection" or value.stage == "unmet" then
        return { { id = "submit_check", label = "Submit the party to a bite check",
            enabled = true } }
    end
    if value.stage == "demand" then
        return {
            { id = "surrender", label = "Hand over the bitten companion",
                enabled = true, detail = "The League will execute them" },
            { id = "refuse", label = "Refuse and defend your companion",
                enabled = true, detail = "The checkpoint turns hostile" },
            { id = "lie", label = "Say they aren't bitten",
                enabled = true, detail = "The League checks again" },
        }
    end
    return {}
end

function League.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" or action == "hit_player" then
        return hostile(group, value, "attack")
    end
    if not near(group, player) then return false, "checkpoint_too_far" end
    if action == "submit_check" and (value.stage == "inspection"
        or value.stage == "unmet") then
        return inspect(group, value, player)
    end
    if value.stage ~= "demand" then return false, "checkpoint_choice_unavailable" end
    if action == "refuse" then return hostile(group, value, "refused_handover") end
    if action == "lie" then
        say(group, "lie")
        return inspect(group, value, player)
    end
    if action == "surrender" then
        local record = value.infectedActorId and SC.Registry
            and SC.Registry.byId(value.infectedActorId) or nil
        if not record or not record.actor or not U().isValidActor(record.actor)
            or U().distance(record.actor, player) > CHECK_RANGE then
            return false, "infected_fellow_not_present"
        end
        local assessment = SC.Medical and SC.Medical.assess(record.actor)
        if not assessment or not (assessment.knoxInfected == true
            or (assessment.bites or 0) > 0) then
            return inspect(group, value, player)
        end
        value.stage = "execution"
        say(group, "surrender")
        return true, "league_execution_authorized"
    end
    return false, "unknown_checkpoint_choice"
end

return League
