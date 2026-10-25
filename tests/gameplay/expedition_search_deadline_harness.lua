-- SPDX-License-Identifier: MIT
-- Run the production footprint cursor and itinerary clock together. The
-- fixture models a normal-speed day; no synchronous full-building scan.
local SC = SurvivorCompanion
local E, Encounter = SC.ExpeditionPrototype, SC.Encounter
local clock, elapsed, minutesPerDay, probes, contentReads = 0, 0, 60, 0, 0
local cells, slot, bounds = {}, nil, { 100, 100, 180, 180 }
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
local function square(x, y, z)
    local id = key(x, y, z)
    cells[id] = cells[id] or { x = x, y = y, z = z, objects = {}, getRoom = function() return {} end }
    return cells[id]
end
local function position(value)
    if not value then return nil end
    local at = value.square or value
    return at.x, at.y, at.z
end
local function distance(a, b)
    local ax, ay, az = position(a)
    local bx, by, bz = position(b)
    return math.sqrt((ax - bx)^2 + (ay - by)^2 + (az - bz)^2)
end
local function call(object, method, ...)
    if object and type(object[method]) == "function" then return object[method](object, ...), true end
    return nil, false
end
local actor = { id = "deadline-worker", square = square(90, 100, 0), inventory = {} }
local player = { square = square(80, 80, 0) }
for _, value in ipairs({ actor, player }) do
    value.getX = function(a) return a.square.x end
    value.getY = function(a) return a.square.y end
    value.getZ = function(a) return a.square.z end
    value.getCurrentSquare = function(a) return a.square end
    value.isDead = function() return false end
