-- SPDX-License-Identifier: MIT
-- One bed is one claim, whichever of its tiles a worker's survey found first.
local SC = SurvivorCompanion
local G, checks = SC.BedGeometry, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "bed segments " .. checks .. ": " .. message)
end

local squares = {}
local function square(x, y)
    local key = x .. ":" .. y
    if not squares[key] then
        local value = { x = x, y = y, z = 0, objects = {}, moving = {} }
        function value:getX() return self.x end
        function value:getY() return self.y end
        function value:getZ() return self.z end
        function value:getObjects() return self.objects end
        function value:getMovingObjects() return self.moving end
        function value:getRoom() return nil end
        squares[key] = value
    end
    return squares[key]
end
getCell = function()
    return { getGridSquare = function(_, x, y) return squares[x .. ":" .. y] end }
end

-- Native grids belong to the furniture type, so two placed beds share this one.
local grid = {}
function grid:getSpriteGridPosX(sprite) return sprite.gx end
function grid:getSpriteGridPosY(sprite) return sprite.gy end
function grid:getWidth() return 1 end
function grid:getHeight() return 2 end
local function segment(x, y, gy)
    local tile = square(x, y)
    local sprite = { gx = 0, gy = gy }
    function sprite:getSpriteGrid() return grid end
    function sprite:getName() return "furniture_bedding_01_" .. gy end
    function sprite:getProperties()
        return { get = function(_, key)
            return key == "BedType" and "goodBed" or key == "CustomName" and "Bed" or nil
        end }
    end
    local object = { square = tile, sprite = sprite }
    function object:getSquare() return self.square end
    function object:getSprite() return self.sprite end
    tile.objects[#tile.objects + 1] = object
    return object
end

local head, foot = segment(5, 5, 0), segment(5, 6, 1)
local otherHead, otherFoot = segment(5, 7, 0), segment(5, 8, 1)
local function has(list, value)
    for _, candidate in ipairs(list) do if candidate == value then return true end end
    return false
end

for _, tile in ipairs({ head, foot }) do
    local found = G.segments(tile)
    check(#found == 2 and has(found, head) and has(found, foot),
        "either tile of a bed finds both of its tiles")
    check(not has(found, otherHead) and not has(found, otherFoot),
        "an identical bed placed next to it stays a separate bed")
end
local lone = { square = square(9, 9) }
function lone:getSquare() return self.square end
check(#G.segments(lone) == 1 and G.segments(lone)[1] == lone,
    "furniture without a grid is its own only segment")

local me, sleeper = {}, {}
function sleeper:isOnBed() return true end
function me:isOnBed() return true end
check(G.occupant(foot, me) == nil, "an empty bed has no occupant")
square(5, 5).moving[1] = me
check(G.occupant(foot, me) == nil, "a worker does not count as occupying its own bed")
square(5, 5).moving[1] = sleeper
check(G.occupant(foot, me) == sleeper and G.occupant(head, me) == sleeper,
    "a body lying on one tile occupies the bed from the other tile too")
check(G.occupant(otherFoot, me) == nil, "a body in the neighbouring bed does not block this one")
local stander = {}
function stander:isOnBed() return false end
square(5, 5).moving[1] = stander
check(G.occupant(foot, me) == nil, "someone merely standing on the tile is not lying in the bed")
square(5, 5).moving[1] = nil

-- Downtime reserves the whole bed. A second worker cannot take the other half.
local furnitureKind, _, _, _, _, _, _, _, _, reserve, release, stateFor, _, reserveActivity, freeAccess,
    releaseActivity = SC.Downtime._furnitureForTests()
local first, second = {}, {}
local activity = { kind = "rest_bed", object = head }
check(reserveActivity(first, activity, 1000) == true, "the first worker reserves the bed")
check(reserve(foot, second, 1000) == false,
    "the other half of a reserved bed cannot be reserved by a second worker")
check(reserveActivity(second, { kind = "rest_bed", object = foot }, 1000) == false,
    "a second worker's bed activity on the other half is refused")
check(reserve(otherHead, second, 1000) == true, "the neighbouring bed remains free")
release(otherHead, second)

local third = {}
check(reserveActivity(third, { kind = "rest_bed", object = head }, 1000) == false,
    "the first worker's own tile stays refused too")
check(activity.bedSegments and #activity.bedSegments == 1 and activity.bedSegments[1] == foot,
    "the activity records the other tile so it can be released")
stateFor(first).active = activity
check(reserve(foot, second, 1000 + 86400000) == false,
    "a night's sleep outlasts the lease and the sleeper still holds the whole bed")
stateFor(first).active = nil
releaseActivity(first, activity)
check(reserve(foot, second, 1000) == true, "releasing the activity frees the whole bed")
release(foot, second)

-- A sleeper the reservations cannot see, such as the player, still closes the bed.
SeatingManager = { getInstance = function()
    return { getFacingDirection = function() return "N" end }
end }
square(5, 5).moving[1] = sleeper
local reached, targets, why = freeAccess(me, foot)
check(reached == false and #targets == 0 and why == "seat_spot_busy",
    "a bed with someone lying on its other tile offers no way in")
square(5, 5).moving[1] = nil
check(furnitureKind ~= nil, "the furniture test hooks are available")

SC_TEST_REPORT = "BED_SEGMENTS_PASS checks=" .. checks
