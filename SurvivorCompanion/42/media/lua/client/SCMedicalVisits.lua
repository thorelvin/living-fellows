-- SPDX-License-Identifier: MIT
-- Scheduling and scoped patient holds for camp care. Medical owns every effect.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.MedicalVisits = SC.MedicalVisits or {}
local V = SC.MedicalVisits
local holds = setmetatable({}, { __mode = 'k' })
local runtimes = setmetatable({}, { __mode = 'k' })
local visitOwners = setmetatable({}, { __mode = 'k' })
local leaseScans = setmetatable({}, { __mode = 'k' })
local function U() return SC.GameplayUtil end
local function M() return SC.Medical end
local function now() return U().nowMs() end
local function closed(job) return job.state == 'completed' or job.state == 'cancelled' end
function V.isJob(job)
    return type(job)=='table' and job.type=='replace_bandage' and type(job.target)=='table'
        and type(job.target.patientId)=='string'
end
function V.patientId(job)
    if not job or job.type~='replace_bandage' then return nil end
    return V.isJob(job) and job.target.patientId or job.assignedId
end
local function meta(job)
    return V.isJob(job) and type(job.target.medicalVisit)=='table' and job.target.medicalVisit or nil
end
local function resolve(id) return id and U().resolveActor(id) or nil end
local function pending(patient)
    local value=patient and M().pendingCare and M().pendingCare(patient) or nil
    return value and not value.terminalQuarantine and value.active~=false and value or nil
end
local function changed()
    if SC.BaseLife.noteWorkOwnershipMutation then SC.BaseLife.noteWorkOwnershipMutation() end
end
local function waitingMs()
    return math.max(2000, math.min(60000, tonumber(U().config('medicalCampVisitWaitMs')) or 20000))
end
local function initialize(job, base)
    if not meta(job) then
        job.target.medicalVisit = { baseId=base.id, medicId=job.assignedId,
            waitUntil=(tonumber(job.createdAt) or now())+waitingMs(), phase='waiting' }
        changed()
    end
    return meta(job)
end
local function residentValid(actor, base)
    if not actor or not U().isValidActor(actor) or U().isDead(actor) then return false end
    local resident = SC.BaseLife.resident(U().idOf(actor))
    local commands = SC.Commands and SC.Commands.peek(actor)
    return resident and resident.baseId==base.id and resident.duty==true
        and commands and commands.recruited==true and SC.BaseLife.isInside(actor)==true
end
local function allies(helper, patient)
    return helper==patient or (not SC.Factions or not SC.Factions.areAlliesBetween
        or SC.Factions.areAlliesBetween(helper, patient)==true)
end
local function urgent(assessment)
    if not assessment or assessment.alive==false then return true end
    for _, wound in ipairs(assessment.wounds or {}) do
        if wound.bleeding==true and wound.bandaged~=true then return true end
    end
    return false
end
local function snapshot(context)
    return type(context)=='table' and (context.senses and context.senses.current or context.snapshot) or nil
end
local function safe(actor, context)
    local observed = snapshot(context)
    return type(observed)=='table' and type(M().isCareSnapshotSafe)=='function'
        and M().isCareSnapshotSafe(actor, observed)==true
end
local function undressedBleeding(assessment)
    for _, wound in ipairs(assessment and assessment.wounds or {}) do
        if wound.bleeding and not wound.bandaged then return true end
    end
    return false
end
local function ownedPeek(helper, patient, entry)
    local active = helper and M().peek(helper)
    return active and active.patient==patient and entry.careKey~=nil
        and active.careKey==entry.careKey and active or nil
end
local function releaseHold(patient, job)
    local held = patient and holds[patient]
    if held and held.job==job then holds[patient]=nil end
end
local function current(job, helper)
    return V.isJob(job) and SC.BaseLife.job(job.id)==job and not closed(job)
        and job.reservedBy==U().idOf(helper) and (job.state=='active' or job.state=='reserved')
