-- SPDX-License-Identifier: MIT
-- Runtime-only source graph. A visit reads contents only after physical arrival;
-- its bounded candidate page is rebuilt after each committed batch.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ScavengeLoot = SC.ScavengeLoot or {}
local Loot = SC.ScavengeLoot
-- Native profiling: six keeps the verified commit within the work budget.
Loot.batchLimit = 6
local function U() return SC.GameplayUtil end

function Loot.contents(container)
    local items, ok = U().call(container, "getItems")
    if ok then return items end
    if U().hasMethod(container, "getItems") then return nil end
    if type(container) == "table" then return container.items or container end
end

function Loot.nested(item)
    local readable = true
    for _, method in ipairs({ "getInventory", "getItemContainer" }) do
        local container, ok = U().call(item, method)
        if container then return container, true end
        if not ok and U().hasMethod(item, method) then readable = false end
    end
    return nil, readable and select(1, U().call(item, "IsInventoryContainer")) ~= true
end

local function size(items)
    if not items then return nil end
    if U().hasMethod(items, "size") then
        local count, ok = U().call(items, "size")
        count = tonumber(count)
        if ok and count and count >= 0 then return math.floor(count) end
        return nil
    end
    if type(items) == "table" then return #items end
end

-- No content read: safe during blind world discovery. All compartments share
-- one physical owner and visit, including an object with only a secondary bin.
function Loot.primary(owner, fallback)
    local container = select(1, U().call(owner, "getContainer"))
    if container then return container end
    local count = tonumber((U().call(owner, "getContainerCount")))
    if count and count > 0 then return select(1, U().call(owner, "getContainerByIndex", 0)) end
    return fallback
end

local function get(items, index)
    if U().listGet then return U().listGet(items, index) end
    local value
    U().each(items, 1, function(item) value = item end, index)
    return value
end

function Loot.valid(visit, row)
    if not visit or not row or not U().inventoryContains(row.source, row.item) then return false end
    local actual, readable = U().call(row.item, "getContainer")
    if readable and actual ~= row.source then return false end
    if U().hasMethod(visit.owner, "getSquare") and not U().squareOf(visit.owner) then return false end
    if select(1, U().call(row.item, "isFavorite")) == true then return false end
    if row.parentBag then
        local parent, known = U().call(row.parentBag, "getContainer")
        if known and parent ~= row.root then return false end
        if not U().inventoryContains(row.root, row.parentBag)
            or Loot.nested(row.parentBag) ~= row.source
            or select(1, U().call(row.parentBag, "isFavorite")) == true then return false end
        if SC.PersonalItems and SC.PersonalItems.isProtected(row.parentBag,
                visit.actor, "return_to_owner") then return false end
    end
    -- A world container must still belong to that same object. Test-only lists
    -- may have no parent API; real sources must never follow a bag into a player.
    if U().hasMethod(visit.owner, "getContainerCount") then
        local index = visit.rootSet[row.root]
        if index == true then
            return select(1, U().call(visit.owner, "getContainerCount")) == 0
                and select(1, U().call(visit.owner, "getContainer")) == row.root
        end
        return type(index) == "number"
            and select(1, U().call(visit.owner, "getContainerByIndex", index)) == row.root
    end
    local primary, ok = U().call(visit.owner, "getContainer")
    return not ok or primary == row.root
end

local function better(a, b)
    if a.band ~= b.band then return a.band > b.band end
    if a.category == "food" and b.category == "food" and a.foodTier ~= b.foodTier then
        return a.foodTier < b.foodTier
    end
    if a.score ~= b.score then return a.score > b.score end
    return a.sequence < b.sequence
end
Loot.better = better

