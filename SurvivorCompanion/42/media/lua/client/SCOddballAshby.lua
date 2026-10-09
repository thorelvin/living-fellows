-- SPDX-License-Identifier: MIT
-- Dr. Ashby trades real medicine for three distinct, fresh zombie bodies.
-- Bodies are tagged in place so their inventory is never silently destroyed.

local SC = SurvivorCompanion
SC.OddballAshby = SC.OddballAshby or {}
local Ashby = SC.OddballAshby
local ID = "doctor_vernon_ashby"
local FRESH_HOURS = 72

local lines = {
    greet = "Fresh ones. Not the soupy kind. I can't use soup.",
    specimen = "Cold enough. Still useful. Two more, if you have the stomach.",
    complete = "Three specimens. I'm three weeks from a cure. Been three weeks away for a while.",
    medicine = "Antibiotics. Real ones. Don't ask me where I found them.",
    vaccine = "Trial vaccine. Handwritten label. No promises, except that I believe in it.",
    study = "Leave the bitten one with me. For science. For everyone.",
    decline = "I understand. I wouldn't leave my own people either.",
    refuse = "That's a human body. I asked for the dead, not one of yours.",
}

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function say(group, key)
    local actor = actorFor(group)
    return actor and lines[key] and U().say(actor, lines[key]) == true or false
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 6
        and U().canSee(player, actor) == true
end

local function worldHour()
    if type(getGameTime) ~= "function" then return nil end
    local okay, gameTime = pcall(getGameTime)
    if not okay or not gameTime then return nil end
    local hour = select(1, U().call(gameTime, "getWorldAgeHours"))
    return tonumber(hour)
end

local function specimen(body, groupId, hour)
    if not U().instanceOf(body, "IsoDeadBody") then return false end
    local zombie = select(1, U().call(body, "isZombie"))
    local animal = select(1, U().call(body, "isAnimal"))
    local fake = select(1, U().call(body, "isFakeDead"))
    if zombie ~= true or animal == true or fake == true then return false end
    local rawDeathTime = select(1, U().call(body, "getDeathTime"))
    local deathTime = tonumber(rawDeathTime)
    if not hour or not deathTime or deathTime < 0
        or hour - deathTime < 0 or hour - deathTime > FRESH_HOURS then
        return false
    end
    local data = U().modData(body)
    return type(data) == "table" and data.lfAshbyAcceptedId == nil
end

local function bodyAtDoor(group)
    local site = story(group).site
    local center = site and site.spawn
    local hour = worldHour()
    if not center or not hour then return nil end
    for dx = -3, 3 do
        for dy = -3, 3 do
            if dx * dx + dy * dy <= 10 then
                local square = U().gridSquare(center.x + dx, center.y + dy,
                    center.z or 0)
                local found
                U().squareStaticMovingObjects(square, function(body)
                    if not found and specimen(body, group.id, hour) then
                        found = body
                    end
                end, 24)
                if found then return found end
            end
        end
    end
    return nil
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 8)
        or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function bittenFellow(player)
    if not player or not SC.Registry or type(SC.Registry.living) ~= "function"
        or not SC.Medical or type(SC.Medical.assess) ~= "function" then
        return nil
    end
    for _, actor in ipairs(SC.Registry.living()) do
        local record = SC.Registry.byId(U().idOf(actor))
        if record and record.recruited == true
            and U().distance(actor, player) <= 6 then
            local okay, medical = pcall(SC.Medical.assess, actor)
            if okay and medical and (medical.knoxInfected == true
                or (tonumber(medical.bites) or 0) > 0) then
                return record
            end
        end
    end
    return nil
end

function Ashby.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "ashby_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "ashby_inventory_unavailable" end
    local pick = itemFor(actor, "Base.IcePick")
    if not pick and value.equipmentSeeded ~= true then
        pick = U().addItem(inventory, "Base.IcePick")
    end
    if pick and not select(1, U().call(actor, "getPrimaryHandItem")) then
        U().call(actor, "setPrimaryHandItem", pick)
    end
    if value.equipmentSeeded ~= true and pick then
        if not itemFor(actor, "Base.Antibiotics") then
            U().addItem(inventory, "Base.Antibiotics")
        end
        if not itemFor(actor, "Base.Pills") then
            U().addItem(inventory, "Base.Pills")
        end
        local vitamins = itemFor(actor, "Base.PillsVitamins")
            or U().addItem(inventory, "Base.PillsVitamins")
        if vitamins then
            U().call(vitamins, "setName", "Ashby's trial vaccine")
            value.equipmentSeeded = true
        end
    end
    value.specimens = tonumber(value.specimens) or 0
    if value.stage == "unmet" then value.stage = "research" end
    return true, "ashby_ready"
