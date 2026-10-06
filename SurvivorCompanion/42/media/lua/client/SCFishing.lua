-- SPDX-License-Identifier: MIT
-- One fishing controller for camp duty and expedition searches. Movement stays
-- with Navigation; the game owns fish generation, abundance, bait and visuals.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Fishing = SC.Fishing or {}
local Angling = SC.Fishing

local states = setmetatable({}, { __mode = "k" })
local engineRetryAt = setmetatable({}, { __mode = "k" })
local lastPartyFishingLineAt = -math.huge
local SEARCH_RADIUS = 24
local SCAN_BUDGET = 180
local CAST_DELAY = 1100
local PICKUP_DELAY = 2200
local ENGINE_RETRY_DELAY = 60000
local CAMP_CATCH_TAG = "SC_CampFishingCatch"
local CAMP_DELIVERY_COUNT = 3
local CAMP_DELIVERY_LOAD_RATIO = 0.70
local BANK_GROUP_SIZE = 12
-- worldmap.xml cells are 256 squares, unlike terrain map cells.
local MAP_CELL_SIZE = 256
local MAP_EDGE_STEP = 10
local BANK_DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- One shoreline scan serves every page of the expedition picker.
local BANK_LIST_CACHE_MS = 30000
local MAX_BANK_RADIUS = 1000
local LOADED_BANK_SCAN_RADIUS = 200
local bankListCache

local function U() return SC.GameplayUtil end
local function now() return U().nowMs() end
local function water(square)
    return square and SC.Topology and SC.Topology.squareIsWater(square) == true
end

local function point(square)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

local function usableBank(square)
    if not square or square:getZ() ~= 0 or water(square)
        or not U().isSquareFree(square) then return nil end
    local x, y = square:getX(), square:getY()
    for _, direction in ipairs(BANK_DIRECTIONS) do
        local dx, dy = direction[1], direction[2]
        local first = U().loadedSquare({ x = x + dx, y = y + dy, z = 0 })
        local second = U().loadedSquare({ x = x + 2 * dx,
            y = y + 2 * dy, z = 0 })
        if water(first) and water(second) then
            local castX, castY = x + 2 * dx + 0.5, y + 2 * dy + 0.5
            if not (Fishing and Fishing.isNoFishZone
                and Fishing.isNoFishZone(castX, castY)) then
                return { bank = point(square), water = { x = castX,
                    y = castY, z = 0 }, dx = dx, dy = dy }
            end
        end
    end
    return nil
end

-- A loaded shore is confirmed by game squares. Mapped shores farther away
-- are labelled possible until a companion arrives and checks the real bank.
local function bankRow(site, originX, originY)
    local bank = site.bank
    local distance = math.floor(math.sqrt((bank.x - originX)^2
        + (bank.y - originY)^2) + 0.5)
    return { id = "bank:" .. bank.x .. ":" .. bank.y,
        anchor = bank, kind = "fishing_bank",
        label = "Fishing bank " .. bank.x .. ", " .. bank.y,
        distance = distance, distanceSq = (bank.x - originX)^2
            + (bank.y - originY)^2,
        knowledge = "loaded_water_confirmed" }
end

-- The minimap has the world's map features even where game squares are not
-- loaded. Its water polygons give us possible shores for a remote mission;
-- the arrival scan still has to find a real, free bank before anyone casts.
local function mapWorld()
    local mini = type(getPlayerMiniMap) == "function"
        and getPlayerMiniMap(0) or nil
    local javaMap = mini and mini.inner and mini.inner.javaObject
    -- UIWorldMap.getWorldMap exists in Java but is not exposed to stock Lua.
    -- The narrow bridge returns it only after its feature data is loaded.
    if not javaMap or not SCBridge or not SCBridge.loadedWorldMap then
        return nil
    end
    return SCBridge.loadedWorldMap(javaMap)
end

local function mapWaterFeatures(world, cx, cy, cache)
    local key = cx .. ":" .. cy
    if cache[key] then return cache[key] end
    local result = {}
    local cell = world:getCell(cx, cy)
    if cell then
        local features = cell.features
        for i = 0, features:size() - 1 do
            local feature = features:get(i)
            if feature:hasPolygon() and feature.properties:get("water") then
                result[#result + 1] = feature
            end
        end
    end
    cache[key] = result
    return result
end

local function mapWaterAt(world, x, y, cache)
    local cx, cy = math.floor(x / MAP_CELL_SIZE),
        math.floor(y / MAP_CELL_SIZE)
    for _, feature in ipairs(mapWaterFeatures(world, cx, cy, cache)) do
        if feature:containsPoint(x - cx * MAP_CELL_SIZE,
            y - cy * MAP_CELL_SIZE) then return true end
    end
    return false
end

local function mapBankRow(x, y, originX, originY)
    local dx, dy = x - originX, y - originY
    return { id = "bank:" .. x .. ":" .. y,
        anchor = { x = x, y = y, z = 0 }, kind = "fishing_bank",
        label = "Possible fishing shore " .. x .. ", " .. y,
        distance = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5),
        distanceSq = dx * dx + dy * dy,
        knowledge = "map_water_unconfirmed" }
