-- SPDX-License-Identifier: MIT
-- Production Integration owns every transfer; only native containers/poses are fixtures.
local SC, T = SurvivorCompanion, INTEGRATION_TEST
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
SC_TEST_REPORT = "Essential cargo delivery: " .. X.checks() .. " checks passed"
