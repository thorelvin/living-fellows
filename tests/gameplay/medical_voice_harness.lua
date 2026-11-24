-- SPDX-License-Identifier: MIT
-- Who speaks around a treatment, and the quality of the medical and needs
-- lines. Real pools, real Medical.treat; speech is recorded, not shown.
local SC=SurvivorCompanion
local M,D,U=SC.Medical,SC.Dialogue,SC.GameplayUtil
local P,MF=SC.TestMedicalProcedures,SC.TestMedicalMedicines
local checks=0
local function check(value,reason) checks=checks+1;assert(value,'medical voice '..checks..': '..reason) end

-- ---------------------------------------------------------------------------
-- Line quality
-- ---------------------------------------------------------------------------
local ROUGH={"damn","damned","dammit","goddamn","hell","shit","shitty","bullshit","fuck","fucking",
    "fucked","ass","asses","dumbass","bastard","bastards","bitch","christ"}
local STIFF={"i am","i will","i would","i have not","i do not","do not","does not","did not","is not",
    "are not","was not","cannot","will not","would not","could not","should not","have not","has not",
    "that is","it is","there is","we are","you are","we will","you will"}
local REPORT={"critical","deficit","cycle","impair","priority","immediately","functional","operational",
    "noticeable","fluids","calories","demanding"}
local STOCK={"hold still","keep still","keep breathing","sting"}
local NEED_WORDS={hungry=1,hunger=1,food=1,eat=1,eating=1,eaten=1,meal=1,starving=1,thirsty=1,
    thirst=1,water=1,drink=1,tired=1,sleep=1,rest=1,fatigue=1}
local function has(text,phrase)
    return string.find(string.lower(text),"%f[%a]"..phrase.."%f[%A]")~=nil
end
local function hasStem(text,stem) return string.find(string.lower(text),"%f[%a]"..stem)~=nil end
local function anyOf(text,list) for _,phrase in ipairs(list) do if has(text,phrase) then return phrase end end end
-- "Worse than it is." cannot contract; only a phrase that runs on into
-- another word can.
local function stiff(text)
    for _,phrase in ipairs(STIFF) do
        if string.find(string.lower(text),"%f[%a]"..phrase.." +%a") then return phrase end
    end
end
local function words(text) local n=0 for _ in string.gmatch(text,"%S+") do n=n+1 end return n end
local function ascii(text)
    for index=1,#text do local b=string.byte(text,index) if b<32 or b>126 then return false end end
    return true
