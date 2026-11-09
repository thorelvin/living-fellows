-- SPDX-License-Identifier: MIT
-- Subject scenarios use the same native-shaped fixture as the essential checks.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog = f.makeSquare, f.squares, f.movementLog
function SurvivorCompanion.__testManualFilterMasks()
    local sc = SurvivorCompanion
    local safe = { snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 } }
    local originalNative = sc.NativeActions
    local tagCalls, residents = 0, {}
    local function taggedItem(tag, label)
        local gear = item("Test.FilterPolicy" .. label, "Clothing", {
            bodyLocation = "MaskEyes", biteDefense = 30, condition = 10, weight = 0.5,
            usesFloat = 0.37, usedDelta = 0.37,
        })
        function gear:getTags()
            return { iterator = function()
                local pending = true
                return { hasNext = function() return pending end,
                    next = function()
                        pending = false
                        return { getTranslationName = function() return "base:" .. tag end }
                    end }
            end }
        end
        function gear:hasTag()
            tagCalls = tagCalls + 1
            error("mask policy must use the Build 42 ItemTag iterator")
        end
        return gear
    end
    local function carrier(label, mask, recruited)
        local fellow = actor("sc-filter-policy-" .. label, 11, 5,
            { inventory = inventory({ mask }), recruited = recruited ~= false })
        registry[fellow.id] = fellow
        residents[#residents + 1] = fellow
        return fellow
    end
    for _, tag in ipairs({ "gasmask", "gasmasknofilter", "respirator",
            "respiratornofilter", "improvisedgasmask" }) do
        local mask = taggedItem(tag, tag)
        local fellow = carrier(tag, mask)
        check(sc.Logistics.manualOnlyFilterMask(mask)
                and not sc.Logistics.canTake(fellow, mask, "clothing", nil, "useful")
                and not sc.Logistics.canTake(fellow, mask, "tools")
                and sc.Logistics.itemNeedScore(fellow, mask) == 0
                and sc.Logistics.clothingScore(mask) == -math.huge
                and not sc.Logistics.clothingUpgrade(fellow, mask)
                and sc.Logistics.status(fellow).clothingUpgrade == nil,
            "automatic loot and loadout reject the engine's " .. tag .. " tag")
    end
    for _, tag in ipairs({ "gasmaskfilter", "respiratorfilter", "islowerdisguise" }) do
        check(not sc.Logistics.manualOnlyFilterMask(taggedItem(tag, tag)),
            "mask policy does not classify detached filters or ordinary disguise tags: " .. tag)
    end
    local plain = taggedItem("islowerdisguise", "PlainFaceCover")
    check(sc.Logistics.clothingUpgrade(carrier("plain", plain), plain),
        "ordinary face-slot clothing remains eligible for automatic wear")
    local offered = taggedItem("gasmask", "EncounterOffer")
    local scavenger = carrier("encounter", offered)
    scavenger.inventory:Remove(offered)
    scavenger.square, scavenger.modData.SC_Scavenge = cell:getGridSquare(-54, -54, 0), true
    local spareFilter = taggedItem("gasmaskfilter", "EncounterFilter")
    spareFilter.category = "Item"
    local stock = containerObject(scavenger.square, { offered, spareFilter })
    local oldBonus, oldQuirks = sc.Objectives.itemBonus, sc.Quirks
    sc.Objectives.itemBonus = function(_, candidate) return candidate == offered and 100000 or 50000 end
    sc.Quirks = { acceptsLoot = function() return true end,
        itemDesireBonus = function(_, candidate) return candidate == offered and 100000 or 50000, "personal" end }
    for _ = 1, 8 do
        sc.Encounter.tryScavenge(scavenger, nil, safe)
        if scavenger.inventory:contains(spareFilter) then break end
    end
    sc.Objectives.itemBonus, sc.Quirks = oldBonus, oldQuirks
    check(stock:contains(offered) and not scavenger.inventory:contains(offered)
            and scavenger.inventory:contains(spareFilter) and not stock:contains(spareFilter),
        "real scavenging rejects a tagged mask despite objective and quirk overrides while taking a detached filter")

    local mask = taggedItem("gasmask", "Spawned")
    mask:setFavorite(true)
    local fellow = carrier("spawned", mask)
    fellow:setWornItem("MaskEyes", mask)
    local filter = { charge = 0.37, serial = "original-filter" }
    local data = mask:getModData()
    data.filter = filter
    local visual = "active"
    sc.NativeActions = {
        visualStatus = function(_, expected) return visual, expected end,
        clearVisual = function() visual = "none" end,
        cancelVisual = function() visual = "cancelled" return true end,
        stopDirect = function(subject) subject.moving = false return true end,
    }
    local load = sc.Logistics.status(fellow)
    check(load.manualMaskRemoval and load.manualMaskRemoval.item == mask
            and sc.Logistics.update(fellow, nil, safe)
            and fellow:getWornItem("MaskEyes") == mask
            and sc.ActionSupervisor.snapshot(fellow).owner == "logistics",
        "a spawned filter mask waits under supervised ownership before being unworn")
    visual = "completed"
    check(sc.Logistics.update(fellow, nil, safe)
            and fellow:getWornItem("MaskEyes") == nil
            and fellow.inventory:contains(mask) and mask:getContainer() == fellow.inventory
            and mask:getModData() == data and data.filter == filter and filter.charge == 0.37
            and mask:getCurrentUsesFloat() == 0.37 and mask:getUsedDelta() == 0.37
            and mask:isFavorite()
            and sc.ActionSupervisor.reservationCount(fellow) == 0,
        "unwearing preserves the exact mask, filter, charge, favourite state and inventory ownership")

    for _, protection in ipairs({ "manual", "personal", "work", "held", "neutral" }) do
        local kept = taggedItem("respirator", protection)
        local owner = carrier(protection, kept, protection ~= "neutral")
        owner:setWornItem("MaskEyes", kept)
        local mark = kept:getModData()
        if protection == "manual" then
            check(sc.Logistics.equipExactWearable(owner, kept)
                    and mark.SC_ManualWearFor == owner.id,
                "explicit Wear marks the exact filter mask as a player choice")
        elseif protection == "personal" then
            mark.SC_PersonalOwnerId, mark.SC_PersonalKey, mark.SC_PersonalKind = owner.id, "mask", "keepsake"
        elseif protection == "work" then mark.LF_QuestItem = true
        elseif protection == "held" then owner.primary = kept end
        visual = "completed"
        sc.Logistics.update(owner, nil, safe)
        local remainsWorn = protection == "manual" or protection == "neutral"
        check((owner:getWornItem("MaskEyes") == kept) == remainsWorn
                and owner.inventory:contains(kept) and kept:getModData() == mark
                and (protection ~= "held" or owner.primary == kept),
            "mask cleanup preserves " .. protection .. " ownership and wear policy")
    end
    local raced = taggedItem("gasmask", "ManualRace")
    local owner = carrier("manual-race", raced)
    owner:setWornItem("MaskEyes", raced)
    visual = "active"
    check(sc.Logistics.update(owner, nil, safe), "mask cleanup begins before an explicit Wear choice")
    check(sc.Logistics.equipExactWearable(owner, raced), "explicit Wear takes precedence during mask cleanup")
    visual = "completed"
    sc.Logistics.update(owner, nil, safe)
    check(owner:getWornItem("MaskEyes") == raced and owner.inventory:contains(raced)
            and raced:getModData().SC_ManualWearFor == owner.id
            and sc.ActionSupervisor.reservationCount(owner) == 0,
        "mask cleanup rechecks a manual Wear choice acquired during the removal pose")
    check(tagCalls == 0, "mask classification never calls the unsafe string hasTag overload")
    for _, resident in ipairs(residents) do
        sc.Logistics.reset(resident)
        sc.ActionSupervisor.releaseActor(resident)
        registry[resident.id] = nil
        resident.dead = true
    end
    sc.NativeActions = originalNative
end
SurvivorCompanion.__testManualFilterMasks()
SurvivorCompanion.__testManualFilterMasks = nil

function SurvivorCompanion.__testPreparationPacking()
    local sc, originalClock = SurvivorCompanion, f.clock
    local safe = { snapshot = { threats = {}, threatCount = 0, immediateCount = 0, pressure = 0 } }
    local residents = {}
    local function resident(label, contents)
        local fellow = actor("sc-preparation-pack-" .. label, 11, 6, { inventory = inventory(contents) })
        function fellow:getMaxWeight() return 10 end
        registry[fellow.id] = fellow
        residents[#residents + 1] = fellow
        return fellow
    end
    local function prepare(fellow, request)
        local ready, assessment, reason
        for _ = 1, 20 do
            local handled
            handled, reason, ready, assessment = sc.Logistics.prepareLoadout(fellow, request, safe)
            if ready or assessment and assessment.stage == "blocked" then break end
            f.clock = f.clock + 501
        end
        return ready, assessment, reason
    end
    do
        local bag = item("Base.Bag_ProjectedPreparation", "Container", {
            nestedInventory = inventory(), bagCapacity = 28, weightReduction = 70,
            bodyLocation = "Back", equipLocation = "Back", weight = 1,
        })
        function bag:getEquippedWeight() return 3 end
        function bag:getUnequippedWeight() return 10 end
        local fellow = resident("projected-hands", { bag })
        fellow.primary, fellow.secondary = bag, bag
        function fellow.inventory:getCapacityWeight() return 6 end
        local projected, _, _, _, delta = sc.GameplayUtil.projectedCarryLoad(fellow, false)
        local actual = sc.GameplayUtil.projectedCarryLoad(fellow, true)
        local ready, assessment = prepare(fellow, { key = "projected-hands", atCamp = false,
            allowHeldBag = false, cargoRaw = 3, haulRequired = true })
        fellow:setWornItem("Back", bag)
        local worn = sc.GameplayUtil.projectedCarryLoad(fellow, false)
        check(projected == 13 and delta == 7 and actual == 6 and worn == 6
                and not ready and assessment.actualCarryWeight == 6 and assessment.plannedCarryWeight == 13,
            "departure projects a relinquished held bag once while preserving actual and worn-bag load")
    end
    for _, placement in ipairs({ "worn", "held" }) do
        local contents = inventory()
        contents.capacity = 28
        local bag = item("Base.Bag_Preparation" .. placement, "Container", {
            nestedInventory = contents, bagCapacity = 28, weightReduction = 80,
            bodyLocation = "Back", equipLocation = "Back", weight = 1,
        })
        local axe = item("Base.HandAxe", "Weapon", { weight = 4 })
        local food = item("Base.CannedBeansPreparation", "Food", { weight = 5, hungerChange = -0.2 })
        local favorite = item("Base.FavoritePreparation", "Item", { favorite = true, weight = 1 })
        local cargo = item("Base.QuestPreparation", "Item", { weight = 1 })
        cargo:getModData().LF_QuestItem = true
        local fellow = resident(placement, { bag, axe, food, favorite, cargo })
        fellow.primary = axe
        if placement == "worn" then fellow:setWornItem("Back", bag) else fellow.secondary = bag end
        fellow.inventory.capacity = 20
        -- Model native encumbrance, including the equipped bag's real contents.
        function fellow.inventory:getCapacityWeight()
            local weight = contents:getCapacityWeight() * 0.2
            for _, carried in ipairs(self.items) do weight = weight + carried:getActualWeight() end
            return weight
        end
        local request = { key = "packing-" .. placement, atCamp = false, allowHeldBag = true,
            cargoRaw = 8, haulRequired = true, requiredTools = { { itemType = "Base.HandAxe" } } }
        local oldScavenge, handoffs
        if placement == "worn" then
            local careCancels = 0
            local care = assert(sc.ActionSupervisor.begin(fellow, {
                owner = "medical", action = "bandage", priority = sc.ActionSupervisor.Priority.COMBAT_RESCUE,
                onCancel = function() careCancels = careCancels + 1 return true end,
            }))
            local careReady = prepare(fellow, request)
            check(not careReady and careCancels == 0 and sc.ActionSupervisor.isCurrent(care)
                    and fellow.inventory:contains(food) and not contents:contains(food),
                "trip packing preserves higher-priority care and exact inventory ownership")
            sc.ActionSupervisor.cancel(fellow, "care_finished", nil, false)
            assert(sc.Logistics.resetPreparation(fellow, request.key))
            handoffs = 0
            oldScavenge = assert(sc.ActionSupervisor.begin(fellow, {
                owner = "encounter", action = "scavenge", priority = sc.ActionSupervisor.Priority.WORK,
                onCancel = function() handoffs = handoffs + 1 return true end,
            }))
        end
        local ready, assessment = prepare(fellow, request)
        if oldScavenge then
            check(ready and handoffs == 1 and not sc.ActionSupervisor.isCurrent(oldScavenge),
                "trip packing safely takes over an old routine scavenge before moving exact gear")
        end
        check(ready and assessment.cargoReady and contents:contains(food)
                and fellow.primary == axe and fellow.inventory:contains(axe)
                and fellow.inventory:contains(favorite) and favorite:isFavorite()
                and fellow.inventory:contains(cargo) and cargo:getModData().LF_QuestItem == true
                and (placement ~= "held" or fellow.secondary == bag),
            "preparation packs ordinary supplies into a " .. placement .. " bag without moving protected gear")
        local bags = 0
        for _, row in ipairs(assessment.bags) do
            if row.id ~= "inventory" then
                bags = bags + 1
                check(row.name == bag:getName() and row.capacity == 28,
                    "the " .. placement .. " bag retains its reported name and capacity")
            end
        end
        check(bags == 1 and sc.GameplayUtil.itemStableId(bag, false) == nil,
            "an unidentified " .. placement .. " bag is reported without assigning a persistent identity")
        check(assessment.cargoBagId ~= "inventory" and assessment.cargoBagName == bag:getName()
                and assessment.supplies.food.carried >= 1,
            "the preparation report identifies its real cargo bag and carried supplies")
        request = { key = "raw-reserve-" .. placement, atCamp = false, allowHeldBag = true,
            cargoRaw = 28, cargoEffective = 1.6, haulRequired = true,
            requiredTools = { { itemType = "Base.HandAxe" } } }
        ready, assessment = prepare(fellow, request)
        check(not ready and assessment.rawFree < 28 and assessment.carryWeight + 1.6 <= 10
                and contents:contains(food),
            "raw cargo space remains mandatory despite a small effective reserve in a " .. placement .. " bag")
    end

    local base = sc.BaseLife
    local oldInside, oldActive, oldRows, oldStorage, oldResolve = base.isInside,
        base.active, base.storageRows, base.storage, base.resolveContainer
    local axe = item("Base.HandAxe", "Weapon", { weight = 1 })
    local food = item("Base.CannedPeasPreparation", "Food", { weight = 0.2, hungerChange = -0.2 })
    local water = item("Base.WaterBottlePreparation", "Food", { weight = 0.2,
        fluidContainer = { getAmount = function() return 0.5 end, getCapacity = function() return 1 end,
            isEmpty = function() return false end, isWaterOnlySource = function() return true end } })
    local bandage = item("Base.BandagePreparation", "Medical", { weight = 0.1 })
    local favorite = item("Base.FavoriteCampPreparation", "Item", { favorite = true, weight = 0.5 })
    local cargo = item("Base.QuestCampPreparation", "Item", { weight = 0.5 })
    cargo:getModData().LF_QuestItem = true
    local kept = item("Base.MissionKeptPreparation", "Item", { weight = 0.5 })
    local keptId = sc.GameplayUtil.itemStableId(kept, true)
    local surplus = item("Base.OrdinarySurplusPreparation", "Item", { weight = 8 })
    local fellow = resident("camp", { axe, food, water, bandage, favorite, cargo, kept, surplus })
    fellow.primary = axe
    local shelf = containerObject(fellow.square, {})
    local row = { id = "storage:preparation", category = "general", deposits = true, withdrawals = false }
    base.isInside = function() return true end
    base.active = function() return { id = "base:preparation" } end
    base.storageRows = function(category, withdrawals)
        return withdrawals ~= true and (category == nil or category == "general") and { row } or {}
    end
    base.storage = function(id) return id == row.id and row or nil end
    base.resolveContainer = function(storage) if storage == row then return shelf, shelf.owner end end
    local function request(key, weight)
        return { key = key, atCamp = true, allowBagUpgrade = false, cargoRaw = weight,
            haulRequired = true, keepItems = { keptId }, requiredTools = { { itemType = "Base.HandAxe" } } }
    end
    local ready, assessment, preparationReason = prepare(fellow, request("camp-surplus", 4))
    check(ready and shelf:contains(surplus) and not fellow.inventory:contains(surplus)
            and fellow.primary == axe and fellow.inventory:contains(food) and fellow.inventory:contains(water)
            and fellow.inventory:contains(bandage) and fellow.inventory:contains(favorite)
            and fellow.inventory:contains(cargo) and fellow.inventory:contains(kept),
        "camp preparation stages ordinary surplus while retaining basics, required tools and protected cargo"
            .. ": ready=" .. tostring(ready) .. " reason=" .. tostring(preparationReason)
            .. " stage=" .. tostring(assessment and assessment.stage)
            .. " surplusShelf=" .. tostring(shelf:contains(surplus))
            .. " surplusRoot=" .. tostring(fellow.inventory:contains(surplus))
            .. " axe=" .. tostring(fellow.primary == axe) .. " food=" .. tostring(fellow.inventory:contains(food))
            .. " water=" .. tostring(fellow.inventory:contains(water))
            .. " medicine=" .. tostring(fellow.inventory:contains(bandage))
            .. " favorite=" .. tostring(fellow.inventory:contains(favorite))
            .. " cargo=" .. tostring(fellow.inventory:contains(cargo)) .. " kept=" .. tostring(fellow.inventory:contains(kept)))
    ready, assessment = prepare(fellow, request("protected-cargo", 8))
    check(not ready and assessment.reason == "loadout_carry_capacity"
            and fellow.inventory:contains(food) and fellow.inventory:contains(water)
            and fellow.inventory:contains(bandage) and fellow.inventory:contains(favorite)
            and fellow.inventory:contains(cargo) and fellow.inventory:contains(kept),
        "preparation blocks a larger cargo reserve instead of shelving essentials or protected items")
    shelf:Remove(surplus)
    fellow.inventory:AddItem(surplus)
    shelf.capacity = 0
    local groundBefore = #fellow.square.worldItems
    ready, assessment = prepare(fellow, request("full-storage", 4))
    check(not ready and assessment.reason == "loadout_carry_capacity"
            and string.find(table.concat(assessment.warnings, ":"), "loadout_storage_unavailable", 1, true)
            and fellow.inventory:contains(surplus) and not shelf:contains(surplus)
            and #fellow.square.worldItems == groundBefore,
        "full camp storage leaves surplus owned and blocks the required reserve without a ground drop")
    surplus.weight = 1
    ready, assessment = prepare(fellow, request("full-storage-room", 4))
    check(ready and assessment.cargoReady and fellow.inventory:contains(surplus)
            and not shelf:contains(surplus) and #fellow.square.worldItems == groundBefore
            and string.find(table.concat(assessment.warnings, ":"), "loadout_storage_unavailable", 1, true),
        "full storage permits a reduced-room departure when the minimum haul still fits")

    local priorSelection = sc.Navigation.selectInteraction
    shelf.capacity = 50
    sc.Navigation.selectInteraction = function(subject, ownerState, ...)
        if subject == fellow then return nil, "pending" end
        return priorSelection(subject, ownerState, ...)
    end
    local surveyRequest = request("pending-optional-storage-survey", 4)
    ready, assessment = prepare(fellow, surveyRequest)
    check(not ready and fellow.inventory:contains(surplus),
        "optional route selection gets its bounded opportunity before being skipped")
    f.clock = f.clock + 6000
    ready, assessment = prepare(fellow, surveyRequest)
    check(ready and assessment.cargoReady and fellow.inventory:contains(surplus)
            and not shelf:contains(surplus) and sc.ActionSupervisor.reservationCount(fellow) == 0
            and string.find(table.concat(assessment.warnings, ":"), "loadout_storage_unreachable", 1, true),
        "optional destination planning cannot hold departure indefinitely; exact surplus remains carried")
    sc.Logistics.resetPreparation(fellow)
    sc.Navigation.selectInteraction = priorSelection

    -- A long walk/loot pose can change encumbrance without invalidating the
    -- chosen surplus. More than one scan slice must not replay that pose.
    shelf.capacity = 50
    local priorAccess, priorRequest = sc.GameplayUtil.directInteractionAccess, sc.Navigation.requestAny
    sc.GameplayUtil.directInteractionAccess = function(subject, object, ...)
        if subject == fellow then return false, { fellow.square }, "interaction_route_pending" end
        return priorAccess(subject, object, ...)
    end
    sc.Navigation.requestAny = function(subject, ...)
        if subject == fellow then
            local options = select(3, ...)
            sc.ActionSupervisor.transition(options.supervisorToken, "approaching")
            sc.ActionSupervisor.progress(options.supervisorToken, "search:" .. f.clock)
            return true, "searching"
        end
        return priorRequest(subject, ...)
    end
    local stallRequest = request("crowded-storage", 4)
    ready = prepare(fellow, stallRequest)
    check(not ready and fellow.inventory:contains(surplus), "blocked optional stashing starts without moving its item")
    ready, assessment = prepare(fellow, stallRequest)
    check(ready and assessment.cargoReady and fellow.inventory:contains(surplus) and not shelf:contains(surplus)
            and sc.ActionSupervisor.reservationCount(fellow) == 0
            and string.find(table.concat(assessment.warnings, ":"), "loadout_storage_unreachable", 1, true),
        "stationary storage search yields departure with exact surplus retained when cargo still fits"
            .. ": ready=" .. tostring(ready) .. " reason=" .. tostring(assessment and assessment.reason)
            .. " warnings=" .. table.concat(assessment and assessment.warnings or {}, ":")
            .. " reservations=" .. sc.ActionSupervisor.reservationCount(fellow))
    local priorX, movingX = fellow.getX, fellow:getX()
    fellow.getX = function() return movingX end
    local movingRequest = request("moving-storage", 4)
    for _ = 1, 45 do
        sc.Logistics.prepareLoadout(fellow, movingRequest, safe)
        movingX, f.clock = movingX + .3, f.clock + 501
    end
    assessment = sc.Logistics.preparationStatus(fellow)
    check(assessment and assessment.stage ~= "blocked" and #assessment.warnings == 0
            and fellow.inventory:contains(surplus) and not shelf:contains(surplus),
        "a long approach with real physical progress is not skipped")
    for _ = 1, 25 do
        movingX, f.clock = movingX + .3, f.clock + 501
        sc.Logistics.prepareLoadout(fellow, movingRequest, safe)
    end
    ready, assessment = prepare(fellow, movingRequest)
    check(ready and assessment.cargoReady and fellow.inventory:contains(surplus)
            and not shelf:contains(surplus) and sc.ActionSupervisor.reservationCount(fellow) == 0
            and string.find(table.concat(assessment.warnings, ":"), "loadout_stashing_deferred", 1, true),
        "continued movement cannot extend optional stashing indefinitely; surplus and cargo checks survive")
    local unsafeRequest = request("moving-storage-required-room", 8)
    for _ = 1, 75 do
        movingX, f.clock = movingX + .3, f.clock + 501
        sc.Logistics.prepareLoadout(fellow, unsafeRequest, safe)
    end
    ready, assessment = prepare(fellow, unsafeRequest)
    check(not ready and assessment.reason == "loadout_carry_capacity"
            and fellow.inventory:contains(surplus) and not shelf:contains(surplus)
            and sc.ActionSupervisor.reservationCount(fellow) == 0,
        "optional stashing deadline never bypasses the required cargo reserve")
    sc.Logistics.resetPreparation(fellow)
    fellow.getX = priorX
    sc.GameplayUtil.directInteractionAccess, sc.Navigation.requestAny = priorAccess, priorRequest
    do
        local first = item("Base.FirstShelfPreparation", "Item", { weight = .1 })
        local plank = item("Base.Plank", "Item", { weight = .1 })
        local last = item("Base.LastShelfPreparation", "Item", { weight = .1 })
        local storageRows, storageById, resolve = base.storageRows, base.storage, base.resolveContainer
        local constructionShelf = containerObject(fellow.square, {})
        local construction = { id = "storage:preparation-construction", category = "construction", deposits = true }
        base.storageRows = function(category, withdrawals)
            if category == "construction" then return { construction } end
            return storageRows(category, withdrawals)
        end
        base.storage = function(id) return id == construction.id and construction or storageById(id) end
        base.resolveContainer = function(storage)
            if storage == construction then return constructionShelf, constructionShelf.owner end
            return resolve(storage)
        end
        -- The existing surplus starts the general shelf visit. Inventory order
        -- then alternates categories, but the last general item should go first.
        fellow.inventory:AddItem(first)
        fellow.inventory:AddItem(plank)
        fellow.inventory:AddItem(last)
        local order, addGeneral, addConstruction = {}, shelf.AddItem, constructionShelf.AddItem
        shelf.AddItem = function(destination, moved)
            order[#order + 1] = moved
            return addGeneral(destination, moved)
        end
        constructionShelf.AddItem = function(destination, moved)
            order[#order + 1] = moved
            return addConstruction(destination, moved)
        end
        ready, assessment = prepare(fellow, request("group-shelf-visits", 4))
        local positions = {}
        for index, moved in ipairs(order) do positions[moved] = index end
        check(ready and shelf:contains(first) and shelf:contains(last) and constructionShelf:contains(plank)
                and positions[last] < positions[plank],
            "preparation groups deposits at the current shelf while respecting construction storage"
                .. ": ready=" .. tostring(ready) .. " reason=" .. tostring(assessment and assessment.reason)
                .. " first=" .. tostring(positions[first]) .. " last=" .. tostring(positions[last])
                .. " plank=" .. tostring(positions[plank]) .. " construction=" .. tostring(constructionShelf:contains(plank)))
        shelf.AddItem, constructionShelf.AddItem = addGeneral, addConstruction
        base.storageRows, base.storage, base.resolveContainer = storageRows, storageById, resolve
        shelf:Remove(surplus)
        fellow.inventory:AddItem(surplus)
    end
    local fillers = {}
    for index = 1, 245 do
        fillers[index] = item("Base.KeptPreparation" .. tostring(index), "Item", { favorite = true, weight = 0 })
        fellow.inventory:AddItem(fillers[index])
    end
    local originalMovement, originalMaximum, originalAdd = sc.Actor.setMovement, fellow.getMaxWeight, shelf.AddItem
    local poses, deposits = 0, 0
    sc.Actor.setMovement = function(subject, mode, intent)
        if subject == fellow and intent and intent.action == "loot_container" and intent.item == surplus then
            poses = poses + 1
            if poses == 1 then
                f.clock = f.clock + 35000
                water.weight = water.weight + 0.01
                fellow.getMaxWeight = function() return 11 end
            end
        end
        return originalMovement(subject, mode, intent)
    end
    shelf.AddItem = function(destination, transferred)
        if transferred == surplus then deposits = deposits + 1 end
        return originalAdd(destination, transferred)
    end
    ready, assessment = prepare(fellow, request("changing-carry-load", 4))
    sc.Actor.setMovement, fellow.getMaxWeight, shelf.AddItem = originalMovement, originalMaximum, originalAdd
    water.weight = 0.2
    check(ready and shelf:contains(surplus) and not fellow.inventory:contains(surplus)
            and deposits == 1 and poses == 1 and fellow.inventory:contains(kept)
            and sc.ActionSupervisor.reservationCount(fellow) == 0,
        "preparation reconciles changed carry values across a large inventory and deposits exact surplus once")
    for _, filler in ipairs(fillers) do fellow.inventory:Remove(filler) end

    shelf:Remove(surplus)
    fellow.inventory:AddItem(surplus)
    local changedKit = request("newly-required-surplus", 4)
    local surplusId = sc.GameplayUtil.itemStableId(surplus, true)
    local protectedPose = false
    sc.Actor.setMovement = function(subject, mode, intent)
        if subject == fellow and intent and intent.action == "loot_container" and intent.item == surplus then
            protectedPose = true
            changedKit.keepItems[#changedKit.keepItems + 1] = surplusId
        end
        return originalMovement(subject, mode, intent)
    end
    prepare(fellow, changedKit)
    sc.Actor.setMovement = originalMovement
    check(protectedPose and fellow.inventory:contains(surplus) and not shelf:contains(surplus)
            and surplus:getContainer() == fellow.inventory
            and sc.ActionSupervisor.reservationCount(fellow) == 0,
        "preparation revalidates a newly required exact kit item before depositing it")

    local function ration(name, kind, fresh)
        local value = item("Base." .. name, "Food", { weight = 0.1, hungerChange = -0.2 })
        function value:getFoodType() return kind end
        function value:isFresh() return fresh == true end
        function value:getOffAge() return fresh and 4 or 1000000000 end
        return value
    end
    for preferred = 1, 3 do
        local emergency = ration("MaggotsPreparation" .. preferred, "Insect")
        local normal = ration("CannedPeasPreparation" .. preferred, "Vegetables")
        local fresh = ration("PeachPreparation" .. preferred, "Fruit", true)
        local foods = { emergency }
        if preferred <= 2 then foods[#foods + 1] = normal end
        if preferred == 1 then foods[#foods + 1] = fresh end
        local carrier = resident("ration-priority-" .. preferred, { unpack(foods) })
        local wanted = preferred == 1 and fresh or preferred == 2 and normal or emergency
        local packed = prepare(carrier, { key = "ration-priority-" .. preferred,
            atCamp = true, allowBagUpgrade = false, cargoRaw = 1 })
        check(packed and carrier.inventory:contains(wanted),
            "packing keeps the best available food tier " .. preferred)
        for _, candidate in ipairs(foods) do
            if candidate ~= wanted then
                check(shelf:contains(candidate) and not carrier.inventory:contains(candidate),
                    "lower-priority food is stored instead of replacing the selected ration")
            end
        end
    end
    local oldAvailable, oldObject = base.availableCountExact, base.resolveObject
    local supply = containerObject(fellow.square, {})
    local supplies = { id = "storage:preparation-food", category = "food", withdrawals = true, deposits = false }
    local emergency = ration("MaggotsStoredPreparation", "Insect")
    local normal = ration("CannedPeasStoredPreparation", "Vegetables")
    local fresh = ration("PeachStoredPreparation", "Fruit", true)
    supply:AddItem(emergency) supply:AddItem(normal)
    for index = 1, 80 do supply:AddItem(item("Base.SupplyFiller" .. index, "Item", { favorite = true, weight = 0 })) end
    supply:AddItem(fresh)
    base.storageRows = function(_, withdrawals) return withdrawals and { supplies } or { row } end
    base.storage = function(id) return id == supplies.id and supplies or id == row.id and row or nil end
    base.resolveContainer = function(storage)
        local container = storage == supplies and supply or shelf
        return container, container.owner
    end
    base.resolveObject = function(storage) return storage == supplies and supply.owner or shelf.owner end
    base.availableCountExact = function(_, kind)
        for _, candidate in ipairs(supply.items) do if candidate:getFullType() == kind then return 1 end end
        return 0
    end
    local carrier = resident("stored-ration", {})
    ready = prepare(carrier, { key = "stored-ration", atCamp = true, allowBagUpgrade = false, cargoRaw = 1 })
    check(ready and carrier.inventory:contains(fresh) and supply:contains(emergency) and supply:contains(normal),
        "bounded supply discovery finds fresh food beyond its first scan slice")
    local stockAxe = item("Base.HandAxe", "Weapon", { weight = 1 })
    supply:AddItem(stockAxe)
    sc.GameplayUtil.directInteractionAccess = function() return false, { fellow.square }, "interaction_route_pending" end
    sc.Navigation.requestAny = function(subject, targets, mode, options)
        sc.ActionSupervisor.transition(options.supervisorToken, "approaching")
        sc.ActionSupervisor.progress(options.supervisorToken, "search:" .. f.clock)
        return true, "searching"
    end
    for _, purpose in ipairs({ "food", "tool" }) do
        local bottle = item("Base.WaterBottleStock" .. purpose, "Food", { weight = .2,
            fluidContainer = water:getFluidContainer() })
        local seeker = resident("bounded-stock-" .. purpose, { bottle })
        local req = { key = "bounded-stock-" .. purpose, atCamp = true, allowBagUpgrade = false, cargoRaw = 1,
            requiredTools = purpose == "tool" and { { itemType = "Base.HandAxe" } } or nil }
        for _ = 1, 75 do
            sc.Logistics.prepareLoadout(seeker, req, safe)
            f.clock = f.clock + 501
        end
        ready, assessment = prepare(seeker, req)
        check((purpose == "food" and ready
                and string.find(table.concat(assessment.warnings, ":"), "loadout_supplies_deferred", 1, true)
                and sc.ActionSupervisor.reservationCount(seeker) == 0)
            or (purpose == "tool" and not ready and sc.ActionSupervisor.reservationCount(seeker) > 0),
            "unreachable optional top-ups yield, while a required tool still prevents departure: " .. purpose)
        check(supply:contains(stockAxe) and not seeker.inventory:contains(stockAxe),
            "a timed supply approach never moves or recreates the exact source tool")
        sc.Logistics.resetPreparation(seeker)
    end
    sc.GameplayUtil.directInteractionAccess, sc.Navigation.requestAny = priorAccess, priorRequest
    local pot = item("Base.Pot", "Item", { weight = 2, fluidContainer = water:getFluidContainer() })
    local lightBottle = item("Base.WaterBottleLightStock", "Food", { weight = .1, fluidContainer = water:getFluidContainer() })
    supply:AddItem(pot) supply:AddItem(lightBottle)
    local waterCarrier = resident("light-water-stock", {})
    ready = prepare(waterCarrier, { key = "light-water-stock", atCamp = true, allowBagUpgrade = false, cargoRaw = 1 })
    check(ready and waterCarrier.inventory:contains(lightBottle) and supply:contains(pot),
        "preparation prefers a light drinking container over the first stored cooking pot")
    base.availableCountExact, base.resolveObject = oldAvailable, oldObject
    base.isInside, base.active, base.storageRows, base.storage, base.resolveContainer =
        oldInside, oldActive, oldRows, oldStorage, oldResolve
    for _, fellow in ipairs(residents) do
        sc.Logistics.resetPreparation(fellow)
        sc.Logistics.reset(fellow)
        sc.ActionSupervisor.releaseActor(fellow)
        registry[fellow.id] = nil
        fellow.dead = true
    end
    f.clock = originalClock
end
SurvivorCompanion.__testPreparationPacking()
SurvivorCompanion.__testPreparationPacking = nil

print("LOADOUT_PASS checks=" .. tostring(f.checks()))
