-- SPDX-License-Identifier: MIT
-- A stocked expedition carrier gathers requested camp supplies without
-- changing opportunistic scavenging or the native capacity/safety admission.
local SC, checks = SurvivorCompanion, 0
local Logistics = SC.Logistics
local function check(value, message)
    checks = checks + 1
    if not value then error("supply policy " .. checks .. ": " .. message) end
end
SC.GameplayUtil = {
    call = function(value, method, ...)
        if value and type(value[method]) == "function" then
            return value[method](value, ...), true
        end
        return nil, false
    end,
    itemType = function(value) return value.fullType end,
    itemWeight = function(value) return value.weight end,
    itemHasTag = function(value, tag) return value.tags[tag] == true end,
    hasMethod = function(value, method) return type(value[method]) == "function" end,
    instanceOf = function() return false end,
    characterStatValue = function(_, _, fallback) return fallback end,
    config = function() return nil end,
    idOf = function(value) return value.id end,
}
SC.Combat = { weaponAvailability = function() return 2, 2 end }
SC.Medical = { assess = function() return {} end }
SC.FarmWork = { isFarmingSupply = function(value) return value.farming == true end }
SC.BaseLife = { isValuableItem = function(value) return value.valuable == true end }
local function item(fullType, category, fields)
    local value = fields or {}
    value.fullType, value.category = fullType, category or "Item"
    value.weight, value.tags = value.weight or 1, value.tags or {}
    function value:getFullType() return self.fullType end
    function value:getCategory() return self.category end
    function value:getDisplayCategory() return self.category end
    function value:getCondition() return self.condition == nil and 10 or self.condition end
    function value:getConditionMax() return 10 end
    function value:getUsedDelta() return 1 end
    function value:isRotten() return self.rotten == true end
    function value:getBodyLocation() return self.location end
    function value:getScriptItem()
        return { isHidden = function() return value.hidden == true end,
            isCosmetic = function() return value.cosmetic == true end }
    end
    return value
end
local actor = { id = "stocked-expedition-leader" }
local audit = { role = "generalist", counts = {}, profile = { target = {} },
    weight = 2, capacity = 10, softRatio = 0.7, hardRatio = 0.9 }
local supplies = {
    { "food", item("Base.CannedCorn", "Food") },
    { "water", item("Base.WaterBottleFull", "Item", { tags = { WaterContainer = true } }) },
    { "medicine", item("Base.Bandage") },
    { "weapon", item("Base.Machete", "Weapon") },
    { "ammunition", item("Base.Bullets9mm") },
    { "tools", item("Base.Saw", "Item", { tags = { Saw = true } }) },
    { "construction", item("Base.Nails") },
    { "crafting", item("Base.Thread") },
    { "farming", item("Base.BellPepperBagSeed", "Item", { farming = true }) },
    { "clothing", item("Base.Shirt_Denim", "Clothing") },
    { "literature", item("Base.Book", "Literature") },
}
local bag = item("Base.Bag_Schoolbag")
function bag:getItemContainer() return {} end
supplies[#supplies + 1] = { "container", bag }
local request = { scavengeRequestedCategory = "useful", scavengeRequestedQuantity = 8 }
for _, row in ipairs(supplies) do
    audit.profile.target[row[1]], audit.counts[row[1]] = 1, 99
end
for _, row in ipairs(supplies) do
    local category, value = row[1], row[2]
    check(Logistics.itemCategory(value) == category, "real item classification identifies " .. category)
    local accepted, reason = Logistics.canTake(actor, value, category, audit, "useful")
    local score, scoredCategory = Logistics.itemNeedScore(actor, value, request, audit)
    check(accepted and reason == "expedition_supply"
        and score >= Logistics.TIER.useful and scoredCategory == category,
        "a stocked carrier gathers requested useful " .. category .. " for camp")
    if category ~= "crafting" and category ~= "construction" then
        local ordinary, ordinaryReason = Logistics.canTake(actor, value, category, audit)
        check(not ordinary and ordinaryReason == "loadout_satisfied"
            and Logistics.itemNeedScore(actor, value, {}, audit) == 0,
            "ordinary scavenging still leaves surplus " .. category .. " behind")
    end
end
local food = supplies[1][2]
check(Logistics.canTake(actor, food, "food", audit, "food") == true
    and Logistics.canTake(actor, food, "food", audit, "water") == false,
    "a specific supply request still admits only its requested category beyond personal targets")

for _, value in ipairs({ item("Base.Saw", "Item", { condition = 0 }),
        item("Base.UnknownWidget"), item("Base.Cash", "Item", { valuable = true }) }) do
    local category = Logistics.itemCategory(value)
    audit.counts[category] = 99
    check(Logistics.canTake(actor, value, category, audit, "useful") == false
        and Logistics.itemNeedScore(actor, value, request, audit) == 0,
        "useful does not promote junk or miscellaneous " .. category .. " into requested supplies")
end
for _, value in ipairs({ item("Base.InternalTool", "Item", { hidden = true }),
        item("Base.Cosmetic", "Clothing", { cosmetic = true }),
        item("Base.WristWatch_Left_DigitalRed", "Clothing", { location = "LeftWrist" }) }) do
    check(Logistics.itemNeedScore(actor, value, request, audit) == 0,
        "a broad request still refuses hidden and cosmetic items")
end
check(Logistics.itemNeedScore(actor, item("Base.CannedCorn", "Food", { rotten = true }),
    request, audit) == 0, "requested camp food still rejects rotten food")

-- Mission quantity never becomes permission to exceed physical capacity.
audit.weight = 8.5
request.scavengeRequestedQuantity = 999
for _, row in ipairs(supplies) do
    local accepted, reason = Logistics.canTake(actor, row[2], row[1], audit, "useful")
    check(not accepted and reason == "loadout_too_heavy"
        and Logistics.itemNeedScore(actor, row[2], request, audit) == 0,
        "even a large camp request stops before overloading " .. row[1])
end
SC_TEST_REPORT = "SUPPLY_POLICY_PASS checks=" .. checks
