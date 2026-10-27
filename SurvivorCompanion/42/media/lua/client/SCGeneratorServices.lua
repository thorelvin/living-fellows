-- SPDX-License-Identifier: MIT
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
SC.GeneratorServices=SC.GeneratorServices or {}
local G=SC.GeneratorServices
local owned=setmetatable({}, {__mode="k"})
if type(require)=="function" then pcall(require,"TimedActions/ISActivateGenerator") pcall(require,"TimedActions/ISFixGenerator") end
local function U() return SC.ControlUtil end
local localFallback={schema=1,jobs={}}
local function fieldJobs()
    local value=ModData and ModData.getOrCreate and ModData.getOrCreate("LF_FieldGeneratorServices") or localFallback
    if value.schema==nil then value.schema,value.jobs=1,{} end
    return value.schema==1 and value.jobs or nil
end
function G.requestLocal(player,generator,operation)
    G.pulse()
    local jobs=fieldJobs()
    if not jobs then return false,"Local service records are unreadable." end
    local target,reason=SC.BaseLife.describeObject(generator,true)
    if not target then return false,reason end
    for _,job in pairs(jobs) do
        if job.target.objectId==target.objectId then
            if job.target.operation~=operation then return false,"This generator already has another service request." end
            job.retryHour=nil
            return true,"The existing local request will retry."
        end
    end
    local choices={}
    for _,actor in ipairs(SC.Registry.living()) do
        local id=SC.Registry.idOf(actor)
        local command=SC.Commands.describe(id,player)
        local owner=SC.ActionSupervisor and SC.ActionSupervisor.current(actor)
        if command and command.recruited and command.available~=false and command.alive~=false
            and (command.order=="follow" or command.order=="stay" or command.order=="guard")
            and not owner and not jobs[id] and U().near(actor,generator,15)
            and not SC.NativeActions.isWorkActive(actor) and not U().call(actor,"getVehicle") then
            choices[#choices+1]={actor=actor,id=id,command=command}
        end
    end
    table.sort(choices,function(a,b)
        local x,y=U().skill(a.actor),U().skill(b.actor)
        return x==y and tostring(a.id)<tostring(b.id) or x>y
    end)
    local selected=choices[1]
    if not selected then return false,"No idle local companion can perform this service." end
    target.operation=operation
    local owned=SC.Commands.peek and SC.Commands.peek(selected.actor) or selected.command
    jobs[selected.id]={id="field-generator:"..selected.id..":"..tostring(U().now()),type="generator_service",field=true,
        actorId=selected.id,reservedBy=selected.id,commandSerial=tonumber(owned.commandSerial) or 0,target=target}
    return true,"Asked "..SC.GameplayUtil.nameOf(selected.actor).." to "..operation.." the generator."
end
function G.request(player,generator,operation,row)
    if operation~="start" and operation~="stop" and operation~="repair" then return false,"Unsupported generator service." end
    if not U().present(generator) then return false,"Generator unavailable." end
    local running=U().call(generator,"isActivated")==true
    if operation=="start" and running or operation=="stop" and not running then return true,"Generator is already in that state." end
    if operation=="start" and (U().call(generator,"isConnected")~=true or (U().call(generator,"getFuel") or 0)<=0 or (U().call(generator,"getCondition") or 0)<=0) then
        return false,"The generator needs connection, fuel and usable condition."
    end
    if operation=="repair" and running then return false,"Stop the generator before repairing it." end
    if row and row.starter and operation~="repair" then return G.remote(player,generator,operation,row) end
    local life=SC.BaseLife
    if not life or not life.active() or not life.withinWorkReach(generator) then
        return G.requestLocal(player,generator,operation)
    end
    local descriptor,reason=life.describeObject(generator,true)
    if not descriptor then return false,reason end
    descriptor.operation=operation
    for _,job in ipairs(life.active().jobs or {}) do
        if job.type=="generator_service" and job.target.objectId==descriptor.objectId
            and job.state~="completed" and job.state~="cancelled" then
            return false,"This generator already has a service request."
        end
    end
    return life.enqueueJob({type="generator_service",priority=5,target=descriptor})
end
function G.remote(player,generator,operation,row)
    if not U().present(generator) then return false,"Generator unavailable." end
    if not SC.TerminalHardware then return false,"Starter hardware unavailable." end
    local battery=SC.TerminalHardware.restorePart(row.starter)
    if not battery then return false,"The saved starter battery is unreadable." end
    local charge=U().charge(battery) or 0
    if (tonumber(U().call(battery,"getCondition")) or 0)<=0 then return false,"The starter battery is broken." end
    if operation=="start" and charge<0.01 then return false,"The starter battery needs charging." end
    if type(ISActivateGenerator)~="table" or type(ISActivateGenerator.complete)~="function" then return false,"Native generator activation unavailable." end
    if operation=="start" then U().setCharge(battery,math.max(0,charge-0.01)) end
    local saved=SC.TerminalHardware.capturePart(battery)
    if not saved then return false,"Starter battery state could not be preserved." end
    row.starter=saved
    local okay=pcall(ISActivateGenerator.complete,{generator=generator,activate=operation=="start"})
    if not okay then return false,"Native startup did not complete. Inspect the generator." end
    return U().call(generator,"isActivated")== (operation=="start"),"Generator "..(U().call(generator,"isActivated") and "running." or "stopped; a failed start may need repair.")
end
function G.fit(player,generator,row,battery)
    if not U().near(player,generator,3) or U().skill(player)<4 or not U().hasTool(player,"Base.Screwdriver") then
        return false,"Stand beside the generator with Electrical 4 and a screwdriver."
    end
    if row.starter then return false,"A starter is already installed." end
    if not U().owns(player,battery) or not tostring(U().call(battery,"getFullType")):match("^Base%.CarBattery") then return false,"Choose your own car battery." end
    local part=SC.TerminalHardware.capturePart(battery)
    if not part then return false,"The exact battery could not be preserved." end
    local okay,reason=U().consume(player,row.remoteController and {} or {["Base.ElectricWire"]=2,["Base.ElectronicsScrap"]=4})
    if not okay then return false,reason end
    local container=U().call(battery,"getContainer")
    U().call(container,"Remove",battery)
    if SC.GameplayUtil.containerContainsIdentity(container,battery) then U().refund(reason) return false,"Battery transfer failed." end
    row.starter=part
    row.remoteController=true
    return true,"Remote-start controller fitted."
end
function G.removeStarter(player,generator,row)
    if not U().near(player,generator,3) or not U().hasTool(player,"Base.Screwdriver") then return false,"Stand beside the generator with a screwdriver." end
    if not row.starter then return false,"No starter battery is fitted." end
    local battery=SC.TerminalHardware.restorePart(row.starter)
    if not battery then return false,"The original battery is unreadable; its saved payload has been preserved." end
    for _,candidate in ipairs(U().items(player)) do
        if U().call(candidate,"getID")==row.starter.id then return false,"An item with this identity is already present. Transfer stopped." end
    end
    local inventory=U().inventory(player)
    if U().call(inventory,"hasRoomFor",player,battery)~=true then return false,"Make room for the starter battery." end
    local part=row.starter row.starter=nil
    U().call(inventory,"AddItem",battery)
    if not SC.GameplayUtil.containerContainsIdentity(inventory,battery) then row.starter=part return false,"Transfer failed; battery preserved in its controller." end
    return true,"Original starter battery removed. The controller can accept a replacement."
end
function G.canContinue(actor,generator,jobId)
    local job=SC.BaseLife.job(jobId)
    if not job then local jobs=fieldJobs() job=jobs and jobs[SC.GameplayUtil.idOf(actor)] end
    local commands=job and job.field and SC.Commands.peek(actor)
    return job and (not job.field or commands and (tonumber(commands.commandSerial) or 0)==job.commandSerial)
        and job.type=="generator_service" and job.reservedBy==SC.GameplayUtil.idOf(actor)
        and job.id==jobId
        and SC.BaseLife.resolveObject(job.target)==generator and U().call(actor,"isDead")~=true
        and select(1,SC.GameplayUtil.directInteractionAccess(actor,generator))==true
end
function G.update(actor,state,job)
    local target=job.target
    local generator=SC.BaseLife.resolveObject(target)
    if not U().present(generator) then return false,"generator_service_unloaded",true end
    if target.operation~="start" and target.operation~="stop" and target.operation~="repair" then return false,"generator_service_invalid",true end
    if SC.NativeActions.workKind(actor)=="generator_service" then
        if owned[actor]~=job.id then return false,"generator_service_owner_unknown",true end
        if SC.NativeActions.isWorkActive(actor) then return true,"generator_service_active" end
        local okay,reason=SC.NativeActions.finishWork(actor)
        if not okay then return false,reason,true end
        target.serviceStarted=nil
        if target.operation=="start" and U().call(generator,"isActivated")~=true
            or target.operation=="stop" and U().call(generator,"isActivated")~=false then
            return false,"generator_service_retry",true
        end
    end
    local done=target.operation=="repair" and (U().call(generator,"getCondition") or 0)>=100
        or target.operation=="start" and U().call(generator,"isActivated")==true
        or target.operation=="stop" and U().call(generator,"isActivated")==false
    if done then if owned[actor]==job.id then owned[actor]=nil end return true,"generator_service_completed",false,true end
    if target.serviceStarted then target.serviceStarted=nil return false,"generator_service_retry",true end
    if target.operation=="repair" then
        local scrap
        for _,item in ipairs(U().items(actor)) do if U().call(item,"getFullType")=="Base.ElectronicsScrap" then scrap=item break end end
        if not scrap then
            if job.field then return false,"missing_supply:Base.ElectronicsScrap",true end
            for _,storage in ipairs(SC.BaseLife.storageRows(nil,true)) do
                if SC.BaseLife.availableCount(storage,"Base.ElectronicsScrap")>0 then
                    local container=SC.BaseLife.resolveContainer(storage)
                    for _,item in ipairs(U().list(U().call(container,"getItems"),512)) do
                        if U().call(item,"getFullType")=="Base.ElectronicsScrap" then
                            local okay,reason=SC.BaseWork.withdrawFromStorage(actor,state,storage,container,item)
                            return okay,reason or "approaching_base_storage",okay~=true
                        end
                    end
                end
            end
            return false,"missing_supply:Base.ElectronicsScrap",true
        end
    end
    local at,squares,reason=SC.GameplayUtil.directInteractionAccess(actor,generator)
    if not at then
        if not squares or #squares==0 then return false,reason or "generator_service_no_access",true end
        local okay,why=SC.Navigation.requestAny(actor,squares,"walk",{action="move_to_generator_service",targetSquare=squares[1],arrivalDistance=0.15,workCampOnly=not job.field,workReach=not job.field})
        if okay then owned[actor]=job.id end
        return okay,why,not okay
    end
    local okay,why=SC.NativeActions.startGeneratorService(actor,generator,target.operation,job.id)
    if okay then target.serviceStarted=true owned[actor]=job.id end
    return okay,why,not okay
end
function G.cancel(actor,job)
    local owns=actor and job and owned[actor]==job.id
    if owns and SC.NativeActions.workKind(actor)=="generator_service" then
        local okay,reason=SC.NativeActions.cancelWork(actor,"generator_service_cancelled")
        if not okay then return false,reason end
    end
    local navigation=owns and SC.Navigation and SC.Navigation.peek and SC.Navigation.peek(actor)
    if navigation and navigation.goalAction=="move_to_generator_service" then
        local okay,reason=SC.Navigation.cancel(actor,"generator_service_cancelled")
        if not okay then return false,reason end
    end
    if owns then owned[actor]=nil end
    if job then job.target.serviceStarted=nil job.assignedId=nil end
    return true
end
function G.releaseAffinity(actor,job)
    if actor and job and owned[actor]==job.id and SC.NativeActions.workKind(actor)=="generator_service" and SC.NativeActions.isWorkActive(actor) then return false end
    return G.cancel(actor,job)
end
function G.fieldPending(actor)
    local jobs=fieldJobs()
    return jobs and jobs[SC.GameplayUtil.idOf(actor)]
end
function G.pulse()
    local jobs=fieldJobs()
    if not jobs or not SC.Registry or not SC.Registry.byId then return end
    for id,job in pairs(jobs) do
        local record=SC.Registry.byId(id)
        local actor=record and record.actor
        local commands=actor and SC.Commands.peek(actor)
        if not record or actor and (U().call(actor,"isDead")==true or commands and (tonumber(commands.commandSerial) or 0)~=job.commandSerial) then
            if G.cancel(actor,job) then jobs[id]=nil end
        end
    end
end
function G.updateField(actor,commands,urgent)
    local jobs=fieldJobs() local id=SC.GameplayUtil.idOf(actor)
    local job=jobs and jobs[id]
    if not job then return nil end
    if (tonumber(commands.commandSerial) or 0)~=job.commandSerial or U().call(actor,"isDead")==true then
        G.cancel(actor,job) jobs[id]=nil return nil
    end
    local hour=U().hours()
    if urgent then
        G.cancel(actor,job) job.retryHour=hour and hour+0.05
        return nil
    end
    if job.retryHour and (not hour or hour<job.retryHour) then return nil end
    job.retryHour=nil
    local okay,reason,blocked,done=G.update(actor,{},job)
    if done then jobs[id]=nil return true,"generator_service_completed" end
    if blocked then
        G.cancel(actor,job) job.retryHour=hour and hour+0.05 job.blocker=reason
        return nil
    end
    return okay,reason
end
return G
