-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Logistics = SC.Logistics or {}
local Logistics = SC.Logistics
local states = setmetatable({}, { __mode = "k" })
local containerHasRoom
local storageFor

local function U()
    return SC.GameplayUtil
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
        local nested, nestedOk = U().call(item, "getInventory")
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
    literature = "literature", clothing = "general", container = "general",
    general = "general",
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

function Logistics.itemCategory(item)
    local utility = U()
    local itemType = lower(utility.itemType(item))
    local category, categoryOk = utility.call(item, "getCategory")
    category = categoryOk and lower(category) or ""
    local display, displayOk = utility.call(item, "getDisplayCategory")
    display = displayOk and lower(display) or ""
    if SC.FarmWork and type(SC.FarmWork.isFarmingSupply) == "function"
        and SC.FarmWork.isFarmingSupply(item) == true then return "farming" end
    -- Check the engine category before filename heuristics. Ordinary magazines
    -- otherwise match the ammunition fragment below and get shelved with ammo.
    if category == "literature" or display == "literature" then return "literature" end
    if typeContains(itemType, { "bandage", "rippedsheet", "disinfect", "painkiller",
        "antibiotic", "suture", "firstaid", "alcoholwipes", "pills" })
        or category == "medical" or display == "medical" then return "medicine" end
    if typeContains(itemType, { "waterbottle", "waterbottle", "canteen", "flask" })
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
    if typeContains(itemType, { "scrap", "electronic", "screws", "glue", "ducttape",
        "adhesivetape", "twine", "thread", "leather", "rope", "tarp", "fabric" })
        or display == "crafting" then return "crafting" end
    local nested, nestedOk = utility.call(item, "getInventory")
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

