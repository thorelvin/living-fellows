-- SPDX-License-Identifier: MIT
-- Real utility/facts/adapters; count only ownership reads, not normal facts.
local SC, checks = SurvivorCompanion, 0
local function check(value, why)
    checks = checks + 1
    assert(value, "External human fast path " .. checks .. ": " .. why)
end
local mods, ownershipReads, modQueries, frame = {}, 0, 0, 1
function getActivatedMods()
    modQueries = modQueries + 1
    return { contains = function(_, id) return mods[id] == true end }
end
function instanceof(value, name) return value.class == name end
SC.State = { active = true }
SC.Runtime = { frameSerial = function() return frame end }
local square = { getX = function() return 1 end, getY = function() return 2 end, getZ = function() return 0 end }
local function zombie()
    local actor = { class = "IsoZombie", md = {}, bandit = false }
    function actor:hasModData() ownershipReads = ownershipReads + 1 return next(self.md) ~= nil end
    function actor:getModData() ownershipReads = ownershipReads + 1 return self.md end
    function actor:getVariableString() ownershipReads = ownershipReads + 1 return nil end
    function actor:GetVariable() ownershipReads = ownershipReads + 1 return nil end
    function actor:getVariableBoolean(key)
        if key == "Bandit" then ownershipReads = ownershipReads + 1 return self.bandit end
        return false
    end
    function actor:getSquare() return square end
    function actor:getX() return 1.5 end
    function actor:getY() return 2.5 end
    function actor:getZ() return 0 end
    function actor:isDead() return false end
    function actor:getHealth() return 1 end
    function actor:isExistInTheWorld() return true end
    function actor:isReanimatedForGrappleOnly() return false end
    return actor
end
local bandit, alife, ordinary = zombie(), zombie(), zombie()
bandit.bandit, alife.md.ProjectALifeOwned = true, true
local B, A, U, F = SC.BanditsAdapter, SC.ALifeAdapter, SC.GameplayUtil, SC.ZombieFacts
check(B.owns(bandit) and A.owns(alife), "marked startup actors remain human before initialize")
local function absentWorld()
    B.reset()
    A.reset()
    mods.Bandits2, mods.ProjectALifeNPCs = nil, nil
    check(not B.initialize() and B.status().state == "absent", "Bandits absence verified")
    check(not A.initialize() and A.status().state == "absent", "A-Life absence verified")
    F.reset()
    ownershipReads, modQueries = 0, 0
    local first = F.get(ordinary)
    check(first.zombie and not first.gone, "ordinary native facts still build with optional mods absent")
    for _ = 1, 100 do
        check(U.isZombie(ordinary), "ordinary classification preserved")
        check(F.get(ordinary) == first, "same-frame facts cache preserved")
    end
    check(ownershipReads == 0, "absent adapters perform zero native marker or mod-data reads, including facts cache hits")
    check(modQueries == 0, "absence checks do not query activated mods per zombie")
end
absentWorld()
mods.Bandits2 = true
check(not B.initialize() and B.status().state == "unsupported", "partial Bandits startup has no combat authority")
check(B.owns(bandit) and not U.isZombie(bandit), "enabled partial Bandits remain protected humans")
F.reset()
local prior = F.get(ordinary)
ordinary.bandit = true
check(prior.zombie and F.get(ordinary).gone and not F.get(ordinary).zombie,
    "Bandit promotion overrides the zombie facts cache in the same frame")
ordinary.bandit = false
mods.ProjectALifeNPCs = true
check(not A.initialize() and A.status().state == "unsupported", "partial A-Life startup has no combat authority")
check(A.owns(alife) and not U.isZombie(alife), "enabled partial A-Life shells remain protected humans")
F.reset()
prior = F.get(ordinary)
ordinary.md.ProjectALifeOwned = true
check(prior.zombie and F.get(ordinary).gone and not F.get(ordinary).zombie,
    "A-Life promotion overrides the zombie facts cache in the same frame")
ordinary.md.ProjectALifeOwned = nil
B.reset()
A.reset()
check(B.owns(bandit) and A.owns(alife), "reset clears prior absence and preserves pre-initialize classification")
frame = frame + 1
absentWorld()
SC_TEST_REPORT = "EXTERNAL_HUMAN_FASTPATH_PASS checks=" .. checks .. " absent_native_reads=" .. ownershipReads
