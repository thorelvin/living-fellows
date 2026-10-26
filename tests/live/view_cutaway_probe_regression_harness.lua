-- SPDX-License-Identifier: MIT
-- Test probe evidence rules, never substitute these fixtures for the GL gate.
local T = SCRealSandboxHarnessProbes.SCViewCutawayProbe._tests
local checks = 0
local function check(value, why)
    checks = checks + 1
    if not value then error("view cutaway probe: " .. why) end
end
for _, row in ipairs({ { 0, false, false }, { 1, true, false },
        { 2, false, true }, { 3, true, true } }) do
    check(T.hasBit(row[1], 1) == row[2], "north edge orientation")
    check(T.hasBit(row[1], 2) == row[3], "west edge orientation")
end
check(not T.hasBit(nil, 1), "missing native flags cannot count as hidden")
local actor = { count = 16, failure = "", dead = false }
function actor:getCompanionPostUpdateDiagnostic() return "ok,count=" .. self.count end
function actor:getBridgeFailure() return self.failure end
function actor:isDead() return self.dead end
check(T.healthy(actor, 15), "a living actor must complete another native postupdate")
check(not T.healthy(actor, 16), "stationary counter cannot establish post-demotion updates")
actor.failure = "native update disabled"
check(not T.healthy(actor, 15), "bridge-disabled actor cannot pass through dirty flags")
actor.failure, actor.dead = "", true
check(not T.healthy(actor, 15), "removed/dead former leader cannot establish retention")
actor.dead = false
check(not T.healthy(actor, nil), "missing pre-close counter invalidates fixture")
IsoFlagType = { cutN = "north", cutW = "west" }
local room = { getName = function() return "kitchen" end }
local function square(x, y, inside, wall)
    local value = {}
    function value:getProperties() return { has = function(_, flag) return wall == flag end } end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:HasTree() return false end
    function value:TreatAsSolidFloor() return true end
    function value:hasFloor() return true end
    function value:getVehicleContainer() return nil end
    function value:getRoom() return inside and room or nil end
    function value:getDoorTo() return nil end
    function value:getWindowTo() return nil end
    return value
end
local squares = { ["5:5"] = square(5, 5, false, "north"),
    ["5:4"] = square(5, 4, true), ["5:6"] = square(5, 6, false) }
local U = { gridSquare = function(x, y) return squares[x .. ":" .. y] end }
local south = T.wallAt(U, 5, 5, 1)
check(south and south.bit == 1 and south.inside.y == 4.5
    and south.outside.y == 6.5, "south face uses the north-owned edge of southern square")
squares["5:4"].isSolid = function() return true end
squares["5:3"] = square(5, 3, true)
local counterWall = T.wallAt(U, 5, 5, 1)
check(counterWall and counterWall.roomName == "kitchen" and counterWall.inside.y == 3.5,
    "counter against wall does not erase kitchen ownership; choose free pose farther inside same room")
squares["5:4"].isSolid = function() return false end
squares["5:5"] = square(5, 5, false, "west")
squares["4:5"], squares["6:5"] = square(4, 5, true), square(6, 5, false)
local east = T.wallAt(U, 5, 5, 2)
check(east and east.bit == 2 and east.inside.x == 4.5
    and east.outside.x == 6.5, "east face uses the west-owned edge of eastern square")
squares["5:5"].getWindowTo = nil
check(T.wallAt(U, 5, 5, 2) ~= nil, "missing optional native method is not invoked under debug mode")
squares["5:5"].getDoorTo = function() return {} end
check(T.wallAt(U, 5, 5, 2) == nil, "door alone is not a fixed solid-wall fixture")
local kitchenWindow = { bit = 1, roomName = "kitchen", windowSection = true }
local kitchenOpaque = { bit = 1, roomName = "kitchen", windowSection = false }
local garageOpaque = { bit = 1, roomName = "garage", windowSection = false }
check(T.chooseWall({ kitchenWindow, kitchenOpaque, garageOpaque }, 1, true) == kitchenOpaque,
    "prefer an opaque kitchen wall over a nearer window section")
