-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Logistics = SC.Logistics or {}
local Logistics = SC.Logistics
local states = setmetatable({}, { __mode = "k" })
local pendingGifts = setmetatable({}, { __mode = "k" })
local storageFor
local Preparation = { actors = setmetatable({}, { __mode = "k" }) }

local function U()
    return SC.GameplayUtil
end

local function nestedInventory(item)
    local nested, ok = U().call(item, "getItemContainer")
    if ok and nested then return nested, true end
    return U().call(item, "getInventory")
end

local function supervisor()
    if type(SC.ActionSupervisor) == "table" then return SC.ActionSupervisor end
    return nil
end

local function walkContainer(container, limit, callback, visited)
    if not container or limit.remaining <= 0 then return end
    visited = visited or setmetatable({}, { __mode = "k" })
    if visited[container] then return end
    visited[container] = true
    local items, itemsOk = U().call(container, "getItems")
    if not itemsOk and type(container) == "table" then items = container.items or container end
    U().each(items, limit.remaining, function(item)
        limit.remaining = limit.remaining - 1
        if callback(item, container) == false or limit.remaining <= 0 then return false end
        local nested, nestedOk = nestedInventory(item)
        if nestedOk and nested then walkContainer(nested, limit, callback, visited) end
        return limit.remaining > 0
    end)
end

local profiles = {
    generalist = {
        target = { food = 2, water = 2, medicine = 3, weapon = 2,
            ammunition = 4, clothing = 1, tools = 1, construction = 1,
            crafting = 1, farming = 1, container = 1 },
        keep = { food = 1, water = 1, medicine = 2, weapon = 1,
            ammunition = 0, clothing = 0, tools = 0, construction = 0,
            crafting = 0, farming = 0, container = 1 },
    },
    guard = {
        target = { food = 2, water = 2, medicine = 3, weapon = 3,
            ammunition = 10, clothing = 1, tools = 1, construction = 0,
            crafting = 0, farming = 1, container = 1 },
        keep = { food = 1, water = 1, medicine = 2, weapon = 1,
            ammunition = 3, clothing = 0, tools = 0, construction = 0,
            crafting = 0, farming = 0, container = 1 },
    },
    builder = {
        target = { food = 2, water = 2, medicine = 2, weapon = 1,
            ammunition = 2, clothing = 1, tools = 5, construction = 12,
            crafting = 6, farming = 1, container = 1 },
        keep = { food = 1, water = 1, medicine = 1, weapon = 1,
            ammunition = 0, clothing = 0, tools = 2, construction = 2,
            crafting = 1, farming = 0, container = 1 },
    },
    quartermaster = {
        target = { food = 6, water = 4, medicine = 6, weapon = 3,
            ammunition = 12, clothing = 4, tools = 4, construction = 16,
            crafting = 12, farming = 1, container = 2 },
        keep = { food = 2, water = 2, medicine = 2, weapon = 1,
            ammunition = 2, clothing = 1, tools = 1, construction = 1,
            crafting = 1, farming = 0, container = 1 },
    },
    medic = {
        target = { food = 2, water = 2, medicine = 10, weapon = 1,
            ammunition = 3, clothing = 1, tools = 1, construction = 0,
            crafting = 2, farming = 1, container = 1 },
        keep = { food = 1, water = 1, medicine = 5, weapon = 1,
            ammunition = 0, clothing = 0, tools = 0, construction = 0,
            crafting = 0, farming = 0, container = 1 },
    },
    farmer = {
        target = { food = 3, water = 3, medicine = 2, weapon = 1,
            ammunition = 2, clothing = 1, tools = 2, construction = 0,
            crafting = 1, farming = 2, container = 1 },
        keep = { food = 1, water = 1, medicine = 1, weapon = 1,
            ammunition = 0, clothing = 0, tools = 1, construction = 0,
            crafting = 0, farming = 0, container = 1 },
    },
}

local storageCategory = {
    food = "food", water = "water", medicine = "medical",
    weapon = "weapons", ammunition = "ammunition", tools = "tools",
    construction = "construction", crafting = "crafting",
    farming = "farming",
    literature = "literature", clothing = "clothing", container = "general",
    general = "general", trash = "general", valuables = "valuables",
}

local roleWeights = {
    generalist = { food = 5, water = 6, medicine = 6, weapon = 5,
        ammunition = 2, clothing = 2, tools = 3, construction = 2, crafting = 2,
        farming = 3 },
    guard = { food = 4, water = 6, medicine = 6, weapon = 10,
        ammunition = 10, clothing = 2, tools = 2, construction = 0, crafting = 0 },
    builder = { food = 4, water = 6, medicine = 4, weapon = 3,
        ammunition = 1, clothing = 2, tools = 10, construction = 10, crafting = 8 },
    quartermaster = { food = 8, water = 8, medicine = 7, weapon = 5,
        ammunition = 6, clothing = 5, tools = 7, construction = 9, crafting = 9 },
    medic = { food = 4, water = 6, medicine = 12, weapon = 3,
        ammunition = 1, clothing = 3, tools = 3, construction = 0, crafting = 4 },
    farmer = { food = 8, water = 8, medicine = 3, weapon = 3,
        ammunition = 1, clothing = 2, tools = 7, construction = 1, crafting = 2,
        farming = 12 },
}

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function typeContains(itemType, fragments)
    for _, fragment in ipairs(fragments) do
        if string.find(itemType, fragment, 1, true) then return true end
    end
    return false
end

-- Things worth carrying home for nobody: ruined gear that cannot be repaired,
-- and the small rubbish a scavenging run accumulates. Deliberately narrow -- a
-- companion quietly binning something useful is far worse than one carrying a
-- broken fork -- so it is an explicit list plus provably ruined condition, and
-- never a favourite or a keepsake.
local TRASH_TYPES = {
    "dirtyrag", "burntfood", "emptybottle", "brokenglass", "brokenbottle",
    "garbagebag", "tinlid", "cigarettebutt", "unusablemetal", "unusablewood",
}

function Logistics.isTrash(item)
    if item == nil then return false end
    local utility = U()
    if utility.call(item, "isFavorite") == true then return false end
    if SC.PersonalItems and type(SC.PersonalItems.personalRecord) == "function"
        and SC.PersonalItems.personalRecord(item) ~= nil then
        return false
    end
    local itemType = lower(utility.itemType(item) or "")
    if itemType == "" then return false end
    if typeContains(itemType, TRASH_TYPES) then return true end
    -- Ruined and beyond repair: a weapon or tool at zero condition is weight.
    local condition, conditionOk = utility.call(item, "getCondition")
    local maximum, maximumOk = utility.call(item, "getConditionMax")
    if conditionOk and maximumOk and tonumber(maximum) ~= nil
        and tonumber(maximum) > 0 and tonumber(condition) == 0 then
        return true
    end
    return false
end

local function isClothingItem(item)
    if not item then return false end
    local clothing, clothingOk = U().call(item, "IsClothing")
    if clothingOk and clothing == true then return true end
    if U().instanceOf(item, "Clothing") then return true end
    local category, categoryOk = U().call(item, "getCategory")
    local display, displayOk = U().call(item, "getDisplayCategory")
    return (categoryOk and lower(category) == "clothing")
        or (displayOk and lower(display) == "clothing")
end

-- Filtered masks consume their fitted filter while worn. Their use is a
-- player's loadout choice, including the improvised native variant.
function Logistics.manualOnlyFilterMask(item)
    if not item or type(U().itemHasTag) ~= "function" then return false end
    for _, tag in ipairs({ "gasmask", "gasmasknofilter", "respirator",
        "respiratornofilter", "improvisedgasmask" }) do
        if U().itemHasTag(item, tag) then return true end
    end
    return false
end
Logistics.isManualOnlyFilterMask = Logistics.manualOnlyFilterMask

function Logistics.itemCategory(item)
    local utility = U()
    if SC.CleaningSupplies and SC.CleaningSupplies.containsCleaner(item) then return "tools" end
    local itemType = lower(utility.itemType(item))
    local category, categoryOk = utility.call(item, "getCategory")
    category = categoryOk and lower(category) or ""
    local display, displayOk = utility.call(item, "getDisplayCategory")
    display = displayOk and lower(display) or ""
    -- Before any category can claim it: a ruined axe is still an axe by type,
    -- and would otherwise be shelved with the weapons.
    if Logistics.isTrash(item) then return "trash" end
    if SC.BaseLife and SC.BaseLife.isValuableItem
        and SC.BaseLife.isValuableItem(item) then return "valuables" end
    if SC.FarmWork and type(SC.FarmWork.isFarmingSupply) == "function"
        and SC.FarmWork.isFarmingSupply(item) == true then return "farming" end
    -- Check the engine category before filename heuristics. Ordinary magazines
    -- otherwise match the ammunition fragment below and get shelved with ammo.
    if category == "literature" or display == "literature" then return "literature" end
    if typeContains(itemType, { "bandage", "rippedsheet", "disinfect", "painkiller",
        "antibiotic", "suture", "firstaid", "alcoholwipes", "pills" })
        or category == "medical" or display == "medical" then return "medicine" end
    if SC.Needs and type(SC.Needs.isDrinkingContainer)=="function"
        and SC.Needs.isDrinkingContainer(item) then return "water" end
    if typeContains(itemType, { "waterbottle", "canteen", "flask" })
        or utility.itemHasTag(item, "WaterContainer") then return "water" end
    if category == "food" or utility.hasMethod(item, "getCalories") then return "food" end
    -- Runtime class identity must win over filename heuristics: vanilla armor
    -- types such as Vest_BulletCivilian contain "bullet" but are Clothing,
    -- not ammunition.
    if isClothingItem(item) or category == "clothing" or display == "clothing" then
        return "clothing"
    end
    if typeContains(itemType, { "ammo", "bullet", "shell", "cartridge", "magazine" })
        or category == "ammunition" then return "ammunition" end
    --[[
    A pen is defined in the game's own weapon.txt with ItemType = base:weapon,
    so it used to count toward the weapon loadout. Combat refuses to swing a
    diarist's pen (weaponRecord skips writing implements), so a companion
    carrying two pens reported a satisfied weapon loadout, stopped scavenging
    weapons entirely, and then fled every fight bare-handed. The two systems
    have to agree on what a weapon is.

    A weapon at zero condition is likewise not one for loadout purposes:
    weaponUsableNow rejects it in combat, so counting it as satisfying the
    need would keep a companion "armed" with something it will never swing.
    ]]
    if utility.instanceOf(item, "HandWeapon") or category == "weapon" then
        local hasData, hasDataOk = utility.call(item, "hasModData")
        if (not hasDataOk or hasData == true) and SC.PersonalItems
            and type(SC.PersonalItems.personalRecord) == "function" then
            local personal = SC.PersonalItems.personalRecord(item)
            if personal and personal.kind == "writing_implement" then return "general" end
        end
        local conditionValue = select(1, utility.call(item, "getCondition"))
        local condition = tonumber(conditionValue)
        if condition ~= nil and condition <= 0 then return "general" end
        return "weapon"
    end
    if typeContains(itemType, { "plank", "nails", "log", "cement", "concrete",
        "sandbag", "gravelbag", "wire", "metalbar", "metalpipe", "sheetmetal" })
        or display == "material" or category == "material" then return "construction" end
    if utility.itemHasTag(item, "Hammer") or utility.itemHasTag(item, "Axe")
        or utility.itemHasTag(item, "Saw") or utility.itemHasTag(item, "Screwdriver")
        or typeContains(itemType, { "hammer", "hatchet", "woodaxe", "handsaw",
            "screwdriver", "wrench", "crowbar", "torch", "weldermask" })
        or category == "tool" or display == "tool" then return "tools" end
    -- A battery is crafting stock, which means it is always worth carrying
    -- home -- and it is also what keeps a flashlight working, so a companion
    -- that never picks one up can never swap a flat torch. A car battery is
    -- thirty kilos of vehicle part and is emphatically not this.
    if string.find(itemType, "battery", 1, true) ~= nil
        and string.find(itemType, "carbattery", 1, true) == nil then
        return "crafting"
    end
    if typeContains(itemType, { "scrap", "electronic", "screws", "glue", "ducttape",
        "adhesivetape", "twine", "thread", "leather", "rope", "tarp", "fabric" })
        or display == "crafting" then return "crafting" end
    local nested, nestedOk = nestedInventory(item)
    if nestedOk and nested then return "container" end
    return "general"
end

function Logistics.roleOf(actor)
    local id = actor and U().idOf(actor) or nil
    if id and SC.BaseLife and type(SC.BaseLife.resident) == "function" then
        local resident = SC.BaseLife.resident(id)
        if resident and profiles[resident.role] then return resident.role end
    end
    if id and SC.Registry and type(SC.Registry.byId) == "function"
        and SC.Background and type(SC.Background.preferredRole) == "function" then
        local record = SC.Registry.byId(id)
        local personality = record and type(record.state) == "table"
            and type(record.state.personality) == "table" and record.state.personality or nil
        local background = personality and personality.background
            or (record and record.background)
        local role = background and SC.Background.preferredRole(background) or nil
        if profiles[role] then return role end
    end
    return "generalist"
end

function Logistics.roleMinimums(actor)
    local profile = profiles[Logistics.roleOf(actor)] or profiles.generalist
    return profile.keep
end

local function overloadAllowed(actor)
    -- Logistics.status is used as a read-only decision probe. Reading the
    -- already-persisted actor flag avoids Commands.peek() initializing a new
    -- command state (and its personal keepsake) merely because load was read.
    local data, dataOk = U().call(actor, "getModData")
    if dataOk and type(data) == "table" then return data.SC_AllowOverload == true end
    return false
end

local function loadRatios(role, actor)
    if overloadAllowed(actor) then
        return U().config("logisticsOverloadSoftLoadRatio") or 1.0,
            U().config("logisticsOverloadHardLoadRatio") or 1.2
    end
    if role == "quartermaster" then
        return U().config("logisticsQuartermasterSoftLoadRatio") or 0.82,
            U().config("logisticsQuartermasterHardLoadRatio") or 0.95
    end
    return U().config("logisticsSoftLoadRatio") or 0.72,
        U().config("logisticsHardLoadRatio") or 0.90
end

-- Exact items a job owns until it delivers them: field-order harvest, wood
-- and borrowed axes, a harvest kept for pickup, refuel/upkeep supplies and
-- expedition receipts. keptHarvestDeposit admits one case: a harvest kept for
-- pickup because no car was chosen may go into camp storage.
local buildRequirements

-- A hammer, plank or nail fetched for a barricade is not surplus while that
-- barricade is still the worker's order, however loaded the worker is. Read the
-- saved order, because Commands.peek creates state and hands out a keepsake.
local function barricadeKit(actor, item)
    local data = select(1, U().call(actor, "getModData"))
    if type(data) ~= "table" or data.SC_Order ~= "work"
        or data.SC_WorkKind ~= "barricade" then return false end
    for _, requirement in ipairs(buildRequirements) do
        local ok, matched = pcall(requirement.predicate, item)
        if ok and matched == true then return true end
    end
    return false
end

local function workCargo(actor, item, keptHarvestDeposit)
    if barricadeKit(actor, item) then return true end
    if SC.BaseWork and type(SC.BaseWork.cargoReserved) == "function"
        and SC.BaseWork.cargoReserved(actor, item) then return true end
    if SC.Fishing and type(SC.Fishing.gearReserved) == "function"
        and SC.Fishing.gearReserved(actor, item) then return true end
    if SC.ExpeditionPrototype and SC.ExpeditionPrototype.receiptPending
        and SC.ExpeditionPrototype.receiptPending(item) then return true end
    local itemData = select(1, U().call(item, "getModData"))
    if type(itemData) ~= "table" then return false end
    -- Harvest and woodcut orders own their exact cargo until delivery or
    -- cancellation. Generic overload handling must never drop it as surplus.
    local fieldMarked = itemData.LF_FieldOrder ~= nil
        or itemData.LF_FieldBorrowedAxe ~= nil
        or itemData.LF_FieldCarryWorker ~= nil
    if fieldMarked
        and SC.FieldWork and type(SC.FieldWork.reserved) == "function"
        and SC.FieldWork.reserved(item) == true
        and not (keptHarvestDeposit and itemData.LF_FieldOrder == nil
            and itemData.LF_FieldBorrowedAxe == nil
            and itemData.LF_FieldCarryWorker == tostring(U().idOf(actor) or "")) then
        return true
    end
    if (itemData.LF_RefuelJobId ~= nil or itemData.LF_UpkeepJobId ~= nil)
        and (not SC.BaseFuel or type(SC.BaseFuel.reserved) ~= "function"
            or SC.BaseFuel.reserved(item) == true) then
        return true
    end
    -- The same ownership WorkTransport refuses to move out of storage must
    -- not be shed from a pack either: quest items and rewards, trade
    -- recovery, a chef's borrowed supplies (its receipt must find them
    -- again) and cleaning loans.
    if itemData.LF_QuestItem == true or itemData.LF_QuestReward == true
        or itemData.LF_TradeRecoveryId ~= nil
        or itemData.LF_TradeRecoveryBuildId ~= nil
        or itemData.SC_ChefSupplyReceipt ~= nil then
        return true
    end
    if (itemData.LF_CleanToolJobId ~= nil or itemData.LF_CleanLiquidJobId ~= nil)
        and SC.BaseWork and type(SC.BaseWork.choreReserved) == "function"
        and SC.BaseWork.choreReserved(item) == true then
        return true
    end
    -- Production, farm, gather/haul receipts and log-yard splits. Field
    -- markers are decided above, including the kept-harvest deposit case.
    if not fieldMarked and SC.WorkTransport
        and type(SC.WorkTransport.isCargoProtected) == "function"
        and SC.WorkTransport.isCargoProtected(item, actor, "loadout") == true then
        return true
    end
    return false