end

local function mapBankIsPlausible(world, x, y, cache)
    cache = cache or {}
    if mapWaterAt(world, x + 0.5, y + 0.5, cache) then return false end
    for _, direction in ipairs(BANK_DIRECTIONS) do
        local dx, dy = direction[1], direction[2]
        if mapWaterAt(world, x + dx * 6 + 0.5, y + dy * 6 + 0.5, cache)
            and mapWaterAt(world, x + dx * 9 + 0.5,
                y + dy * 9 + 0.5, cache) then return true end
    end
    return false
end

local function addMapBanks(world, ox, oy, radius, groups)
    local cache = {}
    local minCX = math.floor(math.max(0, ox - radius) / MAP_CELL_SIZE)
    local maxCX = math.floor((ox + radius) / MAP_CELL_SIZE)
    local minCY = math.floor(math.max(0, oy - radius) / MAP_CELL_SIZE)
    local maxCY = math.floor((oy + radius) / MAP_CELL_SIZE)
    for cx = minCX, maxCX do
        for cy = minCY, maxCY do
            local features = mapWaterFeatures(world, cx, cy, cache)
            for _, feature in ipairs(features) do
                local rings = feature.geometry.points
                for ri = 0, rings:size() - 1 do
                    local ring = rings:get(ri)
                    local count = ring:numPoints()
                    for pi = 0, count - 1 do
                        local nextIndex = (pi + 1) % count
                        local ax, ay = ring:getX(pi), ring:getY(pi)
                        local bx, by = ring:getX(nextIndex),
                            ring:getY(nextIndex)
                        local ex, ey = bx - ax, by - ay
                        local length = math.sqrt(ex * ex + ey * ey)
                        if length > 0 then
                            local nx, ny = -ey / length, ex / length
                            local steps = math.ceil(length / MAP_EDGE_STEP)
                            for step = 0, steps - 1 do
                                local t = (step + 0.5) / steps
                                local px = cx * MAP_CELL_SIZE + ax + ex * t
                                local py = cy * MAP_CELL_SIZE + ay + ey * t
                                for side = -1, 1, 2 do
                                    local x = math.floor(px + nx * side * 4)
                                    local y = math.floor(py + ny * side * 4)
                                    local distSq = (x - ox)^2 + (y - oy)^2
                                    if x >= 0 and y >= 0 and distSq >= 64
                                        and distSq <= radius * radius
                                        and mapBankIsPlausible(world, x, y, cache) then
                                        local row = mapBankRow(x, y, ox, oy)
                                        local key = math.floor(x / BANK_GROUP_SIZE)
                                            .. ":" .. math.floor(y / BANK_GROUP_SIZE)
                                        local old = groups[key]
                                        if not old or (old.knowledge ~= "loaded_water_confirmed"
                                            and row.distanceSq < old.distanceSq) then
                                            groups[key] = row
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Angling.bankById(actor, id, radius)
    local sx, sy
    if type(id) == "string" then
        sx, sy = id:match("^bank:(%d+):(%d+)$")
    end
    local x, y = tonumber(sx), tonumber(sy)
    local ox, oy
    if actor then ox, oy = U().position(actor) end
    radius = tonumber(radius)
    if not x or not y or not ox or not oy or not radius
        or radius < 1 or radius > MAX_BANK_RADIUS or x > 30000 or y > 30000
        or (x - ox)^2 + (y - oy)^2 > radius * radius then
        return nil, "fishing_bank_out_of_range"
    end
    local loaded = U().loadedSquare({ x = x, y = y, z = 0 })
    if loaded then
        local site = usableBank(loaded)
        if not site then return nil, "fishing_bank_unavailable" end
        return bankRow(site, ox, oy)
    end
    local ok, plausible = pcall(function()
        local world = mapWorld()
        return world and mapBankIsPlausible(world, x, y)
    end)
    if ok and plausible then return mapBankRow(x, y, ox, oy) end
    return nil, "fishing_bank_unavailable"
end

