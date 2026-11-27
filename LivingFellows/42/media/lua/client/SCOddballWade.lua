-- SPDX-License-Identifier: MIT
local SC = LivingFellows
local Wade = {}
SC.OddballWade = Wade

local ID = "wade_hensley"
local CHANNEL = 90000
local ROD = "Base.FishingRod"
local LINE = { ["Base.FishingLine"] = true, ["Base.PremiumFishingLine"] = true }
local ITEM_MARKER = "SC_WadeItem"
local STAGES = { unmet = true, accepted = true, hooked = true,
    release = true, supper = true, complete = true, dead = true }
local TEXT = {
    call = "Wade Hensley here. If you find fishing line, I'll trade you supper. Look for the red canoe up in the sycamore.",
    reminder = "Wade again. One spool of line if you're headed this way. River bend, canoe in the tree.",
    reply = "There's a deer path down to the bank. I'll mark the bend for you.",
    meet = "My last line went with a fish. One spool'll do me, if you've got it.",
    accept = "That'll do. Let me thread it.",
    danger = "Hold up. Something's coming down the bank.",
    lure = "There's my lure. See that nick? I put it there.",
    release = "That one and me are even now.",
    supper = "Here. Cleaned this one this morning.",
    visit = "I'll be here awhile. Sit if you like.",
}
local jobs = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function valueFor(group) return SC.OddballKit.story(group, ID) end
local function bank() return SC.OddballWadeBank end
local function radio() return SC.OddballDistressRadio end
local function read(value, method, ...) return (U().call(value, method, ...)) end

local function runtime(group)
    local state = jobs[group]
    if not state then state = {}; jobs[group] = state end
    return state
end

local function nearby(actor, player, radius)
    return player and U().sameFloor(actor, player) and SC.OddballKit.seenWithin(actor, player, radius)
end

local function speech(state, actor, key, now)
    local line = TEXT[key]
    if U().say(actor, line) then state.speechUntil = now + U().speechDisplayMillis(line) end
end

local function readyToSpeak(state, now) return now >= (state.speechUntil or 0) end

local function exactItem(actor, id, expected)
    if not id then return nil end
    return SC.OddballKit.itemWhere(actor, function(kind, item)
        return (not expected or expected == kind) and U().itemStableId(item, false) == id
    end, 480, 32)
end

local function offeredLine(player)
    return SC.OddballKit.itemWhere(player, function(kind, item)
        return LINE[kind] and (tonumber(read(item, "getCurrentUsesFloat")) or 0) > 0
    end, 480, 32)
end

local function reserveItem(group, actor, story, field, kind)
    if story[field] then return exactItem(actor, story[field], kind) end
    local mark = group.id .. ":" .. field
    local item = SC.OddballKit.itemWhere(actor, function(itemKind, candidate)
        local data = U().modData(candidate)
        return itemKind == kind and data and data[ITEM_MARKER] == mark
    end, 160, 8)
    if not item then
        local inventory = U().inventory(actor)
        item = U().addItem(inventory, kind)
        local data = item and U().modData(item)
        if not data then
            if item then U().call(inventory, "Remove", item) end
            return nil
        end
        data[ITEM_MARKER] = mark
    end
    story[field] = U().itemStableId(item, true)
    return story[field] and item or nil
end

function Wade.onSpawn(group, actor)
    local story = valueFor(group)
    if not story or not actor then return false, "wade_unavailable" end
    local okay, why = bank().onSpawn(group)
    if not okay then return false, why end
    if not story.rodId then
        local rod = SC.OddballKit.itemOfType(actor, ROD, 160, 8)
        local data = rod and U().modData(rod)
        if not data then return false, "wade_rod_unavailable" end
        data.fishing_LineCondition = 0
        story.rodId = U().itemStableId(rod, true)
        if not story.rodId then return false, "wade_rod_identity_unavailable" end
    end
    if story.stage == "unmet" and not story.radioSeeded then
        local powered, item = radio().provisionRadio(actor, true)
        if powered then
            story.radioSeeded = true
            story.radioId = U().itemStableId(item, true)
        end
    end
    return true
