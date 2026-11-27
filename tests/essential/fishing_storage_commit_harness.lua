-- SPDX-License-Identifier: MIT
-- Camp fishing keeps its chosen food shelf while the angler walks there and
-- plays the loot pose. The player may relabel that shelf in between updates;
-- the catch must then go to a shelf that is still marked for food.
local SC, f = LivingFellows, LivingFellows.TestFixture
local base, checks, serial = SC.BaseLife, 0, 0
local function check(value, reason)
    checks = checks + 1
    assert(value, 'fishing storage commit ' .. checks .. ': ' .. reason)
end

local function shelf(x, y, category, label)
    local container, object = f.containerObject(f.makeSquare(x, y, 0), {})
    function object:getObjectIndex()
        for index, candidate in ipairs(self.square.objects) do
            if candidate == self then return index - 1 end
        end
        return -1
    end
    local okay, row = base.registerStorage(object, category)
    check(okay == true, label .. ' shelf registered as ' .. category)
    return { container = container, object = object, row = row }
end

local function begin(label)
    serial = serial + 1
    SC.Fishing.reset(); SC.BaseWork.reset(); base.reset()
    check(base.create(f.makeSquare(20, 20, 0), 'Fishing ' .. label), label .. ' camp created')
    local actor = f.actor('fishing-commit-' .. serial, 20, 20)
    f.registry[actor.id] = actor
    actor.modData.SC_Order = 'base_duty'
    local fish = f.item('Base.Fish', 'Food', { displayCategory = 'Food', weight = 0.5 })
    function fish:getOffAgeMax() return 5 end
    fish:getModData().SC_CampFishingCatch = true
    actor.inventory:AddItem(fish)
    -- Both shelves are one step away; the first registered is chosen first.
    local first = shelf(21, 20, 'fresh_food', label .. ' first')
    local second = shelf(20, 21, 'fresh_food', label .. ' second')
    local ctx = { actor = actor, fish = fish, first = first, second = second,
        label = label, visual = 'active' }
    -- Only native pose timing is controlled. Camp catches, food shelf choice,
    -- approach, marker revalidation and the item transfer are production code.
    SC.NativeActions = { visualStatus = function() return ctx.visual end,
        clearVisual = function() return true end,
        cancelVisualOwned = function() return true end }
    SC.Fishing._setStateForTests(actor, { mode = 'camp', phase = 'finding',
        scanIndex = 0, delivering = true })
    local reason
    for _ = 1, 4 do
        _, reason = SC.Fishing.update(actor, 'camp')
        if reason == 'base_storage_looting' then break end
    end
    check(reason == 'base_storage_looting', label .. ' angler is in the loot pose at the first shelf: '
        .. tostring(reason))
    check(fish:getContainer() == actor.inventory, label .. ' catch is still carried during the pose')
    return ctx
end

local function settle(ctx)
    ctx.visual = 'completed'
    local results = {}
    for _ = 1, 6 do
        local handled, reason = SC.Fishing.update(ctx.actor, 'camp')
        results[#results + 1] = tostring(handled) .. '/' .. tostring(reason)
        if reason == 'fishing_catch_stored' then break end
    end
    return table.concat(results, ' ')
end

local unchanged = begin('unchanged')
local trace = settle(unchanged)
check(unchanged.fish:getContainer() == unchanged.first.container
        and unchanged.first.container:contains(unchanged.fish)
        and not unchanged.actor.inventory:contains(unchanged.fish),
    'an unchanged food shelf receives the catch: ' .. trace)
check(unchanged.fish:getModData().SC_CampFishingCatch == nil,
    'a stored catch is no longer counted as carried')

local relabeled = begin('relabeled')
check(base.setStorageCategory(relabeled.first.row.id, 'medical'),
    'the player relabels the chosen shelf through the camp API')
trace = settle(relabeled)
check(not relabeled.first.container:contains(relabeled.fish),
    'a shelf relabelled away from food never receives the catch: ' .. trace)
check(relabeled.fish:getContainer() == relabeled.second.container
        and relabeled.second.container:contains(relabeled.fish)
        and not relabeled.actor.inventory:contains(relabeled.fish),
    'the angler chooses the remaining food shelf and stores the exact catch there: ' .. trace)

local pantry = begin('relabeled within food')
check(base.setStorageCategory(pantry.first.row.id, 'food'),
    'the chosen fridge is relabelled as shelf-stable food')
trace = settle(pantry)
check(pantry.fish:getContainer() == pantry.second.container,
    'fresh fish follows the current fresh-food marker, not the old one: ' .. trace)

-- The option only narrows deposits. Callers that pass no category keep the
-- registration, permission and container checks they already had.
local plain = begin('no category option')
local carried = f.item('Base.Nails', 'Item', { weight = 0.1 })
plain.actor.inventory:AddItem(carried)
local plainState = {}
SC.NativeActions.visualStatus = function() return 'completed' end
local moved, why
for _ = 1, 4 do
    moved, why = SC.BaseWork.depositToStorage(plain.actor, plainState,
        plain.second.row, plain.second.container, carried)
    if why == 'base_supply_returned' then break end
end
check(moved == true and plain.second.container:contains(carried),
    'a deposit without an expected category still completes: ' .. tostring(why))
local refused = f.item('Base.Nails', 'Item', { weight = 0.1 })
plain.actor.inventory:AddItem(refused)
moved, why = SC.BaseWork.depositToStorage(plain.actor, {}, plain.second.row,
    plain.second.container, refused, { storageCategory = 'tools' })
check(moved == false and why == 'base_storage_changed' and plain.actor.inventory:contains(refused),
    'a deposit whose expected category no longer matches is refused before any move: ' .. tostring(why))

SC_TEST_REPORT = 'FISHING_STORAGE_COMMIT_PASS checks=' .. checks
print(SC_TEST_REPORT)
