-- SPDX-License-Identifier: MIT
-- One compact scenario group: production ownership, scans, projections and receipts.
local SC, f = LivingFellows, LivingFellows.TestFixture
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

do
    local find = nails(1)[1]
    local worker, cupboard = fixture({ find })
    local logistics, loot = SC.Logistics, SC.ScavengeLoot
    local classify, canTake, scan = logistics.itemCategory, logistics.canTake, loot.scan
    local evaluations, classifications, admissions, evaluating = 0, 0, 0, false
    logistics.itemCategory = function(item)
        if evaluating and item == find then classifications = classifications + 1 end
        return classify(item)
    end
    logistics.canTake = function(actor, item, ...)
        if evaluating and actor == worker and item == find then admissions = admissions + 1 end
        return canTake(actor, item, ...)
    end
    loot.scan = function(visit, evaluate, ...)
        return scan(visit, function(item, node)
            if visit.actor ~= worker or item ~= find then return evaluate(item, node) end
            evaluations, evaluating = evaluations + 1, true
            local score, category, band = evaluate(item, node)
            evaluating = false
            return score, category, band
        end, ...)
    end
    local planned = animate(worker)
    logistics.itemCategory, logistics.canTake, loot.scan = classify, canTake, scan
    check(evaluations > 0 and classifications == evaluations and admissions == evaluations,
        "initial loot scoring classifies and admits once per evaluation: "
            .. evaluations .. "/" .. classifications .. "/" .. admissions)
    check(planned.takeList[1].item == find, "the chosen row retains the exact candidate")
    complete(worker)
    check(worker.inventory:contains(find) and not cupboard:contains(find)
        and SC.Encounter.peek(worker).lastLoot.verified, "the new score path retains exact pickup evidence")
end

do
    local logistics = SC.Logistics
    local worker = fixture({})
    local projection = logistics.lootProjection(worker, logistics.audit(worker))
    local personal = f.item("Base.Bandage", "Medical", { weight = .05 })
    local expectedScore = logistics.itemNeedScore(worker, personal, {}, projection.audit)
    local acceptsLoot = SC.Quirks.acceptsLoot
    SC.Quirks.acceptsLoot = function(actor, item) return actor == worker and item == personal end
    local choice = logistics.lootChoice(worker, personal, "personal", projection, {}, nil, true)
    SC.Quirks.acceptsLoot = acceptsLoot
    check(expectedScore > 130 and choice and choice.category == "personal"
        and choice.destination == worker.inventory and choice.score == expectedScore,
        "an explicit personal category keeps its admission and destination with the native medicine score")

    local garment = f.item("Base.Shirt_FormalWhite", "Clothing", {
        bodyLocation = "Torso1", condition = 7, biteDefense = 10, weight = .2,
    })
    local bag = f.item("Base.Bag_DuffelBag", "Container", {
        nestedInventory = f.inventory(), bagCapacity = 10, weightReduction = 80,
        equipLocation = "Back", weight = .5,
    })
    for _, entry in ipairs({ { garment, "clothingUpgrade" }, { bag, "bagUpgrade" } }) do
        local item, method = entry[1], entry[2]
        expectedScore = logistics.itemNeedScore(worker, item, {}, projection.audit)
        local upgrade, calls = logistics[method], 0
        logistics[method] = function(actor, candidate)
            if candidate == item then calls = calls + 1 end
            return upgrade(actor, candidate)
        end
        choice = logistics.lootChoice(worker, item, nil, projection, {}, nil, true)
        logistics[method] = upgrade
        check(expectedScore > 130 and choice and choice.score == expectedScore and calls == 1,
            "admission supplies the same upgrade score with one " .. method .. " check: " .. calls)
    end
end

do
    local worker = fixture(nails(1))
    local Logistics, index = SC.Logistics, SC.InventoryIndex
    local nativeAudit, calls = Logistics.audit, 0
    Logistics.audit = function(...)
        calls = calls + 1
        return nativeAudit(...)
    end
    local prepared = Logistics.status(worker)
    check(prepared.inventoryComplete and calls == 1, "status prepares a complete loot audit")
    tick(worker)
    check(calls == 1, "first Scavenge decision reuses a complete prepared audit")

    local added = nails(1)[1]
    worker.inventory:AddItem(added)
    index.touch(worker)
    local fresh = Logistics.status(worker)
    check(fresh ~= prepared and fresh.items[1].item == added and calls == 2,
        "an inventory revision replaces the cached status before its time limit")
    local swapped = f.item("Base.Bandage", "Medical", { weight = .05 })
    worker.inventory:Remove(added)
    worker.inventory:AddItem(swapped)
    index.touch(worker)
    local loot = Logistics.lootAudit(worker, {}, fresh)
    check(loot.items[1].item == swapped and calls == 3,
        "a same-weight change invalidates an already prepared audit through its revision")
    fresh = Logistics.status(worker)
    swapped.weight = .1
    loot = Logistics.lootAudit(worker, {}, fresh)
    check(loot.weight == .1 and calls == 5,
        "a native weight change without an index event also invalidates the prepared audit")
    fresh = Logistics.status(worker)
    worker.modData.SC_AllowOverload = true
    loot = Logistics.lootAudit(worker, {}, fresh)
    check(loot.hardRatio == 1.2 and calls == 7,
        "the prepared audit cannot retain a changed load policy")
    Logistics.audit = nativeAudit
    SC.Encounter.reset(worker)

    local scanWorker = f.actor("expedition-loot-revision", -44, -33, { inventory = f.inventory(nails(81)) })
    local old = scanWorker.inventory.items[1]
    local oldLimit = SC.Config._values.logisticsInventoryItemBudget
    SC.Config._values.logisticsInventoryItemBudget = 4
    local work = {}
    check(Logistics.lootAudit(scanWorker, work) == nil, "large inventory audit yields its first slice")
    local replacement = f.item("Base.Bandage", "Medical", { weight = .05 })
    scanWorker.inventory:Remove(old)
    scanWorker.inventory:AddItem(replacement)
    index.touch(scanWorker)
    check(Logistics.lootAudit(scanWorker, work) == nil, "inventory revision restarts a partial loot audit")
    loot = Logistics.lootAudit(scanWorker, work)
    check(loot and #loot.items == 81 and loot.items[1].item ~= old and loot.items[81].item == replacement,
        "completed revision-safe audit contains the exact live replacement")
    SC.Config._values.logisticsInventoryItemBudget = oldLimit
