-- SPDX-License-Identifier: MIT
-- Production Home dispatch, final approach and exact whole-crew handover.
local SC=SurvivorCompanion
local E,H,I,F=SC.ExpeditionPrototype,SC.HomeTrip,SC.ExpeditionIntegration,assert(SC.HomeTestFixture)
local at,records=F.at,F.records
F.reset()
local car={}
SC.Vehicle.isStationary=function() return true end
records[1].actor.vehicle,records[2].actor.vehicle=car,car
local seated={records=F.selection.records,travelMode="drive",vehicle=car}
local shown=H.roster(seated)
assert(#shown.records==2 and #shown.exclusions==0,"selected parked-car crew remains in the shown roster")
records[2].actor.vehicle=nil
assert(#H.roster(seated).records==2,"mixed seated and walking selected-car crew remains eligible")
assert(#H.roster({records=F.selection.records,travelMode="straight"}).records==1,
    "walking excludes the seated member instead of silently dispatching that member")
records[1].actor.vehicle=nil
F.roadAvailable=false
local review=H.draft(F.selection,true)
assert(review.canStart and review.requestedTravelMode=="road" and review.routeFallback
    and review.travelMode=="straight" and #review.records==2,"review shows the effective fallback and the exact crew")
local started,trip=H.start(F.selection,review)
assert(started and trip.scout.kind=="home" and trip.scout.phase=="inbound"
    and trip.scout.travelMode=="straight" and not trip.scout.site and not trip.scout.search,
    "the first dispatch accepts the reviewed fallback and starts only the home leg")
assert(#trip.roster==2 and trip.roster[1].id==review.records[1].id
    and trip.roster[2].id==review.records[2].id,"dispatch owns exactly the shown members")
at(records[1].actor,213,200) at(records[2].actor,214,200)
assert(not H.pulse(trip) and trip.testWaypoint and trip.testWaypoint.x==200,
    "actual home travel stages the camp core waypoint for the last approach")
at(records[1].actor,200,200)
assert(not E.finishHome() and F.prepares==0,"leader-only arrival cannot prepare native handover")
at(records[2].actor,201,200) records[2].actor.vehicle=car
assert(not E.finishHome() and F.prepares==0,"every surviving member must physically exit their vehicle")
records[2].actor.vehicle=nil
SC.ActionSupervisor={current=function(a) return a==records[2].actor and {} or nil end}
assert(not E.finishHome() and not trip.homeRelease and F.prepares==0,
    "an unfinished member action blocks handover before native preparation")
SC.ActionSupervisor=nil
F.releaseFailure=true
assert(not E.finishHome() and trip.homeRelease.committed and F.prepares==1 and F.commits==1,
    "native release refusal retains one durable exact-crew handover")
assert(H.inventoryContainerFrozen(records[1].actor.inventory)
    and H.inventoryContainerFrozen(records[2].actor.inventory)
    and not H.inventoryContainerFrozen(records[3].actor.inventory),
    "pending handover freezes only its own crew inventories")
local prepared,committed=F.prepares,F.commits
F.removed=true
assert(E.pulse() and not E.current() and F.remoteReleases==1
    and F.prepares==prepared and F.commits==committed,
    "retry closes the retained native ticket without repeating persistence or duplicating actors")
F.removed=false
local debrief=E.lastDebrief()
assert(debrief.kind=="home" and I.valid(debrief.integration)
    and I.summary(debrief.integration).stored==0 and #debrief.integration.items==0,
    "arrival records pending cleanup without inventing a cargo delivery")
local idle=E.export()
assert(#idle.deliveries==1 and E.reset() and E.restore(idle),"the pending home cleanup survives reload")
for _,record in ipairs(F.selection.records) do
    for _=1,7 do I.update(idle.deliveries[1],record.actor) end
end
assert(I.summary(idle.deliveries[1]).complete,"ordinary cleanup settles the pending whole-crew obligation")

F.reset()
at(F.player,100,100)
assert(H.start({records=F.selection.records,travelMode="straight"}))
at(records[2].actor,140,100)
assert(H.cancel(F.player) and E.current() and F.joinedReleases==0,
    "near recall keeps mission ownership while the crew regroups")
assert(not E.finishAtPlayer(F.player),"recall cannot release a distant surviving follower")
at(records[2].actor,102,100) records[2].actor.vehicle=car
assert(not E.finishAtPlayer(F.player),"recall requires every member unseated")
records[2].actor.vehicle=nil
assert(E.finishAtPlayer(F.player) and F.joinedReleases==1
    and E.lastDebrief().endReason=="recalled_nearby" and not E.lastDebrief().integration,
    "the assembled recalled crew returns without creating a camp delivery")
SC_TEST_REPORT="Essential Home: reviewed fallback, whole-crew arrival, pending handover/retry and recall passed"
