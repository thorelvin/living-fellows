-- SPDX-License-Identifier: MIT
-- Home trips own no site work. Preview planning is an explicit UI action;
-- menu eligibility and card reads never ask the road planner to do work.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.HomeTrip = SC.HomeTrip or {}
local Home = SC.HomeTrip
local cachedKey, cachedDraft
local radioRequests, radioSerial = setmetatable({}, {__mode="k"}), 0
local function E() return SC.ExpeditionPrototype end
local function U() return SC.GameplayUtil end
local function call(actor, method, ...)
    if not actor then return nil end
    local value, okay = U().call(actor, method, ...)
    if okay then return value end
end
local function point(actor)
    local x,y,z = U().position(actor)
    if not x or not y or not z then return nil end
    return {x=math.floor(x),y=math.floor(y),z=math.floor(z)}
end
local function copy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 12 then return nil end
    local result = {}
    for key,item in pairs(value) do result[key] = copy(item,(depth or 0)+1) end
    return result
end
local function validId(id) return type(id)=="string" and #id>0 and #id<=128 end
local function coordinate(n, maximum)
    return type(n)=="number" and n==math.floor(n) and n>=0 and n<=(maximum or 30000)
end
local function validPoint(p)
    return type(p)=="table" and coordinate(p.x) and coordinate(p.y) and p.z==0
end
local function inside(actor, area)
    local x,y,z=U().position(actor)
    return x and y and z and math.abs(z-area.z)<=0.2
        and x>=area.x1 and x<=area.x2+0.99 and y>=area.y1 and y<=area.y2+0.99
