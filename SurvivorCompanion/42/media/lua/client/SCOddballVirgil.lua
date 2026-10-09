-- SPDX-License-Identifier: MIT
-- Virgil Toombs's sealed route. Deliveries are confirmed at real saved doors.

local SC = SurvivorCompanion
SC.OddballVirgil = SC.OddballVirgil or {}
local Virgil = SC.OddballVirgil

local ID = "postman_virgil_toombs"
local TALK_RANGE = 8
local WIFE_MARKER = "LF_OddballVirgilWifeGroupId"

local lines = {
    greet = "Neither rain, nor heat, nor the dead walking. That's the job.",
    route = "Three addresses. Three letters. Please keep the envelopes closed.",
    clue = "Two-Twelve Maple's been on hold since the ninth. Can't have that.",
    privacy = "Opening someone else's mail is a federal crime, son.",
    reward = "Every address accounted for. I kept your pay in the sorting drawer.",
    final = "Last letter. This one's addressed to me.",
    wife = "She's at the house. I need to know what happened there.",
    after = "There was nothing left to say to her. Thank you for going.",
    stay = "I'll stay with the mail. Somebody has to keep the counter open.",
    recruit = "My route's finished. Maybe yours could use another pair of hands.",
    fellow = "Who's he even delivering to? Who's reading them?",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    value.delivered = type(value.delivered) == "table" and value.delivered or {}
    value.issued = type(value.issued) == "table" and value.issued or {}
    return value
end

function Virgil.actor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, topic)
    local actor = Virgil.actor(group)
    return actor and lines[topic] and U().say(actor, lines[topic]) == true or false
end

local function near(group, player)
    local actor = Virgil.actor(group)
    return actor and player and U().distance(actor, player) <= TALK_RANGE
        and (not U().canSee or U().canSee(player, actor) == true)
end

local function targetLabel(target)
    if type(target) ~= "table" then return "unknown address" end
    if type(target.label) == "string" and #target.label > 0 then
        return target.label
    end
    local described = SC.Factions and type(SC.Factions.describeLocation) == "function"
        and SC.Factions.describeLocation(target) or nil
    return described and described.address or
        ("House near " .. tostring(target.x) .. ", " .. tostring(target.y))
end

local function targetsValid(value)
    local site = value.site
    if type(site) ~= "table" or type(site.mailTargets) ~= "table"
        or #site.mailTargets ~= 3 or type(site.homeTarget) ~= "table"
        or type(site.homeZombie) ~= "table" then
        return false
    end
    local seen = {}
    for _, target in ipairs(site.mailTargets) do
        if tonumber(target.x) == nil or tonumber(target.y) == nil then return false end
        local key = tostring(target.x) .. ":" .. tostring(target.y)
        if seen[key] then return false end
        seen[key] = true
    end
    return tonumber(site.homeTarget.x) ~= nil
        and tonumber(site.homeTarget.y) ~= nil
        and tonumber(site.homeZombie.x) ~= nil
        and tonumber(site.homeZombie.y) ~= nil
end

local function letterSlot(item, group)
    if U().itemType(item) ~= "Base.LetterHandwritten" then return nil end
    local data = U().modData(item)
    if type(data) ~= "table" or data.LF_VirgilGroupId ~= group.id then
        return nil
    end
    local slot = tonumber(data.LF_VirgilMailSlot)
    return slot and math.floor(slot) == slot and slot >= 1 and slot <= 5
        and slot or nil, data
end

local function letterIn(actor, group, slot)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 14)
        or {}) do
        local found = letterSlot(item, group)
        if found == slot then return item end
    end
    return nil
end

local function markHostile(group, value, reason)
    if value.stage == "hostile" then return true, "already_hostile" end
    if value.stage == "recruited" then return false, "virgil_joined" end
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        local changed, why = SC.Factions.forceStanding(group.id, "Hostile")
        if not changed then return false, why or "standing_change_failed" end
    else
        group.standing, group.lifecycle = "Hostile", "hostile"
    end
    value.stage = "hostile"
    value.hostileReason = reason
    group.permanentHostility = true
    speak(group, "privacy")
    return true, "mail_privacy_violated"
