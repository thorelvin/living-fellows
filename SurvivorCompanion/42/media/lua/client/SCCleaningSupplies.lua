-- SPDX-License-Identifier: MIT
-- Demand-driven cleaning supplies. No events or background service are installed.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.CleaningSupplies = SC.CleaningSupplies or {}
local C = SC.CleaningSupplies
local camps = setmetatable({}, { __mode = "k" })
local inventories = setmetatable({}, { __mode = "k" })
local EPS = 0.0001
C.RATIO, C.BATCH_LITRES = 0.05, 2
C.MARKERS = { tool = "LF_CleanToolJobId", liquid = "LF_CleanLiquidJobId",
    concentrate = "LF_CleanConcentrateJobId", water = "LF_CleanWaterJobId" }

local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if not object then return nil end
    return select(1, U().call(object, method, ...))
end
local function finite(value)
    value = tonumber(value)
    return value and value == value and value >= 0 and value < math.huge and value or nil
end
local function fluid(name) return Fluid and Fluid[name] end
function C.dose()
    return finite(ZomboidGlobals and ZomboidGlobals.CleanBloodBleachAmount) or 0.24999
end
function C.containsCleaner(item)
    local fc = call(item, "getFluidContainer")
    return fc ~= nil and ((fluid("Bleach") and call(fc, "contains", fluid("Bleach")) == true)
        or (fluid("CleaningLiquid") and call(fc, "contains", fluid("CleaningLiquid")) == true)) or false
end
function C.inspect(item)
    local fc = call(item, "getFluidContainer")
    if not fc then return nil end
    local amount = finite(call(fc, "getAmount"))
    if not amount then return nil end
    local result = { item = item, fluid = fc, amount = amount,
        capacity = finite(call(fc, "getCapacity")), cleanerAmount = 0, waterAmount = 0 }
    local sum, cleanerKinds, complete = 0, 0, true
    for _, name in ipairs({ "Water", "TaintedWater", "Bleach", "CleaningLiquid" }) do
        local kind = fluid(name)
        local contains = kind and call(fc, "contains", kind) == true
        local value = kind and finite(call(fc, "getSpecificFluidAmount", kind))
        if value == nil then
            if contains then complete = false end
            value = 0
        end
        sum = sum + value
        result[name] = value
        if name == "Bleach" or name == "CleaningLiquid" then
            if contains then
                cleanerKinds = cleanerKinds + 1
                result.cleanerName = name
            end
            result.cleanerAmount = result.cleanerAmount + value
        else result.waterAmount = result.waterAmount + value end
    end
    result.cleaner = cleanerKinds > 0
    result.known = complete and cleanerKinds <= 1 and math.abs(sum - amount) <= EPS
    result.empty = amount < EPS
    result.waterOnly = result.known and not result.cleaner and result.waterAmount > EPS
    result.mixture = result.known and cleanerKinds == 1 and result.waterAmount > EPS
    result.pureCleaner = result.known and cleanerKinds == 1 and result.waterAmount < EPS
    result.usable = result.known and cleanerKinds == 1 and amount >= C.dose()
    result.ratio = amount > 0 and result.cleanerAmount / amount or 0
    return result
end
function C.tool(item)
    return ItemTag and ItemTag.CLEAN_STAINS and call(item, "hasTag", ItemTag.CLEAN_STAINS) == true
        and call(item, "isBroken") ~= true or false
end
function C.bucket(item)
    local kind = string.lower(tostring(U().itemType(item)))
    return string.find(kind, "bucket", 1, true) ~= nil
        or U().itemHasTag and U().itemHasTag(item, "Bucket") == true
end
function C.canReceive(item, name)
    local fc, kind = call(item, "getFluidContainer"), fluid(name)
    return fc and kind and call(fc, "isInputLocked") ~= true
        and call(fc, "canAddFluid", kind) == true or false
end
function C.waterRejected(job, object)
    local point = U().squareOf(object)
    for _, rejected in ipairs(job and job.target and job.target.cleanRejectedWater or {}) do
        if point and point:getX() == rejected.x and point:getY() == rejected.y
            and point:getZ() == rejected.z and call(object, "getObjectIndex") == rejected.index
            and call(object, "getSpriteName") == rejected.sprite then return true end
    end
    return false
