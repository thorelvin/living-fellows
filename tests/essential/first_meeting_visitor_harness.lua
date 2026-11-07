-- SPDX-License-Identifier: MIT
-- The first visitor's waiting state reaches the real independent-survivor routine.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check = f.check
local visitor = f.actor("essential-visitor", 8, 1, { recruited = false })
f.registry[visitor.id] = visitor
local why, searched = nil, 0
local savedMeeting, savedScavenge = SC.FirstMeeting, SC.Encounter.tryScavenge
SC.FirstMeeting = { approach = function() return nil, why end }
SC.Encounter.tryScavenge = function() searched = searched + 1; return false, "nothing_nearby" end
why = "first_meeting_nearby"
local ok, reason = SC.Encounter.update(visitor, f.player, {})
check(searched == 1, "a waiting visitor still looks for supplies close by")
check(ok == true and reason == "first_meeting_waiting",
    "a waiting visitor stays instead of wandering, hiding or chasing sounds: " .. tostring(reason))
SC.Encounter.tryScavenge = function() return true, "neutral_scavenge" end
f.clock = f.clock + 11000
ok, reason = SC.Encounter.update(visitor, f.player, {})
check(ok == true and reason == "neutral_scavenge", "a nearby find is still searched")
SC.Encounter.tryScavenge = function() return false, "nothing_nearby" end
why = nil
ok, reason = SC.Encounter.update(visitor, f.player, {})
check(reason ~= "first_meeting_waiting", "other independent survivors keep their own routine")
SC.FirstMeeting, SC.Encounter.tryScavenge = savedMeeting, savedScavenge
print("BEHAVIOUR_FIRST_MEETING_VISITOR_PASS checks=" .. tostring(f.checks()))