end

-- Weight an item adds to the actor's own load. A worn bag's weight
-- reduction applies to everything inside it, as in vanilla encumbrance.
local function carriedWeight(item, source, root)
    local weight = U().itemWeight(item)
    if source == nil or source == root then return weight end
    local holder = select(1, U().call(source, "getContainingItem"))
    local reduction = tonumber(holder and select(1, U().call(holder, "getWeightReduction")))
    if reduction and reduction > 0 and reduction <= 100 then
        weight = weight * (1 - reduction / 100)
    end
    return weight
end

function Logistics.audit(actor, preparedInventory)
    local role = Logistics.roleOf(actor)
    local profile = profiles[role] or profiles.generalist
    local counts, gearCounts, items = {}, {}, {}
    local cargoWeight = 0
    local root = U().inventory(actor)
    local scanBudget = { remaining = U().config("logisticsInventoryItemBudget") or 256 }
    if preparedInventory then
        counts, gearCounts, items, cargoWeight = preparedInventory.counts,
            preparedInventory.gearCounts, preparedInventory.items, preparedInventory.cargoWeight
    else walkContainer(root, scanBudget, function(item, source)
        local category = Logistics.itemCategory(item)
        counts[category] = (counts[category] or 0) + 1
        if workCargo(actor, item) then
            cargoWeight = cargoWeight + carriedWeight(item, source, root)
        else
            gearCounts[category] = (gearCounts[category] or 0) + 1
        end
        items[#items + 1] = { item = item, category = category, source = source }
        return true
    end)
    end
    local weight, capacity, ratio, inventory = U().inventoryLoad(actor)
    local soft, hard = loadRatios(role, actor)
    -- Playtest: a no-car harvest kept for pickup filled a companion to 76%,
    -- and overload handling then dropped his own food, spare axe, rags and
    -- ID cards to make room for cargo it may never drop. The harvest also
    -- inflated the food count, so his rations scored as the worst surplus.
    -- Shedding decisions therefore see only the actor's own gear; the real
    -- load still reports overload and limits what the actor will pick up.
    local gearRatio = capacity > 0
        and math.max(0, weight - cargoWeight) / capacity or 0
    -- capacity/ratio are the physical inventory scale: overload, dropping and
    -- loadout checks stay on it. The Strength limit only decides what a
    -- companion shelves at camp, where surplus goes into storage, never onto
    -- the ground.
    local _, carryCapacity = U().carryLoad(actor)
    local carryGearRatio = carryCapacity > 0
        and math.max(0, weight - cargoWeight) / carryCapacity or 0
    local farmWaterCan = role == "farmer" and ratio <= hard and SC.FarmWork
        and SC.FarmWork.carriedWaterContainer and SC.FarmWork.carriedWaterContainer(actor) or nil
    return {
        role = role, profile = profile, counts = counts, items = items,
        farmWaterCan = farmWaterCan,
        gearCounts = gearCounts, cargoWeight = cargoWeight, gearRatio = gearRatio,
        weight = weight, capacity = capacity, ratio = ratio,
        carryCapacity = carryCapacity, carryGearRatio = carryGearRatio,
        softRatio = soft, hardRatio = hard, inventory = inventory,
        allowOverload = overloadAllowed(actor),
        inventoryComplete = preparedInventory ~= nil or scanBudget.remaining > 0,
    }
end

local function dynamicTarget(audit, category, actor)
    local target = tonumber(audit.profile.target[category]) or 0
    if category == "valuables" then return 3 end
    if category == "food" then
        local hunger = U().characterStatValue(actor, "HUNGER", 0)
        if hunger >= 0.7 then target = target + 1 end
    elseif category == "water" then
        local thirst = U().characterStatValue(actor, "THIRST", 0)
        if thirst >= 0.6 then target = target + 1 end
    end
    return target
end

local function wearableLocation(item)
    local utility = U()
    local location, locationOk = utility.call(item, "getBodyLocation")
    local text = locationOk and lower(location) or ""
    if locationOk and location ~= nil and location ~= false and text ~= ""
        and text ~= "none" and text ~= "null" and text ~= "false" then return location end
    location, locationOk = utility.call(item, "canBeEquipped")
    text = locationOk and lower(location) or ""
    if locationOk and location ~= nil and location ~= false and text ~= ""
        and text ~= "none" and text ~= "null" and text ~= "false" then return location end
    return nil
end

local function wornAt(actor, location)
    if not actor or location == nil then return nil end
    local worn, wornOk = U().call(actor, "getWornItem", location)
    return wornOk and worn or nil
end

local function isWorn(actor, item, location)
    if wornAt(actor, location or wearableLocation(item)) == item then return true end
    local equipped, equippedOk = U().call(actor, "isEquippedClothing", item)
    return equippedOk and equipped == true
end

local function replacementItems(actor, location)
    local utility = U()
    local result, seen = {}, setmetatable({}, { __mode = "k" })
    local wornItems, wornOk = utility.call(actor, "getWornItems")
    local size, sizeOk, group, groupOk = nil, false, nil, false
    if wornOk then
        size, sizeOk = utility.call(wornItems, "size")
        group, groupOk = utility.call(wornItems, "getBodyLocationGroup")
    end
    if sizeOk and tonumber(size) then
        for index = 0, math.min(tonumber(size) - 1, 63) do
            local worn, entryOk = utility.call(wornItems, "get", index)
            if entryOk and worn then
                local item, itemOk = utility.call(worn, "getItem")
                local wornLocation, locationOk = utility.call(worn, "getLocation")
                local replaces = locationOk and wornLocation == location
                if not replaces and groupOk and group and locationOk then
                    local exclusive, exclusiveOk = utility.call(
                        group, "isExclusive", location, wornLocation)
                    replaces = exclusiveOk and exclusive == true
                end
                if replaces and itemOk and item and not seen[item] then
                    seen[item] = true
                    result[#result + 1] = item
                end
            end
        end
    end
    local exact = wornAt(actor, location)
    if exact and not seen[exact] then result[#result + 1] = exact end
    return result
end

local function conditionRatio(item)
    local condition, conditionOk = U().call(item, "getCondition")
    local maximum, maxOk = U().call(item, "getConditionMax")
    if conditionOk and maxOk and tonumber(maximum) and tonumber(maximum) > 0 then
        return U().clamp((tonumber(condition) or 0) / tonumber(maximum), 0, 1)
    end
    return 1
end

local function numericMethod(item, methodName, fallback)
    local value, ok = U().call(item, methodName)
    return ok and tonumber(value) or fallback or 0
end

local function cosmeticWearable(item)
    local location = lower(wearableLocation(item))
    local itemType = lower(U().itemType(item))
    -- `wound` is the slot a zombie's visible injuries are worn in. They are
    -- hidden script items, so notRealGear() already refuses them before
    -- canTake reaches here; this keeps clothingScore consistent for any other
    -- path that consults the cosmetic test directly.
    local cosmeticLocation = location == "wound"
        or location == "leftwrist" or location == "rightwrist"
        or string.find(location, "wristwatch", 1, true) ~= nil
        or string.find(location, "necklace", 1, true) ~= nil
        or string.find(location, "earring", 1, true) ~= nil
        or string.find(location, "ring", 1, true) ~= nil
        or string.find(location, "bellybutton", 1, true) ~= nil
        or location == "nose" or location == "makeup"
    local cosmeticType = typeContains(itemType, {
        "wristwatch", "digitalred", "digitalblack", "bracelet", "necklace",
        "earring", "nosering", "nosepiercing", "bellybutton", "ring_",
        "brief", "underpants", "underwear", "bikini",
    })
    return cosmeticLocation or cosmeticType
end

function Logistics.clothingScore(item)
    if Logistics.manualOnlyFilterMask(item) then return -math.huge end
    if not item or not isClothingItem(item) or not wearableLocation(item)
        or cosmeticWearable(item) then
        return -math.huge
    end
    local broken, brokenOk = U().call(item, "isBroken")
    if brokenOk and broken then return -math.huge end
    local bite = numericMethod(item, "getBiteDefense", 0)
    local scratch = numericMethod(item, "getScratchDefense", 0)
    local bullet = numericMethod(item, "getBulletDefense", 0)
    local insulation = numericMethod(item, "getInsulation", 0)
    local wind = numericMethod(item, "getWindresistance", 0)
    local blood = numericMethod(item, "getBloodLevel", 0)
    local dirt = numericMethod(item, "getDirtiness", 0)
    local combat = numericMethod(item, "getCombatSpeedModifier", 1)
    local run = numericMethod(item, "getRunSpeedModifier", 1)
    return conditionRatio(item) * 24 + bite * 0.52 + scratch * 0.34 + bullet * 0.14
        + insulation * 3 + wind * 2 + (combat - 1) * 18 + (run - 1) * 14
        - blood * 0.07 - dirt * 0.04 - U().itemWeight(item) * 0.6
end

function Logistics.clothingUpgrade(actor, item)
    if Logistics.manualOnlyFilterMask(item) then return false, 0, nil, wearableLocation(item) end
    local location = wearableLocation(item)
    if not location or not isClothingItem(item) then
        return false, 0, nil, nil
    end
    local replacements = replacementItems(actor, location)
    local current = replacements[1]
    if isWorn(actor, item, location) then return false, 0, current, location end
    -- A player explicitly dressed this companion. Routine loadout decisions
    -- must not immediately undo that choice while the garment is still worn.
    for _, replaced in ipairs(replacements) do
        local data = select(1, U().call(replaced, "getModData"))
        local broken = select(1, U().call(replaced, "isBroken"))
        if type(data) == "table" and data.SC_ManualWearFor == U().idOf(actor)
            and broken ~= true then
            return false, 0, current, location
        end
    end
    local candidateScore = Logistics.clothingScore(item)
    if candidateScore == -math.huge then return false, 0, current, location end
    local currentScore = 0
    for _, replaced in ipairs(replacements) do
        local score = Logistics.clothingScore(replaced)
        -- Never replace a non-clothing wearable through a clothing decision;
        -- its utility is not comparable to garment protection.
        if score == -math.huge then return false, 0, current, location end
        currentScore = currentScore + score
    end
    local difference = candidateScore - currentScore
    return difference >= (U().config("logisticsClothingUpgradeMinimum") or 8),
        difference, current, location
end

local function bagScore(item)
    local nested, nestedOk = nestedInventory(item)
    local location = nestedOk and nested and wearableLocation(item) or nil
    if not location then return nil, nil, nil end
    local capacity = numericMethod(item, "getCapacity", 0)
    if capacity <= 0 then capacity = numericMethod(nested, "getCapacity", 0) end
    local reduction = U().clamp(numericMethod(item, "getWeightReduction", 0), 0, 100)
    return capacity * reduction / 100 - U().itemWeight(item) * 0.35,
        location, nested
end

function Logistics.bagUpgrade(actor, item)
    local score, location = bagScore(item)
    if not score or not location or isWorn(actor, item, location) then
        return false, 0, nil, location
    end
    local replacements = replacementItems(actor, location)
    local current = replacements[1]
    local currentScore = 0
    for _, replaced in ipairs(replacements) do
        local data = select(1, U().call(replaced, "getModData"))
        local broken = select(1, U().call(replaced, "isBroken"))
        if type(data) == "table" and data.SC_ManualWearFor == U().idOf(actor)
            and broken ~= true then
            return false, 0, current, location
        end
        local replacedScore = select(1, bagScore(replaced))
        -- Likewise, never let a bag decision silently remove armor or another
        -- wearable whose value cannot be represented as bag capacity.
        if replacedScore == nil then return false, 0, current, location end
        currentScore = currentScore + (tonumber(replacedScore) or 0)
    end
    local difference = score - currentScore
    return difference >= (U().config("logisticsBagUpgradeMinimum") or 2),
        difference, current, location
end

local function selectBagUpgrade(actor, audit)
    local best
    for _, record in ipairs(audit.items) do
        local score, location, nested = bagScore(record.item)
        if score and not isWorn(actor, record.item, location) then
            local accepted, difference = Logistics.bagUpgrade(actor, record.item)
            if accepted and (not best or difference > best.difference) then
                best = { item = record.item, source = record.source, location = location,
                    inventory = nested, score = score, difference = difference }
            end
        end
    end
    return best
end

--[[
Some script items are not gear at all. A zombie's visible injuries are
implemented as clothing worn in the `wound` body location -- weightless,
WorldRender = false, and marked `hidden = true` -- so a corpse "contains" items
like Wound_Abdomen_Bite_Male. A companion looted one and announced that they
had found a wound.

The cosmetic filter below is a hand-maintained list of slot names and type
substrings, and `wound` was not on it. Rather than add one more name, ask the
engine: Item.isHidden() marks anything not meant for a player's inventory, and
Item.isCosmetic() is the game's own notion of jewellery and similar. Both are
checked for every category, because a hidden item is never worth carrying
whatever bucket it is sorted into.
]]
local function notRealGear(item)
    local script = select(1, U().call(item, "getScriptItem"))
    if script == nil then return false end
    local hidden, hiddenOk = U().call(script, "isHidden")
    if hiddenOk and hidden == true then return true end
    local cosmetic, cosmeticOk = U().call(script, "isCosmetic")
    if cosmeticOk and cosmetic == true then return true end
    return false
end

-- A camp supply request includes stock beyond this carrier's own loadout.
-- Keep the broad request limited to the expedition's real supply categories;
-- miscellaneous objects, valuables and rubbish gain no new loot permission.
local usefulSupplyCategories = {
    food = true, water = true, medicine = true, weapon = true,
    ammunition = true, tools = true, construction = true, crafting = true,
    farming = true, clothing = true, container = true, literature = true,
}
local function requestedSupplyMatches(requestedCategory, category)
    return requestedCategory ~= nil and (requestedCategory == category
        or requestedCategory == "useful" and usefulSupplyCategories[category] == true)
end

function Logistics.canTake(actor, item, category, audit, requestedCategory, sourceStorage)
    if not actor or not item then return false, "invalid_loot" end
    if Logistics.manualOnlyFilterMask(item) then return false, "manual_only_filter_mask" end
    if notRealGear(item) then return false, "not_real_gear" end
    audit = audit or Logistics.audit(actor)
    category = category or Logistics.itemCategory(item)
    -- A loose watch may be sorted into Valuables at base, but a cosmetic
    -- wearable is still not a reason to stop scavenging and loot a corpse.
    if category == "valuables" and cosmeticWearable(item) then
        return false, "cosmetic_wearable"
    end
    if category == "clothing" then
        if cosmeticWearable(item) then return false, "cosmetic_wearable" end
        local upgrade = Logistics.clothingUpgrade(actor, item)
        if upgrade then
            if audit.capacity > 0 and audit.weight + U().itemWeight(item)
                > audit.capacity * audit.hardRatio then return false, "loadout_too_heavy" end
            return true, "clothing_upgrade"
        end
    end
    if category == "container" then
        local upgrade = Logistics.bagUpgrade(actor, item)
        if upgrade then
            if audit.capacity > 0 and audit.weight + U().itemWeight(item)
                > audit.capacity * audit.hardRatio then return false, "loadout_too_heavy" end
            return true, "bag_upgrade"
        end
    end
    local target = dynamicTarget(audit, category, actor)
    local needsWeapon = false
    if category == "weapon" and SC.Combat and SC.Combat.weaponOperational and SC.Combat.weaponAvailability
        and not requestedSupplyMatches(requestedCategory, category) then
        if not SC.Combat.weaponOperational(actor, item) then return false, "weapon_unusable" end
        local _, usable = SC.Combat.weaponAvailability(actor)
        needsWeapon = target > 0 and usable == 0
    end
    -- Marked camp stock is already home. Replenish the personal loadout,
    -- without taking extras that surplus handling would immediately shelve.
    -- Keep real equipment upgrades, unusable-weapon replacement and explicit
    -- supply requests on their existing checked paths.
    if sourceStorage and requestedCategory==nil and not needsWeapon then
        local carriedTarget=tonumber(audit.profile.target[category]) or 0
        if (audit.counts[category] or 0)>=carriedTarget then
            return false,"camp_stock_already_stored"
        end
    end
    if not needsWeapon and (target <= 0 or (audit.counts[category] or 0) >= target) then
        -- A finite expedition request can exceed this survivor's personal
        -- loadout target. The request never overrides the real carry limit.
        if requestedSupplyMatches(requestedCategory, category) then
            if audit.capacity > 0 and audit.weight + U().itemWeight(item)
                > audit.capacity * audit.hardRatio then
                return false, "loadout_too_heavy"
            end
            return true, "expedition_supply"
        end
        -- The base always has a use for more nails, planks, thread and tape,
        -- so crafting stock is not capped by a per-role target the way a third
        -- axe is. Weight caps it instead, and at the soft ratio rather than the
        -- hard one, so there is still room for the food, water and dressings a
        -- survivor picks up on the way home.
        if category ~= "crafting" and category ~= "construction" then
            return false, "loadout_satisfied"
        end
        local ceiling = tonumber(audit.softRatio) or audit.hardRatio
        if audit.capacity > 0 and ceiling ~= nil
            and audit.weight + U().itemWeight(item) > audit.capacity * ceiling then
            return false, "loadout_satisfied"
        end
        return true, "base_supply"
    end
    if audit.capacity > 0 then
        local projected = audit.weight + U().itemWeight(item)
        if projected > audit.capacity * audit.hardRatio then
            return false, "loadout_too_heavy"
        end
    end
    return true, "loadout_needed"
end

-- Need-driven scavenging priority.
--
-- Scoring used to be one flat formula -- a base, a stock deficit and a small
-- role weight -- so a survivor with no weapon at all could rate a TV dinner
-- above a machete sitting in the same room. The ladder below makes urgency
-- dominate: a higher tier always outranks a lower one, and the old formula
-- only decides order *within* a tier.
--
-- The order is the player's: a weapon first (and emphatically so while
-- unarmed), then a spare, then something to stop bleeding, then food and
-- water, then clothing and armour, then everything else. Each tier is
-- conditional on the survivor's actual state, so a bleeding companion does not
-- step over bandages to collect a second axe, and a well-fed one does not
-- hoard food.
local TIER = {
    desperate = 900,   -- no usable weapon, or bleeding with nothing to dress it
    urgent = 700,      -- starving, dying of thirst, wounded and untreated
    important = 500,   -- a spare weapon, ammunition for a carried firearm
    useful = 300,      -- ordinary restocking below target
    marginal = 120,    -- an upgrade worth taking if it is on the way
    ignore = 0,        -- nothing this survivor needs
}
-- Published so a harness can name a tier rather than pin its number.
Logistics.TIER = TIER

local function statValue(actor, name)
    local value = U().characterStatValue(actor, name, 0)
    return tonumber(value) or 0
end

-- Does the survivor have something they could actually swing right now? Reuses
-- the combat layer's own answer so "armed" means the same thing to the
-- scavenger as it does to the fighter -- a broken axe and a diarist's pen
-- count for neither.
local function armedState(actor)
    if SC.Combat == nil or type(SC.Combat.weaponAvailability) ~= "function" then
        return nil, nil
    end
    local carried, usable = SC.Combat.weaponAvailability(actor)
    carried, usable = tonumber(carried), tonumber(usable)
    if carried == nil or carried < 0 then return nil, nil end
    return carried, usable
end

local function untreatedInjury(actor)
    if SC.Medical == nil or type(SC.Medical.assess) ~= "function" then return false, false end
    local ok, assessment = pcall(SC.Medical.assessCached or SC.Medical.assess, actor)
    if not ok or type(assessment) ~= "table" then return false, false end
    -- Field names are Medical.assess's own: bleedingCount counts parts that
    -- are bleeding and NOT already bandaged, so it is exactly "needs a bandage
    -- right now"; openWounds counts dressing that is missing but not urgent.
    local bleeding = assessment.needsBandage == true
        or (tonumber(assessment.bleedingCount) or 0) > 0
    local wounded = bleeding
        or (tonumber(assessment.openWounds) or 0) > 0
        or (tonumber(assessment.dirtyBandages) or 0) > 0
    return bleeding, wounded
end

-- The urgency tier for one category, given what this survivor is short of.
function Logistics.needTier(actor, category, audit, hasStock)
    audit = audit or Logistics.audit(actor)
    if category == "weapon" then
        local carried, usable = armedState(actor)
        if usable ~= nil and usable <= 0 then return TIER.desperate end
        if usable ~= nil and usable == 1 then return TIER.important end
        if carried == nil then return TIER.important end
        return hasStock and TIER.marginal or TIER.useful
    end
    if category == "medicine" then
        local bleeding, wounded = untreatedInjury(actor)
        local stocked = (audit.counts.medicine or 0) > 0
        if bleeding and not stocked then return TIER.desperate end
        if wounded then return TIER.urgent end
        return hasStock and TIER.marginal or TIER.useful
    end
    if category == "food" then
        local hunger = statValue(actor, "HUNGER")
        if hunger >= 0.7 then return TIER.urgent end
        if hunger >= 0.35 then return TIER.useful end
        return hasStock and TIER.ignore or TIER.marginal
    end
    if category == "water" then
        local thirst = statValue(actor, "THIRST")
        if thirst >= 0.7 then return TIER.urgent end
        if thirst >= 0.35 then return TIER.useful end
        return hasStock and TIER.ignore or TIER.marginal
    end
    if category == "ammunition" then
        -- Ammunition is only urgent to somebody holding a firearm.
        local carried = select(1, armedState(actor))
        return carried ~= nil and carried > 0 and TIER.important or TIER.marginal
    end
    if category == "clothing" then return TIER.marginal end
    return hasStock and TIER.ignore or TIER.marginal
end

function Logistics.itemNeedScore(actor, item, commands, audit, sourceStorage)
    audit = audit or Logistics.audit(actor)
    local category = Logistics.itemCategory(item)
    local requestedCategory = type(commands) == "table"
        and commands.scavengeRequestedCategory or nil
    local accepted, reason = Logistics.canTake(
        actor, item, category, audit, requestedCategory, sourceStorage)
    if not accepted then return 0, category end
    local target = math.max(1, dynamicTarget(audit, category, actor))
    local held = audit.counts[category] or 0
    local deficit = math.max(0, target - held) / target
    -- The tier decides the order; the old formula only ranks within it, so a
    -- deficit, a role preference and item condition still choose between two
    -- equally urgent finds.
    local tier = Logistics.needTier(actor, category, audit, held >= target)
    local score = tier + 22 + deficit * 64
        + ((roleWeights[audit.role] or {})[category] or 0)
    if requestedSupplyMatches(requestedCategory, category) then
        score = math.max(score, TIER.useful + 20)
    end
    -- Crafting material is always worth the space it takes. The base can
    -- always use nails, planks, thread and tape, and a companion that walks
    -- past them because nobody is short of anything today is how a workshop
    -- ends up empty.
    --
    -- Surplus, though -- stock past this survivor's own target -- is the last
    -- thing worth carrying, not one of the first. The floor was set at
    -- TIER.useful + 14, which is 314, against 211 for food and 212 for water
    -- when a companion is carrying no provisions at all: an interrupted trip
    -- came home with spare planks and nothing to eat. It belongs just above
    -- "nothing needed" and below every real restocking.
    if category == "crafting" or category == "construction" then
        score = math.max(score, TIER.marginal + 10)
    end
    if reason == "clothing_upgrade" then
        local _, difference = Logistics.clothingUpgrade(actor, item)
        score = TIER.marginal + 72 + math.min(48, math.max(0, difference))
    elseif reason == "bag_upgrade" then
        -- A better bag raises everything else this survivor can carry, so it
        -- outranks ordinary restocking without displacing a real emergency.
        local _, difference = Logistics.bagUpgrade(actor, item)
        score = TIER.useful + 78 + math.min(42, math.max(0, difference) * 3)
    end
    local condition, conditionOk = U().call(item, "getCondition")
    local maximum, maxOk = U().call(item, "getConditionMax")
    if conditionOk and maxOk and tonumber(maximum) and maximum > 0 then
        score = score * math.max(0.15, tonumber(condition) / maximum)
    end
    if category == "food" then
        local rotten, rottenOk = U().call(item, "isRotten")
        if rottenOk and rotten then return 0, category end
    elseif category == "water" then
        local fluid=U().call(item,"getFluidContainer")
        local amount=tonumber((U().call(fluid,"getAmount")))
        local capacity=tonumber((U().call(fluid,"getCapacity")))
        if amount and capacity and capacity>0 then
            score=score*math.max(.2,math.min(1,amount/capacity))
        else
            local used,okay=U().call(item,"getUsedDelta")
            if okay and type(used)=="number" then score=score*math.max(.2,used) end
        end
        local weight=SC.Needs and SC.Needs.drinkingContainerWeight
            and SC.Needs.drinkingContainerWeight(item) or U().itemWeight(item)
        score=score+12/(1+weight)
    end
    return score, category
end

-- keptHarvestDeposit admits one case: a harvest kept for pickup because no
-- car was chosen may go into camp storage. It is still never dropped.
local function isProtected(actor, item, keptHarvestDeposit)
    if not actor or not item then return true end
    if workCargo(actor, item, keptHarvestDeposit) then return true end
    local manualData = select(1, U().call(item, "getModData"))
    if Preparation.manualItem(actor, manualData) then return true end
    -- A key weighs almost nothing and opens the car or building it belongs
    -- to. Shelving the expedition car's key at camp strands the next trip.
    -- Keep call's second result (the success flag) out of tonumber, which
    -- would read it as a base and demand a string.
    local keyId = U().call(item, "getKeyId")
    keyId = tonumber(keyId)
    if keyId ~= nil and keyId ~= -1 then return true end
    if select(1, U().call(item, "isKeyRing")) == true then return true end
    local category = select(1, U().call(item, "getCategory"))
    local fullType = U().itemType(item)
    if tostring(category) == "Literature" or string.find(
        string.lower(fullType), "book", 1, true) then
        local data = select(1, U().call(item, "getModData"))
        local loan = type(data) == "table" and data.SC_BookLoan or nil
        if type(loan) == "table" and loan.finished ~= true
            and loan.actorId == U().idOf(actor) then return true end
    end
    if SC.PersonalItems and SC.PersonalItems.isProtected
        and SC.PersonalItems.isProtected(item, actor,
            keptHarvestDeposit and "kept_harvest_deposit" or "loadout") then
        return true
    end
    local favorite, favoriteOk = U().call(item, "isFavorite")
    if favoriteOk and favorite == true then return true end
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if primaryOk and primary == item then return true end
    local secondary, secondaryOk = U().call(actor, "getSecondaryHandItem")
    if secondaryOk and secondary == item then return true end
    local worn, wornOk = U().call(actor, "isEquippedClothing", item)
    if wornOk and worn == true then return true end
    local nested, nestedOk = nestedInventory(item)
    if nestedOk and nested and #U().inventoryItems(nested, 1) > 0 then return true end
    return false
end

function Preparation.manualItem(actor, data)
    if type(data) ~= "table" then return false end
    if data.SC_ManualWearFor ~= nil then return true end
    if data.SC_ManualEquipFor ~= nil then
        local owner = tostring(data.SC_ManualEquipFor) == tostring(U().idOf(actor)) and actor
            or U().resolveActor and U().resolveActor(tostring(data.SC_ManualEquipFor))
        if not owner then return true end
        local ownerData = select(1, U().call(owner, "getModData"))
        return type(ownerData) ~= "table" or (tonumber(data.SC_ManualEquipSerial) or 0)
            == (tonumber(ownerData.SC_ManualWeaponSerial) or 0)
    end
    return false
end

function Preparation.removableMask(actor, item)
    local actorData = select(1, U().call(actor, "getModData"))
    if type(actorData) ~= "table" or actorData.SC_Recruited ~= true
        or not Logistics.manualOnlyFilterMask(item) or not isWorn(actor, item) then return false end
    local itemData = select(1, U().call(item, "getModData"))
    if type(itemData) == "table" and itemData.SC_ManualWearFor ~= nil then return false end
    -- Removing an automatic wearable never transfers, disposes of, or changes
    -- the item. Favourite, personal and receipt ownership remains intact.
    return true
end

function Preparation.maskRemoval(actor, audit)
    for _, record in ipairs(audit.items) do
        if Preparation.removableMask(actor, record.item) then return record end
    end
end

-- Playtest: a companion looted kneepads and never put them on, and nothing in
-- the log said why. A clothing upgrade can be refused for several unrelated
-- reasons -- not classified as clothing at all, no wearable body location, a
-- cosmetic or broken garment, a non-comparable wearable already in the slot, or
-- simply too small an improvement -- and they were indistinguishable from
-- outside. Report the decision so the next one is answerable.
local function reportClothingDecision(actor, item, outcome, detail)
    if SC.Diagnostics == nil or type(SC.Diagnostics.report) ~= "function" then return end
    if U().config("logisticsClothingTrace") ~= true then return end
    pcall(SC.Diagnostics.report, "logistics-clothing", U().idOf(actor),
        "item=" .. tostring(U().itemType(item))
        .. " outcome=" .. tostring(outcome) .. " " .. tostring(detail or ""))
end

local function selectOwnedClothingUpgrade(actor, audit)
    local best
    for _, record in ipairs(audit.items) do
        -- Favourite is a disposal guard, not a veto against wearing a gift.
        -- Personal keepsakes remain outside autonomous loadout choices.
        local personal = SC.PersonalItems and SC.PersonalItems.isProtected
            and SC.PersonalItems.isProtected(record.item, actor, "loadout")
        if record.category == "clothing" and not personal
            and not isWorn(actor, record.item) then
            local accepted, difference, current, location = Logistics.clothingUpgrade(actor, record.item)
            if accepted and (not best or difference > best.difference) then
                best = { item = record.item, source = record.source, current = current,
                    location = location, difference = difference }
            elseif not accepted then
                reportClothingDecision(actor, record.item, "refused",
                    "location=" .. tostring(location)
                    .. " score=" .. tostring(Logistics.clothingScore(record.item))
                    .. " difference=" .. tostring(difference)
                    .. " current=" .. tostring(current and U().itemType(current) or "none"))
            end
        elseif record.category ~= "clothing" and isClothingItem(record.item) then
            -- A wearable that the category pass did not call clothing: this is
            -- the shape the kneepad report would take if classification is the
            -- problem rather than the score.
            reportClothingDecision(actor, record.item, "not_categorised_clothing",
                "category=" .. tostring(record.category))
        end
    end
    return best
end

function Preparation.bagEquipped(actor, item, allowHeld)
    return isWorn(actor, item) or allowHeld == true
        and (select(1, U().call(actor, "isHandItem", item)) == true
            or select(1, U().call(actor, "getPrimaryHandItem")) == item
            or select(1, U().call(actor, "getSecondaryHandItem")) == item)
end

local function selectPackMove(actor, audit, options)
    local best
    -- Only loose items in the main inventory are packed. An item already in
    -- one worn bag is never moved into another: with two worn bags (a duffel
    -- and a fanny pack) that ping-ponged the same items back and forth
    -- forever, each move succeeding and replaying the Loot pose.
    local root = U().inventory(actor)
    for _, bagRecord in ipairs(audit.items) do
        local bagValue, location, bagInventory = bagScore(bagRecord.item)
        local reduction = tonumber((select(1, U().call(bagRecord.item, "getWeightReduction")))) or 0
        if bagValue and bagRecord.source == root and reduction > 0
            and Preparation.bagEquipped(actor, bagRecord.item,
                options == nil or options.allowHeldBag == true) then
            for _, record in ipairs(audit.items) do
                local nested, nestedOk = nestedInventory(record.item)
                local clothingUpgrade = record.category == "clothing"
                    and select(1, Logistics.clothingUpgrade(actor, record.item)) == true
                local bagUpgrade = record.category == "container"
                    and select(1, Logistics.bagUpgrade(actor, record.item)) == true
                if record.item ~= bagRecord.item and record.source ~= bagInventory
                    and record.source == root
                    and record.item ~= audit.farmWaterCan
                    and not (options and options.tools and options.tools[record.item])
                    and not (nestedOk and nested) and not isProtected(actor, record.item)
                    -- Keep weapons in the root inventory. Combat/equip actions
                    -- need immediate ownership of newly gifted fallback weapons;
                    -- packing a BreadKnife into the worn bag both hid it from the
                    -- native handoff and caused a pointless unpack/equip cycle.
                    and record.category ~= "weapon"
                    and not clothingUpgrade and not bagUpgrade
                    and U().inventoryContains(record.source, record.item)
                    and U().containerHasRoom(bagInventory, actor, record.item) == true
                    and (not options or Preparation.free(bagInventory, actor)
                        >= U().itemWeight(record.item) + (options.rawReserve or 0)) then
                    local weight = U().itemWeight(record.item)
                    local priority = weight * 8
                        + ((roleWeights[audit.role] or {})[record.category] or 0)
                        + math.max(0, bagValue)
                    if weight >= 0.1 and (not best or priority > best.priority) then
                        best = { item = record.item, source = record.source,
                            destination = bagInventory, bag = bagRecord.item,
                            category = record.category, priority = priority }
                    end
                end
            end
        end
    end
    return best
end

local function commitWearable(actor, record)
    local utility = U()
    local root = utility.inventory(actor)
    local source = record.source
    local previous = {}
    for _, item in ipairs(replacementItems(actor, record.location)) do
        previous[#previous + 1] = { item = item, location = wearableLocation(item) }
    end
    local function restorePrevious()
        local restored = true
        for _, worn in ipairs(previous) do
            if worn.location == nil then
                restored = false
            elseif not isWorn(actor, worn.item, worn.location) then
                local resolved, resolvedOk = utility.call(worn.item, "getBodyLocation")
                if not resolvedOk or resolved == nil then
                    resolved, resolvedOk = utility.call(worn.item, "canBeEquipped")
                end
                local wornLocation = (resolvedOk and resolved ~= nil) and resolved
                    or worn.location
                local restoreResult, restoreOk = utility.call(
                    actor, "setWornItem", wornLocation, worn.item)
                if not restoreOk or restoreResult == false
                    or not isWorn(actor, worn.item, worn.location) then
                    restored = false
                end
            end
        end
        return restored
    end
    if source ~= root then
        if select(1, utility.transferItemVerified(source, root, record.item)) ~= true then
            return false, "wearable_root_transfer_failed"
        end
    end
    for _, worn in ipairs(previous) do
        local _, removed = utility.call(actor, "removeWornItem", worn.item, false)
        if not removed or isWorn(actor, worn.item, worn.location) then
            restorePrevious()
            if source and source ~= root then utility.transferItem(root, source, record.item) end
            utility.call(actor, "resetModelNextFrame")
            return false, "wearable_replacement_remove_failed"
        end
    end
    -- setWornItem needs the ItemBodyLocation object; resolve it from the item.
    -- Clothing exposes getBodyLocation(); bags and equippable containers use
    -- canBeEquipped() instead. Fall back to the persisted string only if neither.
    local recordLocation, recordLocationOk = utility.call(record.item, "getBodyLocation")
    if not recordLocationOk or recordLocation == nil then
        recordLocation, recordLocationOk = utility.call(record.item, "canBeEquipped")
    end
    recordLocation = (recordLocationOk and recordLocation ~= nil) and recordLocation
        or record.location
    local result, setOk = utility.call(actor, "setWornItem", recordLocation, record.item)
    local verified = setOk and result ~= false and isWorn(actor, record.item, record.location)
    if not verified then
        if isWorn(actor, record.item, record.location) then
            utility.call(actor, "removeWornItem", record.item, false)
        end
        local restored = restorePrevious()
        local returned = true
        if source and source ~= root then
            returned = select(1,
                utility.transferItemVerified(root, source, record.item)) == true
        end
        utility.call(actor, "resetModelNextFrame")
        if not restored or not returned then
            return false, "wearable_equip_failed_and_rollback_incomplete"
        end
        return false, "wearable_equip_failed"
    end
    utility.call(actor, "resetModelNextFrame")
    if type(triggerEvent) == "function" then
        pcall(triggerEvent, "OnClothingUpdated", actor)
    end
    utility.call(root, "setDirty", true)
    utility.call(root, "setDrawDirty", true)
    if type(ISInventoryPage) == "table" then ISInventoryPage.renderDirty = true end
    if SC.InventoryIndex and type(SC.InventoryIndex.touch) == "function" then
        SC.InventoryIndex.touch(actor)
    end
    return true, "wearable_equipped"
end

-- The exact item chosen in the borrowed loot pane may be inside a worn bag.
-- Keep native ownership and the existing verified replacement rollback in one
-- place rather than asking vanilla's player-targeted Wear action to do it.
function Logistics.equipExactWearable(actor, item)
    if not U().isValidActor(actor) or not item then return false, "invalid_wear_request" end
    local location = wearableLocation(item)
    if not location or (not isClothingItem(item)
        and select(1, bagScore(item)) == nil) then
        return false, "item_not_wearable"
    end
    local source
    for _, record in ipairs(Logistics.audit(actor).items) do
        if record.item == item then source = record.source break end
    end
    if not source then return false, "item_not_owned" end
    if isWorn(actor, item, location) then
        local data = select(1, U().call(item, "getModData"))
        if type(data) == "table" then data.SC_ManualWearFor = U().idOf(actor) end
        return true, "already_worn"
    end
    local equipped, reason = commitWearable(actor, {
        item = item, source = source, location = location,
    })
    if equipped then
        local data = select(1, U().call(item, "getModData"))
        if type(data) == "table" then data.SC_ManualWearFor = U().idOf(actor) end
        local state = states[actor]
        if state then state.auditAt = -math.huge end
        local gifts = pendingGifts[actor]
        if gifts then gifts.items[item] = nil end
    end
    return equipped, reason
end

function Logistics.selectSurplus(actor, audit, skip)
    audit = audit or Logistics.audit(actor)
    local best, bestScore
    local usableWeapons = SC.Combat and SC.Combat.weaponOperational and SC.Combat.weaponAvailability
        and select(2, SC.Combat.weaponAvailability(actor)) or nil
    for _, record in ipairs(audit.items) do
        local item = record.item
        if item ~= audit.farmWaterCan and not isProtected(actor, item) and not (skip and skip(item)) then
            local category = record.category or Logistics.itemCategory(item)
            local count = (audit.gearCounts or audit.counts)[category] or 0
            local target = tonumber(audit.profile.target[category]) or 0
            local keep = tonumber(audit.profile.keep[category]) or 0
            local eligible = category == "general" or count > target
                or ((audit.gearRatio or audit.ratio) > audit.hardRatio
                    and count > keep)
            if category == "weapon" and usableWeapons ~= nil and usableWeapons >= 0 and usableWeapons <= keep
                and SC.Combat.weaponOperational(actor, item) then eligible = false end
            if eligible then
                local weight=category=="water" and SC.Needs and SC.Needs.drinkingContainerWeight
                    and SC.Needs.drinkingContainerWeight(item) or U().itemWeight(item)
                local score = (category == "general" and 100 or 35)
                    + math.max(0, count - target) * 12 + weight * 4
                if category=="water" and SC.Needs and SC.Needs.isSafeWaterItem
                    and not SC.Needs.isSafeWaterItem(item) then score=score+16 end
                if bestScore == nil or score > bestScore then
                    best = { item = item, category = category, source = record.source }
                    bestScore = score
                end
            end
        end
    end
    return best
end

-- Literature has no loadout purpose once it is no longer being read. Offer a
-- real book or magazine for shelving even below the ordinary unload threshold;
-- private diaries, favourites, equipped objects and work cargo remain protected
-- by the same ownership boundary as every other logistics move.
local function selectLiteratureSurplus(actor, audit)
    for _, record in ipairs(audit.items or {}) do
        if (record.category or Logistics.itemCategory(record.item)) == "literature"
            and not isProtected(actor, record.item) then
            return {
                item = record.item, category = "literature", source = record.source,
                proactive = true,
            }
        end
    end
    return nil
end

-- A harvest kept for pickup goes into camp storage once its carrier is
-- inside the camp; otherwise it would ride in the pack until it rots.
local function selectKeptHarvest(actor, audit, skip)
    if not SC.BaseLife or type(SC.BaseLife.isInside) ~= "function"
        or SC.BaseLife.isInside(actor) ~= true then return nil end
    local id = tostring(U().idOf(actor) or "")
    for _, record in ipairs(audit.items or {}) do
        local data = select(1, U().call(record.item, "getModData"))
        if type(data) == "table" and data.LF_FieldCarryWorker == id
            and not (skip and skip(record.item))
            and not isProtected(actor, record.item, true) then
            return {
                item = record.item, source = record.source, proactive = true,
                category = record.category or Logistics.itemCategory(record.item),
                keptHarvest = true,
            }
        end
    end
    return nil
end

local function selectFarmingSurplus(actor, audit, skip)
    for _, record in ipairs(audit.items or {}) do
        if (record.category or Logistics.itemCategory(record.item)) == "farming"
            and record.item ~= audit.farmWaterCan
            and not (skip and skip(record.item))
            and not isProtected(actor, record.item) then
            return {
                item = record.item, category = "farming", source = record.source,
                proactive = true,
            }
        end
    end
    return nil
end

-- Moves that failed or were cancelled (a Loot pose knocked loose, a bag that
-- will not take the item, an upgrade that will not equip) cool down with an
-- exponential backoff. Without this memory the next audit proposed the same
-- move at once, and a companion could loop the Loot pose indefinitely instead
-- of following its leader.
local moveMemory = { byActor = setmetatable({}, { __mode = "k" }) }

function moveMemory.key(kind, item)
    return tostring(kind) .. "|" .. tostring(item)
end

function moveMemory.cooling(actor, kind, item, current)
    local ledger = actor and moveMemory.byActor[actor] or nil
    local record = ledger and item ~= nil and ledger[moveMemory.key(kind, item)] or nil
    return record ~= nil and current < (tonumber(record.retryAt) or 0)
end

function moveMemory.note(actor, kind, item, current)
    if actor == nil or item == nil then return end
    local ledger = moveMemory.byActor[actor]
    if not ledger then
        ledger = { order = {} }
        moveMemory.byActor[actor] = ledger
    end
    local key = moveMemory.key(kind, item)
    local record = ledger[key]
    if not record then
        record = { failures = 0 }
        ledger[key] = record
        ledger.order[#ledger.order + 1] = key
        while #ledger.order > 32 do ledger[table.remove(ledger.order, 1)] = nil end
    end
    record.failures = record.failures + 1
    local base = tonumber(U().config("logisticsFailureCooldownMs")) or 30000
    local cap = tonumber(U().config("logisticsFailureMaxCooldownMs")) or 600000
    record.retryAt = current + math.min(cap, base * (2 ^ math.min(8, record.failures - 1)))
end

function moveMemory.clear(actor, kind, item)
    local ledger = actor and moveMemory.byActor[actor] or nil
    if ledger and item ~= nil then ledger[moveMemory.key(kind, item)] = nil end
end

-- A successful player-to-companion transfer is a loadout event, not a new
-- scavenging order. Retain exact item identities until a safe decision beat
-- can consider them; several pieces of an outfit may arrive in one UI session.
function Logistics.noteGift(actor, item)
    if not actor or not item then return false, "invalid_gift" end
    local gifts = pendingGifts[actor]
    if not gifts then
        gifts = { items = {} }
        pendingGifts[actor] = gifts
    end
    gifts.items[item] = true
    local state = states[actor]
    if state then
        state.auditAt = -math.huge
        state.nextWeaponAt = 0
    end
    if SC.InventoryIndex and type(SC.InventoryIndex.touch) == "function" then
        SC.InventoryIndex.touch(actor)
    end
    return true
end

local function reviewPendingGifts(actor, audit)
    local gifts = pendingGifts[actor]
    if not gifts then return end
    local owned = {}
    for _, record in ipairs(audit.items) do owned[record.item] = record end
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local armed = SC.Combat and type(SC.Combat.primaryWeaponUsable) == "function"
        and SC.Combat.primaryWeaponUsable(actor) == true
        or (not (SC.Combat and type(SC.Combat.primaryWeaponUsable) == "function")
            and primary ~= nil)
    local pending = false
    for item in pairs(gifts.items) do
        local record = owned[item]
        if record and record.category == "weapon" and not armed then
            audit.giftWeapon = true
            pending = true
        elseif record and record.category == "clothing"
            and select(1, Logistics.clothingUpgrade(actor, item)) == true then
            pending = true
        elseif record and record.category == "container"
            and select(1, Logistics.bagUpgrade(actor, item)) == true then
            pending = true
        else
            gifts.items[item] = nil
        end
    end
    if not pending then pendingGifts[actor] = nil end
    audit.giftPending = pending
end

function Logistics.status(actor)
    local state = states[actor]
    local current = U().nowMs()
    if state and state.audit and current - (state.auditAt or 0) < 500 then
        return state.audit
    end
    local audit = Logistics.audit(actor)
    audit.bagUpgrade = selectBagUpgrade(actor, audit)
    audit.clothingUpgrade = selectOwnedClothingUpgrade(actor, audit)
    audit.manualMaskRemoval = Preparation.maskRemoval(actor, audit)
    reviewPendingGifts(actor, audit)
    -- The vanilla transfer hook cannot see every way an item reaches a
    -- companion (including restored and mod-inserted inventory). A recruited
    -- follower should ready any usable carried weapon before meeting a threat,
    -- even if the leader is still walking. Leave base workers' tools alone.
    local data, dataOk = U().call(actor, "getModData")
    local following = dataOk and type(data) == "table"
        and data.SC_Recruited == true and data.SC_Order == "follow"
    local weaponDue = current >= (state and tonumber(state.nextWeaponAt) or 0)
    if weaponDue and SC.Combat and type(SC.Combat.weaponAvailability) == "function"
        and type(SC.Combat.primaryWeaponUsable) == "function" then
        local usable = SC.Combat.primaryWeaponUsable(actor) == true
        if following and type(SC.Combat.preferredWeapon) == "function" then
            local service = supervisor()
            if not usable or not service or not service.current or service.current(actor) == nil then
                local best = SC.Combat.preferredWeapon(actor, data.SC_WeaponPriority or "best")
                audit.weaponReady = best ~= nil and best ~= select(1, U().call(actor, "getPrimaryHandItem"))
            end
        elseif following and not usable then
            local _, usable = SC.Combat.weaponAvailability(actor)
            audit.weaponReady = usable > 0
        end
        if not usable and audit.giftWeapon == true then audit.weaponReady = true end
        if state then state.nextWeaponAt = current + 1500 end
    end
    audit.packMove = selectPackMove(actor, audit)
    -- A move that just failed cools down instead of being proposed again.
    if audit.bagUpgrade and moveMemory.cooling(actor, "wear", audit.bagUpgrade.item, current) then
        audit.bagUpgrade = nil
    end
    if audit.clothingUpgrade
        and moveMemory.cooling(actor, "wear", audit.clothingUpgrade.item, current) then
        audit.clothingUpgrade = nil
    end
    if audit.packMove and moveMemory.cooling(actor, "pack", audit.packMove.item, current) then
        audit.packMove = nil
    end
    local actorData = select(1, U().call(actor, "getModData"))
    local atCamp = SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(actor) == true
    audit.fieldReturnCleanup = atCamp and type(actorData) == "table"
        and actorData.LF_FieldReturnCleanup ~= nil
    -- The return cleanup is one pass over what the worker carries. An item
    -- whose storage just failed cools down; offer the next one instead, so the
    -- pass can finish while that item waits with its carrier for a retry.
    local skip = audit.fieldReturnCleanup and function(item)
        return moveMemory.cooling(actor, "deposit", item, current)
            or moveMemory.cooling(actor, "drop", item, current)
    end or nil
    local surplus = selectKeptHarvest(actor, audit, skip)
    -- A returning field worker can carry ordinary excess below the overload
    -- threshold. Shelve it while at camp, using the normal role minimums.
    if not surplus and audit.fieldReturnCleanup then
        surplus = Logistics.selectSurplus(actor, audit, skip)
        if surplus then surplus.proactive = true end
    end
    if not surplus and audit.capacity > 0
        and (audit.gearRatio or audit.ratio) > audit.softRatio then
        surplus = Logistics.selectSurplus(actor, audit)
    end
    -- Above the Strength limit's unload share, a companion at camp puts its
    -- surplus into marked storage so it does not walk around under Heavy
    -- Load. This is shelving only: without storage the item stays carried.
    if not surplus and atCamp and (audit.carryCapacity or 0) > 0
        and (audit.carryGearRatio or 0) > audit.softRatio then
        surplus = Logistics.selectSurplus(actor, audit)
        if surplus then surplus.proactive, surplus.shelveOnly = true, true end
    end
    if not surplus then
        local literature = selectLiteratureSurplus(actor, audit)
        if literature and storageFor(actor, literature.item, "literature", true) then
            surplus = literature
        end
    end
    if not surplus then
        local farming = selectFarmingSurplus(actor, audit, skip)
        if farming and (audit.fieldReturnCleanup
            or storageFor(actor, farming.item, "farming", true)) then surplus = farming end
    end
    audit.cleanupDone = audit.fieldReturnCleanup and surplus == nil
    if surplus and (moveMemory.cooling(actor, "deposit", surplus.item, current)
        or moveMemory.cooling(actor, "drop", surplus.item, current)) then
        surplus = nil
    end
    audit.surplus = surplus
    audit.fieldReturnCargo = surplus ~= nil and surplus.keptHarvest == true
    audit.shouldUnload = surplus ~= nil
    audit.shouldManage = audit.weaponReady == true
        or audit.manualMaskRemoval ~= nil
        or audit.bagUpgrade ~= nil or audit.clothingUpgrade ~= nil
        or audit.packMove ~= nil or audit.shouldUnload or audit.cleanupDone
    audit.overloaded = audit.capacity > 0 and audit.ratio > audit.hardRatio
    state = state or {}
    states[actor] = state
    state.audit, state.auditAt = audit, current
    return audit
end

-- Supplies go straight into the best worn bag when that bag can accept the
-- exact item. Equipment upgrades remain at inventory root so the native equip
-- action can take ownership without first creating another hidden transfer.
function Logistics.preferredLootDestination(actor, item, category, audit)
    local root = U().inventory(actor)
    if not root or not item then return nil, "inventory_unavailable" end
    category = category or Logistics.itemCategory(item)
    local bagEligible = category ~= "container" and category ~= "clothing"
        and category ~= "weapon" and category ~= "personal"
    if not bagEligible then return root, "inventory" end
    audit = audit or Logistics.audit(actor)
    local best, bestScore, bestItem
    for _, record in ipairs(audit.items or {}) do
        if record.item ~= item then
            local score, location, nested = bagScore(record.item)
            if score and nested and record.source == root
                and Preparation.bagEquipped(actor, record.item, true)
                and U().containerHasRoom(nested, actor, item) == true then
                local free, freeOk = U().call(nested, "getFreeCapacity", actor)
                if not freeOk or type(free) ~= "number" then
                    local current, currentOk = U().call(nested, "getCapacityWeight")
                    local capacity, capacityOk = U().call(nested, "getEffectiveCapacity", actor)
                    free = currentOk and capacityOk and type(current) == "number"
                        and type(capacity) == "number" and math.max(0, capacity - current) or 0
                end
                local candidateScore = score + free * 0.15
                if bestScore == nil or candidateScore > bestScore then
                    best, bestScore, bestItem = nested, candidateScore, record.item
                end
            end
        end
    end
    if best then return best, isWorn(actor, bestItem) and "worn_bag" or "held_bag", bestItem end
    return root, "inventory"
end

storageFor = function(actor, item, category, dedicatedOnly, ownerState)
    if not SC.BaseLife or type(SC.BaseLife.storageRows) ~= "function"
        or type(SC.BaseLife.resolveContainer) ~= "function" then return nil end
    local wanted = storageCategory[category] or "general"
    if wanted == "valuables" and #SC.BaseLife.depositStorageRows("valuables") == 0 then
        wanted = isClothingItem(item) and "clothing" or "general"
    end
    if wanted == "food" and type(SC.BaseLife.foodDepositCategory) == "function" then
        wanted = SC.BaseLife.foodDepositCategory(item)
    end
    local fieldReturn = ownerState and (ownerState.fieldReturnCleanup == true
        or ownerState.keptHarvest == true)
    if fieldReturn and U().itemType(item) == "Base.Log"
        and SC.LogYard and type(SC.LogYard.select) == "function" then
        local yard = SC.LogYard.select(actor)
        if yard then
            return { storage = yard, container = yard.square,
                owner = yard.square, distance = U().distance(actor, yard.square) }
        end
    end
    local categories = fieldReturn and #SC.BaseLife.depositStorageRows(wanted) > 0
        and { wanted }
        or dedicatedOnly and { wanted }
        or wanted == "valuables" and { wanted }
        or wanted == "general" and { "general", "output" }
        or { wanted, "general", "output" }
    local best, bestDistance, choices
    for _, storageType in ipairs(categories) do
        choices = {}
        for _, storage in ipairs(SC.BaseLife.storageRows(storageType) or {}) do
            if storage.deposits ~= false then
                local container, owner = SC.BaseLife.resolveContainer(storage)
                if container and container ~= U().inventory(actor)
                    and U().containerHasRoom(container, actor, item) == true then
                    local distance = U().distance(actor, owner or container)
                    if distance <= (U().config("logisticsStorageRange") or 32)
                        and (bestDistance == nil or distance < bestDistance) then
                        best = { storage = storage, container = container,
                            owner = owner or container, distance = distance }
                        bestDistance = distance
                    end
                    if distance <= (U().config("logisticsStorageRange") or 32) then
                        choices[#choices + 1] = {
                            id = storage.id, object = owner or container,
                            destination = { storage = storage, container = container,
                                owner = owner or container, distance = distance },
                        }
                    end
                end
            end
        end
        if #choices > 0 then break end
    end
    if ownerState and #choices > 0 and SC.Navigation
        and type(SC.Navigation.selectInteraction) == "function" then
        local selected, reason, receipt = SC.Navigation.selectInteraction(actor, ownerState,
            "logistics_deposit:" .. tostring(select(1, U().call(item, "getID")) or item),
            choices, { nodeBudget = 1600, retainRoute = true })
        if selected then return selected.destination, nil, receipt end
        return nil, reason == "pending" and "storage_route_pending"
            or reason == "unknown" and "storage_route_unknown"
            or "storage_route_unreachable"
    end
    return best
end

local function safeToManage(actor, runtime)
    local root = U().actorState(actor, runtime)
    local snapshot = root.senses and root.senses.current or root.snapshot
    if type(snapshot) == "table" and ((snapshot.threatCount or 0) > 0
        or (snapshot.immediateCount or 0) > 0 or (snapshot.pressure or 0) >= 1) then
        return false, snapshot
    end
    if SC.Combat and type(SC.Combat.peek) == "function" then
        local combat = SC.Combat.peek(actor)
        if combat and combat.active then return false, snapshot end
    end
    return true, snapshot
end

local function visualStatus(actor, expectedAction)
    if not SC.NativeActions then return nil end
    if type(SC.NativeActions.visualStatus) ~= "function" then
        return type(SC.NativeActions.dispatch) == "function"
            and "unavailable" or nil
    end
    local ok, status = pcall(SC.NativeActions.visualStatus, actor,
        expectedAction or "loot_container")
    return ok and status or "unavailable"
end

local function clearVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        pcall(SC.NativeActions.clearVisual, actor)
    end
end

local function cleanupTransaction(actor, state, reason)
    local transaction = state and state.transaction or nil
    local native = SC.NativeActions
    if transaction and transaction.visualToken ~= nil and native
        and type(native.cancelVisualOwned) == "function" then
        -- End exactly the pose this move started, whatever phase it reached.
        -- A Loot pose left completed but unclaimed keeps the actor owned and
        -- refuses every later action, a car seat included.
        pcall(native.cancelVisualOwned, actor, transaction.visualToken,
            reason or "logistics_cancelled")
    elseif transaction and transaction.phase == "visual" and native
        and type(native.cancelVisual) == "function" then
        pcall(native.cancelVisual, actor, reason or "logistics_cancelled")
    end
    if state then state.transaction = nil end
end

local function cancelTransaction(actor, state, reason)
    local transaction = state and state.transaction or nil
    local service = supervisor()
    local token = transaction and transaction.supervisorToken or nil
    if token and service and type(service.isCurrent) == "function"
        and service.isCurrent(token) and type(service.cancel) == "function" then
        service.cancel(actor, reason or "logistics_cancelled", nil, true)
        if state.transaction == transaction then cleanupTransaction(actor, state, reason) end
        return
    end
    cleanupTransaction(actor, state, reason)
end

local function terminalTransaction(actor, state, succeeded, reason, receipt)
    local transaction = state and state.transaction or nil
    local token = transaction and transaction.supervisorToken or nil
    if transaction and transaction.preparationKey then
        local preparation = Preparation.actors[actor]
        if preparation and preparation.key == transaction.preparationKey then
            preparation.inventoryScan, preparation.auditData = nil, nil
        end
    end
    if transaction then
        if succeeded == true then
            moveMemory.clear(actor, transaction.kind, transaction.item)
        elseif reason ~= "logistics_unsafe" then
            moveMemory.note(actor, transaction.kind, transaction.item, U().nowMs())
        end
    end
    cleanupTransaction(actor, state, reason)
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "logistics_interaction")
    end
    states[actor] = nil
    local service = supervisor()
    if token and service then
        if succeeded and type(service.complete) == "function" then
            service.complete(token, reason or "completed", receipt)
        elseif not succeeded and type(service.fail) == "function" then
            service.fail(token, reason or "logistics_failed", receipt)
        end
    end
    return succeeded == true, reason
end

local function markTransactionVerifying(transaction, detail)
    local service = supervisor()
    if service and transaction and transaction.supervisorToken
        and type(service.transition) == "function" then
        service.transition(transaction.supervisorToken, "verifying", detail)
    end
end

local function markTransactionCommitting(transaction)
    local service = supervisor()
    if service and transaction.supervisorToken and type(service.transition) == "function" then
        service.transition(transaction.supervisorToken, "committing", { kind = transaction.kind })
    end
end

local function transactionTargetKey(transaction)
    return tostring(transaction.kind) .. "|" .. tostring(transaction.item)
        .. "|" .. tostring(transaction.destination or transaction.square or "none")
end

local function beginTransaction(actor, state, transaction)
    transaction.phase = transaction.phase or "selected"
    state.transaction = transaction
    local service = supervisor()
    if not service or type(service.begin) ~= "function" then return true, "started" end
    local token, reason = service.begin(actor, {
        owner = "logistics", action = "logistics_" .. tostring(transaction.kind),
        priority = service.Priority and service.Priority.WORK or 150,
        targetKey = transactionTargetKey(transaction),
        targetLabel = U().itemName(transaction.item), retryCategory = "*",
        requiresVisual = true,
        allowedActions = {
            wear_clothing = true, loot_container = true,
            move_to_base_storage = true,
        },
        metadata = {
            kind = transaction.kind, item = U().itemType(transaction.item),
            preparationKey = transaction.preparationKey,
        },
        onCancel = function(cancelActor, cancelReason)
            cleanupTransaction(cancelActor, state,
                cancelReason or "logistics_cancelled")
            if SC.Navigation and type(SC.Navigation.cancel) == "function" then
                pcall(SC.Navigation.cancel, cancelActor, "logistics_interaction")
            end
            return true, cancelReason
        end,
    })
    if not token then
        state.transaction = nil
        if service.containsDeferredStatus and service.containsDeferredStatus(reason) then
            -- Urgent work took the actor this cycle. The transaction was never
            -- started, so clearing it is right; reporting it as a refusal is not.
            return false, "deferred:" .. tostring(reason)
        end
        return false, reason or "action_owner_unavailable"
    end
    transaction.supervisorToken = token
    local reserved, reserveReason = service.reserve(token, transaction.item, "transaction_item")
    if not reserved then
        cleanupTransaction(actor, state, reserveReason)
        service.fail(token, reserveReason or "resource_reserved", {
            kind = transaction.kind, item = U().itemType(transaction.item),
        })
        return false, reserveReason or "resource_reserved"
    end
    if transaction.phase == "approach" and type(service.transition) == "function" then
        service.transition(token, "approaching", { kind = transaction.kind })
    end
    return true, "started"
end

local function stopForInventoryAction(actor)
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "logistics_interaction")
    end
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor)
    else
        U().stop(actor)
    end
end

local function advanceTransactionVisual(actor, transaction)
    local service = supervisor()
    local token = transaction.supervisorToken
    local visualAction = (transaction.kind == "wear" or transaction.kind == "unwear")
        and "wear_clothing" or "loot_container"
    -- Commit validation can span bounded inventory scan slices. The pose
    -- already completed; waiting for that scan must not replay it.
    if transaction.phase == "commit" then return true, "logistics_action_completed" end
    if transaction.phase == "visual" then
        local status = visualStatus(actor, visualAction)
        if status == "active" then
            if service and token and type(service.progress) == "function" then
                service.progress(token, "visual:active", { action = visualAction })
            end
            return false, "logistics_action_active"
        end
        if status == "completed" then
            clearVisual(actor)
            if service and token and type(service.markVisualVerified) == "function" then
                service.markVisualVerified(token, { action = visualAction })
            end
            transaction.phase = "commit"
            return true, "logistics_action_completed"
        end
        if status == nil then
            if service and token and type(service.markVisualVerified) == "function" then
                service.markVisualVerified(token, { action = visualAction, tracked = false })
            end
            transaction.phase = "commit"
            return true, "logistics_action_untracked"
        end
        return nil, "logistics_animation_" .. tostring(status)
    end

    stopForInventoryAction(actor)
    local intent = (transaction.kind == "wear" or transaction.kind == "unwear") and {
        action = "wear_clothing", item = transaction.item,
        wearLocation = transaction.record and transaction.record.location,
        durationTicks = 90, supervisorToken = token,
    } or {
        action = "loot_container", item = transaction.item,
        container = transaction.destination,
        packing = transaction.kind == "pack",
        depositing = transaction.kind == "deposit" or transaction.kind == "drop",
        groundDrop = transaction.kind == "drop",
        durationTicks = 90, supervisorToken = token,
    }
    if service and token and type(service.expectVisual) == "function" then
        service.expectVisual(token, { action = visualAction })
    end
    local animated, reason = U().move(actor, "walk", intent)
    if not animated then return nil, reason or "logistics_action_rejected" end
    if SC.NativeActions and type(SC.NativeActions.visualToken) == "function" then
        transaction.visualToken = SC.NativeActions.visualToken(actor, visualAction)
    end
    local status = visualStatus(actor, visualAction)
    if status == "active" then
        transaction.phase = "visual"
        if service and token and type(service.transition) == "function" then
            service.transition(token, "animating", { action = visualAction })
        end
        return false, "logistics_action_active"
    end
    if status == "completed" then clearVisual(actor)
    elseif status ~= nil then return nil, "logistics_animation_" .. tostring(status) end
    if service and token and type(service.markVisualVerified) == "function" then
        service.markVisualVerified(token, { action = visualAction, tracked = status ~= nil })
    end
    transaction.phase = "commit"
    return true, "logistics_action_completed"
end

local function executeTransaction(actor, state)
    local transaction = state and state.transaction or nil
    if not transaction then return false, "logistics_transaction_missing" end
    if not U().inventoryContains(transaction.source, transaction.item) then
        return terminalTransaction(actor, state, false, "logistics_source_changed", {
            kind = transaction.kind,
        })
    end
    if transaction.kind == "unwear" and not Preparation.removableMask(actor, transaction.item) then
        return terminalTransaction(actor, state, false, "manual_mask_cleanup_protected")
    end
    if transaction.kind == "pack" and transaction.bag
        and (not U().inventoryContains(U().inventory(actor), transaction.bag)
            or not Preparation.bagEquipped(actor, transaction.bag, transaction.allowHeldBag ~= false)) then
        return terminalTransaction(actor, state, false, "packing_bag_changed")
    end
    -- Work may claim an item after inventory selection but before this move
    -- commits. Recheck ownership before packing, dropping or shelving it.
    if (transaction.kind == "drop" or transaction.kind == "deposit"
            or transaction.kind == "pack")
        and isProtected(actor, transaction.item,
            transaction.kind == "deposit" and transaction.keptHarvest == true) then
        return terminalTransaction(actor, state, false, "logistics_item_reserved", {
            kind = transaction.kind,
        })
    end
    if transaction.kind == "deposit" then
        local atStorage = U().directInteractionAccess(actor, transaction.owner)
        if atStorage ~= true then
            return terminalTransaction(actor, state, false,
                "logistics_storage_contact_lost", { kind = transaction.kind })
        end
    end
    local ready, reason = advanceTransactionVisual(actor, transaction)
    if ready == false then return true, reason end
    if ready == nil then
        return terminalTransaction(actor, state, false, reason, {
            kind = transaction.kind,
        })
    end

    if transaction.kind == "unwear" then
        if not Preparation.removableMask(actor, transaction.item) then
            return terminalTransaction(actor, state, false, "manual_mask_cleanup_protected")
        end
        markTransactionCommitting(transaction)
        local _, removed = U().call(actor, "removeWornItem", transaction.item, false)
        local verified = removed and not isWorn(actor, transaction.item)
            and U().inventoryContains(transaction.source, transaction.item)
        markTransactionVerifying(transaction, { kind = transaction.kind })
        U().call(actor, "resetModelNextFrame")
        if type(triggerEvent) == "function" then pcall(triggerEvent, "OnClothingUpdated", actor) end
        return terminalTransaction(actor, state, verified == true,
            verified and "manual_mask_removed" or "manual_mask_remove_failed")
    end

    if transaction.kind == "wear" then
        markTransactionCommitting(transaction)
        local equipped, equipReason = commitWearable(actor, transaction.record)
        markTransactionVerifying(transaction, { kind = transaction.kind })
        if equipped and SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "wear_equipment", "equipped", {
                kind = "long",
            })
        end
        local resultReason = equipped == true and "wearable_equipped"
            or equipReason or "wearable_equip_failed"
        return terminalTransaction(actor, state, equipped == true, resultReason, {
            worn = equipped == true, item = U().itemType(transaction.item),
        })
    end

    if transaction.kind == "drop" then
        markTransactionCommitting(transaction)
        local dropped, dropReason = U().dropItem(transaction.source,
            transaction.square, transaction.item, 0.5, 0.5, 0)
        markTransactionVerifying(transaction, { kind = transaction.kind })
        if dropped and SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "logistics_drop", "completed")
        end
        local resultReason = dropped == true and "surplus_dropped"
            or dropReason or "surplus_drop_failed"
        return terminalTransaction(actor, state, dropped == true, resultReason, {
            dropped = dropped == true, item = U().itemType(transaction.item),
        })
    end
    -- Capacity or item restrictions can change while the transfer pose runs.
    if (transaction.kind == "pack" or transaction.kind == "repack") and transaction.bag
        and (not U().inventoryContains(U().inventory(actor), transaction.bag)
            or not Preparation.bagEquipped(actor, transaction.bag, transaction.allowHeldBag ~= false)) then
        return terminalTransaction(actor, state, false, "packing_bag_changed")
    end
    if transaction.preparationKey then
        local valid, validationReason = Preparation.validTransfer(actor, transaction)
        if valid == nil then return true, validationReason or "loadout_inventory_pending" end
        if valid ~= true then
            return terminalTransaction(actor, state, false, validationReason or "loadout_transfer_changed")
        end
    end
    local room, capacityReason = U().containerHasRoom(
        transaction.destination, actor, transaction.item)
    if room ~= true then
        return terminalTransaction(actor, state, false, capacityReason, {
            kind = transaction.kind,
        })
    end
    markTransactionCommitting(transaction)
    local transferred, transferReason = U().transferItemVerified(
        transaction.source, transaction.destination, transaction.item)
    markTransactionVerifying(transaction, { kind = transaction.kind })
    if transferred then
        if transaction.kind == "deposit" then
            local data = select(1, U().call(transaction.item, "getModData"))
            if type(data) == "table" and type(data.SC_BookLoan) == "table"
                and data.SC_BookLoan.finished == true then
                data.SC_BookLoan = nil
            end
            if transaction.keptHarvest == true and type(data) == "table" then
                data.LF_FieldCarryWorker = nil
            end
        end
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "logistics_" .. tostring(transaction.kind),
                "completed")
        end
        return terminalTransaction(actor, state, true,
            transaction.kind == "pack" and "item_packed" or "surplus_stored", {
                sourceEmpty = not U().inventoryContains(transaction.source, transaction.item),
                destinationContains = U().inventoryContains(
                    transaction.destination, transaction.item),
            })
    end
    return terminalTransaction(actor, state, false,
        transferReason or (transaction.kind == "pack"
            and "bag_pack_failed" or "logistics_deposit_failed"), {
                kind = transaction.kind,
            })