end

-- A narrow adapter for a vanilla read hook. Reading even an authorized
-- delivery is a privacy breach; possession alone is not.
function Virgil.isSealedMail(item)
    if U().itemType(item) ~= "Base.LetterHandwritten" then return false end
    local data = U().modData(item)
    if type(data) ~= "table" or data.LF_VirgilSealed ~= true
        or type(data.LF_VirgilGroupId) ~= "string" then return false end
    return true, data.LF_VirgilGroupId
end

function Virgil.openMailFor(item, player)
    local sealed, groupId = Virgil.isSealedMail(item)
    if not sealed then return false, "not_virgil_mail" end
    if not player then return false, "reader_unavailable" end
    local container = select(1, U().call(item, "getContainer"))
    if not container or U().containerContainsIdentity(container, item) ~= true then
        return false, "letter_not_available_to_read"
    end
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    local value = story(group)
    if not value then return false, "route_unavailable" end
    local slot = letterSlot(item, group)
    if not slot or value.delivered[slot] == true then
        return false, "letter_already_delivered"
    end
    return markHostile(group, value, "player_opened_mail")
end

local function seedLetters(group, actor, value)
    if value.lettersSeeded == true then return true, "mail_already_seeded" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "mail_inventory_unavailable" end
    for slot = 1, 5 do
        if not letterIn(actor, group, slot) then
            local item, reason = U().addItem(inventory, "Base.LetterHandwritten")
            if not item then return false, reason or "mail_creation_failed" end
            local data = U().modData(item)
            if type(data) ~= "table" then return false, "mail_marker_unavailable" end
            data.LF_VirgilGroupId = group.id
            data.LF_VirgilMailSlot = slot
            data.LF_VirgilSealed = true
            local label = slot <= 3 and targetLabel(value.site.mailTargets[slot])
                or slot == 4 and targetLabel(value.site.homeTarget) or "Virgil Toombs"
            U().call(item, "setName", "Sealed letter for " .. label)
            U().call(item, "setCustomName", true)
        end
    end
    value.lettersSeeded = true
    return true, "five_letters_sorted"
end

local function spawnWife(group, value)
    if value.wifeSpawned == true or value.wifeDead == true then
        return true, "wife_already_spawned"
    end
    local point = value.site and value.site.homeZombie
    if type(point) ~= "table" then return false, "home_room_unavailable" end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square or not U().isSafeSpawnSquare(square) then
        return false, "home_room_unloaded"
    end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    if player and U().canSee and U().canSee(player, square) then
        return false, "home_room_visible"
    end
    if type(addZombiesInOutfit) ~= "function" then
        return false, "zombie_spawn_api_unavailable"
    end
    local ok, zombies = pcall(addZombiesInOutfit, point.x, point.y,
        point.z or 0, 1, nil, 100)
    local wife = ok and zombies and U().listGet(zombies, 0) or nil
    if not wife or not U().isZombie(wife) then return false, "wife_spawn_failed" end
    local data = U().modData(wife)
    if type(data) ~= "table" then
        value.wifeSpawned = true -- a partial spawn must not create a second wife
        value.wifeIssue = "wife_marker_unavailable"
        return false, value.wifeIssue
    end
    data[WIFE_MARKER] = group.id
    value.wifeSpawned = true
    return true, "wife_at_home"
end

local function sameFloorNear(player, target, distance)
    if not player or type(target) ~= "table" then return false end
    local _, _, z = U().position(player)
    if tonumber(z) == nil or math.floor(z) ~= math.floor(tonumber(target.z) or 0) then
        return false
    end
    return U().distance(player, target) <= distance
end

