-- SPDX-License-Identifier: MIT
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local B = SC.BaseLife
local dead, alive = "sc-former-resident", "sc-living-resident"
local actor = f.actor(alive, 2, 3, {})
f.registry[alive] = actor
SC.Persistence = {restoreStatus=function() return true end, isPending=function() return false end}
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, "resident work " .. checks .. ": " .. label)
end
local function camp()
    B.reset()
    local okay, base = B.create({x=2,y=3,z=0}, "Resident recovery")
    assert(okay and B.assign(dead, "maintainer", true) and B.assign(alive, "generalist", true))
    return base
end
local function enqueue(kind, id, target)
    local okay, job = B.enqueueJob({type=kind, assignedId=id, target=target or {}})
    assert(okay, tostring(job))
    return job
end
local function retire()
    if B.forgetGoneResident then return B.forgetGoneResident(dead) end
end

local base = camp()
local barrier = enqueue("barricade", dead, {objectId="object:1", maintenanceId="maintenance:1"})
barrier.state, barrier.reservedBy, barrier.leaseUntil = "active", dead, f.clock+60000
local repair, craft = enqueue("repair", dead), enqueue("craft_supply", dead)
local selfCare = enqueue("replace_bandage", dead)
local playerJob = enqueue("build", dead)
playerJob.state = "manual"
local otherJob = enqueue("barricade", dead, {objectId="object:other"})
otherJob.state, otherJob.reservedBy, otherJob.leaseUntil = "active", alive, f.clock+65000
local blocked = enqueue("haul", dead, {yardUnstack={ownerId=dead,x=42,y=21,z=0}})
local floor = enqueue("sort_floor", dead, {floorCargo={zoneId="zone:former",x=42,y=21,z=0,itemId=213}})
local visit = enqueue("replace_bandage", dead, {patientId=alive, medicalVisit={
    medicId=dead,owner=dead,phase="recovery",careKey=alive..":0:remove_glass",careKind="remove_glass"}})
local patientVisit = enqueue("replace_bandage", alive, {patientId=dead, medicalVisit={owner=alive}})
local another = enqueue("repair",alive)
local oldCancel, attempts = SC.Commands.cancelBaseJob, 0
SC.Commands.cancelBaseJob = function(id, reason)
    if id==barrier.id then attempts=attempts+1 end
    return oldCancel(id, reason)
end
local oldSquare = SC.GameplayUtil.gridSquare
local shelfLoaded = false
SC.GameplayUtil.gridSquare = function(x,y,z)
    if x==42 and y==21 and not shelfLoaded then return nil end
    return oldSquare(x,y,z)
end
B.setRestriction(dead,"quarantine","crisis:test")
local revision=B.workConsistencyRevision()
local removed=retire()
check(B.job(barrier.id)==barrier and barrier.state=="pending" and not barrier.assignedId
    and not barrier.reservedBy and barrier.leaseUntil==0 and barrier.target.objectId=="object:1",
    "the dead maintainer's exact marked target is immediately open")
check(attempts==1, "release cancels only the matching barricade command")
check(B.job(repair.id)==nil and B.job(craft.id)==nil, "personal repair and crafting requests are retired")
check(B.job(selfCare.id)==nil, "legacy self-care is removed with its patient")
check(B.job(patientVisit.id)==nil, "an active medic visit to the deceased patient is cancelled through MedicalVisits")
check(B.job(visit.id)==visit and visit.assignedId==alive and not visit.reservedBy
    and visit.target.medicalVisit.careKey==alive..":0:remove_glass" and not visit.target.medicalVisit.owner
    and visit.target.medicalVisit.selfFallback, "a surviving patient keeps exact recovery after its medic dies")
check(B.job(another.id)==another and another.assignedId==alive and B.job(playerJob.id)==playerJob
    and playerJob.state=="manual" and otherJob.state=="active" and otherJob.reservedBy==alive,
    "other residents' leases and a manual player build survive")
check(removed and not B.resident(dead) and B.resident(alive) and B.restriction(dead)=="quarantine",
    "the roster drops the dead resident even when a separate cargo receipt must wait")
check(B.workConsistencyRevision()>revision and not retire(), "roster retirement invalidates work and is idempotent")
check(B.job(blocked.id)==blocked and blocked.assignedId==dead, "the independent blocked cargo still has its exact owner")
check(B.job(floor.id)==floor and not floor.assignedId and not floor.target.floorCargo,
    "the floor sorter releases its own saved cargo before worker affinity is cleared")
