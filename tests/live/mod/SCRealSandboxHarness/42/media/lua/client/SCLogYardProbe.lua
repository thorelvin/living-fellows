-- SPDX-License-Identifier: MIT
-- Two real four-log piles in an isolated seed clone, using normal camp jobs.
local P={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCLogYardProbe=P
local function call(o,m,...)
    local okay,value=pcall(function(...) return o[m](o,...) end,...)
    if okay then return value end
end
local function photo(H,label)
    pcall(function()
        for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
        getCore():TakeFullScreenshot(H.config.run_id.."-log-yard-"..label..".png")
    end)
end
local function finish(H,current,setPhase)
    local f,SC=H.logYard,SurvivorCompanion
    if f and f.originalDecision then SC.Decision.update=f.originalDecision end
    setPhase("finish",current)
end
local function fail(H,current,check,setPhase,label,why)
    photo(H,"blocked-"..label); check(label,false,tostring(why)); finish(H,current,setPhase)
end
local function countRope(actor)
    local n=0
    for _,item in ipairs(SurvivorCompanion.GameplayUtil.inventoryItems(actor:getInventory(),1024)) do
        if item:getFullType()=="Base.Rope" then n=n+1 end
    end
    return n
end
local function unstack(H,f,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local work=f.unstack
    if not work.job then
        if current-work.startedAt<1000 then return end
        photo(H,"finished")
        local source=SC.LogYard.contents(f.a).bundles[1]
        work.source,work.world=source.item,source.world
        local queued,job=SC.BaseLife.enqueueJob({type="build",priority=3,
            target={x=f.a:getX(),y=f.a:getY(),z=0}})
        if not queued then return fail(H,current,check,setPhase,"unstack_parent_job",job) end
        local claimed,why=SC.BaseLife.claimJob(f.id,function(candidate) return candidate.id==job.id end)
        if not claimed then return fail(H,current,check,setPhase,"unstack_parent_lease",why) end
        work.job,work.ropesBefore=job,countRope(f.actor)
    end
    SC.BaseLife.touchJob(work.job.id,f.id,"active")
    local taken,reason,item,terminal=SC.LogYard.takeOne(f.actor,
        {zoneId=f.zone.id,x=f.a:getX(),y=f.a:getY(),z=0},work.job)
    if SC.NativeActions.workKind(f.actor)=="unstack_logs" and not work.actionPhoto then
        work.actionPhoto=true; photo(H,"untying")
    end
    if current-work.startedAt>90000 or terminal then
        return fail(H,current,check,setPhase,"unstack_native_blocked",reason)
    end
    if not taken or reason~="log_yard_log_taken" then return end
    local contents=SC.LogYard.contents(f.a)
    check("yard_native_unstack_action",work.actionPhoto==true,"stock UnstackFourLogs observed")
    check("yard_unstack_exact_selected_log",item and item:getFullType()=="Base.Log"
        and SC.GameplayUtil.inventoryContains(f.actor:getInventory(),item),"one native-created log carried")
    check("yard_unstack_native_source_consumed",SC.GameplayUtil.worldItemPresent(f.a,work.world)~=true,
        "the original bundle's world wrapper is gone")
    check("yard_unstack_remainders",#contents.logs==3 and #contents.bundles==0 and not contents.splitPending,
        "three actual native log outputs left in the same yard tile, claims released")
    check("yard_unstack_native_rope_return",countRope(f.actor)==work.ropesBefore+2,
        "stock OnCreate returned two Base.Rope; no scripted replacement items")
    check("yard_unstack_parent_receipt_cleared",not work.job.target.yardUnstack,"existing job may continue")
    SC.BaseLife.completeJob(work.job.id,f.id,"native_unstack_verified")
    result("PASS","log_yard_native_unstack_complete","one real four-log bundle became one carried log + three ground logs + two native ropes")
    f.finishPhoto="unstacked"; f.finishedAt=current
end
function P.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local U,Y=SC.GameplayUtil,SC.LogYard
    local f=H.logYard
    if f and f.finishedAt then
        -- Let native world-item rendering catch up with the final drop before
        -- taking the evidence image and closing the isolated client.
        if current-f.finishedAt>=1000 then photo(H,f.finishPhoto or "finished"); finish(H,current,setPhase) end
        return
    end
    if not f then
        local record
        for _,candidate in ipairs(SC.Registry.snapshot()) do
            if candidate.actor and candidate.recruited and not U.isDead(candidate.actor) then record=candidate; break end
        end
        if not record and current-H.phaseStartedAt<12000 then return end
        if not record then return fail(H,current,check,setPhase,"yard_worker","no recruited loaded worker") end
        f={actor=record.actor,id=record.id,startedAt=current,lastAt=0,lastTrace=0}; H.logYard=f
        SC.Downtime.cancel(f.actor,"log_yard_probe")
        SC.BaseWork.cancel(f.actor,"log_yard_probe")
        SC.Navigation.cancel(f.actor,"log_yard_probe")
        local source
        for _,category in ipairs({"crafting","tools","construction","general"}) do
            for _,storage in ipairs(SC.BaseLife.storageRows(category,true)) do
                local container=SC.BaseLife.resolveContainer(storage)
                if container then f.storage,f.container=storage,container; source=U.squareOf(container:getParent()); break end
            end
            if f.container then break end
        end
        local fixtureShelf=source==nil
        source=source or H.player:getCurrentSquare()
        local sx,sy=U.position(source)
        for radius=2,20 do
            for dx=-radius,radius do for _,dy in ipairs({-radius,radius}) do
                local a=U.gridSquare(math.floor(sx)+dx,math.floor(sy)+dy,0)
                local b=U.gridSquare(math.floor(sx)+dx+1,math.floor(sy)+dy,0)
                if a and b and U.isSquareFree(a) and U.isSquareFree(b)
                    and SC.BaseLife.isOutdoorSquare(a)==true and SC.BaseLife.isOutdoorSquare(b)==true
                    and (fixtureShelf or SC.BaseLife.withinWorkReach(a)) then
                    f.a,f.b=a,b; break
                end
            end if f.a then break end end
            if f.a then break end
        end
        if not f.a then return fail(H,current,check,setPhase,"yard_ground","no clear outdoor pair within work reach") end
        if fixtureShelf then
            SC.BaseLife.create(f.a,"Log yard acceptance")
            local base=SC.BaseLife.active(); base.zones={}; base.storages={}; base.jobs={}
            SC.BaseLife.beginZone("area",{x=f.a:getX()-5,y=f.a:getY()-5,z=0})
            assert(SC.BaseLife.finishZone({x=f.a:getX()+5,y=f.a:getY()+5,z=0},"Test camp"))
            local crateSquare
            for dx=-3,3 do for dy=-3,3 do
                local tile=U.gridSquare(f.a:getX()+dx,f.a:getY()+dy,0)
                if not crateSquare and math.abs(dx)+math.abs(dy)>=2 and tile and U.isSquareFree(tile)
                    and SC.BaseLife.isOutdoorSquare(tile)==true then crateSquare=tile end
            end end
            if not crateSquare then return fail(H,current,check,setPhase,"yard_shelf_fixture","no free crate tile") end
            local object=IsoThumpable.new(getCell(),crateSquare,"carpentry_01_16",false,{})
            object:setIsContainer(true); object:setContainer(ItemContainer.new("crate",crateSquare,object))
            object:getContainer():setCapacity(50); crateSquare:AddSpecialObject(object)
            local registered,row=SC.BaseLife.registerStorage(object,"crafting")
            if not registered then return fail(H,current,check,setPhase,"yard_shelf_fixture",row) end
            f.storage,f.container=row,object:getContainer()
            result("PASS","yard_native_shelf_fixture","clone-only real outdoor crate marked Crafting")
        end
        SC.BaseLife.beginZone("log_yard",f.a)
        local marked,zone=SC.BaseLife.finishZone(f.b,"Native log stack test")
        if not marked then return fail(H,current,check,setPhase,"yard_zone",zone) end
        f.zone=zone
        local base=SC.BaseLife.active()
        base.jobs={} -- clone-only isolation; no unrelated queued chore can claim this worker
        base.settings.workOutsideAtNight=true
        local stats=f.actor:getStats()
        stats:set(CharacterStat.FATIGUE,0.1); stats:set(CharacterStat.ENDURANCE,1)
        getGameTime():setTimeOfDay(12)
        f.ropes={}
        for i=1,4 do f.ropes[i]=f.container:AddItem("Base.Rope") end
        for _,sq in ipairs({f.a,f.b}) do for i=1,4 do sq:AddWorldInventoryItem("Base.Log",0.4,0.4,0) end end
        SC.BaseLife.assign(f.id,"quartermaster",true)
        SC.Commands.issue(f.id,"base_duty",nil,H.player)
        f.originalDecision=SC.Decision.update
        SC.Decision.update=function() return true,"log_yard_fixture_owned" end
        if not H.placeCombatActor(f.actor,{x=f.a:getX()+0.5,y=f.a:getY()+0.5,z=0}) then
            return fail(H,current,check,setPhase,"yard_actor_position","native placement failed")
        end
        -- Observe from nearby, with the two real native piles on screen.
        local observer
        for dx=-4,4 do for dy=-4,4 do
            local tile=U.gridSquare(f.a:getX()+dx,f.a:getY()+dy,0)
            if not observer and math.abs(dx)+math.abs(dy)>=4 and tile and U.isSquareFree(tile)
                and SC.BaseLife.isOutdoorSquare(tile)==true then observer=tile end
        end end
        local px,py=(observer or f.a):getX()+0.5,(observer or f.a):getY()+0.5
        H.player:teleportTo(px,py,0); H.player:setX(px); H.player:setY(py)
        H.player:setNextX(px); H.player:setNextY(py); H.player:setLastX(px); H.player:setLastY(py)
        H.player:setCurrentSquareFromPosition()
        if SC.UI.instance then SC.UI.instance:setVisible(false) end
        getPlayerInventory(0):setVisible(false); getPlayerLoot(0):setVisible(false)
        Y.bundleAt(f.actor,f.a); Y.bundleAt(f.actor,f.b)
        f.remainingBefore=#f.ropes
        check("yard_queued_jobs",#base.jobs==2,"two full tiles queued two ordinary Stack logs jobs")
        photo(H,"before")
        print("SC_LOG_YARD_TRACE|fixture|8 native Base.Log + 4 native Base.Rope; normal BaseWork, shelf withdrawals and handcraft; clone needs fixture only")
        setPhase("log_yard_work",current)
        return
    end
    if current-f.lastAt<100 then return end
    f.lastAt=current
    if f.unstack then return unstack(H,f,current,check,result,setPhase) end
    local okay,reason=SC.BaseWork.update(f.actor,H.player,{immediateCount=0,pressure=0})
    local completed=0
    for _,sq in ipairs({f.a,f.b}) do
        local contents=Y.contents(sq)
        if contents and #contents.bundles==1 and contents.bundles[1].count==4
            and #contents.logs==0 then completed=completed+1 end
    end
    local kind=SC.NativeActions.workKind(f.actor)
    if kind=="stack_logs" and not f.actionPhoto then f.actionPhoto=true; photo(H,"tying") end
    if current-f.lastTrace>2000 then
        f.lastTrace=current
        print("SC_LOG_YARD_TRACE|progress|elapsed="..(current-f.startedAt).." reason="..tostring(reason)
            .." native="..tostring(kind).." bundles="..completed)
    end
    local blocked
    for _,job in ipairs(SC.BaseLife.active().jobs) do if job.state=="blocked" then blocked=job.blocker end end
    if blocked then return fail(H,current,check,setPhase,"yard_blocked",blocked) end
    if current-f.startedAt>150000 then return fail(H,current,check,setPhase,"yard_deadline",reason) end
    if completed==2 then
        local ropesLeft=0
        for _,item in ipairs(f.ropes) do if item:getContainer() or item:getWorldItem() then ropesLeft=ropesLeft+1 end end
        check("yard_native_rope_consumption",ropesLeft==0,"four exact ropes consumed by the stock recipe")
        check("yard_native_handcraft",f.actionPhoto==true,"native stack_logs action observed before completion")
        for i,sq in ipairs({f.a,f.b}) do
            local bundle=Y.contents(sq).bundles[1].item
            local data=bundle:getModData()
            check("yard_native_metadata_"..i,type(data.ropeItems)=="table" and data.ropeItems[0]=="Base.Rope"
                and data.ropeItems[1]=="Base.Rope","stock OnCreate rope receipts retained; output="..tostring(bundle:getID()))
        end
        result("PASS","log_yard_live_complete","8 native logs and 4 exact ropes became two four-log bundles on adjacent yard tiles")
        f.unstack={startedAt=current}
    end
end
return P