function Logistics.audit(actor)
    local role = Logistics.roleOf(actor)
    local profile = profiles[role] or profiles.generalist
    local counts, items = {}, {}
    local remaining = U().config("logisticsInventoryItemBudget") or 256
    walkContainer(U().inventory(actor), { remaining = remaining }, function(item, source)
        local category = Logistics.itemCategory(item)
        counts[category] = (counts[category] or 0) + 1
        items[#items + 1] = { item = item, category = category, source = source }
        return true
    end)
    local weight, capacity, ratio, inventory = U().inventoryLoad(actor)
    local soft, hard = loadRatios(role, actor)
    return {
        role = role, profile = profile, counts = counts, items = items,
        weight = weight, capacity = capacity, ratio = ratio,
        softRatio = soft, hardRatio = hard, inventory = inventory,
        allowOverload = overloadAllowed(actor),
    }
end

local function dynamicTarget(audit, category, actor)
    local target = tonumber(audit.profile.target[category]) or 0
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
    local location = wearableLocation(item)
    if not location or not isClothingItem(item) then
        return false, 0, nil, nil
    end
    local replacements = replacementItems(actor, location)
    local current = replacements[1]
    if isWorn(actor, item, location) then return false, 0, current, location end
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
    local nested, nestedOk = U().call(item, "getInventory")
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

function Logistics.canTake(actor, item, category, audit)
    if not actor or not item then return false, "invalid_loot" end
    if notRealGear(item) then return false, "not_real_gear" end
    audit = audit or Logistics.audit(actor)
    category = category or Logistics.itemCategory(item)
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
    if target <= 0 or (audit.counts[category] or 0) >= target then
        return false, "loadout_satisfied"
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
    local ok, assessment = pcall(SC.Medical.assess, actor)
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

function Logistics.itemNeedScore(actor, item, commands, audit)
    audit = audit or Logistics.audit(actor)
    local category = Logistics.itemCategory(item)
    local accepted, reason = Logistics.canTake(actor, item, category, audit)
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
        local amount, amountOk = U().call(item, "getUsedDelta")
        if amountOk and type(amount) == "number" then score = score * math.max(0.2, amount) end
    end
    return score, category
end

local function isProtected(actor, item)
    if not actor or not item then return true end
    if SC.PersonalItems and SC.PersonalItems.isProtected
        and SC.PersonalItems.isProtected(item, actor, "loadout") then return true end
    local favorite, favoriteOk = U().call(item, "isFavorite")
    if favoriteOk and favorite == true then return true end
    local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
    if primaryOk and primary == item then return true end
    local secondary, secondaryOk = U().call(actor, "getSecondaryHandItem")
    if secondaryOk and secondary == item then return true end
    local worn, wornOk = U().call(actor, "isEquippedClothing", item)
    if wornOk and worn == true then return true end
    local nested, nestedOk = U().call(item, "getInventory")
    if nestedOk and nested and #U().inventoryItems(nested, 1) > 0 then return true end
    return false
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
        if record.category == "clothing" and not isProtected(actor, record.item) then
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

local function selectPackMove(actor, audit)
    local best
    -- Only loose items in the main inventory are packed. An item already in
    -- one worn bag is never moved into another: with two worn bags (a duffel
    -- and a fanny pack) that ping-ponged the same items back and forth
    -- forever, each move succeeding and replaying the Loot pose.
    local root = U().inventory(actor)
    for _, bagRecord in ipairs(audit.items) do
        local bagValue, location, bagInventory = bagScore(bagRecord.item)
        if bagValue and isWorn(actor, bagRecord.item, location) then
            for _, record in ipairs(audit.items) do
                local nested, nestedOk = U().call(record.item, "getInventory")
                local clothingUpgrade = record.category == "clothing"
                    and select(1, Logistics.clothingUpgrade(actor, record.item)) == true
                local bagUpgrade = record.category == "container"
                    and select(1, Logistics.bagUpgrade(actor, record.item)) == true
                if record.item ~= bagRecord.item and record.source ~= bagInventory
                    and record.source == root
                    and not (nestedOk and nested) and not isProtected(actor, record.item)
                    -- Keep weapons in the root inventory. Combat/equip actions
                    -- need immediate ownership of newly gifted fallback weapons;
                    -- packing a BreadKnife into the worn bag both hid it from the
                    -- native handoff and caused a pointless unpack/equip cycle.
                    and record.category ~= "weapon"
                    and not clothingUpgrade and not bagUpgrade
                    and U().inventoryContains(record.source, record.item)
                    and containerHasRoom(bagInventory, record.item) then
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
    return true, "wearable_equipped"
end

function Logistics.selectSurplus(actor, audit)
    audit = audit or Logistics.audit(actor)
    local best, bestScore
    for _, record in ipairs(audit.items) do
        local item = record.item
        if not isProtected(actor, item) then
            local category = record.category or Logistics.itemCategory(item)
            local count = audit.counts[category] or 0
            local target = tonumber(audit.profile.target[category]) or 0
            local keep = tonumber(audit.profile.keep[category]) or 0
            local eligible = category == "general" or count > target
                or (audit.ratio > audit.hardRatio and count > keep)
            if eligible then
                local score = (category == "general" and 100 or 35)
                    + math.max(0, count - target) * 12 + U().itemWeight(item) * 4
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

local function selectFarmingSurplus(actor, audit)
    for _, record in ipairs(audit.items or {}) do
        if (record.category or Logistics.itemCategory(record.item)) == "farming"
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

function Logistics.status(actor)
    local state = states[actor]
    local current = U().nowMs()
    if state and state.audit and current - (state.auditAt or 0) < 500 then
        return state.audit
    end
    local audit = Logistics.audit(actor)
    audit.bagUpgrade = selectBagUpgrade(actor, audit)
    audit.clothingUpgrade = selectOwnedClothingUpgrade(actor, audit)
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
    local surplus = nil
    if audit.capacity > 0 and audit.ratio > audit.softRatio then
        surplus = Logistics.selectSurplus(actor, audit)
    end
    if not surplus then
        local literature = selectLiteratureSurplus(actor, audit)
        if literature and storageFor(actor, literature.item, "literature", true) then
            surplus = literature
        end
    end
    if not surplus then
        local farming = selectFarmingSurplus(actor, audit)
        if farming and storageFor(actor, farming.item, "farming", true) then surplus = farming end
    end
    if surplus and (moveMemory.cooling(actor, "deposit", surplus.item, current)
        or moveMemory.cooling(actor, "drop", surplus.item, current)) then
        surplus = nil
    end
    audit.surplus = surplus
    audit.shouldUnload = surplus ~= nil
    audit.shouldManage = audit.bagUpgrade ~= nil or audit.clothingUpgrade ~= nil
        or audit.packMove ~= nil or audit.shouldUnload
    audit.overloaded = audit.capacity > 0 and audit.ratio > audit.hardRatio
    state = state or {}
    states[actor] = state
    state.audit, state.auditAt = audit, current
    return audit
end

containerHasRoom = function(container, item)
    local current, currentOk = U().call(container, "getCapacityWeight")
    local capacity, capacityOk = U().call(container, "getCapacity")
    if not capacityOk or type(capacity) ~= "number" or capacity <= 0 then
        capacity, capacityOk = U().call(container, "getMaxWeight")
    end
    if not currentOk or not capacityOk or type(current) ~= "number"
        or type(capacity) ~= "number" or capacity <= 0 then return true end
    return current + U().itemWeight(item) <= capacity
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
            if score and nested and isWorn(actor, record.item, location)
                and containerHasRoom(nested, item) then
                local current, currentOk = U().call(nested, "getCapacityWeight")
                local capacity, capacityOk = U().call(nested, "getCapacity")
                local free = currentOk and capacityOk and tonumber(capacity)
                    and math.max(0, tonumber(capacity) - (tonumber(current) or 0)) or 0
                local candidateScore = score + free * 0.15
                if bestScore == nil or candidateScore > bestScore then
                    best, bestScore, bestItem = nested, candidateScore, record.item
                end
            end
        end
    end
    if best then return best, "worn_bag", bestItem end
    return root, "inventory"
end

storageFor = function(actor, item, category, dedicatedOnly)
    if not SC.BaseLife or type(SC.BaseLife.storageRows) ~= "function"
        or type(SC.BaseLife.resolveContainer) ~= "function" then return nil end
    local wanted = storageCategory[category] or "general"
    local categories = dedicatedOnly and { wanted }
        or wanted == "general" and { "general", "output" }
        or { wanted, "general", "output" }
    local best, bestDistance
    for _, storageType in ipairs(categories) do
        for _, storage in ipairs(SC.BaseLife.storageRows(storageType) or {}) do
            if storage.deposits ~= false then
                local container, owner = SC.BaseLife.resolveContainer(storage)
                if container and container ~= U().inventory(actor) and containerHasRoom(container, item) then
                    local distance = U().distance(actor, owner or container)
                    if distance <= (U().config("logisticsStorageRange") or 32)
                        and (bestDistance == nil or distance < bestDistance) then
                        best = { storage = storage, container = container,
                            owner = owner or container, distance = distance }
                        bestDistance = distance
                    end
                end
            end
        end
        if best then break end
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
    if not SC.NativeActions or type(SC.NativeActions.visualStatus) ~= "function" then
        return nil
    end
    local ok, status = pcall(SC.NativeActions.visualStatus, actor,
        expectedAction or "loot_container")
    return ok and status or nil
end

local function clearVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        pcall(SC.NativeActions.clearVisual, actor)
    end
end

local function cleanupTransaction(actor, state, reason)
    local transaction = state and state.transaction or nil
    if transaction and transaction.phase == "visual" and SC.NativeActions
        and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "logistics_cancelled")
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
    local visualAction = transaction.kind == "wear"
        and "wear_clothing" or "loot_container"
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
            if service and token and type(service.transition) == "function" then
                service.transition(token, "committing", { action = visualAction })
            end
            return true, "logistics_action_completed"
        end
        if status == nil then
            if service and token and type(service.markVisualVerified) == "function" then
                service.markVisualVerified(token, { action = visualAction, tracked = false })
            end
            transaction.phase = "commit"
            if service and token and type(service.transition) == "function" then
                service.transition(token, "committing", { action = visualAction })
            end
            return true, "logistics_action_untracked"
        end
        return nil, "logistics_animation_" .. tostring(status)
    end

    stopForInventoryAction(actor)
    local intent = transaction.kind == "wear" and {
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
    if service and token and type(service.transition) == "function" then
        service.transition(token, "committing", { action = visualAction })
    end
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

    if transaction.kind == "wear" then
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
    local transferred, transferReason = U().transferItemVerified(
        transaction.source, transaction.destination, transaction.item)
    markTransactionVerifying(transaction, { kind = transaction.kind })
    if transferred then
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
    if audit.bagUpgrade then
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "wear", item = audit.bagUpgrade.item,
            source = audit.bagUpgrade.source, record = audit.bagUpgrade,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if audit.clothingUpgrade then
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "wear", item = audit.clothingUpgrade.item,
            source = audit.clothingUpgrade.source, record = audit.clothingUpgrade,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if audit.packMove then
        local move = audit.packMove
        local state = states[actor] or {}
        states[actor] = state
        local started, reason = beginTransaction(actor, state, {
            kind = "pack", item = move.item, source = move.source,
            destination = move.destination,
        })
        if not started then states[actor] = nil return false, reason end
        return executeTransaction(actor, state)
    end
    if not audit.shouldUnload then states[actor] = nil return false, "load_balanced" end
    local state = states[actor] or {}
    states[actor] = state
    if not state.item or not state.source or not U().inventoryContains(state.source, state.item) then
        state.item, state.category = audit.surplus.item, audit.surplus.category
        state.proactive = audit.surplus.proactive == true
        state.source = audit.surplus.source or audit.inventory
        state.destination = storageFor(actor, state.item, state.category,
            state.proactive and (state.category == "literature" or state.category == "farming"))
    end
    if state.destination then
        local destination = state.destination
        -- Even an adjacent actor must prove it is on a usable side of the
        -- container.  Raw range admits the tile across an exterior wall.
        local phase = "approach"
        local started, reason = beginTransaction(actor, state, {
            kind = "deposit", item = state.item, source = state.source,
            destination = destination.container, owner = destination.owner,
            phase = phase,
        })
        if not started then states[actor] = nil return false, reason end
        if phase == "approach" then return approachTransaction(actor, state, snapshot) end
        return executeTransaction(actor, state)
    end

    -- Proactive shelving is allowed only when the player marked a real
    -- literature destination. Without one, keep the item instead of falling
    -- through to the overload path that drops surplus on the ground.
    if state.proactive and (state.category == "literature" or state.category == "farming") then
        moveMemory.note(actor, "deposit", state.item, U().nowMs())
        states[actor] = nil
        return false, state.category .. "_storage_unavailable"
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

local buildRequirements = {
    {
        key = "build_hammer",
        count = 1,
        predicate = matchesHammer,
        missing = "companion needs an unbroken hammer",
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

function Logistics.reset(actor)
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" and actor then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    if actor then
        cancelTransaction(actor, states[actor], "logistics_reset")
        states[actor] = nil
        moveMemory.byActor[actor] = nil
    else
        for value, state in pairs(states) do
            cancelTransaction(value, state, "logistics_reset")
        end
        states = setmetatable({}, { __mode = "k" })
        moveMemory.byActor = setmetatable({}, { __mode = "k" })
    end
    return true
end

return Logistics
