-- Runs inside the real Kahlua VM against the game's own ISBaseTimedAction,
-- ISTimedActionQueue and ISRadioAction. Checks that cancelling an owned radio
-- action really removes it, whether it is still waiting or already running.

local Device = PZRL.Device
local failures = 0

local function check(name, condition)
    if condition then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FAIL " .. name)
    end
end

local function newCharacter()
    local c = { farming = false }
    function c:setTimedActionToRetrigger() end
    function c:getTimedActionToRetrigger() return nil end
    function c:getMoodles() return { getMoodleLevel = function() return 0 end } end
    function c:getTimedActionTimeModifier() return 1 end
    function c:StartAction() end
    function c:setIsFarming(value) self.farming = value end
    return c
end

local function newRadio()
    local data = { on = true, power = 1, volume = 0.2, channel = 100000 }
    function data:getIsTurnedOn() return self.on end
    function data:getPower() return self.power end
    function data:getDeviceVolume() return self.volume end
    function data:setDeviceVolume(v) self.volume = v end
    function data:getChannel() return self.channel end
    function data:isIsoDevice() return false end
    local item = {}
    function item:getDeviceData() return data end
    return item, data
end

print("cancel while waiting behind another action")
do
    local player = newCharacter()
    local item, data = newRadio()
    local blocker = ISBaseTimedAction:new(player)
    blocker.maxTime = 10
    blocker.ignoreHandsWounds = true
    ISTimedActionQueue.add(blocker)
    local queue = ISTimedActionQueue.getTimedActionQueue(player)

    local owned = Device.beginOwnedAction("SetVolume", player, item, 0.8, {})
    check("owned action queued", owned ~= nil and queue:indexOf(owned.action) == 2)
    check("owned action not yet begun", owned ~= nil and owned.action.action == nil)

    check("cancel reports success", Device.cancelOwnedAction(owned) == true)
    check("owned action left the queue", queue:indexOf(owned.action) == -1)
    check("player's own action untouched", queue:indexOf(blocker) == 1)

    -- The player's action finishes; ours must not start behind it.
    blocker:perform()
    check("cancelled action never began", owned.action.action == nil and not owned.started)
    check("volume unchanged", data.volume == 0.2)
    check("queue empty", #queue.queue == 0)
end

print("cancel while running")
do
    local player = newCharacter()
    local item, data = newRadio()
    local owned = Device.beginOwnedAction("SetVolume", player, item, 0.8, {})
    check("owned action begun", owned ~= nil and owned.action.action ~= nil)
    check("cancel reports success", Device.cancelOwnedAction(owned) == true)
    check("stop observed", owned.stopped == true)
    check("volume unchanged", data.volume == 0.2)
end

print("cancel after it already left the queue")
do
    local player = newCharacter()
    local item = newRadio()
    local blocker = ISBaseTimedAction:new(player)
    blocker.maxTime = 10
    blocker.ignoreHandsWounds = true
    ISTimedActionQueue.add(blocker)
    local owned = Device.beginOwnedAction("SetVolume", player, item, 0.8, {})
    ISTimedActionQueue.getTimedActionQueue(player):removeFromQueue(owned.action)
    check("already-gone action counts as cancelled", Device.cancelOwnedAction(owned) == true)
end

print("nothing to cancel")
check("nil handle", Device.cancelOwnedAction(nil) == false)

if failures > 0 then
    error(tostring(failures) .. " queue check(s) failed")
end
print("queue harness: all checks passed")
