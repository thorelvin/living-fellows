-- SPDX-License-Identifier: MIT
-- Production Integration owns every transfer; only native containers/poses are fixtures.
local SC, T = LivingFellows, INTEGRATION_TEST
local I, X = SC.ExpeditionIntegration, assert(T.WoodDelivery)
local check = X.check

X.clear()
local original = X.log("essential:carried")
local worker = T.actor("hauler", "Hauler", {})
local bag = X.bagFor(worker, { original })
local store = T.storage("construction:home", "construction", {}, 1)
local receipt = X.create(worker, { original })
I.refresh(receipt)
check(I.summary(receipt).returned == 1 and I.summary(receipt).stored == 0,
    "arrival alone does not claim supplies were stored")
check(select(2, I.update(receipt, worker)) == "expedition_supply_stored"
    and original.container == store.container and #bag.items == 0 and T.moves == 1,
    "the original carried log reaches permitted storage exactly once")
check(not I.update(receipt, worker) and T.moves == 1 and I.summary(receipt).complete,
    "completed delivery cannot replay the transfer")

X.clear()
original = X.log("essential:full-store")
worker = T.actor("hauler", "Hauler", { original })
store = T.storage("construction:home", "construction", { T.item("existing", "construction") }, 1)
receipt = X.create(worker, { original })
local moved, why = I.update(receipt, worker)
check(not moved and why == "matching_storage_full" and original.container == worker.inventory
    and receipt.retryRemainingMs == 180000 and not I.wants(receipt, worker),
    "full storage preserves actual cargo and pauses instead of dropping or inventing delivery")
T.now = 60000
local saved = I.copy(receipt)
I.reset()
T.now, store.container.items = 0, {}
check(saved.retryRemainingMs == 120000 and saved.items[1].retryRemainingMs == 120000
    and not I.wants(saved, worker) and not I.settle(saved),
    "reload preserves the remaining delay and exact outstanding receipt")
T.now = 120001
check(I.wants(saved, worker) and select(2, I.update(saved, worker)) == "expedition_supply_stored"
    and original.container == store.container and T.moves == 1,
    "the persisted retry stores the same physical item once space becomes available")

X.clear()
original = X.log("essential:manual-retry")
worker = T.actor("hauler", "Hauler", { original })
receipt = X.create(worker, { original })
I.update(receipt, worker)
store = T.storage("construction:new", "construction", {}, 1)
check(not I.wants(receipt, worker) and I.retry(receipt) and I.wants(receipt, worker)
    and select(2, I.update(receipt, worker)) == "expedition_supply_stored"
    and original.container == store.container,
    "manual retry uses newly permitted storage without recreating cargo")
X.clear()
original = X.log("essential:roadside")
worker = T.actor("hauler", "Hauler", {})
local car = X.carFor(original)
store = T.storage("construction:home", "construction", {}, 1)
receipt = X.create(worker, { original }, { car = car })
I.refresh(receipt)
check(select(2, I.update(receipt, worker)) == "car_trunk_looting"
    and T.cargoOptions.action == "move_to_car_trunk"
    and T.cargoOptions.workCampOnly == true and T.cargoOptions.workReach == true,
    "roadside wood delivery uses the normal bounded camp-trunk route and its search lease")
I.update(receipt, worker)
check(select(2, I.update(receipt, worker)) == "expedition_supply_stored"
    and original.container == store.container and #car.trunk.items == 0,
    "roadside extraction and storage preserve the same physical log")

X.clear()
original = X.log("essential:overloaded-return")
worker = T.actor("hauler", "Hauler", {})
worker.overloaded, worker.load = true, 15.4
car = X.carFor(original)
car.x, car.y = 32, 10
local yard = X.yard()
receipt = X.create(worker, { original }, { car = car })
T.navigationReason = "pending"
check(select(2, I.update(receipt, worker)) == "storage_route_pending"
    and original.container == car.trunk and T.animations == 0,
    "the trunk retains the exact log while the distant route is being surveyed")
T.navigationReason = "unknown"
check(select(2, I.update(receipt, worker)) == "storage_route_unknown"
    and original.container == car.trunk and receipt.retryRemainingMs == 180000,
    "an unverified camp route preserves cargo and backs off")
T.navigationReason = "cross_floor_unverified"
check(I.retry(receipt) and select(2, I.update(receipt, worker)) == "matching_storage_unreachable"
    and original.container == car.trunk and T.animations == 0,
    "an unverified cross-floor candidate cannot authorize an overloaded pickup")
T.navigationReason = nil
check(I.retry(receipt) and select(2, I.update(receipt, worker)) == "car_trunk_looting",
    "a proven same-floor route beyond twenty tiles permits the overloaded pickup")
I.update(receipt, worker)
check(select(2, I.update(receipt, worker)) == "expedition_supply_stored"
    and yard.worlds[1]:getItem() == original and #car.trunk.items == 0,
    "the same log reaches the distant yard exactly once")

do
    X.clear()
    local log = X.log("essential:resting-carrier")
    local tired = T.actor("tired", "Tired", {})
    tired.stamina = 0
    local parked = X.carFor(log)
    local destination = T.storage("construction:rest", "construction", {}, 1)
    local delivery = X.create(tired, { log }, { car = parked })
    local utility = SC.GameplayUtil
    utility.characterStatValue = function(actor, _, fallback) return actor.stamina or fallback end
    utility.companionSeverelyExerted = function(actor) return (actor.stamina or 1) <= 0.25 end
    local traversal = SC.NativeTraversalActions
    SC.NativeTraversalActions = { poll = function()
        return "failed", "traversal_exited_without_destination", { phase = "failed" }
    end }
    check(select(2, I.update(delivery, tired)) == "wood_delivery_rest"
        and log.container == parked.trunk and T.animations == 0 and T.moves == 0,
        "an exhausted timber worker yields before walking to or opening the trunk")
    SC.NativeTraversalActions = traversal
    check(not I.wants(delivery, tired) and I.wants(delivery, tired, true)
        and I.summary(delivery).woodStaminaWaiting,
        "only the recovery controller can claim the waiting worker and the report names the wait")
    check(I.retry(delivery) and not I.wants(delivery, tired),
        "manual retry preserves the resting pause")

    local relief = T.actor("relief", "Relief", {})
    delivery.members[2] = { id = relief.id, name = relief.name, commandSerial = 0,
        restockIndex = 1, dutyDone = true, shortages = {} }
    check(I.wants(delivery, relief), "an exhausted crew member does not block another from unloading")
    tired.stamina = 0.30
    check(not I.wants(delivery, tired), "a small stamina gain does not immediately restart timber work")
    local resting, reason, target = I.update(delivery, tired)
    check(not resting and reason == "wood_delivery_rest" and target == 0.50
        and log.container == parked.trunk, "polling recovery keeps the same trunk log and stamina target")
    tired.stamina = 0.50
    check(I.wants(delivery, tired) and not I.summary(delivery).woodStaminaWaiting
        and select(2, I.update(delivery, tired)) == "car_trunk_looting",
        "recovery resumes the same delivery without waiting for a retry timer")
    I.update(delivery, tired)
    check(select(2, I.update(delivery, tired)) == "expedition_supply_stored"
        and log.container == destination.container and #parked.trunk.items == 0,
        "the exact reserved log is deposited after recovery")
    utility.characterStatValue, utility.companionSeverelyExerted = nil, nil
end

SC_TEST_REPORT = "Essential cargo delivery: " .. X.checks() .. " checks passed"
