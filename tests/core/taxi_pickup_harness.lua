-- SPDX-License-Identifier: MIT
-- Drive actual booking/service dispatch through loaded overlapping Nav zones.
local SC = SurvivorCompanion
local Service, Booking = SC.TaxiService, SC.TaxiBooking
local function check(value, label)
    if not value then error("taxi pickup: " .. label) end
end
local function list(values)
    return { size = function() return #values end,
        get = function(_, index) return values[index + 1] end }
end
local clock, roads, overlays, options, owned, car
local workClock = 0
local spawned, drivers, rebound, routes, queries, squares, descriptors, lookups
local maxSquares, maxRoutes, maxDescriptors
local caller = { x = 100, y = 100, z = 0 }
local inventory, radio = {}, {}
function caller:getInventory() return inventory end
function caller:getVehicle() return nil end
function radio:getContainer() return inventory end
function radio:getDeviceData()
    return { getIsPortable = function() return true end,
        getIsTwoWay = function() return true end,
        getTransmitRange = function() return 100 end,
        getIsTurnedOn = function() return true end,
        getHasBattery = function() return true end,
        getPower = function() return 1 end }
end
function getSpecificPlayer(index) return index == 0 and caller or nil end
IsoDirections = { E = "E", W = "W", N = "N", S = "S" }
Vector3f = { new = function() return {} end }
isoToScreenX = function(_, x) return (x - caller.x) * 10 end
isoToScreenY = function(_, _, y) return (y - caller.y) * 10 end
getPlayerScreenLeft = function() return options.visible and -5000 or -450 end
getPlayerScreenTop = function() return options.visible and -5000 or -450 end
getPlayerScreenWidth = function() return options.visible and 10000 or 900 end
getPlayerScreenHeight = function() return options.visible and 10000 or 900 end

local function zone(x, y, w, h, kind, contains)
    return { getX = function() descriptors = descriptors + 1 return x end,
        getY = function() return y end,
        getWidth = function() return w end, getHeight = function() return h end,
        getType = function() return kind or "Nav" end,
        isRectangle = function() return contains == nil end,
        contains = function(_, tx, ty, z)
            if z ~= 0 then return false end
            if contains then return contains(tx, ty) end
            return tx >= x and tx < x + w and ty >= y and ty < y + h
        end }
