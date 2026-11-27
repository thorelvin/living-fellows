-- SPDX-License-Identifier: MIT
local SC = LivingFellows
SC.OddballEvacuation = SC.OddballEvacuation or {}
local Evacuation = SC.OddballEvacuation

local ID = "evacuation"
local REWARDS = { "Base.Antibiotics", "Base.Antibiotics", "Base.Bandage", "Base.Bandage" }
local ACTIVE = { boarding = true, driving = true, retiring = true }
local STAGES = { unmet = true, awaiting_car = true, boarding = true,
    driving = true, retiring = true, evacuated = true, failed = true, dead = true }
local REWARD_MARKER = "SC_EvacuationReward"

local function U() return SC.GameplayUtil end
local function valueFor(group) return SC.OddballKit.story(group, ID) end
local function shelter() return SC.OddballEvacuationShelter end
local function vehicle() return SC.OddballEvacuationVehicle end

local function text(key, ...)
    return getText("UI_SC_Evacuation_" .. key, ...)
end

local function nearbyJoy(group, player)
    local joy = SC.OddballKit.livingActor(group, 1)
    local _, _, joyZ = U().position(joy)
    local _, _, playerZ = U().position(player)
    return joyZ ~= nil and playerZ == joyZ and SC.OddballKit.seenWithin(joy, player, 3.5)
        and joy or nil
end

local function rewardToken(group, index)
    return group.id .. ":" .. index
end

local function seedRewards(group, story, joy)
    local inventory = U().inventory(joy)
    if not inventory then return false, "evacuation_inventory_unavailable" end
    story.rewardItems = story.rewardItems or {}
    for index, kind in ipairs(REWARDS) do
        if not story.rewardItems[index] then
            local token = rewardToken(group, index)
            local item = SC.OddballKit.itemWhere(joy, function(itemKind, candidate)
                local data = U().modData(candidate)
                return itemKind == kind and data and data[REWARD_MARKER] == token
            end, 160, 8)
            if not item then
                item = U().addItem(inventory, kind)
                local data = item and U().modData(item)
                if not data then
                    if item then U().call(inventory, "Remove", item) end
                    return false, "evacuation_reward_unavailable"
                end
                data[REWARD_MARKER] = token
            end
            local id = U().itemStableId(item, true)
            if not id then return false, "evacuation_reward_identity_unavailable" end
            story.rewardItems[index] = { id = id, delivered = false }
        end
    end
    return true
end

local function pay(group, story, player)
    if story.rewardPaid then return true end
    local joy = nearbyJoy(group, player)
    local source, destination = U().inventory(joy), U().inventory(player)
    if not source or not destination then return false, "evacuation_reward_out_of_reach" end
    for index, kind in ipairs(REWARDS) do
        local receipt = story.rewardItems and story.rewardItems[index]
        if not receipt then return false, "evacuation_reward_unavailable" end
        if not receipt.delivered then
            local function exact(itemKind, item)
                return itemKind == kind and U().itemStableId(item, false) == receipt.id
            end
            if not SC.OddballKit.itemWhere(player, exact, 960, 64) then
                local item = SC.OddballKit.itemWhere(joy, exact, 160, 8)
                if not item then return false, "evacuation_reward_missing" end
                local moved, reason = U().transferItemVerified(source, destination, item)
                if moved ~= true then return false, reason end
            end
            receipt.delivered = true
        end
    end
    story.rewardPaid = true
    U().say(joy, text("Paid"))
    return true
end

local function seedInjury(story, brock)
    if story.injurySeeded then return true end
    local body = (U().call(brock, "getBodyDamage"))
    local leg = body and BodyPartType and (U().call(body, "getBodyPart", BodyPartType.LowerLeg_L))
    if not leg then return false, "evacuation_leg_unavailable" end
    local _, fractured = U().call(leg, "setFractureTime", 60)
    local _, scratched = U().call(leg, "setScratched", true, true)
    local _, stabilized = U().call(leg, "setBleedingTime", 0)
    if not fractured or not scratched or not stabilized
        or (tonumber((U().call(leg, "getFractureTime"))) or 0) <= 0 then
        return false, "evacuation_injury_readback_failed"
    end
    story.injurySeeded = true
    return true
end

