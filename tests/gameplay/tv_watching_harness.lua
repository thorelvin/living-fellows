-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local TV = SC.TVWatching
local originalUtil, originalRegistry, originalPeek =
    SC.GameplayUtil, SC.Registry, SC.Downtime.peek
local originalSeating, originalPerks, originalSandbox, originalAddXp =
    SeatingManager, Perks, SandboxVars, addXp
local originalSay, originalLastSpoken, originalRand =
    SC.Dialogue.say, SC.Dialogue.lastSpokenAt, ZombRand
local originalBaseLife, originalNavigation = SC.BaseLife, SC.Navigation
local spoken = {}
SC.Dialogue.say = function(value, topic)
    spoken[#spoken + 1] = { actor = value, topic = topic }
    return true
end
SC.Dialogue.lastSpokenAt = function() return -math.huge end
ZombRand = function() return 0 end
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "TV check " .. tostring(checks) .. ": " .. message)
end

local room = {}
local upperRoom = {}
local squares = {}
local function square(x, y, z)
    z = z or 0
    local key = x .. ":" .. y .. ":" .. z
    local value = squares[key]
    if not value then
        value = { x = x, y = y, z = z, objects = {},
            room = z == 0 and room or upperRoom }
        function value:getRoom() return self.room end
        squares[key] = value
    end
    return value
end
local television = { square = square(10, 10), on = true, power = 1, volume = 0.5 }
function television:getDeviceData()
    return {
        getIsTelevision = function() return true end,
        getIsTurnedOn = function() return self.on end,
        getPower = function() return self.power end,
        getDeviceVolume = function() return self.volume end,
    }
end
television.square.objects[1] = television
local chair = { square = square(10, 12) }
chair.square.objects[1] = chair
local function actor(x, y)
    local value = {
        square = square(x, y), seated = false, xp = 0, level = 0,
        known = {}, recipes = {},
    }
    function value:getSitOnFurnitureDirection()
        return self.seatDirection or "N"
    end
    function value:getPerkLevel() return self.level end
    function value:getXp()
        return { getXP = function() return self.xp end,
            AddXP = function(_, _, amount) self.xp = self.xp + amount end }
    end
    function value:isKnownMediaLine(guid) return self.known[guid] == true end
    function value:addKnownMediaLine(guid) self.known[guid] = true end
    function value:learnRecipe(recipe) self.recipes[recipe] = true return true end
    function value:faceThisObject(object) self.faced = object end
    return value
end
local first, second = actor(10, 13), actor(10, 13)
local firstRecord = { state = { downtime = {} } }
local secondRecord = { state = { downtime = {} } }
local actors = { first, second }
local records = { [first] = firstRecord, [second] = secondRecord }
local active = {}
local clock = 100000

SC.GameplayUtil = {
    call = function(object, method, ...)
        if object == nil or type(object[method]) ~= "function" then
            return nil, false
        end
        local ok, result = pcall(object[method], object, ...)
        return ok and result or nil, ok
    end,
    squareOf = function(value) return value and (value.square or value) end,
    position = function(value)
        local point = value and (value.square or value)
        return point and point.x, point and point.y, point and point.z
    end,
    gridSquare = function(x, y, z)
        return squares[x .. ":" .. y .. ":" .. z]
    end,
    squareObjects = function(value, callback)
        for _, object in ipairs(value.objects) do
            if callback(object) == false then break end
        end
    end,
    canSee = function() return true end,
    isSquareFree = function() return true end,
    movingBlocker = function() return nil end,
    distance = function(a, b)
        local aa, bb = a.square or a, b.square or b
        local dx, dy = aa.x - bb.x, aa.y - bb.y
        return math.sqrt(dx * dx + dy * dy)
    end,
    sameSquare = function(a, b)
        local aa, bb = a.square or a, b.square or b
        return aa == bb
    end,
    nowMs = function() return clock end,
}
SC.Registry = {
    living = function() return actors end,
    idOf = function(value) return records[value] and "sc-tv-" .. tostring(value) end,
    byId = function()
        -- The media adapter resolves the exact actor through idOf below.
        return nil
    end,
}
local ids = { [first] = "sc-tv-first", [second] = "sc-tv-second" }
local byId = { ["sc-tv-first"] = firstRecord, ["sc-tv-second"] = secondRecord }
SC.Registry.idOf = function(value) return ids[value] end
SC.Registry.byId = function(id) return byId[id] end
SC.Downtime.peek = function(value) return { active = active[value] } end
SeatingManager = { getInstance = function()
    return { getFacingDirection = function() return "N" end }
end }
Perks = { Woodwork = "Woodwork" }
SandboxVars = { LevelForMediaXPCutoff = 3 }
addXp = function(value, _, amount) value.xp = value.xp + amount end

