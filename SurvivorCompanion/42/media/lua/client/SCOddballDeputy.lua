-- SPDX-License-Identifier: MIT
-- Strange Folk: Deputy Rhonda Vance's checkpoint and its captives.
-- Her story state contains only save-safe values. Faction membership, movement,
-- and human combat remain with their existing owners.

local SC = SurvivorCompanion
SC.OddballDeputy = SC.OddballDeputy or {}
local Deputy = SC.OddballDeputy

local ID = "checkpoint_deputy_rhonda"
local CHECKPOINT_MS = 30000
local TALK_RANGE = 8
local SESSION_KEY = tostring({}) .. ":" .. tostring(os and os.time and os.time() or 0)

local lines = {
    challenge = { "Drop it. Hands where I can see them.",
        "Drop it. Hands where I can see them." },
    law = { "This county still has laws. I'm what's left of them.",
        "This county still has laws. I'm what's left of them." },
    custody = { "They're in protective custody. For their protection.",
        "They're in protective custody. For their protection." },
    badge = { "Why didn't you say so, officer? They're all yours.",
        "Why didn't you say so, officer? They're all yours." },
    citation = { "Looting, trespass, being out after curfew. Sign here.",
        "Looting, trespass, being out after curfew. Sign here." },
    warning = { "Drop it, dipshit. I won't say it twice.",
        "Drop it, genius. I won't say it twice." },
    hostile = { "You made your choice. Hands off my prisoners.",
        "You made your choice. Hands off my prisoners." },
}

local function U() return SC.GameplayUtil end

local function stateFor(group)
    local state = type(group) == "table" and group.oddball or nil
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    return state
end

local function memberFor(group, actor)
    local actorId = actor and U().idOf(actor) or nil
    if not actorId then return nil end
    for _, member in ipairs(group.members or {}) do
        if member.actorId == actorId then return member end
    end
    return nil
end

function Deputy.actor(group)
    local member = type(group) == "table" and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, topic)
    local actor = Deputy.actor(group)
    local choice = lines[topic]
    if not actor or not choice then return false end
    local clean = U().config and U().config("profanityEnabled") == false
    return U().say(actor, choice[clean and 2 or 1]) == true
end

local function nearDeputy(group, player)
    local actor = Deputy.actor(group)
    return actor ~= nil and player ~= nil and U().distance(actor, player) <= TALK_RANGE
        and (not U().canSee or U().canSee(player, actor) == true)
end

local function insideStation(state, player)
    local bounds = state.site and state.site.house and state.site.house.bounds
    local x, y, z = U().position(player)
    return type(bounds) == "table" and x ~= nil and y ~= nil and z ~= nil
        and z == (state.site.spawn and state.site.spawn.z or 0)
        and x >= bounds.x1 and x <= bounds.x2
        and y >= bounds.y1 and y <= bounds.y2
end

local function hasBadge(player)
    local inventory = player and U().inventory(player)
    if not inventory then return false end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        if U().itemType(item) == "Base.Badge" then return true end
    end
    return false
end

local function companionReaction(player)
    if not player or not SC.Registry or type(SC.Registry.living) ~= "function" then
        return false
    end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        if record and record.recruited == true and U().distance(actor, player) <= 8 then
            return U().say(actor, "Is she arresting us? Is that what this is?") == true
        end
    end
    return false
end

local function startCheckpoint(group, player, state, now)
    if state.stage ~= "unmet" then return false end
    state.stage = "checkpoint"
    state.checkpointStartedAt = now
    state.checkpointDeadlineAt = now + CHECKPOINT_MS
    state.checkpointSession = SESSION_KEY
    state.lawSpoken = false
    state.checkpointWarned = false
    group.discovered = true
    speak(group, "challenge")
    companionReaction(player)
    return true
end

