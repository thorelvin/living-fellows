-- SPDX-License-Identifier: MIT
-- Exercise the real world context hook on a clicked car and generator: camp
-- chores appear only where the camp can reach, the follow-car submenu only
-- when someone could take the wheel, and every refusal reads as a sentence.
require = function() return true end

local function menu()
    local result = { options = {} }
    function result:addOption(label, target, callback, ...)
        local option = { label = label, target = target, callback = callback,
            args = { ... } }
        self.options[#self.options + 1] = option
        return option
    end
    result.addOptionOnTop = result.addOption
    function result:addSubMenu(option, subMenu) option.subMenu = subMenu end
    return result
end
local function option(items, label)
    for _, entry in ipairs(items.options) do
        if entry.label == label then return entry end
    end
    return nil
end
VEHICLE_CONTEXT_TEST = { menu = menu, option = option, checks = 0 }
function VEHICLE_CONTEXT_TEST.check(value, label)
    VEHICLE_CONTEXT_TEST.checks = VEHICLE_CONTEXT_TEST.checks + 1
    if not value then
        error("vehicle context check " .. VEHICLE_CONTEXT_TEST.checks .. ": " .. label)
    end
end

ISContextMenu = { getNew = function() return menu() end }
ISWorldObjectContextMenu = {}
ISInventoryPaneContextMenu = {}
ISToolTip = {}
function ISToolTip:new() return { initialise = function() end, setVisible = function() end } end
getText = function(key) return key end

local T = VEHICLE_CONTEXT_TEST
local car = { sqlId = 12 }
function car:getSqlId() return self.sqlId end
local generator = {}
local square = { car = car }
function square:getVehicleContainer() return self.car end
function square:getGenerator() return self.generator end
T.car, T.generator, T.square = car, generator, square
local player = { note = nil }
function player:getVehicle() return nil end
function player:setHaloNote(note) self.note = note end
T.player = player
getSpecificPlayer = function(index) return index == 0 and player or nil end

-- Chore and follow-car answers are set per scenario by the run file.
T.refuel = { false, "base_missing" }
T.upkeep = { inflate_tires = { false, "base_missing" }, wash_vehicle = { false, "base_missing" } }
T.generatorAnswer = { false, "base_missing" }
T.preflight = { nil, "car_has_no_fuel" }
T.living = {}

SurvivorCompanion = {
    GameplayUtil = {
        isZombie = function() return false end,
        instanceOf = function() return false end,
    },
    UI = {
        baseFailureReason = function(reason) return "Sentence for " .. tostring(reason) end,
    },
    Registry = {
        living = function() return T.living end,
        byId = function(id)
            for _, actor in ipairs(T.living) do
                if actor.id == id then return { actor = actor, recruited = true } end
            end
            return nil
        end,
    },
    Commands = {
        peek = function() return { recruited = true, order = "follow" } end,
        issue = function() return false, "car_has_no_fuel" end,
    },
    Convoy = {
        preflight = function() return T.preflight[1], T.preflight[2] end,
    },
    VehicleRefuel = {
        eligible = function(vehicle) return T.refuel[1], T.refuel[2] end,
        queue = function() return false, "car_tank_full" end,
    },
    VehicleUpkeep = {
        eligible = function(kind) return T.upkeep[kind][1], T.upkeep[kind][2] end,
        queue = function() return true end,
    },
    GeneratorRefuel = {
        eligible = function() return T.generatorAnswer[1], T.generatorAnswer[2] end,
        queue = function() return true end,
    },
}
SurvivorCompanion.UI.describeEntry = function(entry)
    return { id = entry.id, name = entry.name, recruited = true, distance = 2 }
end