check(T.chooseWall({ kitchenWindow, garageOpaque }, 1, true) == kitchenWindow,
    "window-wall fallback retains actual kitchen ownership")
check(T.chooseWall({ garageOpaque }, 1, true) == nil,
    "garage cannot silently replace the required kitchen south wall")
local player, resident = { sql = 1 }, { sql = 2 }
local slot = 2
SurvivorCompanion = { ViewSession = { slotSqlId = function() return slot end } }
SCSplitScreenProbe = { debugPlayerSqlId = function(value) return value.sql end }
local H = { player = player }
local fixture = { records = { { id = "retained", actor = resident } } }
fixture.stockSql = T.snapshotSql(H, fixture)
check(T.sameSql(H, fixture), "stock comparison preserves exact primary and companion identities")
resident.sql = 3
check(not T.sameSql(H, fixture), "unrelated companion row mutation fails comparison")
resident.sql, player.sql = 2, 4
check(not T.sameSql(H, fixture), "primary row mutation fails comparison")
player.sql, slot = 1, 5
check(not T.sameSql(H, fixture), "reusable ViewSession identity cannot change during stock control")
local mutableRegistry = { id = "retained", actor = resident }
SurvivorCompanion.Registry = { byId = function() return mutableRegistry end }
check(T.retainedIdentity(SurvivorCompanion, fixture), "exact original actor is registered")
mutableRegistry.actor = nil
check(not T.retainedIdentity(SurvivorCompanion, fixture), "mutable Registry retirement is an explicit fixture failure")
check(fixture.records[1].actor == resident, "retired Registry entry cannot erase the retained fixture reference")
mutableRegistry.actor = { sql = resident.sql }
check(not T.retainedIdentity(SurvivorCompanion, fixture), "replacement actor with same SQL is not original identity")
local requestedScreenshot
getCore = function() return { TakeFullScreenshot = function(_, name) requestedScreenshot = name end } end
T.capture({ config = { run_id = "probe-contract" } }, { walls = {}, frames = 2 }, "frame2", true)
check(requestedScreenshot == "probe-contract-view-cutaway-frame2.png",
    "native screenshot API receives .png explicitly; it does not append extensions")
local fallback, upperNear, upperFar = { z = 0, gap = 400 }, { z = 1, gap = 100 }, { z = 1, gap = 900 }
check(T.preferRemote(nil, fallback) == fallback, "same-floor fallback remains available without upper room")
check(T.preferRemote(fallback, upperNear) == upperNear, "loaded upper room takes priority over distant same-floor room")
check(T.preferRemote(upperNear, upperFar) == upperFar, "prefer the farther loaded upper-floor fixture")
check(T.preferRemote(upperFar, upperNear) == upperFar, "near upper room cannot erase the larger separation")
check(T.preferRemote(upperFar, fallback) == upperFar, "same-floor fallback cannot downgrade upper-floor coverage")
local leader, otherLeader = {}, {}
local lifecycle = { mode = "expedition", openGeneration = 3, leader = { actor = leader } }
lifecycle.releaseObserved = T.releaseReceipt(lifecycle, "expedition", "expedition", leader, true, true, true, true)
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "solo",
    "automatic normal return proceeds to solo without a second finish")
check(T.releaseTransition(lifecycle, "view_cutaway_remote", nil, true, false) == "solo",
    "normal release during remote settling is observed immediately")
lifecycle.releaseObserved = nil
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "missing_release",
    "vanished slot without captured release cannot count as success")
check(T.releaseTransition(lifecycle, "view_cutaway_join", nil, false, true) == nil,
    "real pending native join remains allowed")
check(T.releaseTransition(lifecycle, "view_cutaway_join", nil, false, false) == "missing_release",
    "missing native join ownership cannot hide as a pending join")
