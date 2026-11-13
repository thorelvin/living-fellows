-- SPDX-License-Identifier: MIT
-- One compact scenario group: production ownership, scans, projections and receipts.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check, U = f.check, SC.GameplayUtil
local commandViews, visuals, poses, durations, lines, pacing = {}, {}, {}, {}, {}, {}
local originalMove, originalDialogue = U.move, SC.Dialogue.say
SC.Commands.peek = function(actor) return commandViews[actor] end
SC.Performance.preciseNowMs = function() return f.clock end
SC.Config._values.scavengeLootReactionChancePercent = 100
SC.Dialogue.say = function(actor, topic, _, params)
    lines[#lines + 1] = { actor = actor, topic = topic, name = params[1] }
    return true, params[1]
end
SC.NativeActions = {
    dispatch = function() return true end,
    visualStatus = function(actor) return visuals[actor] or "none", "loot_container" end,
    clearVisual = function(actor) visuals[actor] = nil end,
    cancelVisualOwned = function(actor) visuals[actor] = nil return true end,
    stopDirect = function(actor) actor.moving = false return true end,
}
U.move = function(actor, mode, intent)
    if intent and intent.action == "loot_container" then
        if pacing[actor] then return false, "action_pacing:logistics_deposit" end
        poses[actor] = (poses[actor] or 0) + 1
        durations[actor], visuals[actor] = intent.durationTicks, "active"
        return true, "looting"
    end
    return originalMove(actor, mode, intent)
end
local safe = { snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 } }
local sequence = 0
local function fixture(items)
    sequence = sequence + 1
    local actor = f.actor("loot-batch-" .. sequence, -50 + sequence * 2, -30, {})
    f.registry[actor.id] = actor
    local source, owner = f.containerObject(actor.square, items)
    commandViews[actor] = { recruited = true, scavenge = true, order = "stay",
        commandSerial = 1, scavengeTargetContainer = source }
    return actor, source, owner
end
local function nails(count)
    local items = {}
    for index = 1, count do items[index] = f.item("Base.Nails", "Material", { weight = 0.05 }) end
    return items
end
local function tick(actor)
    f.clock = f.clock + 100
    return SC.Encounter.tryScavenge(actor, nil, safe)
end
local function animate(actor)
    for _ = 1, 100 do
        tick(actor)
        local state = SC.Encounter.peek(actor)
        if state.task and state.task.phase == "animate" then return state.task end
    end
    error("batch did not reach its owned animation")
end
local function complete(actor)
    visuals[actor] = "completed"
    local handled, why = tick(actor)
    check(handled and why == "looted", "completed native visual commits its batch: " .. tostring(why))
end

local actor, source, owner = fixture(nails(5))
local task = animate(actor)
check(#task.takeList == 5 and #actor.inventory.items == 0 and durations[actor] == 300,
    "five planned items remain in the cupboard until one lengthened native animation completes")
local oldPicker, shelfRefreshes = ItemPicker, 0
ItemPicker = { updateOverlaySprite = function(parent)
    if parent == owner then shelfRefreshes = shelfRefreshes + 1 end
end }
complete(actor)
ItemPicker = oldPicker
check(#source.items == 0 and #actor.inventory.items == 5 and poses[actor] == 1,
    "one visual transfers all five exact objects")
check(shelfRefreshes == 1, "a batch refreshes the emptied shelf once after exact transfers settle")
check(SC.Encounter.peek(actor).lastLoot.verified and actor.modData.LF_LootReturnPending,
    "verified pickups retain per-item evidence and a home-delivery obligation")

