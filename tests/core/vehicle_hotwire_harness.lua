-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Hotwire = SC.VehicleHotwire
local function check(value, label) assert(value, label) end
check(Hotwire.canHotwire(actor), "electrical 1 and mechanics 2 qualifies")
actor.mechanics = 1
check(not Hotwire.canHotwire(actor), "lower mechanics does not qualify")
actor.burglar = true
check(Hotwire.canHotwire(actor), "burglar qualifies without the skills")
actor.mechanics, actor.burglar = 2, false
check(Hotwire.request(actor, car, player), "qualified squad member accepts order")
check(Hotwire.step(actor, {}) and boards == 1 and actor.car == car,
    "driver boards through verified expedition car path")
check(Hotwire.step(actor, {}) and attempts == 0,
    "native hotwire waits for the timed action")
clock = clock + 4001
check(Hotwire.step(actor, {}) and attempts == 1,
    "native game hotwire attempted with companion electrical skill")
clock = clock + 1501
check(Hotwire.step(actor, {}) and car.hotwired and exits == 1
    and actor.car == nil and not Hotwire.active(actor),
    "success is read back and driver exits without any key")
check(not Hotwire.request(actor, car, player),
    "already hotwired car has no hotwire order")
car.hotwired = false
car.tryHotwire = function() attempts = attempts + 1 end
check(Hotwire.request(actor, car, player), "second attempt can be ordered")
Hotwire.step(actor, {})
Hotwire.step(actor, {})
clock = clock + 4001
Hotwire.step(actor, {})
clock = clock + 1501
check(not Hotwire.step(actor, {}) and attempts == 2 and exits == 2,
    "failed native roll is reported and companion exits")
print("vehicle hotwire checks passed")
