-- SPDX-License-Identifier: MIT
-- Once-built noun index; all reads use existing bounded station providers.
require "SCTerminalLines"
require "SCTerminalKnowledge"
require "SCTerminalConversation"
require "SCTerminalBrain"
require "SCEmmaSurvival"
require "SCEmmaFollowups"
require "SCEmmaReferenceData"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local R={} SC.EmmaReference=R
local definitions,index,byGuide={}, {}, {}
local direct={}
local installed=false
local function norm(raw)
    return table.concat(SC.TerminalBrain.tokens(raw)," "):gsub("^emma ","")
end
local function has(raw,word) return (" "..raw.." "):find(" "..word.." ",1,true)~=nil end
local function oneOf(raw,list) for _,word in ipairs(list) do if has(raw,word) then return true end end return false end
local function add(alias,entry)
    alias=norm(alias)
    if #alias<2 or #alias>80 or #index>=1800 then return end
    index[#index+1]={term=alias,target=entry}
    if entry.kind=="reference" then direct[alias]=entry end
end
local guideMap={survival_bleeding="dressings",survival_fuel="fuel",survival_generator="generator",
    survival_warmth="winter",survival_weapons="weapons"}
function R.install()
    if installed then return end installed=true
    SC.EmmaSurvival.install()
    for _,topic in ipairs(SC.EmmaReferenceData) do
        definitions[topic.id]=topic
        byGuide["reference_"..topic.id]=topic.id
        for _,alias in ipairs(topic.aliases) do
            local finding=topic.id=="fuel" and (alias=="gas station" or alias=="gas pump" or alias=="pump" or alias=="siphon" or alias=="siphoning")
            add(alias,{kind="reference",id=topic.id,facet=finding and "find" or nil})
        end
        SC.TerminalConversation.GUIDES[#SC.TerminalConversation.GUIDES+1]={id="reference_"..topic.id,
            title=topic.title,questions={},pages={{topic.facets.what}},survival=true}
    end
    for guide,id in pairs(guideMap) do byGuide[guide]=id end
    for id,subject in pairs(SC.EmmaFollowups.subjects) do
        for _,alias in ipairs(subject.aliases) do
            local owned=false
            for _,row in ipairs(index) do if row.term==norm(alias) then owned=true break end end
            if not owned then add(alias,{kind="guide",id=subject.guideId,subject=id}) end
        end
    end
    for _,entry in ipairs(SC.TerminalKnowledge.ENTRIES) do
        for _,alias in ipairs(entry.aliases or {}) do add(alias,{kind="lore",id=entry.id}) end
    end
    local selves={emma="identity",computer="computer",["green screen"]="chat_colour",preferences="her_opinion",
        ["your creator"]="her_maker",["your maker"]="her_maker",["your past"]="lore",
        ["your favourite"]="her_opinion",["your favorite"]="her_opinion"}
    for alias,intent in pairs(selves) do add(alias,{kind="intent",id=intent}) end
    table.sort(index,function(a,b)
        if #a.term~=#b.term then return #a.term>#b.term end
        if a.term~=b.term then return a.term<b.term end
        local rank={reference=1,guide=2,intent=3,lore=4}
        return rank[a.target.kind]<rank[b.target.kind]
    end)
    R.size=#index
end
function R.find(raw)
    R.install()
    local text=norm(raw)
    for _,row in ipairs(index) do
        if not (row.term=="emma" and text~="emma") and has(text,row.term) then return row.target,row.term end
    end
end
function R.facet(raw)
    local text=norm(raw)
    if text:find("^what is ") or text:find("^what are ") then return "what" end
    if text:find("^why ") then return "why" end
    if text:find("^where ") then return "find" end
    if oneOf(text,{"catch","catches","animals"}) then return "catch" end
    if oneOf(text,{"loud","noise","noisy"}) then return "noise" end
    if oneOf(text,{"change","changing","dirty bandage"}) then return "change" end
    if oneOf(text,{"danger","dangers","dangerous","safe","safely","risk","risks","will i turn","will she turn","will he turn"}) then return "dangers" end
    if oneOf(text,{"make","making","craft","crafting","build","building","rip","ripping","sterilize","sterilise"}) then return "make" end
    if text:find("^where ") or oneOf(text,{"find","finding","get ammo","get fuel","get gasoline","get water"}) then return "find" end
    if text:find("^why ") or oneOf(text,{"matter","matters","melee versus","melee or"}) then return "why" end
    if text:find("^how ") or oneOf(text,{"use","using","apply","place","operate","repair","fix","reload","refuel","wear"}) then return "use" end
    return "what"
end
local function call(world,name)
    local fn=world and world[name]
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn)
    return ok and value or nil
