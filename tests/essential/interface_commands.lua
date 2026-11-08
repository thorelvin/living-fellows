-- SPDX-License-Identifier: MIT
-- Click the production callback after selection changes, retaining exact payload.
local SC, UI = SurvivorCompanion, SurvivorCompanion.UI
local saved = { commands = SC.Commands, interaction = SC.Interaction, refresh = UI.refresh }
local issued = {}
SC.Commands = { issue = function(id, command, payload, player)
    issued[#issued + 1] = { id = id, command = command, payload = payload, player = player }
    return true
end }
SC.Interaction = nil
UI.refresh = function() end
ISButton = ISPanel:derive("ISButton")
function ISButton:new(x, y, width, height, title, target, onClick)
    local object = ISPanel.new(self, x, y, width, height)
    object.title, object.target, object.onClick = title, target, onClick
    return object
end
function ISButton:setEnable(value) self.enable = value end
local alice = { id = "interface-alice", recruited = true, available = true }
local bob = { id = "interface-bob", recruited = true, available = true }
local root = { selectedRow = alice }
local detail = BasePolicyFixture.classes.SCUIDetail:new(0, 0, 240, 300, root)
local panel, payload = ISPanel:new(0, 0, 240, 300), { group = "Beta" }
detail:addCommand(panel, 0, "UI_SC_Group_Apply", "set_group", payload)
local button = panel.childrenInOrder[1]
assert(#issued == 0, "building command controls is read-only")
root.selectedRow = bob
button.onClick(button.target, button)
assert(#issued == 1 and issued[1].id == bob.id and issued[1].command == "set_group"
    and issued[1].payload == payload and issued[1].player == getSpecificPlayer(0),
    "the real button routes the exact command and payload to the currently selected actor")
root.selectedRow = nil
button.onClick(button.target, button)
root.selectedRow = { id = bob.id, available = false }
button.onClick(button.target, button)
assert(#issued == 1, "missing and unavailable selections cannot dispatch")
SC.Commands, SC.Interaction, UI.refresh = saved.commands, saved.interaction, saved.refresh
SC_TEST_REPORT = (SC_TEST_REPORT or "") .. "; Selected command PASS: exact actor, payload and player; stale selection guarded"

-- Holding right mouse runs the real diagnostic with a native-style list size.
-- safeMethod returns a trailing nil; it must not become tonumber's radix.
local savedInput = { config = SC.Config, mouse = isMouseButtonDown,
    timestamp = getTimestampMs, player = getSpecificPlayer, manager = UIManager,
    prerender = ISPanel.prerender }
local clock, held, inspected = 1000, true, 0
SC.Config = { get = function(key) return key == "debugSpawnEnabled" and true or nil end }
isMouseButtonDown = function() return held end
getTimestampMs = function() return clock end
getSpecificPlayer = function() return {
    getVehicle = function() end, isAiming = function() return false end,
} end
UIManager = { getUI = function() return {
    size = function() inspected = inspected + 1 return 2 end,
    get = function() end,
} end }
ISPanel.prerender = function() end
local inputRoot = setmetatable({ lastScreenWidth = BasePolicyFixture.screenWidth,
    lastScreenHeight = BasePolicyFixture.screenHeight },
    { __index = BasePolicyFixture.classes.SCUIRoot })
inputRoot:prerender()
clock = 1400
inputRoot:prerender()
inputRoot:prerender()
assert(inspected == 1, "right-hold diagnostic accepts a numeric list size and reports only once")
held = false
inputRoot:prerender()
SC.Config, isMouseButtonDown, getTimestampMs, getSpecificPlayer, UIManager,
    ISPanel.prerender = savedInput.config, savedInput.mouse, savedInput.timestamp,
    savedInput.player, savedInput.manager, savedInput.prerender
