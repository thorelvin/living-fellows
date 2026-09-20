-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "view-control check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local function actorAt(x, y, z)
    local actor = { x = x, y = y, z = z or 0, dead = false }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:isDead() return self.dead end
    return actor
end

local player = actorAt(10, 10, 0)
local selected = actorAt(18, 16, 0)
local keyDown = false
local writes = {}
local clears = 0

function player:setHaloNote(text) self.halo = text end
function getSpecificPlayer(index) return index == 0 and player or nil end
function isKeyDown(key) return key == 26 and keyDown end
function getText(key) return key end

SC.UI = {
    DEFAULT_PEEK_HOTKEY = 26,
    peekHotkey = function() return 26 end,
    selectedActor = function() return selected end,
}

SCBridge = {
    setViewOffset = function(x, y)
        writes[#writes + 1] = { x = x, y = y }
        return true
    end,
    clearViewOffset = function()
        clears = clears + 1
        return true
    end,
}

local View = SC.ViewControl
View.reset()

keyDown = true
View.update()
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
local first = writes[#writes]
check(first.x > 0 and first.x < 8 and first.y > 0 and first.y < 6,
    "held Peek eases toward the selected live actor instead of snapping")
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
local second = writes[#writes]
check(second.x > first.x and second.x < 8 and second.y > first.y and second.y < 6,
    "successive frames move monotonically toward the live companion offset")
check(View.status().active == true and View.status().reason == "active",
    "status reports an active Peek while the key and target are valid")

player.x = 16
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
local moved = writes[#writes]
check(moved.x < second.x, "Peek follows the current player-to-companion delta")

keyDown = false
for _ = 1, 24 do
    SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    View.update()
end
check(clears == 1 and View.status().reason == "idle"
        and View.status().x == 0 and View.status().y == 0,
    "release eases home and clears the native offset exactly once")

local writesBeforeRefusal = #writes
selected = actorAt(40, 10, 0)
keyDown = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(#writes == writesBeforeRefusal and View.status().reason == "too_far",
    "a companion outside the sixteen-tile loaded-area bound cannot move the camera")
check(player.halo == "UI_SC_Peek_TooFar", "distance refusal is surfaced once to the player")

keyDown = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
selected = actorAt(12, 10, 1)
keyDown = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(#writes == writesBeforeRefusal and View.status().reason == "other_floor",
    "Peek refuses a selected companion on another floor")
check(player.halo == "UI_SC_Peek_OtherFloor", "floor refusal is surfaced to the player")

keyDown = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
selected = nil
keyDown = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(View.status().reason == "no_selection"
        and player.halo == "UI_SC_Peek_NoSelection",
    "Peek explains a missing roster selection without touching the view")

keyDown = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
selected = actorAt(13, 10, 0)
local writesBeforeDisabled = #writes
SC.UI.peekHotkey = function() return 0 end
keyDown = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(#writes == writesBeforeDisabled and View.status().active == false,
    "an explicitly unbound Peek key never falls back to the default binding")
SC.UI.peekHotkey = nil
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(#writes > writesBeforeDisabled,
    "an absent key API still uses the registered default Peek binding")
keyDown = false

local watched = actorAt(15, 12, 0)
local replacement = actorAt(14, 11, 0)
local watchRecord = { actor = watched, runtime = {} }
local originalIsCompanion = SC.Actor and SC.Actor.isCompanion or nil
SC.Actor = SC.Actor or {}
local actorOnlyActive = true
SC.Actor.isCompanion = function(value)
    return value == watched and actorOnlyActive or value == replacement
end
SC.Registry = {
    byId = function(id) return id == "sc-watched" and watchRecord or nil end,
    isActive = function(actor, id)
        return id == "sc-watched" and watchRecord ~= nil
            and watchRecord.actor == actor
            and not (watchRecord.runtime and watchRecord.runtime.inactive == true)
    end,
}
local beganWatch, watchReason = View.watch("sc-watched", watched)
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(beganWatch and watchReason == "watching" and View.status().watching == true
        and View.status().watchId == "sc-watched" and View.status().active == true,
    "right-click Watch owns a persistent offset without changing player identity")
watchRecord.actor = replacement
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(View.status().watchActor == replacement and View.status().watching == true,
    "Watch follows the live same-id registry replacement and drops the old object reference")
local stoppedWatch, stopReason = View.stopWatching()
for _ = 1, 24 do
    SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    View.update()
end
check(stoppedWatch and stopReason == "watch_stopped"
        and View.status().watching == false and View.status().reason == "idle",
    "Stop watching eases home and leaves no persistent camera ownership")

watchRecord.actor, watchRecord.runtime = watched, { inactive = false }
check(View.watch("sc-watched", watched) == true, "active watched record can be selected again")
watchRecord.runtime.inactive = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(View.status().watching == false,
    "an inactive or quarantined registry record ends Watch and starts easing home")
watchRecord.runtime.inactive = false
check(View.watch("sc-watched", watched) == true, "live watched record can be restored")
watchRecord = nil
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(View.status().watching == false,
    "removing a watched registry record never retains its stale actor object")

actorOnlyActive = true
check(View.watch(watched) == true, "actor-only Watch validates a live companion")
actorOnlyActive = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
check(View.status().watching == false,
    "actor-only Watch ends when companion ownership is no longer live")
SC.Registry = nil
SC.Actor.isCompanion = originalIsCompanion

selected = actorAt(14, 10, 0)
keyDown = true
SC_TEST_CLOCK = SC_TEST_CLOCK + 100
View.update()
local clearsBeforeReset = clears
View.reset()
check(clears == clearsBeforeReset + 1 and View.status().reason == "idle",
    "world reset clears any owned camera offset")

print("VIEW_CONTROL_KAHLUA_PASS checks=" .. tostring(checks))
