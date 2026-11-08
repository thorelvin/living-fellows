-- SPDX-License-Identifier: MIT
-- Real job persistence and supervisor ownership; only native PC/radio surfaces
-- are substituted, using the shared gameplay fixture and its actual actor.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local R,B,S,U = SC.RadioWork,SC.BaseLife,SC.ActionSupervisor,SC.GameplayUtil
local check = f.check
local oldTime=getGameTime
getGameTime=function()
    local time=oldTime();time.getWorldAgeHours=function() return f.worldHour end;return time
end
local actor=f.actor("radio-operator",3,1,{})
f.registry[actor.id]={id=actor.id,actor=actor,recruited=true}
actor.modData.SC_Order="base_duty"
B.create(actor.square,"Radio camp");B.assign(actor.id,"generalist",true)
actor.square.outside=false
local _,pc=f.containerObject(f.makeSquare(4,1,0),{}, {containerType="desk"})
pc.modData.movableData={system={identity="radio-test-pc",locked=false}}
function pc:getObjectIndex() return 0 end
function pc:getObjectName() return "Computer" end
local powered,hasRadio,stateReplacements=true,true,0
SC.ControlUtil={present=function(object) return object==pc end}
SC.TerminalSystem={MEMORY_KEY="system"}
SC.Terminal={isComputer=function(object) return object==pc end,powered=function() return powered end,
    computerState=function() stateReplacements=stateReplacements+1;return pc.modData.movableData.system end,
    companionAvailable=function() return true end}
SC.TerminalHardware={state=function() return {radio=hasRadio and {} or nil} end,
    receiver=function() if hasRadio then return {},{},{getCondition=function() return 100 end} end end}
local visual,clearedVisuals="active",0
SC.NativeActions={visualStatus=function() return visual end,cancelVisual=function() return true end,
    clearVisual=function() clearedVisuals=clearedVisuals+1 end}
local access=U.directInteractionAccess
U.directInteractionAccess=function() return true,{} end
local records=SC.Registry.records
SC.Registry.records=function() return {f.registry[actor.id]} end
local commands=SC.Commands.peek
SC.Commands.peek=function() return {order="base_duty"} end
local generated,rolls=0,0
local originalSay,topics=SC.Dialogue.say,{}
SC.Dialogue.say=function(_,topic) topics[topic]=(topics[topic] or 0)+1;return true end
SC.Spawn={generateIdentity=function() generated=generated+1;return {forename="Nolan",surname="Reed",gender="male",outfit="Generic01"} end}
ZombRand=function() rolls=rolls+1;return 0 end
check(R.assign(pc,actor.id),"a radio-equipped camp PC accepts a named base-duty operator")
check(not R.assign(pc,actor.id),"one PC cannot get competing shifts")
local job=B.claimJob(actor.id)
check(job and job.type=="radio_work","the real base queue dispatches the assignment")
local originalMove,keyboardAttempts=U.move,0
U.move=function(a,mode,intent)
    if intent.action=="computer_use" and keyboardAttempts==0 then
        keyboardAttempts=1;return false,"actor already has a native timed action"
    end
    return originalMove(a,mode,intent)
end
check(R.update(actor,{},job) and R.owns(actor,pc),
    "a pending native chair handoff keeps its job rather than blocking preparation")
f.clock=f.clock+250
check(R.update(actor,{},job),"operator starts keyboard work when the native queue clears")
U.move=originalMove
local originalEdge,standAccess=SC.Topology.barrierBetween,U.directInteractionAccess
local chair={getSquare=function() return actor.square end,getObjectIndex=function() return 0 end}
actor.getSitOnFurnitureObject=function() return chair end
actor.isSittingOnFurniture=function() return true end
U.directInteractionAccess=function() return false,{} end
SC.Topology.barrierBetween=function() return nil,"open" end
local seated={object=pc,chair=chair,seatRequested=f.clock,seated=true}
check(SC.ComputerUse.valid(actor,seated,true),
    "an occupied native chair does not require a free standing square to reach its keyboard")
seated.seatRequested=f.clock-60000
local staying,seatReason=SC.ComputerUse.approach(actor,seated)
check(staying and seatReason=="arrived","typing renewal keeps an established chair beyond the entry timeout")
SC.Topology.barrierBetween=function() return nil,"wall" end
check(not SC.ComputerUse.valid(actor,seated,true),"seated keyboard access never reaches through a wall")
actor.getSitOnFurnitureObject,actor.isSittingOnFurniture=nil,nil
SC.Topology.barrierBetween,U.directInteractionAccess=originalEdge,standAccess
check(S.peekOwner(actor)=="radio_work" and SC.ComputerUse.yieldToPlayer(pc),
    "monitoring the screen does not eject the explicitly assigned operator")
