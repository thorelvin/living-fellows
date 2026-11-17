-- SPDX-License-Identifier: MIT
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local A, U, F = SC.StayWithMeAdapter, SC.GameplayUtil, SC.ZombieFacts
local checks = 0
local function check(value, why)
    checks = checks + 1
    assert(value, "SWM identity " .. checks .. ": " .. why)
end
local mods, queries = {}, 0
function getActivatedMods()
    queries = queries + 1
    return { contains = function(_, key) return mods[key] == true end }
end
local body, normal = f.zombie(2, 2, {}), f.zombie(3, 2, {})
A.reset()
body.animVariables.NotAloneBody = true
check(A.owns(body), "live animation marker protects during partial startup")
check(not U.isZombie(body) and U.isExternalHuman(body), "SWM bodies are human before perception")
body.animVariables.NotAloneBody = nil
body.modData.notAloneBody = true
check(A.owns(body), "saved/server mod-data marker protects before animation setup")
body.modData.notAloneBody = nil
body.animVariables.SWMSeatPuppet = true
check(A.owns(body), "seated visual is also protected")
body.animVariables.SWMSeatPuppet = nil
body.animVariables.SurvivorNPC = true
body.modData.notAloneBody = "true"
check(not A.owns(body), "generic NPC flags and string values cannot claim an ordinary zombie")
body.modData.notAloneBody = nil
Bridge = { body = body }
check(A.owns(body) and not A.owns(normal), "current exact client body reference protects only its owner")
Bridge = { isCompanion = function(candidate) return candidate == body end }
check(A.owns(body), "client identity API covers unmarked mirrors")
Bridge = nil
BridgeServer = { isCompanionBody = function(candidate) return candidate == body end }
check(A.owns(body), "server identity API covers other owners' bodies")
BridgeServer = nil
check(not A.owns(body), "releasing a body clears protection without a sticky identity cache")
body.animVariables.NotAloneBody = true
mods.Bridge = true
check(A.initialize() and A.status().state == "active", "Bridge mod id activates the passive adapter")
check(A.relationship(body) == "neutral" and A.relationship(normal) == "unknown", "SWM never supplies LF hostility")
A.reset();mods.Bridge = nil;mods["\\Bridge"] = true
check(A.initialize(), "qualified Build 42 mod id is accepted")
A.reset();mods["\\Bridge"] = nil
check(not A.initialize() and A.status().state == "absent", "disabled mod is authoritative absence")
local reads = 0
local absentActor = setmetatable({}, { __index = function() reads = reads + 1;error("native read") end })
queries = 0
local absentOwned = false
for _ = 1, 100 do absentOwned = A.owns(absentActor) or absentOwned end
check(not absentOwned, "absent dependency keeps repeated identity scans inert")
check(reads == 0 and queries == 0, "absent fast path reads no markers and queries no mod lists")
A.reset()
check(A.owns(body), "world reset clears the previous world's absence")
check(not A.owns(nil) and not A.owns(1) and not A.owns("Rin"), "non-actors are rejected")
check(not A.owns(absentActor), "unexposed native method lookup is contained")
function getActivatedMods() return { contains = function() error("list not ready") end } end
check(not A.initialize() and A.status().state == "pending" and A.owns(body),
    "unready mod list cannot erase proven body identity")
function getActivatedMods() return { contains = function(_, key) return key == "Bridge" end } end
A.initialize()
F.reset()
local previousRuntime = SC.Runtime
SC.Runtime = { frameSerial = function() return 1 end }
local first = F.get(normal)
check(first.zombie, "ordinary native zombie remains an enemy")
normal.animVariables.NotAloneBody = true
check(not F.get(normal).zombie and F.get(normal).gone, "same-frame promotion invalidates cached zombie facts")
normal.animVariables.NotAloneBody = nil
F.forget(normal)
check(F.get(normal).zombie, "released/recycled unmarked zombie becomes an enemy again")
SC.Runtime = previousRuntime
SC_TEST_REPORT = "STAY_WITH_ME_IDENTITY_PASS checks=" .. checks
