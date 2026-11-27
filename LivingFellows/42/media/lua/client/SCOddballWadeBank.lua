-- SPDX-License-Identifier: MIT

local SC = LivingFellows
local Bank = {}
SC.OddballWadeBank = Bank

local CANOE_MARKER = "LF_WadeCanoeOwner"
local ESCAPE_STEPS = 4
local WATER_DEPTH = 6
local TREE_LIMIT = 5
local WOODLAND_RADIUS = 10
local CANOE_RADIUS = 10
local CANOE_RADIUS_SQUARED = CANOE_RADIUS * CANOE_RADIUS
local function U() return SC.GameplayUtil end

local function read(object, method, ...)
    return (U().call(object, method, ...))
end

local function squareAt(position)
    return position and U().gridSquare(position.x, position.y, position.z)
end

local function offset(origin, x, y)
    return { x = origin.x + x, y = origin.y + y, z = origin.z }
end

local function samePoint(left, right)
    return left and right and left.x == right.x and left.y == right.y and left.z == right.z
end

local function water(square)
    return square and SC.Topology.squareIsWater(square) == true
end

local function dryOutdoors(square)
    return square and read(square, "isOutside") == true
        and read(square, "getBuilding") == nil and not water(square)
end

local function clearDry(square, player)
    return dryOutdoors(square) and not read(square, "getTree")
        and U().isClearActorSpawnSquare(square) and not U().safehouseBlocker(square, player)
end

local function unseen(square, player, allowSeen)
    if allowSeen == true then return true end
    local index = tonumber(read(player, "getPlayerNum"))
    if index == nil then return false end
    local seen, checked = U().call(square, "isCanSee", math.floor(index))
    return checked and seen ~= true and U().canSee(player, square) ~= true
end

local function openEdge(from, to, player)
    local edge = SC.Topology.classifyEdge(player, from, to)
    return edge and edge.traversable == true and edge.affordance == "open"
end

