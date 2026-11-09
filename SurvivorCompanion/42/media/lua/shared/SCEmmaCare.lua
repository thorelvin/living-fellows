-- SPDX-License-Identifier: MIT
-- Text only. No native actors, logging, networking or world polling.
require "SCEmmaCareData"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaCare = SC.EmmaCare or {}
local Care = SC.EmmaCare
local contractions = { im="i am", ive="i have", dont="do not", cant="can not", cannot="can not",
    wont="will not", couldnt="could not", isnt="is not", wanna="want to",
    gonna="going to", whats="what is", theres="there is", idk="i do not know", kms="kill myself",
    wasnt="was not", werent="were not", wouldnt="would not", didnt="did not", shouldnt="should not" }
local excluded = { ["see a future"]=true, ["will not need it"]=true, ["take them all"]=true,
    ["not worth it"]=true, ["end it"]=true, ["if i died"]=true, ["if i was gone"]=true,
    ["if i were gone"]=true, ["tired of fighting"]=true, ["want out"]=true,
    ["thinking about ending"]=true,["think about ending"]=true,["will not be around"]=true,
    ["too many pills"]=true }

local function distance(a,b)
    if a==b then return 0 end
    if math.abs(#a-#b)>1 then return 2 end
    if #a==#b then
        local bad={}; for i=1,#a do if a:sub(i,i)~=b:sub(i,i) then bad[#bad+1]=i end end
        if #bad==1 then return 1 end
        if #bad==2 and bad[2]==bad[1]+1 and a:sub(bad[1],bad[1])==b:sub(bad[2],bad[2])
            and a:sub(bad[2],bad[2])==b:sub(bad[1],bad[1]) then return 1 end
        return 2
    end
    if #a>#b then a,b=b,a end
    for i=1,#b do if b:sub(1,i-1)..b:sub(i+1)==a then return 1 end end
    return 2
end
Care.distance=distance
local function near(a,b)
    if a==b then return true end
    if #b<4 or #a<3 or a:sub(1,1)~=b:sub(1,1) then return false end
    if SC.EmmaUnderstand and SC.EmmaUnderstand.known(a) then return false end
    return distance(a,b)==1
end
function Care.tokens(raw)
    local text=tostring(raw or ""):sub(1,512):lower():gsub("\226\128\153", "'"):gsub("'","")
    local out={}
    for word in text:gmatch("[%a%d]+") do
        local expanded=contractions[word]
        if not expanded then
            for key,value in pairs(contractions) do
                if #key>=4 and near(word,key) then expanded=value; break end
            end
        end
        if expanded then for part in expanded:gmatch("%S+") do out[#out+1]=part end
        else out[#out+1]=word end
        if #out>=80 then break end
    end
    return out
end
local phrases={}
local function matches(tokens,phrase)
    local words=phrases[phrase]
    if not words then words=Care.tokens(phrase); phrases[phrase]=words end
    for at=1,#tokens-#words+1 do
        local okay=true
        for k,word in ipairs(words) do if not near(tokens[at+k-1],word) then okay=false; break end end
        if okay then return true end
    end
    return false
end
local function any(tokens,list)
    for _,phrase in ipairs(list or {}) do if matches(tokens,phrase) then return true end end
    return false
end
function Care.selfWorth(raw)
    return any(Care.tokens(raw),SC.EmmaCareData.SELF_WORTH_PHRASES)
end
local function concept(tokens)
    local c=SC.EmmaCareData.CONCEPTS
    if not c then return false end
    local self=any(tokens,c.self)
    if not self then return false end
    local compact={}
    for _,word in ipairs(tokens) do if word~="just" and word~="could" then compact[#compact+1]=word end end
    local desire=any(compact,{"want","wish","rather","planning","ready to","thinking about",
        "think about","feel like","better if","easier if","happier if","tired of","sick of"})
    local ending=any(compact,{"me to die","i died","i die","i disappeared","i was dead","i were dead",
        "my life to end","stop living","stop existing","i did not exist","i was not alive","i were not alive"})
    if desire and ending then return true end
    if any(tokens,{"tired of being alive","sick of being alive"}) then return true end
    -- Indirect hints need an actual reference to the operator disappearing or
    -- dying, not a missing tool, a dying generator or a hopeful future.
    if any(tokens,{"notice if i","miss me if i","care if i","better if i"})
        and any(tokens,{"i disappeared","i was gone","i died","i die"}) then return true end
    return any(tokens,{"no point","no reason","not worth"})
        and any(tokens,{"being alive","keep living","my life","to live","keep going"})
        and not any(tokens,{"expedition","job","shift","scan","call","radio","game","base"})
end
function Care.assess(raw)
    local tokens=Care.tokens(raw)
    local joined=" "..table.concat(tokens," ").." "
    if joined:find(" i do not want to die ",1,true) or joined:find(" cut myself shaving ",1,true)
        or matches(tokens,"cut myself") and any(tokens,{"accidentally","while cooking","on broken glass"}) then return "comfort" end
    local data=SC.EmmaCareData
    for word in pairs(data.CARE_WORDS) do
        if matches(tokens,word) and not (word=="suicide" and matches(tokens,"suicide squad")) then return "care" end
    end
    for _,phrase in ipairs(data.CARE_PHRASES) do
        if not excluded[phrase] and matches(tokens,phrase) then return "care" end
    end
    if any(tokens,data.SELF_WORTH_PHRASES) then return "comfort" end
    local whole=joined:match("^%s*emma%s+(.-)%s*$") or joined:match("^%s*(.-)%s*$")
    local wholeTokens=Care.tokens(whole)
    for _,phrase in ipairs(data.CARE_WHOLE) do
        if #wholeTokens==#Care.tokens(phrase) and matches(wholeTokens,phrase) then return "care" end
    end
    if any(tokens,{"i do not see a future","life is not worth it","i want out of life",
        "i took too many pills","i have taken too many pills","do not want to exist",
        "nobody cares whether i live","no one cares whether i live"}) then return "care" end
    if any(tokens,{"pills","medicine","medication"}) and any(tokens,{"take them all","take all of them"})
        and any(tokens,{"i want","i plan","i am going"}) then return "care" end
    if matches(tokens,"end it") and any(tokens,{"should i","i should","i want","i am going to"})
        and not any(tokens,{"expedition","job","shift","scan","call","radio","story","game","argument"}) then return "care" end
    -- Indirect language needs both a self reference and an actual wish/loss of
    -- hope. Resource statements and ordinary reports of danger are not wishes.
    local self=joined:find(" i ",1,true) or joined:find(" me ",1,true) or joined:find(" myself ",1,true)
    local marker=matches(tokens,"want") or matches(tokens,"wish") or matches(tokens,"thinking")
        or matches(tokens,"planning") or matches(tokens,"feel like") or matches(tokens,"no reason")
        or matches(tokens,"pointless") or matches(tokens,"would be better")
    local ending=matches(tokens,"stop living") or matches(tokens,"not alive") or matches(tokens,"not exist")
        or matches(tokens,"ending my life") or matches(tokens,"everything to end")
        or matches(tokens,"end it tonight") or matches(tokens,"i just disappeared")
        or matches(tokens,"being alive") and (matches(tokens,"point") or matches(tokens,"not worth"))
        or matches(tokens,"whether i live") or matches(tokens,"dying every day")
    if self and marker and ending then return "care" end
    if concept(tokens) then return "care" end
    for _,phrase in ipairs(data.COMFORT_PHRASES) do
        if phrase~="i lost my" and phrase~="i miss my" and phrase~="i give up" and matches(tokens,phrase) then return "comfort" end
    end
    if #wholeTokens==3 and matches(wholeTokens,"i give up") then return "comfort" end
    local person=joined:find(" wife ",1,true) or joined:find(" husband ",1,true) or joined:find(" parents ",1,true)
        or joined:find(" family ",1,true) or joined:find(" brother ",1,true) or joined:find(" sister ",1,true)
        or joined:find(" friend ",1,true) or joined:find(" kids ",1,true) or joined:find(" daughter ",1,true)
        or joined:find(" son ",1,true) or joined:find(" dog ",1,true) or joined:find(" cat ",1,true)
    if person and (matches(tokens,"miss") or matches(tokens,"lost") or matches(tokens,"died")
        or matches(tokens,"did not make it") or matches(tokens,"thinking about")) then return "comfort" end
    local k=data.COMFORT_CONCEPTS
    if k and any(tokens,k.who) and any(tokens,k.loss) then return "comfort" end
    if k and (any(tokens,k.strong) or self and any(tokens,k.feeling)) then return "comfort" end
end

function Care.quiet(session) return session and (session.careMode==true or session.careCheckin
    or (session.comfortTurns or 0)>0) end
function Care.reset(session)
    if not session then return end
    session.careMode,session.careQuestion,session.careCheckin=nil,nil,nil
    session.comfortTurns,session.comfortKind,session.carePicks=nil,nil,nil
    session.emmaLogPrevious=nil
end
local dataIntents={status=true,food=true,storage=true,people_list=true,people_hurt=true,people_mood=true,
    person=true,jobs=true,blocked=true,skills=true,shortages=true,alarms=true,deliveries=true,
    expedition=true,power=true,weather=true,time=true,date=true,math=true,guide=true,survival=true,
      notes=true,recall=true,help=true,conversation_history=true,more=true,followup_clarify=true,
      me_status=true,me_need=true,me_infected=true,me_look=true,me_kills=true,me_survived=true,
      me_where=true,me_skills=true,me_file=true,helicopter=true,water_off=true,power_off=true,
      forecast=true,daylight=true,calendar=true}
local function pool(session,key)
    local choices=SC.EmmaCareData.pools[key] or SC.EmmaCareData.pools.care_more
    session.carePicks=session.carePicks or {}
    local index=(session.carePicks[key] or 0)%#choices+1; session.carePicks[key]=index
    local selected=choices[index]
    return type(selected)=="table" and selected or { selected }
end
local function reply(session,key)
    local lines={}
    for _,line in ipairs(pool(session,key)) do
        lines[#lines+1]=line:gsub("{name}",function() return tostring(session.operator or "operator") end)
    end
    return {intent="care",category="care",lines=lines,thinkMs=0,private=true}
end
function Care.respond(session,raw,intent,locked)
    local assessment=Care.assess(raw)
    local worth=Care.selfWorth(raw)
    if intent=="care" or intent=="comfort" then assessment=assessment or intent end
    if assessment=="care" then
        local first=session.careMode~=true
        session.careMode=true; session.context=session.context or {}
        session.context.pending,session.context.personChoices=nil,nil
        local result=reply(session,worth and "care_worth" or first and "care" or "care_more")
        result.careDetected=true
        if first then
            result.support=SC.EmmaCareData.NOTE
            session.careQuestion=true
            local question=pool(session,"care_ask")[1]
            result.lines[#result.lines+1]=question
        end
        return result
    end
    local normalized=table.concat(Care.tokens(raw)," ")
    if session.careCheckin then
        if normalized=="yes" or normalized=="y" or normalized=="no" or normalized=="n" then
            session.careCheckin=nil
            return reply(session,(normalized=="yes" or normalized=="y") and "care_checkin_yes" or "care_checkin_no")
        elseif normalized=="maybe" or normalized=="i do not know" or normalized=="not sure" then
            session.careCheckin=nil
            return {intent="care",category="care",thinkMs=0,private=true,lines={
                "It is all right not to have an answer. You can still reach out to someone you trust today."}}
        end
        -- An unrelated question is not an answer to the check-in.
        if locked or not dataIntents[intent] then return reply(session,"care_more") end
        return nil
    end
    if session.careMode then
        if session.careQuestion then
            if normalized=="no" or normalized=="n" or normalized=="nope" or normalized=="not really"
                or normalized=="i am not" then
                session.careQuestion=nil; return reply(session,"care_ask_no")
            elseif normalized=="yes" or normalized=="y" then
                session.careQuestion=nil; return reply(session,"care_ask_yes")
            elseif normalized=="maybe" or normalized=="i do not know" or normalized=="not sure" then
                session.careQuestion=nil
                return {intent="care",category="care",thinkMs=0,private=true,lines={
                    "Thank you for telling me. You do not have to work this out alone.",
                    "If you might act on these thoughts, seek urgent help now. Please reach out to someone you trust today."}}
            end
        end
        if not locked and dataIntents[intent] then return nil end
        if intent=="exit" or normalized=="goodbye" or normalized=="bye" then
            local result=reply(session,"care_bye"); result.command="close"; return result
        end
        return reply(session,worth and "care_worth" or intent=="hello" and "care_hello"
            or intent=="thanks" and "care_thanks" or "care_more")
    end
    if assessment=="comfort" then
        session.comfortTurns=4
        session.comfortKind=worth and "worth" or normalized:find("shaving",1,true) and "injury"
            or normalized:find("do not want to die",1,true) and "fear" or nil
        local k=SC.EmmaCareData.COMFORT_CONCEPTS
        if not session.comfortKind and k and not (any(Care.tokens(raw),k.who) and any(Care.tokens(raw),k.loss)) then
            session.comfortKind="support"
        end
    end
    if (session.comfortTurns or 0)>0 and (assessment=="comfort" or not dataIntents[intent]) then
        session.comfortTurns=session.comfortTurns-1
        local result=reply(session,session.comfortKind=="worth" and "care_worth" or "comfort"); result.intent="comfort"
        if session.comfortKind=="injury" then result.lines={"That sounds painful. Check the wound and use a clean dressing. Ask about first aid if you need the steps."}
        elseif session.comfortKind=="fear" then result.lines={"That sounds frightening. Get somewhere safe, and tell someone you trust how you are feeling. You do not have to face this alone."} end
        if session.comfortKind=="support" then result.lines={"I am glad you told me. You do not have to carry that alone. Talk to someone you trust today."} end
        return result
    end
end

function Care.checkin(session)
    session.careCheckin=true
    return reply(session,"care_checkin")
end

return Care
