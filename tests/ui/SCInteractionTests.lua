-- SPDX-License-Identifier: MIT
local interaction = assert(SurvivorCompanion.Interaction)
local player = {}
local row = { id = "sam", actor = {}, alive = true, available = true,
    recruited = true, distance = 2 }

assert(#interaction.categories == 3)
assert(#interaction.quickOrders == 4)
assert(interaction.availability(row, "doing", player))
SurvivorCompanion.GameplayUtil = {
    sameFloor = function() return false end,
}
local sameFloorAllowed, floorReason = interaction.availability(row, "doing", player)
assert(not sameFloorAllowed and floorReason == "UI_SC_Talk_DifferentFloor")
SurvivorCompanion.GameplayUtil = nil
assert(interaction.reasonText("conversation_partner_too_far") ==
    "UI_SC_Disabled_TooFar:16")
local neutral = { id = "stranger", actor = {}, alive = true, available = true,
    recruited = false, distance = 2 }
assert(interaction.availability(neutral, "doing", player))
assert(not interaction.availability(neutral, "praise", player))

interaction.begin(row.id, "doing")
local pending = interaction.state(row.id)
assert(pending.state == "approaching" and #pending.lines == 0,
    "approaching must not count as spoken dialogue")
assert(not interaction.availability(row, "needs", player),
    "pending dialogue prevents duplicate requests")
interaction.finish(row.id, "doing", "Checking the shelves")
assert(pending.state == "replied" and #pending.lines == 2)
assert(pending.lines[1].speaker == "player")
assert(pending.lines[2].speaker == "companion")
assert(interaction.availability(row, "needs", player))

interaction.begin(row.id, "needs")
interaction.finish(row.id, "needs", nil, "conversation_interrupted_by_danger")
assert(pending.state == "interrupted" and #pending.lines == 3)
assert(pending.lines[3].speaker == "system",
    "cancelled dialogue must not add a spoken player line")

for index = 1, 30 do interaction.note(row.id, "system", index) end
assert(#pending.lines == 24)
interaction.reset()
assert(#interaction.state(row.id).lines == 0)
