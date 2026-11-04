-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local E, W, F = SC.ExpeditionPrototype, SC.ExpeditionWood, SC.ExpeditionForests
local metadataPreview = F.preview
local metadataNearCar = F.nearCar
local checks, hour, slot, departures = 0, 5, nil, 0
local timeOfDay, nightWork = 12, false
local function check(value, message)
    checks = checks + 1
    assert(value, "wood mission check " .. checks .. ": " .. message)
end
local function actor(id, x)
    return { id = id, x = x, y = 100, z = 0,
        isDead = function(a) return a.dead == true end,
        getX = function(a) return a.x end, getY = function(a) return a.y end,
        getZ = function() return 0 end,
        getCurrentSquare = function() return { getRoom = function() return nil end } end }
end
local leader, follower, player = actor("leader", 100), actor("follower", 101), actor("player", 99)
local roster = { { id = "leader", actor = leader }, { id = "follower", actor = follower } }
SC.Registry = { isActive = function(a, id) return a.id == id end,
    byId = function(id) for _, r in ipairs(roster) do if r.id == id then return r end end end }
SC.GameplayUtil = { position = function(a) return a.x, a.y, a.z end,
    nameOf = function(a) return a.id end, nowMs = function() return SC_TEST_CLOCK end,
    call = function(a, name, ...) if a and type(a[name]) == "function" then return a[name](a, ...), true end return nil, false end,
    config = function() return 256 end, isDead = function() return false end,
    sameFloor = function() return true end, distance = function(a,b) return math.abs(a.x-b.x) end,
    canSee = function() return false end }
SC.Commands, SC.BaseWatch, SC.Medical, SC.ZombieAttack, SC.Senses = nil, nil, nil, nil, nil
SC.Dialogue = { say = function() departures = departures + 1 return true end }
SC.BaseLife = { active = function() return { id = "camp", core = { x = 100, y = 100, z = 0 } } end,
    policies = function() return { workOutsideAtNight = nightWork } end, isInside = function(a) return a.x <= 110 end }
SC.ExpeditionIntegration = { woodDestinationAvailable = function() return true end,
    settle = function() return false end, reset = function() end }
SC.ViewSession = { claim = function(_, a) slot = a return true, a end,
    slotSqlId = function() return 2 end, owner = function() return "expedition" end,
    released = function() slot = nil end, rememberSlotSqlId = function() end,
    adopt = function() return true end }
SCSplitScreenProbe = { isLeader = function(a) return slot == a end,
    leaderSqlId = function() return 2 end, releaseForWorldExit = function() slot = nil return true end }
function getSpecificPlayer(i) if i == 0 then return player elseif i == 1 then return slot end end
function destroyPlayerData() end
function getGameTime() return { getWorldAgeHours = function() return hour end,
    getTimeOfDay = function() return timeOfDay end } end
Events = nil
local site = { id = "forest:140:100:Forest", label = "Forest east near Oak Street", type = "Forest",
    anchor = { x = 140, y = 100, z = 0 }, bounds = { x1 = 132, y1 = 92, x2 = 148, y2 = 108, z = 0 }, distance = 40 }
F.preview = function() return { candidates = { site }, provisional = true } end
local verifyCalls = 0
F.verify = function() verifyCalls = verifyCalls + 1 return true, "forest_verified" end
local prepared, preparationCar, preparationLeader = false, nil, nil
W.prepare = function(_, _, car, leaderId)
    preparationCar, preparationLeader = car, leaderId
    return true, "wood_preparing_axes", prepared
end
for _, sample in ipairs({ { 0, false }, { 5.999, false }, { 6, true }, { 12, true },
    { 20.999, true }, { 21, false }, { 23.999, false }, { 24, false } }) do
    timeOfDay = sample[1]
    check(W.outsideWorkAllowed() == sample[2], "actual time of day policy at " .. timeOfDay)
    check((W.safety(leader, {}) ~= "wood_night") == sample[2], "worker shares daylight policy at " .. timeOfDay)
