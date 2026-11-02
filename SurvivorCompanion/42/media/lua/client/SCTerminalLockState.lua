-- SPDX-License-Identifier: MIT
-- Additive schema-one lock data. A damaged extension cannot erase a computer.
SurvivorCompanion=SurvivorCompanion or {}
local S={} SurvivorCompanion.TerminalLockState=S
local kinds={persona=true,pending=true,word=true,remember=true,wheel=true,emma=true,search=true,radio=true,phone=true,rival=true,story=true}
local argumentKinds={truth=true,authority=true,pity=true,threat=true,humour=true}
local claimKinds={days=true,people=true,screwdriver=true,zombie=true,electrical=true}
local function argumentId(id)
    if type(id)~="string" then return false end
    for _,argument in ipairs(SurvivorCompanion.TerminalLockEmmaData and SurvivorCompanion.TerminalLockEmmaData.arguments or {}) do
        if id==argument.id then return argument end
    end
    return false
end
local function broken(value)
    return {kind="word",legacy=true,attempts={},realItems=true,stash={committed=true,items={}},
        welcomed=type(value)=="table" and value.welcomed==true,
        grantedShown=type(value)=="table" and value.grantedShown==true}
end
function S.number(v,low,high)
    v=tonumber(v)
    if v and v==v and v>=low and v<=high then return v end
end
function S.text(v,limit)
    if type(v)=="string" and #v<=limit and not v:find("[%c]") then return v end
end
function S.location(v)
    if type(v)~="table" then return nil end
    local x,y,z=S.number(v.x,0,100000),S.number(v.y,0,100000),S.number(v.z,-32,32)
    local kind=S.text(v.type,40)
    if not x or not y or not z or not kind or x~=math.floor(x) or y~=math.floor(y) or z~=math.floor(z) then return nil end
    return {x=x,y=y,z=z,type=kind,sprite=S.text(v.sprite,96),open=v.open==true,forced=v.forced==true}