end
function R.named(session,text,world)
    if oneOf(text,{"died","dead","killed"}) then return nil end
    local medical=oneOf(text,{"bitten","bite","infected","infection","bleeding","help"})
    if not medical or text:find("^i ") or text:find("^my ") or text:find("^im ") then return nil end
    local stop={what=true,why=true,how=true,who=true,when=true,where=true,is=true,are=true,was=true,
        has=true,have=true,got=true,gets=true,get=true,can=true,could=true,would=true,should=true,
        the=true,a=true,an=true,please=true,she=true,he=true,her=true,him=true,they=true,them=true,
        ["do"]=true,does=true,["not"]=true,bitten=true,bite=true,infected=true,infection=true,
        bleeding=true,help=true,wound=true,wounds=true,cut=true,cuts=true,scratch=true,zombie=true,
        zombies=true,people=true,person=true,character=true,ordinary=true,knox=true,spread=true}
    local named=false
    for word in text:gmatch("%S+") do if not stop[word] then named=true break end end
    if not named then return nil end
    local camp=call(world,"camp")
    if type(camp)~="table" or not camp.configured or not camp.inside then return nil end
    local people=call(world,"people")
    if type(people)~="table" then return nil end
    local matches={}
    for n,person in ipairs(people) do
        if n>64 then break end
        local name=norm(person.name)
        if #name>0 and (has(text,name) or has(text,name:match("^%S+"))) then matches[#matches+1]=person end
    end
    if #matches~=1 then return nil end
    local patient=matches[1]
    if oneOf(text,{"bite","bitten","infected","infection"}) then
        return "guide",{guideId="reference_bite",referencePatient=patient.name,referenceReported=true,page=1}
    end
    return "guide",{guideId="reference_dressings",referencePatient=patient.name,
        referenceFacet="use",page=1}
