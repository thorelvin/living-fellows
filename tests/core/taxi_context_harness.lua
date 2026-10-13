-- SPDX-License-Identifier: MIT
-- Exercise the actual world and inventory context hooks with a boarded fare.
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
local function check(value, label)
    if not value then error("taxi context: " .. label) end
end

ISContextMenu = { getNew = function() return menu() end }
ISWorldObjectContextMenu = {}
ISInventoryPaneContextMenu = {}
getText = function(key) return key end

local car = {}
local inventory = {}
local player = { car = car, note = nil }
function player:getVehicle() return self.car end
function player:getInventory() return inventory end
function player:setHaloNote(note) self.note = note end
getSpecificPlayer = function(index) return index == 0 and player or nil end
local radio = { container = inventory }
function radio:getContainer() return self.container end
local fareItem = {}
function fareItem:getDisplayName() return "Gold Ring" end

local departCount, offerCount = 0, 0
local phase = "ready_to_depart"
SurvivorCompanion = {
    GameplayUtil = {
        isZombie = function() return false end,
        instanceOf = function(item, class)
            return item == radio and class == "Radio"
        end,
    },
    TaxiBooking = {
        dispatchReady = true,
        checkRadio = function(_, candidate)
            return candidate == radio
        end,
    },
    TaxiService = {
        current = function() return { phase = phase } end,
        isBookedPassenger = function(actor, vehicle)
            return actor == player and vehicle == car
        end,
        destinations = function(actor, candidate)
            check(actor == player and (candidate == radio or candidate == nil),
                "destination caller")
            return { { id = "base", name = "Home", required = 3 } }
        end,
        depart = function(actor, candidate, destination)
            check(actor == player and (candidate == radio or candidate == nil)
                and destination == "base", "departure parameters")
            departCount = departCount + 1
            return true, "taxi_departed"
        end,
        offer = function(actor, candidate, item)
            check(actor == player and (candidate == radio or candidate == nil)
                and item == fareItem, "fare parameters")
            offerCount = offerCount + 1
            return true, "fare_offered"
        end,
    },
    TaxiCab = {
        looseItems = function(vehicle)
            check(vehicle == car, "fare car")
            return { { item = fareItem, itemType = "Base.GoldRing" } }
        end,
        recover = function() return true, car end,
    },
    TaxiFares = { valueFor = function(item)
        return item == fareItem and 3 or nil
    end },
}

function TaxiContextRun()
local square = { getVehicleContainer = function() return car end }
local object = { getSquare = function() return square end }
local worldMenu = menu()
SurvivorCompanion.UIContext.fillWorldObjectContextMenu(0, worldMenu,
    { object }, false)
local taxi = option(worldMenu, "UI_SC_Taxi_Menu")
check(taxi and taxi.subMenu, "boarded world menu")
check(not option(taxi.subMenu, "UI_SC_Taxi_Status"),
    "hide location request after boarding")
local destination = option(taxi.subMenu, "UI_SC_Taxi_DriveTo")
local fare = option(taxi.subMenu, "UI_SC_Taxi_Offer")
check(destination and fare and option(taxi.subMenu, "UI_SC_Taxi_MapHint"),
    "world menu includes map, destination and fare")
destination.callback(destination.target, unpack(destination.args))
fare.callback(fare.target, unpack(fare.args))
check(departCount == 1 and offerCount == 1,
    "in-car actions work without a radio")

local radioMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0, radioMenu, { radio })
local radioTaxi = option(radioMenu, "UI_SC_Taxi_Menu")
check(radioTaxi and radioTaxi.subMenu, "boarded radio menu")
check(not option(radioTaxi.subMenu, "UI_SC_Taxi_Status"),
    "hide location request in boarded radio menu")
check(option(radioTaxi.subMenu, "UI_SC_Taxi_DriveTo")
    and option(radioTaxi.subMenu, "UI_SC_Taxi_Offer"),
    "radio keeps destination and fare")

phase = "in_transit"
local ridingMenu = menu()
SurvivorCompanion.UIContext.fillRadioContextMenu(0, ridingMenu, { radio })
check(not option(ridingMenu, "UI_SC_Taxi_Menu"),
    "in-transit radio does not leave an empty taxi submenu")

player.car = nil
local walkingMenu = menu()
SurvivorCompanion.UIContext.fillWorldObjectContextMenu(0, walkingMenu,
    { object }, false)
check(not option(walkingMenu, "UI_SC_Taxi_Menu"),
    "in-car menu unavailable outside cab")

print("taxi context harness passed")
end
