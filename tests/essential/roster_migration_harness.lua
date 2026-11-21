-- SPDX-License-Identifier: MIT
-- Drive old resident rows through restoration and the normal maintenance pulse.
local SC = SurvivorCompanion
local B, W, f = SC.BaseLife, SC.BaseWork, SC.TestFixture
local checks = 0
local function check(result, message)
    checks = checks + 1
    assert(result, 'roster migration '..checks..' '..message)
end
local live, gone, lookups = {}, {}, 0
SC.Registry.byId = function(id)
    lookups = lookups + 1
    return live[id]
end
SC.Persistence = {restoreStatus=function() return true end, isPending=function() return false end}
local function camp()
    B.reset()
    assert(B.create({x=3,y=4,z=0},'Roster migration'))
end
local function pulse()
    local before = lookups
    f.clock = f.clock + 1001
    W.auditMaintenance(nil,function() return 0 end)
    check(lookups-before <= 1, 'maintenance classified more than one resident on this pulse')
end
camp()
for index=1,18 do
    local id = 'sc-ledger-'..index
    assert(B.assign(id,'maintainer',true))
    if index % 3 == 0 then gone[#gone+1] = id else live[id] = {dormant=true} end
end
local saved = assert(B.export())
check(saved.residents[gone[1]].duty, 'legacy save contains the stale on-duty role')
camp()
assert(B.assign('sc-other-world','guard',true))
assert(B.restore(saved))
for tick=1,18 do pulse() end
for _,id in ipairs(gone) do check(not B.resident(id), 'bounded public audit retained an old dead resident') end
for id in pairs(live) do check(B.resident(id).role=='maintainer' and B.resident(id).duty, 'audit lost a dormant row') end
local cleaned = assert(B.export())
assert(B.restore(cleaned))
check(not B.resident(gone[1]) and not cleaned.residents[gone[#gone]], 'disk state reintroduced a retired resident')

-- Exercise each ordinary writer, including Handover's explicit takeover removal.
camp()
assert(B.assign('sc-stays','guard',true)); live['sc-stays']={dormant=true}
assert(B.applyResidentAssignment(assert(B.planResidentAssignment('sc-group','generalist',true))))
assert(B.restoreResident('sc-undo',{present=true,value={baseId=B.active().id,role='scout',duty=true}}))
for tick=1,3 do pulse() end
check(B.resident('sc-group')==nil and B.resident('sc-undo')==nil and B.resident('sc-stays')~=nil,
    'the index must follow group assignment, rollback and reset')
assert(B.abandon()); assert(B.create({x=3,y=4,z=0},'New camp'))
assert(B.assign('sc-after-abandon','guard',true)); pulse()
check(B.resident('sc-after-abandon')==nil, 'a new camp audits its first resident immediately')
assert(B.assign('sc-before-empty-restore','guard',true))
assert(B.restore(nil)); assert(B.create({x=3,y=4,z=0},'Fresh restore'))
assert(B.assign('sc-only','guard',true)); pulse()
check(not B.resident('sc-only'), 'fresh-world restore discards the former audit index')
assert(B.assign('sc-before-reset','guard',true)); camp()
assert(B.assign('sc-after-reset','guard',true)); pulse()
check(not B.resident('sc-after-reset'), 'reset discards the former audit index')
assert(B.assign('sc-takeover','scout',true))
assert(B.restoreResident('sc-takeover',{present=false}))
check(B.resident('sc-takeover')==nil, 'explicit takeover keeps its immediate removal semantics')
assert(B.assign('sc-next','scout',true)); pulse()
check(not B.resident('sc-next'), 'taking over a recruit releases its audit slot immediately')
SC_TEST_REPORT='ROSTER_MIGRATION_PASS checks='..checks
