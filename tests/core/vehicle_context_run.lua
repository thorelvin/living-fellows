-- SPDX-License-Identifier: MIT
local T = VEHICLE_CONTEXT_TEST
local check, option = T.check, T.option
local Context = SurvivorCompanion.UIContext
local object = { getSquare = function() return T.square end }

local function open()
    local items = T.menu()
    Context.fillWorldObjectContextMenu(0, items, { object }, false)
    return items
end

-- No camp and nobody recruited nearby: a car gets no Living Fellows chores.
local plain = open()
check(not option(plain, "UI_SC_Base_RefuelFromBase")
        and not option(plain, "UI_SC_Base_InflateTires")
        and not option(plain, "UI_SC_Base_WashCar"),
    "a car the camp cannot reach lists no greyed-out camp chores")
check(not option(plain, "UI_SC_Vehicle_CommandFollowCar"),
    "no follow-car submenu without a recruited companion nearby")

-- A parked car inside the camp: open chores are offered, closed ones explain.
T.refuel = { false, "car_tank_full" }
T.upkeep.inflate_tires = { true, {} }
T.upkeep.wash_vehicle = { false, "car_clean" }
local camp = open()
local refuel = option(camp, "UI_SC_Base_RefuelFromBase")
local tires = option(camp, "UI_SC_Base_InflateTires")
local wash = option(camp, "UI_SC_Base_WashCar")
check(refuel and refuel.notAvailable and refuel.toolTip
        and refuel.toolTip.description == "Sentence for car_tank_full",
    "a closed chore on a camp car is greyed out with a sentence")
check(tires and not tires.notAvailable, "an open chore on a camp car is offered")
check(wash and wash.notAvailable
        and wash.toolTip.description == "Sentence for car_clean",
    "each closed chore explains its own reason")
refuel.callback(refuel.target, unpack(refuel.args))
check(T.player.note == "UI_SC_Base_ChoreRejected",
    "a refused order reports a chore refusal, not a raw base error")

-- A generator: outside the camp it is left alone; near it, full is explained.
T.square.car, T.square.generator = nil, T.generator
T.generatorAnswer = { false, "generator_outside_base" }
check(not option(open(), "UI_SC_Base_RefuelGeneratorFromBase"),
    "a generator outside the camp lists no camp refuel")
T.generatorAnswer = { false, "generator_full" }
local fueled = option(open(), "UI_SC_Base_RefuelGeneratorFromBase")
check(fueled and fueled.notAvailable
        and fueled.toolTip.description == "Sentence for generator_full",
    "a full camp generator explains why it cannot be refueled")

-- A recruited companion nearby can be offered the wheel.
T.square.car, T.square.generator = T.car, nil
local ann = { id = "sc-ann", name = "Ann" }
T.living = { ann }
local follow = option(open(), "UI_SC_Vehicle_CommandFollowCar")
local driver = follow and follow.subMenu and option(follow.subMenu, "Ann")
check(driver and driver.notAvailable
        and driver.toolTip.description == "Sentence for car_has_no_fuel",
    "a companion who cannot take this car is shown with a sentence")

-- The progress request appears only on a radio actually equipped by the
-- primary player and uses the expedition's acknowledged radio path.
local inventory = {}
local radio = { container = inventory }
function radio:getContainer() return self.container end
function T.player:getInventory() return inventory end
T.player.getPrimaryHandItem = function() return nil end
SurvivorCompanion.GameplayUtil.instanceOf = function(item, kind)
    return item == radio and kind == "Radio"
end
local acknowledged
SurvivorCompanion.ExpeditionPrototype = {
    current = function() return { scout = {
        phase = "searching", search = {} } } end,
    sendRadioOrder = function(_, command, payload)
        acknowledged = command == "progress_report" and payload == "status"
        return true, "progress_acknowledged"
    end,
}
local unequipped = T.menu()
Context.fillRadioContextMenu(0, unequipped, { radio })
check(not option(unequipped, "UI_SC_Expedition_AskProgress"),
    "an unequipped radio cannot request a progress report")
T.player.getPrimaryHandItem = function() return radio end
local equipped = T.menu()
Context.fillRadioContextMenu(0, equipped, { radio })
local ask = option(equipped, "UI_SC_Expedition_AskProgress")
check(ask ~= nil, "the equipped radio offers Ask for progress report")
ask.callback(ask.target, unpack(ask.args))
check(acknowledged == true
        and T.player.note == "UI_SC_Expedition_ProgressAcknowledged",
    "the menu dispatches the acknowledged status request")

SC_TEST_REPORT = "VEHICLE_CONTEXT_PASS checks=" .. tostring(T.checks)
