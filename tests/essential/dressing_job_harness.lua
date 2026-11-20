-- SPDX-License-Identifier: MIT
-- Camp washing must retain exact stock ownership across native replacement.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local W, U = SC.BandageWashing, SC.GameplayUtil
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'dressing job ' .. checks .. ': ' .. message)
end
check(W ~= nil, 'camp washing controller is loaded by the release group')
local actor = f.actor('wash-medic', 2, 2, {})
local other = f.actor('wash-other', 2, 2, {})
local dirty = f.item('Base.BandageDirty', 'Item', {})
local clean = f.item('Base.Bandage', 'Item', {})
function dirty:getID() return 73401 end
function clean:getID() return 73402 end
actor.inventory:AddItem(dirty)
local source = { id = 'storage:dirty', category = 'general', deposits = true,
    container = f.inventory({}), object = {} }
local medical = { id = 'storage:medical', category = 'medical', deposits = true,
    container = f.inventory({}), object = {} }
local batch = { owner = actor.id, sourceId = source.id, ids = { dirty:getID() },
    types = { 'Base.BandageDirty' }, washed = { false }, phase = 'wash', index = 1 }
local job = { id = 'job:washing', type = 'wash_dressings', target = { dressingBatch = batch },
    state = 'active', reservedBy = actor.id, assignedId = actor.id }
dirty:getModData().LF_DressingWashJob = job.id
local base = { id = 'base:washing', jobs = { job }, zones = {} }
local priorBase, priorNative = SC.BaseLife, SC.NativeActions
SC.BaseLife = {
    active = function() return base end,
    job = function(id) return id == job.id and job end,
    storage = function(id) return id == source.id and source or id == medical.id and medical end,
    resolveContainer = function(row) return row.container end,
    resolveObject = function(row) return row.object end,
    depositStorageRows = function(category) return category == 'medical' and { medical } or {} end,
    storageAcceptsDeposit = function(row, container)
        return row.deposits and row.container == container
    end,
    withdrawable = function() return true end,
    noteWorkOwnershipMutation = function() end,
}
check(W.reserved(dirty), 'the exact selected dirty stock is protected')
check(not W.ownsInput(other, dirty, job.id), 'another worker cannot claim the selected stock')
check(W.ownsInput(actor, dirty, job.id), 'the current owner can identify its dirty stock')
local claim = W.claim(actor, job)
check(claim and SC.WorkTransport.bandageWashInputAllowed(dirty, actor, claim),
    'a matching wash receipt permits only its own dirty input')
dirty:getModData().SC_PersonalOwnerId = actor.id
dirty:getModData().SC_PersonalKey = 'do-not-use'
check(not SC.WorkTransport.bandageWashInputAllowed(dirty, actor, claim),
    'personal protection still wins over the wash receipt')
dirty:getModData().SC_PersonalOwnerId, dirty:getModData().SC_PersonalKey = nil, nil
dirty:getModData().LF_QuestItem = true
check(not SC.WorkTransport.bandageWashInputAllowed(dirty, actor, claim),
    'quest protection still wins over the wash receipt')
dirty:getModData().LF_QuestItem = nil
check(not W.acceptResult(actor, job, { verified = true, input = dirty, output = clean }),
    'a result cannot precede the native attempt boundary')
check(claim.onAttempt({ item = dirty }), 'native attempt durably records possible replacement')
actor.inventory:Remove(dirty)
actor.inventory:AddItem(clean)
check(W.acceptResult(actor, job, { verified = true, input = dirty, output = clean }),
    'the exact verified native replacement migrates the receipt')
check(batch.ids[1] == clean:getID() and batch.types[1] == 'Base.Bandage'
    and batch.washed[1] == true and W.reserved(clean),
    'clean output identity and protection replace the consumed input')
check(not W.ownsInput(actor, clean, job.id), 'a verified output cannot be washed a second time')
check(not W.acceptResult(actor, job, { verified = true, input = dirty, output = clean }),
    'replayed native result cannot migrate a second time')
