-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local E, W, F = SC.ExpeditionPrototype, SC.ExpeditionWood, SC.ExpeditionForests
local metadataPreview = F.preview
local metadataNearCar = F.nearCar
local checks, hour, slot, departures = 0, 12, nil, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "wood mission check " .. checks .. ": " .. message)
end
local function actor(id, x)
    return { id = id, x = x, y = 100, z = 0,
        isDead = function() return false end,
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
    policies = function() return {} end, isInside = function(a) return a.x <= 110 end }
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
function getGameTime() return { getWorldAgeHours = function() return hour end } end
Events = nil
local site = { id = "forest:140:100:Forest", label = "Forest east near Oak Street", type = "Forest",
    anchor = { x = 140, y = 100, z = 0 }, bounds = { x1 = 132, y1 = 92, x2 = 148, y2 = 108, z = 0 }, distance = 40 }
F.preview = function() return { candidates = { site }, provisional = true } end
local verifyCalls = 0
F.verify = function() verifyCalls = verifyCalls + 1 return true, "forest_verified" end
local prepared, preparationCar = false, nil
W.prepare = function(_, _, car) preparationCar = car return true, "wood_preparing_axes", prepared end
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
check(active.scout.wood.preparation and departures == 0 and active.scout.turnHomeAtHour == 16,
    "accepted mission pauses for automatic gear preparation with a bounded default trip time")
check(E.woodPreparationFor(leader) and E.woodPreparationFor(follower) == nil,
    "only the leader owns predeparture tool-fetch actions")
E.pulse()
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
hour, prepared = 22, true
E.updateWood(leader)
check(active.scout.wood.preparationReason == "wood_waiting_for_daylight" and departures == 0,
    "night policy delays departure while retaining borrowed tool state")
hour = 30
E.updateWood(leader)
check(not active.scout.wood.preparation and active.scout.departureHour == 30
    and active.scout.turnHomeAtHour == 34 and departures == 1,
    "actual departure resets travel deadlines after the preparation pause")
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
hour = 45
E.pulse()
check(delegated[1] == "wood_night" and active.scout.phase == "boarding_home"
    and active.scout.vehicle.leg == "home", "night recall delegates a running car to native homeward transition")
E.pulse()
check(homePulses == 1 and #delegated == 1,
    "homeward car remains controlled by Car.pulse at night without repeated wood recalls")
hour = 30
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
print("EXPEDITION_WOOD_MISSION_KAHLUA_PASS checks=" .. checks)