local function retain(visit, row)
    local category = row.category or "personal"
    local page = visit.pages[category]
    if not page then
        if visit.pageCount >= 16 then return end
        page = {}; visit.pages[category] = page; visit.pageCount = visit.pageCount + 1
    end
    page[#page + 1] = row
    table.sort(page, better)
    if #page > 8 then table.remove(page) end
end

function Loot.new(actor, owner, container)
    return { actor = actor, owner = owner, container = container,
        roots = {}, rootSet = {}, queue = {}, seen = {}, cursor = 1,
        compartment = 0, pages = {}, pageCount = 0, sequence = 0 }
end

local function addRoot(visit, container, index)
    if not container or visit.rootSet[container] then return end
    visit.rootSet[container] = index or true
    visit.roots[#visit.roots + 1] = container
    visit.seen[container] = true
    visit.queue[#visit.queue + 1] = { source = container, root = container, index = 0 }
end

function Loot.scan(visit, evaluate, deadline, budget)
    local clock = SC.Performance and SC.Performance.preciseNowMs or U().nowMs
    budget = math.max(1, math.min(40, tonumber(budget) or 40))
    deadline = deadline or clock() + 1.5
    local inspected = 0
    while inspected < budget and (inspected == 0 or clock() < deadline) do
        if not visit.rootsDone then
            local count, supported = U().call(visit.owner, "getContainerCount")
            count = tonumber(count)
            if not supported and U().hasMethod(visit.owner, "getContainerCount") then
                return false, "source_unreadable"
            end
            if supported and (not count or count < 0 or count > 256) then return false, "source_unreadable" end
            if supported and count > 0 and visit.compartment < count then
                local container, ok = U().call(visit.owner, "getContainerByIndex", visit.compartment)
                if not ok or not container then return false, "source_unreadable" end
                addRoot(visit, container, visit.compartment)
                visit.compartment = visit.compartment + 1
                inspected = inspected + 1
            else
                if not supported or count == 0 then addRoot(visit, visit.container) end
                visit.rootsDone = true
            end
        else
            local node = visit.queue[visit.cursor]
            if not node then
                visit.complete = true
                return true
            end
            local items = Loot.contents(node.source)
            if not items then return false, "source_unreadable" end
            local count = size(items)
            if count == nil then return false, "source_unreadable" end
            if node.size ~= nil and node.size ~= count then return false, "source_changed" end
            node.size = count
            if node.parentBag and (not U().inventoryContains(node.root, node.parentBag)
                or Loot.nested(node.parentBag) ~= node.source) then return false, "source_changed" end
            if node.index >= count then visit.cursor, inspected = visit.cursor + 1, inspected + 1
            else
                local item = get(items, node.index)
                if not item then return false, "source_changed" end
                node.index, inspected = node.index + 1, inspected + 1
                visit.sequence = visit.sequence + 1
                if item then
                    local protected = SC.PersonalItems
                        and SC.PersonalItems.isProtected(item, visit.actor, "return_to_owner")
                    protected = protected or select(1, U().call(item, "isFavorite")) == true
                    local nested, readable
                    if not protected then nested, readable = Loot.nested(item) end
                    if readable == false then return false, "source_unreadable" end
                    local nestedSize = nested and size(Loot.contents(nested))
                    if nested and nestedSize == nil then return false, "source_unreadable" end
                    local filled = nestedSize and nestedSize > 0
                    if filled and not node.parentBag and not visit.seen[nested] then
                        if #visit.queue >= 256 then return false, "source_scan_limit" end
                        visit.seen[nested] = true
                        visit.queue[#visit.queue + 1] = { source = nested, root = node.root,
                            parentBag = item, index = 0 }
                    end
                    -- A filled bag's descendants are searched; its shell is
                    -- left behind, so hidden/deeper cargo cannot hitch a ride.
                    if not protected and not filled then
                        local score, category, band = evaluate(item, node)
                        if (tonumber(score) or 0) > 0 then
                            retain(visit, { item = item, source = node.source, root = node.root,
                                parentBag = node.parentBag, score = score, category = category,
                                band = band or 1, sequence = visit.sequence,
                                foodTier = category == "food" and SC.Needs and SC.Needs.foodTier
                                    and (SC.Needs.foodTier(item) or 99) or 2 })
                        end
                    end
                end
            end
        end
    end
    return false, "container_slice_pending"
end

function Loot.rows(visit)
    local result = {}
    for _, page in pairs(visit.pages) do
        for _, row in ipairs(page) do result[#result + 1] = row end
    end
    table.sort(result, better)
    return result
end

return Loot
