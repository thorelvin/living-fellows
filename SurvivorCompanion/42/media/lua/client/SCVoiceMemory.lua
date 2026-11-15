-- SPDX-License-Identifier: MIT
-- Compact save-local speech memory. No text, actor references or command
-- fields are saved: 96 counted hashes plus four bounded daily Bloom filters.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local V={} SC.VoiceMemory=V
local alphabet="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local digits={} for n=1,#alphabet do digits[alphabet:sub(n,n)]=n-1 end
local cache={}
local together={}
local WIDTH,LIMIT,BIN_WIDTH,BINS=13,96,68,4
V.MAX_BYTES=LIMIT*WIDTH+BIN_WIDTH*BINS
local function encode(value,width)
    local out=""
    for n=1,width do local d=value%64 out=alphabet:sub(d+1,d+1)..out value=math.floor(value/64) end
    return out
end
local function decode(value)
    local out=0 for n=1,#value do out=out*64+(digits[value:sub(n,n)] or 0) end
    return out
end
local function h(value) return SC.DiaryText.stableHash(value) end
local function now() return SC.LifeEvents.now()/60000 end
local function actorId(actor) return type(actor)=="string" and actor or SC.GameplayUtil.idOf(actor) end
local function valid(value,maximum,modulus)
    return type(value)=="string" and #value<=maximum and #value%modulus==0 and not value:find("[^%w_-]")
end
function V.clean(source)
    local out,count,inspected={},0,0
    for id,row in pairs(type(source)=="table" and source or {}) do
        inspected=inspected+1 if count>=64 or inspected>128 then break end
        if type(id)=="string" and #id>0 and #id<=80 and type(row)=="table" then
            local p=valid(row.p,LIMIT*WIDTH,WIDTH) and row.p or ""
            local b=valid(row.b,BIN_WIDTH*BINS,BIN_WIDTH) and row.b or ""
            local t=type(row.t)=="number" and row.t==row.t and row.t>=0 and row.t<math.huge and row.t or 0
            out[id]={p=p,b=b,t=math.min(t,86400000000000)} count=count+1
        end
    end
    return out