function Angling.bankCandidates(actor, radius, limit, offset, refresh)
    local ox, oy
    if actor then ox, oy = U().position(actor) end
    radius, limit, offset = tonumber(radius), tonumber(limit), tonumber(offset) or 0
    if not ox or not oy or not radius or radius < 1 or radius > MAX_BANK_RADIUS
        or radius ~= math.floor(radius) or not limit or limit < 1
        or limit > 32 or limit ~= math.floor(limit) or offset < 0
        or offset > 4096 or offset ~= math.floor(offset) then
        return nil, "invalid_fishing_bank_query"
    end
    ox, oy = math.floor(ox), math.floor(oy)
    -- Loaded squares are only useful near the active player stream. Scan at
    -- most 200 tiles here; mapped water supplies the distant candidates.
    -- Paging reuses one scan and the picker's Refresh rescans.
    local cached = bankListCache
    if refresh ~= true and cached and cached.x == ox and cached.y == oy
        and cached.radius == radius and now() - cached.at < BANK_LIST_CACHE_MS then
        local page = {}
        for index = offset + 1, math.min(#cached.rows, offset + limit) do
            page[#page + 1] = cached.rows[index]
        end
        return page, nil, #cached.rows
    end
    local cell = type(getCell) == "function" and getCell() or nil
    local function squareAt(x, y)
        if cell then return cell:getGridSquare(x, y, 0) end
        return U().loadedSquare({ x = x, y = y, z = 0 })
    end
    local groups, rows = {}, {}
    local loadedRadius = math.min(radius, LOADED_BANK_SCAN_RADIUS)
    for x = math.max(0, ox - loadedRadius), ox + loadedRadius do
        for y = math.max(0, oy - loadedRadius), oy + loadedRadius do
            if (x - ox)^2 + (y - oy)^2 <= radius * radius
                and water(squareAt(x, y)) then
                for _, direction in ipairs(BANK_DIRECTIONS) do
                    local bank = squareAt(x - direction[1],
                        y - direction[2])
                    local site = usableBank(bank)
                    if site then
                        local row = bankRow(site, ox, oy)
                        if row.distance >= 8 and row.distance <= radius then
                            local key = math.floor(site.bank.x / BANK_GROUP_SIZE)
                                .. ":" .. math.floor(site.bank.y / BANK_GROUP_SIZE)
                            local old = groups[key]
                            if not old or row.distanceSq < old.distanceSq then
                                groups[key] = row
                            end
                        end
                    end
                end
            end
        end
    end
    local ok, err = pcall(function()
        local world = mapWorld()
        if world then addMapBanks(world, ox, oy, radius, groups) end
    end)
    if not ok and SC.Diagnostics and SC.Diagnostics.report then
        SC.Diagnostics.report("fishing-map", nil,
            "mapped shore lookup failed", err)
    end
    for _, row in pairs(groups) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if a.distanceSq ~= b.distanceSq then return a.distanceSq < b.distanceSq end
        return a.id < b.id
    end)
    bankListCache = { x = ox, y = oy, radius = radius, at = now(), rows = rows }
    local result = {}
    for index = offset + 1, math.min(#rows, offset + limit) do
        result[#result + 1] = rows[index]
    end
    return result, nil, #rows
end

local function reserved(actor, site)
    for other, state in pairs(states) do
        if other ~= actor and state.site and state.phase ~= "failed"
            and state.site.bank.x == site.bank.x
            and state.site.bank.y == site.bank.y then return true end
    end
    return false
end

local function eligibleSite(site, rect)
    if not site or not rect.catchRadius then return site ~= nil end
    local dx = site.water.x - rect.catchX
    local dy = site.water.y - rect.catchY
    return dx * dx + dy * dy <= rect.catchRadius * rect.catchRadius
end

local function scanRects(actor, state, rects)
    local count = 0
    while state.scanRectIndex <= #rects and count < SCAN_BUDGET do
        local rect = rects[state.scanRectIndex]
        local width = rect.x2 - rect.x1 + 1
        local total = width * (rect.y2 - rect.y1 + 1)
        while state.scanIndex < total and count < SCAN_BUDGET do
            local index = state.scanIndex
            state.scanIndex = index + 1
            count = count + 1
            local x = rect.x1 + index % width
            local y = rect.y1 + math.floor(index / width)
            local square = U().loadedSquare({ x = x, y = y, z = 0 })
            local site = usableBank(square)
            if eligibleSite(site, rect) and not reserved(actor, site)
                and (not U().movingBlocker
                    or U().movingBlocker(square, actor) == nil) then
                local score = U().distanceSq(actor, site.bank)
                if not state.bestScore or score < state.bestScore then
                    state.bestCandidate, state.bestScore = site, score
                end
            end
        end
        if state.scanIndex >= total then
            state.scanRectIndex, state.scanIndex = state.scanRectIndex + 1, 0
        end
    end
    if state.scanRectIndex > #rects then
        if state.bestCandidate and reserved(actor, state.bestCandidate) then
            state.scanRectIndex, state.scanIndex = 1, 0
            state.bestCandidate, state.bestScore = nil, nil
            state.nextScanAt = now() + 5000
            return nil, "waiting_for_bank"
        end
        state.site = state.bestCandidate
        return state.site, state.site and "bank_found" or "no_fishing_water"
    end
    return nil, "scanning_water"
end

local function campRects()
    local base = SC.BaseLife and SC.BaseLife.active()
    if not base then return nil end
    local rects = {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "fishing" and zone.z == 0 then
            rects[#rects + 1] = zone
        end
    end
    return #rects > 0 and rects or nil
end

local function siteFor(actor, state, mode, request)
    if state.site then return state.site, "bank_found" end
    if state.nextScanAt and now() < state.nextScanAt then
        return nil, "waiting_for_bank"
    end
    state.nextScanAt = nil
    local rects
    if mode == "camp" then
        rects = campRects()
        if not rects then return nil, "fishing_zone_missing" end
    else
        local destination = request and request.destination
        if not destination then return nil, "fishing_destination_missing" end
        local x, y = math.floor(destination.x), math.floor(destination.y)
        rects = { { x1 = math.max(0, x - SEARCH_RADIUS),
            y1 = math.max(0, y - SEARCH_RADIUS),
            x2 = x + SEARCH_RADIUS, y2 = y + SEARCH_RADIUS,
            catchX = destination.x, catchY = destination.y,
            catchRadius = tonumber(request.catchRadius) or 27 } }
    end
    local signatureParts = { mode }
    for _, rect in ipairs(rects) do
        signatureParts[#signatureParts + 1] = table.concat({ rect.x1, rect.y1,
            rect.x2, rect.y2, rect.catchX or "", rect.catchY or "",
            rect.catchRadius or "" }, ":")
    end
    local signature = table.concat(signatureParts, "|")
    if state.scanSignature ~= signature then
        state.scanSignature, state.scanRectIndex, state.scanIndex = signature, 1, 0
        state.bestCandidate, state.bestScore = nil, nil
    end
    return scanRects(actor, state, rects)
end

local function gear(actor, state)
    local audit = SC.Logistics and SC.Logistics.audit(actor)
    local rod, lure
    local equipped = actor:getPrimaryHandItem()
    local inventory = actor:getInventory()
    if state and state.rod and (equipped == state.rod
        or U().inventoryContains(inventory, state.rod)) then
        rod = state.rod
        if rod:getModData().fishing_Lure then return rod, nil end
    end
    if equipped and U().itemHasTag(equipped, "FISHING_ROD") then
        rod = equipped
        if equipped:getModData().fishing_Lure then return equipped, nil end
    end
    for _, entry in ipairs(audit and audit.items or {}) do
        local item = entry.item
        if item and U().itemHasTag(item, "FISHING_ROD") then
            if item:getModData().fishing_Lure then return item, nil end
            rod = rod or item
        elseif item and Fishing and Fishing.lure and Fishing.lure.All
            and Fishing.lure.All[U().itemType(item)] then
            lure = lure or item
        end
    end
    return rod, lure
end

function Angling.checkGear(actor)
    if not actor then return false, "fishing_rod_missing" end
    local rod, lure = gear(actor)
    if not rod then return false, "fishing_rod_missing" end
    if not rod:getModData().fishing_Lure and not lure then
        return false, "fishing_bait_missing"
    end
    return true
end

local function cancelBaitAction(actor, state)
    local action, queue = state.baitAction, state.baitQueue
    state.baitAction, state.baitQueue = nil, nil
    if not action or not queue then return end
    local queued = queue.current == action
    if not queued and type(queue.indexOf) == "function" then
        local ok, index = pcall(queue.indexOf, queue, action)
        queued = ok and index ~= -1
    end
    if not queued then return end
    if action.action then
        if type(actor.cancelCompanionPendingAction) == "function" then
            pcall(actor.cancelCompanionPendingAction, actor, action.action)
        end
        pcall(action.forceStop, action)
    elseif type(action.forceCancel) == "function" then
        pcall(action.forceCancel, action)
    end
    if type(queue.removeFromQueue) == "function" then
        pcall(queue.removeFromQueue, queue, action)
    end
    if queue.current == action then queue.current = nil end
end

function Angling.cancel(actor, reason)
    local state = states[actor]
    if not state then return false end
    cancelBaitAction(actor, state)
    if state.visualAt ~= nil and SC.NativeActions
        and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "fishing_cancelled")
    end
    if state.delivering and SC.Navigation
        and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, reason or "fishing_cancelled")
    end
    if state.bobber then pcall(state.bobber.destroy, state.bobber) end
    if state.rodSim and state.rodSim.resetItemModel then
        pcall(state.rodSim.resetItemModel, state.rodSim)
    end
    pcall(function()
        actor:setFishingStage("None")
        actor:setVariable("FishingFinished", true)
        if state.rod and actor:getPrimaryHandItem() == state.rod then
            actor:setPrimaryHandItem(state.previousHand)
        end
    end)
    states[actor] = nil
    return true, reason or "fishing_cancelled"
end

local function failFishing(actor, mode, reason, retry)
    if retry then
        engineRetryAt[actor] = now() + ENGINE_RETRY_DELAY
    end
    Angling.cancel(actor, reason)
    if mode == "expedition" and SC.ExpeditionPrototype
        and type(SC.ExpeditionPrototype.fishingUnable) == "function" then
        SC.ExpeditionPrototype.fishingUnable(actor, reason)
    end
    return false, reason
end

local function missingGearFailure(actor, mode, reason, player, snapshot)
    local failed, explanation = failFishing(actor, mode, reason)
    if not player or not SC.Dialogue
        or type(SC.Dialogue.missingToolKind) ~= "function"
        or type(SC.Dialogue.requestMissingTool) ~= "function" then
        return failed, explanation
    end
    local kind = SC.Dialogue.missingToolKind(reason)
    if kind then
        SC.Dialogue.requestMissingTool(actor, player, kind, snapshot, nil,
            function()
                local rod, lure = gear(actor)
                if kind == "rod" then return rod == nil end
                local data = rod and select(1, U().call(rod, "getModData"))
                return rod ~= nil and not (data and data.fishing_Lure)
                    and lure == nil
            end)
    end
    return failed, explanation
end

function Angling.active(actor) return states[actor] ~= nil end
function Angling._stateForTests(actor) return states[actor] end

local function speak(actor, topic, chance, gap)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    local current = now()
    local last = type(SC.Dialogue.lastSpokenAt) == "function"
        and SC.Dialogue.lastSpokenAt(actor) or -math.huge
    if current - last < (gap or 10000) then return false end
    if current - lastPartyFishingLineAt < 6000 then return false end
    if type(ZombRand) == "function" and ZombRand(100) >= (chance or 100) then
        return false
    end
    local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, nil,
        { recentLimit = 5, salt = tostring(current) })
    if ok and spoken == true then lastPartyFishingLineAt = current end
    return ok and spoken == true
end

local function handleBite(actor, state)
    local fish = state.bobber and state.bobber.fish
    if not fish or not fish.fishItem then return false end
    state.isTrash = fish.isTrash == true
    -- A hooked fish can still throw the line. Use the rod's native miss path
    -- so the lost-bite line corresponds to a real failed catch and lost bait.
    local level = select(1, U().call(actor, "getPerkLevel",
        Perks and Perks.Fishing))
    if type(level) ~= "number" then level = 0 end
    local missChance = math.max(4, 12 - level)
    if not state.isTrash and type(ZombRand) == "function"
        and ZombRand(100) < missChance then
        if state.rodSim then
            state.rodSim.bobber = state.bobber
            pcall(state.rodSim.missFish, state.rodSim)
            state.rodSim.bobber = nil
        end
        pcall(state.bobber.destroy, state.bobber)
        state.bobber, state.catch = nil, nil
        state.phase, state.phaseAt = "ready", now()
        pcall(actor.setVariable, actor, "FishingFinished", true)
        speak(actor, "fishing.lost", 100, 6000)
        return true
    end
    state.catch = fish.fishItem
    state.phase, state.phaseAt = "pickup", now()
    state.bobber.catchFishStarted = true
    pcall(actor.setFishingStage, actor,
        state.isTrash and "PickUpTrash" or "PickUp")
    if not state.isTrash then speak(actor, "fishing.bite", 45, 10000) end
    return true
end

Angling._handleBiteForTests = handleBite

-- Bobber:update is the actual Build 42 fish-school/weather/skill simulation.
-- Its tick cadence is deliberately independent of the 250 ms decision cadence.
function Angling.onTick()
    for actor, state in pairs(states) do
        if state.bobber and state.phase == "waiting" then
            local ok = pcall(state.bobber.update, state.bobber)
            if not ok then
                failFishing(actor, state.mode, "fishing_engine_failed", true)
            elseif state.bobber.fish and state.bobber.fish.fishItem then
                handleBite(actor, state)
            end
        end
    end
end

local function faceWater(actor, site)
    if Fishing and Fishing.Utils and Fishing.Utils.FacePlayerToBobber then
        pcall(Fishing.Utils.FacePlayerToBobber, actor,
            site.water.x, site.water.y)
    end
end

local function campCatches(actor, state, refresh)
    if refresh or state.campCatchItems == nil
        or now() >= (state.nextCatchScanAt or 0) then
        local items = {}
        local inventory = actor:getInventory()
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 256, 12)) do
            local data = item and item:getModData()
            if data and data[CAMP_CATCH_TAG] == true then
                items[#items + 1] = item
            end
        end
        state.campCatchItems = items
        state.nextCatchScanAt = now() + 10000
    end
    return state.campCatchItems
end

local function foodDestination(actor, item)
    if not SC.BaseLife or type(SC.BaseLife.depositStorageRows) ~= "function" then
        return nil, nil, "fishing_food_storage_missing"
    end
    local rows = SC.BaseLife.depositStorageRows("food")
    local best, bestContainer, bestDistance
    for _, storage in ipairs(rows) do
        local container = SC.BaseLife.resolveContainer(storage)
        local object = SC.BaseLife.resolveObject(storage)
        if container and object then
            local accepts = SC.BaseLife.storageAcceptsDeposit(storage, container)
            local room
            if SC.WorkTransport and SC.WorkTransport.hasRoom then
                room = SC.WorkTransport.hasRoom(container, actor, item)
            else
                local allowed, called = U().call(container, "hasRoomFor", actor, item)
                room = called and allowed == true
            end
            if accepts == true and room == true then
                local distance = U().distanceSq(actor, object)
                if not bestDistance or distance < bestDistance then
                    best, bestContainer, bestDistance = storage, container, distance
                end
            end
        end
    end
    if not best then
        return nil, nil, #rows == 0 and "fishing_food_storage_missing"
            or "fishing_food_storage_unavailable"
    end
    return best, bestContainer
end

local function deliverCampCatches(actor, state, items)
    if #items == 0 then
        state.delivering, state.deliveryItem = nil, nil
        state.deliveryStorage, state.deliveryContainer = nil, nil
        state.phase = "finding"
        return nil
    end
    if not state.delivering then
        state.delivering = true
        if state.rodSim and state.rodSim.resetItemModel then
            pcall(state.rodSim.resetItemModel, state.rodSim)
        end
        pcall(function()
            actor:setFishingStage("None")
            actor:setVariable("FishingFinished", true)
            if state.rod and actor:getPrimaryHandItem() == state.rod then
                actor:setPrimaryHandItem(state.previousHand)
            end
        end)
    end
    local item = state.deliveryItem or items[1]
    local inventory = actor:getInventory()
    local source = item:getContainer()
    if source ~= inventory then
        if not source or not U().inventoryContains(source, item) then
            state.deliveryItem, state.deliveryStorage = nil, nil
            state.deliveryContainer, state.visualAt = nil, nil
            campCatches(actor, state, true)
            return true, "fishing_catch_changed"
        end
        local moved = U().transferItemVerified(source, inventory, item)
        if moved ~= true then return false, "fishing_catch_inaccessible" end
    elseif not U().inventoryContains(inventory, item) then
        state.deliveryItem, state.deliveryStorage = nil, nil
        state.deliveryContainer, state.visualAt = nil, nil
        campCatches(actor, state, true)
        return true, "fishing_catch_changed"
    end
    state.deliveryItem = item
    if not state.deliveryStorage then
        local storage, container, reason = foodDestination(actor, item)
        if not storage then return false, reason end
        state.deliveryStorage, state.deliveryContainer = storage, container
    end
    if not SC.BaseWork or type(SC.BaseWork.depositToStorage) ~= "function" then
        return false, "fishing_storage_transfer_unavailable"
    end
    local handled, reason = SC.BaseWork.depositToStorage(actor, state,
        state.deliveryStorage, state.deliveryContainer, item)
    if handled == true and reason == "base_supply_returned" then
        item:getModData()[CAMP_CATCH_TAG] = nil
        state.deliveryItem, state.deliveryStorage = nil, nil
        state.deliveryContainer, state.visualAt = nil, nil
        for index, pending in ipairs(items) do
            if pending == item then table.remove(items, index) break end
        end
        if #items == 0 then
            state.delivering = nil
            state.phase = "finding"
        end
        return true, "fishing_catch_stored"
    end
    if handled ~= true and (reason == "destination_full"
        or reason == "base_storage_unloaded"
        or reason == "base_storage_changed"
        or reason == "base_storage_deposits_disabled") then
        state.deliveryStorage, state.deliveryContainer = nil, nil
        state.visualAt = nil
    end
    return handled, reason
end

local function finishCatch(actor, state)
    local item = state.catch
    if not item then return false, "catch_missing" end
    local inventory = actor:getInventory()
    local received = U().addItem(inventory, item)
    if received ~= item or not U().inventoryContains(inventory, item) then
        return false, "catch_inventory_failed"
    end
    if state.rodSim and state.rodSim.consumeLure then
        pcall(state.rodSim.consumeLure, state.rodSim, state.isTrash)
    end
    if type(addXp) == "function" and Perks and Perks.Fishing then
        local size = tonumber(item:getModData().fishing_FishSize)
        pcall(addXp, actor, Perks.Fishing, size and 2 * size or 1)
    end
    local modData = actor:getModData()
    modData["fishing_CatchDone_" .. item:getFullType()] = true
    modData.Fishing_IsFirstFishing = true
    local receiptAccepted = true
    local activeRequest = state.mode == "expedition" and not state.isTrash
        and SC.ExpeditionPrototype
        and type(SC.ExpeditionPrototype.fishingRequestFor) == "function"
        and SC.ExpeditionPrototype.fishingRequestFor(actor)
    if activeRequest then
        receiptAccepted = SC.ExpeditionPrototype
            and type(SC.ExpeditionPrototype.noteFishCaught) == "function"
            and SC.ExpeditionPrototype.noteFishCaught(actor, item,
                state.site.water) == true
    end
    if state.bobber then pcall(state.bobber.destroy, state.bobber) end
    state.bobber, state.catch = nil, nil
    state.phase, state.phaseAt = "ready", now()
    pcall(actor.setVariable, actor, "FishingFinished", true)
    if not receiptAccepted then
        return failFishing(actor, state.mode, "fish_receipt_failed")
    end
    if state.mode == "camp" and not state.isTrash then
        local catches = campCatches(actor, state)
        item:getModData()[CAMP_CATCH_TAG] = true
        catches[#catches + 1] = item
    end
    speak(actor, state.isTrash and "fishing.trash" or "fishing.catch", 55, 8000)
    return true, "fish_caught"
end

function Angling.update(actor, mode, request, player, snapshot)
    if mode ~= "camp" and mode ~= "expedition" then return false, "invalid_fishing_mode" end
    if type(isClient) == "function" and isClient() then
        return false, "fishing_singleplayer_only"
    end
    if engineRetryAt[actor] then
        if now() < engineRetryAt[actor] then
            return false, "fishing_engine_cooldown"
        end
        engineRetryAt[actor] = nil
    end
    local state = states[actor]
    if state and state.mode ~= mode then Angling.cancel(actor, "fishing_mode_changed") state = nil end
    if not state then
        state = { mode = mode, phase = "finding", scanIndex = 0 }
        states[actor] = state
    end
    if mode == "camp" then
        local catches = campCatches(actor, state)
        if #catches == 0 then
            state.delivering = nil
        else
            local needsDelivery = state.delivering
                or #catches >= CAMP_DELIVERY_COUNT
            if not needsDelivery then
                local _, _, loadRatio = U().inventoryLoad(actor)
                needsDelivery = loadRatio >= CAMP_DELIVERY_LOAD_RATIO
            end
            if needsDelivery then return deliverCampCatches(actor, state, catches) end
        end
    end
    local rod, lure = gear(actor, state)
    if not rod then
        return missingGearFailure(actor, mode, "fishing_rod_missing", player,
            snapshot)
    end
    if rod:getModData().fishing_Lure == nil and not lure
        and state.phase ~= "baiting" then
        return missingGearFailure(actor, mode, "fishing_bait_missing", player,
            snapshot)
    end
    local site, siteReason = siteFor(actor, state, mode, request)
    if not site then
        if siteReason == "no_fishing_water" then
            Angling.cancel(actor, siteReason)
            if mode == "expedition" and SC.ExpeditionPrototype
                and type(SC.ExpeditionPrototype.noFishingWater) == "function" then
                SC.ExpeditionPrototype.noFishingWater(actor)
            end
        end
        return siteReason == "scanning_water"
            or siteReason == "waiting_for_bank", siteReason
    end
    if state.bobber and not U().arrived(actor, site.bank,
        { targetKind = "square", distance = 1.5 }) then
        Angling.cancel(actor, "fishing_bank_left")
        return false, "fishing_bank_left"
    end
    local ax, ay = U().position(actor)
    if ax == nil or math.floor(ax) ~= site.bank.x
        or math.floor(ay) ~= site.bank.y
        or not U().arrived(actor, site.bank,
            { targetKind = "square", distance = 0.6 }) then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "navigation_unavailable"
        end
        local square = U().loadedSquare(site.bank)
        if not square then return false, "fishing_bank_unloaded" end
        return SC.Navigation.request(actor, square, "walk", {
            action = "move_to_fishing_spot", targetSquare = square,
            requireSameSquare = true, workReach = mode == "camp" })
    end
    local inventory = actor:getInventory()
    local source = rod:getContainer()
    if source and source ~= inventory then
        local moved = U().transferItemVerified(source, inventory, rod)
        if not moved then return false, "fishing_rod_inaccessible" end
    end
    if rod:getModData().fishing_Lure == nil then
        -- The vanilla action consumes bait and plays the change-bait animation.
        if state.phase ~= "baiting" then
            if not lure then
                return missingGearFailure(actor, mode, "fishing_bait_missing",
                    player, snapshot)
            end
            local lureSource = lure:getContainer()
            if lureSource and lureSource ~= inventory then
                local moved = U().transferItemVerified(lureSource, inventory, lure)
                if not moved then return false, "fishing_bait_inaccessible" end
            end
            if not AIAttachLureAction or not ISTimedActionQueue
                or type(ISTimedActionQueue.getTimedActionQueue) ~= "function" then
                return failFishing(actor, mode, "bait_action_unavailable", true)
            end
            local queue = ISTimedActionQueue.getTimedActionQueue(actor)
            if not queue or queue.current ~= nil
                or type(queue.queue) ~= "table" or #queue.queue ~= 0 then
                return false, "bait_action_busy"
            end
            local action = AIAttachLureAction:new(actor, rod, lure)
            state.phase, state.phaseAt = "baiting", now()
            state.baitAction, state.baitQueue = action, queue
            local added = pcall(ISTimedActionQueue.add, action)
            if not added then
                return failFishing(actor, mode, "bait_action_unavailable", true)
            end
        elseif now() - state.phaseAt > 15000 then
            return failFishing(actor, mode, "bait_action_timeout", true)
        end
        return true, "attaching_bait"
    end
    if state.phase == "baiting" then
        state.phase, state.baitAction, state.baitQueue = "ready", nil, nil
    end
    if actor:getPrimaryHandItem() ~= rod then
        state.previousHand = state.previousHand or actor:getPrimaryHandItem()
        actor:setPrimaryHandItem(rod)
        return true, "equipping_fishing_rod"
    end
    state.rod = rod
    -- Equipping a rod on the split-screen local player creates the input-driven
    -- vanilla manager. The AI owns this actor while its mission is active.
    local managers = Fishing and Fishing.ManagerInstances
    local index = actor.getPlayerNum and actor:getPlayerNum() or nil
    if managers and index ~= nil and managers[index] then
        pcall(managers[index].destroy, managers[index])
        managers[index] = nil
    end
    if not Fishing or not Fishing.FishingRod or not Fishing.Bobber then
        return failFishing(actor, mode, "fishing_engine_unavailable", true)
    end
    faceWater(actor, site)
    if state.phase == "pickup" then
        if now() - state.phaseAt < PICKUP_DELAY then return true, "landing_fish" end
        return finishCatch(actor, state)
    end
    if state.phase == "waiting" then return true, "waiting_for_fish" end
    if state.phase == "casting" then
        if now() - state.phaseAt < CAST_DELAY then return true, "casting" end
        local ok, bobber = pcall(Fishing.Bobber.new, Fishing.Bobber,
            actor, state.rodSim, site.water.x, site.water.y)
        if not ok or not bobber then
            return failFishing(actor, mode, "cast_failed", true)
        end
        state.bobber, state.phase = bobber, "waiting"
        pcall(actor.setFishingStage, actor, "Idle")
        return true, "waiting_for_fish"
    end
    local ready, sim = pcall(Fishing.FishingRod.new,
        Fishing.FishingRod, actor, -1)
    if not ready or not sim then
        return failFishing(actor, mode, "fishing_rod_unusable", true)
    end
    state.rodSim = sim
    state.rodSim.getTension = function() return 0.18 end
    state.rodSim.getRodEndXY = function()
        return actor:getX() + 0.5, actor:getY() + 0.5
    end
    state.phase, state.phaseAt = "casting", now()
    pcall(actor.setVariable, actor, "FishingFinished", false)
    pcall(actor.setFishingStage, actor, "Cast")
    pcall(actor.reportEvent, actor, "EventFishing")
    pcall(actor.playSound, actor, "CastFishingLine")
    speak(actor, "fishing.cast", 25, 45000)
    return true, "casting"
end

function Angling.reset()
    local actors = {}
    for actor in pairs(states) do actors[#actors + 1] = actor end
    for _, actor in ipairs(actors) do Angling.cancel(actor, "reset") end
    engineRetryAt = setmetatable({}, { __mode = "k" })
    lastPartyFishingLineAt = -math.huge
    bankListCache = nil
end

Angling._usableBankForTests = usableBank
Angling._siteForTests = siteFor
Angling._finishCatchForTests = finishCatch
Angling._setStateForTests = function(actor, state) states[actor] = state end
