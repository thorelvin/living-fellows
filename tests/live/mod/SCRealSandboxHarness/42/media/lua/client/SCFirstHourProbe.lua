-- SPDX-License-Identifier: MIT
-- Disposable fresh-LF fixture on a real loaded map. Clears only the clone's LF
-- history, seeds ordinary zombies, then uses production spawning and checked UI.
local Probe = {}
local function call(o,m,...)
    local ok,v=pcall(function(...) return o[m](o,...) end,...)
    return ok and v or nil
end
local function find(root,predicate)
    if not root then return nil end
    if predicate(root) then return root end
    for _,child in pairs(root.children or {}) do
        local match=find(child,predicate);if match then return match end
    end
end
local function capture(H,label)
    getCore():setAutoZoom(0,false)
    for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
    local name=H.config.run_id.."-first-hour-"..label..".png"
    getCore():TakeFullScreenshot(name)
    print("SC_REAL_SANDBOX|FIRST_HOUR_SCREENSHOT|"..name)
end
function Probe.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local s=H.firstHour
    local function stop(id,why)
        capture(H,"blocked-"..id)
        result("FAIL",id,why);setPhase("first_hour_failed_capture",current)
    end
    if H.phase=="first_hour_failed_capture" then
        if current-H.phaseStartedAt>2000 then setPhase("finish",current) end
        return
    end
    if H.phase=="first_hour_prepare" then
        if current-H.phaseStartedAt<8000 then return end
        for _,r in ipairs(SC.Registry.records()) do
            if r.actor then
                local okay,why=SC.Actor.remove(r.actor)
                if not okay then return stop("fresh_actor_cleanup",tostring(why)) end
            end
        end
        SC.BaseLife.reset()
        local okay,why=SC.Persistence.reset()
        if not okay then return stop("fresh_persistence_reset",tostring(why)) end
        ModData.getOrCreate(SC.Identity.worldSaveKey).document=nil
        okay,why=SC.Persistence.restore(H.player)
        if not okay then return stop("fresh_empty_restore",tostring(why)) end
        SC.FirstMeeting.reset();SC.Spawn.reset();SC.Guidance.resetTips()
        SC.UserOptions.setShowTips(true)
        SandboxVars.LivingFellows.EncountersEnabled=true
        SandboxVars.LivingFellows.FirstMeetingEnabled=true
        SC.Config.refreshSandbox()
        s={started=current,zombies={}};H.firstHour=s
        -- Offer the west-side spot that reaches the house without climbing the
        -- camp's tall fences (a separate, known arrival limit). Production
        -- placement still validates it and falls back to its own sample.
        s.choose=SC.Encounter.chooseSpawnSquare
        local preferred=getCell():getGridSquare(11987,6757,0)
        SC.Encounter.chooseSpawnSquare=function() return preferred end
        s.square=SC.Spawn.chooseSquare(H.player,SC.State,true,true)
        SC.Encounter.chooseSpawnSquare=s.choose
        if not s.square then return stop("arrival_candidate","no loaded off-screen candidate") end
        print("SC_REAL_SANDBOX|FIRST_HOUR_CANDIDATE|"..s.square:getX()..","..s.square:getY())
        -- Hold the validated native candidate for repeatability; its production
        -- visibility/geometry checks and sliced safety preparation still run.
        SC.Encounter.chooseSpawnSquare=function() return s.square end
        for _,offset in ipairs({{-3,-3},{-3,3},{3,-3},{3,3},{0,5},{5,0}}) do
            local sq=getCell():getGridSquare(s.square:getX()+offset[1],s.square:getY()+offset[2],0)
            if sq and SC.GameplayUtil.isSquareFree(sq) then
                local list=addZombiesInOutfit(sq:getX(),sq:getY(),0,1,nil,0)
                if list and list:size()>0 then s.zombies[#s.zombies+1]=list:get(0) end
            end
        end
        check("fresh_lf_fixture",#SC.Registry.records()==0 and not SC.BaseLife.active(),
            "real map clone; original camp and actors removed only in clone")
        check("arrival_native_zombies",#s.zombies>=3,"seeded="..#s.zombies)
        SC.Guidance.pulse(H.player,current)
        check("first_step_meet",SC.Guidance.view() and SC.Guidance.view().id=="meet",SC.Guidance.summary())
        SC.UI.open("status")
        setPhase("first_hour_arrival",current)
    elseif H.phase=="first_hour_arrival" then
        if not s.cardCaptured and current-s.started>4000 then
            capture(H,"fresh-status");s.cardCaptured=true
        end
        local receipt=SC.FirstMeeting.export()
        local record=receipt.actorId and SC.Registry.byId(receipt.actorId)
        if record and record.actor then
            s.actor,s.id=record.actor,record.id
            SC.Encounter.chooseSpawnSquare=s.choose
            local removed=0
            for _,z in ipairs(s.zombies) do if not call(z,"getCurrentSquare") then removed=removed+1 end end
            check("arrival_cleared_native_zombies",removed>=3,"removed="..removed.." seeded="..#s.zombies)
            check("arrival_independent_vulnerable",not record.recruited and not record.factionId
                and call(s.actor,"isGodMod")~=true and call(s.actor,"isInvincible")~=true,
                "actor="..s.id.."; no immunity enabled")
            s.spawnAt=current;setPhase("first_hour_meet",current)
        elseif current-s.started>160000 then
            return stop("arrival_timeout","receipt="..tostring(receipt.phase).." attempts="..receipt.attempts)
        end
    elseif H.phase=="first_hour_meet" then
        local record=SC.Registry.byId(s.id)
        if not record or SC.GameplayUtil.isDead(s.actor) then return stop("visitor_unavailable",tostring(s.id)) end
        local distance=SC.GameplayUtil.distance(s.actor,H.player)
        local navigation=SC.Navigation.peek(s.actor)
        if navigation and navigation.lastBlocker and navigation.lastBlocker~=s.lastBlocker then
            s.lastBlocker=navigation.lastBlocker;s.blocks=(s.blocks or 0)+1
            capture(H,"approach-block-"..s.blocks.."-"..tostring(s.lastBlocker.type))
        end
        -- Simulate the observer looking toward the approaching visitor. This
        -- changes only the real player's facing, never sight or companion AI.
        if distance<=20 then H.player:faceLocationF(s.actor:getX(),s.actor:getY()) end
        if not s.nextTrace or current>=s.nextTrace then
            s.nextTrace=current+10000
            local rt=SC.Registry.byId(s.id).runtime or {}
            print("SC_REAL_SANDBOX|FIRST_HOUR_APPROACH|distance="..distance..";decision="..tostring(rt.lastDecision)
                ..";sight="..tostring(SC.GameplayUtil.canSee(H.player,s.actor))
                ..";los="..tostring(SC.GameplayUtil.canSee(H.player,s.actor:getCurrentSquare())))
        end
        local receipt=SC.FirstMeeting.export()
        if receipt.called and distance<=20 then
            capture(H,"survivor-arrival")
            check("arrival_callout_and_contact",receipt.called and SC.Guidance.view()
                and SC.Guidance.view().id=="invite","distance="..distance)
            -- Leave the visitor alone for a while: after the call-out they
            -- must stay within reach instead of going back to wandering.
            s.maxDistance=distance;SC.UI.instance:setCollapsed(true)
            setPhase("first_hour_wait",current)
        elseif current-s.spawnAt>240000 then return stop("approach_timeout","distance="..distance) end
    elseif H.phase=="first_hour_wait" then
        local record=SC.Registry.byId(s.id)
        if not record or SC.GameplayUtil.isDead(s.actor) then return stop("visitor_unavailable_waiting",tostring(s.id)) end
        local distance=SC.GameplayUtil.distance(s.actor,H.player)
        s.maxDistance=math.max(s.maxDistance,distance)
        local receipt=SC.FirstMeeting.export()
        if receipt.phase~="waiting" then return stop("visitor_stopped_waiting","phase="..tostring(receipt.phase)) end
        if distance>30 then return stop("visitor_wandered","distance="..distance) end
        if not s.waitTraced or current>=s.waitTraced then
            s.waitTraced=current+5000
            local rt=record.runtime or {}
            print("SC_REAL_SANDBOX|FIRST_HOUR_WAIT|distance="..string.format("%.1f",distance)
                ..";decision="..tostring(rt.lastDecision)..";reason="..tostring(rt.lastReason))
        end
        if not s.trackerCaptured and current-H.phaseStartedAt>=3000 then
            local line=SC.Guidance.tracker()
            check("launcher_line_current_step",line and line.id=="invite",line and line.id or "none")
            capture(H,"collapsed-tracker-invite");s.trackerCaptured=true
        end
        if current-H.phaseStartedAt>=30000 then
            check("visitor_waits_nearby",s.maxDistance<=30,"max_distance="..string.format("%.1f",s.maxDistance)
                ..";phase="..receipt.phase)
            SC.UI.open("talk",s.id);setPhase("first_hour_invite",current)
        end
    elseif H.phase=="first_hour_invite" then
        if current-H.phaseStartedAt<2000 then return end
        local b=find(SC.UI.instance,function(c) return c.scCommand=="recruit" end)
        if not b or b.enable==false then return stop("talk_invitation","Invite to join unavailable") end
        b.onclick(b.target,b)
        setPhase("first_hour_order",current)
    elseif H.phase=="first_hour_order" then
        if current-H.phaseStartedAt<2000 then return end
        local r=SC.Registry.byId(s.id)
        if not r or not r.recruited then return stop("invite_checked_command","recruit did not succeed") end
        s.recruitedAt=current
        SC.Guidance.pulse(H.player,current)
        check("first_step_explicit_order",SC.Guidance.view().id=="order","joining is not a player order")
        local okay,why=SC.Commands.issue(s.id,"stay",nil,H.player)
        if not okay then return stop("first_stay_order",tostring(why)) end
        local core=H.player:getCurrentSquare()
        okay,why=SC.BaseLife.create(core,"First steps camp")
        if not okay then return stop("first_camp_core",tostring(why)) end
        s.campAt=current
        SC.Guidance.pulse(H.player,current)
        check("first_step_storage",SC.Guidance.view().id=="storage",SC.Guidance.summary())
        -- A loaded, real container inside the new camp, selected from known
        -- fixture coordinates; guidance itself performs no discovery scans.
        for x=12022,12040 do for y=6738,6748 do
            local square=getCell():getGridSquare(x,y,0)
            local objects=square and square:getObjects()
            for i=0,(objects and objects:size() or 0)-1 do
                local object=objects:get(i)
                if not s.storage and call(object,"getContainer") then
                    local accepted=SC.BaseLife.registerStorage(object,"general")
                    if accepted then s.storage=object end
                end
            end
        end end
        if not s.storage then return stop("first_storage_mark","no native container accepted") end
        SC.Guidance.pulse(H.player,current)
        check("first_step_job",SC.Guidance.view().id=="job",SC.Guidance.summary())
        okay,why=SC.Commands.issue(s.id,"set_base_role",{role="generalist"},H.player)
        if not okay then return stop("first_base_job",tostring(why)) end
        SC.Guidance.pulse(H.player,current)
        check("first_six_steps",SC.Guidance.view().id=="computer",SC.Guidance.summary())
        SC.UI.open("status",s.id);setPhase("first_hour_capture",current)
    elseif H.phase=="first_hour_capture" then
        if current-H.phaseStartedAt<3000 then return end
        capture(H,"camp-status")
        local expand=find(SC.UI.instance,function(c) return c.scGuideAction=="expand" end)
        if expand then expand.onclick(expand.target,expand) end
        setPhase("first_hour_checklist",current)
    elseif H.phase=="first_hour_checklist" then
        if current-H.phaseStartedAt<2000 then return end
        capture(H,"expanded-checklist")
        SC.UI.instance:setCollapsed(true)
        setPhase("first_hour_tracker",current)
    elseif H.phase=="first_hour_tracker" then
        if current-H.phaseStartedAt<2000 then return end
        check("optional_step_quiet_launcher",SC.Guidance.tracker()==nil,"view="..tostring(SC.Guidance.view() and SC.Guidance.view().id))
        capture(H,"collapsed-tracker")
        result("PASS","first_hour_walkthrough","recruit_ms="..(s.recruitedAt-s.started)
            ..";camp_ms="..(s.campAt-s.started)..";walkthrough_ms="..(current-s.started)
            .."; natural native arrival, checked Invite/Stay/job, real camp and storage")
        setPhase("first_hour_complete",current)
    elseif H.phase=="first_hour_complete" and current-H.phaseStartedAt>2000 then
        setPhase("finish",current)
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFirstHourProbe=Probe
return Probe