local function removeExactLetter(item)
    local source = item and select(1, U().call(item, "getContainer")) or nil
    if not source or U().containerContainsIdentity(source, item) ~= true then
        return false, "sealed_letter_missing"
    end
    local _, called = U().call(source, "Remove", item)
    if not called or U().containerContainsIdentity(source, item) ~= false then
        return false, "sealed_letter_could_not_be_delivered"
    end
    return true
end

local function routeComplete(value)
    return value.delivered[1] == true and value.delivered[2] == true
        and value.delivered[3] == true
end

local function deliverNearby(group, value, player)
    if not player or value.stage ~= "route"
        and value.stage ~= "final_delivery" then return false end
    local startSlot = value.stage == "final_delivery" and 4 or 1
    local endSlot = value.stage == "final_delivery" and 4 or 3
    for slot = startSlot, endSlot do
        local target = slot == 4 and value.site.homeTarget
            or value.site.mailTargets[slot]
        if value.issued[slot] == true and value.delivered[slot] ~= true
            and sameFloorNear(player, target, 2) then
            local letter = letterIn(player, group, slot)
            if not letter then return false, "delivery_requires_sealed_letter" end
            local delivered, reason = removeExactLetter(letter)
            if not delivered then return false, reason end
            value.delivered[slot] = true
            if slot == 4 then
                value.stage = value.wifeDead and "return_to_post"
                    or "awaiting_wife"
            elseif routeComplete(value) then
                value.stage = "route_complete"
            end
            return true, "letter_delivered_at_address_" .. tostring(slot)
        end
    end
    return false
end

local function issueFinalLetter(group, value, player)
    if value.stage ~= "route_complete" or value.rewarded ~= true then
        return false, "route_reward_required"
    end
    local actor = Virgil.actor(group)
    local letter = actor and letterIn(actor, group, 4)
    if not letter then return false, "final_letter_missing" end
    local source = select(1, U().call(letter, "getContainer"))
    local destination = player and U().inventory(player)
    if not source or not destination then return false, "mail_container_unavailable" end
    local transferred, reason = U().transferItemVerified(source, destination, letter)
    if not transferred then return false, reason or "mail_transfer_failed" end
    local data = U().modData(letter)
    data.LF_VirgilAuthorized = true
    value.issued[4] = true
    value.stage = "final_delivery"
    speak(group, "final")
    return true, "final_letter_issued"
end

local function reward(group, value, player)
    if not routeComplete(value) then return false, "route_not_complete" end
    if not near(group, player) then return false, "virgil_too_far" end
    if value.rewarded == true then return true, "route_reward_already_paid" end
    local inventory = U().inventory(player)
    if not inventory then return false, "player_inventory_unavailable" end
    local rewards = { "Base.Bullets9mmBox", "Base.Hammer", "Base.Screwdriver" }
    for index = (tonumber(value.rewardItems) or 0) + 1, #rewards do
        local item, reason = U().addItem(inventory, rewards[index])
        if not item then return false, reason or "route_reward_failed" end
        value.rewardItems = index
    end
    value.rewarded = true
    speak(group, "reward")
    return true, "route_reward_paid"
end

local function issueLetters(group, value, player)
    local actor = Virgil.actor(group)
    local destination = player and U().inventory(player)
    if not actor or not destination then return false, "mail_carrier_unavailable" end
    if not targetsValid(value) then return false, "route_addresses_unavailable" end
    for slot = 1, 3 do
        if value.issued[slot] ~= true then
            local item = letterIn(actor, group, slot)
            if not item then return false, "sealed_letter_missing" end
            local source = select(1, U().call(item, "getContainer"))
            local moved, reason = U().transferItemVerified(source, destination, item)
            if not moved then return false, reason or "mail_transfer_failed" end
            value.issued[slot] = true
            local data = U().modData(item)
            data.LF_VirgilAuthorized = true
        end
    end
    value.stage = "route"
    speak(group, "route")
    return true, "sealed_route_issued"
end

