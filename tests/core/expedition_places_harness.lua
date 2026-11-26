-- SPDX-License-Identifier: MIT
local Places = SurvivorCompanion.ExpeditionPlaces
local fixture = SurvivorCompanion.ExpeditionPlacesFixture
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, "place check " .. tostring(checks) .. ": " .. message)
end

local nearby, reason = Places.nearby(20, 20, 120, 16)
check(nearby ~= nil and reason == nil and #nearby == 6,
    "bounded metadata query returns six actual buildings")
check(nearby[1].kind == "police" and nearby[1].label == "Police building",
    "police room identifies a police candidate")
check(nearby[2].kind == "fire" and nearby[2].label == "Fire station",
    "fire storage identifies a fire candidate")
check(nearby[3].kind == "store" and nearby[3].label == "Store",
    "grocery room identifies a store candidate")
check(nearby[4].kind == "residence" and nearby[4].label == "House",
    "ordinary bedroom and kitchen identify a house candidate")
check(nearby[5].kind == "unclassified", "unknown rooms remain unclassified")
check(nearby[6].kind == "gas_station" and nearby[6].label == "Gas station",
    "gas store rooms identify a fuel stop")
check(nearby[1].street == "Oak St" and nearby[1].streetDistance == 7,
    "street is descriptive metadata")
check(nearby[1].id == "20:20:30:30"
        and nearby[1].anchor.x == 25 and nearby[1].anchor.y == 25,
    "building footprint provides a stable coordinate target")
check(nearby[1].groundFloor == true and nearby[1].minLevel == 0
        and nearby[1].maxLevel == 1,
    "surface eligibility derives from the building's actual floor range")
check(nearby[1].address == nil and nearby[4].address == nil,
    "no house number or address is invented")
local limited = Places.nearby(20, 20, 120, 2)
check(#limited == 2 and limited[1].distance <= limited[2].distance,
    "nearest candidates are sorted before the result limit")
local invalid, invalidReason = Places.nearby(20, 20, 201, 2)
check(invalid == nil and invalidReason == "invalid_place_query",
    "unbounded radius is rejected")
invalid, invalidReason = Places.nearby(20, 20, 120, 4097)
check(invalid == nil and invalidReason == "invalid_place_query",
    "unbounded result count is rejected")
invalid, invalidReason = Places.describeBuilding({ getX = function() return 20 end })
check(invalid == nil and invalidReason == "building_bounds_unavailable",
    "incomplete map metadata fails closed")
fixture.buildings[1].rooms = fixture.list()
for index = 1, 257 do
    fixture.buildings[1].rooms:add({ getName = function() return "office" end })
end
invalid, invalidReason = Places.describeBuilding(fixture.buildings[1])
check(invalid == nil and invalidReason == "building_rooms_unbounded",
    "corrupt or excessive room metadata is rejected")
fixture.buildings[1].rooms = fixture.list({
    { getName = function() return "policeoffice" end },
})
local source = {
    getX = function() return 10 end,
    getY = function() return 25 end,
    getRoom = function() return nil end,
}
local actor = { getCurrentSquare = function() return source end }
local planned, plannedReason = Places.plannedApproach(nearby[1], actor)
check(planned ~= nil and plannedReason == nil
        and planned.x == 19 and planned.y == 25
        and planned.scope == "map_exterior_pending",
    "map footprint gives the leader a direction without a route search")
local approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach ~= nil and approachReason == nil
        and approach.x == 19 and approach.y == 25
        and approach.side == "west" and approach.pathNodes == 2
        and approach.scope == "loaded_exterior_only",
    "approach uses a native path to a loaded square beside the building")
local restoredApproach = Places.loadedSiteApproach(nearby[1].id, actor)
check(restoredApproach ~= nil and restoredApproach.x == 19,
    "arrival can recheck exterior access from a saved site ID")
