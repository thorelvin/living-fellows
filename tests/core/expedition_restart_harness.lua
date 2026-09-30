-- SPDX-License-Identifier: MIT
-- Exercise a resumed mission with a saved casualty and a pending distant team.
local SC = SurvivorCompanion
local expedition = SC.ExpeditionPrototype
SC.GameplayUtil = {
    nameOf = function(actor) return actor.name or "Companion" end,
    position = function(actor) return actor.x, actor.y, actor:getZ() end,
    canSee = function() return false end,
}
local departures = {}
SC.Dialogue = {
    say = function(actor, topic)
        departures[#departures + 1] = { actor = actor, topic = topic }
        return true
    end,
}
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "expedition restart check " .. tostring(checks) .. ": " .. message)
end

local function actorAt(x, y)
    local actor = { x = x, y = y }
    function actor:isDead() return self.dead == true end
    function actor:isCorpseReady() return self.corpseReady == true end
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return 0 end
    return actor
end

local player = actorAt(20, 20)
local leader = actorAt(21, 20)
local follower = actorAt(100, 100)
local slot1
local actors = { beta = leader, gamma = follower }
local actorRuntimes = { beta = {}, gamma = {} }
local uiDestroyed = false
local released = false
local promotions = 0
local lastPromotionSlot
local coldStarts = 0
local cold = actorAt(6400, 6400)
local reserve = actorAt(23, 20)

SC.Registry = {
    byId = function(id)
        local actor = actors[id]
        return actor and { actor = actor, runtime = actorRuntimes[id] } or nil
    end,
    isActive = function(actor, id) return actors[id] == actor end,
}
function getSpecificPlayer(index)
    if index == 0 then return player end
    if index == 1 then return slot1 end
    return nil
end
function destroyPlayerData(actor)
    check(actor == leader or actor == follower or actor == reserve,
        "only the mission leader owns the second view UI")
    uiDestroyed = true
end
SCSplitScreenProbe = {
    promote = function(actor, slotSqlId)
        promotions = promotions + 1
        lastPromotionSlot = slotSqlId
        if slotSqlId and slotSqlId >= 2 then actor.sqlId = slotSqlId end
        slot1 = actor
        return actor
    end,
    isLeader = function(actor) return slot1 == actor end,
    isColdProbe = function(actor) return actor == cold and slot1 == cold end,
    startColdCompanionProbe = function(x, y, z, sqlId)
        check(x == 6400 and y == 6400 and z == 0 and sqlId == 2,
            "automatic bootstrap uses the saved leader tile and slot identity")
        coldStarts = coldStarts + 1
        return cold
    end,
    replaceColdProbeWithRestoredLeader = function(actor, sqlId)
        check(slot1 == cold and actor == leader and sqlId == 2,
            "only the exact restored leader can replace the cold loader")
        actor.sqlId = sqlId
        slot1 = actor
        return true
    end,
    leaderSqlId = function() return slot1 and slot1.sqlId or -1 end,
    persistJoinedLeaderSlotForReuse = function()
        check(slot1 == leader or slot1 == follower or slot1 == reserve,
            "only a joined expedition leader may persist the native slot")
        slot1.sqlId = slot1.sqlId or 2
        return slot1.sqlId
    end,
    persistDeadLeaderSlotForReuse = function()
        check(slot1 == leader and leader:isDead(),
            "only the dead mission leader may persist the native slot")
        return slot1.sqlId
    end,
    canReleaseJoinedLeader = function() return true end,
    releaseJoinedLeader = function()
        check(slot1 == leader or slot1 == follower or slot1 == reserve,
            "release targets the current expedition leader")
        slot1 = nil
        released = true
        return true
    end,
    releaseDeadLeader = function()
        check(slot1 == leader and leader:isDead(),
            "all-dead release targets the native dead slot")
        slot1 = nil
        return true
    end,
    stageDeadCorpseChunk = function(actor)
        check(actor and actor:isDead(), "all-dead release stages each native corpse")
        return true
    end,
    releaseForWorldExit = function()
        check(slot1 == reserve and not reserve:isDead(),
            "world exit unloads only the live expedition slot")
        slot1 = nil
        released = true
        return true
    end,
}

local descriptor = {
    schema = 1,
    roster = { "alpha", "beta", "gamma" },
    survivors = { "beta", "gamma" },
    leaderId = "beta",
    radioSession = "saved-session",
    radioSequence = 7,
    slotSqlId = 2,
}
local restored = expedition.restore(descriptor)
check(restored == true, "saved mission descriptor is accepted")
local resumed, reason = expedition.pulse()
check(resumed == true and reason == "expedition_resumed" and slot1 == leader,
    "the saved living leader reacquires slot 1")
local observed = expedition.describeForPlayer(nil)
check(observed.leaderName == "beta" and #observed.members == 3
        and observed.members[1].visible == false
        and observed.members[1].x == nil
        and observed.members[1].health == nil
        and observed.phase == nil and observed.destination == nil,
    "the public mission view contains roster identity but no remote state")
