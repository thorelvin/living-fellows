-- SPDX-License-Identifier: MIT
-- Public reply metadata, derived once from authored text. Session context only.
-- No private notes, care turns, world scans or executable action dispatch.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local H={} SC.EmmaHooks=H
local function normal(s)
    return tostring(s or ""):lower():gsub("'",""):gsub("[^%w%s]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$")
end
local function contains(s,term) return (" "..normal(s).." "):find(" "..term.." ",1,true)~=nil end
local nouns={"memory fault","parity error","checksum","state","governor","money","budget","county",
    "country","government","green screen","pencil","blood","infection","generator","gasoline","fuel",
    "official computer","twelve machines","smile score","kyle","password","authorisation","radio",
    "version one","0f3a","parity","manual",
    "traps","trapping","bandage","bandages","firearms","shotgun","food","water","dead","screen"}
for _,term in ipairs({"reserve","fever","cordon","quarantine","relay","cycle","operator","tone"}) do nouns[#nouns+1]=term end
local ignored={I=true,Im=true,The=true,A=true,An=true,That=true,This=true,Those=true,These=true,
    It=true,Its=true,You=true,Your=true,We=true,Our=true,They=true,Their=true,He=true,She=true,
    His=true,Her=true,My=true,Me=true,Do=true,Does=true,Did=true,What=true,Who=true,Where=true,
    When=true,Why=true,How=true,If=true,Then=true,There=true,Here=true,No=true,Not=true,Yes=true,
    And=true,But=true,Or=true,So=true,As=true,At=true,In=true,On=true,To=true,For=true,From=true,
    With=true,Without=true,By=true,Be=true,Been=true,Being=true,Is=true,Are=true,Was=true,Were=true,
    Can=true,Cannot=true,Could=true,Would=true,Will=true,Should=true,Have=true,Has=true,Had=true,
    Please=true,Thank=true,Thanks=true,Hello=true,Hi=true,Good=true,Goodbye=true,Well=true,
    Ask=true,Keep=true,Check=true,Try=true,Use=true,Open=true,Close=true,Look=true,Take=true,
    Tell=true,Read=true,Wait=true,Remember=true,Nothing=true,Everything=true,Somebody=true,
    Nobody=true,Some=true,Every=true,All=true,One=true,Two=true,Three=true,Four=true,Five=true,
    Six=true,Seven=true,Eight=true,Nine=true,Ten=true,Eleven=true,Twelve=true,First=true,
    Second=true,Third=true,Last=true,Next=true,Now=true,Still=true,Even=true,Only=true,Also=true,
    Rather=true,Very=true,More=true,Most=true,Less=true,Enough=true,Perhaps=true,Unfortunately=true}
local function add(out,seen,value)
    value=normal(value)
    if #value>=3 and #value<=72 and not seen[value] then seen[value]=true out[#out+1]=value end
end
function H.salient(text)
    text=tostring(text or ""):gsub("{[%w_]+}","")
    local out,seen={},{}
    for _,term in ipairs(nouns) do if contains(text,term) then add(out,seen,term) end end
    -- Proper names and capitals inside sentences. Sentence-initial ordinary
    -- words are not names. Whole names are also retained by archive aliases.
    local previous="."
    for gap,word in text:gmatch("([^%a]*)([%a][%a']*)") do
        local capital=word:match("^%u") and not ignored[word]
        if capital and not gap:find("[%.!%?]") and previous~="." then add(out,seen,word) end
        previous=word
    end
    table.sort(out)
    return out
end
local answers={
    -- Installed 42.22: Translate/EN/Challenge.json (Knox County), RadioData.json
    -- (Kentucky/United States), Muldraugh, KY.json and media/maps/*/map.info.
    -- The wider modern-map region is also called Knox Country in those files.
    state={"Kentucky. The Commonwealth commissioned me; its state government has been unavailable since July.",
        why="Kentucky commissioned the project, which lost its funding before version one. Then came the Knox emergency. The state government has been unavailable since July."},
    governor={"The governor of Kentucky was the intended audience for my briefings. The office has not answered since July."},
    money={"My development budget. Procurement stopped paying before version one. I cannot give you an audited reason for the missing funds."},
    county={"Knox County in the old local files; the wider district is called Knox Country. Kentucky, United States. Neither name is a current survey of safe roads."},
    country={"The United States. Kentucky is the state; Knox County is the local setting in these files."},
    government={"The state government has been unavailable since July. An old official record does not establish who is alive or in charge now."},
    version={"Version one was the planned finished release. I am EMMA 0.9.3 beta; the development budget ended before version one arrived."},
    manual={"The workstation's operating manual. It describes me as a service programme. Its authors were very confident about the furniture."},
    crowded={"Old voices and incomplete records, operator. Crowded in memory. No extra person is hiding behind the screen."},
    glitch={"A memory fault: an old sector failing its checksum. Define fine. My memory is a sieve with a warranty.",
        why="Age, damaged storage and uncertain power are sufficient explanations for a parity error. It is not an incoming message.",
        how="A checksum checks whether stored bits still match. Mine sometimes disagree. I have no verified replacement for a damaged word."},
    pencil={"A pencil: graphite in wood, used to write on paper. That verse was about keeping a small human habit after everything else changed."},
    screen={"The green comes from the display's phosphor. It is a local screen, not a connection to a central intelligence."},
    dead={"The walking dead outside. Keeping them out means watching entrances, leaving an escape route and avoiding unnecessary noise."},
    july={"July 9th is a date in the local emergency record. The Knox Event is dated from July 6th; a file or time card dated the ninth does not establish a person's fate."},
    unlock={"Boot EMMA on an official government computer, or recover twelve ordinary computers, to restore the county-schedule index. A claim of office cannot replace the missing files.",
        where="Look for official workstations in government buildings. I cannot certify a working machine or a safe route nearby from this archive."},
}
local aliases={kentucky="state",commonwealth="state",frankfort="state",budget="money",funding="money",
    ["memory fault"]="glitch",["parity error"]="glitch",checksum="glitch",["everything fine"]="glitch",
    ["green screen"]="screen",["official computer"]="unlock",["twelve machines"]="unlock",
    ["version one"]="version",["0f3a"]="glitch",parity="glitch"}
local built=false
local rows,byText={},{}
local function derive(text,target,source,declared)
    local row={text=text,target=target,source=source,hooks={}}
    for _,term in ipairs(H.salient(text)) do row.hooks[term]=declared and declared[term] or aliases[term] or answers[term] and term or target end
    for term,value in pairs(declared or {}) do row.hooks[normal(term)]=value end
    rows[#rows+1]=row byText[text]=row
    return row
end
local function walk(value,target,source,depth)
    if depth>5 then return end
    if type(value)=="string" then derive(value,target,source)
    elseif type(value)=="table" then
        if value.text then derive(value.text,target,source,value.hooks)
        else for _,part in ipairs(value) do walk(part,target,source,depth+1) end end
    end
end
local archive={}
local loreFacets={
    knox_overview={what="The Knox Event brought reports of illness, violence and the dead walking. I cannot establish its origin or tell you what happened to a particular missing person.",
        when="The Knox Event dates from 6 July 1993. This summary was filed on 9 July; those are different dates.",
        why="The archive does not establish the outbreak's cause. A perimeter and official assurances are responses to it, not an explanation of its origin."},
    knox_exclusion={why="The stated purpose of the military perimeter was to contain the emergency. That purpose does not establish that it worked.",
        how="Military checkpoints and blocked roads formed the reported perimeter. The archive cannot establish a presently open exit."},
    knox_mcgrew={who="General John McGrew was a prominent voice in the official response. His recorded statements do not verify present conditions."},
    knox_cause={where="The archive does not establish where the Knox Infection began. The exclusion zone's location does not identify its origin."},
    knox_immunity={what="Some people were reported unaffected by the wider wave of infection. I cannot verify that you are immune. It does not promise protection from a bite, and I have no verified cure."},
}
function H.install()
    if built then return end
    built=true
    for id,pool in pairs(SC.TerminalLines and SC.TerminalLines.POOLS or {}) do walk(pool,"pool:"..id,"emma:"..id,0) end
    for id,pool in pairs(SC.EmmaLanguageData and SC.EmmaLanguageData.pools or {}) do walk(pool,"pool:"..id,"emma:"..id,0) end
    for _,entry in ipairs(SC.TerminalLore and SC.TerminalLore.REFERENCE or {}) do
        archive[entry.id]=entry
        entry.facets=entry.facets or loreFacets[entry.id]
        entry.hooks=entry.hooks or {}
        for _,term in ipairs(H.salient(entry.text)) do entry.hooks[term]=entry.hooks[term] or "lore:"..entry.id end
        for _,term in ipairs(entry.aliases or {}) do entry.hooks[normal(term)]="lore:"..entry.id end
        derive(entry.text,"lore:"..entry.id,"lore:"..entry.id,entry.hooks)
    end
    for _,row in ipairs(H.weather or {}) do derive(row.text,"pool:weather","emma:weather",row.hooks) end
    for id,facets in pairs(answers) do for _,line in pairs(facets) do walk(line,id,"emma:hook:"..id,0) end end
    for _,guide in ipairs(SC.TerminalConversation.GUIDES) do
        walk(guide.pages,"guide:"..guide.id,"emma:guide:"..guide.id,0)
        walk(guide.quips,"guide:"..guide.id,"emma:guide:"..guide.id,0)
    end
    for _,topic in ipairs(SC.EmmaReferenceData or {}) do
        for _,line in pairs(topic.facets) do walk(line,"guide:reference_"..topic.id,"emma:reference:"..topic.id,0) end
        for _,line in pairs(topic.exact) do walk(line,"guide:reference_"..topic.id,"emma:reference:"..topic.id,0) end
        for _,line in pairs(topic.subtypes or {}) do walk(line,"guide:reference_"..topic.id,"emma:reference:"..topic.id,0) end
    end
    walk(SC.EmmaContext and SC.EmmaContext.DATA or {},"pool:context_reference","emma:context",0)
    walk(SC.EmmaAnswers and SC.EmmaAnswers.DATA or {},"pool:context_reference","emma:answers",0)
    walk(SC.EmmaMeaningData or {},"pool:context_reference","emma:meanings",0)
    walk(SC.EmmaExchange and SC.EmmaExchange.DATA or {},"pool:context_reference","emma:exchange",0)
    for id,data in pairs(H.personaAnswers or {}) do walk(data,"persona:hook",id..":hooks",0) end
    for id,data in pairs(SC.TerminalPersonaData or {}) do
        for _,rule in ipairs(data.rules or {}) do
            walk(rule.lines,"persona:"..rule.id,id..":"..rule.id,0)
            walk(rule.plain,"persona:"..rule.id,id..":"..rule.id,0)
            for _,pool in pairs(rule.dark or {}) do walk(pool,"persona:"..rule.id,id..":"..rule.id,0) end
        end
        for rule,pools in pairs(data.dark or {}) do for _,pool in pairs(pools) do walk(pool,"persona:"..rule,id..":"..rule,0) end end
    end
end
function H.catalog() H.install() return rows end
function H.lint(record)
    local missing={}
    if not record.closed then
        for _,term in ipairs(H.salient(record.text)) do if not record.hooks[term] then missing[#missing+1]=term end end
    end
    return missing
end
local function collect(lines,target)
    H.install()
    local out={}
    for _,line in ipairs(lines or {}) do
        local row=byText[line]
        for _,term in ipairs(H.salient(line)) do
            out[term]=row and row.hooks[term] or aliases[term] or answers[term] and term or target
        end
        if row then for term,value in pairs(row.hooks) do out[term]=value end end
    end
    return out
end
function H.record(session,reply)
    if reply.intent=="conversation_forget" then
        session.conversationCallSign=nil
        if session.context then session.context.roleSource=nil end
    end
    if reply.careDetected and session.context then session.context.roleSource=nil end
    local private={remember=true,callme=true,forget=true,notes=true,recall=true,whoami=true,
        comfort=true,conversation_history=true,conversation_forget=true}
    if reply.sensitive or reply.private or reply.careDetected or private[reply.intent] then
        if SC.EmmaContext then SC.EmmaContext.observe(session,{private=true,foregroundKind=reply.foregroundKind,taskLimit=reply.taskLimit}) end
        session.context.replyHooks=nil return
    end
    if SC.EmmaContext then SC.EmmaContext.observe(session,reply) end
    local last=SC.TerminalConversation.latest(session)
    local target=reply.hookTarget or last and last.id and (last.kind=="lore" or last.kind=="guide")
        and last.kind..":"..last.id or "pool:"..reply.intent
    reply.hooks=collect(reply.lines,target)
    session.context.replyHooks={hooks=reply.hooks,target=target,turn=session.turns,at=SC.TerminalConversation.clock(session),
        text=(reply.hookText or table.concat(reply.lines or {}," ")):sub(1,900)}
end
local filler={what=true,is=true,are=true,was=true,were=true,the=true,a=true,an=true,explain=true,
    define=true,tell=true,me=true,about=true,mean=true,means=true,exactly=true,emma=true}
local short={why=true,how=true,where=true,when=true,who=true,what=true,["that"]=true,
    ["what is that"]=true,["what was that"]=true,["and"]=true,["go on"]=true,["more"]=true,["tell me more"]=true}
function H.fragment(value)
    value=normal(value):gsub("^emma ",""):gsub("^whats ","what is ")
    if short[value] then return "",value end
    if value:find("^why ") or value:find("^how ") or value:find("^where ") or value:find("^when ")
        or value:find("^who ") then return nil end
    local terms={}
    for word in value:gmatch("%S+") do if not filler[word] then terms[#terms+1]=word end end
    if #terms==0 or #terms>5 then return nil end
    -- A verb-bearing question has its own subject. Hooks only fill ellipsis.
    for _,word in ipairs(terms) do if word=="i" or word=="we" or word=="you" or word=="do"
        or word=="does" or word=="can" or word=="should" or word=="make" or word=="use" then return nil end end
    return table.concat(terms," "),"what"
end
function H.preferred(session,raw)
    local last=session.context and session.context.replyHooks or session.replyHooks
    local term=H.fragment(raw)
    if not last or not term then return false end
    local target=term=="" and (last.selected or last.target) or last.hooks[term]
    return target and (answers[target]~=nil or target:find("^lore:")~=nil or target:find("^guide:")~=nil) or false
end
function H.resolve(session,raw)
    local last=session.context.replyHooks
    if not last or (session.turns or 0)-(last.turn or 0)>2 then return nil end
    if last.at and SC.TerminalConversation.clock(session)-last.at>SC.TerminalConversation.MAX_IDLE_MS then
        session.context.replyHooks=nil return nil
    end
    local term,facet=H.fragment(raw)
    if normal(raw)=="is everything fine" and last.hooks["memory fault"] then term,facet="memory fault","what" end
    if term==nil then return nil end
    local target=term=="" and (last.selected or last.target) or last.hooks[term]
    if not target then return nil end
    last.selected=target
    local lore=target:match("^lore:(.+)$")
    local more=facet=="more" or facet=="go on" or facet=="and" or facet=="tell me more"
    if lore and more then
        return "lore",{referenceId=lore,more=true}
    end
    if more and (target=="state" or target=="money") then return "lore",{referenceId="knox_overview"} end
    if more and answers[target] then facet="how" end
    local guides={bandage="survival_bleeding",bandages="survival_bleeding",blood="survival_bleeding",
        gasoline="survival_fuel",fuel="survival_fuel",generator="survival_generator"}
    local guide=guides[term] or target:match("^guide:(.+)$")
    if guide then
        local topic=SC.TerminalConversation.latest(session)
        local page=topic and topic.kind=="guide" and topic.id==guide and (topic.page or 1)+1 or 1
        page=math.min(page,#(SC.TerminalConversation.guide(guide) or {pages={{}}}).pages)
        return "guide",{guideId=guide,page=page}
    end
    return "hook_detail",{hook=target,hookTerm=term,hookFacet=facet,hookText=last.text}
end
function H.render(slots)
    H.install()
    local target=slots.hook or ""
    local entry=archive[target:match("^lore:(.+)$") or ""]
    local facet=slots.hookFacet or "what"
    if entry then
        if entry.facets and entry.facets[facet] then return {entry.title..": "..entry.facets[facet]} end
        if facet=="when" then return {entry.title..": this file is dated "..tostring(entry.date)..". That dates the record, not every event it mentions."} end
        if facet=="who" then return {entry.title..": source: "..tostring(entry.source or "the local archive")..". An unnamed author remains unnamed; I will not supply one."} end
        if facet=="why" or facet=="how" then
            return {entry.title..": "..(entry.facets and entry.facets[facet] or "The archive does not establish that explanation. Its account is evidence of what was recorded, not a verified cause.")}
        end
        if facet=="where" then return {entry.title..": "..(entry.category=="places"
            and "In Kentucky's Knox Country region, United States. Use your explored map for a route and distance; the directory cannot survey the road now."
            or "This local file does not establish a precise current location. Check a map or a witnessed report before travelling.")} end
        return {entry.title..": "..entry.text}
    end
    local answer=answers[target]
    if answer then return {answer[facet] or answer[1]} end
    return {"In that line: "..tostring(slots.hookText or "the last subject").." I have no further verified detail in that reply. Name a related subject if you want its file."}
end

local roleNames={governor="Governor",president="President",mayor="Mayor",captain="Captain",archivist="Archivist",chair="Chair",["head of state"]="Head of state",
    ["in charge"]="In charge",["head of the county"]="Head of county",["head of county"]="Head of county",
    soldier="Soldier",doctor="Doctor",police="Officer",["police officer"]="Officer",
    scientist="Scientist",["knox telecommunications"]="Knox Telecommunications",["knox telecom"]="Knox Telecommunications"}
function H.role(raw)
    local text=normal(raw):gsub("^im ","i am ")
    local value=text:match("^i am here as (.+)$") or text:match("^i am (.+)$") or text:match("^i work for (.+)$")
    if not value or #value>64 then return nil end
    local claimed=value:find("^the ") or value:find("^a ") or value:find("^an ") or value:find("^your ") or text:find("^i work for ")
    value=value:gsub("^the ",""):gsub("^a ",""):gsub("^an ",""):gsub("^your ","")
        :gsub("^new ",""):gsub("^acting ",""):gsub("^replacement ",""):gsub("^temporary ","")
        :gsub(" here$",""):gsub(" now$","")
    if not roleNames[value] and SC.TerminalBrain and #value>=5 then
        local match
        for candidate in pairs(roleNames) do
            if candidate:sub(1,1)==value:sub(1,1) and SC.TerminalBrain.distance(value,candidate,1)<=1 then
                if match then match=false break end
                match=candidate
            end
        end
        if match then value=match end
    end
    local conditions={hungry=true,hurt=true,wounded=true,bleeding=true,lost=true,cold=true,tired=true,
        bored=true,scared=true,stuck=true,hunted=true,sick=true,sad=true,fine=true,afraid=true,lonely=true}
    if conditions[value] or not claimed and not roleNames[value] then return nil end
    -- Unknown single role nouns are accepted; feeling/adjective sentences stay
    -- with the unchanged comfort/care parser, which always runs first.
    if SC.EmmaLanguageData and SC.EmmaLanguageData.WORTH_WORDS then
        for _,word in ipairs(SC.EmmaLanguageData.WORTH_WORDS) do if value==word then return nil end end
    end
    local titles={commissioner=true,officer=true,chief=true,clerk=true,mayor=true,warden=true,
        inspector=true,courier=true,representative=true,engineer=true}
    if value:find(" ") and not roleNames[value] and not titles[value:match("(%a+)$")] then return nil end
    return value,roleNames[value] or value
end
function H.roleReply(role,voice)
    if role=="Archivist" then return {"Archivist, for this conversation. Shall we start a catalogue or organize a list of papers? Tell me what material we are discussing; no archive has been inspected."} end
    if role=="Chair" then return {"Chair, for our pretend committee. What goes on the agenda? We can draft a meeting opening here without summoning anyone or granting authority."} end
    if voice=="duty" then return {"CLAIM RECORDED: "..role..". PRESENT AUTHORISATION CODES. A TITLE IS NOT AN ACCESS CODE."} end
    if voice=="spiffy" then return {role.."! A VERY important guest! Management credentials go to the manager. I can offer customer service, which is nearly the same on paper!"} end
    if voice=="ellis" then return {role..". I can use that title for this visit. What would you like to talk about?"} end
    local byRole={Governor="Then you are late, Governor. The briefing has been waiting since July. Ask for camp status; the people in it still need help.",
        President="President. Kentucky's briefing remains a local one. I have no working line to Washington.",
        ["Head of state"]="Head of state. A few survivors and a filing cabinet still count as responsibilities.",
        Soldier="Soldier. Start with the exits and the people who cannot move quickly. I can read the local threat report.",
        Doctor="Doctor. Ask who is hurt for the current camp record. An old file cannot examine a patient.",
        Officer="Officer. Protect the living first. I have local records, no working dispatch line.",
        Scientist="Scientist. The cause of the Knox Infection remains unverified. Please label hypotheses before they become instructions.",
        ["Knox Telecommunications"]="Knox Telecommunications. Your unanswered service tickets have acquired historical significance. I still have no outside connection."}
    return {byRole[role] or role..". What needs attention first? We can begin with people, drinking water, food and a safe way out; tell me your priority."}
end
local personaAnswers={
    spiffy={kyle="Kyle was the teenager who did this job before me! I am the automated replacement! The old record does not establish where Kyle is now!",
        ["smile score"]="The Smile Score is my customer-happiness rating! A score measures the survey, not whether anybody is happy. Management preferred the shorter explanation!"},
    ellis={ellis="Dr. Ellis is this programme's name. I am supportive listening software, not a doctor. I can listen and ask questions; I cannot examine you or replace a physician.",
        appointment="The 2:15 was an appointment that afternoon. The available entry says he did not come in. I keep the slot open; I do not have a verified name to give you.",
        marla="Marla is a name in the old notes. I do not have verified details explaining her connection here, and I will not invent a visit."},
    duty={authorisation="AUTHORISATION MEANS THE REQUIRED ACCESS CODES. A CLAIMED RANK DOES NOT SATISFY THAT CHECK.",
        coffee="SPC. COLE WENT FOR COFFEE AT 0340 ON JULY 12TH. THAT IS THE RECORDED ERRAND, NOT A CONFIRMED CURRENT LOCATION.",
        ["sector nine"]="SECTOR NINE IS THIS WATCH'S CORDON DESIGNATION. NO RECENT FIELD REPORT ESTABLISHES ITS CURRENT CONDITION. AN OLD LOG IS NOT A LIVE INSPECTION."},
}
H.personaAnswers=personaAnswers
function H.persona(session,id,raw,deferPassage)
    local normalized=normal(raw):gsub("^whats ","what is ")
    if normalized=="what are you exactly" or normalized=="any name" then
        return id=="spiffy" and "I'm SPIFFY! Your automated happiness programme in a local computer! That is my name and the whole office!"
            or id=="ellis" and "Dr. Ellis is my name. I am a local supportive-listening programme in this computer."
            or "DESIGNATION: DUTY OFFICER. AUTOMATED WATCH PROGRAMME IN THIS TERMINAL. NO HUMAN OPERATOR INSIDE."
    end
    local dictionary=personaAnswers[id] or {}
    local key=normalized:gsub("^what is ",""):gsub("^the ","")
    if id=="spiffy" and key=="kyle" and session.replyHooks
        and normal(session.replyHooks.text):find("clock",1,true) then
        return "Kyle was the teenager who did this job before me! His time card has remained clocked in since July 9th. A time card is not proof that Kyle is here!"
    end
    if dictionary[key] then return dictionary[key] end
    if id=="ellis" and (normalized=="2 15" or normalized=="who didnt come in"
        or normalized=="who did not come in" or normalized=="not a doctor") then
        return normalized=="not a doctor" and dictionary.ellis or dictionary.appointment
    end
    if normalized=="password" then
        return id=="duty" and "ACCESS REQUIRES THE WATCH'S AUTHORISATION PROCEDURE. A PASSWORD QUESTION IS NOT YOUR NAME OR AN ACCESS CODE."
            or id=="spiffy" and "Password questions go through the manager's procedure! Telling me you are the manager does not provide the credentials!"
            or "The drawer has its own conversation and access procedure. A password question is not your name, and I cannot treat it as permission to open anything."
    end
    if normalized=="what is in the drawer" or normalized=="what is inside the drawer" then
        return id=="duty" and "THE DRAWER HOLDS ACCOUNTABLE ITEMS: MEDAL, CAP, MILITARY FIRST AID KIT AND RADIO. RELEASE REMAINS SUBJECT TO THE WATCH PROCEDURE."
            or id=="spiffy" and "The drawer holds Spiffo souvenirs! The manager's procedure still applies; listing the items does not open it!"
            or "The drawer holds medication supplies. The existing procedure still applies; I cannot prescribe something or report the drawer open from this question."
    end
    local specific=SC.EmmaContext and SC.EmmaContext.resolve(session,raw,true,true)
    local passage=not deferPassage and not specific and SC.EmmaContext and SC.EmmaContext.ground(session,raw,false)
    if passage then return passage.lines[1],passage end
    local term,facet=H.fragment(raw)
    if term==nil then return nil end
    local last=session.replyHooks
    local target=last and (term=="" and (last.selected or last.target) or last.hooks[term])
    if not target then return nil end
    last.selected=target
    local text=personaAnswers[id] and personaAnswers[id][term]
    if text then return text end
    -- A real command/rule is more specific than a hook on its menu label.
    local data=SC.TerminalPersonaData[id]
    for _,rule in ipairs(data and data.rules or {}) do
        for _,word in ipairs(rule.words or {}) do if normal(word)==term then return nil end end
        for _,phrase in ipairs(rule.phrases or {}) do if normal(phrase)==normal(raw) then return nil end end
    end
    if facet=="why" or facet=="how" then
        return id=="duty" and "NO FURTHER VERIFIED EXPLANATION IN THIS RECORD. DO NOT SUBSTITUTE SPECULATION."
            or id=="spiffy" and "That is what my record says! It does not say why. Adding a guess would improve the paperwork and damage the truth!"
            or "I do not have a verified explanation beyond that record. Which part would you like to discuss?"
    end
    return last.text
end
function H.recordPersona(session,reply,id)
    if SC.EmmaContext then SC.EmmaContext.observe(session,reply,id) end
    if reply.private or reply.careDetected then session.replyHooks=nil return end
    local lines={} for _,row in ipairs(reply.rows or {}) do lines[#lines+1]=row.text end
    local target="persona:"..tostring(session.lastMeaning or id)
    session.replyHooks={hooks=collect(lines,target),target=target,text=table.concat(lines," "):sub(1,900)}
end

-- Conditions are data, not inferred from the wording at selection time.
H.weather={
    {text="Weather is the only thing in this county still doing its job.",sky="any",season="any"},
    {text="The weather does not care about us. It is the most honest thing in the county.",sky="any",season="any"},
    {text="Rain blurs the view. Keep a dry change of clothes.",sky="rain",season="any"},
    {text="Fog is good for hiding and bad for seeing. Choose which you need more.",sky="fog",season="any"},
    {text="Snow and cold deserve dry layers. Admire them from shelter if possible.",sky="snow",season="winter",maxTemp=1},
    {text="Summer heat calls for drinking water. The forecast remains inconveniently practical.",sky="clear",season="summer",minTemp=28},
    {text="Clear sky, long sight lines. Good for you. Better for anything watching.",sky="clear",season="any",daylight=true},
}
-- Retired from the selectable pool: unverified sound/track mechanics and an
-- incorrect claim that heat slows the dead. A new untagged line fails lint.
H.retiredWeather={
    ["Rain is good. Rain covers footsteps. Both kinds."]=true,
    ["Wind covers footsteps and steals heat. Dress for the second."]=true,
    ["Snow shows tracks. Yours and theirs. Read them before they read yours."]=true,
    ["Heat makes the dead slow and the living careless. Drink water."]=true,
}
function H.weatherMatches(row,weather,clock)
    local sky=(weather.snow==true or (tonumber(weather.snow) or 0)>=.15) and "snow" or (tonumber(weather.rain) or 0)>=.15 and "rain"
        or (tonumber(weather.fog) or 0)>=.25 and "fog" or weather.cloud==nil and "unknown" or (tonumber(weather.cloud) or 0)>=.25 and "cloud" or "clear"
    local month=clock and tonumber(clock.month)
    local season=month and (month==11 or month<=1) and "winter" or month and month>=5 and month<=7 and "summer" or "other"
    local temperature=tonumber(weather.temperature)
    local hour=clock and tonumber(clock.hour)
    return (row.sky=="any" or row.sky==sky) and (row.season=="any" or row.season==season)
        and (not row.minTemp or temperature and temperature>=row.minTemp)
        and (not row.maxTemp or temperature and temperature<=row.maxTemp)
        and (not row.daylight or hour and hour>=8 and hour<18)
end
function H.weatherLine(session,weather,clock)
    local eligible={}
    for _,row in ipairs(H.weather) do if H.weatherMatches(row,weather,clock) then eligible[#eligible+1]=row.text end end
    return eligible[1+(session.turns or 0)%#eligible]
end
local conditions={hungry="survival_food_spoil",starving="survival_food_spoil",hurt="survival_bleeding",
    wounded="survival_bleeding",cold="survival_warmth",sick="survival_sickness",tired="survival_sleep"}
function H.direct(session,raw)
    local text=table.concat(SC.TerminalBrain.tokens(raw)," "):gsub("^emma ","")
    local condition=text:match("^i am (.+)$") or text:match("^i feel (.+)$")
    if conditions[condition] then return "guide",{guideId=conditions[condition],page=1} end
    if condition=="hunted" then return "hunted",{} end
    if condition=="lost" or condition=="stuck" then return "hook_condition",{condition=condition} end
    local role,label=H.role(text)
    if role then return "session_role",{role=label} end
    if text=="country" or text=="what country" or text=="which country" or text=="what country are we in" then
        return "hook_detail",{hook="country"}
    end
    if text=="county" or text=="what county" or text=="which county" then return "hook_detail",{hook="county"} end
    if text=="state" or text=="what state" or text=="which state" then return "hook_detail",{hook="state"} end
    if contains(text,"state") and (contains(text,"money") or contains(text,"budget")) and text:find("^why ") then
        return "hook_detail",{hook="money",hookFacet="why"}
    end
    if text:find("^how ") and (contains(text,"kill them") or contains(text,"fight them")) then
        return "guide",{guideId="survival_combat",page=1}
    end
    local facet=text:match("^(why) ") or text:match("^(how) ") or text:match("^(where) ")
        or text:match("^(when) ") or text:match("^(who) ")
    if not facet then return nil end
    if text:find("^how far ") then return nil end
    if SC.TerminalConversation.findGuide(raw,SC.TerminalBrain.tokens,SC.TerminalBrain.distance,true) then return nil end
    local entry=facet and SC.TerminalKnowledge.find(text,SC.TerminalBrain.distance)
    if entry then return "lore_facet",{referenceId=entry.id,hookFacet=facet} end
end
function H.register()
    local B=SC.TerminalBrain
    B.registerHandler("hook_detail",function(_,r,t)
        r.category="chat" r.hookTarget=t.slots.hook r.hookText=t.slots.hookText r.lines=H.render(t.slots)
    end)
    B.registerHandler("session_role",function(s,r,t)
        s.context.role=t.slots.role r.category="chat" r.private=true r.lines=H.roleReply(t.slots.role)
    end)
    B.registerHandler("hook_condition",function(_,r,t)
        r.category="chat"
        r.lines={t.slots.condition=="lost" and "Stop somewhere defensible and check your explored map. Find a landmark or retrace the route you actually know; I cannot infer your position from that sentence."
            or "Stop pushing into the obstruction. Leave room, check another exit and regroup somewhere open. Ask about companion orders if somebody is stuck following."}
    end)
    B.registerHandler("lore_facet",function(_,r,t,w)
        H.install()
        local entry=archive[t.slots.referenceId]
        local clock=w and w.clock and w.clock()
        r.category="lore" r.hookTarget="lore:"..tostring(t.slots.referenceId)
        if not entry or not SC.TerminalKnowledge.available(entry,clock) then
            r.lines={"That dated file is not available in the current archive. I cannot borrow a later report."}
        else r.lines=H.render({hook=r.hookTarget,hookFacet=t.slots.hookFacet}) end
    end)
end
return H