end

local function approachTransaction(actor, state, snapshot)
    local transaction = state and state.transaction or nil
    if not transaction or transaction.phase ~= "approach" then return nil end
    local atStorage, targets, accessReason = U().directInteractionAccess(
        actor, transaction.owner, { snapshot = snapshot })
    if atStorage == true then
        stopForInventoryAction(actor)
        transaction.phase = "selected"
        local service = supervisor()
        if service and transaction.supervisorToken and type(service.transition) == "function" then
            service.transition(transaction.supervisorToken, "settling", {
                kind = transaction.kind,
            })
        end
        return executeTransaction(actor, state)
    end
    if accessReason == "no_interaction_targets" then
        return terminalTransaction(actor, state, false,
            accessReason, { kind = transaction.kind })
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return terminalTransaction(actor, state, false,
            "logistics_navigation_unavailable", { kind = transaction.kind })
    end
    local accepted, reason = SC.Navigation.requestAny(actor, targets, "walk", {
        action = "move_to_base_storage", container = transaction.destination,
        item = transaction.item, object = transaction.owner, snapshot = snapshot,
        logistics = true, arrivalDistance = 0.35, requireSameSquare = true,
        continuousApproach = true,
        supervisorToken = transaction.supervisorToken,
        interactionRouteReceipt = state.interactionRouteReceipt,
        interactionRouteOwner = state,
    })
    local service = supervisor()
    if service and transaction.supervisorToken and type(service.progress) == "function" then
        service.progress(transaction.supervisorToken, "approach:" .. tostring(reason), {
            navigation = reason,
        })
    end
    local terminalNavigation = not accepted and (string.find(
        tostring(reason or ""), "recovery_exhausted:", 1, true) == 1
        or string.find(tostring(reason or ""), "actor_state_timeout:", 1, true) == 1)
    if terminalNavigation then
        return terminalTransaction(actor, state, false, reason, {
            kind = transaction.kind, navigation = reason,
        })
    end
    return accepted, reason or "approaching_storage"