local entryActor = {
    getX = function() return 19 end,
    getY = function() return 25 end,
    getCurrentSquare = function()
        return fixture.cell:getGridSquare(19, 25, 0)
    end,
}
local interior = Places.loadedInteriorCandidates(nearby[1].id, entryActor)
check(#interior > 0 and #interior <= 12 and interior[1].x >= 20,
    "arrival offers bounded loaded floor tiles within the selected building")
do
    local oldTopology = SurvivorCompanion.Topology
    SurvivorCompanion.Topology = {classifyEdge = function(_, outside, inside)
        if outside:getX() == 19 and inside:getX() == 20 then
            if outside:getY() == 25 then return {affordance="door", reason="door_locked"} end
            if outside:getY() == 24 then return {affordance="window", traversable=true} end
        end
        return {affordance="blocked"}
    end}
    local _, _, portals = Places.loadedInteriorCandidates(nearby[1].id, entryActor)
    check(portals and #portals == 1 and portals[1].outside.x == 19
        and portals[1].outside.y == 24 and portals[1].inside.x == 20,
        "entry survey skips the locked door and pairs the alternate window stand with its landing")
    SurvivorCompanion.Topology = oldTopology
end
do
    local SC = SurvivorCompanion
    local topology, square = SC.Topology, fixture.cell.getGridSquare
    local gridSquare = SC.GameplayUtil.gridSquare
    local stationId = "8040:11137:8052:11164"
    fixture.buildings[#fixture.buildings + 1] = fixture.building(8040, 11137, 8052, 11164, {"fossoil"})
    local checked, unlocked = 0, false
    fixture.cell.getGridSquare = function(self, x, y, z)
        checked = checked + 1
        local result = square(self, x, y, z)
        if x >= 8040 and x <= 8052 and y >= 11137 and y <= 11164 then
            result.getRoom = function() return "station" end
        end
        return result
    end
    SC.GameplayUtil.gridSquare = function(x, y, z) return fixture.cell:getGridSquare(x, y, z) end
    SC.Topology = {classifyEdge = function(_, from, to)
        if from:getX() == 8039 and to:getX() == 8040 and to:getY() == 11153
            and from:getY() == 11153 and unlocked then
            return {affordance = "door", traversable = true}
        end
        return {affordance = "door", reason = "door_locked"}
    end}
    local crew = {getX = function() return 8045 end, getY = function() return 11169 end}
    local function surveyFor(rejected, now)
        local survey = {budget = 48, rejected = rejected, now = now}
        local candidates, reason, portals, retryPending
        repeat
            local oldIndex = survey.index or 0
            checked = 0
            candidates, reason, portals, retryPending = Places.loadedInteriorCandidates(stationId, crew, survey)
            check(survey.index - oldIndex <= 48 and checked <= 48 * 5,
                "the wider site survey yields after its per-update square budget")
            if not candidates then check(reason == "site_entry_survey_pending", "entry survey yields while incomplete") end
        until candidates
        return candidates, portals, retryPending
    end
    local floor, initial = surveyFor(nil, 1000)
    check(#floor > 0 and #initial == 0, "loaded room tiles do not certify a locked entrance")
    unlocked = true
    local _, portals = surveyFor(nil, 4000)
    local portal = portals[1]
    check(#portals == 1 and portal.outside.x == 8039 and portal.outside.y == 11153,
        "a new unlocked entrance beyond the old radius is discovered")
    local _, delayed, retryPending = surveyFor(
        {[portal.key] = {signature = portal.signature, retryAt = 16000}}, 4000)
    check(#delayed == 0 and retryPending, "an unchanged failed threshold cools down before one bounded retry")
    local _, retried = surveyFor(
        {[portal.key] = {signature = portal.signature, retryAt = 16000}}, 16000)
    check(#retried == 1, "a formerly obstructed portal can be verified again")
    unlocked = false
    check(not Places.siteEntryPortalSquares(crew, portal), "revalidation rejects a door locked since the survey")
    table.remove(fixture.buildings)
    SC.Topology, fixture.cell.getGridSquare, SC.GameplayUtil.gridSquare = topology, square, gridSquare
end
check(not Places.actorInsideSite(nearby[1].id, entryActor),
    "the exterior arrival point does not count as entering the building")
entryActor.getCurrentSquare = function()
    return fixture.cell:getGridSquare(20, 25, 0)
end
check(Places.actorInsideSite(nearby[1].id, entryActor),
    "a room tile belonging to the selected building completes entry")
local firstPath = SurvivorCompanion.Navigation.findPath
SurvivorCompanion.Navigation.findPath = function(source, destination)
    if destination:getX() == 19 and destination:getY() == 23 then
        return { source, destination }
    end
    return nil
end
local alternateFace = Places.loadedApproach(nearby[1], actor)
check(alternateFace ~= nil and alternateFace.x == 19
        and alternateFace.y == 23,
    "a reachable fourth face square survives three blocked window approaches")
SurvivorCompanion.Navigation.findPath = firstPath
do
    local SC = SurvivorCompanion
    local nav, perf, getSquare = SC.Navigation, SC.Performance, fixture.cell.getGridSquare
    local geometryReads, edgeReads, resumes, polls = 0, 0, 0, 0
    local sharedQuota, quotaClaims = 0, 0
    SC.Performance = {
        frameId = function() return polls end,
        claimUnits = function(kind, quota)
            check(kind == "navigation" and quota <= 48,
                "site searches use the shared navigation work budget")
            quotaClaims = quotaClaims + 1
            return math.min(sharedQuota, quota)
        end,
    }
    local squares = {}
    fixture.cell.getGridSquare = function(self, x, y, z)
        geometryReads = geometryReads + 1
        local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
        if not squares[key] then squares[key] = getSquare(self, x, y, z) end
        return squares[key]
    end
    local function square(x, y)
        return fixture.cell:getGridSquare(x, y, 0)
    end
    local origin = square(7, 25)
    local walker = { getCurrentSquare = function() return origin end }
    local firstSearchAt, rejectedEdge, preferClosedCenter = nil, false, true
    local starts, completed, movedOriginResumes = {}, {}, 0
    SC.Navigation = {
        findPath = function() error("a sliced survey must not use the synchronous planner") end,
        beginPathSearch = function(from, to, _, options)
            check(from == origin and options.nodeBudget == 1800 and options.actor == walker,
                "the native path search retains its source, actor and per-candidate cap")
            firstSearchAt = firstSearchAt or polls
            local job = { from = from, to = to, slices = 0 }
            starts[#starts + 1] = job
            return job
        end,
        resumePathSearch = function(job, quota)
            resumes = resumes + 1
            if job.from ~= origin then movedOriginResumes = movedOriginResumes + 1 end
            if quota <= 0 then return "pending", nil, nil, 0, nil, 0 end
            check(quota <= 48, "a path resume has the bounded node quota")
            job.slices = job.slices + 1
            if job.slices == 1 then return "pending", nil, nil, quota, nil, quota end
            local path = { job.from }
            for x = job.from:getX() + 1, job.to:getX() - 1 do
                path[#path + 1] = square(x, job.from:getY())
            end
            path[#path + 1] = job.to
            completed[job.to] = true
            return "complete", path, nil, 1, nil, 1
        end,
        _adjacentStepForWorkRoutes = function(from, to)
            local dx, dy = math.abs(to:getX() - from:getX()), math.abs(to:getY() - from:getY())
            return dx <= 1 and dy <= 1 and dx + dy > 0
        end,
        _passableEdgeForWorkRoutes = function(from, to)
            edgeReads = edgeReads + 1
            if preferClosedCenter and completed[to] and to:getX() == 19 and to:getY() == 25 then
                rejectedEdge = true
                return false, nil, "door_locked"
            end
            return true
        end,
    }
    check(type(Places.pollLoadedSiteApproach) == "function",
        "the loaded site survey exposes a resumable poll")
    local function poll(survey)
        geometryReads, edgeReads, resumes, polls = 0, 0, 0, polls + 1
        local selected, why, status = Places.pollLoadedSiteApproach(nearby[1].id, walker, survey)
        -- The mock path builder uses the same square cache. Account for its
        -- reads on resume separately from the geometry and proof budgets.
        check((resumes > 0 or geometryReads <= 24) and edgeReads <= 8 and resumes <= 1,
            "one poll bounds footprint discovery, path resumes and live edge checks")
        return selected, why, status
    end
    local survey = {}
    local selected, why, status = poll(survey)
    local firstReads = geometryReads
    selected, why, status = Places.pollLoadedSiteApproach(nearby[1].id, walker, survey)
    check(status == "pending" and geometryReads == firstReads and resumes == 0 and edgeReads == 0,
        "a second call on the same performance frame does no survey work")
    repeat
        selected, why, status = poll(survey)
    until quotaClaims > 0 or status ~= "pending" or polls >= 16
    check(status == "pending" and quotaClaims == 1 and #starts == 0,
        "zero shared navigation quota leaves the pending candidate unstarted")

    sharedQuota = 48
    repeat
        selected, why, status = poll(survey)
    until status ~= "pending" or polls >= 64
    check(status == "complete" and why == nil and selected and selected.x == 19
            and selected.y == 24 and selected.pathNodes == 13 and selected.side == "west"
            and selected.scope == "loaded_exterior_only",
        "a changed edge on the first path selects the exact next ranked exterior")
    check(firstSearchAt >= 3 and rejectedEdge and #starts == 2
            and starts[1].slices == 2 and starts[2].slices == 2
            and starts[1].to:getX() == 19 and starts[1].to:getY() == 25,
        "footprint discovery yields and a late locked edge rejects the previously found path")

    local firstOwnerCount = #starts
    survey, polls, preferClosedCenter = {}, 0, false
    repeat
        selected, why, status = poll(survey)
    until #starts > firstOwnerCount or status ~= "pending" or polls >= 16
    check(status == "pending" and starts[firstOwnerCount + 1].from == origin,
        "the original route retains a pending frontier")
    origin = square(8, 25)
    repeat
        selected, why, status = poll(survey)
    until status ~= "pending" or polls >= 64
    check(status == "complete" and selected and selected.x == 19 and selected.y == 25
            and selected.pathNodes == 12 and movedOriginResumes == 0
            and starts[#starts].from == origin,
        "moving the scout discards the old search and proves a route from the new square")
    SC.Navigation, SC.Performance, fixture.cell.getGridSquare = nav, perf, getSquare
end
local originalPosition = SurvivorCompanion.GameplayUtil.position
local originalShelterSquare = fixture.cell.getGridSquare
local originalShelterPath = SurvivorCompanion.Navigation.findPath
SurvivorCompanion.GameplayUtil.position = function(value)
    return value:getX(), value:getY(), 0
end
fixture.cell.getGridSquare = function(self, x, y, z)
    local square = originalShelterSquare(self, x, y, z)
    if x >= 100 and x <= 110 and y >= 20 and y <= 30 then
        square.getRoom = function() return { id = "house-room" } end
    end
    return square
end
SurvivorCompanion.Navigation.findPath = function(source, destination)
    if destination:getX() >= 100 and destination:getX() <= 110 then
        return { source, destination }
    end
    return nil
end
local shelterActor = {
    getX = function() return 95 end,
    getY = function() return 25 end,
    getCurrentSquare = function()
        return originalShelterSquare(fixture.cell, 95, 25, 0)
    end,
}
local shelter, shelterReason = Places.nearestLoadedShelter(shelterActor)
check(shelter ~= nil and shelterReason == nil
        and shelter.x >= 100 and shelter.x <= 110
        and shelter.buildingId == nearby[4].id,
    "emergency refuge selects a native reachable square inside a house")
local shelterNearby=Places.nearby
local firstHouse=nearby[4]
local secondHouse={id='alternate-house',kind='residence',groundFloor=true,
    bounds={x=120,y=20,x2=130,y2=30}}
Places.nearby=function() return {firstHouse,secondHouse} end
fixture.cell.getGridSquare=function(self,x,y,z)
    local square=originalShelterSquare(self,x,y,z)
    if (x>=100 and x<=110 or x>=120 and x<=130) and y>=20 and y<=30 then
        square.getRoom=function() return {id='house-room'} end
    end
    return square
end
local firstHouseChecks,secondHouseChecks=0,0
SurvivorCompanion.Navigation.findPath=function(source,destination)
    if destination:getX()<120 then firstHouseChecks=firstHouseChecks+1
    else secondHouseChecks=secondHouseChecks+1 end
    return {source,destination}
end
local excluded={[firstHouse.id]=true}
shelter=Places.nearestLoadedShelter(shelterActor,nil,excluded)
check(shelter and shelter.buildingId==secondHouse.id and firstHouseChecks==0 and secondHouseChecks==1,
    'failed house is excluded before path admission so another indoor tile in it cannot win again')
check(excluded[firstHouse.id] and not excluded[secondHouse.id],
    'shelter selection does not mutate the caller rejection set')
excluded[secondHouse.id]=true
shelter,shelterReason=Places.nearestLoadedShelter(shelterActor,nil,excluded)
check(not shelter and shelterReason=='shelter_no_loaded_path',
    'all failed houses yield no shelter rather than cycling their interior tiles')
Places.nearby=shelterNearby
SurvivorCompanion.Navigation.findPath = function() return nil end
shelter, shelterReason = Places.nearestLoadedShelter(shelterActor)
check(shelter == nil and shelterReason == "shelter_no_loaded_path",
    "an unreachable map house cannot be reported as shelter")
SurvivorCompanion.Navigation.findPath = originalShelterPath
fixture.cell.getGridSquare = originalShelterSquare
SurvivorCompanion.GameplayUtil.position = originalPosition
check(Places.siteContainsPoint(nearby[1].id, 20, 25, 0)
        and Places.siteContainsPoint(nearby[1].id, 20, 25, 1)
        and not Places.siteContainsPoint(nearby[1].id, 19, 25, 0)
        and not Places.siteContainsPoint(nearby[1].id, 55, 25, 1)
        and not Places.siteContainsPoint(nearby[1].id, 20, 25, 2),
    "selected building includes its upper floor but excludes neighbors and absent floors")
local siteFloors = Places.siteFloors(nearby[1].id)
check(siteFloors and #siteFloors == 2 and siteFloors[1] == 0
        and siteFloors[2] == 1,
    "saved site resolves the selected building's bounded floor range")
local sightActor = {
    getX = function() return 19 end,
    getY = function() return 25 end,
    getZ = function() return 0 end,
}
SurvivorCompanion.GameplayUtil.canSee = function(_, square)
    return square:getX() == 20 and square:getY() == 25
end
check(Places.visibleSiteSquare(nearby[1].id, sightActor)
        and not Places.visibleSiteSquare(nearby[2].id, sightActor),
    "a scout can confirm only a visible square in the selected building")
SurvivorCompanion.GameplayUtil.canSee = function() return false end
check(not Places.visibleSiteSquare(nearby[1].id, sightActor),
    "map metadata alone cannot confirm a building the scout cannot see")
local originalFindPath = SurvivorCompanion.Navigation.findPath
SurvivorCompanion.Navigation.findPath = function() return nil end
planned, plannedReason = Places.plannedApproach(nearby[1], actor)
check(planned ~= nil and plannedReason == nil and planned.x == 19,
    "a distant place stays selectable when no complete loaded path exists")
approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach == nil and approachReason == "approach_no_loaded_path",
    "an inaccessible exterior square does not become a destination")
SurvivorCompanion.Navigation.findPath = originalFindPath
local originalGetCell = fixture.world.getCell
fixture.world.getCell = function() return {
    getGridSquare = function() return nil end,
} end
planned, plannedReason = Places.plannedApproach(nearby[1], actor)
check(planned ~= nil and plannedReason == nil and planned.x == 19,
    "an unstreamed target retains its map-derived exterior direction")
approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach == nil and approachReason == "approach_exterior_unavailable",
    "unloaded site edges do not count as an available approach")
fixture.world.getCell = originalGetCell
approach, approachReason = Places.loadedApproach({ bounds = nearby[1].bounds,
    id = "wrong-building" }, actor)
check(approach == nil and approachReason == "invalid_place_reference",
    "a stale or mismatched building reference is rejected")
planned, plannedReason = Places.plannedApproach({ bounds = nearby[1].bounds,
    id = "wrong-building", groundFloor = true }, actor)
check(planned == nil and plannedReason == "invalid_place_reference",
    "map planning also rejects a stale building reference")
local basement = Places.describeBuilding({
    getX = function() return 20 end,
    getY = function() return 20 end,
    getX2 = function() return 30 end,
    getY2 = function() return 30 end,
    getRooms = function() return fixture.list() end,
    getMinLevel = function() return -1 end,
    getMaxLevel = function() return -1 end,
})
approach, approachReason = Places.loadedApproach(basement, actor)
check(basement.groundFloor == false and approach == nil
        and approachReason == "place_without_ground_floor",
    "a basement-only footprint cannot be offered as a surface approach")
planned, plannedReason = Places.plannedApproach(basement, actor)
check(planned == nil and plannedReason == "place_without_ground_floor",
    "map planning excludes basement-only footprints")
local known, knownReason = Places.knownNearby(20, 20, 120, 8)
check(known ~= nil and knownReason == nil and #known == 1
        and known[1].kind == "police"
        and known[1].knowledge == "player_seen_interior",
    "only a player-seen interior exposes its building label")
check(known[1].rooms == nil and known[1].id == nearby[1].id,
    "player-facing candidate does not expose raw room metadata")
check(SurvivorCompanion.Config.get("expeditionDestinationScope") == "all_nearby",
    "all nearby buildings are the default destination scope")
local selectable, selectableReason = Places.targetableNearby(20, 20, 120, 8)
check(selectable ~= nil and selectableReason == nil and #selectable == 6,
    "default destination pool includes unvisited nearby buildings")
check(selectable[2].kind == "fire"
        and selectable[2].knowledge == "map_metadata_unconfirmed"
        and selectable[2].rooms == nil and selectable[2].distance ~= nil,
    "map-derived candidates are marked unconfirmed and omit raw rooms")
SurvivorCompanion.Config.refreshSandbox({ LivingFellows = {
    ExpeditionDestinationScope = 2,
} })
selectable, selectableReason = Places.targetableNearby(20, 20, 120, 8)
check(SurvivorCompanion.Config.get("expeditionDestinationScope") == "known_only"
        and selectableReason == nil and #selectable == 1
        and selectable[1].knowledge == "player_seen_interior",
    "known-only option limits targets to player-seen interiors")
SurvivorCompanion.Config.refreshSandbox({ LivingFellows = {
    ExpeditionDestinationScope = 1,
} })
selectable = Places.targetableNearby(20, 20, 120, 8)
check(#selectable == 6,
    "switching the sandbox option back restores all nearby targets")
SurvivorCompanion.Config.refreshSandbox()
local originalGetSquare = fixture.cell.getGridSquare
fixture.cell.getGridSquare = function(self, x, y, z)
    local square = originalGetSquare(self, x, y, z)
    if x >= 20 and x <= 30 and y >= 20 and y <= 30 then
        square.getRoomDef = function()
            return { getName = function() return "bathroom" end }
        end
    end
    return square
end
known, knownReason = Places.knownNearby(20, 20, 120, 8)
check(known ~= nil and #known == 1
        and known[1].kind == "unclassified"
        and known[1].label == "Building",
    "an unseen police room cannot classify a seen generic room")
fixture.cell.getGridSquare = originalGetSquare
known, knownReason = Places.knownNearby(20, 20, 120, 33)
check(known == nil and knownReason == "invalid_known_place_limit",
    "known-place presentation has a smaller bounded result limit")
selectable, selectableReason = Places.targetableNearby(20, 20, 120, 33)
check(selectable == nil and selectableReason == "invalid_targetable_place_limit",
    "all-nearby presentation has the same bounded result limit")
for index = 0, 39 do
    local x = 20 + index * 4
    fixture.buildings[#fixture.buildings + 1] = fixture.building(
        x, 100, x + 2, 102, { "bedroom" })
end
local firstPage, pageReason, total = Places.targetableNearby(
    20, 20, 200, 32, 0)
local secondPage, secondReason, secondTotal = Places.targetableNearby(
    20, 20, 200, 32, 32)
check(pageReason == nil and secondReason == nil
        and #firstPage == 32 and #secondPage == 14
        and total == 46 and secondTotal == 46,
    "200-tile picker pages every eligible building beyond the first 32")
local ids = {}
for _, candidate in ipairs(firstPage) do ids[candidate.id] = true end
for _, candidate in ipairs(secondPage) do
    check(not ids[candidate.id], "pages do not repeat a building")
    ids[candidate.id] = true
end
local later, laterReason = Places.targetableById(20, 20, 200,
    secondPage[#secondPage].id)
check(later ~= nil and laterReason == nil,
    "dispatch can revalidate a building on a later page")

local oversized = fixture.building(20, 130, 101, 140, { "bedroom" })
fixture.buildings[#fixture.buildings + 1] = oversized
local tooWideId = "20:130:101:140"
local originalWideSquare = fixture.cell.getGridSquare
fixture.cell.getGridSquare = function(self, x, y, z)
    local square = originalWideSquare(self, x, y, z)
    if x >= 20 and x <= 101 and y >= 130 and y <= 140 then
        square.getRoom = function() return { id = "seen-wide-interior" } end
        square.getRoomDef = function()
            return { getName = function() return "bedroom" end }
        end
        square.isSeen = function() return true end
    end
    return square
end
local afterWide, wideReason, wideTotal = Places.targetableNearby(
    20, 20, 200, 32, 0)
local wideKnown = Places.knownNearby(20, 20, 200, 8)
local wideLookup, wideLookupReason = Places.targetableById(
    20, 20, 200, tooWideId)
check(wideReason == nil and wideTotal == 46 and #afterWide == 32
        and wideKnown ~= nil and #wideKnown == 1
        and wideLookup == nil
        and wideLookupReason == "place_no_longer_selectable",
    "an 81-tile footprint is excluded from lists, counts, and dispatch")
fixture.cell.getGridSquare = originalWideSquare
fixture.buildings[#fixture.buildings] = nil

local departureBuilding = fixture.buildings[1]
local room = { getBuilding = function() return departureBuilding end }
local hall = { getBuilding = function() return departureBuilding end }
local interior = {
    getX = function() return 25 end,
    getY = function() return 25 end,
    getRoom = function() return room end,
}
local hallwaySquare = { getRoom = function() return hall end }
local insideActor = { getCurrentSquare = function() return interior end }
local originalHallPath = SurvivorCompanion.Navigation.findPath
SurvivorCompanion.Navigation.findPath = function(start, destination)
    if destination:getX() == 19 and destination:getY() == 25 then
        return { start, hallwaySquare, destination }
    end
end
local hallwayExit = Places.loadedApproach(nearby[1], insideActor)
check(hallwayExit ~= nil and hallwayExit.x == 19
        and hallwayExit.pathNodes == 3,
    "an exit through a hallway in the same building remains usable")
hall = { getBuilding = function() return fixture.buildings[2] end }
local foreignHall, foreignReason = Places.loadedApproach(nearby[1], insideActor)
check(foreignHall == nil and foreignReason == "approach_no_loaded_path",
    "a path through another building is not a valid exterior exit")
SurvivorCompanion.Navigation.findPath = originalHallPath
print("EXPEDITION_PLACES_PASS checks=" .. tostring(checks))
