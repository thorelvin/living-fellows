-- SPDX-License-Identifier: MIT
-- Camp medical work must name its patient independently from its assigned medic.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local checks = 0
local function check(value, reason)
    checks = checks + 1
    assert(value, 'medical visits '..checks..': '..tostring(reason))
end
check(SC.BaseWork.reset(), 'prior base work releases before the visit scenario')
SC.BaseLife.reset()
local square = f.makeSquare(4, 4, 0)
check(SC.BaseLife.create(square, 'Medical visit contracts'), 'real camp state is created')
local base = SC.BaseLife.active()
base.settings.autoMaintenance, base.settings.routines = true, false
local wound = f.bodyPart({ isScratched = true, isBandaged = true, dirty = true })
local patient = f.actor('visit-patient', 4, 4, { body = f.bodyDamage(100, { wound }) })
local medic = f.actor('visit-medic', 5, 4, {})
f.registry[patient.id] = {id=patient.id,actor=patient,recruited=true}
f.registry[medic.id] = {id=medic.id,actor=medic,recruited=true}
patient.modData.SC_Order, medic.modData.SC_Order = 'base_duty', 'base_duty'
patient.modData.SC_Group, medic.modData.SC_Group = 'farm-squad', 'home-squad'
check(SC.BaseLife.assign(patient.id, 'generalist', true), 'patient is a resident on duty')
check(SC.BaseLife.assign(medic.id, 'medic', true), 'another resident is the camp medic')
local job
for _ = 1, 24 do
    SC.BaseWork.auditMaintenance(f.player, function() return math.huge end)
    for _, candidate in ipairs(base.jobs) do
        if candidate.type == 'replace_bandage' then job = candidate; break end
    end
    if job then break end
end
check(job ~= nil, 'the real medical maintenance audit queues dirty-wound care')
check(job.assignedId == medic.id and job.target.patientId == patient.id,
    'camp medical work assigns the medic while retaining the distinct exact patient')
local V = assert(SC.MedicalVisits, 'visiting medic controller is loaded')
check(SC.Commands.peek(patient).group ~= SC.Commands.peek(medic).group,
    'the two allied camp residents retain their distinct ordinary squad groups')
local U, M = SC.GameplayUtil, SC.Medical
local oldNeed, oldTreat, oldPeek, oldCancel, oldPending = M.campCareNeed, M.treat, M.peek, M.cancel, M.pendingCare
local oldCancelCare=M.cancelCare
local clinical, pending, active, treatmentCalls, cancelled = {}, {}, {}, {}, 0
local mode, refuseCancel = 'approach', false
local doctorRuntime, patientRuntime = U.actorState(medic), U.actorState(patient)
doctorRuntime.snapshot = { valid=true, time=f.clock, threatCount=0, closeThreatCount=0, immediateCount=0 }
patientRuntime.snapshot = { valid=true, time=f.clock, threatCount=0, closeThreatCount=0, immediateCount=0 }
local other = f.actor('visit-other-medic', 6, 4, {})
f.registry[other.id] = {id=other.id,actor=other,recruited=true}
SC.BaseLife.assign(other.id, 'medic', true)
clinical[patient] = { kind='replace_bandage', key='ForeArm_L:bandage', woundIndex=0, rank=8, visitEligible=true }
M.campCareNeed = function(who) return clinical[who] end
M.pendingCare = function(who) return pending[who] end
M.peek = function(who) return active[who] end
M.cancel = function(who)
    cancelled = cancelled + 1
    if refuseCancel then return false, 'medical_settlement_pending' end
    local value = active[who]
    if value then M.releasePatient(who, value.patient) end
    active[who] = nil
    return true, 'cancelled'
end
M.cancelCare = function(helper,subject,key,reason)
    local current=active[helper]
    if current and (current.patient~=subject or current.careKey~=key) then return false,'foreign_medical_owner' end
    return M.cancel(helper,reason)
