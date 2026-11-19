-- SPDX-License-Identifier: MIT
-- Reviewed native metadata and real storage selectors; loadout roles remain separate.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local cases, checks = assert(SC_STORAGE_CATEGORY_CASES), 0
local function check(value, message)
    checks = checks + 1
    assert(value, 'storage categories ' .. checks .. ': ' .. message)
end
ItemTag = { CLEAN_STAINS = 'CleanStains' }
local function model(row)
    local tags = {}; for _, tag in ipairs(row.tags) do tags[tag] = true end
    local item = f.item(row.type, row.category, { displayCategory = row.display, tags = tags,
        nestedInventory = row.category == 'Container' and f.inventory() or nil })
    function item:getTags()
        return { iterator = function()
            local index = 0
            return { hasNext = function() return index < #row.tags end,
                next = function()
                    index = index + 1
                    local name = row.tags[index]
                    return { getTranslationName = function() return name end }
                end }
        end }
    end
    -- Food freshness itself has dedicated lifetime tests. These cases retain
    -- that existing preferred shelf while testing category precedence.
    function item:getOffAgeMax() return row.expected == 'fresh_food' and 7 or 1000000000 end
    return item
end
SC.BaseLife.reset(); SC.BaseWork.reset()
local centre = f.makeSquare(20, 20, 0)
check(SC.BaseLife.create(centre, 'Storage category contracts'), 'camp created')
local actor = f.actor('sc-storage-categories', 20, 20)
local storages, containers = {}, {}
local categories = { 'food', 'fresh_food', 'water', 'medical', 'tools', 'construction',
    'crafting', 'literature', 'weapons', 'ammunition', 'clothing', 'valuables', 'farming', 'general', 'output' }
for index, category in ipairs(categories) do
    local sq = f.makeSquare(22 + (index - 1) % 4, 20 + math.floor((index - 1) / 4), 0)
    local container, object = f.containerObject(sq, {})
    container.capacity = 100000
    function object:getObjectIndex()
        for n, candidate in ipairs(self.square.objects) do if candidate == self then return n - 1 end end
        return -1
    end
    local okay, row = SC.BaseLife.registerStorage(object, category)
    check(okay, 'registered ' .. category)
    storages[category], containers[category] = row, container
end
for _, row in ipairs(cases) do
    local item = model(row)
    local wanted, certain = SC.BaseWork.classifyItem(item)
    check(wanted == row.expected and certain == true,
        row.type .. ' expected ' .. row.expected .. ', got ' .. tostring(wanted))
    local routes, category = SC.BaseWork.floorDestinations(actor, item)
    check(category == wanted and #routes == 1 and routes[1].destination == storages[wanted],
        row.type .. ' floor intake chooses the reviewed shelf')
    local destination = SC.BaseWork.destinationForCarItem(actor, item)
    check(destination == storages[wanted], row.type .. ' car unload chooses the same shelf')
    check(SC.Logistics.depositCategory(item, SC.Logistics.itemCategory(item)) == wanted,
        row.type .. ' logistics storage agrees without changing its loadout role')
    check(item:getContainer() == nil, 'selectors do not move ' .. row.type)
end
-- Strong native metadata wins even when a modded item has a misleading name.
for _, row in ipairs({
    { type='Mod.UndergroundRoundTable', category='Item', display='Furniture', tags={}, expected='crafting' },
    { type='Mod.WirelessAmmoHeadphones', category='Item', display='Electronics', tags={}, expected='crafting' },
    { type='Mod.WaterBottleGasTank', category='Item', display='VehicleMaintenance', tags={}, expected='tools' },
    { type='Mod.ShellBulletVest', category='Clothing', display='ProtectiveGear', tags={}, expected='clothing' },
    { type='Mod.SeedsMagazine', category='Literature', display='RecipeResource', tags={}, expected='literature' },
}) do
    check(SC.BaseWork.classifyItem(model(row)) == row.expected, row.type .. ' ignores misleading fragments')