local function markHostile(group, state, reason)
    if state.stage == "hostile" then return true, "already_hostile" end
    if state.stage == "recruited" then return false, "deputy_recruited" end
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
        if not changed then return false, why or "standing_change_failed" end
    else
        group.standing, group.lifecycle = "Hostile", "hostile"
    end
    group.permanentHostility = true
    state.stage = "hostile"
    state.hostileReason = reason
    state.badgePresented = false
    state.checkpointDeadlineAt = nil
    speak(group, "hostile")
    return true, "deputy_hostile"
end

local function releaseCaptives(group, state)
    if not SC.Factions or type(SC.Factions.releaseCaptiveMember) ~= "function" then
        return false, "captive_release_unavailable"
    end
    local pending, released = false, 0
    local lastReason
    for index = 2, #(group.members or {}) do
        local member = group.members[index]
        if member.role == "captive" and member.alive ~= false
            and member.departed ~= true then
            local okay, reason = SC.Factions.releaseCaptiveMember(group.id, member.key)
            if okay then released = released + 1
            else pending, lastReason = true, reason end
        end
    end
    state.releasePending = pending
    state.captivesReleased = not pending
    return not pending, pending and (lastReason or "captive_release_pending")
        or (released > 0 and "captives_released" or "no_captives_remaining")
end

local function livingCaptivesHeld(group)
    for index = 2, #(group.members or {}) do
        local member = group.members[index]
        if member.role == "captive" and member.alive ~= false
            and member.departed ~= true then return true end
    end
    return false
end

local function finishBadgeRelease(group, state)
    local released, releaseReason = releaseCaptives(group, state)
    if not released or livingCaptivesHeld(group) then
        state.releasePending = true
        return false, releaseReason or "captive_release_pending"
    end
    local trusted, reason = SC.Factions.forceStanding(group.id, "Trusted")
    if not trusted then
        state.releasePending = true
        return false, reason or "deputy_trust_unavailable"
    end
    state.badgeShown = true
    state.releasePending = false
    state.stage = "officer"
    speak(group, "badge")
    return true, "deputy_deferred_captives_released"
end

