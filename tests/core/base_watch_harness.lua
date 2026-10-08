-- SPDX-License-Identifier: MIT
-- A real second slot is asynchronous; prove Base Watch survives the join,
-- remote radio exchange, handoff, joined release, and cold session restore.
local SC = SurvivorCompanion
local watch, view = SC.BaseWatch, SC.ViewSession
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "base watch check " .. checks .. ": " .. message)
end

local function actor(id, x)
    local value = { id = id, name = id, x = x, y = 2, z = 0 }
    function value:isDead() return self.dead == true end
    function value:isCorpseReady() return self.corpseReady == true end
    function value:isBridgeHealthy() return true end
    function value:getCurrentSquare() return {} end
    function value:getVehicle() return nil end
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getInventory() return self.inventory end
    function value:getEquipedRadio() return self.radio end
    function value:getPrimaryHandItem() return self.radio end
    function value:getSecondaryHandItem() return nil end
    function value:getClothingItem_Back() return nil end
    return value
end
local human = actor("human", 2)
local alice, bob = actor("sc-alice", 3), actor("sc-bob", 4)
local cold = actor("cold-loader", 3)
local slot, nativeLeader, policy, detached
local radioHook
local hudClock = { y = 10 }
local speedControls = { y = 42 }
function hudClock:setY(y) self.y = y end
UIManager = {
    getClock = function() return hudClock end,
    resize = function() speedControls.y = hudClock.y + 32 end,
}
local playerRadio, leaderRadio
local function radio(owner)
    local device = {}
    local data = {}
    function device:getContainer() return owner.inventory end
    function device:getDeviceData() return data end
    function data:getIsTwoWay() return true end
    function data:getIsTurnedOn() return true end
    function data:getHasBattery() return true end
    function data:getPower() return 1 end
    function data:getTransmitRange() return 1000 end
    function data:getMicIsMuted() return false end
    function data:isNoTransmit() return false end
    function data:getChannel() return self.channel or 90000 end
    return device, data
end
for _, survivor in ipairs({ human, alice, bob }) do
    survivor.inventory = {}
    survivor.radio, survivor.radioData = radio(survivor)
end
playerRadio, leaderRadio = human.radio, alice.radio

function getSpecificPlayer(index)
    if index == 0 then return human end
    if index == 1 then return slot end
end
function destroyPlayerData(value)
    check(value == slot, "teardown owns the exact second local player")
    detached = (detached or 0) + 1
end
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    nameOf = function(value) return value.name end,
    call = function(value, method, message) value.lastHalo = message end,
}
local records = {
    [alice.id] = { id = alice.id, actor = alice },
    [bob.id] = { id = bob.id, actor = bob },
}
SC.Registry = {
    byId = function(id) return records[id] end,
    snapshot = function() return { records[alice.id], records[bob.id] } end,
    isActive = function(value, id) return records[id].actor == value end,
}
local base = { id = "test-base" }
local residents = {
    [alice.id] = { baseId = base.id, duty = true },
    [bob.id] = { baseId = base.id, duty = true },
}
SC.BaseLife = {
    active = function() return base end,
    resident = function(id) return residents[id] end,
    restriction = function() return nil end,
    isInside = function(value) return value.x < 10 end,
    isOutdoorSquare = function(value) return value.outside == true end,
    jobFor = function() return nil end,
    summary = function()
        return { duty = 2, jobs = { active = 1, blocked = 0 },
            operations = { alerts = {} }, residentRows = {
                { id = alice.id, duty = true }, { id = bob.id, duty = true },
            } }
    end,
    setPolicy = function(key, value)
        if key ~= "defense" then return false end
        policy = value
        return true
    end,
}
SC.Commands = { peek = function() return { recruited = true, order = "base_duty" } end }
local expeditionActive
SC.ExpeditionPrototype = { current = function() return expeditionActive end }
SC.Persistence = { pendingBootstrap = function(id)
    if id == alice.id then return { x = 3, y = 2, z = 0 } end
end }
function getWorld()
    return { getCell = function()
        return { getGridSquare = function() return nil end }
    end }
end
Events = { OnDeviceText = {
    Add = function(callback) radioHook = callback end,
    Remove = function(callback)
        if radioHook == callback then radioHook = nil end
    end,
} }
SCSplitScreenProbe = {
    promote = function(value, sqlId)
        check(nativeLeader == nil and slot == nil, "single view is claimed once")
        nativeLeader = value
        value.sqlId = sqlId >= 2 and sqlId or 2
        return value
    end,
    isLeader = function(value) return nativeLeader == value end,
    isColdProbe = function(value) return value == cold and nativeLeader == cold end,
    startColdCompanionProbe = function(x, y, z, sqlId)
        check(x == 3 and y == 2 and z == 0 and sqlId == 2,
            "cold loader receives only saved tile and slot identity")
        nativeLeader, cold.sqlId = cold, sqlId
        return cold
    end,
    replaceColdProbeWithRestoredLeader = function(value, sqlId)
        check(slot == cold and nativeLeader == cold and value == alice
            and sqlId == 2, "cold handoff targets restored resident")
        nativeLeader, slot, value.sqlId = value, value, sqlId
        return true
    end,
    leaderSqlId = function() return slot and slot.sqlId or -1 end,
    canReleaseJoinedLeader = function() return slot == nativeLeader end,
    persistJoinedLeaderSlotForReuse = function() return slot.sqlId end,
    releaseJoinedLeader = function()
        slot, nativeLeader = nil, nil
        return true
    end,
    stageDeadCorpseChunk = function() return true end,
    handoff = function(value)
        check(nativeLeader:isDead(), "dead leader handoff is native")
        value.sqlId = nativeLeader.sqlId
        nativeLeader, slot = value, value
        return value
    end,
    handoffLiving = function(value)
        check(not nativeLeader:isDead(), "living leader handoff is native")
        value.sqlId, nativeLeader.sqlId = nativeLeader.sqlId, -1
        nativeLeader, slot = value, value
        return value
    end,
    isLeaderRadioTextContextActive = function() return true end,
    sendTestRadioWithLeaderText = function(x, y, channel, message, guid, codes)
        check(radioHook ~= nil, "radio hook installed")
        local receiver = x == human.x and human.radio ~= nil
            and nativeLeader.radio or human.radio
        if receiver:getDeviceData():getChannel() == channel then
            radioHook(guid, codes, x, y, 0, message, receiver)
        end
    end,
    releaseForWorldExit = function()
        slot, nativeLeader = nil, nil
        return true
    end,
}

