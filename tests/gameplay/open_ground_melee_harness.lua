-- SPDX-License-Identifier: MIT
-- Exercise the production risk, utility and execution paths for local kiting.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local U, checks = SC.GameplayUtil, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "open-ground melee " .. checks .. ": " .. message)
end
local actor = f.actor("sc-open-ground", 4, 4, {})
f.registry[actor.id] = actor
local item = f.item("Base.HuntingKnife", "Weapon", { range = 0.9 })
function item:getMaxRange() return 0.9 end
function item:getMinRange() return 0.61 end
function item:getCondition() return 10 end
function item:getConditionMax() return 10 end
function item:getMaxDamage() return 1.2 end
function item:getCategories() return {"SmallBlade"} end
actor:setPrimaryHandItem(item)
actor.inventory:AddItem(item)
local _, _, weapon = SC.Combat.meleeRange(actor, item)
weapon.equipped = true
local enemy = f.zombie(6,4,{})
function enemy:getX() return self.worldX or self.square.x+0.5 end
function enemy:getY() return self.worldY or self.square.y+0.5 end
enemy.worldX, enemy.worldY = actor:getX()+1.45, actor:getY()
local rear = f.zombie(7,4,{})
function rear:getX() return self.worldX or self.square.x+0.5 end
function rear:getY() return self.worldY or self.square.y+0.5 end
rear.worldX, rear.worldY = actor:getX()+3, actor:getY()
local target = { actor=enemy, visible=true, bearing="front", closingSpeed=1,
    distanceSq=1.45^2, score=90 }
local commands = { order="stay", recruited=true, combatDoctrine="weapons_free" }
local snapshot = { threats={{actor=enemy,visible=true},{actor=rear,visible=true}},
    pressure=5, immediateCount=3, closeImmediateCount=3, closeThreatCount=3,
    occupiedThreatSectors=1, escapeSquares={{square=f.cell:getGridSquare(1,4,0),
        danger=0, nearestThreatSq=16}}, allies={} }
local previousVector, previousSegment = SC.Navigation.combatVector, SC.Navigation.openSegment
local blocked = false
SC.Navigation.combatVector = function() return -1,0,false,"direct" end
SC.Navigation.openSegment = function() return not blocked end
local oldReadiness = SC.Combat.readiness
local function readiness()
    local value = oldReadiness(actor,snapshot,weapon,commands)
    value.endurance=1;value.enduranceReserve=0.25;value.staminaCritical=false
    return value
end
local ready = readiness()
snapshot.player={actor=actor,available=true,health=100}
snapshot.allies={{actor=actor,health=100,distanceSq=0}}
check(readiness().support==0,"a watched solo fighter cannot count its own player anchor or ally entry as backup")
snapshot.allies={}
local function context() return SC.MeleeKiting.context(actor,snapshot,target,weapon,ready) end
check(context()~=nil, "fit lone fighter has a verified outdoor lane")
SC.Combat.readiness = function() return ready end
local assessed = SC.Combat.assessOverrun(actor,snapshot,weapon,commands,{target=target})
check(not assessed.overrun and assessed.localKite~=nil,
    "three frontal contacts select local footwork instead of forced full withdrawal")
enemy.onFloor=true
check(not SC.Combat.assessOverrun(actor,snapshot,weapon,commands,{target=target}).overrun
    and SC.MeleeKiting.action(actor,target,weapon,ready,context(),{},1000)==nil,
    "knocking the selected zombie down preserves local evasion and the ordinary safe finisher")
enemy.onFloor=false
local actions = SC.Combat._actionUtilitiesForTests(actor,nil,snapshot,target,weapon,nil,commands,ready)
check(actions[1].kind=="hold_range" and actions[1].localKite,
    "short blade waits for its own reach instead of endless kiting or utility retreat")
enemy.worldX=actor:getX()+1.07;target.distanceSq=1.07^2
actions=SC.Combat._actionUtilitiesForTests(actor,nil,snapshot,target,weapon,nil,commands,ready)
check(actions[1].kind=="melee" and actions[1].anticipatorySwing,
    "closing pursuer opens a short-blade strike at native animation lead")
