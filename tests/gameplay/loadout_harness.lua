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
        local ready, assessment = prepare(fellow, request)
        check(ready and assessment.cargoReady and contents:contains(food)
                and fellow.primary == axe and fellow.inventory:contains(axe)
                and fellow.inventory:contains(favorite) and favorite:isFavorite()
                and fellow.inventory:contains(cargo) and cargo:getModData().LF_QuestItem == true
                and (placement ~= "held" or fellow.secondary == bag),
            "preparation packs ordinary supplies into a " .. placement .. " bag without moving protected gear")
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

    -- A long walk/loot pose can change encumbrance without invalidating the
    -- chosen surplus. More than one scan slice must not replay that pose.
    shelf.capacity = 50
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
