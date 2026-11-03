-- SPDX-License-Identifier: MIT
-- One bounded decision at first boot. No world scan, timer or event hook.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local D={} SC.TerminalPersonaDiscovery=D
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local okay,value=pcall(fn,...) if okay then return value end
end
function D.normalizeLedger(raw)
    local V=SC.TerminalLockState
    local old=type(raw.persona)=="table" and raw.persona or {}
    local boots=math.floor(V.number(old.boots,0,10000000) or 0)
    local last=V.number(old.lastAt,0,10000000)
    local clean={boots=boots,lastAt=last and math.min(boots,math.floor(last)) or nil,met={},talked={},campReady={},campMentions={},spiffyGuest=false}
    for _,id in ipairs(SC.TerminalPersona.ORDER) do
        if type(old.met)=="table" and old.met[id]==true then clean.met[id]=true end
        if clean.met[id] and type(old.talked)=="table" and old.talked[id]==true then clean.talked[id]=true end
        if id=="spiffy" and clean.talked[id] and old.spiffyGuest==true then clean.spiffyGuest=true end
        -- Older readiness did not prove that SPIFFY filed a nameless guest.
        if clean.talked[id] and type(old.campReady)=="table" and old.campReady[id]==true
            and (id~="spiffy" or clean.spiffyGuest) then clean.campReady[id]=true end
        -- Delivery remains consumed even when eligibility is requalified.
        if clean.talked[id] and type(old.campMentions)=="table" and old.campMentions[id]==true then clean.campMentions[id]=true end
    end
    raw.persona=clean
end
function D.noteConversation(w)
    local p=w.system and w.system.lock and w.system.lock.persona
    if not p or not p.met or (tonumber(p.spoken) or 0)<1 or not SC.TerminalPersonaData[p.id] then return end
    local ledger=SC.TerminalLocks.ledger()
    if ledger then
        local book=ledger.persona book.talked[p.id]=true
        -- The supplied follow-ups describe real outcomes, not just discovery.
        -- SPIFFY's line only fits a player it filed as VALUED GUEST.
        local guest=p.id=="spiffy" and not p.name and (tonumber(p.used and p.used.name_none) or 0)>0
        if guest then book.spiffyGuest=true end
        if guest or p.id=="ellis" and w.system.lock.effects and w.system.lock.effects.reliefDay~=nil
            or p.id=="duty" and p.flags.relieved then book.campReady[p.id]=true end
    end
end
local campLines={
    spiffy='You have started saying "valued guest". I would like to know where you picked that up.',
    ellis='You seem calmer. I did not do that. I would like to know who did.',
    duty='Something at the county level just signed off after a very long shift. It listed you as commanding officer. I have questions.',
}
function D.campLine(w)
    if not w.system or w.system.locked then return nil end
    local camp=w.world and read(w.world.camp)
    if type(camp)~="table" or camp.inside~=true then return nil end
    local ledger=SC.TerminalLocks.ledger() local book=ledger and ledger.persona
    if not book then return nil end
    for _,id in ipairs(SC.TerminalPersona.ORDER) do
        if book.campReady[id] and (id~="spiffy" or book.spiffyGuest==true) and not book.campMentions[id] then
            return campLines[id],id
        end
    end
end
function D.completeCampLine(w,id)
    if not campLines[id] or not w.system or w.system.locked then return false end
    local camp=w.world and read(w.world.camp)
    if type(camp)~="table" or camp.inside~=true then return false end
    local ledger=SC.TerminalLocks.ledger() local book=ledger and ledger.persona
    if not book or not book.campReady[id] or (id=="spiffy" and book.spiffyGuest~=true)
        or book.campMentions[id] then return false end
    book.campMentions[id]=true
    return true
end
function D.recoveryLine()
    local ledger=SC.TerminalLocks.ledger() local book=ledger and ledger.persona
    for _,id in ipairs(SC.TerminalPersona.ORDER) do
        if book and book.talked[id] then return "Some machines have questions of their own." end
    end
