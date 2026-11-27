-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Bank = SC.OddballWadeBank
local anchorX, anchorY = 6402, 6416
local grid, cell = {}, {}
local depth, closed, claimed = 6, false, false
local nearShoreUnloaded, sparseWood = false, false
local zoneType, forestLimitX
local function tree(name, size)
    return { getSize = function() return size end,
        getSprite = function() return { getName = function() return name end } end }
end
local defaultTree = tree("e_virginiapine_1", 5)
local snagTree = tree("e_riverbirchJUMBO_1", 7)

local function square(x, y, z)
    if z ~= 0 then return nil end
    if nearShoreUnloaded and x == anchorX - 6 and y == anchorY + 3 then return nil end
    local key = tostring(x) .. ":" .. y
    if grid[key] then return grid[key] end
    local value = { x = x, y = y, z = z, objects = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:isOutside() return true end
    function value:isCanSee() return self.seen == true end
    function value:getBuilding() return self.building end
    function value:getFloor()
        local name = self.floor
        return name and { getSprite = function() return { getName = function() return name end } end }
    end
    function value:getZone()
        if zoneType and (not forestLimitX or self.x <= forestLimitX) then
            return { getType = function() return zoneType end }
        end
    end
    function value:getTree()
        if self.tree ~= nil then return self.tree or nil end
        if self.x == anchorX - 1 and self.y == anchorY + 3 then return snagTree end
        if not sparseWood and (anchorX - self.x) % 3 == 0 and self.x < anchorX and self.y ~= anchorY then
            return defaultTree
        end
    end
    function value:AddTileObject(object) self.objects[#self.objects + 1] = object end
    function value:RemoveTileObject(object)
        for index, existing in ipairs(self.objects) do
            if existing == object then table.remove(self.objects, index) break end
        end
    end
    grid[key] = value
    return value
end

local function read(object, method, ...)
    if object and object[method] then return object[method](object, ...), true end
    return nil, false
end
SC.GameplayUtil = {
    gridSquare = square,
    loadedSquare = function(pos) return square(pos.x, pos.y, pos.z) end,
    call = read,
    nowMs = function() return 0 end,
    canSee = function(_, value) return value.seen end,
    isSquareFree = function(value) return value:getTree() == nil end,
    isClearActorSpawnSquare = function(value) return value:getTree() == nil end,
    safehouseBlocker = function() return false end,
    modData = function(object) return object.data end,
    squareObjects = function(value, callback) for _, object in ipairs(value.objects) do callback(object) end end,
    cell = function() return cell end,
}
SC.Topology = {
    squareIsWater = function(value) return value.x > anchorX and value.x <= anchorX + depth end,
    classifyEdge = function(_, from, to)
        local isOpen = not closed and math.abs(from.x - to.x) + math.abs(from.y - to.y) == 1
        return { traversable = isOpen, affordance = isOpen and "open" or "blocked" }
    end,
}
SC.Factions = { atPosition = function() return claimed and {} or nil end }
local player = { getPlayerNum = function() return 0 end }
local shore = square(anchorX, anchorY, 0)
local site = assert(Bank.siteFor(shore, player, false), "a wooded fishable bank has a dry escape and canoe tree")
assert(site.canoePost.x == anchorX - 1 and site.canoePost.y == anchorY + 3,
    "a real mature broadleaf carries the canoe on the dry side")
assert(#site.bankEscape == 4 and site.bankEscape[4].x == anchorX - 4
    and Bank.storyRules.acceptSite(site), "fresh dry escape reaches four metres into the woods")
nearShoreUnloaded, zoneType = true, "TownZone"
assert(Bank.siteFor(shore, player, false),
    "real woods pass with one survey tile unloaded and a broad town zone label")
nearShoreUnloaded, zoneType = false, nil
local ground = square(anchorX - 2, anchorY + 1, 0)
ground.floor = "blends_street_01_0"
assert(Bank.siteFor(shore, player, false) == nil, "actual paving near the bank rules out seclusion")
ground.floor, ground.building = nil, {}
assert(Bank.siteFor(shore, player, false) == nil, "a nearby native building rules out seclusion")
ground.building, sparseWood, zoneType = nil, true, "Forest"
assert(Bank.siteFor(shore, player, false) == nil, "a forest label and one physical tree are insufficient")
ground.tree = tree("e_virginiapine_1", 2)
local nearPost = square(anchorX - 1, anchorY + 3, 0)
local farPost = square(anchorX - 8, anchorY + 2, 0)
nearPost.tree, farPost.tree, forestLimitX = false, snagTree, anchorX - 8
assert(Bank.siteFor(shore, player, false) == nil, "two physical trees need forest across at least half the survey")
forestLimitX = nil
local farSite = assert(Bank.siteFor(shore, player, false), "native forest and two physical trees supply woodland")
assert(farSite.canoePost.x == farPost.x and farSite.canoePost.y == farPost.y
    and farSite.house.bounds.x1 <= farPost.x and Bank.storyRules.acceptSite(farSite),
    "a mature canoe tree eight metres inland fits the site bounds and final check")
local validation = {
    fail = function(_, message) return false, message end,
    positionKey = function(position) return position.x .. ":" .. position.y end,
    positions = function(list, path, _, _, options)
        for _, position in ipairs(list) do
            local valid, reason = options.accept(position, path)
            if not valid then return false, reason end
        end
        return true
    end,
}
assert(Bank.storyRules.validate({ site = farSite }, "wade", validation), "saved sites accept the farther canoe tree")
farSite.canoePost = { x = anchorX - 11, y = anchorY, z = 0 }
assert(not Bank.storyRules.validate({ site = farSite }, "wade", validation), "saved sites reject an unduly remote canoe")
nearPost.tree, farPost.tree, ground.tree, sparseWood, zoneType = nil, nil, nil, false, nil
depth = 2
assert(Bank.siteFor(shore, player, false) == nil, "a shallow decorative pool never supplies the encounter")
depth, closed = 6, true
assert(Bank.siteFor(shore, player, false) == nil and not Bank.storyRules.acceptSite(site),
    "a blocked escape rejects both scanning and final placement")
closed, claimed = false, true
assert(Bank.siteFor(shore, player, false) == nil, "a faction's bank remains reserved")
claimed, shore.seen = false, true
assert(Bank.siteFor(shore, player, false) == nil and Bank.siteFor(shore, player, true),
    "visible placement is allowed only by the explicit debug route")
shore.seen = false

IsoDirections = { N = {} }
local sprite = { getTextureForCurrentFrame = function() return {} end,
    getName = function(self) return self.name end,
    setName = function(self, name) self.name = name end }
getSprite = function(name)
    assert(name == "media/textures/World/LFWadeCanoeY.png")
    return sprite
end
local spawned = 0
IsoObject = { new = function(_, value, texture)
    spawned = spawned + 1
    return { data = {}, visual = texture,
        setName = function() end,
        getSprite = function(self) return self.visual end,
        setSprite = function(self, nextVisual) self.visual = nextVisual end,
        getRenderYOffset = function(self) return self.lift or 0 end,
        setRenderYOffset = function(self, lift) self.lift = lift end }
end }
local group = { id = "wade-test", oddball = { site = site } }
local post = square(site.canoePost.x, site.canoePost.y, 0)
assert(Bank.onSpawn(group) and group.oddball.canoePlaced and spawned == 1
    and post.objects[1]:getRenderYOffset() > 35 and Bank.castSite(group),
    "first load places one lifted canoe and preserves the separate water target")
post.objects[1].visual = nil
assert(Bank.onSpawn(group) and spawned == 1 and post.objects[1].visual == sprite,
    "a saved blank world object gets the same visual without a duplicate")
post.tree = false
assert(Bank.onSpawn(group) and #post.objects == 0 and spawned == 1,
    "chopping the tree drops the exact owned decoration from the scene")
post.tree = snagTree
assert(Bank.onSpawn(group) and #post.objects == 0 and Bank.castSite(group),
    "a lost canoe remains advisory without blocking Wade's actual fishing")