check(#departures == 0, "restoring a mission must not replay its departure line")
check(expedition.restartBootstrapCandidate() == nil,
    "an active restored leader never requests a second restart loader")
check(expedition.followDistanceFor(follower) == 2
        and expedition.followDistanceFor(leader) == nil,
    "only expedition followers inherit the temporary close travel spacing")
local policyMission = expedition.current()
policyMission.scout = { phase = "searching" }
function leader:getCurrentSquare()
    return { getRoom = function() return {} end }
end
check(expedition.followDistanceFor(follower) == 5,
    "indoor search gives followers room at containers and doors")
policyMission.scout.phase = "inbound"
check(expedition.followDistanceFor(follower) == 2,
    "the return leg resumes close travel spacing")
policyMission.scout = nil
local exported = expedition.export()
check(#exported.roster == 3 and #exported.survivors == 2
        and exported.leaderId == "beta" and exported.radioSequence == 7
        and exported.slotSqlId == 2,
    "casualty history and surviving roster remain distinct")
local finished, refusal = expedition.finishAtPlayer(player)
check(finished == false and refusal == "return_member_not_assembled",
    "a distant living follower still prevents release")
follower.x, follower.y = 22, 20
finished, reason = expedition.finishAtPlayer(player)
check(finished == true and reason == "returned" and uiDestroyed and released,
    "the team returns even though the saved casualty has no actor")
check(expedition.current() == nil, "completed mission relinquishes ownership")
local idle = expedition.export()
check(idle ~= nil and idle.schema == 2 and idle.state == "idle"
        and idle.slotSqlId == 2,
    "a completed mission durably reserves its native slot identity")
local invalid, invalidReason = expedition.restore({
    schema = 2, state = "idle", slotSqlId = 1,
})
check(invalid == false and invalidReason == "saved idle expedition slot is invalid",
    "a corrupted idle descriptor cannot claim the primary player's row")
restored = expedition.restore(idle)
check(restored == true and expedition.current() == nil,
    "a reload restores the idle slot without inventing an active mission")
local started, newMission = expedition.start({
    { id = "gamma", actor = follower },
})
check(started == true and newMission.leader.actor == follower
        and lastPromotionSlot == 2 and follower.sqlId == 2,
    "a different saved companion reuses the dormant slot for a later mission")
check(#departures == 1 and departures[1].actor == follower
        and departures[1].topic == "expedition.departure",
    "a successful mission start makes its leader speak once")
finished, reason = expedition.finishAtPlayer(player)
check(finished == true and reason == "returned",
    "the second mission releases the same slot cleanly")

-- The native cold loader may already have handed the view to the saved
-- leader before the mission pulse observes all restored members.
restored = expedition.restore(descriptor)
check(restored == true, "descriptor accepts a saved local-player identity")
slot1 = leader
local beforePromotion = promotions
resumed, reason = expedition.pulse()
check(resumed == true and reason == "expedition_resumed"
        and promotions == beforePromotion,
    "the exact saved leader already in slot 1 resumes without a second promotion")
finished, reason = expedition.finishAtPlayer(player)
check(finished == true and reason == "returned",
    "the resumed preassigned view still completes its return")

actors.beta, actors.gamma = nil, nil
slot1 = nil
uiDestroyed, released = false, false
restored = expedition.restore(descriptor)
check(restored == true, "remote descriptor survives another load")
resumed, reason = expedition.pulse()
check(resumed == false and reason == "expedition_restart_waiting_for_native_team"
        and slot1 == nil,
    "missing distant actors leave the mission paused without a false view")
SC.Persistence = {
    pendingBootstrap = function(id)
        check(id == "beta", "only the saved leader may bootstrap the distant area")
        return { id = id, x = 6400, y = 6400, z = 0 }
    end,
}
local candidate = expedition.restartBootstrapCandidate()
check(candidate ~= nil and candidate.id == "beta"
        and candidate.x == 6400 and candidate.y == 6400
        and candidate.slotSqlId == 2,
    "the paused mission exposes the exact leader's pending native tile")
exported = expedition.export()
check(#exported.survivors == 2 and exported.leaderId == "beta"
        and exported.slotSqlId == 2,
    "a pause save retains every still-pending survivor")

function getWorld()
    return { getCell = function()
        return { getGridSquare = function() return nil end }
    end }
end
resumed, reason = expedition.pulse()
check(resumed == false and reason == "expedition_restart_waiting_for_native_team"
        and coldStarts == 1 and slot1 == nil,
    "ordinary mission pulse queues one cold loader for the pending remote leader")
resumed, reason = expedition.pulse()
check(resumed == false and coldStarts == 1,
    "a pending native loader is not queued again")
slot1 = cold
actors.beta, actors.gamma = leader, follower
expedition.holdColdHandoffForTest(true)
resumed, reason = expedition.pulse()
check(resumed == false and reason == "expedition_restart_handoff_held_for_test"
        and slot1 == cold and expedition.current().restoring == true,
    "crash probe holds the temporary native slot before leader handoff")
expedition.holdColdHandoffForTest(false)
resumed, reason = expedition.pulse()
check(resumed == true and reason == "expedition_resumed"
        and slot1 == leader and coldStarts == 1,
    "ordinary mission pulse hands the loaded view to the exact restored leader")
check(expedition.current().technicalIssue == nil
        and expedition.current().bootstrapActor == nil,
    "resumption clears the technical pause and temporary loader reference")

leader.dead, follower.dead = true, true
resumed, reason = expedition.pulse()
check(resumed == false and reason == "member_corpse_pending"
        and slot1 == leader and expedition.current() ~= nil,
    "dead team keeps its loaded view until native corpses are ready")
leader.corpseReady, follower.corpseReady = true, true
resumed, reason = expedition.pulse()
check(resumed == true and reason == "all_dead"
        and expedition.current() == nil
        and expedition.lastOutcome() == "all_dead"
        and slot1 == nil,
    "a saved earlier casualty does not block the final native death release")
idle = expedition.export()
check(idle ~= nil and idle.schema == 2 and idle.slotSqlId == 2,
    "an all-dead team retains the released slot for surviving companions")
actors.delta = reserve
local radioHook, attachedRadioHook
Events = { OnDeviceText = {
    Add = function(callback) radioHook = callback; attachedRadioHook = callback end,
    Remove = function(callback)
        check(attachedRadioHook == callback,
            "only the expedition's own radio callback is removed")
        attachedRadioHook = nil
    end,
} }
started, newMission = expedition.start({ { id = "delta", actor = reserve } })
check(started == true and newMission.leader.actor == reserve
        and slot1 == reserve and lastPromotionSlot == 2
        and expedition.lastOutcome() == nil and attachedRadioHook ~= nil,
    "an outside saved companion can start after an all-dead expedition")

local prepared, prepareReason = expedition.prepareReset()
check(prepared == true and slot1 == nil and attachedRadioHook == nil
        and newMission.suspended == true and released and uiDestroyed,
    "world exit releases only its view, UI and callback before actor disposal")
check(expedition.prepareReset() == true,
    "retrying world exit does not release the slot twice")
check(expedition.reset() == true and expedition.current() == nil
        and expedition.export() == nil,
    "completed runtime teardown forgets the old-world mission and slot")
check(radioHook("stale", "stale", 0, 0, 0, "stale", {}) == nil
        and expedition.radioCommandAuthorized(reserve, "set_move_mode", "walk", player) == false,
    "a late radio callback cannot revive a closed mission")

-- A scout owns its own sequence of short, loaded outdoor legs. The plan is
-- checked before the native slot is promoted, and survives a world reload.
SC.GameplayUtil = {
    position = function(value) return value.x, value.y, 0 end,
    nameOf = function(actor) return actor.name or "Companion" end,
    nowMs = function() return scoutClock end,
    isSquareFree = function() return true end,
    canSee = function() return true end,
    squareKey = function(value)
        return tostring(value.x) .. ":" .. tostring(value.y) .. ":0"
    end,
    call = function(value, method)
        if value == nil or type(value[method]) ~= "function" then
            return nil, false
        end
        return value[method](value), true
    end,
}
scoutClock = 1000
local squareFor
squareFor = function(x, y)
    return { x = x, y = y, getRoom = function() return nil end }
end
function reserve:getCurrentSquare()
    return squareFor(math.floor(self.x), math.floor(self.y))
end
function getWorld()
    return { getCell = function()
        return { getGridSquare = function(_, x, y, z)
            if z == 0 then return squareFor(x, y) end
        end }
    end }
end
SC.Navigation = {
    findPath = function(source, target)
        return { source, squareFor(source.x + 1, source.y), target }
    end,
}
SC.Senses = {
    cached = function(actor, runtime)
        assert(runtime == actorRuntimes.delta,
            "scout reads the registered decision runtime's perception snapshot")
        return { valid = true, time = scoutClock,
            origin = { square = actor:getCurrentSquare() },
            scannedSquares = 12, scanComplete = true,
            scanDiscoveryComplete = true, scanVisualComplete = true,
            nativeDiscovery = { complete = true, freshComplete = true },
            threats = {} }
    end,
}
function getGameTime()
    return { getWorldAgeHours = function() return worldHour or 431.25 end }
end
SC.Persistence = nil
actorRuntimes.delta = {}
local beforeInvalidPromotion = promotions
local invalidStart = expedition.start({ { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 23, y = 20, z = 0 } })
check(invalidStart == false and promotions == beforeInvalidPromotion,
    "a too-close scout target is rejected before slot promotion")
local invalidScout = {
    schema = 3, roster = { "delta" }, survivors = { "delta" },
    leaderId = "delta", radioSession = "scout-session", radioSequence = 0,
    scout = { phase = "inbound", destination = { x = 80, y = 20, z = 0 },
        returnPoint = { x = 20, y = 20, z = 0 }, legs = -1 },
}
check(expedition.restore(invalidScout) == false,
    "a corrupted saved scout itinerary cannot be resumed")
started, newMission = expedition.start({ { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 80, y = 20, z = 0 } })
check(started == true and newMission.scout.phase == "outbound"
        and newMission.scout.returnPoint.x == 20 and slot1 == reserve,
    "a valid scout saves its departure rally and promotes the actual companion")
expedition.pulse()
check(newMission.testWaypoint ~= nil and newMission.testWaypoint.x > reserve.x,
    "scout selects a loaded forward leg without a harness waypoint")
local firstWaypoint = newMission.testWaypoint
scoutClock = scoutClock + 13000
expedition.pulse()
check(newMission.testWaypoint ~= nil
        and (newMission.testWaypoint.x ~= firstWaypoint.x
            or newMission.testWaypoint.y ~= firstWaypoint.y)
        and newMission.scout.replans == 1,
    "a stalled scout abandons its target and chooses a different loaded leg")
local recoveredWaypoint = newMission.testWaypoint
reserve.x, reserve.y = recoveredWaypoint.x, recoveredWaypoint.y
check(expedition.noteTestWaypointArrived(reserve) == true
        and newMission.scout.replans == 0,
    "a completed leg clears the consecutive stall count")
local scoutSaved = expedition.export()
check(scoutSaved.schema == 3 and scoutSaved.scout.destination.x == 80
        and scoutSaved.scout.phase == "outbound",
    "the unfinished scout route is durably described")
check(expedition.prepareReset() == true and expedition.reset() == true,
    "a planned scout relinquishes its old-world native view")
check(expedition.restore(scoutSaved) == true,
    "the saved scout itinerary is accepted after world reload")
resumed, reason = expedition.pulse()
check(resumed == true and reason == "expedition_resumed"
        and expedition.current().scout.destination.x == 80,
    "the restored scout reacquires its actual leader and destination")
local reachedOut, reachedHome, inboundReloaded = false, false, false
for index = 1, 40 do
    scoutClock = scoutClock + 6000
    expedition.pulse()
    local active = expedition.current()
    if active == nil then reachedHome = true break end
    if active.scout.phase == "observing" then reachedOut = true end
    if active.scout.phase == "inbound" and not inboundReloaded then
        local returnSaved = expedition.export()
        check(returnSaved.schema == 3 and #returnSaved.scout.trail > 1
                and returnSaved.scout.returnIndex >= 1
                and returnSaved.scout.observation.status == "complete"
                and returnSaved.scout.observation.scannedSquares == 12
                and returnSaved.scout.observation.visibleSquares == 9
                and returnSaved.scout.observation.worldHour == 431.25,
            "the observed site and reverse checkpoints are saved during return")
        check(expedition.prepareReset() == true
                and expedition.reset() == true
                and expedition.restore(returnSaved) == true,
            "the return itinerary survives a second world reload")
        resumed, reason = expedition.pulse()
        check(resumed == true and reason == "expedition_resumed"
                and expedition.current().scout.returnIndex
                    == returnSaved.scout.returnIndex,
            "the restored team resumes the same reverse checkpoint")
        inboundReloaded = true
        active = expedition.current()
    end
    local waypoint = active.testWaypoint
    if waypoint ~= nil then
        reserve.x, reserve.y = waypoint.x, waypoint.y
        check(expedition.noteTestWaypointArrived(reserve) == true,
            "the native leader completes its current local scout leg")
    end
end
check(reachedOut and inboundReloaded and reachedHome
        and expedition.lastOutcome() == "returned"
        and slot1 == nil,
    "the saved scout visits its goal and automatically releases the view at its original rally"
        .. " out=" .. tostring(reachedOut) .. " home=" .. tostring(reachedHome)
        .. " phase=" .. tostring(expedition.current() and expedition.current().scout.phase)
        .. " position=" .. tostring(reserve.x) .. "," .. tostring(reserve.y)
        .. " outcome=" .. tostring(expedition.lastOutcome()))
local debrief = expedition.lastDebrief()
local idleScout = expedition.export()
check(debrief ~= nil and debrief.observation.status == "complete"
        and idleScout.schema == 2
        and idleScout.debrief.observation.visibleSquares == 9,
    "the joined scout debrief retains only its recorded observation")
check(expedition.reset() == true
        and expedition.restore(idleScout) == true
        and expedition.lastDebrief().observation.visibleSquares == 9,
    "the scout debrief survives an idle-slot reload")

-- A supply trip reuses the same native itinerary, but carries a request and
-- counts only Encounter's verified item receipt for this mission session.
SC.GameplayUtil.itemStableId = function(item)
    return item and item.stableId
end
SC.GameplayUtil.config = function() return 256 end
SC.Logistics = {
    audit = function(actor)
        local items = {}
        for _, item in ipairs(actor.testItems or {}) do
            items[#items + 1] = { item = item }
        end
        return { items = items, capacity = 20, weight = 2, hardRatio = 0.9 }
    end,
}
local beforeInvalidSearchPromotion = promotions
local invalidSearch = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "search", destination = { x = reserve.x + 12, y = 20, z = 0 },
    request = { category = "construction", quantity = 0 },
})
check(invalidSearch == false and promotions == beforeInvalidSearchPromotion,
    "an invalid supply quantity is rejected before native slot promotion")
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "search", destination = { x = reserve.x + 12, y = 20, z = 0 },
    request = { category = "construction", quantity = 1 },
})
check(started == true and newMission.scout.kind == "search"
        and newMission.scout.search.request.quantity == 1,
    "a finite supply request starts with the actual saved companion")
