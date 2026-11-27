-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local U, Angling = SC.GameplayUtil, SC.Fishing
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local function square(x, y, water)
    local tile = { x = x, y = y, z = 0, water = water }
    function tile:getX() return self.x end
    function tile:getY() return self.y end
    function tile:getZ() return self.z end
    return tile
end

local bank, shallows, water = square(10, 10), square(11, 10, true), square(12, 10, true)
local tiles = { [10] = bank, [11] = shallows, [12] = water }
function getCell()
    return { getGridSquare = function(_, x, y, z)
        return y == 10 and z == 0 and tiles[math.floor(x)] or nil
    end }
end
SC.Topology = { squareIsWater = function(tile) return tile.water == true end }
function U.isSquareFree(tile) return not tile.water end
function U.itemHasTag(item, tag) return item.rod == true and tag == "FISHING_ROD" end

local paused, delta = false, 0
function isGamePaused() return paused end
function getGameTime()
    return { getRealworldSecondsSinceLastUpdate = function() return delta end }
end
local function advance(milliseconds)
    delta = milliseconds / 1000
    Angling.onTick()
end

local rod = { rod = true, __modData = { fishing_Lure = "Base.Worm" } }
local heldBefore = {}
local actor = { x = 10.5, y = 10.5, z = 0, square = bank, hand = heldBefore,
    action = "idle", sounds = {}, casts = 0, stockUpdates = 0 }
actor.inventory = { contains = function(_, item) return item == rod end }
function actor:getInventory() return self.inventory end
function actor:getPrimaryHandItem() return self.hand end
function actor:setPrimaryHandItem(item) self.hand = item end
function actor:setFishingStage(stage) self.stage = stage end
function actor:setVariable(key, value) self[key] = value end
function actor:reportEvent(event)
    if event == "EventFishing" then self.casts = self.casts + 1 end
end
function actor:playSound(sound) self.sounds[sound] = (self.sounds[sound] or 0) + 1 end
function actor:getCompanionActionStateName() return self.action end
function actor:getPlayerNum() return 0 end

