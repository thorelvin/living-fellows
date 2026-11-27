-- SPDX-License-Identifier: MIT
local SC = LivingFellows
local F = SC.EvacuationFixture
local E = SC.OddballEvacuation
local group, story, player, joy, brock = F.group, F.story, F.player, F.joy, F.brock

assert(E.onSpawn(group, joy))
assert(E.onSpawn(group, joy))
assert(#joy.items == 4 and F.itemCount == 4, "setup retries preserve the four reserved items")
assert(E.pulse(group, player, 1) and story.stage == "unmet", "the offer waits for both actors")
assert(E.onSpawn(group, brock) and F.leg.fracture > 0 and F.leg.scratch and F.leg.bleeding == 0)
assert(E.pulse(group, player, 2) and story.stage == "awaiting_car" and group.discovered)
assert(#E.menuOptions(group, player, brock) == 0, "Brock cannot accept the car")
player.z = 1
assert(#E.menuOptions(group, player, joy) == 0, "Joy must be on the same floor")
player.z = 0
local choice = assert(E.menuOptions(group, player, joy)[1])
assert(choice.id == "car_ready" and choice.confirm and choice.payload == 14)
assert(not E.action(group, "car_ready", player, 19), "a stale car selection never pays")
assert(#player.items == 0 and story.stage == "awaiting_car")

F.interruptItem = story.rewardItems[2].id
assert(E.action(group, "car_ready", player, choice.payload))
assert(#player.items == 1 and story.rewardItems[1].delivered and not story.rewardPaid)
assert(not E.pulse(group, player, 3) and F.vehiclePulses == nil,
    "boarding waits for the exact payout to finish")
F.interruptItem = nil
-- Reconcile an item moved to the player immediately before its saved receipt.
assert(SC.GameplayUtil.transferItemVerified(joy.items, player.items, joy.items[1]))
assert(E.pulse(group, player, 4) and story.rewardPaid and #joy.items == 0)
assert(#player.items == 4 and player.items[1].kind == "Base.Antibiotics"
    and player.items[2].kind == "Base.Antibiotics" and player.items[3].kind == "Base.Bandage"
    and player.items[4].kind == "Base.Bandage", "the payout is exactly two of each item")

F.vehicleStatus = "replacement"
assert(E.pulse(group, player, 5) and story.stage == "awaiting_car")
F.carSqlId = 15
assert(E.action(group, "car_ready", player, 15) and #player.items == 4 and F.itemCount == 4,
    "replacing the car does not mint or transfer another reward")
F.vehicleStatus = "departed"
story.stage = "retiring"
assert(E.storyRules.ownsLifecycle(story) and not E.storyRules.memberDeparted(story))
F.crewVisible = true
assert(not E.pulse(group, player, 6) and SC.OddballKit.recordActor(group, 1) == joy,
    "the crew stay present if the player catches up after the car is removed")
F.crewVisible = false
assert(E.pulse(group, player, 6) and F.flushed and group.lifecycle == "destroyed"
    and E.storyRules.memberDeparted(story), "only verified departure retires the group")
print("EVACUATION_STORY_PASS")