end
local commands, runtime = {}, { snapshot = { immediateCount = 0, pressure = 0 } }
SC.GameplayUtil = {
    call = call, nowMs = function() return clock end, position = position,
    config = function(name)
        if name == "performanceScavengeSquaresPerFrame" then return 28 end
        if name == "scavengeSquareBudget" then return 100 end
        if name == "expeditionDestinationRadius" then return 256 end
        return nil
    end,
    nameOf = function() return "Store worker" end, idOf = function(a) return a.id end,
    isDead = function() return false end, actorState = function(_, state) return state or {} end,
    nativeHealth = function() return 100 end, characterStatValue = function() return 0 end,
    distance = distance, distanceSq = function(a, b) return distance(a, b)^2 end,
    sameFloor = function(a, b) return a.square.z == b.square.z end, canSee = function() return false end,
    gridSquare = function(x, y, z) probes = probes + 1 return cells[key(x, y, z)] end,
    squareOf = function(value) return value and (value.square or value) end,
    squareObjects = function(at, callback) for _, object in ipairs(at.objects) do callback(object) end end,
    squareStaticMovingObjects = function() end, hasMethod = function(object, name) return type(object[name]) == "function" end,
    instanceOf = function() return false end, itemHasTag = function() return false end,
    roomName = function() return "store" end, listSize = function(list) return #list end,
    each = function(list, budget, callback, start)
        for index = start or 0, math.min(#list - 1, (start or 0) + budget - 1) do callback(list[index + 1]) end
    end,
    modData = function(value) value.data = value.data or {} return value.data end,
    inventory = function(a) return a.inventory end,
    inventoryContains = function(list, item)
        for _, value in ipairs(list) do if value == item then return true end end return false
    end,
    itemType = function(item) return item.type end, itemName = function(item) return item.type end,
    sameSquare = function(a, b) return distance(a, b) < 0.01 end,
    stop = function() return true end, move = function() return true end,
    transferItemVerified = function() error("discovery must not transfer cargo") end,
}
SC.Registry = { isActive = function(a, id) return a == actor and id == actor.id end,
    byId = function(id) return id == actor.id and { actor = actor, runtime = runtime } end }
SC.Commands = { peek = function() return commands end }
SC.Performance = { claimUnits = function(_, requested) return math.min(28, requested) end }
SC.Logistics = { status = function() return { shouldUnload = false } end,
    audit = function() return { shouldUnload = false, weight = 0, capacity = 20, hardRatio = 0.9 } end,
    itemNeedScore = function(_, item) return item.score or 0, item.category end,
    canTake = function() return true end }
SC.PersonalItems = { isProtected = function() return false end }
SC.Navigation = { interactionTargets = function(_, owner) return { owner.square } end,
    requestAny = function() return true, "walking" end, cancel = function() return true end }
SC.Actor = { setMovement = function() return true end }
SC.NativeActions = { visualStatus = function() return "active" end, stopDirect = function() return true end }
SC.ViewSession = { claim = function(_, a) slot = a return true, a end, slotSqlId = function() return 2 end,
    released = function() slot = nil end, owner = function() return slot and "expedition" end,
    rememberSlotSqlId = function() end }
SCSplitScreenProbe = { isLeader = function(a) return slot == a end, leaderSqlId = function() return 2 end,
    releaseForWorldExit = function() slot = nil return true end }
SC.ExpeditionPlaces = {
    siteFloors = function() return { 0 } end,
    siteContainsPoint = function(_, x, y, z)
        return x >= bounds[1] and x <= bounds[3] and y >= bounds[2] and y <= bounds[4] and z == 0
    end,
    actorInsideSite = function(_, a)
        local x, y, z = position(a)
        return SC.ExpeditionPlaces.siteContainsPoint(nil, x, y, z)
    end,
}
function getSpecificPlayer(index) return index == 0 and player or index == 1 and slot or nil end
function getGameTime() return { getWorldAgeHours = function() return 100 + elapsed * 24 / (minutesPerDay * 60) end,
    getMinutesPerDay = function() return minutesPerDay end } end
function destroyPlayerData() end
Events = nil
local function begin(dayLength, small, withShelf, returnHours)
    if E.current() then assert(E.prepareReset() and E.reset()) end
    Encounter.reset()
    cells, elapsed, contentReads = {}, 0, 0
    clock, minutesPerDay = clock + 10000, dayLength
    bounds = small and { 100, 100, 102, 102 } or { 100, 100, 180, 180 }
    actor.square, player.square = square(90, 100, 0), square(80, 80, 0)
    runtime.snapshot = { immediateCount = 0, pressure = 0 }
    local siteId = bounds[1] .. ":" .. bounds[2] .. ":" .. bounds[3] .. ":" .. bounds[4]
    local started, mission = E.start({ { id = actor.id, actor = actor } }, {
        kind = "search", destination = { x = 100, y = 100, z = 0 },
        request = { category = "useful", quantity = 1 }, turnHomeAfterHours = returnHours or 4,
        site = { id = siteId, label = "Test store", knowledge = "player_seen_interior" } })
    assert(started, "real search controller starts: " .. tostring(mission))
    actor.square = square(100, 100, 0)
    mission.scout.phase, mission.scout.siteApproachConfirmed = "entering_site", true
    E.pulse()
    assert(mission.scout.phase == "searching", "physical arrival starts real search timer")
    commands = { recruited = true, order = "stay", scavenge = true,
        scavengeMissionId = mission.radioSession, scavengeRequestedCategory = "useful",
        scavengeSite = { x = 100, y = 100, z = 0, buildingId = siteId } }
    if withShelf then
        local owner = { square = square(100, 150, 0) }
        local container = { parent = owner }
        owner.getContainer = function() return container end
        container.getParent = function() return owner end
        container.getItems = function() contentReads = contentReads + 1
            return { { type = "Base.CannedFood", category = "food", score = 320 } } end
        owner.square.objects[1] = owner
    end
    return mission
end
local function beat()
    elapsed, clock, probes = elapsed + 1, clock + 1000, 0
    E.pulse()
    if E.testSearchFor(actor) then Encounter.tryScavenge(actor, nil, runtime) end
    assert(probes <= 28, "actual search never exceeds a frame's discovery budget")
end
for _, dayLength in ipairs({ 60, 120 }) do
    local mission = begin(dayLength, false, true)
    local deadline = mission.scout.search.deadlineHour
    for _ = 1, 150 do
        beat()
        if Encounter.peek(actor) and Encounter.peek(actor).task then break end
    end
    local state = Encounter.peek(actor)
    assert(elapsed >= 144 and state and state.task and mission.scout.phase == "searching",
        "late shelf at cursor 4051 is discovered before actual " .. dayLength .. "-minute-day deadline")
    assert(contentReads == 0 and mission.scout.search.deadlineHour == deadline,
        "one initial allowance neither reads remote contents nor extends itself on every pulse")
    actor.square = state.task.owner.square
    beat()
    beat()
    assert(contentReads > 0 and state.task.item and state.task.item.type == "Base.CannedFood",
        "physical arrival opens the late shelf while real controller still permits looting")
end
do
    local mission = begin(60, true, false)
    assert(mission.scout.search.deadlineHour <= 100.77, "small empty stores retain a short finite search")
    for _ = 1, 120 do beat() if mission.scout.phase ~= "searching" then break end end
    assert(mission.scout.phase ~= "searching" and mission.scout.search.endReason == "search_deadline",
        "empty stores eventually return instead of perpetually extending discovery")
    mission = begin(60, false, true, 0.25)
    for _ = 1, 40 do beat() if mission.scout.phase ~= "searching" then break end end
    assert(mission.scout.phase ~= "searching" and mission.scout.search.endReason == "return_time_reached",
        "overall player return deadline preempts the discovery allowance")
    mission = begin(60, false, true)
    runtime.snapshot.immediateCount, runtime.snapshot.pressure = 1, 10
    beat()
    assert(not Encounter.peek(actor) or not Encounter.peek(actor).task,
        "an immediate threat still prevents ordinary container search")
    assert(E.prepareReset() and E.reset() and not E.current(), "cancellation releases the mission during discovery")
end
print("EXPEDITION_SEARCH_DEADLINE_PASS")