end

do
    local worker = fixture(nails(1))
    local item = nails(1)[1]
    worker.inventory:AddItem(item)
    worker.inventory.capacity = 20
    local Logistics, index = SC.Logistics, SC.InventoryIndex
    local audit, status, roleOf = Logistics.audit, Logistics.status, Logistics.roleOf
    local calls, statusCalls, role = 0, 0, "generalist"
    Logistics.audit = function(...)
        calls = calls + 1
        return audit(...)
    end
    Logistics.status = function(...)
        statusCalls = statusCalls + 1
        return status(...)
    end
    Logistics.roleOf = function() return role end
    local work = {}
    local function read(mission)
        local operation = Logistics.expeditionLootAudit
        return operation and operation(worker, work, mission)
    end
    local first = read("first-trip")
    check(first and first.items[1].item == item and first.capacity == 20 and statusCalls == 0,
        "expedition prepares the load and exact loot inventory without base management")
    check(read("first-trip") == first and calls == 1,
        "a stable expedition decision reuses the exact inventory classification")

    local replacement = f.item("Base.Bandage", "Medical", { weight = .05 })
    worker.inventory:Remove(item)
    worker.inventory:AddItem(replacement)
    index.touch(worker)
    check(read("first-trip").items[1].item == replacement and calls == 2,
        "same-weight inventory revision invalidates the expedition cache")
    replacement.weight = .1
    check(read("first-trip").weight == .1 and calls == 3,
        "physical weight invalidates it with no inventory event")
    worker.inventory.capacity = 19
    check(read("first-trip").capacity == 19 and calls == 4,
        "physical capacity also invalidates it without an event")
    role = "quartermaster"
    check(read("first-trip").hardRatio == .95 and calls == 5,
        "role changes refresh the expedition policy")
    worker.modData.SC_AllowOverload = true
    check(read("first-trip").hardRatio == 1.2 and calls == 6,
        "an explicit overload change refreshes the same work immediately")
    worker.inventory = f.inventory({ item })
    check(read("first-trip").items[1].item == item and calls == 7,
        "replacing the native inventory refreshes the exact records")
    check(read("second-trip") and calls == 8,
        "reusing worker state for a different mission requires fresh evidence")

    worker.inventory:Remove(item)
    replacement.weight = item.weight
    worker.inventory:AddItem(replacement)
    check(read("second-trip").items[1].item == item and calls == 8,
        "unreported same-weight mutations are bounded by the refresh interval")
    f.clock = f.clock + 500
    check(read("second-trip").items[1].item == replacement and calls == 9,
        "the bounded refresh catches silent same-weight mutations")

    commandViews[worker].scavengeMissionId = "third-trip"
    tick(worker)
    check(statusCalls == 0 and calls == 10,
        "the production Search entry point bypasses general logistics status")
    tick(worker)
    check(statusCalls == 0 and calls == 10,
        "the production Search entry point reuses its site classification")
    Logistics.audit, Logistics.status, Logistics.roleOf = audit, status, roleOf
    SC.Encounter.reset(worker)
end

do
    local weight = f.item("Base.Nails", "Material", { weight = 8.99 })
    local worker = f.actor("expedition-capacity", -43, -33, { inventory = f.inventory({ weight }) })
    worker.inventory.capacity = 10
    local Logistics = SC.Logistics
    local roleOf = Logistics.roleOf
    local role = "generalist"
    Logistics.roleOf = function() return role end
    local reads = 0
    local getItems = worker.inventory.getItems
    worker.inventory.getItems = function(self)
        reads = reads + 1
        return getItems(self)
    end
    check(not Logistics.expeditionLoadFull(worker), "ordinary hard capacity admits just below its boundary")
    weight.weight = 9
    check(Logistics.expeditionLoadFull(worker), "ordinary hard capacity rejects exactly at the boundary")
    role = "quartermaster"
    local physicalWeight, limit, inventory = Logistics.physicalLoadLimit(worker)
    check(physicalWeight == 9 and limit == 9.5 and inventory == worker.inventory,
        "the role-aware physical load exposes the exact inventory for bycatch")
    check(not Logistics.expeditionLoadFull(worker), "quartermaster retains its higher capacity threshold")
    weight.weight = 9.5
    check(Logistics.expeditionLoadFull(worker), "quartermaster hard capacity rejects at its boundary")
    worker.modData.SC_AllowOverload = true
    local _, overloadLimit = Logistics.physicalLoadLimit(worker)
    check(overloadLimit == 12, "the physical load limit includes the actor's explicit overload setting")
    check(not Logistics.expeditionLoadFull(worker), "explicit overload overrides the role threshold")
    weight.weight = 12
    check(Logistics.expeditionLoadFull(worker), "explicit overload remains finite at its boundary")
    worker.inventory.capacity = 0
    check(not Logistics.expeditionLoadFull(worker) and reads == 0,
        "capacity check handles unknown load limit and never enumerates native items")
    Logistics.roleOf = roleOf
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

