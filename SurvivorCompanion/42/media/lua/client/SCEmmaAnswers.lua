-- SPDX-License-Identifier: MIT
-- Answer planning for a supplied public passage. Speech only: no providers,
-- actor calls, persistence, hardware controls or executable instructions.
require "SCEmmaReference"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local A={} SC.EmmaAnswers=A
local function norm(s) return table.concat(SC.TerminalBrain.tokens(s)," ") end
local function has(s,w) return (" "..s.." "):find(" "..w.." ",1,true)~=nil end
local function any(s,ws) for _,w in ipairs(ws) do if has(s,w) then return true end end return false end
local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
local function clauses(text)
    text=tostring(text or ""):sub(1,900):gsub("(%d)%.(%d)","%1\1%2")
    local out={}
    for line in text:gmatch("[^%.!?;]+") do
        line=trim(line:gsub("\1",".")):gsub("^['\"]",""):gsub("['\"]$","")
        if #line>1 then out[#out+1]=line end
        if #out>=12 then break end
    end
    return out
end
local function reply(source,kind,text,extra)
    local r=extra or {}
    r.kind=kind or "source_answer" r.lines={text}
    r.sourceBound=true
    if not r.private then r.publicSource=source r.publicSelection=1 end
    return r
end
A.DATA={
    crack="A crack is a split or break in the bottle wall. Even a small one can let water escape or worsen. An unknown glue is not automatically suitable for drinking water; a sound replacement container is the safer option.",
    layers="Two coats are not automatically better. Give the inner and outer layers useful jobs, keep them dry, and check that you can move comfortably. An inner layer can take up sweat; an outer one can keep rain off. A soaked or restrictive pile of clothing defeats the purpose.",
    dressings="A clean, dry jar with a suitable lid can protect loose bandages from dirt and moisture. It does not make the dressings sterile again. Keep usable wrappers closed until needed and inspect what you actually have.",
    packing="Start with drinking water, food, suitable clothing, a light and a little clean dressing material. Match the load to the trip and what you can carry safely. How far are you going, and what carrying space do you actually have?",
    hands="With only your hands, choose a small manageable load and the most immediate need first, such as a usable container of drinking water. I am not assuming a bag or another carrier. A shorter trip or another carrying arrangement may be necessary.",
    practice="This is a rehearsal on paper: we talk through the checks. No engine is started and no real fuel is used by that discussion. It does not establish that an actual generator is ready.",
    records="Updating the list means changing the written record to reflect what was used or replaced. It does not restock anything. Replacement supplies still have to be obtained and checked separately.",
    site="For any proposed camp site, check runoff and flooding, weather exposure, structural condition, cover and a way out. Higher ground can avoid a collecting hollow, but it does not settle all those questions. Without a roof, find suitable cover or consider another site; I cannot certify an unseen bridge or invent equipment.",
    cover="One practical idea is to use an available, suitable cover to keep rain off while leaving water a route away from where you rest. A tarp must be intact and secured so it sheds rain rather than collecting it. Check the ground and weather before choosing a place.",
    tarp="Given you say you have a tarp, consider using it as overhead rain cover if it is intact and can be secured to shed water. Check wind, runoff and the ground beneath it. I am not assuming a tent or choosing a location for you.",
    battery="Yes. A quiet radio can still use battery energy while switched on. Silence is not the same as being off. Switching it off when it is not needed can conserve energy; I have not measured its charge or operated its controls.",
    identity="A talkative box, with a programme and a conversational identity. The name and the first-person voice do not put a human body inside the case. I use 'I' for the programme speaking to you.",
    pronouns="Yes, you are the person providing the words, and I am the computer answering you in this exchange. Those pronouns keep the conversation straight; they do not identify a third participant or prove that I have a human body.",
    origin="For a computer, that means being built or programmed, not being born or growing up. This entry gives no verified creation date. Without that date and a reliable date to compare it with, I cannot give an exact age.",
    plain="Sure. Plain words, same subject. Ask what you need; I do not need a formal address.",
    same_voice="Yes. Same programme, plainer wording. A change of tone does not create a different person or machine.",
    whisper="All right. Quiet, short words on the screen. This is a text style; I am not claiming to control a connected speaker.",
    warning_missing="If the warning text has rubbed off, I cannot reconstruct it as fact. Tell me any remaining words, symbols or markings. The contents and hazard stay unconfirmed until you have reliable information.",
}
local function definitions(lines)
    local out={}
    for index,line in ipairs(lines) do
        local x,y=line:match("[Bb]y (.-) I meant (.+)")
        if not x then x,y=line:match("^(.+) means (.+)") end
        if not x then x,y=line:match("^[Aa]n? (.-) is (.+)") end
        if x and y and #x<=64 and #y<=350 then out[#out+1]={subject=trim(x),predicate=trim(y),index=index} end
    end
    return out
