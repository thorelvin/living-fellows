-- SPDX-License-Identifier: MIT
-- Run after the native SCUIContext/medical context fixture. Exercise the real
-- car submenu without allowing a candidate scan or route plan in construction.
local T, SC = MEDICAL_CONTEXT_TEST, SurvivorCompanion
local previous = { registry = SC.Registry, commands = SC.Commands, home = SC.HomeTrip,
    homeUi = SC.UIHomeTrip, car = SC.ExpeditionCar, text = SC.UI.text,
    getNew = ISContextMenu.getNew }
local records, actors, opened, checks = {}, {}, nil, 0
for index = 1, 5 do
    local id = "car-home-" .. index
    local actor = T.actor(id, "Car crew " .. index, 20 + index, 0, false)
    function actor:getModData() return { SC_Id = self.id } end
    function actor:getFullName() return self.name end
    actor.state = { group = "alpha", order = index <= 3 and "follow" or "stay" }
    local record = { id = id, actor = actor, recruited = true, name = actor.name }
    actors[#actors + 1], records[id] = actor, record
end
local vehicle = { getX = function() return 0 end, getY = function() return 0 end,
    getSqlId = function() return 777 end }
SC.Registry = { living = function() return actors end, byId = function(id) return records[id] end }
SC.Commands = { peek = function(actor) return actor.state end,
    peekExisting = function(actor) return actor.state end }
SC.UI.text = function(key, name, count)
    if key == "UI_SC_HomeTrip_GroupCount" then return name .. " (" .. count .. ")" end
    if key == "UI_SC_Select_GroupAlpha" then return "Alpha" end
    return key
end
local blocker
SC.HomeTrip = { eligibility = function(selection)
    checks = checks + 1
    local result = { records = {} }
    for _, record in ipairs(selection.records or { selection.record }) do
        if record.actor.state.order == "follow" then result.records[#result.records + 1] = record end
    end
    result.leaderId = result.records[1] and result.records[1].id
    result.blocker, result.canStart = blocker, blocker == nil
    return result
end, reasonText = function() return "You are in this car. Get out first." end,
    draft = function() error("car context must not plan a route") end }
SC.ExpeditionCar = { displayName = function() return "Estate" end,
    fieldCandidates = function() error("car context must not scan candidate cars") end,
    preflightField = function() error("car context must not preflight a route") end }
SC.UIHomeTrip = { openSheet = function(selection) opened = selection return true end }
local function menu()
    local result = T.menu()
    function result:addSubMenu(option, submenu) option.subMenu = submenu end
    return result
end
ISContextMenu.getNew = function() return menu() end

local root = menu()
local submenu = SC.UIContext.addHomeTripCarMenu(root, vehicle, T.doctor)
assert(submenu and #root.options == 1 and #submenu.options == 4 and checks == 4,
    "a right-click car lists followers out to 30 m plus their actual eligible group without route planning")
assert(submenu.options[4].name == "Alpha (3)",
    "a five-person group lists its three travelling followers rather than the parked members")
local option = submenu.options[4]
option.onSelect(option.target, option.param1)
assert(opened and opened.group == "alpha" and opened.travelMode == "drive"
    and opened.vehicle == vehicle and opened.vehicleSqlId == 777
    and opened.vehicleName == "Estate" and opened.leaderId == actors[1].id,
    "car group action opens the common sheet with the exact clicked car and chosen leader")

opened, blocker = nil, "player_car"
root = menu()
submenu = SC.UIContext.addHomeTripCarMenu(root, vehicle, T.doctor)
assert((submenu.options[1].notAvailable or submenu.options[1].isDisabled) and submenu.options[1].toolTip
    and submenu.options[1].toolTip.description == "You are in this car. Get out first." and opened == nil,
    "a blocked clicked car remains visible with its readable reason and never opens a sheet during construction")
for _, actor in ipairs(actors) do actor.square.x = 31 end
root = menu()
assert(SC.UIContext.addHomeTripCarMenu(root, vehicle, T.doctor) == nil and #root.options == 0,
    "a car with no following crew within 30 m does not offer a home submenu")

SC.Registry, SC.Commands, SC.HomeTrip = previous.registry, previous.commands, previous.home
SC.UIHomeTrip, SC.ExpeditionCar, SC.UI.text = previous.homeUi, previous.car, previous.text
ISContextMenu.getNew = previous.getNew
print("HOME_TRIP_CONTEXT_PASS")
