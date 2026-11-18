-- SPDX-License-Identifier: MIT
-- Native item roles, registered shelves and the real bounded supply planner.
local SC, checks = SurvivorCompanion, 0
local f, C = assert(SC.TestFixture), assert(SC.CleaningSupplies)
local function check(value, message)
    checks = checks + 1
    assert(value, "cleaning storage " .. checks .. ": " .. message)
end
ItemTag = { CLEAN_STAINS = "base:cleanstains" }
Fluid = { Bleach = "Bleach", CleaningLiquid = "CleaningLiquid", Water = "Water", TaintedWater = "TaintedWater" }
local function tool(kind, category, display)
    return f.item(kind, category or "Weapon", { displayCategory = display or "HouseholdWeapon",
        tags = { [ItemTag.CLEAN_STAINS] = true }, weight = 1, condition = 3, conditionMax = 3 })
end
local function cleaner()
    local item = f.item("Base.Bleach", "Normal", { weight = 0.5 })
    local fc = {}
    function fc:getAmount() return 1 end
    function fc:getCapacity() return 1 end
    function fc:contains(kind) return kind == Fluid.Bleach end
    function fc:getSpecificFluidAmount(kind) return self:contains(kind) and 1 or 0 end
    item.fluidContainer = fc
    return item
end
local mop, broom = tool("Base.Mop"), tool("Base.Broom")
for _, item in ipairs({ mop, broom, tool("Mod.Brush", "Normal", "Household"),
    tool("Base.BathTowel", "Normal", "Household") }) do
    local category, certain = SC.BaseWork.classifyItem(item)
    check(category == "tools" and certain, item:getFullType() .. " sorts as a cleaning tool")
    check(SC.Logistics.itemCategory(item) == "tools", item:getFullType() .. " shares the loadout/cargo category")
    check(C.tool(item), "an intact tagged cleaning item remains usable")
end
local unrelated = f.item("Base.ButterKnife", "Weapon", { displayCategory = "HouseholdWeapon" })
check(SC.BaseWork.classifyItem(unrelated) == "weapons" and SC.Logistics.itemCategory(unrelated) == "weapon",
    "HouseholdWeapon alone does not turn every household weapon into a cleaning tool")
local broken = tool("Base.Mop")
broken.broken, broken.condition = true, 0
check(not C.tool(broken) and SC.Logistics.itemCategory(broken) == "trash",
    "a ruined mop cannot clean or satisfy a tool loadout")

local function scene()
    SC.BaseWork.reset(); SC.BaseLife.reset(); C.reset()
    local centre = f.makeSquare(5, 5, 0)
    check(SC.BaseLife.create(centre, "Cleaning storage test"), "camp created")
    local actor = f.actor("sc-cleaning-storage", 5, 5)
    local rows, containers = {}, {}
    for index, category in ipairs({ "weapons", "ammunition", "tools", "general", "memorial" }) do
        local square = f.makeSquare(5 + index, 5, 0)
        local container, object = f.containerObject(square, {})
        container.capacity = 1000
        function object:getObjectIndex()
            for n, candidate in ipairs(self.square.objects) do if candidate == self then return n - 1 end end
            return -1
        end
        local okay, row = SC.BaseLife.registerStorage(object, category)
        check(okay, "registered " .. category)
        rows[category], containers[category] = row, container
    end
    containers.tools:AddItem(cleaner())
    return actor, rows, containers
end
local function plan(actor)
    for _ = 1, 200 do
        f.clock = f.clock + 100
        local result, reason = C.plan(actor)
        if result or reason ~= "cleaning_supplies_scanning" then return result, reason end
    end
    error("cleaning discovery did not finish within its bounded slices")
end
for _, category in ipairs({ "weapons", "ammunition", "tools", "general" }) do
    local actor, rows, containers = scene()
    local item = tool("Base.Mop")
    -- A late item behind several native-sized slices must still be found.
    for _ = 1, 150 do containers[category]:AddItem(f.item("Base.Nails", "Normal")) end
    containers[category]:AddItem(item)
    local selection, reason = plan(actor)
    check(selection and selection.tool.item == item and selection.tool.storageId == rows[category].id,
        "a misfiled/late mop is found in " .. category .. ": " .. tostring(reason))
    check(selection.mode == "undiluted" and item:getContainer() == containers[category],
        "discovery selects supplies without moving them")
    if category == "weapons" or category == "ammunition" or category == "general" then
        local source, destination, selected, why
        local sortJob = { type = "sort", target = {} }
        for _ = 1, 80 do
            local a, _, b, _, c, d = SC.BaseWork.sortTransfer(sortJob, actor)
            source, destination, selected, why = a, b, c, d
            if source then break end
            f.clock = f.clock + 100
        end
        check(source == rows[category] and destination == rows.tools and selected == item,
            "ordinary sorting corrects the exact mop from " .. category .. " into Tools: " .. tostring(why))
    end
    check(#SC.BaseWork.floorDestinations(actor, item) == 1,
        "floor intake has only Tools as the cleaning-tool destination")
end
for _, restriction in ipairs({ "withdrawals", "reserve", "memorial", "broken" }) do
    local actor, rows, containers = scene()
    local item = tool("Base.Mop")
    local category = restriction == "memorial" and "memorial" or "weapons"
    containers[category]:AddItem(item)
    if restriction == "withdrawals" then rows[category].withdrawals = false
    elseif restriction == "reserve" then rows[category].reserve = 1
    elseif restriction == "broken" then item.broken, item.condition = true, 0 end
    local selection, reason = plan(actor)
    check(not selection and reason == "cleaning_tool_missing", restriction .. " is respected by discovery")
    check(item:getContainer() == containers[category], restriction .. " does not move the unavailable mop")
end
local actor, rows, containers = scene()
containers.general:AddItem(f.item("Base.Paperclip", "Normal"))
local destinations = SC.BaseWork.floorDestinations(actor, mop)
check(#destinations == 1 and destinations[1].destination == rows.tools,
    "General source remains intake rather than a competing sorting destination")
SC_TEST_REPORT = "CLEANING_STORAGE_PASS checks=" .. checks
print(SC_TEST_REPORT)
