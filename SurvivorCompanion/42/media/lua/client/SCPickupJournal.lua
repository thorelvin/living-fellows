-- SPDX-License-Identifier: MIT
SurvivorCompanion = SurvivorCompanion or {}
local SC=SurvivorCompanion
local S=SC.PickupService
local phases={acquire=true,acquire_outbound=true,acquire_return=true,board_driver=true,
    outbound=true,pickup_handoff=true,waiting_board=true,ride_start=true,ride=true,
    drop_wait=true,returning=true,parked=true,exit_driver=true,camp_arrival=true,finish=true,held=true}
local function integer(n,low,high)
    return type(n)=="number" and n==math.floor(n) and n>=low and n<=high
end
local function number(n,low,high) return type(n)=="number" and n==n and n>=low and n<=high end
local function text(value,max) return type(value)=="string" and #value>0 and #value<=max end
local function point(p)
    return type(p)=="table" and number(p.x,0,30000) and number(p.y,0,30000) and p.z==0
end
local function position(p)
    return type(p)=="table" and number(p.x,0,30000) and number(p.y,0,30000) and integer(p.z,-32,31)
end
local function id(value) return SC.Registry.isValidId(value) end
local function pair(value)
    return value==nil or type(value)=="table" and id(value.driverId) and integer(value.carSqlId,1,2147483647)
end
local function validOutcome(value)
    return value==nil or type(value)=="table" and text(value.requestId,128) and id(value.driverId)
        and integer(value.carId,1,2147483647) and (value.result=="ended" or value.result=="driver_lost"
            or value.result=="returned" and SC.HomeTrip.validCarReceipt(value.carSaveReceipt,value.carId))
end
local function validActive(a)
    if type(a)~="table" or not text(a.requestId,128) or not phases[a.phase] or not id(a.driverId)
        or not integer(a.carSqlId,1,2147483647) or not integer(a.commandSerial,0,10000000)
        or not SC.HomeTrip.validCamp(a.camp) or not point(a.pickup) or not position(a.restorePoint)
        or not integer(a.playerSeat,1,31) or type(a.seats)~="table" or a.seats[a.driverId]~=0
        or type(a.candidateIds)~="table" or #a.candidateIds>512
        or (a.destination~=nil and not point(a.destination))
        or (a.slotSqlId~=nil and not integer(a.slotSqlId,2,2147483647))
        or (a.driverDead~=nil and type(a.driverDead)~="boolean")
        or (a.cancelled~=nil and type(a.cancelled)~="boolean")
        or (a.relinquished~=nil and type(a.relinquished)~="boolean")
        or (a.resumePhase~=nil and not phases[a.resumePhase])
        or (a.afterBoard~=nil and not phases[a.afterBoard]) then return false end
    local seen={[a.playerSeat]=true}
    local count=0
    for actorId,seat in pairs(a.seats) do
        count=count+1
        if count>31 or not id(actorId) or not integer(seat,0,31) or seen[seat] then return false end
        seen[seat]=true
    end
    for _,actorId in ipairs(a.candidateIds) do if not id(actorId) then return false end end
    local p=a.plan
    if type(p)~="table" or not text(p.script,128) or not point(p.departure) or not point(p.entry)
        or not point(p.exit) or type(p.zone)~="table" or p.zone.z~=0 or not text(p.zone.id,128)
        or not number(p.zone.x1,0,30000) or not number(p.zone.y1,0,30000)
        or not number(p.zone.x2,p.zone.x1,30000) or not number(p.zone.y2,p.zone.y1,30000)
        or not number(p.access,0,1000) or not number(p.fuelRequired,0,10000)
        or type(p.route)~="table" or not number(p.route.roadLength,0,1000000) then return false end
    if a.carSaveReceipt and not SC.HomeTrip.validCarReceipt(a.carSaveReceipt,a.carSqlId) then return false end
    return true
end
function S.export()
    local active,outcome,preferred,sequence=S.journalState()
    local saved={schema=1,state=active and "active" or "idle",sequence=sequence,
        outcome=S.copy(outcome),preferred=S.copy(preferred)}
    if active then
        local a={}
        for _,key in ipairs({"requestId","phase","driverId","carSqlId","commandSerial","playerSeat",
            "seats","candidateIds","camp","pickup","destination","resumePhase","afterBoard",
            "cancelled","slotSqlId","watchPaused","watchWarning","carSaveReceipt","reason","relinquished"}) do a[key]=S.copy(active[key]) end
        a.driverDead=active.deadActor~=nil or active.actor and active.actor:isDead()==true or false
        a.restorePoint=SC.PickupDispatch.point(active.actor) or S.copy(active.restorePoint) or S.copy(active.plan.departure)
        a.restorePoint.z=math.floor(a.restorePoint.z)
        local p=active.plan
        a.plan={script=p.script,departure=S.copy(p.departure),entry=S.copy(p.entry),exit=S.copy(p.exit),
            zone=S.copy(p.zone),access=p.access,fuelRequired=p.fuelRequired,route={roadLength=p.route.roadLength}}
        saved.active=a
    end
    return saved
end
function S.exportRemoteArrival(integration)
    local a,_,preferred,sequence=S.journalState()
    if not a or a.phase~="finish" or type(integration)~="table"
        or integration.requestId~=a.requestId or integration.driverId~=a.driverId
        or integration.carId~=a.carSqlId or integration.result~="returned" or not validOutcome(integration) then
        return nil,"pickup_arrival_mismatch"
    end
    return {schema=1,state="idle",sequence=sequence,slotSqlId=a.slotSqlId or SC.ViewSession.slotSqlId(),outcome=S.copy(integration),
        preferred={driverId=a.driverId,carSqlId=a.carSqlId}}
end
function S.restore(saved)
    if S.current() or S.previewCurrent() then return false,"pickup_already_active" end
    if saved==nil then return true end
    if type(saved)~="table" or saved.schema~=1 or not integer(saved.sequence,0,10000000)
        or saved.slotSqlId~=nil and not integer(saved.slotSqlId,2,2147483647)
        or not validOutcome(saved.outcome) or not pair(saved.preferred)
        or saved.state~="idle" and saved.state~="active"
        or saved.state=="idle" and saved.active~=nil
        or saved.state=="active" and not validActive(saved.active) then return false,"invalid_saved_pickup" end
    if saved.active and saved.active.driverDead==true then
        local a=saved.active
        return S.setJournal(nil,{requestId=a.requestId,driverId=a.driverId,carId=a.carSqlId,result="driver_lost"},
            S.copy(saved.preferred),saved.sequence)
    end
    return S.setJournal(S.copy(saved.active),S.copy(saved.outcome),S.copy(saved.preferred),saved.sequence)
end
return S
