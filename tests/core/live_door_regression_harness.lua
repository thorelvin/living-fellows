-- SPDX-License-Identifier: MIT
-- Load after SCRealSandboxHarness.lua in an isolated Kahlua process.
local SC, H, checks = SurvivorCompanion, SCRealSandboxHarness, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "live door regression " .. checks .. ": " .. message)
end
local cells = {}
local function square(x, y, z)
    local key = x .. ":" .. y .. ":" .. (z or 0)
    if cells[key] then return cells[key] end
    local value = { x = x, y = y, z = z or 0, moving = {}, objects = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getMovingObjects() return self.moving end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:TreatAsSolidFloor() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:isFree() return true end
    function value:isBlockedTo(other) return other.blocked == true end
    cells[key] = value
    return value
end
local oldCell, oldBarrier = getCell, SC.Topology.barrierBetween
function getCell() return { getGridSquare = function(self, x, y, z) return square(x, y, z) end } end
local companion = { __class = "IsoPlayer", isCollidable = function() return true end }
local player = { __class = "IsoPlayer", isCollidable = function() return true end }
H.actor = companion
square(0, 0).moving = { companion }
square(-1, 0).moving = { player }
check(not H.doorLandingFree(square(-1, 0)), "local player makes direct rear landing unavailable")
check(H.doorLandingFree(square(0, 0)), "probe actor does not obstruct its own starting square")
local alternate = H.doorLanding(square(0, 0), -1, 0)
check(alternate and alternate.x == -1 and math.abs(alternate.y) == 1,
    "occupied direct landing selects a free side landing on the same side of door")
square(-1, -1).moving, square(-1, 1).moving = { player }, { player }
check(H.doorLanding(square(0, 0), -1, 0) == nil, "no landing selected through occupied bodies")
square(-1, -1).moving, square(-1, 1).moving = {}, {}
square(0, -1).blocked, square(0, 1).blocked = true, true
check(H.doorLanding(square(0, 0), -1, 0) == nil, "blocked side bends cannot be used as setup shortcuts")
square(0, -1).blocked, square(0, 1).blocked = nil, nil
SC.Topology.barrierBetween = function() return { IsOpen = function() return true end }, "door" end
local candidate = H.doorCrossingCandidate(square(0, 0), square(1, 0))
check(candidate and candidate.nearGoal.x == -1 and candidate.farGoal.x == 2
    and candidate.mx == 1 and candidate.dx == 1, "alternate setup preserves exact crossing plane and far-side goals")
H.config.pathing_only = "true"
check(H.afterDoorCrossingPhase() == "finish", "focused pathing mode ends after physical door probe")
H.config.pathing_only = nil
check(H.afterDoorCrossingPhase() == "awareness", "normal full suite retains combat and faction phases")
companion.x, companion.y, companion.z = 0.5, 0.5, 0
function companion:getX() return self.x end
function companion:getY() return self.y end
function companion:getZ() return self.z end
function companion:getSquare() return square(0, 0) end
function companion:getCompanionCollisionDiagnostic()
    return self.collisionDiagnostic or "move{intended=0.55/0.5};invalid=4:rejected_nonfinite_request"
end
local metrics = {}
check(H.checkDoorState(metrics, 1000), "finite coordinates and real square membership pass")
companion.x = 0.55
check(H.checkDoorState(metrics, 1016) and metrics.checkedFrames == 2,
    "normal movement passes even when native safely rejected an invalid request")
companion.collisionDiagnostic = "move{intended=NaN/NaN}"
check(not H.checkDoorState({}, 1032), "invalid coordinates that reached actual physics fail")
companion.collisionDiagnostic = nil
square(0, 0).moving = {}
check(not H.checkDoorState({}, 1032), "missing native square membership fails")
square(0, 0).moving = { companion }
companion.x = 0.95
check(not H.checkDoorState(metrics, 1032), "same-tile snap exceeds normal movement envelope")
companion.x = 0 / 0
check(not H.checkDoorState({}, 1048), "nonfinite world position fails before movement arithmetic")
getCell, SC.Topology.barrierBetween = oldCell, oldBarrier
SC_TEST_REPORT = "LIVE_DOOR_REGRESSION_PASS checks=" .. checks
