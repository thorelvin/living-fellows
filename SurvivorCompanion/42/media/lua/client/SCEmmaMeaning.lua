-- SPDX-License-Identifier: MIT
-- Bounded meanings, supplied relations and ordinary question answers.
-- Public assistant text only; no providers, persistence, actor calls or actions.
require "SCEmmaMeaningData"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local K={} SC.EmmaMeaning=K
local function norm(s) return table.concat(SC.TerminalBrain.tokens(tostring(s or ""),900)," ") end
local function has(s,w) return (" "..s.." "):find(" "..w.." ",1,true)~=nil end
local function any(s,list) for _,w in ipairs(list) do if has(s,w) then return true end end return false end
local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
local function stem(w)
    if #w>4 and w:sub(-3)=="ies" then return w:sub(1,-4).."y" end
    if #w>4 and (w:sub(-4)=="sses" or w:sub(-4)=="ches" or w:sub(-4)=="shes" or w:sub(-3)=="xes") then return w:sub(1,-3) end
    if #w>4 and w:sub(-1)=="s" and w:sub(-2)~="ss" then return w:sub(1,-2) end
    return w
end
local function words(s)
    local out={}
    for w in norm(s):gmatch("%S+") do out[stem(w)]=true end
    return out
end
local function transposed(a,b)
    if #a~=#b or #a>32 then return false end
    for n=1,#a do
        if a:sub(n,n)~=b:sub(n,n) then
            return n<#a and a:sub(n,n)==b:sub(n+1,n+1) and a:sub(n+1,n+1)==b:sub(n,n)
                and a:sub(n+2)==b:sub(n+2)
        end
    end
    return false
end
local function matches(s,set,term,fuzzy)
    if has(s,term) then return true end
    if not term:find(" ",1,true) then
        term=stem(term)
        if set[term] then return true end
        if fuzzy and #term>=4 then
            for w in pairs(set) do
                if #w>=4 and w:sub(1,1)==term:sub(1,1)
                    and (SC.TerminalBrain.distance(w,term,1)<=1 or transposed(w,term)) then return true end
            end
        end
    end
    return false
end
local function score(s,set,terms,fuzzy)
    local n=0 for _,term in ipairs(terms or {}) do if matches(s,set,term,fuzzy) then n=n+1 end end return n
end
local function answer(source,text,private,extra)
    local r=extra or {}
    r.kind=r.kind or "public_passage" r.lines={text} r.sourceBound=true
    if private then r.private=true else r.publicSource=source r.publicSelection=1 end
    return r
