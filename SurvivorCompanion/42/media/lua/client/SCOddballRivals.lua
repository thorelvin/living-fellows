-- SPDX-License-Identifier: MIT
-- Two linked, separately owned factions. Their feud uses the existing human
-- combat path; mediation uses an exact clipping or a caring recruited fellow.

local SC = SurvivorCompanion
SC.OddballRivals = SC.OddballRivals or {}
local Rivals = SC.OddballRivals
local PEST = "doctor_pest"
local BOLT = "bluegrass_bolt"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or (value.id ~= PEST
        and value.id ~= BOLT) then return nil end
    value.stage = value.stage or "feud"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function rivalGroup(group)
    local value = story(group)
    return value and value.rivalGroupId and SC.Factions
        and SC.Factions.group(value.rivalGroupId) or nil
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function itemFor(actor, predicate)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        if predicate(U().itemType(item), item) then return item end
    end
    return nil
end

local function clipping(_, item)
    local data = U().modData(item)
    return data and data.lfRivalClipping == true
end

local function caringFellow(player)
    if not SC.Registry or type(SC.Registry.living) ~= "function"
        or not SC.Commands or type(SC.Commands.peek) ~= "function" then
        return nil
    end
    for _, actor in ipairs(SC.Registry.living() or {}) do
        local id = U().idOf(actor)
        local record = id and SC.Registry.byId(id) or nil
        local state = record and record.recruited == true
            and SC.Commands.peek(actor) or nil
        local profile = state and state.personalityProfile
        if record and record.recruited == true
            and actor ~= player and U().distance(actor, player) <= 8
            and type(profile) == "table"
            and (profile.archetype == "caring"
                or (tonumber(profile.compassion) or 0) >= 70) then
            return actor
        end
    end
    return nil
end

local function reconcile(group, mediator)
    local other = rivalGroup(group)
    local own, rival = story(group), story(other)
    if not other or not rival or other.lifecycle == "destroyed" then
        return false, "rival_no_longer_available"
    end
    own.stage, rival.stage = "mediated", "mediated"
    own.feudActive, rival.feudActive = false, false
    local first = SC.Factions.forceStanding(group.id, "Trusted")
    local second = SC.Factions.forceStanding(other.id, "Trusted")
    if not first or not second then return false, "mediation_standing_failed" end
    local speaker = actorFor(group)
    if speaker then U().say(speaker,
        mediator and "A real person asked us to stop. That's more heroic than either costume."
            or "The paper called it a publicity stunt. We made it a war.") end
    local rivalActor = actorFor(other)
    if rivalActor then U().say(rivalActor,
        "Justice takes a break. A long, overdue break.") end
    return true, "rival_feud_mediated"
end

function Rivals.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "rival_unavailable" end
    if value.gearSeeded == true then return true, "rival_gear_ready" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "rival_inventory_unavailable" end
    local gear = value.id == PEST and "Base.KnapsackSprayer"
        or "Base.Glasses_Aviators"
    local item = itemFor(actor, function(kind) return kind == gear end)
    if not item then item = U().addItem(inventory, gear) end
    if not item then return false, "rival_costume_unavailable" end
    if value.id == PEST then
        U().call(actor, "setWornItem", "Back", item)
        local news = U().addItem(inventory, "Base.Newspaper")
        if news then
            U().call(news, "setName",
                "Kentucky Gazette: Costume Feud Staged for Radio")
            local data = U().modData(news)
            if data then data.lfRivalClipping = true end
        end
    else
        U().call(actor, "setWornItem", "Eyes", item)
    end
    value.gearSeeded = true
    return true, "rival_costumed"
end

function Rivals.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    local other = rivalGroup(group)
    if other and other.lifecycle == "destroyed"
        and value.stage ~= "mediated" and value.stage ~= "victory" then
        value.stage = "victory"
        value.feudActive = false
        SC.Factions.forceStanding(group.id, "Trusted")
        if actor then U().say(actor,
            "I wanted the feud to end. I didn't say I wanted a funeral.") end
    end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor, value.id == PEST
            and "Vermin, vermin everywhere. And the worst wears a cape."
            or "Justice never sleeps. Justice naps. Briefly. Heroically.")
    end
    return true, value.stage
end