end
function Home.captureCamp(base)
    if type(base)~="table" or not validId(base.id) or not validPoint(base.core) then return nil end
    local areas, geometry, arrival = {}, {}, nil
    for _,zone in ipairs(base.zones or {}) do
        if zone.kind=="area" then
            if not coordinate(zone.x1) or not coordinate(zone.y1) or not coordinate(zone.x2) or not coordinate(zone.y2)
                or type(zone.z)~="number" then return nil end
            geometry[#geometry+1]=table.concat({zone.z,zone.x1,zone.y1,zone.x2,zone.y2},",")
            if zone.z==0 and coordinate(zone.x1) and coordinate(zone.y1)
                and coordinate(zone.x2) and coordinate(zone.y2) and zone.x1<=zone.x2 and zone.y1<=zone.y2 then
                areas[#areas+1]={x1=zone.x1,y1=zone.y1,x2=zone.x2,y2=zone.y2,z=0}
            end
        end
    end
    table.sort(geometry)
    table.sort(areas,function(a,b)
        return table.concat({a.x1,a.y1,a.x2,a.y2},",")<table.concat({b.x1,b.y1,b.x2,b.y2},",")
    end)
    for _,area in ipairs(areas) do if inside(base.core,area) then arrival=area break end end
    if not arrival then return nil end
    return {id=base.id,core=copy(base.core),arrival=copy(arrival),
        fingerprint=table.concat({base.id,base.core.x,base.core.y,base.core.z,table.concat(geometry,";")},"|")}
end
function Home.validCamp(camp)
    local a=type(camp)=="table" and camp.arrival
    return validId(camp and camp.id) and validPoint(camp.core)
        and type(camp.fingerprint)=="string" and #camp.fingerprint>0 and #camp.fingerprint<=8192
        and type(a)=="table" and coordinate(a.x1) and coordinate(a.y1)
        and coordinate(a.x2) and coordinate(a.y2) and a.x1<=a.x2 and a.y1<=a.y2 and a.z==0
        and inside(camp.core,a)==true
end
function Home.sameStop(a,b)
    if type(a)~="table" or type(b)~="table" or a.kind~=b.kind or a.zoneId~=b.zoneId then return false end
    for _,field in ipairs({"point","roadEntry","parking"}) do
        local left,right=a[field],b[field]
        if (left==nil)~=(right==nil) then return false end
        if left then for _,axis in ipairs({"x","y","z","x1","y1","x2","y2"}) do if left[axis]~=right[axis] then return false end end end
    end
    return true
end
function Home.campUnchanged(camp)
    local current=SC.BaseLife and SC.BaseLife.active and Home.captureCamp(SC.BaseLife.active())
    if not Home.validCamp(camp) or not current or current.fingerprint~=camp.fingerprint then return false end
    for _,axis in ipairs({"x","y","z"}) do if current.core[axis]~=camp.core[axis] then return false end end
    for _,axis in ipairs({"x1","y1","x2","y2","z"}) do if current.arrival[axis]~=camp.arrival[axis] then return false end end
    return true
end
function Home.copyCamp(camp)
    if not Home.validCamp(camp) then return nil end
    return {id=camp.id,core={x=camp.core.x,y=camp.core.y,z=0},fingerprint=camp.fingerprint,
        arrival={x1=camp.arrival.x1,y1=camp.arrival.y1,x2=camp.arrival.x2,y2=camp.arrival.y2,z=0}}
end
function Home.remoteAvailable()
    if not SCSplitScreenProbe then return false end
    local ok,available=pcall(function() return SCSplitScreenProbe.remoteArrivalCapability() end)
    return ok and available==true and SC.Persistence
        and type(SC.Persistence.commitRemoteArrival)=="function"
        and type(SC.Persistence.abortRemoteArrival)=="function"
        and type(SC.Persistence.completeRemoteArrival)=="function" or false
end
function Home.driveAvailable()
    if not SCSplitScreenProbe then return false end
    local okay,ready=pcall(function() return SCSplitScreenProbe.homeVehicleSaveCapability() end)
    return okay and ready==true
end
function Home.validCarReceipt(value,sqlId)
    if type(value)~="table" or value.version~=1 or value.sqlId~=sqlId
        or type(value.tagUUID)~="string" or #value.tagUUID<1 or #value.tagUUID>128
        or type(value.sha256)~="string" or #value.sha256~=64 or not string.match(value.sha256,"^%x+$") then return false end
    for _,axis in ipairs({"x","y","z"}) do
        local n=value[axis]
        if type(n)~="number" or n~=n or n==math.huge or n==-math.huge
            or n<(axis=="z" and -32 or 0) or n>(axis=="z" and 31 or 30000) then return false end
    end
    for _,field in ipairs({"worldVersion","byteLength"}) do
        local n=value[field]
        if type(n)~="number" or n~=math.floor(n) or n<1 or n>10000000 then return false end
    end
    return true
end
function Home.copyCarReceipt(value,sqlId)
    if not Home.validCarReceipt(value,sqlId) then return nil end
    return {version=1,sqlId=value.sqlId,tagUUID=value.tagUUID,x=value.x,y=value.y,z=value.z,
        worldVersion=value.worldVersion,byteLength=value.byteLength,sha256=value.sha256}
end
function Home.primaryRecallCarReady(active,car)
    local home=active and active.scout and active.scout.home
    if not home or not home.recalling or active.homeRelease or not car or not home.vehicleSqlId then return false end
    if active.homeRecallCar and active.homeRecallCar~=car then return false end
    local okay,retained=pcall(function() return SCSplitScreenProbe.primaryRetainsHomeVehicle(car,home.vehicleSqlId) end)
    return okay and retained==true
end
function Home.recallReadyForRelease(active)
    local home=active and active.scout and active.scout.home
    if not home or not home.recallCarPrimary then return true end
    local car=active.homeRecallCar or SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(home.vehicleSqlId)
    if not Home.primaryRecallCarReady(active,car) then return false,"home_recall_car_not_retained" end
    active.homeRecallCar=car
    if home.blocker=="home_recall_car_not_retained" then home.blocker=nil end
    return true
end
-- The native vehicle database owns the physical car. Wait for its actual
-- queued write before the companion view can leave a stopped field car.
function Home.carStopReady(active,car)
    local home=active and active.scout and active.scout.home
    if not home or not home.vehicleSqlId then return false,"home_car_save_unavailable" end
    if home.recallStopping and Home.primaryRecallCarReady(active,car) then
        local prior=active.homeCarSave
        if prior and prior.ticket then
            local okay,cancelled=pcall(function() return SCSplitScreenProbe.cancelHomeVehicleSave(prior.ticket) end)
            if not okay or cancelled~=true then return false,"home_finish_busy" end
        end
        active.homeCarSave,active.homeRecallCar=nil,car
        home.recallCarPrimary=true
        return true
    end
    if not Home.driveAvailable() then return false,"home_car_save_unavailable" end
    local transaction=active.homeCarSave
    if not transaction then
        transaction={car=car}
        active.homeCarSave=transaction
    end
    transaction.car=transaction.car or car
    if not transaction.ticket then
        -- A newly stopped car can still be coasting below the controller's
        -- threshold. A refused initial request owns no native snapshot yet;
        -- keep its trunk held and retry after the physics has had time to settle.
        if active.homeRelease and (active.homeRelease.carAttached or active.homeRelease.committed) then
            return false,"home_car_save_failed"
        end
        local now=U().nowMs()
        if transaction.retryAt and now<transaction.retryAt then return false,"home_car_save_pending" end
        local okay,ticket=pcall(function()
            if home.carSaveReceipt then return SCSplitScreenProbe.restoreHomeVehicleSave(home.carSaveReceipt) end
            if car then return SCSplitScreenProbe.requestHomeVehicleSave(car) end
            return 0
        end)
        if not okay or type(ticket)~="number" or ticket<=0 then
            transaction.retryAt=now+500
            return false,"home_car_save_failed"
        end
        transaction.ticket,transaction.retryAt=ticket,nil
    end
    local okay,status=pcall(function() return SCSplitScreenProbe.pollHomeVehicleSave(transaction.ticket) end)
    if not okay or status=="failed" then return false,"home_car_save_failed" end
    if status~="ready" then return false,"home_car_save_pending" end
    local read,receipt=pcall(function() return SCSplitScreenProbe.homeVehicleSaveReceipt(transaction.ticket) end)
    local copied=read and Home.copyCarReceipt(receipt,home.vehicleSqlId)
    if not copied then return false,"home_car_save_failed" end
    transaction.receipt,home.carSaveReceipt=copied,copied
    return true
end
function Home.releaseCarSave(active)
    Home.cancelRadio(active)
    local transaction=active and active.homeCarSave
    if transaction and transaction.ticket then
        pcall(function() return SCSplitScreenProbe.cancelHomeVehicleSave(transaction.ticket) end)
    end
    if active then active.homeCarSave=nil end
end
function Home.memberSeated(actor)
    if call(actor,"getVehicle")~=nil then return true end
    if SC.Vehicle and SC.Vehicle.isNativeSeated then
        local seated,vehicle=SC.Vehicle.isNativeSeated(actor)
        return seated==true or vehicle~=nil
    end
    return false
end
function Home.recordEligibility(record, viewer, selection)
    if type(record)~="table" or not validId(record.id) or not record.actor then return false,"home_member_unavailable" end
    local registered=SC.Registry and SC.Registry.byId(record.id)
    if not registered or registered.actor~=record.actor or registered.recruited~=true then return false,"home_not_recruited" end
    if not SC.Registry.isActive(record.actor,record.id) or U().isDead(record.actor) then return false,"home_member_unavailable" end
    if E() and E().isMemberId(record.id) then return false,"home_member_away" end
    if SC.BaseLife and SC.BaseLife.isInside(record.actor) then return false,"home_already_home" end
    local command=SC.Commands and SC.Commands.peek(record.actor)
    if not command or (command.order~="follow" and command.order~="regroup") then return false,"home_not_following" end
    local at=point(record.actor)
    if not at or at.z~=0 or math.abs(select(3,U().position(record.actor)))>0.2 then return false,"home_ground_floor_only" end
    local selected=selection and selection.travelMode=="drive" and (selection.vehicle or SC.Vehicle and SC.Vehicle.loadedBySqlId
        and SC.Vehicle.loadedBySqlId(selection.vehicleSqlId or selection.sqlId))
    local selectedParked=selection and selection.travelMode=="drive" and selected
        and SC.Vehicle and SC.Vehicle.isStationary and SC.Vehicle.isStationary(selected)==true
    local current=call(record.actor,"getVehicle")
    if current~=nil and (not selectedParked or current~=selected) then return false,"home_member_seated" end
    if SC.Vehicle and SC.Vehicle.isNativeSeated then
        local seated,vehicle=SC.Vehicle.isNativeSeated(record.actor)
        if (seated or vehicle~=nil) and (not selectedParked or vehicle~=selected) then return false,"home_member_seated" end
    end
    return true
end
function Home.validateStart(records,plan)
    if not Home.remoteAvailable() then return false,"home_safe_handover_unavailable" end
    if not Home.validState(plan.home) or plan.home.recalling or not Home.campUnchanged(plan.home.camp)
        or not validPoint(plan.destination) then return false,"home_invalid_plan" end
    local core=plan.home.camp.core
    if plan.destination.x~=core.x or plan.destination.y~=core.y or plan.destination.z~=core.z
        or plan.site or plan.search or plan.request or plan.wood or plan.vehicle
        or plan.turnHomeAfterHours or plan.arriveByHour or plan.mapTarget
        or (plan.travelMode~="road" and plan.travelMode~="straight" and plan.travelMode~="drive")
        or type(records)~="table" or #records<1 or #records>4 then return false,"home_invalid_plan" end
    local seen={}
    for _,record in ipairs(records) do
        local okay,reason=Home.recordEligibility(record,nil,{travelMode=plan.travelMode,vehicle=plan.fieldVehicle,vehicleSqlId=plan.vehicleSqlId})
        if not okay then return false,reason end
        if seen[record.id] then return false,"home_duplicate_member" end
        seen[record.id]=true
    end
    if plan.travelMode=="drive" then
        if not Home.driveAvailable() then return false,"home_car_save_unavailable" end
        if not SC.ExpeditionCar or not SC.ExpeditionCar.preflightField then return false,"driving_unavailable" end
        local car=plan.fieldVehicle or SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(plan.vehicleSqlId)
        local fresh,reason=plan.fieldCarPlan
        if not fresh then fresh,reason=SC.ExpeditionCar.preflightField(records,car,SC.BaseLife.active()) end
        if not fresh then return false,reason end
        if not Home.validState(plan.home) or plan.home.vehicleSqlId~=fresh.sqlId
            or not Home.sameStop(plan.home.carStop,fresh.homeStop) then return false,"home_review_changed" end
        plan.fieldCarPlan=fresh
    elseif plan.home.vehicleSqlId~=nil then return false,"home_invalid_plan" end
    local gameTime=type(getGameTime)=="function" and getGameTime()
    local hour=gameTime and call(gameTime,"getWorldAgeHours")
    plan.home.departureHour=tonumber(hour)
    return true
end
function Home.roster(selection)
    selection=type(selection)=="table" and selection or {}
    local records=selection.records or (selection.record and {selection.record}) or (selection.id and {selection}) or {}
    local result={records={},eligibleRecords={},exclusions={},memberNames={},leaderId=selection.leaderId}
    local seen={}
    for _,record in ipairs(records) do
        record=type(record)=="table" and record or {}
        local okay,reason=Home.recordEligibility(record,selection.player,selection)
        local name=record and record.actor and U().nameOf(record.actor) or record and record.id or "?"
        if record.id and seen[record.id] then okay,reason=false,"home_duplicate_member" result.blocker=reason end
        if record.id then seen[record.id]=true end
        if okay then
            result.records[#result.records+1]=record
            result.memberNames[#result.memberNames+1]=name
        else result.exclusions[#result.exclusions+1]={id=record.id,name=name,reason=reason,blocker=reason} end
    end
    result.eligibleRecords=result.records
    result.leaderId=result.leaderId or result.records[1] and result.records[1].id
    if #result.records<1 then result.blocker=result.exclusions[1] and result.exclusions[1].reason or "home_no_members"
    elseif #result.records>4 then result.blocker="home_too_many" end
    if result.leaderId then
        local found=false
        for index,record in ipairs(result.records) do
            if record.id==result.leaderId then
                found=true
                table.remove(result.records,index)
                table.insert(result.records,1,record)
                break
            end
        end
        if not found then result.blocker="home_leader_unavailable" end
    end
    return result
end
function Home.eligibility(selection)
    local result=Home.roster(selection)
    local base=SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    result.hidden=base==nil or (#result.records==0 and #result.exclusions==1
        and (result.exclusions[1].reason=="home_not_recruited" or result.exclusions[1].reason=="home_already_home"))
    local active=E() and E().current()
    local blocker=active and (active.scout and active.scout.kind=="home" and "home_view_trip" or "home_view_expedition")
        or SC.BaseWatch and SC.BaseWatch.current and SC.BaseWatch.current() and "home_view_base_watch"
        or SC.ViewSession and SC.ViewSession.owner and SC.ViewSession.owner()~=nil and "home_view_expedition"
        or not Home.remoteAvailable() and "home_safe_handover_unavailable"
        or not base and "home_no_camp"
    local camp=Home.captureCamp(base)
    blocker=blocker or (not camp and "home_camp_ground_area_required") or result.blocker
    if blocker==nil and E() and E().homeDeliveryAvailable and not E().homeDeliveryAvailable() then blocker="home_delivery_queue_full" end
    result.camp=camp
    result.blocker,result.reason=blocker,blocker
    result.canStart=blocker==nil
    return result
end
local function cacheKey(review,mode)
    local keys={mode,review.camp and review.camp.fingerprint or ""}
    for _,record in ipairs(review.records) do
        local p=point(record.actor)
        keys[#keys+1]=record.id..":"..tostring(p and p.x)..","..tostring(p and p.y)..","..tostring(p and p.z)
    end
    return table.concat(keys,";")
end
-- This is a cheap stale-review guard. It never asks the road planner to run.
function Home.reviewKey(selection)
    selection=type(selection)=="table" and selection or {}
    local review=Home.eligibility(selection)
    local key=cacheKey(review,selection.travelMode or "road")
    if selection.travelMode=="drive" then
        local id=selection.vehicleSqlId or selection.sqlId or call(selection.vehicle,"getSqlId")
        local car=selection.vehicle or SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(id)
        local fingerprint=SC.ExpeditionCar and SC.ExpeditionCar.fieldFingerprint
            and SC.ExpeditionCar.fieldFingerprint(car,review.records,selection.player)
        local baseFingerprint=SC.ExpeditionCar and SC.ExpeditionCar.fieldBaseFingerprint
            and SC.ExpeditionCar.fieldBaseFingerprint(SC.BaseLife and SC.BaseLife.active())
        key=key..";car="..tostring(id)..":"..tostring(car)..":"..tostring(fingerprint)..":"..tostring(baseFingerprint)
    end
    return key
end
function Home.validCargo(rows)
    if type(rows)~="table" or #rows>256 then return false end
    local ids,native={},{}
    for _,row in ipairs(rows) do
        if type(row)~="table" or not validId(row.id) or ids[row.id]
            or type(row.itemType)~="string" or #row.itemType<1 or #row.itemType>160
            or type(row.nativeId)~="number" or row.nativeId~=math.floor(row.nativeId)
            or row.nativeId < -2147483648 or row.nativeId>2147483647 or native[row.nativeId] then return false end
        ids[row.id],native[row.nativeId]=true,true
    end
    return true
end
function Home.captureCarCargo(car,create)
    if not SC.Vehicle or not SC.Vehicle.cargoPart then return nil,"home_cargo_unreadable" end
    local _,trunk,reason=SC.Vehicle.cargoPart(car)
    if not trunk then
        if reason=="car_trunk_missing" then return {} end
        return nil,reason or "home_cargo_unreadable"
    end
    local items,okay=U().call(trunk,"getItems")
    if not okay or not items then return nil,"home_cargo_unreadable" end
    local count,counted=U().call(items,"size")
    if not counted and type(items)=="table" and type(items.size)~="function" then count,counted=#items,true end
    if not counted or type(count)~="number" or count~=math.floor(count) or count<0 then return nil,"home_cargo_unreadable" end
    if count>256 then return nil,"home_cargo_too_many" end
    local result,ids={},{}
    for index=0,count-1 do
        local item,read=U().call(items,"get",index)
        if not read and type(items)=="table" and type(items.get)~="function" then item=items[index+1] end
        local nativeId=call(item,"getID")
        local itemType=U().itemType and U().itemType(item) or call(item,"getFullType")
        if not item or call(item,"getContainer")~=trunk or type(nativeId)~="number"
            or nativeId~=math.floor(nativeId) or nativeId < -2147483648 or nativeId>2147483647
            or ids[nativeId] or type(itemType)~="string" or itemType=="" then return nil,"home_cargo_unreadable" end
        ids[nativeId]=true
        local id=U().itemStableId and U().itemStableId(item,create==true)
        if create and not validId(id) then return nil,"home_cargo_unreadable" end
        result[#result+1]={id=id,nativeId=nativeId,itemType=itemType}
    end
    if create and not Home.validCargo(result) then return nil,"home_cargo_unreadable" end
    return result
end
function Home.routeDistance(route,actor,target)
    local at=point(actor)
    if not at or not validPoint(target) then return nil end
    if not route then return math.sqrt((at.x-target.x)^2+(at.y-target.y)^2) end
    local first,last=route.points and route.points[1],route.points and route.points[#route.points]
    if not first or not last or type(route.roadLength)~="number" or route.roadLength~=route.roadLength or route.roadLength<0 then return nil end
    return route.roadLength+math.sqrt((at.x-first.x)^2+(at.y-first.y)^2)
        +math.sqrt((last.x-target.x)^2+(last.y-target.y)^2)
end
function Home.draft(selection, refresh)
    selection=type(selection)=="table" and selection or {}
    local result=Home.eligibility(selection)
    result.requestedTravelMode=selection.travelMode or "road"
    result.travelMode=result.requestedTravelMode
    if result.travelMode~="road" and result.travelMode~="straight" and result.travelMode~="drive" then result.blocker="home_walk_only" end
    if result.blocker then result.canStart=false return result end
    if result.travelMode=="drive" then
        if not Home.driveAvailable() then result.blocker,result.reason,result.canStart="home_car_save_unavailable","home_car_save_unavailable",false return result end
        local signature=Home.reviewKey(selection)
        if not refresh and signature==cachedKey and cachedDraft then
            for _,field in ipairs({"car","homeStop","distance","measuredDistance","estimatedHours","reviewKey","blocker","reason","canStart"}) do result[field]=copy(cachedDraft[field]) end
            result._carPlan=cachedDraft._carPlan
            return result
        end
        local car=selection.vehicle or SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(selection.vehicleSqlId or selection.sqlId)
        local plan,reason,review
        if SC.ExpeditionCar and SC.ExpeditionCar.preflightField then plan,reason,review=SC.ExpeditionCar.preflightField(result.records,car,SC.BaseLife.active()) end
        result.car=review or plan
        if not plan then result.blocker,result.reason,result.canStart=reason or "car_unavailable",reason or "car_unavailable",false return result end
        local cargo,issue=Home.captureCarCargo(plan.vehicle,false)
        result.car,result.homeStop=review or plan,copy(plan.homeStop)
        result._carPlan,result.distance,result.measuredDistance,result.estimatedHours=plan,plan.distance,plan.distance,plan.estimatedHours
        result.reviewKey=Home.reviewKey(selection)
        if not cargo then result.blocker=issue
        elseif type(plan.distance)~="number" or plan.distance~=plan.distance or type(plan.estimatedHours)~="number"
            or plan.estimatedHours<=0 then result.blocker="home_invalid_plan"
        elseif plan.distance>5000 then result.blocker="home_too_far" end
        result.canStart,result.reason=result.blocker==nil,result.blocker
        cachedKey,cachedDraft=signature,result
        return result
    end
    local signature=Home.reviewKey(selection)
    local route
    if not refresh and signature==cachedKey and cachedDraft then
        for _,field in ipairs({"travelMode","routeFallback","distance","measuredDistance","estimatedHours","routeReason","streets","provisional"}) do result[field]=copy(cachedDraft[field]) end
        result._route=cachedDraft._route
    else
        local leader=result.records[1].actor
        local at=point(leader)
        result.distance=math.sqrt((at.x-result.camp.core.x)^2+(at.y-result.camp.core.y)^2)
        if result.travelMode=="road" then
            local why
            if SC.ExpeditionRoute and SC.ExpeditionRoute.plan then route,why=SC.ExpeditionRoute.plan(leader,result.camp.core) end
            if route then
                local ready,reason=SC.ExpeditionRoute.verifyEntry(route,leader)
                if not ready then route,why=nil,reason end
            end
            if route then
                local first,last=route.points[1],route.points[#route.points]
                result.distance=(route.roadLength or 0)+math.sqrt((at.x-first.x)^2+(at.y-first.y)^2)
                    +math.sqrt((last.x-result.camp.core.x)^2+(last.y-result.camp.core.y)^2)
                result.streets,result.provisional={},(route.inferredJunctions or 0)>0
                local seen={}
                for _,p in ipairs(route.points) do if type(p.street)=="string" and p.street~="" and not seen[p.street] then
                    seen[p.street]=true result.streets[#result.streets+1]=p.street
                end end
            else result.travelMode,result.routeFallback,result.routeReason="straight",true,why or "road_routing_unavailable" end
        end
        -- This is a one-way estimate from measured route length. It has no
        -- outbound trail from which to infer a pace. The fallback is the same
        -- conservative 0.005 game hours/tile used by expedition return clocks.
        result.estimatedHours=math.max(0.1,result.distance*0.005)
        result.measuredDistance=result.distance
        result._route=route
        cachedKey,cachedDraft=signature,result
    end
    if result.measuredDistance>1000 then result.blocker="home_too_far" end
    result.distance=math.floor(result.distance+0.5)
    result.reviewKey=signature
    result.canStart=result.blocker==nil
    result.reason=result.blocker
    return result
end
function Home.start(selection,reviewed)
    if reviewed and reviewed.reviewKey~=Home.reviewKey(selection) then return false,"home_review_changed" end
    local review=reviewed or Home.draft(selection)
    if not review.canStart then return false,review.blocker end
    if review.reviewKey~=Home.reviewKey(selection) then return false,"home_review_changed" end
    local home={camp=Home.copyCamp(review.camp)}
    if review.travelMode=="drive" then
        local cargo,reason=Home.captureCarCargo(review._carPlan.vehicle,true)
        if not cargo then return false,reason end
        home.vehicleSqlId,home.carName,home.carStop,home.cargo=review._carPlan.sqlId,review._carPlan.name,copy(review.homeStop),cargo
    end
    return E().startHome(review.records,{kind="home",destination=review.camp.core,
        travelMode=review.travelMode,home=home,restockBaseDuty=true,vehicleSqlId=home.vehicleSqlId,
        fieldVehicle=review._carPlan and review._carPlan.vehicle,fieldCarPlan=review._carPlan,reviewKey=review.reviewKey,
        roadRoute=review._route})
end
function Home.validState(home)
    if type(home)~="table" or not Home.validCamp(home.camp) then return false end
    if home.vehicleSqlId~=nil then
        if type(home.vehicleSqlId)~="number" or home.vehicleSqlId<0 or home.vehicleSqlId~=math.floor(home.vehicleSqlId)
            or type(home.carName)~="string" or #home.carName<1 or #home.carName>128
            or not Home.validCargo(home.cargo) or not SC.ExpeditionCar or not SC.ExpeditionCar.validFieldStop
            or not SC.ExpeditionCar.validFieldStop(home.carStop,home.camp) then return false end
        if home.carSaveReceipt~=nil and not Home.validCarReceipt(home.carSaveReceipt,home.vehicleSqlId) then return false end
    elseif home.carStop~=nil or home.cargo~=nil or home.carSaveReceipt~=nil then return false end
    if home.recalling~=nil and type(home.recalling)~="boolean" then return false end
    if home.recallStopping~=nil and (type(home.recallStopping)~="boolean" or home.recalling~=true or home.vehicleSqlId==nil) then return false end
    if home.recallCarPrimary~=nil and (type(home.recallCarPrimary)~="boolean" or home.recalling~=true or home.vehicleSqlId==nil) then return false end
    if home.recalling and not validPoint(home.recallPoint) then return false end
    if home.recallPoint~=nil and not validPoint(home.recallPoint) then return false end
    if home.departureHour~=nil and (type(home.departureHour)~="number" or home.departureHour~=home.departureHour or home.departureHour<0 or home.departureHour>10000000) then return false end
    if home.blocker~=nil and (type(home.blocker)~="string" or #home.blocker>96) then return false end
    if home.knowledge~=nil then
        local k=home.knowledge
        if type(k)~="table" or not coordinate(k.distance,100000)
            or type(k.at)~="number" or k.at~=k.at or k.at<0 or k.at>10000000
            or (k.place~=nil and (type(k.place)~="string" or #k.place>160)) then return false end
    end
    for _,key in ipairs({"radioHold","radioHoldStopping","radioVehicleHold","recallByRadio"}) do
        if home[key]~=nil and type(home[key])~="boolean" then return false end
    end
    if home.radioHoldStopping and (not home.radioHold or home.vehicleSqlId==nil)
        or home.radioVehicleHold and (not home.radioHold or home.vehicleSqlId==nil)
        or home.recallByRadio and not home.recalling then return false end
    for _,key in ipairs({"radioRecallAt","radioHeldAt"}) do
        if home[key]~=nil and (type(home[key])~="number" or home[key]~=home[key] or home[key]<0 or home[key]>10000000) then return false end
    end
    if home.radioReport~=nil and not Home.validRadioReport(home.radioReport) then return false end
    return true
end
function Home.copyState(home)
    if not Home.validState(home) then return nil end
    return {camp=Home.copyCamp(home.camp),recalling=home.recalling,recallStopping=home.recallStopping,
        recallCarPrimary=home.recallCarPrimary,recallPoint=home.recallPoint and copy(home.recallPoint),
        radioHold=home.radioHold,radioHoldStopping=home.radioHoldStopping,radioVehicleHold=home.radioVehicleHold,
        recallByRadio=home.recallByRadio,radioRecallAt=home.radioRecallAt,radioHeldAt=home.radioHeldAt,
        radioReport=home.radioReport and copy(home.radioReport),
        vehicleSqlId=home.vehicleSqlId,carName=home.carName,carStop=home.carStop and copy(home.carStop),cargo=home.cargo and copy(home.cargo),
        carSaveReceipt=home.carSaveReceipt and Home.copyCarReceipt(home.carSaveReceipt,home.vehicleSqlId),
        departureHour=home.departureHour,blocker=home.blocker,knowledge=home.knowledge and {
            distance=home.knowledge.distance,at=home.knowledge.at,place=home.knowledge.place}}
end
function Home.current()
    local active=E() and E().current()
    return active and active.scout and active.scout.kind=="home" and active or nil
end
function Home._radioPair(player)
    local active=Home.current()
    if not active or not player or type(getSpecificPlayer)~="function" or getSpecificPlayer(0)~=player
        or active.restoring or active.terminal or not active.leader or not active.leader.actor
        or getSpecificPlayer(1)~=active.leader.actor or U().isDead(player)
        or U().isDead(active.leader.actor) then return nil,"home_radio_unavailable" end
    local function equipped(actor)
        local item=call(actor,"getEquipedRadio")
        if not item or call(item,"getContainer")~=call(actor,"getInventory")
            or item~=call(actor,"getPrimaryHandItem") and item~=call(actor,"getSecondaryHandItem")
                and item~=call(actor,"getClothingItem_Back") then return nil end
        local data=call(item,"getDeviceData")
        local power,range=data and call(data,"getPower"),data and call(data,"getTransmitRange")
        if not data or call(data,"getIsTwoWay")~=true or call(data,"getIsTurnedOn")~=true
            or call(data,"getHasBattery")~=true or type(power)~="number" or power~=power or power<=0 or power==math.huge
            or type(range)~="number" or range~=range or range<=0 or range==math.huge
            or call(data,"getMicIsMuted")~=false or call(data,"isNoTransmit")~=false then return nil end
        return item,data,range
    end
    local source,sourceData,sourceRange=equipped(player)
    local receiver,receiverData,receiverRange=equipped(active.leader.actor)
    if not source or not receiver then return nil,"home_radio_needed" end
    local channel=call(sourceData,"getChannel")
    local gap=U().distance(player,active.leader.actor)
    if type(channel)~="number" or channel~=math.floor(channel) or channel<0 or channel==math.huge
        or channel~=call(receiverData,"getChannel") or type(gap)~="number" or gap~=gap
        or gap>sourceRange or gap>receiverRange then return nil,"home_radio_needed" end
    return {source=source,sourceData=sourceData,receiver=receiver,receiverData=receiverData,
        channel=channel,range=sourceRange,returnRange=receiverRange}
end
function Home.radioState(player)
    local active=Home.current()
    if not active then return {actions={},holding=false,blocked=false} end
    local home,scout=active.scout.home,active.scout
    local pending=active.homeRadioRequest
    local _,reason=Home._radioPair(player)
    if active.homeRelease then reason="home_finish_busy"
    elseif pending or active.pendingRadio or active.pendingReport then reason="home_radio_busy"
    elseif active.radioTextHooked~=true then reason="home_radio_unavailable" end
    local blocked=scout.pause~=nil and (scout.pause.reported==true
        or home.radioReport and home.radioReport.state=="blocked")
    local result={actions={},holding=home.radioHold==true,blocked=blocked==true,
        report=home.radioReport and copy(home.radioReport),
        lastReply=active.homeRadioReply and copy(active.homeRadioReply)}
    if pending then result.pending={id=pending.id,verb=pending.verb,leaderName=active.leader.name} end
    for _,verb in ipairs({"come_back","hold","status","push_on"}) do
        local why=reason
        if not why and verb=="hold" and home.recallStopping then why="home_radio_recall_stopping" end
        if not why and verb=="hold" and home.radioHold then why="home_radio_already_holding" end
        if not why and verb=="push_on" and (not home.radioHold and not blocked
            or home.radioHoldStopping or active.technicalIssue) then why="home_radio_not_stopped" end
        result.actions[verb]={enabled=why==nil,reason=why}
    end
    return result
end
function Home.requestRadio(player,verb,expectedTripId)
    local active=Home.current()
    if not active or expectedTripId~=active.radioSession then return false,"home_radio_stale" end
    local status=Home.radioState(player)
    local action=status.actions[verb]
    if not action then return false,"home_radio_unavailable" end
    if not action.enabled then return false,action.reason end
    local target=point(player)
    if verb=="come_back" and not validPoint(target) then return false,"home_ground_floor_only" end
    local pair,reason=Home._radioPair(player)
    if not pair then return false,reason end
    radioSerial=radioSerial+1
    local request={id=radioSerial,verb=verb,leaderName=active.leader.name}
    radioRequests[request]={active=active,player=player,leader=active.leader.actor,tripId=active.radioSession,
        target=target,pair=pair,phase="queued",verb=verb,id=radioSerial}
    active.homeRadioRequest=request
    return true,"home_radio_queued"
end
function Home.radioRequestCurrent(active,request)
    local proof=radioRequests[request]
    if not proof or proof.active~=active or Home.current()~=active or active.homeRadioRequest~=request
        or proof.tripId~=active.radioSession or proof.leader~=active.leader.actor or active.homeRelease
        or request.id~=proof.id or request.verb~=proof.verb or proof.phase=="applied" then return false,"home_radio_stale" end
    local pair,reason=Home._radioPair(proof.player)
    if not pair then return false,reason end
    for _,key in ipairs({"source","sourceData","receiver","receiverData","channel"}) do
        if pair[key]~=proof.pair[key] then return false,"home_radio_stale" end
    end
    return true,proof
end
function Home.beginRadioRequest(active,request)
    local okay,proof=Home.radioRequestCurrent(active,request)
    if not okay then return false,proof end
    if proof.phase~="queued" then return false,"home_radio_busy" end
    proof.phase="transmitting"
    return true,proof
end
function Home.ownRadioField(active,request,field,value)
    local proof=radioRequests[request]
    if not proof or proof.active~=active or active.homeRadioRequest~=request
        or (field~="pendingRadio" and field~="pendingReport" and field~="radioAuthorization")
        or active[field]~=nil and active[field]~=proof[field] then return false end
    proof[field]=value
    active[field]=value
    return true
end
function Home.clearRadioField(active,request,field)
    local proof=radioRequests[request]
    if proof and proof.active==active and proof[field]~=nil and active[field]==proof[field] then active[field]=nil end
end
function Home.cancelRadio(active,request)
    request=request or active and active.homeRadioRequest
    local proof=request and radioRequests[request]
    if not proof or proof.active~=active then return false end
    for _,field in ipairs({"pendingRadio","pendingReport","radioAuthorization"}) do Home.clearRadioField(active,request,field) end
    if active.homeRadioRequest==request then active.homeRadioRequest=nil end
    radioRequests[request]=nil
    return true
end
function Home._radioReport(active)
    local scout,home=active.scout,active.scout.home
    local gameTime=type(getGameTime)=="function" and getGameTime()
    local hour=gameTime and call(gameTime,"getWorldAgeHours")
    local at=point(active.leader.actor)
    if type(hour)~="number" or not at then return nil end
    local route=scout.roadRoute
    local place=route and route.points and route.points[route.index or 1]
    place=place and place.street
    return {at=hour,distance=math.floor(math.sqrt((at.x-home.camp.core.x)^2+(at.y-home.camp.core.y)^2)+.5),
        place=type(place)=="string" and place~="" and string.sub(place,1,160) or nil,
        holdingAt=home.radioHeldAt,
        transport=call(active.leader.actor,"getVehicle")~=nil and "drive" or "foot",
        state=(home.radioHoldStopping or home.recallStopping) and "stopping" or home.radioHold and "holding"
            or home.recalling and "returning" or scout.pause and "blocked"
            or scout.vehicle and scout.vehicle.state=="driving_home" and "driving" or "walking"}
end
function Home.validRadioReport(report)
    return type(report)=="table" and type(report.at)=="number" and report.at==report.at and report.at>=0 and report.at<=10000000
        and coordinate(report.distance,100000) and (report.place==nil or type(report.place)=="string" and #report.place<=160)
        and (report.holdingAt==nil or type(report.holdingAt)=="number" and report.holdingAt==report.holdingAt
            and report.holdingAt>=0 and report.holdingAt<=10000000)
        and (report.transport=="drive" or report.transport=="foot")
        and (report.state=="stopping" or report.state=="holding" or report.state=="returning"
            or report.state=="blocked" or report.state=="driving" or report.state=="walking")
end
function Home.applyRadioRequest(active,request,player)
    local okay,proof=Home.radioRequestCurrent(active,request)
    if not okay then return false,proof end
    if proof.phase~="transmitting" or proof.player~=player
        or not E().radioCommandAuthorized(active.leader.actor,"home_radio",request,player) then
        return false,"home_radio_stale"
    end
    local scout,home=active.scout,active.scout.home
    local report=Home._radioReport(active)
    if not report then return false,"home_radio_unavailable" end
    local accepted,reason=true,"home_radio_status"
    if proof.verb=="come_back" then
        home.radioHold,home.radioHoldStopping,home.radioVehicleHold,home.radioHeldAt=nil,nil,nil,nil
        accepted,reason=Home.stageRecall(active,nil,"recalled_radio",copy(proof.target))
        if accepted then
            home.recallByRadio,home.radioRecallAt=true,report.at
            reason="home_radio_returning"
        end
    elseif proof.verb=="hold" then
        if home.recallStopping then return false,"home_radio_recall_stopping" end
        home.radioHold=true
        home.radioHeldAt=report.at
        home.radioHoldStopping=scout.vehicle and scout.vehicle.state~="home_wait" and scout.vehicle.state~="abandoned" or nil
        home.radioVehicleHold=home.radioHoldStopping and true or nil
        if active.testWaypoint then E().clearTestWaypoint(active.leader.actor) end
        for _,member in ipairs(active.roster) do
            if member.actor and not U().isDead(member.actor) and not home.radioHoldStopping then
                if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(member.actor,"home_radio_hold") end
                if SC.Actor and SC.Actor.stop then SC.Actor.stop(member.actor) end
            end
        end
        reason="home_radio_holding"
    elseif proof.verb=="push_on" then
        if not home.radioHold and not (scout.pause and (scout.pause.reported or home.radioReport and home.radioReport.state=="blocked"))
            or home.radioHoldStopping or active.technicalIssue then return false,"home_radio_not_stopped" end
        if scout.pause then
            accepted,reason=E().applyHomeRadioPush(request,player)
            if not accepted then return false,reason end
        end
        if home.radioVehicleHold then
            accepted,reason=false,"home_car_unsettled"
            if SC.ExpeditionCar and SC.ExpeditionCar.resumeHome then
                accepted,reason=SC.ExpeditionCar.resumeHome(active,U().nowMs())
            end
            if not accepted then return false,reason end
        end
        home.radioHold,home.radioHoldStopping,home.radioVehicleHold,home.radioHeldAt=nil,nil,nil,nil
        scout.lastStalledTarget,scout.legPlan,scout.lastPlanAt=nil,nil,nil
        scout.replans=0
        reason="home_radio_resumed"
    end
    if accepted then
        proof.phase="applied"
        home.radioReport=Home._radioReport(active)
        return true,reason
    end
    return false,reason
end
function Home.serviceRadio(active)
    local request=active.homeRadioRequest
    if not request then return end
    local proof=radioRequests[request]
    local called,accepted,reason=pcall(E().exchangeHomeRadio,request)
    if not called then accepted,reason=false,"home_radio_unavailable" end
    Home.cancelRadio(active,request)
    if Home.current()==active then
        active.homeRadioReply={id=request.id,verb=request.verb,acknowledged=accepted==true,reason=reason}
        if accepted and proof then
            local suffix=({come_back="RadioRecallAck",hold="RadioHoldAck",push_on="RadioPushAck",status="RadioStatusAck"})[proof.verb]
            local translated,message=false,reason
            if type(getText)=="function" then translated,message=pcall(getText,"UI_SC_HomeTrip_"..suffix,active.leader.name) end
            if not translated then message=reason end
            call(proof.player,"setHaloNote",message)
            if SC.Dialogue and SC.Dialogue.say and proof.verb~="status" then
                pcall(SC.Dialogue.say,active.leader.actor,proof.verb=="come_back" and "home.turning_back"
                    or proof.verb=="hold" and "home.holding" or "home.push_on")
            end
        end
    end
    radioRequests[request]=nil
end
function Home.canRecall(player)
    local active=Home.current()
    if not active or not player then return false,"home_no_trip" end
    if active.homeRelease then return false,"home_finish_busy" end
    if active.homeRadioRequest or active.pendingRadio or active.pendingReport then return false,"home_radio_busy" end
    for _,member in ipairs(active.roster) do
        if member.actor and E().playerCanObserve(member.actor,player) then return true end
    end
    return false,"home_out_of_earshot"
end
function Home.inventoryFrozen(actor)
    local active=Home.current()
    local transaction=active and active.homeRelease
    for _,member in ipairs(transaction and transaction.actors or {}) do
        if member==actor then return true,"home_finish_busy" end
    end
    return false
end
function Home.handoverOwns(actor) return Home.inventoryFrozen(actor) end
function Home.inventoryContainerFrozen(container)
    local active=Home.current()
    local transaction=active and active.homeRelease
    local carSave=active and active.homeCarSave
    if not container or not transaction and not carSave then return false end
    local roots={}
    for _,actor in ipairs(transaction and transaction.actors or {}) do
        local root=call(actor,"getInventory")
        if root then roots[root]=true end
    end
    if SC.Vehicle and SC.Vehicle.cargoPart then
        local function addCarRoot(car)
            if car then local _,trunk=SC.Vehicle.cargoPart(car) if trunk then roots[trunk]=true end end
        end
        addCarRoot(transaction and transaction.car)
        addCarRoot(carSave and carSave.car)
        if carSave and SC.Vehicle.loadedBySqlId then addCarRoot(SC.Vehicle.loadedBySqlId(active.scout.home.vehicleSqlId)) end
    end
    local outer=call(container,"getOutermostContainer")
    if roots[container] or outer and roots[outer] then return true,"home_finish_busy" end
    local current,seen=container,{}
    for _=1,12 do
        if not current or seen[current] then break end
        if roots[current] then return true,"home_finish_busy" end
        seen[current]=true
        local item=call(current,"getContainingItem") or call(current,"getParent")
        current=item and call(item,"getContainer") or nil
    end
    if current and roots[current] then return true,"home_finish_busy" end
    return false
end
function Home.cancel(player)
    local allowed,reason=Home.canRecall(player)
    if not allowed then return false,reason end
    return E().cancelHome("recalled_nearby",player)
end
function Home.arrivalReady(active)
    if not active or not Home.validState(active.scout and active.scout.home) then return false,"home_invalid_state" end
    local home=active.scout.home
    if not Home.campUnchanged(home.camp) then return false,"home_camp_changed" end
    if active.scout.vehicle then
        if not SC.ExpeditionCar or not SC.ExpeditionCar.homeArrivalReady then return false,"home_car_not_ready" end
        local ready,reason=SC.ExpeditionCar.homeArrivalReady(active)
        if ready~=true then return false,reason or "home_car_not_ready" end
        local car=SC.Vehicle and SC.Vehicle.loadedBySqlId and SC.Vehicle.loadedBySqlId(home.vehicleSqlId)
        ready,reason=Home.carStopReady(active,car)
        if ready~=true then return false,reason end
    end
    local actors={}
    for _,member in ipairs(active.roster) do
        local actor=member.actor
        if actor and U().isDead(actor) then
            -- Generic travel retains ready corpses on its pulses. Arrival can
            -- also be requested directly, and a newly fallen follower may not
            -- have produced its native corpse yet. Keep the remote map until
            -- that exact body's chunk is retained for the native save barrier.
            if call(actor,"isCorpseReady")~=true then return false,"home_corpse_pending" end
            local staged,retained=pcall(function() return SCSplitScreenProbe.stageDeadCorpseChunk(actor) end)
            if not staged or retained~=true then return false,"home_corpse_retention_failed" end
        elseif active.survivors==nil or active.survivors[member.id] then
            if actor==nil then return false,"home_member_unresolved" end
            if not SC.Registry.isActive(actor,member.id) then return false,"home_member_unresolved" end
            if call(actor,"getVehicle")~=nil then return false,"home_member_seated" end
            if SC.Vehicle and SC.Vehicle.isNativeSeated then
                local seated,vehicle=SC.Vehicle.isNativeSeated(actor)
                if seated or vehicle~=nil then return false,"home_member_seated" end
            end
            if not inside(actor,home.camp.arrival) or not SC.BaseLife.isInside(actor) then return false,"home_member_not_home" end
            actors[#actors+1]=actor
        end
    end
    if #actors<1 then return false,"home_no_survivors" end
    return true,actors
end
-- The journey's final fence/door entry belongs to Navigation. The bounded
-- exterior progress planner is useful between loaded areas, but can keep
-- surveying short exterior legs outside a closed camp boundary indefinitely.
function Home.continueApproach(active,reason)
    local scout,home=active.scout,active.scout.home
    if home.recalling or active.homeRelease or active.technicalIssue or active.cohesionHold or scout.pause
        or scout.vehicle and scout.vehicle.state~="home_wait" and scout.vehicle.state~="abandoned" then return false end
    local core=home.camp.core
    local at=point(active.leader.actor)
    local distance=at and math.sqrt((at.x-core.x)^2+(at.y-core.y)^2)
    if scout.phase=="awaiting_player" and at
        and (not inside(active.leader.actor,home.camp.arrival) or at.x~=core.x or at.y~=core.y) then scout.phase="inbound" end
    if not distance or distance>18 or not U().gridSquare or not U().gridSquare(core.x,core.y,core.z) then return false end
    if inside(active.leader.actor,home.camp.arrival) and distance<=0.75 then
        scout.phase="awaiting_player"
        home.blocker=reason or "home_member_not_home"
        if active.testWaypoint then E().clearTestWaypoint(active.leader.actor) end
        return true
    end
    scout.phase="inbound"
    home.blocker=nil
    local waypoint=active.testWaypoint
    if waypoint and waypoint.x==core.x and waypoint.y==core.y and waypoint.z==core.z then return false end
    if waypoint then E().clearTestWaypoint(active.leader.actor) end
    if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(active.leader.actor,"home_final_approach") end
    scout.legPlan,scout.lastStalledTarget=nil,nil
    local staged,issue=E().stageTestWaypoint(active.leader.actor,core.x,core.y,core.z)
    if staged~=true then
        home.blocker=issue or "home_final_approach_unavailable"
        active.technicalIssue={reason=home.blocker}
        return true
    end
    scout.bestDistanceToWaypoint,scout.lastProgressAt,scout.waypointStagedAt=distance,U().nowMs(),U().nowMs()
    return false
end
function Home.finalApproachFor(actor)
    local active=Home.current()
    if not active or active.leader.actor~=actor or active.homeRelease or active.scout.home.recalling then return false end
    local core,waypoint=active.scout.home.camp.core,active.testWaypoint
    return active.scout.phase=="inbound" and waypoint~=nil
        and waypoint.x==core.x and waypoint.y==core.y and waypoint.z==core.z
end
function Home.pulse(active)
    local scout=active.scout
    if not scout or scout.kind~="home" then return false end
    local home=scout.home
    Home.serviceRadio(active)
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    local seen=(SC.ViewSession and SC.ViewSession.owner and SC.ViewSession.owner()=="expedition"
        and type(getSpecificPlayer)=="function" and getSpecificPlayer(1)==active.leader.actor)
        or E().playerCanObserve(active.leader.actor,player)
    if seen then
        local p=point(active.leader.actor)
        local gameTime=type(getGameTime)=="function" and getGameTime()
        local hour=gameTime and call(gameTime,"getWorldAgeHours")
        local route=scout.roadRoute
        local street=route and route.points and route.points[route.index or 1]
        street=street and street.street
        if p and type(hour)=="number" then
            home.knowledge={at=hour,distance=math.floor(math.sqrt((p.x-home.camp.core.x)^2+(p.y-home.camp.core.y)^2)+0.5),
                place=type(street)=="string" and street~="" and string.sub(street,1,160) or nil}
        end
    end
    if home.recallStopping then
        Home.stageRecall(active,nil,"recalled_nearby",copy(home.recallPoint))
        if home.recallStopping then return true end
    end
    if home.recalling and home.radioHold then return true end
    if home.recalling then
        if scout.phase=="awaiting_player" then
            local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
            if player then
                local finished,issue=E().finishAtPlayer(player)
                if finished then return true end
                if issue=="home_recall_car_not_retained" then home.blocker=issue end
            end
        end
        return false
    end
    if not Home.campUnchanged(home.camp) then
        home.blocker="home_camp_changed"
        if scout.vehicle and scout.vehicle.state~="abandoned" then
            local stopped=SC.ExpeditionCar and SC.ExpeditionCar.cancelField and SC.ExpeditionCar.cancelField(active,U().nowMs())
            if stopped~=true then return true end
        end
        if active.testWaypoint then E().clearTestWaypoint(active.leader.actor) end
        if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(active.leader.actor,"home_camp_changed") end
        active.technicalIssue={reason="home_camp_changed"}
        return true
    end
    if home.radioHold then
        if home.radioVehicleHold then
            local stopped,issue=false,"home_car_unsettled"
            if SC.ExpeditionCar and SC.ExpeditionCar.holdHome then stopped,issue=SC.ExpeditionCar.holdHome(active,U().nowMs()) end
            if stopped==true then home.radioHoldStopping=nil home.blocker=nil
            else home.radioHoldStopping=true home.blocker=issue or "home_car_unsettled" end
        end
        return true
    end
    if scout.vehicle and scout.vehicle.state~="home_wait" and scout.vehicle.state~="abandoned" then
        home.blocker=scout.vehicle.blocker
        return false
    end
    local ready,reason=Home.arrivalReady(active)
    if ready then
        local finished,issue=E().finishHome()
        if not finished then home.blocker=string.sub(tostring(issue or "home_finish_busy"),1,96) end
        return true
    end
    if Home.continueApproach(active,reason) then return true end
    home.blocker=scout.phase=="awaiting_player" and reason or nil
    return false
end
function Home.stageRecall(active,player,reason,readyPoint)
    local previous=active.scout.home.recallPoint
    if active.scout.home.recalling and not active.scout.home.recallStopping and not active.scout.home.radioHold
        and (not readyPoint or previous and previous.x==readyPoint.x and previous.y==readyPoint.y and previous.z==readyPoint.z) then
        return true,"home_recall_staged"
    end
    local target=readyPoint or point(player)
    if not validPoint(target) then return false,"home_ground_floor_only" end
    local scout,home=active.scout,active.scout.home
    home.radioHold,home.radioHoldStopping,home.radioVehicleHold,home.radioHeldAt=nil,nil,nil,nil
    if player and reason=="recalled_nearby" then home.recallByRadio,home.radioRecallAt=nil,nil end
    active.integration=nil
    if scout.vehicle and scout.vehicle.state~="abandoned" then
        home.recalling,home.recallStopping,home.recallPoint=true,true,copy(target)
        local stopped,issue=false,"home_car_trip_invalid"
        if SC.ExpeditionCar and SC.ExpeditionCar.cancelField then stopped,issue=SC.ExpeditionCar.cancelField(active,U().nowMs()) end
        if stopped~=true then home.blocker=issue or "home_car_stopping" return true,"home_recall_staged" end
    end
    home.recallStopping=nil
    if active.testWaypoint then E().clearTestWaypoint(active.leader.actor) end
    if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(active.leader.actor,"home_recall") end
    home.recalling,home.recallPoint,home.blocker=true,target,nil
    active.homeBaseId=nil
    scout.phase,scout.returnPoint,scout.destination="inbound",copy(target),copy(target)
    scout.roadRoute,scout.road,scout.pause,scout.returnIndex,scout.travelBudget=nil,nil,nil,nil,nil
    scout.trail={point(active.leader.actor)}
    scout.legs,scout.replans,scout.lastStalledTarget,scout.legPlan=0,0,nil,nil
    active.technicalIssue,active.cohesionHold=nil,nil
    if scout.travelMode=="road" and SC.ExpeditionRoute then
        local route=SC.ExpeditionRoute.plan(active.leader.actor,target,true)
        if route and SC.ExpeditionRoute.verifyEntry(route,active.leader.actor) then
            scout.roadRoute,scout.road=route,SC.ExpeditionRoute.descriptor(route,"inbound")
        else scout.travelMode="straight" end
    end
    return true,"home_recall_staged"
end
function Home.debrief(active,reason)
    local names,casualties={},{}
    for _,member in ipairs(active.roster) do
        if member.actor and not U().isDead(member.actor)
            and (active.survivors==nil or active.survivors[member.id]) then names[#names+1]=member.name or member.id
        else casualties[#casualties+1]=member.name or member.id end
    end
    local gameTime=type(getGameTime)=="function" and getGameTime()
    local home,vehicle=active.scout.home,active.scout.vehicle
    return {kind="home",camp=Home.copyCamp(home.camp),names=names,casualties=casualties,
        homeStop=home.carStop and copy(home.carStop),vehicleName=home.carName,vehicleSqlId=home.vehicleSqlId,
        carSaveReceipt=home.carSaveReceipt and Home.copyCarReceipt(home.carSaveReceipt,home.vehicleSqlId),
        vehicleState=vehicle and vehicle.state,vehicleAt=vehicle and copy(vehicle.abandonedAt or vehicle.position),
        vehicleIssue=vehicle and vehicle.lastFailure and vehicle.lastFailure.reason,
        at=gameTime and call(gameTime,"getWorldAgeHours"),endReason=reason,
        integration=active.integration and SC.ExpeditionIntegration.copy(active.integration) or nil}
end
function Home.announceArrival(active)
    if active.homeArrivalAnnounced then return end
    active.homeArrivalAnnounced=true
    local report=Home.debrief(active,"home")
    if SC.Dialogue and SC.Dialogue.say then pcall(SC.Dialogue.say,active.leader.actor,"home.arrival") end
    local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0)
    if player and type(getText)=="function" then
        call(player,"setHaloNote",getText("UI_SC_HomeTrip_Arrived",table.concat(report.names,", ")))
    end
end
function Home.savedLegacy(saved)
    local scout=saved.scout
    if type(scout)~="table" or scout.kind~="home" or not Home.validState(scout.home)
        or (scout.vehicle==nil and scout.phase~="inbound" and scout.phase~="awaiting_player") or scout.site or scout.search or scout.wood
        or scout.observation or scout.fishingPreparation or scout.mapTarget
        or scout.turnHomeAtHour or scout.arriveByHour or scout.departureHour then return nil,"saved home itinerary is invalid" end
    local returning=scout.home.recalling and not scout.home.recallStopping
    local target=returning and scout.home.recallPoint or scout.home.camp.core
    if not validPoint(scout.destination) or not validPoint(scout.returnPoint)
        or scout.destination.x~=target.x or scout.destination.y~=target.y
        or scout.returnPoint.x~=target.x or scout.returnPoint.y~=target.y
        or saved.homeBaseId~=(not returning and scout.home.camp.id or nil)
        or saved.restockBaseDuty~=true then return nil,"saved home target is invalid" end
    local legacy={}
    for k,v in pairs(saved) do legacy[k]=v end
    legacy.scout={}
    for k,v in pairs(scout) do legacy.scout[k]=v end
    if scout.vehicle then
        local vehicle=SC.ExpeditionCar and SC.ExpeditionCar.copyDescriptor(scout.vehicle,saved.roster,saved.roster[1])
        if not vehicle or vehicle.field~=true or vehicle.leg~="home" or scout.home.vehicleSqlId~=vehicle.sqlId
            or not Home.sameStop(scout.home.carStop,vehicle.homeStop)
            or vehicle.home.x~=scout.home.camp.core.x or vehicle.home.y~=scout.home.camp.core.y
            or (scout.phase~=vehicle.state and scout.phase~="inbound" and scout.phase~="awaiting_player") then return nil,"saved home car is invalid" end
        legacy.scout.vehicle=vehicle
    end
    legacy.schema,legacy.scout.kind,legacy.scout.home=scout.vehicle and 6 or 5,"scout",nil
    return legacy
end
-- Persistence owns the snapshot/flush/detach transaction; native teardown is
-- allowed only after that exact full-roster transaction has committed.
function Home.releaseRemote(active,actors)
    if not Home.remoteAvailable() then return false,"home_safe_handover_unavailable" end
    if type(destroyPlayerData)~="function" then return false,"home_ui_teardown_unavailable" end
    local camp=active.scout.home.camp
    local area=camp.arrival
    local transaction=active.homeRelease
    if not transaction then
        if active.testWaypoint then E().clearTestWaypoint(active.leader.actor) end
        for _,actor in ipairs(actors) do
            if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor,"home_arrival") end
            if SC.Actor and SC.Actor.stop then SC.Actor.stop(actor) end
            if SC.ActionSupervisor and SC.ActionSupervisor.current and SC.ActionSupervisor.current(actor) then
                return false,"home_arrival_action_pending"
            end
            if SC.NativeActions and SC.NativeActions.activityStatus
                and SC.NativeActions.activityStatus(actor)~="none" then return false,"home_arrival_action_pending" end
            if ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue then
                local queue=ISTimedActionQueue.getTimedActionQueue(actor)
                if queue and (queue.current~=nil or type(queue.queue)=="table" and #queue.queue>0) then
                    return false,"home_arrival_action_pending"
                end
            end
        end
        local prepared,token=pcall(function()
            return SCSplitScreenProbe.prepareRemoteArrival(actors,area.x1,area.y1,area.x2,area.y2,area.z)
        end)
        if not prepared or token==nil then return false,"home_remote_prepare_failed" end
        transaction={token=token,actors=actors}
        active.homeRelease=transaction
    end
    if type(transaction.slotId)~="number" or transaction.slotId<2 then
        local slotOkay,slotId=pcall(function() return SCSplitScreenProbe.remoteArrivalSlotSqlId(transaction.token) end)
        if not slotOkay or type(slotId)~="number" or slotId<2 then
            if SC.Persistence.abortRemoteArrival(transaction.token) then active.homeRelease,active.integration=nil,nil end
            return false,"home_slot_identity_unavailable"
        end
        transaction.slotId=slotId
    end
    if active.scout.home.vehicleSqlId and not transaction.carAttached then
        local save=active.homeCarSave
        transaction.car=save and save.car
        if not save or not save.ticket or not save.receipt then
            if SC.Persistence.abortRemoteArrival(transaction.token) then active.homeRelease,active.integration=nil,nil end
            return false,"home_car_save_pending"
        end
        local attached,ready=pcall(function() return SCSplitScreenProbe.attachRemoteArrivalVehicleSave(transaction.token,save.ticket) end)
        if not attached or ready~=true then
            if SC.Persistence.abortRemoteArrival(transaction.token) then active.homeRelease,active.integration=nil,nil end
            return false,"home_car_save_failed"
        end
        transaction.carAttached=true
    end
    -- commitRemoteArrival must durably save integration as well as actor state
    -- before removing any native actors. No inventory outcome is inferred here.
    if not transaction.committed then
        local committed,issue=SC.Persistence.commitRemoteArrival(transaction.actors,camp,transaction.token,active.integration)
        if committed~=true then
            local aborted=SC.Persistence.abortRemoteArrival(transaction.token)
            if aborted then active.homeRelease,active.integration=nil,nil end
            return false,issue or "home_remote_save_failed"
        end
        transaction.committed=true
    end
    if not transaction.uiDetached then
        local torn=pcall(destroyPlayerData,active.leader.actor)
        if not torn then return false,"home_ui_teardown_failed" end
        transaction.uiDetached=true
    end
    if not transaction.nativeReleased then
        local okay,released=pcall(function() return SCSplitScreenProbe.releaseRemoteArrival(transaction.token) end)
        if not okay or released~=true then return false,"home_remote_release_failed" end
        transaction.nativeReleased=true
    end
    if not transaction.viewReleased then
        local restored,reason=SC.ViewSession.released("expedition",transaction.slotId)
        if restored~=true then return false,reason or "home_view_restore_pending" end
        transaction.viewReleased=true
    end
    local complete,reason=SC.Persistence.completeRemoteArrival(transaction.token)
    if complete~=true then return false,reason or "home_remote_completion_pending" end
    return true,transaction.slotId
end
function Home.describe(player)
    local active=Home.current()
    if not active then
        local debrief=E() and E().lastDebrief()
        return debrief and debrief.kind=="home" and {active=false,debrief=debrief,
            handover=debrief.integration and SC.ExpeditionIntegration.summary(debrief.integration) or nil} or nil
    end
    local scout,home=active.scout,active.scout.home
    local view=E().describeForPlayer(player)
    local observed=view and view.leaderVisible or false
    local knownView=SC.ViewSession and SC.ViewSession.owner and SC.ViewSession.owner()=="expedition"
        and type(getSpecificPlayer)=="function" and getSpecificPlayer(1)==active.leader.actor
    observed=observed or knownView
    local names={}
    for _,member in ipairs(active.roster) do names[#names+1]=member.name or member.id end
    local blocker=home.blocker or active.technicalIssue and active.technicalIssue.reason
        or scout.pause and scout.pause.reason
    local result={active=true,kind="home",tripId=active.radioSession,radio=Home.radioState(player),memberNames=names,names=names,leaderName=active.leader.name,
        observed=observed,state=observed and (blocker and "blocked" or home.recalling and "coming_back" or "walking") or "away",
        travelMode=scout.travelMode,at=home.departureHour,blocker=observed and blocker or nil,
        canRecall=Home.canRecall(player),physicallyNearby=Home.canRecall(player),members=view and view.members}
    if home.knowledge then
        result.lastSeenAt,result.lastSeenDistance,result.lastSeenPlace=home.knowledge.at,home.knowledge.distance,home.knowledge.place
    end
    if active.restoring then result.state="resuming" end
    if home.radioHold and not active.restoring then result.state=home.radioHoldStopping and "stopping" or "holding" end
    if observed then
        if scout.vehicle then
            result.vehicleState,result.vehicleName=scout.vehicle.state,home.carName
            result.vehicleIssue=scout.vehicle.blocker or scout.vehicle.lastFailure and scout.vehicle.lastFailure.reason
            result.homeStop=home.carStop and copy(home.carStop)
            if not blocker and not home.recalling and not home.radioHold and scout.vehicle.state~="abandoned" then result.state=scout.vehicle.state end
        end
        result.walkWaypoint=active.testWaypoint and copy(active.testWaypoint) or nil
        result.walkReason=home.blocker or active.technicalIssue and active.technicalIssue.reason
            or scout.pause and scout.pause.reason or scout.lastPlanFailure or scout.lastRoadFailure
        result.finalApproach=Home.finalApproachFor(active.leader.actor)
    end
    if observed then
        local p=point(active.leader.actor)
        result.distance=p and math.floor(math.sqrt((p.x-home.camp.core.x)^2+(p.y-home.camp.core.y)^2)+0.5)
    end
    return result
end
function Home.validDebrief(value)
    if type(value)~="table" or value.kind~="home" or not Home.validCamp(value.camp)
        or type(value.names)~="table" or #value.names<1 or #value.names>4
        or (value.endReason~="home" and value.endReason~="recalled_nearby" and value.endReason~="recalled_radio") then return false end
    for _,name in ipairs(value.names) do if type(name)~="string" or #name>80 then return false end end
    if value.casualties~=nil then
        if type(value.casualties)~="table" or #value.casualties>4 then return false end
        for _,name in ipairs(value.casualties) do if type(name)~="string" or #name>80 then return false end end
    end
    if value.vehicleSqlId~=nil and (type(value.vehicleSqlId)~="number" or value.vehicleSqlId<0
        or value.vehicleSqlId~=math.floor(value.vehicleSqlId) or type(value.vehicleName)~="string"
        or #value.vehicleName>128 or not SC.ExpeditionCar or not SC.ExpeditionCar.validFieldStop
        or not SC.ExpeditionCar.validFieldStop(value.homeStop,value.camp)) then return false end
    if value.carSaveReceipt~=nil and not Home.validCarReceipt(value.carSaveReceipt,value.vehicleSqlId) then return false end
    if value.at~=nil and (type(value.at)~="number" or value.at~=value.at or value.at<0 or value.at>10000000) then return false end
    return value.integration==nil or SC.ExpeditionIntegration and SC.ExpeditionIntegration.valid(value.integration)
end
function Home.copyDebrief(value)
    if not Home.validDebrief(value) then return nil end
    return {kind="home",camp=Home.copyCamp(value.camp),names=copy(value.names),at=value.at,
        casualties=value.casualties and copy(value.casualties),endReason=value.endReason,
        homeStop=value.homeStop and copy(value.homeStop),vehicleName=value.vehicleName,vehicleSqlId=value.vehicleSqlId,
        carSaveReceipt=value.carSaveReceipt and Home.copyCarReceipt(value.carSaveReceipt,value.vehicleSqlId),
        vehicleState=value.vehicleState,vehicleAt=value.vehicleAt and copy(value.vehicleAt),vehicleIssue=value.vehicleIssue,
        integration=value.integration and SC.ExpeditionIntegration.copy(value.integration) or nil}
end
function Home.dismiss() if E() and E().dismissHomeDebrief then E().dismissHomeDebrief() end end
function Home.isMemberId(id) local active=Home.current() return active and E().isMemberId(id) or false end
function Home.reasonText(reason,arg)
    if not reason then return "" end
    local keys={home_view_trip="NoViewTrip",home_view_expedition="NoViewExpedition",home_view_base_watch="NoViewBaseWatch",
        home_safe_handover_unavailable="SafeHandoverUnavailable",home_no_camp="NoCamp",home_already_home="AlreadyHome",
        home_too_many="TooMany",home_not_following="NotFollowing",home_out_of_earshot="OutOfEarshot",
        home_ground_floor_only="GroundFloorOnly",home_camp_ground_area_required="CampGroundAreaRequired",
        home_camp_changed="CampChanged",home_too_far="TooFar",home_member_unavailable="MemberUnavailable",
        home_leader_unavailable="LeaderUnavailable",home_no_members="NoMembers",home_member_seated="MemberSeated",
        home_not_recruited="NotRecruited",home_member_away="MemberAway",home_duplicate_member="DuplicateMember",
        home_walk_only="WalkOnly",home_delivery_queue_full="DeliveryQueueFull",home_member_not_home="WaitingForMembers",
        home_mixed_group="MixedGroup",home_finish_busy="FinishBusy",home_recall_first="RecallFirst",
        home_arrival_action_pending="FinishBusy",home_corpse_pending="CorpsePending",
        home_corpse_retention_failed="CorpseRetention",home_review_changed="ReviewChanged",
        home_cargo_unreadable="CargoUnreadable",home_cargo_too_many="CargoTooMany",
        home_car_not_ready="CarUnsettled",home_car_unsettled="CarUnsettled",home_car_unloading="CarUnloading",
        home_car_stopping="CarStopping",home_car_trip_invalid="CarUnavailable",home_stop_unavailable="NoStop",
        home_drive_too_far="DriveTooFar",car_unavailable="CarUnavailable",car_not_loaded="CarUnavailable",
        car_too_far="CarTooFar",player_car="PlayerInCar",player_aboard="PlayerInCar",
        car_moving="CarMoving",parking_not_stationary="CarMoving",too_few_seats="TooFewSeats",
        drive_stop_pending="CarStopping",
        seat_unavailable="SeatUnavailable",car_has_other_occupants="CarOccupied",
        field_driver_mismatch="DriverMismatch",
        driver_needs_key="NeedsKey",driver_needs_key_from_player="NeedsKey",key_owner_unavailable="NeedsKey",
        key_transfer_failed="KeyTransferFailed",key_transfer_unverified="KeyTransferFailed",
        fuel_insufficient="NoFuel",fuel_unreadable="FuelUnreadable",engine_unusable="EngineUnusable",
        wheel_unusable="WheelUnusable",engine_shutdown_pending="CarStopping",engine_shutdown_failed="CarStopping",
        home_parking_changed="ParkingChanged",road_routing_unavailable="NoDriveRoute",no_route="NoDriveRoute",
        road_access_not_loaded="RoadAccess",road_access_blocked="RoadAccess",road_access_vehicle_blocked="RoadAccess",
        road_access_unavailable="RoadAccess",road_access_too_far="RoadAccess",door_inaccessible="DoorInaccessible",
        car_identity_unavailable="CarUnavailable",car_orientation_unavailable="CarUnavailable",
        parking_footprint_unreadable="NoStop",parking_exit_blocked="DoorInaccessible",roadside_stop_not_reached="CarUnsettled",
        roadside_inside_camp="NoStop",parking_bay_blocked="NoStop",parking_bay_occupied="NoStop",
        parking_missing="NoStop",parking_not_loaded="CarUnsettled",parking_vehicle_unreadable="NoStop",
        parking_footprint_outside_area="NoStop",parking_road_end_unavailable="NoStop",
        parking_failed_drive_not_at_road_end="NoStop",parking_approach_out_of_range="NoStop",
        parking_approach_rejected="NoStop",parking_approach_failed="NoStop",parking_approach_blocked="NoStop",
        parking_approach_timeout="NoStop",parking_timeout="NoStop",parking_streaming_stalled="NoStop",
        parking_alignment_unavailable="NoStop",parking_alignment_limit="NoStop",parking_alignment_failed="NoStop",
        parking_alignment_timeout="NoStop",parking_alignment_pose_or_speed="NoStop",parking_alignment_displacement="NoStop",
        parking_alignment_room_changed="NoStop",parking_alignment_target_not_forward="NoStop",
        ["parking bay requires a clear forward approach"]="NoStop",
        ["parking approach requires a clear two-point route within 15 tiles"]="NoStop",
        ["parking car is missing"]="ParkingStopped",["companion is not driving"]="ParkingStopped",
        parking_requires_arrived_drive="ParkingStopped",drive_requires_release="ParkingStopped",
        drive_owner_lost="ParkingStopped",native_released="ParkingStopped",released="ParkingStopped",
        actor_released="ParkingStopped",left_driver_seat="ParkingStopped",not_driver="ParkingStopped",
        bridge_failure="ParkingStopped",driver_dead="ParkingStopped",survival_priority="ParkingStopped",
        faction_priority="ParkingStopped",player_order="ParkingStopped",engine_failed="EngineUnusable",
        team_unavailable="MemberUnavailable",player_unavailable="CarUnavailable",driving_unavailable="CarUnavailable",
        home_car_save_unavailable="CarSaveUnavailable",home_car_save_pending="CarSavePending",home_car_save_failed="CarSaveFailed",
        home_recall_car_not_retained="RecallCarNotRetained",
        home_radio_needed="RadioNeeded",home_radio_unavailable="RadioUnavailable",home_radio_busy="RadioBusy",
        home_radio_stale="RadioStale",home_radio_no_ack="RadioNoAck",home_radio_already_holding="RadioAlreadyHolding",
        home_radio_not_stopped="RadioNotStopped",home_radio_returning="RadioReturning",home_radio_holding="RadioHolding",
        home_radio_recall_stopping="RadioRecallStopping",
        home_radio_resumed="RadioResumed",home_radio_status="RadioStatusReply",home_radio_queued="RadioReceived"}
    local key="UI_SC_HomeTrip_"..(keys[reason] or "Unavailable")
    return type(getText)=="function" and getText(key,arg or "") or key
end
function Home.reset()
    local queued={}
    for request,proof in pairs(radioRequests) do queued[#queued+1]={request=request,active=proof.active} end
    for _,entry in ipairs(queued) do Home.cancelRadio(entry.active,entry.request) end
    cachedKey,cachedDraft=nil,nil radioRequests=setmetatable({}, {__mode="k"})
end
