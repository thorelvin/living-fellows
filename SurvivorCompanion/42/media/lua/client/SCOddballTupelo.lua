-- SPDX-License-Identifier: MIT
-- The King's invitation grants a real bar-looting exception; the boys fight
-- through the normal faction combat path and recruit one named member.

local SC = SurvivorCompanion
SC.OddballTupelo = SC.OddballTupelo or {}
local Tupelo = SC.OddballTupelo
local ID = "tupelo_boys"
local MUSIC = { ["Base.GuitarAcoustic"] = true,
    ["Base.Magazine_Music"] = true,
    ["Base.Magazine_Music_New"] = true }

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    value.gearSeeded = value.gearSeeded or {}
    value.recruitmentCandidateKey = "member-2"
    return value
end

local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function near(group, player)
    for index = 1, #(group.members or {}) do
        local actor = actorFor(group, index)
        if actor and player and U().distance(actor, player) <= 7
            and U().canSee(player, actor) == true then return true end
    end
    return false
end

local function musicItem(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if MUSIC[U().itemType(item)] then return item end
    end
    return nil
end

function Tupelo.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "tupelo_unavailable" end
    local index
    for current = 1, #(group.members or {}) do
        if actor == actorFor(group, current) then index = current; break end
    end
    if not index then return false, "tupelo_member_missing" end
    if value.gearSeeded[index] then return true, "gear_already_seeded" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "tupelo_inventory_unavailable" end
    local kind = index == 3 and "Base.GuitarAcoustic" or "Base.Pistol"
    local weapon = U().addItem(inventory, kind)
    if not weapon then return false, "tupelo_weapon_unavailable" end
    U().call(actor, "setPrimaryHandItem", weapon)
    if kind == "Base.Pistol" then
        U().call(weapon, "setCurrentAmmoCount", 10)
        U().addItem(inventory, "Base.Bullets9mmBox")
    end
    value.gearSeeded[index] = true
    return true, "tupelo_armed"
end

function Tupelo.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local leader = actorFor(group, 1)
    if leader and near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(leader,
            "Thank you. Thank you very much. Now state your business.")
    end
    return true, value.stage
end

function Tupelo.onZombieDead(group, zombie, attacker)
    local value = story(group)
    if not value or not attacker then return false end
    local memberIndex
    for index = 1, #(group.members or {}) do
        if attacker == actorFor(group, index) then memberIndex = index; break end
    end
    if not memberIndex then return false end
    local current = U().nowMs()
    if current >= (tonumber(value.nextFightLineAt) or 0) then
        value.nextFightLineAt = current + 30000
        U().say(attacker,
            memberIndex == 1 and "This block's got rules, son. Rule one: respect."
                or "Keep the beat. Keep the dead out.")
    end
    return true
end

function Tupelo.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function Tupelo.canRecruit(group)
    local value = story(group)
    return value and value.blessing == true
        and group.standing == "Trusted"
        and group.members and group.members[2]
        and group.members[2].alive ~= false
end

function Tupelo.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if group.standing == "Hostile" then return {} end
    local options = { { id = "ask_king", label = "Ask for the King's blessing",
        enabled = true } }
    if not value.blessing then
        options[#options + 1] = {
            id = "offer_music", label = "Bring the King some music",
            enabled = musicItem(player) ~= nil,
            detail = "A guitar or a music magazine opens this block" }
    else
        local candidate = actorFor(group, 2)
        local recruitment = SC.FactionRecruitment
            and type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if recruitment and recruitment.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask Jerry for his decision",
                enabled = recruitment.canDecide == true }
        elseif not recruitment or recruitment.status ~= "joined" then
            options[#options + 1] = { id = "recruit",
                label = "Ask Jerry to ride with you",
                enabled = candidate ~= nil and U().distance(player,
                    candidate) <= 6 }
        end
    end
    return options
end

function Tupelo.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) or group.standing == "Hostile" then
        return false, "tupelo_unavailable"
    end
    local leader = actorFor(group, 1)
    if action == "ask_king" then
        U().say(leader, value.blessing
            and "You can take what you need. Leave something worth singing about."
            or "Bring me music. Then this block is yours to walk.")
        return true, "king_spoke"
    end
    if action == "offer_music" then
        if value.blessing then return false, "blessing_already_given" end
        local item = musicItem(player)
        local source = item and select(1, U().call(item, "getContainer"))
        local destination = leader and U().inventory(leader)
        if not item or not source or not destination
            or not U().transferItemVerified(source, destination, item) then
            return false, "music_transfer_failed"
        end
        value.blessing = true
        value.stage = "trusted"
        local accepted = SC.Factions.forceStanding(group.id, "Trusted")
        if not accepted then
            U().transferItemVerified(destination, source, item)
            value.blessing, value.stage = false, "unmet"
            return false, "trust_change_failed"
        end
        U().say(leader,
            "Now that's a song. You have the King's blessing. Mind the boys.")
        return true, "block_opened_by_real_music"
    end
    if action == "recruit" then
        if not Tupelo.canRecruit(group) then
            return false, "king_trust_required"
        end
        local candidate = actorFor(group, 2)
        if not candidate or U().distance(player, candidate) > 6 then
            return false, "jerry_too_far"
        end
        if not SC.FactionRecruitment then
            return false, "recruitment_unavailable"
        end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, reason = SC.FactionRecruitment.ask(
                group.id, player, false)
            if not asked then return false, reason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    if action == "recruitment_decide" and SC.FactionRecruitment then
        return SC.FactionRecruitment.decide(group.id, player)
    end
    return false, "unknown_tupelo_choice"
end

return Tupelo