-- Carry room and food safety can change between the pose and verified transfer.
for _, mode in ipairs({ "spoiled", "full" }) do
    local apple = f.item("Base.Apple", "Food", { hungerChange = -.20, weight = .2 })
    actor, source = fixture({ apple })
    check(animate(actor).takeList[1].item == apple, "a fresh apple fits before the loot pose")
    if mode == "spoiled" then apple.rotten = true else actor.inventory.capacity = .01 end
    visuals[actor] = "completed"; tick(actor)
    check(source:contains(apple) and not actor.inventory:contains(apple),
        "fresh transfer checks leave the planned apple in its source when " .. mode)
end

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

local function readyForUpgrade()
    local concrete = f.item("Base.ConcretePowder", "Material", { weight = 6.8 })
    local carrier = fixture({ concrete })
    function carrier:getMaxWeight() return 10 end
    animate(carrier); complete(carrier)
    check(concrete:getModData().LF_ScavengedBy == carrier.id, "a verified field pickup records its original looter")
    local better = f.item("Base.Bandage", "Medical", { weight = 1 })
    local cupboard = f.containerObject(carrier.square, { better })
    commandViews[carrier].scavengeTargetContainer = cupboard
    return carrier, concrete, better, cupboard
end

do
    local carrier, concrete, better, cupboard = readyForUpgrade()
    local plan = animate(carrier)
    check(plan.takeList[1].drop and plan.takeList[1].drop.item == concrete
        and carrier.inventory:contains(concrete) and cupboard:contains(better),
        "a needed bandage reserves the scavenged concrete bag without changing either owner during animation")
    complete(carrier)
    check(carrier.inventory:contains(better) and not cupboard:contains(better)
        and not carrier.inventory:contains(concrete) and U.worldItemPresent(carrier.square, concrete:getWorldItem())
        and not concrete:getModData().LF_ScavengedBy,
        "the verified exchange replaces one exact item and leaves the old concrete recoverable on the floor")
end

do
    local carrier, concrete, better, cupboard = readyForUpgrade()
    animate(carrier)
    carrier.inventory.rejectAddType = "Base.Bandage"
    visuals[carrier] = "completed"
    tick(carrier)
    check(carrier.inventory:contains(concrete) and not concrete:getWorldItem()
        and cupboard:contains(better) and not carrier.inventory:contains(better),
        "a rejected replacement restores the original concrete bag and leaves the find in its cupboard")
end

do
    local carrier, concrete, better, cupboard = readyForUpgrade()
    animate(carrier)
    concrete:setFavorite(true)
    visuals[carrier] = "completed"
    tick(carrier)
    check(carrier.inventory:contains(concrete) and cupboard:contains(better)
        and not concrete:getWorldItem(), "favoriting the reserved carried item cancels the exchange at commit")
    concrete:setFavorite(false)
    SC.Logistics.noteGift(carrier, concrete)
    local audit = SC.Logistics.audit(carrier)
    check(not SC.Logistics.lootReplacement(carrier, better, "medicine",
        SC.Logistics.lootProjection(carrier, audit), commandViews[carrier]),
        "player-supplied items cannot be used as field exchange stock")
end

do
    -- A find taken home becomes camp kit. It may be shelved and issued back to
    -- the same companion, who must not trade that camp supply away later.
    local carrier, concrete, better = readyForUpgrade()
    local function exchange()
        local audit = SC.Logistics.audit(carrier)
        return SC.Logistics.lootReplacement(carrier, better, "medicine",
            SC.Logistics.lootProjection(carrier, audit), commandViews[carrier])
    end
    local before = exchange()
    check(before and before.drop and before.drop.item == concrete,
        "control: during its outing the concrete bag is exchange stock")
    local base, oldInside = SC.BaseLife, SC.BaseLife.isInside
    base.isInside = function() return true end
    SC.Logistics.status(carrier)
    base.isInside = oldInside
    check(concrete:getModData().LF_ScavengedBy == carrier.id and not exchange(),
        "after a visit to camp the same find is no longer field exchange stock")
    carrier.inventory:Remove(concrete)
    local legacy = f.item("Base.ConcretePowder", "Material", { weight = 6.8 })
    legacy:getModData().LF_ScavengedBy = carrier.id
    carrier.inventory:AddItem(legacy)
    check(not exchange(), "a mark without its outing, as saved by 0.27.62, is not exchange stock")
end

do
    local heavyFind = f.item("Base.Plank", "Material", { weight = 3 })
    local lighterFind = f.item("Base.Plank", "Material", { weight = .5 })
    local carrier = fixture({ heavyFind, lighterFind })
    check(animate(carrier).takeList[1].item == lighterFind,
        "equal-value loot prioritizes the lighter find")
    complete(carrier)
end

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
check(uncertain:getModData().SC_LootTransferUncertain == actor.id,
    "the uncertainty mark names the looter whose transfer failed")

