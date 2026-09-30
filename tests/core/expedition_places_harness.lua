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