end
local function contextValid(job, helper, patient, helperRuntime, stage)
    local entry, base = meta(job), SC.BaseLife.active()
    if not entry or not base or entry.baseId~=base.id or SC.BaseLife.job(job.id)~=job
        or closed(job) or job.target.patientId~=U().idOf(patient)
        or entry.owner~=U().idOf(helper) then return false, 'medical_visit_owner_changed' end
    if not allies(helper, patient) or not M().sameCareGroup(helper, patient) then
        return false, 'medical_visit_not_allied'
    end
    -- Only the original pinned committed obligation may finish outside the
    -- old camp schedule. Core still enforces contact, life and exact supplies.
    local debt = pending(patient)
    if debt and entry.owner~=nil and debt.owner==entry.owner and entry.careKey==nil then
        return false, 'medical_visit_owner_busy'
    end
    local recovery = stage=='recovery' and debt and debt.committed==true
        and (debt.owner==nil or debt.owner==U().idOf(helper)) and debt.key==entry.careKey
    if not recovery then
        if not current(job, helper) then return false, 'medical_visit_owner_changed' end
        if not residentValid(patient, base) then return false, 'medical_visit_patient_left' end
        if not residentValid(helper, base) then return false, 'medical_visit_medic_left' end
        local x,y,z = U().position(patient)
        local policy = {type=job.type,target={x=x,y=y,z=z}}
        if not SC.BaseLife.workPermitted(U().idOf(helper), policy) then return false, 'infection_restriction' end
    end
    local patientRuntime = helper==patient and helperRuntime or U().peekActorState(patient)
    if not safe(helper, helperRuntime) or not safe(patient, patientRuntime) then return false, 'danger_preempted' end
    local inspect = stage=='claim' and M().assess or M().assessCached
    if not recovery and (undressedBleeding(inspect(patient,nil,100))
        or undressedBleeding(inspect(helper,nil,100))) then return false,'medical_visit_urgent_bleeding' end
    if M().isReceivingCare(patient) then return false, 'medical_visit_player_care' end
    return true
end
function V.isClaimValid(helper, patient, careKey)
    local job = visitOwners[helper]
    local entry = meta(job)
    if entry and job.target.patientId==U().idOf(patient) and entry.owner==U().idOf(helper)
        and entry.careKey==careKey then
        local state = runtimes[job]
        return contextValid(job, helper, patient, state and state.runtime or U().peekActorState(helper), 'claim')
    end
    return false
end
function V.isPatientHeld(patient, patientRuntime, assessment, currentTime)
    local held = holds[patient]
    if not held or (tonumber(currentTime) or now())>held.untilAt then return false end
    local job, helper = held.job, held.helper
    if helper==patient then return false end
    local entry = meta(job)
    if not entry or held.key~=entry.careKey or not current(job, helper)
        or not ownedPeek(helper, patient, entry) then return false end
    if M().treatmentHolder(patient, currentTime)~=helper then return false end
    if not safe(patient, patientRuntime) or urgent(assessment or M().assessCached(patient,nil,100))
        or urgent(M().assessCached(helper,nil,100)) then return false end
    local state = runtimes[job]
    return contextValid(job, helper, patient, state and state.runtime or U().peekActorState(helper), 'hold')==true
end
local function clearPin(job)
    local entry = meta(job)
    if entry then entry.careKind, entry.careKey, entry.woundIndex = nil,nil,nil end
end
local function patientGone(job, patient)
    -- Retirement runs BaseWork.reset before unregistering a native death.
    -- For a missing actor the registry and restore queue decide finality.
    if patient then return U().isDead(patient) end
    return SC.BaseWork.workerUnregistered(job.target.patientId)
end
local function retireVisit(helper, job, patient)
    local entry, state = meta(job), runtimes[job]
    if not entry then return true end
    helper = helper or (state and state.helper)
    patient = patient or (state and state.patient)
    if patient and ownedPeek(helper, patient, entry) then
        local okay, why = M().cancelCare(helper, patient, entry.careKey, 'medical_visit_patient_gone', true)
        if okay ~= true then return false, why end
    end
    if patient then
        releaseHold(patient, job)
        if helper and not M().peek(helper) then M().releasePatient(helper, patient) end
    end
    if entry.careKey then
        local clinical = SC.MedicalMedicines.handles(entry.careKind) and SC.MedicalMedicines or SC.MedicalMaintenance
        clinical.retireVisit(job.target.patientId, entry.careKey, patient)
    end
    clearPin(job)
    entry.owner, entry.phase = nil, 'finished'
    if helper and visitOwners[helper]==job then visitOwners[helper]=nil end
    runtimes[job]=nil
    changed()
    return true