end

function Preparation.free(container, actor)
    local free = tonumber((select(1, U().call(container, "getFreeCapacity", actor))))
    if free then return math.max(0, free) end
    local capacity = tonumber((select(1, U().call(container, "getEffectiveCapacity", actor))))
        or tonumber((select(1, U().call(container, "getCapacity"))))
    local weight = tonumber((select(1, U().call(container, "getCapacityWeight"))))
    return capacity and weight and math.max(0, capacity - weight) or 0
end

function Preparation.inventory(actor, preparation)
    if preparation.auditData then return Logistics.audit(actor, preparation.auditData) end
    local root = U().inventory(actor)
    if not root then return nil, "loadout_inventory_unavailable" end
    local scan = preparation.inventoryScan
    if not scan or scan.root ~= root then
        scan = { root = root, queue = { { container = root, index = 0 } }, cursor = 1,
            seen = { [root] = true }, items = {}, counts = {}, gearCounts = {}, cargoWeight = 0 }
        preparation.inventoryScan = scan
    end
    local inspected = 0
    while scan.cursor <= #scan.queue and inspected < 80 do
        local node = scan.queue[scan.cursor]
        local items, readable = U().call(node.container, "getItems")
        if not readable and type(node.container) == "table" then items = node.container.items end
        if items == nil then return nil, "loadout_inventory_unreadable" end
        local size = U().listSize(items)
        if node.size ~= nil and node.size ~= size then preparation.inventoryScan = nil return nil end
        node.size = size
        if node.bag and (not U().inventoryContains(node.parent, node.bag)
            or select(1, nestedInventory(node.bag)) ~= node.container) then
            preparation.inventoryScan = nil
            return nil
        end
        if node.index >= size then scan.cursor = scan.cursor + 1
        else
            if #scan.items >= 4096 then return nil, "loadout_inventory_scan_limit" end
            local item = U().listGet(items, node.index)
            node.index, inspected = node.index + 1, inspected + 1
            if item then
                local category = Logistics.itemCategory(item)
                scan.items[#scan.items + 1] = { item = item, source = node.container, category = category }
                scan.counts[category] = (scan.counts[category] or 0) + 1
                if workCargo(actor, item) then scan.cargoWeight = scan.cargoWeight + carriedWeight(item, node.container, root)
                else scan.gearCounts[category] = (scan.gearCounts[category] or 0) + 1 end
                local nested = select(1, nestedInventory(item))
                if nested and not scan.seen[nested] then
                    if #scan.queue >= 128 then return nil, "loadout_container_scan_limit" end
                    scan.seen[nested] = true
                    scan.queue[#scan.queue + 1] = { container = nested, bag = item, parent = node.container, index = 0 }
                end
            end
        end
    end
    if scan.cursor <= #scan.queue then return nil end
    -- Containers changed during assessment are rescanned before any decision.
    for _, node in ipairs(scan.queue) do
        local items = select(1, U().call(node.container, "getItems"))
        if items == nil and type(node.container) == "table" then items = node.container.items end
        if items == nil or U().listSize(items) ~= node.size
            or node.bag and not U().inventoryContains(node.parent, node.bag) then
            preparation.inventoryScan = nil
            return nil
        end
    end
    preparation.auditData, preparation.inventoryScan = scan, nil
    return Logistics.audit(actor, scan)
end

function Preparation.matches(item, requirement)
    if select(1, U().call(item, "isBroken")) == true then return false end
    local condition = select(1, U().call(item, "getCondition"))
    if type(condition) == "number" and condition <= 0 then return false end
    if type(requirement) == "string" then
        return U().itemType(item) == requirement or U().itemHasTag(item, requirement)
    end
    return type(requirement) == "table" and (requirement.itemType
        and U().itemType(item) == requirement.itemType
        or requirement.tag and U().itemHasTag(item, requirement.tag)) or false
end

function Preparation.camp(actor, requirements)
    if requirements.allowCampStaging ~= true and requirements.atCamp ~= true
        or requirements.allowCampStaging == false or requirements.atCamp == false
        or not SC.BaseLife or not SC.BaseLife.isInside or SC.BaseLife.isInside(actor) ~= true then return false end
    local base = SC.BaseLife.active and SC.BaseLife.active()
    local wanted = requirements.originCampId or requirements.camp
    if type(wanted) == "table" then wanted = wanted.id end
    return base ~= nil and (wanted == nil or base.id == wanted)
end

function Preparation.warn(preparation, warning)
    preparation.warningSet = preparation.warningSet or {}
    if not preparation.warningSet[warning] and #preparation.warnings < 12 then
        preparation.warningSet[warning] = true
        preparation.warnings[#preparation.warnings + 1] = warning
    end
end

function Preparation.kit(actor, audit, requirements)
    local keep, tools, missing, exact = {}, {}, {}, {}
    local supplied = requirements.keepItems or {}
    local hasSupplied = false
    for _ in pairs(supplied) do hasSupplied = true break end
    if hasSupplied then for _, record in ipairs(audit.items) do
        local itemId = U().itemStableId(record.item, false)
        if itemId and (supplied[itemId] == true) then keep[record.item] = true end
        for _, wanted in ipairs(supplied) do
            if itemId ~= nil and tostring(itemId) == tostring(wanted) then keep[record.item] = true end
        end
        if keep[record.item] then exact[#exact + 1] = { item = record.item, source = record.source } end
    end
    end
    local minima = Logistics.roleMinimums(actor)
    local counts = {}
    for _, record in ipairs(audit.items) do
        local category = record.category
        local safe = category ~= "food" or not SC.Needs or not SC.Needs.isSafeFoodItem
            or SC.Needs.isSafeFoodItem(record.item)
        safe = safe and (category ~= "water" or not SC.Needs or not SC.Needs.isSafeWaterItem
            or SC.Needs.isSafeWaterItem(record.item))
        if safe and (category == "food" or category == "water" or category == "medicine") then
            counts[category] = (counts[category] or 0) + 1
            if counts[category] <= (tonumber(minima[category]) or 0) then keep[record.item] = true end
        end
    end
    for _, wanted in ipairs(requirements.requiredTools or {}) do
        local needed = type(wanted) == "table" and math.max(1, tonumber(wanted.count) or 1) or 1
        for _, record in ipairs(audit.items) do
            if needed > 0 and Preparation.matches(record.item, wanted) then
                keep[record.item], tools[record.item] = true, true
                needed = needed - 1
            end
        end
        if needed > 0 then missing[#missing + 1] = wanted end
    end
    local preferred
    if SC.Combat and type(SC.Combat.preferredWeapon) == "function" then
        local actorData = select(1, U().call(actor, "getModData"))
        local preference = type(actorData) == "table" and actorData.SC_WeaponPriority or "best"
        local ok, item = pcall(SC.Combat.preferredWeapon, actor, preference)
        if ok then preferred = item end
    end
    local weapons = {}
    if preferred then keep[preferred], weapons[#weapons + 1] = true, preferred end
    for _, record in ipairs(audit.items) do
        if #weapons < 2 and record.item ~= preferred and record.category == "weapon" then
            local usable = SC.Combat and type(SC.Combat.weaponOperational) == "function"
                and SC.Combat.weaponOperational(actor, record.item)
            if usable then keep[record.item], weapons[#weapons + 1] = true, record.item end
        end
    end
    for _, weapon in ipairs(weapons) do
        local ammo = select(1, U().call(weapon, "getAmmoType"))
        ammo = select(1, U().call(ammo, "getItemKey")) or ammo
        local magazine = select(1, U().call(weapon, "getMagazineType"))
        for _, record in ipairs(audit.items) do
            local kind = lower(U().itemType(record.item))
            local tail = string.match(kind, "[^%.:]+$")
            for _, wanted in ipairs({ tostring(ammo or ""), tostring(magazine or "") }) do
                if wanted ~= "" and tail == string.match(lower(wanted), "[^%.:]+$") then keep[record.item] = true end
            end
        end
    end
    return keep, tools, missing, counts, exact
end

function Preparation.bags(actor, audit, requirements, tools)
    local result = { { container = audit.inventory, factor = 1 } }
    local held = requirements.allowHeldBag == true
    for item in pairs(tools or {}) do
        if select(1, U().call(item, "isTwoHandWeapon")) == true then held = false end
    end
    for _, record in ipairs(audit.items) do
        local nested = select(1, nestedInventory(record.item))
        if nested and record.source == audit.inventory
            and Preparation.bagEquipped(actor, record.item, held) then
            local reduction = tonumber((select(1, U().call(record.item, "getWeightReduction")))) or 0
            result[#result + 1] = { container = nested, item = record.item,
                factor = 1 - U().clamp(reduction, 0, 100) / 100 }
        end
    end
    table.sort(result, function(a, b)
        if a.factor ~= b.factor then return a.factor < b.factor end
        return tostring(a.item or a.container) < tostring(b.item or b.container)
    end)
    return result, held
end

function Preparation.assess(actor, preparation, audit, tools)
    local requirements = preparation.requirements
    local cargo = type(requirements.cargo) == "table" and requirements.cargo or {}
    local raw = math.max(0, tonumber(requirements.cargoRaw or requirements.cargoWeight or cargo.weight) or 0)
    local effective = tonumber(requirements.cargoEffective)
    local bags, held = Preparation.bags(actor, audit, requirements, tools)
    local actual = U().carryLoad(actor)
    local weight, maximum, _, _, delta = U().projectedCarryLoad(actor, held)
    local known = type(weight) == "number" and type(maximum) == "number" and maximum > 0
    local planned = weight
    weight, maximum = tonumber(weight) or 0, tonumber(maximum) or 0
    local assessment = { key = preparation.key, stage = preparation.stage, reason = preparation.reason,
        ready = false, cargoReady = false, carryWeight = actual, actualCarryWeight = actual,
        plannedCarryWeight = planned, carryCapacity = maximum,
        physicalCapacity = audit.capacity, rawFree = 0,
        rootFree = math.max(0, Preparation.free(audit.inventory, actor) - (delta or 0)),
        bags = {}, warnings = preparation.warnings,
        cargoDeficit = { raw = raw, effective = 0 }, capacityKnown = known }
    local deficitScore
    for _, bag in ipairs(bags) do
        local free = Preparation.free(bag.container, actor)
        if bag.container == audit.inventory then free = assessment.rootFree end
        local contents = tonumber((select(1, U().call(bag.container, "getContentsWeight"))))
            or tonumber((select(1, U().call(bag.container, "getCapacityWeight")))) or 0
        local capacity = tonumber((select(1, U().call(bag.container, "getEffectiveCapacity", actor))))
            or contents + free
        assessment.rawFree = math.max(assessment.rawFree, free)
        if #assessment.bags < 8 then assessment.bags[#assessment.bags + 1] = {
            id = bag.item and U().itemStableId(bag.item, false) or "inventory",
            name = bag.item and U().itemName(bag.item) or "Inventory",
            weight = contents, capacity = capacity, free = free, factor = bag.factor,
        } end
        local rawDeficit = math.max(0, raw - free, raw - assessment.rootFree)
        local effectiveDeficit = math.max(0, weight + (effective or raw * bag.factor) - maximum)
        if deficitScore == nil or rawDeficit + effectiveDeficit < deficitScore then
            assessment.cargoDeficit = { raw = rawDeficit, effective = effectiveDeficit }
            deficitScore = rawDeficit + effectiveDeficit
        end
        if known and free + 0.000001 >= raw and maximum and maximum > 0
            and weight + (effective or raw * bag.factor) <= maximum + 0.000001
            and weight + raw <= audit.capacity + 0.000001 then assessment.cargoReady = true end
    end
    preparation.assessment, preparation.rawReserve, preparation.allowHeld = assessment, raw, held
    preparation.lastAudit = audit
    preparation.tools = tools
    preparation.auditProof = Preparation.fingerprint(actor, preparation)
    return assessment
end

-- Compare bounded native identities and capacity values, without rerunning
-- role, equipment or storage selection on every ready-member probe.
function Preparation.fingerprint(actor, preparation)
    local audit = preparation.lastAudit
    if not audit then return nil end
    local weight, maximum = U().carryLoad(actor)
    local parts = { tostring(U().inventory(actor)), tostring(weight), tostring(maximum),
        tostring(select(1, U().call(actor, "getPrimaryHandItem"))),
        tostring(select(1, U().call(actor, "getSecondaryHandItem"))),
        tostring(Preparation.camp(actor, preparation.requirements)),
        tostring(preparation.requirements.cargoRaw or preparation.requirements.cargoWeight),
        tostring(preparation.requirements.cargoEffective) }
    local seen = {}
    for _, record in ipairs(audit.items) do
        local container = record.source
        if container and not seen[container] then
            seen[container] = true
            local items = select(1, U().call(container, "getItems"))
            if items == nil and type(container) == "table" then items = container.items end
            local count = items and U().listSize(items) or 0
            parts[#parts + 1] = tostring(container) .. ":" .. tostring(count)
                .. ":" .. tostring(Preparation.free(container, actor))
        end
    end
    for _, node in ipairs(preparation.auditData and preparation.auditData.queue or {}) do
        if node.bag then parts[#parts + 1] = tostring(U().inventoryContains(node.parent, node.bag)) end
    end
    for item in pairs(preparation.tools or {}) do
        local source = select(1, U().call(item, "getContainer"))
        parts[#parts + 1] = tostring(item) .. ":" .. tostring(source)
            .. ":" .. tostring(select(1, U().call(item, "isBroken")))
    end
    for _, record in ipairs(preparation.exactKeep or {}) do
        parts[#parts + 1] = tostring(record.item) .. ":" .. tostring(select(1, U().call(record.item, "getContainer")))
            .. ":" .. tostring(U().inventoryContains(record.source, record.item))
    end
    if SC.InventoryIndex and type(SC.InventoryIndex.version) == "function" then
        parts[#parts + 1] = tostring(SC.InventoryIndex.version(actor))
    end
    -- Empty root inventories still need an identity/count/weight proof.
    local rootItems = select(1, U().call(U().inventory(actor), "getItems"))
    parts[#parts + 1] = tostring(rootItems and U().listSize(rootItems) or 0)
    return table.concat(parts, "|")
end

function Preparation.finish(preparation, ready, reason)
    preparation.ready, preparation.blocked, preparation.reason = ready, ready ~= true, reason
    preparation.stage = ready and "ready" or "blocked"
    local assessment = preparation.assessment or {}
    assessment.stage, assessment.reason, assessment.ready = preparation.stage, reason, ready
    preparation.assessment = assessment
    if ready then preparation.fingerprint = Preparation.fingerprint(preparation.actor, preparation) end
    return false, reason, ready, assessment
end

function Preparation.pending(preparation, stage, reason)
    preparation.stage, preparation.reason = stage, reason
    preparation.assessment.stage, preparation.assessment.reason = stage, reason
    return true, reason, false, preparation.assessment
end

function Logistics.preparationStatus(actor, key)
    local preparation = actor and Preparation.actors[actor]
    if preparation and (key == nil or preparation.key == key) then return preparation.assessment end
end

function Logistics.resetPreparation(actor, key, reason)
    local preparation = actor and Preparation.actors[actor]
    if not preparation or key ~= nil and preparation.key ~= key then return true end
    local state = states[actor]
    if state and state.transaction and state.transaction.preparationKey == preparation.key then
        local released, why = Logistics.yieldToWork(actor)
        if released ~= true then return false, why end
    end
    Preparation.actors[actor] = nil
    return true, reason or "loadout_preparation_reset"
end

-- Cancellation and gear handoffs may finish one already-owned inventory
-- action. This entry point never selects another item or starts another scan.
function Logistics.settlePreparation(actor, key, runtime)
    local preparation = actor and Preparation.actors[actor]
    if not preparation or key ~= nil and preparation.key ~= key then return false, "loadout_settled", true end
    local state = states[actor]
    local transaction = state and state.transaction
    if not transaction then return false, "loadout_settled", true end
    if transaction.preparationKey ~= preparation.key then return false, "loadout_inventory_pending", false end
    local safe, snapshot = safeToManage(actor, runtime)
    if not safe then return false, "loadout_unsafe", false end
    local service = supervisor()
    if service and service.update then service.update(actor) end
    if state.transaction ~= transaction then return false, "loadout_action_cancelled", true end
    local handled, reason
    if transaction.phase == "approach" then handled, reason = approachTransaction(actor, state, snapshot)
    else handled, reason = executeTransaction(actor, state) end
    return handled, reason, not (states[actor] and states[actor].transaction)
end

function Preparation.validTransfer(actor, transaction)
    local preparation = Preparation.actors[actor]
    if not preparation or preparation.key ~= transaction.preparationKey then return false end
    -- Weight, carrying limits and cache versions may change while walking to
    -- storage or playing the transfer pose. They invalidate the cached audit,
    -- not the exact transfer. Reconcile in bounded slices before committing.
    if preparation.auditData and preparation.auditProof ~= Preparation.fingerprint(actor, preparation) then
        preparation.auditData, preparation.inventoryScan = nil, nil
    end
    local audit, inventoryReason = Preparation.inventory(actor, preparation)
    if not audit then
        if inventoryReason then return false, inventoryReason end
        local service, scan = supervisor(), preparation.inventoryScan
        local token = transaction.supervisorToken
        if service and token and scan then
            -- Reconciliation is interruptible pre-commit work. Only genuine
            -- scan advancement extends its deadline, never a stalled cursor.
            if type(service.transition) == "function" then
                service.transition(token, "waiting", { reason = "loadout_inventory_pending" })
            end
            if type(service.progress) == "function" then
                service.progress(token, "inventory:" .. tostring(#scan.items) .. ":" .. tostring(scan.cursor))
            end
        end
        return nil, "loadout_inventory_pending"
    end
    local keep, tools, _, _, exact = Preparation.kit(actor, audit, preparation.requirements)
    preparation.exactKeep = exact
    Preparation.assess(actor, preparation, audit, tools)
    if transaction.kind == "deposit" then
        return Preparation.camp(actor, preparation.requirements) and not keep[transaction.item]
            and not isProtected(actor, transaction.item) and transaction.storage ~= nil
            and SC.BaseLife.storageAcceptsDeposit(transaction.storage, transaction.destination) == true
    end
    if transaction.kind == "withdraw" then
        return Preparation.camp(actor, preparation.requirements)
            and SC.BaseLife.storage(transaction.storage.id) == transaction.storage
            and SC.BaseLife.resolveContainer(transaction.storage) == transaction.source
            and Preparation.supplyAllowed(actor, transaction.storage, transaction.source,
                transaction.item, audit)
    end
    if transaction.kind == "pack" then
        return not tools[transaction.item]
            and transaction.bag and U().inventoryContains(audit.inventory, transaction.bag)
            and Preparation.bagEquipped(actor, transaction.bag, preparation.allowHeld)
            and Preparation.free(transaction.destination, actor) + 0.000001
                >= U().itemWeight(transaction.item) + preparation.rawReserve
    end
    if transaction.kind == "repack" then
        if isProtected(actor, transaction.item) or not transaction.sourceBag
            or not U().inventoryContains(audit.inventory, transaction.sourceBag) then return false end
        if tools[transaction.item] then return transaction.destination == audit.inventory end
        return transaction.destination == audit.inventory
            or transaction.bag and Preparation.bagEquipped(actor, transaction.bag, preparation.allowHeld)
                and Preparation.free(transaction.destination, actor) + 0.000001
                    >= U().itemWeight(transaction.item) + preparation.rawReserve
    end
    return true
end

function Preparation.begin(actor, preparation, transaction, snapshot)
    local state = states[actor] or {}
    states[actor] = state
    transaction.preparationKey = preparation.key
    if transaction.kind == "wear" and transaction.record then
        preparation.replacedBags = replacementItems(actor, transaction.record.location)
    end
    local started, reason = beginTransaction(actor, state, transaction)
    if not started then return Preparation.finish(preparation, false, reason) end
    preparation.moves = preparation.moves + 1
    preparation.stage = transaction.kind == "deposit" and "staging"
        or transaction.kind == "withdraw" and "supplies" or transaction.kind
    preparation.reason = "loadout_" .. preparation.stage
    preparation.assessment.stage, preparation.assessment.reason = preparation.stage, preparation.reason
    local handled, why
    if transaction.phase == "approach" then handled, why = approachTransaction(actor, state, snapshot)
    else handled, why = executeTransaction(actor, state) end
    if handled ~= true then return Preparation.finish(preparation, false, why) end
    return true, why, false, preparation.assessment
end

-- A replaced bag is drained in one direction only. It cannot become another
-- automatic packing destination, and protected receipt items remain untouched.
function Preparation.repack(actor, preparation, audit, tools, snapshot)
    for _, old in ipairs(preparation.replacedBags or {}) do
        local source = select(1, nestedInventory(old))
        if source and U().inventoryContains(audit.inventory, old)
            and not Preparation.bagEquipped(actor, old, true) then
            for _, record in ipairs(audit.items) do
                if record.source == source and not isProtected(actor, record.item) then
                    local destination, bag
                    if tools[record.item] or record.category == "weapon" then
                        if U().containerHasRoom(audit.inventory, actor, record.item) == true then destination = audit.inventory end
                    else
                        local choices = Preparation.bags(actor, audit, preparation.requirements, tools)
                        for _, choice in ipairs(choices) do
                            if choice.item and choice.factor < 1
                                and Preparation.free(choice.container, actor) >= U().itemWeight(record.item) + preparation.rawReserve
                                and U().containerHasRoom(choice.container, actor, record.item) == true then
                                destination, bag = choice.container, choice.item
                                break
                            end
                        end
                    end
                    if destination then return Preparation.begin(actor, preparation, { kind = "repack", item = record.item,
                        source = source, sourceBag = old, destination = destination, bag = bag,
                        allowHeldBag = preparation.allowHeld }, snapshot) end
                end
            end
        end
    end
end

function Preparation.supplyAllowed(actor, row, container, item, audit)
    if not item or not SC.BaseLife.withdrawable(row)
        or not U().inventoryContains(container, item) or Logistics.manualOnlyFilterMask(item)
        or SC.WorkTransport and SC.WorkTransport.foreignProtected
            and SC.WorkTransport.foreignProtected(item, actor) then return false end
    local itemData = select(1, U().call(item, "getModData"))
    if select(1, U().call(item, "isFavorite")) == true
        or Preparation.manualItem(actor, itemData) then return false end
    if SC.PersonalItems and SC.PersonalItems.isProtected
        and SC.PersonalItems.isProtected(item, actor, "camp_supply") then return false end
    if SC.BaseLife.availableCountExact(row, U().itemType(item)) <= 0 then return false end
    local category = Logistics.itemCategory(item)
    if category == "food" and SC.Needs and SC.Needs.isSafeFoodItem
        and not SC.Needs.isSafeFoodItem(item) then return false end
    if category == "water" and SC.Needs and SC.Needs.isSafeWaterItem
        and not SC.Needs.isSafeWaterItem(item) then return false end
    return U().containerHasRoom(audit.inventory, actor, item) == true
end

function Preparation.findSupply(actor, preparation, audit, purpose, wanted)
    local scan = preparation.scan
    if not scan or scan.purpose ~= purpose then
        scan = { purpose = purpose, rows = SC.BaseLife.storageRows(nil, true) or {}, row = 1, index = 0 }
        preparation.scan = scan
    end
    local inspected = 0
    while scan.row <= #scan.rows and inspected < 80 do
        local row = scan.rows[scan.row]
        local container = SC.BaseLife.resolveContainer(row)
        local items = select(1, U().call(container, "getItems"))
        local size = items and U().listSize(items) or 0
        if scan.index >= size then scan.row, scan.index = scan.row + 1, 0
        else
            local item = U().listGet(items, scan.index)
            scan.index, inspected = scan.index + 1, inspected + 1
            if Preparation.supplyAllowed(actor, row, container, item, audit) then
                local matches = purpose == "bag" and select(1, Logistics.bagUpgrade(actor, item)) == true
                    or purpose == "tool" and Preparation.matches(item, wanted)
                    or purpose ~= "bag" and purpose ~= "tool" and Logistics.itemCategory(item) == purpose
                if matches then
                    local candidate = { storage = row, container = container, item = item, purpose = purpose }
                    if purpose == "bag" then
                        local _, difference = Logistics.bagUpgrade(actor, item)
                        if not scan.best or difference > scan.difference then
                            scan.best, scan.difference = candidate, difference
                        end
                    else
                        preparation.scan, preparation.supply = nil, candidate
                        return true
                    end
                end
            end
        end
    end
    if scan.row <= #scan.rows then return nil end
    preparation.scan = nil
    if scan.best then preparation.supply = scan.best return true end
    return false
end

-- A task calls this for its own actor. Status probes read only the retained
-- assessment; blocked attempts remain quiet until the task explicitly retries.
function Logistics.prepareLoadout(actor, requirements, runtime)
    if not actor or type(requirements) ~= "table" or type(requirements.key) ~= "string"
        or requirements.key == "" or #requirements.key > 256
        or requirements.requiredTools ~= nil and type(requirements.requiredTools) ~= "table"
        or requirements.keepItems ~= nil and type(requirements.keepItems) ~= "table"
        or type(requirements.requiredTools) == "table" and #requirements.requiredTools > 16
        or type(requirements.keepItems) == "table" and #requirements.keepItems > 128 then
        return false, "invalid_loadout_request", false
    end
    for _, value in ipairs({ requirements.cargoRaw or 0, requirements.cargoWeight or 0,
        requirements.cargoEffective or 0, type(requirements.cargo) == "table" and requirements.cargo.weight or 0 }) do
        if type(value) ~= "number" or value ~= value or value < 0 or value > 10000 then
            return false, "invalid_loadout_request", false
        end
    end
    local preparation = Preparation.actors[actor]
    if preparation and preparation.key ~= requirements.key then
        local reset, why = Logistics.resetPreparation(actor, preparation.key)
        if not reset then return false, why, false, preparation.assessment end
        preparation = nil
    end
    if not preparation then
        preparation = { key = requirements.key, actor = actor, requirements = requirements, moves = 0,
            warnings = {}, completedSupplies = {}, skipped = {}, stage = "assessing" }
        Preparation.actors[actor] = preparation
    end
    if preparation.ready and preparation.fingerprint ~= Preparation.fingerprint(actor, preparation) then
        preparation.ready, preparation.blocked, preparation.moves = nil, nil, 0
        preparation.requirements, preparation.completedSupplies, preparation.skipped = requirements, {}, {}
        preparation.warnings, preparation.warningSet, preparation.stage = {}, {}, "assessing"
        preparation.auditData, preparation.inventoryScan = nil, nil
    end
    if preparation.ready or preparation.blocked then
        return false, preparation.reason, preparation.ready == true, preparation.assessment
    end
    local safe, snapshot = safeToManage(actor, runtime)
    if not safe then return false, "loadout_unsafe", false, preparation.assessment end
    local state = states[actor]
    if state and state.transaction then
        local transaction = state.transaction
        if transaction.preparationKey ~= preparation.key then
            return false, "loadout_inventory_pending", false, preparation.assessment
        end
        local service = supervisor()
        if service and service.update then service.update(actor) end
        if state.transaction ~= transaction then return Preparation.finish(preparation, false, "loadout_action_cancelled") end
        local handled, why
        if transaction.phase == "approach" then handled, why = approachTransaction(actor, state, snapshot)
        else handled, why = executeTransaction(actor, state) end
        if not handled then return Preparation.finish(preparation, false, why) end
        return true, why, false, preparation.assessment
    end
    if preparation.supply then
        local supply = preparation.supply
        preparation.supply = nil
        if supply.purpose == "bag" then preparation.completedSupplies.bag = true end
        if not Preparation.camp(actor, requirements) then return Preparation.finish(preparation, false, "loadout_camp_changed") end
        return Preparation.begin(actor, preparation, { kind = "withdraw", item = supply.item,
            source = supply.container, destination = U().inventory(actor), storage = supply.storage,
            owner = SC.BaseLife.resolveObject(supply.storage), phase = "approach" }, snapshot)
    end
    if preparation.moves >= 64 then return Preparation.finish(preparation, false, "loadout_move_limit") end
    if preparation.auditData and preparation.auditProof
        and preparation.auditProof ~= Preparation.fingerprint(actor, preparation) then
        preparation.auditData, preparation.inventoryScan = nil, nil
    end
    local audit, inventoryReason = Preparation.inventory(actor, preparation)
    if not audit then
        if inventoryReason then return Preparation.finish(preparation, false, inventoryReason) end
        preparation.stage, preparation.reason = "assessing", "loadout_inventory_pending"
        preparation.assessment = preparation.assessment or { warnings = preparation.warnings }
        preparation.assessment.stage, preparation.assessment.reason = preparation.stage, preparation.reason
        preparation.assessment.ready, preparation.assessment.cargoReady = false, false
        return true, preparation.reason, false, preparation.assessment
    end
    local keep, tools, missing, counts, exact = Preparation.kit(actor, audit, requirements)
    preparation.exactKeep = exact
    local assessment = Preparation.assess(actor, preparation, audit, tools)
    if not assessment.capacityKnown then return Preparation.finish(preparation, false, "loadout_capacity_unavailable") end
    local camp = Preparation.camp(actor, requirements)
    if camp then
        if #missing > 0 then
            if preparation.completedSupplies.tool then return Preparation.finish(preparation, false, "loadout_tool_missing") end
            local found = Preparation.findSupply(actor, preparation, audit, "tool", missing[1])
            if found ~= false then return Preparation.pending(preparation, "supplies", "loadout_seeking_tool") end
            preparation.completedSupplies.tool = true
            return Preparation.finish(preparation, false, "loadout_tool_missing")
        end
        local removal = Preparation.maskRemoval(actor, audit)
        if removal then return Preparation.begin(actor, preparation, { kind = "unwear", item = removal.item,
            source = removal.source, record = { location = wearableLocation(removal.item) } }, snapshot) end
        if requirements.allowBagUpgrade ~= false then
            local upgrade = selectBagUpgrade(actor, audit)
            if upgrade then return Preparation.begin(actor, preparation, { kind = "wear", item = upgrade.item,
                source = upgrade.source, record = upgrade }, snapshot) end
            if not preparation.completedSupplies.bag then
                local found = Preparation.findSupply(actor, preparation, audit, "bag")
                if found ~= false then return Preparation.pending(preparation, "supplies", "loadout_seeking_bag") end
                preparation.completedSupplies.bag = true
            end
        end
        for _, record in ipairs(audit.items) do
            if not keep[record.item] and not isProtected(actor, record.item)
                and not preparation.skipped[record.item] then
                preparation.destinationState = preparation.destinationState or {}
                local destination, why = storageFor(actor, record.item, record.category, false, preparation.destinationState)
                if why == "storage_route_pending" then return Preparation.pending(preparation, "staging", why) end
                if destination and destination.storage and destination.storage.kind ~= "log_yard" then
                    preparation.destinationState = nil
                    return Preparation.begin(actor, preparation, { kind = "deposit", item = record.item,
                        source = record.source, destination = destination.container, owner = destination.owner,
                        storage = destination.storage, phase = "approach" }, snapshot)
                end
                preparation.skipped[record.item], preparation.destinationState = true, nil
                Preparation.warn(preparation, "loadout_storage_unavailable")
            end
        end
    end
    local repacked, repackReason, repackReady, repackAssessment = Preparation.repack(actor, preparation, audit, tools, snapshot)
    if repacked ~= nil then return repacked, repackReason, repackReady, repackAssessment end
    local move = selectPackMove(actor, audit, { allowHeldBag = preparation.allowHeld,
        rawReserve = preparation.rawReserve, tools = tools })
    if move then return Preparation.begin(actor, preparation, { kind = "pack", item = move.item,
        source = move.source, destination = move.destination, bag = move.bag,
        allowHeldBag = preparation.allowHeld }, snapshot) end
    if camp then
        for _, category in ipairs({ "food", "water", "medicine" }) do
            if (counts[category] or 0) < (tonumber(Logistics.roleMinimums(actor)[category]) or 0)
                and not preparation.completedSupplies[category] then
                local found = Preparation.findSupply(actor, preparation, audit, category)
                if found ~= false then return Preparation.pending(preparation, "supplies", "loadout_seeking_" .. category) end
                preparation.completedSupplies[category] = true
                Preparation.warn(preparation, "loadout_" .. category .. "_shortage")
            end
        end
    end
    for _, category in ipairs({ "food", "water", "medicine" }) do
        if (counts[category] or 0) < (tonumber(Logistics.roleMinimums(actor)[category]) or 0) then
            Preparation.warn(preparation, "loadout_" .. category .. "_shortage")
        end
    end
    if #missing > 0 then return Preparation.finish(preparation, false, "loadout_tool_missing") end
    if not assessment.cargoReady and requirements.haulRequired ~= false then
        return Preparation.finish(preparation, false, "loadout_carry_capacity")
    end
    if not assessment.cargoReady then Preparation.warn(preparation, "loadout_reduced_cargo_room") end
    return Preparation.finish(preparation, true, #preparation.warnings > 0 and "loadout_ready_with_warnings" or "loadout_ready")
end

function Logistics.update(actor, player, runtime)
    if not actor then return false, "invalid_logistics_actor" end
    local safe, snapshot = safeToManage(actor, runtime)
    local existing = states[actor]
    if existing and existing.transaction then
        -- Logistics owns its token for the entire asynchronous visual. Unlike a
        -- movement request it does not naturally call movementPermission(), so
        -- explicitly service the deadline and protected-pose invariants here.
        -- Without this watchdog a native Loot action that never advanced could
        -- pin the companion in "Logistics: packing" until its chunk unloaded.
        local transaction = existing.transaction
        local service = supervisor()
        if service and type(service.update) == "function" then service.update(actor) end
        if existing.transaction ~= transaction then
            -- The supervisor ended the move (a moved protected pose, a
            -- deadline): cool it down so the same Loot pose is not restarted.
            moveMemory.note(actor, transaction.kind, transaction.item, U().nowMs())
            states[actor] = nil
            return false, "logistics_action_cancelled"
        end
    end
    if not safe then
        cancelTransaction(actor, existing, "logistics_unsafe")
        if existing then states[actor] = nil end
        return false, "logistics_unsafe"
    end
    if existing and existing.transaction then
        if existing.transaction.phase == "approach" then
            return approachTransaction(actor, existing, snapshot)
        end
        return executeTransaction(actor, existing)
    end
    local audit = Logistics.status(actor)
    if audit.manualMaskRemoval then
        local record = audit.manualMaskRemoval
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "unwear", item = record.item, source = record.source,
            record = { location = wearableLocation(record.item) },
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if audit.weaponReady then
        local gifts = pendingGifts[actor]
        local data, dataOk = U().call(actor, "getModData")
        local preference = dataOk and type(data) == "table"
            and data.SC_WeaponPriority or "best"
        local equipped, reason = false, "combat_unavailable"
        if SC.Combat and type(SC.Combat.equipPreferred) == "function" then
            equipped, reason = SC.Combat.equipPreferred(actor, preference, {
                immediateCommand = false,
            })
        end
        local state = states[actor]
        if state then
            state.nextWeaponAt = U().nowMs() + (equipped and 0 or 1500)
            state.auditAt = -math.huge
        end
        if equipped or reason == "no_usable_weapon" then
            if gifts then
                for item in pairs(gifts.items) do
                    if Logistics.itemCategory(item) == "weapon" then
                        gifts.items[item] = nil
                    end
                end
            end
        end
        return equipped, reason
    end
    local fieldDelivery = audit.fieldReturnCleanup and audit.shouldUnload
    if audit.bagUpgrade and not fieldDelivery then
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "wear", item = audit.bagUpgrade.item,
            source = audit.bagUpgrade.source, record = audit.bagUpgrade,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if audit.clothingUpgrade and not fieldDelivery then
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "wear", item = audit.clothingUpgrade.item,
            source = audit.clothingUpgrade.source, record = audit.clothingUpgrade,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if audit.packMove and not fieldDelivery then
        local move = audit.packMove
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "pack", item = move.item, source = move.source,
            destination = move.destination, bag = move.bag,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if not audit.shouldUnload then
        if audit.cleanupDone then
            local data = select(1, U().call(actor, "getModData"))
            if type(data) == "table" then data.LF_FieldReturnCleanup = nil end
        end
        states[actor] = nil
        return false, "load_balanced"
    end
    local state = states[actor] or {}
    states[actor] = state
    if not state.item or not state.source or not U().inventoryContains(state.source, state.item) then
        state.item, state.category = audit.surplus.item, audit.surplus.category
        state.proactive = audit.surplus.proactive == true
        state.keptHarvest = audit.surplus.keptHarvest == true
        state.shelveOnly = audit.surplus.shelveOnly == true
        state.fieldReturnCleanup = audit.fieldReturnCleanup == true
        state.source = audit.surplus.source or audit.inventory
        state.destination, state.navigationChoice, state.interactionRouteReceipt = nil, nil, nil
    end
    if not state.destination then
        local destination, routeReason, receipt = storageFor(actor, state.item, state.category,
            state.proactive and not state.fieldReturnCleanup
                and (state.category == "literature" or state.category == "farming"),
            state)
        state.destination = destination
        state.interactionRouteReceipt = receipt
        if routeReason then
            -- A pending survey resumes next beat. A finished survey that
            -- found no walkable route (or ran out of budget) is a failed
            -- deposit: cool this item down like any other failed move, or
            -- the same unreachable shelf is chosen again on every beat.
            if routeReason ~= "storage_route_pending" then
                moveMemory.note(actor, "deposit", state.item, U().nowMs())
                states[actor] = nil
            end
            return routeReason == "storage_route_pending", routeReason
        end
    end
    if state.destination then
        local destination = state.destination
        if destination.storage and destination.storage.kind == "log_yard" then
            local root = U().inventory(actor)
            if state.source ~= root then
                local unpacked, unpackReason = U().transferItemVerified(
                    state.source, root, state.item)
                if not unpacked then return false, unpackReason end
                state.source = root
            end
            if not SC.BaseWork or type(SC.BaseWork.depositToStorage) ~= "function" then
                return false, "log_yard_delivery_unavailable"
            end
            local accepted, yardReason = SC.BaseWork.depositToStorage(actor,
                state, destination.storage, destination.container, state.item,
                { movementPriority = 74 })
            if accepted == true and not U().inventoryContains(root, state.item) then
                local data = U().modData(state.item)
                if data then data.LF_FieldCarryWorker = nil end
                state.auditAt = -math.huge
                states[actor] = nil
                return true, "surplus_stored"
            end
            return accepted, yardReason or "log_yard_delivery_pending"
        end
        -- Even an adjacent actor must prove it is on a usable side of the
        -- container.  Raw range admits the tile across an exterior wall.
        local phase = "approach"
        local started, reason = beginTransaction(actor, state, {
            kind = "deposit", item = state.item, source = state.source,
            destination = destination.container, owner = destination.owner,
            phase = phase, keptHarvest = state.keptHarvest,
        })
        if not started then states[actor] = nil return false, reason end
        if phase == "approach" then return approachTransaction(actor, state, snapshot) end
        return executeTransaction(actor, state)
    end

    -- Proactive shelving is allowed only when the player marked a real
    -- literature destination. Without one, keep the item instead of falling
    -- through to the overload path that drops surplus on the ground. Field
    -- return cleanup and Strength-limit shelving are storage-only too: only
    -- the physical overload above may ever drop an item.
    if state.fieldReturnCleanup or state.shelveOnly
        or state.proactive and (state.keptHarvest
        or state.category == "literature" or state.category == "farming") then
        moveMemory.note(actor, "deposit", state.item, U().nowMs())
        states[actor] = nil
        return false, (state.keptHarvest and "harvest" or state.category)
            .. "_storage_unavailable"
    end

    local square = U().squareOf(actor)
    if not square then states[actor] = nil return false, "drop_square_unavailable" end
    local started, reason = beginTransaction(actor, state, {
        kind = "drop", item = state.item, source = state.source, square = square,
        destination = state.source,
    })
    if not started then states[actor] = nil return false, reason end
    return executeTransaction(actor, state)
end

local function matchesHammer(item)
    local broken, brokenOk = U().call(item, "isBroken")
    if brokenOk and broken then return false end
    local itemTag = type(_G) == "table" and rawget(_G, "ItemTag") or nil
    local tagOk, hammerTag = pcall(function() return itemTag and itemTag.HAMMER or nil end)
    if tagOk and hammerTag ~= nil then
        local tagged, taggedOk = U().call(item, "hasTag", hammerTag)
        if taggedOk then return tagged == true end
    end
    return U().itemHasTag(item, "Hammer")
end

local function matchesType(item, shortType)
    local full = string.lower(U().itemType(item))
    local wanted = string.lower(shortType)
    return full == wanted or full == "base." .. wanted
end

buildRequirements = {
    {
        key = "build_hammer",
        count = 1,
        predicate = matchesHammer,
        missing = "companion needs a hammer",
    },
    {
        key = "build_plank",
        count = 1,
        predicate = function(item) return matchesType(item, "Plank") end,
        missing = "companion needs one plank",
    },
    {
        key = "build_nails",
        count = 2,
        predicate = function(item) return matchesType(item, "Nails") end,
        missing = "companion needs two nails",
    },
}

local function inventoryCount(actor, predicate)
    local count = 0
    walkContainer(U().inventory(actor), { remaining = 256 }, function(item)
        local protected = SC.PersonalItems
            and SC.PersonalItems.isProtected(item, actor, "build_material")
        local ok, matched = false, false
        if not protected then ok, matched = pcall(predicate, item) end
        if ok and matched == true then count = count + 1 end
        return true
    end)
    return count
end

function Logistics.prepareBuild(actor, targetSquare, snapshot, moveMode)
    if not actor then return false, false, "invalid_build_actor" end
    for _, requirement in ipairs(buildRequirements) do
        if inventoryCount(actor, requirement.predicate) < requirement.count then
            if not SC.Encounter or type(SC.Encounter.takePlayerSupply) ~= "function" then
                return false, false, requirement.missing
            end
            local status, reason = SC.Encounter.takePlayerSupply(
                actor,
                requirement.key,
                requirement.predicate,
                {
                    origin = targetSquare or actor,
                    snapshot = snapshot,
                    moveMode = moveMode or "walk",
                }
            )
            if status == "taken" or status == "in_progress" then
                return false, true, reason or "gathering_build_supplies"
            end
            if status == "unsafe" then return false, true, reason end
            if status == "missing" then return false, false, requirement.missing end
            return false, false, reason or requirement.missing
        end
    end
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    return true, false, "build_supplies_ready"
end

-- Routine shelving may yield before its transfer starts. Never discard an
-- animating/committing transaction to make a higher-scoring chore look ready.
function Logistics.yieldToWork(actor)
    local state = actor and states[actor]
    local transaction = state and state.transaction
    if not transaction then return true end
    if transaction.phase ~= "approach" then return false, "logistics_transfer_in_progress" end
    local service, token = supervisor(), transaction.supervisorToken
    if token and service and service.isCurrent and service.isCurrent(token) then
        local cancelled, reason = service.cancel(actor, "priority_base_work")
        if cancelled ~= true then return false, reason end
    elseif token then
        return false, "logistics_owner_changed"
    else
        cleanupTransaction(actor, state, "priority_base_work")
        if SC.Navigation and SC.Navigation.cancel then SC.Navigation.cancel(actor, "priority_base_work") end
    end
    if state.transaction ~= nil then return false, "logistics_release_pending" end
    states[actor] = nil
    return true
end

-- True while a pack, wear, deposit or drop holds this actor's action owner.
function Logistics.busy(actor)
    local state = actor and states[actor] or nil
    return state ~= nil and state.transaction ~= nil
end

function Logistics.reset(actor)
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" and actor then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    if actor then
        cancelTransaction(actor, states[actor], "logistics_reset")
        states[actor] = nil
        Preparation.actors[actor] = nil
        -- A stay, order change, or interrupted transaction resets logistics,
        -- but must not erase the player's confirmed gift before its loadout
        -- review. The next audit discards items no longer owned by this actor.
        moveMemory.byActor[actor] = nil
    else
        for value, state in pairs(states) do
            cancelTransaction(value, state, "logistics_reset")
        end
        states = setmetatable({}, { __mode = "k" })
        Preparation.actors = setmetatable({}, { __mode = "k" })
        pendingGifts = setmetatable({}, { __mode = "k" })
        moveMemory.byActor = setmetatable({}, { __mode = "k" })
    end
    return true
end

return Logistics
