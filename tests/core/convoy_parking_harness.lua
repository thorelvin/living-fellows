-- SPDX-License-Identifier: MIT
-- Real convoy, driving lease and commands; native motion/seat outcomes are doubles.
local SC, T = SurvivorCompanion, SC_DRIVING_TEST
local C, D = SC.Convoy, SC.Driving
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
local actor = T.actor("parking-driver")
local car = actor.vehicle
car.sqlId = 933
function car:getSqlId() return self.sqlId end
local lead = {x=125,y=100,z=0}
local player = {x=125,y=100,z=0,vehicle=lead}
function player:getVehicle() return self.vehicle end
function player:setHaloNote() end
function lead:getDriver() return player.vehicle==lead and player or nil end
getPlayer = function() return player end
SC.Vehicle.loadedBySqlId = function(id) return id==933 and car or nil end
SC.Registry.living = function() return {actor} end
local originalExit, originalStationary = SC.Vehicle.exit, SC.Vehicle.isStationary
local originalFollow = SCBridge.driveFollowVehicle
local start = SC_TEST_CLOCK + 100000
local function tick(at) SC_TEST_CLOCK=at; C.tick(at) end
local function begin()
    D.release(actor,"fixture_reset"); C.reset()
    SC.Vehicle.exit, SC.Vehicle.isStationary = originalExit, originalStationary
    SCBridge.driveFollowVehicle = originalFollow
    T.stopRejected = false
    actor.vehicle, car.driver, car.x, car.y = car, actor, 100, 100
    player.vehicle = lead
    actor.data.SC_FollowCarSqlId = 933
    SC.Commands.reset(actor); C.activate(actor)
    check(C.step(actor,player,{})==true and D.isDriving(actor),"fresh exact follow-car owner")
    tick(start)
    player.vehicle=nil
    tick(start+500)
end

begin()
local exits=T.exits
check(D.isDriving(actor) and actor.vehicle==car and T.exits==exits,
    "player exit does not abandon a distant stationary follow car")
check(T.convoyFollow.leader==lead and T.convoyFollow.speed<=20,
    "the remembered player car remains the bounded parking target")
local passenger=T.actor("parking-passenger")
passenger.vehicle=car
SC.Registry.living=function() return {actor,passenger} end
check(C.ownsSeat(passenger,car,player),"overflow passenger remains seated during parking")
car.x=118
tick(start+1000)
check(D.isDriving(actor) and actor.vehicle==car,"progress alone cannot substitute for verified spacing")
T.native[actor].convoyParked=true
tick(start+1250)
check(not D.isDriving(actor) and actor.vehicle==nil and T.exits==exits+1,
    "verified spacing releases the wheel and exits")
check(not C.ownsSeat(passenger,car,player),"passenger can exit after the driver parks")
check(C.step(actor,player,{})==nil,"parked driver resumes ordinary foot following")

start=start+30000; begin(); exits=T.exits
tick(start+8250)
check(T.exits==exits,"unreachable grace period is not shortened by an old driving timestamp")
tick(start+8500)
check(T.exits==exits+1 and not D.isDriving(actor),"eight seconds without progress exits safely")
check(SC.Commands.peek(actor).followCarSqlId==933,"parking timeout retains the car choice for the next drive")

start=start+30000; begin(); exits=T.exits
for pulse=1,39 do
    car.x=car.x+0.6
    tick(start+500+pulse*500)
end
check(T.exits==exits,"small real movements keep the stall clock alive before the absolute limit")
car.x=car.x+0.6; tick(start+20500)
check(T.exits==exits+1,"twenty seconds is an absolute parking limit even with continuous movement")

start=start+30000; begin(); exits=T.exits
SCBridge.driveFollowVehicle=function() return false end
tick(start+1000); tick(start+8500)
check(T.exits==exits+1 and not D.isDriving(actor),"rejected or unloaded lead route cannot hold the driver forever")

start=start+30000; begin(); exits=T.exits
SC.Vehicle.isStationary=function() return false end
tick(start+8500)
check(T.exits==exits and actor.vehicle==car,"timeout never ejects a rolling driver")
SC.Vehicle.isStationary=originalStationary
tick(start+8750)
check(T.exits==exits+1,"timeout exit resumes once the car really stops")

start=start+30000; begin(); exits=T.exits
T.stopRejected=true
tick(start+8500)
check(T.exits==exits and D.isDriving(actor),"failed native release preserves the seat and lease")
T.stopRejected=false
tick(start+8750)
check(T.exits==exits+1 and not D.isDriving(actor),"safe release retries after a rejected stop")

start=start+30000; begin(); exits=T.exits
local blockedExits=0
SC.Vehicle.exit=function() blockedExits=blockedExits+1; return false,"no_safe_exit" end
tick(start+8500); tick(start+8750)
check(blockedExits==2 and T.exits==exits and actor.vehicle==car and not D.isDriving(actor),
    "a blocked door remains stopped and retries; timeout does not fabricate an exit")
SC.Vehicle.exit=originalExit
tick(start+9000)
check(T.exits==exits+1,"a later real exit releases the parked driver")

start=start+30000; begin(); exits=T.exits
player.vehicle=lead; tick(start+7000)
player.vehicle=nil; tick(start+7500)
tick(start+10000)
check(T.exits==exits and D.isDriving(actor),"player reboarding cancels the old dismount deadline")
tick(start+15500)
check(T.exits==exits+1,"a later player exit receives a fresh bounded parking attempt")

start=start+30000; begin(); exits=T.exits
C.reset()
check(C.step(actor,player,{})==nil and C.ownsSeat(actor,car,player),
    "restored seat with no remembered lead remains safe while its timeout starts")
tick(start+1000); tick(start+9000)
check(T.exits==exits+1 and not D.isDriving(actor),
    "a restored driver without a remembered player car cannot wait indefinitely")

C.reset()
SC_TEST_REPORT="CONVOY_PARKING_HARNESS_PASS checks="..checks
print(SC_TEST_REPORT)