end
function V.cancel(helper, job, reason)
    if not V.isJob(job) then return true end
    local entry = meta(job)
    helper = helper or resolve(entry and entry.owner or job.reservedBy or job.assignedId)
    local patient = resolve(job.target.patientId)
    if patientGone(job, patient) then return retireVisit(helper, job, patient) end
    if not patient and helper then
        local tracked=M().peek(helper)
        if tracked and U().idOf(tracked.patient)==job.target.patientId then patient=tracked.patient end
    end
    releaseHold(patient, job)
    if not entry then return true end
    if not patient and entry.careKey~=nil then return false,'medical_visit_patient_missing' end
    local active = helper and M().peek(helper)
    local debt = pending(patient)
    if debt and entry.owner~=nil and debt.owner==entry.owner and entry.careKey==nil then
        return false, 'medical_visit_owner_busy'
    end
    local ownsDebt = helper and debt and debt.owner~=nil and debt.owner==U().idOf(helper) and debt.key==entry.careKey
    if active and not ownedPeek(helper, patient, entry) then
        if ownsDebt then return false, 'medical_visit_owner_busy' end
    elseif active or ownsDebt then
        local okay, why
        if M().cancelCare then okay,why=M().cancelCare(helper, patient, entry.careKey, reason or 'medical_visit_cancelled')
        else okay,why=M().cancel(helper, reason or 'medical_visit_cancelled') end
        if okay~=true then entry.phase='recovery'; changed(); return false,why end
    end
    debt = pending(patient)
    if debt and entry.owner~=nil and debt.owner==entry.owner and debt.key==entry.careKey then
        entry.phase='recovery'; changed(); return false, 'medical_visit_recovery_pending'
    end
    if helper and (not M().peek(helper) or ownedPeek(helper, patient, entry)) then
        M().releasePatient(helper, patient)
    end
    entry.owner, entry.phase = nil,debt and debt.key==entry.careKey and 'recovery' or 'waiting'
    if helper and visitOwners[helper]==job then visitOwners[helper]=nil end
    if not debt or debt.key~=entry.careKey then clearPin(job) end
    runtimes[job]=nil; changed()
    return true
end
function V.cancelActor(actor, reason)
    local base, id = SC.BaseLife.active(), U().idOf(actor)
    for _, job in ipairs(base and base.jobs or {}) do
        local entry = meta(job)
        if entry and (entry.owner==id or job.target.patientId==id) then
            local okay,why=V.cancel(resolve(entry.owner),job,reason)
            if okay~=true then return false,why end
        end
    end
    return true
end
-- The missing medic has already left the registry. A living, unloaded
-- patient's pinned recovery survives this scheduler handoff.
function V.releaseGoneMedic(job, id)
    local entry = meta(job)
    if entry and entry.owner and entry.owner ~= id then return false, 'medical_visit_owner_busy' end
    local state = runtimes[job]
    local helper, patient = state and state.helper, state and state.patient
    if entry and helper and patient and ownedPeek(helper, patient, entry) then
        local okay, why = M().cancelCare(helper, patient, entry.careKey, 'medical_visit_medic_left')
        if okay ~= true then return false, why end
    end
    releaseHold(patient, job)
    if helper and patient and not M().peek(helper) then M().releasePatient(helper, patient) end
    if helper and visitOwners[helper]==job then visitOwners[helper]=nil end
    runtimes[job]=nil
    if entry then entry.owner,entry.medicId,entry.phase,entry.selfFallback=nil,nil,'waiting',true end
    job.assignedId,job.reservedBy,job.state,job.leaseUntil=job.target.patientId,nil,'pending',0
    job.retryAt,job.blocker=0,nil
    changed()
    return true