local impostor = f.item('Base.Bandage', 'Item', {})
function impostor:getID() return 73403 end
actor.inventory:AddItem(impostor)
check(not W.reserved(impostor), 'same-type personal cargo never acquires a camp claim')
SC.NativeActions = { cancelWork = function() return true end }
local restored = SC.BaseWork.restoreDepositToStorage
local returned = 0
SC.BaseWork.restoreDepositToStorage = function(who, row, container, item)
    returned = returned + 1
    return U.transferItemVerified(who.inventory, container, item)
end
medical.category = 'ammunition'
check(not W.cancel(actor, job), 'cancel refuses a relabeled Medical shelf')
check(actor.inventory:contains(clean) and returned == 0 and W.reserved(clean),
    'blocked cancellation keeps the exact output and its receipt')
medical.category = 'medical'
check(W.cancel(actor, job), 'cancellation settles clean output to permitted Medical storage')
check(medical.container:contains(clean) and not actor.inventory:contains(clean)
    and job.target.dressingBatch == nil and not W.reserved(clean),
    'settlement releases only the delivered output claim')
check(actor.inventory:contains(impostor), 'personal lookalike remains with its owner')
SC.BaseWork.restoreDepositToStorage = restored

-- Drive the real controller through audit, exact take, native callbacks and
-- interrupted delivery. Only the irreversible native action is simulated.
local priorNavigation, priorPrepare = SC.Navigation, SC.NativeCareActions.prepare
local priorAccess = U.directInteractionAccess
local priorTake, priorDeposit = SC.BaseWork.withdrawFromStorage, SC.BaseWork.depositToStorage
local priorReturn, priorRestore = SC.BaseWork.restoreToStorage, SC.BaseWork.restoreDepositToStorage
local priorGone = SC.BaseWork.workerUnregistered
local rows, taken, attempts, activity, validator, active, refuseStop, takeFailure, lateTake, cancelledCalls, finishedCalls
local serial, nextId, gone = 0, 74000, false
local waterSquare = f.makeSquare(2, 2, 0)
local water = { amount = 10, tainted = false }
function water:getSquare() return waterSquare end
function water:getFluidAmount() return self.amount end
function water:isTaintedWater() return self.tainted end
waterSquare.objects[#waterSquare.objects + 1] = water
local function item(kind)
    local value = f.item(kind or 'Base.BandageDirty', 'Item', {})
    nextId = nextId + 1; value.nativeId = nextId
    function value:getID() return self.nativeId end
    return value
end
local function fresh(count, saved)
    W.reset(); serial = serial + 1
    actor = f.actor('wash-case-' .. serial, 2, 2, {})
    f.registry[actor.id] = actor
    source = { id = 'dirty-' .. serial, category = 'general', withdrawals = true,
        container = f.inventory({}), object = {} }
    medical = { id = 'medical-' .. serial, category = 'medical', deposits = true,
        container = f.inventory({}), object = {} }
    rows = { source, medical }
    for _ = 1, count or 1 do source.container:AddItem(item()) end
    job = { id = 'wash-job-' .. serial, type = 'wash_dressings', target = {},
        state = 'active', reservedBy = actor.id, assignedId = nil }
    base = { id = 'wash-base-' .. serial, jobs = { job },
        zones = { { kind = 'area', x1 = 2, y1 = 2, x2 = 2, y2 = 2, z = 0 } } }
    taken, attempts, activity, validator, active, refuseStop, takeFailure, lateTake, gone =
        {}, 0, nil, nil, false, false, nil, nil, false
    water.amount, water.tainted = 10, false
    cancelledCalls, finishedCalls = 0, 0
    if saved then
        batch = { owner = actor.id, sourceId = source.id, ids = {}, types = {}, washed = {}, phase = 'wash', index = 1 }
        for index, value in ipairs(source.container.items) do
            batch.ids[index], batch.types[index], batch.washed[index] = value:getID(), value:getFullType(), false
            value:getModData().LF_DressingWashJob = job.id
        end
        while #source.container.items > 0 do
            local value = source.container.items[1]
            source.container:Remove(value); actor.inventory:AddItem(value)
        end
        job.target.dressingBatch, job.assignedId = batch, actor.id
    else batch = nil end
    return { snapshot = { threatCount = 0, closeThreatCount = 0, immediateCount = 0 } }
end
SC.BaseLife.storage = function(id)
    for _, row in ipairs(rows or {}) do if row.id == id then return row end end
end
SC.BaseLife.storageRows = function() return rows end
SC.BaseLife.withdrawable = function(row) return row.withdrawals ~= false end
SC.BaseLife.depositStorageRows = function(category)
    local found = {}; for _, row in ipairs(rows or {}) do
        if row.category == category then found[#found + 1] = row end
    end; return found
end
SC.BaseLife.availableCountExact = function(row, kind)
    local count = 0
    for _, value in ipairs(row.container.items) do if value:getFullType() == kind then count = count + 1 end end
    return math.max(0, count - (row.reserve or 0))
end
SC.BaseLife.enqueueJob = function(spec)
    spec.id, spec.state = 'audit-' .. serial, 'queued'; base.jobs[#base.jobs + 1] = spec
    return true, spec
end
SC.Navigation = {
    selectInteraction = function(_, _, _, choices) return choices[1] end,
    requestAny = function() return true, 'walking', true end,
    peek = function() return nil end,
}
U.directInteractionAccess = function() return true, { waterSquare } end
SC.NativeCareActions.prepare = function() return true end
SC.NativeActions = {
    isWorkActive = function() return active end,
    workKind = function() return activity and 'wash_bandage' end,
    ownsDowntimeAction = function(_, value) return activity ~= nil and activity == value end,
    finishWork = function() finishedCalls = finishedCalls + 1; activity = nil; return true end,
    pacingStatus = function() return false end,
    cancelWork = function()
        cancelledCalls = cancelledCalls + 1
        if refuseStop then return false end; active, activity = false, nil; return true
    end,
    startDowntimeAction = function(_, value, validate)
        attempts, activity, validator, active = attempts + 1, value, validate, true
        return true
    end,
}
SC.BaseWork.withdrawFromStorage = function(who, _, row, container, value, options)
    if lateTake then lateTake(value, options) end
    if not options or not options.validate or options.validate() ~= true then return false, 'base_supply_changed' end
    if takeFailure then return false, takeFailure end
    local done = U.transferItemVerified(container, who.inventory, value)
    if done then taken[#taken + 1] = value end
    return done, done and 'base_supply_taken' or 'take_failed'
end
SC.BaseWork.depositToStorage = function(who, _, row, container, value, options)
    if row.category ~= 'medical' or not options or options.storageCategory ~= 'medical'
        or row.deposits ~= true then return false, 'base_storage_changed' end
    local done = U.transferItemVerified(who.inventory, container, value)
    return done, done and 'base_supply_returned' or 'deposit_failed'
end
SC.BaseWork.restoreToStorage = function(who, _, container, value)
    return U.transferItemVerified(who.inventory, container, value)
end
SC.BaseWork.restoreDepositToStorage = function(who, row, container, value)
    if row.category ~= 'medical' or not row.deposits then return false, 'base_storage_changed' end
    return U.transferItemVerified(who.inventory, container, value)
end
SC.BaseWork.workerUnregistered = function() return gone end
local function completeNative()
    local act = activity
    check(act and validator() == true, 'native preflight accepts the current quiet camp')
    check(act.washJobClaim.onAttempt(act), 'the native effect records its exact pending input')
    act.nativeAttempted = true
    local output = item(SC.BandageWash.cleanType(act.item))
    actor.inventory:Remove(act.item); actor.inventory:AddItem(output)
    local wrong = item('Base.RippedSheets'); actor.inventory:AddItem(wrong)
    check(not act.washJobClaim.onResult({ verified = true, input = act.item, output = wrong }, act),
        'a different native output type cannot inherit the camp receipt')
    actor.inventory:Remove(wrong)
    check(act.washJobClaim.onResult({ verified = true, input = act.item, output = output }, act),
        'native exact output migrates the durable identity')
    act.nativeCompleted, active = true, false
    return output
end

local quiet = fresh(12)
-- All forbidden rows/items precede valid stock, rather than relying on the
-- success case to accidentally avoid them.
local memorial = { id = 'memorial', category = 'memorial', container = f.inventory({ item() }) }
local locked = { id = 'locked', category = 'medical', withdrawals = false, container = f.inventory({ item() }) }
table.insert(rows, 1, locked); table.insert(rows, 1, memorial)
local personal, loan, quest = source.container.items[1], source.container.items[2], source.container.items[3]
personal:getModData().SC_PersonalOwnerId, personal:getModData().SC_PersonalKey = actor.id, 'keepsake'
loan:getModData().LF_BorrowedDressing = 'player'
quest:getModData().LF_QuestItem = true
source.reserve = 1
local okay = W.update(actor, {}, job, quiet)
batch = job.target.dressingBatch
check(okay and #taken == 8 and batch and #batch.ids == 8 and attempts == 1,
    'one visit takes at most eight eligible dirty items from one permitted stock source')
check(source.container:contains(personal) and source.container:contains(loan) and source.container:contains(quest)
    and #memorial.container.items == 1 and #locked.container.items == 1,
    'personal, loan, quest, memorial and withdrawal-disabled stock remain untouched')
check(validator() == true, 'the shared controller starts at a reachable clean camp source')
quiet.snapshot = { threatCount = 1, closeThreatCount = 1 }
check(validator() == false, 'new close threats invalidate the native action at commit')
quiet.snapshot = { threatCount = 0, closeThreatCount = 0 }
water.tainted = true
check(validator() == false, 'tainted world water is never enabled by camp washing')
water.tainted = false
base.zones = {}
check(validator() == false, 'removing the camp area invalidates its cached world source')
base.zones = { { kind = 'area', x1 = 2, y1 = 2, x2 = 2, y2 = 2, z = 0 } }
refuseStop = true
check(not W.cancel(actor, job) and job.target.dressingBatch == batch and #actor.inventory.items == 8,
    'failed native stop retains all exact inputs and their receipt')
refuseStop = false
check(W.cancel(actor, job) and #actor.inventory.items == 0 and #source.container.items == 12,
    'cancelling before native effect returns every borrowed input without washing it')

quiet = fresh(2)
takeFailure = 'base_storage_unloaded'
local handled, why, terminal = W.update(actor, {}, job, quiet)
check(handled and why == 'base_storage_unloaded' and terminal ~= true and job.target.dressingBatch,
    'transient source unloading retains the receipt for a bounded retry')
takeFailure = nil
lateTake = function(value) value:getModData().LF_BorrowedDressing = 'new-player-loan' end
handled, why = W.update(actor, {}, job, quiet)
check(not handled and #taken == 0 and source.container:contains(source.container.items[1]),
    'protection added during the Loot pose is checked immediately before withdrawal')
lateTake = nil
check(W.cancel(actor, job), 'a rejected late withdrawal still settles exact untouched stock')

quiet = fresh(2)
takeFailure = 'base_storage_unloaded'; W.update(actor, {}, job, quiet); takeFailure = nil
batch = job.target.dressingBatch
lateTake = function() batch.ids[1] = batch.ids[2] end
check(not W.update(actor, {}, job, quiet) and #taken == 0,
    'commit validation rejects a selected row whose exact receipt ID changes during approach')

quiet = fresh(0)
for _ = 1, 4200 do source.container:AddItem(item('Base.TinCan')) end
source.container:AddItem(item())
local passes = 0
repeat
    handled, why = W.update(actor, {}, job, quiet); passes = passes + 1
until why ~= 'dressing_stock_scanning' or passes > 40
check(handled and attempts == 1 and passes > 1 and #taken == 1,
    'bounded stock scanning reaches an eligible dirty item beyond inventory index4096')

quiet = fresh(1, true)
check(W.update(actor, {}, job, quiet), 'a restored wash receipt resumes with its exact input')
local output = completeNative()
SC.NativeActions.finishWork(actor)
W.reset()
handled, why, terminal = W.update(actor, {}, job, quiet)
check(handled and why == 'dressings_washed' and terminal ~= true and medical.container:contains(output)
    and attempts == 1 and job.target.dressingBatch == nil,
    'restart after verified replacement deposits its exact output without washing again')

quiet = fresh(2, true)
batch = job.target.dressingBatch
local second = actor.inventory.items[2]
batch.ids[1], batch.types[1], batch.washed[1] = 0, '', false
actor.inventory:Remove(actor.inventory.items[1])
batch.phase, batch.washed[2], batch.types[2] = 'deposit', true, 'Base.Bandage'
second.itemType = 'Base.Bandage'
check(W.cancel(actor, job) and medical.container:contains(second) and job.target.dressingBatch == nil,
    'restart skips settled zero IDs and completes remaining clean delivery')

quiet = fresh(1, true)
batch = job.target.dressingBatch
local held = actor.inventory.items[1]
held.itemType, batch.types[1], batch.washed[1], batch.phase = 'Base.Bandage', 'Base.Bandage', true, 'deposit'
actor.inventory:Remove(held); medical.container:AddItem(held)
check(W.cancel(actor, job) and job.target.dressingBatch == nil and medical.container:contains(held),
    'a move committed before receipt clear is recovered idempotently from Medical storage')

quiet = fresh(2, true)
batch = job.target.dressingBatch
for index, value in ipairs(actor.inventory.items) do
    value.itemType, batch.types[index], batch.washed[index] = 'Base.Bandage', 'Base.Bandage', true
end
batch.phase = 'deposit'
local completedReturns, expectedFirst, expectedSecond = 0, actor.inventory.items[1], actor.inventory.items[2]
SC.BaseWork.restoreDepositToStorage = function(who, _, container, value)
    completedReturns = completedReturns + 1
    if completedReturns > 1 then return false, 'destination_full' end
    return U.transferItemVerified(who.inventory, container, value)
end
check(not W.cancel(actor, job) and batch.ids[1] == 0 and batch.phase == 'returning'
    and medical.container:contains(expectedFirst) and actor.inventory:contains(expectedSecond),
    'a partial cancellation durably records its delivered slot and pending exact remainder')
W.reset()
SC.BaseWork.restoreDepositToStorage = function(who, _, container, value)
    return U.transferItemVerified(who.inventory, container, value)
end
check(W.cancel(actor, job) and medical.container:contains(expectedSecond) and #medical.container.items == 2
    and job.target.dressingBatch == nil, 'restart completes partial return without fetching or duplicating the first item')

quiet = fresh(1, true)
batch = job.target.dressingBatch
local unchanged = actor.inventory.items[1]
batch.phase = 'deposit'
check(not W.cancel(actor, job) and actor.inventory:contains(unchanged) and #medical.container.items == 0,
    'a malformed saved deposit phase cannot deposit an unwashed input as clean output')

quiet = fresh(1, true)
batch = job.target.dressingBatch; batch.phase = 'washing'
local original = actor.inventory.items[1]
actor.inventory:Remove(original)
local lookalike = item('Base.Bandage'); actor.inventory:AddItem(lookalike)
check(not W.cancel(actor, job) and job.target.dressingBatch == batch and actor.inventory:contains(lookalike)
    and #medical.container.items == 0,
    'ambiguous restart after native attempt retains uncertainty and never adopts a lookalike')
check(not W.reconcileExpiredJob(job, actor.id), 'an ambiguous native attempt cannot release its expired lease')
f.registry[actor.id] = nil
check(not W.reconcileExpiredJob(job, actor.id), 'a dormant missing owner keeps exact cargo ownership')
gone = true
check(W.reconcileExpiredJob(job, actor.id) and job.target.dressingBatch == nil
    and actor.inventory:contains(lookalike), 'proven removed owner retires affinity without fabricating or deleting items')

quiet = fresh(1, true)
active = true
check(not W.reconcileExpiredJob(job, actor.id) and job.target.dressingBatch,
    'a live native owner prevents expired lease reassignment')
active = false
SC.Navigation.peek = function() return { goalSquare = waterSquare } end
check(not W.reconcileExpiredJob(job, actor.id), 'a live approach also prevents expired lease reassignment')
SC.Navigation.peek = function() return nil end
check(W.reconcileExpiredJob(job, actor.id) and #source.container.items == 1,
    'an idle live owner settles exact unstarted inputs before lease release')

quiet = fresh(1, true)
check(W.update(actor, {}, job, quiet), 'ownership control starts an exact native wash action')
local savedBatch, foreignActivity = job.target.dressingBatch, { kind = 'repair' }
activity, active = foreignActivity, true
handled, why = W.cancel(actor, job)
check(not handled and why == 'dressing_native_owner_busy' and cancelledCalls == 0,
    'a foreign native action cannot be cancelled by an older wash receipt')
handled, why = W.update(actor, {}, job, quiet)
check(handled and why == 'dressing_native_owner_busy' and finishedCalls == 0 and job.target.dressingBatch == savedBatch,
    'normal wash update cannot finish a foreign native owner')
W.reset(); active = false
handled, why = SC.BaseWork.cancelJob(job.id, actor.id, 'foreign-owner-control')
check(not handled and why == 'dressing_native_owner_busy' and cancelledCalls == 0 and activity == foreignActivity,
    'public cancelJob preserves inactive foreign tracked work after receipt restoration')
handled, why = W.update(actor, {}, job, quiet)
check(handled and why == 'dressing_native_owner_busy' and finishedCalls == 0,
    'restored receipt never treats workKind alone as exact ownership proof')
activity = nil
check(W.cancel(actor, job) and #source.container.items == 1,
    'saved exact receipt settles safely once the foreign owner releases its own action')

quiet = fresh(1)
base.jobs = {}
check(W.audit(base, nil, {}), 'audit queues eligible camp stock at a valid water source')
check(#base.jobs == 1 and base.jobs[1].priority == 4 and base.jobs[1].type == 'wash_dressings',
    'camp audit emits one priority-four washing job')
check(not W.audit(base, nil, {}) and #base.jobs == 1, 'queued job suppresses duplicate audits')
base.jobs[1].state = 'blocked'
check(not W.audit(base, nil, {}) and #base.jobs == 1, 'blocked recovery job also suppresses duplicate audits')
base.jobs = {}; source.withdrawals = false
check(not W.audit(base, nil, {}) and #base.jobs == 0, 'audit respects all withdrawal-disabled dirty stock')
source.withdrawals, source.reserve = true, 1
check(not W.audit(base, nil, {}) and #base.jobs == 0, 'audit respects reserved stock quantities')
source.reserve, water.tainted = 0, true
check(not W.audit(base, nil, {}) and #base.jobs == 0, 'audit leaves tainted world water for other policies')

quiet = fresh(1); base.jobs = {}
local dirtyRow = source
rows = {}
for index = 1, 200 do rows[#rows + 1] = { id = 'empty-' .. index, category = 'general', container = f.inventory({}) } end
rows[#rows + 1], rows[#rows + 2] = dirtyRow, medical
local scan = {}
handled, why, terminal = W.audit(base, nil, scan)
check(not handled and why == 'dressing_stock_scanning' and terminal == true and #base.jobs == 0,
    'hundreds of empty shelves consume audit budget instead of all being scanned in one pulse')
check(W.audit(base, nil, scan) and #base.jobs == 1,
    'the bounded empty-shelf audit resumes and eventually finds eligible stock')

SC.BaseWork.withdrawFromStorage, SC.BaseWork.depositToStorage = priorTake, priorDeposit
SC.BaseWork.restoreToStorage, SC.BaseWork.restoreDepositToStorage = priorReturn, priorRestore
SC.BaseWork.workerUnregistered = priorGone
U.directInteractionAccess, SC.Navigation, SC.NativeCareActions.prepare = priorAccess, priorNavigation, priorPrepare
SC.BaseLife, SC.NativeActions = priorBase, priorNative
print('DRESSING_JOB_PASS checks=' .. checks)
