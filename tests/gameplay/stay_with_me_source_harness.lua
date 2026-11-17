-- SPDX-License-Identifier: MIT
-- Contract checks run the dependency's real client/server identity functions.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local A, checks = SC.StayWithMeAdapter, 0
local function check(value, why)
    checks = checks + 1
    assert(value, "SWM source " .. checks .. ": " .. why)
end
local clientIdentity, serverIdentity = Bridge.isCompanion, BridgeServer.isCompanionBody
local body = f.zombie(2, 2, {})
local other = f.zombie(3, 2, {})
local pid = BridgeServer.markId(23)
function body:getPersistentOutfitID() return pid end
function other:getPersistentOutfitID() return 24 end
function body:isFemale() return true end
function other:isFemale() return true end
A.reset();check(A.initialize(), "downloaded mod id enables the adapter")
body.animVariables.NotAloneBody = true
check(Bridge.isCompanion(body) and BridgeServer.isCompanionBody(body)
    and BridgeCompanion.isBody(body) and A.owns(body), "published animation marker agrees with all original ownership readers")
body.animVariables.NotAloneBody = nil
body.modData.notAloneBody = true
check(BridgeServer.isCompanionBody(body) and A.owns(body), "original server and LF read the saved marker")
body.modData.notAloneBody = nil
Bridge.body = body
check(BridgeCompanion.isBody(body) and A.owns(body), "original current-body contract is honoured")
Bridge.body = nil
Bridge.mp = true
Bridge.bodyIndex = { [pid] = { owner = "someone-else" } }
check(Bridge.isCompanion(body) and A.owns(body), "original multiplayer index protects an unmarked mirror owned by someone else")
Bridge.bodyIndex = {}
Bridge.store = { bodyId = pid }
check(Bridge.isCompanion(body) and A.owns(body), "original saved current-body id protects a mirror before marking")
Bridge.store = nil;Bridge.mp = false
local world = BridgeData.world(nil)
world.players["someone-else"] = { bodyId = pid }
check(BridgeServer.isCompanionBody(body) and A.owns(body), "original marked server roster protects another owner's body")
world.players["someone-else"] = nil
check(not BridgeServer.isCompanionBody(body) and not A.owns(body),
    "a marked outfit id without an original owner cannot grant permanent immunity")
BridgeSeatPuppet.p = body
check(BridgeSeatPuppet.is(body) and A.owns(body), "original seated visual identity is protected")
BridgeSeatPuppet.p = nil
body.animVariables.SWMSeatPuppet = true
check(A.owns(body), "published seated visual marker protects before the owner's cache")
body.animVariables.SWMSeatPuppet = nil
check(not A.owns(body) and not A.owns(other), "release and ordinary zombie controls remain enemies")
check(Bridge.isCompanion == clientIdentity and BridgeServer.isCompanionBody == serverIdentity,
    "adapter leaves original identity functions and their foreign AI untouched")
SC_TEST_REPORT = "STAY_WITH_ME_ORIGINAL_SOURCE_PASS checks=" .. checks
