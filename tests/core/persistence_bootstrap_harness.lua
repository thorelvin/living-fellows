-- SPDX-License-Identifier: MIT
-- Run the production import, retry and save transaction with a provider that
-- can become available after the old six-attempt budget would have expired.
local SC = SurvivorCompanion
local P = SC.Persistence
local checks, calls, successes = 0, 0, 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'check ' .. tostring(checks) .. ': ' .. message)
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local failure = 'SCBridge is not exposed; install or repair the native companion bootstrap; fallback: native actor bridge unavailable; experimental IsoPlayer NPC fallback is disabled'
local square = { getX=function() return 10 end, getY=function() return 20 end, getZ=function() return 0 end }
function getCell() return { getGridSquare=function() return square end } end
SC.Actor = {
    spawn = function(at, profile)
        calls = calls + 1
        if failure then return nil, failure end
        check(at == square and profile.id == 'sc-bootstrap-retained'
            and profile.identity.forename == 'Morgan' and profile.restored,
            'availability resumes the same saved identity at the loaded square')
        successes = successes + 1
        return { restoredId=profile.id }
    end,
    cancelSpawn=function() return true end,
}
local function savedRecord()
    return {
        id='sc-bootstrap-retained', recruited=true,
        identity={forename='Morgan',surname='Reed',gender='female',outfit=''},
        speechColorKey='lavender', position={x=10,y=20,z=0},
        inventory={schema=2,complete=true,count=0,roots={},legacy=false,
            equipment={worn={},attached={}}},
        skills={{id='Axe',level=4,xp=812.5}}, vitals={fatigue=0.47,endurance=0.63},
        order={mode='follow'}, extensionForFuture={marker='keep-exactly'},
    }
end
local original = savedRecord()
local store = SC_TEST_SET_WORLD_STORE({document={schema=SC.Identity.saveSchema,
    companions={[original.id]=original},factionActors={}}})
check(P.restore({}) == true and P.pendingCount() == 1, 'valid recruit is imported while its bridge is missing')
for index=1,12 do
    SC_TEST_CLOCK = SC_TEST_CLOCK + 300000
    P.restorePulse({})
end
local entry = P.pendingSnapshot()[original.id]
check(entry and entry.status == 'waiting_environment' and entry.attempts == 0
        and entry.failureClass == 'transient' and calls >= 12,
    'missing bootstrap keeps probing past six attempts without quarantine')
check(P.quarantineSnapshot().companions[original.id] == nil, 'bridge absence never quarantines the recruit')
check(P.save({}) == true and same(store.document.companions[original.id], original),
    'synchronous save retains the complete original record, including unknown fields')
check(P.requestScheduledSave({}) == true, 'scheduled save accepts the waiting recruit')
local status
for index=1,1000 do status=P.pulse(); if status ~= 'yielded' then break end end
check(status == 'complete' and same(store.document.companions[original.id], original),
    'scheduled save retains the same complete waiting record')
failure = nil
SC_TEST_CLOCK = SC_TEST_CLOCK + 5001
P.restorePulse({})
check(P.pendingCount() == 0 and successes == 1, 'late bridge availability restores once without a manual retry')
P.restorePulse({})
check(successes == 1, 'a completed restore cannot create a duplicate')

-- An installed old bridge is an environment wait too. Updating it must not
-- cost this recruit restore attempts or quarantine its original save record.
check(P.reset() == true, 'reset before protocol mismatch')
failure = 'native bridge protocol mismatch: expected 42.22-isocompanion-34, received 42.22-isocompanion-33; fallback: native actor bridge unavailable; experimental IsoPlayer NPC fallback is disabled'
original = savedRecord()
store = SC_TEST_SET_WORLD_STORE({document={schema=SC.Identity.saveSchema,
    companions={[original.id]=original},factionActors={}}})
check(P.restore({}) == true, 'protocol mismatch imports a valid raw recruit')
for index=1,12 do SC_TEST_CLOCK=SC_TEST_CLOCK+300000; P.restorePulse({}) end
entry = P.pendingSnapshot()[original.id]
check(entry and entry.status == 'waiting_environment' and entry.attempts == 0
    and entry.failureClass == 'transient', 'old bridge never consumes the recruit retry budget')
check(P.save({}) == true and same(store.document.companions[original.id], original),
    'old bridge preserves the complete saved recruit')
failure = nil
SC_TEST_CLOCK=SC_TEST_CLOCK+5001; P.restorePulse({})
check(P.pendingCount() == 0 and successes == 2, 'matching bridge resumes the same recruit once')

-- A damaged native API or invalid native inventory transaction retains its
-- existing bounded policy.
for _,reason in ipairs({
    'native bridge readiness check failed: broken_native_api; fallback: native actor bridge unavailable; experimental IsoPlayer NPC fallback is disabled',
    'native actor inventory could not be restored',
}) do
    check(P.reset() == true, 'reset the preceding completed import')
    failure = reason
    original = savedRecord()
    store = SC_TEST_SET_WORLD_STORE({document={schema=SC.Identity.saveSchema,
        companions={[original.id]=original},factionActors={}}})
    check(P.restore({}) == true, 'negative control imports a valid raw recruit')
    for index=1,8 do SC_TEST_CLOCK=SC_TEST_CLOCK+300000; P.restorePulse({}) end
    entry = P.pendingSnapshot()[original.id]
    check(entry and entry.status == 'quarantined' and entry.failureClass ~= 'transient',
        'incompatible or damaged native restore remains bounded: ' .. reason)
    check(P.save({}) == true and same(store.document.companions[original.id], original),
        'quarantine still preserves the original record in negative controls')
end
print('PERSISTENCE_BOOTSTRAP_KAHLUA_PASS checks=' .. checks)