end

function Wade.radioOffer(group, _, now)
    local story = valueFor(group)
    if not story or story.stage ~= "unmet" or story.radioAnswered or story.greeted
        or now < (story.nextRadioAt or 0) then return nil end
    local line = story.radioStarted and TEXT.reminder or TEXT.call
    story.radioStarted, story.nextRadioAt = true, now + 90000
    return { frequency = CHANNEL, text = line, replyLabel = "Wade" }
end

function Wade.radioRespond(group)
    local story = valueFor(group)
    if not story or story.stage ~= "unmet" or story.radioAnswered then
        return false, "wade_call_closed"
    end
    group.discovered = true
    return true, "wade_bank_marked", TEXT.reply
end

function Wade.menuOptions(group, player)
    local story, actor = valueFor(group), SC.OddballKit.livingActor(group, 1)
    if not story or story.stage ~= "unmet" or not story.rodId or not nearby(actor, player, 3.5) then return {} end
    local item = offeredLine(player)
    return { { id = "offer_line", label = getText("UI_SC_Wade_OfferLine"), enabled = item ~= nil,
        detail = item == nil and getText("UI_SC_Wade_LineMissing") or nil } }
end

function Wade.action(group, action, player)
    local story, actor = valueFor(group), SC.OddballKit.livingActor(group, 1)
    if action ~= "offer_line" or not story or story.stage ~= "unmet" or not story.rodId
        or not nearby(actor, player, 3.5) then return false, getText("UI_SC_Wade_TradeUnavailable") end
    local line = offeredLine(player)
    if not line then return false, getText("UI_SC_Wade_LineMissing") end
    local id = U().itemStableId(line, true)
    if not id then return false, getText("UI_SC_Wade_TradeUnavailable") end
    local source = read(line, "getContainer") or U().inventory(player)
    if U().transferItemVerified(source, U().inventory(actor), line) ~= true then
        return false, getText("UI_SC_Wade_TradeUnavailable")
    end
    story.lineId, story.playerSlot, story.stage = id, tonumber(read(player, "getPlayerNum")) or 0, "accepted"
    group.discovered = true
    return true, getText("UI_SC_Wade_LineAccepted")
end

local function completeStockAction(action, actor, rod, item)
    if not action or not item then return false end
    local okay, completed = pcall(function() return action:new(actor, rod, item):complete() end)
    return okay and completed == true
end

local function rig(actor, story)
    local rod = exactItem(actor, story.rodId, ROD)
    local data = rod and U().modData(rod)
    if not data then return nil, "wade_rod_unavailable" end
    if (tonumber(data.fishing_LineCondition) or 0) <= 0 then
        local line = exactItem(actor, story.lineId)
        if not line or not LINE[U().itemType(line)]
            or not completeStockAction(ISChangeFishingRodEquip, actor, rod, line)
            or (tonumber(data.fishing_LineCondition) or 0) <= 0 then
            return nil, "wade_line_unavailable"
        end
    end
    if not data.fishing_HookType then
        local hook = SC.OddballKit.itemOfType(actor, "Base.FishingHook", 160, 8)
        if not completeStockAction(ISChangeFishingRodEquip, actor, rod, hook) then
            return nil, "wade_hook_unavailable"
        end
    end
    if not data.fishing_Lure then
        local worm = SC.OddballKit.itemOfType(actor, "Base.Worm", 160, 8)
        if not completeStockAction(AIAttachLureAction, actor, rod, worm) then
            return nil, "wade_bait_unavailable"
        end
    end
    if read(actor, "getSecondaryHandItem") then U().call(actor, "setSecondaryHandItem", nil) end
    if read(actor, "getPrimaryHandItem") ~= rod then U().call(actor, "setPrimaryHandItem", rod) end
    return read(actor, "getPrimaryHandItem") == rod and rod or nil, "wade_rod_not_held"
end

