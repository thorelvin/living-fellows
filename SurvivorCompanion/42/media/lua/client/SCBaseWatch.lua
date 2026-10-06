-- SPDX-License-Identifier: MIT
-- A camp resident holds LF's second local view while the human travels.
require "SCViewSession"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseWatch = SC.BaseWatch or {}
local Watch = SC.BaseWatch

local session
local DEFENSE = { rotation = true, role_based = true, all_hands = true }

local function now()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return math.floor(os.clock() * 1000)
end

local function primary()
    return type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
end

local function second()
    return type(getSpecificPlayer) == "function" and getSpecificPlayer(1) or nil
end

local function validSlotId(value)
    return type(value) == "number" and value >= 2 and value <= 2147483647
        and value == math.floor(value)
end

local function alive(actor)
    if actor == nil then return false end
    local ok, dead = pcall(actor.isDead, actor)
    return ok and dead == false
end

local function distance(a, b)
    if a == nil or b == nil then return math.huge end
    local ok, value = pcall(function()
        local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
        return math.sqrt(dx * dx + dy * dy)
    end)
    return ok and value or math.huge
end

local function atCamp(actor)
    return SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(actor) == true
end

local function residentCandidate(id, indoors)
    if type(id) ~= "string" or id == "" or SC.BaseLife == nil
        or SC.Registry == nil then return nil end
    local resident = SC.BaseLife.resident(id)
    local base = SC.BaseLife.active()
    local record = SC.Registry.byId(id)
    local actor = record and record.actor
    if base == nil or resident == nil or resident.baseId ~= base.id
        or resident.duty ~= true or actor == nil or not alive(actor)
        or not atCamp(actor)
        or (indoors and SC.BaseLife.isOutdoorSquare(actor) ~= false)
        or (SC.BaseLife.restriction and SC.BaseLife.restriction(id)) then
        return nil
    end
    if type(SC.Registry.isActive) == "function"
        and SC.Registry.isActive(actor, id) ~= true then return nil end
    local command = SC.Commands and SC.Commands.peek and SC.Commands.peek(actor)
    if command == nil or command.recruited ~= true
        or command.order ~= "base_duty" then return nil end
    local healthy, value = pcall(actor.isBridgeHealthy, actor)
    if not healthy or value ~= true then return nil end
    local squareOk, square = pcall(actor.getCurrentSquare, actor)
    if not squareOk or square == nil then return nil end
    local vehicleOk, vehicle = pcall(actor.getVehicle, actor)
    if vehicleOk and vehicle ~= nil then return nil end
    return record
end