end
local stop={}
for word in ("the a an to of in for it that you i is are be do does can should what how why when where who just then"):gmatch("%S+") do stop[word]=true end
local verbs={}
for v in ("check inspect wash wipe dry watch observe use keep fill place leave wait record write count read ask compare look secure close press hold remove seek find clear fire turn switch"):gmatch("%S+") do verbs[v]=true end
local function roots(s)
    local out={}
    for w in norm(s):gmatch("%S+") do
        if #w>2 and not stop[w] then
            out[w]=true
            if w:sub(-1)=="s" then out[w:sub(1,-2)]=true end
            if w:sub(-3)=="ing" then
                local base=w:sub(1,-4) out[base]=true
                if verbs[base.."e"] then out[base.."e"]=true end
            end
            if w:sub(-2)=="ed" then out[w:sub(1,-3)]=true end
        end
    end
    return out
end
local function overlap(a,b)
    local n=0 for w in pairs(a) do if b[w] then n=n+1 end end return n
end
local function imperative(line)
    local first=line:match("^(%a+)")
    if not first then return nil end
    local low=first:lower()
    if verbs[low] or low=="avoid" then return line end
    if low:sub(-3)=="ing" then
        local base=low:sub(1,-4)
        if not verbs[base] and verbs[base.."e"] then base=base.."e" end
        if verbs[base] then
            local action=line:gsub("^%a+",base,1):gsub("%s+can help.*$",""):gsub("%s+may help.*$","")
            action=action:gsub(" and (%a+)ing ",function(v)
                local b=v
                if not verbs[b] and verbs[b.."e"] then b=b.."e" end
                return " and "..(verbs[b] and b or v.."ing").." "
            end)
            return action
        end
    end