local playerManager = { player = {} }
local bobbers, resets, hookCount = {}, 0, 0
local wrongSplash = false
Fishing = {
    ManagerInstances = { [0] = playerManager },
    FishingRod = { new = function(_, fisher)
        assert(fisher:getPrimaryHandItem() == rod, "cast uses the owned equipped rod")
        return { resetItemModel = function() resets = resets + 1 end }
    end },
    Bobber = { new = function(_, fisher, _, x, y)
        assert(x == 12.5 and y == 10.5, "bobber lands in the authored water")
        fisher:playSound("LureHitWater")
        local bobber = { sq = not wrongSplash and water or nil }
        function bobber:destroy() self.released = true end
        function bobber:update() error("scripted fishing entered the random simulation") end
        bobbers[#bobbers + 1] = bobber
        return bobber
    end },
}

local ordinary = { stockUpdates = 0 }
Angling._setStateForTests(ordinary, { mode = "expedition", phase = "waiting", bobber = {
    update = function() ordinary.stockUpdates = ordinary.stockUpdates + 1 end,
} })
local site = Angling.usableBank(bank)
check(site and site.water.x == 12.5 and site.dx == 1, "site finder exposes a real dry bank and two water tiles")
check(not Angling.beginScriptedCast(actor, { bank = site.bank, water = { x = 11.5, y = 10.5, z = 0 } }, rod, "other"),
    "a nearby but unverified cast target is refused")

local function onHook(fisher, token)
    check(fisher == actor and token == "first", "hook callback keeps actor and token ownership")
    check(Angling.scriptedCastStatus(actor, token) == "hooked",
        "the runtime advances state before dispatching the one-off callback")
    hookCount = hookCount + 1
end

check(Angling.beginScriptedCast(actor, site, rod, "first", onHook)
    and actor.stage == "Cast" and actor.casts == 1 and actor.sounds.CastFishingLine == 1,
    "the native cast starts exactly once")
check(Angling.beginScriptedCast(actor, site, rod, "first", onHook) and actor.casts == 1
    and not Angling.beginScriptedCast(actor, site, rod, "other"),
    "repeat calls reuse the owned cast and other tokens cannot seize it")
check(Fishing.ManagerInstances[0] == playerManager, "a scripted cast preserves another player's manager")
advance(1100)
check(Angling.scriptedCastStatus(actor, "first") == "casting" and #bobbers == 0,
    "a timer alone does not confirm that the native graph cast")
actor.action = "fishing"
advance(16)
check(Angling.scriptedCastStatus(actor, "first") == "waiting" and #bobbers == 1
    and actor.stage == "Idle" and actor.sounds.LureHitWater == 1,
    "time zero is a verified bobber in the exact water")

advance(5999)
check(Angling.scriptedCastStatus(actor, "first") == "waiting" and hookCount == 0,
    "no bite at 5,999 active real milliseconds")
paused = true
advance(10000)
check(Angling.scriptedCastStatus(actor, "first") == "waiting" and hookCount == 0,
    "pause does not advance the real-time gate")
paused = false
advance(1)
local stage, _, didHook = Angling.scriptedCastStatus(actor, "first")
check(stage == "hooked" and didHook and hookCount == 1 and actor.stage == "PickUp"
    and actor.sounds.PickUpFish == 1 and bobbers[1].catchFishStarted,
    "at 6,000 ms start the actual pickup and fire the cue once")
advance(2199)
check(Angling.scriptedCastStatus(actor, "first") == "hooked" and actor.sounds.PickUpFish == 1,
    "consecutive updates do not repeat the cue or land too soon")
advance(1)
stage, _, didHook = Angling.scriptedCastStatus(actor, "first")
check(stage == "landed" and didHook and not Angling.active(actor) and actor.hand == heldBefore
    and actor.FishingFinished and actor.stage == "None" and bobbers[1].released and resets == 1,
    "landing releases the bobber and restores the exact previous hand while retaining the receipt")
check(Angling.beginScriptedCast(actor, site, rod, "first", onHook) and actor.casts == 1,
    "a completed token cannot start a second catch")
check(ordinary.stockUpdates > 0, "ordinary fishing still advances its native bobber independently")

check(Angling.beginScriptedCast(actor, site, rod, "second"), "a new token starts a later cast")
advance(1100)
check(not Angling.cancelScriptedCast(actor, "first", "wrong_owner"), "an old token cannot cancel the new cast")
check(Angling.cancelScriptedCast(actor, "second", "left_bank") and bobbers[2].released,
    "cancelling before the bite releases native resources")
stage, _, didHook = Angling.scriptedCastStatus(actor, "second")
check(stage == "cancelled" and not didHook and actor.sounds.PickUpFish == 1,
    "a cancelled cast before the bite gives no hook receipt")

check(Angling.beginScriptedCast(actor, site, rod, "third"), "start a third cast to exercise interruption")
advance(1100)
advance(6000)
actor.action = "melee"
advance(16)
stage, _, didHook = Angling.scriptedCastStatus(actor, "third")
check(stage == "cancelled" and didHook and bobbers[3].released and actor.hand == heldBefore,
    "an interruption after the bite preserves the hook receipt and frees the pose")

actor.action, wrongSplash = "fishing", true
check(Angling.beginScriptedCast(actor, site, rod, "fourth"), "start a cast whose native bobber fails placement")
advance(1100)
stage, _, didHook = Angling.scriptedCastStatus(actor, "fourth")
check(stage == "cancelled" and not didHook and bobbers[4].released,
    "a detached bobber is cleaned up and never starts the six-second clock")
Angling.reset()
check(Angling.scriptedCastStatus(actor, "fourth") == nil, "world reset discards runtime receipts")

SC_TEST_REPORT = "Scripted fishing PASS: " .. tostring(checks) .. " checks"
