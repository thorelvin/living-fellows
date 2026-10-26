-- SPDX-License-Identifier: MIT
-- The camp computer entry rides on the world-object menu. This fixture's
-- roster is empty, which is the early-return path, so it also proves the
-- entry is offered on menus with nothing else of ours on them, and that a
-- failing terminal cannot take the rest of the menu down.
local T, SC = MEDICAL_CONTEXT_TEST, SurvivorCompanion
local Context = SC.UIContext
local check = T.check

local calls = {}
SC.Terminal = { fillWorldObjectContextMenu = function(playerIndex, context, worldObjects, player)
    calls[#calls + 1] = { playerIndex = playerIndex, context = context, worldObjects = worldObjects,
        player = player }
    context:addOption("Use computer", player, function() end)
    return true
end }
local computer = { getSquare = function() return T.square(20, 20) end }
local menu = T.menu()
Context.fillWorldObjectContextMenu(0, menu, { computer }, false)
check(#calls == 1 and calls[1].playerIndex == 0 and calls[1].context == menu
    and calls[1].worldObjects[1] == computer and calls[1].player == T.doctor,
    "the computer hook gets the menu, the clicked objects and the player")
check(menu:getOptionFromName("Use computer") ~= nil,
    "the computer entry survives the empty-roster early return")

calls = {}
Context.fillWorldObjectContextMenu(0, T.menu(), { computer }, true)
check(#calls == 0, "a menu test pass never builds the computer entry")

local reports = {}
SC.Diagnostics = { report = function(area, actor, message, detail)
    reports[#reports + 1] = { area = area, message = message, detail = tostring(detail) }
end }
SC.Terminal.fillWorldObjectContextMenu = function() error("injected terminal failure") end
local failingMenu = T.menu()
local ok = pcall(Context.fillWorldObjectContextMenu, 0, failingMenu, { computer }, false)
check(ok and #reports == 1 and reports[1].area == "terminal"
    and string.find(reports[1].detail, "injected terminal failure", 1, true) ~= nil,
    "a failing computer entry is reported and the menu carries on")
SC.Terminal, SC.Diagnostics = nil, nil
ok = pcall(Context.fillWorldObjectContextMenu, 0, T.menu(), { computer }, false)
check(ok, "the menu works without the terminal module")

SC_TEST_REPORT = "Camp computer menu hook: " .. T.checks .. " checks passed"
