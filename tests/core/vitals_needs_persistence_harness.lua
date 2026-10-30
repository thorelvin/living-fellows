-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,"vitals needs "..checks..": "..message)
end
CharacterStat.FATIGUE={name="FATIGUE"}
local function actor(fatigue,endurance)
    local values={HUNGER=0.27,THIRST=0.38,FATIGUE=fatigue,ENDURANCE=endurance}
    local stats={values=values}
    function stats:get(stat) return self.values[stat.name] end
    function stats:set(stat,value)
        if self.throw==stat.name then error("injected native stat failure") end
        if self.ignore~=stat.name then self.values[stat.name]=value end
    end
    local body={health=100,infected=false,time=-1,mortality=-1}
    function body:getBodyParts() return {size=function() return 0 end,get=function() end} end
    function body:getOverallBodyHealth() return self.health end
    function body:setOverallBodyHealth(value) self.health=value end
    function body:isInfected() return self.infected end
    function body:setInfected(value) self.infected=value end
    function body:getInfectionTime() return self.time end
    function body:setInfectionTime(value) self.time=value end
    function body:getInfectionMortalityDuration() return self.mortality end
    function body:setInfectionMortalityDuration(value) self.mortality=value end
    local value={health=100,stats=stats}
    function value:getBodyDamage() return body end
    function value:getStats() return self.stats end
    function value:getHealth() return self.health end
    function value:setHealth(amount) self.health=amount end
    return value
end
local function near(left,right) return type(left)=="number" and math.abs(left-right)<0.0001 end
for _,fatigue in ipairs({0,0.46,0.83,1}) do
    local current=actor(fatigue,0.23)
    for cycle=1,3 do
        local saved=SC.Vitals.capture(current)
        check(saved and near(saved.fatigue,fatigue) and near(saved.endurance,0.23),
            "capture retains tiredness and stamina, including zero/100%, cycle "..cycle)
        local persisted,reason=SC.StableValue.copyStrict(saved,{maxDepth=8,maxEntries=256})
        check(persisted and not reason,"vitals remain plain serializable save data")
        current=actor(0,1)
        local okay,why=SC.Vitals.apply(current,persisted)
        check(okay and near(current.stats.values.FATIGUE,fatigue) and near(current.stats.values.ENDURANCE,0.23),
            "fresh actor restores exact pre-load needs: "..tostring(why))
    end
end
local rested=actor(0.91,0.12)
rested.stats.values.FATIGUE=0.19 rested.stats.values.ENDURANCE=0.86
local afterSleep=SC.Vitals.capture(rested)
local replacement=actor(0,1)
check(SC.Vitals.apply(replacement,afterSleep) and near(replacement.stats.values.FATIGUE,0.19)
    and near(replacement.stats.values.ENDURANCE,0.86),"the next save records recovery instead of replaying older exhaustion")
local legacy=SC.Vitals.capture(actor(0.9,0.2)) legacy.fatigue=nil legacy.endurance=nil
replacement=actor(0.31,0.64)
check(SC.Vitals.apply(replacement,legacy) and near(replacement.stats.values.FATIGUE,0.31)
    and near(replacement.stats.values.ENDURANCE,0.64),"older saves without these fields retain existing native defaults")
for _,name in ipairs({"FATIGUE","ENDURANCE"}) do
    replacement=actor(0,1) replacement.stats.ignore=name
    local okay,why=SC.Vitals.apply(replacement,afterSleep)
    check(not okay and tostring(why):find(name:lower(),1,true),"an ignored "..name.." setter cannot report successful restoration")
    replacement=actor(0,1) replacement.stats.throw=name
    check(not SC.Vitals.apply(replacement,afterSleep),"native "..name.." setter failure propagates to the restore transaction")
end
SC_TEST_REPORT="VITALS_NEEDS_PERSISTENCE_PASS checks="..checks