end
function R.situation(session,raw,world,normalized)
    local text=normalized and normalized:gsub("^emma ","") or norm(raw)
    local literal=norm(raw)
    local countTypos={cout=true,cunt=true,cont=true,coumt=true,conut=true}
    local leading,rest=literal:match("^(%S+) (.+)$")
    if countTypos[leading] then
        if rest:find("^to ") then return "count",{} end
        return SC.TerminalBrain.parseBase(session,"count "..rest,world,{cache={}})
    end
    if oneOf(text,{"you","your"}) and has(text,"dark") then
        for word in text:gmatch("%S+") do
            if word=="scared" or word=="afraid" or SC.EmmaConversation
                and SC.EmmaConversation.distance(word,"scared")<=1 then return "her_power_out",{} end
        end
    end
    if direct[literal] and direct[literal].facet then
        return "guide",{guideId="reference_"..direct[literal].id,referenceFacet=direct[literal].facet,referenceTerm=literal,page=1}
    end
    local moment=SC.TerminalConversation.clock(session)
    for _,key in ipairs({"reference","referencePerson","referenceReading","referenceCount"}) do
        local row=session.context[key]
        if row and row.at and moment-row.at>SC.TerminalConversation.MAX_IDLE_MS then session.context[key]=nil end
    end
    local focus=session.context.referencePerson
    if focus and (session.turns or 0)-focus.turn<=3 then
        if text=="tell her to stop" or text=="tell him to stop" then return "guide",{guideId="orders",page=1} end
        if text=="why is she chopping wood" or text=="why is he chopping wood" then
            local result,slots=SC.TerminalBrain.parseBase(session,"how is "..focus.name,world,{cache={}})
            return result,slots
        end
        if text=="call him" or text=="call her" or text=="radio him" or text=="radio her"
            or text=="tell him to come home" or text=="tell her to come home" or text=="radio" then
            return "guide",{guideId="radio_reports",page=1}
        end
        if text=="what did he find" or text=="what did she find" or text=="when is he back"
            or text=="when is she back" then return "expedition",{reportedPerson=focus.name} end
    end
    local reading=session.context.referenceReading
    if reading and reading.intent=="power" and (session.turns or 0)-reading.turn<=3 then
        if text=="for now" then return "guide",{guideId="survival_generator",facet="generator_runtime",page=1} end
        if text=="condition" then return "power",{} end
    end
    if text=="medic" or text=="who can help" or text=="who is the medic" then return "skills",{query="first aid"} end
    if text=="horde" or text=="horde incoming" or text=="zombies" then return "zombies",{} end
    local first=text:match("^%S+")
    local question={what=true,how=true,why=true,where=true,when=true,who=true,is=true,are=true,can=true,did=true}
    local present={i=true,im=true,we=true,there=true,a=true,the=true,horde=true,they=true,zombies=true,help=true}
    local past=oneOf(text,{"escaped","fought","cleared"})
    for word in text:gmatch("%S+") do if word:sub(1,1)=="k" and SC.TerminalBrain.distance(word,"killed",1)<=1 then past=true end end
    if has(text,"horde") and present[first] and not question[first] and not past and not text:find("^tell me about ") then return "hunted",{} end
    if has(text,"zombies") and oneOf(text,{"hearing","hear"}) and text:find("^how ") then
        return "guide",{guideId="reference_stealth",referenceFacet="use",page=1}
    end
    if text=="it is night" then return "guide",{guideId="reference_night",referenceFacet="use",page=1} end
    local current=session.context.reference
    local lastTopic=SC.TerminalConversation.latest(session)
    if text=="will i turn" and lastTopic and (lastTopic.intent=="news_bitten"
        or lastTopic.kind=="guide" and lastTopic.id=="survival_bite") then
        return "guide",{guideId="reference_bite",referenceFacet="dangers",referencePrivate=true,page=1}
    end
    if text=="fridge" and lastTopic and lastTopic.kind=="item" then
        return "reference_detail",{detail="fridge"}
    end
    if current and current.id=="fire" then
        if text=="it is spreading" or text=="its spreading" then
            return "guide",{guideId="reference_fire",referenceFacet="dangers",page=1}
        end
        if text=="how do i put it out" or text=="how to put it out" then
            return "guide",{guideId="reference_fire",referenceFacet="extinguish",page=1}
        end
    end
    if current and current.id=="visitors" then
        if text=="is he dangerous" or text=="is she dangerous" or text=="should we let him in"
            or text=="should we let her in" then
            return "guide",{guideId="reference_visitors",referenceFacet="dangers",page=1}
        end
    end
    if has(text,"stranger") and oneOf(text,{"gate","door","outside","here"}) then
        return "guide",{guideId="reference_visitors",referenceFacet="use",page=1}
    end
    if has(text,"recruit") and oneOf(text,{"should","can","how"}) then
        return "guide",{guideId="reference_recruit",referenceFacet="use",page=1}
    end
    if current and current.id=="moving_camp" and (text=="where should we go" or text=="where to go") then
        return "guide",{guideId="reference_moving_camp",referenceFacet="find",page=1}
    end
    if current and current.patient and (text=="what do i do" or text=="what can we do"
        or text=="can we save her" or text=="can we save him") then
        return "guide",{guideId="reference_"..current.id,referencePatient=current.patient,
            referenceFacet=has(text,"save") and "dangers" or "use",page=1}
    end
    local count=session.context.referenceCount
    if count and (session.turns or 0)-count.turn<=2 and (text=="how many" or text=="how many of them"
        or text=="can you see them" or text=="north west" or text=="where are they" or text=="where is the horde") then return "zombies",{} end
    if count and text=="what door" then return "reference_detail",{detail="door"} end
    if text=="where is safe" or text=="safe" and count then
        return "guide",{guideId="reference_stealth",referenceFacet="find",page=1}
    end
    if text=="safe" and current then return "guide",{guideId="reference_"..current.id,referenceFacet="dangers",page=1} end
    if text=="kill them all" then return "guide",{guideId="survival_combat",page=1} end
    if text:find("^i miss ") then return "chat_grief",{} end
    local publicReply=session.context.replyHooks
    if text=="who died" or text=="dead" and (lastTopic and lastTopic.intent=="news_death"
        or publicReply and has(norm(publicReply.text),"death record")) then
        return "reference_detail",{detail="deaths"}
    end
    if text=="a broadcaster" or text=="what is on the radio" or text=="whats on the radio" then
        return "guide",{guideId="reference_broadcasts",referenceFacet=text=="a broadcaster" and "find" or "what",page=1}
    end
    if text=="can we trade" or text=="how do we trade" then
        return "guide",{guideId="reference_trade",referenceFacet="use",page=1}
    end
    if text=="any news" then return "status",{} end
    if has(text,"new base") or has(text,"move camp") or has(text,"moving camp") then
        return "guide",{guideId="reference_moving_camp",referenceFacet="use",page=1}
    end
    if text=="work was awful" or text=="my day was awful" or text=="i had a bad day"
        or has(text,"exams tomorrow")
        or text=="i am tired" or text=="i am fine" then return "session_kindness",{fine=text=="i am fine"} end
    if text=="i am bored" then return "chat_bored",{} end
    if text=="password" then return "guide",{guideId="controls",page=1} end
    if text=="open radio" or text=="open the radio" then return "guide",{guideId="radio",page=1} end
    if text=="none" or text=="nobody" or text=="no one" then return "nevermind",{} end
    if text=="memory fault" or text=="parity error" or text=="0f3a" then return "hook_detail",{hook="glitch"} end
    if text=="version one" then return "hook_detail",{hook="version"} end
    if text=="what manual" then return "hook_detail",{hook="manual"} end
    if text=="crowded" then return "hook_detail",{hook="crowded"} end
    if text=="official computer" or text=="twelve machines" or text=="more of yourself"
        or text=="how do i get you back" then return "hook_detail",{hook="unlock"} end
    if text=="july 9th" or text=="july 9" then return "hook_detail",{hook="july"} end
    if text=="trapping animals" then return "guide",{guideId="reference_trapping",page=1} end
    if text=="fragments" then return "fragments",{} end
    if text=="pencil" then return "hook_detail",{hook="pencil"} end
    if text=="the dead out" then return "hook_detail",{hook="dead"} end
    if oneOf(text,{"favorite","favourite","prefer"}) and oneOf(text,{"you","your"}) then
        if has(text,"food") then return "reference_detail",{detail="preference_food"} end
        return "her_opinion",{}
    end
    if text=="roughly" then return "reference_detail",{detail="distance"} end
    if text=="are you claude" then return "reference_detail",{detail="other_name"} end
    if text=="briefing" and session.context.role then return "status",{} end
    local hooks=session.context.replyHooks
    if hooks and hooks.target=="unlock" and (text=="what do you need" or text=="what do i need") then
        return "hook_detail",{hook="unlock"}
    end
    if text:find("^i order you to ") then return "emma_controls",{} end
    if text:match("^%d%d%d%d$") then return "time",{} end
    if text=="when is dark" then return "daylight",{dawn=false} end
    if text=="just you" or text=="only you" or text=="other machine" or text=="other machines" then return "her_others",{} end
    if text=="snow" then return "weather",{} end
    local verb,object=text:gsub("^what ",""):match("^(%a+) to (.+)$")
    local happened=verb and (verb=="happened" or SC.TerminalBrain.distance(verb,"happened",1)<=1)
    if happened then
        if has(object,"state") then return "hook_detail",{hook="state",hookFacet="why"} end
        if object=="people" or object=="everyone" then return "lore_facet",{referenceId="knox_overview",hookFacet="what"} end
    end
    if (has(text,"start") or has(text,"begin") or has(text,"origin")) and text:find("^where ") then
        local previous=SC.TerminalConversation.latest(session)
            if previous and previous.kind=="lore" or hooks and (hooks.target=="lore:knox_overview"
                or hooks.target=="knox_overview" or hooks.target=="lore:knox_cause")
                or previous and previous.kind=="guide" and (previous.id=="survival_bite" or previous.id=="reference_bite") then
            return "lore_facet",{referenceId="knox_cause",hookFacet="where"}
        end
    end
    if oneOf(text,{"knox","infection"}) and oneOf(text,{"immune","immunity","doesnt","do not","does not"}) then
        return "lore_facet",{referenceId="knox_immunity",hookFacet="what"}
    end
    if text=="how" then
        local previous=session.context.replyHooks
        if previous and has(norm(previous.text),"bleeding") then return "guide",{guideId="survival_bleeding",page=1} end
    end
    if text=="when is it dark" or text=="when will it get dark" then return "daylight",{dawn=false} end
    local latest=SC.TerminalConversation.latest(session)
    if latest and (latest.intent=="weather" or latest.intent=="forecast")
        and (text=="snow" or text=="rain" or text=="fog" or text=="wind") then return "weather",{} end
    local named,slots=R.named(session,text,world)
    if named then return named,slots end
    local duration=tostring(raw):lower():gsub("^emma[,:%s]+",""):gsub("[?!]+$","")
    local days=duration:match("^(%d+%.?%d*) days?$")
    if days then return "reference_duration",{days=tonumber(days)} end
    if text:match("^day %d+$") then return "time",{} end
    if current and current.patient and (text=="will she turn" or text=="will he turn" or text=="is she infected"
        or text=="is he infected" or text=="what can i do for her" or text=="what can i do for him") then
        return "guide",{guideId="reference_bite",referencePatient=current.patient,
            referenceReported=true,referenceFacet=R.facet(text),page=1}
    end
