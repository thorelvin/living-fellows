-- SPDX-License-Identifier: MIT
-- Native UI and metadata acceptance in the disposable camp clone.
local run={step=0,next=0}
local function log(value)
    print("EXPEDITION_MAP|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/expedition-map.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not player or not player:getSquare() or not SC.ExpeditionTargets then return end
    if run.step==0 then
        player:setGodMod(true)
        player:setGhostMode(true)
        run.records={}
        for _,actor in ipairs(SC.Registry.living()) do
            local id=SC.Registry.idOf(actor)
            local summary=SC.Commands.describe(id,player)
            if summary.recruited and summary.available~=false and actor:getSquare() then
                run.records[#run.records+1]=SC.Registry.byId(id)
            end
        end
        if #run.records==0 then
            run.deadline=run.deadline or now+60000
            assert(now<run.deadline,"no loaded expedition crew")
            run.next=now+1000
            return
        end
        local record
        for _,candidate in ipairs(run.records) do
            if SC.GameplayUtil.nameOf(candidate.actor):find("Tess",1,true) then record=candidate break end
        end
        if not record then
            run.preferredDeadline=run.preferredDeadline or now+15000
            if now<run.preferredDeadline then run.next=now+500 return end
            record=run.records[1]
        end
        run.leader=record
        log("FIXTURE leader="..SC.GameplayUtil.nameOf(record.actor)
            .." fatigue="..tostring(SC.GameplayUtil.characterStatValue(record.actor,"FATIGUE",-1))
            .." endurance="..tostring(SC.GameplayUtil.characterStatValue(record.actor,"ENDURANCE",-1))
            .." load="..tostring(record.actor:getInventory():getCapacityWeight()))
        assert(SC.Commands.issue(record.id,"follow",nil,player))
        assert(SC.Commands.issue(record.id,"set_group",{group="charlie"},player))
        local x,y=record.actor:getX(),record.actor:getY()
        local places,reason=SC.ExpeditionPlaces.nearby(math.floor(x),math.floor(y),200,32)
        assert(places,"building lookup: "..tostring(reason))
        for _,place in ipairs(places) do
            if place.distance>25 and place.distance<180 then run.place=place break end
        end
        assert(run.place,"no local building for picker")
        local point={x=run.place.anchor.x,y=run.place.anchor.y,z=0}
        WorldMapVisited.getInstance():setKnownInSquares(point.x-2,point.y-2,point.x+2,point.y+2)
        assert(SC.ExpeditionTargets.known(point),"native known map flag not readable")
        run.target=assert(SC.ExpeditionTargets.resolveAtPoint("scout",point,
            SC.ExpeditionTargets.context(record.actor,"straight")))
        log("PASS native saved map knowledge and direct building lookup "..run.target.label)
        local root=SC.UI.open("expeditions",record.id)
        run.root,run.detail=root,root.detail
        local draft=root.detail.expeditionDraft
        draft.leaderId,draft.kind,draft.travelMode=record.id,"scout","straight"
        draft.hours,draft.style=24,"close_defense"
        draft.group=SC.Commands.describe(record.id,player).group or "alpha"
        SC.UIExpeditions.applyMapTarget(root.detail,run.target,false)
        SC.UIExpeditions.onButton(root.detail,{scExpeditionAction="choose_map"})
        assert(SC.ExpeditionMap.session,"picker did not open")
        run.step,run.next=1,now+4000
    elseif run.step==1 then
        local map=assert(ISWorldMap_instance)
        local a=run.target.anchor
        local x,y=map.mapAPI:worldToUIX(a.x,a.y),map.mapAPI:worldToUIY(a.x,a.y)
        assert(ISWorldMap.onRightMouseUp(map,x,y),"map context not consumed")
        local context=getPlayerContextMenu(0)
        run.option=nil
        for _,option in ipairs(context.options) do
            if option.name and option.name:find("Select ",1,true)==1 then run.option=option end
        end
        assert(run.option,"real map context has no expedition selection action")
        assert(SC.ExpeditionMap.session.highlight,"selected footprint was not highlighted")
        context:hideAndChildren()
        getCore():TakeFullScreenshot("expedition-map-picker")
        run.step,run.next=2,now+1500
    elseif run.step==2 then
        run.option.onSelect()
        assert(SC.ExpeditionMap.session==nil and run.root:isVisible(),"picker did not restore planner")
        assert(run.detail.expeditionDraft.mapTarget.id==run.target.id,"target lost on return")
        assert(getNumActivePlayers()==1 and getSpecificPlayer(0)==player,"map changed player ownership")
        log("PASS native context selection, cancel lifecycle and primary ownership")
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        local target=run.detail.expeditionDraft.mapTarget
        local records={run.leader}
        local before=target.id
        local preview,reason=SC.ExpeditionPrototype.previewMapTarget(records,target,{travelMode="straight"})
        assert(preview,"manual target preview: "..tostring(reason))
        assert(target.id==before and SC.ExpeditionPrototype.current()==nil,"review moved or launched crew")
        assert(run.detail.expeditionDraft.review,"selection did not return to mission review")
        getCore():TakeFullScreenshot("expedition-map-review")
        log("PASS native route review remains read-only distance="..tostring(preview.distance))
        run.step,run.next=4,now+1500
    elseif run.step==4 then
        run.launch=true
        run.deadline=now+240000
        run.step,run.next=5,now+1000
    elseif run.step==5 then
        local trip=SC.ExpeditionPrototype.current()
        if trip then
            if trip.scout.observation then run.observed=true end
            assert(now<run.deadline,"native selected scout trip did not return")
            if now>(run.lastReport or 0)+10000 then
                log("TRIP "..trip.scout.phase.." at="..trip.leader.actor:getX()..","..trip.leader.actor:getY())
                run.lastReport=now
            end
            return
        end
        assert(run.launched,"launch never ran on the simulation thread")
        local debrief=SC.ExpeditionPrototype.lastDebrief()
        log("RESULT "..tostring(debrief and debrief.endReason).." observed="..tostring(debrief and debrief.observation~=nil))
        assert(run.observed or debrief and debrief.observation,"scout returned without observing the selected site")
        assert(getSpecificPlayer(0)==player and getSpecificPlayer(1)==nil,"trip did not restore primary ownership")
        assert(not run.leader.actor:isDead(),"selected scout died")
        log("PASS native selected scouting trip returned alive to solo view")
        run.step,run.next=6,now+10000
    elseif run.step==6 then
        assert(getSpecificPlayer(0)==player and getSpecificPlayer(1)==nil,"solo view did not remain stable")
        log("PASS native expedition map acceptance complete")
        run.step=99
    end
end
local function guarded()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) Events.OnPostUIDraw.Remove(guarded) end
end
Events.OnPostUIDraw.Add(guarded)
Events.OnTick.Add(function()
    if run.launch then
        run.launch=nil
        local SC=SurvivorCompanion
        local okay,reason=pcall(function()
            SC.UIExpeditions.onButton(run.detail,{scExpeditionAction="launch"})
            local trip=assert(SC.ExpeditionPrototype.current(),"reviewed launch was rejected")
            assert(trip.scout.mapTarget and SC.ExpeditionPrototype.export().schema==8,"launch lost manual target")
            run.launched=true
            log("PASS native UI dispatch preserves schema 8 target")
        end)
        if not okay then log("FAIL "..tostring(reason)) end
    end
end)
