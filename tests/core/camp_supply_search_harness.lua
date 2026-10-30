-- SPDX-License-Identifier: MIT
-- "Missing" stops a camp job, so it has to mean the item is really not in marked
-- storage. A held container, a far shelf or a very full crate must not read as it.
local SC = SurvivorCompanion
local U, E, checks = SC.GameplayUtil, SC.Encounter, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "camp supply search " .. checks .. ": " .. message)
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
        squares[key] = value
    end
    return squares[key]
end
getCell = function()
    return { getGridSquare = function(_, x, y) return square(x, y) end }
end

local function makeItem(kind)
    return { kind = kind, getFullType = function() return kind end }
end

local function shelf(x, y, contents)
    local tile = square(x, y)
    local object = { square = tile }
    function object:getSquare() return self.square end
    function object:getX() return self.square.x end
    function object:getY() return self.square.y end
    function object:getZ() return self.square.z end
    local container = { items = contents, parent = object }
    function container:getItems() return self.items end
    function container:getParent() return self.parent end
    function object:getContainer() return container end
    tile.objects[#tile.objects + 1] = object
    return container, { x = x, y = y, z = 0, id = "storage:" .. x .. ":" .. y,
        category = "tools", container = container }
end

local rows = {}
SC.BaseLife = {
    isInside = function() return true end,
    storageRows = function() return rows end,
    resolveContainer = function(storage) return storage.container end,
    availableCount = function() return 1 end,
}
SC.Navigation = { requestAny = function() return true, "moving" end }
U.directInteractionAccess = function(_, owner)
    return false, { U.squareOf(owner) }, nil
end

local function worker(x, y)
    local value = { square = square(x, y), x = x, y = y, z = 0 }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getSquare() return self.square end
    return value
end
local function isHammer(item) return item.kind == "Base.Hammer" end
local quiet = { snapshot = { immediateCount = 0, pressure = 0 } }
local function take(actor) return E.takePlayerSupply(actor, "build_hammer", isHammer, quiet) end

local window = worker(0, 0)
check(take(window) == "missing", "an empty camp really has no hammer")

-- Far past the six tiles the ring always reads. One look must find it, every time.
local _, far = shelf(21, 13, { makeItem("Base.Hammer") })
rows = { far }
for phase = 1, 8 do
    local seeker = worker(0, 0)
    check(take(seeker) == "in_progress",
        "a hammer on a marked shelf far from the window is found on the first look, attempt " .. phase)
    E.cancelPlayerSupply(seeker)
end

-- Another worker holding the only hammer's shelf is a wait, not a shortage.
local first, second = worker(0, 0), worker(1, 0)
check(take(first) == "in_progress", "the first worker claims the shelf")
local status, reason = take(second)
check(status == "in_progress" and reason == "camp_supply_reserved",
    "a second worker waits for a shelf in use instead of reporting the hammer missing: " .. tostring(status))
E.cancelPlayerSupply(first)
check(take(second) == "in_progress", "the shelf is free once the first worker lets go")
E.cancelPlayerSupply(second)

-- A free shelf beats waiting for a held one.
local _, spare = shelf(3, 0, { makeItem("Base.Hammer") })
rows = { far, spare }
check(take(first) == "in_progress", "the first worker takes the nearest shelf")
local spareStatus = take(second)
check(spareStatus == "in_progress", "the second worker goes to the other shelf: " .. tostring(spareStatus))
E.cancelPlayerSupply(first)
E.cancelPlayerSupply(second)

-- A crate too big to read at once is not proof until all of it has been read.
local filler = {}
for index = 1, 300 do filler[index] = makeItem("Base.Nails") end
local _, crate = shelf(2, 2, filler)
rows = { crate }
local reader = worker(0, 0)
local firstLook = take(reader)
check(firstLook == "in_progress", "the first slice of a full crate proves nothing yet: " .. tostring(firstLook))
check(take(reader) == "missing", "once the whole crate has been read the hammer really is missing")
filler[#filler + 1] = makeItem("Base.Hammer")
take(reader)
check(take(reader) == "in_progress" and reader ~= nil,
    "a hammer at the bottom of a full crate is found on the next slice")
E.cancelPlayerSupply(reader)

SC_TEST_REPORT = "CAMP_SUPPLY_SEARCH_PASS checks=" .. checks