f.clock=f.clock+1000;f.worldHour=f.worldHour+.1
local state={}
local quiet={threatCount=0,immediateCount=0,pressure=0,threats={},player={danger=0}}
local permitted,phase=SC.Locomotion.authorize(actor,"walk",{action="computer_use",
    supervisorToken=S.current(actor)})
check(permitted and phase=="interact","keyboard work is an interaction, never walking out of a chair")
local healthy={health=100,alive=true,wounds={},bleedingCount=0}
check(SC.Decision._holdOwnedActivityOrPacingForTests(actor,f.player,quiet,healthy,{},
    {recruited=true,order="base_duty",commandSerial=1},state,f.clock,{})
    and state.current=="base_work","the real AI ownership hold polls the radio's base-job controller")
check(job.target.radioHours>.09,"observed keyboard time advances work")
job.target.radioHours=.36
f.clock=f.clock+1000;f.worldHour=f.worldHour+.02
R.update(actor,{},job)
check(topics["radio_work.banter"]==1,"working banter follows accumulated work rather than the short animation lifetime")
local progress=job.target.radioHours
local token=S.current(actor)
SC.Decision._holdOwnedActivityOrPacingForTests(actor,f.player,quiet,healthy,{hungry=true,hunger=.75},
    {recruited=true,order="base_duty",commandSerial=1},{},f.clock,{})
check(not S.isCurrent(token),"routine hunger preempts typing before starvation")
local originalHunger,mealRuntime=actor.hunger,{}
actor.hunger=.78
SC.Needs.assess(actor,mealRuntime)
actor.hunger=.301
local finishingMeal=SC.Needs.assess(actor,mealRuntime)
local duty={recruited=true,order="base_duty",commandSerial=1}
local choices=SC.Decision._evaluateForTests(actor,f.player,quiet,duty,healthy,
    finishingMeal,{},f.clock)
check(finishingMeal.hungry and choices[1].kind=="needs",
    "an admitted camp meal keeps priority over radio work between its final bites")
actor.hunger=.299
local finishedMeal=SC.Needs.assess(actor,mealRuntime)
choices=SC.Decision._evaluateForTests(actor,f.player,quiet,duty,healthy,finishedMeal,{},f.clock)
check(not finishedMeal.hungry and not finishedMeal.mealInProgress and choices[1].kind=="base_work",
    "the completed meal releases duty so the same radio shift can resume")
actor.hunger=originalHunger
SC.Needs.reset(actor)
f.worldHour=f.worldHour+8
R.update(actor,{},job)
check(job.target.radioHours==progress,"unattended and need-break time grants no progress")
local system=pc.modData.movableData.system
local renewalOwner=S.current(actor)
f.clock=f.clock+19000;f.worldHour=f.worldHour+.01
visual="completed";R.update(actor,{},job)
visual="active";R.update(actor,{},job)
check(S.current(actor)==renewalOwner and R.owns(actor,pc) and clearedVisuals==1,
    "renewing a short animation retains the radio job and its desk reservation")
check(stateReplacements==0 and pc.modData.movableData.system==system,
    "renewing staffed typing never replaces the live monitor's system record")
check(topics["radio_work.banter"]==1,"animation renewal does not spam the working line")
R.pause(actor,"save")
local exported=B.export()
check(B.restore(exported),"radio shift uses the existing base save schema")
job=B.claimJob(actor.id)
check(job.target.radioHours==progress,"reload preserves accumulated work without elapsed-time catch-up")
powered=false
local _,why,blocked=R.update(actor,{},job)
check(blocked and why=="radio_work_no_power" and job.target.radioHours==progress,
    "power failure preserves progress and releases the action")
B.blockJob(job.id,actor.id,why)
check(B.jobAutoRetry(job) and not B.jobParked(job),"power loss keeps automatic retry")
powered=true;B.retryJob(job.id);job=B.claimJob(actor.id)
R.update(actor,{},job)
job.target.radioHours=R.HOURS-.01
f.clock=f.clock+1000;f.worldHour=f.worldHour+.02
local finishCancel,finishAttempts=SC.NativeActions.cancelVisual,0
local finishOwner=S.current(actor)
SC.NativeActions.cancelVisual=function()
    finishAttempts=finishAttempts+1;return finishAttempts>1,"native visual removal pending"
end
SC.BaseWork.update(actor,f.player,{})
check(B.job(job.id)==job and S.isCurrent(finishOwner) and R.owns(actor,pc)
    and R.snapshot(pc).status=="finishing",
    "a completed shift keeps its real job and keyboard until native cleanup succeeds")
local finishSave,contactId=B.export(),R.snapshot(pc).contact.id
visual="cancelled"
SC.BaseWork.update(actor,f.player,{})
check(not B.job(job.id) and not S.isCurrent(finishOwner) and not R.owns(actor,pc)
    and R.snapshot(pc).status=="found" and R.snapshot(pc).contact.name=="Nolan Reed",
    "completion retries cleanup even after the typing pose has left the native queue")