local oldBarrier=SC.Topology.strikeBarrier
SC.Topology.strikeBarrier=function(_,_,kind) return kind=="melee","fence" end
actions=SC.Combat._actionUtilitiesForTests(actor,nil,snapshot,target,weapon,nil,commands,ready)
for _,choice in ipairs(actions) do
    check(choice.kind~="melee","local counterattacks still pass the physical strike-barrier gate")
end
SC.Topology.strikeBarrier=oldBarrier
target.closingSpeed=0.3
actions=SC.Combat._actionUtilitiesForTests(actor,nil,snapshot,target,weapon,nil,commands,ready)
check(actions[1].kind=="hold_range","slow motion cannot request an early swing the native range gate rejects")
target.closingSpeed=1
target.bearing="rear"
actions=SC.Combat._actionUtilitiesForTests(actor,nil,snapshot,target,weapon,nil,commands,ready)
check(actions[1].kind=="hold_range" and context()~=nil,
    "turning away to run retains local evasion but requires facing the pursuer before another strike")
target.bearing="front"
enemy.worldX=actor:getX()+1.2;target.distanceSq=1.2^2;target.closingSpeed=1.6
rear.worldX=actor:getX()+2.2
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),{},1000).kind~="melee",
    "a short blade waits when a second pursuer can arrive during native recovery")
enemy.worldX=actor:getX()+1.1;target.distanceSq=1.1^2
local control=SC.MeleeKiting.action(actor,target,weapon,ready,context(),{},1000)
check(control.kind=="shove" and control.kiteControl,
    "a short blade can control the front contact when a stab cannot recover safely")
local controlState={}
SC.MeleeKiting.accept(actor,enemy,control,controlState,1000)
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),controlState,1200).kind~="shove",
    "a control shove cannot replace every following decision")
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),controlState,2800).kind=="shove",
    "another bounded control opening is available after recovery")
local wideItem=f.item("Base.Axe","Weapon",{range=1.2,minRange=0.61})
local _,_,wideWeapon=SC.Combat.meleeRange(actor,wideItem);wideWeapon.equipped=true
local wideContext=SC.MeleeKiting.context(actor,snapshot,target,wideWeapon,ready)
check(SC.MeleeKiting.action(actor,target,wideWeapon,ready,wideContext,{},1000).kind=="melee",
    "a wider weapon keeps its safe ordinary strike instead of short-blade control")
rear.worldX=actor:getX()+3.2
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),{},1000).kind=="melee",
    "a short blade can counter when the other pursuer leaves recovery time")
enemy.worldX=actor:getX()+3.47;target.distanceSq=3.47^2;target.closingSpeed=0
rear.worldX=actor:getX()+4.5
local waitingState={}
local waitingAction=SC.MeleeKiting.action(actor,target,weapon,ready,context(),waitingState,1000)
check(waitingAction.kind=="hold_range","a new quiet gap gets a brief guarded wait")
SC.MeleeKiting.accept(actor,enemy,waitingAction,waitingState,1000)
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),waitingState,2000).kind=="hold_range",
    "the waiting interval cannot turn into immediate rushing")
local reentry=SC.MeleeKiting.action(actor,target,weapon,ready,context(),waitingState,2300)
check(reentry.kind=="approach" and reentry.stalledApproach
    and reentry.minimumDistance<weapon.range,
    "a stalled 3.47-metre gap gets a bounded weapon-specific re-entry")
enemy.worldX=actor:getX()+3.1;target.distanceSq=3.1^2;target.closingSpeed=1
SC.MeleeKiting.accept(actor,enemy,waitingAction,waitingState,2400)
check(waitingState.kiteWait.at==2400
    and SC.MeleeKiting.action(actor,target,weapon,ready,context(),waitingState,3000).kind=="hold_range",
    "observed closing progress restarts the guarded wait")
target.closingSpeed=0;target.attacking=true
check(SC.MeleeKiting.action(actor,target,weapon,ready,context(),waitingState,4000).kind~="approach",
    "an active attack cannot trigger stalled-target re-entry")
