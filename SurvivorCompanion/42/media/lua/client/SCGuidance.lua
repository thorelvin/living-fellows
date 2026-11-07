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
local recruitHint,campSince,idleSince,nextSound = nil,nil,nil,0
local nudgeDue,driveAwayAt = {},nil
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
    {id="recruit_hint", title="Following you", text="New companions start on Follow. You can ask them to stay or retreat."},
    {id="storage_hint", title="A place for supplies", text="Mark a container inside your camp so companions know where supplies belong."},
    {id="nudge_jobs", title="Camp jobs", text="Residents can help with daily work. Select one, open More > Base, and choose their Base job."},
    {id="nudge_expeditions", title="Expeditions", text="Your camp has a crew now. Expeditions can send them scouting, looting, fishing or collecting wood."},
}
local byId = {}
for _, tip in ipairs(definitions) do byId[tip.id] = tip end
local steps = {"meet","invite","order","camp","storage","job","computer"}
-- A feature nudge keeps a dot on its tab until that tab is visited.
local nudgeTabs = {nudge_expeditions="expeditions",nudge_jobs="more"}
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
local function restoreTooltip(c)
    if c.menu then if c.control.toolTip then c.control.toolTip.description=c.description or "" end
    else c.control.tooltip=c.tooltip end
end
local function restoreTooltips() for _,c in ipairs(controls) do restoreTooltip(c) end end
local function write()
    if type(getFileWriter) ~= "function" then return false end
    local f
    local ok = pcall(function()
        f = assert(getFileWriter(FILE, true, false))
        f:write(HEADER .. "\n")
        for _, d in ipairs(definitions) do
            if seen[d.id] then f:write("seen:" .. d.id .. "\n") end
            if learned[d.id] then f:write("done:" .. d.id .. "\n") end
        end
        if dismissed then f:write("dismissed\n") end
    end)
    if f then local closed=pcall(function() f:close() end);ok=ok and closed end
    if ok then missing=false end
    return ok
end
function G.load()
    if loaded then return not missing end
    loaded = true
    if type(getFileReader) ~= "function" then return false end
    local f
    local ok, result = pcall(function()
        f = getFileReader(FILE, false)
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
        if good then seen,learned,dismissed = s,l,d end
        return good
    end)
    if f then local closed=pcall(function() f:close() end);ok=ok and closed end
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
    if different and done and lastSafe and now()>=nextSound and U().playUISound then
        nextSound=now()+600;U().playUISound("UISelectListItem")
    end
end
function G.resetTips()
    G.clearPointer()
    seen,learned,observations = {},{},{}
    -- The panel's tabs stay registered; their pointers may run again.
    for _,c in ipairs(controls) do c.expired,c.at=false,now() end
    loaded,missing,migrated,dismissed = true,false,false,false
    active,pointer,lastNudge,startupAt,startupUntil = nil,nil,-math.huge,nil,nil
    recruitHint,campSince,idleSince=nil,nil,nil;nudgeDue={};driveAwayAt=nil
    changed();write()