SC.NativeActions.cancelVisual=finishCancel;visual="active"
check(rolls==1 and generated==1,"the outcome and identity are generated once")
check(B.restore(finishSave),"a shift awaiting keyboard release can be saved and restored")
job=B.claimJob(actor.id)
local oldMove,completionStarts=U.move,0
U.move=function(a,mode,intent)
    if intent.action=="computer_use" then completionStarts=completionStarts+1 end
    return oldMove(a,mode,intent)
end
SC.BaseWork.update(actor,f.player,{})
U.move=oldMove
check(not B.job(job.id) and completionStarts==0 and rolls==1 and generated==1
    and R.snapshot(pc).contact.id==contactId,
    "restoring a finished shift releases it without another typing action, roll or contact")
local begins=0
SC.Navigation.spawnAccessible=function() return true end
-- Existing native-safe square checks are required before spawning anything.
local square=f.makeSquare(17,1,0)
function square:isSafeToSpawn() return true end
local oldGrid=U.gridSquare
U.gridSquare=function(x,y,z)
    local tile=f.makeSquare(x,y,z)
    function tile:isSafeToSpawn() return true end
    return tile
end
SC.Actor.beginSpawn=function(_,profile)
    begins=begins+1;check(profile.id==R.snapshot(pc).contact.id,"spawn identity is fixed before native dispatch")
    return {}
end
check(R.invite(pc,f.player),"player can invite the waiting contact")
check(not R.invite(pc,f.player) and begins==1,"repeat invitation cannot duplicate a native spawn")
SC.Actor.pollSpawn=function() return nil,"failed" end
R.pulse();R.observe(pc)
check(R.snapshot(pc).contact.status=="arrival_uncertain" and begins==1,
    "ambiguous interrupted arrival is retained and never recreated")
pc.modData.movableData[R.KEY].contact=nil
U.gridSquare=oldGrid
check(R.assign(pc,actor.id),"a new shift can be assigned after the completed receipt is cleared in this fixture")
job=B.claimJob(actor.id)
local originalResolve=B.resolveObject
-- The preceding arrival-surface fixture replaces grid squares. Restore this
-- physical PC seam while keeping the real queue and cancellation controller.
B.resolveObject=function(reference)
    if reference==job.target then return pc end
    return originalResolve(reference)
end
local began,beginWhy=R.update(actor,{},job)
check(R.owns(actor,pc),"cancellation fixture has an active keyboard owner: "..tostring(beginWhy))
local oldCancel,cancelAttempts=SC.NativeActions.cancelVisual,0
SC.NativeActions.cancelVisual=function()
    cancelAttempts=cancelAttempts+1;return cancelAttempts>1,"native visual removal pending"
end
local accepted,why=R.stop(pc)
check(accepted and why=="radio_work_cancelling" and B.job(job.id),
    "one Cancel request survives asynchronous native action removal")
R.update(actor,{},job)
check(not B.job(job.id) and not R.owns(actor,pc),"the next work tick completes cancellation without another click")
SC.NativeActions.cancelVisual=oldCancel
check(R.assign(pc,actor.id),"another shift can be assigned after cancellation")
job=B.claimJob(actor.id)
R.update(actor,{},job)
check(R.pause(actor,"radio_work_no_power"),"a blocked shift releases its operator")
B.blockJob(job.id,actor.id,"radio_work_no_power")
local _,otherPC=f.containerObject(f.makeSquare(5,1,0),{}, {containerType="desk"})
otherPC.modData.movableData={system={identity="radio-other-pc",locked=false}}
function otherPC:getObjectIndex() return 0 end
SC.ControlUtil.present=function(object) return object==pc or object==otherPC end
SC.Terminal.isComputer=SC.ControlUtil.present
check(R.assign(otherPC,actor.id),"an operator with a blocked shift can work at a different PC")
local otherJob=B.claimJob(actor.id)
local pcResolve=B.resolveObject
B.resolveObject=function(reference)
    if reference==otherJob.target then return otherPC end
    return pcResolve(reference)
end
check(R.update(actor,{},otherJob) and R.owns(actor,otherPC),"the second PC owns its active shift")
local otherOwner=S.current(actor)
check(R.stop(pc) and not B.job(job.id) and B.job(otherJob.id)==otherJob
    and R.owns(actor,otherPC) and S.isCurrent(otherOwner),
    "cancelling an older blocked shift preserves the newer job, keyboard and supervisor")
check(R.stop(otherPC) and not B.job(otherJob.id) and not R.owns(actor,otherPC),
    "cancelling the matching shift still releases its keyboard")
B.resolveObject=originalResolve
U.directInteractionAccess,U.gridSquare,SC.Registry.records,SC.Commands.peek=access,oldGrid,records,commands
getGameTime=oldTime
SC.Dialogue.say=originalSay
R.reset()
SC_TEST_REPORT="Radio work PASS: assignment, ownership, working time, pause, power, reload, single roll and exact invitation"
