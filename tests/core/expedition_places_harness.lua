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
local invalid, invalidReason = Places.nearby(20, 20, 151, 2)
check(invalid == nil and invalidReason == "invalid_place_query",
    "unbounded radius is rejected")
invalid, invalidReason = Places.nearby(20, 20, 120, 129)
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
local approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach ~= nil and approachReason == nil
        and approach.x == 19 and approach.y == 25
        and approach.side == "west" and approach.pathNodes == 2
        and approach.scope == "loaded_exterior_only",
    "approach uses a native path to a loaded square beside the building")
local originalFindPath = SurvivorCompanion.Navigation.findPath
SurvivorCompanion.Navigation.findPath = function() return nil end
approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach == nil and approachReason == "approach_no_loaded_path",
    "an inaccessible exterior square does not become a destination")
SurvivorCompanion.Navigation.findPath = originalFindPath
local originalGetCell = fixture.world.getCell
fixture.world.getCell = function() return {
    getGridSquare = function() return nil end,
} end
approach, approachReason = Places.loadedApproach(nearby[1], actor)
check(approach == nil and approachReason == "approach_exterior_unavailable",
    "unloaded site edges do not count as an available approach")
fixture.world.getCell = originalGetCell
approach, approachReason = Places.loadedApproach({ bounds = nearby[1].bounds,
    id = "wrong-building" }, actor)
check(approach == nil and approachReason == "invalid_place_reference",
    "a stale or mismatched building reference is rejected")
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
print("EXPEDITION_PLACES_PASS checks=" .. tostring(checks))
