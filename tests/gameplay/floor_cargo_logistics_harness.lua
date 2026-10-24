-- SPDX-License-Identifier: MIT
-- The intake worker must deliver its exact claim before generic packing.
local SC = SurvivorCompanion
local checks, current, moves = 0, 1000, 0
local function check(okay, message)
    checks = checks + 1
    if not okay then error("floor cargo/logistics " .. checks .. ": " .. message) end
end
local function call(value, method, ...)
    if value and type(value[method]) == "function" then return value[method](value, ...), true end
    return nil, false
end
local function container()
    local value = { items = {} }
    function value:getItems() return self.items end
    function value:getContainingItem() return self.holder end
    return value
end
local function item(id, fullType, category)
    local value = { id = id, fullType = fullType, category = category, modData = {}, weight = 1 }
    function value:getID() return self.id end
    function value:getFullType() return self.fullType end
    function value:getCategory() return self.category end
    function value:getDisplayCategory() return self.category end
    function value:getModData() return self.modData end
    function value:getContainer() return self.container end
    function value:getInventory() return self.nested end
    function value:getItemContainer() return self.nested end
    function value:getBodyLocation() return self.location end
    function value:getCapacity() return self.nested and 30 or 0 end
    function value:getWeightReduction() return self.nested and 80 or 0 end
    return value
end
local function add(owner, value)
    owner.items[#owner.items + 1], value.container = value, owner
end
local function contains(owner, value)
    for _, candidate in ipairs(owner and owner.items or {}) do if candidate == value then return true end end
    return false
end
local function transfer(source, destination, value)
    for index, candidate in ipairs(source.items) do
        if candidate == value then
            table.remove(source.items, index)
            add(destination, value)
            return true, "transferred"
        end
    end
    return false, "source_missing"
end
local root, bagInventory, store = container(), container(), container()
local bag = item(100, "Base.Bag_ALICEpack", "Container")
bag.nested, bag.location, bagInventory.holder = bagInventory, "Back", bag
local cargo = item(101, "Base.TinCan", "Item")
local stale = item(102, "Base.TinCan", "Item")
local actor = { id = "resident:floor", inventory = root, x = 10, y = 10, z = 0, modData = {} }
function actor:getModData() return self.modData end
function actor:getWornItem(location) return location == "Back" and bag or nil end
function actor:isEquippedClothing(value) return value == bag end
add(root, bag)
add(root, cargo)
local zone = { id = "zone:intake", kind = "sorting_floor", x1 = 9, x2 = 9, y1 = 10, y2 = 10, z = 0 }
local job = { id = "job:115", type = "sort_floor", assignedId = actor.id,
    target = { zoneId = zone.id, floorCargo = { zoneId = zone.id, itemId = cargo.id, x = 9, y = 10, z = 0 } } }
local base = { zones = { zone }, jobs = { job } }
local storage = { id = "storage:tools" }
local object = { x = 10, y = 10, z = 0 }
local utility = {
    call = call, nowMs = function() return current end, config = function() return nil end,
    idOf = function(value) return value.id end,
    inventory = function(value) return value.inventory end,
    inventoryContains = contains, transferItemVerified = transfer,
    each = function(values, limit, visit)
        for index = 1, math.min(#(values or {}), limit) do if visit(values[index]) == false then break end end
    end,
    itemType = function(value) return value.fullType end,
    itemWeight = function(value) return value.weight end,
    itemHasTag = function() return false end,
    instanceOf = function() return false end,
    hasMethod = function(value, method) return type(value[method]) == "function" end,
    clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
    inventoryLoad = function() return 2, 50, .04, root end,
    carryLoad = function() return 2, 12 end,
    containerHasRoom = function() return true end,
    actorState = function(_, runtime) return runtime or {} end,
    directInteractionAccess = function() return true, { object }, "at_interaction_target" end,
    position = function(value) return value.x, value.y, value.z end,
    gridSquare = function() return object end,
    squareOf = function() return object end,
    move = function() moves = moves + 1 return true end,
    stop = function() return true end,
}
SC.GameplayUtil = utility
SC.BaseLife = {
    active = function() return base end,
    job = function(id) return id == job.id and job or nil end,
    resident = function() return { role = "generalist" } end,
    isInside = function() return true end,
    resolveObject = function() return object end,
    resolveContainer = function() return store end,
    storageAcceptsDeposit = function() return true end,
}
SC.NativeActions = { stopDirect = function() return true end,
    visualStatus = function() return "completed" end,
    clearVisual = function() return true end }
SC.Navigation = { cancel = function() return true end }
SC.PersonalItems, SC.Combat, SC.Background, SC.Registry = nil, nil, nil, nil
SC.FarmWork, SC.ExpeditionPrototype, SC.FieldWork = nil, nil, nil
SC.BaseWork.floorDestinations = function()
    return { { destination = storage, container = store } }, "general"
end
cargo.modData.LF_FloorSortJob, stale.modData.LF_FloorSortJob = job.id, job.id
check(SC.WorkTransport.isCargoProtected(cargo, actor, "loadout"), "the exact carried floor claim is protected")
check(SC.WorkTransport.isCargoProtected(stale, actor, "loadout") == false, "same-job stale identity is not protected")
local audit = SC.Logistics.status(actor)
check(audit.packMove == nil and audit.cargoWeight == 1, "real Logistics excludes the exact claim from packing and gear weight")
for _ = 1, 4 do
    current = current + 1000
    local _, reason = SC.Logistics.update(actor, nil, { snapshot = {} })
    check(reason == "load_balanced" and cargo.container == root and moves == 0,
        "normal logistics beats leave the intake cargo rooted without restarting Loot")
end
add(root, stale)
current = current + 1000
audit = SC.Logistics.status(actor)
check(audit.packMove and audit.packMove.item == stale, "an unrelated stale-marked item is still normally packable")
root.items[#root.items] = nil
stale.container = nil
-- Start in a nested bag as a save or another inventory operation can do.
check(transfer(root, bagInventory, cargo), "the exact fixture cargo can begin nested")
current = current + 1000
local handled, reason = SC.FloorSort.update(actor, {}, job)
check(handled and reason == "floor_item_stored" and cargo.container == store,
    "the real intake controller stages then physically deposits its protected exact cargo")
check(not contains(root, cargo) and not contains(bagInventory, cargo) and contains(store, cargo)
    and cargo.modData.LF_FloorSortJob == nil and job.target.floorCargo == nil,
    "verified delivery has one owner and clears both marker and receipt")
print("FLOOR_CARGO_LOGISTICS_PASS checks=" .. checks)
