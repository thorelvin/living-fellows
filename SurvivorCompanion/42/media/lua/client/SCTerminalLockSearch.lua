-- SPDX-License-Identifier: MIT
-- Deleted-sector recovery is an input-only lookup over the fixed lore corpus.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local Search={} SC.TerminalLockSearch=Search
local indexes={}
local stop={about=true,after=true,again=true,also=true,been=true,before=true,being=true,
    both=true,could=true,does=true,each=true,from=true,have=true,into=true,just=true,
    more=true,must=true,only=true,other=true,over=true,same=true,should=true,some=true,
    than=true,that=true,their=true,them=true,["then"]=true,there=true,these=true,they=true,
    this=true,those=true,very=true,were=true,what=true,when=true,where=true,which=true,
    ["while"]=true,will=true,with=true,would=true,your=true}
function Search.valid(raw)
    if type(raw)~="string" or #raw>32 then return nil end
    local query=raw:lower():match("^%s*(.-)%s*$")
    if #query<4 or stop[query] or not query:match("^[a-z]+$") then return nil end
    return query
end
function Search.indexes(archive)
    if indexes[archive] then return indexes[archive] end
    local profile=SC.TerminalFiles.get(archive)
    local result={}
    for index,entry in ipairs(profile and profile.entries or {}) do
        local candidates,seen={},{}
        for word in entry.text:lower():gmatch("[a-z]+") do
            if Search.valid(word) and not seen[word] then
                seen[word]=true
                local unique=true
                for other,sibling in ipairs(profile.entries) do
                    if other~=index and sibling.text:lower():find(word,1,true) then unique=false break end
                end
                if unique then candidates[#candidates+1]=word end
            end
        end
        table.sort(candidates,function(a,b) return #a==#b and a<b or #a>#b end)
        result[index]=candidates[1]
    end
    indexes[archive]=result
    return result
end
function Search.has(state,index)
    for _,found in ipairs(state.lock.found or {}) do if found==index then return true end end
    return false
end
function Search.nextIndex(state)
    local words=Search.indexes(state.archive)
    for i=1,4 do if not Search.has(state,i) then return words[i],i end end
end
local function initials(owner)
    local text=""
    for word in tostring(owner):gmatch("[A-Za-z]+") do text=text..word:sub(1,1):upper() end
    return text:sub(1,4)
end
local function sentence(entry,query)
    for line in entry.text:gmatch("[^.!?]+[.!?]?") do
        if line:lower():find(query,1,true) then return line:match("^%s*(.-)%s*$") end
    end
    return entry.text
end
function Search.query(state,raw)
    local query=Search.valid(raw)
    if not query then return nil,"Too many sectors. Use one word of 4-32 letters." end
    local profile=SC.TerminalFiles.get(state.archive)
    if not profile then return nil,"The owner index is unavailable." end
    local result={}
    local function collect(candidate)
        for index,entry in ipairs(candidate.entries) do
            if #result<4 and entry.text:lower():find(query,1,true) then
                result[#result+1]={archive=candidate.id,index=index,initials=initials(candidate.owner),
                    date=entry.date,title=entry.title,text=sentence(entry,query),own=candidate.id==profile.id}
            end
        end
    end
    collect(profile)
    for _,candidate in ipairs(SC.TerminalFiles.all()) do
        if #result>=4 then break end
        if candidate.kind==profile.kind and candidate.id~=profile.id then collect(candidate) end
    end
    return result,nil,query
end
function Search.ensure(state)
    state.lock.found=state.lock.found or {}
    state.lock.search=state.lock.search or {misses=0}
    local words=Search.indexes(state.archive)
    for i=1,4 do if not words[i] then return false end end
    return true
end
function Search.input(w,raw)
    local rows,reason,query=Search.query(w.system,raw)
    if not rows then w.securityMessage=reason return true end
    local state=w.system local progress=state.lock.search
    progress.query=query w.lockSearchResults=rows w.securityScroll=0
    local restored=0
    for _,row in ipairs(rows) do
        if row.own and not Search.has(state,row.index) then
            state.lock.found[#state.lock.found+1]=row.index restored=restored+1
        end
    end
    if #rows==0 then
        progress.misses=math.min(8,progress.misses+1)
        w.securityMessage="No matching sectors."
        if progress.misses>=3 then w.securityMessage=w.securityMessage.." Try INDEX: "..tostring(Search.nextIndex(state)) end
        if progress.misses>=8 then
            state.lock.bypass=true
            w.securityMessage=w.securityMessage.." Other ways in are available."
            if SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"failure",50) end
        end
    else
        w.securityMessage=restored>0 and (restored.." owner file(s) restored.") or "Sectors found; no new owner files restored."
    end
    if #state.lock.found==4 then SC.TerminalLocks.finishUnlock(w,"search") end
    return true
end
function Search.lines(w)
    local state=w.system local rows={"RESTORED FILES: "..#state.lock.found.."/4"}
    local nextWord=Search.nextIndex(state)
    if nextWord then rows[#rows+1]={text="[INDEX: "..nextWord.."]",searchWords=true} end
    local clue=state.lock.crewClue
    if clue and clue.kind=="search" then rows[#rows+1]={text="Companion's index: "..clue.value,searchWords=true} end
    if SC.Terminal.electricalSkill(w.player)>=3 and #state.lock.found==0 then
        rows[#rows+1]={text="[INDEX: "..Search.indexes(state.archive)[2].."]",searchWords=true}
        rows[#rows+1]="Electrical training: a second index recovered."
    end
    rows[#rows+1]=w.securityMessage or "Search deleted sectors. Click an index or any word in a result."
    for _,row in ipairs(w.lockSearchResults or {}) do
        rows[#rows+1]=row.initials.." | "..row.date.." | "..(row.own and "OWNER FILE" or "OTHER OWNER")
        rows[#rows+1]={text=row.text,searchWords=true}
        if row.own then
            local word=Search.nextIndex(state)
            if word then rows[#rows+1]={text="[INDEX: "..word.."]",searchWords=true} end
        end
    end
    return rows
end
return Search