target.attacking=false;target.closingSpeed=1
enemy.worldX=actor:getX()+1.35;target.distanceSq=1.35^2;rear.worldX=actor:getX()+1.55
local state={}
local action=SC.MeleeKiting.action(actor,target,weapon,ready,context(),state,1000)
check(action.kiteRun and action.kind=="backstep", "crowded weapon gets a short turn-and-run")
enemy.worldX=actor:getX()+1.45;target.distanceSq=1.45^2;rear.worldX=actor:getX()+1.65
local otherTarget={actor=rear,visible=true,bearing="front",closingSpeed=1,
    distanceSq=1.65^2,score=90}
local committed={target=rear,targetCommitUntil=U.nowMs()+2000}
check(not SC.Combat.assessOverrun(actor,snapshot,weapon,commands,{target=otherTarget}).overrun,
    "risk assessment retains the open lane while the selected target is being replaced")
local pair=SC.Combat._selectViablePairForTests(actor,nil,snapshot,{otherTarget,target},
    commands,committed,U.nowMs(),"melee",otherTarget)
check(pair and pair.target.actor==enemy and pair.action.localKite,
    "old target commitment cannot replace a verified local escape with full retreat")
enemy.worldX=actor:getX()+1.35;target.distanceSq=1.35^2;rear.worldX=actor:getX()+1.55
local oldMove, mode, intent=U.move,nil,nil
U.move=function(_,gait,options) mode,intent=gait,options;return true end
local accepted,reason=SC.Combat._executeForTests(actor,nil,snapshot,target,weapon,action,commands,state)
check(accepted and reason=="kite_run" and mode=="jog" and not intent.keepFacing
    and not intent.weaponReady and intent.allowMovingTurn and intent.dx<0,
    "execution turns into the checked escape vector and runs with the weapon lowered")
SC.MeleeKiting.accept(actor,enemy,action,state,1000)
action=SC.MeleeKiting.action(actor,target,weapon,ready,context(),state,2400)
check(not action.kiteRun, "elapsed run cannot restart another burst without a facing interval")
SC.MeleeKiting.accept(actor,enemy,action,state,2400)
check(state.kiteBurst==nil and state.kiteRunCooldown==3050, "accepted facing step installs run cooldown")
action=SC.MeleeKiting.action(actor,target,weapon,ready,context(),state,2500)
check(not action.kiteRun, "run cooldown is observed on the next reflex pulse")
U.move=oldMove
for _,scenario in ipairs({"tired","injured","indoor","encircled","no_exit","blocked_lane","flank","squad"}) do
    ready=readiness()
    local savedEscape=snapshot.escapeSquares
    if scenario=="tired" then ready.endurance=0.15;ready.staminaCritical=true
    elseif scenario=="injured" then ready.health=45
    elseif scenario=="indoor" then ready.indoors=true
    elseif scenario=="encircled" then snapshot.encircled=true
    elseif scenario=="no_exit" then snapshot.escapeSquares={}
    elseif scenario=="blocked_lane" then blocked=true
    elseif scenario=="flank" then rear.worldX=actor:getX()-1
    elseif scenario=="squad" then ready.support=1 end
    check(context()==nil, scenario .. " preserves the ordinary safety policy")
    if scenario=="tired" or scenario=="injured" then
        check(SC.Combat.assessOverrun(actor,snapshot,weapon,commands,{target=target}).overrun,
            scenario .. " still triggers emergency withdrawal")
    end
    snapshot.escapeSquares=savedEscape;snapshot.encircled=false;blocked=false
    rear.worldX=actor:getX()+1.55
    ready=readiness()
    check(context()~=nil,scenario .. " control restores a usable open lane")
end
ready=readiness()
local laneSquare=f.cell:getGridSquare(2,4,0)
laneSquare.hasTree=true
check(context()==nil,"a tree in the run lane prevents open-ground classification")
laneSquare.hasTree=false;laneSquare.room={}
check(context()==nil,"a building in the run lane prevents open-ground classification")
laneSquare.room=nil;laneSquare.hasFloor=false
check(context()==nil,"missing floor prevents open-ground classification")
laneSquare.hasFloor=true
local savedVector,savedSegment=SC.Navigation.combatVector,SC.Navigation.openSegment
SC.Navigation.combatVector=function(_,_,kind)
    if kind=="kite" then return 0,1,true end
    return -1,0,false
