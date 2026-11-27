-- SPDX-License-Identifier: MIT
local F,SC=SC_HANDOVER_TEST,LivingFellows
local H=SC.Handover
local a=F.recruit('Mara');F.recruit('Ben')
a.car=F.car;F.car.passenger=a
assert(H.begin(F.primary)==false,'living player cannot switch')
assert(H.begin(a)==false,'companion death cannot replace the human')
F.primary.dead=true
assert(H.begin(F.primary) and F.speed==0,'primary death pauses selection')
local death=H.current();assert(H.begin(F.primary) and H.current()==death,'duplicate death callback is idempotent')
assert(#H.options()==2,'living recruits are listed without role filtering')
assert(H.chooseCompanion('missing')==false and F.records.Mara,'invalid choice leaves source intact')
SC.Vehicle.prepareDriverKeyReset=function() return false,'borrowed key is still settling' end
assert(H.chooseCompanion('Mara')==false and F.serial==0 and F.car.passenger==a,
    'unsettled borrowed keys block capture and leave the source passenger intact')
SC.Vehicle.prepareDriverKeyReset=function() return true end
F.saveFail=true
assert(H.chooseCompanion('Mara')==false and F.records.Mara,'failed prepare save cannot consume the companion')
assert(H.pendingReceipt()==nil,'failed prepare leaves no commit receipt')
assert(F.car.passenger==a,'a failed prepare cannot detach the original passenger')
F.saveFail=false;F.admitFail=true
local okay=pcall(H.chooseCompanion,'Mara')
assert(not okay and H.pendingReceipt().phase=='committing','native admission failure retains durable ownership')
assert(F.records.Mara==nil and H.retired('Mara'),'committed source is retired once')
local durable,removed
for i,v in ipairs(F.log) do if v=='durable:committing' then durable=i end;if v=='remove:Mara' then removed=i;break end end
assert(durable and removed and durable<removed,'durable transfer receipt precedes source removal')
F.admitFail=false;H.pulse();H.pulse()
assert(H.current().phase=='saving' and F.speed==0,'retry reaches native save while paused')
H.pulse();assert(H.current()~=nil,'queued player save is not durability proof')
F.ack=true;F.now=F.now+500;H.pulse()
assert(H.current()==nil and F.speed==1 and F.primary.id=='Mara','acknowledged successor resumes play')
assert(F.primary.cut==17 and F.primary.health==83,'takeover does not heal')
assert(F.car.passenger==F.primary and a.car==nil,'durable retirement releases the exact old occupant before stock passenger attachment')
assert(H.pendingReceipt()==nil and H.retired('Mara'),'completion removes snapshot but retains successor exclusion')
local greeting=H.greeting();assert(greeting and greeting:find('Mara',1,true),'EMMA recognizes successor')
assert(H.greeting()==nil,'Handover greeting is consumed once')
local n=#F.log;H.pulse();assert(#F.log==n,'completed Handover is not replayed')
local priorCrew=F.world.LF_HandoverV1.crew
priorCrew.stranded={id='stranded',phase='sheltered',serial=4,helpReported=true,shelterReported=true,nextReportAt=F.now+30000}
F.primary.dead=true;assert(H.begin(F.primary))
assert(priorCrew.stranded.phase=='sheltered' and not priorCrew.stranded.helpReported and priorCrew.stranded.nextReportAt==0,
    'a second death preserves dormant stranded crew and enables reports to the next operator')
F.blockTiles=true;assert(H.startNew(false)==false and H.isChoosing(),'an obstructed camp leaves the chooser and other choices available')
F.blockTiles=false
assert(H.startNew(false) and F.creator and H.current().phase=='creating','base choice opens ordinary creator')
H.cancelCreation();assert(H.current().phase=='choosing' and H.pendingReceipt()==nil,'creator cancellation consumes nobody')
F.base=nil;assert(H.startNew(false)==false,'missing camp retains alternatives')
assert(H.startNew(true),'ordinary respawn remains available without camp')
H.cancelCreation();H.reset()
local world=F.world.LF_HandoverV1
world.pending={phase='prepared',id='Ben',token='prepared'}
assert(H.reconcile() and world.pending==nil and F.records.Ben,'uncommitted prepare rolls back on load')
local snapshot=SCBridge.captureHandoverPlayer(F.records.Ben.actor)
world.pending={phase='committing',id='Ben',token='lf-handover-recovery-000000000001',snapshot=snapshot}
world.retired.Ben=world.pending.token
F.primary.dead=false;F.ack=false
assert(H.reconcile() and F.recoveries==1,'committed receipt replaces stale pre-death player row on reload')
H.pulse();assert(F.primary.id=='Ben','recovery chooses the recorded successor')
F.ack=true;F.now=F.now+500;H.pulse()
assert(H.current()==nil and world.pending==nil,'recovery completes the same transfer once')
world.schema=99
assert(H.reconcile()==false and world.schema==99,'unsupported journal is preserved')
world.schema=1
world.pending='damaged'
assert(H.reconcile()==false and world.pending=='damaged','malformed transfer receipt is preserved and blocks ordinary restore')
world.pending=nil
print('HANDOVER_HARNESS_PASS durable ordering, failures, replay, cancellation, camp fallback and identity')
