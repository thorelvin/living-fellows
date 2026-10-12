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
check(events[#events - 2] == "attempt" and events[#events - 1] == "exit"
    and events[#events] == "vehicle.hotwire.success",
    "success line is spoken only after the verified vehicle exit")
check(not Hotwire.request(actor, car, player),
    "already hotwired car has no hotwire order")
car.hotwired = false
car.tryHotwire = function()
    events[#events + 1] = "attempt"
    attempts = attempts + 1
end
check(Hotwire.request(actor, car, player), "second attempt can be ordered")
Hotwire.step(actor, {})
Hotwire.step(actor, {})
clock = clock + 4001
Hotwire.step(actor, {})
clock = clock + 1501
exitBlocked = true
check(Hotwire.step(actor, {}) and attempts == 2 and exits == 1
    and Hotwire.active(actor) and events[#events] == "attempt",
    "blocked door holds the result without speaking")
exitBlocked = false
check(not Hotwire.step(actor, {}) and exits == 2
    and events[#events - 1] == "exit"
    and events[#events] == "vehicle.hotwire.failure",
    "failed native roll is spoken after companion exits")

car.tryHotwire = function(self)
    attempts = attempts + 1
    self.hotwired = true
end
check(Hotwire.request(actor, car, player), "third attempt starts")
Hotwire.step(actor, {})
Hotwire.step(actor, {})
clock = clock + 4001
Hotwire.step(actor, {})
clock = clock + 1501
exitBlocked = true
local saidBefore = #events
check(Hotwire.step(actor, {}) and Hotwire.active(actor),
    "successful attempt waits for a blocked exit")
clock = clock + 15001
check(Hotwire.step(actor, {}) and Hotwire.active(actor)
    and player.note:find("Car hotwired", 1, true)
    and #events == saidBefore,
    "exit timeout reports the verified result without speaking from the car")
exitBlocked = false
check(Hotwire.step(actor, {}) and actor.car == nil
    and events[#events] == "vehicle.hotwire.success"
    and not Hotwire.active(actor),
    "the later exit delivers the result line exactly once")
print("vehicle hotwire checks passed")
