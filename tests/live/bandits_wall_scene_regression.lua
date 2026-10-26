-- SPDX-License-Identifier: MIT
local Probe = SCRealSandboxHarnessProbes.SCBanditsWallAcceptance
local checks, room, grid = 0, {}, {}
local kind, object, edgeOpen, blocked = "blocked", nil, true, true
local function expect(value, why)
    checks = checks + 1
    assert(value, "wall scene " .. checks .. ": " .. why)
end
local function square(x, indoor)
    local value = { room = indoor and room or nil, clear = true }
    value.getX = function() return x end
    value.getY = function() return 0 end
    value.getZ = function() return 0 end
    value.getRoom = function() return value.room end
    grid[x .. ":0"] = value
    return value
end
local inside, observer = square(0, true), square(-2, true)
for x = 1, 7 do square(x, false) end
getCell = function() return { getGridSquare = function(_, x, y) return grid[x .. ":" .. y] end } end
LosUtil = { lineClear = function(_, _, _, _, x) return x == 7.5 and blocked and "Blocked" or "Clear" end }
local SC = { GameplayUtil = { isClearActorSpawnSquare = function(value) return value ~= nil and value.clear end,
    isSquareFree = function(value) return value ~= nil and value.clear end },
    Topology = { barrierBetween = function() return object, kind end,
        classifyEdge = function() return { traversable = edgeOpen, affordance = edgeOpen and "open" or "door" } end } }
local site = Probe.candidate(SC, {}, inside)
expect(site and site.inside == inside and site.observer == observer and site.enemy == grid["7:0"]
    and site.exposed == grid["3:0"], "a real blocked wall with open outdoor staging and an indoor observer supplies the intended scene")
for _, other in ipairs({ "door", "window", "window_frame", "fence", "open" }) do
    kind = other
    expect(Probe.candidate(SC, {}, inside) == nil, other .. " cannot substitute for solid-wall acceptance")
end
kind, object = "blocked", {}
expect(Probe.candidate(SC, {}, inside) == nil, "an unresolved concrete traversal object is not relabeled a solid wall")
object, edgeOpen = nil, false
expect(Probe.candidate(SC, {}, inside) == nil, "blocked exterior staging routes cannot supply a clear attack position")
edgeOpen, blocked = true, false
expect(Probe.candidate(SC, {}, inside) == nil, "a geometry label without actual native blocked LOS is insufficient")
blocked, observer.room = true, {}
expect(Probe.candidate(SC, {}, inside) == nil, "an observer in another room cannot supply the sheltered setup")
observer.room, inside.clear = room, false
expect(Probe.candidate(SC, {}, inside) == nil, "an occupied indoor spawn is refused")
inside.clear, grid["5:0"].clear = true, false
expect(Probe.candidate(SC, {}, inside) == nil, "intervening outdoor bodies or furniture keep the staging lane unavailable")
SC_TEST_REPORT = "BANDITS_WALL_SCENE_PASS checks=" .. checks