end
function S.normalize(value,locked)
    if value==nil then return locked and {kind="word",legacy=true,attempts={},realItems=true} or nil end
    if type(value)~="table" or not kinds[value.kind] then
        return broken(value)
    end
    local clean={kind=value.kind,machineKind=S.text(value.machineKind,40),legacy=value.legacy==true,
        bypass=value.bypass==true,welcomed=value.welcomed==true,crewHint=value.crewHint==true,unlockApplied=value.unlockApplied==true,
        settled=value.settled==true,realItems=value.realItems~=false,slip=value.slip==true,grantedShown=value.grantedShown==true,
        drawerChecked=value.drawerChecked==true,
        seenRecorded=value.seenRecorded==true,classic=value.classic==true,heard=value.heard==true,codeWrong=value.codeWrong==true,
        serial=S.text(value.serial,8),redialUntil=S.number(value.redialUntil,0,100000000),rivalGroup=S.text(value.rivalGroup,96),rewardTier=value.rewardTier and math.floor(S.number(value.rewardTier,1,3) or 1) or nil,
        manualSpawned=value.manualSpawned==true,manualItemId=S.text(value.manualItemId,40),
        caseFinished=value.caseFinished==true,attempts={},reactions={}}
    if value.kind=="persona" then
        local okay,persona=pcall(function()
            return SurvivorCompanion.TerminalPersona and SurvivorCompanion.TerminalPersona.normalize(value.persona)
        end)
        if not okay or not persona then return broken(value) end
        clean.persona=persona
        -- Keep malformed native saved numbers out of conversation selection,
        -- without modifying the supplied engine or losing the other fields.
        clean.persona.seed=math.floor(S.number(clean.persona.seed,1,2147483646) or 1)
        local h=value.home
        if type(h)=="table" then
            local x,y,z=S.number(h.x,0,100000),S.number(h.y,0,100000),S.number(h.z,-32,32)
            if x and y and z then clean.home={x=math.floor(x),y=math.floor(y),z=math.floor(z)} end
        end
        clean.effects={}
        local e=type(value.effects)=="table" and value.effects or {}
        for _,key in ipairs({"noiseAt","reliefDay","cheerDay"}) do clean.effects[key]=S.number(e[key],0,100000000) end
        clean.effects.weight=math.floor(S.number(e.weight,0,2) or 0)
    end
    if clean.serial and not clean.serial:match("^%d%d%d%d%d%d%d%d$") then return broken(value) end
    if value.story~=nil then
        clean.story=SurvivorCompanion.TerminalLockStory.normalize(value.story)
        if not clean.story then return broken(value) end
    end
    if value.fame~=nil then
        if type(value.fame)~="table" then return broken(value) end
        clean.fame={}
        for i=1,math.min(8,#value.fame) do
            local line=S.text(value.fame[i],160) if not line then return broken(value) end
            clean.fame[#clean.fame+1]=line
        end
    end
    if value.phone~=nil then
        clean.phone=S.location(value.phone)
        if not clean.phone then return broken(value) end
        clean.phone.room=S.text(value.phone.room,48) or "internal office"
    end
    if value.rival~=nil then
        local r=value.rival
        if type(r)~="table" or not S.number(r.remainingMs,0,25000) or type(r.guesses)~="table" or #r.guesses>16 then return broken(value) end
        clean.rival={remainingMs=r.remainingMs,guesses={},message=S.text(r.message,200),lost=r.lost==true,
            winner=(r.winner=="player" or r.winner=="user2") and r.winner or nil}
        for _,g in ipairs(r.guesses) do
            if type(g)~="table" or not S.text(g.word,6) or not g.word:match("^[A-Z][A-Z][A-Z][A-Z][A-Z][A-Z]$")
                or not S.number(g.likeness,0,6) or g.likeness~=math.floor(g.likeness) then return broken(value) end
            clean.rival.guesses[#clean.rival.guesses+1]={word=g.word,likeness=g.likeness}
        end
    end
    for _,moment in ipairs({"first","failure","unlock","clutch","phone","radio"}) do
        if type(value.reactions)=="table" and value.reactions[moment]==true then clean.reactions[moment]=true end
    end
    if type(value.crewClue)=="table" and (value.crewClue.kind=="story" or value.crewClue.kind=="wheel" or value.crewClue.kind=="search" or value.crewClue.kind=="emma" or value.crewClue.kind=="phone" or value.crewClue.kind=="radio")
        and S.text(value.crewClue.value,40) then
        clean.crewClue={kind=value.crewClue.kind,value=value.crewClue.value,stage=math.floor(S.number(value.crewClue.stage,0,5) or 0)}
    end
    for i=1,math.min(type(value.attempts)=="table" and #value.attempts or 0,6) do
        local a=value.attempts[i]
        if type(a)=="table" then
            local name,guess,result=S.text(a.name,64),S.text(a.guess,96),S.text(a.result,40)
            local day=S.number(a.day,0,10000000)
            if name and guess and result and day then clean.attempts[#clean.attempts+1]={name=name,guess=guess,result=result,day=day} end
        end
    end
    if value.crack~=nil then
        local c=value.crack
        if type(c)~="table" then return broken(value) end
        local done,required,last=S.number(c.doneHours,0,100000),S.number(c.requiredHours,1,100000),S.number(c.lastHours,0,100000000)
        if not done or not required or not last then return broken(value) end
        clean.crack={doneHours=math.min(done,required),requiredHours=required,lastHours=last,powered=c.powered==true,
            sealed=math.floor(S.number(c.sealed,0,80) or 0)}
    end
    if value.found~=nil then
        if type(value.found)~="table" then return broken(value) end
        clean.found={}
        local used={}
        for i=1,math.min(#value.found,4) do
            local index=S.number(value.found[i],1,4)
            if not index or index~=math.floor(index) or used[index] then return broken(value) end
            clean.found[#clean.found+1]=index used[index]=true
        end
    end
    if value.search~=nil then
        if type(value.search)~="table" or not S.number(value.search.misses,0,8) then return broken(value) end
        clean.search={misses=math.floor(value.search.misses),query=S.text(value.search.query,32)}
    end
    if value.wheel~=nil then
        local v=value.wheel
        if type(v)~="table" or not S.number(v.correct,0,3) or (v.required~=1 and v.required~=3)
            or not S.number(v.wrong,0,3) or not S.number(v.rotation,0,25) then return broken(value) end
        clean.wheel={correct=math.floor(v.correct),required=v.required,wrong=math.floor(v.wrong),rotation=math.floor(v.rotation),
            retryUntil=S.number(v.retryUntil,0,100000000)}
        if v.retryUntil~=nil and not clean.wheel.retryUntil then return broken(value) end
    end
    if value.emma~=nil then
        local v=value.emma
        if type(v)~="table" or not S.number(v.round,0,5) or not S.number(v.conviction,0,6)
            or not S.number(v.patience,0,2) or not S.number(v.attempt,0,1000000) then return broken(value) end
        local e={round=math.floor(v.round),conviction=math.floor(v.conviction),patience=math.floor(v.patience),
            attempt=math.floor(v.attempt),mentions=math.floor(S.number(v.mentions,0,3) or 0),used={},history={},
            retryUntil=S.number(v.retryUntil,0,100000000),won=argumentKinds[v.won] and v.won or nil}
        if v.retryUntil~=nil and not e.retryUntil or v.won~=nil and not e.won then return broken(value) end
        local inspected=0
        for id,used in pairs(type(v.used)=="table" and v.used or {}) do
            inspected=inspected+1 if inspected>30 then break end
            if argumentId(id) and used==true then e.used[id]=true end
        end
        if v.offers~=nil then
            if type(v.offers)~="table" or #v.offers~=4 then return broken(value) end
            e.offers={} local ids,offeredKinds={},{}
            for _,offer in ipairs(v.offers) do
                local argument=type(offer)=="table" and argumentId(offer.id)
                if not argument or ids[offer.id] or offeredKinds[argument.kind] or not e.used[offer.id] then return broken(value) end
                local number=S.number(offer.number,0,10000000)
                if (argument.claim=="days" or argument.claim=="people" or argument.claim=="electrical") and not number then return broken(value) end
                ids[offer.id]=true offeredKinds[argument.kind]=true
                e.offers[#e.offers+1]={id=offer.id,number=number,truthful=offer.truthful==true}
            end
        end
        for i=1,math.min(type(v.history)=="table" and #v.history or 0,7) do
            local exchange=v.history[i]
            if type(exchange)~="table" or not S.text(exchange.reply,200) then return broken(value) end
            e.history[#e.history+1]={argument=S.text(exchange.argument,200),reply=exchange.reply,
                id=argumentId(exchange.id) and exchange.id or nil}
        end
        if v.lie~=nil then
            if type(v.lie)~="table" or not claimKinds[v.lie.claim] or not S.number(v.lie.actual,0,10000000)
                or not S.number(v.lie.claimed,0,10000000) then return broken(value) end
            e.lie={claim=v.lie.claim,actual=v.lie.actual,claimed=v.lie.claimed}
        end
        clean.emma=e
    end
    if value.drawer~=nil then
        clean.drawer=S.location(value.drawer)
        if not clean.drawer then return broken(value) end
    end
    if value.stash~=nil then
        local v=value.stash
        if type(v)~="table" then return broken(value) end
        clean.stash={committed=v.committed==true,note=S.text(v.note,200),items={}}
        local where=S.location(v.location)
        if where then clean.stash.location=where end
        for i=1,math.min(type(v.items)=="table" and #v.items or 0,8) do
            local item=v.items[i]
            if type(item)=="table" and S.text(item.id,40) and S.text(item.type,80) then
                clean.stash.items[#clean.stash.items+1]={id=item.id,type=item.type}
            end
        end
    end
    return clean
end
return S
