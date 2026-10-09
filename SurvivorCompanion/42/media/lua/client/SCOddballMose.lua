-- SPDX-License-Identifier: MIT
-- An old sniper waits on an actual wooded porch. He respects a stealthy
-- approach, fights if attacked, and dies by the native life-ending path after
-- seven in-game days away, leaving his real rifle and note in the corpse.

local SC = SurvivorCompanion
SC.OddballMose = SC.OddballMose or {}
local Mose = SC.OddballMose
local ID = "sniper_old_mose_calloway"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "watching"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function dayNow()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local hours = select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(hours) and math.floor(tonumber(hours) / 24) or nil
end

local function rifle(actor)
    local inv = actor and U().inventory(actor)
    for _, item in ipairs(inv and U().inventoryItemsDeep(inv, 120, 4)
        or {}) do
        if U().itemType(item) == "Base.HuntingRifle" then return item end
    end
    return nil
end

local function stealthApproach(player)
    if not player or not SC.Commands
        or type(SC.Commands.teamCombatDoctrine) ~= "function"
        or SC.Commands.teamCombatDoctrine(player) ~= "stealth" then
        return false
    end
    local sneaking = select(1, U().call(player, "isSneaking"))
    if sneaking ~= true then
        sneaking = select(1, U().call(player, "isCrouching"))
    end
    return sneaking == true
end

local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= (radius or 4)
        and U().canSee(player, actor) == true
end

local function leaveNote(group, value, actor)
    if value.notePlaced == true then return true end
    local inventory = U().inventory(actor)
    if not inventory then return false, "mose_inventory_unavailable" end
    local note = U().addItem(inventory, "Base.LetterHandwritten")
    if not note then return false, "mose_note_unavailable" end
    U().call(note, "setName",
        "Mose's note: Waited for you. Got tired. Rifle's yours. Keep it oiled.")
    local data = U().modData(note)
    if type(data) == "table" then data.lfMoseGroupId = group.id end
    value.notePlaced = true
    return true
end

function Mose.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "mose_unavailable" end
    if value.stage == "unmet" then value.stage = "watching" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "mose_inventory_unavailable" end
    if value.rifleSeeded ~= true then
        local weapon = rifle(actor) or U().addItem(inventory,
            "Base.HuntingRifle")
        if not weapon then return false, "mose_rifle_unavailable" end
        U().call(actor, "setPrimaryHandItem", weapon)
        U().addItem(inventory, "Base.308Box")
        value.rifleSeeded = true
    end
    return true, "mose_on_porches"
end

function Mose.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local actor = actorFor(group)
    if not actor then return true, "mose_unloaded" end
    local day = dayNow()
    if player and U().distance(actor, player) <= 40
        and value.firstSeenDay == nil then
        value.firstSeenDay = day
        group.discovered = true
    end
    if value.stage == "dying" then
        local dead = select(1, U().call(actor, "isDead"))
        if dead == true then
            value.stage = "dead"
            if SC.Oddballs then SC.Oddballs.retire(group, "dead_of_age") end
        end
        return true, value.stage
    end
    if value.stage == "watching" and value.firstSeenDay and day
        and day - value.firstSeenDay >= 7 then
        local placed, reason = leaveNote(group, value, actor)
        if not placed then return false, reason end
        if not SC.Actor or type(SC.Actor.endLife) ~= "function" then
            return false, "native_life_end_unavailable"
        end
        local ended, endReason = SC.Actor.endLife(actor)
        if ended ~= true then return false, endReason end
        value.stage = "dying"
        return true, "mose_age_death_requested"
    end
    if value.stage == "watching" and player
        and U().distance(actor, player) <= 40
        and not stealthApproach(player)
        and current >= (tonumber(value.nextWarningAt) or 0) then
        value.nextWarningAt = current + 40000
        U().call(actor, "playSound", "MSR788Shoot")
        U().say(actor,
            "That was a warning. I'm ninety-one and I don't miss twice.")
        return true, "mose_warning_shot"
    end
    return true, value.stage
end

function Mose.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "mose_perch", priority = 30 }
end

function Mose.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "mose_perch" then return false end
    local post = story(group).site and story(group).site.spawn
    if not post then return true, "porch_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 2.25 then
        if player and U().distance(actor, player) <= 40 then
            return U().move(actor, "walk", { action = "face_alert",
                target = player, facingTarget = player,
                stableFacing = true, weaponReady = true,
                humanAnimationOnly = true })
        end
        return true, "mose_waiting"
    end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return true, "porch_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_perch", arrivalDistance = 1.5 })
end

function Mose.canRecruit()
    return false, "mose_stays_at_his_cabin"
end

function Mose.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    return { { id = "ask_patience", label = "Ask why he waits",
        enabled = value.stage == "watching" },
        { id = "stealth_yield", label = "Ask the surprised sniper to yield",
            enabled = value.stage == "watching" and stealthApproach(player) } }
end

function Mose.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        U().say(actorFor(group), "You chose a fight. I warned you.")
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "mose_too_far" end
    local actor = actorFor(group)
    if action == "ask_patience" and value.stage == "watching" then
        U().say(actor, "Patience is the only weapon that never jams.")
        return true, "mose_patience"
    elseif action == "stealth_yield" and value.stage == "watching" then
        if not stealthApproach(player) then
            return false, "stealth_and_crouch_required"
        end
        local weapon = rifle(actor)
        local source = weapon and select(1, U().call(weapon,
            "getContainer"))
        local destination = player and U().inventory(player)
        if not source or not destination or not weapon
            or not U().transferItemVerified(source,
                destination, weapon) then
            return false, "rifle_transfer_failed"
        end
        U().call(actor, "setPrimaryHandItem", nil)
        value.stage = "yielded"
        SC.Factions.forceStanding(group.id, "Wary")
        local clean = U().config and U().config("profanityEnabled") == false
        U().say(actor, clean
            and "Ninety-one and still a better shot than you, you little pup."
            or "Ninety-one and still a better shot than you, you little shit.")
        return true, "mose_yielded_real_rifle"
    end
    return false, "unknown_mose_choice"
end

return Mose