-- Try three short, cardinal routes away from the water. A bend around the
-- first tree is fine as long as the whole route is on loaded, walkable land.
local function dryEscape(cast, player)
    local spawn = squareAt(cast.bank)
    for _, side in ipairs({ 0, -1, 1 }) do
        local route, previous = {}, spawn
        for step = 1, ESCAPE_STEPS do
            local inland = side == 0 and step or step - 1
            local position = offset(cast.bank, -inland * cast.dx + side * cast.dy,
                -inland * cast.dy - side * cast.dx)
            local square = squareAt(position)
            if not clearDry(square, player) or not openEdge(previous, square, player) then break end
            route[#route + 1], previous = position, square
        end
        if #route == ESCAPE_STEPS then return route end
    end
    return nil
end

local function riverWater(cast)
    for step = 3, WATER_DEPTH do
        if not water(squareAt(offset(cast.bank, cast.dx * step, cast.dy * step))) then return false end
    end
    for side = -3, 3, 3 do
        local position = offset(cast.bank, cast.dx * 3 + cast.dy * side,
            cast.dy * 3 - cast.dx * side)
        if not water(squareAt(position)) then return false end
    end
    return true
end

local function pavedRoad(square)
    local floor = read(square, "getFloor")
    local name = read(read(floor, "getSprite"), "getName")
    return type(name) == "string" and (name:find("^blends_street_") ~= nil
        or name:find("^floors_exterior_street_") ~= nil or name:find("^street_curbs_") ~= nil)
end

local function wooded(cast)
    local loaded, forest, trees = 0, 0, 0
    for inland = 0, WOODLAND_RADIUS do
        for side = -WOODLAND_RADIUS, WOODLAND_RADIUS do
            local distance = inland * inland + side * side
            if distance <= WOODLAND_RADIUS * WOODLAND_RADIUS then
                local position = offset(cast.bank, -cast.dx * inland + cast.dy * side,
                    -cast.dy * inland - cast.dx * side)
                local square = squareAt(position)
                if square then
                    if (distance <= 49 and read(square, "getBuilding") ~= nil)
                        or (distance <= 25 and pavedRoad(square)) then
                        return false
                    end
                    loaded = loaded + 1
                    local zone = read(read(square, "getZone"), "getType")
                    if zone == "Forest" or zone == "DeepForest" then forest = forest + 1 end
                    if read(square, "getTree") then trees = trees + 1 end
                end
            end
        end
    end
    return trees >= TREE_LIMIT or (trees >= 2 and forest * 2 >= loaded)
end

local function matureTree(square)
    if not dryOutdoors(square) then return nil end
    local tree = read(square, "getTree")
    local size = tonumber(read(tree, "getSize")) or 0
    if size >= 4 then return tree, size end
end

local function canoeTree(cast, player, allowSeen)
    local best, bestRank
    for x = -CANOE_RADIUS, CANOE_RADIUS do
        for y = -CANOE_RADIUS, CANOE_RADIUS do
            local distance = x * x + y * y
            if distance > 0 and distance <= CANOE_RADIUS_SQUARED and x * cast.dx + y * cast.dy <= 0 then
                local position = offset(cast.bank, x, y)
                local square = squareAt(position)
                local tree = matureTree(square)
                if tree and unseen(square, player, allowSeen) then
                    local name = tostring(read(read(tree, "getSprite"), "getName") or ""):lower()
                    -- Stock broad-leaved river trees make the closest visual
                    -- stand-in for the sycamore Wade mentions on the radio.
                    local broadleaf = name:find("birch", 1, true) or name:find("maple", 1, true)
                        or name:find("linden", 1, true) or name:find("sycamore", 1, true)
                    local rank = distance + (broadleaf and 0 or CANOE_RADIUS_SQUARED + 1)
                    if not bestRank or rank < bestRank then best, bestRank = position, rank end
                end
            end
        end
    end
    return best
end

local function unclaimed(bounds, points, player)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    local core = base and base.core
    if core then
        local radius = tonumber(base.radius) or tonumber(SC.Config.get("baseDefaultAreaRadius")) or 12
        if core.x + radius >= bounds.x1 and core.x - radius <= bounds.x2
            and core.y + radius >= bounds.y1 and core.y - radius <= bounds.y2 then return false end
    end
    for _, position in ipairs(points) do
        if SC.Factions.atPosition(position) or U().safehouseBlocker(squareAt(position), player) then
            return false
        end
    end
    return true
end

function Bank.siteFor(square, player, allowSeen)
    local fishing = SC.Fishing
    if not fishing or not fishing.usableBank then return nil, "fishing_unavailable" end
    local cast = fishing.usableBank(square)
    if not cast then return nil, "no_cast" end
    if not clearDry(square, player) or not unseen(square, player, allowSeen) then
        return nil, "bank_unavailable"
    end
    if not riverWater(cast) then return nil, "shallow_water" end
    if not wooded(cast) then return nil, "bank_not_secluded" end
    local escape = dryEscape(cast, player)
    if not escape then return nil, "bank_no_dry_exit" end
    local spawn = cast.bank
    local canoe = canoeTree(cast, player, allowSeen)
    if not canoe then return nil, "bank_no_canoe_tree" end
    local bounds = { x1 = spawn.x - CANOE_RADIUS, y1 = spawn.y - CANOE_RADIUS,
        x2 = spawn.x + CANOE_RADIUS, y2 = spawn.y + CANOE_RADIUS }
    local points = { spawn, canoe }
    for _, position in ipairs(escape) do points[#points + 1] = position end
    if not unclaimed(bounds, points, player) then return nil end
    return {
        kind = "fishing_bank", room = "riverbank", anchor = spawn, spawn = spawn,
        castWater = cast.water, bankEscape = escape, canoePost = canoe,
        house = { id = "fishing-bank:" .. spawn.x .. ":" .. spawn.y, anchor = spawn,
            bounds = bounds, interior = { spawn }, openings = {} },
    }
end

local function currentCast(site)
    local fishing = SC.Fishing
    local cast = site and fishing and fishing.usableBank and fishing.usableBank(squareAt(site.spawn))
    if cast and samePoint(cast.water, site.castWater) then return cast end
    return nil
end

function Bank.castSite(group)
    return currentCast(group and group.oddball and group.oddball.site)
end

local function ownedCanoe(square, groupId)
    local found
    U().squareObjects(square, function(object)
        local data = U().modData(object)
        if data and data[CANOE_MARKER] == groupId then found = object end
    end, 64)
    return found
end

local function canoeSprite(site)
    if type(getSprite) ~= "function" or not IsoDirections then return nil end
    local path = "media/textures/World/LFWadeCanoe"
        .. (site.castWater.x == site.spawn.x + 0.5 and "X" or "Y") .. ".png"
    local called, sprite = pcall(getSprite, path)
    if not called or not sprite or not read(sprite, "getTextureForCurrentFrame", IsoDirections.N) then return nil end
    if read(sprite, "getName") ~= path then U().call(sprite, "setName", path) end
    return read(sprite, "getName") == path and sprite or nil
end

function Bank.onSpawn(group)
    local story = group and group.oddball
    local site = story and story.site
    local square = site and squareAt(site.canoePost)
    if not square then return story and story.canoePlaced == true, "wade_canoe_unloaded" end
    local object = ownedCanoe(square, group.id)
    -- Once placed, a missing prop stays missing. A cold load may instead
    -- restore the object and its owner with a blank dynamic sprite.
    if story.canoePlaced == true and not object then return true, "wade_canoe_removed" end
    local tree, size = matureTree(square)
    if not tree then
        if object then U().call(square, "RemoveTileObject", object) end
        return story.canoePlaced == true, "wade_canoe_tree_removed"
    end
    local sprite = canoeSprite(site)
    if not sprite then return false, "wade_canoe_sprite_unavailable" end
    if not object then
        if not IsoObject or type(IsoObject.new) ~= "function" then
            return false, "wade_canoe_post_unavailable"
        end
        local okay, canoe = pcall(IsoObject.new, U().cell(), square, sprite)
        local data = okay and canoe and U().modData(canoe)
        if not data then return false, "wade_canoe_create_failed" end
        data[CANOE_MARKER] = group.id
        U().call(canoe, "setName", "Red canoe")
        U().call(square, "AddTileObject", canoe)
        object = ownedCanoe(square, group.id)
    end
    if not object then return false, "wade_canoe_add_failed" end
    if read(object, "getSprite") ~= sprite then U().call(object, "setSprite", sprite) end
    if read(object, "getSprite") ~= sprite then return false, "wade_canoe_sprite_rejected" end
    local lift = 36 + math.min(4, size - 4) * 4
    if read(object, "getRenderYOffset") ~= lift then U().call(object, "setRenderYOffset", lift) end
    if read(object, "getRenderYOffset") ~= lift then return false, "wade_canoe_lift_rejected" end
    story.canoePlaced = true
    return true, "wade_canoe_ready"
end

local function validate(story, path, kit)
    local site = story.site
    local spawn, target, canoe = site.spawn, site.castWater, site.canoePost
    if not target or not canoe or spawn.z ~= 0 or target.z ~= 0 or canoe.z ~= 0 then
        return kit.fail(path .. ".site", "missing ground-floor bank, cast or canoe post")
    end
    local dx, dy = (target.x - spawn.x - 0.5) / 2, (target.y - spawn.y - 0.5) / 2
    if math.abs(dx) + math.abs(dy) ~= 1 or dx % 1 ~= 0 or dy % 1 ~= 0 then
        return kit.fail(path .. ".site.castWater", "cast point does not face the water from the bank")
    end
    local cx, cy = canoe.x - spawn.x, canoe.y - spawn.y
    local distance = cx * cx + cy * cy
    if distance == 0 or distance > CANOE_RADIUS_SQUARED or cx * dx + cy * dy > 0
        or cx % 1 ~= 0 or cy % 1 ~= 0 then
        return kit.fail(path .. ".site.canoePost", "canoe tree is beyond the bank")
    end
    if story.canoePlaced ~= nil and type(story.canoePlaced) ~= "boolean" then
        return kit.fail(path .. ".canoePlaced", "invalid canoe receipt")
    end
    local previous = spawn
    local seen = { [kit.positionKey(spawn)] = true }
    local valid, reason = kit.positions(site.bankEscape, path .. ".site.bankEscape", ESCAPE_STEPS, ESCAPE_STEPS, {
        seen = seen, duplicate = "duplicate bank escape step",
        accept = function(position, stepPath)
            local px, py = position.x - spawn.x, position.y - spawn.y
            if position.z ~= 0 or math.abs(position.x - previous.x) + math.abs(position.y - previous.y) ~= 1
                or px * dx + py * dy > 0 then return kit.fail(stepPath, "escape step leaves dry inland route") end
            previous = position
            return true
        end,
    })
    if not valid then return false, reason end
    if (previous.x - spawn.x) * dx + (previous.y - spawn.y) * dy > -(ESCAPE_STEPS - 1) then
        return kit.fail(path .. ".site.bankEscape", "escape path must reach inland")
    end
    return true
end

Bank.storyRules = {
    siteKind = "fishing_bank",
    siteFields = {
        { field = "castWater", depth = 2, position = true, required = true },
        { field = "canoePost", depth = 2, position = true, required = true },
        { field = "bankEscape", depth = 3, count = 24, required = true },
    },
    claims = { castWater = true, canoePost = true, bankEscape = true },
    acceptSite = function(site)
        local cast = currentCast(site)
        if not cast or not riverWater(cast) or not matureTree(squareAt(site.canoePost))
            or type(site.bankEscape) ~= "table" or #site.bankEscape ~= ESCAPE_STEPS then
            return false, "wade_bank_changed"
        end
        local previous = squareAt(cast.bank)
        for _, position in ipairs(site.bankEscape) do
            local square = squareAt(position)
            if not clearDry(square) or not openEdge(previous, square) then return false, "wade_bank_blocked" end
            previous = square
        end
        return true
    end,
    validate = validate,
}

return Bank