end
function G.dismiss() dismissed=true;active=nil;G.clearPointer();changed();write() end
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
        if event=="recruited" and enabled() and not seen.recruit_hint and facts.actor then
            recruitHint={actor=facts.actor,expires=now()+60000}
        end
        if event=="recruited" then mark("meet",true) end
        mark(id,true)
        if active and active.id==id then active=nil;G.clearPointer() end
    elseif event=="tab" then
        if facts.tab=="expeditions" then mark("expeditions",false);mark("nudge_expeditions",true)
        elseif facts.tab=="base" then mark("camp_jobs",false);mark("nudge_jobs",true)
        elseif facts.tab=="more" then mark("nudge_jobs",true) end
    elseif event=="panel" then mark("first_notice",true)
    elseif event=="computer_near" or event=="locked_closed" or event=="arrived_home" then
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
    local f={recruits=0,idle=0,storage=0,duty=0,carCrew=0,base=SC.BaseLife and SC.BaseLife.active()}
    local car=select(1,U().call(player,"getVehicle"))
    local driving=car and select(1,U().call(car,"getDriver"))==player
    for _,r in ipairs(records) do
        local a=r.actor
        if r.recruited and (not a or not U().isDead(a)) then
            f.recruits=f.recruits+1
            if a then
                if driving and select(1,U().call(a,"getVehicle"))==car then f.carCrew=f.carCrew+1 end
                f.speaker=f.speaker or (U().sameFloor(a,player) and U().distance(a,player)<=12 and a or nil)
                local rt=r.runtime or {}
                local downtime=SC.Downtime and SC.Downtime.peek and SC.Downtime.peek(a)
                local kind=downtime and downtime.active and downtime.active.kind
                if rt.lastDecision=="idle" or rt.lastDecision=="sit" or kind=="sit" or kind=="read"
                    or kind=="tv_watch" or kind=="radio_listen" then f.idle=f.idle+1 end
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
    f.inside=f.base and SC.BaseLife.isInside and SC.BaseLife.isInside(player)==true
    if driving and f.carCrew>0 and not f.inside then driveAwayAt=now()
    elseif driveAwayAt and f.inside and now()-driveAwayAt<30000 then
        G.report("arrived_home");driveAwayAt=nil
    elseif driveAwayAt and now()-driveAwayAt>=30000 then driveAwayAt=nil end
    return f
end
local function currentStep()
    for _,id in ipairs(steps) do if not learned[id] then return id end end
end
function G.pulse(player, current)
    G.load();current=current or now();lastPlayer=player
    if not enabled() then
        G.clearPointer()
        restoreTooltips()
        if active or pointer or lastSafe then active,pointer,lastSafe=nil,nil,false;changed() end
        return true
    end
    local records=SC.Registry and SC.Registry.records() or {}
    local f=facts(player,records)
    if not migrated then
        migrated=true
        if missing and (f.base or f.recruits>0 or SC.Persistence and SC.Persistence.hasWorldHistory and SC.Persistence.hasWorldHistory()) then
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
    if not safe then
        active=nil;G.clearPointer()
        restoreTooltips()
        return true
    end
    -- Panel controls follow what has been learned, not only the last hover.
    for _,c in ipairs(controls) do if not c.menu then c.control.tooltip=G.tip(c.id) or c.tooltip end end
    if not startupAt then
        startupAt=current
        if not seen.first_notice then startupUntil=current+12000;mark("first_notice",false) end
    end
    local bridge=SC.State and SC.State.active==false
    local step=not dismissed and currentStep() or nil
    local id=bridge and "bridge" or step
    -- A nudge's twelve seconds start when it is first on screen.
    if active and active.kind=="nudge" and (learned[active.id]
        or active.shownAt and current-active.shownAt>=12000) then
        active=nil;G.clearPointer();changed()
    end
    if id then
        if not active or active.id~=id and (active.kind~="nudge" or id~="computer") then
            active={id=id,kind="step",at=current};mark(id,false);changed()
        end
    elseif active and active.kind=="step" then active=nil;changed() end
    G.nudges(current,f,step)
    G.updatePointer(current)
    G.teach(player,current,f)
    return true
end
local function worldHours()
    local time=type(getGameTime)=="function" and getGameTime() or nil
    return tonumber((U().call(time,"getWorldAgeHours")))
end
local function speak(actor,id,current)
    if not actor or U().isDead(actor) or not lastPlayer or not U().sameFloor(actor,lastPlayer)
        or U().distance(actor,lastPlayer)>12 or not SC.Dialogue then return false end
    if SC.Dialogue.lastDisplayUntil and current<SC.Dialogue.lastDisplayUntil(actor)+300 then return false end
    local okay=SC.Dialogue.say(actor,"guidance."..id)
    if okay then mark(id,false) end
    return okay==true
