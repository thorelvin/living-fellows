-- SPDX-License-Identifier: MIT
require "SCNamespace"
require "SCGameplayUtil"

local SC = SurvivorCompanion
SC.Guidance = SC.Guidance or {}
local G = SC.Guidance
local FILE, HEADER = "LivingFellows-guidance.txt", "LF_GUIDANCE_1"
local seen, learned, observations, controls = {}, {}, {}, {}
local loaded, missing, migrated, dismissed = false, true, false, false
local revision, active, pointer, lastNudge = 0, nil, nil, -math.huge
local lastPlayer, lastSafe, startupAt, startupUntil = nil, false, nil, nil
local definitions = {
    {id="bridge", title="Bridge ready", text="Living Fellows isn't fully running. Open More > Support and copy the report."},
    {id="meet", title="Meet a survivor", text="Find another survivor. They turn up in houses and along roads."},
    {id="invite", title="Invite them", text="Right-click them, choose Talk to (their name), then Invite to join."},
    {id="order", title="Give an order", text="Right-click your companion: Follow, Stay or Retreat. Orders holds the rest."},
    {id="camp", title="Set a camp core", text="Right-click the ground where you want to live > Living Fellows > Set camp core here."},
    {id="storage", title="Mark storage", text="Right-click a container inside camp > Living Fellows > Mark storage as..."},
    {id="job", title="Give someone a job", text="Select a companion, open More > Base, and pick their Base job."},
    {id="computer", title="Use a computer (optional)", text="Right-click a powered computer > Use computer. EMMA keeps the camp's records."},
    {id="expeditions", title="Expeditions", text="Open Expeditions to send a crew scouting, looting, fishing or collecting wood. Choose their supplies and return time."},
    {id="send_home", title="Send home", text="Use Send home... to return an away crew to camp on foot or in a suitable car. Review the route before sending them."},
    {id="short_version", title="EMMA's short version", text="Ask EMMA about status, who is hurt, how much food, what is everyone doing, or advice. Camp records are available only at home."},
    {id="dead_computer", title="Power a computer", text="A desktop needs mains power or a working generator before Use computer is available."},
    {id="locked_computer", title="Locked computers", text="A locked desktop needs its password or a supported recovery method. Inspect the machine and nearby clues."},
    {id="camp_jobs", title="Camp jobs", text="With storage marked, give a resident a Base job in More > Base. Their role and supplies decide what they can do."},
    {id="first_notice", title="Open Living Fellows", text="Press Home for Living Fellows."},
}
local byId = {}
for _, tip in ipairs(definitions) do byId[tip.id] = tip end
local steps = {"meet","invite","order","camp","storage","job","computer"}
G.definitions, G.steps = definitions, steps
local function U() return SC.GameplayUtil end
local function now() return U().nowMs() end
local function changed() revision = revision + 1 end
local function text(id, field)
    local d = byId[id]
    return d and U().text("UI_SC_Guide_" .. id .. "_" .. (field or "text"), d[field or "text"]) or ""
end
G.text = text
local function enabled() return not SC.UserOptions or SC.UserOptions.get("showTips") ~= false end
G.enabled = enabled
local function write()
    if type(getFileWriter) ~= "function" then return false end
    local ok = pcall(function()
        local f = assert(getFileWriter(FILE, true, false))
        f:write(HEADER .. "\n")
        for _, d in ipairs(definitions) do
            if seen[d.id] then f:write("seen:" .. d.id .. "\n") end
            if learned[d.id] then f:write("done:" .. d.id .. "\n") end
        end
        if dismissed then f:write("dismissed\n") end
        f:close()
    end)
    return ok
end
function G.load()
    if loaded then return not missing end
    loaded = true
    if type(getFileReader) ~= "function" then return false end
    local ok, result = pcall(function()
        local f = getFileReader(FILE, false)
        if not f then return false end
        local good = f:readLine() == HEADER
        local s, l, d = {}, {}, false
        if good then for _=1,64 do
            local line = f:readLine()
            if line == nil then break end
            local kind,id = string.match(line,"^(%a+):([%w_]+)$")
            if id and byId[id] then
                if kind == "seen" then s[id]=true elseif kind == "done" then l[id]=true end
            elseif line == "dismissed" then d=true end
        end end
        f:close()
        if good then seen,learned,dismissed = s,l,d end
        return good
    end)
    missing = not (ok and result)
    return not missing
