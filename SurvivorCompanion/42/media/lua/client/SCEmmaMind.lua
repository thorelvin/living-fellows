-- SPDX-License-Identifier: MIT
-- Shared world memory, touched only at the keyboard. Temporary conversations
-- and care dialogue never enter this record. No tick, scan or actor cache.
require "SCEmmaMindData"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local M={} SC.EmmaMind=M
M.KEY="LF_EmmaMindV1"
M.FRAGMENT_KEY="LF_EmmaFrag"
M.MERGED_KEY="LF_EmmaMerged"
M.OPERATOR_KEY="LF_EmmaOperatorV1"
M.MAX_FRAGMENTS=512
local serial=0
local function clean(value,limit)
    if type(value)~="string" then return "" end
    return value:gsub("[%c]"," "):gsub("[{}]",""):gsub("%s+"," "):match("^%s*(.-)%s*$"):sub(1,limit)
end
local function number(value,maximum,default)
    local n=tonumber(value)
    return n and n==n and n>=0 and n<=maximum and n or default
end
local function integer(value,maximum) return math.floor(number(value,maximum,0)) end
local function revised(value) return (value+1)%1000000000 end
local function call(object,name,...)
    if not object then return nil end
    local value,okay=SC.GameplayUtil.call(object,name,...)
    return okay and value or nil
end
local function identity(prefix)
    serial=serial+1
    local stamp=type(getTimestampMs)=="function" and getTimestampMs() or 0
    local random=type(ZombRand)=="function" and ZombRand(2147483646) or math.random(1,2147483646)
    return prefix..":"..tostring(stamp)..":"..tostring(random)..":"..serial
end
function M.tier(count)
    local tier=0
    for index,limit in ipairs(SC.EmmaMindData.tiers) do if count>=limit then tier=index end end
    return tier
end
function M.noteLimit(count)
    return count>=12 and 20 or count>=4 and 16 or count>=2 and 12 or 8
