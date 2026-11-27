-- SPDX-License-Identifier: MIT
-- Real captureRecord and applySkills preserve native XP before the first level.
local SC=LivingFellows
local F,T=SC.TestMedicalMedicines,SC.TestFixture
local checks=0
local function check(value,reason) checks=checks+1;assert(value,"medical XP persistence "..checks..": "..reason) end
local previousFactory=PerkFactory
local previousFromString,previousMax,previousNone=Perks.FromString,Perks.MAX,Perks.None
local function perk(name)
    return {getId=function() return name end,getType=function(self) return self end}
end
local doctor,wood=perk("Doctor"),perk("Woodwork")
local known={Doctor=doctor,Woodwork=wood}
local maximum,none=perk("MAX"),perk("None")
Perks.MAX,Perks.None=maximum,none
Perks.FromString=function(name) return known[name] or maximum end
PerkFactory={PerkList={doctor,wood},getPerkFromName=function(name)
    return name=="First Aid" and doctor or name=="Carpentry" and wood or nil
end}
check(PerkFactory.getPerkFromName("Doctor")==nil and Perks.FromString("Doctor")==doctor,
    "fixture distinguishes canonical Doctor ID from native First Aid display name")
local function subject(points,infos)
    local actor=F.actor(nil,{})
    actor.skillPoints=points or {};actor.skillLevels={};actor.skillInfos=infos or {}
    function actor:getPerkList() return self.skillInfos end
    function actor:getPerkLevel(value)
        if self.rejectNativeLevelRead then error("native level read unavailable") end
        return self.skillLevels[value:getId()] or 0
    end
    function actor:setPerkLevelDebug(value,level)
        self.levelWrites=(self.levelWrites or 0)+1
        if self.rejectNativeLevelWrite then error("native level write unavailable") end
        if not self.noopNativeLevelWrite then self.skillLevels[value:getId()]=level end
    end
    local xp={}
    function xp:getXP(value)
        if actor.rejectXpRead then error("native XP read unavailable") end
        return actor.skillPoints[value:getId()] or 0
    end
    function xp:setXPToLevel(value,level)
        if actor.rejectLevelRestore then error("native level restore unavailable") end
        local name=value:getId()
        actor.skillPoints[name]=level*75
    end
    function xp:AddXPNoMultiplier()
        actor.oldXpCalls=(actor.oldXpCalls or 0)+1
        -- The installed short helper delegates to the local-player-only path.
    end
    function xp:AddXP(value,amount,first,multipliers,third,halo)
        actor.xpCalls=(actor.xpCalls or 0)+1
        check(first==true and multipliers==false and third==false and halo==false,
            "saved remainder uses six native arguments with all multipliers and halo disabled")
        if actor.rejectXpAdd then error("native XP add unavailable") end
        if actor.noopXpAdd then return end
        -- A non-default multiplier makes accidentally enabled learning visibly
        -- wrong; restore must copy the earned value rather than award it again.
        local awarded=multipliers and amount*7 or amount
        local name=value:getId();actor.skillPoints[name]=(actor.skillPoints[name] or 0)+awarded
    end
    function actor:getXp() return xp end
    return actor,T.registry[actor.id]
end
local function captured(actor,record)
    local saved,why=SC.Persistence.captureRecord(record)
    check(saved~=nil,"actual save capture accepts native skill facts: "..tostring(why))
    return saved
end
for _,points in ipairs({75,75.25}) do
    local actor,record=subject({Doctor=points},{{perk=doctor}})
    actor.skillLevels.Doctor=1
    local saved=captured(actor,record)
    local restored=subject({})
    check(restored:getPerkLevel(doctor)==0,"fresh actor starts below the saved earned Doctor level")
    check(SC.Persistence._applySkillsForTests(restored,saved.skills) and restored:getPerkLevel(doctor)==1
        and restored.skillPoints.Doctor==points and restored.levelWrites==1,
        "earned Doctor level and exact XP survive capture/restore at and above the first-level boundary")
    check(SC.Persistence._applySkillsForTests(restored,saved.skills) and restored:getPerkLevel(doctor)==1
        and restored.skillPoints.Doctor==points and restored.levelWrites==1,
        "second restore retains the earned level and never doubles its XP remainder")
