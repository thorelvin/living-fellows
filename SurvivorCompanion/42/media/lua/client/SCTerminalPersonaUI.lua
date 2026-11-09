-- SPDX-License-Identifier: MIT
-- Native UI and world effects for the supplied, pure conversation engine.
-- Nothing here runs after the terminal closes. Discovery is a separate module.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local UI={} SC.TerminalPersonaUI=UI
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local okay,value=pcall(fn,...) if okay then return value end
end
local function call(object,method,...)
    if not object then return nil end
    return read(function(...) return object[method](object,...) end,...)
end
local function now() return SC.GameplayUtil.nowMs() end
function UI.active(w)
    local s=w and w.system
    return s and s.locked and s.lock and s.lock.kind=="persona" and s.lock.persona~=nil
end
function UI.layout(w)
    -- Alpha alone leaves UITextBox2's private caret visible on 42.21.
    -- The native child stays focused/editable off-screen; paint only our prompt.
    w.entry:setX(-10000) w.entry:setY(-10000)
    w.closeButton:setVisible(false)
end
function UI.boot(w)
    w.personaSession=SC.TerminalPersona.session()
    w.personaInputAt,w.personaFinishedAt=now(),now()
    w.startupReady,w.state,w.lockPage=true,"idle",nil
    w.entry.backgroundColor.a=0 w.entry.borderColor.a=0
    call(w.entry,"setTextRGBA",0,0,0,0)
    call(w.entry,"setPlaceholderText","")
    call(w.entry,"setMaxTextLength",SC.TerminalPersona.MAX_INPUT)
    UI.layout(w) w:setFocusMode("chat")
    if SC.EmmaTerminal then SC.EmmaTerminal.boot(w) end
end
local moodles={tired="TIRED",panic="PANIC",hungry="HUNGRY",pain="PAIN",drunk="DRUNK",unhappy="UNHAPPY",wet="WET",bored="BORED"}
function UI.facts(w,at,includeWorld)
    local lock=w.system.lock local f={moodles={}}
    f.hours=read(SC.ControlUtil.hours)
    f.days=read(SC.TerminalPayoff.daysSinceOutbreak)
    local clock=read(getGameTime)
    f.hour=call(clock,"getHour") f.minute=call(clock,"getMinutes")
    if f.hour and f.minute then
        f.time=string.format("%d:%02d %s",(f.hour+11)%12+1,f.minute,f.hour>=12 and "PM" or "AM")
    end
    local x,y,z
    -- read() intentionally returns one value; positions need their own guarded tuple.
    local okay,px,py,pz=pcall(SC.ControlUtil.position,w.object)
    if okay and px and py and pz then
        x,y,z=px,py,pz f.level=z f.deep=SC.TerminalPersona.isDeepPost(x,y,z)
        if lock.home then f.moved=x~=lock.home.x or y~=lock.home.y or z~=lock.home.z end
    end
    f.atCamp=w.campReportAvailable
    f.sitting=call(w.player,"isSittingOnFurniture")
    f.pause=math.max(0,(at-(w.personaFinishedAt or at))/1000)
    local drawer=lock.drawer
    f.drawer=drawer and (drawer.forced and "forced" or drawer.open and "open" or "closed") or "none"
    for key,name in pairs(moodles) do f.moodles[key]=read(SC.GameplayUtil.moodleLevel,w.player,name) end
    local threat=w.personaThreat
    if type(threat)=="table" then
        f.threat={distance=threat.closingDistance or threat.distance,closing=threat.closingDistance~=nil}
    end
    -- Counts and historical facts are only needed for submitted questions.
    -- The 500ms threat watch never rescans the camp or the zombie population.
    if includeWorld then
        local crew=read(SC.TerminalLockCrew.candidates,w)
        if type(crew)=="table" then
            f.companions=#crew
            if #crew>0 then f.companion=read(SC.TerminalLockCrew.name,crew[w.system.seed%#crew+1]) end
        end
        local fallen=SC.Community and read(SC.Community.recentDeaths,64)
        if type(fallen)=="table" and #fallen>0 then
            local record=fallen[w.system.seed%#fallen+1]
            local name=record and record.subjectDisplayName
            if type(name)=="string" and name~="" then f.fallen=name:gsub("[^ -~]",""):sub(1,16) end
        end
        local zs=read(w.world and w.world.zombies)
        if type(zs)=="table" then f.zombies=zs.count end
    end
    return f
end
local function effectStats(w,kind,amount,remove)
    local stats=call(w.player,"getStats")
    local stat=CharacterStat and CharacterStat[kind]
    if stats and stat then return call(stats,remove and "remove" or "add",stat,amount) end
end
function UI.noise(object)
    local okay,x,y,z=pcall(SC.ControlUtil.position,object)
    if not okay or not x then return nil end
    local emitter=call(read(getWorld),"getFreeEmitter",x+.5,y+.5,z)
    local handle=call(emitter,"playSound","LFSpiffyJingle")
    read(addSound,nil,x,y,z,40,40)
    return handle,emitter
end
function UI.effects(w,effects,f)
    local lock=w.system.lock local p=lock.persona
    lock.effects=lock.effects or {} local saved=lock.effects
    local confirm
    if effects.drawer then
        local okay,opened=pcall(SC.TerminalDrawers.open,w.player,w.object,w.system,false,true)
        confirm=SC.TerminalPersona.confirmDrawer(p,okay and opened==true)
    end
    local hours=f.hours local day=hours and math.floor(hours/24)
    if effects.noise and hours and (not saved.noiseAt or hours>=saved.noiseAt+1) then
        saved.noiseAt=hours -- commit before native calls: errors cannot duplicate noise
        UI.noise(w.object)
    end
    if effects.relief and day and saved.reliefDay~=day then
        saved.reliefDay=day effectStats(w,"STRESS",.25,true) effectStats(w,"UNHAPPINESS",20,true)
    end
    if effects.cheer and day and saved.cheerDay~=day then
        saved.cheerDay=day effectStats(w,"BOREDOM",25,true)
    end
    if effects.weight and (saved.weight or 0)<2 then
        saved.weight=(saved.weight or 0)+1 effectStats(w,"STRESS",.05,false)
    end
    if effects.shutdown then w.personaEnding="shutdown"
    elseif effects.close then w.personaEnding="close" end
    return confirm
end
function UI.reply(w,reply,f)
    w.privateEmmaReply=reply.private==true
    local failed=UI.effects(w,reply.effects or {},f)
    if failed then reply.rows=failed.rows end
    w.replyAutoScroll=true
    w.replyAnchor=w.pendingPrompt and {source=w.pendingPrompt,part=1} or nil
    w.pendingPrompt=nil
    for _,row in ipairs(reply.rows or {}) do
        w:enqueue({row.text},"emma",(reply.speed or 95)*(row.slow and .25 or 1))
    end
    w:enqueue({""},"emma",reply.speed or 95)
    if reply.support then w:enqueue(reply.support,"support",reply.speed or 95) end
    if reply.private and SC.EmmaTerminal then SC.EmmaTerminal.remember(w.player,reply,w.gameHours) end
    if reply.command then w.pendingCommand=reply.command end
    local wait=reply.thinkMs or 0
    w.state=wait>0 and "thinking" or "typing"
    w.thinkStart,w.thinkEnd=now(),now()+wait
end
function UI.input(w,raw)
    local at=now() local f=UI.facts(w,at,true)
    w.personaInputAt=at
    UI.reply(w,SC.TerminalPersona.respond(w.system.lock.persona,w.personaSession,raw,f),f)
    return true
end
function UI.finished(w)
    w.personaFinishedAt=now()
    if w.privateEmmaReply or SC.EmmaCare and SC.EmmaCare.quiet(w.personaSession) then w.personaEnding=nil; return end
    if SC.TerminalPersonaDiscovery then SC.TerminalPersonaDiscovery.noteConversation(w) end
    local p=w.system.lock and w.system.lock.persona
    if p and p.met and SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"persona_"..p.id,35) end
    local ending=w.personaEnding w.personaEnding=nil
    if ending=="close" then w.closeAt=now()+900 end
    if ending~="shutdown" then return end
    if not w:hasCurrentAccess() or not SC.Terminal.powered(w.object) then return end
    local s=w.system local lock=s.lock
    if lock.drawer and not lock.drawer.open and not lock.drawer.forced then SC.TerminalDrawers.release(w.object) end
    s.locked,s.lock=false,nil
    local okay,message=SC.Terminal.factoryReset(w)
    if not okay then
        s.locked,s.lock=true,lock w:print(message,"alert") return
    end
    w:close() SC.Terminal.open(w.player,w.object)
