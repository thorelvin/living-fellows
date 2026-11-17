-- SPDX-License-Identifier: MIT
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local U, A, checks = SC.GameplayUtil, SC.StayWithMeAdapter, 0
local function check(value, why)
    checks = checks + 1
    assert(value, "SWM combat " .. checks .. ": " .. why)
end
function getActivatedMods() return { contains = function(_, key) return key == "Bridge" end } end
A.reset();A.initialize()
local actor = f.actor("sc-swm-guard", 10, 10, {})
local rin, zombie = f.zombie(11, 10, {}), f.zombie(13, 10, {})
rin.animVariables.NotAloneBody = true
local writes = 0
for _, key in ipairs({ "pathToCharacter", "pathToLocation", "setUseless", "setCanWalk",
    "setTarget", "changeState", "setPath2", "setPathFindBehavior2" }) do
    rin[key] = function() writes = writes + 1;error("foreign navigation mutation") end
end
check(SC.Factions.relationshipBetween(actor, rin, f.player) == "neutral"
    and SC.Factions.isProtectedBetween(actor, rin, f.player)
    and not SC.Factions.isHostileBetween(actor, rin, f.player), "SWM is protected through the shared relationship policy")
-- Competing compatibility annotations cannot override SWM ownership.
local oldBandits, oldALife = SC.BanditsAdapter, SC.ALifeAdapter
SC.BanditsAdapter = { owns = function(value) return value == rin end,
    relationship = function() return "hostile" end }
SC.ALifeAdapter = { owns = function(value) return value == rin end,
    relationship = function() return "hostile" end }
check(not SC.Factions.isHostileBetween(actor, rin, f.player)
    and not SC.Factions.isHostileBetween(rin, actor, f.player)
    and SC.Factions.relationshipBetween(actor, rin, f.player) == "neutral",
    "SWM identity takes priority over stale hostile foreign metadata")
SC.BanditsAdapter, SC.ALifeAdapter = oldBandits, oldALife
local priorNative = f.cell.getZombieList
function f.cell:getZombieList()
    return { size = function() return 2 end, get = function(_, index) return index == 0 and rin or zombie end }
end
local snapshot = SC.Senses.snapshot(actor, f.player, {})
local protected, threats = false, false
for _, row in ipairs(snapshot.protectedActors or {}) do if row.actor == rin then protected = true end end
for _, row in ipairs(snapshot.threats or {}) do
    check(row.actor ~= rin, "SWM never enters ordinary zombie targets")
    if row.actor == zombie then threats = true end
end
check(protected and threats and snapshot.humanThreat == nil,
    "production perception protects SWM and still discovers the real zombie")
local blocked, blocker = SC.Combat.friendlyFireBlocked(actor, zombie,
    { kind = "melee", snapshot = snapshot })
check(blocked and blocker == rin, "SWM blocks an incidental melee lane")
blocked, blocker = SC.Combat.friendlyFireBlocked(actor, zombie,
    { kind = "ranged", snapshot = snapshot })
check(blocked and blocker == rin, "SWM blocks an incidental firearm lane")
rin.square = f.cell:getGridSquare(11, 13, 0)
check(not SC.Combat.friendlyFireBlocked(actor, zombie, {kind="ranged",snapshot=snapshot}),
    "a clear lane still allows combat against the real zombie")
local providerCalls = 0
local provider = { directNative = false, attack = function()
    providerCalls = providerCalls + 1;return true, "provider_attack"
end }
-- Drive the production native combat handler after outer ownership admission.
-- The configured handler itself owns the direct-target guard.
for _, action in ipairs({ "attack_melee", "attack_firearm", "shove", "stomp" }) do
    local okay, why = SC.NativeCombatActions.dispatch(actor, action, { target = rin }, provider)
    check(not okay and why == "stay_with_me_target_protected" and providerCalls == 0,
        "stale/direct " .. action .. " is rejected before a provider or native swing")
end
check(writes == 0, "adapter, perception and rejected attacks never control foreign navigation")
f.cell.getZombieList = priorNative
SC_TEST_REPORT = "STAY_WITH_ME_COMBAT_PASS checks=" .. checks