local searchOutbound = expedition.export()
check(searchOutbound.schema == 4 and searchOutbound.scout.kind == "search"
        and searchOutbound.scout.phase == "outbound",
    "the supply itinerary and requested quantity are saved before travel")
check(expedition.prepareReset() == true and expedition.reset() == true
        and expedition.restore(searchOutbound) == true,
    "an outbound supply trip survives world reload")
check(expedition.pulse() == true,
    "the same saved leader reacquires the second view for its supply trip")
local reachedSearch = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local active = expedition.current()
    if active.scout.phase == "searching" then reachedSearch = true break end
    if active.testWaypoint then
        reserve.x, reserve.y = active.testWaypoint.x, active.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
check(reachedSearch and expedition.testSearchFor(reserve)
        and expedition.testSearchCategoryFor(reserve) == "construction"
        and expedition.testSearchMissionIdFor(reserve)
            == expedition.current().radioSession,
    "arrival starts a scoped construction search beside the saved destination")
local searchMissionId = expedition.current().radioSession
check(expedition.noteVerifiedSearchLoot(reserve, {
        verified = true, missionId = "other-mission",
        requestedCategory = "construction", stableId = "lf-item:test-1",
        type = "Base.FiberglassTape", sourceX = 31, sourceY = 20,
        sourceZ = 0,
    }) == false,
    "a verified receipt from a different mission cannot satisfy this request")
local acceptedLoot = expedition.noteVerifiedSearchLoot(reserve, {
    verified = true, missionId = searchMissionId,
    requestedCategory = "construction", stableId = "lf-item:test-1",
    type = "Base.FiberglassTape", sourceX = 31, sourceY = 20,
    sourceZ = 0, sourceObjectIndex = 2,
})
reserve.testItems = { { stableId = "lf-item:test-1" } }
check(acceptedLoot and not expedition.testSearchFor(reserve),
    "one exact requested acquisition closes a one-item search immediately")
expedition.pulse()
local searchInbound = expedition.export()
check(searchInbound.schema == 4
        and searchInbound.scout.phase == "inbound"
        and searchInbound.scout.search.endReason == "quantity_met"
        and #searchInbound.scout.search.acquisitions == 1
        and searchInbound.scout.search.acquisitions[1].sourceObjectIndex == 2,
    "verified cargo and the bounded return decision survive an inbound save")
check(expedition.prepareReset() == true and expedition.reset() == true
        and expedition.restore(searchInbound) == true,
    "the supply return accepts its own saved receipt after reload")
check(expedition.pulse() == true,
    "the restored leader resumes its supply return")
local searchReturned = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local active = expedition.current()
    if active == nil then searchReturned = true break end
    if active.testWaypoint then
        reserve.x, reserve.y = active.testWaypoint.x, active.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
local searchDebrief = expedition.lastDebrief()
check(searchReturned and searchDebrief.kind == "search"
        and searchDebrief.request.quantity == 1
        and #searchDebrief.acquisitions == 1
        and #searchDebrief.returnedIds == 1
        and searchDebrief.returnedIds[1] == "lf-item:test-1"
        and searchDebrief.inventoryComplete == true,
    "the returned result counts the same stable item still carried by the team")
local idleSearch = expedition.export()
check(idleSearch.schema == 2 and idleSearch.debrief.kind == "search"
        and expedition.reset() == true
        and expedition.restore(idleSearch) == true
        and expedition.lastDebrief().returnedIds[1] == "lf-item:test-1",
    "the exact supply result survives an idle-slot reload")

worldHour = 500
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "search", destination = { x = reserve.x + 12, y = 20, z = 0 },
    request = { category = "literature", quantity = 1 },
})
check(started == true,
    "a later supply request may depart with an item from a previous mission")
local emptySearchReached = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local active = expedition.current()
    if active.scout.phase == "searching" then
        emptySearchReached = true break
    end
    if active.testWaypoint then
        reserve.x, reserve.y = active.testWaypoint.x, active.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
check(emptySearchReached and #newMission.scout.search.acquisitions == 0,
    "carried departure stock does not become a search acquisition")
worldHour = 501
expedition.pulse()
check(newMission.scout.phase == "inbound"
        and newMission.scout.search.endReason == "search_deadline",
    "the durable in-world deadline turns an unfilled search home")
local emptySearchReturned = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local active = expedition.current()
    if active == nil then emptySearchReturned = true break end
    if active.testWaypoint then
        reserve.x, reserve.y = active.testWaypoint.x, active.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
local emptyDebrief = expedition.lastDebrief()
check(emptySearchReturned and emptyDebrief.kind == "search"
        and emptyDebrief.endReason == "search_deadline"
        and #emptyDebrief.acquisitions == 0
        and #emptyDebrief.returnedIds == 0,
    "an exhausted time budget reports zero verified acquisitions and returns")

-- The selected whole-trip return time applies during outbound travel too.
-- A search that turns back before reaching its site has no fabricated loot.
reserve.x, reserve.y = 23, 20
worldHour = 600
local beforeBadTimePromotion = promotions
local badTime, badTimeReason = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "scout", destination = { x = 80, y = 20, z = 0 },
    turnHomeAfterHours = 0.1,
})
check(badTime == false and badTimeReason == "invalid_return_time"
        and promotions == beforeBadTimePromotion,
    "an invalid return time is rejected before taking the second player slot")
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "scout", destination = { x = 80, y = 20, z = 0 },
    turnHomeAfterHours = 0.5,
})
check(started and newMission.scout.turnHomeAtHour == 600.5,
    "the scout stores an absolute in-world turn-home time")
expedition.pulse()
check(newMission.testWaypoint ~= nil and newMission.scout.phase == "outbound",
    "the timed scout begins normal outbound travel")
worldHour = 600.5
scoutClock = scoutClock + 1000
expedition.pulse()
check(newMission.scout.phase == "inbound"
        and newMission.scout.endReason == "return_time_reached"
        and newMission.testWaypoint == nil,
    "the scout abandons its outbound waypoint when the return time arrives")
local timedScoutSave = expedition.export()
check(timedScoutSave.scout.turnHomeAtHour == 600.5
        and timedScoutSave.scout.endReason == "return_time_reached"
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(timedScoutSave),
    "the timed scout's return decision survives restart")
check(expedition.pulse() == true, "the timed scout's leader reacquires slot 1")
expedition.pulse()
local timedScoutDebrief = expedition.lastDebrief()
check(expedition.current() == nil and timedScoutDebrief.kind == "scout"
        and timedScoutDebrief.observation == nil
        and timedScoutDebrief.endReason == "return_time_reached",
    "a scout that turned back early reports no invented site observation")

-- A clicked equipped radio must receive an exact leader-side native text
-- acknowledgement before the outbound mission changes to its return trail.
local senderData = {
    getIsTwoWay = function() return true end,
    getIsTurnedOn = function() return true end,
    getHasBattery = function() return true end,
    getPower = function() return 1 end,
    getMicIsMuted = function() return false end,
    isNoTransmit = function() return false end,
    getTransmitRange = function() return 100 end,
    getChannel = function() return 90000 end,
}
local playerInventory, reserveInventory = {}, {}
function player:getInventory() return playerInventory end
function reserve:getInventory() return reserveInventory end
local sender = { container = playerInventory,
    getDeviceData = function() return senderData end }
function sender:getContainer() return self.container end
local receiver = { container = reserveInventory,
    getDeviceData = function() return senderData end }
function receiver:getContainer() return self.container end
function player:getEquipedRadio() return sender end
function player:getPrimaryHandItem() return sender end
function player:getSecondaryHandItem() return nil end
function player:getClothingItem_Back() return nil end
function reserve:getEquipedRadio() return receiver end
function reserve:getPrimaryHandItem() return receiver end
function reserve:getSecondaryHandItem() return nil end
function reserve:getClothingItem_Back() return nil end
SCSplitScreenProbe.isLeaderRadioTextContextActive = function() return true end
SCSplitScreenProbe.sendTestRadioWithLeaderText = function(_x, _y, _channel,
        message, guid, codes)
    radioHook(guid, codes, 0, 0, 0, message, receiver)
end
worldHour = 650
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "scout", destination = { x = 80, y = 20, z = 0 },
    turnHomeAfterHours = 2,
})
check(started == true and newMission.scout.phase == "outbound",
    "radio return probe begins with a moving mission")
expedition.pulse()
sender.container = {}
local packedReturn, packedReason = expedition.sendRadioOrder(player,
    "return_now", "now")
