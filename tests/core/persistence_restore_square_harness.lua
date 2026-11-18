-- SPDX-License-Identifier: MIT
-- A blocked saved tile is replaced by a free tile in the same kind of place:
-- outdoors for an outdoor origin, the same room or building for an indoor one.
local SC = SurvivorCompanion
local nearby = assert(SC.Persistence._nearbyRestoreSquareForTests, 'restore square test hook')
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'check ' .. tostring(checks) .. ': ' .. message)
end

local houseA, houseB = { name = 'A' }, { name = 'B' }
local kitchen = { getBuilding = function() return houseA end }
local hall = { getBuilding = function() return houseA end }
local neighbour = { getBuilding = function() return houseB end }
local grid = {}
local cell = { getGridSquare = function(_, x, y, z) return grid[x .. ':' .. y .. ':' .. z] end }
local function square(x, y, room, free)
    local value = {
        getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
        getCell = function() return cell end, getChunk = function() return {} end,
        isSolid = function() return false end, isSolidTrans = function() return false end,
        TreatAsSolidFloor = function() return true end, isFree = function() return free end,
        isSafeToSpawn = function() return true end, getRoom = function() return room end,
        label = tostring(x) .. ',' .. tostring(y),
    }
    grid[x .. ':' .. y .. ':0'] = value
    return value
end
local function label(value) return value and value.label or 'nil' end

-- Ring one is scanned from (-1,-1); the first free tile there is indoors.
grid = {}
local street = square(10, 10, nil, false)
square(9, 9, neighbour, true)
local pavement = square(11, 11, nil, true)
local chosen = nearby(street)
check(chosen == pavement, 'a blocked outdoor tile stays outdoors, not inside the next house: ' .. label(chosen))

grid = {}
local stove = square(10, 10, kitchen, false)
square(9, 9, neighbour, true)
local doorway = square(8, 8, hall, true)
chosen = nearby(stove)
check(chosen == doorway, 'a blocked indoor tile stays in its own building, not the closer neighbour: ' .. label(chosen))

grid = {}
stove = square(10, 10, kitchen, false)
square(9, 9, nil, true)
local counter = square(8, 8, kitchen, true)
chosen = nearby(stove)
check(chosen == counter, 'an indoor origin prefers its own room over the yard outside: ' .. label(chosen))

grid = {}
street = square(10, 10, nil, false)
local onlyRoom = square(11, 10, neighbour, true)
chosen = nearby(street)
check(chosen == onlyRoom, 'with no free tile outdoors the nearest free tile still restores: ' .. label(chosen))

grid = {}
local open = square(10, 10, nil, true)
check(nearby(open) == open, 'a free saved tile is used exactly')

print('PERSISTENCE_RESTORE_SQUARE_KAHLUA_PASS checks=' .. checks)
