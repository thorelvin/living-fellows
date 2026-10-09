-- SPDX-License-Identifier: MIT
-- Server authority for Walt Reed's campfire. The client only requests a
-- placement; vanilla SCampfireSystem owns the real persistent world object.

if type(isClient) == "function" and isClient() == true then return end

SCStoryCampfireServer = SCStoryCampfireServer or {}
local Server = SCStoryCampfireServer
local MODULE = "LivingFellowsCampStory"
local SCENE = "survivalist05_mid_storyteller"
local STORE = "LivingFellowsStoryCampfire"

local function call(object, method, ...)
    if not object then return nil, false end
    local okay, fn = pcall(function() return object[method] end)
    if not okay or type(fn) ~= "function" then return nil, false end
    local invoked, value = pcall(fn, object, ...)
    return invoked and value or nil, invoked
end

local function integer(value, limit)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge
        or math.abs(value) > limit or math.floor(value) ~= value then
        return nil
    end
    return value
end

local function naturalFloor(square)
    local floor = select(1, call(square, "getFloor"))
    local sprite = select(1, call(floor, "getSprite"))
    local name = select(1, call(sprite, "getName"))
    name = type(name) == "string" and string.lower(name) or ""
    return string.find(name, "blends_natural", 1, true) ~= nil
        or string.find(name, "blends_grass", 1, true) ~= nil
        or string.find(name, "blends_forest", 1, true) ~= nil
        or string.find(name, "vegetation", 1, true) ~= nil
end

local function outside(square)
    return square and select(1, call(square, "getRoom")) == nil
        and select(1, call(square, "getBuilding")) == nil
        and select(1, call(square, "isOutside")) == true
end

local function safe(square)
    return outside(square) and naturalFloor(square)
        and select(1, call(square, "getTree")) == nil
        and select(1, call(square, "isSolid")) ~= true
        and select(1, call(square, "isSolidTrans")) ~= true
        and select(1, call(square, "TreatAsSolidFloor")) == true
        and select(1, call(square, "isFree", true)) == true
        and select(1, call(square, "isSafeToSpawn")) == true
end

local function wooded(cell, x, y)
    local trees = 0
    for dx = -5, 5, 2 do
        for dy = -5, 5, 2 do
            local tile = select(1, call(cell, "getGridSquare", x + dx,
                y + dy, 0))
            if tile and select(1, call(tile, "getTree")) then
                trees = trees + 1
            end
        end
    end
    if trees < 8 then return false end
    for _, offset in ipairs({ { 2, 0 }, { 0, 2 }, { -2, 0 },
        { 0, -2 } }) do
        local stand = select(1, call(cell, "getGridSquare",
            x + offset[1], y + offset[2], 0))
        local mid = select(1, call(cell, "getGridSquare",
            x + offset[1] / 2, y + offset[2] / 2, 0))
        if safe(stand) and safe(mid) then return true end
    end
    return false
end

local function ledger()
    if type(ModData) ~= "table"
        or type(ModData.getOrCreate) ~= "function" then return nil end
    local okay, value = pcall(ModData.getOrCreate, STORE)
    return okay and type(value) == "table" and value or nil
end

local function system()
    if SCampfireSystem and SCampfireSystem.instance then
        return SCampfireSystem.instance
    end
    if type(require) == "function" then
        pcall(require, "Camping/SCampfireSystem")
    end
    return SCampfireSystem and SCampfireSystem.instance or nil
end

function Server.place(player, args)
    if type(args) ~= "table" or args.scene ~= SCENE
        or type(args.groupId) ~= "string"
        or not args.groupId:match("^faction%-oddball%-%d+%-%d+$") then
        return false, "invalid_scene"
    end
    local x, y, z = integer(args.x, 30000), integer(args.y, 30000),
        integer(args.z, 8)
    if not x or not y or z ~= 0 then return false, "invalid_position" end
    local state = ledger()
    if not state then return false, "campfire_ledger_unavailable" end
    if state.groupId then
        if state.groupId == args.groupId and state.x == x and state.y == y then
            return true, "already_handled"
        end
        return false, "another_story_camp_exists"
    end
    local px = select(1, call(player, "getX"))
    local py = select(1, call(player, "getY"))
    local pz = select(1, call(player, "getZ"))
    if type(px) ~= "number" or type(py) ~= "number"
        or type(pz) ~= "number" or math.floor(pz) ~= 0
        or (px - x) ^ 2 + (py - y) ^ 2 > 1024 * 1024 then
        return false, "sender_too_far"
    end
    local cell = type(getCell) == "function" and getCell() or nil
    local square = select(1, call(cell, "getGridSquare", x, y, z))
    if not square then return false, "square_unloaded" end
    local fires = system()
    if not fires then return false, "campfire_system_unavailable" end
    local fire = select(1, call(fires, "getLuaObjectOnSquare", square))
    if not fire then
        if not safe(square) or not wooded(cell, x, y) then
            return false, "forest_clearing_invalid"
        end
        fire = select(1, call(fires, "addCampfire", square))
        if not fire then return false, "campfire_placement_failed" end
        local _, fueled = call(fire, "addFuel", 180)
        if fueled then call(fire, "lightFire") end
    end
    state.groupId, state.x, state.y, state.z = args.groupId, x, y, z
    return true, "campfire_placed"
end

function Server.onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= "place" then return end
    Server.place(player, args)
end

-- Server Lua sits outside the client bootstrap, which cannot require it, so
-- this registers itself the way vanilla server systems do. Replace any earlier
-- handler so loading the file again never leaves two placing campfires.
function Server.register()
    local event = Events and Events.OnClientCommand
    if not event or type(event.Add) ~= "function" then return false end
    if Server.registeredHandler and type(event.Remove) == "function" then
        pcall(event.Remove, Server.registeredHandler)
    end
    event.Add(Server.onClientCommand)
    Server.registeredHandler = Server.onClientCommand
    return true
end

Server.register()

return Server