end
do
    local actor,record=subject({Doctor=3.75})
    check(#actor:getPerkList()==0 and actor:getPerkLevel(doctor)==0,"level-zero Doctor has no native PerkInfo before capture")
    local saved=captured(actor,record)
    check(#saved.skills==1 and saved.skills[1].id=="Doctor" and saved.skills[1].level==0 and saved.skills[1].xp==3.75,
        "positive native Doctor XP is captured before the first native level")
    local restored=subject({})
    check(SC.Persistence._applySkillsForTests(restored,saved.skills) and restored.skillPoints.Doctor==3.75
        and restored:getPerkLevel(doctor)==0 and restored.xpCalls==1 and not restored.oldXpCalls,
        "nonlocal remainder restores exactly through the supported overload without reapplying learning multipliers")
    check(SC.Persistence._applySkillsForTests(restored,saved.skills) and restored.skillPoints.Doctor==3.75 and restored.xpCalls==2,
        "repeated restore starts from saved level and never doubles the earned remainder")
end
do
    local actor,record=subject({Doctor=83.75,Woodwork=2.25},{{perk=doctor},{perk=doctor}})
    actor.skillLevels.Doctor=1
    local saved=captured(actor,record)
    local doctorCount,woodCount=0,0
    for _,entry in ipairs(saved.skills) do
        if entry.id=="Doctor" then doctorCount=doctorCount+1;check(entry.level==1 and entry.xp==83.75,"existing learned Doctor facts remain unchanged") end
        if entry.id=="Woodwork" then woodCount=woodCount+1;check(entry.level==0 and entry.xp==2.25,"other positive native level-zero progress uses the same schema") end
    end
    check(doctorCount==1 and woodCount==1 and #saved.skills==2,"actor and registry scans never duplicate skill identifiers")
end
do
    local actor,record=subject({Doctor=0,Woodwork=-1})
    check(#captured(actor,record).skills==0,"empty and negative unlisted skill values do not invent learned records")
end
do
    local registry={}
    local points={}
    for index=1,130 do local name="Skill"..index;registry[index]=perk(name);points[name]=1 end
    local old=PerkFactory.PerkList;PerkFactory.PerkList=registry
    local actor,record=subject(points)
    check(#captured(actor,record).skills==128,"positive registry discovery preserves the existing 128-record bound")
    PerkFactory.PerkList=old
end
for _,mode in ipairs({"rejectLevelRestore","rejectXpRead","rejectXpAdd","noopXpAdd"}) do
    local actor=subject({})
    actor[mode]=true
    local okay,why=SC.Persistence._applySkillsForTests(actor,{{id="Doctor",level=0,xp=3.75}})
    check(not okay and type(why)=="string",mode.." refuses a falsely successful native skill restore")
end
for _,mode in ipairs({"rejectNativeLevelRead","rejectNativeLevelWrite","noopNativeLevelWrite"}) do
    local actor=subject({})
    actor[mode]=true
    local okay,why=SC.Persistence._applySkillsForTests(actor,{{id="Doctor",level=1,xp=75.25}})
    check(not okay and type(why)=="string" and not actor.xpCalls,
        mode.." cannot report an earned native level restored or award a remainder")
end
for _,name in ipairs({"UnknownFutureSkill","MAX","None"}) do
    local actor=subject({})
    local okay,why=SC.Persistence._applySkillsForTests(actor,{{id=name,level=0,xp=3.75}})
    check(not okay and type(why)=="string" and not actor.xpCalls,
        "unknown ID or native sentinel is refused before any XP award: "..name)
end
do
    local actor=subject({})
    local resolve=Perks.FromString
    Perks.FromString=function() return wood end
    local okay=SC.Persistence._applySkillsForTests(actor,{{id="Doctor",level=0,xp=3.75}})
    check(not okay and not actor.xpCalls and actor.skillLevels.Woodwork==nil,
        "returned canonical perk identity must exactly match the saved skill ID")
    Perks.FromString=resolve
end
PerkFactory=previousFactory
Perks.FromString,Perks.MAX,Perks.None=previousFromString,previousMax,previousNone
SC_TEST_REPORT="MEDICAL_XP_PERSISTENCE_PASS checks="..checks
print(SC_TEST_REPORT)
