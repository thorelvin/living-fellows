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
