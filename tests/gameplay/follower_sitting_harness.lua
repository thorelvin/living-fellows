-- SPDX-License-Identifier: MIT
-- Real downtime/supervisor policies with the seat-route fixture's native adapters.
local SC=SurvivorCompanion
local D,U,S=SC.Downtime,SC.GameplayUtil,SC.ActionSupervisor
local _,seatActivity,_,begin,_,_,floorRest,_,_,_,_,stateFor=D._furnitureForTests()
local checks=0
local function check(value,message) checks=checks+1 assert(value,"follower sitting "..checks..": "..message) end
local hour=100
function getGameTime() return {getWorldAgeHours=function() return hour end} end
local square={x=10,y=10,z=0,getRoom=function() return nil end}
local chair={x=10,y=10,z=0,square=square,useSquare=square,getName=function() return "Chair" end}
SeatingManager={getInstance=function() return {getTilePositionCount=function() return 1 end} end}
U.gridSquare=function() return square end
U.squareObjects=function(_,visit) visit(chair) end
U.isDue=function() return false end
U.sortByScoreDescending=function(rows) table.sort(rows,function(a,b) return a.score>b.score end) end
U.characterStatValue=function(actor,key,fallback)
    if key=="FATIGUE" then return actor.fatigue or 0 end
    if key=="ENDURANCE" then return actor.endurance or 1 end
    return fallback
end
local quiet={snapshot={indoors=true,threatCount=0,immediateCount=0}}
local function fellow(id)
    SC_READING_CLOCK=SC_READING_CLOCK+200000
    local actor=SC_READING_ACTOR("follow-sit:"..id)
    local player=SC_READING_ACTOR("follow-leader:"..id)
    actor.square,actor.access,actor.endurance=square,true,1
    actor.commands.order="follow"
    player.x=actor.x+1
    function player:isMoving() return self.moving==true end
    return actor,player,stateFor(actor)
end
local function enter(actor,player,state,activity)
    local okay,why=begin(actor,state,activity,actor.commands,SC_READING_CLOCK)
    check(okay,"real supervised rest accepted: "..tostring(why))
    actor.entered,actor.seatState=true,activity.kind=="rest_floor" and "ground" or "furniture"
    if activity.kind=="rest_floor" then
        SC.NativeActions.groundStatus=function() return "entered" end
    end
    D.update(actor,player,quiet,"sit")
    check(state.active==activity and activity.startedAt~=nil,"native pose entered before rest timing")
end

local actor,player,state=fellow("routine")
local _,why=D.update(actor,player,quiet,"sit")
check(why=="leader_pause_too_short" and not state.active,"a brief indoor stop does not start sitting")
SC_READING_CLOCK=SC_READING_CLOCK+14999
D.update(actor,player,quiet,"sit")
check(not state.active,"the whole stillness interval is required")
SC_READING_CLOCK=SC_READING_CLOCK+1
D.update(actor,player,quiet,"sit")
local activity=state.active
check(activity and activity.kind=="sit" and activity.followPause
    and activity.durationMs==15000 and activity.gameDurationHours==nil,"routine follower sit uses a short real-time duration")
actor.entered,actor.seatState=true,"furniture"
D.update(actor,player,quiet,"sit")
local started=activity.startedAt
hour=hour+2
SC_READING_CLOCK=started+14999
D.update(actor,player,quiet,"sit")
check(state.active==activity,"game-speed changes do not turn the follower pause into a long game-time rest")
SC_READING_CLOCK=started+15000
D.update(actor,player,quiet,"sit")
check(not state.active and not S.current(actor) and actor.seatState=="standing",
    "a finished routine pause releases its token and stands up")
SC_READING_CLOCK=SC_READING_CLOCK+61000
check(not D.canPerform(actor,"sit"),"routine sitting cannot repeat after only the old one-minute cooldown")
SC_READING_CLOCK=state.followSitCooldownUntil
check(D.canPerform(actor,"sit"),"routine sitting becomes available again after three minutes")

actor,player,state=fellow("moving")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
player.moving=true
check(D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+1)
    and not state.active and actor.seatState=="standing" and not S.current(actor),
    "nearby movement interrupts the owned sit before normal decision arbitration")

actor,player,state=fellow("position-motion")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
player.x=player.x+0.3
check(D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+1)
    and actor.seatState=="standing","position changes also interrupt when a mod omits the movement flag")

actor,player,state=fellow("recovery")
actor.endurance=0.3
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
check(activity.recoveryRest and activity.durationMs==60000,"low stamina retains a bounded recovery rest")
SC_READING_CLOCK=activity.startedAt+5000
actor.endurance=0.9
D.update(actor,player,quiet,"sit")
check(not state.active and actor.seatState=="standing","recovery ends early when native stamina has recovered")

actor,player,state=fellow("recovery-cap")
actor.endurance=0.3
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
SC_READING_CLOCK=activity.startedAt+60000
D.update(actor,player,quiet,"sit")
check(not state.active and actor.endurance==0.3,"the maximum recovery time is bounded without manufacturing stamina")