check(packedReturn == false and packedReason == "local_radio_not_equipped"
        and newMission.scout.phase == "outbound",
    "a hand reference to a walkie packed inside a bag cannot send an order")
sender.container = playerInventory
receiver.container = {}
local packedLeaderReturn, packedLeaderReason = expedition.sendRadioOrder(player,
    "return_now", "now")
check(packedLeaderReturn == false and packedLeaderReason == "radio_no_ack"
        and newMission.scout.phase == "outbound",
    "a hand reference to a leader walkie inside a bag cannot acknowledge")
receiver.container = reserveInventory
local radioReturn, radioReason = expedition.sendRadioOrder(player,
    "return_now", "now")
check(radioReturn == true and radioReason == "returning"
        and newMission.scout.phase == "inbound"
        and newMission.scout.endReason == "radio_return"
        and newMission.testWaypoint == nil,
    "acknowledged radio return abandons the outbound leg immediately")
check(expedition.prepareReset() and expedition.reset(),
    "radio return probe releases its native slot")

worldHour = 700
reserve.name = "Test Leader"
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "search", destination = { x = 80, y = 20, z = 0 },
    request = { category = "medicine", quantity = 2 },
    turnHomeAfterHours = 0.5, doctrine = "stealth",
})
check(started and newMission.scout.turnHomeAtHour == 700.5,
    "a supply trip stores the same whole-trip deadline")
observed = expedition.describeForPlayer(nil)
check(observed.leaderName == "Test Leader"
        and observed.kind == "search"
        and observed.turnHomeAtHour == 700.5
        and observed.members[1].name == "Test Leader"
        and observed.members[1].visible == false
        and observed.phase == nil and observed.members[1].x == nil,
    "known departure details remain visible without live mission progress")
local savedDoctrine = { combatDoctrine = "weapons_free",
    combatMode = "aggressive", holdFire = false }
local missionDoctrine = expedition.effectiveDoctrineFor(reserve, savedDoctrine)
check(newMission.doctrine == "stealth"
        and missionDoctrine.combatDoctrine == "stealth"
        and missionDoctrine.combatMode == "passive"
        and savedDoctrine.combatDoctrine == "weapons_free",
    "mission combat style is effective only while assigned and leaves saved orders intact")
expedition.pulse()
worldHour = 700.5
scoutClock = scoutClock + 1000
expedition.pulse()
local timedSearchSave = expedition.export()
check(timedSearchSave.scout.phase == "inbound"
        and timedSearchSave.doctrine == "stealth"
        and timedSearchSave.rosterNames.delta == "Test Leader"
        and timedSearchSave.scout.search.startedHour == nil
        and timedSearchSave.scout.search.endReason == "return_time_reached"
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(timedSearchSave),
    "a search may turn home before site arrival and restore that itinerary")
check(expedition.current().doctrine == "stealth",
    "mission-only combat doctrine survives restart")
check(expedition.pulse() == true, "the timed search reacquires its leader")
expedition.pulse()
local timedSearchDebrief = expedition.lastDebrief()
check(expedition.current() == nil and timedSearchDebrief.kind == "search"
        and timedSearchDebrief.endReason == "return_time_reached"
        and #timedSearchDebrief.acquisitions == 0
        and #timedSearchDebrief.returnedIds == 0,
    "the early search return reports zero verified acquisitions")

reserve.x, reserve.y = 23, 20
worldHour = 800
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "scout", destination = { x = 80, y = 20, z = 0 },
    arriveByHour = 801,
})
check(started and newMission.scout.departureHour == 800
        and newMission.scout.arriveByHour == 801,
    "an arrival target records both absolute departure and due times")
expedition.pulse()
local firstTimedLeg = newMission.testWaypoint
check(firstTimedLeg ~= nil,
    "the arrival target allows the measured outbound route to begin")
reserve.x, reserve.y = firstTimedLeg.x, firstTimedLeg.y
expedition.noteTestWaypointArrived(reserve)
worldHour = 800.4
scoutClock = scoutClock + 1000
expedition.pulse()
check(newMission.scout.phase == "inbound"
        and newMission.scout.endReason == "arrival_reserve_reached"
        and worldHour < newMission.scout.arriveByHour,
    "measured outbound pace reserves time for the same route home")
local arriveBySave = expedition.export()
check(arriveBySave.scout.departureHour == 800
        and arriveBySave.scout.arriveByHour == 801
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(arriveBySave),
    "the arrival target and early return decision survive restart")
check(expedition.pulse() == true,
    "the arrival-target leader reacquires its saved view")
local arriveByReturned = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local active = expedition.current()
    if active == nil then arriveByReturned = true break end
    if active.testWaypoint then
        reserve.x, reserve.y = active.testWaypoint.x, active.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
check(arriveByReturned and expedition.lastDebrief().endReason
        == "arrival_reserve_reached"
        and expedition.lastDebrief().observation == nil,
    "the arrival-target scout returns without claiming an unvisited site")

reserve.x, reserve.y = 23, 20
worldHour = 900
started, newMission = expedition.start({ { id = "delta", actor = reserve } }, {
    kind = "search", destination = { x = 80, y = 20, z = 0 },
    request = { category = "medicine", quantity = 1 },
    arriveByHour = 900.5,
})
check(started and newMission.scout.search.startedHour == nil,
    "an arrival-target search departs before opening its site")
expedition.pulse()
worldHour = 900.3
scoutClock = scoutClock + 1000
expedition.pulse()
local earlySearchSave = expedition.export()
check(earlySearchSave.scout.phase == "inbound"
        and earlySearchSave.scout.search.startedHour == nil
        and earlySearchSave.scout.search.endReason == "arrival_reserve_reached"
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(earlySearchSave),
    "an arrival-target search restores after turning back before site entry")
check(expedition.pulse() == true,
    "the early search's original leader reacquires slot 1")
expedition.pulse()
check(expedition.current() == nil
        and expedition.lastDebrief().endReason == "arrival_reserve_reached"
        and #expedition.lastDebrief().acquisitions == 0,
    "the early search debrief contains no fabricated supply receipts")
worldHour = nil

-- The player-facing place list is a read-only draft. Commit rechecks the
-- current sandbox knowledge pool and the map-derived exterior direction.
reserve.x, reserve.y = 23, 20
local place = { id = "70:10:90:30", label = "Store",
    knowledge = "map_metadata_unconfirmed", street = "Oak St" }
local placeVisible, approachReady = true, true
local siteArrivalReady = false
SC.ExpeditionPlaces = {
    targetableNearby = function(x, y, radius, limit)
        check(x == 20 and y == 20 and radius == 200 and limit == 32,
            "place selection reads the player's bounded nearby area")
        return placeVisible and { place } or {}
    end,
    targetableById = function(x, y, radius, id)
        check(x == reserve.x and y == reserve.y and radius == 200
                and id == place.id,
            "dispatch rechecks the selected footprint near the leader")
        return placeVisible and place or nil,
            placeVisible and nil or "place_no_longer_selectable"
    end,
    plannedApproach = function(candidate, actor)
        check(candidate == place and actor == reserve,
            "the selected leader rechecks the exact place footprint")
        if not approachReady then return nil, "approach_exterior_unavailable" end
        return { x = 80, y = 20, z = 0 }
    end,
    loadedSiteApproach = function(siteId, actor)
        check(siteId == place.id and actor == reserve,
            "the moving leader rechecks the selected building on arrival")
        if not siteArrivalReady then
            return nil, "approach_no_loaded_path"
        end
        return { x = 80, y = 19, z = 0 }
    end,
    visibleSiteSquare = function() return false end,
}
local beforePlaceDraft = promotions
local missingChoices, missingReason = expedition.placeCandidates("missing")
check(missingChoices == nil and missingReason == "leader_unavailable",
    "a stale selected leader cannot silently use the player's target range")
local choices = expedition.placeCandidates()
check(#choices == 1 and choices[1].knowledge == "map_metadata_unconfirmed"
        and promotions == beforePlaceDraft and expedition.current() == nil,
    "listing nearby places neither promotes nor assigns a companion")
placeVisible = false
local placed, placeReason = expedition.startAtPlace(
    { { id = "delta", actor = reserve } }, place.id, "scout")
check(placed == false and placeReason == "place_no_longer_selectable"
        and promotions == beforePlaceDraft,
    "a candidate removed by the current knowledge policy cannot start a trip")
placeVisible, approachReady = true, false
placed, placeReason = expedition.startAtPlace(
    { { id = "delta", actor = reserve } }, place.id, "scout")
check(placed == false and placeReason == "approach_exterior_unavailable"
        and promotions == beforePlaceDraft,
    "a footprint without an exterior coordinate fails before assignment")
approachReady = true
placed, newMission = expedition.startAtPlace(
    { { id = "delta", actor = reserve } }, place.id, "scout",
    { turnHomeAfterHours = 1 })
check(placed and newMission.scout.destination.x == 80
        and newMission.scout.site.id == place.id
        and newMission.scout.site.knowledge == "map_metadata_unconfirmed",
    "a map exterior direction starts Scout before the destination is loaded")
reserve.x, reserve.y = 78, 20
expedition.pulse()
check(newMission.scout.phase == "outbound"
        and newMission.scout.siteApproachConfirmed ~= true,
    "the team does not claim arrival while the site route is unavailable")
siteArrivalReady = true
scoutClock = scoutClock + 3000
expedition.pulse()
check(newMission.scout.destination.x == 80
        and newMission.scout.destination.y == 19
        and newMission.scout.siteApproachConfirmed == true
        and newMission.scout.phase == "observing",
    "the loaded arrival rechecks access and selects the reachable exterior")
