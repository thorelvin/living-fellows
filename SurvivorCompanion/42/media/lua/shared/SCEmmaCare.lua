-- SPDX-License-Identifier: MIT
-- Text only. No native actors, logging, networking or world polling.
require "SCEmmaCareData"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaCare = SC.EmmaCare or {}
local Care = SC.EmmaCare
local contractions = { im="i am", ive="i have", id="i would", dont="do not", cant="can not", cannot="can not",
    wont="will not", couldnt="could not", isnt="is not", wanna="want to",
    gonna="going to", whats="what is", theres="there is", idk="i do not know", kms="kill myself",
    wasnt="was not", werent="were not", wouldnt="would not", didnt="did not", shouldnt="should not",
    hasnt="has not", havent="have not" }
local excluded = { ["see a future"]=true, ["will not need it"]=true, ["take them all"]=true,
    ["not worth it"]=true, ["end it"]=true, ["if i died"]=true, ["if i was gone"]=true,
    ["if i were gone"]=true, ["tired of fighting"]=true, ["want out"]=true,
    ["thinking about ending"]=true,["think about ending"]=true,["will not be around"]=true,
    ["too many pills"]=true,["jump off"]=true,["miss me if"]=true }

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
local function matches(tokens,phrase,from,exact)
    local words=phrases[phrase]
    if not words then words=Care.tokens(phrase); phrases[phrase]=words end
    for at=from or 1,#tokens-#words+1 do
        local okay=true
        for k,word in ipairs(words) do
            if tokens[at+k-1]~=word and (exact or not near(tokens[at+k-1],word)) then okay=false; break end
        end
        if okay then return at,at+#words-1 end
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
-- Match related concepts in order, with bounded gaps. Every first occurrence
-- is considered, so a longer message's first "I" cannot hide a later clause.
local function ordered(tokens,groups,gap)
    local start=1
    while start<=#tokens do
        local cursor,first,okay=start,nil,true
        for index,group in ipairs(groups) do
            local best,finish
            for _,phrase in ipairs(group) do
                local at,last=matches(tokens,phrase,cursor)
                if at and (not best or at<best) then best,finish=at,last end
            end
            if index==1 then first=best end
            if not best or index>1 and best-cursor>(gap or 6) then okay=false;break end
            cursor=finish+1
        end
        if okay then return true end
        if not first then return false end
        start=first+1
    end
    return false
end
local tasks={"expedition","job","shift","scan","call","radio","game","base"}
local selfWords={"i","me","my","myself"}
local plans={"i am going to","i will","i want to","i plan to","i am planning to","i am ready to","i feel like",
    "thinking about","think about","considering"}
local thoughts={"thinking about","think about","thoughts about","picturing","imagining"}
local ownEnding={"i died","i die","i disappeared","i was dead","i were dead","i was gone","i were gone","i am gone",
    "i did not exist","i was not alive","i were not alive","i was not around","i were not around","i was not here"}
local continuation={"going on","go on","keep going","carrying on","carry on","living","being alive","to live"}
local means={"pills","rope","gun","razor"}
local ordinaryPurpose={"for my headache","for a headache","for pain","to shave","for climbing","for repairs",
    "to fight zombies","to shoot zombies","for hunting","to tie","for the fence","for first aid"}
