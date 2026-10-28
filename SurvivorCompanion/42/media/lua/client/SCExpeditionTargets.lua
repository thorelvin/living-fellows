-- SPDX-License-Identifier: MIT
-- Manual map targets are plain data. Knowledge and geometry are read again at
-- review/dispatch; a UI label or saved distance never grants permission.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionTargets = SC.ExpeditionTargets or {}
local T = SC.ExpeditionTargets
local kinds = { scout = true, search = true, fish = true, wood = true }

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return nil end
    local success, value = pcall(fn, object, ...)
    return success and value or nil
end

local function tile(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= 30000 and value == math.floor(value)
end

local function point(value)
    return type(value) == "table" and tile(value.x) and tile(value.y) and value.z == 0
end

function T.limit(mode) return mode == "drive" and 5000 or 1000 end

function T.known(at)
    if not point(at) then return false end
    local visited
    -- Static Java functions use dot invocation; Lua fixtures can do so too.
    if not visited and WorldMapVisited and type(WorldMapVisited.getInstance) == "function" then
        local ok, value = pcall(WorldMapVisited.getInstance)
        visited = ok and value or nil
    end
    return call(visited, "isKnown", at.x, at.y) == true
        or call(visited, "isVisited", at.x, at.y) == true
end

function T.valid(target)
    if type(target) ~= "table" or target.version ~= 1 or not kinds[target.kind]
        or not point(target.anchor) or type(target.id) ~= "string"
        or #target.id < 1 or #target.id > 128 or type(target.label) ~= "string"
        or #target.label < 1 or #target.label > 80 then return false end
    if target.kind == "wood" then
        local b, a = target.workBounds, target.anchor
        return target.id == "wood:"..a.x..":"..a.y
            and type(b) == "table" and b.z == 0 and tile(b.x1) and tile(b.y1)
            and tile(b.x2) and tile(b.y2)
            and b.x1 == math.max(0, a.x - 32) and b.y1 == math.max(0, a.y - 32)
            and b.x2 == math.min(30000, a.x + 32) and b.y2 == math.min(30000, a.y + 32)
    end
    if target.kind == "fish" then
        return target.workBounds == nil and target.id == "bank:"..target.anchor.x..":"..target.anchor.y
    end
    local x,y,x2,y2=target.id:match("^(%d+):(%d+):(%d+):(%d+)$")
    x,y,x2,y2=tonumber(x),tonumber(y),tonumber(x2),tonumber(y2)
    if not x or target.anchor.x<x or target.anchor.y<y
        or target.anchor.x>x2 or target.anchor.y>y2 then return false end
    return target.workBounds == nil
end

function T.copy(target)
    if not T.valid(target) then return nil end
    local copy = { version = 1, kind = target.kind, id = target.id,
        label = target.label, anchor = { x = target.anchor.x, y = target.anchor.y, z = 0 } }
    if target.workBounds then
        local b = target.workBounds
        copy.workBounds = { x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2, z = 0 }
    end
    return copy
end

function T.fingerprint(target)
    if not T.valid(target) then return "none" end
    local a, b = target.anchor, target.workBounds
    return table.concat({ target.kind, target.id, a.x, a.y,
        b and b.x1 or "", b and b.y1 or "", b and b.x2 or "", b and b.y2 or "" }, ":")
end

function T.reviewFingerprint(target, options, records)
    local parts={T.fingerprint(target)}
    for _,key in ipairs({"travelMode","turnHomeAfterHours","doctrine","restockBaseDuty","parkingZoneId","vehicleSqlId"}) do
        parts[#parts+1]=tostring(options[key])
    end
    local request=options.request or {}
    parts[#parts+1]=tostring(request.mode)
    parts[#parts+1]=tostring(request.category)
    parts[#parts+1]=tostring(request.quantity)
    for _,record in ipairs(records or {}) do parts[#parts+1]=tostring(record.id) end
    return table.concat(parts,"|")
end

function T.context(leader, mode, map)
    if type(leader) == "string" then leader = SC.Registry and SC.Registry.byId(leader) or nil end
    return { actor = type(leader) == "table" and leader.actor or leader,
        travelMode = mode or "road", mapData = map or T.mapData }
end

function T.distance(at, context)
    local actor = context and context.actor
    local x, y = call(actor, "getX"), call(actor, "getY")
    if x == nil and SC.GameplayUtil and actor then x, y = SC.GameplayUtil.position(actor) end
    if type(x) ~= "number" or type(y) ~= "number" or x~=x or y~=y
        or x<0 or y<0 or x>30000 or y>30000 then return nil end
    return math.sqrt((at.x - x)^2 + (at.y - y)^2)
end

local function eligible(target, context)
    if not context or (context.travelMode ~= "road" and context.travelMode ~= "straight"
        and context.travelMode ~= "drive") then return nil, "invalid_travel_mode" end
    local distance = T.distance(target.anchor, context)
    if not distance then return nil, "leader_unavailable" end
    if distance > T.limit(context.travelMode) then return nil, "map_target_out_of_range" end
    local strict = (target.kind == "scout" or target.kind == "search")
        and SC.Config and SC.Config.get("expeditionDestinationScope") == "known_only"
    local known = T.known(target.anchor)
    if (distance > 200 or strict) and not known then return nil, "map_target_unexplored" end
    target.distance, target.mapKnown = math.ceil(distance), known
    return target
end

local function forestAt(at, context)
    local world = type(getWorld) == "function" and getWorld() or nil
    local grid = call(world, "getMetaGrid")
    local zones = call(grid, "getZonesIntersecting", at.x, at.y, 0, 1, 1)
    if not zones then return nil, "forest_map_unavailable" end
    local zone, kind
    for index = 0, math.min(127, (tonumber(call(zones, "size")) or 0) - 1) do
        local candidate = call(zones, "get", index)
        local name = call(candidate, "getType")
        if (name == "Forest" or name == "DeepForest")
            and call(candidate, "contains", at.x, at.y, 0) == true then
            zone, kind = candidate, name
            break
        end
    end
    if not zone then return nil, "map_target_not_forest" end
    local base = SC.BaseLife
    local b = { x1 = math.max(0, at.x - 32), y1 = math.max(0, at.y - 32),
        x2 = math.min(30000, at.x + 32), y2 = math.min(30000, at.y + 32), z = 0 }
    local target = { version = 1, kind = "wood", id = "wood:" .. at.x .. ":" .. at.y,
        anchor = at, workBounds = b, label = "Woodland", sites = {} }
    for _, offset in ipairs({ {0,0}, {24,0}, {-24,0}, {0,24}, {0,-24} }) do
        local x, y = at.x + offset[1], at.y + offset[2]
        local zx, zy = tonumber(call(zone, "getX")), tonumber(call(zone, "getY"))
        local zw, zh = tonumber(call(zone, "getWidth")), tonumber(call(zone, "getHeight"))
        if zx and zy and zw and zh and call(zone, "contains", x, y, 0) == true then
            local bounds = { x1 = math.max(b.x1, zx, x - 8), y1 = math.max(b.y1, zy, y - 8),
                x2 = math.min(b.x2, zx + zw - 1, x + 8), y2 = math.min(b.y2, zy + zh - 1, y + 8), z = 0 }
            local outside = true
            for _, p in ipairs({ {x=x,y=y,z=0}, {x=bounds.x1,y=bounds.y1,z=0},
                {x=bounds.x2,y=bounds.y2,z=0}, {x=bounds.x1,y=bounds.y2,z=0},
                {x=bounds.x2,y=bounds.y1,z=0} }) do
                if call(zone, "contains", p.x, p.y, 0) ~= true or base and base.isInside
                    and (base.isInside(p) or base.isInside(p, "parking")) then outside = false end
            end
            if outside and tile(x) and tile(y) then
                target.sites[#target.sites + 1] = { id = "forest:" .. x .. ":" .. y .. ":" .. kind,
                    type = kind, label = "Selected woodland", anchor = { x=x,y=y,z=0 }, bounds = bounds,
                    distance = math.ceil(T.distance({x=x,y=y,z=0}, context) or 5001),
                    knowledge = "forest_metadata_unconfirmed" }
                if #target.sites == 3 then break end
            end
        end
    end
    if #target.sites == 0 then return nil, "map_target_not_forest" end
    target.place = target.sites[1]
    return target
end

function T.resolveAtPoint(kind, at, context)
    if not kinds[kind] or type(at) ~= "table" or type(at.x) ~= "number"
        or type(at.y) ~= "number" then return nil, "map_target_invalid" end
    at = { x = math.floor(at.x), y = math.floor(at.y), z = at.z or 0 }
    if not point(at) then return nil, "map_target_invalid" end
    local target, reason
    if kind == "wood" then
        -- Reject unknown distant points before querying hidden woodland metadata.
        local admitted, why = eligible({kind=kind,anchor=at}, context)
        if not admitted then return nil, why end
        target, reason = forestAt(at, context)
    elseif kind == "fish" then
        if not SC.Fishing or not SC.Fishing.bankNearPoint then return nil, "fishing_bank_lookup_unavailable" end
        local bank
        bank, reason = SC.Fishing.bankNearPoint(context and context.actor, at,
            T.limit(context and context.travelMode), context and context.mapData or T.mapData)
        if bank then target = { version=1,kind=kind,id=bank.id,anchor=bank.anchor,
            label="Fishing bank",place=bank } end
    else
        local admitted, why = eligible({kind=kind,anchor=at}, context)
        if not admitted then return nil, why end
        local place = SC.ExpeditionPlaces and SC.ExpeditionPlaces.atPoint(at)
        if place then target = {version=1,kind=kind,id=place.id,anchor=at,
            label=place.label,place=place} else reason = "map_target_not_building" end
    end
    if not target then return nil, reason end
    local admitted, why = eligible(target, context)
    if not admitted then return nil, why end
    local location = SC.Factions and SC.Factions.describeLocation
        and SC.Factions.describeLocation(target.anchor)
    local street = location and location.nearestStreet and location.nearestStreet.name
    if type(street) == "string" and street ~= "" then target.label = target.label .. " near " .. street end
    target.label = string.sub(target.label, 1, 64)
    return target
end

function T.validate(target, context)
    if not T.valid(target) then return nil, "map_target_invalid" end
    local fresh, reason = T.resolveAtPoint(target.kind, target.anchor, context)
    if not fresh then return nil, reason end
    if fresh.id ~= target.id or T.fingerprint(fresh) ~= T.fingerprint(target) then
        return nil, "map_target_changed"
    end
    return fresh
end

function T.reset() T.mapData = nil end

function T.matchesMission(target, scout)
    if not T.valid(target) or type(scout) ~= "table" then return false end
    if target.kind == "wood" then
        if scout.kind ~= "wood" or type(scout.wood) ~= "table"
            or type(scout.wood.sites) ~= "table" or #scout.wood.sites < 1 or #scout.wood.sites > 3 then return false end
        local b = target.workBounds
        for _, site in ipairs(scout.wood.sites) do
            local s = type(site) == "table" and site.bounds
            if type(s) ~= "table" or not tile(s.x1) or not tile(s.y1) or not tile(s.x2) or not tile(s.y2)
                or s.x1 < b.x1 or s.y1 < b.y1 or s.x2 > b.x2 or s.y2 > b.y2 then return false end
        end
        return true
    elseif target.kind == "fish" then
        return scout.kind == "search" and type(scout.search) == "table"
            and type(scout.search.request) == "table" and scout.search.request.category == "fish"
            and point(scout.destination)
            and scout.destination.x == target.anchor.x and scout.destination.y == target.anchor.y
    end
    return scout.kind == target.kind and type(scout.site) == "table" and scout.site.id == target.id
end
return T
