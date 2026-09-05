-- SPDX-License-Identifier: MIT
--
-- Player-initiated companion care: the local player walks to a wounded companion
-- and hand-bandages it over a timed action, spending a bandage from the player's
-- own inventory. This is native/UI-only (it requires ISBaseTimedAction and
-- ISTimedActionQueue), so the file is auto-loaded in-game but never by the headless
-- harnesses; SCCommands fails the "bandage" command closed when SC.PlayerCare is
-- absent. The actual wound apply and every validity check route through
-- SC.Medical.playerBandagePreflight / applyPlayerBandage, which are unit-tested.

require "TimedActions/ISBaseTimedAction"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.PlayerCare = SC.PlayerCare or {}
local PlayerCare = SC.PlayerCare

local function careReady(character, companion)
    if not character or not companion then return false end
    if not SC.Medical or type(SC.Medical.playerBandagePreflight) ~= "function" then
        return false
    end
    local ok = SC.Medical.playerBandagePreflight(companion, character)
    return ok == true
end

SCApplyCompanionBandage = ISBaseTimedAction:derive("SCApplyCompanionBandage")

function SCApplyCompanionBandage:isValid()
    -- Re-checked every tick: the companion must still be a valid, in-range,
    -- treatable target and the player must still hold a bandage.
    return careReady(self.character, self.companion)
end

function SCApplyCompanionBandage:waitToStart()
    if self.companion then pcall(function() self.character:faceThisObject(self.companion) end) end
    return self.character:shouldBeTurning()
end

function SCApplyCompanionBandage:update()
    if self.companion then pcall(function() self.character:faceThisObject(self.companion) end) end
end

function SCApplyCompanionBandage:start()
    -- Best-effort animation; a missing anim name must not break the action, which
    -- still completes on its timer.
    pcall(function() self:setActionAnim("Bandage") end)
end

function SCApplyCompanionBandage:stop()
    ISBaseTimedAction.stop(self)
end

function SCApplyCompanionBandage:perform()
    if SC.Medical and type(SC.Medical.applyPlayerBandage) == "function" then
        pcall(SC.Medical.applyPlayerBandage, self.companion, self.character)
    end
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
-- care preflight no longer holds.
function PlayerCare.queueBandage(player, companion)
    if type(ISTimedActionQueue) ~= "table" or type(luautils) ~= "table" then
        return false, "timed_actions_unavailable"
    end
    if not careReady(player, companion) then return false, "cannot_bandage" end
    local square = nil
    pcall(function() square = companion:getSquare() end)
    if square == nil then return false, "companion_unreachable" end
    if not luautils.walkAdj(player, square) then return false, "companion_unreachable" end
    local ticks = 220
    if SC.Config and type(SC.Config.get) == "function" then
        ticks = tonumber(SC.Config.get("medicalPlayerBandageActionTicks")) or ticks
    end
    ISTimedActionQueue.add(SCApplyCompanionBandage:new(player, companion, ticks))
    return true, "bandage_started"
end

return PlayerCare