local function threatened(actor)
    if SC.ZombieAttack and SC.ZombieAttack.isGrabbed(actor) then return true end
    local record = SC.Registry.byId(U().idOf(actor))
    local state = record and record.runtime
    local snapshot = state and (state.senses and state.senses.current or state.snapshot)
    return snapshot and (tonumber(snapshot.immediateCount) or 0) > 0 or false
end

local function cancelCast(state, actor, reason)
    if state.castToken then SC.Fishing.cancelScriptedCast(actor, state.castToken, reason) end
end

local function cast(group, story, state, actor, player, now)
    if state.castToken then
        local status, _, didHook = SC.Fishing.scriptedCastStatus(actor, state.castToken)
        if didHook then story.stage = "hooked" end
        if status == "waiting" or status == "casting" then
            if threatened(actor) then
                cancelCast(state, actor, "wade_bank_danger")
                if nearby(actor, player, 8) and readyToSpeak(state, now) then speech(state, actor, "danger", now) end
            elseif not nearby(actor, player, 8) then
                cancelCast(state, actor, "wade_witness_left")
            end
            return true, status
        end
        state.castToken = nil
        if story.stage == "hooked" then return true, "wade_hooked" end
    end
    if not nearby(actor, player, 8) or threatened(actor) or not readyToSpeak(state, now) then
        return true, "wade_waiting_to_cast"
    end
    if not story.thanked then
        story.thanked = true
        speech(state, actor, "accept", now)
        return true, "wade_rigging"
    end
    local site = bank().castSite(group)
    if not site or not U().arrived(actor, site.bank, { targetKind = "square", distance = 0.6 }) then
        return true, "wade_bank_unavailable"
    end
    if not reserveItem(group, actor, story, "filletId", "Base.FishFillet") then
        return false, "wade_supper_unavailable"
    end
    local rod, reason = rig(actor, story)
    if not rod then return false, reason end
    state.castNumber = (state.castNumber or 0) + 1
    local token = group.id .. ":" .. tostring(state.castNumber)
    local started, why = SC.Fishing.beginScriptedCast(actor, site, rod, token, function(_, confirmed)
        if state.castToken == confirmed and story.stage == "accepted" then story.stage = "hooked" end
    end)
    if started then state.castToken = token end
    return started, why
end

local function resolveCatch(group, story, state, actor, player, now)
    if story.stage == "hooked" and state.castToken then
        local status = SC.Fishing.scriptedCastStatus(actor, state.castToken)
        if status == "hooked" then return true, "wade_landing_bass" end
        state.castToken = nil
    end
    if not nearby(actor, player, 8) or threatened(actor) or not readyToSpeak(state, now) then
        return true, "wade_waiting_with_catch"
    end
    if story.stage == "hooked" then
        if not reserveItem(group, actor, story, "bassId", "Base.SmallmouthBass")
            or not reserveItem(group, actor, story, "lureId", "Base.JigLure") then
            return false, "wade_catch_unavailable"
        end
        story.stage = "release"
        speech(state, actor, "lure", now)
    elseif story.stage == "release" then
        local fish = exactItem(actor, story.bassId, "Base.SmallmouthBass")
        if fish then
            local inventory = read(fish, "getContainer") or U().inventory(actor)
            U().call(inventory, "Remove", fish)
            if U().inventoryContains(inventory, fish) then return false, "wade_release_pending" end
            U().call(actor, "playSound", "LureHitWater")
        end
        story.stage = "supper"
        speech(state, actor, "release", now)
    else
        local donor = player
        if type(getSpecificPlayer) == "function" then donor = getSpecificPlayer(story.playerSlot) end
        if not nearby(actor, donor, 3.5) then return true, "wade_supper_waiting" end
        if not exactItem(donor, story.filletId, "Base.FishFillet") then
            local fillet = exactItem(actor, story.filletId, "Base.FishFillet")
            local source = fillet and (read(fillet, "getContainer") or U().inventory(actor))
            if not fillet or U().transferItemVerified(source, U().inventory(donor), fillet) ~= true then
                return false, "wade_supper_pending"
            end
        end
        story.stage = "complete"
        speech(state, actor, "supper", now)
    end
    return true, story.stage
end