end
function G.teach(player,current,f)
    if not enabled() or not lastSafe then return end
    if recruitHint then
        if current>recruitHint.expires then recruitHint=nil
        elseif speak(recruitHint.actor,"recruit_hint",current) then recruitHint=nil;return end
    end
    if not f then return end
    local h=worldHours()
    local inside=f.base and SC.BaseLife.isInside and SC.BaseLife.isInside(player)==true
    if inside and f.storage==0 then campSince=campSince or h else campSince=nil end
    if inside and f.storage>0 and f.duty==0 and f.idle>=2 then idleSince=idleSince or h else idleSince=nil end
    if current-lastNudge<900000 then return end
    local id,step
    local o=observations.computer_near
    if o and current-o.at>=5000 and not learned.computer and SC.Terminal
        and SC.Terminal.present(o.facts.object) and U().distance(player,U().squareOf(o.facts.object))<=5
        and not SC.Terminal.powered(o.facts.object) then id,step="dead_computer","computer" end
    o=observations.locked_closed
    if not id and o and SC.Terminal and SC.Terminal.present(o.facts.object)
        and SC.Terminal.powered(o.facts.object) and U().distance(player,U().squareOf(o.facts.object))<=5
        and o.facts.system and o.facts.system.locked and not SC.Terminal.window then id,step="locked_computer","computer" end
    if not id and h and campSince and h-campSince>=1 then id,step="storage_hint","storage" end
    if not id and h and idleSince and h-idleSince>=1 then id,step="camp_jobs","job" end
    o=observations.arrived_home
    if not id and o and current-o.at<60000 and not learned.send_home then id="send_home" end
    if not id or seen[id] then return end
    if active and active.kind=="step" and active.id~=step and active.id~="computer" then return end
    -- One at a time: a feature nudge still waiting for the screen goes first.
    if active and active.kind=="nudge" then return end
    if speak(f.speaker,id,current) then
        lastNudge=current
        local nudgeId=id=="camp_jobs" and "nudge_jobs" or id
        if id=="camp_jobs" then mark(nudgeId,false) end
        if not active or active.id=="computer" then
            -- Spoken aloud, so it already counts as shown.
            active={id=nudgeId,kind="nudge",at=current,shownAt=current};changed()
        end
    end
end
function G.offerShortVersion()
    G.load()
    if not enabled() or seen.short_version then return false end
    mark("short_version",false);return true
end
function G.nudges(current,f,step)
    if not lastSafe or step and step~="computer" then return end
    local h=worldHours()
    local eligible={nudge_jobs=f.storage>0 and f.idle>=2 and f.duty==0 and h and idleSince and h-idleSince>=1,
        nudge_expeditions=f.base~=nil and f.recruits>=2}
    for _,id in ipairs({"nudge_jobs","nudge_expeditions"}) do
        if not eligible[id] then nudgeDue[id]=nil
        elseif not seen[id] then
            nudgeDue[id]=nudgeDue[id] or current
            if current-nudgeDue[id]>=60000 and current-lastNudge>=900000
                and (not active or active.id=="computer") then
                -- Seen, spacing and the twelve seconds wait for G.shown.
                active={id=id,kind="nudge",at=current};changed();break
            end
        end
    end
end
-- Called by whichever surface actually draws the nudge's text.
function G.shown(id)
    if not active or active.id~=id or active.kind~="nudge" or active.shownAt then return end
    local current=now()
    active.shownAt,lastNudge=current,current
    mark(id,false)
end
function G.dot(tab)
    if not enabled() or not lastSafe then return false end
    for id,nudgeTab in pairs(nudgeTabs) do
        if nudgeTab==tab and not learned[id] and (seen[id] or active and active.id==id) then return true end
    end
    return false
end
function G.view()
    if not enabled() or not lastSafe or dismissed then return nil end
    local id=active and active.id or currentStep()
    if id then
        local message=text(id)
        if id=="meet" and SC.FirstMeeting and SC.FirstMeeting.pending() then
            message=U().text("UI_SC_Guide_MeetingPending","Someone is alive nearby. Listen for a voice.")
        end
        return {id=id,kind=active and active.id==id and active.kind or "step",title=text(id,"title"),text=message}
    end
    return {id="complete",title=U().text("UI_SC_Guide_Complete","That's the basics."),
        text=U().text("UI_SC_Guide_CompleteText","The Field Guide has the rest: thorelvin.github.io/living-fellows")}
end
function G.signature() return tostring(revision)..":"..tostring(G.expanded==true)..":"..tostring(G.tipsExpanded==true) end
function G.tip(id)
    if not enabled() or not lastSafe or learned[id] then return nil end
    return text(id)
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
    if pointer and pointer.menu and pointer.control.name==pointer.label
        and pointer.control.iconTexture==pointer.appliedIcon then
        pointer.control.iconTexture=pointer.originalIcon
    end
    pointer=nil
