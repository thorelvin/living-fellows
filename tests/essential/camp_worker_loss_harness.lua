-- SPDX-License-Identifier: MIT
-- A restored queue may contain both live and permanently retired owners.
local SC = LivingFellows
local B = SC.BaseLife
local dead, away = "sc-worker-gone", "sc-worker-away"
local restoring, pending, lookups = false, false, 0
SC.Registry.byId = function(id)
    lookups = lookups + 1
    if id == away then return {dormant = true} end
end
SC.Persistence = {restoreStatus = function() return not restoring end,
    isPending = function(id) return pending and id == dead end}
local function camp()
    B.reset()
    local ok, base = B.create({x=2, y=3, z=0}, "Worker recovery")
    assert(ok)
    return base
end
local function enqueue(kind, id, orderId)
    local ok, job = B.enqueueJob({type=kind, assignedId=id,
        target={orderId=orderId, x=2, y=3, z=0}})
    assert(ok)
    return job
end

for _, kind in ipairs({"production","gather_materials"}) do
    for _, count in ipairs({1,2}) do
        local base = camp()
        local ledger = kind == "production" and base.production or base.work
        local order = {id="test-order", workers={dead}, state="running", completed=1, delivered=1,
            requested=3, operation="dig_graves", material="logs"}
        ledger.orders[1] = order
        local first = enqueue(kind, dead, order.id)
        local second
        if count == 2 then
            order.workers[2] = away
            second = enqueue(kind, away, order.id)
            order.state, order.blocker = "blocked", "destination_storage_unloaded"
        end
        restoring = true
        B.auditJobRecovery()
        assert(B.job(first.id) == first and #order.workers == count, "restoring workers retain orders")
        restoring, pending = false, true
        B.auditJobRecovery()
        assert(B.job(first.id) == first, "pending restoration retains the worker row")
        pending = false
        for i = 1, count do B.auditJobRecovery() end
        assert(B.job(first.id) == nil and first.state == "cancelled" and #order.workers == count-1,
            "a retired worker releases the order assignment")
        assert(order.completed == 1 and order.delivered == 1, "no native output is credited on retirement")
        if second then
            assert(order.state == "blocked" and order.blocker == "destination_storage_unloaded"
                and B.job(second.id) == second and order.workers[1] == away,
                "retiring one worker preserves a live co-worker and the order's independent blocker")
        else
            assert(order.state == "cancelled", "a single-worker order releases its camp slot")
        end
    end
end

local base = camp()
for i = 1, 12 do enqueue("farm", away) end
local plot = enqueue("farm", nil)
plot.state, plot.reservedBy, plot.leaseUntil = "active", dead, 0
local assigned = enqueue("farm", dead)
lookups = 0
B.auditJobRecovery()
assert(lookups <= 1, "an ordinary maintenance pulse checks at most one job owner")
for i = 1, #base.jobs * 2 do B.auditJobRecovery() end
assert(B.job(plot.id) == nil and B.job(assigned.id) == nil and #base.jobs == 12,
    "active and queued farm jobs release their retired owner while dormant farmers keep all assignments")
local receipt = {id="farm-receipt:23", jobId=plot.id, actorId=dead, kind="output", phase="recovery"}
base.farm.receipts[1] = receipt
local item = {data={LF_FarmReceiptId=receipt.id}}
function item:getModData() return self.data end
restoring = true
for _, t in ipairs({0,130000,260000}) do SC.FarmWork._settleLostCarrierForTests(receipt,t) end
assert(receipt.phase == "recovery", "restore delays past the grace period preserve physical farm claims")
restoring = false
SC.FarmWork._settleLostCarrierForTests(receipt,300000)
assert(SC.WorkTransport.isCargoProtected(item, nil, "loadout"), "the carrier grace period protects the exact item")
SC.FarmWork._settleLostCarrierForTests(receipt,430000)
assert(receipt.phase == "consumed" and not SC.WorkTransport.isCargoProtected(item,nil,"loadout")
    and item.data.LF_FarmReceiptId == nil, "an observed farm item loses its settled claim in place")
-- Normal farm maintenance sees both cold actors and re-openable source-only
-- watering plans before BaseLife's rotating retirement check runs.
base = camp()
local cold = enqueue("farm", away)
cold.target.operation, cold.state = "water", "blocked"
local waiting = enqueue("farm", dead)
waiting.target.operation = "water"
pending = true
SC.FarmWork.audit(base)
assert(cold.assignedId == away and waiting.assignedId == dead,
    "the farm scan keeps water affinity for a dormant and a pending-restore farmer")
pending, restoring = false, true
SC.FarmWork.audit(base)
assert(waiting.assignedId == dead, "an unfinished save restore keeps a named watering plan")
restoring = false
local _, loan = B.allocateFarmReceipt({jobId=waiting.id, actorId=dead, kind="output",
    itemType="Base.Tomato", phase="recovery", nativeId=20})
SC.FarmWork.audit(base)
assert(waiting.assignedId == dead, "a dead farmer's exact receipt stays attached until retirement")
local sourceOnly = enqueue("farm", dead)
sourceOnly.target.operation = "water"
SC.FarmWork.audit(base)
assert(sourceOnly.assignedId == nil, "source-only watering is available to another farmer")

-- Legacy IDs round-trip unchanged. A later camp starts its own local serial
-- at one, but may never claim an earlier camp's bucket or delivered log.
base = camp()
local oldJob = enqueue("farm", dead)
local function supply(job)
    local ok, receipt = B.allocateFarmReceipt({jobId=job.id, actorId=dead,
        kind="output", itemType="Base.Tomato", phase="carried", nativeId=20})
    assert(ok)
    return receipt
end
local oldReceipt = supply(oldJob)
local oldId, oldJobId = oldReceipt.id, oldJob.id
oldReceipt.id = "farm-receipt:1"
assert(B.restore(B.export()) and B.farmReceipt("farm-receipt:1"), "legacy active farm receipts survive restore")
local legacyFarm = B.farmReceipt("farm-receipt:1")
local candidate = {data={LF_FarmReceiptId=legacyFarm.id}, getModData=item.getModData,
    getFullType=function() return "Base.Bucket" end, getID=function() return 21 end}
assert(not SC.FarmWork.isItemProtected(candidate) and not candidate.data.LF_FarmReceiptId,
    "a different native type cannot inherit a live legacy farm receipt")
candidate.getFullType = function() return "Base.Tomato" end
candidate.data.LF_FarmReceiptId = legacyFarm.id
assert(SC.FarmWork.isItemProtected(candidate),"ordinary farm cargo keeps its receipt across a rebuilt native ID")
legacyFarm.milk = {fluid="CowMilk"}
assert(not SC.FarmWork.isItemProtected(candidate) and not candidate.data.LF_FarmReceiptId,
    "a preserved native ID distinguishes another animal-loan item with the same legacy token")
candidate.getID = function() return 20 end
candidate.data.LF_FarmReceiptId = legacyFarm.id
assert(SC.FarmWork.isItemProtected(candidate),"the exact original native farm loan retains protection")
legacyFarm.milk = nil
B.updateFarmReceipt("farm-receipt:1", {phase="consumed"})
assert(B.abandon())
local created, nextBase = B.create({x=8,y=9,z=0},"Next camp")
assert(created)
local newJob = enqueue("farm", away)
local nextReceipt = supply(newJob)
assert(nextReceipt.id ~= oldId and newJob.id ~= oldJobId and nextReceipt.id ~= "farm-receipt:1",
    "a replacement camp never reserves discarded native cargo with a recycled receipt")
local stale = {data={LF_FarmReceiptId=oldId}, getModData=item.getModData}
local live = {data={LF_FarmReceiptId=nextReceipt.id}, getModData=item.getModData}
assert(not SC.WorkTransport.isCargoProtected(stale,nil,"loadout") and not stale.data.LF_FarmReceiptId
    and SC.WorkTransport.isCargoProtected(live,nil,"loadout") and live.data.LF_FarmReceiptId==nextReceipt.id,
    "only the replacement camp's marked physical item remains reserved")
local function gathering(base)
    local order = {id="work-order:1",workers={dead},state="running",material="logs",
        itemType="Base.Log",delivered=0,requested=1,destinationStorageId="storage:1"}
    base.work.orders[1] = order
    local job = enqueue("gather_materials",dead,order.id)
    local ok, receipt = B.allocateWorkReceipt({orderId=order.id, jobId=job.id, actorId=dead,
        source={x=0,y=0,z=0},nativeId=22,snapshot={}})
    assert(ok)
    return order, receipt
end
base = camp()
local firstOrder, original = gathering(base)
original.phase, original.owner, original.accounted = "cancelled","retired",true
assert(B.abandon())
local founded, successor = B.create({x=1,y=2,z=0},"New log depot")
assert(founded)
local order, cargo = gathering(successor)
assert(cargo.id ~= original.id,"an old camp's native log cannot inherit the new depot's receipt")
local fixture = SC.TestFixture
local store, previousRows, previousResolve = {id="storage:1"}, B.storageRows, B.resolveContainer
local wrong, exact = fixture.item("Base.Log"), fixture.item("Base.Log")
function wrong:getID() return 11 end
function exact:getID() return 22 end
local destination = fixture.inventory({wrong})
B.storageRows = function() return {store} end
B.resolveContainer = function() return destination end
cargo.id, cargo.phase, cargo.owner = "work-receipt:1", "quarantined", "retired"
wrong:getModData().LF_WorkReceiptId, exact:getModData().LF_WorkReceiptId = cargo.id,cargo.id
assert(not SC.WorkTransport.retryOrder(order.id) and order.delivered==0,
    "manual retry refuses a prior camp's wrong native log carrying a reused legacy receipt")
destination:AddItem(exact)
assert(SC.WorkTransport.retryOrder(order.id) and order.delivered==1 and cargo.phase=="delivered"
    and wrong:getModData().LF_WorkReceiptId==cargo.id and exact:getModData().LF_WorkReceiptId==nil,
    "manual retry passes the first wrong log and settles only the exact native legacy delivery")
B.storageRows, B.resolveContainer = previousRows, previousResolve
print("CAMP_WORKER_LOSS_PASS")
