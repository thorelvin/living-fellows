-- SPDX-License-Identifier: MIT
-- Bounded snapshots of the actual operator. No mutation, event hook or cache.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local B={} SC.EmmaBody=B
local function call(object,key,...)
    if not object then return nil end
    local okay,value=pcall(function(...) return object[key](object,...) end,...)
    if okay then return value end
end
local function number(value,lo,hi)
    local n=tonumber(value)
    if n and n==n and n>=lo and n<=hi then return n end
end
local function text(value,limit)
    return type(value)=="string" and value:sub(1,240):gsub("[%c{}]"," "):sub(1,limit or 80) or nil
end
local function primary(player)
    return player and call(player,"isDead")~=true
        and (type(getSpecificPlayer)~="function" or getSpecificPlayer(0)==player)
end
local function list(value,limit)
    if not value then return {},false end
    local size=number(call(value,"size"),0,100000)
    if not size and type(value)=="table" then size=#value end
    if not size then return {},false end
    local rows={}
    for index=0,math.min(size,limit)-1 do
        local row=call(value,"get",index)
        if row==nil and type(value)=="table" then row=value[index+1] end
        if row then rows[#rows+1]=row end
    end
    return rows,size<=limit and #rows==size
end
local parts={Hand_L="left hand",Hand_R="right hand",ForeArm_L="left forearm",ForeArm_R="right forearm",
    UpperArm_L="left upper arm",UpperArm_R="right upper arm",Torso_Upper="upper torso",Torso_Lower="lower torso",
    Head="head",Neck="neck",Groin="groin",UpperLeg_L="left thigh",UpperLeg_R="right thigh",
    LowerLeg_L="left shin",LowerLeg_R="right shin",Foot_L="left foot",Foot_R="right foot"}
B.MOODLES={
    {"BLEEDING","bleeding",99},{"ZOMBIE","zombie",98},{"HYPOTHERMIA","cold",97},{"HYPERTHERMIA","hot",96},
    {"SICK","sick",95},{"THIRST","thirsty",94},{"HUNGRY","hungry",93},{"ENDURANCE","winded",92},
    {"TIRED","tired",91},{"PAIN","pain",90},{"INJURED","injured",89},{"DRUNK","drunk",88},
    {"WINDCHILL","windchill",87},{"HAS_A_COLD","cold_illness",86},{"NOXIOUS_SMELL","smell",85},
    {"PANIC","panic",84},{"STRESS","stress",83},{"UNHAPPY","unhappy",82},{"HEAVY_LOAD","heavy",81},
    {"WET","wet",80},{"ANGRY","angry",79},{"BORED","bored",78},{"CANT_SPRINT","cant_sprint",77},
    {"UNCOMFORTABLE","uncomfortable",76},
}
function B.read(player,mode)
    if not primary(player) then return nil end
    local body=call(player,"getBodyDamage")
    if not body or call(body,"getParentChar") and call(body,"getParentChar")~=player then return nil end
    local infected=call(body,"IsInfected")
    if type(infected)~="boolean" then infected=call(body,"isInfected") end
    local fake=call(body,"IsFakeInfected")
    local result={fake=fake==true,
        infectionKnown=type(infected)=="boolean",health=number(call(body,"getHealth"),0,100),wounds={},needs={}}
    -- Lua's false-and-nil idiom cannot retain a confirmed negative reading.
    if type(infected)=="boolean" then result.infected=infected end
    result.infectionTime=number(call(body,"getInfectionTime"),0,10000000)
    result.infectionDuration=number(call(body,"getInfectionMortalityDuration"),0,10000000)
    result.hoursSurvived=number(call(player,"getHoursSurvived"),0,10000000)
    local options=type(getSandboxOptions)=="function" and getSandboxOptions()
    result.mortality=number(call(call(options,"getOptionByName","ZombieLore.Mortality"),"getValue"),1,7)
    if result.mortality==nil then
        result.mortality=SandboxVars and SandboxVars.ZombieLore and number(SandboxVars.ZombieLore.Mortality,1,7)
    end
    if mode=="infection" then return result end
    local moodles=call(player,"getMoodles")
    result.needsComplete=moodles~=nil
    for _,spec in ipairs(B.MOODLES) do
        local kind=MoodleType and MoodleType[spec[1]]
        local level=kind and number(call(moodles,"getMoodleLevel",kind),0,4)
        if not level or level~=math.floor(level) then result.needsComplete=false
        else
            local row={kind=spec[2],level=level,priority=spec[3],label=text(call(moodles,"getMoodleDisplayString",kind),100)}
            if level>0 then result.needs[#result.needs+1]=row end
        end
    end
    table.sort(result.needs,function(a,b) return a.level==b.level and a.priority>b.priority or a.level>b.level end)
    if mode=="need" then return result end
    local rows,complete=list(call(body,"getBodyParts"),32)
    result.woundsComplete=complete and #rows>0
    for index,part in ipairs(rows) do
        local id=tostring(call(part,"getType") or "")
        local name=parts[id] or text(call(body,"getBodyPartName",index-1),80) or "unidentified body part"
        local flags={}
        for key,method in pairs({bite="bitten",scratch="scratched",cut="isCut",deep="isDeepWounded",
            bleeding="bleeding",burn="isBurnt",glass="haveGlass",bullet="haveBullet",bandaged="bandaged",
            dirty="isBandageDirty",festering="isInfectedWound"}) do
            local value=call(part,method)
            if type(value)~="boolean" then result.woundsComplete=false else flags[key]=value end
        end
        local fracture=number(call(part,"getFractureTime"),0,10000000)
        if fracture==nil then result.woundsComplete=false end
        flags.fracture=fracture and fracture>0 or false
        local rank=flags.bleeding and not flags.bandaged and 100 or flags.deep and 90 or flags.fracture and 89
            or (flags.glass or flags.bullet) and 88 or flags.burn and 80 or flags.festering and 75
            or flags.bandaged and flags.dirty and 74 or flags.bite and 70 or flags.cut and 65 or flags.scratch and 60
        if rank then
            flags.part,flags.rank,flags.index=name,rank,index
            result.wounds[#result.wounds+1]=flags
        end
    end
    table.sort(result.wounds,function(a,b) return a.rank==b.rank and a.index<b.index or a.rank>b.rank end)
    return result
end
local function place(player)
    local square=call(player,"getSquare")
    if not square then return nil end
    local room=call(square,"getRoom")
    local kind=room and SC.TerminalFiles and SC.TerminalFiles.classify(call(room,"getName"))
    local names={home="a house",clinic="a clinic",pharmacy="a pharmacy",research="a laboratory",police="a police building",
        emergency="an emergency-services building",security="a security office",military="a military building",
        government="a government building",media="a broadcasting building",education="an educational building",
        grocery="a food shop",hardware="a hardware shop",retail="a shop",restaurant="a restaurant",cafe="a cafe",
        bank="a bank",industry="an industrial building",mechanic="a workshop",fuel="a fuel station",office="an office"}
    local town=SC.NicknameLife and SC.NicknameLife.townAt and SC.NicknameLife.townAt(call(square,"getX"),call(square,"getY"))
    local location=room and (names[kind] or "a building") or "an outdoor location"
    return location..(type(town)=="string" and " in "..town or " outside my town records")
end
function B.file(player,mode)
    if not primary(player) then return nil end
    local result={}
    if mode=="me_kills" or mode=="me_file" then result.kills=number(call(player,"getZombieKills"),0,1000000000) end
    if mode=="me_survived" or mode=="me_look" or mode=="me_file" then
        result.hours=number(call(player,"getHoursSurvived"),0,10000000)
    end
    if mode=="me_where" or mode=="me_file" then result.place=place(player) end
    if mode=="me_file" then
        local descriptor=call(player,"getDescriptor")
        result.name=text((call(descriptor,"getForename") or "").." "..(call(descriptor,"getSurname") or ""),80)
        local traits=call(player,"getCharacterTraits")
        local rows,complete=list(call(traits,"getKnownTraits"),64)
        result.traits,result.traitsComplete={},complete
        for _,trait in ipairs(rows) do
            if call(traits,"get",trait)==true then
                local name=text(call(trait,"getName"),60)
                if name then result.traits[#result.traits+1]=name end
                if #result.traits>=8 then break end
            end
        end
    end
    if mode=="me_skills" or mode=="me_file" then
        result.skills={}
        local rows,complete=list(PerkFactory and PerkFactory.PerkList,128)
        result.skillsComplete=complete and #rows>0
        if #rows==0 then
            for _,spec in ipairs(SC.TerminalWorld and SC.TerminalWorld.SKILLS or {}) do
                local perk=Perks and Perks[spec[1]]
                if perk then rows[#rows+1]=perk end
            end
        end
        for _,perk in ipairs(rows) do
            local level=number(call(player,"getPerkLevel",perk),0,10)
            local name=text(call(perk,"getName"),60)
            if level and name and level>0 then result.skills[#result.skills+1]={name=name,level=math.floor(level)} end
        end
        table.sort(result.skills,function(a,b) return a.level==b.level and a.name<b.name or a.level>b.level end)
        while #result.skills>3 do table.remove(result.skills) end
    end
    return result
end
return B