function Evacuation.available()
    return shelter() ~= nil and vehicle() ~= nil and vehicle().available() == true
end

function Evacuation.siteFor(house, player, allowSeen)
    return shelter().siteFor(house, player, allowSeen)
end

function Evacuation.onSpawn(group, actor)
    local story = valueFor(group)
    if not story or not actor then return false, "evacuation_unavailable" end
    if actor == SC.OddballKit.recordActor(group, 1) then
        local secured, reason = shelter().onJoySpawn(group, actor)
        if secured ~= true then return false, reason end
        return seedRewards(group, story, actor)
    end
    if actor == SC.OddballKit.recordActor(group, 2) then return seedInjury(story, actor) end
    return false, "evacuation_member_unavailable"
end

local function retire(group, player)
    for index in ipairs(group.members) do
        local actor = SC.OddballKit.recordActor(group, index)
        local x, y = U().position(actor)
        if x and y and not SC.TaxiService.outsideViews(x, y) then
            return false, "evacuation_crew_still_in_view"
        end
    end
    for index, member in ipairs(group.members) do
        local actor = SC.OddballKit.recordActor(group, index)
        if actor then
            local okay, reason = SC.Actor.remove(actor)
            if okay ~= true then return false, reason end
        end
        if member.actorId then
            local okay, reason = SC.Persistence.retirePendingFactionActor(member.actorId, group.id)
            if okay ~= true then return false, reason end
        end
    end
    local retired, reason = SC.Factions.retireOddballMembers(group, "evacuated")
    if retired == true then vehicle().flush(player) end
    return retired, reason
end

local function fail(group, story)
    shelter().release(group)
    if story.vehicle and vehicle().cancel(group, "evacuation_member_died") ~= true then
        return false, "evacuation_cancel_pending"
    end
    story.stage = "failed"
    if group.members[1].alive == false and group.members[2].alive == false then
        group.lifecycle = "destroyed"
        SC.Oddballs.retire(group, "dead")
    end
    return true, "evacuation_failed"
end

local function retirementCommitted(story)
    return story.stage == "retiring" and story.vehicle and story.vehicle.retirement ~= nil
end

function Evacuation.pulse(group, player, current)
    local story = valueFor(group)
    if not story then return false, "evacuation_unavailable" end
    if story.stage == "evacuated" or story.stage == "dead" then return true, story.stage end
    if (story.failed or story.stage == "failed") and not retirementCommitted(story) then
        return fail(group, story)
    end
    if ACTIVE[story.stage] then
        if not story.rewardPaid then
            local donor = player
            if type(getSpecificPlayer) == "function" then donor = getSpecificPlayer(story.rewardPlayer or 0) end
            local paid, reason = pay(group, story, donor)
            if paid ~= true then return false, reason end
        end
        local status, reason = vehicle().pulse(group, player, current)
        if status == "departed" then return retire(group, player) end
        if status == "replacement" then
            story.stage = "awaiting_car"
            U().say(SC.OddballKit.livingActor(group, 1), text("Replacement"))
        elseif status == "failed" then
            story.failed = true
            return fail(group, story)
        end
        return true, reason or status
    end

    local ready, reason = shelter().pulse(group, player, current)
    local joy = SC.OddballKit.livingActor(group, 1)
    if ready and story.stage == "unmet" and joy and SC.OddballKit.livingActor(group, 2)
        and story.injurySeeded and story.rewardItems and #story.rewardItems == #REWARDS then
        story.stage = "awaiting_car"
        group.discovered = true
        U().say(joy, text("Request"))
    end
    return true, reason or story.stage
end

function Evacuation.intentFor(actor, _, _, group)
    local story = valueFor(group)
    if not story or story.failed then return nil end
    if ACTIVE[story.stage] then return { mode = "evacuation_travel" } end
    local index = actor == SC.OddballKit.recordActor(group, 1) and 1 or 2
    return { mode = "evacuation_hold", post = story.site.memberSpawns[index] }
end

function Evacuation.update(actor, _, _, intent)
    if intent.mode == "evacuation_travel" then return true, "evacuation_travel" end
    local post = intent.post
    if not post then return false, "evacuation_post_unavailable" end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    if not square then return false, "evacuation_post_unloaded" end
    if U().sameSquare(actor, square) then return true, "evacuation_shelter_hold" end
    return SC.Navigation.request(actor, square, "walk", {
        action = "walk_to_square", reason = "evacuation_shelter_hold",
    })