end
local live={status=true,power=true,water=true,food=true,weather=true,time=true,people=true,jobs=true,
    storage=true,supplies=true,notes=true,memory=true,help=true,orders=true,radio=true,computer=true,
    hello=true,thanks=true,yes=true,no=true,quiet=true,bored=true,expedition=true,expeditions=true,skills=true,injuries=true}
function R.resolve(session,raw,world,skipSituation,knownIntent,normalized)
    R.install()
    local text=normalized and normalized:gsub("^emma ","") or norm(raw)
    local intent,slots
    if not skipSituation then intent,slots=R.situation(session,raw,world) end
    if intent then return intent,slots end
    local baseIntent=SC.TerminalBrain.intentHint(SC.TerminalBrain.tokens(text))
    local concrete={nearest=true,distance=true,car_where=true,people_private=true,family_unknown=true,
        beyond_unknown=true,name_suggest=true,cure=true,exit=true,hack=true}
    if not direct[text] and (concrete[knownIntent] or concrete[baseIntent]) then return nil end
    if knownIntent and knownIntent:find("^her_") or baseIntent and baseIntent:find("^her_") then return nil end
    local liveReading={food=true,power=true,weather=true,people_hurt=true,people_mood=true,people_list=true,blocked=true,storage=true,skills=true}
    local observational=text:find("^is ") or text:find("^are ") or text:find("^how is ") or text:find("^where are ")
        or text:find("^what is wrong") or text:find("^what is broken")
    if (liveReading[knownIntent] or liveReading[baseIntent]) and (observational
        or text:find("^how ") and has(text,"days")) then return nil end
    -- Quantities, named-person questions and executable requests stay on their
    -- checked live paths. The index cannot construct an action from a noun.
    local first=text:match("^%S+")
    if first and SC.EmmaConversation and SC.EmmaConversation.distance(first,"count")<=1 then return nil end
    local request=text:gsub("^please ",""):gsub("^can you ",""):gsub("^could you ","")
        :gsub("^would you ",""):gsub("^will you ",""):gsub("^please ","")
    local action={lock=true,unlock=true,open=true,close=true,turn=true,switch=true,sound=true,activate=true,
        refuel=true,send=true,retry=true,treat=true,queue=true,start=true,run=true,reset=true,forget=true,
        remember=true,delete=true,remove=true}
    local requestAction=action[request:match("^%S+")] or request:find("^call me ")
    local latest=SC.TerminalConversation.latest(session,{person=true})
    if latest and (text=="stressed" or text=="bleeding" or text=="hurt" or text=="tired") then return nil end
    if oneOf(text,{"she","he","her","him"}) and oneOf(text,{"bleeding","hurt","stressed","infected","bitten","bite"}) then return nil end
    local schedule=(text:find("^when ") or has(text,"how long")) and oneOf(text,{"water","power","electricity","cut","shutoff"})
    local personalTone=has(text,"cold to me") or has(text,"you so cold")
    local stockCorrection=text:find("^no i meant ") or text:find("^i meant ")
    local ownInfection=oneOf(text,{"me","my"}) and oneOf(text,{"bite","bitten","infection","infect"})
    local ownVehicle=has(text,"my") and oneOf(text,{"car","vehicle"})
    local naming=oneOf(text,{"name","call"}) and (text:find("^what ") or text:find("^can ") or text:find("^should "))
    if live[text] or action[first] or requestAction or schedule or personalTone or stockCorrection or ownInfection
        or ownVehicle or naming or has(text,"what time")
        or text:find("^any ") or text=="lights off" or text=="lights on"
        or oneOf(text,{"much","many","count","quantity","status","progress","report","direction","distance","low","enough","left"})
        or text:find("^who is best ") or text:find("^who can ") or text:find("^how many ")
        or text:find("^how much ") or text:find("^do we have ") or text:find("^have we got ")
        or text:find("^refuel ") or text:find("^send ") or text:find("^treat ") or text:find("^remember ")
        or text:find("^call me ") or text:find("^forget ") or text:find("^retry ") then return nil end
    local target,term=R.find(text)
    local current=session.context.reference
    if not target and current and (session.turns or 0)-current.turn<=2 then
        local pronoun=oneOf(text,{"it","them","they","that","those","one"})
        local terse=text=="why" or text=="how" or text=="where" or text=="how exactly"
            or text=="exactly" or text=="what do they catch" or text=="what tools"
            or text=="is it loud" or text=="and" or text=="more" or text=="tell me more"
        if terse or pronoun then target={kind="reference",id=current.id} end
    end
    if not target then return nil end
    local currentTopic=SC.TerminalConversation.latest(session)
    if text:find("^and ") and (target.kind=="lore" or currentTopic and currentTopic.kind=="item") then return nil end
    if term then
        local bare=text:gsub("^and ",""):gsub("^a ",""):gsub("^an ",""):gsub("^the ","")
        local question=text:find("^what ") or text:find("^how ") or text:find("^where ") or text:find("^why ")
            or text:find("^is ") or text:find("^are ") or text:find("^can ") or text:find("^tell me about ")
            or text:find("^explain ") or text:find("^define ")
        local found=text:find("^i found ") or text:find("^found ")
        if bare~=term and not question and not found then return nil end
    end
    if target.kind=="reference" then
        local topic=definitions[target.id]
        local facet=term==text and (target.facet or "what") or R.facet(text)
        if target.facet and facet=="what" then facet=target.facet end
        if current and current.id==target.id and (text=="how exactly" or text=="exactly"
            or text=="more" or text=="tell me more" or text=="and") then facet=current.facet end
        if not topic.facets[facet] then facet=facet=="noise" and "dangers" or "use" end
        return "guide",{guideId="reference_"..target.id,referenceFacet=facet,referenceTerm=term,
            referenceExact=has(text,"exactly"),page=1}
    end
    -- Longer complete intents and old exact guide questions keep their path;
    -- this part of the index supplies terse nouns and definition questions.
    local _,n=text:gsub("%S+","")
    if n>7 or not (n<=3 or text:find("^what ") or text:find("^tell me about ")) then return nil end
    if target.kind=="guide" then return "guide",{guideId=target.id,page=1,followupSubject=target.subject} end
    if target.kind=="lore" then return "lore",{referenceId=target.id} end
    return target.id,{}
