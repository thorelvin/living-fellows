-- SPDX-License-Identifier: MIT
-- A safe floor-finisher offer must survive the production execution gates.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local U, checks = SC.GameplayUtil, 0
local function check(value, message)
    checks=checks+1;assert(value,"ground finisher execution " .. checks .. ": " .. message)
end
local actor=f.actor("sc-ground-execution",4,4,{})
local victim=f.zombie(4,4,{onFloor=true})
local other=f.zombie(4,4,{onFloor=true})
local item=f.item("Base.Sledgehammer","Weapon",{condition=10,conditionMax=10,range=1.35})
actor:setPrimaryHandItem(item)
local _,_,weapon=SC.Combat.meleeRange(actor,item)
weapon.equipped=true
local target={actor=victim,visible=true,bearing="front",distanceSq=0.41^2}
local snapshot={threats={{actor=victim,posture="downed"},{actor=other,posture="downed"}},
    allies={},closeImmediateCount=2,immediateCount=2,reachableImmediateCount=0}
local oldMove,moves,lastIntent=U.move,0,nil
U.move=function(_,_,intent) moves=moves+1;lastIntent=intent;return true end
local commands={order="stay",recruited=true}
local function execute(kind)
    moves,lastIntent=0,nil
    return SC.Combat._executeForTests(actor,nil,snapshot,target,weapon,
        {kind=kind,floorAttack=kind=="melee"},commands,{})
end
for _,kind in ipairs({"melee","stomp"}) do
    local accepted=execute(kind)
    check(accepted and moves==1 and lastIntent.floorAttack
        and lastIntent.action==(kind=="melee" and "attack_melee" or "stomp"),
        "two downed zombies permit the selected native " .. kind .. " finisher")
end
snapshot.threats[2].posture="upright";other.onFloor=false
for _,kind in ipairs({"melee","stomp"}) do
    local accepted,reason=execute(kind)
    check(not accepted and reason=="finisher_unsafe" and moves==0,
        "an upright close attacker still blocks " .. kind)
end
snapshot.threats[2].posture="downed";other.onFloor=true
victim.onFloor=false;SC.ZombieFacts.forget(victim)
for _,kind in ipairs({"melee","stomp"}) do
    local accepted,reason=execute(kind)
    check(not accepted and moves==0 and (reason=="stomp_anchor_invalid"
        or reason=="ground_melee_target_invalid"),
        "live target posture invalidates a stale " .. kind .. " finisher offer")
end
victim.onFloor=true;SC.ZombieFacts.forget(victim)
local squad=SC.CombatSquad;SC.CombatSquad=nil
for _,kind in ipairs({"melee","stomp"}) do
    local accepted=execute(kind)
    check(not accepted and moves==0,"missing posture-aware safety keeps conservative " .. kind .. " fallback")
end
SC.CombatSquad=squad;U.move=oldMove
SC_TEST_REPORT=(SC_TEST_REPORT and SC_TEST_REPORT .. "\n" or "")
    .. "GROUND_FINISHER_EXECUTION_PASS checks=" .. checks
