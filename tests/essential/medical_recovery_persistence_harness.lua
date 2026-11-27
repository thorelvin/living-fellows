-- SPDX-License-Identifier: MIT
-- Clinical metadata shares the ordinary Commands/Persistence care document.
local SC=LivingFellows
local F,T=SC.TestMedicalProcedures,SC.TestFixture
local M,P,C,U=SC.Medical,SC.MedicalProcedures,SC.MedicalMaintenance,SC.GameplayUtil
local checks,serial=0,91000
local function check(value,reason)
    checks=checks+1;assert(value,'medical persistence '..checks..': '..tostring(reason))
end
local function identified(kind,options)
    local item=F.item(kind,options);serial=serial+1;item.nativeId=serial
    function item:getID() return self.nativeId end
    return item
end
local function register(actor)
    local record={id=actor.id,actor=actor,recruited=true,
        identity={forename='Medical',surname='Persistence',gender='woman',outfit='Generic01'},
        state={personality={}},runtime={}}
    T.registry[actor.id]=record
    SC.Commands.peek(actor)
    return record
end
local native,service,move,stop=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop
SC.NativeActions,SC.ActionSupervisor=nil,nil
U.move=function() return true end;U.stop=function() return true end

local infected=F.part({infectedWound=true,scratchTime=8,isBandaged=true,
    bandageType='Base.Bandage',bandageLife=10})
local fresh=identified('Base.Bandage')
local wipes=identified('Base.AlcoholWipes',{drainable=true,alcoholPower=4,uses=2})
local actor=F.actor({infected},{fresh,wipes})
local record=register(actor)
local state=SC.Commands.peek(actor)
state.care=state.care or {}
for index=1,190 do state.care['legacy'..index]=index end
check(SC.Commands.persist(actor), 'dense legacy care is accepted by ordinary command persistence')
local okay,why=M.treat(actor,actor)
check(okay and why=='wound_disinfected', 'actual disinfect procedure creates its cooldown through canonical care')
local hours=P.worldHours()
local savedTimes=P.readCare(actor,'medicalDisinfectHours')
check(type(savedTimes)=='table' and savedTimes['0']==hours,
    'cooldown is present in the canonical Commands care table')
infected.alcoholLevel=0
check(not P.disinfectReady(actor,0,0), 'spent alcohol does not bypass the retained time cooldown')
local exported=SC.Commands.export(actor)
check(exported and exported.care.legacy190==190 and exported.care.medicalDisinfectHours['0']==hours,
    'ordinary export retains dense old care plus newly written clinical cooldown')
SC.Commands.reset(actor);P.reset();C.reset()
check(SC.Commands.restore(actor,exported), 'ordinary Commands restore accepts the clinical care extension')
local restoredTimes=P.readCare(actor,'medicalDisinfectHours')
check(type(restoredTimes)=='table' and restoredTimes['0']==hours and not P.disinfectReady(actor,0,0),
    'module reset and command roundtrip do not reopen the disinfect cooldown')
check(SC.Commands.issue(actor.id,'set_group',{group='persistence-proof'},T.player),
    'an unrelated ordinary command persists after the clinical write')
check(SC.Commands.export(actor).care.legacy190==190 and P.readCare(actor,'medicalDisinfectHours')['0']==hours,
    'an unrelated command cannot overwrite either old care or cooldown metadata')

-- Commit an irreversible burn effect, then leave its exact consumption pending.
local burn=F.part({burn=8,needBurnWash=true,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
local redress,cloth=identified('Base.Bandage'),identified('Base.Bandage',{rejectUse=true})
actor.body=T.bodyDamage(100,{burn});actor.inventory=T.inventory({redress,cloth});M.invalidate(actor)
okay,why=M.treat(actor,actor)
check(okay and why=='medical_redress_pending' and burn.burnCleanCalls==1,
    'irreversible burn clean publishes a pending exact debit before retry')
local debt=M.pendingCare(actor)
check(debt and debt.committed and debt.owner==actor.id,
    'pending clinical owner is represented by the stable actor identity')
local metadata=P.readCare(actor,'medicalRecovery')
check(type(metadata)=='table', 'pending clinical proof is saved into ordinary care metadata')
check(C.save(actor)~=false, 'explicit receipt capture succeeds within the shared care budget')
exported=SC.Commands.export(actor)
check(exported and exported.care.legacy190==190 and exported.care.medicalRecovery
    and exported.care.medicalDisinfectHours['0']==hours,
    'dense old care, cooldown and full active receipt coexist in command export')
SC.Commands.persist(actor)

-- Losing native handles across a load must quarantine unknown debit, not replay
-- it. Capture a valid empty inventory to model that deliberate missing handle.
actor.inventory=T.inventory({})
local captured,reason=SC.Persistence.captureRecord(record)
check(captured~=nil, 'actual persistence capture accepts clinical metadata: '..tostring(reason))
check(captured.personality.care.legacy190==190 and captured.personality.care.medicalRecovery
    and captured.personality.care.medicalDisinfectHours['0']==hours,
    'actual save capture preserves old-budget care, cooldown and the committed receipt')
SC.Commands.reset(actor);C.reset();P.reset()
check(SC.Commands.restore(actor,captured), 'ordinary command restore reads the actual saved clinical care')
debt=M.pendingCare(actor)
check(debt and debt.committed and debt.quarantined and debt.owner==nil,
    'restored unknown debit is quarantined without retaining a phantom native owner')
check(burn.burnCleanCalls==1 and (cloth.useCalls or 0)==1,
    'loading the receipt never replays the burn operation or its uncertain consume')
check(not P.disinfectReady(actor,0,0), 'actual persistence restore also retains disinfection cooldown')

-- A new real dressing may finish care while the uncertain proof remains durable.
local replacement=identified('Base.Bandage');actor.inventory:AddItem(replacement)
M.invalidate(actor)
okay,why=M.treat(actor,actor)
check(okay and burn.isBandaged and burn.burnCleanCalls==1,
    'quarantined recovery can dress the patient without repeating the native effect')
debt=M.pendingCare(actor)
check(debt and debt.terminalQuarantine and debt.active==false,
    'completed uncertain recovery becomes forensic metadata instead of active work')
local final=SC.Commands.export(actor)
SC.Commands.reset(actor);C.reset();P.reset()
check(SC.Commands.restore(actor,final), 'completed forensic proof survives a second ordinary roundtrip')
debt=M.pendingCare(actor)
check(debt and debt.terminalQuarantine and debt.active==false and burn.burnCleanCalls==1,
    'forensic restore keeps proof without resurrecting surgery or blocking work ownership')

SC.NativeActions,SC.ActionSupervisor,U.move,U.stop=native,service,move,stop
print('MEDICAL_RECOVERY_PERSISTENCE_PASS checks='..checks)