end
function V.update(helper, _, job, helperRuntime)
    local base = SC.BaseLife.active()
    if not base or not current(job, helper) then return false,'medical_visit_owner_changed',true end
    local entry = initialize(job, base)
    local patient = resolve(job.target.patientId)
    if patientGone(job, patient) then
        local okay, why = retireVisit(helper, job, patient)
        return true, why or 'medical_visit_patient_gone', false, okay==true
    end
    if not patient then return true,'medical_visit_patient_missing' end
    if entry.owner and entry.owner~=U().idOf(helper) then
        local previous=resolve(entry.owner)
        local debt=pending(patient)
        if debt and debt.owner==entry.owner or previous and ownedPeek(previous,patient,entry) then
            return true,'medical_visit_owner_busy'
        end
        local stopped,why=V.cancel(previous,job,'medical_visit_owner_changed')
        if not stopped then return true,why end
    end
    entry.owner = U().idOf(helper)
    local state = runtimes[job] or {}; runtimes[job]=state
    state.runtime, state.helper, state.patient = helperRuntime, helper, patient
    local debt = pending(patient)
    local active = M().peek(helper)
    if active and not ownedPeek(helper,patient,entry) then return true,'medical_visit_owner_busy' end
    if debt and entry.careKey==nil then return true,'medical_visit_owner_busy' end
    visitOwners[helper] = job
    local need = M().campCareNeed(patient)
    if need and need.pending and not debt then need=nil end
    if not need and not active and not debt then
        V.cancel(helper,job,'medical_visit_resolved')
        return true,'medical_visit_resolved',false,true
    end
    local valid, why = contextValid(job,helper,patient,helperRuntime,debt and debt.committed and 'recovery' or 'start')
    if not valid then
        local stopped,stopWhy=V.cancel(helper,job,why)
        if stopped~=true then return true,stopWhy end
        return true,why,false,true
    end
    if not active and not debt then
        if not need or need.visitEligible~=true then return true,'medical_visit_resolved',false,true end
        entry.careKind,entry.careKey,entry.woundIndex = need.kind,need.key,need.woundIndex
    end
    local okay,result = M().treat(helper,patient,helperRuntime,{
        campVisit=true,careKind=entry.careKind,careKey=entry.careKey,woundIndex=entry.woundIndex,
        validateContext=function(h,p,stage) return contextValid(job,h,p,helperRuntime,stage) end,
    })
    active = ownedPeek(helper,patient,entry)
    if active then
        entry.phase='treating'
        if helper~=patient then holds[patient]={job=job,helper=helper,key=entry.careKey,untilAt=now()+6000} end
    else releaseHold(patient,job) end
    if pending(patient) then entry.phase='recovery' end
    changed()
    if result=='medical_need_changed' or result=='wound_no_longer_treatable' then
        if not active and not pending(patient) then clearPin(job); return true,result end
    end
    if okay and not active and not pending(patient) then
        if not M().campCareNeed(patient) then
            V.cancel(helper,job,'medical_visit_resolved')
            return true,result,false,true
        end
        clearPin(job)
    end
    if active or pending(patient) then return true,result end
    return okay==true,result,okay~=true
end
local function openFor(base, id)
    for _, job in ipairs(base.jobs or {}) do
        if not closed(job) and V.patientId(job)==id then return job end
    end
end
local function medicFor(base, patient)
    local available, busy
    for _, id in ipairs(SC.BaseLife.dutyResidentIds()) do
        local actor, resident = resolve(id),SC.BaseLife.resident(id)
        if actor~=patient and resident and resident.role=='medic' and residentValid(actor,base)
            and allies(actor,patient) and M().sameCareGroup(actor,patient) then
            if not SC.BaseLife.jobFor(id) and not M().peek(actor) then available=available or actor
            else busy=busy or actor end
        end
    end
    return available or busy