local function checkPrivacy(group, value, player)
    if not player or value.stage == "hostile" or value.stage == "recruited" then
        return false
    end
    local inventory = U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 240, 14)
        or {}) do
        local slot, data = letterSlot(item, group)
        if slot and (value.issued[slot] ~= true
            or data.LF_VirgilAuthorized ~= true) then
            return markHostile(group, value, "mail_taken_without_permission")
        end
    end
    return false
end

function Virgil.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "virgil_unavailable" end
    if not targetsValid(value) then return false, "route_addresses_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "virgil_inventory_unavailable" end
    if value.hammerSeeded ~= true then
        local hammer
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 100, 5)) do
            if U().itemType(item) == "Base.Hammer" then hammer = item break end
        end
        if not hammer then hammer = U().addItem(inventory, "Base.Hammer") end
        if not hammer then return false, "hammer_unavailable" end
        U().call(actor, "setPrimaryHandItem", hammer)
        value.hammerSeeded = true
    end
    return seedLetters(group, actor, value)
end

function Virgil.onZombieDead(zombie)
    local data = zombie and U().modData(zombie)
    local id = type(data) == "table" and data[WIFE_MARKER] or nil
    local group = id and SC.Factions and SC.Factions.group(id) or nil
    local value = story(group)
    if not value or value.wifeDead == true then return false end
    value.wifeDead = true
    if value.delivered[4] == true then
        value.stage = "return_to_post"
    end
    return true, "wife_death_recorded"
end

function Virgil.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.recruitmentStarted == true and SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function" then
        local summary = SC.FactionRecruitment.summary(group.id)
        if summary and summary.status == "joined" then
            value.stage = "recruited"
            if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
                SC.Oddballs.retire(group, "recruited")
            end
        end
    end
    local privacy, reason = checkPrivacy(group, value, player)
    if privacy then return true, reason end
    local delivered, deliveryReason = deliverNearby(group, value, player)
    if delivered then return true, deliveryReason end
    if value.stage == "final_delivery" or value.stage == "awaiting_wife" then
        local home = value.site and value.site.homeTarget
        if sameFloorNear(player, home, 35) then
            if not value.wifeSpawned and (tonumber(value.wifeSpawnAttempts) or 0) < 3 then
                local spawned, why = spawnWife(group, value)
                if not spawned and why ~= "home_room_unloaded"
                    and why ~= "home_room_visible" then
                    value.wifeSpawnAttempts = (tonumber(value.wifeSpawnAttempts) or 0) + 1
                end
            end
        end
        if value.delivered[4] == true and value.wifeDead == true then
            value.stage = "return_to_post"
        end
    end
    if value.stage == "return_to_post" and near(group, player) then
        value.stage = "choice"
        speak(group, "after")
    end
    return true, value.stage
end

function Virgil.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { priority = 110, kind = "faction", mode = "hostile",
            factionId = group.id }
    end
    return { priority = 30, kind = "faction", mode = "virgil_post",
        factionId = group.id }
end

function Virgil.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if intent and intent.mode == "hostile" then
        return false, "delegate_human_combat"
    end
    local destination
    local point = value.site and value.site.spawn
    if type(point) == "table" then
        destination = U().gridSquare(point.x, point.y, point.z or 0)
    end
    if not destination then return true, "destination_unloaded" end
    if U().distance(actor, destination) <= 1.5 then
        U().stop(actor)
        return true, "sorting_or_waiting"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, destination, "walk", {
        action = "virgil_route", arrivalDistance = 1.2,
        targetSquare = destination })
end

function Virgil.canRecruit(group)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage ~= "choice" then return false, "final_delivery_unfinished" end
    if value.wifeDead ~= true then return false, "wife_not_accounted_for" end
    if group.standing == "Hostile" then return false, "virgil_hostile" end
    return true, "virgil_ready"
end