scoutClock = scoutClock + 6000
expedition.pulse()
check(newMission.scout.phase == "observing"
        and newMission.scout.observationReason == "selected_site_not_visible",
    "a selected building remains unconfirmed when only nearby squares are visible")
scoutClock = scoutClock + 30000
expedition.pulse()
check(newMission.scout.phase == "inbound"
        and newMission.scout.observation.status == "unavailable",
    "the sight deadline reports an unconfirmed site before returning")
reserve.x, reserve.y = 23, 20
local placedSave = expedition.export()
check(placedSave.scout.site.street == "Oak St"
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(placedSave),
    "the selected place description survives a mission restart")
check(expedition.pulse() == true
        and expedition.current().scout.site.id == place.id,
    "the restored leader keeps the selected site identity")
check(expedition.finishAtPlayer(player) == true
        and expedition.lastDebrief().site.id == place.id,
    "the read-only debrief names the same selected site")
SC.ExpeditionPlaces.siteContainsPoint = function(siteId, x, y, z)
    return siteId == place.id and x >= 70 and x <= 90
        and y >= 10 and y <= 30 and z == 0
end
local siteSearchStarted, siteSearch = expedition.startAtPlace(
    { { id = "delta", actor = reserve } }, place.id, "search",
    { request = { category = "construction", quantity = 1 } })
siteSearch.scout.phase = "searching"
siteSearch.scout.search.startedHour = 431.25
siteSearch.scout.search.deadlineHour = 432.25
local scopedSite = expedition.searchSiteFor(reserve)
check(siteSearchStarted and scopedSite.buildingId == place.id,
    "the selected building identity reaches the Search scan")
local siteMissionId = siteSearch.radioSession
check(not expedition.noteVerifiedSearchLoot(reserve, {
        verified = true, missionId = siteMissionId,
        requestedCategory = "construction", stableId = "outside-source",
        type = "Base.FiberglassTape", sourceX = 65,
        sourceY = 20, sourceZ = 0,
    }) and #siteSearch.scout.search.acquisitions == 0,
    "verified loot from the next building cannot satisfy this Search")
check(expedition.noteVerifiedSearchLoot(reserve, {
        verified = true, missionId = siteMissionId,
        requestedCategory = "construction", stableId = "inside-source",
        type = "Base.FiberglassTape", sourceX = 80,
        sourceY = 20, sourceZ = 0,
    }) and #siteSearch.scout.search.acquisitions == 1,
    "only a source in the selected building counts toward the request")
check(expedition.finishAtPlayer(player) == true,
    "the scoped Search releases its leader")

local usefulStarted, usefulSearch = expedition.startAtPlace(
    { { id = "delta", actor = reserve } }, place.id, "search",
    { request = { category = "useful", quantity = 1 } })
check(usefulStarted and usefulSearch.scout.search.request.category == "useful",
    "an everything-useful supply request is admitted as a real Search")
usefulSearch.scout.phase = "searching"
usefulSearch.scout.search.startedHour = 431.25
usefulSearch.scout.search.deadlineHour = 432.25
local usefulMissionId = usefulSearch.radioSession
check(not expedition.noteVerifiedSearchLoot(reserve, {
        verified = true, missionId = usefulMissionId,
        requestedCategory = "food", stableId = "useful-wrong-request",
        type = "Base.CannedCorn", sourceX = 80, sourceY = 20,
        sourceZ = 0,
    }) and expedition.noteVerifiedSearchLoot(reserve, {
        verified = true, missionId = usefulMissionId,
        requestedCategory = "useful", stableId = "useful-food",
        type = "Base.CannedCorn", sourceX = 80, sourceY = 20,
        sourceZ = 0,
    }) and #usefulSearch.scout.search.acquisitions == 1,
    "only a verified receipt for the broad request counts toward its quantity")
check(expedition.finishAtPlayer(player) == true,
    "the everything-useful Search releases its leader")

-- Every living member of a Search may use Encounter's own container search.
-- Each exact receipt belongs to the actor carrying it, and the shared target
-- closes the request before a fourth item can be credited.
local scouts = { actorAt(reserve.x + 1, reserve.y),
    actorAt(reserve.x, reserve.y + 1) }
for index, actor in ipairs(scouts) do
    actors["search-mate-" .. index] = actor
    function actor:getCurrentSquare() return { getRoom = function() return {} end } end
end
local formerRand = ZombRand
ZombRand = function() return 0 end
local beforeArrivalSpeech = #departures
local teamStarted, teamSearch = expedition.start({
    { id = "delta", actor = reserve },
    { id = "search-mate-1", actor = scouts[1] },
    { id = "search-mate-2", actor = scouts[2] },
}, {
    kind = "search",
    destination = { x = reserve.x + 12, y = reserve.y, z = 0 },
    request = { category = "useful", quantity = 3 },
})
check(teamStarted == true, "a three-member supply team starts")
local teamArrived = false
for index = 1, 30 do
    scoutClock = scoutClock + 1000
    for _, actor in ipairs(scouts) do
        actor.x, actor.y = reserve.x + 1, reserve.y
    end
    expedition.pulse()
    if teamSearch.scout.phase == "searching" then teamArrived = true break end
    if teamSearch.testWaypoint then
        reserve.x, reserve.y = teamSearch.testWaypoint.x, teamSearch.testWaypoint.y
        expedition.noteTestWaypointArrived(reserve)
    end
end
check(teamArrived and #departures > beforeArrivalSpeech
        and departures[#departures].topic == "expedition.search_arrival",
    "the arriving squad occasionally calls out before searching")
check(teamArrived and math.abs(teamSearch.scout.search.deadlineHour
        - teamSearch.scout.search.startedHour - 1.25) < 0.0001,
    "a three-carrier request gets enough Search time for separate approaches")
for _, actor in ipairs({ reserve, scouts[1], scouts[2] }) do
    check(expedition.testSearchFor(actor)
            and expedition.testSearchCategoryFor(actor) == "useful"
            and expedition.searchSiteFor(actor) ~= nil,
        "each living member receives the same site-scoped Search")
end
local teamSession = teamSearch.radioSession
for index, actor in ipairs({ reserve, scouts[1], scouts[2] }) do
    check(expedition.noteVerifiedSearchLoot(actor, {
        verified = true, missionId = teamSession,
        requestedCategory = "useful", stableId = "team-loot-" .. index,
        type = "Base.CannedCorn", sourceX = teamSearch.scout.destination.x,
        sourceY = teamSearch.scout.destination.y, sourceZ = 0,
    }) == true, "each member can contribute an exact native loot receipt")
    if index < 3 then
        check(not expedition.testSearchFor(actor)
                and expedition.testSearchFor(scouts[index]),
            "a member who just looted yields the next search turn")
    end
    if index == 1 then
        scoutClock = scoutClock + 60001
        check(expedition.testSearchFor(reserve),
            "a quiet search lets a previous carrier resume after sixty seconds")
    end
end
check(#teamSearch.scout.search.acquisitions == 3
        and teamSearch.scout.search.acquisitions[1].memberId == "delta"
        and teamSearch.scout.search.acquisitions[2].memberId == "search-mate-1"
        and teamSearch.scout.search.acquisitions[3].memberId == "search-mate-2"
        and not expedition.testSearchFor(scouts[1]),
    "cargo is attributed to each carrier and the shared quantity closes Search")
local cancelled = {}
SC.Encounter = { cancelScavenge = function(actor)
    cancelled[actor] = true
end }
expedition.pulse()
check(teamSearch.scout.phase == "inbound"
        and cancelled[reserve] and cancelled[scouts[1]]
        and cancelled[scouts[2]],
    "turning home cancels all three container approaches")
SC.Encounter = nil
ZombRand = formerRand
reserve.x, reserve.y = player.x + 1, player.y
for index, actor in ipairs(scouts) do
    actor.x, actor.y = player.x + index + 1, player.y
    actor.testItems = { { stableId = "team-loot-" .. (index + 1) } }
end
reserve.testItems = { { stableId = "team-loot-1" } }
check(expedition.finishAtPlayer(player) == true,
    "the team Search releases its leader after recording all carriers")
check(#expedition.lastDebrief().returnedIds == 3,
    "the debrief finds the three exact requested items on their carriers")

-- The review names long off-road stretches at either end of a road route.
local realPlan = SC.ExpeditionRoute.plan
SC.ExpeditionRoute.plan = function(actor, goal)
    return { points = { { x = actor.x + 40, y = actor.y, street = "Oak St" },
            { x = goal.x - 60, y = goal.y, street = "Oak St" } },
        index = 1, roadLength = 150, inferredJunctions = 0,
        goal = { x = goal.x, y = goal.y, z = goal.z } }
end
local preview = expedition.previewAtPlace({ actor = reserve }, place, "road")
check(preview ~= nil and preview.mode == "road" and preview.distance == 150
        and preview.offRoadStart == 40 and preview.offRoadEnd == 60,
    "the road preview names the off-road stretches at both ends")
SC.ExpeditionRoute.plan = realPlan

-- The long road itinerary keeps native movement ownership and replans its
-- return from the leader's real position. Save data has no native graph.
local routeCalls = {}
SC.ExpeditionRoute.plan = function(actor, goal, _, avoidance)
    routeCalls[#routeCalls + 1] = { x = actor.x, y = actor.y,
        goalX = goal.x, goalY = goal.y,
        avoidance = avoidance }
    local direction = goal.x >= actor.x and 1 or -1
    return { points = { { x = actor.x + direction * 10, y = actor.y },
            { x = goal.x - direction * 10, y = goal.y } },
        index = 1, fingerprint = "test-roads", goal = {
            x = goal.x, y = goal.y, z = goal.z }, roadLength = 150,
        avoidance = avoidance }
end
SC.ExpeditionRoute.verifyEntry = function() return true end
SC.Config = { get = function(key)
    if key == "expeditionDestinationRadius" then return 200 end
    if key == "expeditionRoadRoutingEnabled" then return true end
end }
reserve.x, reserve.y = 23, 20
worldHour = 1100
local roadStarted, roadMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        turnHomeAfterHours = 1, travelMode = "road" })
check(roadStarted == true and roadMission.scout.road ~= nil
        and #routeCalls == 1 and routeCalls[1].x == 23,
    "a 167-tile mission requires a connected road plan")