end
M.treat = function(helper, subject, context, options)
    treatmentCalls[#treatmentCalls+1] = { helper=helper, patient=subject, options=options }
    local valid, reason = options.validateContext(helper, subject, mode=='recover' and 'recovery' or 'start')
    if not valid then return false, reason end
    check(options.campVisit==true and options.careKey==clinical[subject].key,
        'the controller pins the exact clinical need into the shared treatment API')
    if mode == 'done' then
        active[helper], clinical[subject], pending[subject] = nil, nil, nil
        M.releasePatient(helper, subject)
        return true, 'bandaged'
    end
    if not M.claimPatient(helper, subject, f.clock, options) then return false, 'patient_already_treated' end
    active[helper] = { patient=subject, phase='approaching', careKey=options.careKey,
        careKind=options.careKind, committed=false, pending=false }
    return true, 'approaching_patient'
end
local claimed = SC.BaseLife.claimJob(medic.id)
check(claimed == job, 'the assigned medic claims the existing patient job')
SC.BaseLife.touchJob(job.id, medic.id, 'active')
check(not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'an assigned job does not hold the patient before the medic owns actual care')
local handled,initialReason = V.update(medic, {}, job, doctorRuntime)
check(handled and treatmentCalls[#treatmentCalls].patient==patient and treatmentCalls[#treatmentCalls].helper==medic,
    'the medic treats the selected resident instead of treating itself: '..tostring(initialReason))
check(V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'a matching owned approach holds its patient while both remain safe')
check(not M.isReceivingCare(patient), 'visiting hold never overwrites the player-care ledger')
patientRuntime.snapshot.valid=false
check(not V.isPatientHeld(patient,patientRuntime,M.assess(patient),f.clock), 'invalid patient observation cannot authorize a visit hold')
patientRuntime.snapshot.valid=true; V.update(medic,{},job,doctorRuntime)
patientRuntime.snapshot.time=f.clock-5000
check(not V.isPatientHeld(patient,patientRuntime,M.assess(patient),f.clock), 'stale patient observation cannot authorize a visit hold')
patientRuntime.snapshot.time=f.clock; V.update(medic,{},job,doctorRuntime)
patientRuntime.snapshot.threatCount,patientRuntime.snapshot.escapeSquares=1,{square}
check(V.isPatientHeld(patient,patientRuntime,M.assess(patient),f.clock),
    'fresh distant danger with a usable escape preserves the existing semi-safe care policy')
patientRuntime.snapshot.threatCount,patientRuntime.snapshot.escapeSquares=0,nil
patientRuntime.snapshot.closeThreatCount = 1
check(not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'the patient immediately ignores a visit hold when its own close danger appears')
check(M.treatmentHolder(patient,f.clock)==nil,
    'unsafe uncommitted visit claim expires immediately without cross-actor cancellation')
patientRuntime.snapshot.closeThreatCount = 0
local urgent = { health=100, alive=true, bleedingCount=1, openWounds=1,
    wounds={ { bleeding=true, bandaged=false } } }
check(not V.isPatientHeld(patient, patientRuntime, urgent, f.clock),
    'new undressed bleeding frees the patient for urgent self-care or rescue')
patient.body.health=25; M.invalidate(patient)
check(V.update(medic,{},job,doctorRuntime) and active[medic] and active[medic].patient==patient,
    'a quiet low-health patient with covered bleeding remains eligible for visiting care')
check(V.isPatientHeld(patient,patientRuntime,M.assess(patient),f.clock),
    'quiet covered low health does not let ordinary base duty walk away from the medic')
patient.body.health=100; M.invalidate(patient)
medic.body.parts = { f.bodyPart({ isBleeding=true, isScratched=true }) }
M.invalidate(medic)
check(not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'a medic who now needs urgent self-care cannot keep another resident waiting still')
medic.body.parts = {}; M.invalidate(medic)
local savedToken = active[medic]
active[medic] = { patient=other, phase='approaching', careKey='another-patient' }
check(not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'a helper changing clinical target invalidates the old visit hold immediately')
local previousCancels=cancelled
check(V.cancel(medic,job,'foreign_care_control') and cancelled==previousCancels and active[medic].patient==other,
    'stale visit cleanup cannot cancel the helper clinical work for another patient')
active[medic] = nil
check(V.update(medic,{},job,doctorRuntime), 'a finished foreign clinical owner permits a fresh owned visit attempt')
M.noteReceivingCare(patient, f.player, f.clock)
check(V.cancel(medic, job, 'visit_cancelled'), 'owned uncommitted visit can cancel cleanly')
check(M.isReceivingCare(patient) and not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'visit cancellation releases only its scoped hold and preserves player care')
M.clearReceivingCare(patient)

-- A waiting medic must not postpone self-care forever. Exercise the sweep
-- directly so this does not depend on the twelve-family audit cursor.
SC.BaseLife.releaseJob(job.id, medic.id, 'test_release')
job.target.medicalVisit = nil
job.assignedId = medic.id
job.createdAt = f.clock
for _=1,2 do V.audit(base, function() return math.huge end, {}) end
local startingCount = #base.jobs
f.clock = f.clock + 21000
doctorRuntime.snapshot.time,patientRuntime.snapshot.time=f.clock,f.clock
V.auditOpenJobs(base, function() return math.huge end, {})
check(job.assignedId == patient.id and #base.jobs==startingCount,
    'an unclaimed busy medic lease falls back on the same patient job without duplication')
for _=1,2 do V.audit(base, function() return math.huge end, {}) end
check(#base.jobs==startingCount, 'self fallback remains a dedup anchor during later audits')
check(SC.BaseLife.claimJob(patient.id)==job, 'the original patient can claim its own fallback job')
SC.BaseLife.touchJob(job.id,patient.id,'active')
local supplied={snapshot={valid=true,time=f.clock,threatCount=0,closeThreatCount=0,immediateCount=0}}
U.clearActorState(patient)
check(V.update(patient,{},job,supplied) and treatmentCalls[#treatmentCalls].helper==patient,
    'self fallback uses its explicitly supplied runtime even without a weak-map runtime')
check(not V.isPatientHeld(patient,supplied,M.assess(patient),f.clock), 'self fallback never creates a self-hold that stalls its own procedure')
check(V.cancel(patient,job,'self_fallback_control'), 'the self fallback owner can release its own care')
SC.BaseLife.releaseJob(job.id,patient.id,'self_fallback_control')
U.actorState(patient).snapshot=patientRuntime.snapshot

-- Once clinical effects commit, a visit cannot hand its proof to a new owner.
job.assignedId, job.reservedBy, job.state = medic.id, medic.id, 'active'
job.leaseUntil = f.clock + 45000
job.target.medicalVisit = nil
V.update(medic, {}, job, doctorRuntime)
pending[patient] = { kind=clinical[patient].kind, key=clinical[patient].key,
    woundIndex=0, owner=medic.id, committed=true, pending=true }
active[medic].committed, active[medic].pending = true, true
refuseCancel = true
SC.BaseLife.resident(patient.id).duty = false
check(not V.isPatientHeld(patient, patientRuntime, M.assess(patient), f.clock),
    'leaving duty immediately releases the visit hold even while committed recovery stays owned')
local stopped = V.cancel(medic, job, 'patient_off_duty')
check(not stopped and pending[patient].owner==medic.id,
    'unverified committed recovery prevents cancellation from dropping its exact owner')
local patientRecord, priorGone = f.registry[patient.id], SC.BaseWork.workerUnregistered
f.registry[patient.id]=nil
SC.BaseWork.workerUnregistered=function() return false end
SC.BaseLife.resident(patient.id).duty=true
f.clock=f.clock+1001
doctorRuntime.snapshot.time,patientRuntime.snapshot.time=f.clock,f.clock
V.auditOpenJobs(base,function() return math.huge end,{})
check(SC.BaseLife.job(job.id)==job and job.assignedId==medic.id and pending[patient].owner==medic.id,
    'a temporarily unloaded patient retains its job and committed clinical owner by stable identity')
f.registry[patient.id], SC.BaseWork.workerUnregistered=patientRecord,priorGone
SC.BaseLife.resident(patient.id).duty=false
f.clock = f.clock + 60000
doctorRuntime.snapshot.time,patientRuntime.snapshot.time=f.clock,f.clock
V.auditOpenJobs(base, function() return math.huge end, {})
check(job.assignedId==medic.id and pending[patient].owner==medic.id,
    'expired scheduling leases cannot reassign an unsettled clinical obligation')
refuseCancel = false
pending[patient].owner = nil
check(V.cancel(medic, job, 'patient_off_duty'),
    'core-confirmed handoff lets invalid camp work release without starting more surgery')
check(pending[patient]~=nil and pending[patient].owner==nil,
    'visit cleanup preserves the shared patient redress obligation for normal medical recovery')

local washOkay, washJob = SC.BaseLife.enqueueJob({ type='wash_dressings', assignedId=medic.id,
    target={dressingBatch={owner=medic.id,ids={74001},types={'Base.Bandage'},washed={true},phase='deposit',index=1}} })
check(washOkay, 'a saved washing obligation is present for the public cancellation contract')
local oldWashCancel, washCancels = SC.BandageWashing.cancel, 0
SC.BandageWashing.cancel = function(owner, selected)
    washCancels=washCancels+1
    check(owner==medic and selected==washJob, 'public cancellation resolves the exact washing owner and receipt')
    return false,'dressing_storage_missing'
end
local removed, refusal = SC.BaseLife.cancelJob(washJob.id)
check(not removed and refusal=='dressing_storage_missing' and washCancels==1
    and SC.BaseLife.job(washJob.id)==washJob,
    'public BaseLife.cancelJob keeps a washing receipt when exact return cannot settle')
SC.BandageWashing.cancel = function() return true end
check(SC.BaseLife.cancelJob(washJob.id) and SC.BaseLife.job(washJob.id)==nil,
    'public cancellation removes the washing row only after its owner confirms settlement')
SC.BandageWashing.cancel = oldWashCancel

M.campCareNeed, M.treat, M.peek, M.cancel, M.pendingCare = oldNeed, oldTreat, oldPeek, oldCancel, oldPending
M.cancelCare=oldCancelCare
-- The role/target contract also runs through real core treatment. Only the
-- optional native visual owner is absent in this synchronous Lua fixture.
check(SC.BaseLife.cancelJob(job.id), 'prior visit row settles before actual core dispatch')
SC.BaseLife.resident(patient.id).duty=true
wound.isScratched,wound.isBandaged,wound.dirty=true,true,true
M.invalidate(patient)
local exactFresh=f.item('Base.Bandage','Medical',{})
medic.inventory:AddItem(exactFresh)
local native,service,move,stop=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop
SC.NativeActions,SC.ActionSupervisor=nil,nil
U.move=function() return true end; U.stop=function() return true end
local queued,actualJob=V.audit(base,function() return math.huge end,{})
check(queued and actualJob.assignedId==medic.id and actualJob.target.patientId==patient.id,
    'actual core need selects a medic for an allied resident from another squad')
check(SC.BaseLife.claimJob(medic.id)==actualJob, 'actual core dispatch claims its exact scheduling row')
SC.BaseLife.touchJob(actualJob.id,medic.id,'active')
local progressed,result,terminal,complete=V.update(medic,{},actualJob,doctorRuntime)
check(progressed and complete and result=='bandaged' and not wound.dirty and wound.isBandaged,
    'real Medical.treat dresses the distinct camp patient through the visiting controller')
check(not medic.inventory:contains(exactFresh) and M.peek(medic)==nil and not V.isPatientHeld(patient,patientRuntime,M.assess(patient),f.clock),
    'actual cross-resident completion consumes only the helper fresh dressing and releases clinical/hold ownership')
SC.NativeActions,SC.ActionSupervisor,U.move,U.stop=native,service,move,stop
-- An active visit owns real clinical resources while its medic approaches.
check(SC.BaseLife.completeJob(actualJob.id,medic.id,'previous_case'), 'previous visit closes')
local function goneJob(suffix)
    local part=f.bodyPart({isScratched=true,isBandaged=true,dirty=true})
    local who=f.actor('visit-death-'..suffix,8,4,{body=f.bodyDamage(100,{part})})
    f.registry[who.id]={id=who.id,actor=who,recruited=true}
    who.modData.SC_Order='base_duty'
    check(SC.BaseLife.assign(who.id,'generalist',true), 'new patient on duty')
    local accepted,row=SC.BaseLife.enqueueJob({type='replace_bandage',assignedId=medic.id,
        target={patientId=who.id,x=8,y=4,z=0}})
    check(accepted and SC.BaseLife.claimJob(medic.id)==row and SC.BaseLife.touchJob(row.id,medic.id,'active'), 'new exact visit active')
    U.actorState(who).snapshot=doctorRuntime.snapshot
    return who,row
end
local dead,liveJob=goneJob('approach')
local heldBandage=f.item('Base.Bandage','Medical',{})
medic.inventory:AddItem(heldBandage)
U.move=function() return true end; U.stop=function() return true end
local accepted,why=V.update(medic,{},liveJob,doctorRuntime)
local activeVisit=M.peek(medic)
check(accepted and activeVisit and activeVisit.patient==dead and activeVisit.supervisorToken
    and service.isCurrent(activeVisit.supervisorToken) and service.isReserved(heldBandage),
    'real visit reserves its exact dressing and supervisor during the approach: '..tostring(why))
check(M.releaseActor(dead), 'normal retirement releases clinical resources')
check(M.peek(medic)==nil and not service.isCurrent(activeVisit.supervisorToken) and not service.isReserved(heldBandage)
    and medic.inventory:contains(heldBandage) and not M.treatmentHolder(dead),
    'patient release returns the exact still-unused dressing and clears the medic supervisor and claim')
f.registry[dead.id]=nil
check(SC.BaseWork.workerUnregistered(dead.id), 'missing registry record is confirmed terminal')
local ok,r,_,finished=V.update(medic,{},liveJob,doctorRuntime)
check(ok and finished and r=='medical_visit_patient_gone' and not liveJob.target.medicalVisit.careKey
    and not liveJob.target.medicalVisit.owner, 'next update completes a pinned visit to a gone patient')
check(V.cancel(medic,liveJob) and SC.BaseWork.cancel(medic,'leave_base_duty') and SC.BaseLife.cancelJob(liveJob.id),
    'terminal uncommitted visit permits public work and job cancellation')
U.move,U.stop=move,stop

local function pinnedRecovery(suffix)
    local who,row=goneJob(suffix)
    local key=who.id..':0:remove_glass'
    local receipt={version=1,patientId=who.id,index=0,kind='remove_glass',redress=true,
        returned=false,returns={},quarantined=false,terminalQuarantine=false,
        procedure={kind='remove_glass',ownerId=medic.id,painVerified=true,debitDone=true,debitAttempted=true}}
    check(SC.MedicalProcedures.writeCare(who,'medicalRecovery',receipt),'committed procedure receipt saved')
    local obligation=assert(SC.MedicalMaintenance.pending(who))
    obligation.ownerId=medic.id
    row.target.medicalVisit={owner=medic.id,baseId=base.id,phase='recovery',careKey=key,careKind='remove_glass',woundIndex=0}
    return who,row
end
dead,liveJob=pinnedRecovery('committed')
dead.dead=true
check(SC.BaseWork.cancel(dead,'base_work_reset'), 'a confirmed native death can retire before registry removal')
check(not SC.MedicalMaintenance.pending(dead) and not liveJob.target.medicalVisit.careKey,
    'confirmed death clears only the pinned clinical obligation')
f.registry[dead.id]=nil
local _,_,_,committedFinished=V.update(medic,{},liveJob,doctorRuntime)
check(committedFinished and SC.BaseLife.cancelJob(liveJob.id), 'committed dead-patient visit ends without replay')
dead,liveJob=pinnedRecovery('lease')
f.registry[dead.id]=nil
local medicRecord=f.registry[medic.id]
f.registry[medic.id]={id=medic.id,recruited=true}
liveJob.leaseUntil=f.clock-1
check(SC.BaseLife.jobFor(medic.id)==nil and not liveJob.reservedBy and not liveJob.target.medicalVisit.careKey,
    'public lease reconciliation releases the dead patient row even while its medic is dormant')
f.registry[medic.id]=medicRecord
f.clock=f.clock+1500
for _=1,4 do V.auditOpenJobs(base,function() return math.huge end); f.clock=f.clock+1500 end
check(SC.BaseLife.job(liveJob.id)==nil, 'bounded visit audit removes the gone patient job')
-- A dead patient's other obligation still belongs to its own treatment.
dead,liveJob=pinnedRecovery('different-operation')
liveJob.target.medicalVisit.careKey=dead.id..':0:clean_burn'
liveJob.target.medicalVisit.careKind='clean_burn'
dead.dead=true
check(V.cancel(medic,liveJob) and SC.MedicalMaintenance.pending(dead)
    and SC.MedicalMaintenance.pending(dead).kind=='remove_glass', 'a different pinned care cannot discard the foreign glass receipt')
check(SC.BaseLife.cancelJob(liveJob.id), 'foreign procedure case closes its job')

for _,kind in ipairs({'take_painkillers','take_antibiotics'}) do
    local who,row=goneJob('medicine-'..kind)
    local saved={version=1,kind='take_painkillers',ownerId=medic.id,phase='effect_attempted'}
    check(SC.MedicalProcedures.writeCare(who,'medicalMedicineRecovery',saved),'medicine stores its dose receipt')
    row.target.medicalVisit={owner=medic.id,baseId=base.id,phase='recovery',careKind=kind,careKey=who.id..':whole:'..kind}
    who.dead=true
    check(V.cancel(medic,row),'gone visit releases its medicine pin')
    local after=SC.MedicalProcedures.readCare(who,'medicalMedicineRecovery')
    if kind=='take_painkillers' then
        check(after==nil,'exact dead-patient medicine debt retires without redosing')
    else
        check(after and after.kind=='take_painkillers','a foreign medicine receipt remains with its original treatment')
    end
    check(SC.BaseLife.cancelJob(row.id),'medicine visit cancellation succeeds')
end

dead,liveJob=pinnedRecovery('abandon')
f.registry[dead.id]=nil
check(SC.BaseLife.abandon() and not SC.BaseLife.active(), 'camp abandon succeeds directly on a pinned dead-patient visit')
SC_TEST_REPORT='MEDICAL_VISITS_PASS checks='..checks