local function heldWeapons(actor)
    local list, seen = {}, {}
    for _, hand in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local item = select(1, U().call(actor, hand))
        if item and not seen[item] and (U().instanceOf(item, "HandWeapon")
            or U().instanceOf(item, "zombie.inventory.types.HandWeapon")
            or U().hasMethod(item, "getMaxDamage")) then
            seen[item] = true
            list[#list + 1] = item
        end
    end
    return list
end

local function partyForCheckpoint(player)
    local result = { player }
    if not SC.Registry or type(SC.Registry.living) ~= "function" then return result end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        if actor ~= player and record and record.recruited == true
            and U().distance(actor, player) <= TALK_RANGE then
            result[#result + 1] = actor
        end
    end
    return result
end

local function dropPartyWeapons(player)
    if not player then return false, "player_unavailable" end
    -- Only visible held weapons are surrendered. Carried tools and weapons in
    -- bags remain the owner's inventory; this avoids confiscating unrelated
    -- belongings and makes the outcome legible on the ground.
    for _, actor in ipairs(partyForCheckpoint(player)) do
        local square = U().squareOf(actor)
        if not square then return false, "weapon_drop_square_unavailable" end
        local primary = select(1, U().call(actor, "getPrimaryHandItem"))
        local secondary = select(1, U().call(actor, "getSecondaryHandItem"))
        for _, item in ipairs(heldWeapons(actor)) do
            local source = select(1, U().call(item, "getContainer"))
            if not source or U().containerContainsIdentity(source, item) ~= true then
                return false, "held_weapon_container_unavailable"
            end
            if primary == item then U().call(actor, "setPrimaryHandItem", nil) end
            if secondary == item then U().call(actor, "setSecondaryHandItem", nil) end
            local dropped, reason = U().dropItem(source, square, item)
            if not dropped then
                if primary == item then U().call(actor, "setPrimaryHandItem", item) end
                if secondary == item then U().call(actor, "setSecondaryHandItem", item) end
                return false, reason or "weapon_drop_failed"
            end
        end
    end
    return true, "held_weapons_dropped"
end

local function citation(player, group)
    local inventory = player and U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    -- Base.Note is a non-writable photo in Build 42. SheetPaper2 has one
    -- writable page and is opened through the game's ordinary Read Note UI.
    local item, reason = U().addItem(inventory, "Base.SheetPaper2")
    if not item then return false, reason or "citation_item_unavailable" end
    local body = "Knox County Sheriff's Office\nCitation: looting, "
        .. "trespass, and curfew violation.\nDeputy Rhonda Vance"
    local _, wrote = U().call(item, "addPage", 1, body)
    if not wrote then
        U().call(inventory, "Remove", item)
        return false, "citation_page_unavailable"
    end
    local data = U().modData(item)
    if data then
        data.SC_CitationFactionId = group.id
        data.SC_NoteText = body
    end
    U().call(item, "setName", "Knox County citation")
    U().call(item, "setCustomName", true)
    return true, "citation_issued"
end

local function itemOfType(actor, fullType)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == fullType then return item end
    end
    return nil
end

function Deputy.onSpawn(group, actor)
    local state = stateFor(group)
    if not state or not actor then return false, "wrong_oddball" end
    local member = memberFor(group, actor)
    if not member then return false, "deputy_member_unavailable" end
    if member.role == "captive" then return true, "captive_in_cell" end
    if member.key ~= "member-1" then return false, "deputy_member_unknown" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "deputy_inventory_unavailable" end
    for _, fullType in ipairs({ "Base.Nightstick", "Base.Pistol",
        "Base.Bullets9mmBox" }) do
        if state.loadoutSeeded ~= true and not itemOfType(actor, fullType) then
            local item, reason = U().addItem(inventory, fullType)
            if not item then return false, reason or "deputy_loadout_failed" end
        end
    end
    if state.loadoutSeeded ~= true then
        local pistol = itemOfType(actor, "Base.Pistol")
        if pistol then U().call(pistol, "setCurrentAmmoCount", 15) end
        state.loadoutSeeded = true
    end
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    if not primary then
        local pistol = itemOfType(actor, "Base.Pistol")
        if pistol then U().call(actor, "setPrimaryHandItem", pistol) end
    end
    return true, "deputy_ready"
end

function Deputy.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local now = tonumber(current) or U().nowMs()
    local lead = group.members and group.members[1]
    if lead and lead.alive == false then
        state.stage = "deputy_dead"
        state.releasePending = true
        local released, reason = releaseCaptives(group, state)
        if released then
            group.lifecycle = "destroyed"
            if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "deputy_dead")
            end
        end
        return released, released and "captives_freed_after_deputy_death" or reason
    end
    if state.releasePending and state.badgePresented == true
        and state.badgeShown ~= true then
        finishBadgeRelease(group, state)
    elseif state.releasePending then
        releaseCaptives(group, state)
    end
    if state.stage == "hostile" or state.stage == "processed"
        or state.stage == "officer" or state.stage == "recruited"
        or state.stage == "badge_release_pending" then
        return true, state.stage
    end
    local actor = Deputy.actor(group)
    if not actor then return true, "deputy_unloaded" end
    local distance = player and U().distance(player, actor) or math.huge
    if state.stage == "unmet" and distance <= TALK_RANGE
        and insideStation(state, player) then
        startCheckpoint(group, player, state, now)
    end
    if state.stage ~= "checkpoint" then return true, state.stage end
    if distance > 12 then
        return markHostile(group, state, "checkpoint_abandoned")
    end
    local started = tonumber(state.checkpointStartedAt) or now
    local deadline = tonumber(state.checkpointDeadlineAt) or 0
    if state.checkpointSession ~= SESSION_KEY or now < started
        or deadline < started or deadline > now + CHECKPOINT_MS then
        -- A saved wall clock can be older than this process's clock. The player
        -- receives a fresh thirty seconds after loading instead of a false
        -- automatic refusal.
        state.checkpointStartedAt = now
        state.checkpointDeadlineAt = now + CHECKPOINT_MS
        state.checkpointSession = SESSION_KEY
        state.lawSpoken = false
        state.checkpointWarned = false
        return true, "checkpoint_timer_restarted"
    end
    if now >= deadline then return markHostile(group, state, "deadline_refused") end
    if not state.lawSpoken and now >= started + 8000 then
        state.lawSpoken = true
        speak(group, "law")
    end
    if not state.checkpointWarned and now >= deadline - 10000 then
        state.checkpointWarned = true
        speak(group, "warning")
    end
    return true, "checkpoint_pending"
end

function Deputy.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    local member = memberFor(group, actor)
    if member and member.role == "captive" then
        return { priority = 35, kind = "faction", mode = "deputy_captive",
            factionId = group.id }
    end
    if state.stage == "hostile" or group.standing == "Hostile" then
        return { priority = 110, kind = "faction", mode = "hostile",
            factionId = group.id }
    end
    return { priority = 35, kind = "faction", mode = "deputy_checkpoint",
        factionId = group.id }
end

function Deputy.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local mode = intent and intent.mode
    if mode == "hostile" then return false, "delegate_human_combat" end
    if mode == "deputy_captive" then
        U().stop(actor)
        return true, "captive_waiting"
    end
    if mode ~= "deputy_checkpoint" then return false, "wrong_deputy_intent" end
    local spawn = state.site and state.site.spawn
    if spawn and U().distance(actor, spawn) > 2.5
        and SC.Navigation and type(SC.Navigation.request) == "function" then
        local target = U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
        if target then
            return SC.Navigation.request(actor, target, "walk", {
                action = "deputy_return_checkpoint", targetSquare = target,
                arrivalDistance = 1.5,
            })
        end
    end
    if player and U().distance(actor, player) <= 12 then
        return U().move(actor, "walk", { action = "face_alert", target = player,
            facingTarget = player, stableFacing = true, weaponReady = true,
            humanAnimationOnly = true })
    end
    U().stop(actor)
    return true, "deputy_holding_checkpoint"
end

function Deputy.canRecruit(group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if state.stage == "hostile" or state.stage == "recruited"
        or state.stage == "deputy_dead"
        or group.permanentHostility == true then
        return false, "deputy_hostile_or_joined"
    end
    if state.badgeShown ~= true then return false, "badge_required" end
    if livingCaptivesHeld(group) then return false, "captives_still_held" end
    if group.standing ~= "Trusted" then return false, "trusted_standing_required" end
    return true, "deputy_ready"
end

function Deputy.menuOptions(group, player)
    local state = stateFor(group)
    if not state then return {} end
    local nearby = nearDeputy(group, player)
    if state.stage == "hostile" or state.stage == "deputy_dead" then return {} end
    local options = {}
    if state.stage == "unmet" then
        options[#options + 1] = { id = "greet", label = "Speak to Deputy Vance",
            enabled = nearby }
    end
    if state.stage == "checkpoint" then
        local remaining = math.max(0, math.ceil(((tonumber(state.checkpointDeadlineAt)
            or U().nowMs()) - U().nowMs()) / 1000))
        options[#options + 1] = { id = "surrender_weapons",
            label = "Lay down the party's held weapons", enabled = nearby,
            detail = tostring(remaining) .. " seconds to comply" }
        options[#options + 1] = { id = "refuse", label = "Refuse the checkpoint",
            enabled = nearby }
    end
    if state.stage == "checkpoint" or state.stage == "processed"
        or state.stage == "officer" then
        options[#options + 1] = { id = "ask_captives",
            label = "Ask about the people in the cells", enabled = nearby }
    end
    if state.stage ~= "recruited" and state.badgeShown ~= true then
        options[#options + 1] = { id = "show_badge",
            label = state.badgePresented and "Ask Vance to release the captives"
                or "Show your police badge",
            enabled = nearby and hasBadge(player),
            detail = "Requires a real Base.Badge" }
    end
    local held = false
    for index = 2, #(group.members or {}) do
        local member = group.members[index]
        if member.role == "captive" and member.departed ~= true
            and member.alive ~= false then held = true break end
    end
    if held and state.badgePresented ~= true and state.stage ~= "recruited" then
        options[#options + 1] = { id = "force_release",
            label = "Free the captives by force", enabled = nearby,
            detail = "Deputy Vance will fight" }
    end
    if state.stage == "officer" then
        local eligible, reason = Deputy.canRecruit(group)
        options[#options + 1] = { id = "recruit",
            label = "Ask Deputy Vance to join", enabled = nearby and eligible,
            detail = reason }
    end
    local summary = SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function"
        and SC.FactionRecruitment.summary(group.id) or nil
    if summary and summary.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Ask Vance for her decision", enabled = nearby
                and summary.canDecide == true, detail = summary.reason }
        options[#options + 1] = { id = "recruitment_return",
            label = "Tell Vance to return to the station", enabled = nearby
                and summary.canReturn == true }
    end
    return options
end

function Deputy.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hurt" then
        return markHostile(group, state, "player_attack")
    end
    if not nearDeputy(group, player) then return false, "deputy_too_far" end
    if action == "greet" then
        if state.stage ~= "unmet" then return false, "checkpoint_already_started" end
        startCheckpoint(group, player, state, U().nowMs())
        return true, "checkpoint_started"
    elseif action == "ask_captives" then
        if state.stage ~= "checkpoint" and state.stage ~= "processed"
            and state.stage ~= "officer" then
            return false, "deputy_not_discussing_captives"
        end
        speak(group, "custody")
        return true, "deputy_claims_protective_custody"
    elseif action == "refuse" then
        if state.stage ~= "checkpoint" then return false, "no_active_checkpoint" end
        return markHostile(group, state, "explicit_refusal")
    elseif action == "force_release" then
        if state.stage == "officer" or state.stage == "recruited" then
            return false, "captives_already_released"
        end
        local hostile, reason = markHostile(group, state, "forced_captive_release")
        if not hostile then return false, reason end
        local released, releaseReason = releaseCaptives(group, state)
        return true, released and "captives_freed_under_fire"
            or (releaseReason or "captive_release_pending")
    elseif action == "show_badge" then
        if state.stage == "hostile" or state.stage == "recruited" then
            return false, "deputy_hostile_or_joined"
        end
        if not hasBadge(player) then return false, "real_badge_required" end
        if not SC.Factions or type(SC.Factions.forceStanding) ~= "function"
            or type(SC.Factions.releaseCaptiveMember) ~= "function" then
            return false, "deputy_story_services_unavailable"
        end
        state.badgePresented = true
        state.stage = "badge_release_pending"
        state.releasePending = true
        state.checkpointDeadlineAt = nil
        local released, releaseReason = finishBadgeRelease(group, state)
        return true, released and "deputy_deferred_captives_released"
            or (releaseReason or "captive_release_pending")
    elseif action == "surrender_weapons" then
        if state.stage ~= "checkpoint" then return false, "no_active_checkpoint" end
        if state.checkpointSession == SESSION_KEY
            and U().nowMs() >= (tonumber(state.checkpointDeadlineAt) or math.huge) then
            markHostile(group, state, "deadline_refused")
            return false, "checkpoint_expired"
        end
        local inventory = U().inventory(player)
        if not inventory then return false, "player_inventory_unavailable" end
        local dropped, reason = dropPartyWeapons(player)
        if not dropped then return false, reason end
        local issued, citeReason = citation(player, group)
        if not issued then return false, citeReason end
        state.stage = "processed"
        state.checkpointDeadlineAt = nil
        speak(group, "citation")
        return true, "deputy_processed_and_released"
    elseif action == "recruit" then
        local eligible, reason = Deputy.canRecruit(group)
        if not eligible then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, askReason end
        end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    elseif action == "recruitment_decide" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.decide(group.id, player)
    elseif action == "recruitment_return" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.returnNow(group.id, player, false)
    end
    return false, "unsupported_deputy_action"
end

return Deputy