end
-- Pinned controls (the panel's own tabs) live as long as the panel and are
-- never pushed out by short-lived buttons and menu options.
function G.control(control,id,parent,menu,pinned)
    if not control or not byId[id] then return end
    for i=#controls,1,-1 do
        local c=controls[i]
        if c.control==control or pinned and c.pinned and c.id==id then table.remove(controls,i) end
    end
    if #controls>=24 then
        for i=1,#controls do
            if not controls[i].pinned then restoreTooltip(controls[i]);table.remove(controls,i);break end
        end
    end
    controls[#controls+1]={control=control,id=id,parent=parent,menu=menu,pinned=pinned==true,at=now(),
        tooltip=control.tooltip,description=control.toolTip and control.toolTip.description}
    local tip=G.tip(id)
    if tip and not menu then control.tooltip=tip end
end
function G.updatePointer(current)
    if not lastSafe then G.clearPointer();return end
    if pointer and (not active or current-pointer.at>=12000 or pointer.id~=active.id) then
        pointer.expired=true;G.clearPointer()
    end
    for index=#controls,1,-1 do
        local c=controls[index]
        local visible=c.parent and select(1,U().call(c.parent,"isVisible"))==true
        if visible then
            local parent=c.parent
            for _=1,6 do
                parent=parent.parent
                if not parent then break end
                if select(1,U().call(parent,"isVisible"))==false then visible=false;break end
            end
        end
        local hovering=visible and (c.menu and c.parent.options and c.parent.options[c.parent.mouseOver]==c.control
            or not c.menu and select(1,U().call(c.control,"isMouseOver"))==true)
        if hovering then
            local hint=G.tip(c.id)
            if hint then mark(c.id,false) end
            if c.menu and c.control.toolTip then c.control.toolTip.description=hint or c.description
            elseif not c.menu then c.control.tooltip=hint or c.tooltip end
        end
        if not visible then c.at=current;c.expired=false
        elseif active and (c.id==active.id or c.id=="job" and active.id=="bridge")
            and not c.expired and current-c.at>=2000 and not pointer then
            c.at=current;c.expired=true
            pointer={control=c.control,id=active.id,parent=c.parent,menu=c.menu,at=current,originalIcon=c.control.iconTexture,label=c.control.name}
            if c.menu and type(getTexture)=="function" then
                c.control.iconTexture=getTexture("media/ui/ArrowRight.png") or getTexture("media/ui/ArrowUp.png")
                pointer.appliedIcon=c.control.iconTexture
            end
            mark(c.id,false)
            break
        end
    end
end
function G.pointer() return enabled() and lastSafe and pointer or nil end
function G.dismissPointer()
    local id=pointer and pointer.id
    for _,c in ipairs(controls) do if c.id==id then c.expired=true end end
    G.clearPointer()
end
-- The line beside the collapsed launcher. Nudges show there even after the
-- checklist card was dismissed; the optional computer step does not linger.
function G.tracker()
    if not enabled() or not lastSafe then return nil end
    if active and active.kind=="nudge" then
        return {id=active.id,kind="nudge",title=text(active.id,"title"),text=text(active.id),tab=nudgeTabs[active.id]}
    end
    if dismissed then return nil end
    local id=active and active.kind=="step" and active.id or currentStep()
    if not id or id=="computer" then return nil end
    return {id=id,kind="step",title=text(id,"title")}
end
function G.notice()
    if enabled() and lastSafe and startupUntil and now()<startupUntil and not learned.first_notice then
        return U().text("UI_SC_Guide_OpenNotice","Press %1 for Living Fellows.",SC.UI and SC.UI.hotkeyName() or "Home")
    end
end
function G.reset()
    G.clearPointer();restoreTooltips();observations,controls={},{}
    active,lastPlayer,lastSafe,startupAt,startupUntil,migrated=nil,nil,false,nil,nil,false
    recruitHint,campSince,idleSince=nil,nil,nil;nudgeDue={};driveAwayAt=nil
    changed()
end
return G
