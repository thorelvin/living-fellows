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
        local before=SC.ExpeditionTargets.fingerprint(run.detail.expeditionDraft.mapTarget)
        SC.UIExpeditions.onButton(run.detail,{scExpeditionAction="choose_map"})
        assert(SC.ExpeditionMap.session,"cancel check did not reopen picker")
        ISWorldMap_instance:close()
        assert(run.root:isVisible() and SC.ExpeditionMap.session==nil
            and SC.ExpeditionTargets.fingerprint(run.detail.expeditionDraft.mapTarget)==before,
            "cancel changed the destination or lost the planner")
        log("PASS native context selection, cancellation and primary ownership")
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
        local actor=run.leader.actor
        local forest,why=SC.ExpeditionForests.preview(actor,"straight",{radius=1000,cacheKey="map-native-acceptance"})
        if not forest and why=="forest_scan_pending" then run.next=now+200 return end
        assert(forest,"native woodland discovery: "..tostring(why))
        local wood
        for _,site in ipairs(forest.candidates) do
            local a=site.anchor
            WorldMapVisited.getInstance():setKnownInSquares(a.x-34,a.y-34,a.x+34,a.y+34)
            wood=SC.ExpeditionTargets.resolveAtPoint("wood",a,SC.ExpeditionTargets.context(actor,"road"))
            if wood then break end
        end
        assert(wood and #wood.sites<=3,"native chosen woodland did not resolve")
        log("PASS native chosen woodland resolves bounded alternatives distance="..wood.distance)
        run.step,run.next=5,now+500
    elseif run.step==5 then
        local actor=run.leader.actor
        local banks,why=SC.Fishing.bankCandidates(actor,1000,32,0,false)
        assert(banks and #banks>0,"native mapped shores: "..tostring(why))
        local fish
        for _,bank in ipairs(banks) do
            local a=bank.anchor
            WorldMapVisited.getInstance():setKnownInSquares(a.x-34,a.y-34,a.x+34,a.y+34)
            fish=SC.ExpeditionTargets.resolveAtPoint("fish",a,SC.ExpeditionTargets.context(actor,"road"))
            if fish then break end
        end
        assert(fish,"native chosen bank did not resolve")
        log("PASS native fishing bank resolves using retained full-map data distance="..fish.distance)
        run.step,run.next=6,now+500
    elseif run.step==6 then
        local actor=run.leader.actor
        for _,sample in ipairs({{1000,"road"},{5000,"drive"}}) do
            local limit,mode=sample[1],sample[2]
            local target
            local started=getTimestampMs()
            for _,inset in ipairs({100,250,400}) do
                for direction=0,31 do
                    local angle=direction*math.pi*2/32
                    local x=math.floor(actor:getX()+math.cos(angle)*(limit-inset))
                    local y=math.floor(actor:getY()+math.sin(angle)*(limit-inset))
                    local places=SC.ExpeditionPlaces.nearby(x,y,128,32)
                    for _,place in ipairs(places or {}) do
                        local gap=SC.ExpeditionTargets.distance(place.anchor,SC.ExpeditionTargets.context(actor,mode))
                        if gap<=limit and gap>=limit*0.85 then
                            local a=place.anchor
                            WorldMapVisited.getInstance():setKnownInSquares(a.x-2,a.y-2,a.x+2,a.y+2)
                            target=SC.ExpeditionTargets.resolveAtPoint("search",a,SC.ExpeditionTargets.context(actor,mode))
                            if target then break end
                        end
                    end
                    if target then break end
                end
                if target then break end
            end
            assert(target,"no native distant building for "..mode)
            local approach=SC.ExpeditionPlaces.plannedApproach(target.place,actor)
            local route,reason=SC.ExpeditionRoute.plan(actor,approach or target.anchor)
            log("PASS native distant map target mode="..mode.." distance="..target.distance
                .." route="..tostring(route and route.roadLength or reason).." lookupAndRouteMs="..(getTimestampMs()-started))
        end
        assert(getSpecificPlayer(1)==nil and SC.ExpeditionPrototype.current()==nil,"metadata checks changed actor/view ownership")
        SC.UI.close()
        player:teleportTo(12036.5,6739.5,0)
        run.step,run.next=7,now+5000
    elseif run.step==7 then
        local square=assert(getCell():getGridSquare(12035,6739,0),"camp computer tile not loaded")
        for index=0,square:getObjects():size()-1 do
            local object=square:getObjects():get(index)
            if SC.Terminal.isComputer(object) then run.pc=object end
        end
        assert(run.pc,"original desktop not loaded")
        local _,access=SC.GameplayUtil.directInteractionAccess(player,run.pc)
        local tile=assert(access[1],"computer has no native access tile")
        player:teleportTo(tile:getX()+0.5,tile:getY()+0.5,tile:getZ())
        local inv=player:getInventory()
        inv:AddItem("Base.Screwdriver") inv:AddItem("Base.ElectricWire")
        inv:AddItem("Base.ElectronicsScrap") inv:AddItem("Base.ElectronicsScrap")
        for _=1,10 do
            if player:getPerkLevel(Perks.Electricity)<2 then player:LevelPerk(Perks.Electricity) end
        end
        local radio=inv:AddItem("Base.WalkieTalkie5")
        radio:getDeviceData():setChannel(88100)
        local state=SC.TerminalHardware.state(run.pc,false)
        if not state or not state.radio then
            local installed,why=SC.TerminalHardware.install(player,run.pc,"radio",radio)
            assert(installed,"station radio installation failed: "..tostring(why))
        end
        assert(SC.Terminal.use(player,run.pc),"computer use failed")
        run.step,run.next,run.deadline=8,now+500,now+30000
    elseif run.step==8 then
        local window=SC.Terminal.window
        if not window then
            assert(now<run.deadline,"terminal never opened") run.next=now+500 return
        end
        window:flush()
        if window.system.locked then
            SC.TerminalSystem.ensurePuzzle(window.system,4)
            window.entry.javaObject:SetText(window.system.puzzle.answer)
            window.entry.javaObject:onKeyEnter() window:flush()
        end
        run.window=window
        window.stationDraft={kind="scout",travelMode="road",quantity=4,category="food",hours=24,
            crew={run.leader.id},mapTarget=SC.ExpeditionTargets.copy(run.target),placeId=run.target.id}
        assert(SC.TerminalServices.input(window,"",{serviceAction="map_pick"}),"station did not consume picker action")
        assert(SC.ExpeditionMap.session and not window:isVisible(),"station did not suspend its existing window")
        run.step,run.next=9,now+1000
    elseif run.step==9 then
        local window=run.window
        ISWorldMap_instance:close()
        assert(window:isVisible() and SC.Terminal.window==window and not window.closed,
            "cancelling did not restore the station session")
        assert(window.stationDraft.mapTarget.id==run.target.id,"station cancel lost the destination")
        SC.TerminalServices.input(window,"",{serviceAction="map_pick"})
        local map=assert(ISWorldMap_instance)
        local at=run.target.anchor
        map:onRightMouseUp(map.mapAPI:worldToUIX(at.x,at.y),map.mapAPI:worldToUIY(at.x,at.y))
        local context=getPlayerContextMenu(0)
        local select
        for _,option in ipairs(context.options) do
            if option.name and option.name:find("Select ",1,true)==1 then select=option break end
        end
        assert(select,"station map context has no selection")
        context:hideAndChildren() select.onSelect()
        assert(SC.Terminal.window==window and window:isVisible() and not window.closed,
            "selecting did not restore the same station session")
        assert(window.stationDraft.mapTarget.id==run.target.id and window.menuPage=="station_review"
            and window.stationReviewed.mapFingerprint==SC.ExpeditionTargets.fingerprint(run.target),
            "station selection did not bind its reviewed target")
        window:flush()
        log("PASS native EMMA cancellation and selection restore the original session and reviewed destination")
        run.step,run.next=10,now+1000
    elseif run.step==10 then
        getCore():TakeFullScreenshot("expedition-map-station-review")
        assert(getSpecificPlayer(1)==nil and SC.ExpeditionPrototype.current()==nil,"station picker launched a trip")
        log("PASS native expedition map acceptance complete")
        run.step=99
    end
end
local function guarded()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) Events.OnPostUIDraw.Remove(guarded) end
end
Events.OnPostUIDraw.Add(guarded)