end
function D.remember(id)
    local ledger=SC.TerminalLocks.ledger()
    if not ledger or not SC.TerminalPersonaData[id] then return end
    if not ledger.persona.met[id] then
        ledger.persona.met[id]=true ledger.persona.lastAt=ledger.persona.boots
    end
end
function D.level()
    local option=SandboxVars and SandboxVars.LivingFellows and SandboxVars.LivingFellows.RareComputers
    return (option==1 or option==3) and option or 2
end
local function atCamp(player,object)
    local provider=read(SC.TerminalWorld.new,player,object)
    local camp=provider and read(provider.camp)
    -- Unknown camp membership is not permission to replace a home computer.
    if type(camp)~="table" then return nil end
    return camp.inside==true
end
local function override(deep)
    local config=type(SCConfig)=="table" and SCConfig or SC.Config
    if type(config)~="table" or read(isDebugEnabled)~=true then return nil end
    local id=config.debugPersona
    if id=="deep" then id=deep and "duty" or nil end
    if id and SC.TerminalPersonaData[id] then return id,config end
end
function D.settle(state,player,object,insideCamp)
    if not state.fresh then return false end
    state.fresh=nil -- first boot, never creation or furniture pickup
    if state.archive=="_factory" then return false end
    local okay,x,y,z=pcall(SC.ControlUtil.position,object)
    if not okay then x,y,z=nil,nil,nil end
    local P=SC.TerminalPersona
    local debugId,config=override(P.isDeepPost(x,y,z))
    if not debugId then
        if insideCamp==nil then insideCamp=atCamp(player,object) end
        if insideCamp~=false then return false end
    end
    local ledger=SC.TerminalLocks.ledger()
    if not ledger then return false end
    local book=ledger.persona
    local draft={boots=book.boots,lastAt=book.lastAt,met={},talked={},campReady={},campMentions={},spiffyGuest=book.spiffyGuest==true}
    for _,id in ipairs(P.ORDER) do
        draft.met[id]=book.met[id]
        draft.talked[id]=book.talked[id]
        draft.campReady[id]=book.campReady[id]
        draft.campMentions[id]=book.campMentions[id]
    end
    local days=read(SC.TerminalPayoff.daysSinceOutbreak) or 0
    local level=D.level()
    local enabled=SC.TerminalDrawers.enabled()
    -- Dates and Off are decided before inspecting any furniture. The supplied
    -- Director still counts this first boot even when no machine can appear.
    local eligible=debugId~=nil or days>=P.DIRECTOR.firstDay and level~=1
    local hasDrawer=enabled and eligible and read(SC.TerminalDrawers.find,object)~=nil
    local chosen
    if debugId then
        draft.boots=draft.boots+1
        if hasDrawer then chosen=debugId draft.met[chosen]=true draft.lastAt=draft.boots end
    else
        local kind=hasDrawer and read(SC.TerminalWorld.computerKind,object,state.brand) or nil
        chosen=P.choose(draft,kind,state.brand,state.seed,hasDrawer,level,P.isDeepPost(x,y,z),days)
    end
    if not chosen then ledger.persona=draft return false end
    local old={lock=state.lock,locked=state.locked,puzzle=state.puzzle,theme=state.theme}
    state.locked,state.puzzle,state.theme=true,nil,SC.TerminalPersonaData[chosen].theme
    state.lock={kind="persona",persona=P.new(chosen,state.seed),realItems=true,
        home=x and {x=x,y=y,z=z} or nil}
    SC.TerminalDrawers.claim(player,object,state)
    if not state.lock.drawer then
        -- The physical claim may fail (for example, the claim ledger is full).
        -- Do not spend a unique personality or replace the original computer.
        state.lock,state.locked,state.puzzle,state.theme=old.lock,old.locked,old.puzzle,old.theme
        book.boots=draft.boots
        return false
    end
    ledger.persona=draft
    if config then config.debugPersona=nil end
    return true
end
return D