function Watch.candidates()
    local result = {}
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if base == nil then return result end
    for _, entry in ipairs(SC.Registry.snapshot()) do
        local id = entry.id
        local resident = SC.BaseLife.resident(id)
        if resident and resident.baseId == base.id and resident.duty == true then
            local record = residentCandidate(id, true)
            if record then
                result[#result + 1] = {
                    id = id, actor = record.actor,
                    name = SC.GameplayUtil and SC.GameplayUtil.nameOf
                        and SC.GameplayUtil.nameOf(record.actor) or id,
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function rememberActors()
    if session == nil then return end
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if base == nil or base.id ~= session.baseId then return end
    for _, record in ipairs(SC.Registry.snapshot()) do
        local resident = SC.BaseLife.resident(record.id)
        if resident and resident.baseId == base.id and record.actor then
            session.knownActors[record.id] = record.actor
        end
    end
end

local function backup(current, livingTransfer)
    local choices = {}
    for _, row in ipairs(Watch.candidates()) do
        if row.actor ~= current
            and (not livingTransfer or (row.actor:getZ() == current:getZ()
                and distance(row.actor, current) <= 16)) then
            choices[#choices + 1] = row
        end
    end
    table.sort(choices, function(a, b)
        local da, db = distance(a.actor, current), distance(b.actor, current)
        return da == db and a.id < b.id or da < db
    end)
    return choices[1]
end

local function stageDeadActors()
    for id, actor in pairs(session and session.knownActors or {}) do
        local refused = session.unstagedCorpses and session.unstagedCorpses[id]
        local retry = session.corpseRetries and session.corpseRetries[id]
        local stagedBefore = session.stagedCorpses and session.stagedCorpses[id]
        if actor ~= nil and not refused and not stagedBefore
            and (not retry or now() >= retry.nextAt) and not alive(actor) then
            local ready, value = pcall(actor.isCorpseReady, actor)
            local squareOk, square = pcall(actor.getCurrentSquare, actor)
            -- Only the second view's nearby live chunks need an extra owner.
            -- A distant resident's corpse belongs to normal world saving.
            if ready and value == true and squareOk and square ~= nil
                and distance(actor, session.leaderActor) <= 32 then
                local staged, result = pcall(SCSplitScreenProbe.stageDeadCorpseChunk,
                    actor)
                if staged and result == true then
                    session.stagedCorpses = session.stagedCorpses or {}
                    session.stagedCorpses[id] = true
                    if session.corpseRetries then session.corpseRetries[id] = nil end
                    if session.corpseWarningId == id then
                        session.corpseWarning, session.corpseWarningId = nil, nil
                    end
                else
                    -- A chunk can be unavailable for a few pulses during
                    -- handoff. Retry with backoff; the native retention cap
                    -- is permanent for this session.
                    local attempts = (retry and retry.attempts or 0) + 1
                    local permanent = string.find(tostring(result),
                        "corpse chunk retention limit reached", 1, true) ~= nil
                        or attempts >= 6
                    if permanent then
                        session.unstagedCorpses = session.unstagedCorpses or {}
                        session.unstagedCorpses[id] = true
                    else
                        session.corpseRetries = session.corpseRetries or {}
                        session.corpseRetries[id] = { attempts = attempts,
                            nextAt = now() + math.min(30000,
                                1000 * (2 ^ attempts)) }
                    end
                    session.corpseWarning = "base_watch_corpse_retention_failed:"
                        .. tostring(result)
                    session.corpseWarningId = id
                end
            end
        end
    end
    return true
end

local function unhookRadio()
    if session and session.radioHooked and Events and Events.OnDeviceText then
        Events.OnDeviceText.Remove(Watch.onDeviceText)
        session.radioHooked = false
    end
end

local function hookRadio()
    if session and not session.radioHooked and Events and Events.OnDeviceText
        and type(Events.OnDeviceText.Add) == "function" then
        Events.OnDeviceText.Add(Watch.onDeviceText)
        session.radioHooked = true
    end
end

function Watch.current() return session end
function Watch.isLeader(actor)
    return session ~= nil and session.leaderActor == actor
end
function Watch.isLeaderId(id)
    return session ~= nil and session.leaderId == id
end

function Watch.isRemote(player)
    if session == nil or player == nil or player ~= primary() then return false end
    local leader = session.leaderActor
    return not atCamp(player) or distance(player, leader) > 16
end

function Watch.isRemoteResident(actor, player)
    if not Watch.isRemote(player) or actor == nil then return false end
    local id = SC.GameplayUtil and SC.GameplayUtil.idOf
        and SC.GameplayUtil.idOf(actor)
    local resident = id and SC.BaseLife and SC.BaseLife.resident(id)
    return resident ~= nil and resident.baseId == session.baseId
        and distance(actor, player) > 16
end

function Watch.contextFor(actor, human)
    if session == nil or session.restoring or not alive(session.leaderActor)
        or actor == nil then return human end
    local id = SC.GameplayUtil and SC.GameplayUtil.idOf
        and SC.GameplayUtil.idOf(actor)
    local resident = id and SC.BaseLife.resident(id)
    if resident ~= nil and resident.baseId == session.baseId
        and resident.duty == true then return session.leaderActor end
    return human
end

function Watch.start(leaderId)
    if session ~= nil then return false, "base_watch_already_active" end
    if SC.ExpeditionPrototype and SC.ExpeditionPrototype.current
        and SC.ExpeditionPrototype.current() ~= nil then
        return false, "expedition_uses_companion_view"
    end
    if SC.ViewSession.owner() ~= nil then return false, "companion_view_in_use" end
    if primary() == nil or not atCamp(primary()) then
        return false, "player_not_at_base"
    end
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    local record = residentCandidate(leaderId, true)
    if base == nil or record == nil then
        return false, "base_watch_leader_unavailable"
    end
    local existing = SC.BaseLife.jobFor and SC.BaseLife.jobFor(leaderId)
    if existing and SC.BaseLife.outdoorJob(existing) then
        return false, "leader_finishing_outdoor_work"
    end
    local accepted, reason = SC.ViewSession.claim("base_watch", record.actor)
    if not accepted then return false, reason end
    session = {
        baseId = base.id, leaderId = leaderId, leaderActor = record.actor,
        knownActors = {}, departed = false, joining = true,
        radioSession = tostring(now()) .. ":" .. tostring(
            type(ZombRand) == "function" and ZombRand(2147483647) or 0),
        radioSequence = 0,
    }
    rememberActors()
    hookRadio()
    return true, "base_watch_started"
end

local function finishJoined()
    if session == nil or second() ~= session.leaderActor
        or type(destroyPlayerData) ~= "function" or SCSplitScreenProbe == nil
        or SCSplitScreenProbe.canReleaseJoinedLeader() ~= true then
        return false, "base_watch_return_not_ready"
    end
    local staged, stageReason = stageDeadActors()
    if not staged then return false, stageReason end
    local saved, sqlId = pcall(SCSplitScreenProbe.persistJoinedLeaderSlotForReuse)
    if not saved or not validSlotId(sqlId) then
        return false, "base_watch_slot_save_failed:" .. tostring(sqlId)
    end
    local uiOk, uiReason = pcall(destroyPlayerData, session.leaderActor)
    if not uiOk then return false, "base_watch_ui_teardown_failed:" .. tostring(uiReason) end
    local released, value = pcall(SCSplitScreenProbe.releaseJoinedLeader)
    if not released or value ~= true then
        session.technicalIssue = "base_watch_view_release_failed"
        return false, tostring(value)
    end
    unhookRadio()
    SC.ViewSession.released("base_watch", sqlId)
    session = nil
    return true, "base_watch_finished"
end

function Watch.cancelBeforeDeparture()
    if session == nil then return false, "base_watch_not_active" end
    if session.departed then return false, "base_watch_player_away" end
    return finishJoined()
end

local function handleDeadLeader()
    local dead = session.leaderActor
    local ready, corpseReady = pcall(dead.isCorpseReady, dead)
    if not ready or corpseReady ~= true then
        return false, "base_watch_corpse_pending"
    end
    local staged, stageReason = stageDeadActors()
    if not staged then return false, stageReason end
    local replacement = backup(dead, false)
    if replacement then
        local switched, actor = pcall(SCSplitScreenProbe.handoff,
            replacement.actor)
        if not switched or actor ~= replacement.actor then
            return false, "base_watch_handoff_failed:" .. tostring(actor)
        end
        session.leaderId, session.leaderActor = replacement.id, actor
        session.outsideSince, session.coverageLost = nil, nil
        return true, "base_watch_new_leader"
    end
    if type(destroyPlayerData) ~= "function" then
        return false, "base_watch_ui_teardown_unavailable"
    end
    local saved, sqlId = pcall(SCSplitScreenProbe.persistDeadLeaderSlotForReuse)
    if not saved or not validSlotId(sqlId) then
        return false, "base_watch_dead_slot_save_failed:" .. tostring(sqlId)
    end
    local uiOk, uiReason = pcall(destroyPlayerData, dead)
    if not uiOk then return false, "base_watch_ui_teardown_failed:" .. tostring(uiReason) end
    local released, result = pcall(SCSplitScreenProbe.releaseDeadLeader)
    if not released or result ~= true then
        return false, "base_watch_dead_release_failed:" .. tostring(result)
    end
    unhookRadio()
    SC.ViewSession.released("base_watch", sqlId)
    session = nil
    return true, "base_watch_all_leaders_lost"
end

local function restoreView()
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if base == nil or base.id ~= session.baseId then
        return false, "base_watch_saved_base_unavailable"
    end
    local record = residentCandidate(session.leaderId, false)
    if record == nil then
        -- The base may be outside the primary player's loaded area. A cold
        -- companion loads it before the ordinary persistence owner restores
        -- the real leader and the other residents.
        if not session.bootstrapQueued and second() == nil
            and SC.Persistence and SC.Persistence.pendingBootstrap then
            local pending = SC.Persistence.pendingBootstrap(session.leaderId)
            if pending == nil then
                for _, row in ipairs(SC.BaseLife.summary().residentRows or {}) do
                    if row.duty and row.id ~= session.leaderId then
                        pending = SC.Persistence.pendingBootstrap(row.id)
                        if pending then session.leaderId = row.id break end
                    end
                end
            end
            if pending then
                local world = type(getWorld) == "function" and getWorld() or nil
                local cell = world and world:getCell() or nil
                if cell and cell:getGridSquare(pending.x, pending.y,
                    pending.z) == nil then
                    local called, loader = pcall(
                        SCSplitScreenProbe.startColdCompanionProbe,
                        pending.x, pending.y, pending.z,
                        session.slotSqlId or -1)
                    if not called or loader == nil then
                        return false, "base_watch_restart_loader_failed:"
                            .. tostring(loader)
                    end
                    session.bootstrapQueued = true
                    session.bootstrapActor = loader
                end
            end
        end
        return false, "base_watch_waiting_for_residents"
    end
    local slot = second()
    if slot ~= nil and slot ~= record.actor then
        if SCSplitScreenProbe.isColdProbe(slot) ~= true
            or (session.bootstrapActor and slot ~= session.bootstrapActor) then
            return false, "base_watch_second_slot_occupied"
        end
        local called, replaced = pcall(
            SCSplitScreenProbe.replaceColdProbeWithRestoredLeader,
            record.actor, session.slotSqlId or -1)
        if not called or replaced ~= true then
            return false, "base_watch_restart_handoff_failed:" .. tostring(replaced)
        end
    elseif slot == nil then
        if session.bootstrapQueued then
            return false, "base_watch_restart_loader_pending"
        end
        local claimed, reason = SC.ViewSession.claim("base_watch",
            record.actor, session.slotSqlId)
        if not claimed then return false, reason end
    end
    if second() ~= record.actor then
        return false, "base_watch_restart_view_join_pending"
    end
    local slotId = SCSplitScreenProbe.leaderSqlId()
    local adopted, reason = SC.ViewSession.adopt("base_watch",
        record.actor, slotId)
    if not adopted then return false, reason end
    session.leaderActor = record.actor
    session.knownActors[record.id] = record.actor
    session.restoring = nil
    session.joining = nil
    session.bootstrapQueued, session.bootstrapActor = nil, nil
    session.technicalIssue = nil
    hookRadio()
    return true, "base_watch_resumed"
end

function Watch.pulse()
    if session == nil then return false, "base_watch_not_active" end
    if SCSplitScreenProbe == nil then return false, "local_view_unavailable" end
    if session.restoring then
        local ok, reason = restoreView()
        if not ok then session.technicalIssue = reason end
        return ok, reason
    end
    local leader = session.leaderActor
    if session.joining and second() == nil
        and SCSplitScreenProbe.isLeader(leader) == true then
        return true, "base_watch_view_join_pending"
    end
    if second() ~= leader then
        session.technicalIssue = "base_watch_view_owner_mismatch"
        return false, session.technicalIssue
    end
    session.joining = nil
    session.technicalIssue = session.corpseWarning
    -- Slot-1 hotbar has no input, and stock B42 toggles it every frame.
    if type(getPlayerHotbar) == "function" then
        local ok, bar = pcall(getPlayerHotbar, 1)
        if ok and bar and bar ~= session.hiddenHotbar
            and type(bar.setVisible) == "function"
            and type(bar.removeFromUIManager) == "function" then
            bar:setVisible(false)
            bar:removeFromUIManager()
            session.hiddenHotbar = bar
        end
    end
    local current = now()
    if current < (session.nextCheckAt or 0) then return true, "base_watch_active" end
    session.nextCheckAt = current + 1000
    rememberActors()
    stageDeadActors()
    session.technicalIssue = session.corpseWarning
    if not alive(leader) then
        local ok, reason = handleDeadLeader()
        if not ok and session then session.technicalIssue = reason end
        return ok, reason
    end
    if SC.BaseLife.isOutdoorSquare(leader) == true or not atCamp(leader) then
        session.outsideSince = session.outsideSince or current
        if current - session.outsideSince >= 4000 then
            local replacement = backup(leader, true)
            if replacement and type(SCSplitScreenProbe.handoffLiving) == "function" then
                local switched, actor = pcall(SCSplitScreenProbe.handoffLiving,
                    replacement.actor)
                if switched and actor == replacement.actor then
                    session.leaderId, session.leaderActor = replacement.id, actor
                    session.outsideSince, session.coverageLost = nil, nil
                    return true, "base_watch_new_leader"
                end
            end
            session.coverageLost = true
        end
    else
        session.outsideSince, session.coverageLost = nil, nil
    end
    local player = primary()
    if player == nil then return true, "base_watch_no_player" end
    if not session.departed then
        if not atCamp(player) and distance(player, leader) > 24 then
            session.departed = true
        end
    elseif atCamp(player) and distance(player, leader) <= 16
        and SCSplitScreenProbe.canReleaseJoinedLeader() == true then
        return finishJoined()
    end
    return true, session.coverageLost and "base_watch_coverage_lost"
        or "base_watch_active"
end

local function equippedRadio(actor, transmit)
    if actor == nil then return nil end
    local radio = actor:getEquipedRadio()
    if radio == nil or radio:getContainer() ~= actor:getInventory()
        or (radio ~= actor:getPrimaryHandItem()
            and radio ~= actor:getSecondaryHandItem()
            and radio ~= actor:getClothingItem_Back()) then return nil end
    local data = radio:getDeviceData()
    if data == nil or not data:getIsTwoWay() or not data:getIsTurnedOn()
        or not data:getHasBattery() or data:getPower() <= 0
        or data:getTransmitRange() <= 0
        or (transmit and (data:getMicIsMuted()
            or data:isNoTransmit())) then return nil end
    return radio, data
end

function Watch.radioAvailable(player)
    if session == nil or session.restoring or second() ~= session.leaderActor
        or player ~= primary() then return false end
    local sender, senderData = equippedRadio(player, true)
    local receiver, receiverData = equippedRadio(session.leaderActor, false)
    return sender ~= nil and receiver ~= nil
        and senderData:getChannel() == receiverData:getChannel()
        and distance(player, session.leaderActor)
            <= senderData:getTransmitRange()
        and distance(player, session.leaderActor)
            <= receiverData:getTransmitRange()
end

function Watch.onDeviceText(guid, codes, _x, _y, _z, message, device)
    local pending = session and session.pendingRadio
    if pending and not pending.received and pending.guid == tostring(guid)
        and pending.codes == tostring(codes)
        and pending.text == tostring(message)
        and pending.receiver == device
        and second() == pending.leader
        and SCSplitScreenProbe.isLeaderRadioTextContextActive() == true then
        pending.received = true
    end
end

local function radioReply(player, textValue, sequence)
    local source, sourceData = equippedRadio(session.leaderActor, true)
    local receiver, receiverData = equippedRadio(player, false)
    if source == nil or receiver == nil
        or sourceData:getChannel() ~= receiverData:getChannel()
        or distance(player, session.leaderActor)
            > sourceData:getTransmitRange() then
        return false
    end
    local pending = {
        leader = session.leaderActor, receiver = receiver,
        guid = "LF-BASE-" .. session.radioSession,
        codes = "REPLY-" .. tostring(sequence), text = textValue,
    }
    session.pendingRadio = pending
    local called = pcall(SCSplitScreenProbe.sendTestRadioWithLeaderText,
        math.floor(session.leaderActor:getX()),
        math.floor(session.leaderActor:getY()), sourceData:getChannel(),
        textValue, pending.guid, pending.codes, 0.8, 0.9, 1.0,
        sourceData:getTransmitRange(), false)
    session.pendingRadio = nil
    if not called or pending.received ~= true then return false end
    SC.GameplayUtil.call(player, "setHaloNote", textValue)
    session.lastReport = textValue
    return true
end

function Watch.sendRadio(player, action, value)
    if session == nil or session.restoring then return false, "base_watch_not_ready" end
    if player ~= primary() or not Watch.isRemote(player) then
        return false, "base_watch_player_not_away"
    end
    if action ~= "status" and (action ~= "defense" or not DEFENSE[value]) then
        return false, "unsupported_base_radio_order"
    end
    if not session.radioHooked or session.pendingRadio then
        return false, "base_watch_radio_unavailable"
    end
    local sender, senderData = equippedRadio(player, true)
    local receiver, receiverData = equippedRadio(session.leaderActor, false)
    if sender == nil or receiver == nil
        or senderData:getChannel() ~= receiverData:getChannel()
        or distance(player, session.leaderActor)
            > senderData:getTransmitRange() then
        return false, "base_watch_radio_no_ack"
    end
    session.radioSequence = session.radioSequence + 1
    local sequence = session.radioSequence
    local pending = {
        leader = session.leaderActor, receiver = receiver,
        guid = "LF-BASE-" .. session.radioSession,
        codes = "CMD-" .. tostring(sequence),
        text = action .. ":" .. tostring(value or ""),
    }
    session.pendingRadio = pending
    local sent = pcall(SCSplitScreenProbe.sendTestRadioWithLeaderText,
        math.floor(player:getX()), math.floor(player:getY()),
        senderData:getChannel(), pending.text, pending.guid, pending.codes,
        0.8, 0.9, 1.0, senderData:getTransmitRange(), false)
    session.pendingRadio = nil
    if not sent or pending.received ~= true
        or second() ~= session.leaderActor then
        return false, "base_watch_radio_no_ack"
    end
    if action == "defense" then
        local changed, reason = SC.BaseLife.setPolicy("defense", value)
        if changed ~= true then return false, reason end
        local reply = "Base defense set to " .. tostring(value):gsub("_", " ") .. "."
        if not radioReply(player, reply, sequence) then
            return true, "base_watch_defense_set_reply_lost"
        end
        return true, reply
    end
    local summary = SC.BaseLife.summary()
    local jobs = summary.jobs or {}
    local alerts = summary.operations and summary.operations.alerts or {}
    local reply = "Base: " .. tostring(summary.duty or 0) .. " on duty, "
        .. tostring(jobs.active or 0) .. " working, "
        .. tostring(jobs.blocked or 0) .. " blocked."
    if #alerts > 0 then reply = reply .. " " .. tostring(alerts[1]) end
    if not radioReply(player, reply, sequence) then
        return false, "base_watch_report_not_received"
    end
    return true, reply
end

function Watch.describe()
    if session == nil then return nil end
    local record = SC.Registry and SC.Registry.byId(session.leaderId)
    return {
        leaderId = session.leaderId,
        leaderName = record and record.actor and SC.GameplayUtil.nameOf(record.actor)
            or session.leaderId,
        departed = session.departed == true,
        joining = session.joining == true,
        restoring = session.restoring == true,
        coverageLost = session.coverageLost == true,
        technicalIssue = session.technicalIssue,
        lastReport = session.lastReport,
    }
end

function Watch.export()
    if session == nil then return nil end
    local liveId = SCSplitScreenProbe ~= nil
        and SCSplitScreenProbe.leaderSqlId() or -1
    local slotId = validSlotId(liveId) and liveId
        or SC.ViewSession.slotSqlId() or session.slotSqlId
    return {
        schema = 1, baseId = session.baseId,
        leaderId = session.leaderId, departed = session.departed == true,
        slotSqlId = validSlotId(slotId) and slotId or nil,
        radioSession = session.radioSession,
        radioSequence = session.radioSequence,
    }
end

function Watch.restore(saved)
    if session ~= nil then return false, "base_watch_already_active" end
    if type(saved) ~= "table" or saved.schema ~= 1
        or type(saved.baseId) ~= "string" or saved.baseId == ""
        or type(saved.leaderId) ~= "string" or saved.leaderId == ""
        or type(saved.departed) ~= "boolean"
        or (saved.slotSqlId ~= nil and not validSlotId(saved.slotSqlId))
        or type(saved.radioSession) ~= "string"
        or #saved.radioSession < 1 or #saved.radioSession > 128
        or type(saved.radioSequence) ~= "number"
        or saved.radioSequence < 0 or saved.radioSequence > 1000000
        or saved.radioSequence ~= math.floor(saved.radioSequence) then
        return false, "invalid_saved_base_watch"
    end
    if SC.ExpeditionPrototype and SC.ExpeditionPrototype.current
        and SC.ExpeditionPrototype.current() ~= nil then
        return false, "expedition_uses_companion_view"
    end
    if saved.slotSqlId and SC.ViewSession.slotSqlId() == nil then
        SC.ViewSession.rememberSlotSqlId(saved.slotSqlId)
    end
    session = {
        baseId = saved.baseId, leaderId = saved.leaderId,
        departed = saved.departed, slotSqlId = saved.slotSqlId,
        radioSession = saved.radioSession,
        radioSequence = saved.radioSequence,
        knownActors = {}, restoring = true,
        technicalIssue = "base_watch_waiting_for_residents",
    }
    return true
end

function Watch.prepareReset()
    if session == nil or session.suspended then return true end
    local slot = second()
    if slot == nil and SCSplitScreenProbe ~= nil
        and (SCSplitScreenProbe.isLeader(session.leaderActor) == true
            or (session.bootstrapActor ~= nil
                and SCSplitScreenProbe.isLeader(session.bootstrapActor) == true)) then
        return false, "base_watch_view_join_pending"
    end
    if slot ~= nil then
        if not session.restoring and slot ~= session.leaderActor then
            return false, "base_watch_view_owner_mismatch"
        end
        if type(destroyPlayerData) ~= "function" then
            return false, "base_watch_ui_teardown_unavailable"
        end
        if not session.uiDetached then
            local uiOk, reason = pcall(destroyPlayerData, slot)
            if not uiOk then return false, tostring(reason) end
            session.uiDetached = true
        end
        local released, result = pcall(SCSplitScreenProbe.releaseForWorldExit)
        if not released or result ~= true then return false, tostring(result) end
    end
    if SC.ViewSession.owner() == "base_watch" then
        SC.ViewSession.released("base_watch", session.slotSqlId)
    end
    unhookRadio()
    session.suspended = true
    return true
end

function Watch.reset()
    if session ~= nil and not session.suspended then
        return false, "base_watch_view_still_owned"
    end
    session = nil
    return true
end

return Watch
