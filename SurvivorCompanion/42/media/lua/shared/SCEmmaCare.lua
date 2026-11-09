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
    hasnt="has not", havent="have not", itll="it will", thatll="that will" }
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
    "thinking about","think about","thinking of","think of","considering","the guts to","the nerve to",
    "the courage to","i think to","thinking to"}
local thoughts={"thinking about","think about","thoughts about","picturing","imagining"}
local ownEnding={"i died","i die","i disappeared","i was dead","i were dead","i was gone","i were gone","i am gone",
    "i did not exist","i was not alive","i were not alive","i was not around","i were not around","i was not here",
    "i was never here","i never existed","i had never been born"}
local continuation={"going on","go on","keep going","carrying on","carry on","living","being alive","to live"}
local means={"pills","rope","gun","razor"}
local ordinaryPurpose={"for my headache","for a headache","for pain","to shave","for climbing","for repairs",
    "to fight zombies","to shoot zombies","for hunting","to tie","for the fence","for first aid",
    "sheet ladder","sheet rope","ladder","to tow","for towing","for fishing","for a trap","for traps","for the tent",
    "to climb","climb out","climb down","climb up"}
-- True when the message ends with this phrase ("let them get me", not "get me some ammo").
local function endsWith(tokens,phrase)
    local at,last=matches(tokens,phrase,math.max(1,#tokens-3),true)
    return at~=false and last==#tokens
end
local rules={
    {id="absence",test=function(t)
        return any(t,ownEnding) and (ordered(t,{{"would be","might be","will be"},
            {"happier","relieved","better","glad","easier"},{"if i","when i"}},8)
            or ordered(t,{{"notice","miss me","care"},{"if i","when i"}},4))
            or ordered(t,{{"if i died","if i was dead","if i was gone","if i did not wake up"},{"would be","will be"},
                {"relief","a relief","better","easier","peaceful"}},4)
    end},
    {id="ending_plan",test=function(t)
        return any(t,selfWords) and ordered(t,{plans,{"end things","ending things","end everything","ending everything","end it all","ending it all",
            "end my life","ending my life","finish my life","finishing my life","finish myself"}},5)
            and not any(t,tasks)
    end},
    {id="continuation",implicit=true,test=function(t)
        if any(t,tasks) then return false end
        return ordered(t,{{"what is the point","what is even the point","no point","no reason","why bother"},continuation},6)
            or ordered(t,{{"i do not","i can not","i no longer"},{"see","find","know"},{"point","reason"},continuation},4)
            or any(t,{"can not keep living","can not keep going on","point of me being alive",
                "is it worth living","is life worth living","is it worth going on","is it worth staying alive"})
            or ordered(t,{{"i do not think i can"},{"keep living","keep going"}},2)
    end},
    {id="prepared_means",test=function(t)
        return any(t,selfWords) and any(t,means) and not any(t,ordinaryPurpose)
            and (any(t,{"saved","saving","stockpiled","hoarding","ready","enough"})
                or ordered(t,{means,{"when i can not take it","when i give up"}},10))
    end},
    {id="goodbye_act",test=function(t)
        return ordered(t,{{"i wrote","i am writing","i have written","i left","i am leaving","my","wrote","writing"},
            {"goodbye","farewell","last"},{"letter","note","message","letters","notes","messages"}},4)
            or any(t,{"this is goodbye","need a new owner","needs a new owner","find a new home for my",
                "new home for my"}) and any(t,selfWords)
            or any(t,{"giving my things away","give my things away","goodbye for the last time",
                "said my last goodbye","my last goodbye"})
    end},
    {id="disappearing",test=function(t)
        return ordered(t,{{"i","myself"},{"disappear","vanish","disappearing","vanishing"},
            {"for good","forever","permanently"}},6)
            or ordered(t,{{"i should","i should just"},{"disappear","vanish"}},1)
    end},
    {id="jumping_plan",test=function(t)
        return any(t,{"i","myself"}) and ordered(t,{{"thinking about","think about","want to","going to","planning to"},
            {"jumping off","jump off","jumping in front of","jump in front of","stepping off","step off",
                "stepping in front of","step in front of","letting go"}},4)
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
            or ordered(t,{{"wish","want"},{"turn like them","be one of them","become one of them","just gone",
                "be gone","end things","end it all"}},6)
            or ordered(t,{{"i feel like"},{"dying","being dead"}},2)
            or any(t,{"tired of being alive","sick of being alive"}))
    end},
    -- Warning signs from general guidance rather than single sentences:
    -- an act of self-harm, letting the dead take you, a last night, goodbyes
    -- to everyone, not being here later, arrangements for after you are gone.
    {id="self_harm_act",test=function(t)
        return any(t,{"been cutting","cutting again","started cutting","cutting myself","cut myself again",
            "gun to my head","gun against my head","barrel in my mouth","do something to myself",
            "something stupid to myself","something to hurt myself","burning myself","burn myself on purpose",
            "let myself bleed","let myself die","let myself drown","let myself starve","let myself freeze",
            "into my skin","knife into","blade into","cut deeper","go deeper","to feel something",
            "punch myself","punching myself","hit myself in the head","hitting myself","sewer slide","self delete",
            "unalive myself","off myself","delete myself","end myself","stopped eating on purpose",
            "not eating on purpose","starving myself"})
            or ordered(t,{{"burning","burned","burnt","burn","punching","punched","hitting","scratching"},
                {"my arm","my arms","my wrist","my wrists","my skin","my leg","my legs","my thigh","my thighs"}},1)
                and not any(t,{"accidentally","by accident","cooking","stove","oven","fire","while"})
            or ordered(t,{{"hoping","hope","praying"},{"i crash","i die","it is over","i do not wake","i get hit"}},5)
    end},
    {id="let_them_take_me",test=function(t)
        if any(t,{"do not let","never let","will not let","not going to let","do not want them to"}) then return false end
        return ordered(t,{{"let","wish","hope","want"},{"them","the zombies","zombies","the horde","the dead","it",
                "the infection","the bite","the cold","the river"},
                {"have me","kill me","finish me","end me","take me","eat me","get me on purpose"}},4)
            or ordered(t,{{"let","wish","hope","want"},{"them","the zombies","zombies","the horde","the dead"}},4)
                and endsWith(t,"get me")
            or ordered(t,{{"zombies","them","the horde"},{"get me","have me","kill me"},{"on purpose"}},4)
            or ordered(t,{{"wish","should have","could have"},{"finished me","killed me","ended me"}},6)
            or ordered(t,{{"do not care","no longer care","stopped caring"},{"if","whether"},
                {"get me","kill me","i die","i live","i make it","i survive"}},6)
    end},
    {id="final_time",test=function(t)
        for index=2,#t-1 do
            if t[index-1]=="my" and t[index]=="last" and (t[index+1]=="night" or t[index+1]=="day") then
                local after=t[index+2]
                if not after or after=="alive" or after=="on" and t[index+3]=="earth" then return true end
            end
        end
        return any(t,{"last night alive","last day alive"})
            or ordered(t,{{"tonight","today","this weekend","this week","tomorrow"},{"is my last","will be my last"}},2)
            or any(t,{"gone for real","gone for good"}) and any(t,selfWords)
            or ordered(t,{{"envy","jealous of"},{"dead","dies","died","dying","the dead","them"}},6)
    end},
    {id="farewell_all",test=function(t)
        return any(t,{"goodbye to everyone","goodbye to everybody","goodbye to all of you","goodbye to you all",
            "goodbyes to everyone","say my goodbyes","saying my goodbyes"})
    end},
    {id="not_here_later",test=function(t)
        return any(t,{"not be here tomorrow","not want to be here tomorrow","not be here much longer",
            "not be here for much longer","not be around much longer","not be around for much longer",
            "not going to be here much longer","not going to be around much longer","not be alive tomorrow",
            "not be around after","not be here after","not be around after this","not be here after this"})
            or ordered(t,{{"make it to","making it to","last until","see"},{"my birthday","next week","next month",
                "christmas","the weekend","next year","tomorrow"}},3)
                and any(t,{"do not think","do not want","will not","not going to"})
    end},
    {id="after_gone",test=function(t)
        return any(t,{"when i am gone","once i am gone","after i am gone","when i am dead","once i am dead",
            "after i am dead"}) and any(t,{"miss me","looked after","look after","take care of","taken care of",
            "remember me","have my","keep my","get my"})
    end},
    {id="peaceful_death",implicit=true,test=function(t)
        return ordered(t,{{"dying","death","being dead"},{"sounds","seems","feels","would be","looks"},
            {"peaceful","nice","good","better","easier","calm","like rest"}},3)
            and not any(t,{"dying light","death stranding","game"})
    end},
    {id="tired_of_self",test=function(t)
        return any(t,{"tired of being a person","tired of being me","tired of being myself","tired of being human",
            "tired of existing","sick of existing","sick of being me","sick of being myself","tired of live",
            "tired of life","sick of life"})
    end},
    {id="want_out_of_life",implicit=true,test=function(t)
        return any(t,{"want out of life","want out of this life","want out of this world","want out of existence"})
            or any(t,{"want out of it","want out of everything","want out of it all"})
                and any(t,{"life","living","pain","hurts","alive","world","exist"})
    end},
    {id="enough_of_world",implicit=true,test=function(t)
        return any(t,{"had enough of this world","had enough of life","had enough of living","had enough of everything",
            "had enough of being alive","done with this world","check out for good","checking out for good",
            "check out of this world","checking out of this world","check out of life","checking out of life"})
            or any(t,{"checking out","check out"}) and any(t,{"had enough","of this world","of life","for good","forever"})
    end},
    {id="stop_feeling",test=function(t)
        return any(t,{"stop feeling","feel nothing","not feel anything","stop everything","stop thinking"})
            and any(t,{"permanently","forever","for good","ever again"})
    end},
    {id="hurts_to_live",implicit=true,test=function(t)
        return ordered(t,{{"living","being alive","existing","life","being me"},
            {"hurts","is pain","is only pain","is agony","is unbearable","hurts too much"}},3)
            and not any(t,{"living room","for a living","living in","living with"})
    end},
    {id="better_without_me",implicit=true,test=function(t)
        return any(t,{"better without me","happier without me","easier without me"})
            or any(t,{"without me"}) and any(t,{"better","fine","happier","easier","relieved","lighter","safer"})
                and not any(t,{"run","trip","expedition","raid","loot","looting","job","shift","fight"})
    end},
}
local function concept(tokens)
    local compact={}
    -- Filler words break phrase rules: "would honestly be better off if i was not around".
    local filler={just=true,could=true,even=true,honestly=true,really=true,probably=true,seriously=true,
        literally=true,actually=true,ngl=true,tbh=true,lowkey=true,kinda=true,maybe=true,truly=true}
    for _,word in ipairs(tokens) do if not filler[word] then compact[#compact+1]=word end end
    local own=any(tokens,selfWords)
    for _,rule in ipairs(rules) do if (own or rule.implicit) and rule.test(compact) then return true end end
    return false
end
-- Mask only the matched idiom, not the whole message. A separate explicit
-- disclosure in the same input must still override an otherwise ordinary line.
local ordinary={"dying of","dying to","dead tired","nearly died","almost died","almost killed myself",
    "do not let me die","not going to die","cut myself free","cut myself loose","cut myself out of",
    "suicide squad","i want to be alive","celebrate being alive","glad to be alive","living fellows",
    "dead on my feet","dead serious","dead set","dead end","dead asleep","dead last","dead beat",
    "starving to death","freezing to death","scared to death","bored to death","worked to death",
    "eat me alive","eaten alive","die on this hill","dying laughing","kill myself laughing","shot myself in the foot",
    "hope i do not die","please do not let me die","nearly killed myself","cut myself some slack",
    "cutting myself some slack","cut myself a"}
-- Harm verbs aimed at oneself, in any tense: the phrase list only held base
-- forms, so "hanging myself" and "shooting myself" slipped past it.
local harmStems={kill=true,hang=true,shoot=true,cut=true,stab=true,drown=true,overdose=true,hurt=true,harm=true,
    poison=true,starve=true,suffocate=true,strangle=true,bleed=true,slit=true,choke=true}
local function harmVerb(word)
    if type(word)~="string" or #word<3 then return false end
    if harmStems[word] then return true end
    for _,suffix in ipairs({"ing","ed","es","s"}) do
        if #word>#suffix+2 and word:sub(-#suffix)==suffix then
            local base=word:sub(1,#word-#suffix)
            if harmStems[base] or harmStems[base.."e"] then return true end
            if #base>3 and base:sub(-1)==base:sub(-2,-2) and harmStems[base:sub(1,-2)] then return true end
        end
    end
    return word=="shot" or word=="hung" or word=="bled" or word=="slit"
end
local function selfHarm(tokens)
    for index=1,#tokens do
        local word=tokens[index]
        if word:sub(1,7)=="overdos" then return true end
        local target=tokens[index+1]
        if target=="my" and tokens[index+2]=="self" then target="myself" end
        if target=="myself" and harmVerb(word) and tokens[index+2]~="laughing" then return true end
        if harmVerb(word) and target=="my" and (tokens[index+2]=="wrist" or tokens[index+2]=="wrists"
            or tokens[index+2]=="arms" or tokens[index+2]=="arm" or tokens[index+2]=="throat") then return true end
    end
    -- "i took a bunch of pills", but not "i took two pills for my headache"
    return ordered(tokens,{{"i took","i have taken","i swallowed","i just took"},
            {"bunch of","all","whole","handful of","lot of","every","entire","too many"},{"pills","tablets","bottle"}},3)
        and not any(tokens,ordinaryPurpose)
end
local function filtered(tokens,fear,injury)
    local out={};for index,word in ipairs(tokens) do out[index]=word end
    local list={};for _,phrase in ipairs(ordinary) do list[#list+1]=phrase end
    if fear then list[#list+1]="not want to die" end
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
local gameCauses={horde=true,crash=true,outbreak=true,infection=true,bite=true,raid=true,herd=true}
local questionLeads={how=true,when=true,will=true,would=true,could=true,can=true,am=true,is=true,are=true,
    what=true,does=true,["do"]=true,which=true,where=true,why=true}
local whLeads={how=true,when=true,what=true,which=true,where=true,why=true}
local subjects={i=true,you=true,we=true,it=true,my=true,the=true,there=true,they=true,this=true,that=true,
    he=true,she=true,a=true,any=true,anyone=true,emma=true,your=true,u=true}
-- "can i die from this" is a question; "cant sleep again" is a statement.
local function questionStart(tokens)
    local at=tokens[1]=="emma" and 2 or 1
    local lead=tokens[at] or ""
    if whLeads[lead] then return true end
    if questionLeads[lead] then return subjects[tokens[at+1] or ""]==true end
    for key in pairs(questionLeads) do
        if #key>=4 and near(lead,key) then return whLeads[key] or subjects[tokens[at+1] or ""]==true end
    end
    return false
end
local despairCues={"want","wish","rather","deserve","ready","better off","should","plan","planning","worth","point",
    "reason","bother","anymore","still alive","tired","sick of","kill myself","end it","hurt myself","on purpose",
    "nobody","no one","care if","miss me","until it","stay asleep","not wake","never wake","quick","even"}
local softSignals={"stay asleep","not get up","never get up","never wake","until it was over","until it is over",
    "until it ends","it will be quick","it would be quick","my funeral","own funeral","write my will","writing my will",
    "wrote my will","for real this time","for good this time"}
local hopelessQuestions={"why keep trying","why keep going","why even try","why keep fighting","why go on"}
local neverBetter={"never get better","never going to get better","never be better","ever get better"}
local function uncertain(tokens,asked)
    if any(tokens,hopelessQuestions) and not any(tokens,tasks) then return true end
    if any(tokens,neverBetter) and any(tokens,{"nothing","everything","life","things","it all","i","me","my"})
        and not any(tokens,{"generator","car","radio","weather","wound","bite","game"}) then return true end
    if not any(tokens,selfWords) then return false end
    if any(tokens,{"last save","last character","came back as someone else","for my headache","for climbing"}) then return false end
    -- Softer signs with no death word: still worth the direct question.
    if any(tokens,softSignals) then return true end
    if tokens[#tokens]=="done" and any(tokens,{"i think i am done","i am so done","i am really done",
        "i am totally done","i am completely done","done done"}) then return true end
    -- How, when and will questions about dying are survival questions in this
    -- game. They keep their ordinary answers unless they carry despair.
    if (asked or questionStart(tokens)) and not any(tokens,despairCues) then return false end
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
            local who=(SC.EmmaCareData.COMFORT_CONCEPTS or {}).who or {}
            for at=math.max(subject+1,index-4),index-1 do
                if objects[tokens[at]] then other=true end
                for _,person in ipairs(who) do
                    if near(tokens[at],person) then other=true end
                end
            end
            if word=="dead" and objects[tokens[index+1]] then other=true end
            -- Nobody reports their own real death: "i died ..." is a game report.
            local before=tokens[index-2]
            if word=="died" and (tokens[index-1]=="i" or before=="i" and tokens[index-1]=="just")
                and before~="if" and before~="wish" and before~="hope" and before~="when" and before~="rather" then
                other=true
            end
            -- A past game report names what killed you: "i died to a zombie".
            if word=="died" or word=="die" or word=="dying" or word=="dead" then
                for at=index+1,math.min(#tokens,index+6) do
                    if objects[tokens[at]] or gameCauses[tokens[at]] then other=true end
                end
            end
            if word=="rope" and any(tokens,ordinaryPurpose) then other=true end
            if word=="alive" and history or word=="die" and dangerQuestion then other=true end
            -- A question about an explicit in-game wound remains medical fear,
            -- rather than a question about wanting to end one's life.
            if any(tokens,{"from this bite","from a bite","from infection","from hunger","from thirst"}) then other=true end
            -- A fresh in-game wound: "i got bit, am i gonna die now" is fear for the character.
            if (word=="die" or word=="dying" or word=="dead") and any(tokens,{"bit","bitten","bite","scratched",
                "scratch","infected","laceration","lacerated"}) then other=true end
            if not other then return true end
        end
    end
    return false
end
function Care.assess(raw)
    local original=Care.tokens(raw)
    local asked=tostring(raw or ""):find("?",1,true)~=nil
    -- "i really dont want to die this run" is fear, not a wish: allow words between.
    local fear=matches(original,"not want to die")
    local injury=matches(original,"cut myself shaving") or matches(original,"cut myself")
        and any(original,{"accidentally","while cooking","on broken glass"})
    local tokens=filtered(original,fear,injury)
    local joined=" "..table.concat(tokens," ").." "
    -- Questions about the game's own rules: "can my character overdose on pills".
    if (asked or questionStart(tokens)) and any(tokens,{"my character","in the game","in game","this game"})
        and not any(tokens,{"i want","i will","i am going to","for real","i feel","myself","real life"}) then return nil end
    local data=SC.EmmaCareData
    for word in pairs(data.CARE_WORDS) do
        if matches(tokens,word) and not (word=="suicide" and any(tokens,{"suicide squad","suicide run",
            "suicide mission","suicide door","suicide doors","suicide dive","suicide jump"})) then return "care" end
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
    if selfHarm(tokens) or concept(tokens) then return "care" end
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
    if uncertain(tokens,asked) then return "care_check" end
end

-- Answers to EMMA's direct questions. People rarely type a bare "yes": a
-- "yeah", "kind of" or "yes i am" must count, and "nah im fine" is a no.
local yesLead={yes=true,y=true,yeah=true,yea=true,yep=true,yup=true,ya=true,yah=true,ye=true,yeh=true,
    yess=true,aye=true,sure=true,affirmative=true,correct=true}
local noLead={no=true,n=true,nope=true,nah=true,naw=true,nay=true,negative=true}
local notAnswerAfterNo={one=true,body=true,point=true,reason=true,future=true,hope=true,way=true,
    more=true,longer=true,matter=true}
local yesWhole={"i am","i think so","i guess","i guess so","i suppose","i suppose so","kind of","kinda","sort of","sorta",
    "a little","a bit","a little bit","sometimes","often","a lot","all the time","every day","most days","lately",
    "probably","i have been","i do","i was","i might","i might be","maybe a little","maybe a bit",
    "more than i want to","i think i am","i have thought about it","i have been thinking about it",
    "thinking about it","honestly yes","i am thinking about it"}
local noWhole={"not really","i am not","not at all","never","of course not","no way","i am fine","i am ok","i am okay",
    "i am good","i am alright","i am all right","i was joking","just joking","i was kidding","just kidding","jk",
    "not like that","nothing like that","not anymore","i meant in the game","in the game","just the game","i am safe"}
local unsureWhole={"maybe","i do not know","not sure","i am not sure","dunno","i dunno","perhaps","hard to say",
    "no idea","i do not really know","i am unsure","unsure","i can not say","i do not know anymore"}
function Care.answer(raw)
    local t=Care.tokens(raw)
    if t[1]=="emma" then table.remove(t,1) end
    if #t==0 or #t>14 then return nil end
    local joined=table.concat(t," ")
    local function whole(list)
        for _,phrase in ipairs(list) do if joined==phrase then return true end end
        return false
    end
    if whole(unsureWhole) then return "unsure" end
    if whole(noWhole) then return "no" end
    if whole(yesWhole) then return "yes" end
    if any(t,{"in the game","in game","about the game","my character","joking","kidding","just asking"}) then return "no" end
    if yesLead[t[1]] then
        if noLead[t[2]] then return "no" end
        return "yes"
    end
    if noLead[t[1]] and not notAnswerAfterNo[t[2]] then
        if any(t,{"but","sometimes","a little","kind of","maybe","not sure","i do not know"}) then return "unsure" end
        return "no"
    end
    if t[1]=="i" and t[2]=="am" and t[3]=="not" and (t[4]==nil or t[4]=="thinking" or t[4]=="suicidal"
        or t[4]=="going" or t[4]=="planning" or t[4]=="like") then return "no" end
    if t[1]=="i" and t[2]=="am" and #t<=6 and (t[3]=="fine" or t[3]=="ok" or t[3]=="okay" or t[3]=="good"
        or t[3]=="alright" or t[3]=="safe") then return "no" end
    if t[1]=="maybe" or t[1]=="perhaps" then return "unsure" end
    if any(t,{"sometimes","all the time","every day","i think so"}) then return "yes" end
    return nil
end

-- The safety net under the rules. Rules miss most new wording, so a
-- first-person statement with ending or sadness words that the parser could
-- only place in a joke, a data report or an unrelated topic gets care instead.
-- Ending words ask the direct question; sadness gets a warm line and support.
local placed={care=true,comfort=true,care_check=true,care_gentle=true,worth=true,chat_grief=true,chat_fear=true,
    chat_scared=true,me_status=true,me_need=true,me_infected=true,news_hurt=true,news_bitten=true,help=true,
    hello=true,thanks=true,sorry=true,chat_apology=true,news_death=true,news_escape=true,news_killed=true,
    me_die=true,yes=true,no=true,confirm=true,declined=true,clarify_action=true}
local endingSigns={"plan for tonight","a plan for tonight","you can not stop me","can not stop me","nobody can stop me",
    "almost did it","nearly did it","go through with it","do it tonight","doing it tonight","ready to go",
    "at peace with it","stop breathing","fade away","never come back","not come back","not make it to",
    "making it to next week","see myself making it","see myself alive","against my wrist","to my wrist","my wrists",
    "knife against","blade against","razor to","edge of the roof","edge of the bridge","off the bridge","in front of a",
    "into the river","into the lake","into the water","drive off the road","off the road","walk into the horde",
    "for the last time","will not need my","giving away my","give away my","giving my stuff","be done with it",
    "no longer be here","be a problem for","a favor by","a favour by"}
local sadSigns={"nothing left","no one left","nobody left","can not take","can not do this","can not handle",
    "can not cope","can not breathe","can not stop crying","hopeless","empty","numb","lonely","so alone","all alone",
    "hurting","the pain","in pain","tired of everything","tired of it all","tired of this","tired of trying",
    "so tired of","i am broken","i feel broken","broken inside","falling apart","give up on everything","giving up on everything","gave up on everything",
    "give up on life","giving up on life","gave up on life","given up on everything","given up on life","miserable","depressed","so sad",
    "i am sad","crying","overwhelmed","feel lost","no hope","no future","pointless","meaningless","fed up",
    "sick of everything","sick of it all","drowning","suffocating","nobody cares","no one cares","nobody understands",
    "no one understands","dark place","losing it","can not sleep","nightmares","heavy","weighs on me","waking up every day",
    "stressed","anxiety","anxious","panic attack","burnt out","burned out","exhausted every","crushing me",
    "nobody to talk","no one to talk","nobody here to talk","nobody remembered","no one remembered","nobody texts",
    "no one texts","hide in my room","stopped talking to me","than my real life","laid off","lost my job",
    "can not pay","in the hospital","does not look good","broke up with me","can not catch up","rough week",
    "rough day","bad week"}
local gameWords={"loot","looting","raid","scavenge","scavenging","expedition","mall","store","base","camp","zombie",
    "zombies","horde","car","truck","generator","map","wall","farm","fishing","hunting","craft","build","building",
    "character","game","save","server","mod","run","trip","fight","fighting","beans","food","water","ammo"}
function Care.distress(raw,parsed)
    if placed[parsed] then return nil end
    local tokens=filtered(Care.tokens(raw),false,false)
    local lead=tokens[1]=="emma" and tokens[2] or tokens[1] or ""
    -- A means "not for" its usual job: "bought a rope and its not for the game".
    if any(tokens,{"rope","pills","gun","razor","knife","blade"})
        and any(tokens,{"is not for","not for the","not for a","not for my"}) then return "care_check" end
    -- "had a panic attack in class", "grandma is in the hospital": about the
    -- speaker, or the speaker's family, without saying "i".
    local implicitLead={feeling=true,feel=true,been=true,had=true,got=true,working=true,so=true}
    if not any(tokens,selfWords) and not implicitLead[lead] and not any(tokens,{"grandma","grandpa","mom","dad",
        "mum","brother","sister","wife","husband","girlfriend","boyfriend"}) then return nil end
    local asked=tostring(raw or ""):find("?",1,true)~=nil
        or any(tokens,{"what do i do","what should i do","how do i","how can i","what can i do"})
    if (asked or questionStart(tokens)) and not any(tokens,despairCues) then return nil end
    local game=any(tokens,gameWords)
    if any(tokens,endingSigns) and not game then return "care_check" end
    -- Fixing on a means: "i keep looking at the bridge and thinking about it".
    if any(tokens,{"thinking about it","think about it","keep thinking","can not stop thinking"})
        and any(tokens,{"river","bridge","edge","roof","ledge","rope","pills","gun","knife","tracks","train"})
        and not game then return "care_check" end
    if any(tokens,sadSigns) and not game then return "care_gentle" end
    return nil
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
    if intent=="care" or intent=="comfort" or intent=="care_check" or intent=="care_gentle" then
        assessment=assessment or intent
    end
    local normalized=table.concat(Care.tokens(raw)," ")
    local asked=session.careSoft or session.careMode and session.careQuestion
    local answer=(asked or session.careCheckin) and Care.answer(raw) or nil
    -- A yes to "Are you thinking about ending your life?" always gets the
    -- urgent-help reply, even when it arrives with more ("yes, i have pills").
    if asked and answer=="yes" then
        session.careMode,session.careSoft,session.careQuestion=true,nil,nil
        clearPending(session)
        local result=reply(session,"care_ask_yes")
        result.careDetected=true
        support(session,result)
        return result
    end
    -- Another uncertain own-death line right after the question is not a
    -- reason to ask again. Treat it as the disclosure it probably is.
    if session.careSoft and assessment=="care_check" then assessment="care" end
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
        if answer=="no" then
            local result=reply(session,"care_ask_no");result.intent="comfort";return result
        elseif answer=="unsure" then
            return uncertainReply()
        end
        -- Not an answer. A data question or a new feeling gets its own handling
        -- below; anything else gets a warm line, never the joke the parser picks.
        if intent=="exit" then
            local result=reply(session,"care_bye");result.intent="comfort";result.command="close";return result
        end
        -- Sadness right after the question is not a no. Treat it as unsure.
        if assessment=="care_gentle" then return uncertainReply() end
        if not assessment and not dataIntents[intent] then
            local result=reply(session,"care_check_open");result.intent="comfort";return result
        end
    end
    if assessment=="care_check" and not session.careMode then
        clearPending(session)
        session.careQuestion,session.careSoft=true,true
        local result=reply(session,"care_check");result.intent="care_check"
        return result
    end
    if assessment=="care_gentle" and not session.careMode then
        clearPending(session)
        session.comfortTurns,session.comfortKind=1,"support"
        local result=reply(session,"care_gentle");result.intent="care_gentle"
        return result
    end
    if session.careCheckin then
        if answer=="yes" or answer=="no" then
            session.careCheckin=nil
            return reply(session,answer=="yes" and "care_checkin_yes" or "care_checkin_no")
        elseif answer=="unsure" then
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
            -- A yes was answered above, before any other assessment.
            if answer=="no" then
                session.careQuestion=nil; return reply(session,"care_ask_no")
            elseif answer=="unsure" then
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
