-- SPDX-License-Identifier: MIT
--
-- Player-initiated companion care: the local player walks to a wounded companion
-- and hand-bandages it over a timed action, spending a bandage from the player's
-- own inventory. This is native/UI-only (it requires ISBaseTimedAction and
-- ISTimedActionQueue), so the file is auto-loaded in-game but never by the headless
-- harnesses; SCCommands fails the "bandage" command closed when SC.PlayerCare is
-- absent. The actual wound apply and every validity check route through
-- SC.Medical.playerBandagePreflight / applyPlayerBandage, which are unit-tested.
-- While the player works, the companion is held still through
-- SC.Medical.noteReceivingCare so it cannot walk out of reach mid-action.

require "TimedActions/ISBaseTimedAction"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.PlayerCare = SC.PlayerCare or {}
local PlayerCare = SC.PlayerCare

local function careReady(character, companion)
    if not character or not companion then return false, "invalid_target" end
    if not SC.Medical or type(SC.Medical.playerBandagePreflight) ~= "function" then
        return false, "medical_unavailable"
    end
    local ok, reason = SC.Medical.playerBandagePreflight(companion, character)
    return ok == true, reason
end

local function holdCompanion(companion, character)
    if SC.Medical and type(SC.Medical.noteReceivingCare) == "function" then
        pcall(SC.Medical.noteReceivingCare, companion, character)
    end
end

local function releaseCompanion(companion)
    if SC.Medical and type(SC.Medical.clearReceivingCare) == "function" then
        pcall(SC.Medical.clearReceivingCare, companion)
    end
end

local function note(companion, message)
    local utility = SC.GameplayUtil
    if utility and type(utility.diagnostic) == "function" then
        pcall(utility.diagnostic, "player-care", companion, message)
    end
end

SCApplyCompanionBandage = ISBaseTimedAction:derive("SCApplyCompanionBandage")

function SCApplyCompanionBandage:isValid()
    -- Re-checked every tick: the companion must still be a valid, in-range,
    -- treatable target and the player must still hold a bandage.
    local ready, reason = careReady(self.character, self.companion)
    if not ready and self.lastInvalidReason ~= reason then
        self.lastInvalidReason = reason
        note(self.companion, "action=bandage_invalid reason=" .. tostring(reason))
    end
    return ready
end

function SCApplyCompanionBandage:waitToStart()
    holdCompanion(self.companion, self.character)
    if self.companion then pcall(function() self.character:faceThisObject(self.companion) end) end
    return self.character:shouldBeTurning()
end

function SCApplyCompanionBandage:update()
    holdCompanion(self.companion, self.character)
    if self.companion then pcall(function() self.character:faceThisObject(self.companion) end) end
end

function SCApplyCompanionBandage:start()
    -- Best-effort animation; a missing anim name must not break the action, which
    -- still completes on its timer.
    pcall(function() self:setActionAnim("Bandage") end)
end

function SCApplyCompanionBandage:stop()
    releaseCompanion(self.companion)
    ISBaseTimedAction.stop(self)
end

function SCApplyCompanionBandage:perform()
    local applied, reason = false, "medical_unavailable"
    if SC.Medical and type(SC.Medical.applyPlayerBandage) == "function" then
        local ok, value, applyReason = pcall(SC.Medical.applyPlayerBandage,
            self.companion, self.character)
        applied = ok and value == true
        reason = ok and applyReason or tostring(value)
    end
    note(self.companion, "action=bandage_" .. (applied and "applied" or "failed")
        .. " reason=" .. tostring(reason))
    releaseCompanion(self.companion)
    if SC.UI and type(SC.UI.refresh) == "function" then pcall(SC.UI.refresh) end
    ISBaseTimedAction.perform(self)
end

function SCApplyCompanionBandage:new(character, companion, maxTime)
    local o = ISBaseTimedAction.new(self, character)
    o.companion = companion
    o.maxTime = tonumber(maxTime) or 220
    o.stopOnWalk = true
    o.stopOnRun = true
    o.caloriesModifier = 2
    return o
end

-- Walk the player adjacent to the companion, then queue the bandage action. Fails
-- closed if timed actions are unavailable, the companion is unreachable, or the
-- care preflight no longer holds. The companion holds still from here on.
function PlayerCare.queueBandage(player, companion)
    if type(ISTimedActionQueue) ~= "table" or type(luautils) ~= "table" then
        return false, "timed_actions_unavailable"
    end
    local ready, reason = careReady(player, companion)
    if not ready then
        note(companion, "action=bandage_refused reason=" .. tostring(reason))
        return false, "cannot_bandage"
    end
    local square = nil
    pcall(function() square = companion:getSquare() end)
    if square == nil then return false, "companion_unreachable" end
    holdCompanion(companion, player)
    if not luautils.walkAdj(player, square) then
        releaseCompanion(companion)
        note(companion, "action=bandage_refused reason=companion_unreachable")
        return false, "companion_unreachable"
    end
    local ticks = 220
    if SC.Config and type(SC.Config.get) == "function" then
        ticks = tonumber(SC.Config.get("medicalPlayerBandageActionTicks")) or ticks
    end
    ISTimedActionQueue.add(SCApplyCompanionBandage:new(player, companion, ticks))
    return true, "bandage_started"
end

return PlayerCare
