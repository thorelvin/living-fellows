-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Route = SC.ExpeditionRoute
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "route check " .. tostring(checks) .. ": " .. message)
end
local enabled = true
SC.Config = { get = function(key)
    if key == "expeditionRoadRoutingEnabled" then return enabled end
end }
local source = { x = 10, y = 10 }
local entry = { x = 20, y = 10 }
SC.GameplayUtil = {
    position = function(object) return object.x, object.y, 0 end,
    isSquareFree = function() return true end,
}
SC.Navigation = { findPath = function(first, last)
    if first == source and last == entry then return { source, entry } end
end }
SC.Factions = { streetDataApi = function() return {} end }
SCBridge = {}
local nativeStatus = "READY"
local actor
SC.Call = { static = function(_, method, _, sx, sy, tx, ty, ...)
    local args = { ... }
    local out = args[#args]
    check((method == "planRoadRoute"
            or method == "planRoadRouteAvoiding")
            and sx == actor.x and sy == 10
            and tx == 100 and ty == 10, "native request has actor and goal")
    if method == "planRoadRouteAvoiding" then
        check(args[1] == 35 and args[2] == 10 and args[3] == 9,
            "horde area is passed to the native road planner")
    end
    out.status = nativeStatus
    out.reason = "missing"
    out.geometry = "20.0,10.0,Oak St;60.0,10.0,Oak St;90.0,10.0,Pine Rd"
    out.roadLength = 70
    out.fingerprint = "abc123"
    out.inferredJunctions = 1
    return true, true
end }
function getWorld() return { getCell = function() return {
    getGridSquare = function(_, x, y)
        if x == 20 and y == 10 then return entry end
    end,
} end } end
actor = { x = 10, y = 10,
    getCurrentSquare = function() return source end }
local route, reason = Route.plan(actor, { x = 100, y = 10, z = 0 })
check(route ~= nil and reason == nil and #route.points == 3
        and route.roadLength == 70, "bounded native geometry becomes a route")
check(Route.verifyEntry(route, actor) == true,
    "entry connector needs a loaded local path")
check(Route.target(route, actor).x == 20, "first leg reaches road entry")
actor.x = 20
check(Route.target(route, actor).x == 60, "reaching entry advances to road")
check(Route.withinCorridor(route, { { x = 30, y = 10 } }),
    "on-road path remains inside corridor")
check(not Route.withinCorridor(route, { { x = 30, y = 30 } }),
    "a long detour outside the road corridor is rejected")
check(Route.allowInteriorAccess(route, "search", "outbound", false) == false,
    "a Search team may not cut through an unrelated house between roads")
route.index = 1
check(Route.allowInteriorAccess(route, "search", "outbound", true),
    "the road-entry leg may leave an indoor departure point")
check(not Route.allowInteriorAccess(route, "search", "outbound", false),
    "an outdoor road-entry leg does not cross an unrelated house")
route.index = #route.points + 1
check(Route.allowInteriorAccess(route, "search", "outbound", false),
    "final site access may use the building's door")
route.index = 2
check(Route.allowInteriorAccess(route, "search", "inbound", true),
    "return can leave the searched building")
check(not Route.allowInteriorAccess(route, "search", "inbound", false),
    "road return does not enter an unrelated building")
check(Route.allowInteriorAccess(nil, "search", "outbound", false),
    "legacy straight Search retains its site-approach permission")
check(not Route.allowInteriorAccess(nil, "scout", "outbound", false),
    "ordinary straight Scout keeps exterior travel")
check(Route.allowInteriorAccess(nil, "scout", "inbound", false),
    "the final local return leg can approach a player indoors")
actor.x = 60
check(Route.target(route, actor).x == 90, "junction advances to next road")
actor.x = 90
check(Route.target(route, actor).x == 100, "exit advances to final approach")
check(Route.validDescriptor(Route.descriptor(route, "outbound")),
    "restart descriptor keeps only bounded stable data")
route.index = 2
actor.x = 20
local threats = {}
for index = 1, 12 do
    threats[index] = { x = 35, y = 10,
        visible = true, obstructed = false }
end
local snapshot = { valid = true, reflexTime = 1000, threats = threats }
check(Route.visibleHorde(route, actor, snapshot, 4, 1100) == nil,
    "three zombies per living member does not trigger a detour")
threats[13] = { x = 35, y = 10,
    visible = true, obstructed = false }
local avoid = Route.visibleHorde(route, actor, snapshot, 4, 1100)
check(avoid ~= nil and avoid.x == 35 and avoid.y == 10
        and avoid.radius == 8 and avoid.seen == 13,
    "more than three visible zombies per member identifies a road hazard")
check(Route.visibleHorde(route, actor, snapshot, 4, 4000) == nil,
    "old sight data cannot change the expedition route")
local detour = Route.plan(actor, { x = 100, y = 10, z = 0 }, true,
    { x = 35, y = 10, radius = 9 })
check(detour ~= nil and Route.validDescriptor(
        Route.descriptor(detour, "outbound")),
    "detour geometry and bounded avoidance survive route description")
check(not Route.withinCorridor(detour, { { x = 35, y = 10 } }),
    "a local shortcut through the visible horde is rejected")
nativeStatus = "INCOMPLETE_MAP_DATA"
local unavailable, failure = Route.plan(actor, { x = 100, y = 10, z = 0 })
check(unavailable == nil and failure == "INCOMPLETE_MAP_DATA",
    "missing connector cannot become a direct path")
enabled = false
unavailable, failure = Route.plan(actor, { x = 100, y = 10, z = 0 })
check(unavailable == nil and failure == "road_routing_unavailable",
    "public gate keeps unaccepted routing disabled")
nativeStatus = "READY"
local resumed = Route.plan(actor, { x = 100, y = 10, z = 0 }, true)
check(resumed ~= nil,
    "an already saved road mission may safely replan after restart")
print("EXPEDITION_ROUTE_PASS checks=" .. tostring(checks))