end
nightWork, timeOfDay = true, 22
check(W.outsideWorkAllowed() and not W.safety(leader, {}), "night-work permission bypasses clock restriction")
nightWork, timeOfDay = false, 12
W.status = function(wood) return { done = wood.testDone == true, reason = "wood_quantity_met" } end
local realStart, originalCar, captured = E.start, SC.ExpeditionCar, nil
local near, far = F.copySite(site), F.copySite(site)
near.id, near.anchor.x, near.bounds.x1, near.bounds.x2 = "near", 170, 162, 178
far.id, far.anchor.x, far.bounds.x1, far.bounds.x2 = "far", 500, 492, 508
F.preview = function() return { candidates = { site, near, far } } end
F.nearCar = function() return { candidates = { near, far } } end
SC.ExpeditionCar = { preflight = function() return { exit = { x = 130, y = 100, z = 0 } } end }
E.start = function(_, plan) captured = plan return false, "captured" end
E.startWoodCollection(roster, { travelMode = "drive" })
check(captured and #captured.wood.sites == 2 and captured.wood.sites[2].id == "near",
    "drive preview and dispatch retain only forest alternatives reachable from the same parked work area")
E.start, SC.ExpeditionCar = realStart, originalCar
F.preview = function() return { candidates = { site }, provisional = true } end
F.nearCar = metadataNearCar
local began, active = E.startWoodCollection(roster, { travelMode = "straight", request = { mode = "count", quantity = 24 } })
check(began and active.scout.kind == "wood" and active.scout.search == nil,
    "wood is a separate physical mission, never generic container search")
check(active.scout.wood.preparation and departures == 0 and active.scout.turnHomeAtHour == 9,
    "accepted mission pauses for automatic gear preparation with a bounded default trip time")
check(E.woodPreparationFor(leader) and E.woodPreparationFor(follower) == nil,
    "only the leader owns predeparture tool-fetch actions")
