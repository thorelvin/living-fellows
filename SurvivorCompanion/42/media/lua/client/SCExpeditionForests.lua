-- SPDX-License-Identifier: MIT
-- Forest metadata chooses a place to look; only loaded, mature native trees
-- establish that the crew has found timber. No map or camp zones are created.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionForests = SC.ExpeditionForests or {}
local Forests = SC.ExpeditionForests
local scans = setmetatable({}, { __mode = "k" })
local checks = setmetatable({}, { __mode = "k" })
local CELL, ZONE_BUDGET, MAX_ZONES = 200, 48, 4096
local PATCH_RADIUS, MIN_TREES, MAX_CANDIDATES, MAX_REJECTED = 8, 1, 256, 4096

local function call(object, method, ...)
    if object == nil then return nil end
    local readable, fn = pcall(function() return object[method] end)
    if not readable or type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
end

local function position(actor)
    local utility = SC.GameplayUtil
    if utility and type(utility.position) == "function" then
        return utility.position(actor)
    end
    return call(actor, "getX"), call(actor, "getY"), call(actor, "getZ")
end

local function integer(value, low, high)
    return type(value) == "number" and value == value
        and value == math.floor(value) and value >= low and value <= high
end

local function outsideCamp(x, y)
    local base = SC.BaseLife
    return not (base and type(base.isInside) == "function"
        and (base.isInside({ x = x, y = y, z = 0 }) == true
            or base.isInside({ x = x, y = y, z = 0 }, "parking") == true))
end

local function label(x, y, ox, oy)
    local dx, dy = x - ox, y - oy
    local direction = (math.abs(dy) > math.abs(dx) * 0.4 and (dy < 0 and "north" or "south") or "")
        .. (math.abs(dx) > math.abs(dy) * 0.4 and (dx < 0 and "west" or "east") or "")
    local location = SC.Factions and type(SC.Factions.describeLocation) == "function"
        and SC.Factions.describeLocation({ x = x, y = y, z = 0 }) or nil
    local street = location and location.nearestStreet and location.nearestStreet.name
    return string.sub("Forest " .. direction .. (type(street) == "string"
        and street ~= "" and (" near " .. street) or ""), 1, 80)
end

local function copySite(site)
    return { id = site.id, label = site.label, type = site.type,
        anchor = { x = site.anchor.x, y = site.anchor.y, z = 0 },
        bounds = { x1 = site.bounds.x1, y1 = site.bounds.y1,
            x2 = site.bounds.x2, y2 = site.bounds.y2, z = 0 },
        distance = site.distance, knowledge = "forest_metadata_unconfirmed" }
end

function Forests.validSite(site)
    return type(site) == "table" and type(site.id) == "string" and #site.id <= 128
        and #site.id > 0 and type(site.label) == "string" and #site.label > 0 and #site.label <= 80
        and (site.type == "Forest" or site.type == "DeepForest")
        and type(site.anchor) == "table" and integer(site.anchor.x, 0, 30000)
        and integer(site.anchor.y, 0, 30000) and site.anchor.z == 0
        and type(site.bounds) == "table"
        and integer(site.bounds.x1, 0, 30000) and integer(site.bounds.y1, 0, 30000)
        and integer(site.bounds.x2, site.bounds.x1, 30000)
        and integer(site.bounds.y2, site.bounds.y1, 30000)
        and site.anchor.x >= site.bounds.x1 and site.anchor.x <= site.bounds.x2
        and site.anchor.y >= site.bounds.y1 and site.anchor.y <= site.bounds.y2
        and site.bounds.x2 - site.bounds.x1 <= PATCH_RADIUS * 2
        and site.bounds.y2 - site.bounds.y1 <= PATCH_RADIUS * 2
        and site.bounds.z == 0 and integer(site.distance, 0, 5100)
end

function Forests.copySite(site)
    return Forests.validSite(site) and copySite(site) or nil
end