end

function Ashby.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.stage == "research" and near(group, player)
        and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        say(group, "greet")
    end
    return true, value.stage
end

function Ashby.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "ashby_lab", priority = 30 }
end

function Ashby.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "ashby_lab" then return false end
    local site = story(group).site
    local post = site and site.spawn
    if not post then return true, "lab_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (post.z or 0) and (x - post.x) ^ 2
        + (y - post.y) ^ 2 <= 2.25 then return true, "researching" end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return true, "lab_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_lab", arrivalDistance = 1.5 })
end

function Ashby.canRecruit()
    return false, "ashby_stays_with_his_research"
end

function Ashby.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    local result = {}
    if value.specimens < 3 then
        result[#result + 1] = { id = "deliver_specimen",
            label = "Offer a fresh zombie corpse at the lab door",
            enabled = bodyAtDoor(group) ~= nil,
            detail = tostring(value.specimens) .. "/3 specimens accepted" }
    else
        result[#result + 1] = { id = "claim_medicine",
            label = "Collect Ashby's medicine payment",
            enabled = value.rewardClaimed ~= true }
    end
    if value.vaccineTaken ~= true then
        result[#result + 1] = { id = "take_vaccine",
            label = "Take Ashby's trial vaccine",
            enabled = true, detail = "A bottle of vitamins; no Knox protection" }
    end
    local fellow = bittenFellow(player)
    if fellow and value.studyActorId ~= fellow.id then
        result[#result + 1] = { id = "leave_for_study",
            label = "Let the bitten companion stay for study",
            enabled = true, detail = "They remain alive and can be recalled" }
        result[#result + 1] = { id = "refuse_study",
            label = "Refuse to leave your companion",
            enabled = true }
    end
    return result
end

function Ashby.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "ashby_too_far" end
    if action == "deliver_specimen" then
        if value.specimens >= 3 then return false, "specimens_complete" end
        local body = bodyAtDoor(group)
        if not body then return false, "fresh_zombie_body_required" end
        local data = U().modData(body)
        if type(data) ~= "table" or data.lfAshbyAcceptedId ~= nil then
            return false, "specimen_already_claimed"
        end
        data.lfAshbyAcceptedId = group.id
        value.specimens = value.specimens + 1
        say(group, value.specimens == 3 and "complete" or "specimen")
        return true, value.specimens == 3 and "ashby_contract_complete"
            or "ashby_specimen_accepted"
    end
    if action == "claim_medicine" then
        if value.specimens < 3 or value.rewardClaimed == true then
            return false, "medicine_not_owed"
        end
        local doctor = actorFor(group)
        local source = doctor and U().inventory(doctor)
        local destination = player and U().inventory(player)
        if not source or not destination then return false, "inventory_unavailable" end
        for _, entry in ipairs({
            { kind = "Base.Antibiotics", flag = "antibioticsPaid" },
            { kind = "Base.Pills", flag = "pillsPaid" },
        }) do
            if value[entry.flag] ~= true then
                local item = itemFor(doctor, entry.kind)
                if not item or not U().transferItemVerified(source,
                    destination, item) then
                    return false, "medicine_transfer_failed"
                end
                value[entry.flag] = true
            end
        end
        value.rewardClaimed = true
        say(group, "medicine")
        return true, "ashby_medicine_delivered"
    end
    if action == "take_vaccine" then
        if value.vaccineTaken == true then return false, "vaccine_already_taken" end
        local doctor = actorFor(group)
        local source = doctor and U().inventory(doctor)
        local destination = player and U().inventory(player)
        local item = itemFor(doctor, "Base.PillsVitamins")
        if not source or not destination or not item
            or not U().transferItemVerified(source, destination, item) then
            return false, "vaccine_transfer_failed"
        end
        value.vaccineTaken = true
        say(group, "vaccine")
        return true, "ashby_trial_vitamins_delivered"
    end
    if action == "refuse_study" then
        if not bittenFellow(player) then return false, "no_bitten_fellow" end
        say(group, "decline")
        return true, "study_refused"
    end
    if action == "leave_for_study" then
        local fellow = bittenFellow(player)
        if not fellow or not fellow.actor or not SC.Commands
            or type(SC.Commands.issue) ~= "function" then
            return false, "study_companion_unavailable"
        end
        local accepted, reason = SC.Commands.issue(fellow.id, "stay", nil, player)
        if accepted ~= true then return false, reason end
        value.studyActorId = fellow.id
        say(group, "study")
        return true, "fellow_staying_for_study"
    end
    return false, "unknown_ashby_choice"
end

return Ashby