-- The voice layer reads each pulse and work result after the fact.
local voiceCalls = {}
SC.WorkVoice = {
    expeditionPulse = function(m) voiceCalls[#voiceCalls + 1] = "pulse:" .. tostring(m == active) end,
    woodResult = function(_, reason) voiceCalls[#voiceCalls + 1] = "wood:" .. tostring(reason) end,
}
E.pulse()
check(voiceCalls[1] == "pulse:true", "each expedition pulse is offered to the voice layer")
check(active.testWaypoint == nil and verifyCalls == 0, "preparing crew cannot begin travel or site work")
local recallRetries, normalCar = 0, SC.ExpeditionCar
SC.ExpeditionCar = { requestReturn = function() recallRetries = recallRetries + 1 return false, "wood_work_settling" end }
active.scout.vehicle = { state = "walking_to_car", leg = "outbound" }
active.scout.wood.pendingCarReturnReason = "radio_return"
E.pulse()
check(recallRetries == 1 and E.woodPreparationFor(leader) == nil,
    "pending car recall retries before the preparation hold and suppresses new axe-fetch decisions")
active.scout.wood.pendingCarReturnReason = nil
active.scout.vehicle = nil
SC.ExpeditionCar = normalCar
active.scout.vehicle = { state = "abandoned", sqlId = 44 }
E.updateWood(leader)
check(preparationCar == nil and E.woodPreparationFor(leader).carId == nil,
    "a restored abandoned car cannot grant predeparture shuttle capacity or require a usable trunk")
active.scout.vehicle = nil
hour, timeOfDay, prepared = 15, 22, true
E.updateWood(leader)
check(active.scout.wood.preparationReason == "wood_waiting_for_daylight" and departures == 0,
    "night policy delays departure while retaining borrowed tool state")
check(voiceCalls[#voiceCalls] == "wood:wood_waiting_for_daylight"
        and voiceCalls[#voiceCalls - 1] == "wood:wood_preparing_axes",
    "wood preparation results reach the voice layer unchanged: " .. table.concat(voiceCalls, ", "))
SC.WorkVoice = { expeditionPulse = function() error("voice fault") end,
    woodResult = function() error("voice fault") end }
hour, timeOfDay = 29, 12
E.updateWood(leader)
check(not active.scout.wood.preparation and active.scout.departureHour == 29
    and active.scout.turnHomeAtHour == 33 and departures == 1,
    "actual departure resets travel deadlines after the preparation pause")
-- A remote squad can need more than eight seconds of bounded Lua planning.
-- The expedition watchdog must not cancel that live search before Navigation
-- can finish it or hand it to the native pathfinder.
local normalScout, normalNavigation, normalClock = active.scout, SC.Navigation, SC_TEST_CLOCK
local routeProbe = {}
for key, value in pairs(normalScout) do routeProbe[key] = value end
active.scout = routeProbe
local navigationStatus, routeCancels = { active = true, phase = "planning", action = "ordered_move", pathSearchAgeMs = 9000 }, 0
SC.Navigation = {
    status = function() return navigationStatus end,
    cancel = function(a, reason)
        check(a == leader and reason == "scout_stalled", "only the stalled leader route is cancelled")
        routeCancels = routeCancels + 1
    end,
}
local function stageRouteProbe(current, age)
    SC_TEST_CLOCK = current
    active.testWaypoint = { x = 120, y = 100, z = 0 }
    routeProbe.bestDistanceToWaypoint = 20
    routeProbe.waypointStagedAt, routeProbe.lastProgressAt = current - age, current - age
    routeProbe.replans, routeProbe.lastStalledTarget = 0, nil
    routeProbe.lastPlanAt, routeProbe.firstPlanFailureAt = nil, nil
end
stageRouteProbe(100000, 9000)
E.pulse()
check(active.testWaypoint ~= nil and routeCancels == 0,
    "a live ordered-move search survives the eight-second movement watchdog")
stageRouteProbe(120000, 29000)
navigationStatus.pathSearchAgeMs = 29000
E.pulse()
check(active.testWaypoint ~= nil and routeCancels == 0,
    "bounded planning may use the existing thirty-second waypoint allowance")
stageRouteProbe(150000, 31000)
navigationStatus.pathSearchAgeMs = 31000
E.pulse()
check(active.testWaypoint == nil and routeCancels == 1,
    "planning cannot suppress the thirty-second hard waypoint watchdog")
stageRouteProbe(170000, 9000)
navigationStatus.phase = "moving"
E.pulse()
check(active.testWaypoint == nil and routeCancels == 2,
    "an ordinary route with no motion still recovers after eight seconds")
stageRouteProbe(190000, 9000)
navigationStatus.phase, navigationStatus.action = "planning", "move_to_base_storage"
E.pulse()
check(active.testWaypoint == nil and routeCancels == 3,
    "an unrelated planner cannot retain the expedition waypoint")
active.scout, SC.Navigation, SC_TEST_CLOCK = normalScout, normalNavigation, normalClock
active.testWaypoint, active.cohesionHold = nil, nil
leader.x, follower.x = 140, 141
E.pulse()
check(active.scout.phase == "wood_working" and verifyCalls == 1,
    "arrival verifies physical mature forest before workers receive the site")
check(E.woodRequestFor(follower).bounds.x1 == 132 and not E.testSearchFor(leader),
    "each worker gets the bounded forest and no generic loot instruction")
active.scout.vehicle = { state = "abandoned", sqlId = 44 }
check(E.woodRequestFor(leader).carId == nil and E.woodRequestFor(follower).carId == nil,
    "walking workers never shuttle physical logs back to an abandoned expedition car")
active.scout.vehicle = nil
active.scout.wood.loans.leader = { itemId = "axe-1", storageId = "tool-shelf" }
for i = 1, 24 do active.scout.wood.acquisitions[i] = { id = "log-" .. i, itemType = "Base.Log",
    memberId = "leader", source = { x = 140, y = 100, z = 0 } } end
local saved = E.export()
check(saved.schema == 7 and #saved.scout.wood.acquisitions == 24
    and saved.scout.wood.loans.leader.itemId == "axe-1", "schema7 preserves large wood cargo and exact tool loans")
saved.scout.wood.acquisitions[1].id = "changed-copy"
check(active.scout.wood.acquisitions[1].id == "log-1", "save data shares no mutable wood ledger with the active mission")
saved = E.export()
active.scout.wood.testDone = true
local originalController, delegated, homePulses = SC.ExpeditionCar, {}, 0
SC.ExpeditionCar = {
    requestReturn = function(m, _, reason)
        delegated[#delegated + 1] = reason
        m.scout.vehicle.leg = "home"
        m.scout.vehicle.state = reason == "wood_night" and "boarding_home" or "returning_to_car"
        m.scout.phase = m.scout.vehicle.state
        m.scout.wood.pendingCarReturnReason, m.scout.wood.pendingReturnReason = nil, nil
        return true
    end,
    pulse = function() homePulses = homePulses + 1 return true end,
}
active.scout.vehicle, active.scout.phase = { state = "driving_out", leg = "outbound" }, "driving_out"
hour, timeOfDay = 38, 21
E.pulse()
check(delegated[1] == "wood_night" and active.scout.phase == "boarding_home"
    and active.scout.vehicle.leg == "home", "night recall delegates a running car to native homeward transition")
E.pulse()
check(homePulses == 1 and #delegated == 1,
    "homeward car remains controlled by Car.pulse at night without repeated wood recalls")
hour, timeOfDay = 29, 12
active.scout.vehicle, active.scout.phase = { state = "parked_at_site", leg = "outbound" }, "wood_working"
active.scout.wood.pendingReturnReason = "wood_quantity_met"
E.pulse()
check(delegated[2] == "wood_quantity_met" and active.scout.phase == "returning_to_car"
    and active.scout.wood.pendingReturnReason == nil,
    "settled work completion uses the car return intent and clears stale walking recall retries")
local recoveryPulses = 0
active.scout.vehicle, active.scout.phase = { state = "held", leg = "outbound" }, "held"
active.scout.wood.pendingCarReturnReason = "wood_quantity_met"
SC.ExpeditionCar = {
    requestReturn = function() return false, "car_recovery_required" end,
    pulse = function(m) recoveryPulses = recoveryPulses + 1; m.scout.vehicle.state = "abandoned"; return true end,
}
E.pulse()
check(recoveryPulses == 1 and active.scout.vehicle.state == "abandoned",
    "pending car recall lets held-car recovery advance instead of starving its pulse")
E.pulse()
check(active.scout.phase == "inbound" and active.scout.wood.pendingCarReturnReason == nil,
    "abandonment clears the car recall queue and resumes physical walking home")
SC.ExpeditionCar = originalController
active.scout.vehicle, active.scout.phase = nil, "wood_working"
E.pulse()
check(active.scout.phase == "inbound" and active.scout.wood.endReason == "wood_quantity_met",
    "settled worker completion automatically turns the crew home")
check(E.prepareReset() and E.reset(), "world exit releases mission-owned native view before reset")
check(E.restore(saved), "an active schema7 wood mission restores through strict travel and roster validation")
check(E.current().scout.wood.request.quantity == 24 and E.current().scout.search == nil,
    "restore never leaves its validation-only search request in the live mission")
check(E.woodMarkerLive({ tripId = E.current().radioSession, id = "log-1" }, nil)
    and E.woodMarkerLive(nil, { id = "axe-1", memberId = "leader" }),
    "the active trip keeps its cargo and borrowed-axe markers live")
check(not E.woodMarkerLive({ tripId = "settled-trip", id = "log-x" }, nil)
    and not E.woodMarkerLive(nil, { id = "axe-2", memberId = "leader" })
    and not E.woodMarkerLive(nil, { id = "axe-1", memberId = "follower" }),
    "a marker whose trip and loan are gone protects nothing")
local savedPersistence = SC.Persistence
SC.Persistence = { restoreStatus = function() return false end }
check(E.woodMarkerLive({ tripId = "settled-trip", id = "log-x" }, nil),
    "every marker stays live until the save has been restored")
SC.Persistence = savedPersistence
check(E.pulse(), "restored wood mission reacquires its exact native crew before work resumes")
SC.Senses = { cached = function() return { valid = true, reflexTime = SC_TEST_CLOCK,
    threats = { { x = 142, y = 100, visible = true } } } end }
local protectedTrip, normalCarController = E.current(), SC.ExpeditionCar
local carTravelPulses = 0
protectedTrip.scout.phase = "driving_out"
protectedTrip.scout.vehicle = { state = "driving_out", sqlId = 44 }
SC.ExpeditionCar = { pulse = function() carTravelPulses = carTravelPulses + 1 return true end }
E.pulse()
check(protectedTrip.scout.phase == "driving_out" and carTravelPulses == 1
    and protectedTrip.scout.wood.endReason == nil,
    "nearby road threats preserve protected driving and defer to existing vehicle travel safety")
protectedTrip.scout.phase, protectedTrip.scout.vehicle = "wood_working", nil
SC.ExpeditionCar = normalCarController
E.pulse()
check(E.current().scout.phase == "inbound" and E.current().scout.wood.endReason == "wood_unsafe",
    "mission safety returns the party even when urgent combat prevents the worker from running")
SC.Senses = nil
leader.x, follower.x = 104, 105
SC.GameplayUtil.canSee = function() return true end
SC.GameplayUtil.directInteractionAccess = function() return true end
local realFinish, reunionPhase = E.finishAtPlayer, nil
E.finishAtPlayer = function() reunionPhase = E.current().scout.phase return true end
E.current().testWaypoint = { x = 100, y = 100, z = 0 }
E.pulse()
check(reunionPhase == "awaiting_player" and E.current().testWaypoint == nil,
    "a visible assembled wood crew back inside camp can finish before its last walking waypoint")
E.finishAtPlayer = realFinish
check(E.prepareReset() and E.reset(), "the restored validation fixture can be disposed")
saved.scout.wood.acquisitions[1].itemType = "Base.Plank"
check(not E.restore(saved) and E.current() == nil, "a forged wood receipt fails closed without creating a mission")
saved.scout.wood.acquisitions[1].itemType = "Base.Log"
saved.scout.wood.cutterId = "outside-roster"
check(not E.restore(saved) and E.current() == nil,
    "a saved cutter must belong to the mission roster")
saved.scout.wood.cutterId = "leader"
saved.scout.wood.tripId = "other-trip"
check(not E.restore(saved), "wood ownership cannot be rebound to another saved radio session")
check(not E.startWoodCollection(roster, { request = { mode = "count", quantity = 257 } }),
    "unbounded wood requests are rejected")
local beganFallback, fallback = E.startWoodCollection(roster, { travelMode = "straight" })
check(beganFallback, "the depleted-forest fallback fixture starts")
E.updateWood(leader)
local third = F.copySite(site)
third.id, third.anchor.y, third.bounds.y1, third.bounds.y2 = "third", 132, 124, 140
fallback.scout.wood.sites = { site, near, third }
fallback.scout.vehicle = { state = "parked_at_site", leg = "outbound", sqlId = 44,
    siteStop = { x = 130, y = 100, z = 0 } }
local fallbackChecks, previousVerify, previousCar = 0, F.verify, SC.ExpeditionCar
F.verify = function()
    fallbackChecks = fallbackChecks + 1
    return fallbackChecks >= 3, fallbackChecks >= 3 and "forest_verified" or "forest_no_mature_trees"
end
SC.ExpeditionCar = { pulse = function() return false end }
leader.x, leader.y, follower.x, follower.y = 140, 100, 141, 100
E.pulse()
check(fallback.scout.wood.siteIndex == 2 and fallback.scout.destination.x == 170,
    "an empty first car-side patch advances to the second stored forest")
fallback.scout.vehicle.state = "abandoned"
fallback.scout.vehicle.siteStop = { x = 1000, y = 1000, z = 0 }
leader.x, follower.x = 170, 171
E.pulse()
check(fallback.scout.wood.siteIndex == 3 and fallback.scout.destination.y == 132,
    "an abandoned distant car cannot leash walking fallback to the third forest")
leader.x, leader.y, follower.x, follower.y = 140, 132, 141, 132
E.pulse()
check(fallbackChecks == 3 and fallback.scout.phase == "wood_working" and E.woodRequestFor(leader).carId == nil,
    "the third verified patch begins physical work using real walking capacity")
F.verify, SC.ExpeditionCar = previousVerify, previousCar
fallback.scout.vehicle = nil
check(E.prepareReset() and E.reset(), "the fallback fixture retains clean view and native work teardown")
leader.x, leader.y, follower.x, follower.y = 104, 100, 105, 100
local originalWorld, routeChecks = getWorld, 0
local function forestZone(x, y)
    return { getType = function() return "Forest" end, getX = function() return x end,
        getY = function() return y end, getWidth = function() return 70 end, getHeight = function() return 70 end,
        contains = function(_, px, py) return px >= x and px < x + 70 and py >= y and py < y + 70 end }
end
local zones = { forestZone(120, 120), forestZone(400, 100) }
function getWorld() return { getMetaGrid = function() return { getZonesIntersecting = function(_, x, y)
    local list = {}
    for _, zone in ipairs(zones) do
        if zone:getX() < x + 200 and zone:getX() + 70 > x and zone:getY() < y + 200 and zone:getY() + 70 > y then
            list[#list + 1] = zone
        end
    end
    return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
end } end } end
F.preview = metadataPreview
F.reset()
captured = nil
E.start = function(_, plan) captured = plan return false, "captured" end
SC.ExpeditionCar = { preflight = function(_, _, _, destination)
    routeChecks = routeChecks + 1
    return { exit = destination.x >= 400 and destination or { x = 0, y = 0, z = 0 } }
end }
for _ = 1, 200 do
    local before = routeChecks
    local _, reason = E.startWoodCollection(roster, { travelMode = "drive" })
    check(routeChecks - before <= 3, "each automatic drive discovery pulse checks at most three road routes")
    if captured or reason ~= "forest_scan_pending" then break end
end
check(captured and captured.destination.x >= 400 and routeChecks > 3 and #captured.wood.sites == 3,
    "drive admission finds a farther usable forest plus two patches near its road stop before dispatch")
E.start, SC.ExpeditionCar, getWorld = realStart, originalCar, originalWorld
do
    prepared = false
    F.preview = function() return { candidates = { site } } end
    local started, trip = E.startWoodCollection(roster, { travelMode = "straight" })
    check(started and E.updateWood(leader) and preparationLeader == leader.id,
        "production preparation passes current expedition leader to worker")
    SCSplitScreenProbe.handoff = function(a) slot = a return a end
    leader.dead = true
    E.pulse()
    check(trip.leader.id == follower.id and E.woodPreparationFor(follower)
        and not E.woodPreparationFor(leader) and trip.roster[1].id == leader.id,
        "native-view handoff transfers preparation while retaining original roster order")
    E.updateWood(follower)
    check(preparationLeader == follower.id, "subsequent tool preparation receives actual living handoff leader")
    check(E.prepareReset() and E.reset(), "handoff preparation tears down cleanly")
    leader.dead, F.preview = nil, metadataPreview
end
do
    local savedPreview=F.preview
    F.preview=function() return {candidates={site}} end
    local started,trip=E.startWoodCollection(roster,{travelMode="straight"})
    check(started,"manual wood persistence fixture starts")
    local anchor=trip.scout.wood.sites[1].anchor
    trip.scout.mapTarget={version=1,kind="wood",id="wood:"..anchor.x..":"..anchor.y,
        label="Chosen woodland",anchor={x=anchor.x,y=anchor.y,z=0},
        workBounds={x1=anchor.x-32,y1=anchor.y-32,x2=anchor.x+32,y2=anchor.y+32,z=0}}
    local saved=E.export()
    check(saved.schema==8 and saved.baseSchema==7,"manual wood saves exact selected bounds under schema 8")
    check(E.prepareReset() and E.reset() and E.restore(saved),"schema 8 delegates wood receipts and tool loans to the existing validator")
    local restored=E.export()
    check(restored.scout.mapTarget.workBounds.x1==saved.scout.mapTarget.workBounds.x1
        and #restored.scout.wood.sites==#saved.scout.wood.sites,"wood reload preserves selected area and alternatives")
    check(E.prepareReset() and E.reset(),"manual wood persistence releases its view")
    F.preview=savedPreview
end
do
    local previousLogistics, previousActor, previousPreview = SC.Logistics, SC.Actor, F.preview
    local previousGear, previousReady, previousClock = W.departureGear, W.departureReady, SC_TEST_CLOCK
    local ready, calls, resets, blocked, expected, pending, settles = {}, {}, 0, false, nil, nil, 0
    SC.Actor = { stop = function(a) a.preparationHeld = true return true end }
    SC.Logistics = {
        prepareLoadout = function(a, request)
            check(a == expected and request.haulRequired == false and request.cargo.weight == 9,
                "only the current actor services its own shared loadout and cargo reservation")
            calls[a] = (calls[a] or 0) + 1
            if a == follower and blocked then return false, "loadout_storage_unavailable", false, { stage = "blocked" } end
            return not ready[a], ready[a] and "loadout_ready" or "loadout_pack", ready[a],
                { stage = ready[a] and "ready" or "pack", cargoReady = a == follower,
                    carryWeight = 9, carryCapacity = 17, rawFree = 30, bags = {} }
        end,
        busy = function(a) return pending == a end,
        settlePreparation = function(a)
            check(a == expected and pending == a, "only the actor polls its existing preparation transfer")
            pending, settles = nil, settles + 1
            return true, "loadout_settled", true
        end,
        resetPreparation = function(a)
            if pending == a then return false, "loadout_inventory_pending" end
            resets = resets + 1 return true
        end,
    }
    W.departureGear = function(a) return { "axe-kept" }, a ~= leader end
    W.departureReady = function(_, _, _, options)
        check(options.allowHeldById.leader == false and options.allowHeldById.follower == true,
            "the final wood gate preserves the cutter's tool hands and the helper's held bag allowance")
        return true
    end
    F.preview = function() return { candidates = { site } } end
    prepared, hour, timeOfDay, leader.x, follower.x = false, 40, 12, 104, 105
    local beforeDeparture = departures
    local started, trip = E.startWoodCollection(roster, { travelMode = "straight" })
    local leaderRow, followerRow = E.departurePreparationFor(leader), E.departurePreparationFor(follower)
    check(started and leaderRow and followerRow and leaderRow.gearPending, "whole crew receives stable shared preparation rows")
    E.updateDeparturePreparation(follower)
    check(not calls[follower] and follower.preparationHeld, "followers wait for required tools before any packing action")
    prepared, hour = true, 41
    E.updateWood(leader)
    check(E.departurePreparationFor(leader) == leaderRow and not leaderRow.gearPending
        and departures == beforeDeparture and trip.scout.departureHour == 40 and trip.scout.turnHomeAtHour == 44,
        "gear completion preserves the handoff identity and does not start the trip clock or announcement")
    ready[leader], expected = true, leader
    E.updateDeparturePreparation(leader)
    expected = follower
    E.updateDeparturePreparation(follower)
    local car, carPulses = SC.ExpeditionCar, 0
    SC.ExpeditionCar = { pulse = function() carPulses = carPulses + 1 return true end }
    trip.scout.vehicle = { state = "walking_to_car", leg = "outbound" }
    E.pulse()
    check(carPulses == 0 and departures == beforeDeparture and trip.testWaypoint == nil,
        "walking and boarding remain held until every surviving member finishes")
    trip.scout.vehicle, SC.ExpeditionCar = nil, car
    local saved = E.export()
    check(saved.schema == 7 and saved.scout.departurePreparation.originCampId == "camp"
        and saved.scout.departurePreparation.members[1].ready == nil,
        "existing schema saves only the pending preparation, origin and exact member identities")
    check(E.prepareReset() and E.reset() and E.restore(saved) and E.pulse(), "pending shared preparation survives native teardown and reload")
    trip = E.current()
    leaderRow, followerRow = E.departurePreparationFor(leader), E.departurePreparationFor(follower)
    check(leaderRow and not leaderRow.ready and followerRow and not followerRow.ready, "reload re-audits readiness instead of trusting saved ready flags")
    expected = leader
    E.updateDeparturePreparation(leader)
    blocked, expected = true, follower
    E.updateDeparturePreparation(follower)
    local beforeCalls, beforeResets = calls[follower], resets
    E.updateDeparturePreparation(follower)
    check(calls[follower] == beforeCalls, "blocked preparation remains quiet before its retry deadline")
    SC_TEST_CLOCK = SC_TEST_CLOCK + 180001
    E.updateDeparturePreparation(follower)
    check(calls[follower] == beforeCalls + 1 and resets == beforeResets + 1, "blocked preparation retries after three minutes")
    check(not E.retryDeparturePreparation("old-trip") and E.retryDeparturePreparation(trip.radioSession), "manual retry is bound to the exact active trip")
    blocked, ready[follower], hour = false, true, 43
    E.updateDeparturePreparation(follower)
    check(not trip.scout.departurePreparation and departures == beforeDeparture + 1
        and trip.scout.departureHour == 43 and trip.scout.turnHomeAtHour == 47,
        "only complete crew readiness starts the real departure and travel allowance")
    check(E.prepareReset() and E.reset(), "shared preparation fixture releases its mission")
    started, trip = E.startWoodCollection(roster, { travelMode = "straight" })
    E.updateWood(leader)
    followerRow = E.departurePreparationFor(follower)
    local beforePacking = calls[follower]
    pending, expected, prepared, trip.scout.wood.preparation = follower, follower, false, true
    E.pulse()
    E.updateDeparturePreparation(follower)
    check(started and settles == 1 and not pending and calls[follower] == beforePacking
        and E.departurePreparationFor(follower) == followerRow and followerRow.gearPending,
        "reopened gear work settles an existing member transfer without beginning another packing action")
    prepared = true
    E.updateWood(leader)
    pending = follower
    trip.scout.departurePreparation.returnReason = "radio_return"
    E.pulse()
    check(trip.scout.departurePreparation and pending == follower, "return waits while the exact inventory transfer is pending")
    E.updateDeparturePreparation(follower)
    E.pulse()
    check(settles == 2 and calls[follower] == beforePacking and not trip.scout.departurePreparation
        and trip.scout.phase == "inbound", "the actor settles cancellation ownership before return resumes without new preparation")
    check(E.prepareReset() and E.reset(), "pending preparation return tears down cleanly")
    SC.Logistics, SC.Actor, F.preview = previousLogistics, previousActor, previousPreview
    W.departureGear, W.departureReady, SC_TEST_CLOCK = previousGear, previousReady, previousClock
end
print("EXPEDITION_WOOD_MISSION_KAHLUA_PASS checks=" .. checks)