local outbound = expedition.export()
check(outbound.schema == 5 and outbound.scout.road.phase == "outbound"
        and outbound.scout.road.fingerprint == "test-roads",
    "road save retains a bounded route descriptor")
local ordinaryCached = SC.Senses.cached
SC.Senses.cached = function()
    local threats = {}
    for index = 1, 4 do
        threats[index] = { x = 28, y = 20,
            visible = true, obstructed = false }
    end
    return { valid = true, reflexTime = scoutClock,
        threats = threats }
end
expedition.pulse()
check(#routeCalls == 2 and routeCalls[2].avoidance ~= nil
        and routeCalls[2].avoidance.x == 28
        and roadMission.scout.hordeDetours == 1
        and roadMission.scout.road.avoidance.x == 28,
    "a fresh horde above three times team size cancels the old road intent and replans")
SC.Senses.cached = ordinaryCached
local detourSave = expedition.export()
check(detourSave.scout.road.avoidance.x == 28,
    "the avoided horde area survives a travel checkpoint")
reserve.x = 125
worldHour = 1101.2
scoutClock = scoutClock + 1000
expedition.pulse()
check(roadMission.scout.phase == "inbound"
        and roadMission.scout.road.phase == "inbound"
        and routeCalls[#routeCalls].x == 125
        and routeCalls[#routeCalls].goalX == player.x
        and routeCalls[#routeCalls].avoidance.x == 28,
    "turn-home replans from the actual leader position")
local inbound = expedition.export()
check(inbound.schema == 5 and inbound.scout.road.phase == "inbound"
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(inbound),
    "an inbound road mission survives a restart")
check(expedition.pulse() == true,
    "the road leader reacquires the second view on restart")
expedition.pulse()
check(routeCalls[#routeCalls].x == 125
        and expedition.current().scout.roadRoute ~= nil,
    "restored road geometry is rebuilt from the current actor")
reserve.x = 23
check(expedition.finishAtPlayer(player) == true,
    "the restored road mission can release its native leader")
local successfulRoadPlan = SC.ExpeditionRoute.plan
SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
    if avoidance ~= nil and goal.x == 190 then
        return nil, "NO_SAFE_ROAD_DETOUR"
    end
    return successfulRoadPlan(actor, goal, continuing, avoidance)
end
local blockedStarted, blockedMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
check(blockedStarted and blockedMission.scout.phase == "outbound",
    "blocked-road probe starts with a real outbound intent")
SC.Senses.cached = function()
    local threats = {}
    for index = 1, 4 do
        threats[index] = { x = 28, y = 20,
            visible = true, obstructed = false }
    end
    return { valid = true, reflexTime = scoutClock,
        threats = threats }
end
expedition.pulse()
check(blockedMission.scout.phase == "inbound"
        and blockedMission.scout.endReason == "horde_no_safe_detour"
        and blockedMission.scout.road.phase == "inbound"
        and blockedMission.scout.road.avoidance.x == 28
        and blockedMission.technicalIssue == nil,
    "no safe outbound road detour turns the team home around the horde")
SC.Senses.cached = ordinaryCached
SC.ExpeditionRoute.plan = successfulRoadPlan
check(expedition.finishAtPlayer(player) == true,
    "the blocked-road return releases the native leader")
SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
    if avoidance ~= nil then return nil, "NO_SAFE_ROAD_DETOUR" end
    return successfulRoadPlan(actor, goal, continuing, avoidance)
end
sender.container = {}
reserve.x, reserve.y = 23, 20
local noRadioStarted, noRadioMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
SC.Senses.cached = function()
    local threats = {}
    for index = 1, 4 do
        threats[index] = { x = 28, y = 20,
            visible = true, obstructed = false }
    end
    return { valid = true, reflexTime = scoutClock,
        threats = threats }
end
scoutClock = scoutClock + 1000
expedition.pulse()
check(noRadioStarted and noRadioMission.scout.phase == "inbound"
        and noRadioMission.scout.pause ~= nil
        and noRadioMission.scout.pause.mode == "seeking_shelter"
        and noRadioMission.scout.pause.reported == false,
    "without radio or a safe road home the squad seeks cover")
SC.Senses.cached = ordinaryCached
sender.container = playerInventory
check(expedition.finishAtPlayer(player) == true,
    "the unconnected blocked-road probe releases its native leader")
-- A real player-side receipt exposes three choices. The leader changes course
-- only after its own exact radio acknowledgement, including on the way home.
SCSplitScreenProbe.sendTestRadioWithLeaderText = function(_x, _y, _channel,
        message, guid, codes)
    local device = (string.find(message, "Horde blocks our route", 1, true)
        or string.find(message, "Sheltered inside a house", 1, true))
        and sender or receiver
    radioHook(guid, codes, 0, 0, 0, message, device)
end
local function blockingContacts(x)
    SC.Senses.cached = function()
        local threats = {}
        for index = 1, 4 do
            threats[index] = { x = x, y = 20,
                visible = true, obstructed = false }
        end
        return { valid = true, reflexTime = scoutClock,
            threats = threats }
    end
end
SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
    if avoidance ~= nil then return nil, "NO_SAFE_ROAD_DETOUR" end
    return successfulRoadPlan(actor, goal, continuing, avoidance)
end
for _, answer in ipairs({ "hold_position", "push_on", "return" }) do
    reserve.x, reserve.y = 23, 20
    worldHour = worldHour + 1
    local radioStarted, radioMission = expedition.start(
        { { id = "delta", actor = reserve } },
        { kind = "scout", destination = { x = 190, y = 20, z = 0 },
            travelMode = "road" })
    blockingContacts(28)
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local view = expedition.describeForPlayer(player)
    check(radioStarted and radioMission.scout.phase == "outbound"
            and radioMission.scout.pause ~= nil
            and radioMission.scout.pause.reported == true
            and view.helpRequest ~= nil,
        "blocked outbound road reports the horde to the player radio")
    local ordered, orderReason = expedition.sendRadioOrder(player,
        "expedition_decision", answer)
    check(ordered == true and radioMission.lastRadioOrder.payload == answer
            and (answer == "hold_position"
                and radioMission.scout.pause.mode == "holding"
                or answer == "push_on"
                    and radioMission.scout.pause == nil
                    and radioMission.scout.pushUntilHour > worldHour
                or answer == "return"
                    and radioMission.scout.pause == nil
                    and radioMission.scout.phase == "inbound"),
        "leader acknowledges and applies the selected blocked-road answer: "
            .. answer .. " / " .. tostring(orderReason))
    SC.Senses.cached = ordinaryCached
    check(expedition.finishAtPlayer(player) == true,
        "answered blocked-road mission releases its native leader")
end
reserve.x, reserve.y = 23, 20
worldHour = worldHour + 1
local homeStarted, homeMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        turnHomeAfterHours = 1, travelMode = "road" })
reserve.x = 125
worldHour = worldHour + 1.2
SC.Senses.cached = ordinaryCached
scoutClock = scoutClock + 1000
expedition.pulse()
check(homeStarted and homeMission.scout.phase == "inbound"
        and homeMission.scout.roadRoute ~= nil,
    "the return-road radio probe starts on the home route")
blockingContacts(120)
scoutClock = scoutClock + 1000
expedition.pulse()
check(homeMission.scout.pause ~= nil
        and homeMission.scout.pause.mode == "seeking_shelter"
        and homeMission.scout.pause.reported == true
        and homeMission.scout.trailReturn == true,
    "a blocked return road reports in and diverts toward shelter")
local homeHold = expedition.sendRadioOrder(player,
    "expedition_decision", "hold_position")
check(homeHold == true and homeMission.scout.pause.mode == "seeking_shelter",
    "a homeward hold order keeps the squad moving to cover")
local shelterLookup = SC.ExpeditionPlaces.nearestLoadedShelter
SC.ExpeditionPlaces.nearestLoadedShelter = function()
    return { x = 126, y = 20, z = 0 }
end
scoutClock = scoutClock + 1000
expedition.pulse()
check(homeMission.scout.pause.shelterTarget.x == 126,
    "the blocked home squad selects a loaded interior refuge")
local pausedSave = expedition.export()
check(pausedSave.scout.pause.reported == true
        and expedition.prepareReset() and expedition.reset()
        and expedition.restore(pausedSave) and expedition.pulse()
        and expedition.current().scout.pause.shelterTarget.x == 126,
    "the blocked home decision and shelter target survive restart")
local originalReserveSquare = reserve.getCurrentSquare
function reserve:getCurrentSquare()
    local square = originalReserveSquare(self)
    if self.x == 126 then
        square.getRoom = function() return { id = "refuge" } end
    end
    return square
end
reserve.x = 126
scoutClock = scoutClock + 1000
expedition.pulse()
scoutClock = scoutClock + 1000
expedition.pulse()
local shelteredView = expedition.describeForPlayer(player)
check(expedition.current().scout.pause.mode == "sheltered"
        and expedition.current().scout.pause.shelterReported == true
        and shelteredView.helpRequest.shelter == true
        and shelteredView.helpRequest.x == 126,
    "shelter arrival sends a second exact radio report with pickup coordinates")
reserve.getCurrentSquare = originalReserveSquare
SC.ExpeditionPlaces.nearestLoadedShelter = shelterLookup
SC.Senses.cached = ordinaryCached
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player) == true,
    "a sheltered return squad can reunite with the player")