end
local function available(row, actor, job)
    local item, base = row.item, SC.BaseLife
    if not item or not U().inventoryContains(row.container, item) then return false end
    if row.personal then
        local current, owned = row.container, false
        for _ = 1, 5 do
            if current == U().inventory(actor) then owned = true break end
            current = call(call(current, "getContainingItem"), "getContainer")
            if not current then break end
        end
        if not owned then return false end
    end
    if row.storageId then
        local storage = base.storage(row.storageId)
        if not storage or base.withdrawable(storage) ~= true
            or base.resolveContainer(storage) ~= row.container then return false end
        local kind = U().itemType(item)
        if base.storageReserve(storage, kind) > 0 and base.availableCountExact(storage, kind) <= 0 then return false end
    end
    local data = U().modData(item) or {}
    for kind, marker in pairs(C.MARKERS) do
        if job and data[marker] == job.id and job.target.cleanLoans
            and job.target.cleanLoans[kind] then return true end
    end
    if SC.BaseWork and SC.BaseWork.choreReserved and SC.BaseWork.choreReserved(item) then return false end
    if SC.WorkTransport and SC.WorkTransport.foreignProtected
        and SC.WorkTransport.foreignProtected(item, actor) == true then return false end
    if SC.PersonalItems and SC.PersonalItems.isProtected
        and SC.PersonalItems.isProtected(item, actor, "base_clean") then return false end
    return true
end
C.available = available
local function list(container)
    return call(container, "getItems") or type(container) == "table" and container.items or {}
end
local function scanNew(roots)
    return { roots = roots, root = 1, index = 0, rows = {}, seen = {}, complete = false }
end
local function surveyContainer(quota, row)
    local key = row.storageId or row.container
    if quota.seen[key] then return true end
    if quota.containers <= 0 then return false end
    quota.seen[key], quota.containers = true, quota.containers - 1
    return true
