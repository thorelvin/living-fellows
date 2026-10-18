-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, INTEGRATION_TEST
local I = SC.ExpeditionIntegration
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, "expedition integration " .. checks .. ": " .. label)
end
local rootItem = T.item("root", "tools")
local bagItem = T.item("bagged", "food")
bagItem.safeFood = true
local unrelated = T.item("personal", "tools")
local bag = T.item("pack", "container")
bag.nested = T.container({ bagItem })
bag.nested.getContainingItem = function() return bag end
local a = T.actor("a", "Alice", { bag, unrelated })
local b = T.actor("b", "Bob", { rootItem })
T.storage("tools-1", "tools", {}, 4)
T.storage("food-1", "food", {}, 4)
local mission = { radioSession = "trip:1", homeBaseId = "camp:1",
    restockBaseDuty = false, commandSerials = { a = 0, b = 0 },
    roster = { { id = "a", name = "Alice", actor = a },
        { id = "b", name = "Bob", actor = b } },
    scout = { search = { request = { category = "useful", quantity = 2 },
        acquisitions = { { id = "bagged", itemType = bagItem.fullType,
            memberId = "a" }, { id = "root", itemType = rootItem.fullType,
            memberId = "b" } } } },
}
local record = I.create(mission)
check(I.valid(record), "created exact receipt ledger is valid")
I.refresh(record)
local status = I.summary(record)
check(status.requested == 2 and status.collected == 2
    and status.broughtBack == 2 and status.stored == 0
    and status.items[1].reason == nil,
    "returned counts precede verified storage")
check(select(2, I.update(record, a)) == "receipt_taken_from_bag"
    and bagItem.container == a.inventory,
    "nested bag item is staged by identity")
local resumed = I.copy(record)
I.reset()
check(I.valid(resumed) and select(2, I.update(resumed, a))
        == "expedition_supply_stored"
    and select(2, I.update(resumed, b)) == "expedition_supply_stored",
    "both real carriers deposit their own receipts")
status = I.summary(resumed)
check(status.stored == 2 and status.pending == 0 and T.moves == 3,
    "one bag stage and two deposits, no copied item")
check(unrelated.container == a.inventory,
    "unrelated personal gear is untouched")
check(I.copy(resumed) and I.valid(I.copy(resumed)),
    "delivery ledger survives save copy")

local movedBagItem = T.item("moved-bag-item", "food")
bag.nested.items = { movedBagItem }
movedBagItem.container = bag.nested
mission.radioSession = "trip:moved-bag"
mission.scout.search.acquisitions = { { id = movedBagItem.id,
    itemType = movedBagItem.fullType, memberId = "a" } }
local movedBag = I.create(mission)
I.refresh(movedBag)
local playerBag = T.container({ bag })
for index, item in ipairs(a.inventory.items) do
    if item == bag then table.remove(a.inventory.items, index) break end
end
check(select(2, I.update(movedBag, a)) == "delivery_not_ready"
    and movedBagItem.container == bag.nested
    and bag.container == playerBag,
    "a bag moved to someone else invalidates its cached carrier")
