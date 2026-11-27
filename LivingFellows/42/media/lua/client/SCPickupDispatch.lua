-- SPDX-License-Identifier: MIT
-- Read-only eligibility and real-car geometry for camp pickups.
LivingFellows = LivingFellows or {}
local SC=LivingFellows
local D={}
SC.PickupDispatch=D
local function call(object,name,...)
    if object == nil then return nil end
    return (SC.GameplayUtil.call(object,name,...))
end
function D.point(object)
    local x,y,z=SC.GameplayUtil.position(object)
    return x and {x=x,y=y,z=z} or nil
end
function D.ids(baseId)
    local result,seen={},{}
    for _,record in ipairs(SC.Registry.snapshot()) do
        local resident=SC.BaseLife.resident(record.id)
        if resident and resident.baseId==baseId then result[#result+1]=record.id seen[record.id]=true end
    end
    for _,record in ipairs(SC.Persistence.pendingCampRecords(baseId)) do
        if not seen[record.id] then result[#result+1]=record.id end
    end
    table.sort(result)
    return result
end
function D.drivers(ctx)
    local result={}
    for _,id in ipairs(ctx.candidateIds or {}) do
        local record=SC.Registry.byId(id)
        local actor=record and record.actor
        local resident=SC.BaseLife.resident(id)
        local state=actor and SC.Commands.peek(actor)
        local assessment=actor and SC.Medical and SC.Medical.assess and SC.Medical.assess(actor)
        if actor and resident and resident.baseId==ctx.camp.id and resident.duty==true
            and not SC.BaseLife.restriction(id) and state and state.recruited==true
            and state.order=="base_duty" and not state.expeditionMember
            and call(actor,"isDead")==false and call(actor,"isBridgeHealthy")==true
            and call(actor,"getVehicle")==nil and SC.BaseLife.isInside(actor)
            and not (assessment and (assessment.downed or assessment.urgent)) then
            result[#result+1]={id=id,actor=actor,name=SC.GameplayUtil.nameOf(actor)}
        end
    end
    table.sort(result,function(a,b)
        if a.id==ctx.preferredDriver then return true end
        if b.id==ctx.preferredDriver then return false end
        return a.id<b.id
    end)
    return result
end
function D.party(player)
    local result={}
    local p=D.point(player)
    if not p then return result end
    for _,record in ipairs(SC.Registry.snapshot()) do
        local actor=record.actor
        local state=actor and SC.Commands.peek(actor)
        local a=actor and D.point(actor)
        if a and state and state.recruited==true and state.rideWithPlayer~=false
            and (state.order=="follow" or state.order=="regroup")
            and state.followCarSqlId==nil and not state.expeditionMember
            and call(actor,"isDead")==false and call(actor,"getVehicle")==nil
            and (a.x-p.x)^2+(a.y-p.y)^2<=35^2 then
            result[#result+1]={id=record.id,actor=actor,name=SC.GameplayUtil.nameOf(actor)}
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function D.seats(car,driverId,party)
    local seats,playerSeat={[driverId]=0},nil
    local count=tonumber(call(car,"getMaxPassengers")) or 0
    if count<2 or count>32 then return nil,"too_few_seats" end
    local nextParty=1
    for seat=1,count-1 do
        if call(car,"isSeatInstalled",seat)==true and call(car,"getCharacter",seat)==nil then
            if not playerSeat then playerSeat=seat
            elseif party[nextParty] then seats[party[nextParty].id]=seat nextParty=nextParty+1 end
        end
    end
    if not playerSeat or nextParty<=#party then return nil,"too_few_seats" end
    return seats,playerSeat
end
function D.stillComing(id,car)
    local record=SC.Registry.byId(id)
    local actor=record and record.actor
    local state=actor and SC.Commands.peek(actor)
    return actor~=nil and state~=nil and state.recruited==true and state.rideWithPlayer~=false
        and (state.order=="follow" or state.order=="regroup") and state.followCarSqlId==nil
        and call(actor,"isDead")==false and (call(actor,"getVehicle")==nil or call(actor,"getVehicle")==car)
end
function D.plan(ctx,driver,car,stop)
    if SC.Vehicle.serviceClaim(car.vehicle) then return nil,"car_reserved" end
    local plan,reason=SC.ExpeditionCar.preflight({driver},car.zone.id,car.sqlId,stop)
    if not plan then return nil,reason end
    local seats,playerSeat=D.seats(car.vehicle,driver.id,ctx.party)
    if not seats then return nil,playerSeat end
    plan.seats,plan.playerSeat=seats,playerSeat
    return plan
end
function D.stopReady(ctx,car,target)
    if not SC.Vehicle.isStationary(car) then return false,"pickup_waiting_for_stop" end
    if call(car,"getDriver")~=ctx.actor then return false,"pickup_driver_changed" end
    local at=D.point(car)
    if not at or not target or (at.x-target.x)^2+(at.y-target.y)^2>36 then
        return false,"pickup_stop_too_far"
    end
    local exits=SC.Vehicle.safeExitSquares(car,ctx.playerSeat)
    if not exits or #exits<1 then return false,"pickup_door_blocked" end
    return true
end
function D.passengersEmpty(car)
    local count=tonumber(call(car,"getMaxPassengers")) or 0
    if count<2 or count>32 then return false end
    for seat=1,count-1 do if call(car,"getCharacter",seat)~=nil then return false end end
    return true
end
function D.route(ctx,car,target,withPassenger)
    local at=D.point(car)
    if not at then return nil,"car_position_unavailable" end
    local route,reason,native=SC.ExpeditionCar.planRoadAccess(car,at,target,true)
    if not route then return nil,reason end
    local tank=call(car,"getPartById","GasTank")
    local fuel=tonumber(call(tank,"getContainerContentAmount"))
    local used=math.max(0.0001,(ctx.plan.fuelRequired or 1)
        / math.max(1,((ctx.plan.route.roadLength or 0)*2+ctx.plan.access*2+30)))
    local returnLength=0
    if withPassenger and (target.x-ctx.plan.departure.x)^2+(target.y-ctx.plan.departure.y)^2>36 then
        local home,_,homeNative=SC.ExpeditionRoute.planFromPoint(target,ctx.plan.departure,true)
        if not home then return nil,"pickup_no_return_route" end
        if not homeNative or not tonumber(homeNative.entryX) or not tonumber(homeNative.entryY)
            or not tonumber(homeNative.exitX) or not tonumber(homeNative.exitY) then return nil,"road_access_unavailable" end
        returnLength=(home.roadLength or 0)
            +math.sqrt((target.x-homeNative.entryX)^2+(target.y-homeNative.entryY)^2)
            +math.sqrt((ctx.plan.departure.x-homeNative.exitX)^2+(ctx.plan.departure.y-homeNative.exitY)^2)
    end
    local length=(route.roadLength or 0)+math.sqrt((at.x-native.entryX)^2+(at.y-native.entryY)^2)
        +math.sqrt((target.x-native.exitX)^2+(target.y-native.exitY)^2)+returnLength+30
    if not fuel or fuel<length*used then return nil,"fuel_insufficient" end
    return {entry={x=native.entryX,y=native.entryY,z=0},
        exit={x=native.exitX,y=native.exitY,z=0},route=route}
end
return D
