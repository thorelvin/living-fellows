-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
SC.Factions = {
    describeLocation = function(_point)
        return { nearestStreet = { name = "Oak St", distance = 7 } }
    end,
}

local function list(values)
    local result = { values = values or {} }
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    function result:add(value) self.values[#self.values + 1] = value end
    return result
end

ArrayList = { new = function() return list() end }

local function building(x, y, x2, y2, names)
    local value = { rooms = list() }
    function value:getX() return x end
    function value:getY() return y end
    function value:getX2() return x2 end
    function value:getY2() return y2 end
    function value:getRooms() return self.rooms end
    function value:getMinLevel() return 0 end
    function value:getMaxLevel() return 1 end
    for _, name in ipairs(names) do
        value.rooms:add({ getName = function() return name end })
    end
    return value
end

local buildings = {
    building(20, 20, 30, 30, { "policestorage", "office" }),
    building(50, 20, 60, 30, { "firestorage", "garage" }),
    building(80, 20, 90, 30, { "grocery", "storage" }),
    building(100, 20, 110, 30, { "bedroom", "kitchen" }),
    building(110, 20, 120, 30, { "warehouse" }),
    building(130, 20, 140, 30, { "fossoil", "gasstore" }),
}

local grid = {}
function grid:getBuildingsIntersecting(x, y, width, height, output)
    for _, value in ipairs(buildings) do
        if value:getX() < x + width and value:getX2() > x
            and value:getY() < y + height and value:getY2() > y then
            output:add(value)
        end
    end
end
function grid:getBuildingAt(x, y, _z)
    for _, value in ipairs(buildings) do
        if x >= value:getX() and x <= value:getX2()
            and y >= value:getY() and y <= value:getY2() then
            return value
        end
    end
    return nil
end
local cell = {}
function cell:getGridSquare(x, y, _z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getRoom = function()
            if x >= 20 and x <= 30 and y >= 20 and y <= 30 then
                return { id = "seen-police-interior" }
            end
            return nil
        end,
        getRoomDef = function()
            if x >= 20 and x <= 30 and y >= 20 and y <= 30 then
                return { getName = function() return "policeoffice" end }
            end
            return nil
        end,
        isSeen = function() return x >= 20 and x <= 30
            and y >= 20 and y <= 30 end,
    }
end
local world = {
    getMetaGrid = function() return grid end,
    getCell = function() return cell end,
}
function getWorld() return world end
SC.GameplayUtil = { isSquareFree = function() return true end }
SC.Navigation = {
    findPath = function(source, destination, _options)
        if destination:getX() == 19 and destination:getY() == 25 then
            return { source, destination }
        end
        return nil
    end,
}

SC.ExpeditionPlacesFixture = {
    buildings = buildings, building = building,
    list = list, world = world, cell = cell,
}
