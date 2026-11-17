-- SPDX-License-Identifier: MIT
local F,SC=PICKUP_RADIO,SurvivorCompanion
local R,E,check=SC.PickupRadio,SC.RadioEndpoints,PICKUP_RADIO.check
local function noHooks() for _ in pairs(F.hooks) do return false end return true end
local caller=R.caller(F.player,F.callerRadio)
local driver=R.driver(F.driver)
local station=E.station(F.player,F.callerPC)
local camp=E.campStation(F.player,F.campPC,"base-1")
check(caller and driver and station and camp,"four real endpoint contracts")
for _,source in ipairs({caller,station}) do
    for _,target in ipairs({driver,camp}) do
        local before=F.transmissions
        check(R.exchange(source,target,"request-1","request"),"endpoint request and acknowledgement")
        check(F.transmissions==before+2,"exactly one request and one acknowledgement")
        check(noHooks(),"temporary listener released")
    end
end
for _,fault in ipairs({"wrongGuid","wrongCodes","wrongDevice","distorted"}) do
    F[fault]=true
    check(not R.exchange(caller,driver,"request-1","cancel"),"uncorrelated reception cannot acknowledge: "..fault)
    check(noHooks(),"listener released after failed reception")
    F[fault]=nil
end
F.receive=false check(not R.exchange(caller,driver,"request-1","update"),"no device event means no delivery") F.receive=nil
local data=F.driverRadio.data
for _,change in ipairs({{"on",false},{"power",0},{"mic",true},{"channel",90000},{"volume",0},{"media",true},{"noTransmit",true}}) do
    local key,value=change[1],change[2]
    local prior=data[key] data[key]=value
    local before=F.transmissions
    check(not R.exchange(caller,driver,"request-1","request"),"unusable endpoint refused: "..key)
    check(before==F.transmissions,"no packet emitted through unusable hardware")
    data[key]=prior
end
local ctx={requestId="request-1",camp={id="base-1"},player=F.player,stations={camp}}
F.driver.equipped=nil
check(R.deliver(ctx,F.driver,station,"request",false),"camp EMMA locally relays to a driver without a handset")
F.driver.camp=false
check(not R.deliver(ctx,F.driver,station,"update",false),"camp relay cannot reach a departed driver without a handset")
F.driver.equipped=F.driverRadio
check(R.deliver(ctx,F.driver,station,"update",false),"departed driver can receive a direct handset update")
F.campPC.generation=2
check(not E.ready(camp),"remounted radio invalidates exact endpoint")
F.campPC.generation=1 F.campPC.borrowed=true
check(not E.ready(camp),"borrowed computer power does not run camp radio") F.campPC.borrowed=nil
F.campPC.locked=true
check(not E.ready(camp),"locking the camp computer invalidates its issued radio endpoint") F.campPC.locked=nil
F.player.x=1000
check(not E.ready(station),"caller cannot use a computer after walking away") F.player.x=100
F.driver.x,F.driver.y=3000,3000
check(not E.link(caller,driver),"range uses both actual transmitters") F.driver.x,F.driver.y=800,800
F.mutate=function() F.driverRadio.data.on=false end
check(not R.exchange(caller,driver,"request-1","cancel"),"hardware lost in native callback invalidates receipt")
F.mutate=nil F.driverRadio.data.on=true
local car={} F.player.vehicle=car F.driver.vehicle=car
check(R.deliver(ctx,F.driver,nil,"destination",true),"local car instruction needs no radio")
check(not E.validate(F.player,{kind="station",owner=F.player}),"forged endpoint refused")
check(noHooks(),"all contacts leave no listener")
SC_TEST_REPORT="PICKUP_RADIO_PASS checks="..tostring(F.checks)