end
SC.Navigation.openSegment=function(_,x) return x>=actor:getX()-1 end
local turned=context()
check(turned and turned.moveX==0 and turned.moveY==1 and turned.microSteered,
    "a blocked rear lane turns into a separately verified lateral escape")
local sideSquare=f.cell:getGridSquare(4,6,0)
sideSquare.hasTree=true
check(context()==nil,"a tree in the lateral lane prevents the escape alternative")
sideSquare.hasTree=false
SC.Navigation.openSegment=function() return false end
check(context()==nil,"blocked rear and lateral lanes preserve the ordinary safety policy")
SC.Navigation.openSegment=function(_,x) return x>=actor:getX()-1 end
SC.Navigation.combatVector=function(_,_,kind)
    if kind=="kite" then return nil,nil,false,"blocked" end
    return -1,0,false
end
check(context()==nil,"native lateral steering refusal cannot be replaced with an unchecked turn")
SC.Navigation.combatVector,SC.Navigation.openSegment=savedVector,savedSegment
SC.Navigation.combatVector=function(_,_,kind)
    if kind=="kite" then return 0,1,false end
    return -1,0,false
end
SC.Navigation.openSegment=function() return true end
local oldClear=actor.isCompanionMovementClear
function actor:isCompanionMovementClear() return true end
local curve=context()
check(curve and curve.curveEscape and curve.moveX< -0.6 and curve.moveY>0.6,
    "clustered pursuers get a fully checked diagonal escape for a short blade")
local curveAction=SC.MeleeKiting.action(actor,target,weapon,ready,curve,{},1000)
check(curveAction.kiteRun and curveAction.kiteCurve,
    "the diagonal escape uses the existing bounded turn-and-run")
local curveState={}
SC.MeleeKiting.accept(actor,enemy,curveAction,curveState,1000)
check(curveState.kiteBurst and curveState.kiteBurst.curve,
    "only accepting the escape preserves its curved run episode")
function actor:isCompanionMovementClear() return false end
curve=context()
check(curve and not curve.curveEscape and curve.moveY==0,
    "native diagonal refusal retains the already checked rear lane")
function actor:isCompanionMovementClear() return true end
local diagonalSquare=f.cell:getGridSquare(2,6,0);diagonalSquare.hasTree=true
curve=context()
check(curve and not curve.curveEscape and curve.moveY==0,
    "a tree anywhere in the diagonal lane prevents the curved escape")
diagonalSquare.hasTree=false
actor.isCompanionMovementClear=oldClear
SC.Navigation.combatVector,SC.Navigation.openSegment=savedVector,savedSegment
local furthestProbe=0
function actor:isCompanionMovementClear(x,y)
    furthestProbe=math.max(furthestProbe,math.sqrt((x-self:getX())^2+(y-self:getY())^2))
    return x>=self:getX()-1
end
local laneX,laneY,_,laneWhy=previousVector(actor,enemy,"kite",snapshot,3)
check(furthestProbe>2.99 and laneX and math.abs(laneX)<0.01 and math.abs(laneY)>0.99,
    "full-lane steering selects a three-metre sideways escape before the fence: probe="
        .. tostring(furthestProbe) .. " vector=" .. tostring(laneX) .. ":" .. tostring(laneY)
        .. " reason=" .. tostring(laneWhy))
SC.Navigation.openSegment=function() return false end
check(previousVector(actor,enemy,"kite",snapshot,3)==nil,
    "full-lane steering still rejects a blocked segment between the endpoints")
SC.Navigation.openSegment=savedSegment
furthestProbe=0
previousVector(actor,enemy,"kite",snapshot)
check(furthestProbe>0.44 and furthestProbe<0.46,
    "ordinary companion steering retains its original short probe by default")
actor.isCompanionMovementClear=oldClear
SC.Combat.readiness=oldReadiness
SC.Navigation.combatVector,SC.Navigation.openSegment=previousVector,previousSegment
SC_TEST_REPORT="Open-ground melee PASS checks=" .. checks
