-- SPDX-License-Identifier: MIT
-- Native completion starts pacing inside the same BaseWork update that
-- settles Downtime. A decision-layer guard cannot intercept that transition.
local SC, f, checks = SurvivorCompanion, SurvivorCompanion.TestFixture, 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'cleaning return pacing ' .. checks .. ': ' .. message)
end
SC.BaseLife.reset(); SC.BaseWork.reset()
local centre = f.makeSquare(5, 5, 0)
check(SC.BaseLife.create(centre, 'Cleaning completion pacing'), 'camp created')
local actor = f.actor('sc-cleaning-pacing', 5, 5)
f.registry[actor.id] = { id = actor.id, actor = actor, recruited = true }
check(SC.BaseLife.assign(actor.id, 'maintainer', true), 'worker assigned')
local shelf = f.makeSquare(7, 5, 0)
local container, object = f.containerObject(shelf, {})
function object:getObjectIndex() return 0 end
local okay, storage = SC.BaseLife.registerStorage(object, 'tools')
check(okay, 'tool shelf registered')
local mop = f.item('Base.Mop', 'Weapon')
local bleach = f.item('Base.Bleach', 'Normal')
function mop:getID() return 101 end
function bleach:getID() return 102 end
actor:getInventory():AddItem(mop); actor:getInventory():AddItem(bleach)
local okay, job = SC.BaseLife.enqueueJob({ type = 'clean', target = { x = 5, y = 5, z = 0 } })
check(okay, 'completed native cleaning has a live job')
job.state, job.reservedBy, job.assignedId, job.leaseUntil = 'active', actor.id, actor.id, f.clock + 60000
job.target.cleanLoans = {
    tool = { sourceStorageId = storage.id, itemId = 101 },
    liquid = { sourceStorageId = storage.id, itemId = 102 },
}
mop:getModData().LF_CleanToolJobId = job.id
bleach:getModData().LF_CleanLiquidJobId = job.id
function centre:haveStains() return false end
do
    local downtime, survey = SC.Downtime, SC.BaseWork.cleaningSuppliesAvailable
    local geometryChecks, surveys, stained, present = 0, 0, false, true
    function centre:haveStains() return stained end
    SC.Downtime = { canCleanAt = function(_, sq, staged)
        geometryChecks = geometryChecks + 1
        if not staged then surveys = surveys + 1 end
        return staged and sq == centre and present
    end }
    SC.BaseWork.cleaningSuppliesAvailable = function() surveys = surveys + 1; return true end
    local priority, loans = job.priority, job.target.cleanLoans
    job.priority = 4
    check(SC.BaseLife.priorityWorkFor(actor.id) == job and surveys == 0 and geometryChecks == 0,
        'an active cleaning loan keeps its priority without a supply survey')
    job.target.cleanLoans = nil
    check(SC.BaseLife.priorityWorkFor(actor.id) == job and surveys == 0 and geometryChecks == 0,
        'an already clean target can finish without a supply survey')
    stained = true
    check(SC.BaseLife.priorityWorkFor(actor.id) == job and surveys == 1 and geometryChecks == 1,
        'a stained target surveys carried and stored cleaning supplies only once')
    present = false
    check(SC.BaseLife.priorityWorkFor(actor.id) == nil and surveys == 1 and geometryChecks == 2,
        'an unreachable cleaning target spends no supply survey time')
    stained = false
    job.priority, job.target.cleanLoans = priority, loans
    SC.Downtime, SC.BaseWork.cleaningSuppliesAvailable = downtime, survey
end
local quiet, pauseUntil, requests, rejected = { active = { kind = 'clean_base' } }, 0, 0, 0
SC.Downtime = {
    peek = function() return quiet end,
    update = function()
        quiet.active, pauseUntil = nil, f.clock + 2400
        return true, 'cleaned'
    end,
    cancel = function() quiet.active = nil; return true end,
}
SC.NativeActions = {
    isWorkActive = function() return false end,
    pacingStatus = function() return f.clock < pauseUntil end,
    stopDirect = function() return true end,
    visualStatus = function() return 'completed' end,
    clearVisual = function() return true end,
}
SC.Navigation = {
    cancel = function() return true end,
    requestAny = function(subject, targets)
        requests = requests + 1
        if f.clock < pauseUntil then rejected = rejected + 1; return false, 'movement_rejected' end
        subject.square = SC.GameplayUtil.squareOf(targets[1])
        return true, 'moving_to_storage'
    end,
}
SC.GameplayUtil.directInteractionAccess = function(subject, target)
    return subject.square == target:getSquare(), { target:getSquare() }, 'not_at_storage'
end
SC.GameplayUtil.move = function() return true end
local handled, reason = SC.BaseWork.update(actor, nil, {})
check(handled and reason == 'cleaning_return_pending' and requests == 0,
    'same-pulse native completion waits without requesting a path: ' .. tostring(reason))
for _ = 1, 5 do
    f.clock = f.clock + 100
    handled, reason = SC.BaseWork.update(actor, nil, {})
    check(handled and requests == 0 and SC.BaseLife.job(job.id) == job,
        'pending repayment retains its live owner during the pause')
end
check(mop:getContainer() == actor:getInventory() and bleach:getContainer() == actor:getInventory()
    and mop:getModData().LF_CleanToolJobId == job.id and bleach:getModData().LF_CleanLiquidJobId == job.id,
    'both exact loans and markers survive the pause')
f.clock = pauseUntil
for _ = 1, 20 do
    f.clock = f.clock + 100
    SC.BaseWork.update(actor, nil, {})
    if not SC.BaseLife.job(job.id) then break end
end
check(requests > 0 and rejected == 0 and SC.BaseLife.job(job.id) == nil,
    'normal repayment resumes without a rejected path or blocked job')
check(mop:getContainer() == container and bleach:getContainer() == container,
    'both exact loans return after the unchanged pause')
check(mop:getModData().LF_CleanToolJobId == nil and bleach:getModData().LF_CleanLiquidJobId == nil,
    'completed repayment clears both reservations')
-- A new player order uses direct rollback. It must not be held by the
-- ordinary pause or lose the exact outstanding loan while the job is released.
check(SC.GameplayUtil.transferItemVerified(container, actor:getInventory(), mop), 'restaged exact tool')
local accepted, cancelledJob = SC.BaseLife.enqueueJob({ type = 'clean', target = { x = 5, y = 5, z = 0 } })
check(accepted, 'cancellation control queued')
cancelledJob.state, cancelledJob.reservedBy, cancelledJob.assignedId, cancelledJob.leaseUntil =
    'active', actor.id, actor.id, f.clock + 60000
cancelledJob.target.cleanLoans = { tool = { sourceStorageId = storage.id, itemId = 101 } }
mop:getModData().LF_CleanToolJobId = cancelledJob.id
pauseUntil = f.clock + 2400
check(SC.BaseWork.update(actor, nil, {}), 'paused second loan remains owned')
local cancelled, cancelReason = SC.BaseWork.cancel(actor, 'new_player_order')
check(cancelled and f.clock < pauseUntil,
    'direct cancellation settles during the pause: ' .. tostring(cancelReason))
check(mop:getContainer() == container and mop:getModData().LF_CleanToolJobId == nil,
    'direct rollback returns the original object and releases its marker')
SC_TEST_REPORT = 'CLEANING_RETURN_PACING_PASS checks=' .. checks
print(SC_TEST_REPORT)