shelfLoaded = true
for i=1,#base.jobs+1 do B.auditJobRecovery() end
check(B.job(blocked.id)==blocked and not blocked.assignedId and blocked.state=="pending",
    "a later recovery pulse releases the previously unavailable cargo job")
SC.Commands.cancelBaseJob, SC.GameplayUtil.gridSquare = oldCancel, oldSquare
otherJob.state, otherJob.reservedBy = "pending", nil
local taken=B.claimJob(alive,function(job) return job==barrier end)
check(taken==barrier and barrier.reservedBy==alive, "a living generalist can claim the old barricade immediately")

for _,kind in ipairs({"production","gather_materials"}) do
    for workers=1,2 do
        base=camp()
        local ledger=kind=="production" and base.production or base.work
        local order={id="orphan-order",workers={dead},state="running",completed=1,delivered=1,requested=4,
            settings={autoCorpsekeeper=true},operation="collect_bodies",material="logs"}
        ledger.orders[1]=order
        local surviving
        if workers==2 then
            order.workers[2]=alive
            order.state,order.blocker="blocked","storage_unloaded"
            surviving=enqueue(kind,alive,{orderId=order.id})
        end
        -- Retiring work cannot rely on finding a matching job in an old save.
        retire()
        check(#order.workers==workers-1,kind.." frees the missing job's worker slot")
        if workers==1 then
            check(order.state=="cancelled",kind.." closes an orphaned single-worker order")
        else
            check(order.workers[1]==alive and B.job(surviving.id)==surviving
                and order.state=="blocked" and order.blocker=="storage_unloaded",
                kind.." keeps the living worker and the pre-existing blocker")
            local newcomer="sc-new-worker"
            f.registry[newcomer]={actor=f.actor(newcomer,2,3,{}),recruited=true}
            assert(B.assign(newcomer,"generalist",true))
            local add=kind=="production" and B.addProductionWorker or B.addGatherWorker
            check(add(order.id,newcomer) and order.workers[2]==newcomer,
                kind.." accepts a new recruit through its ordinary two-worker cap")
        end
        check(order.delivered==1 and order.completed==1,kind.." does not credit a unit for the lost worker")
    end
end
base=camp()
local mixed={id="mixed-order",workers={dead},state="running",operation="dig_graves",requested=3,completed=0}
base.production.orders[1]=mixed
local leased=enqueue("production",dead,{orderId=mixed.id})
leased.state,leased.reservedBy,leased.leaseUntil="active",alive,f.clock+60000
retire()
check(B.job(leased.id)==leased and leased.assignedId==alive and leased.reservedBy==alive
    and leased.state=="active" and mixed.state=="running" and #mixed.workers==1 and mixed.workers[1]==alive,
    "a real surviving lease wins over conflicting legacy assignment metadata")

-- The version-one reader accepts several saved camps. Identical old per-camp
-- IDs must never send one camp's cleanup to a different camp's runtime.
base=camp()
local activeJob=enqueue("barricade",alive,{objectId="object:1"})
base.zones[2]={id="zone:lumber",kind="lumber",x1=0,x2=2,y1=0,y2=3,z=0}
base.zones[3]={id="zone:yard",kind="log_yard",x1=4,x2=5,y1=4,y2=5,z=0}
base.work.orders[1]={id="work-order:1",operation="gather",material="logs",workers={alive},state="running",
    requested=2,delivered=0,zoneId="zone:lumber",destinationZoneId="zone:yard",itemType="Base.Log"}
local logJob=enqueue("gather_materials",alive,{orderId="work-order:1"})
local ok,cargo=B.allocateWorkReceipt({orderId="work-order:1",jobId=logJob.id,actorId=alive,
    source={x=1,y=2,z=0},destinationZoneId="zone:yard",destinationPoint={x=4,y=4,z=0},nativeId=181,snapshot={}})
assert(ok,tostring(cargo))
cargo.id,cargo.token="work-receipt:1","work-receipt:1"
local saved=B.export()
local inactive=B.export().bases[base.id]
inactive.id="base:99"
saved.bases[inactive.id]=inactive
saved.residents[dead].baseId=inactive.id
inactive.jobs[1].assignedId=dead
inactive.jobs[2].assignedId=dead
inactive.work.orders[1].workers={dead}
inactive.work.receipts[1].actorId=dead
local restored,restoreReason=B.restore(saved)
assert(restored,tostring(restoreReason))
retire()
saved=B.export()
check(not saved.residents[dead] and saved.bases["base:99"].jobs[1].assignedId==nil
    and B.job(activeJob.id).assignedId==alive, "a detached camp releases only its own saved assignment")
local retiredCamp,activeCamp=saved.bases["base:99"],saved.bases[saved.activeBaseId]
check(retiredCamp.work.receipts[1].phase=="cancelled" and retiredCamp.work.receipts[1].accounted
    and retiredCamp.work.orders[1].state=="cancelled" and retiredCamp.work.orders[1].delivered==0,
    "a detached camp settles its dead carrier's receipt without a physical delivery")
check(activeCamp.work.receipts[1].phase=="selected" and activeCamp.work.orders[1].workers[1]==alive
    and B.job(logJob.id).assignedId==alive, "the active camp retains its own identical legacy receipt and worker")
check(B.restore(saved), "the independently retired ledgers round-trip through the save validator")

base=camp()
f.registry[dead]={actor=f.actor(dead,2,3,{}),recruited=true}
local cached=B.auditOperations(true)
check(cached and B.auditOperations(false), "the camp can publish staffing derived from the old roster")
f.registry[dead]=nil
revision=B.workConsistencyRevision()
retire()
check(B.auditOperations(false)==nil, "retirement immediately invalidates the published operations cache")
check(B.workConsistencyRevision()==revision+1, "a roster-only death changes the work revision once")
do
    local oldBase, oldNav, util = SC.BaseLife, SC.Navigation, SC.GameplayUtil
    local oldGrid, oldLoaded, oldFree, oldSame =
        util.gridSquare, util.loadedSquare, util.isSquareFree, util.sameSquare
    local oldClock, clock, surveyed = util.nowMs, 1000, 0
    local shelter, rally = { x = 3, y = 3, z = 0 }, { x = 4, y = 3, z = 0 }
    local camp = { id = "base:parking", zones = {
        { kind = "area", x1 = 3, y1 = 3, x2 = 3, y2 = 3, z = 0 },
    } }
    local indoors, rallied, rallyInParking = true, false, false
    SC.BaseLife = {
        active = function() return camp end,
        isOutdoorSquare = function(square) return square ~= shelter or not indoors end,
        isInside = function(square, kind) return kind ~= "parking" or rallyInParking end,
        zoneCenter = function() return rally end,
        withinWorkReach = function() return true end,
    }
    util.nowMs = function() return clock end
    util.gridSquare = function() surveyed = surveyed + 1 return shelter end
    util.loadedSquare = function(value) return value end
    util.isSquareFree = function() return true end
    util.sameSquare = function(_, target) return rallied and target == rally end
    local goal
    SC.Navigation = { requestAny = function(_, choices, _, intent)
        check(intent.action == "return_to_base" and intent.requireSameSquare
                and intent.workCampOnly, "parking departure uses ordinary checked base navigation")
        goal = choices[1]
        return true, "moving"
    end }
    local approach = SC.BaseWork.approachCampShelter
    local route = {}
    check(approach(actor, route, true) and goal == shelter, "parking departure prefers a covered camp tile")
    clock = clock + 11000
    check(approach(actor, route, true) and surveyed == 1, "a slow route keeps its shelter goals across refresh time")
    indoors = false
    check(approach(actor, {}, true) and goal == rally, "an open-air camp routes to its off-lot rally")
    rallied = true
    local handled, reason = approach(actor, {}, true)
    check(not handled and reason == "camp_rally_reached", "the rally must be reached before outdoor downtime")
    rallyInParking = true
    handled, reason = approach(actor, {}, true)
    check(not handled and reason == "camp_shelter_unavailable", "a rally in parking cannot end the departure")
    local oldDowntime = SC.Downtime
    SC.BaseLife.resident = function() return { duty = false } end
    SC.Downtime = {
        parkingExitCamp = function(owner) return owner == actor and camp or nil end,
        update = function() return true, "heading_for_shelter" end,
    }
    handled, reason = SC.BaseWork.update(actor, nil, {})
    check(handled and reason == "heading_for_shelter",
        "an off-duty resident with a parked Base duty order gets the route instead of a job claim")
    SC.Downtime = oldDowntime
    SC.BaseLife, SC.Navigation = oldBase, oldNav
    util.gridSquare, util.loadedSquare, util.isSquareFree, util.sameSquare =
        oldGrid, oldLoaded, oldFree, oldSame
    util.nowMs = oldClock
end
SC_TEST_REPORT = "CAMP_RESIDENT_WORK_PASS checks=" .. checks
