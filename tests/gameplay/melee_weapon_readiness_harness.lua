-- SPDX-License-Identifier: MIT
-- Current game's typed weapon-category API, as used by native melee XP.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local checks = 0
local function check(value, message)
    checks=checks+1;assert(value,"melee weapon readiness " .. checks .. ": " .. message)
end
WeaponCategory={AXE={},BLUNT={},LONG_BLADE={},SMALL_BLADE={},SMALL_BLUNT={},SPEAR={}}
local actor=f.actor("sc-weapon-readiness",4,4,{})
actor.perks={Axe=5,Blunt=6,LongBlade=7,SmallBlade=4,SmallBlunt=2,Spear=3,Aiming=8}
local commands={order="stay",recruited=true}
local snapshot={threats={},allies={},escapeSquares={}}
local function itemFor(kind, category)
    local item=f.item(kind,"Weapon",{condition=10,conditionMax=10,range=1.2})
    function item:isOfWeaponCategory(value) return value==WeaponCategory[category] end
    -- A stale compatibility list must not replace the native category.
    function item:getCategories() return {"SmallBlunt"} end
    return item
end
local function read(item)
    local _,_,weapon=SC.Combat.meleeRange(actor,item)
    return SC.Combat.readiness(actor,snapshot,weapon,commands),weapon
end
for _,case in ipairs({
    {"Base.HandAxe","AXE","Axe",5}, {"Base.Axe","AXE","Axe",5},
    {"Base.WoodAxe","AXE","Axe",5}, {"Base.Plank","BLUNT","Blunt",6},
    {"Base.Sledgehammer","BLUNT","Blunt",6},
    {"Base.Wrench","SMALL_BLUNT","SmallBlunt",2},
    {"Base.KitchenKnife","SMALL_BLADE","SmallBlade",4},
    {"Base.Machete","LONG_BLADE","LongBlade",7},
    {"Base.SpearCrafted","SPEAR","Spear",3},
}) do
    local ready=read(itemFor(case[1],case[2]))
    check(ready.combatSkill==case[4] and ready.combatSkillName==case[3],
        case[1] .. " uses its current native category and actual perk level")
end
local sledge=itemFor("Base.Sledgehammer","BLUNT")
actor.perks.Blunt,actor.perks.SmallBlunt=0,9
local ready=read(sledge)
check(ready.combatSkill==0 and ready.combatSkillName=="Blunt",
    "untrained long-blunt fighter cannot borrow short-blunt skill from hammer's name")
actor.perks.Blunt,actor.perks.SmallBlunt=6,2
local legacy=f.item("Base.Plank","Weapon",{weaponCategories={"Blunt"}})
check(read(legacy).combatSkill==6,"legacy category lists still work when native predicate is absent")
actor.perks.Blunt=0
legacy.itemType="Base.Sledgehammer"
ready=read(legacy)
check(ready.combatSkill==0 and ready.combatSkillName=="Blunt",
    "legacy recognized zero also preserves the declared category")
actor.perks.Blunt=6
local mixed=itemFor("Base.MixedTool","BLUNT")
function mixed:isOfWeaponCategory(value)
    return value==WeaponCategory.BLUNT or value==WeaponCategory.SMALL_BLUNT
end
check(read(mixed).combatSkill==6,"multiple native categories use the fighter's strongest applicable skill")
local broken=itemFor("Base.Wrench","SMALL_BLUNT")
function broken:isOfWeaponCategory() error("native predicate unavailable") end
function broken:getCategories() return {"Axe"} end
check(read(broken).combatSkill==5,"failed native calls retain the compatibility fallback")
local heavy=itemFor("Base.Sledgehammer","BLUNT")
heavy.weight,heavy.enduranceMod,heavy.twoHanded,heavy.range,heavy.minRange=6,4,true,1.35,0.7
local heavyReady,heavyRecord=read(heavy)
heavyRecord.equipped=true
check(heavyReady.weaponCost>25 and heavyReady.enduranceReserve==0.62
    and not heavyReady.staminaCritical and heavyReady.internalRisk<1,
    "fresh heavy-tool fighter keeps the high reserve without fictional exhaustion")
local lone=f.zombie(6,4,{})
function lone:getX() return actor:getX()+1.2 end
function lone:getY() return actor:getY() end
local loneSnapshot={threats={{actor=lone,visible=true}},allies={},escapeSquares={},
    pressure=1.5,immediateCount=1,closeThreatCount=1,occupiedThreatSectors=1}
local loneTarget={actor=lone,visible=true,bearing="front",distanceSq=1.2^2,score=90,closingSpeed=0}
check(not SC.Combat.assessOverrun(actor,loneSnapshot,heavyRecord,commands).overrun,
    "one reachable zombie does not overrun a healthy rested sledgehammer fighter")
local heavyChoices=SC.Combat._actionUtilitiesForTests(actor,nil,loneSnapshot,loneTarget,
    heavyRecord,nil,commands,heavyReady)
check(heavyChoices[1].kind=="melee",
    "a ready heavy weapon can win the normal strike choice outside the open-ground allowance")
actor.endurance=0.91
local farSnapshot={threats={},allies={},escapeSquares={{square=actor.square,danger=0}},
    immediateCount=0,closeThreatCount=0,occupiedThreatSectors=0,pressure=0}
check(not SC.Combat.assessOverrun(actor,farSnapshot,heavyRecord,commands).overrun,
    "91-percent stamina and no close contacts cannot sustain full withdrawal from weapon cost")
actor.endurance=0.55
local tiredHeavy=read(heavy)
check(tiredHeavy.staminaCritical and SC.Combat.assessOverrun(actor,loneSnapshot,
    heavyRecord,commands).overrun,"heavy-tool exhaustion still triggers withdrawal at its real reserve")
actor.endurance=1
WeaponCategory=nil
check(read(legacy).combatSkill==6,"missing category registry retains legacy compatibility")
SC_TEST_REPORT=(SC_TEST_REPORT and SC_TEST_REPORT .. "\n" or "")
    .. "MELEE_WEAPON_READINESS_PASS checks=" .. checks
