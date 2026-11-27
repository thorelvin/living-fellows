-- SPDX-License-Identifier: MIT
-- Foreground conversation state only. No scans, network, or saved personal text.
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local B=SC.TerminalBrain
local C={} SC.EmmaConversation=C
local yes={yes=true,y=true,yeah=true,yep=true,yup=true,ja=true,sure=true,correct=true,affirmative=true,
    ["do it"]=true,["go ahead"]=true,["yes please"]=true,please=true,right=true,ok=true}
local no={no=true,n=true,nope=true,nah=true,nei=true,negative=true,wrong=true,cancel=true,never=true,["no thanks"]=true}
local stop={what=true,which=true,where=true,when=true,why=true,how=true,who=true,is=true,are=true,
    the=true,a=true,an=true,["do"]=true,does=true,i=true,we=true,you=true,it=true,that=true,me=true,
    please=true,tell=true,about=true,can=true,could=true,emma=true,my=true,our=true,
    will=true,would=true,should=true,happen=true,going=true}
C.yes,C.no=yes,no
function C.normal(raw) return table.concat(B.tokens(raw)," "):gsub("^emma ","") end
function C.defaultSuggestions()
    return {{id="people",label="people",term="people",slots={},score=9},
        {id="zombies",label="nearby zombies",term="zombies",slots={},score=9},
        {id="power",label="power",term="power",slots={},score=9}}
end
local ordinals={first=1,second=2,third=3,["first one"]=1,["second one"]=2,["third one"]=3,
    ["the first one"]=1,["the second one"]=2,["the third one"]=3}
local function offeredMatch(answer,choice)
    if answer==C.normal(choice.label) or answer==choice.term then return true end
    for word in C.normal(choice.label):gmatch("%S+") do
        if not stop[word] and answer==word then return true end
        if #word>=5 and #answer>=5 and not answer:find(" ",1,true)
            and not SC.EmmaUnderstand.known(answer) and B.distance(answer,word,1)<=1 then return true end
    end
    return false