actor, source = fixture(nails(12))
animate(actor); complete(actor)
check(#source.items == 6 and #actor.inventory.items == 6, "first batch stops at the profiled six-item ceiling")
animate(actor); complete(actor)
check(#source.items == 0 and #actor.inventory.items == 12 and poses[actor] == 2,
    "twelve pickups use two owned commits without another walk")

actor, source = fixture(nails(5))
task = animate(actor)
local taken = task.takeList[1].item
source:Remove(taken); f.player.inventory:AddItem(taken)
complete(actor)
check(#actor.inventory.items == 4 and f.player.inventory:contains(taken),
    "the player taking the first planned item does not discard the remaining four")

actor, source = fixture(nails(5))
animate(actor)
SC.Encounter.cancelScavenge(actor, "new_command")
check(#source.items == 5 and #actor.inventory.items == 0 and not SC.ActionSupervisor.current(actor),
    "interruption releases claims and transfers nothing before visual proof")

-- Unreadable native APIs must not masquerade as an empty bin or bag.
actor, source, owner = fixture(nails(1))
function owner:getContainerCount() error("native compartment unavailable") end
local visit = SC.ScavengeLoot.new(actor, owner, source)
local scanned, readReason = SC.ScavengeLoot.scan(visit, function() return 100, "construction", 1 end)
check(not scanned and readReason == "source_unreadable" and not visit.complete,
    "failed compartment access cannot silently fall back to primary-only discovery")
local unreadable = f.inventory(nails(1))
function unreadable:getItems() error("native contents unavailable") end
local unreadableBag = f.item("Base.Bag_DuffelBag", "Container", { nestedInventory = unreadable })
actor, source, owner = fixture({ unreadableBag })
visit = SC.ScavengeLoot.new(actor, owner, source)
scanned, readReason = SC.ScavengeLoot.scan(visit, function() return 100, "container", 1 end)
check(not scanned and readReason == "source_unreadable" and #SC.ScavengeLoot.rows(visit) == 0,
    "an unreadable filled bag is neither empty nor eligible cargo")

-- All compartments share one visit; one-level bag contents share the same budget.
local bandage = f.item("Base.Bandage", "Medical", { weight = .05 })
local nested = f.inventory({ bandage })
local bag = f.item("Base.Bag_DuffelBag", "Container", { nestedInventory = nested, weight = .5 })
local forbidden = f.item("Base.Nails", "Material", { weight = .05 })
local deep = f.item("Base.Bag_Schoolbag", "Container", { nestedInventory = f.inventory({ forbidden }) })
nested:AddItem(deep)
actor, source, owner = fixture({ bag })
local freezer = f.inventory(nails(1)); freezer.owner = owner
function owner:getContainerCount() return 2 end
function owner:getContainerByIndex(index) return index == 0 and source or freezer end
task = animate(actor)
check(#task.takeList == 2, "freezer and accessible bag contents join the same batch")
local rival = fixture({})
rival.square = actor.square
commandViews[rival].scavengeTargetContainer = freezer
for _ = 1, 4 do tick(rival) end
check(not SC.ActionSupervisor.current(rival) and #rival.inventory.items == 0,
    "another compartment cannot acquire the same physical fridge during an owned batch")
complete(actor)
check(actor.inventory:contains(bandage) and #freezer.items == 0 and source:contains(bag)
        and nested:contains(deep) and deep.nestedInventory:contains(forbidden),
    "filled bag shells and depth-two contents stay behind, without duplicate pickups")

local inside = f.item("Base.Bandage", "Medical", { weight = .05 })
bag = f.item("Base.Bag_DuffelBag", "Container", { nestedInventory = f.inventory({ inside }) })
actor, source = fixture({ bag })
animate(actor)
source:Remove(bag); f.player.inventory:AddItem(bag)
visuals[actor] = "completed"; tick(actor)
check(#actor.inventory.items == 0 and bag.nestedInventory:contains(inside),
    "a moved parent bag cannot be looted from the player's inventory")

-- Source permissions are checked again at commit, including nested items.
actor, source = fixture(nails(4)); animate(actor)
local originalAccess = SC.Encounter.mayTakeFrom
SC.Encounter.mayTakeFrom = function(container, ...)
    if container == source then return false, "player_storage" end
    return originalAccess(container, ...)
end
visuals[actor] = "completed"; tick(actor)
SC.Encounter.mayTakeFrom = originalAccess
check(#source.items == 4 and #actor.inventory.items == 0, "withdrawn permission cancels the whole remaining batch")

-- A swap with the same item count is checked by identity at application time.
actor, source = fixture(nails(3)); task = animate(actor)
local swapped = task.takeList[2].item
source:Remove(swapped)
local replacement = f.item("Base.Crowbar", "Weapon", { weight = 1 })
source:AddItem(replacement)
complete(actor)
check(#actor.inventory.items == 2 and source:contains(replacement), "same-count replacement is not an unplanned pickup")

-- A stale container list cannot override the native item's actual owner.
actor, source = fixture(nails(1)); task = animate(actor)
local aliased = task.takeList[1].item
aliased.container = f.player.inventory
visuals[actor] = "completed"; tick(actor)
check(#actor.inventory.items == 0 and source:contains(aliased),
    "a stale source membership never steals an item whose native owner changed")

-- A finite mission is rechecked after every real receipt, not once per animation.
actor, source = fixture(nails(8))
local received = 0
commandViews[actor].scavengeMissionId, commandViews[actor].scavengeRequestedCategory = "small-trip", "construction"
local originalExpedition = SC.ExpeditionPrototype
SC.ExpeditionPrototype = {
    searchLootRemaining = function() return 3 - received end,
    noteVerifiedSearchLoot = function(_, receipt)
        check(receipt.verified and receipt.missionId == "small-trip", "mission credit has verified per-item identity")
        received = received + 1
    end,
}
animate(actor); complete(actor)
SC.ExpeditionPrototype = originalExpedition
check(received == 3 and #actor.inventory.items == 3 and #source.items == 5,
    "one batch cannot exceed a three-item remainder")

-- Candidates after the first slice are found, and time slicing never writes an empty verdict.
local many = {}
for _ = 1, 120 do many[#many + 1] = f.item("Base.UnknownJunk", "Item") end
many[#many + 1] = f.item("Base.Bandage", "Medical", { weight = .05 })
actor, source = fixture(many)
tick(actor)
local state = SC.Encounter.peek(actor)
check(state.task and state.task.pendingItem and state.visit.sequence <= 40 and not state.visited[source],
    "an unfinished bounded visit remains pending, not empty")
animate(actor); complete(actor)
check(#actor.inventory.items == 1 and #source.items == 120, "resumable scanning reaches useful contents after junk")

-- Multiple actors cannot double-claim any exact object.
local crew, shared = {}, nil
for index = 1, 4 do
    local fellow, stock = fixture(index == 1 and nails(12) or {})
    if index == 1 then shared = stock else fellow.square = crew[1].square end
    commandViews[fellow].scavengeTargetContainer = shared
    crew[index] = fellow
end
for _ = 1, 15 do
    for _, fellow in ipairs(crew) do
        tick(fellow)
        if visuals[fellow] == "active" then visuals[fellow] = "completed" end
    end
end
local unique, total = {}, 0
for _, fellow in ipairs(crew) do
    for _, item in ipairs(fellow.inventory.items) do check(not unique[item], "cargo identity belongs to only one carrier")
        unique[item], total = true, total + 1 end
end
check(total == 12 and #shared.items == 0, "four competing carriers conserve all twelve items")

-- Effective bag discount and raw space are independent constraints.
local contents = f.inventory(); contents.capacity = 8
bag = f.item("Base.Bag_BigHikingBag", "Container", { nestedInventory = contents,
    weight = .5, weightReduction = 90, equipLocation = "Back", bagCapacity = 8 })
function contents:getContainingItem() return bag end
actor = fixture({})
actor.inventory:AddItem(bag); actor:setWornItem("Back", bag)
function actor:getMaxWeight() return 10 end
local projection = SC.Logistics.lootProjection(actor, SC.Logistics.audit(actor))
local heavy = f.item("Base.Plank", "Material", { weight = 4 })
local choice = SC.Logistics.lootChoice(actor, heavy, "construction", projection, {}, nil, true)
check(choice and choice.destination == contents and choice.delta < .41,
    "worn bag load reduction applies to the actual chosen destination")
SC.Logistics.projectLoot(projection, choice)
choice = SC.Logistics.lootChoice(actor, heavy, "construction", projection, {}, nil, true)
check(choice and choice.destination == contents, "second item fits the remaining raw bag space")
SC.Logistics.projectLoot(projection, choice)
choice = SC.Logistics.lootChoice(actor, heavy, "construction", projection, {}, nil, true)
check(choice and choice.destination == actor.inventory, "a full bag falls back to a safe root destination")
SC.Logistics.projectLoot(projection, choice)
check(not SC.Logistics.lootChoice(actor, heavy, "construction", projection, {}, nil, true),
    "the next heavy item cannot exceed the Strength ceiling despite ample physical space")
check(SC.Logistics.lootChoice(actor, f.item("Base.Nails", "Material", { weight = .05 }),
    "construction", projection, {}, nil, true), "a rejected heavy item does not hide lighter useful loot")

-- Own needs are recalculated between selections; a third tool is an extra.
local stocked = nails(7)
local dressing = f.item("Base.Bandage", "Medical", { weight = .05 })
stocked[#stocked + 1] = dressing
actor, source = fixture(stocked)
task = animate(actor)
check(task.takeList[1].item == dressing and task.takeList[2].category == "construction",
    "needed dressing precedes optional construction stock regardless of inventory order")
complete(actor)

-- Haul speech is deferred, copied and shared across successive cupboards.
SC.Encounter.reset(); lines = {}
actor, source = fixture(nails(1)); animate(actor); complete(actor)
check(#lines == 0, "a verified item does not speak before its haul ends")
local second = f.containerObject(actor.square, { f.item("Base.Bandage", "Medical", { weight = .05 }) })
commandViews[actor].scavengeTargetContainer = second
animate(actor); complete(actor)
for _ = 1, 3 do tick(actor) end
check(#lines == 1 and string.find(lines[1].name, "bandage", 1, true)
        and SC.Encounter.peek(actor).lastHaul.count == 2,
    "one haul across cupboards names its best verified find exactly once")
local quiet, quietStock = fixture(nails(1)); animate(quiet); complete(quiet)
for _ = 1, 3 do tick(quiet) end
check(#lines == 1 and SC.Encounter.peek(quiet).lastHaul.count == 1, "party gap drops, rather than queues, the next loot bark")
f.clock = f.clock + 20000
actor, source = fixture(nails(1)); animate(actor); complete(actor)
SC.Encounter.tryScavenge(actor, nil, { snapshot = { immediateCount = 1, pressure = 1 } })
check(#lines == 1 and not SC.Encounter.peek(actor).haul, "danger discards the pending reaction")
actor, source = fixture(nails(1)); animate(actor); complete(actor)
function actor:isAsleep() return true end
for _ = 1, 3 do tick(actor) end
check(#lines == 1, "sleep suppresses haul speech")

-- Retrying an uncertain transfer must never manufacture another item.
actor, source = fixture(nails(1)); task = animate(actor)
local uncertain = task.takeList[1].item
actor.inventory.rejectAdd, source.rejectAdd = true, true
visuals[actor] = "completed"; tick(actor)
check(#source.items == 0 and #actor.inventory.items == 0 and uncertain:getModData().SC_LootTransferUncertain,
    "a failed native rollback is held for reconciliation without synthetic replacement")

-- Returning loot is storage-only, keeps the obligation while blocked, and can
-- be retried without changing the companion's order.
actor, source = fixture(nails(4)); animate(actor); complete(actor)
local base = SC.BaseLife
local oldInside, oldActive, oldRows, oldStorage, oldResolve = base.isInside, base.active,
    base.storageRows, base.storage, base.resolveContainer
local shelf = f.containerObject(actor.square, {}); shelf.capacity = 0
local row = { id = "storage:loot", category = "general", deposits = true, withdrawals = false }
base.isInside = function() return true end
base.active = function() return { id = "base:loot" } end
base.storageRows = function(category, withdrawals)
    return withdrawals ~= true and (category == nil or category == "general") and { row } or {}
end
base.storage = function(id) return id == row.id and row or nil end
base.resolveContainer = function(storage) if storage == row then return shelf, shelf.owner end end
local load = SC.Logistics.status(actor)
check(load.lootReturnCleanup and load.surplus and load.surplus.shelveOnly and not load.fieldReturnCleanup,
    "ordinary loot gets a separate storage-only cleanup obligation")
SC.Logistics.update(actor, nil, safe)
load = SC.Logistics.status(actor)
check(actor.modData.LF_LootReturnPending and #actor.inventory.items == 4 and #shelf.items == 0
        and not load.lootCleanupDone, "full storage retains cargo and the pending obligation")
shelf.capacity = 50
check(SC.Logistics.retryLootDelivery(actor), "manual retry releases the delivery backoff")
pacing[actor] = true
local _, pacingReason = SC.Logistics.update(actor, nil, safe)
check(pacingReason == "action_pacing:logistics_deposit" and SC.ActionSupervisor.current(actor)
        and actor.modData.LF_LootReturnRetryAt == nil and #actor.inventory.items == 4,
    "native pacing waits without losing ownership, moving cargo or triggering the storage backoff")
pacing[actor] = nil
for _ = 1, 30 do
    f.clock = f.clock + 100
    SC.Logistics.update(actor, nil, safe)
    if visuals[actor] == "active" then visuals[actor] = "completed" end
    if not actor.modData.LF_LootReturnPending then break end
end
check(not actor.modData.LF_LootReturnPending and #actor.inventory.items == 1 and #shelf.items == 3,
    "unloading stores exact surplus and keeps the role's personal target")
for _, item in ipairs(nails(2)) do actor.inventory:AddItem(item) end
actor.modData.LF_LootReturnPending, actor.modData.SC_Order = true, "follow"
SC.Logistics.reset(actor)
SC.Logistics.update(actor, f.player, safe)
f.player.moving = true
local _, yieldReason = SC.Logistics.update(actor, f.player, safe)
f.player.moving = false
check(yieldReason == "loot_delivery_yield" and actor.modData.LF_LootReturnPending,
    "a moving leader interrupts optional shelving while preserving delivery")

-- A route survey may yield under load, but it must not hold delivery forever.
local farShelf = f.containerObject(f.cell:getGridSquare(actor.square.x + 6, actor.square.y, 0), {})
base.resolveContainer = function(storage) if storage == row then return farShelf, farShelf.owner end end
local originalSelect, surveys = SC.Navigation.selectInteraction, 0
SC.Navigation.selectInteraction = function() surveys = surveys + 1 return nil, "pending" end
actor.modData.SC_Order = "base_duty"
SC.Logistics.reset(actor)
SC.Logistics.update(actor, nil, safe)
f.clock = f.clock + 15100
local _, routeReason = SC.Logistics.update(actor, nil, safe)
check(routeReason == "storage_route_unknown" and actor.modData.LF_LootReturnRetryAt == f.clock + 180000,
    "a stalled survey pauses delivery and records a three-minute retry")
local before = surveys
f.clock = f.clock + 1000; SC.Logistics.update(actor, nil, safe)
check(surveys == before and actor.modData.LF_LootReturnPending,
    "a paused delivery does not repeatedly restart expensive route surveys")
SC.Logistics.retryLootDelivery(actor); SC.Logistics.update(actor, nil, safe)
check(surveys > before and actor.modData.LF_LootReturnRetryAt == nil, "manual retry restarts the survey without discarding cargo")
SC.Navigation.selectInteraction = originalSelect
SC.Logistics.reset(actor)
base.isInside, base.active, base.storageRows, base.storage, base.resolveContainer =
    oldInside, oldActive, oldRows, oldStorage, oldResolve

U.move, SC.Dialogue.say = originalMove, originalDialogue
SC_TEST_REPORT = "LOOT_HAUL_PASS checks=" .. f.checks()