-- The mark settles once the item sits consistently in a container and the
-- looter does not also hold it. It used to exclude the item forever.
local settler = fixture({ uncertain })
task = animate(settler)
check(task.takeList[1] and task.takeList[1].item == uncertain
        and uncertain:getModData().SC_LootTransferUncertain == nil,
    "a consistently placed uncertain item settles and can be looted again")

-- A looter still holding the marked item keeps it excluded: taking the second
-- reference would duplicate it.
local duplicate, extra = nails(1)[1], nails(1)[1]
local holder = fixture({ duplicate, extra })
holder.inventory.items[#holder.inventory.items + 1] = duplicate
duplicate:getModData().SC_LootTransferUncertain = holder.id
task = animate(holder)
check(#task.takeList == 1 and task.takeList[1].item == extra
        and duplicate:getModData().SC_LootTransferUncertain == holder.id,
    "an uncertain item its looter still holds stays excluded")

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

-- Field return (send-home trips, field orders) stays a single pass. Surplus
-- with no marked storage cools down and stays carried, and the pass finishes;
-- 0.27.12 first held it open, so a send-home trip could never settle.
local returning = f.actor("loot-field-return", -52, -40, {})
f.registry[returning.id] = returning
for _, item in ipairs(nails(4)) do returning.inventory:AddItem(item) end
base.isInside = function() return true end
base.active = function() return { id = "base:loot" } end
base.storageRows = function() return {} end
base.storage = function() return nil end
returning.modData.LF_FieldReturnCleanup = true
local passes = 0
for _ = 1, 40 do
    passes = passes + 1
    f.clock = f.clock + 1000
    SC.Logistics.update(returning, nil, safe)
    if returning.modData.LF_FieldReturnCleanup == nil then break end
end
check(returning.modData.LF_FieldReturnCleanup == nil and passes <= 10,
    "field-return cleanup finishes when no storage accepts the surplus")
check(#returning.inventory.items == 4, "surplus without storage stays carried, never dropped")
SC.Logistics.reset(returning)
base.isInside, base.active, base.storageRows, base.storage =
    oldInside, oldActive, oldRows, oldStorage

local function campOverflow(placed)
    base.reset()
    f.makeSquare(71, 72, 0)
    local worker = f.actor("overflow-worker", 71, 72, {})
    f.registry[worker.id] = worker
    local storageSquare = f.makeSquare(72, 72, 0)
    local store, crate = f.containerObject(storageSquare, {})
    function crate:getObjectIndex() return 0 end
    store.capacity = 0
    check(base.create(worker.square, "Overflow camp"), "create a marked camp")
    check(base.registerStorage(crate, "construction"), "mark overflow fixture's construction storage")
    if placed then
        check(base.beginZone("sorting_floor", worker.square)
            and base.finishZone(worker.square, "Sorting"), "mark a sorting floor at the worker")
    end
    local items = nails(4)
    for index, value in ipairs(items) do
        local id = (placed and 3000 or 3100) + index
        function value:getID() return id end
        worker.inventory:AddItem(value)
    end
    worker.modData.LF_LootReturnPending = true
    if placed then
        for _ = 1, 15 do
            f.clock = f.clock + 100
            SC.Logistics.update(worker, nil, safe)
            if visuals[worker] == "active" then break end
        end
        check(visuals[worker] == "active", "the fallback drop entered its inventory animation")
        store.capacity = 100
        visuals[worker] = "completed"
        f.clock = f.clock + 100
        local _, reason = SC.Logistics.update(worker, nil, safe)
        check(reason == "overflow_storage_changed" and #worker.square.worldItems == 0
            and #worker.inventory.items == 4, "opening space during the drop keeps container storage first")
        store.capacity = 0
    end
    for _ = 1, 45 do
        f.clock = f.clock + 100
        SC.Logistics.update(worker, nil, safe)
        if visuals[worker] == "active" then visuals[worker] = "completed" end
        if not worker.modData.LF_LootReturnPending then break end
    end
    local spot, zones = nil, 0
    for _, zone in ipairs(base.active().zones) do
        if zone.kind == "sorting_floor" then
            spot = f.cell:getGridSquare(zone.x1, zone.y1, zone.z)
            zones = zones + 1
            check((zone.lootOverflow == true) ~= placed, "the original floor is preferred to automatic marking")
        end
    end
    check(zones == 1 and spot and #spot.worldItems == 3 and #worker.inventory.items == 1
        and not worker.modData.LF_LootReturnPending and #store.items == 0,
        "full storage leaves exact surplus on one floor and keeps the role's construction minimum")
    local saved = base.export()
    check(base.restore(saved), "the floor persists through camp reload")
    local floor = base.active().zones[2]
    check(floor and floor.kind == "sorting_floor" and (floor.lootOverflow == true) ~= placed,
        "reload preserves the same overflow designation")
    check(base.assign(worker.id, "generalist", true), "assign a worker to the next sorting pass")
    worker.modData.SC_Order = "base_duty"
    local queued, job = base.enqueueJob({ type = "sort_floor", priority = 2,
        target = { zoneId = floor.id, x = floor.x1, y = floor.y1, z = floor.z } })
    check(queued, "create a normal sorting job for the overflow floor")
    local work = {}
    SC.FloorSort.update(worker, work, job)
    check(#spot.worldItems == 3 and #worker.inventory.items == 1,
        "the sorter leaves overflow on the floor while its destination is full")
    store.capacity = 100
    f.clock = f.clock + 31000
    for _ = 1, 35 do
        f.clock = f.clock + 100
        SC.FloorSort.update(worker, work, job)
        if visuals[worker] == "active" then visuals[worker] = "completed" end
        if #store.items == 3 then break end
    end
    check(#spot.worldItems == 0 and #store.items == 3 and #worker.inventory.items == 1,
        "the ordinary sorter clears the overflow when the container has room")
end

campOverflow(true)
campOverflow(false)

do
    local item = nails(1)[1]
    local worker, unmarked, cabinet = fixture(nails(1))
    local marked = f.inventory({ item })
    marked.owner = cabinet
    function marked:getType() return "freezer" end
    function marked:getParent() return self.owner end
    function cabinet:getObjectIndex() return 0 end
    function cabinet:getContainerCount() return 2 end
    function cabinet:getContainerByIndex(index)
        if index == 0 then return unmarked end
        if index == 1 then return marked end
    end
    base.reset()
    check(base.create(worker.square, "Exact storage scan"), "create a camp for independent compartments")
    check(base.registerStorage(cabinet, "construction", marked), "mark the second compartment alone")
    commandViews[worker].scavengeTargetContainer = nil
    local picked = animate(worker)
    check(#picked.takeList == 1 and picked.takeList[1].root == marked
        and picked.takeList[1].item == item, "camp discovery starts from the marked compartment")
    complete(worker)
    check(worker.inventory:contains(item) and #unmarked.items == 1 and #marked.items == 0,
        "camp looting moves the original from the marked compartment only")
end

do
    local follower = f.actor("follow-search", 34, 40, {})
    local leader = f.actor("follow-search-leader", 35, 40, {})
    local commands = { recruited = true, scavenge = true, order = "follow", commandSerial = 1 }
    commandViews[follower] = commands
    f.registry[follower.id] = follower
    local originalRecord = SC.Performance.record
    local scans, scores = 0, 0
    SC.Performance.record = function(metric, ...)
        if metric == "scavenge.scan" then scans = scans + 1 end
        if metric == "scavenge.score" then scores = scores + 1 end
        return originalRecord(metric, ...)
    end
    local function pulse(milliseconds)
        f.clock = f.clock + milliseconds
        return SC.Encounter.tryScavenge(follower, leader, safe)
    end
    local handled, reason = pulse(1000)
    check(not handled and reason == "nothing_needed" and scans == 1 and scores == 1,
        "a completed empty Follow scan records a reusable negative result")
    pulse(1000)
    pulse(1000)
    check(scans == 1 and scores == 1, "the next two safe Follow pulses do zero discovery or scoring")
    pulse(1000)
    check(scans == 2 and scores == 2, "Follow searches again at the three-second deadline")
    commands.commandSerial = 2
    pulse(1000)
    check(scans == 3, "an order change bypasses the negative result")
    local originalSquare = leader.square
    leader.square = f.cell:getGridSquare(35, 41, 0)
    pulse(1000)
    check(scans == 4, "moving the leader to a different square wakes the Follow search")
    leader.square = originalSquare
    pulse(1000)
    local beforeInventory = scans
    SC.InventoryIndex.touch(follower)
    pulse(1000)
    check(scans == beforeInventory + 1, "a known inventory revision clears the repeated-empty result")
    local beforeChange = scans
    local distant = f.containerObject(f.cell:getGridSquare(54, 52, 0), nails(1))
    SC.Encounter.noteScavengeContainerChanged(distant)
    pulse(1000)
    check(scans == beforeChange, "a distant container change does not wake a local search")
    local near, cabinet = f.containerObject(follower.square, nails(1))
    SC.Encounter.noteScavengeObjectAdded(cabinet)
    pulse(1000)
    check(scans == beforeChange + 1 and SC.Encounter.peek(follower).task.container == near,
        "a new nearby container wakes Follow before its wait expires")
    SC.Encounter.reset(follower)

    follower = f.actor("follow-unreadable-search", 43, 39, {})
    leader = f.actor("follow-unreadable-leader", 44, 39, {})
    commandViews[follower] = commands
    local unreadableSquare = follower.square
    local readObjects = unreadableSquare.getObjects
    unreadableSquare.getObjects = function() error("world object list unavailable") end
    local beforeUnreadable = scans
    pulse(1000)
    pulse(1000)
    check(scans == beforeUnreadable + 2,
        "an unreadable square never becomes an empty result that can be reused")
    unreadableSquare.getObjects = readObjects
    pulse(1000)
    local beforeSkip = scans
    pulse(1000)
    check(scans == beforeSkip, "a fully readable retry can use the normal wait")
    commands.prioritizeMeleeWeapon = true
    pulse(1000)
    check(scans == beforeSkip + 1, "weapon-priority searches still inspect the world immediately")
    SC.Encounter.reset(follower)
    SC.Performance.record = originalRecord
end

do
    local navigation, oldPlaces = SC.Navigation, SC.ExpeditionPlaces
    local oldSelect, oldTargets, oldRequest = navigation.selectInteraction, navigation.interactionTargets,
        navigation.requestAny
    local oldClaim = SC.Performance.claimUnits
    local worker = f.actor("site-search-route", 45, 50, {})
    f.registry[worker.id] = worker
    local site = { buildingId = "45:50:53:54", x = 49, y = 52, z = 0 }
    SC.ExpeditionPlaces = {
        siteContainsPoint = function(id, x, y, z)
            return id == site.buildingId and x >= 45 and x <= 53 and y >= 50 and y <= 54 and z == 0
        end,
    }
    commandViews[worker] = { recruited = true, scavenge = true, order = "stay", commandSerial = 1,
        scavengeSite = site, scavengeMissionId = "route-trip", scavengeRequestedCategory = "construction" }
    local blocked = f.containerObject(f.cell:getGridSquare(46, 50, 0), nails(1))
    local item = nails(1)[1]
    local reachable, cabinet = f.containerObject(f.cell:getGridSquare(51, 53, 0), { item })
    local stand = f.cell:getGridSquare(51, 52, 0)
    local blockedChecks, blockedReads, request = 0, 0, nil
    local getItems = blocked.getItems
    function blocked:getItems()
        blockedReads = blockedReads + 1
        return getItems(self)
    end
    SC.Performance.claimUnits = function(kind, requested, ...)
        if kind == "scavengeSquares" then return math.min(requested, 2) end
        return oldClaim(kind, requested, ...)
    end
    navigation.interactionTargets = function(_, object)
        return object == cabinet and { stand } or {}
    end
    navigation.selectInteraction = function(_, survey, _, rows, options)
        check(options.expeditionScavenge and options.maxChoices == 4 and options.nodeQuota == 24,
            "site candidates use the bounded route survey")
        check(not SC.ActionSupervisor.current(worker), "a route survey starts before reserving an action")
        if rows[1].container == blocked then
            blockedChecks = blockedChecks + 1
            return nil, blockedChecks == 1 and "pending" or "unknown"
        end
        check(rows[1].container == reachable, "selection advances to a later site scan batch")
        return rows[1], "selected", { ownerState = survey, endpoint = stand, container = reachable }
    end
    navigation.requestAny = function(_, _, _, intent)
        request = intent
        return true, "moving", stand
    end
    for _ = 1, 45 do
        tick(worker)
        if request then break end
    end
    check(request and request.container == reachable and request.interactionRouteReceipt.container == reachable
        and request.interactionRouteReceipt.boundToken == request.supervisorToken
        and request.interactionRouteReceipt.scavengeMissionId == "route-trip",
        "the later reachable source hands off its exact route under the winning action token")
    check(blockedChecks >= 2 and blockedChecks <= 3 and blockedReads == 0 and not worker.inventory:contains(item),
        "a deferred shelf stays unopened and walking starts before transferring any loot")
    worker.square, worker.forwardY = stand, 1
    animate(worker)
    complete(worker)
    check(worker.inventory:contains(item), "only the reached shelf transfers its exact item")
    SC.Encounter.reset(worker)
    navigation.selectInteraction, navigation.interactionTargets, navigation.requestAny = oldSelect, oldTargets, oldRequest
    SC.ExpeditionPlaces, SC.Performance.claimUnits = oldPlaces, oldClaim
end

do
    local navigation, oldPlaces = SC.Navigation, SC.ExpeditionPlaces
    local oldLocked, oldTargets = navigation.behindLockedDoor, navigation.interactionTargets
    local worker = f.actor("site-search-unlock", 44, 45, {})
    f.registry[worker.id] = worker
    local site = { buildingId = "44:45:48:47", x = 46, y = 46, z = 0 }
    SC.ExpeditionPlaces = {
        siteContainsPoint = function(id, x, y, z)
            return id == site.buildingId and x >= 44 and x <= 48 and y >= 45 and y <= 47 and z == 0
        end,
    }
    commandViews[worker] = { recruited = true, scavenge = true, order = "stay", commandSerial = 1,
        scavengeSite = site, scavengeMissionId = "unlock-trip", scavengeRequestedCategory = "construction" }
    local first, second = f.cell:getGridSquare(45, 45, 0), f.cell:getGridSquare(47, 45, 0)
    first.room, second.room = { name = "first" }, { name = "second" }
    local source, shelf = f.containerObject(first, nails(1))
    f.containerObject(second, nails(1))
    local firstLocked = true
    navigation.behindLockedDoor = function(_, square)
        return square == second or square == first and firstLocked
    end
    navigation.interactionTargets = function(_, object)
        return object == shelf and { worker.square } or {}
    end
    for _ = 1, 4 do tick(worker) end
    local state = SC.Encounter.peek(worker)
    local unlockAt = f.clock
    check(state.siteRouteAccess and #state.siteRouteAccess.lockedRooms == 2 and not state.task,
        "known locked rooms stay recorded without picking a shelf")
    firstLocked = false
    for _ = 1, 5 do
        tick(worker)
        if state.task then break end
    end
    check(state.task and state.task.container == source and f.clock < unlockAt + 8000,
        "unlocking an earlier room wakes discovery and admits its previously skipped shelf")
    SC.Encounter.reset(worker)
    navigation.behindLockedDoor, navigation.interactionTargets = oldLocked, oldTargets
    SC.ExpeditionPlaces = oldPlaces
end

local routeScenario = 0
local function siteRouteScenario(name, run)
    routeScenario = routeScenario + 1
    if SC_TEST_SITE_ROUTE_CASE and SC_TEST_SITE_ROUTE_CASE ~= name then return end
    local x, y = 45, routeScenario * 8
    local site = { buildingId = string.format("%d:%d:%d:%d", x, y, x + 4, y + 1), x = x + 2, y = y, z = 0 }
    local navigation, expedition, places = SC.Navigation, SC.ExpeditionPrototype, SC.ExpeditionPlaces
    local select, targets, locked, request = navigation.selectInteraction, navigation.interactionTargets,
        navigation.behindLockedDoor, navigation.requestAny
    local claim = SC.Performance.claimUnits
    local worker = f.actor("route-review-" .. name, x, y, {})
    f.registry[worker.id] = worker
    commandViews[worker] = { recruited = true, scavenge = true, order = "stay", commandSerial = 1,
        scavengeSite = site, scavengeMissionId = name, scavengeRequestedCategory = "construction" }
    SC.ExpeditionPlaces = {
        siteContainsPoint = function(siteId, tileX, tileY, z)
            return siteId == site.buildingId and tileX >= x and tileX <= x + 4 and tileY == y and z == 0
        end,
    }
    local failures = {}
    SC.ExpeditionPrototype = {
        noteSearchWorkerFailure = function(actor, missionId, reason)
            failures[#failures + 1] = { worker = actor, mission = missionId, reason = reason }
        end,
    }
    navigation.interactionTargets = function() return {} end
    local function shelf(offset)
        local square = f.cell:getGridSquare(x + offset, y, 0)
        return f.containerObject(square, nails(1))
    end
    run(worker, shelf, failures)
    SC.Encounter.reset(worker)
    SC.ExpeditionPrototype, SC.ExpeditionPlaces = expedition, places
    navigation.selectInteraction, navigation.interactionTargets, navigation.behindLockedDoor, navigation.requestAny =
        select, targets, locked, request
    SC.Performance.claimUnits = claim
end

local function expectBlockedRotation(worker, failures, case, maxTicks)
    local rotated
    for _ = 1, maxTicks do
        local handled, reason = tick(worker)
        if not handled and reason == "nothing_needed" then rotated = true break end
    end
    check(rotated, "blocked site relinquishes the worker's search slot within the bounded pass: " .. case)
    check(#failures == 1 and failures[1].worker == worker and failures[1].mission == case
        and failures[1].reason == "approach_timeout",
        "blocked site reports one approach failure to the current expedition: " .. case)
    check(not SC.Encounter.peek(worker).task and not SC.ActionSupervisor.current(worker),
        "blocked site ends without ownership of an undeliverable action: " .. case)
end

siteRouteScenario("locked", function(worker, shelf, failures)
    local _, owner = shelf(2)
    owner.square.room = { name = "locked shelf room" }
    local claim, siteScans = SC.Performance.claimUnits, 0
    SC.Performance.claimUnits = function(kind, requested, ...)
        if kind == "scavengeSquares" and requested > 0 then siteScans = siteScans + 1 end
        return claim(kind, requested, ...)
    end
    SC.Navigation.behindLockedDoor = function(_, square) return square == owner.square end
    SC.Navigation.selectInteraction = function() error("A locked source entered the route survey") end
    expectBlockedRotation(worker, failures, "locked", 20)
    check(#SC.Encounter.peek(worker).siteRouteAccess.lockedRooms == 1,
        "rotating the worker preserves the locked-room watch for a later unlock")
    local scansAtRotation = siteScans
    for _ = 1, 90 do tick(worker) end
    check(siteScans == scansAtRotation and #failures == 1,
        "the rotated worker can watch for unlocks without repeating the blocked pass or its report")
end)

siteRouteScenario("unreachable", function(worker, shelf, failures)
    local source = shelf(2)
    local surveys = 0
    SC.Navigation.selectInteraction = function(_, _, _, rows)
        check(#rows == 1 and rows[1].container == source, "only the unreachable shelf enters the survey")
        surveys = surveys + 1
        return nil, "unreachable"
    end
    expectBlockedRotation(worker, failures, "unreachable", 60)
    local visited = SC.Encounter.peek(worker).visited[source]
    check(surveys == 2 and visited and visited.result == "navigation_failed" and visited.expires > f.clock,
        "two hard failures record navigation memory for that shelf")
    for _ = 1, 10 do tick(worker) end
    check(surveys == 2 and #failures == 1,
        "the hard-failed shelf stays out of surveys during its memory back-off")
end)

siteRouteScenario("handoff-changed", function(worker, shelf, failures)
    local source, owner = shelf(2)
    local stand = f.cell:getGridSquare(owner.square.x - 1, owner.square.y, 0)
    local attempts = 0
    SC.Navigation.interactionTargets = function() return { stand } end
    SC.Navigation.selectInteraction = function(_, survey, _, rows)
        check(#rows == 1 and rows[1].container == source, "the route survey picks the same eligible shelf")
        return rows[1], "selected", { ownerState = survey, endpoint = stand, container = source }
    end
    SC.Navigation.requestAny = function(_, _, _, intent)
        local receipt = intent.interactionRouteReceipt
        check(receipt and receipt.container == source and receipt.endpoint == stand
            and receipt.boundToken == intent.supervisorToken,
            "the planned shelf reaches the handoff with its exact receipt and action token")
        attempts = attempts + 1
        return false, "scavenge_route_invalidated"
    end
    for _ = 1, 10 do
        tick(worker)
        if attempts == 1 then break end
    end
    local first = SC.Encounter.peek(worker).visited[source]
    check(attempts == 1 and (not first or first.result ~= "navigation_failed")
        and #failures == 0 and not SC.ActionSupervisor.current(worker),
        "the first rejected handoff releases the action without recording a hard failure")
    for _ = 1, 30 do
        tick(worker)
        if attempts == 2 then break end
    end
    local second = SC.Encounter.peek(worker).visited[source]
    check(attempts == 2 and second and second.result == "navigation_failed" and second.expires > f.clock,
        "the second rejected handoff records navigation memory for the same shelf")
    expectBlockedRotation(worker, failures, "handoff-changed", 20)
    check(attempts == 2, "the back-off prevents a third handoff during the blocked pass")
end)

siteRouteScenario("unknown", function(worker, shelf, failures)
    local source = shelf(2)
    local arrivals = {}
    SC.Navigation.selectInteraction = function(_, _, _, rows)
        check(#rows == 1 and rows[1].container == source, "an inconclusive survey retains the same shortlist")
        arrivals[#arrivals + 1] = f.clock
        return nil, "unknown"
    end
    expectBlockedRotation(worker, failures, "unknown", 60)
    local visited = SC.Encounter.peek(worker).visited[source]
    check(#arrivals == 2 and arrivals[2] - arrivals[1] < 2000
        and (not visited or visited.result ~= "navigation_failed"),
        "budget uncertainty retries the shortlist once without hard-failure memory")
    for _ = 1, 5 do tick(worker) end
    check(#arrivals == 2 and #failures == 1, "an exhausted shortlist gets a brief source cooldown")
end)

siteRouteScenario("lost-winner", function(worker, shelf, failures)
    local stolen, owner = shelf(2)
    local alternate, second = shelf(4)
    local claimant = f.actor("route-review-claimant", owner.square.x, owner.square.y, {})
    f.registry[claimant.id] = claimant
    commandViews[claimant] = { recruited = true, scavenge = true, order = "stay",
        commandSerial = 1, scavengeTargetContainer = stolen }
    local stand = f.cell:getGridSquare(second.square.x - 1, second.square.y, 0)
    local racedAt, chosen, replacementSurveys
    SC.Navigation.selectInteraction = function(actor, survey, _, rows)
        check(actor == worker, "the explicit claimant does not use the route-aware shortlist")
        if not racedAt then
            check(#rows == 2 and rows[1].container == stolen and rows[2].container == alternate,
                "the winner and alternative are in the same route survey batch")
            SC.Encounter.tryScavenge(claimant, nil, safe)
            check(SC.ActionSupervisor.current(claimant) and SC.Encounter.peek(claimant).task.container == stolen,
                "a second worker reserves the winning shelf before the survey caller can claim it")
            racedAt = f.clock
            return rows[1], "selected", { ownerState = survey, endpoint = stand, container = stolen }
        end
        replacementSurveys = (replacementSurveys or 0) + 1
        check(#rows == 1 and rows[1].container == alternate, "the next survey contains only the surviving shelf")
        return rows[1], "selected", { ownerState = survey, endpoint = stand, container = alternate }
    end
    SC.Navigation.interactionTargets = function(actor, object)
        if actor == claimant and object == owner then return { claimant.square } end
        return object == second and { stand } or {}
    end
    SC.Navigation.requestAny = function(actor, _, _, intent)
        if actor == worker then chosen = intent.container end
        return true, "moving", stand
    end
    for _ = 1, 8 do
        tick(worker)
        if chosen then break end
    end
    check(chosen == alternate and replacementSurveys == 1 and f.clock - racedAt < 800 and #failures == 0,
        "losing one shelf keeps the other shelf available without waiting for a whole-site rescan")
    SC.Encounter.reset(claimant)
end)

siteRouteScenario("mixed-mode", function(worker, shelf)
    shelf(2)
    shelf(4)
    local origin = worker.square
    local claim = SC.Performance.claimUnits
    SC.Performance.claimUnits = function(kind, requested, ...)
        if kind == "scavengeContainers" then return math.min(requested, 1) end
        return claim(kind, requested, ...)
    end
    worker.worldX, worker.worldY = worker:getX(), worker:getY()
    worker.getZ = function() return origin.z end
    worker.square = nil
    tick(worker)
    local legacy = SC.Encounter.peek(worker).selectionJob
    check(legacy and legacy.bestContainer and not legacy.siteRouteRows,
        "a no-square tick retains a partial legacy selection and its winning source")
    local reserved = legacy.bestContainer
    worker.square = origin
    SC.Navigation.selectInteraction = function() return nil, "pending" end
    tick(worker)
    local current = SC.Encounter.peek(worker).selectionJob
    check(not current or current ~= legacy and current.siteRouteRows,
        "restoring the actor square cannot resume legacy state as a route-aware selection")
    local claimant = f.actor("route-review-legacy-claimant", reserved.owner.square.x, origin.y, {})
    f.registry[claimant.id] = claimant
    commandViews[claimant] = { recruited = true, scavenge = true, order = "stay",
        commandSerial = 1, scavengeTargetContainer = reserved }
    SC.Navigation.interactionTargets = function(actor) return { actor.square } end
    tick(claimant)
    check(SC.Encounter.peek(claimant).task and SC.Encounter.peek(claimant).task.container == reserved,
        "discarding the legacy selection releases its old container reservation")
    SC.Encounter.reset(claimant)
end)

U.move, SC.Dialogue.say = originalMove, originalDialogue
SC_TEST_REPORT = "LOOT_HAUL_PASS checks=" .. f.checks()