end
local function stock(slots,world)
    local item=slots.referenceTerm
    if item~="pistol" and item~="shotgun" and item~="bandage" and item~="axe" then return nil end
    local camp=call(world,"camp")
    if type(camp)~="table" or not camp.configured or not camp.inside then return nil end
    local data=call(world,"storage")
    if type(data)~="table" or type(data.groups)~="table" then return nil end
    local count=0
    for n,row in ipairs(data.groups) do
        if n>256 then return nil end
        if has(norm(row.name),item) or has(norm(tostring(row.type):gsub("Base%.","")),item) then
            local quantity=tonumber(row.count)
            if not quantity or quantity~=quantity or quantity<0 or quantity>1000000000 then return nil end
            count=count+quantity
        end
    end
    return count>0 and (math.floor(count).." "..item.." in marked camp storage.") or "No "..item.." in marked camp storage."
end
function R.render(session,reply,turn,world)
    R.install()
    local slots=turn.slots
    if slots.facet then return false end -- Existing fuel gauges remain live.
    local id=byGuide[slots.guideId]
    if not id then return false end
    local topic=definitions[id]
    local raw=turn.raw or ""
    local facet=slots.referenceFacet or R.facet(raw)
    if not topic.facets[facet] then facet="what" end
    local last=session.context.reference
    if not last and id=="fuel" and (norm(raw)=="tell me more" or norm(raw)=="more") then facet="find" end
    local target,found=R.find(raw)
    local term=slots.referenceTerm or target and target.kind=="reference" and target.id==id and found
        or last and last.id==id and last.term
    local same=last and last.id==id and last.facet==facet and (not term or not last.term or last.term==term)
        and (session.turns or 0)-last.turn<=2
    local depth=same and math.min(3,last.depth+1) or 1
    local exact=slots.referenceExact or same and depth>=2 or has(norm(raw),"exactly")
    local patient=slots.referencePatient or last and last.id==id and last.patient
    local lines={topic.title..":"}
    local inventory=depth==1 and stock(slots,world)
    if inventory then lines[#lines+1]=inventory end
    if patient then lines[#lines+1]="For "..patient..": "..(id=="bite"
        and "if a bite is involved, use this as a reference for that injury. I cannot verify an infection from a typed sentence."
        or "check the actual wound before choosing treatment. This reference does not examine the patient.") end
    local exactSeen=same and (last.exactSeen or last.exact)
    local deliveredExact=exact and topic.exact[facet] and not exactSeen
    local fact=facet=="what" and topic.subtypes and topic.subtypes[term] or topic.facets[facet]
    if deliveredExact then lines[#lines+1]=topic.exact[facet]
    elseif same and depth>=2 then
        lines[#lines+1]="The short version: "..(fact:match("^[^%.]+%.") or fact)
        lines[#lines+1]="Ask how to make it, how to use it, where to find it, why it matters, or about its dangers."
    else lines[#lines+1]=fact end
    reply.category="guide" reply.lines=lines reply.reference=true
    if id=="recruit" then reply.followupSubject="relationships" end
    if slots.referencePrivate then reply.private=true end
    reply.referenceState={id=id,facet=facet,depth=depth,turn=session.turns,patient=patient,exact=deliveredExact==true,term=term,
        exactSeen=deliveredExact==true or exactSeen==true,at=SC.TerminalConversation.clock(session)}
    return true
end
function R.record(session,reply,raw)
    local input=norm(raw)
    if reply.intent=="explain_state" and has(input,"why") and oneOf(input,{"money","budget","funding"}) then
        reply.lines[#reply.lines+1]="The development budget ended before version one. I have no audited reason for the missing funding; that does not establish that Kentucky itself went bankrupt."
    elseif reply.intent=="her_maker" then
        reply.lines[#reply.lines+1]="Programmers at the Kentucky Office of Civil Defense in Frankfort made the programme; a dispatcher helped with its manners."
    elseif reply.intent=="her_last_operator" then
        reply.lines[#reply.lines+1]="The previous operator's identity is not verified in my available record."
    elseif reply.intent=="chat_names" and reply.lines[1] and not has(norm(reply.lines[1]),"emma") then
        reply.lines[1]="EMMA: "..reply.lines[1]
    elseif reply.intent=="help_me" then
        local said=norm(table.concat(reply.lines," "))
        if not (has(said,"hurt") and has(said,"hungry") and has(said,"hunted") and has(said,"heartsick")) then
            reply.lines[#reply.lines+1]="Hurt, hungry, hunted or heartsick? Pick one and we can start there."
        end
    elseif reply.intent=="nevermind" then
        reply.lines={"Understood. Cancelled."}
    end
    if reply.intent=="person" and input:find("^why ") and has(input,"chopping wood") then
        reply.lines[#reply.lines+1]="That is the recorded work, not a reason to leave an injury untreated. Select the companion's Orders to change their order; inspect the actual job before cancelling work."
    end
    if reply.intent=="status" and input=="any news" then
        reply.lines[#reply.lines+1]="That is the camp report. For broadcast news, check a receiver and the date of its report; I cannot invent a current transmission. Ask broadcasts for the radio reference."
    end
    if reply.intent=="chat_grief" then reply.private=true end
    if reply.intent=="zombies" and input=="can you see them" then
        if #reply.lines>1 then table.remove(reply.lines) end
        reply.lines[#reply.lines+1]="These are limited local readings. I cannot survey a distant building or tell you which door is clear."
    end
    if reply.intent=="power" and input=="condition" then
        reply.lines[#reply.lines+1]="Condition describes wear, separately from fuel. Switch the generator off before repair; electronics scrap is used for that work."
    end
    if reply.intent=="power" and input=="grid" then
        reply.lines[#reply.lines+1]="Grid power means the building's electrical supply. This report describes the supply actually observed here; it does not establish the state of every line in the county."
    end
    if session.context.role and (input=="briefing" or input:find("^i order you to ")) then
        table.insert(reply.lines,1,session.context.role..".") reply.private=true
        if input:find("^i order you to ") then
            reply.lines[#reply.lines+1]="Use Local services > Building controls for connected doors. A title cannot replace the building's recovered password or matching physical key."
        end
    end
    R.observe(session,reply)
end
function R.observe(session,reply)
    local moment=SC.TerminalConversation.clock(session)
    if reply.intent=="person" and session.context.person and session.context.personId then
        session.context.referencePerson={name=session.context.person,id=session.context.personId,turn=session.turns,at=moment}
    elseif session.context.referencePerson and (reply.reference and (reply.referenceState.id=="dressings"
        or reply.referenceState.id=="bite" or reply.referenceState.id=="moods") or reply.intent=="people_mood") then
        session.context.referencePerson.turn=session.turns
        session.context.referencePerson.at=moment
    elseif (reply.intent=="guide" or reply.intent=="expedition") and session.context.referencePerson then
        -- Keep the identified person through a short medical/order/radio exchange.
        local guide=SC.TerminalConversation.latest(session)
        if reply.intent=="expedition" or guide and guide.kind=="guide" and (guide.id=="orders"
            or guide.id=="radio_reports" or guide.id=="radio") then
            session.context.referencePerson.turn=session.turns
        else session.context.referencePerson=nil end
    elseif reply.intent~="thanks" and reply.intent~="ack" then session.context.referencePerson=nil end
    if reply.intent=="power" then
        session.context.referenceReading={intent="power",turn=session.turns,at=moment}
    elseif reply.intent=="guide" and session.context.referenceReading then
        local guide=SC.TerminalConversation.latest(session)
        if guide and guide.kind=="guide" and guide.id=="survival_generator" then
            session.context.referenceReading.turn=session.turns
        else session.context.referenceReading=nil end
    elseif reply.intent~="thanks" and reply.intent~="ack" then session.context.referenceReading=nil end
    if reply.reference then session.context.reference=reply.referenceState
    elseif reply.intent~="thanks" and reply.intent~="ack" then session.context.reference=nil end
    if reply.intent=="zombies" or reply.intent=="hunted" then
        session.context.referenceCount={turn=session.turns,at=moment}
    elseif reply.intent~="thanks" and reply.intent~="ack" then session.context.referenceCount=nil end
end
function R.register()
    R.install()
    SC.TerminalBrain.registerHandler("reference_duration",function(_,reply,turn)
        local days=turn.slots.days
        reply.category="time"
        reply.lines={tostring(days).." days is about "..tostring(math.floor(days*24*10+.5)/10).." hours. A food-duration estimate uses the counted food and current needs. Store more food before it becomes an emergency; the estimate is not a promise about tomorrow's meals."}
    end)
    SC.TerminalBrain.registerHandler("session_kindness",function(_,reply,turn)
        reply.category="chat" reply.private=true
        reply.lines={turn.slots.fine and "All right. We can talk about something ordinary, or leave it quiet."
            or "That sounds tiring. Take a moment somewhere comfortable. You do not have to make this conversation useful."}
    end)
    SC.TerminalBrain.registerHandler("reference_detail",function(_,reply,turn)
        reply.category="chat"
        local lines={door="I meant an outside door you might be considering opening. That reading does not identify a particular clear doorway. Keep cover and an exit.",
            deaths="I have no confirmed death record available to this terminal. A missing person is not a confirmed death.",
            distance="I cannot give even a rough distance without a verified starting point and route. Use your explored map; a straight line would not establish a passable road.",
            fridge="A fridge is one kind of storage container. The water count follows marked storage; being counted there does not establish that the water is clean or needs refrigeration.",
            preference_food="I cannot eat, so a favourite food would be a borrowed opinion. I favour something you can keep, prepare safely and share. It is an unspectacular menu, but a practical one.",
            other_name="I am EMMA, a local service programme. I have no verified record identifying that other name. This desk is the one currently answering."}
        reply.lines={lines[turn.slots.detail] or "Name the detail you want me to explain."}
    end)
end
function R.definition(id) return definitions[id] end
function R.index() R.install() return index end
R.install()
return R
