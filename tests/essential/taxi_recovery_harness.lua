-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Booking, Cab, Fare, X = SC.TaxiBooking, SC.TaxiCab, SC.TaxiFares, assert(SC.TaxiTestFixture)
local check, player, radio, car = X.check, X.player, X.radio, X.vehicle
check(Booking.request(player, radio), "booking records one request")
local ready, token = Cab.prepareSpawn(Booking.current().generation)
check(ready and not Cab.prepareSpawn(Booking.current().generation)
    and select(2, Cab.recover()) == "cab_spawn_unresolved", "pending native spawn cannot create a second cab")
check(Cab.claimSpawn(car, token) and Fare.reserve(player, car, 250) and Fare.commit(car),
    "verified native cab completes its first free journey")
check(Booking.cancel(player, radio) and Booking.request(player, radio)
    and Cab.beginVisit(car, Booking.current().generation), "subsequent journey retains the same cab")

local original = X.item(202, "Base.Ring_Left_RingFinger_Gold")
X.glove.items.values = { original }
check(Fare.offer(player, car, original) and Fare.reserve(player, car, 250), "fare reserves the exact offered item")
X.glove.items.values = {}
check(select(2, Fare.commit(car)) == "fare_item_missing"
    and select(2, Fare.cancel(car)) == "refund_item_unresolved", "missing payment stays unresolved instead of charging or inventing a refund")
local booking, cab, receipt = Booking.export(), Cab.export(), Fare.export()
check(Booking.reset() and Cab.reset() and Fare.reset()
    and Booking.restore(booking) and Cab.restore(cab) and Fare.restore(receipt), "pending fare and cab identities survive reload")
check(Cab.recover() and Fare.current().phase == "refund_due", "reload recovers the original cab and exact outstanding receipt")
X.setLoaded(nil)
check(select(2, Cab.recover()) == "cab_unloaded_or_missing"
    and not Cab.prepareSpawn(Booking.current().generation), "an unloaded owned cab cannot authorize a replacement")
X.setLoaded(car)
X.glove.items.values = { original }
check(select(2, Fare.cancel(car)) == "fare_released" and original.data.LF_TaxiReceipt == nil
    and #X.glove.items.values == 1, "the returned original item settles its receipt once without duplication")
SC_TEST_REPORT = "Essential taxi identity and pending-payment recovery passed"