end
-- Properly shelved items stay put, including the existing dual-use hand-tool
-- exception. A genuinely wrong shelf offers exactly the correct destination.
for _, row in ipairs(cases) do
    if row.physical then
        local item = model(row)
        containers[row.expected]:AddItem(item)
    end
end
local stableJob, result, reason = { type='sort', target={} }
for _ = 1, 60 do
    local source, _, _, _, _, why = SC.BaseWork.sortTransfer(stableJob, actor)
    result, reason = source, why
    check(source == nil, 'an already correct shelf does not generate sorting churn')
    if why ~= 'haul_scan_pending' then break end
    f.clock = f.clock + 100
end
check(result == nil and reason == 'no_sortable_supply', 'correct storage reaches a stable completed scan: ' .. tostring(reason))

for _, row in ipairs(cases) do
    if row.physical then
        local item = model(row)
        containers.general:AddItem(item)
        local job, source, destination, selected = { type='sort', target={} }
        for _ = 1, 80 do
            local a, _, b, _, c = SC.BaseWork.sortTransfer(job, actor)
            source, destination, selected = a, b, c
            if source then break end
            f.clock = f.clock + 100
        end
        check(source == storages.general and destination == storages[row.expected] and selected == item,
            'ordinary sorting chooses the exact intake item and correct shelf for ' .. row.type)
        containers.general:Remove(item)
    end
end

local capacityItem = model(cases[1]) -- Tire iron -> Tools
local limit = containers.tools.capacity
containers.tools.capacity = 0
local destinations, category, why = SC.BaseWork.floorDestinations(actor, capacityItem)
check(#destinations == 0 and category == 'tools' and why == 'floor_storage_full',
    'full dedicated floor storage does not select an unrelated shelf')
check(SC.BaseWork.destinationForCarItem(actor, capacityItem) == storages.general,
    'car unloading retains its explicit unsorted-intake fallback')
containers.tools.capacity = limit
storages.tools.deposits = false
destinations, category, why = SC.BaseWork.floorDestinations(actor, capacityItem)
check(#destinations == 0 and category == 'tools' and why == 'floor_storage_missing',
    'a deposit-disabled shelf is not a matching destination')
storages.tools.deposits = true

local bagRow
for _, row in ipairs(cases) do if row.type == 'Base.Garbagebag' then bagRow = row break end end
local bag = model(assert(bagRow))
check(SC.Logistics.isTrash(bag) == false, 'a native reusable garbage bag is not a trash item')
local hammer = f.item('Base.Hammer', 'Weapon', { displayCategory='ToolWeapon', tags={Hammer=true} })
check(SC.Logistics.itemCategory(hammer) == 'weapon' and SC.BaseWork.classifyItem(hammer) == 'tools',
    'a hammer remains a combat/loadout weapon while preferring Tools storage')
containers.weapons:AddItem(hammer)
local toolSource, _, borrowedTool = SC.BaseWork._findSourceForTests(actor,
    { tool=true, types={ 'Base.Hammer' }, count=1 })
check(toolSource == storages.weapons and borrowedTool == hammer,
    'a builder can find an eligible tool in its valid Weapons shelf')
local unknown = f.item('Mod.MysteryWidget', 'Item', { displayCategory='CustomUnclassified' })
local guessed, certain = SC.BaseWork.classifyItem(unknown)
check(guessed == 'crafting' and certain == false, 'an unknown mod item remains explicitly uncertain')
containers.weapons:AddItem(unknown)
local validJob = { type='sort', target={} }
for _ = 1, 80 do
    local source, _, _, _, _, reason = SC.BaseWork.sortTransfer(validJob, actor)
    check(source == nil, 'valid dual-use storage and uncertain manual placement remain stable')
    if reason ~= 'haul_scan_pending' then break end
    f.clock = f.clock + 100
end
SC_TEST_REPORT = 'STORAGE_CATEGORIES_PASS cases=' .. #cases .. ' checks=' .. checks
print(SC_TEST_REPORT)