end
function M.normalize(raw)
    raw=type(raw)=="table" and raw or {}
    local state={version=1,token=clean(raw.token,96),operators={},notes={},fragments={},domains={},
        visits=integer(raw.visits,1000000),notesRevision=integer(raw.notesRevision,999999999)}
    if state.token=="" then state.token=identity("emma") end
    local seen={}
    for index=1,8 do
        local row=type(raw.operators)=="table" and raw.operators[index]
        if type(row)=="table" then
            local id=clean(row.id,96)
            if id~="" and not seen[id] then
                seen[id]=true
                state.operators[#state.operators+1]={id=id,name=clean(row.name,40),alias=clean(row.alias,40),
                    visits=integer(row.visits,100000),lastSeen=number(row.lastSeen,10000000),
                    infectTold=clean(row.infectTold,48),infectTimeTold=clean(row.infectTimeTold,48),
                    firstDay=integer(row.firstDay,1000000),lastDay=integer(row.lastDay,1000000),dead=row.dead==true}
            end
        end
    end
    state.current=seen[raw.current] and raw.current or nil
    seen={}
    for index=1,20 do
        local note=type(raw.notes)=="table" and clean(raw.notes[index],80) or ""
        if note~="" and not seen[note] then state.notes[#state.notes+1]=note;seen[note]=true end
    end
    local changed=type(raw.notes)~="table" and raw.notes~=nil
    if type(raw.notes)=="table" then
        changed=#raw.notes~=#state.notes
        for index,note in ipairs(state.notes) do if raw.notes[index]~=note then changed=true end end
    end
    if changed then state.notesRevision=revised(state.notesRevision) end
    local count,checked=0,0
    if type(raw.fragments)=="table" then for id,row in pairs(raw.fragments) do
        checked=checked+1;if checked>M.MAX_FRAGMENTS then break end
        if type(id)=="string" and id~="" and #id<=96 and not id:find("[%c]") and type(row)=="table" then
            state.fragments[id]={kind=clean(row.kind,32),town=clean(row.town,64),day=integer(row.day,1000000)}
            count=count+1
        end
    end end
    state.fragmentCount=count
    for _,domain in ipairs({"body","calendar"}) do
        state.domains[domain]=type(raw.domains)=="table" and integer(raw.domains[domain],1000000) or 0
    end
    local last=type(raw.lastLogin)=="table" and raw.lastLogin or {}
    state.lastLogin={computer=clean(last.computer,96),place=clean(last.place,80),
        at=number(last.at,10000000),operator=clean(last.operator,96)}
    return state
end
function M.state()
    if not ModData or type(ModData.getOrCreate)~="function" then return nil,"Shared memory storage is unavailable." end
    local okay,raw=pcall(ModData.getOrCreate,M.KEY)
    if not okay or type(raw)~="table" then return nil,"Shared memory storage is unavailable." end
    if raw.version~=nil and raw.version~=1 then return nil,"This shared memory uses an unsupported format." end
    local normalized=M.normalize(raw)
    for key,value in pairs(normalized) do raw[key]=value end
    return raw
end
local function rowFor(state,id)
    for _,row in ipairs(state.operators) do if row.id==id then return row end end
end
local function copyNotes(notes)
    local copy={};for _,note in ipairs(notes) do copy[#copy+1]=note end;return copy
end
function M.operatorId(player)
    if type(getSpecificPlayer)=="function" and getSpecificPlayer(0)~=player then return nil end
    local data=call(player,"getModData")
    if type(data)~="table" then return nil end
    local id=clean(data[M.OPERATOR_KEY],96)
    if id=="" then id=identity("operator");data[M.OPERATOR_KEY]=id end
    return id
end
-- inputs are plain facts from this computer, not a county survey.
function M.enter(player,pc,portable,facts,legacy)
    if not pc or pc.locked or not portable then return nil end
    if pc.lock and pc.lock.kind=="persona" then portable.LF_EmmaPersona=true end
    if portable.LF_EmmaPersona then return nil end
    local operator=M.operatorId(player)
    if not operator then return nil end
    local state,reason=M.state()
    if not state then return nil,reason end
    facts=facts or {}
    local now=number(facts.hours,10000000)
    local day=math.max(1,math.floor((now or 0)/24)+1)
    local row=rowFor(state,operator)
    local firstOperator=#state.operators==0
    if not row then
        row={id=operator,name=clean(facts.name,40),alias="",visits=0,firstDay=day,lastDay=day}
        if #state.operators>=8 then table.remove(state.operators,1) end
        state.operators[#state.operators+1]=row
    end
    local stamp=clean(portable[M.FRAGMENT_KEY],96)
    if stamp=="" then stamp=pc.identity;portable[M.FRAGMENT_KEY]=stamp end
    local previousCount=state.fragmentCount
    local new=not state.fragments[stamp] and previousCount<M.MAX_FRAGMENTS
    if new then
        state.fragments[stamp]={kind=clean(facts.kind,32),town=clean(facts.town,64),day=day}
        state.fragmentCount=previousCount+1
    end
    legacy=SC.TerminalBrain.normalizeMemory(legacy)
    local receipt=portable[M.MERGED_KEY]
    if type(receipt)~="table" or receipt.world~=state.token then
        receipt={world=state.token,notes=0,visits=false};portable[M.MERGED_KEY]=receipt
    end
    if receipt.visits~=true then
        if firstOperator and legacy.operator then row.alias=legacy.operator end
        state.visits=math.min(1000000,state.visits+legacy.visits)
        row.visits=math.min(100000,row.visits+legacy.visits)
        if row.lastSeen==nil then row.lastSeen=legacy.lastSeen end
        receipt.visits=true
    end
    -- Retain the unread tail on its original PC when the shared notebook is
    -- full. Already migrated/deleted entries must never be imported again.
    receipt.notes=integer(receipt.notes,8)
    local known={};for _,note in ipairs(state.notes) do known[note]=true end
    for index=receipt.notes+1,#legacy.notes do
        local note=legacy.notes[index]
        if not known[note] then
            if #state.notes>=M.noteLimit(state.fragmentCount) then break end
            state.notes[#state.notes+1]=note;known[note]=true;state.notesRevision=revised(state.notesRevision)
        end
        receipt.notes=index
    end
    local memory={operator=row.alias~="" and row.alias or nil,notes=copyNotes(state.notes),visits=row.visits,lastSeen=row.lastSeen}
    local previous=state.lastLogin
    local domain
    local recovered=state.fragments[stamp]
    local kind=recovered and recovered.kind
    if SC.EmmaMindData.body[kind] and state.domains.body==0 then state.domains.body=day;domain="body" end
    if SC.EmmaMindData.calendar[kind] and state.domains.calendar==0 then state.domains.calendar=day;domain="calendar" end
    if state.fragmentCount>=12 then
        for _,key in ipairs({"body","calendar"}) do if state.domains[key]==0 then state.domains[key]=day;domain=key end end
    end
    state.current=operator
    state.visits=math.min(1000000,state.visits+1)
    row.visits=math.min(100000,row.visits+1);row.lastSeen=now;row.lastDay=day
    state.lastLogin={computer=pc.identity,operator=operator,place=clean(facts.place,80),at=now}
    return {world=state.token,operator=operator,computer=pc.identity,memory=memory,limit=M.noteLimit(state.fragmentCount),
        count=state.fragmentCount,tier=M.tier(state.fragmentCount),new=new,kind=kind,domain=domain,
        pendingNotes=math.max(0,#legacy.notes-receipt.notes),
        tierUp=M.tier(state.fragmentCount)>M.tier(previousCount),
        previous=previous.operator==operator and previous.computer~=pc.identity and previous or nil}
end
function M.refresh(session)
    local binding=session and session.emmaMind
    if not binding then return nil end
    local state,reason=M.state()
    if not state or state.token~=binding.world then return nil,reason or "The shared memory changed. Reopen this computer." end
    local row=rowFor(state,binding.operator)
    if not row then return nil,"The operator record changed. Reopen this computer." end
    session.notes=copyNotes(state.notes);session.noteLimit=M.noteLimit(state.fragmentCount)
    session.operator=row.alias~="" and row.alias or row.name
    session.namedOperator=row.alias~=""
    return state,row
end
function M.commit(session)
    local state,row=M.refresh(session)
    return state~=nil
end
function M.rename(session,name)
    local state,row=M.refresh(session)
    if not state then return false,row end
    row.alias=clean(name,40);session.operator=row.alias;session.namedOperator=row.alias~=""
    return true
end
function M.remember(session,note)
    local state,reason=M.refresh(session)
    if not state then return false,reason end
    note=clean(note,80)
    if note=="" then return false,"Name the note to remember." end
    for _,saved in ipairs(state.notes) do if saved==note then return true end end
    if #state.notes>=M.noteLimit(state.fragmentCount) then return false,"The shared notebook is full. Choose a note to forget, or recover more computers." end
    state.notes[#state.notes+1]=note;state.notesRevision=revised(state.notesRevision)
    session.notes=copyNotes(state.notes)
    return true
end
function M.prepareForget(session,proposal)
    local state,reason=M.refresh(session)
    if not state then return nil,reason end
    local index=tonumber(proposal.note)
    if not proposal.all and (not index or index~=math.floor(index) or not state.notes[index]) then return nil,"That note is no longer in the shared notebook." end
    if #state.notes==0 then return nil,"There are no shared notes to erase." end
    local binding=session.emmaMind
    return {world=state.token,operator=binding.operator,revision=state.notesRevision,index=index,all=proposal.all==true,
        snapshot=table.concat(state.notes,"\31")},
        proposal.all and "Erase ALL shared notes on every EMMA computer? [Y/N]"
        or "Erase shared note "..index..": "..state.notes[index].."? This affects every EMMA computer. [Y/N]"
end
function M.forget(session,target)
    local state,reason=M.refresh(session)
    if not state then return false,reason end
    if target.world~=state.token or target.operator~=session.emmaMind.operator or target.revision~=state.notesRevision
        or target.snapshot~=table.concat(state.notes,"\31") then
        return false,"The shared notebook changed. Choose the note again."
    end
    if target.all then state.notes={}
    elseif target.index and state.notes[target.index] then table.remove(state.notes,target.index)
    else return false,"That note is no longer present." end
    state.notesRevision=revised(state.notesRevision);session.notes=copyNotes(state.notes)
    return true,"Shared notebook updated."
end
function M.bootLines(session,entry)
    local lines={}
    if not entry or SC.EmmaCare and SC.EmmaCare.quiet(session) then return lines end
    local data=SC.EmmaMindData
    if entry.new then
        local pool=data.fragment;local pick=math.max(1,math.min(#pool,tonumber(session.random(#pool)) or 1))
        lines[#lines+1]=pool[math.floor(pick)]:gsub("{fragments}",tostring(entry.count))
        lines[#lines+1]=data.kinds[data.groups[entry.kind] or entry.kind] or data.kinds.office
        if entry.tierUp then lines[#lines+1]=data.tier[entry.tier]
        elseif entry.domain then lines[#lines+1]=(entry.domain=="body" and "Medical" or "County calendar").." index recovered." end
    elseif entry.tier>=1 and entry.previous and entry.previous.at then
        lines[#lines+1]="Different desk, same operator. Last login: "..(entry.previous.place~="" and entry.previous.place or "another computer").."."
    end
    if entry.pendingNotes>0 then
        lines[math.min(#lines+1,3)]=entry.pendingNotes.." older notes remain on this computer. Make room in the shared notebook, then reopen it."
    end
    return lines
end
function M.report(session)
    local state,reason=M.refresh(session)
    if not state then return {reason or "No shared memory is connected to this conversation."} end
    local lines={"Computer recovery: "..state.fragmentCount..(state.fragmentCount==1 and " fragment recovered." or " fragments recovered."),
        "Shared notes: "..#state.notes.." / "..M.noteLimit(state.fragmentCount)..".",
        "Each ordinary computer contributes once. Moving or resetting it adds no second fragment."}
    local nextTier=SC.EmmaMindData.tiers[M.tier(state.fragmentCount)+1]
    if nextTier then lines[#lines+1]="Next memory tier at "..nextTier.." fragments." end
    lines[#lines+1]="Medical index: "..(state.domains.body>0 and "recovered" or "missing").."; county calendar: "..(state.domains.calendar>0 and "recovered" or "missing").."."
    return lines
end
return M