end
function UI.watch(w,at)
    if SC.EmmaCare and SC.EmmaCare.quiet(w.personaSession) then return end
    w.personaSensor=w.personaSensor or {}
    w.personaThreat=read(SC.TerminalWorld.nearestThreat,w.player,w.personaSensor,at)
    if w.state~="idle" then return end
    local f=UI.facts(w,at,false)
    local p=w.system.lock.persona local session=w.personaSession
    local reply=SC.TerminalPersona.threat(p,session,f,at)
        or SC.TerminalPersona.idle(p,session,(at-w.personaInputAt)/1000,f)
    if reply then UI.reply(w,reply,f) end
end
function UI.powerCut(w,at)
    w.queue,w.typing,w.personaEnding={},nil,nil
    if SC.EmmaCare and SC.EmmaCare.quiet(w.personaSession) then
        w:print("Power lost. The computer is shutting down.","system")
        w.state,w.closeAt="closing",at+1500;return
    end
    local reply=SC.TerminalPersona.powerCut(w.system.lock.persona)
    for _,row in ipairs(reply.rows) do w:print(row.text,"emma") end
    w.readingAnchor,w.scroll=nil,0 w.state,w.closeAt="closing",at+1500
end
function UI.entryText(w)
    return call(w.entry and w.entry.javaObject,"getInternalText") or call(w.entry,"getText") or ""
end
function UI.prompt(w,at)
    local value=UI.entryText(w)
    return value..(math.floor(at/500)%2==0 and "_" or " ")
end
function UI.draw(w,at)
    UI.layout(w) w.securityHits={}
    local frame=w:readingRange(w:readingFrame(at))
    local top,bottom=w:viewTop(),w:viewBottom()
    w:setStencilRect(w.layout.left-2,top,w.layout.right-w.layout.left+4,bottom-top+2)
    local okay,reason=pcall(function()
        local y=top
        for index=frame.first,frame.last do
            local row=frame.rows[index] or frame.extra[index-#frame.rows]
            if row and y+w.rowHeight<=bottom+2 then w:drawRow(row.text,y,row.kind) end
            y=y+w.rowHeight
        end
    end)
    w:clearStencilRect()
    if not okay then error(reason) end
end
return UI