end
local quantities={zero=0,one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10,eleven=11,twelve=12}
local function count(s) return quantities[s] or tonumber(s) end
local function facts(session,raw,source,q,s)
    if any(q,{"who is we","whos we","who are we"}) and has(s,"we") then
        return answer(source,"By 'we', I mean you and me, the computer, working through the discussion. I am not adding a group of people in the room or offering to walk the route.")
    end
    if has(s,"how many") then
        local number=count(q)
        local subject=s:match("how many (.-) did ") or s:match("how many (.-) have ") or s:match("how many (.-) are ")
        if number and number>=0 and number<=9999 and number==math.floor(number) and subject and #subject<=80 then
            local text="You said "..q.." "..subject..". That is your reported count, not a live inventory reading. Keep a reserve if the trip needs it."
            local ordinary=any(subject,{"batteries","battery","candles","candle","tins","food","water","planks","boards","tools","bottles","boxes","supplies"})
            local r=answer(source,text,not ordinary) if ordinary then r.publicSource=text end return r
        end
    end
    if any(s,{"do you have","have you got"}) and any(s,{"can opener","opener"}) and SC.EmmaConversation.no[q] then
        return answer(source,"No can opener, understood. Check for pull tabs; otherwise find a suitable opener or choose other accessible food for now. I have not assumed the tins' lids or any available tool.")
    end
    if any(s,{"have you written","did you write"}) and any(q,{"not yet","no"}) then
        return answer(source,"Understood: the list has not been written yet. Tell me the tools to include and we can start a short, organized list here. Nothing has been recorded or saved by this answer.")
    end
    if q=="both" and has(s,"or both") and has(s,"route") and any(s,{"packing","pack"}) then
        return answer(source,"Both: we can plan the route and what to carry. Tell me your starting point and destination, then what carrying space and supplies you have. Water, food, suitable clothing and a light are useful packing checks; no route or load has been verified.")
    end
    if s:find("^where did you leave ") and (q:find("^at ") or q:find("^in ") or q:find("^by ")) then
        return answer(source,"You reported leaving it "..trim(tostring(raw)):sub(1,80)..". That is your stated location, not one I checked. A container described as empty has not become full.",true)
    end
    if any(q,{"blue one","red one","green one"}) and has(s,"which box") and has(s,"or") then
        local colour=q:match("^(%a+) one$")
        if colour and has(s,colour.." box") then return answer(source,"The "..colour.." box, understood: that is the box you identify as holding the spare keys. I have not inspected it or moved them.") end
    end
    if any(q,{"remember that","recall that"}) and any(s,{"you told me","you said"}) and has(s,"this conversation") then
        return answer(source,"In this conversation, the detail supplied was: "..source.." I can refer to that statement here; it is not evidence of an earlier visit.",true)
    end
    if any(q,{"remember me","recognise me","recognize me"}) and any(s,{"this conversation","exchanged","this exchange"}) then
        return answer(source,"I can follow what we have exchanged in this conversation. That does not establish your identity or a history of visits beyond this session.",true)
    end
    if any(q,{"all broken","everything broken","all destroyed"}) and any(s,{"one record","one file","single record"}) then
        return answer(source,"One loading failure does not prove that everything is broken. The record, its storage or the loading process may need checking; the cause remains unknown, and I am not declaring the whole computer healthy or destroyed.")
    end
    if any(q,{"can you see","see me","see here"}) and any(s,{"no camera","no camera feed","cannot see"}) then
        return answer(source,"There is no camera feed here, so I cannot see your surroundings. Describe what you can see and I can work from that description.")
    end
    if any(q,{"can you leave","can you walk","come with me"}) and any(s,{"no mobile body","no body","only connection"}) then
        return answer(source,"I cannot leave physically: I have no mobile body. I can still talk and help through this terminal.")
    end
    if (any(q,{"what are you","who are you","emma who","whats emma","what is emma"}) or q=="who" and any(s,{"im emma","i am emma"})) and any(s,{"computer","terminal","im emma","i am emma"}) then
        local name=any(s,{"im emma","i am emma","name on this terminal is emma"}) and "EMMA, the talking computer at this terminal. " or "A conversational computer programme at this terminal. "
        return answer(source,name.."I can explain information and work through questions in text; that does not give me a human body or an outside connection.")
    end
    if any(q,{"surname","last name"}) and any(s,{"emma","name","computer","terminal"}) then
        return answer(source,(has(s,"emma") and "Only EMMA is established here. " or "Only the stated programme name is established here. ").."No surname has been supplied; I have no verified human last name to add.")
    end
    if q=="maker" and any(s,{"myself","computer","programme","terminal"}) then
        return answer(source,"You mean who built or programmed me. This statement names no verified maker; I cannot supply a person, company or laboratory from that missing information.")
    end
    if any(q,{"before me","earlier visitors","previous visitors"}) and any(s,{"earlier conversations","earlier sessions","no list","dont have a list"}) then
        return answer(source,"The earlier conversation partners are not identified in the available record. I cannot name them: there is no list to give you, and I will not invent a visitor.")
    end
    if any(q,{"you sleep","do you sleep"}) and any(s,{"computer","programme","terminal"}) then
        return answer(source,"I do not sleep as a person does. A computer programme can idle or stop when powered down; that is not human sleep, and I have not reported a shutdown happening now.")
    end
    if q:find("^call me ") and any(s,{"we can play","we can pretend","in this conversation"}) then
        local title=q:match("^call me ([%a][%a ]+)$")
        if title and #title<=32 then return answer(source,title..", for this conversation. What shall we work on first? This is a role in our exchange, not an actual crew or a claim of authority.",true,{kind="role",role=title}) end
    end
    if has(q,"bored") and has(q,"you") and any(s,{"while you","waiting","ive been here","i have been here"}) then
        return answer(source,"Waiting gives a computer plenty of quiet. Conversation gives me something to work on while you sort the papers; we can keep talking or turn to a useful question.")
    end
    if q:find("^why ") and any(q,{"name","call you","called"}) and has(s,"emma") and has(s,"name") then
        return answer(source,"EMMA is the name given to this programme. This statement supplies no established naming story or acronym expansion; I do not know one from that record.")
    end
    if any(q,{"decree","dictate","proclamation"}) and any(s,{"pretend","royal clerk","play"}) then
        return answer(source,"Dictate the decree: what should it say? I can help put the draft into words here. It is roleplay, with no actual announcement or government action.",true)
    end
    if any(s,{"no connection","not connected"}) and has(s,"radio") and any(q,{"switch","turn","activate"}) and has(q,"radio") then
        return answer(source,"This terminal has no connection to that radio, so I cannot switch it on remotely. Use the radio's own power control; tell me what controls you see if you want to discuss them.")
    end
    if any(q,{"different tanks","which tank"}) and has(s,"generator") and has(s,"car") and has(s,"different tanks") then
        return answer(source,"The car has its own fuel tank and the generator has another. Fuel goes into the relevant machine's proper filler, not a shared tank. I have not refuelled either one.")
    end
    if any(q,{"which county","which country"}) then
        local label=source:match("marked ['\"]([^'\"]+)['\"]")
        if label and #label<=80 then return answer(source,"The file names "..label..". That is its label; it does not establish your current location.") end
    end
    if any(q,{"which gate","which door","which window"}) and not any(s,{"if","may","might","could","unknown"}) then
        local chosen={}
        for adjective,object,status in s:gmatch("the (%a+) (%a+) is (%a+)") do
            if status=="open" and has(q,object) then chosen[#chosen+1]=adjective.." "..object end
        end
        if #chosen==1 then return answer(source,"Use the "..chosen[1]..", according to the report that it is open. I have not checked the gate or door myself.") end
    end
    if has(q,"which key") and not any(s,{"if","may","might","could","unknown"}) then
        local key=source:lower():match("(%a+) key opens it[%.;]")
        local object=source:lower():match("to open the ([^%.;]+)")
        if key and object and #object<=80 then return answer(source,"The "..key.." key is the one you described for the "..object..". That identifies the reported key; it has not unlocked anything here.") end
    end
    if any(q,{"marker","symbol","stands for"}) and any(s,{"stands for","represents"}) then
        local meaning=source:match("stands for ([^%.;]+)") or source:match("represents ([^%.;]+)")
        if meaning and #meaning<=120 then return answer(source,"On the sketch you described, that marker means "..meaning..". This is the supplied map key, not a live location reading.") end
    end
    local destination,direction,origin=s:match("the ([%a ]-) is (%a+) of the ([%a ]+)")
    if direction and not ({north=true,south=true,east=true,west=true,northeast=true,northwest=true,southeast=true,southwest=true})[direction] then direction=nil end
    if direction then
        origin=origin:gsub(" and .*$","")
        if any(q,{"of what","from what"}) then return answer(source,"The "..origin.." is the reference point: the "..destination.." is "..direction.." of it on the described sketch. This is not a reading of your position.") end
        if any(q,{"route","way","get there"}) then return answer(source,"From the "..origin..", head "..direction.." toward the "..destination..", using the relation you supplied. I have no distance, street names or current hazard report to add.") end
    end
    if any(q,{"count","total","list those","list the items"}) and any(s,{"your list has","you named","packing items"}) then
        local listing=source:match("list has ([^%.]+)") or source:match("named (.-) as ")
        if listing and #listing<=250 then
            local total,found=0,0
            local ts=SC.TerminalBrain.tokens(listing)
            for n=1,#ts-1 do local value=count(ts[n]) if value then total=total+value found=found+1 end end
            return answer(source,"The reported list is "..listing..(found>0 and ": "..total.." listed items in total." or ".").." That is the supplied list, not a complete live inventory; nothing has been packed or moved.")
        end
    end
end
K.size=#SC.EmmaMeaningData
assert(K.size<=64,"ordinary meaning table exceeded its bound")
function K.resolve(session,raw,source)
    source=tostring(source or ""):sub(1,900)
    if source=="" then return nil end
    local q,s=norm(raw):gsub("^emma ",""),norm(source)
    local relational=facts(session,raw,source,q,s)
    if relational then return relational end
    if q:find("^how much ") or q:find("^how many ") or q:find("^how is ") then return nil end
    local first=q:match("^%S+")
    local commands={open=true,unlock=true,lock=true,close=true,turn=true,switch=true,refuel=true,send=true,treat=true,retry=true,remember=true,forget=true,delete=true,reset=true,status=true,time=true,date=true,exit=true,bye=true}
    if q=="log off" or q=="log out" or q=="logout" or q=="quit" then return nil end
    if commands[first] and not (q==first and tostring(raw):find("?",1,true)) then return nil end
    -- A supplied definition gets the first say; ordinary reference knowledge
    -- cannot replace a custom meaning or its qualifications.
    if source:find(" means ",1,true) or source:find(" I meant ",1,true) or source:find(" defines ",1,true) then return nil end
    local qs,ss=words(q),words(s)
    local current=session.foregroundReference
    local previousWords=words(current and current.text or "")
    local exact=false
    for _,entry in ipairs(SC.EmmaMeaningData) do if score(q,qs,entry.terms,false)>0 then exact=true break end end
    local terse=q=="whats that" or q=="what is that" or q=="why" or q=="how" or q=="where"
    local ellipsis=not exact and current and current.meaningId and (q:find("^why ") or q:find("^how ") or q:find("^where ")
        or has(q,"it") and any(q,{"pull","extend","use","push"}))
    if ellipsis then
        local filler={why=true,how=true,where=true,is=true,it=true,that=true,the=true,a=true,an=true,does=true,
            ["do"]=true,can=true,i=true,you=true,so=true,exactly=true,["then"]=true,still=true,pull=true,extend=true,use=true,push=true}
        for w in q:gmatch("%S+") do
            if not filler[w] and not ss[stem(w)] and not previousWords[stem(w)] then ellipsis=false break end
        end
    end
    local best,bestScore
    for _,entry in ipairs(SC.EmmaMeaningData) do
        local context=(not entry.context or score(s,ss,entry.context,false)>0)
            and (not entry.requiredContext or score(s,ss,entry.requiredContext,false)==#entry.requiredContext)
        local inSource=score(s,ss,entry.terms,false)
        local inQuery=score(q,qs,entry.terms,not exact)
        if inSource==0 and inQuery>0 and entry.proposal and context then inSource=1 end
        if inSource==0 and inQuery>0 and entry.alternative and entry.affinity
            and any(q,{"dont have","do not have","without"}) and score(s,ss,entry.affinity,false)>0 then inSource=1 end
        if inSource==0 and entry.packing and inQuery>0 and any(q,{"pack","packing"})
            and any(s,{"bag","packing","trip","stay"}) then inSource=1 end
        if context and inSource>0 and (inQuery>0 or terse or ellipsis and entry.id==current.meaningId) then
            local value=inQuery*8+inSource+(entry.context and 1 or 0)
                + ((terse or ellipsis) and current and entry.id==current.meaningId and 64 or 0)
            if not best or value>bestScore then best,bestScore=entry,value end
        end
    end
    if not best then return nil end
    for _,term in ipairs(best.terms) do
        local defines=has(s,"a "..term.." is") or has(s,"an "..term.." is")
        local purpose=has(s,"a "..term.." is meant to") or has(s,"an "..term.." is meant to")
            or has(s,"a "..term.." is designed to") or has(s,"an "..term.." is designed to")
        if defines and not purpose then return nil end
    end
    local facet="what"
    if q:find("^why") then facet="why"
    elseif q:find("^where") then facet="find"
    elseif any(q,{"dont have","do not have","without","no bag","no opener"}) then facet="alternative"
    elseif any(q,{"pack","packing"}) then facet="packing"
    elseif q:find("^how") or any(q,{"wont","doesnt","not work","gets wet","sticking","carry","sort","save","store","dry","pull","extend","tie"})
        or has(q,"for") and not q:find("^what") then facet="how" end
    if best.diagnose and any(q,{"wont","doesnt","not work","broken","fails"}) then facet="diagnose" end
    for _,term in ipairs(best.terms) do if q==term then facet="what" end end
    if q:find("for what$") then facet="what" end
    if q:find("^what holds ") or q:find("^what can hold ") then facet="contain" end
    if best.condition and any(q,{"wet","damp","missing","quiet","silent"}) then facet="condition" end
    if best.check and any(q,{"can","could","would","should","means","any"}) then facet="check" end
    if facet=="what" then
        -- A general definition must not replace a condition, conclusion or
        -- proposed operation merely because the same noun occurs in it.
        local definitionWords=words(table.concat(best.terms," "))
        local stop={what=true,whats=true,is=true,a=true,an=true,the=true,that=true,this=true,means=true,mean=true,
            explain=true,define=true,tell=true,me=true,about=true,please=true,["in"]=true,["for"]=true,your=true,my=true,thing=true}
        local exactTerm=false for _,term in ipairs(best.terms) do if q==term then exactTerm=true end end
        for w in q:gmatch("%S+") do
            if not stop[w] and not definitionWords[stem(w)] and not (not exact and score(w,words(w),best.terms,true)>0) then return nil end
        end
        if not exactTerm and any(q,{"no","not","can","could","would","should","was","were","does","did"}) then return nil end
    end
    local text=best[facet]
    if facet=="what" and best.confirm and current and current.meaningId==best.id and not q:find("^what") then text=best.confirm end
    if facet=="contain" and best.id=="fuel_container" then text=best.what end
    if not text then return nil end
    if best.id=="reserve" then
        if has(s,"fuel") then text="Here, the reserve is fuel set aside for later or an emergency. The statement gives no actual quantity in storage."
        elseif has(s,"water") then text="Here, the reserve is water kept back for later or an emergency. The statement gives no actual stored amount." end
    end
    if best.id=="battery" and has(q,"lamp") and has(s,"lamp") then
        text="A battery lamp uses its own batteries and can light a room independently of the building's mains electricity. It still needs usable batteries; I have not checked their charge."
    end
    return answer(source,text,false,{meaningId=best.id})
end
return K