lifecycle.releaseObserved = T.releaseReceipt(lifecycle, "expedition", "base_watch", leader, true, true, true, true)
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "invalid_release",
    "wrong ViewSession owner invalidates receipt")
lifecycle.releaseObserved = T.releaseReceipt(lifecycle, "expedition", "expedition", otherLeader, true, true, true, true)
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "invalid_release",
    "another leader's release cannot finish this fixture")
lifecycle.releaseObserved = T.releaseReceipt(lifecycle, "expedition", "expedition", leader, true, true, true, true)
lifecycle.openGeneration = 4
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "invalid_release",
    "old cycle receipt is invalid for the next opening")
lifecycle.releaseObserved = T.releaseReceipt(lifecycle, "expedition", "expedition", leader, true, true, true, false)
check(T.releaseTransition(lifecycle, "view_cutaway_return", nil, true, false) == "invalid_release",
    "leader death release cannot count as ordinary automatic completion")
local floorSquare = square(10, 10, true)
check(T.safeFloor(floorSquare), "a real solid floor is usable")
floorSquare.hasFloor = function() return false end
check(not T.safeFloor(floorSquare), "virtual room with no actual floor cannot be selected upstairs")
floorSquare.hasFloor = function() return true end
floorSquare.TreatAsSolidFloor = function() return false end
check(not T.safeFloor(floorSquare), "non-solid floor cannot be selected merely from room metadata")
local before = { alive = true, z = 0, health = 100, bleeding = 0, deep = 0 }
local after = { alive = true, z = 1, health = 100, bleeding = 0, deep = 0 }
check(T.excursionSafe(before, after, { z = 1 }), "healthy actor actually remains on selected upper floor")
after.z = 0
check(not T.excursionSafe(before, after, { z = 1 }), "fall to lower floor invalidates fixture")
after.z, after.bleeding, after.deep = 1, 2, 2
check(not T.excursionSafe(before, after, { z = 1 }), "new bleeding/deep wounds invalidate excursion")
local viewProbe = SCRealSandboxHarnessProbes.SCViewCutawayProbe
local main, leader, members, active = {}, {}, nil, true
members = { main, leader }
SurvivorCompanion.BanditsAdapter = { status = function() return { active = active } end }
BanditPlayer = { GetPlayers = function() return { size = function() return #members end,
    get = function(_, index) return members[index + 1] end } end,
    GetPlayerById = function(id) if id == 1 then return main elseif id == "lf:sc-view" then return leader end end }
BanditUtils = { GetCharacterID = function(actor) return actor == main and 1 or "lf:sc-view" end }
local viewH = { player = main, config = { bandits_enabled = "true" } }
local viewF = { leader = { actor = leader, id = "sc-view" }, closedAt = 1, visibility = { done = true } }
check(viewProbe.banditsViewState(viewH, viewF, "unit"), "settled main and living leader aliases stay unique")
members = { main, leader, leader }
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "owned secondary slot must not duplicate its registry actor")
members = { main }
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "solo return must retain the living former leader")
members = { main, leader }
local lookup = BanditPlayer.GetPlayerById
BanditPlayer.GetPlayerById = function() return leader end
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "player ID 1 must never resolve to the companion")
BanditPlayer.GetPlayerById = function() return main end
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "LF alias must never fall through to the real player")
BanditPlayer.GetPlayerById = lookup
local identity = BanditUtils.GetCharacterID
BanditUtils.GetCharacterID = function() return 1 end
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "view leader must retain its LF identity")
BanditUtils.GetCharacterID = identity
active = false
check(not viewProbe.banditsViewState(viewH, viewF, "unit"), "enabled but inactive adapter cannot pass the scenario")
viewH.config.bandits_enabled = "false"
check(viewProbe.banditsViewState(viewH, viewF, "unit"), "ordinary view controls do not require an absent dependency")
print("View cutaway probe evidence PASS: " .. checks .. " checks; GL output still requires live run")
