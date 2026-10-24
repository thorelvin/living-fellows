-- SPDX-License-Identifier: MIT
-- Probe orchestration contract only. Real navigation/loot/return needs GL game.
local Probe = SCRealSandboxHarnessProbes.SCNormalExpeditionKitchenProbe
local checks, dispatched, mission, screenshots = 0, nil, nil, {}
local function assertThat(value, why)
    checks = checks + 1
    if not value then error("normal kitchen probe: " .. why) end
end
local function actor(x, y)
    local value = {}
    function value:getX() return x end
    function value:getY() return y end
    function value:getZ() return 0 end
    function value:isDead() return false end
    function value:isBridgeHealthy() return true end
    function value:getBodyDamage() return { getOverallBodyHealth = function() return 100 end,
        getNumPartsBleeding = function() return 0 end } end
    -- Any accidental crew staging would error: no coordinate setters exist.
    return value
end
local primary, crew1, crew2 = actor(12035.5, 6746.5), actor(12040.5, 6746.5), actor(12041.5, 6746.5)
local movementBlocked = true
function primary:isBlockMovement() return movementBlocked end
function primary:setBlockMovement(value) movementBlocked = value end
function primary:getCurrentSquare() return { getRoom = function() return { getName = function() return "kitchen" end } end } end
local vehicle = actor(12039, 6749)
function vehicle:isEngineRunning() return false end
local crew = { { id = "first", actor = crew1 }, { id = "second", actor = crew2 } }
local car = { sqlId = 46, zone = { id = "parking" }, vehicle = vehicle }
local place = { id = "real-store", distance = 112, kind = "store" }
local H = { config = { run_id = "normal-contract" }, player = primary, phase = "normal_kitchen_plan" }
H.normalKitchen = { primary = primary, crew = crew, cars = { car }, places = { place },
    planIndex = 1, carIndex = 1, frames = 100, startedAt = 0, nextTraceAt = 0,
    holdActive = true, previousBlockMovement = false }
getFileWriter = function() return nil end
getPlayerInventory = function() return { setVisible = function() end } end
getPlayerLoot = getPlayerInventory
getCore = function() return { TakeFullScreenshot = function(_, name) screenshots[#screenshots + 1] = name end,
    getScreenWidth = function() return 2560 end } end
getSpecificPlayer = function(index) if index == 0 then return primary end end
getPlayerData = function() return nil end
getPlayerScreenWidth = function() return 2560 end
SCSplitScreenProbe = { isReleased = function() return true end, releaseDiagnostics = function() return "solo" end }
Events = { OnPostRender = { Remove = function() end } }
SurvivorCompanion = {
    ExpeditionPlaces = { plannedApproach = function() return { x = 12020, y = 6850, z = 0 } end },
    ExpeditionCar = { preflight = function(records, zone, id)
        assertThat(records == crew and zone == "parking" and id == 46, "read-only preflight receives actual crew/car")
        return {}
    end },
    ExpeditionPrototype = {
        current = function() return mission end,
        startAtPlace = function(records, id, kind, options)
            dispatched = { records = records, id = id, kind = kind, options = options }
            mission = {}
            return true
        end,
        finishAtPlayer = function() error("probe must never force completion") end,
        requestReturn = function() error("probe must never force a return") end,
        lastDebrief = function() return { endReason = "quantity_met", acquisitions = { a = {}, b = {} },
            returnedIds = { "a", "b" }, integration = { items = { { stored = true }, { stored = true } } } } end,
    },
    ViewSession = { owner = function() return nil end },
    Registry = { byId = function(id) return id == "first" and crew[1] or crew[2] end },
}
local rows = {}
local function result(status, name, detail) rows[name] = { status, detail } end
local function check(name, condition, detail) result(condition and "PASS" or "FAIL", name, detail); return condition end
local function phase(name) H.phase = name end
Probe.step(H, 1, check, result, phase)
assertThat(H.phase == "normal_kitchen_mission" and dispatched ~= nil, "normal UI dispatch starts mission")
assertThat(dispatched.records == crew and dispatched.kind == "search" and dispatched.id == "real-store", "dispatch uses real selected records/site")
assertThat(dispatched.options.turnHomeAfterHours == 1 and dispatched.options.request.quantity == 2
    and dispatched.options.travelMode == "drive", "timer and quantity are actual UI choices")
assertThat(#screenshots == 1 and screenshots[1]:match("before%.png$"), "before screenshot has explicit PNG extension")
mission, H.normalKitchen.sawJoined = nil, true
H.normalKitchen.sawDeparture, H.normalKitchen.sawStoreEntry = true, true
Probe.step(H, 2, check, result, phase)
assertThat(H.phase == "normal_kitchen_return_capture", "only production natural mission end begins capture wait")
assertThat(#screenshots == 2 and screenshots[2]:match("natural%-return%.png$"), "capture the actual natural return immediately")
H.normalKitchen.frames = 399
Probe.step(H, 3, check, result, phase)
assertThat(#screenshots == 2, "no frame300 screenshot before300 completed frames")
H.normalKitchen.firstSoloCaptured = true -- Separate render callback owns the exact two-frame GL capture.
H.normalKitchen.frames = 400
Probe.step(H, 4, check, result, phase)
assertThat(H.phase == "normal_kitchen_complete" and #screenshots == 3,
    "natural return screenshot is queued after300 frames with input still held")
assertThat(movementBlocked, "input stays blocked until the queued final screenshot has rendered")
H.normalKitchen.frames = 403
Probe.step(H, 5, check, result, phase)
assertThat(H.phase == "finish" and not movementBlocked, "original input block is restored only after screenshot frames")
assertThat(rows.normal_kitchen_crew_return_first[1] == "PASS"
    and rows.normal_kitchen_car_engine_stopped[1] == "PASS", "return includes real actor identity/engine checks")
assertThat(Probe._tests.count({ a = {}, b = {} }) == 2, "acquisition dictionaries count correctly")
assertThat(not Probe._tests.tripEvidence({ sawJoined = true }), "boarding rollback is not a completed trip")
assertThat(not Probe._tests.tripEvidence({ sawDeparture = true }), "outbound movement without store entry cannot pass")
assertThat(Probe._tests.tripEvidence({ sawDeparture = true, sawStoreEntry = true }), "completed trip needs both real travel and store entry")
assertThat(Probe._tests.poseStable(actor(12035.54, 6746.48)), "small native placement rounding remains in fixed kitchen pose")
assertThat(not Probe._tests.poseStable(actor(12028.04, 6742.04)), "observed post-return drift invalidates kitchen scene")
assertThat(not Probe._tests.poseStable(actor(12035.76, 6746.5)), "drift beyond0.25tiles is rejected immediately")
local stateMachineIndexed = false
local nativeLikeActor = setmetatable({}, { __index = function(_, method)
    if method == "getStateMachine" then
        stateMachineIndexed = true
        error("unexposed StateMachine must not be queried")
    end
    if method == "getCurrentStateName" then return function() return "IdleState" end end
    error("unexposed optional field: " .. method)
end })
local state = Probe._tests.primaryState(nativeLikeActor)
assertThat(state:find("fsm=IdleState", 1, true) and not stateMachineIndexed,
    "trace reads actor's verified string state name, never nested unexposed StateMachine")
print("Normal expedition kitchen probe PASS: " .. checks .. " checks; actual mission requires live GL run")