end
local function advance(scan, quota, budget)
    while not scan.complete and quota.items > 0 and quota.containers > 0 and budget() do
        local root = scan.roots[scan.root]
        if not root then scan.complete = true break end
        if not surveyContainer(quota, root) then break end
        if root.storageId then
            local storage = SC.BaseLife.storage(root.storageId)
            local container = storage and SC.BaseLife.withdrawable(storage)
                and SC.BaseLife.resolveContainer(storage) or nil
            if root.container ~= container then root.container, scan.index = container, 0 end
        end
        local items = list(root.container)
        local size = U().listSize(items)
        while scan.index < size and quota.items > 0 and budget() do
            local item = U().listGet(items, scan.index)
            scan.index, quota.items = scan.index + 1, quota.items - 1
            if item and not scan.seen[item] then
                scan.seen[item] = true
                if C.tool(item) or call(item, "getFluidContainer") then
                    scan.rows[#scan.rows + 1] = { item = item, container = root.container,
                        storageId = root.storageId, personal = root.personal }
                end
                -- Personal bags stay with their owner. Storage remains tied to
                -- the exact registered container used by verified withdrawals.
                local nested = root.personal and call(item, "getInventory")
                if nested and (root.depth or 0) < 4 then
                    scan.roots[#scan.roots + 1] = { container = nested, personal = true, depth = (root.depth or 0) + 1 }
                end
            end
        end
        if scan.index >= size then scan.root, scan.index = scan.root + 1, 0 end
        if not scan.roots[scan.root] then scan.complete = true end
    end
end
local function campState(base)
    local state, current = camps[base], U().nowMs()
    if not state or state.scan.complete and current - state.finishedAt > 30000
        and (not state.world or state.worldComplete) then
        local roots = {}
        for _, storage in ipairs(SC.BaseLife.storageRows(nil, true)) do
            roots[#roots + 1] = { storageId = storage.id }
        end
        state = { scan = scanNew(roots), finishedAt = current, zone = 1 }
        camps[base] = state
    end
    local tick = math.floor(current / 100)
    if state.tick ~= tick then state.tick, state.quota = tick, { items = 64, containers = 4, seen = {} } end
    return state
end
function C.sources(actor, budget)
    local base = SC.BaseLife and SC.BaseLife.active()
    if not base then return nil, "base_missing" end
    local camp = campState(base)
    local root, current = U().inventory(actor), U().nowMs()
    if not root then return nil, "cleaning_supplies_missing" end
    local personal = inventories[actor]
    local count = U().listSize(list(root))
    if not personal or personal.inventory ~= root or personal.count ~= count
        or personal.scan.complete and current - personal.finishedAt > 1000
            and (not personal.selection or personal.selection.resolved) then
        personal = { inventory = root, count = count, finishedAt = current,
            scan = scanNew({ { container = root, personal = true } }) }
        inventories[actor] = personal
    end
    local personalDone, campDone = personal.scan.complete, camp.scan.complete
    advance(personal.scan, camp.quota, budget)
    advance(camp.scan, camp.quota, budget)
    if not personalDone and personal.scan.complete then personal.finishedAt = current end
    if not campDone and camp.scan.complete then camp.finishedAt = current end
    if not personal.scan.complete or not camp.scan.complete then return nil, "cleaning_supplies_scanning" end
    personal.finishedAt = personal.finishedAt or current
    if personal.campScan ~= camp.scan or personal.rowsScan ~= personal.scan then
        personal.rows, personal.campScan, personal.rowsScan, personal.selection = {}, camp.scan, personal.scan, nil
        for _, row in ipairs(personal.scan.rows) do personal.rows[#personal.rows + 1] = row end
        for _, row in ipairs(camp.scan.rows) do personal.rows[#personal.rows + 1] = row end
    end
    return personal.rows, nil, camp
end
local function sourceUsable(object)
    if not (object and SC.BaseLife.withinWorkReach(object) == true
        and call(object, "hasWater") == true
        and (finite(call(object, "getFluidAmount")) or 0) >= C.dose()
        and type(call(object, "isTaintedWater")) == "boolean") then return false end
    -- IsoObject.hasWater() handles piped reserves, external plumbing and
    -- natural sources. A nonempty physical fluid component must still contain
    -- only the two supported water fluids, never an unknown water-category mix.
    local info = C.inspect(object)
    return not info or info.empty or info.waterOnly
end
C.sourceUsable = sourceUsable
local function worldSources(camp, budget)
    if camp.worldComplete then return camp.world or {} end
    if camp.worldTick == camp.tick then return nil end
    camp.worldTick = camp.tick
    local base, checked = SC.BaseLife.active(), 0
    camp.world = camp.world or {}
    while checked < 32 and budget() do
        local zone = base.zones[camp.zone]
        if not zone then camp.worldComplete = true break end
        if zone.kind ~= "area" then camp.zone, camp.x, camp.y = camp.zone + 1, nil, nil
        else
            camp.x, camp.y = camp.x or zone.x1, camp.y or zone.y1
            local square = U().gridSquare(camp.x, camp.y, zone.z)
            camp.x, checked = camp.x + 1, checked + 1
            if camp.x > zone.x2 then camp.x, camp.y = zone.x1, camp.y + 1 end
            if camp.y > zone.y2 then camp.zone, camp.x, camp.y = camp.zone + 1, nil, nil end
            if square then U().squareObjects(square, function(object)
                if sourceUsable(object) then camp.world[#camp.world + 1] = { object = object,
                    tainted = call(object, "isTaintedWater") == true,
                    x = square:getX(), y = square:getY(), z = square:getZ() } end
                return true
            end, 24) end
        end
    end
    if not camp.worldComplete then return nil end
    return camp.world
end
local function score(row, actor)
    if row.personal then return 0 end
    local storage = SC.BaseLife.storage(row.storageId)
    return storage and (U().distance(actor, storage) or 10000) + 1 or 10000
end
local function extraWeight(row)
    return row and not row.personal and (finite(call(row.item, "getUnequippedWeight"))
        or tonumber(U().itemWeight(row.item)) or 0) or 0
end
local function canCarry(actor, row)
    local weight, capacity = U().carryLoad(actor)
    return not capacity or capacity <= 0 or weight + extraWeight(row) <= capacity
end
local function batch(actor, tool, pure, bucket, water, job)
    if not available(bucket, actor) then return nil end
    local info, concentrated = C.inspect(bucket.item), C.inspect(pure.item)
    if not info or not info.capacity or not (info.empty or info.waterOnly) or not concentrated
        or not C.canReceive(bucket.item, concentrated.cleanerName) then return nil end
    local waterInfo = water and water.item and available(water, actor) and C.inspect(water.item)
    if water and (water.item and (not waterInfo or not waterInfo.waterOnly)
        or water.object and (not sourceUsable(water.object) or C.waterRejected(job, water.object))) then return nil end
    if waterInfo and ((waterInfo.Water > 0 and not C.canReceive(bucket.item, "Water"))
        or (waterInfo.TaintedWater > 0 and not C.canReceive(bucket.item, "TaintedWater"))) then return nil end
    if water and water.object and not C.canReceive(bucket.item, water.tainted and "TaintedWater" or "Water") then return nil end
    local weight, capacity = U().carryLoad(actor)
    local room = capacity and capacity > 0 and math.max(0, capacity * 0.90 - weight
        - extraWeight(tool) - extraWeight(bucket) - extraWeight(pure)
        - (water and water.item and extraWeight(water) or 0)) or 2
    local waterAmount = water and (water.object and finite(call(water.object, "getFluidAmount"))
        or waterInfo.amount) or 0
    local volume = math.min(C.BATCH_LITRES, info.capacity, info.amount + room,
        concentrated.amount / C.RATIO, (info.waterAmount + waterAmount) / (1 - C.RATIO))
    local quantum = math.ceil(C.dose() * 1000) / 1000
    volume = math.floor((volume + EPS) / quantum) * quantum
    if volume >= C.dose() and volume * 0.95 + EPS >= info.waterAmount
        and volume + EPS >= info.amount and volume - info.amount <= info.capacity - info.amount + EPS then
        return { mode = "prepare", tool = tool, liquid = bucket,
            concentrate = pure, water = water or nil, volume = volume, cleanerName = concentrated.cleanerName }
    end
end
function C.plan(actor, job, remainingBudget)
    local precise = SC.Performance and SC.Performance.preciseNowMs
    local deadline = precise and precise() + 1
    local function budget()
        return (not deadline or precise() < deadline)
            and (not remainingBudget or (tonumber(remainingBudget()) or 0) > 0)
    end
    local rows, reason, camp = C.sources(actor, budget)
    if not rows then return nil, reason end
    local selection = inventories[actor].selection
    if not selection then
        selection = { index = 1, buckets = {}, waters = {} }
        inventories[actor].selection = selection
    end
    if selection.complete then
        if selection.tool and not C.tool(selection.tool.item) then
            inventories[actor].selection = nil
            return nil, "cleaning_supplies_scanning"
        end
        for _, row in ipairs({ selection.tool or false, selection.mixed or false, selection.pure or false }) do
            if row and not available(row, actor, job) then
                inventories[actor].selection = nil
                return nil, "cleaning_supplies_scanning"
            end
        end
        local mixedInfo = selection.mixed and C.inspect(selection.mixed.item)
        local pureInfo = selection.pure and C.inspect(selection.pure.item)
        if selection.mixed and (not mixedInfo or not mixedInfo.usable)
            or selection.pure and (not pureInfo or not pureInfo.pureCleaner
                or pureInfo.amount < C.dose() * C.RATIO) then
            inventories[actor].selection = nil
            return nil, "cleaning_supplies_scanning"
        end
    end
    local tool, mixed, pure, buckets, waters = selection.tool, selection.mixed, selection.pure, selection.buckets, selection.waters
    while not selection.complete and selection.index <= #rows and camp.quota.items > 0 and budget() do
        local row = rows[selection.index]
        if not surveyContainer(camp.quota, row) then break end
        selection.index, camp.quota.items = selection.index + 1, camp.quota.items - 1
        if available(row, actor, job) and canCarry(actor, row) then
            local info = C.inspect(row.item)
            if C.tool(row.item) and (not tool or extraWeight(row) < extraWeight(tool)
                or extraWeight(row) == extraWeight(tool) and score(row, actor) < score(tool, actor)) then tool = row end
            if info then
                if info.usable and info.mixture and (not mixed or extraWeight(row) < extraWeight(mixed)
                    or extraWeight(row) == extraWeight(mixed) and score(row, actor) < score(mixed, actor)) then mixed = row end
                if info.pureCleaner and info.amount >= C.dose() * C.RATIO
                    and (not pure or score(row, actor) < score(pure, actor)) then pure = row end
                if C.bucket(row.item) and info.capacity and (info.empty or info.waterOnly) then buckets[#buckets + 1] = row end
                if info.waterOnly then waters[#waters + 1] = { item = row.item, container = row.container,
                    storageId = row.storageId, personal = row.personal,
                    tainted = info.TaintedWater > 0, rank = score(row, actor) } end
            end
        end
    end
    selection.tool, selection.mixed, selection.pure = tool, mixed, pure
    selection.complete = selection.index > #rows
    if not selection.complete then return nil, "cleaning_supplies_scanning" end
    if not tool then selection.resolved = true return nil, "cleaning_tool_missing" end
    local weight, capacity = U().carryLoad(actor)
    local mixedTooHeavy = mixed and capacity and capacity > 0
        and weight + extraWeight(tool) + extraWeight(mixed) > capacity * 0.90
    if mixed and not mixedTooHeavy then selection.resolved = true return { mode = "mixed", tool = tool, liquid = mixed } end
    if not pure then selection.resolved = true return nil,
        mixedTooHeavy and "cleaning_carry_capacity_low" or "cleaning_cleaner_missing" end
    if #buckets > 0 then
        local world = worldSources(camp, budget)
        if not world then return nil, "cleaning_supplies_scanning" end
        if not selection.choices then
            selection.choices, selection.bucketIndex, selection.waterIndex = {}, 1, 1
            for _, water in ipairs(waters) do selection.choices[#selection.choices + 1] = water end
            local ax, ay, az = U().position(actor)
            for _, water in ipairs(world) do
                selection.choices[#selection.choices + 1] = { object = water.object, tainted = water.tainted,
                    rank = ax and math.sqrt((ax-water.x)^2 + (ay-water.y)^2) + math.abs((az or 0)-water.z)*20 + 1 or 10000 }
            end
            -- Sort retained metadata, not thousands of native fluid queries.
            table.sort(selection.choices, function(a, b)
                if a.tainted ~= b.tainted then return a.tainted == true end
                -- A fixed source cannot be auto-drunk from the worker's
                -- inventory while its measured preparation pour is running.
                if (a.object ~= nil) ~= (b.object ~= nil) then return a.object ~= nil end
                return (a.rank or 10000) < (b.rank or 10000)
            end)
            table.insert(selection.choices, 1, false) -- Try the bucket's own existing water first.
        end
        while selection.bucketIndex <= #buckets do
            local bucket = buckets[selection.bucketIndex]
            while selection.waterIndex <= #selection.choices do
                if camp.quota.items <= 0 or not budget() then return nil, "cleaning_supplies_scanning" end
                local water = selection.choices[selection.waterIndex]
                for _, row in ipairs({ tool, pure, bucket, water and water.item and water or false }) do
                    if row and not surveyContainer(camp.quota, row) then return nil, "cleaning_supplies_scanning" end
                end
                camp.quota.items = camp.quota.items - 1
                if not water or water.item ~= bucket.item then
                    local candidate = batch(actor, tool, pure, bucket, water, job)
                    if candidate then selection.resolved = true return candidate end
                end
                selection.waterIndex = selection.waterIndex + 1
            end
            selection.bucketIndex, selection.waterIndex = selection.bucketIndex + 1, 1
        end
    end
    selection.resolved = true
    local info = C.inspect(pure.item)
    if info.usable then
        if capacity and capacity > 0 and weight + extraWeight(tool) + extraWeight(pure) > capacity * 0.90 then
            return nil, "cleaning_carry_capacity_low"
        end
        return { mode = "undiluted", tool = tool, liquid = pure }
    end
    return nil, "cleaning_water_or_bucket_missing"
end
function C.carried(actor, remainingBudget)
    local job = SC.BaseLife and SC.BaseLife.jobFor and SC.BaseLife.jobFor(U().idOf(actor))
    if job and job.type == "clean" and job.target.cleanLoans and SC.BaseWork then
        local tool = SC.BaseWork.cleaningPreparationItem(actor, job, "tool")
        local liquid = SC.BaseWork.cleaningPreparationItem(actor, job, "liquid")
        local info = C.inspect(liquid)
        if tool and C.tool(tool) and info and info.usable then return tool, liquid end
        return nil
    end
    local plan = C.plan(actor, nil, remainingBudget)
    if plan and plan.mode ~= "prepare" and plan.tool.personal and plan.liquid.personal then
        return plan.tool.item, plan.liquid.item
    end
    return nil
end
function C.reset(actor)
    if actor then inventories[actor] = nil
    else camps, inventories = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }) end
end
return C