end

function Evacuation.menuOptions(group, player, sourceActor)
    local story = valueFor(group)
    if not story or story.stage ~= "awaiting_car" or story.failed then return {} end
    local joy = nearbyJoy(group, player)
    if not joy or sourceActor and joy ~= sourceActor then return {} end
    local candidate = vehicle().candidate(group, player)
    if not candidate then return {} end
    return { { id = "car_ready", label = text("CarReady"), enabled = true,
        confirm = text("Confirm", candidate.label, math.floor((candidate.distance or 0) + 0.5)),
        payload = candidate.sqlId } }
end

function Evacuation.action(group, action, player, sqlId)
    local story = valueFor(group)
    if action ~= "car_ready" or not story or story.stage ~= "awaiting_car"
        or story.failed or not nearbyJoy(group, player) then
        return false, text("CarUnavailable")
    end
    local okay = vehicle().accept(group, player, sqlId)
    if okay ~= true then return false, text("CarUnavailable") end
    story.rewardPlayer = tonumber((U().call(player, "getPlayerNum"))) or 0
    local paid = pay(group, story, player)
    return true, text(paid and "CarAccepted" or "PayoutPending")
end

function Evacuation.onMemberDeath(group)
    local story = valueFor(group)
    if not story then return false end
    story.failed = true
    if retirementCommitted(story) then return true, "evacuation_retirement_pending" end
    return fail(group, story)
end

function Evacuation.onSpawnFailed(group)
    return shelter().release(group)
end

function Evacuation.onRetire(group)
    shelter().release(group)
    return true
end

local function validate(story, path, kit)
    local okay, reason = shelter().validate(story, path, kit)
    if okay ~= true then return okay, reason end
    if not STAGES[story.stage] then return kit.fail(path .. ".stage", "unknown evacuation stage") end
    local receipts, paid = story.rewardItems, 0
    if receipts ~= nil then
        local dense, count = kit.denseArray(receipts, path .. ".rewardItems", 0, #REWARDS)
        if not dense then return false, count end
        local seen = {}
        for index, receipt in ipairs(receipts) do
            if type(receipt) ~= "table" or type(receipt.id) ~= "string"
                or #receipt.id > 128 or not string.find(receipt.id, "^lf%-item:")
                or seen[receipt.id] or type(receipt.delivered) ~= "boolean" then
                return kit.fail(path .. ".rewardItems[" .. index .. "]", "invalid evacuation reward receipt")
            end
            seen[receipt.id] = true
            if receipt.delivered then paid = paid + 1 end
        end
    end
    if story.rewardPaid == true and paid ~= #REWARDS then
        return kit.fail(path .. ".rewardPaid", "missing evacuation payout receipts")
    end
    for _, field in ipairs({ "rewardPaid", "injurySeeded", "failed" }) do
        if story[field] ~= nil and type(story[field]) ~= "boolean" then
            return kit.fail(path .. "." .. field, "expected boolean")
        end
    end
    if (story.stage == "awaiting_car" or ACTIVE[story.stage] or story.stage == "evacuated")
        and (not story.injurySeeded or not receipts or #receipts ~= #REWARDS) then
        return kit.fail(path, "incomplete evacuation setup")
    end
    local player = story.rewardPlayer
    if player ~= nil and (not kit.finite(player) or player < 0 or player > 3 or player % 1 ~= 0) then
        return kit.fail(path .. ".rewardPlayer", "invalid evacuation reward recipient")
    end
    return vehicle().validate(story, path, kit)
end

Evacuation.storyRules = {
    siteFields = shelter().siteFields,
    claims = shelter().claims,
    acceptSite = function(...) return shelter().acceptSite(...) end,
    prepareFirstSpawn = function(...) return shelter().prepareFirstSpawn(...) end,
    ownsLifecycle = function(story) return ACTIVE[story.stage] == true end,
    recoverMember = function(...) return vehicle().recoverMember(...) end,
    memberDeparted = function(story) return story.stage == "evacuated" end,
    keepsAfterDeath = function(story) return story.failed == true and ACTIVE[story.stage] == true end,
    validate = validate,
}

return Evacuation