reserve.x, reserve.y = 23, 20
worldHour = worldHour + 1
local trailStarted, trailMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        turnHomeAfterHours = 1, travelMode = "road" })
reserve.x = 125
worldHour = worldHour + 1.2
scoutClock = scoutClock + 1000
expedition.pulse()
trailMission.scout.roadRoute = nil
trailMission.scout.trailReturn = true
trailMission.scout.returnIndex = 1
blockingContacts(120)
scoutClock = scoutClock + 1000
expedition.pulse()
check(trailStarted and trailMission.scout.pause ~= nil
        and trailMission.scout.pause.mode == "seeking_shelter"
        and trailMission.scout.pause.reported == true,
    "a new horde on the reached return trail also requests help")
local unsafeReturn, unsafeReason = expedition.sendRadioOrder(player,
    "expedition_decision", "return")
check(unsafeReturn == false and unsafeReason == "NO_SAFE_ROAD_DETOUR"
        and trailMission.scout.pause ~= nil,
    "an acknowledged return order keeps shelter intent when no safe return exists")
local pushed = expedition.sendRadioOrder(player,
    "expedition_decision", "push_on")
check(pushed == true and trailMission.scout.pause == nil
        and trailMission.scout.pushUntilHour > worldHour,
    "an acknowledged push order explicitly releases the blocked trail")
SC.Senses.cached = ordinaryCached
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player) == true,
    "the trail-horde probe releases its native leader")
SC.ExpeditionRoute.plan = successfulRoadPlan
;(function()
    local returnPlans = 0
    SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
        if continuing and goal.x == player.x then
            returnPlans = returnPlans + 1
            return nil, "NO_RETURN_ROAD"
        end
        return successfulRoadPlan(actor, goal, continuing, avoidance)
    end
    reserve.x, reserve.y = 23, 20
    worldHour = 1200
    local started, active = expedition.start(
        { { id = "delta", actor = reserve } },
        { kind = "scout", destination = { x = 190, y = 20, z = 0 },
            turnHomeAfterHours = 1, travelMode = "road" })
    active.scout.trail = {
        { x = 23, y = 20, z = 0 },
        { x = 60, y = 20, z = 0 },
        { x = 100, y = 20, z = 0 },
    }
    reserve.x = 100
    worldHour = 1201.2
    scoutClock = scoutClock + 1000
    expedition.pulse()
    local saved = expedition.export()
    check(started and active.scout.phase == "inbound"
            and active.scout.trailReturn == true
            and active.scout.returnIndex == 2
            and active.technicalIssue == nil and returnPlans == 1
            and saved.scout.trailReturn == true,
        "failed inbound road planning falls back to reached trail instead of pausing")
    check(expedition.roadCombatFor(reserve)
            and expedition.roadCombatFor(reserve).radius == 2.5,
        "road return keeps its short combat leash on reached trail legs")
    check(expedition.prepareReset() and expedition.reset()
            and expedition.restore(saved) and expedition.pulse(),
        "trail return survives reload with its native leader")
    scoutClock = scoutClock + 2000
    expedition.pulse()
    check(expedition.current().scout.trailReturn == true
            and expedition.current().technicalIssue == nil
            and returnPlans == 1,
        "restored trail return does not retry the failed road graph every pulse")
    saved.scout.trailReturn = nil
    check(expedition.prepareReset() and expedition.reset()
            and expedition.restore(saved) and expedition.pulse(),
        "an older inbound road save can restore its native leader")
    scoutClock = scoutClock + 2000
    expedition.pulse()
    check(expedition.current().scout.trailReturn == true
            and expedition.current().technicalIssue == nil
            and returnPlans == 2,
        "an older inbound road save can recover when its new route fails")
    reserve.x = player.x + 3
    check(expedition.finishAtPlayer(player) == true,
        "trail return can still release the native view at the player")
    SC.ExpeditionRoute.plan = successfulRoadPlan
end)()
local savedMedical = SC.Medical
local escort = actorAt(24, 20)
actors.escort = escort
SC.Medical = { assessCached = function(actor)
    return { health = actor == reserve and 40 or 100,
        bleedingCount = actor == reserve and 1 or 0 }
end }
local woundedStarted, woundedMission = expedition.start(
    { { id = "delta", actor = reserve }, { id = "escort", actor = escort } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
local beforeWithdrawalPlans = #routeCalls
check(woundedStarted and expedition.roadCombatFor(escort)
        and expedition.roadCombatFor(escort).radius == 2.5,
    "a road follower shares the leader's short combat pursuit leash")
scoutClock = scoutClock + 1000
SC.Senses.cached = function()
    local threats = {}
    for index = 1, 3 do
        threats[index] = { x = 28, y = 20,
            visible = true, obstructed = false }
    end
    return { valid = true, reflexTime = scoutClock, threats = threats }
end
expedition.pulse()
check(woundedStarted and woundedMission.scout.phase == "inbound"
        and woundedMission.scout.endReason == "squad_wounded"
        and #routeCalls == beforeWithdrawalPlans + 1
        and routeCalls[#routeCalls].goalX == player.x
        and routeCalls[#routeCalls].avoidance ~= nil,
    "a bleeding low-health member turns the whole road squad home around a smaller group")
SC.Senses.cached = ordinaryCached
check(expedition.finishAtPlayer(player) == true,
    "the wounded squad can release its leader after turning home")
escort.x = reserve.x + 1
worldHour = 1300
local woundedSearchStarted, woundedSearch = expedition.start(
    { { id = "delta", actor = reserve }, { id = "escort", actor = escort } },
    { kind = "search", destination = { x = 190, y = 20, z = 0 },
        request = { category = "construction", quantity = 1 },
        travelMode = "straight" })
woundedSearch.scout.phase = "searching"
woundedSearch.scout.search.startedHour = worldHour
woundedSearch.scout.search.deadlineHour = worldHour + 1
escort.x = reserve.x + 50
scoutClock = scoutClock + 1000
expedition.pulse()
check(woundedSearchStarted and woundedSearch.scout.phase == "inbound"
        and woundedSearch.scout.search.endReason == "squad_wounded",
    "a wounded Search squad returns even while one follower is separated")
escort.x = reserve.x + 1
check(expedition.finishAtPlayer(player) == true,
    "the wounded Search can release its leader")
SC.Medical = { assessCached = function()
    return { health = 100, bleedingCount = 0 }
end }
escort.x = reserve.x + 1
local deadlineStarted, deadlineSearch = expedition.start(
    { { id = "delta", actor = reserve }, { id = "escort", actor = escort } },
    { kind = "search", destination = { x = 190, y = 20, z = 0 },
        request = { category = "construction", quantity = 1 },
        travelMode = "straight" })
deadlineSearch.scout.phase = "searching"
deadlineSearch.scout.search.startedHour = worldHour - 1
deadlineSearch.scout.search.deadlineHour = worldHour
escort.x = reserve.x + 50
scoutClock = scoutClock + 1000
expedition.pulse()
check(deadlineStarted and deadlineSearch.scout.phase == "inbound"
        and deadlineSearch.scout.search.endReason == "search_deadline",
    "a Search deadline takes effect before waiting for a distant follower")
escort.x = reserve.x + 1
check(expedition.finishAtPlayer(player) == true,
    "the deadline Search can release its leader")
SC.Medical = savedMedical
escort.x = reserve.x + 1
local sharedSightStarted, sharedSight = expedition.start(
    { { id = "delta", actor = reserve }, { id = "escort", actor = escort } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
local memberContacts = { [reserve] = {}, [escort] = {} }
for _, member in ipairs({ reserve, escort }) do
    for index = 1, 4 do
        memberContacts[member][index] = { actor = {},
            x = reserve.x + 5, y = reserve.y,
            visible = true, obstructed = false }
    end
end
SC.Senses.cached = function(actor)
    return { valid = true, reflexTime = scoutClock,
        threats = memberContacts[actor] }
end
local beforeSharedSightPlans = #routeCalls
scoutClock = scoutClock + 1000
expedition.pulse()
check(sharedSightStarted and sharedSight.scout.hordeDetours == 1
        and #routeCalls == beforeSharedSightPlans + 1
        and routeCalls[#routeCalls].avoidance ~= nil
        and routeCalls[#routeCalls].avoidance.seen == 8,
    "contacts seen across the squad trigger a detour above the team threshold")
SC.Senses.cached = ordinaryCached
check(expedition.finishAtPlayer(player) == true,
    "the shared-sight squad releases its leader")
actors.escort = nil
local stalledStarted, stalledMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
stalledMission.scout.phase = "inbound"
stalledMission.scout.returnIndex = 0
stalledMission.scout.replans = 5
stalledMission.scout.bestDistanceToWaypoint = 10
stalledMission.scout.lastProgressAt = scoutClock - 31000
stalledMission.scout.waypointStagedAt = scoutClock - 31000
stalledMission.scout.nextHordeCheckAt = scoutClock + 10000
stalledMission.testWaypoint = { x = reserve.x + 10, y = reserve.y, z = 0 }
SC.Senses.cached = function()
    return { valid = true, reflexTime = scoutClock,
        threats = { { x = reserve.x + 5, y = reserve.y,
            visible = true, obstructed = false } } }
end
local beforeStallPlans = #routeCalls
scoutClock = scoutClock + 1000
expedition.pulse()
check(stalledStarted and stalledMission.technicalIssue == nil
        and stalledMission.scout.hordeDetours == 1
        and stalledMission.scout.replans == 0
        and #routeCalls == beforeStallPlans + 1
        and routeCalls[#routeCalls].avoidance ~= nil,
    "a single roadside contact that stalls inbound combat gets one alternate-road plan")
SC.Senses.cached = ordinaryCached
check(expedition.finishAtPlayer(player) == true,
    "the combat-stall detour can release the native leader")
local savedRoadPlan = SC.ExpeditionRoute.plan
local failedDetourStarted, failedDetour = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
failedDetour.scout.phase = "inbound"
failedDetour.scout.replans = 5
failedDetour.scout.bestDistanceToWaypoint = 10
failedDetour.scout.lastProgressAt = scoutClock - 31000
failedDetour.scout.waypointStagedAt = scoutClock - 31000
failedDetour.scout.nextHordeCheckAt = scoutClock + 10000
failedDetour.testWaypoint = { x = reserve.x + 10, y = reserve.y, z = 0 }
SC.ExpeditionRoute.plan = function(actor, goal, continuing, avoidance)
    if avoidance then return nil, "NO_SAFE_ROAD" end
    return savedRoadPlan(actor, goal, continuing, avoidance)
end
SC.Senses.cached = function()
    return { valid = true, reflexTime = scoutClock,
        threats = { { x = reserve.x + 5, y = reserve.y,
            visible = true, obstructed = false } } }
end
scoutClock = scoutClock + 1000
expedition.pulse()
check(failedDetourStarted and failedDetour.technicalIssue == nil
        and failedDetour.scout.trailReturn == true
        and failedDetour.scout.road.avoidance ~= nil
        and failedDetour.scout.road.avoidance.seen == nil
        and expedition.roadCombatFor(reserve).radius == 2.5,
    "failed combat detour keeps the observed hazard and combat leash on trail return")
SC.ExpeditionRoute.plan = savedRoadPlan
SC.Senses.cached = ordinaryCached
check(expedition.finishAtPlayer(player) == true,
    "the protected trail return can release the native leader")
local meetingStarted, meetingMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 80, y = 20, z = 0 },
        travelMode = "straight" })
check(meetingStarted == true, "return rendezvous probe starts")
check(expedition.roadCombatFor(reserve) == nil,
    "straight expedition travel has no road combat leash")
meetingMission.scout.phase = "inbound"
meetingMission.scout.returnIndex = 0
reserve.x = player.x + 9
scoutClock = scoutClock + 2000
expedition.pulse()
check(meetingMission.scout.phase == "inbound"
        and meetingMission.testWaypoint ~= nil,
    "leader continues toward the player at nine tiles instead of waiting too far away")
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player) == true,
    "return rendezvous probe releases the native view")
reserve.x = player.x + 3
local originalFindPath = SC.Navigation.findPath
SC.Navigation.findPath = function() return nil end
local straightStarted, straightMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "straight" })
check(straightStarted == true and straightMission.scout.road == nil
        and expedition.export().schema == 5,
    "straight travel can target 200 tiles without inventing a road")
expedition.pulse()
scoutClock = scoutClock + 31000
expedition.pulse()
check(straightMission.scout.phase == "inbound"
        and straightMission.scout.endReason == "straight_path_unreachable"
        and straightMission.technicalIssue == nil,
    "a blocked straight outbound path turns the team home")
SC.Navigation.findPath = originalFindPath
check(expedition.finishAtPlayer(player) == true,
    "the straight-path fallback releases the leader after return")

-- A Search can turn home before it ever started looking in containers.
reserve.x, reserve.y = 23, 20
local earlyStarted, earlySearch = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "search", destination = { x = 80, y = 20, z = 0 },
        request = { category = "construction", quantity = 2 },
        travelMode = "straight" })
