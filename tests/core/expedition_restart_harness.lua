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
local receiver = { container = reserveInventory }
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

-- The long road itinerary keeps native movement ownership and replans its
-- return from the leader's real position. Save data has no native graph.
local routeCalls = {}
SC.ExpeditionRoute.plan = function(actor, goal, _, avoidance)
    routeCalls[#routeCalls + 1] = { x = actor.x, y = actor.y,
        goalX = goal.x, goalY = goal.y,
        avoidance = avoidance }
    return { points = { { x = actor.x + 10, y = actor.y },
            { x = goal.x - 10, y = goal.y } },
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
local meetingStarted, meetingMission = expedition.start(
    { { id = "delta", actor = reserve } },
    { kind = "scout", destination = { x = 80, y = 20, z = 0 },
        travelMode = "straight" })
check(meetingStarted == true, "return rendezvous probe starts")
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

print("EXPEDITION_RESTART_KAHLUA_PASS checks=" .. tostring(checks))