end
local parking = zone(98, 98, 4, 5, "ParkingStall")
local meta = {}
function meta:getZonesIntersecting()
    queries = queries + 1
    local result = {}
    for _, value in ipairs(overlays) do result[#result + 1] = value end
    for _, value in ipairs(roads) do result[#result + 1] = value end
    return list(result)
end
function meta:getZonesAt(x, y, z)
    lookups = lookups + 1
    local result = { parking }
    for _, value in ipairs(roads) do
        if value:contains(x, y, z) then result[#result + 1] = value end
    end
    return list(result)
end
getWorld = function() return { getMetaGrid = function() return meta end } end
local function square(x, y, z)
    squares = squares + 1
    if options.unloaded and math.abs(x - caller.x) > 30 then return nil end
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end,
        getZone = function() return parking end,
        isOutside = function() return true end, getRoom = function() return nil end,
        isSolid = function()
            return options.blocked == true or options.blockAt ~= nil
                and x == math.floor(options.blockAt.x) and y == math.floor(options.blockAt.y)
        end,
        isSolidTrans = function() return false end,
        getMovingObjects = function()
            return list(x == math.floor(caller.x) and y == math.floor(caller.y)
                and { caller } or {})
        end }
end
SC.GameplayUtil = {
    call = function(object, method, ...)
        local fn = object and object[method]
        if type(fn) ~= "function" then return nil, false end
        return fn(object, ...), true
    end,
    position = function(value) return value.x, value.y, value.z end,
    nowMs = function()
        if options.slowClock then workClock = workClock + 1 end
        return clock + workClock
    end,
    gridSquare = square, squareStaticBlocker = function() return false end,
    isClearActorSpawnSquare = function() return true end,
    instanceOf = function(value, kind) return value == radio and kind == "Radio" end,
    containerContainsIdentity = function(container, value)
        return container == inventory and value == radio
    end,
}
SC.Driving = { passengerAvailable = function() return true end }
SC.Vehicle = {}
SC.Registry = { snapshot = function() return {} end }
SC.Actor = { beginSpawn = function()
    drivers = drivers + 1
    return {}
end }
SC.TaxiFares = { reserve = function() error("pickup cannot charge a fare") end }
SC.TaxiCab = {
    current = function() return owned end,
    recover = function() return car ~= nil, car or "cab_unloaded_or_missing" end,
    prepareSpawn = function(generation)
        check(not owned and generation == Booking.current().generation,
            "only one native allocation per booking")
        owned = { ownershipToken = "markus:pickup", generation = generation }
        return true, owned.ownershipToken
    end,
    claimSpawn = function(vehicle, token)
        check(vehicle == car and token == owned.ownershipToken, "claim exact cab")
        owned.sqlId = 771
        return true
    end,
    applyAppearance = function() return true end,
    beginVisit = function(vehicle, generation)
        check(vehicle == car and generation == Booking.current().generation,
            "reuse the actual owned taxi")
        rebound = rebound + 1
        return true
    end,
}
local function makeCar(x, y)
    local fuel, battery = 0, {}
    function battery:setCurrentUsesFloat() end
    local tank = { getContainerCapacity = function() return 40 end,
        setContainerContentAmount = function(_, amount) fuel = amount end,
        getContainerContentAmount = function() return fuel end }
    return { x = x, y = y, z = 0,
        getSqlId = function() return 771 end,
        getSquare = function() return square(x, y, 0) end,
        getPartById = function() return tank end,
        getBattery = function()
            return { getInventoryItem = function() return battery end }
        end,
        getPassengerPosition = function() return {} end,
        getPassengerPositionWorldPos = function()
            return { x = function() return x end, y = function() return y + 2 end }
        end,
        getEnterSeatDistance = function() return 1 end }
end
addVehicleDebug = function(kind, facing, _, tile)
    check(kind == "Base.CarTaxi" and facing ~= nil, "physical taxi spawn")
    spawned = spawned + 1
    car = makeCar(tile:getX(), tile:getY())
    return car
end
SC.ExpeditionRoute = { planFromPoint = function(from, target)
    routes = routes + 1
    if options.disconnected then return nil, "NO_ROUTE" end
    local points = { { x = from.x, y = from.y } }
    -- A real road turn, rather than a straight chord through the nearby lawn.
    if from.x ~= target.x and from.y ~= target.y then
        points[#points + 1] = { x = from.x, y = target.y }
    end
    points[#points + 1] = { x = target.x, y = target.y }
    local length = math.abs(from.x - target.x) + math.abs(from.y - target.y)
    local entryX = from.x
    if options.ghostConnector then
        local direction = target.x >= from.x and 1 or -1
        options.blockAt = { x = from.x + direction * 5, y = from.y }
        entryX = from.x + direction * 10
        points = { { x = entryX, y = from.y }, { x = target.x, y = target.y } }
    end
    return { points = points, roadLength = length }, nil,
        { entryX = entryX, entryY = from.y, exitX = target.x, exitY = target.y }
end }

local function start(newRoads, settings)
    Service.reset()
    Booking.reset()
    roads, options, overlays = newRoads, settings or {}, { parking }
    owned, car = nil, nil
    clock, spawned, drivers, rebound = 1000, 0, 0, 0
    routes, queries, squares, descriptors, lookups = 0, 0, 0, 0, 0
    maxSquares, maxRoutes, maxDescriptors = 0, 0, 0
    caller.x, caller.y = 100, 100
    check(Service.request(caller, radio), "accept a working roadside handset")
end
local function pulse()
    workClock = 0
    local beforeSquares, beforeRoutes, beforeDescriptors = squares, routes, descriptors
    check(Service.tick(clock), "controlled dispatch pulse")
    maxSquares = math.max(maxSquares, squares - beforeSquares)
    maxRoutes = math.max(maxRoutes, routes - beforeRoutes)
    maxDescriptors = math.max(maxDescriptors, descriptors - beforeDescriptors)
    check(maxSquares <= 150 and maxRoutes <= 1 and maxDescriptors <= 8,
        "one update bounds physical scans, native routing and zone metadata")
    clock = clock + 250
end
local function finishSearch(limit)
    for _ = 1, limit or 250 do
        pulse()
        local state = Service.current()
        if state.phase ~= "searching" or state.reason then return state end
    end
    error("taxi pickup: finite candidate pass did not complete")
end

-- Three arms join a short intersection rectangle. Parking overlays hide Nav
-- in getZone(), and every old same-segment 44-tile spawn remains on screen.
start({ zone(80, 96, 40, 8), zone(32, 96, 48, 8),
    zone(120, 96, 48, 8), zone(96, 32, 8, 64) })
for _ = 1, 300 do overlays[#overlays + 1] = parking end
pulse()
check(spawned == 0 and routes == 0, "metadata discovery yields before native effects")
local generation = Booking.current().generation
check(select(2, Service.request(caller, radio)) == "already_booked"
    and select(2, Service.status(caller, radio)) == "searching"
    and Booking.current().generation == generation, "radio polling preserves partial search")
local found = finishSearch()
check(found.phase == "driver_pending" and spawned == 1 and drivers == 1,
    "overlapped three-way junction dispatches one cab and Markus: "
        .. tostring(found.phase) .. ":" .. tostring(found.reason) .. " routes=" .. routes)
check(math.sqrt((car.x - found.pickup.x)^2 + (car.y - found.pickup.y)^2) > 44
    and queries == 1, "offscreen arrival can use a connected farther road arm")
check(Booking.current().generation == generation and Booking.export().nextGeneration == 2,
    "search slices keep the accepted booking and fare idempotent")

start({ zone(4, 126, 192, 8) })
found = finishSearch()
check(found.phase == "driver_pending" and found.pickup.y == 130
    and math.abs(found.pickup.x - caller.x) <= 12,
    "paved driveway can reach the real loaded road thirty tiles away")

for _, failure in ipairs({ "visible", "unloaded", "blocked", "disconnected" }) do
    start({ zone(4, 96, 192, 8) }, { [failure] = true })
    local failed = finishSearch(600)
    check(failed.phase == "searching" and failed.reason
        and string.find(failed.reason, "no_safe_loaded_road", 1, true)
        and spawned == 0 and drivers == 0 and owned == nil,
        failure .. " road never materializes an unsafe taxi")
    local previousQueries, previousRoutes, previousSquares = queries, routes, squares
    pulse()
    check(queries == previousQueries and routes == previousRoutes
        and squares == previousSquares, "completed failure waits before bounded retry")
end

start({ zone(4, 96, 192, 8, "Nav", function() return false end) })
found = finishSearch()
check(found.phase == "searching" and spawned == 0 and routes == 0,
    "polygon bounding box cannot turn clear grass into a road")

start({ zone(4, 96, 192, 8) }, { ghostConnector = true })
found = finishSearch(600)
check(found.phase == "searching" and spawned == 0 and routes > 0 and owned == nil,
    "road projection cannot skip a blocked ten-tile source access connector")

-- Stress the candidate phase as well as native metadata extraction. Hooks
-- count local anchor work without exporting internal search state to gameplay.
local dense = {}
for index = 0, 1023 do
    dense[#dense + 1] = zone(20 + index % 32, 80 + math.floor(index / 32), 120, 8)
end
start(dense, { visible = true, slowClock = true })
overlays = {}
local sqrt, insert, sort = math.sqrt, table.insert, table.sort
local anchorWork, insertWork, totalAnchorWork = 0, 0, 0
math.sqrt = function(value)
    anchorWork, totalAnchorWork = anchorWork + 1, totalAnchorWork + 1
    return sqrt(value)
end
table.insert = function(...)
    insertWork = insertWork + 1
    return insert(...)
end
table.sort = function(values, ...)
    check(#values <= 12, "dense candidate discovery never performs a global sort")
    return sort(values, ...)
end
for _ = 1, 800 do
    anchorWork, insertWork = 0, 0
    pulse()
    check(anchorWork <= 88 and insertWork <= 40,
        "dense Nav anchors yield within eight zones and twelve retained stops")
end
math.sqrt, table.insert, table.sort = sqrt, insert, sort
check(descriptors == 1024 and totalAnchorWork > 0 and queries == 1
    and spawned == 0 and drivers == 0,
    "slow-clock dense search progresses without restarting discovery or native effects")

start({ zone(4, 96, 192, 8) }, { visible = true })
owned, car = { ownershipToken = "existing", sqlId = 771 }, makeCar(70, 100)
found = finishSearch()
check(found.phase == "driver_pending" and rebound == 1 and spawned == 0
    and drivers == 1 and car.x == 70 and car.y == 100,
    "existing cab drives from its real position without an imaginary offscreen spawn")

print("taxi pickup harness passed")
