-- SPDX-License-Identifier: MIT
-- Search a wide, loaded store through the production discovery/approach flow.
local SC = SurvivorCompanion
local clock, probes, contentReads, moves, failures = 10000, 0, 0, 0, 0
local cells = {}
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
local function square(x, y, z, foreign)
    local value = { x = x, y = y, z = z, foreign = foreign, objects = {} }
    cells[key(x, y, z)] = value
    return value
end
local function position(value)
    if not value then return nil end
    local target = value.square or value
    return target.x, target.y, target.z
end
local function distance(a, b)
    local ax, ay, az = position(a)
    local bx, by, bz = position(b)
    return math.sqrt((ax - bx)^2 + (ay - by)^2 + (az - bz)^2)
end
local function call(value, method, ...)
    if value and type(value[method]) == "function" then return value[method](value, ...), true end
    return nil, false
end
local commands = { recruited = true, scavenge = true, order = "stay",
    scavengeMissionId = "store-trip", scavengeRequestedCategory = "useful",
    scavengeSite = { x = 140, y = 100, z = 0, buildingId = "100:100:140:120" } }
SC.GameplayUtil = {
    config = function() return nil end, nowMs = function() return clock end,
    actorState = function(_, runtime) return runtime or {} end,
    position = position, distance = distance, distanceSq = function(a, b) return distance(a, b)^2 end,
    gridSquare = function(x, y, z) probes = probes + 1 return cells[key(x, y, z)] end,
    squareOf = function(value) return value and (value.square or value) end,
    squareObjects = function(value, callback) for _, object in ipairs(value.objects) do callback(object) end end,
    squareStaticMovingObjects = function() end,
    call = call, hasMethod = function(value, method) return type(value[method]) == "function" end,
    instanceOf = function() return false end, itemHasTag = function() return false end,
    roomName = function() return "" end, idOf = function(actor) return actor.id end,
    nativeHealth = function() return 100 end, characterStatValue = function() return 0 end,
    listSize = function(list) return #list end,
    each = function(list, budget, callback, start)
        for index = start or 0, math.min(#list - 1, (start or 0) + budget - 1) do callback(list[index + 1]) end
    end,
    modData = function(value) value.data = value.data or {} return value.data end,
    inventory = function(actor) return actor.inventory end,
    inventoryContains = function(list, item)
        for _, value in ipairs(list) do if value == item then return true end end return false
    end,
    itemType = function(item) return item.type end, itemName = function(item) return item.type end,
    sameSquare = function(a, b) return distance(a, b) < 0.01 end,
    stop = function() return true end,
    move = function() return true end,
    transferItemVerified = function() error("discovery or approach must never transfer an item") end,
}
SC.Performance = { claimUnits = function(_, requested) return math.min(5, requested) end }
SC.Commands = { peek = function() return commands end }
SC.Logistics = {
    status = function() return { shouldUnload = false } end,
    audit = function() return { shouldUnload = false } end,
    itemNeedScore = function(_, item) return item.score or 0, item.category end,
    canTake = function() return true end,
}
SC.PersonalItems = { isProtected = function(item) return item.protected == true end }
SC.ExpeditionPlaces = {
    siteFloors = function() return { 0, 1 } end,
    siteContainsPoint = function(_, x, y, z)
        local value = cells[key(x, y, z)]
        return x >= 100 and x <= 140 and y >= 100 and y <= 120
            and (z == 0 or z == 1) and not (value and value.foreign)
    end,
}
SC.ExpeditionPrototype = { noteSearchWorkerFailure = function(_, missionId, reason)
    assert(missionId == "store-trip" and reason == "nothing_needed")
    failures = failures + 1
end }
SC.Navigation = {
    interactionTargets = function(_, owner) return { owner.square } end,
    requestAny = function(_, _, _, intent)
        assert(intent.action == "move_to_scavenge" and intent.preferVerifiedPath)
        moves = moves + 1
        return true, "walking"
    end,
    cancel = function() return true end,
}
SC.Actor = { setMovement = function() return true end }
SC.NativeActions = { visualStatus = function() return "active" end, stopDirect = function() return true end }
local function source(value, items)
    local owner = { square = value }
    local container = { parent = owner }
    function owner:getContainer() return container end
    function container:getParent() return owner end
    function container:getItems() contentReads = contentReads + 1 return items or {} end
    value.objects[#value.objects + 1] = owner
    return container
end
local actor = { id = "sc-store-search", square = square(138, 101, 0), inventory = {} }
local protected = { type = "Base.PersonalTool", category = "tools", score = 1000, protected = true }
local junk = { type = "Base.Junk", category = "general", score = 0 }
local wanted = { type = "Base.CannedFood", category = "food", score = 320 }
local farSquare = square(101, 119, 1)
local farSource = source(farSquare, { protected, junk, wanted })
source(square(130, 101, 0, true))
local runtime = { snapshot = { immediateCount = 0, pressure = 0 } }
local scan
for round = 1, 400 do
    probes = 0
    SC.Encounter.tryScavenge(actor, nil, runtime)
    assert(probes <= 5, "a selected-store search respects each frame's square quota")
    local state = SC.Encounter.peek(actor)
    scan = scan or state.containerSearch
    if round == 30 then actor.square = square(130, 110, 1) end
    if state.task then break end
    assert(failures == 0, "a partial empty store scan must not surrender this worker's turn")
    clock = clock + 1000
end
local state = SC.Encounter.peek(actor)
assert(state.task and state.task.container == farSource and state.task.pendingItem
        and moves > 0 and contentReads == 0,
    "the far upstairs shelf is discovered, selected blindly and physically approached")
assert(state.containerSearch == scan, "walking across the store retains the discovery cursor")
local farTask = state.task
local approachStart = farTask.approachStartedAt
assert(not SC.Encounter._approachExpired(farTask, approachStart + 26000, 1,
        { expandedNodes = 100 }, actor)
        and not SC.Encounter._approachExpired(farTask, approachStart + 45000, 1,
            { expandedNodes = 200 }, actor)
        and SC.Encounter._approachExpired(farTask, approachStart + 45001, 1,
            { expandedNodes = 232 }, actor),
    "a distant store route keeps its full 45-second allowance when it nears the shelf")
actor.square = farSquare
SC.Encounter.tryScavenge(actor, nil, runtime)
clock = clock + 1000
SC.Encounter.tryScavenge(actor, nil, runtime)
assert(contentReads > 0 and state.task and state.task.item == wanted
        and #actor.inventory == 0,
    "only physical arrival opens the shelf; personal property and useless junk stay untouched")

-- A nearby shelf can be selected before the far end of a large footprint has
-- been scanned. It must not wait for a complete inventory or building scan.
SC.Encounter.reset()
cells, contentReads, failures = {}, 0, 0
actor.square = square(138, 101, 0)
source(square(139, 101, 0))
SC.Encounter.tryScavenge(actor, nil, runtime)
state = SC.Encounter.peek(actor)
assert(state.task and state.containerSearch and state.containerSearch.index < state.containerSearch.total
        and contentReads == 0, "a discovered shelf begins approach before the footprint scan completes")
approachStart = state.task.approachStartedAt
assert(SC.Encounter._approachExpired(state.task, approachStart + 25001, 1,
        { expandedNodes = 100 }, actor),
    "nearby same-floor expedition sources retain the existing 25-second total cap")

SC.Encounter.reset()
cells, contentReads = {}, 0
actor.square = square(138, 101, 0)
source(square(139, 101, 1))
for _ = 1, 5 do
    SC.Encounter.tryScavenge(actor, nil, runtime)
    if SC.Encounter.peek(actor).task then break end
end
state = SC.Encounter.peek(actor)
assert(state.task, "the nearby upstairs fixture selects a loaded shelf")
approachStart = state.task.approachStartedAt
assert(not SC.Encounter._approachExpired(state.task, approachStart + 26000, 2,
        { expandedNodes = 100 }, actor),
    "a nearby shelf on another floor gets time to reach and cross the stairs")
assert(SC.Encounter._approachExpired(state.task, approachStart + 38001, 2,
        { expandedNodes = 100 }, actor),
    "an extended route still fails after twelve seconds without meaningful progress")

SC.Encounter.reset()
cells, failures = {}, 0
for _ = 1, 400 do
    SC.Encounter.tryScavenge(actor, nil, runtime)
    if failures > 0 then break end
    assert(SC.Encounter.peek(actor).containerSearch ~= nil,
        "worker exhaustion is not reported before the complete selected footprint")
end
assert(failures == 1 and SC.Encounter.peek(actor).containerSearch == nil,
    "a fully exhausted store search yields its worker turn once")
print("EXPEDITION_CONTAINER_SEARCH_PASS")
