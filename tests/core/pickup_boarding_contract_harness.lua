-- SPDX-License-Identifier: MIT
-- Exercise both production boarding layers. Stop at the final revalidation;
-- no mock entry can conceal a lost exact-passenger permission.
local SC=SurvivorCompanion
local driver,caller,car={},{},{}
local checks,calls,expected=0,0,caller
local function check(value,message)
    checks=checks+1 assert(value,message)
end
SC.Registry.idOf=function(actor) return actor==driver and "sc-driver" end
SC.ExpeditionPrototype=nil
SC.Vehicle.isNativeSeated=function() return false end
SC.Vehicle.beginBoarding=function() return {} end
SC.Vehicle.failTransaction=function() end
SC.Vehicle.preflightBoard=function(actor,vehicle,seat,allowDriver,passenger)
    calls=calls+1
    check(actor==driver and vehicle==car and seat==0 and allowDriver==true,
        "both production layers revalidate the exact driver and car")
    check(passenger==expected,"both production layers retain the exact booked passenger")
    if calls%2==1 then return {actorId="sc-driver",vehicle=car,seat=0} end
    return nil,"final_revalidation_reached"
end
for _,booked in ipairs({true,false}) do
    expected=booked and caller or nil
    local okay,reason=SC.ExpeditionCar.boardMember(driver,
        {car=car,seat=0,sqlId=77,permittedPassenger=expected},{})
    check(not okay and reason=="final_revalidation_reached","final native boarding check remains authoritative")
end
check(calls==4,"initial and final checks run for both booked and ordinary boarding")
SC_TEST_REPORT="PICKUP_BOARDING_CONTRACT_PASS checks="..checks