end
function V.audit(base, budget, scan)
    scan.visitRows = scan.visitRows or SC.BaseLife.dutyResidentIds()
    scan.visitIndex = scan.visitIndex or 1
    while scan.visitIndex<=#scan.visitRows do
        if type(budget)=='function' and (tonumber(budget()) or 0)<=0 then return false,'medical_audit_pending',true end
        local id=scan.visitRows[scan.visitIndex]; scan.visitIndex=scan.visitIndex+1
        local patient=resolve(id)
        if residentValid(patient,base) and not openFor(base,id) then
            local need=M().campCareNeed(patient)
            if need and need.visitEligible==true and not need.pending then
                local medic=medicFor(base,patient)
                local x,y,z=U().position(patient)
                return SC.BaseLife.enqueueJob({type='replace_bandage',priority=5,
                    assignedId=U().idOf(medic or patient),target={patientId=id,x=x,y=y,z=z,
                    medicalVisit={baseId=base.id,medicId=medic and U().idOf(medic) or nil,
                        waitUntil=now()+waitingMs(),phase='waiting',selfFallback=medic==nil}}})
            end
        end
    end
    return false,'no_medical_base_job'
end
function V.auditOpenJobs(base, budget, scan)
    scan = leaseScans[base] or {visitJobIndex=1,nextAt=0}
    leaseScans[base] = scan
    if now()<scan.nextAt then return false end
    scan.nextAt = now()+1000
    scan.visitJobIndex = scan.visitJobIndex or 1
    local processed=0
    while scan.visitJobIndex<=#(base.jobs or {}) and processed<16 do
        if type(budget)=='function' and (tonumber(budget()) or 0)<=0 then return false end
        local job=base.jobs[scan.visitJobIndex]; scan.visitJobIndex=scan.visitJobIndex+1; processed=processed+1
        if V.isJob(job) and not closed(job) then
            local entry=initialize(job,base)
            local patient=resolve(job.target.patientId)
            local helper=resolve(entry.owner or job.reservedBy or job.assignedId)
            local debt=pending(patient)
            local resident=SC.BaseLife.resident(job.target.patientId)
            local missing=not patient and not SC.BaseWork.workerUnregistered(job.target.patientId)
                and resident and resident.baseId==base.id and resident.duty==true
            if missing then
                -- Streaming absence is not departure and cannot erase proof.
            elseif not residentValid(patient,base) then
                local okay=V.cancel(helper,job,'medical_visit_patient_left')
                if okay then SC.BaseLife.cancelJob(job.id); scan.visitJobIndex=scan.visitJobIndex-1 end
                return true,'medical_visit_patient_left'
            elseif entry.owner and not residentValid(helper,base) then
                local okay=V.cancel(helper,job,'medical_visit_medic_left')
                if okay then
                    job.assignedId,job.reservedBy,job.state,job.leaseUntil=job.target.patientId,nil,'pending',0
                    job.retryAt,job.blocker,entry.selfFallback=0,nil,true; changed()
                end
                return true,'medical_visit_medic_left'
            elseif entry.selfFallback~=true and now()>=(tonumber(entry.waitUntil) or 0)
                and not (debt and debt.owner~=nil) then
                local active=helper and M().peek(helper)
                if not active or not ownedPeek(helper,patient,entry) then
                    local okay=V.cancel(helper,job,'medical_visit_self_fallback')
                    if okay then
                        job.assignedId,job.reservedBy,job.state,job.leaseUntil=job.target.patientId,nil,'pending',0
                        job.retryAt,job.blocker=0,nil
                        entry.selfFallback,entry.phase=true,'waiting'; changed()
                        return true,'medical_visit_self_fallback'
                    end
                end
            end
        end
    end
    if scan.visitJobIndex>#(base.jobs or {}) then scan.visitJobIndex=1; return false end
    return false
end
function V.reconcileExpiredJob(job, ownerId)
    local entry=meta(job)
    if not entry then return true end
    local helper=resolve(entry.owner or ownerId)
    local patient=resolve(job.target.patientId)
    if patientGone(job, patient) then return retireVisit(helper, job, patient) end
    local debt=pending(patient)
    if not helper and not SC.BaseWork.workerUnregistered(entry.owner or ownerId) then
        return false,'expired_medical_visit_owner_missing'
    end
    if debt and debt.owner~=nil then return false,'medical_visit_recovery_pending' end
    return V.cancel(helper,job,'medical_visit_lease_expired')
end
function V.reset()
    holds=setmetatable({},{__mode='k'}); runtimes=setmetatable({},{__mode='k'})
    visitOwners=setmetatable({},{__mode='k'})
    leaseScans=setmetatable({},{__mode='k'})
end
return V