end
local function shape(text)
    local parts={}
    for word in string.gmatch(string.lower(text),"[%a']+") do parts[#parts+1]=NEED_WORDS[word] and "x" or word end
    return table.concat(parts," ")
end
local function entries(pool)
    local result={}
    for bucket,rows in pairs(pool) do
        if type(rows)=="table" then
            for _,entry in ipairs(rows) do result[#result+1]={bucket=bucket,entry=entry} end
        end
    end
    return result
end
local PROCEDURES={["medical.remove_bullet"]=8,["medical.remove_glass"]=8,["medical.clean_burn"]=8,
    ["medical.disinfect"]=8,["medical.stitch"]=8,["medical.remove_stitches"]=8,["medical.remove_splint"]=6,
    ["medical.painkillers"]=8,["medical.antibiotics"]=8}
local pools=D._allPoolsForTests()
local seenLine,shapeKind,roughByNeed,linted={}, {}, {}, 0
for topic,pool in pairs(pools) do
    local family=string.match(topic,"^(medical)%.") or string.match(topic,"^(need)%.")
    if family then
        local stock=0
        for _,row in ipairs(entries(pool)) do
            local entry=row.entry
            local raw=type(entry)=="table" and entry[1] or entry
            local clean=type(entry)=="table" and entry.clean or nil
            check(type(raw)=="string" and (clean==nil or type(clean)=="string"),'malformed line in '..topic)
            linted=linted+1
            check(ascii(raw) and (clean==nil or ascii(clean)),'non-ASCII line in '..topic..': '..raw)
            check(words(raw)<=16,'line over 16 words in '..topic..': '..raw)
            local rough=anyOf(raw,ROUGH)
            check(not rough or (clean and not anyOf(clean,ROUGH)),'rough line without a clean twin in '..topic..': '..raw)
            check(not stiff(raw),'uncontracted, stiff line in '..topic..': '..raw)
            check(not seenLine[family..":"..raw],'line repeated across '..family..' pools: '..raw)
            seenLine[family..":"..raw]=true
            if anyOf(raw,STOCK) then stock=stock+1 end
            if family=="need" then
                local kind=string.match(topic,"^need%.(%a+)%.")
                for _,stem in ipairs(REPORT) do
                    check(not hasStem(raw,stem),'report-speak in '..topic..' ('..stem..'): '..raw)
                end
                local key=shape(raw)
                check(shapeKind[key]==nil or shapeKind[key]==kind,
                    'one sentence stamped across '..tostring(shapeKind[key])..' and '..kind..': '..raw)
                shapeKind[key]=kind
                if rough and clean then roughByNeed[kind]=true end
            end
        end
        if family=="medical" then
            check(stock<=1,'stock comfort phrase used '..stock..' times in '..topic)
        end
    end
end
check(linted>=400,'medical and needs pools were linted ('..linted..' lines)')
for _,kind in ipairs({"hunger","thirst","fatigue"}) do
    check(roughByNeed[kind],'needs keep the default rough voice for '..kind)
end
for topic,minimum in pairs(PROCEDURES) do
    local pool=pools[topic]
    check(type(pool)=="table" and type(pool.common)=="table" and #pool.common>=minimum,
        topic..' has at least '..minimum..' common lines')
    for _,voice in ipairs({"brave","cautious","caring","practical"}) do
        check(type(pool[voice])=="table" and #pool[voice]>=1,topic..' speaks in the '..voice..' voice')
    end
end

-- ---------------------------------------------------------------------------
-- Who says what
-- ---------------------------------------------------------------------------
local savedNative,savedService,savedMove,savedStop,savedSay=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop,D.say
-- Production always runs the staged animation: the medic speaks when it
-- starts and the patient answers when the verified result lands.
local visual='active'
SC.NativeActions={visualStatus=function() return visual end,clearVisual=function() end,cancelVisual=function() return true end}
SC.ActionSupervisor=nil
U.move=function() return true end;U.stop=function() return true end
local function treat(helper,patient)
    visual='active'
    local okay,why=M.treat(helper,patient)
    if not okay or not M.peek(helper) then return false,'animation did not start: '..tostring(why) end
    -- A procedure can continue into a fresh dressing; follow every stage.
    for _=1,6 do
        visual='completed'
        okay,why=M.treat(helper,patient)
        if not M.peek(helper) then return okay,why end
        visual='active'
        okay,why=M.treat(helper,patient)
        if not M.peek(helper) then return okay,why end
    end
    return false,'treatment never finished: '..tostring(why)
end
local said={}
D.say=function(actor,topic,specification,arguments,options)
    local line=D.choose(actor,topic,specification,arguments,options)
    said[#said+1]={actor=actor,topic=topic,line=line}
    return line~=nil,line
end
local function spoke(actor,topic)
    for _,row in ipairs(said) do if row.actor==actor and row.topic==topic and row.line then return true end end
    return false
end
local function trace()
    local parts={}
    for _,row in ipairs(said) do parts[#parts+1]=tostring(row.actor and row.actor.id)..'='..row.topic end
    return ' [said: '..table.concat(parts,', ')..']'
end
local function spokePrefix(actor,prefix)
    for _,row in ipairs(said) do
        if row.actor==actor and string.sub(row.topic,1,#prefix)==prefix then return row.topic end
    end
end
local function stitchable(part)
    function part:setStitched(enabled)
        if not enabled and not self.stitchFlag then return end
        if not enabled then
            self.removals=(self.removals or 0)+1
            if self:getStitchTime()<40 then self.deepTime=10;self.isBleeding=true else self.scratchTime=2 end
            self.stitchTime=0
        end
        self.stitchFlag=enabled
    end
    return part
end
local function medic(patient,items)
    local helper=P.actor({P.part({})},items or {})
    helper.square=patient.square
    return helper
end

do -- Taking out healed stitches is not a fresh wound.
    said={}
    local part=stitchable(P.part({stitchFlag=true,stitchTime=45}))
    local patient=P.actor({part},{})
    local helper=medic(patient)
    local okay,reason=treat(helper,patient)
    check(okay and reason=='stitches_removed' and part.removals==1,'helper removes ready stitches: '..tostring(reason))
    check(spoke(helper,'medical.remove_stitches'),'medic speaks stitch-removal lines'..trace())
    check(not spokePrefix(helper,'medical.bandage.'),'medic never calls healed stitches a fresh wound')
    check(spoke(patient,'medical.after.healed'),'patient answers as someone healed')
end
do -- A healed splint comes off with its own lines.
    said={}
    local part=P.part({splintFlag=true,splintFactor=1,splintItem='Base.Splint',fracture=0})
    local patient=P.actor({part},{})
    local helper=medic(patient)
    local okay,reason=treat(helper,patient)
    check(okay and reason=='splint_removed' and not part.splintFlag,'helper removes a healed splint: '..tostring(reason))
    check(spoke(helper,'medical.remove_splint') and not spokePrefix(helper,'medical.bandage.'),
        'medic speaks splint-removal lines, not bandage lines')
    check(spoke(patient,'medical.after.healed'),'patient answers the splint removal')
end
do -- Surgery: the medic works, the patient reacts to the procedure.
    said={}
    local part=P.part({glass=true})
    local patient=P.actor({part},{})
    local helper=medic(patient,{P.item('Base.Tweezers'),P.item('Base.Bandage')})
    local okay,reason=treat(helper,patient)
    check(okay and reason=='glass_removed','helper removes glass: '..tostring(reason))
    check(spoke(helper,'medical.remove_glass'),'medic speaks glass lines')
    check(spoke(patient,'medical.after.extraction') and not spoke(patient,'medical.thanks'),
        'patient reacts to the extraction rather than a generic thanks')
end
do -- A bandage still ends with ordinary thanks.
    said={}
    local part=P.part({isScratched=true,scratchTime=6,isBleeding=true})
    local patient=P.actor({part},{})
    local helper=medic(patient,{P.item('Base.Bandage')})
    local okay,reason=treat(helper,patient)
    check(okay and reason=='bandaged','helper bandages a scratch: '..tostring(reason))
    check(spokePrefix(helper,'medical.bandage.')~=nil,'medic speaks a bandage line')
    check(spoke(patient,'medical.thanks'),'patient thanks the medic after a bandage')
end
do -- Painkillers from a medic: the medic hands them over, the patient answers.
    said={}
    local patient=MF.actor(nil,{})
    local stock=MF.item('Base.Pills')
    local helper=MF.actor(nil,{stock});helper.square=patient.square;helper.moodles[MoodleType.PAIN]=0
    local okay,reason=treat(helper,patient)
    check(okay and reason=='painkillers_taken' and patient.pillCalls==1,'helper doses the patient: '..tostring(reason))
    check(spoke(helper,'medical.painkillers'),'medic speaks while handing over the pills')
    check(spoke(patient,'medical.painkillers.taken'),'patient answers in their own words')
    check(not spoke(patient,'medical.painkillers'),'patient never speaks the medic lines')
end
do -- Painkillers taken alone: no thanks to nobody.
    said={}
    local stock=MF.item('Base.Pills')
    local actor=MF.actor(nil,{stock})
    local okay,reason=treat(actor,actor)
    check(okay and reason=='painkillers_taken','companion doses themselves: '..tostring(reason))
    check(spoke(actor,'medical.painkillers.self'),'self dose uses self lines')
    check(not spoke(actor,'medical.painkillers') and not spoke(actor,'medical.painkillers.taken'),
        'self dose neither plays medic nor thanks anyone')
end
D.say=savedSay
SC.NativeActions,SC.ActionSupervisor,U.move,U.stop=savedNative,savedService,savedMove,savedStop
SC_TEST_REPORT='MEDICAL_VOICE_PASS checks='..checks
print(SC_TEST_REPORT)