function Rivals.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    local opponent = value.feudActive == true and actorFor(rivalGroup(group))
    if opponent and U().distance(actor, opponent) <= 15 then
        local x, y, z = U().position(opponent)
        return { mode = "hostile", priority = 108,
            humanThreat = { actor = opponent, id = U().idOf(opponent),
                x = x, y = y, z = z,
                visible = U().canSee(actor, opponent) == true } }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Rivals.canRecruit(group)
    local value = story(group)
    return value and (value.stage == "mediated"
        or value.stage == "victory")
        and group.members and group.members[1]
        and group.members[1].alive ~= false
end

function Rivals.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player)
        or group.standing == "Hostile" then return {} end
    local options = {}
    if value.stage ~= "mediated" and value.stage ~= "victory" then
        options[#options + 1] = { id = "ask_feud",
            label = "Ask about the costumed feud", enabled = true }
        options[#options + 1] = { id = "take_side",
            label = "Promise to defeat the rival", enabled = rivalGroup(group) ~= nil }
        options[#options + 1] = { id = "mediate_caring",
            label = "Let a caring fellow mediate",
            enabled = caringFellow(player) ~= nil }
        options[#options + 1] = { id = "show_clipping",
            label = "Show the old radio-stunt clipping",
            enabled = itemFor(player, clipping) ~= nil }
        if value.id == PEST and value.clippingGiven ~= true then
            options[#options + 1] = { id = "ask_clipping",
                label = "Ask for Pest's old newspaper", enabled = true }
        end
    else
        options[#options + 1] = { id = "claim_gear",
            label = value.id == PEST and "Accept Pest's sprayer"
                or "Accept the Bolt's aviators",
            enabled = value.gearClaimed ~= true }
        local recruitment = SC.FactionRecruitment
            and type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if recruitment and recruitment.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask for the rival's decision",
                enabled = recruitment.canDecide == true }
        elseif not recruitment or recruitment.status ~= "joined" then
            options[#options + 1] = { id = "recruit",
                label = "Ask the former rival to join", enabled = true }
        end
    end
    return options
end

function Rivals.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        value.stage = "hostile"
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) or group.standing == "Hostile" then
        return false, "rival_too_far"
    end
    local actor = actorFor(group)
    if action == "ask_feud" then
        U().say(actor, value.id == PEST
            and "The Bluegrass Bolt calls himself justice. I call him infestation."
            or "Doctor Pest calls me a pest. Has he looked in a mirror?")
        return true, "feud_explained"
    end
    if action == "take_side" then
        local other = rivalGroup(group)
        if not other or other.lifecycle == "destroyed" then
            return false, "rival_unavailable"
        end
        value.feudActive = true
        local rival = story(other)
        if rival then rival.feudActive = true end
        U().say(actor, "Then meet my rival and settle it. No more costumes after this.")
        return true, "feud_live"
    end
    if action == "ask_clipping" and value.id == PEST
        and value.clippingGiven ~= true then
        local item = itemFor(actor, clipping)
        local source = item and select(1, U().call(item, "getContainer"))
        local destination = U().inventory(player)
        if not item or not source or not destination
            or not U().transferItemVerified(source, destination, item) then
            return false, "clipping_transfer_failed"
        end
        value.clippingGiven = true
        U().say(actor, "Read what they printed. Then tell me which of us is a hero.")
        return true, "real_clipping_received"
    end
    if action == "mediate_caring" then
        local fellow = caringFellow(player)
        if not fellow then return false, "caring_fellow_required" end
        local resolved, reason = reconcile(group, fellow)
        if resolved then U().say(fellow,
            "There are enough dead people. Be ridiculous together, not against each other.") end
        return resolved, reason
    end
    if action == "show_clipping" then
        if not itemFor(player, clipping) then
            return false, "radio_clipping_required"
        end
        return reconcile(group, nil)
    end
    if action == "claim_gear" then
        if not Rivals.canRecruit(group) or value.gearClaimed then
            return false, "rival_gear_unavailable"
        end
        local kind = value.id == PEST and "Base.KnapsackSprayer"
            or "Base.Glasses_Aviators"
        local item = itemFor(actor,
            function(current) return current == kind end)
        local source = item and select(1, U().call(item, "getContainer"))
        local destination = U().inventory(player)
        if not item or not source or not destination then
            return false, "rival_gear_missing"
        end
        U().call(actor, "setWornItem", value.id == PEST
            and "Back" or "Eyes", nil)
        if not U().transferItemVerified(source, destination, item) then
            return false, "rival_gear_transfer_failed"
        end
        value.gearClaimed = true
        return true, "exact_rival_gear_received"
    end
    if action == "recruit" then
        if not Rivals.canRecruit(group) then
            return false, "feud_unresolved"
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
    return false, "unknown_rival_choice"
end

return Rivals