local function cells(x, y, radius)
    local rows = {}
    local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
    local band = math.ceil(radius / CELL)
    for oy = -band, band do
        for ox = -band, band do
            local px, py = (cx + ox) * CELL, (cy + oy) * CELL
            if px >= 0 and py >= 0 and px <= 30000 and py <= 30000 then
                local dx = math.max(px - x, x - (px + CELL - 1), 0)
                local dy = math.max(py - y, y - (py + CELL - 1), 0)
                if dx * dx + dy * dy <= radius * radius then
                    rows[#rows + 1] = { x = px, y = py, distance = dx * dx + dy * dy }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return rows
end

local function candidate(scan, zone)
    local kind = call(zone, "getType")
    if kind ~= "Forest" and kind ~= "DeepForest" then return end
    local x, y = tonumber(call(zone, "getX")), tonumber(call(zone, "getY"))
    local width, height = tonumber(call(zone, "getWidth")), tonumber(call(zone, "getHeight"))
    if not x or not y or not width or not height or width < 1 or height < 1 then return end
    local x2, y2 = math.min(30000, x + width - 1), math.min(30000, y + height - 1)
    local centerX = math.max(x, math.min(x2, scan.x))
    local centerY = math.max(y, math.min(y2, scan.y))
    local choices = { { centerX, centerY } }
    for _, distance in ipairs({ 16, 32, 64 }) do
        for _, direction in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
                { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
            choices[#choices + 1] = { math.max(x, math.min(x2, centerX + direction[1] * distance)),
                math.max(y, math.min(y2, centerY + direction[2] * distance)) }
        end
    end
    for _, at in ipairs(choices) do
        local px, py = math.floor(at[1]), math.floor(at[2])
        local gap = (px - scan.x)^2 + (py - scan.y)^2
        local originGap = (px - scan.originX)^2 + (py - scan.originY)^2
        local seed = scan.seed
        local apartFromSeed = not seed or (px - seed.x)^2 + (py - seed.y)^2 >= 24^2
        if originGap >= 8^2 and originGap <= 1000^2 and gap <= scan.radius^2 and apartFromSeed and outsideCamp(px, py)
            and call(zone, "contains", px, py, 0) == true then
            local id = table.concat({ "forest", px, py, kind }, ":")
            if not scan.rejected[id] and not scan.seen[id] then
                scan.seen[id] = true
                local apart = true
                for index = #scan.candidates, 1, -1 do
                    local previous = scan.candidates[index]
                    if (previous.anchor.x - px)^2 + (previous.anchor.y - py)^2 < 24^2 then
                        if gap < previous.gap then table.remove(scan.candidates, index)
                        else apart = false break end
                    end
                end
                if apart then
                    scan.candidates[#scan.candidates + 1] = { id = id, type = kind,
                        anchor = { x = px, y = py, z = 0 },
                        bounds = { x1 = math.max(x, px - PATCH_RADIUS),
                            y1 = math.max(y, py - PATCH_RADIUS),
                            x2 = math.min(x2, px + PATCH_RADIUS),
                            y2 = math.min(y2, py + PATCH_RADIUS), z = 0 },
                        distance = math.floor(math.sqrt(originGap) + 0.5), gap = gap,
                        knowledge = "forest_metadata_unconfirmed" }
                end
            end
        end
    end
    table.sort(scan.candidates, function(a, b) return a.gap < b.gap end)
    while #scan.candidates > MAX_CANDIDATES do
        scan.truncated = true
        table.remove(scan.candidates)
    end
end

-- Admission may reject a mapped patch after a bounded road/car check. Resume
-- the distance-ordered scan rather than treating the first three as the world.
function Forests.reject(actor, travelMode, siteId, cacheKey)
    local bucket = scans[actor]
    local scan = bucket and bucket[travelMode]
    if not scan or scan.cacheKey ~= cacheKey or type(siteId) ~= "string" then return false end
    if not scan.rejected[siteId] then
        if scan.rejectedCount >= MAX_REJECTED then return false end
        scan.rejected[siteId], scan.rejectedCount = true, scan.rejectedCount + 1
    end
    for index = #scan.candidates, 1, -1 do
        if scan.candidates[index].id == siteId then table.remove(scan.candidates, index) end
    end
    if #scan.candidates == 0 and scan.truncated and scan.examined < MAX_ZONES then
        -- Recover farther candidates omitted by the bounded nearest-site bank.
        -- Replays still consume the same lifetime metadata budget.
        scan.cell, scan.zones, scan.seen, scan.truncated = 1, nil, {}, nil
    end
    scan.done = false
    return true
end

-- One small metadata cell and at most 48 zone records are examined per call.
-- Cache only the candidate list, never a promise about unstreamed trees.
function Forests.preview(actor, travelMode, options)
    options = type(options) == "table" and options or {}
    local x, y, z = position(actor)
    local radius = tonumber(options.radius) or 1000
    if not x or not y or z ~= 0 or not integer(radius, 16, 1000)
        or (travelMode ~= "road" and travelMode ~= "straight" and travelMode ~= "drive") then
        return nil, "invalid_forest_query"
    end
    x, y = math.floor(x), math.floor(y)
    local originX, originY = x, y
    local center = options.center
    local limit = options.limit or 3
    if not integer(limit, 1, 3) then return nil, "invalid_forest_query" end
    if center ~= nil then
        if travelMode ~= "drive" or not integer(center.x, 0, 30000)
            or not integer(center.y, 0, 30000) or center.z ~= 0
            or options.seed ~= nil and not Forests.validSite(options.seed) then
            return nil, "invalid_forest_query"
        end
        x, y = center.x, center.y
    end
    local slot = center and "drive_near_car" or travelMode
    local bucket = scans[actor]
    if not bucket then bucket = {}; scans[actor] = bucket end
    local scan = bucket[slot]
    if options.refresh == true or not scan or scan.radius ~= radius
        or scan.cacheKey ~= options.cacheKey
        or scan.limit ~= limit or (center ~= nil and (scan.x ~= x or scan.y ~= y))
        or (scan.originX - originX)^2 + (scan.originY - originY)^2 > 16^2 then
        scan = { x = x, y = y, radius = radius, cells = cells(x, y, radius), cell = 1,
            candidates = {}, seen = {}, examined = 0, rejected = {}, rejectedCount = 0,
            cacheKey = options.cacheKey, limit = limit, originX = originX, originY = originY,
            seed = center and options.seed and { x = options.seed.anchor.x, y = options.seed.anchor.y } or nil }
        bucket[slot] = scan
    end
    if not scan.done then
        local world = type(getWorld) == "function" and getWorld() or nil
        local grid = call(world, "getMetaGrid")
        if not grid then return nil, "forest_map_unavailable" end
        local current = scan.cells[scan.cell]
        local third = scan.candidates[limit]
        if not current or scan.examined >= MAX_ZONES or scan.rejectedCount >= MAX_REJECTED
            or third and current.distance > third.gap then
            scan.done = true
        else
            if not scan.zones then
                scan.zones = call(grid, "getZonesIntersecting", current.x, current.y, 0, CELL, CELL)
                if not scan.zones then return nil, "forest_map_unavailable" end
                scan.zoneIndex, scan.zoneCount = 0, math.min(1024, tonumber(call(scan.zones, "size")) or 0)
            end
            local budget = ZONE_BUDGET
            while budget > 0 and scan.zoneIndex < scan.zoneCount and scan.examined < MAX_ZONES do
                candidate(scan, call(scan.zones, "get", scan.zoneIndex))
                scan.zoneIndex, scan.examined, budget = scan.zoneIndex + 1, scan.examined + 1, budget - 1
            end
            if scan.zoneIndex >= scan.zoneCount then
                scan.cell, scan.zones = scan.cell + 1, nil
            end
        end
    end
    if not scan.done then return nil, "forest_scan_pending" end
    table.sort(scan.candidates, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        return a.id < b.id
    end)
    local result = { candidates = {}, provisional = true, radius = radius, mode = travelMode }
    for index = 1, math.min(limit, #scan.candidates) do
        local site = scan.candidates[index]
        site.label = site.label or label(site.anchor.x, site.anchor.y, scan.originX, scan.originY)
        result.candidates[index] = copySite(site)
    end
    if #result.candidates == 0 then
        return nil, scan.rejectedCount > 0 and "no_reachable_forest" or "no_suitable_forest"
    end
    result.destination, result.label = result.candidates[1].anchor, result.candidates[1].label
    result.distance = result.candidates[1].distance
    return result
end

function Forests.nearCar(actor, stop, firstSite, cacheKey)
    local x, y = stop and tonumber(stop.x), stop and tonumber(stop.y)
    if not x or not y or x ~= x or y ~= y then return nil, "invalid_forest_query" end
    return Forests.preview(actor, "drive", { radius = 64,
        center = { x = math.floor(x), y = math.floor(y), z = 0 },
        seed = firstSite, limit = 2, cacheKey = cacheKey })
end

function Forests.verify(site, actor)
    if not Forests.validSite(site) then return false, "invalid_forest_site" end
    local state = checks[actor]
    if not state or state.id ~= site.id then
        state = { id = site.id, x = site.bounds.x1, y = site.bounds.y1, trees = 0, loaded = 0, scanned = 0 }
        checks[actor] = state
    end
    local utility = SC.GameplayUtil
    local function terminal(ready, reason)
        checks[actor] = nil
        if utility and type(utility.diagnostic) == "function" then
            utility.diagnostic("expedition-forest", actor, "action=arrival_check site=" .. site.id
                .. " label=" .. site.label .. " matureTrees=" .. state.trees
                .. " loadedSquares=" .. state.loaded .. " scannedSquares=" .. state.scanned
                .. " reason=" .. reason)
        end
        return ready, reason
    end
    for _ = 1, 48 do
        if state.y > site.bounds.y2 then
            return terminal(false, state.loaded == 0 and "forest_unloaded" or "forest_no_mature_trees")
        end
        state.scanned = state.scanned + 1
        local square = utility and utility.gridSquare(state.x, state.y, 0)
        if square then state.loaded = state.loaded + 1 end
        if square and outsideCamp(state.x, state.y) then
            local tree = call(square, "getTree")
            local index, size = tonumber(call(tree, "getObjectIndex")), tonumber(call(tree, "getSize"))
            if tree and index and index >= 0 and size and size >= 2 then
                state.trees = state.trees + 1
                if state.trees >= MIN_TREES then return terminal(true, "forest_verified") end
            end
        end
        state.x = state.x + 1
        if state.x > site.bounds.x2 then state.x, state.y = site.bounds.x1, state.y + 1 end
    end
    return nil, "forest_verify_pending"
end

function Forests.reset()
    scans, checks = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
end

return Forests