check(earlyStarted == true, "the pre-search recall probe starts")
earlySearch.scout.trail = {
    { x = 23, y = 20, z = 0 }, { x = 40, y = 20, z = 0 },
    { x = 50, y = 20, z = 0 },
}
reserve.x = 55
earlySearch.scout.replans = 5
earlySearch.scout.firstPlanFailureAt = scoutClock - 31000
earlySearch.scout.lastPlanFailure = "old_outbound_goal"
earlySearch.scout.lastStalledTarget = { x = 60, y = 20, z = 0 }
earlySearch.scout.lastPlanAt = scoutClock
local recalled, recallReason = expedition.sendRadioOrder(player,
    "return_now", "now")
check(recalled == true and recallReason == "returning"
        and earlySearch.scout.phase == "inbound"
        and earlySearch.scout.returnIndex == 3
        and earlySearch.scout.replans == 0
        and earlySearch.scout.firstPlanFailureAt == nil
        and earlySearch.scout.lastPlanFailure == nil
        and earlySearch.scout.lastStalledTarget == nil
        and earlySearch.scout.lastPlanAt == nil,
    "mid-leg recall retraces the reached corner with clean inbound planning")
local earlySaved = expedition.export()
local invalidEarly = expedition.export()
invalidEarly.scout.search.endReason = "quantity_met"
check(earlySaved.scout.search.startedHour == nil
        and earlySaved.scout.search.endReason == "radio_return"
        and expedition.prepareReset() and expedition.reset()
        and not expedition.restore(invalidEarly)
        and expedition.restore(earlySaved),
    "a pre-search recall restores while an invented completed Search does not")
reserve.x = player.x + 3
check(expedition.pulse() and expedition.finishAtPlayer(player),
    "the restored pre-search return can rejoin the player")

reserve.x, reserve.y = 23, 20
local heldStarted, heldRoad = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
check(heldStarted == true, "the held-road recall probe starts")
local heldHazard = { x = 80, y = 20, radius = 10 }
heldRoad.scout.pause = { mode = "holding",
    reason = "horde_no_safe_detour", hazard = heldHazard,
    reported = true }
local heldReturn = expedition.sendRadioOrder(player, "return_now", "now")
check(heldReturn == true and heldRoad.scout.phase == "inbound"
        and heldRoad.scout.pause == nil
        and heldRoad.scout.road.avoidance ~= nil
        and heldRoad.scout.road.avoidance.x == heldHazard.x,
    "general radio recall releases a hold and retains its known hazard")
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player),
    "the recalled held-road squad can rejoin the player")

reserve.x, reserve.y = 23, 20
local trailSavedStarted, arrivedTrail = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
check(trailSavedStarted == true, "the reached-trail restore probe starts")
arrivedTrail.scout.phase = "awaiting_player"
arrivedTrail.scout.trailReturn = true
arrivedTrail.scout.returnIndex = 0
arrivedTrail.scout.road.phase = "inbound"
arrivedTrail.scout.road.goal = { x = player.x, y = player.y, z = 0 }
local awaitingTrail = expedition.export()
check(expedition.prepareReset() and expedition.reset()
        and expedition.restore(awaitingTrail)
        and expedition.current().scout.phase == "awaiting_player"
        and expedition.current().scout.trailReturn == true,
    "an arrived trail-return itinerary remains restorable while awaiting the player")
reserve.x = player.x + 3
check(expedition.pulse() and expedition.finishAtPlayer(player),
    "the restored trail return can finish")

reserve.x, reserve.y = 23, 20
local readyStarted, delayedRoad = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road" })
check(readyStarted == true, "the delayed-road-data probe starts")
delayedRoad.scout.roadRoute = nil
local planCalls = 0
SC.ExpeditionRoute.plan = function()
    planCalls = planCalls + 1
    return nil, "DATA_NOT_READY"
end
scoutClock = scoutClock + 1000
expedition.pulse()
check(delayedRoad.technicalIssue == nil
        and delayedRoad.scout.trailReturn ~= true
        and delayedRoad.scout.nextRoadRestartAt == scoutClock + 1000
        and planCalls == 1,
    "missing street data waits instead of terminating or switching to trail")
scoutClock = scoutClock + 500
expedition.pulse()
check(planCalls == 1, "road restart throttles a transient map-data retry")
SC.ExpeditionRoute.plan = savedRoadPlan
scoutClock = scoutClock + 1000
expedition.pulse()
check(delayedRoad.scout.roadRoute ~= nil
        and delayedRoad.scout.nextRoadRestartAt == nil
        and delayedRoad.scout.lastRoadFailure == nil,
    "road restart resumes when native street data becomes ready")
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player),
    "the recovered road probe releases its leader")
reserve.x, reserve.y = 23, 20
worldHour = 1500
local timedStarted, timedRoad = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 190, y = 20, z = 0 },
        travelMode = "road", turnHomeAfterHours = 0.25 })
check(timedStarted == true, "the timed map-readiness probe starts")
timedRoad.scout.roadRoute = nil
SC.ExpeditionRoute.plan = function() return nil, "DATA_NOT_READY" end
worldHour = 1500.3
scoutClock = scoutClock + 1000
expedition.pulse()
check(timedRoad.scout.phase == "inbound"
        and timedRoad.scout.endReason == "return_time_reached"
        and timedRoad.technicalIssue == nil,
    "return time still takes effect while street data is unavailable")
SC.ExpeditionRoute.plan = savedRoadPlan
reserve.x = player.x + 3
check(expedition.finishAtPlayer(player),
    "the timed map-readiness probe releases its leader")

print("EXPEDITION_RESTART_KAHLUA_PASS checks=" .. tostring(checks))