end
local function mark(id, done)
    G.load()
    if not byId[id] then return end
    local different = not seen[id] or done and not learned[id]
    seen[id] = true
    if done then learned[id] = true end
    if different then changed(); write() end
end
function G.resetTips()
    seen,learned,observations,controls = {},{},{},{}
    loaded,missing,migrated,dismissed = true,false,false,false
    active,pointer,lastNudge,startupAt,startupUntil = nil,nil,-math.huge,nil,nil
    changed();write()
end
function G.dismiss() dismissed=true;active,pointer=nil,nil;changed();write() end
function G.skip()
    G.dismiss()
    if SC.UserOptions and SC.UserOptions.setShowTips then SC.UserOptions.setShowTips(false) end
end
function G.reopen() dismissed=false;changed();write() end
function G.report(event, facts)
    facts = type(facts)=="table" and facts or {}
    local events = {met="meet", recruited="invite", ordered="order", camp="camp",
        storage="storage",job="job",computer="computer",expedition_used="expeditions",send_home_used="send_home"}
    local id=events[event]
    if id then
        if event=="recruited" then mark("meet",true) end
        mark(id,true)
        if active and active.id==id then active=nil;pointer=nil end
    elseif event=="tab" then
        if facts.tab=="expeditions" then mark("expeditions",false)
        elseif facts.tab=="base" then mark("camp_jobs",false) end
    elseif event=="panel" then mark("first_notice",true)
    else
        -- Producers publish facts; they never decide whether a lesson speaks.
        observations[event] = {at=now(),facts=facts}
    end
end
function G.inDanger(player, records)
    if not player or U().isDead(player) then return true end
    if select(1,U().call(player,"isAiming"))==true
        or select(1,U().call(player,"isAttackAnim"))==true
        or SC.ZombieAttack and SC.ZombieAttack.isGrabbed(player) then return true end
    local moodles=select(1,U().call(player,"getMoodles"))
    if MoodleType and MoodleType.Panic and (tonumber((U().call(moodles,"getMoodleLevel",MoodleType.Panic))) or 0)>0 then return true end
    for _, r in ipairs(records or {}) do
        if r.actor and U().sameFloor(player,r.actor) and U().distance(player,r.actor)<=24 then
            local rt=r.runtime or {}
            local s=type(rt.senses)=="table" and rt.senses.current or rt.snapshot
            if type(s)=="table" and ((tonumber(s.threatCount) or 0)>0
                or (tonumber(s.immediateCount) or 0)>0 or (tonumber(s.pressure) or 0)>0
                or type(s.player)=="table" and (tonumber(s.player.danger) or 0)>0) then return true end
        end
    end
    return false
end
local function facts(player, records)
    local f={recruits=0,idle=0,storage=0,duty=0,base=SC.BaseLife and SC.BaseLife.active()}
    for _,r in ipairs(records) do
        local a=r.actor
        if r.recruited and (not a or not U().isDead(a)) then
            f.recruits=f.recruits+1
            if a then
                f.speaker=f.speaker or (U().sameFloor(a,player) and U().distance(a,player)<=12 and a or nil)
                local rt=r.runtime or {}
                if rt.lastDecision=="idle" or rt.lastDecision=="sit" then f.idle=f.idle+1 end
            end
        elseif a and not r.factionId and not (SC.TaxiService and SC.TaxiService.isDriver(a))
            and U().sameFloor(a,player) and U().distance(a,player)<=20 and U().canSee(player,a)==true then
            f.met=true
        end
        local resident=SC.BaseLife and SC.BaseLife.resident(r.id)
        if resident and resident.duty and resident.role~="off" then f.duty=f.duty+1 end
    end
    if f.base then for _ in pairs(f.base.storage or f.base.storages or {}) do
        f.storage=f.storage+1;if f.storage>=256 then break end
    end end
    return f
end
local function currentStep()
    for _,id in ipairs(steps) do if not learned[id] then return id end end