expeditionActive = {}
check(watch.start(alice.id) == false, "expedition owns slot exclusively")
expeditionActive = nil
check(watch.start(alice.id) == true, "indoor base resident starts watch")
check(view.owner() == "base_watch" and slot == nil,
    "mode owns pending async second slot")
check(watch.pulse() == true, "pending join is not mistaken for failure")
slot = alice
check(watch.pulse() == true, "joined base leader begins service")
check(watch.contextFor(bob, human) == alice,
    "base-duty resident uses streamed leader as context")
bob.outside = true
check(watch.contextFor(bob, human) == alice,
    "outdoor work keeps base leader as context")
bob.outside = false

human.x = 100
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and watch.current().departed == true,
    "departure leaves second local view at camp")
check(watch.isRemoteResident(bob, human) == true,
    "remote base resident rejects direct local commands")
check(watch.sendRadio(human, "status") == true,
    "status needs a real received radio text event")
check(watch.sendRadio(human, "defense", "all_hands") == true
        and policy == "all_hands", "defense policy follows radio acknowledgement")
human.radioData.channel = 91000
check(watch.sendRadio(human, "defense", "rotation") == false
        and policy == "all_hands", "unmatched channel cannot mutate policy")
human.radioData.channel = nil

alice.outside = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
watch.pulse()
SC_TEST_CLOCK = SC_TEST_CLOCK + 5000
check(watch.pulse() == true and watch.current().leaderActor == bob
        and slot == bob and alice.sqlId == -1,
    "indoor resident takes the living leader's saved view identity")
check(view.claim("expedition", alice) == false,
    "expedition cannot claim Base Watch's view")
human.x = 3
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
hudClock.y, speedControls.y = 900, 932
check(watch.pulse() == true and watch.current() == nil
        and view.owner() == nil and view.slotSqlId() == 2,
    "return to camp releases second view and reuses one SQL row")
check(hudClock.y == 10 and speedControls.y == 42,
    "Base Watch return restores clock and speed controls to primary HUD")

alice.outside = false
check(watch.start(alice.id) == true, "watch can start again")
slot = alice
check(watch.pulse() == true, "second watch joins")
human.x = 100
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
watch.pulse()
local saved = watch.export()
local savedSlot = view.export()
check(saved.departed and saved.slotSqlId == 2,
    "away save keeps watch and stable slot identity")
check(watch.prepareReset() == true and watch.reset() == true,
    "world exit releases native view before module reset")
view.reset()
records[alice.id].actor = nil
records[bob.id].actor = nil
check(view.restore(savedSlot) == true and watch.restore(saved) == true,
    "world load restores one view owner and camp descriptor")
check(watch.pulse() == false and nativeLeader == cold and slot == nil,
    "restart streams distant camp with a temporary local view")
check(watch.pulse() == false and nativeLeader == cold and slot == nil,
    "repeated restore pulses do not queue another cold loader")
slot = cold
records[alice.id].actor = alice
records[bob.id].actor = bob
check(watch.pulse() == true and view.owner() == "base_watch",
    "restored leader replaces cold loader and reacquires camp view")

local transientAttempts = 0
SCSplitScreenProbe.stageDeadCorpseChunk = function()
    transientAttempts = transientAttempts + 1
    if transientAttempts == 1 then
        error("native corpse is not on a loaded square")
    end
    return true
end
bob.dead, bob.corpseReady = true, true
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and transientAttempts == 1,
    "transient corpse staging failure does not end the watch")
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and transientAttempts == 1,
    "transient staging waits for backoff instead of retrying every pulse")
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and transientAttempts == 2
        and watch.describe().technicalIssue == nil,
    "a later successful staging clears the transient warning")
bob.dead, bob.corpseReady = false, false

-- Retaining the corpse chunk can be refused (eight-chunk limit, unshared
-- chunk). The corpse then falls back to ordinary world saving; the dead
-- leader is still replaced and the refusal is reported once.
local stagingAttempts = 0
SCSplitScreenProbe.stageDeadCorpseChunk = function()
    stagingAttempts = stagingAttempts + 1
    error("corpse chunk retention limit reached")
end
alice.dead, alice.corpseReady = true, true
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and watch.current().leaderActor == bob
        and slot == bob,
    "dead leader hands off to surviving resident even if its corpse chunk is refused")
SC_TEST_CLOCK = SC_TEST_CLOCK + 1000
check(watch.pulse() == true and stagingAttempts == 1
        and string.find(tostring(watch.describe().technicalIssue),
            "corpse_retention_failed", 1, true) ~= nil,
    "a refused corpse chunk is reported and not retried every second")
check(detached >= 2, "joined releases detach slot UI")
SC_TEST_REPORT = "BASE_WATCH_PASS checks=" .. tostring(checks)
