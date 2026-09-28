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
SC.Call = { static = function(_, method, _, sx, sy, tx, ty, out)
    check(method == "planRoadRoute" and sx == actor.x and sy == 10
            and tx == 100 and ty == 10, "native request has actor and goal")
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
actor.x = 60
check(Route.target(route, actor).x == 90, "junction advances to next road")
actor.x = 90
check(Route.target(route, actor).x == 100, "exit advances to final approach")
check(Route.validDescriptor(Route.descriptor(route, "outbound")),
    "restart descriptor keeps only bounded stable data")
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