playerBag.items = {}
a.inventory.items[#a.inventory.items + 1] = bag
bag.container = a.inventory

local walking = T.item("walking", "food")
a.inventory.items[#a.inventory.items + 1] = walking
walking.container = a.inventory
mission.radioSession = "trip:remote"
mission.scout.search.acquisitions = { { id = "walking",
    itemType = walking.fullType, memberId = "a" } }
local remote = I.create(mission)
local inside = SC.BaseLife.isInside
SC.BaseLife.isInside = function(holder)
    return holder ~= a
end
I.refresh(remote)
check(I.summary(remote).broughtBack == 0 and not I.wants(remote, a),
    "an off-camp encounter neither credits nor diverts the carrier")
SC.BaseLife.isInside = inside
I.refresh(remote)
check(I.summary(remote).broughtBack == 1,
    "the exact item counts as brought back only at camp")

local fullItem = T.item("full", "tools")
a.inventory.items[#a.inventory.items + 1] = fullItem
fullItem.container = a.inventory
local general = T.storage("general-1", "general", {}, 4)
T.storages[1].container.capacity = 1
mission.radioSession = "trip:2"
mission.scout.search.acquisitions = { { id = "full",
    itemType = fullItem.fullType, memberId = "a" } }
local blocked = I.create(mission)
check(select(2, I.update(blocked, a)) == "matching_storage_full"
    and fullItem.container == a.inventory
    and #general.container.items == 0,
    "full dedicated storage never falls back to general")
T.now = T.now + 5001
local other = T.storage("tools-2", "tools", {}, 4)
check(select(2, I.update(blocked, a)) == "expedition_supply_stored"
    and fullItem.container == other.container,
    "another matching shelf unblocks the exact pending item")

local odd = T.item("odd", "crafting")
a.inventory.items[#a.inventory.items + 1] = odd
odd.container = a.inventory
mission.radioSession = "trip:3"
mission.scout.search.acquisitions = { { id = "odd",
    itemType = odd.fullType, memberId = "a" } }
local fallback = I.create(mission)
check(select(2, I.update(fallback, a)) == "expedition_supply_stored"
    and odd.container == general.container,
    "general is used only when dedicated category is unmarked")

local fresh = T.item("fresh-produce", "food")
fresh.fresh = true
a.inventory.items[#a.inventory.items + 1] = fresh
fresh.container = a.inventory
local fridge = T.storage("fresh-1", "fresh_food", {}, 4)
mission.radioSession = "trip:fresh"
mission.scout.search.acquisitions = { { id = fresh.id,
    itemType = fresh.fullType, memberId = "a" } }
check(select(2, I.update(I.create(mission), a))
        == "expedition_supply_stored"
    and fresh.container == fridge.container,
    "perishable expedition food goes to marked fresh storage")

local coat = T.item("coat", "clothing")
a.inventory.items[#a.inventory.items + 1] = coat
coat.container = a.inventory
local blockedCloset = T.storage("clothes-blocked", "clothing", {}, 4)
local openCloset = T.storage("clothes-open", "clothing", {}, 4)
local originalDeposit = SC.BaseWork.depositToStorage
SC.BaseWork.depositToStorage = function(actor, state, storage, container, item)
    if storage == blockedCloset then return false, "path_blocked:door_locked" end
    return originalDeposit(actor, state, storage, container, item)
end
mission.radioSession = "trip:alternate-access"
mission.scout.search.acquisitions = { { id = coat.id,
    itemType = coat.fullType, memberId = "a" } }
local alternateAccess = I.create(mission)
check(select(2, I.update(alternateAccess, a)) == "path_blocked:door_locked"
    and coat.container == a.inventory,
    "an inaccessible marked shelf retains the exact item")
T.now = T.now + 2501
check(select(2, I.update(alternateAccess, a))
        == "expedition_supply_stored"
    and coat.container == openCloset.container,
    "delivery retries the next matching shelf after an access failure")
SC.BaseWork.depositToStorage = originalDeposit

local cargo = T.item("cargo", "food")
T.car = { id = 77, locked = true, trunk = T.container({ cargo }) }
function T.car:getPartById() return { getItemContainer = function()
    return T.car.trunk end } end
mission.radioSession = "trip:4"
mission.scout.vehicle = { sqlId = 77 }
mission.scout.search.acquisitions = { { id = "cargo",
    itemType = cargo.fullType, memberId = "b" } }
local driven = I.create(mission)
local campCheck = SC.BaseLife.isInside
SC.BaseLife.isInside = function(holder)
    return holder ~= T.car
end
I.refresh(driven)
check(I.summary(driven).broughtBack == 0
    and select(2, I.update(driven, a)) == "delivery_not_ready"
    and cargo.container == T.car.trunk,
    "a worker at camp cannot credit or unload a car still away")
SC.BaseLife.isInside = campCheck
check(select(2, I.update(driven, a)) == "car_trunk_locked"
    and cargo.container == T.car.trunk
    and I.summary(driven).items[1].carrierId == nil,
    "locked trunk retains exact cargo")
T.car.locked = false
check(select(2, I.update(driven, b)) == "car_item_carried"
    and cargo.container == b.inventory,
    "any squad member can carry exact trunk cargo")
local carriedAfterLoad = I.copy(driven)
I.reset()
I.refresh(carriedAfterLoad)
check(I.summary(carriedAfterLoad).items[1].carrierKind == "trunk"
    and I.summary(carriedAfterLoad).items[1].carrierName == "Bob",
    "reload retains both the trunk origin and actual named carrier")
check(select(2, I.update(carriedAfterLoad, b))
        == "expedition_supply_stored"
    and I.summary(carriedAfterLoad).items[1].carrierKind == "trunk",
    "trunk origin remains credited after verified deposit")

T.minimums = { food = 1, water = 1, medicine = 0, ammunition = 0 }
local safe = T.item("safe-food", "food")
safe.safeFood = true
local rotten = T.item("rotten", "food")
T.storages[2].container.items = { safe, rotten }
safe.container, rotten.container = T.storages[2].container,
    T.storages[2].container
local water = T.item("water", "water")
water.safeWater = false
T.storage("water-1", "water", { water }, 4)
mission.radioSession = "trip:5"
mission.restockBaseDuty = true
mission.scout.vehicle = nil
mission.scout.search.acquisitions = {}
local restock = I.create(mission)
check(select(2, I.update(restock, a)) == "base_supply_taken"
    and safe.container == a.inventory,
    "safe food is physically withdrawn")
for _ = 1, 5 do I.update(restock, a) end
local member = I.summary(restock).members[1]
check(member.shortages.water == 1 and a.order == "base_duty"
    and rotten.container ~= a.inventory,
    "unsafe stock is skipped, shortage reported, duty resumed")

b.serial, b.order = 1, "follow"
check(I.wants(restock, b) == false
    and I.summary(restock).members[2].dutyReason == "new_player_order",
    "newer player order supersedes the planned duty change")
check(I.valid(I.copy(restock)), "restock and shortage state persist")

local dirty = T.item("dirty-med", "medicine", "Base.DirtyBandage")
local medical = T.storage("medical-1", "medical", { dirty }, 4)
T.minimums = { food = 0, water = 0, medicine = 1, ammunition = 0 }
mission.radioSession = "trip:dirty-med"
mission.commandSerials.a = a.serial
local medicalReturn = I.create(mission)
for _ = 1, 5 do I.update(medicalReturn, a) end
check(I.summary(medicalReturn).members[1].shortages.medicine == 1
    and dirty.container == medical.container,
    "dirty bandages are not counted as clean medical restock")

local wrongAmmo = T.item("wrong-ammo", "ammunition",
    "Base.ShotgunShells")
local rightAmmo = T.item("right-ammo", "ammunition",
    "Base.Bullets9mm")
local blockedAmmo = T.item("blocked-ammo", "ammunition",
    "Base.Bullets9mm")
local blockedAmmoShelf = T.storage("ammo-blocked", "ammunition",
    { blockedAmmo }, 4)
local ammoShelf = T.storage("ammo-1", "ammunition",
    { wrongAmmo, rightAmmo }, 4)
local originalWithdraw = SC.BaseWork.withdrawFromStorage
SC.BaseWork.withdrawFromStorage = function(actor, state, storage,
        container, item)
    if storage == blockedAmmoShelf then
        return false, "path_blocked:door_locked"
    end
    return originalWithdraw(actor, state, storage, container, item)
end
a.getPrimaryHandItem = function() return {
    isRanged = function() return true end,
    getAmmoType = function() return "Base.Bullets9mm" end,
} end
T.minimums = { food = 0, water = 0, medicine = 0, ammunition = 1 }
mission.radioSession = "trip:ammo"
local ammoReturn = I.create(mission)
for _ = 1, 3 do I.update(ammoReturn, a) end
check(select(2, I.update(ammoReturn, a)) == "path_blocked:door_locked"
    and blockedAmmo.container == blockedAmmoShelf.container,
    "restock keeps exact stock at an unreachable shelf")
check(select(2, I.update(ammoReturn, a)) == "base_supply_taken"
    and rightAmmo.container == a.inventory
    and wrongAmmo.container == ammoShelf.container
    and blockedAmmo.container == blockedAmmoShelf.container,
    "restock tries another shelf and takes only compatible ammunition")
SC.BaseWork.withdrawFromStorage = originalWithdraw
print("EXPEDITION_INTEGRATION_PASS checks=" .. checks)