actor,player,state=fellow("floor")
actor.fatigue=0.8
check(not floorRest(actor,false,true),"sleep fatigue alone cannot create an endless follower floor-sit cycle")
actor.endurance=0.3
activity=floorRest(actor,false,true)
check(activity and activity.kind=="rest_floor","low stamina can still request a physical floor rest")
check(floorRest(actor,false,false)~=nil,"camp floor-rest fatigue policy is retained")
enter(actor,player,state,activity)
SC_READING_CLOCK=activity.startedAt+5000
actor.endurance=0.9
D.update(actor,player,quiet,"sit")
check(not state.active and actor.seatState=="standing","floor recovery ends when actual stamina recovers")

actor,player,state=fellow("order-change")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
actor.commands.commandSerial=actor.commands.commandSerial+1
D.update(actor,player,quiet,"sit")
check(not state.active and not S.current(actor) and actor.seatState=="standing",
    "an explicit new order still releases the sit and its resources")

actor,player,state=fellow("danger")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
D.update(actor,player,{snapshot={indoors=true,threatCount=1,immediateCount=1}},"sit")
check(not state.active and not S.current(actor) and actor.seatState=="standing",
    "danger interrupts routine seating")

actor,player,state=fellow("reading-seat")
local book=SC_READING_BOOK("SeatFollowup")
actor.inventory=SC_READING_INVENTORY({book})
activity=seatActivity(actor,state,SC_READING_CLOCK)
activity.fact.seatingFor="read"
enter(actor,player,state,activity)
check(activity.durationMs==1500,"a reading seat settles promptly rather than resting for game hours first")
SC_READING_CLOCK=activity.startedAt+1500
D.update(actor,player,quiet,"sit")
check(not state.active and actor.seatState=="furniture" and state.passiveFollowSeat,
    "a real reading follow-up may keep its seated posture")
player.moving=true
check(D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+1)
    and actor.seatState=="standing" and not state.passiveFollowSeat,
    "a passive seat also gets up promptly when the leader resumes walking")

actor,player,state=fellow("passenger")
local car={getDriver=function() return player end}
function actor:getVehicle() return car end
function player:getVehicle() return car end
player.moving=true
state.passiveFollowSeat,actor.seatState=true,"furniture"
check(not D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK)
    and state.passiveFollowSeat,"movement does not cancel passenger reading in the shared car")

actor,player,state=fellow("medical-owner")
state.passiveFollowSeat,actor.seatState=true,"furniture"
player.moving=true
local medical=assert(S.begin(actor,{owner="medical",action="treat",priority=S.Priority.SURVIVAL,
    ignoreRetry=true,onCancel=function() return true end}))
check(not D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK)
    and S.isCurrent(medical) and actor.seatState=="furniture","following cannot cancel another controller's care")
S.cancel(actor,"fixture_done",nil,true)
local passiveDiagnostic=D.status(actor)

local originalLeave=SC.NativeActions.leaveSeating
SC.NativeActions.leaveSeating=function(value)
    if (value.standPollsRemaining or 0)>0 then
        value.standPollsRemaining=value.standPollsRemaining-1
        return false,"standing_from_furniture"
    end
    return originalLeave(value)
end
actor,player,state=fellow("asynchronous-completion")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
actor.standPollsRemaining=2
SC_READING_CLOCK=activity.startedAt+15000
D.update(actor,player,quiet,"sit")
check(state.active==activity and S.current(actor) and not S.current(actor).protectedPose
    and D.status(actor).phase=="getting_up",
    "completion retains ownership while the native get-up transition is pending")
actor.x=actor.x+0.8
S.update(actor)
check(S.current(actor)~=nil,"native get-up root motion is allowed after the seated rest was verified")
SC_READING_CLOCK=SC_READING_CLOCK+250
D.update(actor,player,quiet,"sit")
check(state.active==activity and actor.seatState=="furniture","get-up is polled rather than treated as an instant exit")
SC_READING_CLOCK=SC_READING_CLOCK+250
D.update(actor,player,quiet,"sit")
check(not state.active and not S.current(actor) and actor.seatState=="standing",
    "verified standing completes the routine pause and releases ownership")

actor,player,state=fellow("asynchronous-cancel")
activity=seatActivity(actor,state,SC_READING_CLOCK)
enter(actor,player,state,activity)
actor.standPollsRemaining=3
player.moving=true
D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+1)
check(not state.active and state.exitingRest and actor.seatState=="furniture",
    "movement cancellation retains a pending native exit after releasing the timed action")
player.moving=false
D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+2)
D.resumeFollow(actor,player,quiet.snapshot,SC_READING_CLOCK+3)
check(not state.exitingRest and not state.passiveFollowSeat and actor.seatState=="standing",
    "pending get-up finishes even if the leader stops walking again")
SC.NativeActions.leaveSeating=originalLeave

local unknown=SC_READING_ACTOR("uninitialised-diagnostic")
local before=D.peek(unknown)
local report=D.status(unknown)
check(before==nil and D.peek(unknown)==nil and report.kind=="none" and report.fatigue==0,
    "rest diagnostics read native needs without creating idle state")
check(passiveDiagnostic.kind=="passive_seat" and passiveDiagnostic.endurance==1,
    "diagnostics identify retained seating and stamina")
SC_TEST_REPORT="FOLLOWER_SITTING_PASS checks="..checks
