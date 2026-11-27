-- SPDX-License-Identifier: MIT
require=function() end
local SC={}
LivingFellows=SC
local F={time=1000,trace={},deliver=true,drive=nil,view=nil,reservation=nil,missing=false}
PICKUP=F
function F.check(value,message) if not value then error("pickup: "..message) end F.checks=(F.checks or 0)+1 end
local function log(value) F.trace[#F.trace+1]=value end
local function object(x,y)
    local o={x=x,y=y,z=0}
    function o:getX() return self.x end
    function o:getY() return self.y end
    function o:getZ() return self.z end
    function o:isDead() return false end
    function o:isBridgeHealthy() return true end
    function o:getVehicle() return self.vehicle end
    function o:setHaloNote() end
    return o
end
F.player=object(150,100) F.driver=object(100,100) F.follower=object(151,100)
F.driver.id="sc-driver" F.follower.id="sc-follower"
F.car=object(100,100) F.car.seats={}
function F.car:getSqlId() return 77 end
function F.car:getDriver() return self.seats[0] end
function F.car:getCharacter(seat) return self.seats[seat] end
function F.car:getSeat(actor) for seat,item in pairs(self.seats) do if item==actor then return seat end end return -1 end
function F.car:getScriptName() return "Base.CarNormal" end
function F.car:getMaxPassengers() return 4 end
function F.car:isSeatInstalled() return true end
function F.car:isEngineRunning() return self.running==true end
function F.car:shutOff() self.running=false log("engine_off") end
function F.car:getPartById() return {getContainerContentAmount=function() return 40 end} end
function F.seat(actor,seat) F.car.seats[seat]=actor actor.vehicle=F.car end
function F.exit(actor) local seat=F.car:getSeat(actor) F.car.seats[seat]=nil actor.vehicle=nil end
function getSpecificPlayer(index) if index==0 then return F.player elseif index==1 then return F.viewActor end end
function isClient() return false end
function isServer() return false end
function destroyPlayerData() log("ui_release") end
SC.GameplayUtil={nowMs=function() return F.time end,
    position=function(o) if o then return o.x,o.y,o.z end end,
    call=function(o,name,...) if o and o[name] then return o[name](o,...),true end return nil,false end,
    nameOf=function(o) return o.id end,stop=function() log("actor_stop") return true end}
local records={{id="sc-driver",actor=F.driver},{id="sc-follower",actor=F.follower}}
SC.Registry={snapshot=function() return records end,isValidId=function(id) return id=="sc-driver" or id=="sc-follower" end,
    byId=function(id) if F.detached==id then return nil end
        for _,r in ipairs(records) do if r.id==id then return r end end end}
local states={[F.driver]={recruited=true,order="base_duty",commandSerial=4},
    [F.follower]={recruited=true,order="follow",commandSerial=3}}
SC.Commands={peek=function(actor) if actor and F.detached==actor.id then return nil end return states[actor] end,
    resumeBaseDutyIfUnchanged=function(id,serial,baseId) F.check(id=="sc-driver" and serial==4 and baseId=="base-1","camp duty identity") return true end}
F.states=states
F.camp={id="base-1",core={x=100,y=100,z=0},arrival={x1=90,y1=90,x2=110,y2=110,z=0},fingerprint="camp"}
SC.BaseLife={active=function() return {id="base-1"} end,
    resident=function(id) if id=="sc-driver" then return {baseId="base-1",duty=true} end end,
    restriction=function() return false end,isInside=function(o) return o and o.x<120 end}
SC.HomeTrip={captureCamp=function() return F.camp end,campUnchanged=function() return not F.changed end,
    validCamp=function(c) return type(c)=="table" and c.id=="base-1" end,
    validCarReceipt=function(r,id) return type(r)=="table" and r.sqlId==id end}
SC.Persistence={pendingCampRecords=function() return {} end,requestScheduledSave=function() log("save") return true end}
SC.Medical={assess=function() return {} end}
SC.Vehicle={loadedBySqlId=function(id) return not F.missing and id==77 and F.car or nil end,
    isStationary=function() return not F.moving end,safeExitSquares=function() return F.blockedDoor and {} or {{}} end,
    serviceClaim=function() return F.claim end,
    reserveService=function(id,car,seats,playerSeat) F.claim={id=id,car=car,seats=seats,playerSeat=playerSeat} return true end,
    releaseService=function() F.claim=nil log("car_release") return true end,
    exit=function(actor) F.exit(actor) return true end}
SC.ExpeditionCar={parkedCars=function() return {{vehicle=F.car,sqlId=77,zone={id="parking-1",x1=90,y1=90,x2=110,y2=110,z=0}}} end,
    preflight=function(records,zoneId,id,stop)
        if F.preflightReason then return nil,F.preflightReason end
        return {script="Base.CarNormal",departure={x=100,y=100,z=0},entry={x=100,y=100,z=0},exit=stop,
            zone={id="parking-1",x1=90,y1=90,x2=110,y2=110,z=0},access=0,fuelRequired=1,route={roadLength=50}}
    end,
    ensureDriverKey=function() return true end,
    planRoadAccess=function(car,from,target) return {roadLength=50},nil,{entryX=from.x,entryY=from.y,
        exitX=target.x+(F.roadStop and target.x==100 and 20 or 0),exitY=F.snapGoal and 100 or target.y} end,
    accessBetween=function() return true end,
    fitsParking=function() return not F.badParking,"parking_footprint_outside_area" end,
    boardMember=function(actor,order) F.seat(actor,order.seat) return true end}
SC.ExpeditionRoute={planFromPoint=function(from,target) return {roadLength=50},nil,
    {entryX=from.x,entryY=from.y,exitX=target.x,exitY=target.y} end}
SC.TaxiService={findRoadsideStop=function(at,search,accepts)
    local stop={x=at.x,y=at.y,z=0}
    local okay,reason=true,nil
    if accepts then okay,reason=accepts(stop) end
    if okay then return stop end
    return nil,reason
end}
SC.Driving={isDriving=function() return F.drive~=nil end,
    drive=function(actor,target,options)
        F.check(F.drive==nil,"prior driving lease released")
        F.check(options.passenger==nil or options.passenger==F.player and F.player.vehicle==F.car,"exact seated passenger")
        F.drive={target=target,options=options,phase="driving"} log("drive_start") return true
    end,
    jobStatus=function() return F.drive end,
    approach=function(actor,target)
        F.check(F.drive and F.drive.result=="arrived","parking keeps the arrived wheel lease")
        F.check((F.car.x-target.x)^2+(F.car.y-target.y)^2<=225,"parking uses bounded normal physics legs")
        F.drive={target=target,options=F.drive.options,phase="approaching"}
        F.approaches=(F.approaches or 0)+1
        return true
    end,
    stop=function() F.drive=nil F.moving=false log("drive_stop") return true end}
SC.ViewSession={owner=function() return F.view end,slotSqlId=function() return 2 end,
    released=function() F.view=nil F.viewActor=nil return true end}
SC.PickupJourney={available=function() return true end,
    reserve=function(ctx) F.reservation=ctx.requestId return true end,
    setContext=function() end,warm=function() return true end,
    acquire=function(ctx,actor) F.view="pickup" F.viewActor=actor log("view_acquire") return true end,
    closePreview=function() F.view=nil F.reservation=nil return true end,
    releaseLocal=function() return false,"pickup_primary_view_pending" end,
    releaseNear=function(ctx,actor,car)
        F.check(F.drive==nil,"empty lease stopped before view release")
        F.view=nil F.viewActor=nil log("view_release") return true
    end,
    carSaved=function(ctx,car)
        F.check(car==F.car and not F.missing,"fresh car save needs the loaded original car")
        ctx.carSaveReceipt={sqlId=77} return true
    end,
    retryArrival=function() return true end,
    restoreWatch=function() return true end,clearCarSave=function() end,
    releaseReservation=function() F.reservation=nil log("reservation_release") return true end,
    finishRemote=function(ctx,actor,car,integration)
        F.check(actor==F.driver,"frozen arrival retains its exact actor")
        local saved=SC.PickupService.exportRemoteArrival(integration)
        F.check(saved.state=="idle" and saved.active==nil and saved.outcome.driverId=="sc-driver","typed durable remote finish")
        if not ctx.release then
            ctx.release={actor=actor,token=22}
            F.detached=ctx.driverId
            return false,"remote_arrival_cleanup_pending"
        end
        F.check(F.detached==ctx.driverId,"frozen arrival continues after Registry detaches driver")
        F.view=nil F.viewActor=nil F.detached=nil ctx.release=nil return true
    end,
    prepareReset=function() F.view=nil return true end,reset=function() F.view=nil F.reservation=nil return true end}
SC.PickupRadio={caller=function(player,source) return source end,stations=function() return {} end,
    path=function() if F.deliver then return {{},{}} end return nil,"pickup_no_radio_contact" end,
    deliver=function() log("radio") return F.deliver,"pickup_no_radio_contact" end,
    localContact=function() return true end,reset=function() end}
SCSplitScreenProbe={canReleaseJoinedLeader=function() return F.near==true end,
    primaryRetainsHomeVehicle=function() return F.near==true end,
    persistJoinedLeaderSlotForReuse=function() return 2 end,releaseJoinedLeader=function() return true end}
function F.tick() F.time=F.time+250 SC.PickupService.tick(F.time) end
function F.arrive()
    F.check(F.drive~=nil,"drive exists before arrival")
    F.car.x,F.car.y=F.drive.target.x,F.drive.target.y
    F.drive.result="arrived" F.tick()
end