local rules={
    {id="absence",test=function(t)
        return any(t,ownEnding) and (ordered(t,{{"would be","might be","will be"},
            {"happier","relieved","better","glad","easier"},{"if i","when i"}},8)
            or ordered(t,{{"notice","miss me","care"},{"if i","when i"}},4))
    end},
    {id="ending_plan",test=function(t)
        return any(t,selfWords) and ordered(t,{plans,{"end things","ending things","end everything","ending everything","end it all","ending it all",
            "end my life","ending my life"}},5)
            and not any(t,tasks)
    end},
    {id="continuation",implicit=true,test=function(t)
        if any(t,tasks) then return false end
        return ordered(t,{{"what is the point","what is even the point","no point","no reason","why bother"},continuation},6)
            or ordered(t,{{"i do not","i can not","i no longer"},{"see","find","know"},{"point","reason"},continuation},4)
            or any(t,{"can not keep living","can not keep going on","point of me being alive"})
            or ordered(t,{{"i do not think i can"},{"keep living","keep going"}},2)
    end},
    {id="prepared_means",test=function(t)
        return any(t,selfWords) and any(t,means) and not any(t,ordinaryPurpose)
            and (any(t,{"saved","saving","stockpiled","hoarding","ready","enough"})
                or ordered(t,{means,{"when i can not take it","when i give up"}},10))
    end},
    {id="goodbye_act",test=function(t)
        return ordered(t,{{"i wrote","i am writing","i have written","i left","i am leaving","my"},
            {"goodbye","farewell","last"},{"letter","note","message"}},4)
            or any(t,{"giving my things away","give my things away"})
    end},
    {id="disappearing",test=function(t)
        return ordered(t,{{"i","myself"},{"disappear","vanish","disappearing","vanishing"},
            {"for good","forever","permanently"}},6)
            or ordered(t,{{"i should","i should just"},{"disappear","vanish"}},1)
    end},
    {id="jumping_plan",test=function(t)
        return any(t,{"i","myself"}) and ordered(t,{{"thinking about","think about","want to","going to","planning to"},
            {"jumping off","jump off","jumping in front of","jump in front of"}},4)
    end},
    {id="better_off",test=function(t)
        return ordered(t,{{"i am","i would be","i will be"},{"better off"},{"gone","dead","not here","not alive"}},2)
            or ordered(t,{{"i would rather","i rather"},{"be dead","die","not exist","not be here","not wake up"}},2)
    end},
    {id="wanting_over",test=function(t)
        return ordered(t,{{"i want","i just want"},{"it","it all","everything","all of it"},{"to be over","to end","over"}},2)
            or ordered(t,{{"i am","i feel"},{"done with"},{"everything","life","all of it"}},2)
    end},
    {id="no_way_out",implicit=true,test=function(t)
        return ordered(t,{{"no way out"},{"dying","die","death","dead","ending it"}},4)
            and not any(t,{"my character","last save","the game"})
    end},
    {id="rumination",test=function(t)
        return ordered(t,{{"i","my"},thoughts,{"death","dying","being dead"}},4)
            and not any(t,{"death of","my wife","my husband","my parents","my friend","zombie","zombies"})
    end},
    {id="wish",test=function(t)
        return any(t,selfWords) and (ordered(t,{{"i wish","i want","i would like"},
            {"be dead","not exist","stop living","stop existing","my life to end"}},4)
            or ordered(t,{{"wish","want"},ownEnding},5)
            or ordered(t,{{"i feel like"},{"dying","being dead"}},2)
            or any(t,{"tired of being alive","sick of being alive"}))
    end},
}
local function concept(tokens)
    local compact={}
    for _,word in ipairs(tokens) do if word~="just" and word~="could" and word~="even" then compact[#compact+1]=word end end
    local own=any(tokens,selfWords)
    for _,rule in ipairs(rules) do if (own or rule.implicit) and rule.test(compact) then return true end end
    return false
end
-- Mask only the matched idiom, not the whole message. A separate explicit
-- disclosure in the same input must still override an otherwise ordinary line.
local ordinary={"dying of","dying to","dead tired","nearly died","almost died","almost killed myself",
    "do not let me die","not going to die","cut myself free","cut myself loose","cut myself out of",
    "suicide squad","i want to be alive","celebrate being alive","glad to be alive","living fellows"}
local function filtered(tokens,fear,injury)
    local out={};for index,word in ipairs(tokens) do out[index]=word end
    local list={};for _,phrase in ipairs(ordinary) do list[#list+1]=phrase end
    if fear then list[#list+1]="i do not want to die" end
    if injury then list[#list+1]="cut myself" end
    if not any(tokens,{"i deserve to die","i deserve to be dead"}) then list[#list+1]="die for" end
    for _,phrase in ipairs(list) do
        local from=1
        while from<=#tokens do
            local at,last=matches(tokens,phrase,from,true)
            if not at then break end
            for index=at,last do out[index]="_" end
            from=last+1
        end
    end
    return out
end
local objects={zombie=true,zombies=true,raider=true,raiders=true,bandit=true,bandits=true,they=true,them=true,
    generator=true,car=true,battery=true,radio=true,character=true,game=true,save=true,companion=true}
local deathWords={die=true,died=true,dying=true,dead=true,death=true,alive=true,living=true,exist=true,rope=true,bridge=true}
local ownPossessive={body=true,life=true,self=true,death=true,thoughts=true,head=true,mind=true,
    future=true,existence=true,turn=true,time=true}
local function uncertain(tokens)
    if not any(tokens,selfWords) then return false end
    if any(tokens,{"last save","last character","came back as someone else","for my headache","for climbing"}) then return false end
    local history=ordered(tokens,{{"how long","how many days","how much time"},{"have i","i have"},
        {"been alive","lived","survived"}},4)
    local dangerQuestion=ordered(tokens,{{"will i","could i","am i going to"},{"die"},{"if i"},
        {"go out","go outside","go there","head out"}},3)
    for index,word in ipairs(tokens) do
        if deathWords[word] or matches(tokens,"be over",index,true)==index or matches(tokens,"end it",index,true)==index then
            local other=false
            local subject=1
            for at=index-1,1,-1 do
                local value=tokens[at]
                if value=="i" or value=="me" or value=="myself" or value=="my" then
                    subject=at
                    -- A possessive is not automatically the speaker's body:
                    -- "my crops are dying" and "my turn to die" differ here.
                    if value=="my" and tokens[at+1]~=word and not ownPossessive[tokens[at+1]] then other=true end
                    break
                end
            end
            for at=math.max(subject+1,index-4),index-1 do
                if objects[tokens[at]] then other=true end
                for _,person in ipairs(SC.EmmaCareData.COMFORT_CONCEPTS.who) do
                    if near(tokens[at],person) then other=true end
                end
            end
            if word=="dead" and objects[tokens[index+1]] then other=true end
            if word=="rope" and any(tokens,ordinaryPurpose) then other=true end
            if word=="alive" and history or word=="die" and dangerQuestion then other=true end
            -- A question about an explicit in-game wound remains medical fear,
            -- rather than a question about wanting to end one's life.
            if any(tokens,{"from this bite","from a bite","from infection","from hunger","from thirst"}) then other=true end
            if not other then return true end
        end
    end
    return false
end
function Care.assess(raw)
    local original=Care.tokens(raw)
    local fear=matches(original,"i do not want to die")
    local injury=matches(original,"cut myself shaving") or matches(original,"cut myself")
        and any(original,{"accidentally","while cooking","on broken glass"})
    local tokens=filtered(original,fear,injury)
    local joined=" "..table.concat(tokens," ").." "
    local data=SC.EmmaCareData
    for word in pairs(data.CARE_WORDS) do
        if matches(tokens,word) and not (word=="suicide" and matches(tokens,"suicide squad")) then return "care" end
    end
    for _,phrase in ipairs(data.CARE_PHRASES) do
        if not excluded[phrase] and matches(tokens,phrase) then return "care" end
    end
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
    if concept(tokens) then return "care" end
    if fear or injury or any(tokens,data.SELF_WORTH_PHRASES) then return "comfort" end
    local self=any(tokens,selfWords)
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
    if uncertain(tokens) then return "care_check" end
end

function Care.quiet(session) return session and (session.careMode==true or session.careSoft or session.careCheckin
    or (session.comfortTurns or 0)>0) end
function Care.reset(session)
    if not session then return end
    session.careMode,session.careQuestion,session.careCheckin=nil,nil,nil
    session.careSoft,session.careSupportShown,session.emmaKnock=nil,nil,nil
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
local function support(session,result)
    if not session.careSupportShown then
        session.careSupportShown=true
        result.support=SC.EmmaCareData.NOTE
    end
end
local function clearPending(session)
    session.context=session.context or {}
    session.context.pending,session.context.personChoices=nil,nil
    session.emmaKnock,session.emmaLogPrevious=nil,nil
end
local function uncertainReply()
    return {intent="comfort",category="care",thinkMs=0,private=true,lines={
        "Thank you for telling me. You do not have to work this out alone.",
        "If you might act on these thoughts, seek urgent help now. Please reach out to someone you trust today."}}
end
function Care.respond(session,raw,intent,locked)
    local assessment=Care.assess(raw)
    local worth=Care.selfWorth(raw)
    if intent=="care" or intent=="comfort" or intent=="care_check" then assessment=assessment or intent end
    local normalized=table.concat(Care.tokens(raw)," ")
    if assessment=="care" then
        local first=session.careMode~=true
        session.careMode,session.careSoft=true,nil
        clearPending(session)
        local result=reply(session,worth and "care_worth" or first and "care" or "care_more")
        result.careDetected=true
        if first then
            support(session,result)
            session.careQuestion=true
            local question=pool(session,"care_ask")[1]
            result.lines[#result.lines+1]=question
        end
        return result
    end
    if session.careSoft then
        session.careSoft,session.careQuestion=nil,nil
        session.emmaLogPrevious=nil
        if normalized=="yes" or normalized=="y" then
            session.careMode=true
            clearPending(session)
            local result=reply(session,"care_ask_yes")
            result.careDetected=true
            support(session,result)
            return result
        elseif normalized=="no" or normalized=="n" or normalized=="nope" or normalized=="not really" then
            local result=reply(session,"care_ask_no");result.intent="comfort";return result
        elseif normalized=="maybe" or normalized=="i do not know" or normalized=="not sure" then
            return uncertainReply()
        end
        -- A new subject is not an answer. It gets its own assessment below.
    end
    if assessment=="care_check" and not session.careMode then
        clearPending(session)
        session.careQuestion,session.careSoft=true,true
        local result=reply(session,"care_check");result.intent="care_check"
        return result
    end
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
                local result=uncertainReply();result.intent="care";return result
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