function Virgil.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage == "hostile" or value.stage == "recruited"
        or value.stage == "stayed" then return {} end
    local nearby = near(group, player)
    local options = {
        { id = "greet", label = "Speak to Virgil", enabled = nearby },
    }
    if value.stage == "unmet" then
        options[#options + 1] = { id = "accept_route",
            label = "Take three sealed letters", enabled = nearby
                and value.lettersSeeded == true,
            detail = "Deliver each at its addressed house" }
    elseif value.stage == "route" then
        for slot = 1, 3 do
            options[#options + 1] = { id = "route_address_" .. tostring(slot),
                label = (value.delivered[slot] and "Delivered: " or "Deliver: ")
                    .. targetLabel(value.site.mailTargets[slot]),
                enabled = false }
        end
    elseif value.stage == "route_complete" then
        options[#options + 1] = { id = "claim_reward",
            label = "Collect route pay", enabled = nearby and not value.rewarded }
        options[#options + 1] = { id = "take_final_letter",
            label = "Take Virgil's final letter",
            enabled = nearby and value.rewarded == true,
            detail = targetLabel(value.site.homeTarget) }
    elseif value.stage == "final_delivery" or value.stage == "awaiting_wife"
        or value.stage == "return_to_post" then
        options[#options + 1] = { id = "final_address",
            label = value.stage == "return_to_post" and "Return to Virgil"
                or ("Deliver to Virgil's house: "
                    .. targetLabel(value.site.homeTarget)),
            enabled = false }
    elseif value.stage == "choice" then
        local eligible = Virgil.canRecruit(group)
        options[#options + 1] = { id = "recruit", label = "Ask Virgil to join",
            enabled = nearby and eligible }
        options[#options + 1] = { id = "stay",
            label = "Let Virgil remain at the post office",
            enabled = nearby }
        local summary = SC.FactionRecruitment
            and type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if summary and summary.status == "trial" then
            options[#options + 1] = { id = "recruitment_decide",
                label = "Ask Virgil for his decision", enabled = nearby
                    and summary.canDecide == true }
            options[#options + 1] = { id = "recruitment_return",
                label = "End Virgil's trial", enabled = nearby
                    and summary.canReturn == true }
        end
    end
    return options
end

function Virgil.action(group, action, player, payload)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then return markHostile(group, value, "player_attack") end
    if action == "open_mail" then
        return markHostile(group, value, "player_opened_mail")
    end
    if value.stage == "hostile" or value.stage == "stayed"
        or value.stage == "recruited" then return false, "story_finished" end
    if not near(group, player) then return false, "virgil_too_far" end
    if action == "greet" then
        group.discovered = true
        speak(group, "greet")
        if value.reactionSpoken ~= true then
            value.reactionSpoken = true
            for _, fellow in ipairs(SC.Registry and SC.Registry.living
                and SC.Registry.living() or {}) do
                local record = SC.Registry.byId(U().idOf(fellow))
                if record and record.recruited and U().distance(fellow, player) <= 8 then
                    U().say(fellow, lines.fellow)
                    break
                end
            end
        end
        return true, "virgil_greeted"
    elseif action == "accept_route" then
        if value.stage ~= "unmet" then return false, "route_already_accepted" end
        return issueLetters(group, value, player)
    elseif action == "claim_reward" then
        return reward(group, value, player)
    elseif action == "take_final_letter" then
        return issueFinalLetter(group, value, player)
    elseif action == "stay" then
        if value.stage ~= "choice" then return false, "final_choice_not_ready" end
        value.stage = "stayed"
        speak(group, "stay")
        if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
            SC.Oddballs.retire(group, "stayed")
        end
        return true, "virgil_stays_at_post_office"
    elseif action == "recruit" then
        local eligible, reason = Virgil.canRecruit(group)
        if not eligible then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, why = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, why end
        end
        local started, why = SC.FactionRecruitment.startTrial(group.id, player, false)
        if not started then return false, why end
        value.recruitmentStarted = true
        speak(group, "recruit")
        return true, why or "trial_started"
    elseif action == "recruitment_decide" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.decide(group.id, player)
    elseif action == "recruitment_return" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.returnNow(group.id, player, false)
    end
    return false, "unsupported_virgil_action"
end

return Virgil
