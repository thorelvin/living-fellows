-- SPDX-License-Identifier: MIT
-- Read paths can run before the bounded migration reaches a dead resident.
local SC, f = LivingFellows, LivingFellows.TestFixture
local B, W = SC.BaseLife, SC.BaseWork
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "camp roster readers: " .. message)
end
local function camp()
    B.reset()
    local ok, base = B.create(f.makeSquare(5, 5, 0), "Roster")
    assert(ok)
    return base
end
local function living(id, role)
    local actor = f.actor(id, 5, 5, {})
    f.registry[id] = {id=id, actor=actor, identity={forename="Morgan", surname="Reed"}}
    actor.modData.SC_Order = "base_duty"
    assert(B.assign(id, role, true))
    return actor
end
local function listHas(values, id)
    for _, candidate in ipairs(values) do if candidate==id then return true end end
    return false
end
local function rowFor(summary, id)
    for _, row in ipairs(summary.residentRows) do if row.id==id then return row end end
end
local dead, guard, newest = "sc-00-dead", "sc-11-live", "sc-26-live"
local pending
SC.Persistence = {restoreStatus=function() return true end, isPending=function(id) return pending==id end}
local base = camp()
assert(B.assign(dead, "guard", true))
for i=11,26 do living("sc-"..i.."-live", i==11 and "guard" or "generalist") end
local duty = B.dutyResidentIds()
check(#duty==16 and not listHas(duty,dead) and listHas(duty,newest), "sixteen living duty slots reach the newest recruit")
local medicalScan = {}
SC.MedicalVisits.audit(base, function() return 0 end, medicalScan)
check(listHas(medicalScan.visitRows,newest) and not listHas(medicalScan.visitRows,dead),
    "the medical audit includes the newest recruit before roster migration")
local observed=SC.BaseAlert.observe(f.registry[guard].actor,f.player,{threats={{x=5,y=5,z=0}}},
    {recruited=true,order="base_duty"},f.clock)
check(observed and SC.BaseAlert.peek().told[newest], "the newest recruit hears the camp alarm")
SC.BaseAlert.reset()
for _, clock in ipairs({0,180000,360000,540000}) do
    local serving, selected, count = B.guardStatus(guard,clock)
    check(serving and selected==guard and count==1, "the surviving guard covers rotation at "..clock)
end
for _, policy in ipairs({"all_hands","role_based"}) do
    assert(B.setPolicy("defense",policy))
    local serving, selected, count = B.guardStatus(dead,0)
    local eligible = policy=="all_hands" and 16 or 1
    check(not serving and selected==nil and count==eligible, "a retired guard has no "..policy.." shift")
end
assert(B.assign(dead,"medic",true))
local view = B.summary()
check(view.residents==16 and view.duty==16 and #view.residentRows==16 and not rowFor(view,dead),
    "Staffing omits the retired resident from its rows and totals")
local operations = B.auditOperations(true)
local medic
for _, row in ipairs(operations.coverage) do if row.role=="medic" then medic=row end end
check(medic and medic.required==1 and medic.assigned==0, "a dead medic cannot fill the camp coverage requirement")
local byId, lookups=SC.Registry.byId,{}
SC.Registry.byId=function(id)
    lookups[id]=(lookups[id] or 0)+1
    return byId(id)
end
local observedView=B.summary()
SC.Registry.byId=byId
local exactlyOnce=lookups[dead]==1
for i=11,26 do exactlyOnce=exactlyOnce and lookups["sc-"..i.."-live"]==1 end
check(exactlyOnce and #observedView.residentRows==16, "Staffing observes each present and missing registry identity once")

local away = "sc-31-away"
f.registry[away]={id=away, dormant=true, identity={forename="Ellis",surname="West"}}
assert(B.assign(away,"farmer",true))
check(rowFor(B.summary(),away).name=="Ellis West", "a dormant resident keeps their saved name in Staffing")
SC_TEST_STAFFING_VIEW=B.summary()
f.registry[away], pending = nil, away
local waiting = rowFor(B.summary(),away)
check(waiting and waiting.role=="farmer" and waiting.duty and waiting.name~="" and waiting.name~=away,
    "pending restore preserves duty and keeps internal IDs out of Staffing")

-- Advance the ordinary maintenance family while leaving the independent
-- migration cursor idle. Every row is intentionally still in the ledger.
base=camp()
local maintainer = living("sc-60-maintainer","maintainer")
local helper = living("sc-61-helper","generalist")
assert(B.assign(dead,"maintainer",true))
base.settings.autoMaintenance, base.settings.routines, base.settings.workload=true,false,"essential"
local target={id="maintenance:1",kind="barricade",enabled=true,x=5,y=5,z=0,objectId="barricade-target"}
base.maintenanceTargets[1]=target
local originalResolve, originalAudit=B.resolveObject,B.auditResidentRoster
local originalYard=SC.LogYard
SC.LogYard={audit=function() return false end}
local window={getBarricadeOnSameSquare=function() end, getBarricadeOnOppositeSquare=function() end,
    getNorth=function() return true end}
B.resolveObject=function(row) if row==target then return window end return originalResolve(row) end
B.auditResidentRoster=function() end
local function nextBarricade()
    for turn=1,48 do
        local ok,job=W.auditMaintenance(f.player,function() return math.huge end)
        if ok and type(job)=="table" and job.type=="barricade" then return job end
    end
end
local job=nextBarricade()
check(job and job.assignedId==maintainer.id, "a new barricade targets the surviving maintainer")
if job then assert(B.cancelJob(job.id)) end
assert(B.assign(maintainer.id,"generalist",true))
job=nextBarricade()
local claimed=job and B.claimJob(helper.id,function(candidate) return candidate==job end)
check(job and job.assignedId==nil and claimed==job, "a generalist can take barricade upkeep after the last maintainer dies")
B.resolveObject,B.auditResidentRoster=originalResolve,originalAudit
SC.LogYard=originalYard

-- One physically prepared serving is enough for one chef and a deceased row.
-- A second living resident creates demand for another automatic meal.
base=camp()
local chef=living("sc-70-chef","chef")
assert(B.assign(dead,"generalist",true))
local salad=f.item("Base.Salad","Food")
local fridge=f.inventory({salad})
function fridge:getType() return "fridge" end
function fridge:isPowered() return true end
local sink={getContainer=function() return fridge end}
local square=f.makeSquare(5,5,0)
local priorObjects=square.objects
square.objects={sink}
base.zones={{kind="area",x1=5,y1=5,x2=5,y2=5,z=0}}
SC.ChefWork.reset()
local cooked,why=SC.ChefWork.ensureAutomaticJob(chef,B.resident(chef.id))
check(not cooked and why=="chef_stock_ready", "one prepared serving feeds one living resident")
living("sc-71-diner","generalist")
SC.ChefWork.reset()
local queued,meal=SC.ChefWork.ensureAutomaticJob(chef,B.resident(chef.id))
check(queued and meal.type=="cook", "a second living resident still creates automatic meal demand")
square.objects=priorObjects
SC_TEST_ROSTER_CHECKS=checks
