-- SPDX-License-Identifier: MIT
-- Drive ordinary Logistics.update across a native-pose completion boundary.
-- The player may change a shelf while the companion is already walking/looting.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local base, checks, serial = SC.BaseLife, 0, 0
local function check(value, reason)
    checks = checks + 1
    assert(value, 'logistics storage commit ' .. checks .. ': ' .. reason)
end
local safe = { snapshot={threatCount=0, immediateCount=0, pressure=0} }
local function count(container, item)
    local found = 0
    for _, candidate in ipairs(SC.GameplayUtil.inventoryItems(container, 32)) do
        if candidate == item then found = found + 1 end
    end
    return found
end
local function begin(label)
    serial = serial + 1
    SC.Logistics.reset(); SC.BaseWork.reset(); base.reset()
    check(base.create(f.makeSquare(20,20,0), 'Deposit ' .. label), label .. ' camp created')
    local actor = f.actor('storage-commit-' .. serial, 20, 20)
    f.registry[actor.id] = actor
    actor.modData.SC_Order = 'base_duty'
    local item = f.item('Base.TomatoSeed', 'Item', {displayCategory='Gardening', weight=1})
    actor.inventory:AddItem(item)
    local container, object = f.containerObject(f.makeSquare(21,20,0), {})
    function object:getObjectIndex()
        for index, candidate in ipairs(self.square.objects) do if candidate == self then return index - 1 end end
        return -1
    end
    local okay, row = base.registerStorage(object, 'farming')
    check(okay, label .. ' Farming shelf registered')
    local ctx = {actor=actor, item=item, container=container, object=object, row=row,
        label=label, visual='active', containers={actor.inventory, container}}
    -- Only native visual timing is controlled; selection, approach admission,
    -- item ownership, the supervisor and actual inventory transfer are real LF.
    SC.NativeActions = { visualStatus=function() return ctx.visual end,
        clearVisual=function() end, cancelVisualOwned=function() return true end }
    local reason
    for _=1,4 do
        _, reason = SC.Logistics.update(actor, nil, safe)
        check(item:getContainer() == actor.inventory, label .. ' retains item during its active pose')
    end
    check(reason == 'logistics_action_active', label .. ' owns an active ordinary logistics pose')
    return ctx
end
local function unique(ctx, owner)
    local total = 0
    for _, container in ipairs(ctx.containers) do total = total + count(container, ctx.item) end
    check(total == 1 and ctx.item:getContainer() == owner and count(owner, ctx.item) == 1,
        ctx.label .. ' retains one exact item and a consistent owner')
end
local function finish(ctx, accepted)
    ctx.visual = 'completed'
    local moved, why = SC.Logistics.update(ctx.actor, nil, safe)
    if accepted then
        check(moved == true and why == 'surplus_stored', ctx.label .. ' unchanged shelf completes ordinary deposit')
        unique(ctx, ctx.container)
    else
        check(ctx.item:getContainer() == ctx.actor.inventory,
            ctx.label .. ' changed destination cannot receive the pending deposit: ' .. tostring(why))
        unique(ctx, ctx.actor.inventory)
    end
end

local unchanged = begin('unchanged')
finish(unchanged, true)

local unmarked = begin('unmarked')
check(base.removeStorage(unmarked.row.id), 'public unmark accepts ordinary logistics target')
finish(unmarked, false)

local relabeled = begin('relabeled')
check(base.setStorageCategory(relabeled.row.id, 'medical'), 'public category change accepts ordinary logistics target')
finish(relabeled, false)

local replaced = begin('same-id registration replacement')
local replacementRow = {}
for key, value in pairs(replaced.row) do replacementRow[key] = value end
base.active().storages[1] = replacementRow
check(base.storage(replaced.row.id) == replacementRow, 'replacement keeps the same storage id and container')
finish(replaced, false)

local disabled = begin('deposits disabled')
disabled.row.deposits = false
finish(disabled, false)

local remapped = begin('container replaced')
local newContainer = f.inventory()
function newContainer:getParent() return remapped.object end
function newContainer:getType() return remapped.container:getType() end
function remapped.object:getContainer() return newContainer end
remapped.containers[#remapped.containers + 1] = newContainer
check(base.resolveContainer(remapped.row) == newContainer, 'same marked object now resolves to the replacement container')
finish(remapped, false)

local unloaded = begin('object unloaded')
unloaded.object.square.objects = {}
check(base.resolveContainer(unloaded.row) == nil, 'removed native object no longer resolves as a storage container')
finish(unloaded, false)

local full = begin('capacity changed')
full.container.capacity = 0
finish(full, false)

-- Rejecting an obsolete target must leave the ordinary planner able to finish
-- later. The original failed move's normal cooldown is allowed to expire.
local retry = begin('normal retry')
check(base.setStorageCategory(retry.row.id, 'medical'), 'retry target relabeled through camp API')
finish(retry, false)
local nextContainer, nextObject = f.containerObject(f.makeSquare(20,21,0), {})
function nextObject:getObjectIndex()
    for index, candidate in ipairs(self.square.objects) do if candidate == self then return index - 1 end end
    return -1
end
retry.containers[#retry.containers + 1] = nextContainer
check(base.registerStorage(nextObject, 'farming'), 'replacement eligible Farming shelf registered')
f.clock = f.clock + 60001
for _=1,8 do
    SC.Logistics.update(retry.actor, nil, safe)
    if retry.item:getContainer() == nextContainer then break end
    f.clock = f.clock + 1000
end
check(retry.item:getContainer() == nextContainer and count(retry.container, retry.item) == 0,
    'normal retry uses the new eligible shelf and never fills the relabeled shelf')
unique(retry, nextContainer)

SC_TEST_REPORT = 'LOGISTICS_STORAGE_COMMIT_PASS checks=' .. checks
print(SC_TEST_REPORT)