end
function G.pulse(player, current)
    G.load();current=current or now();lastPlayer=player
    if not enabled() then
        if active or pointer or lastSafe then active,pointer,lastSafe=nil,nil,false;changed() end
        return true
    end
    local records=SC.Registry and SC.Registry.records() or {}
    local f=facts(player,records)
    if not migrated then
        migrated=true
        if missing and (f.base or f.recruits>0) then
            for _,id in ipairs(steps) do mark(id,true) end
            mark("first_notice",true)
            dismissed=true;write()
        end
    end
    if f.met or f.recruits>0 then mark("meet",true) end
    if f.recruits>0 then mark("invite",true) end
    if f.base then mark("camp",true) end
    if f.storage>0 then mark("storage",true) end
    if f.duty>0 then mark("job",true) end
    local safe=not G.inDanger(player,records)
    if safe~=lastSafe then lastSafe=safe;changed() end
    G.facts=f
    if not safe then active=nil;G.clearPointer();return true end
    if not startupAt then startupAt=current;startupUntil=current+12000 end
    if not seen.first_notice then mark("first_notice",false) end
    local bridge=SC.State and SC.State.active==false
    local step=not dismissed and currentStep() or nil
    local id=bridge and "bridge" or step
    if id then
        if not active or active.id~=id then active={id=id,kind="step",at=current};mark(id,false);changed() end
    elseif active and active.kind=="step" then active=nil;changed() end
    G.updatePointer(current)
    return true
end
function G.view()
    if not enabled() or not lastSafe or dismissed then return nil end
    local id=active and active.kind=="step" and active.id or currentStep()
    if id then
        local message=text(id)
        if id=="meet" and SC.FirstMeeting and SC.FirstMeeting.pending() then
            message=U().text("UI_SC_Guide_MeetingPending","Someone is alive nearby. Listen for a voice.")
        end
        return {id=id,title=text(id,"title"),text=message}
    end
    return {id="complete",title=U().text("UI_SC_Guide_Complete","That's the basics."),
        text=U().text("UI_SC_Guide_CompleteText","The Field Guide has the rest: thorelvin.github.io/living-fellows")}
end
function G.signature() return tostring(revision)..":"..tostring(G.expanded==true)..":"..tostring(G.tipsExpanded==true) end
function G.tip(id)
    if not enabled() or not lastSafe or learned[id] then return nil end
    mark(id,false);return text(id)
end
function G.list()
    G.load();local out={}
    for _,d in ipairs(definitions) do if seen[d.id] then
        out[#out+1]={id=d.id,title=text(d.id,"title"),text=text(d.id),done=learned[d.id]==true}
    end end
    return out
end
function G.summary()
    G.load();local done={}
    for _,id in ipairs(steps) do if learned[id] then done[#done+1]=id end end
    return "tips="..tostring(enabled()).."; steps="..table.concat(done,",").."; memory="..(missing and "new/unreadable" or "loaded")
end
function G.clearPointer()
    if pointer and pointer.menu then pointer.control.iconTexture=pointer.originalIcon end
    pointer=nil
end
function G.control(control,id,parent,menu)
    if not control or not byId[id] then return end
    for i=#controls,1,-1 do if controls[i].control==control then table.remove(controls,i) end end
    if #controls>=24 then table.remove(controls,1) end
    controls[#controls+1]={control=control,id=id,parent=parent,menu=menu,at=now()}
    local tip=G.tip(id)
    if tip and not menu then control.tooltip=tip end
end
function G.updatePointer(current)
    if not active or not lastSafe then G.clearPointer();return end
    if pointer and (current-pointer.at>=12000 or pointer.id~=active.id) then
        pointer.expired=true;G.clearPointer()
    end
    for _,c in ipairs(controls) do
        local visible=c.parent and select(1,U().call(c.parent,"isVisible"))==true
        if not visible then c.at=current;c.expired=false
        elseif c.id==active.id and not c.expired and current-c.at>=2000 and not pointer then
            c.at=current;c.expired=true
            pointer={control=c.control,id=c.id,parent=c.parent,menu=c.menu,at=current,originalIcon=c.control.iconTexture}
            if c.menu and type(getTexture)=="function" then
                c.control.iconTexture=getTexture("media/ui/ArrowRight.png") or getTexture("media/ui/ArrowUp.png")
            end
            break
        end
    end
end
function G.pointer() return enabled() and lastSafe and pointer or nil end
function G.tracker()
    local v=G.view()
    if v and v.id~="complete" then return v.title end
end
function G.notice()
    if enabled() and lastSafe and startupUntil and now()<startupUntil and not learned.first_notice then
        return U().text("UI_SC_Guide_OpenNotice","Press %1 for Living Fellows.",SC.UI and SC.UI.hotkeyName() or "Home")
    end
end
function G.reset()
    G.clearPointer();observations,controls={},{}
    active,lastPlayer,lastSafe,startupAt,startupUntil,migrated=nil,nil,false,nil,nil,false
    changed()
end
return G