end
local function load(actor)
    local id=actorId(actor)
    local row=SC.Community.voiceMemoryFor(id)
    local prior=cache[id]
    if prior and prior.p==row.p and prior.b==row.b then return prior,row end
    local value={p=row.p,b=row.b,entries={},lookup={},bins={}}
    for n=1,#row.p,WIDTH do
        local key=decode(row.p:sub(n,n+5))
        local entry={key=key,minute=decode(row.p:sub(n+6,n+8)),count=decode(row.p:sub(n+9,n+9)),
            topic=decode(row.p:sub(n+10,n+12))}
        value.entries[#value.entries+1]=entry value.lookup[key]=entry
    end
    for n=1,BINS do
        local start=(n-1)*BIN_WIDTH+1
        local part=row.b:sub(start,start+BIN_WIDTH-1)
        value.bins[n]={day=#part==BIN_WIDTH and decode(part:sub(1,4)) or -1,
            bits=#part==BIN_WIDTH and part:sub(5) or string.rep("0",64)}
    end
    local count=0 for _ in pairs(cache) do count=count+1 end
    if count>=64 then cache={} end
    cache[id]=value return value,row
end
local function bitSet(bits,index)
    local position=math.floor(index/6)+1
    local flag=2^(index%6)
    local value=decode(bits:sub(position,position))
    if math.floor(value/flag)%2==0 then value=value+flag end
    return bits:sub(1,position-1)..encode(value,1)..bits:sub(position+1)
end
local function bitHas(bits,index)
    local position=math.floor(index/6)+1
    return math.floor(decode(bits:sub(position,position))/2^(index%6))%2==1
end
local function positions(key) return key%384,math.floor(key/389)%384,math.floor(key/1511)%384 end
local function bloomHas(value,key,today)
    local a,b,c=positions(key)
    for _,bin in ipairs(value.bins) do
        if today-bin.day>=0 and today-bin.day<=3 and bitHas(bin.bits,a) and bitHas(bin.bits,b) and bitHas(bin.bits,c) then return true end
    end
    return false
end
local function pack(value,row)
    local chunks={}
    for _,e in ipairs(value.entries) do chunks[#chunks+1]=encode(e.key,6)..encode(e.minute,3)..encode(e.count,1)..encode(e.topic,3) end
    row.p=table.concat(chunks) chunks={}
    for _,bin in ipairs(value.bins) do chunks[#chunks+1]=encode(bin.day<0 and 16777215 or bin.day,4)..bin.bits end
    row.b=table.concat(chunks) value.p,value.b=row.p,row.b
end
local function note(actor,topic,text,bloom)
    local value,row=load(actor)
    local key=h(text) local old=value.lookup[key]
    for n=#value.entries,1,-1 do if value.entries[n].key==key then table.remove(value.entries,n) break end end
    local e={key=key,minute=math.floor(now())%262144,count=math.min(63,(old and old.count or 0)+1),topic=h(topic)%262144}
    value.entries[#value.entries+1]=e value.lookup[key]=e
    while #value.entries>LIMIT do local dropped=table.remove(value.entries,1) value.lookup[dropped.key]=nil end
    if bloom then
        local today=math.floor(now()/1440)
        local bin=value.bins[today%BINS+1]
        if bin.day~=today then bin.day=today bin.bits=string.rep("0",64) end
        local a,b,c=positions(key)
        bin.bits=bitSet(bitSet(bitSet(bin.bits,a),b),c)
    end
    pack(value,row)
end
function V.count(actor,key)
    local value=load(actor) local e=value.lookup[h(key)] return e and e.count or 0
end
function V.noteKey(actor,key) note(actor,"selection",key,false) end
function V.note(actor,topic,text) note(actor,topic,text,true) end
function V.observeTogether(actor,close)
    local key=actorId(actor) local current=SC.LifeEvents.now()
    local prior=together[key]
    if prior and prior.close and close and current>=prior.at and current-prior.at<=3600000 then
        local row=SC.Community.voiceMemoryFor(key)
        row.t=math.min(86400000000000,(tonumber(row.t) or 0)+current-prior.at)
    end
    local count=0 for _ in pairs(together) do count=count+1 end
    if count>=64 and not together[key] then together={} end
    together[key]={at=current,close=close==true}
end
function V.daysTogether(actor) return (tonumber(SC.Community.voiceMemoryFor(actorId(actor)).t) or 0)/86400000 end
function V.applies(topic)
    -- Immediate threat/withdrawal explanations retain their availability.
    if topic:find("^banter%.refusal%.") or topic:find("^banter%.distraction%.")
        or topic=="banter.crowd.yield" or topic:find("^banter%.interior%.panic_") then return false end
    return topic:find("^banter%.") or topic:find("^scene%.") or topic:find("^recall%.")
        or topic:find("^ambient%.") or topic:find("^follow%.") or topic:find("^routine%.")
        or topic:find("^background%.") or topic:find("^memory%.")
end
function V.filter(actor,topic,source,render,poolSize)
    local value=load(actor)
    local candidates,least={},math.huge
    local today=math.floor(now()/1440)
    local topicKey=h(topic)%262144
    local window=math.min(8,math.floor(poolSize/2))
    local recent,found={},0
    for n=#value.entries,1,-1 do
        local entry=value.entries[n]
        if entry.topic==topicKey then
            if found>=window then break end
            recent[entry.key]=true found=found+1
        end
    end
    for _,line in ipairs(source) do
        local text=render(line)
        local key=text and h(text)
        if key and not recent[key] and (poolSize<8 or not bloomHas(value,key,today)) then
            local entry=value.lookup[key]
            local count=entry and entry.count or 0
            if count<least then candidates={} least=count end
            if count==least then candidates[#candidates+1]=line end
        end
    end
    -- Small pools retain a widened window when possible, but cannot become
    -- permanently silent merely because every authored line was heard.
    if #candidates==0 and poolSize<8 then
        for _,line in ipairs(source) do local text=render(line)
            local e=text and value.lookup[h(text)] local count=e and e.count or 0
            if count<least then candidates={} least=count end
            if count==least then candidates[#candidates+1]=line end
        end
    end
    return candidates
end
function V.chooseKey(actor,rows,seed)
    local least,choices=math.huge,{}
    for _,row in ipairs(rows) do
        local count=V.count(actor,"card:"..row.id)
        if count<least then least=count choices={} end
        if count==least then choices[#choices+1]=row end
    end
    return choices[#choices>0 and h(seed)%#choices+1 or 1]
end
function V.reset() cache={} together={} end
function V._encodeForTests(...) return encode(...) end
function V._decodeForTests(...) return decode(...) end
return V
