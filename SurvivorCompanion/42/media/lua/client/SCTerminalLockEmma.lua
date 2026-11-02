-- SPDX-License-Identifier: MIT
-- Numbered arguments, verified claims and a small persistent conversation.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local Emma={} SC.TerminalLockEmma=Emma
Emma.KINDS={"truth","authority","pity","threat","humour"}
local function U() return SC.ControlUtil end
local function data() return SC.TerminalLockEmmaData end
local function pickLine(state,lines,salt)
    return lines[((state.seed+(salt or 0))%#lines)+1]
end
function Emma.argument(id)
    for _,argument in ipairs(data().arguments) do if argument.id==id then return argument end end
end
function Emma.temperament(state)
    local pick=SC.TerminalSystem.random(state.seed+23117)
    local weak=pick(5) local hard=pick(4) if hard>=weak then hard=hard+1 end
    return Emma.KINDS[weak],Emma.KINDS[hard]
end
function Emma.facts(w)
    local hours=U().hours()
    local count=0
    for i,actor in ipairs(SC.Registry and SC.Registry.living() or {}) do
        if i>256 then break end
        local record=SC.Registry.byId(SC.Registry.idOf(actor))
        if record and record.recruited==true and U().call(actor,"isDead")~=true then count=count+1 end
    end
    local held=false
    for _,slot in ipairs({"getPrimaryHandItem","getSecondaryHandItem"}) do
        local item=U().call(w.player,slot)
        local kind=U().call(item,"getFullType")
        if type(kind)=="string" and kind:find("Screwdriver",1,true) then held=true end
    end
    local okay,threat=pcall(SC.TerminalWorld.nearestThreat,w.player,{},SC.GameplayUtil.nowMs())
    local complete=okay and not threat.unknown and not threat.partial
    return {days=hours and math.floor(hours/24),people=count,electrical=SC.Terminal.electricalSkill(w.player),
        screwdriver=held,zombie=okay and threat.distance and threat.distance<=10 or false,
        threatKnown=complete or okay and threat.distance and threat.distance<=10,
        distance=okay and threat.distance and math.floor(threat.distance*10+.5)/10 or 0}
end
function Emma.fill(text,values)
    return (text:gsub("{([A-Z]+)}",function(key) return tostring(values[key] or 0) end))
end
function Emma.ensure(state)
    state.lock.emma=state.lock.emma or {round=0,conviction=0,patience=2,attempt=0,used={},history={},mentions=0}
    return state.lock.emma
end
function Emma.offers(w)
    local state=w.system local e=Emma.ensure(state)
    if e.offers or e.won or e.retryUntil then return e.offers or {} end
    local pick=SC.TerminalSystem.random(state.seed+e.attempt*209759+e.round*4099+37607)
    local weak=Emma.temperament(state) local excluded=pick(5)
    if SC.Terminal.electricalSkill(w.player)>=3 and Emma.KINDS[excluded]==weak then excluded=excluded%5+1 end
    local kinds={}
    for index,kind in ipairs(Emma.KINDS) do if index~=excluded then kinds[#kinds+1]=kind end end
    for i=#kinds,2,-1 do local j=pick(i) kinds[i],kinds[j]=kinds[j],kinds[i] end
    local facts=Emma.facts(w) e.offers={}
    for _,kind in ipairs(kinds) do
        local candidates={}
        for _,argument in ipairs(data().arguments) do
            if argument.kind==kind and not e.used[argument.id] then candidates[#candidates+1]=argument end
        end
        local argument=candidates[pick(#candidates)]
        local offer={id=argument.id}
        if argument.claim and type(facts[argument.claim])=="number" then
            offer.truthful=facts[argument.claim]>0 and pick(2)==1
            offer.number=offer.truthful and facts[argument.claim] or math.min(10000000,facts[argument.claim]*2+pick(3))
        end
        e.used[argument.id]=true e.offers[#e.offers+1]=offer
    end
    return e.offers
end
function Emma.loss(w,now)
    local e=w.system.lock.emma
    e.retryUntil=now+1 e.offers=nil w.system.lock.bypass=true
    e.history[#e.history+1]={reply=pickLine(w.system,data().losses,e.round)}
    SC.TerminalLockCrew.react(w,"failure",50)
end
function Emma.input(w,raw)
    local now=U().hours()
    if not now then w.securityMessage="Clock unavailable." return true end
    local e=Emma.ensure(w.system)
    if e.retryUntil then
        if now<e.retryUntil then w.securityMessage="Discussion closed. Retry in "..math.ceil((e.retryUntil-now)*60).." minutes." return true end
        local mentions,lie=e.mentions,e.lie
        w.system.lock.emma={round=0,conviction=0,patience=2,attempt=math.min(1000000,e.attempt+1),used={},history={},mentions=mentions,lie=lie}
        e=w.system.lock.emma
        w.securityMessage=nil w.securityScroll=0
        Emma.offers(w)
        return true
    end
    local index=tonumber(raw)
    if not index or index~=math.floor(index) or index<1 or index>4 then w.securityMessage="Choose an argument by number: 1-4." return true end
    local offer=Emma.offers(w)[index] local argument=offer and Emma.argument(offer.id)
    if not argument then w.securityMessage="The argument record is unavailable." return true end
    local facts=Emma.facts(w) local actual=argument.claim and facts[argument.claim]
    if argument.claim=="days" and actual==nil or argument.claim=="zombie" and not facts.threatKnown then
        w.securityMessage="I cannot verify that record yet. Choose another argument." return true
    end
    if offer.truthful and offer.number~=actual then
        offer.number=actual
        w.securityMessage="That record changed while you were reading. I have updated the argument; choose again."
        return true
    end
    local claimed=offer.number
    local values={N=claimed,TRUE=actual,FALSE=claimed,D=facts.distance}
    local caught=argument.claim and (type(actual)=="boolean" and not actual or type(actual)=="number" and claimed~=actual)
    local weak,hard=Emma.temperament(w.system) local response
    if caught then
        response=Emma.fill(argument.caught,values) e.patience=e.patience-1
        if not e.lie then e.lie={claim=argument.claim,actual=type(actual)=="number" and actual or 0,claimed=claimed or 0} end
    elseif argument.kind==hard then response=Emma.fill(argument.rejected,values) e.patience=e.patience-1
    else response=Emma.fill(argument.accepted,values) e.conviction=e.conviction+(argument.kind==weak and 2 or 1) end
    e.round=e.round+1 e.offers=nil w.securityMessage=nil w.securityScroll=100000
    e.history[#e.history+1]={argument=Emma.fill(argument.text,values),reply=response,id=argument.id}
    SC.TerminalLocks.record(w,argument.id,caught and "caught" or argument.kind==hard and "rejected" or "accepted")
    if e.conviction>=4 then
        e.won=argument.kind w.lockEmmaJustWon=true
        e.history[#e.history+1]={reply=pickLine(w.system,data().wins[argument.kind],e.round)}
        w.lockEmmaWinLine=e.history[#e.history].reply
        SC.TerminalLocks.finishUnlock(w,"emma")
    elseif e.patience<=0 or e.round>=5 then Emma.loss(w,now)
    elseif e.patience==1 then w.securityMessage=pickLine(w.system,data().warnings,e.round) end
    if not e.won and not e.retryUntil then Emma.offers(w) end
    return true
end
function Emma.lines(w)
    local e=Emma.ensure(w.system) local rows={pickLine(w.system,data().openers)}
    for _,exchange in ipairs(e.history) do
        if exchange.argument then rows[#rows+1]="> "..exchange.argument end
        rows[#rows+1]=exchange.reply
    end
    rows[#rows+1]="CONVICTION "..e.conviction.."/4 | PATIENCE "..e.patience.."/2 | ROUND "..math.min(5,e.round+1).."/5"
    local clue=w.system.lock.crewClue
    if clue and clue.kind=="emma" then rows[#rows+1]="Companion's advice: try "..clue.value.."." end
    if w.securityMessage then rows[#rows+1]=w.securityMessage end
    if e.retryUntil then
        local now=U().hours()
        if not now or now<e.retryUntil then
            rows[#rows+1]="Discussion closed for one hour. Other ways in remain available." return rows
        end
        rows[#rows+1]="[1] Start another discussion"
        return rows
    end
    local weak=Emma.temperament(w.system)
    local offers=e.offers or {}
    for index,offer in ipairs(offers) do
        local argument=Emma.argument(offer.id)
        local label="["..index.."] "..Emma.fill(argument.text,{N=offer.number})
        rows[#rows+1]=label
        if SC.Terminal.electricalSkill(w.player)>=3 and argument.kind==weak then rows[#rows+1]="[SHE HESITATES] Electrical training: she has a tell." end
    end
    return rows
end
function Emma.onVisit(w)
    local e=w.system.lock and w.system.lock.emma
    if not e or not e.won or w.lockEmmaJustWon or w.lockEmmaMentioned or (e.mentions or 0)>=3 then return end
    w.lockEmmaMentioned=true e.mentions=(e.mentions or 0)+1
    local line
    if e.lie then
        line=Emma.fill(data().memory.lie[e.lie.claim],{TRUE=e.lie.actual,FALSE=e.lie.claimed})
    else
        local rows=e.won=="truth" and data().memory.clean or data().memory[e.won]
        line=pickLine(w.system,rows,e.mentions)
    end
    w:print(line,"emma")
end
return Emma