end
function A.answer(session,raw,source,current)
    source=tostring(source or ""):sub(1,900)
    if source=="" then return nil end
    local q=norm(raw):gsub("^emma ","")
    local commands={exit=true,bye=true,quit=true,logout=true,status=true,power=true,time=true,date=true}
    if commands[q] and not tostring(raw):find("?",1,true) then return nil end
    local s=norm(source)
    local action={}
    for v in ("lock unlock open close turn switch activate start run refuel send treat queue retry reset forget"):gmatch("%S+") do action[v]=true end
    local firstWord=q:match("^%S+")
    if action[firstWord] and not any(q,{"it","that","what"}) then return nil end
    local lines=clauses(source)
    local function fixed(kind,key) return reply(source,kind,A.DATA[key]) end
    local yes=SC.EmmaConversation and SC.EmmaConversation.yes[q]
    local title=session.role or session.context and session.context.role
    local offered=source:match("the ([%a]+)'s part")
        or source:match("for the ([%a]+) in the story")
    if offered and (has(q,offered) or offered=="cook" and has(q,"chef") or q=="i am that office") then
        return reply(source,"role",offered..", for this example. The title is a conversational role, not authenticated office.",{private=true,role=offered})
    end
    if title and current and current.kind=="role" then
        local menu=source:match("[Ee]xample menu has ([^%.!?]+)")
        if menu and any(q,{"name","list","two","meals"}) then
            return reply(source,"role","The example names "..menu..". Those are menu categories, not a report of actual stock or preparation.",{private=true})
        end
        if any(q,{"tell","townsfolk","message","draft","read","say"}) then
            return reply(source,"role","What should the message say? Give me its subject or the words and I can put the draft here as text. I have no delivery connection and have not announced it to anyone.",{private=true})
        end
    end
    if any(s,{"practice run","rehearsal","on paper","just pretend"}) and any(q,{"practice","pretend","fuel used","real fuel","rehearsal","used"}) then return fixed("practice","practice") end
    if any(s,{"written record","written list","updating it"}) and any(q,{"update","updating","restock","replace","replacement"}) then return fixed("written_record","records") end
    if has(s,"battery") and has(s,"radio") and any(q,{"anyway","silent","silence","quiet","off","uses it"}) then return fixed("radio_power","battery") end
    if has(s,"clothing layer") and any(q,{"coats","coat","more","two","layers"}) then return fixed("layering","layers") end
    if has(s,"crack") and any(s,{"bottle","container"}) and q=="crack" then return fixed("container","crack") end
    if any(s,{"dressings","dressing","bandages"}) and any(q,{"jar","loose","container"}) then return fixed("dressings","dressings") end
    if has(s,"rain") and any(s,{"sterile","collected","gutter"}) and any(q,{"rain","roof","clean before","changes it"}) then
        return reply(source,"water_quality","Rainwater is not guaranteed clean or sterile before collection. A roof, gutter or container can add dirt and contamination. Collection and treatment matter; I have not tested this water.")
    end
    if has(s,"moisture") and has(s,"bottle") and any(q,{"not a leak","leaking","condensation"}) then
        return reply(source,"container_check","It could be condensation, but that appearance alone does not rule out a leak. Wipe the bottle dry and watch where moisture reappears. I cannot tell which it is without that check.")
    end
    if has(s,"sweat") and has(s,"layer") and any(q,{"sweat","perspiration"}) then
        return reply(source,"layering","Sweat is moisture from your body. It can dampen the inner clothing layer; a wet layer can leave you uncomfortable or chilled. Check dryness as well as warmth.")
    end
    if has(s,"camp") and any(s,{"runoff","hollow","flooded"}) and any(q,{"bridge","ground","higher","roof","site","cover"}) then return fixed("site","site") end
    if any(s,{"rain off","possible covers"}) then
        if has(q,"tarp") then return fixed("cover","tarp") end
        if yes or any(q,{"more","idea","continue","cover"}) then return fixed("cover","cover") end
    end
    if any(s,{"computer","programme","conversational voice","wording changes","person standing in the room"}) then
        if any(q,{"born","built","programmed","how old","creation","age"})
            and not q:find("^who ") and not q:find("^where ") and not q:find("^how were ") then
            local year
            for _,line in ipairs(lines) do
                local before,value=norm(line):match("^(.-)built.-(%d%d%d%d)")
                if not before then before,value=norm(line):match("^(.-)created.-(%d%d%d%d)") end
                if before and not any(before,{"no","not","wasnt","unverified","unknown","unconfirmed"}) then year=value break end
            end
            if year then return reply(source,"computer_origin","The supplied record dates construction or creation to "..year..". An exact age still needs the full creation date and a reliable date to compare it with; this is not a human birthday.") end
            return fixed("computer_origin","origin")
        end
        if any(q,{"more than a box","saying i","person","body"}) then return fixed("computer_identity","identity") end
        if any(s,{"i mean the person","person writing","person providing"}) and any(q,{"me","answering","mean me","youre answering"}) then return fixed("computer_pronouns","pronouns") end
        if any(q,{"less formal","plainer","plain words","less stiff"}) then return fixed("text_style","plain") end
        if any(q,{"whisper","quietly","in text"}) then return fixed("text_style","whisper") end
    end
    if current and current.kind=="text_style" and any(q,{"still you","same","you"}) then return fixed("text_style","same_voice") end
    if any(s,{"wording changes","different style"}) and any(q,{"less formal","plainer","plain"}) then return fixed("text_style","plain") end
    if any(s,{"choosing supplies","supplies to take"}) then
        if any(q,{"hands","no bag","hands only"}) then return fixed("packing","hands") end
        if any(q,{"take","with me","choosing","pack"}) then return fixed("packing","packing") end
    end
    if current and current.kind=="packing" and any(q,{"hands","no bag","carry"}) then return fixed("packing","hands") end
    if any(s,{"food or water","food and water"}) and any(q,{"keep talking","continue","go on","more"}) then return fixed("packing","packing") end
    if any(s,{"trap","traps"}) and any(s,{"animals","animal","bait","birds","rabbit"}) and any(q,{"bird","birds","rabbit","same trap","bait"}) then
        return {kind="trapping",reference="trapping",facet="use",sourceBound=true,publicSource=source,publicSelection=1,
            prefix="Match the actual trap to the animal. More bait cannot change an unsuitable size or design."}
    end
    if any(s,{"do you mean","do you want","would you like"}) then
        local question=source:match("^(.-)%?")
        local left,right
        if question then left,right=question:match("^(.-),? or (.+)$") end
        if left and right then
            left=left:gsub("^[Dd]o you mean ",""):gsub("^[Dd]o you want ",""):gsub("^[Ww]ould you like ","")
            local scoreLeft=overlap(roots(q),roots(left))
            local scoreRight=overlap(roots(q),roots(right))
            local selected=scoreLeft>scoreRight and left or scoreRight>scoreLeft and right
            if selected then
                local line="You mean "..selected..". "
                if any(norm(selected),{"warning","label"}) then line=line.."A warning describes a hazard. What words or symbols can you still read on it? I haven't seen the actual label."
                else line=line.."Tell me the particular detail you want to work through; I will keep that subject." end
                return reply(source,"source_choice",line,{choice=selected:sub(1,160)})
            end
        end
    end
    if current and current.kind=="source_choice" and any(q,{"rubbed off","missing","no words","cannot read","cant read","worn off"}) then return fixed("source_choice","warning_missing") end
    local first,nextStep=source:match("[Ff]irst (.-), then ([^%.!?]+)")
    if first and nextStep and any(q,{"next","then","now","after","pour","fill","checking"}) then
        local line
        if any(q,{"only after","checking"}) then line="Yes. First, "..first.."; only then, "..nextStep.."."
        else line="The next step is to "..nextStep..", after this check: "..first.."." end
        return reply(source,"sequence",line.." This conversation has not performed either step.")
    end
    local queryWords=roots(q)
    if any(q,{"compare","difference","different uses"}) and any(s,{"comparison","while","interchangeable"}) then
        return reply(source,"source_answer",source)
    end
    if any(q,{"use","try","instead","good enough"}) then
        for n,line in ipairs(lines) do
            if imperative(line) and overlap(queryWords,roots(line))>0 then
                return reply(source,"source_answer","The supplied advice is: "..line.."."..(lines[n+1] and " "..lines[n+1].."." or ""))
            end
        end
    end
    if any(q,{"can","should","try","just","fire","clear"}) then
        for _,line in ipairs(lines) do
            if any(norm(line),{"dont","do not","never","avoid"}) and overlap(queryWords,roots(line))>0 then
                return reply(source,"source_answer",line..". That is the instruction; I have not inspected or operated the actual object.")
            end
        end
    end
    if q:find("^how") or any(q,{"what should i do","what do i do","how check"}) then
        local best,bestScore
        for _,line in ipairs(lines) do
            local action=imperative(line)
            if action then
                local score=overlap(queryWords,roots(line))
                if not best or score>bestScore then best,bestScore=action,score end
            end
        end
        if best then return reply(source,"source_answer","Try this check: "..best..". It is an instruction or observation to make, not a result I have obtained.") end
    end
    local defs=definitions(lines)
    if q:find("^under ") or q:find("^behind ") or q:find("^beneath ") or q:find("^beside ") then
        local d=defs[1]
        if d then return reply(source,"source_answer","That position counts as "..d.subject.." only if it meets the definition: "..d.predicate..". Check the actual conditions; I cannot verify the position from here.") end
    end
    local term=SC.EmmaHooks and SC.EmmaHooks.fragment(raw)
    if term and term~="" then
        for _,d in ipairs(defs) do
            if has(norm(d.subject),term) then
                local explanation="Here, "..d.subject.." means "..d.predicate.."."
                local nextLine=lines[d.index+1]
                if nextLine and any(norm(nextLine),{"not","no","never","isnt","arent","cannot","cant","doesnt","without","unknown","unconfirmed"}) then
                    explanation=explanation.." "..nextLine.."."
                end
                return reply(source,"source_answer",explanation)
            end
        end
    end
    if any(q,{"shorter","short version","brief version"}) then
        local selected={}
        if lines[1] then selected[1]=lines[1].."." end
        for n=2,#lines do
            if any(norm(lines[n]),{"not interchangeable","not guaranteed","does not","doesnt","dont"}) then selected[#selected+1]=lines[n].."." break end
        end
        if #selected>0 then return reply(source,"source_answer","Short version: "..table.concat(selected," ")) end
    end
end
return A