end
function C.begin(session,raw,world,turn)
    local context=session.context
    local answer=C.normal(raw)
    if answer=="forget our conversation" or answer=="forget this conversation" or answer=="forget the conversation" then
        return "conversation_forget",{}
    end
    local expected=context.expect context.expect=nil
    if expected and expected.kind=="terminal_tone" then
        if yes[answer] then return "terminal_tone",{} end
        if no[answer] then return "ack",{} end
    end
    if expected and expected.kind=="help_me" then
        local value=answer:gsub("^i am ",""):gsub("^im ",""):gsub("^i feel ","")
        -- The four words she offered also accept a near spelling ("hearsick",
        -- "heathsick", "hungy"): one slip for six letters, two for nine.
        if not value:find(" ") and value:sub(1,4)~="hurt" then
            for _,offered in ipairs({"hungry","hunted","heartsick"}) do
                local limit=#offered>=8 and 2 or 1
                if value~=offered and math.abs(#value-#offered)<=limit and value:sub(1,1)==offered:sub(1,1)
                    and SC.TerminalBrain.distance(value,offered,limit)<=limit then value=offered break end
            end
        end
        if value=="hurt" or value=="wounded" or value=="injured" or value=="bleeding" or value=="in pain" then
            return "guide",{guideId="survival_bleeding",page=1}
        elseif value=="hungry" or value=="starving" or value=="need food" then
            return "guide",{guideId="survival_food_spoil",page=1}
        elseif value=="hunted" or value=="chased" or value=="being chased" or value=="pursued" then
            return "hunted",{}
        elseif value=="heartsick" or value=="heartbroken" or value=="lonely" or value=="sad" then return "comfort",{} end
    end
    local pending=context.pending
    if pending then
        context.pending=nil
        if yes[answer] then return pending.intent,pending.slots or {} end
        if no[answer] then return "did_you_mean_no",{choices=pending.choices} end
    end
    local selection=context.personChoices
    if selection then
        if answer=="none" or answer=="nobody" or answer=="no one" or answer=="never mind"
            or answer=="nevermind" or answer=="none of them" or answer=="cancel" then
            context.personChoices=nil return "nevermind",{}
        end
        -- Names and numbers use the existing identity reader. An unrelated turn
        -- expires the question even if another parser handles that turn first.
        local named=false
        for _,person in ipairs(selection.people or {}) do
            local name=tostring(person.name or ""):lower()
            if answer==name or answer==name:match("^%S+") then named=true end
        end
        if named or answer:match("^%d$") or answer=="first" or answer=="second" or answer=="third" then
            return B.parseBase(session,raw,world,turn)
        end
        context.personChoices=nil
    end
    local suggested=context.suggested
    if suggested then
        if session.turns-(suggested.turn or 0)>2 then context.suggested=nil
        else
            local number=tonumber(answer) or ordinals[answer]
            local selected=number and suggested.choices[number]
            if not selected then
                for _,choice in ipairs(suggested.choices) do
                    if offeredMatch(answer,choice) then selected=choice break end
                end
            end
            if selected then
                context.suggested=nil
                local slots={} for key,value in pairs(selected.slots or {}) do slots[key]=value end
                return selected.id,slots
            end
            if not yes[answer] and answer~="thanks" and answer~="thank you" then context.suggested=nil end
        end
    end
end

local neighbors={}
do
    local rows={"qwertyuiop","asdfghjkl","zxcvbnm"}
    for y,row in ipairs(rows) do for x=1,#row do
        local char=row:sub(x,x) neighbors[char]={}
        for yy=math.max(1,y-1),math.min(3,y+1) do
            for xx=math.max(1,x-1),math.min(#rows[yy],x+1) do neighbors[char][rows[yy]:sub(xx,xx)]=true end
        end
    end end
end
-- A neighbouring phone key is cheaper than a different word. Work is bounded
-- by the 24-character query and the index's fixed per-load vocabulary.
function C.distance(a,b)
    if #a>24 or #b>24 or math.abs(#a-#b)>2 then return 9 end
    local before,previous=nil,{}
    for j=0,#b do previous[j]=j end
    for i=1,#a do
        local current={[0]=i} local ac=a:sub(i,i)
        for j=1,#b do
            local bc=b:sub(j,j)
            local cost=ac==bc and 0 or neighbors[ac] and neighbors[ac][bc] and .35 or 1
            local value=math.min(previous[j]+1,current[j-1]+1,previous[j-1]+cost)
            if before and i>1 and j>1 and ac==b:sub(j-1,j-1) and a:sub(i-1,i-1)==bc then value=math.min(value,before[j-2]+.65) end
            current[j]=value
        end
        before,previous=previous,current
    end
    return previous[#b]
end
local index
local function vocabulary()
    if index then return index end
    index={} local seen={}
    local function add(term,id,label,slots,noun)
        if #index>=1600 or #term<4 or #term>24 or stop[term] then return end
        local key=term..":"..id if seen[key] then return end seen[key]=true
        index[#index+1]={term=term,id=id,label=label or term,slots=slots or {},noun=noun}
    end
    for _,intent in ipairs(B.INTENTS) do if intent.label then
        for word in pairs(intent.words or {}) do add(word,intent.id,intent.label) end
    end end
    for id,topic in pairs(SC.EmmaFollowups.subjects) do
        for _,alias in ipairs(topic.aliases) do for word in alias:gmatch("%a+") do
            add(word,"guide",topic.label,{guideId=topic.guideId,page=1},true)
        end end
    end
    if SC.EmmaReference then
        for _,row in ipairs(SC.EmmaReference.index()) do
            local target=row.target
            local slots,id,label
            if target.kind=="reference" then
                id="guide" slots={guideId="reference_"..target.id,page=1,referenceFacet=target.facet}
                label=SC.EmmaReference.definition(target.id).title
            elseif target.kind=="guide" then id="guide" slots={guideId=target.id,page=1} label=row.term
            -- The archive index has no evidence that this player recovered an
            -- individual fragment. Do not advertise its file/slip aliases.
            elseif target.kind=="lore" and not target.id:find("^fragment_") then
                id="lore" slots={referenceId=target.id} label=row.term
            end
            if id then for word in row.term:gmatch("%a+") do add(word,id,label,slots,true) end end
        end
    end
    table.sort(index,function(a,b) return a.term==b.term and a.id<b.id or a.term<b.term end)
    return index
end
function C.suggestions(session,raw)
    local queries={}
    for word in C.normal(raw):gmatch("%a+") do if #word>=4 and not stop[word] and #queries<8 then queries[#queries+1]=word end end
    local byId={}
    local topic=SC.TerminalConversation.latest(session)
    for _,entry in ipairs(vocabulary()) do
        local best=9
        for _,word in ipairs(queries) do
            local limit=#word<=4 and 0 or #word<=7 and 1 or 2
            if B.distance(word,entry.term,limit)<=limit then
                best=math.min(best,C.distance(word,entry.term))
            end
        end
        local score=best+(entry.noun and 0 or .3)
        if topic and (topic.id==entry.slots.guideId or topic.subject==entry.term) then score=score-.15 end
        local key=entry.id..":"..tostring(entry.slots.guideId or "")
        if best<9 and (not byId[key] or score<byId[key].score) then
            byId[key]={score=score,id=entry.id,label=entry.label,slots=entry.slots,term=entry.term}
        end
    end
    local rows={} for _,entry in pairs(byId) do rows[#rows+1]=entry end
    table.sort(rows,function(a,b) return a.score==b.score and a.label<b.label or a.score<b.score end)
    local out={} for n=1,math.min(3,#rows) do out[#out+1]=rows[n] end
    return out
end
local misses={fallback=true,fallback_echo=true,did_you_mean=true,did_you_mean_no=true}
function C.finish(session,raw,reply)
    local context=session.context
    if reply.intent=="help_me" then context.expect={kind="help_me",at=session.turns} end
    if not misses[reply.intent] then
        context.missStreak=0
        if reply.intent~="ack" and reply.intent~="thanks" then context.suggested=nil end
        return reply
    end
    context.missStreak=math.min(100,(context.missStreak or 0)+1)
    local choices=C.suggestions(session,raw)
    if #choices==0 then choices=C.defaultSuggestions() end
    context.suggested={choices=choices,turn=session.turns}
    local known=false
    for word in C.normal(raw):gmatch("%a+") do if #word>=4 and not stop[word] and SC.EmmaUnderstand.known(word) then known=true end end
    local best=choices[1]
    if reply.intent=="did_you_mean" and best and best.score<=1.05
        and (not choices[2] or choices[2].score-best.score>=.4) and (not known or best.score==0) then
        reply.lines={'Did you mean "'..best.label..'"? Type yes or no.'}
        context.pending={intent=best.id,slots=best.slots,choices=choices}
    else
        context.pending=nil
        -- A miss always helps. English words and known nouns never earn a put-down.
        reply.lines={context.missStreak>1 and "I am still missing the subject. Please rephrase or spell the word; let's narrow it down."
            or "I could not place that question yet. Please rephrase or spell the word."}
        if reply.intent=="did_you_mean" then reply.intent="fallback" end
    end
    local labels={} for _,choice in ipairs(choices) do labels[#labels+1]=choice.label end
    if #labels==0 then labels={"people","nearby zombies","power"} end
    reply.lines[#reply.lines+1]="Try: "..table.concat(labels,", ").."."
    if context.missStreak>=2 and not context.missMenuShown then
        context.missMenuShown=true
        reply.lines[#reply.lines+1]="Topics: people, supplies, jobs, threats, power, weather, county files, or EMMA. Type one of those."
    end
    context.last={lines=reply.lines,category=reply.category,sensitive=reply.sensitive}
    return reply
end
B.registerHandler("hunted",function(_,reply,turn,world)
    reply.category="zombies"
    reply.lines={"Break line of sight. Put solid cover between you and the dead, then change direction quietly. Leave yourself an exit."}
    local camp=world and world.camp and world.camp()
    if camp and camp.inside and world.zombies then
        local z=world.zombies()
        if z and type(z.count)=="number" then reply.lines[#reply.lines+1]=math.floor(z.count).." nearby zombies in the current reading." end
    end
end)
return C