local hooks = {
    seatingStatus = function(value) return value.seated and "furniture" or "standing" end,
    furnitureKind = function(value) return value == chair and "sit" or nil end,
    reserved = function() return false end,
    cooling = function() return false end,
    freeAccess = function() return false, { chair.square } end,
}
local seat = TV.candidate(first, {}, 100000, hooks)
check(seat and seat.kind == "sit" and seat.object == chair,
    "a powered TV chooses a screen-facing chair")
first.seated = true
first.square = chair.square
first.seatDirection = "S"
check(TV.candidate(first, {}, 100000, hooks) == nil,
    "a chair facing away from the screen is not a viewing position")
first.seatDirection = "N"
local watch = TV.candidate(first, {}, 100000, hooks)
check(watch and watch.kind == "tv_watch" and watch.seated,
    "a seated companion watches from the correctly oriented seat")
check(TV.start(first, watch, 100000), "a seated viewer starts watching")
active[first] = watch
check(TV.isWatching(first, 10, 10, 0)
    and not TV.isWatching(first, 11, 10, 0),
    "TV learning is tied to the actual screen source")

TV.onDeviceText("episode-1", "CRP+1", 10, 10, 0)
check(first.xp == 50 and second.xp == 0
    and firstRecord.state.downtime.mediaLines[1] == "episode-1",
    "only the watcher gets stock-sized carpentry XP and saves the line")
check(#spoken == 1 and spoken[1].actor == first
        and spoken[1].topic == "downtime.tv.learn",
    "a viewer sometimes comments on a useful broadcast lesson")
TV.onDeviceText("episode-1", "CRP+1", 10, 10, 0)
check(first.xp == 50 and #spoken == 1,
    "replaying one line gives neither XP nor a repeated comment")
TV.onDeviceText("episode-2", "CRP+1", 11, 10, 0)
check(first.xp == 50, "text from another device is ignored")

second.seated, second.square = true, chair.square
local secondWatch = TV.candidate(second, {}, 100000, hooks)
check(TV.start(second, secondWatch, 100000),
    "a second companion can watch the same TV")
active[second] = secondWatch
clock = clock + 9000
first.level = 3
TV.onDeviceText("episode-3", "CRP+1,RCP=Make Shelf", 10, 10, 0)
first.level = 0
check(first.xp == 50 and second.xp == 50
    and first.recipes["Make Shelf"] and second.recipes["Make Shelf"],
    "the second viewer learns independently and recipes reach both")
check(#spoken == 2 and spoken[2].actor == second,
    "separate viewers can each react without one speaking twice")
clock = clock + 50000
TV.onDeviceText("episode-plain", "", 10, 10, 0)
check(#spoken == 3 and spoken[3].topic == "downtime.tv.comment",
    "one viewer comments while the other gives the same screen room")
clock = clock + 9000
TV.onDeviceText("episode-plain-2", "", 10, 10, 0)
check(#spoken == 4 and spoken[4].actor == second
        and spoken[4].topic == "downtime.tv.comment",
    "the next viewer may comment on a later line without overlap")