function Wade.pulse(group, player, now)
    local story, actor = valueFor(group), SC.OddballKit.livingActor(group, 1)
    if not story or not actor then return false, "wade_unavailable" end
    local state = runtime(group)
    now = now or U().nowMs()
    if now >= (state.bankAt or 0) then
        state.bankAt = now + 5000
        bank().onSpawn(group)
    end
    if story.stage == "unmet" then
        if not story.greeted and nearby(actor, player, 5) and not threatened(actor) then
            story.greeted, group.discovered = true, true
            speech(state, actor, "meet", now)
        end
        if not story.greeted and not story.radioAnswered and now >= (state.radioAt or 0) then
            state.radioAt = now + 10000
            local powered, item = radio().provisionRadio(actor, not story.radioSeeded)
            if powered and not story.radioSeeded then
                story.radioSeeded, story.radioId = true, U().itemStableId(item, true)
            end
        end
    elseif story.stage == "accepted" then
        return cast(group, story, state, actor, player, now)
    elseif story.stage == "hooked" or story.stage == "release" or story.stage == "supper" then
        return resolveCatch(group, story, state, actor, player, now)
    elseif story.stage == "complete" and not story.laterGreeted then
        if player and U().distance(actor, player) >= 15 then story.leftAfterSupper = true end
        if story.leftAfterSupper and nearby(actor, player, 5) and readyToSpeak(state, now) and not threatened(actor) then
            story.laterGreeted = true
            speech(state, actor, "visit", now)
        end
    end
    return true, story.stage
end

function Wade.intentFor(_, _, _, group)
    return { mode = "wade_bank_post", post = valueFor(group).site.spawn }
end

function Wade.update(actor, _, _, intent)
    if U().arrived(actor, intent.post, { targetKind = "square", distance = 0.6 }) then
        return true, "wade_at_bank"
    end
    local square = U().loadedSquare(intent.post)
    if not square then return false, "wade_bank_unavailable" end
    return SC.Navigation.request(actor, square, "walk", { action = "wade_return_bank" })
end

function Wade.onRetire(group)
    local actor = SC.OddballKit.recordActor(group, 1)
    if actor then cancelCast(runtime(group), actor, "wade_retired") end
    jobs[group] = nil
    return true
end
Wade.onMemberDeath = Wade.onRetire

function Wade.siteFor(square, player, allowSeen)
    return bank().siteFor(square, player, allowSeen)
end

local function validate(story, path, kit)
    local okay, reason = bank().storyRules.validate(story, path, kit)
    if not okay then return false, reason end
    if not STAGES[story.stage] then return kit.fail(path .. ".stage", "unknown Wade stage") end
    for _, field in ipairs({ "rodId", "radioId", "lineId", "bassId", "lureId", "filletId" }) do
        local id = story[field]
        if id ~= nil and (type(id) ~= "string" or #id > 128 or not string.find(id, "^lf%-item:")) then
            return kit.fail(path .. "." .. field, "bad Wade item receipt")
        end
    end
    if story.stage ~= "unmet" and story.stage ~= "dead" then
        local slot = story.playerSlot
        if not story.rodId or not story.lineId or not kit.finite(slot) or slot < 0 or slot > 3 or slot % 1 ~= 0 then
            return kit.fail(path, "missing Wade trade receipt")
        end
    end
    if story.stage == "hooked" and not story.filletId then
        return kit.fail(path, "missing Wade supper receipt")
    end
    if (story.stage == "release" or story.stage == "supper" or story.stage == "complete")
        and (not story.bassId or not story.lureId or not story.filletId) then
        return kit.fail(path, "missing Wade catch receipt")
    end
    return true
end

Wade.storyRules = {
    siteKind = bank().storyRules.siteKind,
    siteFields = bank().storyRules.siteFields,
    claims = bank().storyRules.claims,
    acceptSite = bank().storyRules.acceptSite,
    validate = validate,
}
radio().register(ID, "OddballWade", { replyLabel = "Ask Wade where he is",
    replyText = "I hear you. Whereabouts on the river?", mapLabel = "Wade's fishing camp" })

return Wade