television.on = false
TV.onDeviceText("episode-4", "CRP+1", 10, 10, 0)
check(first.xp == 50 and second.xp == 50,
    "an off TV neither attracts viewers nor grants XP")
television.on = true
first.level = 3
TV.onDeviceText("episode-5", "CRP+1", 10, 10, 0)
check(first.xp == 50, "media XP respects the player's level cutoff")

first.seated = false
first.square = square(10, 14)
chair.square.objects = {}
local standing = TV.candidate(first, {}, 100000, hooks)
check(standing and standing.kind == "tv_watch" and not standing.seated,
    "without a usable chair the companion chooses a standing viewpoint")
check(TV.start(first, standing, 100000) and first.faced == television,
    "a standing viewer faces the television before watching")

local upstairsTelevision = { square = square(10, 10, 1),
    on = true, power = 1, volume = 0.5,
    getDeviceData = television.getDeviceData }
upstairsTelevision.square.objects[1] = upstairsTelevision
square(10, 11, 1)
television.on = false
local routeAllowed, onCamp = true, true
local requested
SC.BaseLife = {
    active = function() return true end,
    allowsFloorTransit = function() return routeAllowed end,
    isInside = function() return onCamp end,
    admitsStairTransit = function() return false end,
}
SC.Navigation = {
    request = function(_, goal, _, intent)
        requested = { goal = goal, intent = intent }
        return true, "native_multi_level"
    end,
    peek = function() return nil end,
}
first.square = square(10, 13, 0)
local upstairsWatch = TV.candidate(first, {}, 100000, hooks, "tv_watch")
check(upstairsWatch and upstairsWatch.object == upstairsTelevision
        and upstairsWatch.crossFloor == true,
    "a reachable powered TV on the camp's upper floor is offered downstairs")
check(TV.valid(first, upstairsWatch, false)
        and not TV.valid(first, upstairsWatch, true),
    "a cross-floor TV stays valid in approach but cannot start downstairs")
check(TV.approach(first, upstairsWatch) and requested
        and requested.goal == upstairsWatch.square
        and requested.intent.workCampOnly == true,
    "the upstairs TV approach uses a camp-bounded native route")
onCamp = false
check(not TV.valid(first, upstairsWatch, false),
    "a viewer outside camp cannot keep the cross-floor TV approach")
onCamp = true
routeAllowed = false
check(not TV.valid(first, upstairsWatch, false)
        and TV.candidate(first, {}, 100000, hooks, "tv_watch") == nil,
    "a disconnected upper floor is neither selected nor retained")
routeAllowed = true
first.square = upstairsWatch.square
check(TV.start(first, upstairsWatch, 100000),
    "the viewer starts only after reaching the upstairs screen room")
television.on = true

local restored = actor(10, 12)
restored.seated = true
ids[restored] = "sc-tv-restored"
byId["sc-tv-restored"] = { state = { downtime = {
    mediaLines = { "episode-1" } } } }
actors = { restored }
local restoredWatch = TV.candidate(restored, {}, 100000, hooks)
check(TV.start(restored, restoredWatch, 100000), "restored viewer starts watching")
active[restored] = restoredWatch
TV.reset()
TV.onDeviceText("episode-1", "CRP+1", 10, 10, 0)
check(restored.xp == 0, "a saved media line remains learned after actor rebuild")

SC.GameplayUtil, SC.Registry, SC.Downtime.peek =
    originalUtil, originalRegistry, originalPeek
SeatingManager, Perks, SandboxVars, addXp =
    originalSeating, originalPerks, originalSandbox, originalAddXp
SC.Dialogue.say, SC.Dialogue.lastSpokenAt, ZombRand =
    originalSay, originalLastSpoken, originalRand
SC.BaseLife, SC.Navigation = originalBaseLife, originalNavigation
print("TV watching harness PASS: " .. tostring(checks) .. " checks")
