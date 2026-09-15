-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end
if not SC.BaseObjectRef and type(require) == "function" then pcall(require, "SCBaseObjectRef") end

SC.BaseLife = SC.BaseLife or {}
local BaseLife = SC.BaseLife

BaseLife.VERSION = 1
BaseLife.WORK_VERSION = 1
BaseLife.ROLES = {
    generalist = true, guard = true, builder = true, quartermaster = true, medic = true,
}
BaseLife.ZONE_TYPES = {
    area = true, work = true, rest = true, social = true, guard = true,
    rally = true, quarantine = true, lumber = true, burial = true, pyre = true,
}
BaseLife.STORAGE_CATEGORIES = {
    food = true, water = true, medical = true, tools = true, construction = true,
    crafting = true, weapons = true, ammunition = true, general = true,
    output = true, memorial = true,
}
BaseLife.JOB_TYPES = {
    haul = true, sort = true, fetch = true, repair = true, replace_bandage = true,
    craft_supply = true, barricade = true, maintain = true, build = true,
    gather_materials = true, production = true,
}
BaseLife.GATHER_MATERIALS = {
    logs = "Base.Log",
    planks = "Base.Plank",
}
BaseLife.GATHER_ZONE_KINDS = { work = true, lumber = true }

-- Persisted production operations. This table is the save schema only:
-- SCProduction registers the runtime behaviour for each id. Keeping the
-- schema here lets restore validate and quarantine rows even when the
-- behaviour module is unavailable. New operations add a row through
-- BaseLife.registerProductionOperation before any save is restored.
BaseLife.PRODUCTION_VERSION = 1
BaseLife.PRODUCTION_COUNTERS = {
    "treesFelled", "logsDropped", "planksMade", "gravesDug", "bodiesBuried", "gravesClosed",
    "bodiesCollected", "bodiesBurned", "pyresLit", "fallenBuried",
}
BaseLife.PRODUCTION_OPERATIONS = {
    fell_trees = {
        zoneKinds = { lumber = true }, unit = "trees", maxRequested = 40,
        defaultRequested = 5, destination = "optional",
        settings = { haulLogs = { kind = "boolean", default = true } },
    },
    saw_planks = {
        unit = "planks", maxRequested = 60, defaultRequested = 12,
        source = true, destination = true, settings = {},
    },
    dig_graves = {
        zoneKinds = { burial = true }, unit = "graves", maxRequested = 6,
        defaultRequested = 1, settings = {},
    },
    bury_bodies = {
        zoneKinds = { burial = true }, unit = "bodies", maxRequested = 25,
        defaultRequested = 5,
        settings = {
            withBelongings = { kind = "boolean", default = false },
            closeWhenDone = { kind = "boolean", default = true },
            digIfNeeded = { kind = "boolean", default = true },
            marker = { kind = "enum", values = { none = true, wood = true }, default = "none" },
        },
    },
    -- Collect bodies from the camp and lumber areas and dispose of them in the
    -- chosen burial ground (bury) or pyre (burn): the zone kind decides.
    collect_bodies = {
        zoneKinds = { burial = true, pyre = true }, unit = "bodies", maxRequested = 25,
        defaultRequested = 5,
        settings = {
            fromCamp = { kind = "boolean", default = true },
            fromLumber = { kind = "boolean", default = true },
            withBelongings = { kind = "boolean", default = false },
            marker = { kind = "enum", values = { none = true, wood = true }, default = "none" },
            requireDry = { kind = "boolean", default = true },
        },
    },
    burn_bodies = {
        zoneKinds = { pyre = true }, unit = "bodies", maxRequested = 25,
        defaultRequested = 5,
        settings = {
            withBelongings = { kind = "boolean", default = false },
            requireDry = { kind = "boolean", default = true },
        },
    },
}

local JOB_STATES = {
    pending = true, reserved = true, active = true, blocked = true,
    completed = true, cancelled = true,
}
local roleAffinity = {
    generalist = { haul = 4, sort = 4, fetch = 4, gather_materials = 5,
        repair = 3, replace_bandage = 2,
        craft_supply = 3, barricade = 2, maintain = 2, build = 2, production = 5 },
    guard = { barricade = 4, maintain = 2, haul = 1, fetch = 1, gather_materials = 1,
        production = 1 },
    builder = { build = 10, barricade = 9, maintain = 8, repair = 5,
        gather_materials = 6, fetch = 3, production = 7 },
    quartermaster = { haul = 10, sort = 10, fetch = 9, gather_materials = 8,
        craft_supply = 4, production = 4 },
    medic = { replace_bandage = 10, fetch = 5, haul = 1, production = 2 },
}

local WORK_ORDER_STATES = {
    running = true, paused = true, blocked = true, completed = true, cancelled = true,
}
local WORK_RECEIPT_PHASES = {
    selected = true, carried = true, depositing = true, recovery = true,
    delivered = true, released = true, cancelled = true, quarantined = true,
}

local document
local draftZone
local operationsCache
local workConsistencyRevision = 0

local DEFENSE_POLICIES = { rotation = true, role_based = true, all_hands = true }
local WORKLOAD_POLICIES = { essential = true, balanced = true, continuous = true }
local defaultStockTargets = {
    food = 3, water = 2, medical = 1, construction = 2, ammunition = 6,
}

local function U()
    return SC.GameplayUtil
end

local function bumpWorkConsistencyRevision()
    workConsistencyRevision = workConsistencyRevision + 1
    if workConsistencyRevision >= 9007199254740000 then workConsistencyRevision = 1 end
    return workConsistencyRevision
end

-- Scheduled persistence snapshots the work ledger before actor inventories.
-- This monotonic main-thread revision binds both halves of that consistency
-- unit without synchronously copying the potentially large receipt snapshots
-- again at commit time.
function BaseLife.noteWorkOwnershipMutation()
    return bumpWorkConsistencyRevision()
end

function BaseLife.workConsistencyRevision()
    return workConsistencyRevision
end

local function R()
    return SC.BaseObjectRef
end

local function now()
    local utility = U()
    return utility and utility.nowMs and utility.nowMs() or math.floor(os.clock() * 1000)
end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function integer(value, fallback, low, high)
    value = math.floor(finite(value, fallback or 0))
    if low ~= nil and value < low then value = low end
    if high ~= nil and value > high then value = high end
    return value
end

local function cleanText(value, fallback, maximum)
    local result = type(value) == "string" and value or tostring(value or "")
    result = string.gsub(result, "[%c]", "")
    if result == "" then result = fallback or "" end
    maximum = maximum or 64
    if #result > maximum then result = string.sub(result, 1, maximum) end
    return result
end

local function stableCopy(value, depth, remaining)
    return SC.StableValue.copyStrict(value, {
        maxDepth = tonumber(depth) or 8,
        maxEntries = type(remaining) == "table" and remaining.count or 4096,
        path = "$.baseLife",
    })
end

local function position(value)
    if type(value) == "table" and finite(value.x, nil) ~= nil and finite(value.y, nil) ~= nil then
        return {
            x = integer(value.x, 0), y = integer(value.y, 0), z = integer(value.z, 0),
        }
    end
    local utility = U()
    if not utility or not value then return nil end
    local x, y, z = utility.position(value)
    if x == nil or y == nil then
        local square = utility.squareOf(value)
        x, y, z = utility.position(square)
    end
    if x == nil or y == nil then return nil end
    return { x = integer(x, 0), y = integer(y, 0), z = integer(z, 0) }
end

local function emptyDocument()
    return {
        version = BaseLife.VERSION,
        activeBaseId = nil,
        nextBaseSerial = 1,
        nextZoneSerial = 1,
        nextStorageSerial = 1,
        nextTargetSerial = 1,
        nextObjectSerial = 1,
        nextJobSerial = 1,
        bases = {},
        residents = {},
        restrictions = {},
        history = {},
    }
end

local function emptyWork()
    return {
        version = BaseLife.WORK_VERSION,
        nextOrderSerial = 1,
        nextReceiptSerial = 1,
        recoveryCursor = 1,
        orders = {},
        receipts = {},
        quarantine = nil,
    }
end

local function emptyProductionCounters()
    local counters = {}
    for _, key in ipairs(BaseLife.PRODUCTION_COUNTERS) do counters[key] = 0 end
    return counters
end

local function emptyProduction()
    return {
        version = BaseLife.PRODUCTION_VERSION,
        nextOrderSerial = 1,
        orders = {},
        counters = emptyProductionCounters(),
        quarantine = nil,
    }
end

local function validId(value, prefix)
    return type(value) == "string" and #value >= 3 and #value <= 96
        and (prefix == nil or string.sub(value, 1, #prefix) == prefix)
end

local function normalizePoint(source)
    local point = position(source)
    if not point then return nil end
    return point
end

local function normalizeZone(source)
    if type(source) ~= "table" or not validId(source.id, "zone:")
        or not BaseLife.ZONE_TYPES[source.kind] then return nil end
    local a = normalizePoint({ x = source.x1, y = source.y1, z = source.z })
    local b = normalizePoint({ x = source.x2, y = source.y2, z = source.z })
    if not a or not b then return nil end
    return {
        id = source.id,
        kind = source.kind,
        name = cleanText(source.name, source.kind, 48),
        x1 = math.min(a.x, b.x), y1 = math.min(a.y, b.y),
        x2 = math.max(a.x, b.x), y2 = math.max(a.y, b.y), z = a.z,
        createdAt = math.max(0, finite(source.createdAt, 0)),
    }
end

local function normalizeStorage(source)
    if type(source) ~= "table" or not validId(source.id, "storage:")
        or not BaseLife.STORAGE_CATEGORIES[source.category] then return nil end
    local reference = R() and R().normalize(source) or nil
    if not reference then return nil end
    local reserves = {}
    local count = 0
    for itemType, amount in pairs(type(source.reserves) == "table" and source.reserves or {}) do
        if type(itemType) == "string" and itemType ~= "" and count < 64 then
            reserves[cleanText(itemType, "", 96)] = integer(amount, 0, 0, 9999)
            count = count + 1
        end
    end
    return {
        id = source.id, x = reference.x, y = reference.y, z = reference.z,
        objectIndex = reference.objectIndex, category = source.category,
        objectId = reference.objectId, objectSignature = reference.objectSignature,
        reserve = integer(source.reserve, 0, 0, 9999), reserves = reserves,
        withdrawals = source.withdrawals ~= false, deposits = source.deposits ~= false,
        createdAt = math.max(0, finite(source.createdAt, 0)),
    }
end

local function normalizeTarget(source)
    if type(source) ~= "table" or not validId(source.id, "target:") then return nil end
    local reference = R() and R().normalize(source) or nil
    if not reference then return nil end
    local kind = source.kind == "barricade" and "barricade" or "maintain"
    return {
        id = source.id, kind = kind, x = reference.x, y = reference.y, z = reference.z,
        objectIndex = reference.objectIndex, threshold = integer(source.threshold, 65, 1, 100),
        objectId = reference.objectId, objectSignature = reference.objectSignature,
        enabled = source.enabled ~= false, createdAt = math.max(0, finite(source.createdAt, 0)),
    }
end

local function normalizeJob(source)
    if type(source) ~= "table" or not validId(source.id, "job:")
        or not BaseLife.JOB_TYPES[source.type] then return nil end
    local state = JOB_STATES[source.state] and source.state or "pending"
    if state == "reserved" or state == "active" then state = "pending" end
    return {
        id = source.id, type = source.type, priority = integer(source.priority, 3, 1, 5),
        state = state, target = stableCopy(source.target, 3, { count = 64 }),
        recipeId = type(source.recipeId) == "string" and cleanText(source.recipeId, "", 128) or nil,
        face = integer(source.face, 1, 1, 4),
        assignedId = type(source.assignedId) == "string" and source.assignedId or nil,
        reservedBy = nil, leaseUntil = 0, blocker = source.blocker ~= nil
            and cleanText(source.blocker, "blocked", 160) or nil,
        attempts = integer(source.attempts, 0, 0, 1000),
        retryAt = math.max(0, finite(source.retryAt, 0)),
        createdAt = math.max(0, finite(source.createdAt, 0)),
        updatedAt = math.max(0, finite(source.updatedAt, 0)),
    }
end

local function normalizeWorkerIds(source)
    local result, seen = {}, {}
    for _, id in ipairs(type(source) == "table" and source or {}) do
        if type(id) == "string" and id ~= "" and #id <= 96 and not seen[id]
            and #result < 2 then
            result[#result + 1], seen[id] = id, true
        end
    end
    return result
end

local function normalizeWorkOrder(source)
    if type(source) ~= "table" or not validId(source.id, "work-order:")
        or source.operation ~= "gather" then return nil end
    local material = BaseLife.GATHER_MATERIALS[source.material] and source.material or nil
    local requested = integer(source.requested, 12, 1, 100)
    local delivered = integer(source.delivered, 0, 0, requested)
    local state = WORK_ORDER_STATES[source.state] and source.state or "paused"
    local workers = normalizeWorkerIds(source.workers)
    if not material or not validId(source.zoneId, "zone:")
        or not validId(source.destinationStorageId, "storage:")
        or (state == "running" and #workers < 1) then return nil end
    if state == "completed" and delivered ~= requested then return nil end
    return {
        version = BaseLife.WORK_VERSION,
        id = source.id,
        operation = "gather",
        material = material,
        itemType = BaseLife.GATHER_MATERIALS[material],
        zoneId = source.zoneId,
        destinationStorageId = source.destinationStorageId,
        requested = requested,
        delivered = delivered,
        workers = workers,
        state = state,
        blocker = source.blocker ~= nil and cleanText(source.blocker, "blocked", 160) or nil,
        createdAt = math.max(0, finite(source.createdAt, 0)),
        updatedAt = math.max(0, finite(source.updatedAt, 0)),
        completedAt = source.completedAt ~= nil
            and math.max(0, finite(source.completedAt, 0)) or nil,
    }
end

local function normalizeWorkReceipt(source)
    if type(source) ~= "table" or not validId(source.id, "work-receipt:")
        or not validId(source.orderId, "work-order:")
        or not WORK_RECEIPT_PHASES[source.phase] then return nil end
    local ownerKinds = { world = true, actor = true, destination = true,
        detached = true, retired = true, released = true, unknown = true }
    local snapshot = stableCopy(source.snapshot, 18, { count = 8192 })
    if snapshot == nil then return nil end
    local sourcePoint = source.source and normalizePoint(source.source) or nil
    local actorId = type(source.actorId) == "string"
        and cleanText(source.actorId, "", 96) or nil
    local itemType = type(source.itemType) == "string"
        and cleanText(source.itemType, "", 128) or nil
    local destinationStorageId = validId(source.destinationStorageId, "storage:")
        and source.destinationStorageId or nil
    if not sourcePoint or not actorId or actorId == "" or not itemType or itemType == ""
        or not destinationStorageId then return nil end
    local owner = ownerKinds[source.owner] and source.owner or "unknown"
    local detachedProof = source.detachedProof == true
    if detachedProof and not ((source.phase == "recovery" or source.phase == "quarantined")
        and owner == "detached") then return nil end
    if source.phase == "selected" and owner ~= "world" then return nil end
    if (source.phase == "carried" or source.phase == "depositing")
        and owner ~= "actor" then return nil end
    if source.phase == "delivered"
        and (owner ~= "destination" or source.accounted ~= true) then return nil end
    if source.phase == "released"
        and (owner ~= "released" or source.accounted ~= true) then return nil end
    if source.phase == "cancelled" and source.accounted ~= true then return nil end
    local markerCleanupPending = source.markerCleanupPending == true
    if markerCleanupPending and (source.phase ~= "delivered"
        or owner ~= "destination" or source.accounted ~= true) then return nil end
    return {
        version = BaseLife.WORK_VERSION,
        id = source.id,
        orderId = source.orderId,
        jobId = validId(source.jobId, "job:") and source.jobId or nil,
        token = cleanText(source.token, source.id, 128),
        itemType = itemType,
        nativeId = (type(source.nativeId) == "number" or type(source.nativeId) == "string")
            and source.nativeId or nil,
        actorId = actorId,
        source = sourcePoint,
        destinationStorageId = destinationStorageId,
        phase = source.phase,
        owner = owner,
        detachedProof = detachedProof,
        accounted = source.accounted == true,
        markerCleanupPending = markerCleanupPending,
        markerCleanupAttempts = integer(source.markerCleanupAttempts, 0, 0, 1000),
        markerCleanupNextRetryAt = 0,
        attempts = integer(source.attempts, 0, 0, 1000),
        -- Wall/monotonic retry deadlines are runtime scheduling state. A
        -- restored receipt is eligible for one bounded reconciliation pulse.
        nextRetryAt = 0,
        blocker = source.blocker ~= nil and cleanText(source.blocker, "recovery", 160) or nil,
        snapshot = snapshot,
        createdAt = math.max(0, finite(source.createdAt, 0)),
        updatedAt = math.max(0, finite(source.updatedAt, 0)),
    }
end

local function normalizeWork(source)
    if source == nil then return emptyWork() end
    if type(source) ~= "table" or tonumber(source.version) ~= BaseLife.WORK_VERSION then
        local result = emptyWork()
        local preserved = type(source) == "table"
            and stableCopy(source, 12, { count = 8192 }) or nil
        if preserved then
            result.quarantine = { reason = "unsupported_work_version", raw = preserved }
        end
        return result
    end
    local result = emptyWork()
    result.nextOrderSerial = integer(source.nextOrderSerial, 1, 1, 999999)
    result.nextReceiptSerial = integer(source.nextReceiptSerial, 1, 1, 999999)
    result.recoveryCursor = integer(source.recoveryCursor, 1, 1, 999999)
    local maximumOrders = U() and U().config("workOrderRecordLimit") or 32
    for _, row in ipairs(type(source.orders) == "table" and source.orders or {}) do
        local order = normalizeWorkOrder(row)
        if order and #result.orders < maximumOrders then
            result.orders[#result.orders + 1] = order
        end
    end
    local maximumReceipts = U() and U().config("workRecoveryMaxEntries") or 32
    for _, row in ipairs(type(source.receipts) == "table" and source.receipts or {}) do
        local receipt = normalizeWorkReceipt(row)
        if receipt and #result.receipts < maximumReceipts then
            result.receipts[#result.receipts + 1] = receipt
        end
    end
    if type(source.quarantine) == "table" then
        result.quarantine = stableCopy(source.quarantine, 12, { count = 8192 })
    end
    return result
end

function BaseLife.registerProductionOperation(id, schema)
    if type(id) ~= "string" or not string.match(id, "^[%w_]+$") or #id > 48 then
        return false, "invalid_production_operation_id"
    end
    if type(schema) ~= "table" or type(schema.unit) ~= "string"
        or tonumber(schema.maxRequested) == nil or tonumber(schema.defaultRequested) == nil then
        return false, "invalid_production_schema"
    end
    if schema.zoneKinds ~= nil then
        if type(schema.zoneKinds) ~= "table" then return false, "invalid_production_zone_kinds" end
        for kind in pairs(schema.zoneKinds) do
            if not BaseLife.ZONE_TYPES[kind] then return false, "invalid_production_zone_kinds" end
        end
    end
    for _, spec in pairs(type(schema.settings) == "table" and schema.settings or {}) do
        if type(spec) ~= "table" or (spec.kind ~= "boolean" and spec.kind ~= "enum")
            or (spec.kind == "enum" and (type(spec.values) ~= "table"
                or spec.values[spec.default] ~= true)) then
            return false, "invalid_production_setting"
        end
    end
    BaseLife.PRODUCTION_OPERATIONS[id] = schema
    return true
end

local function normalizeProductionSettings(schema, source)
    local settings = {}
    source = type(source) == "table" and source or {}
    for key, spec in pairs(type(schema.settings) == "table" and schema.settings or {}) do
        local value = source[key]
        if spec.kind == "boolean" then
            if type(value) == "boolean" then settings[key] = value
            else settings[key] = spec.default == true end
        elseif spec.kind == "enum" then
            settings[key] = (type(value) == "string" and spec.values[value] == true)
                and value or spec.default
        end
    end
    return settings
end

-- Returns nil plus "unknown_operation" for rows whose operation has no schema.
-- Callers preserve those rows verbatim instead of discarding player work.
local function normalizeProductionOrder(source)
    if type(source) ~= "table" or not validId(source.id, "production-order:") then
        return nil, "invalid"
    end
    local schema = type(source.operation) == "string"
        and BaseLife.PRODUCTION_OPERATIONS[source.operation] or nil
    if not schema then return nil, "unknown_operation" end
    local maximum = integer(schema.maxRequested, 1, 1, 999)
    local requested = integer(source.requested, integer(schema.defaultRequested, 1, 1, maximum),
        1, maximum)
    local completed = integer(source.completed, 0, 0, requested)
    local state = WORK_ORDER_STATES[source.state] and source.state or "paused"
    local workers = normalizeWorkerIds(source.workers)
    if state == "running" and #workers < 1 then return nil, "invalid" end
    if state == "completed" and completed ~= requested then return nil, "invalid" end
    local zoneId = validId(source.zoneId, "zone:") and source.zoneId or nil
    if schema.zoneKinds ~= nil and zoneId == nil then return nil, "invalid" end
    local sourceStorageId = validId(source.sourceStorageId, "storage:")
        and source.sourceStorageId or nil
    local destinationStorageId = validId(source.destinationStorageId, "storage:")
        and source.destinationStorageId or nil
    if schema.source == true and sourceStorageId == nil then return nil, "invalid" end
    if schema.destination == true and destinationStorageId == nil then return nil, "invalid" end
    local graves = {}
    for _, point in ipairs(type(source.graves) == "table" and source.graves or {}) do
        local normalized = type(point) == "table" and normalizePoint(point) or nil
        if normalized and #graves < 8 then graves[#graves + 1] = normalized end
    end
    return {
        version = BaseLife.PRODUCTION_VERSION,
        id = source.id,
        operation = source.operation,
        zoneId = zoneId,
        sourceStorageId = sourceStorageId,
        destinationStorageId = destinationStorageId,
        requested = requested,
        completed = completed,
        workers = workers,
        state = state,
        blocker = source.blocker ~= nil and cleanText(source.blocker, "blocked", 160) or nil,
        settings = normalizeProductionSettings(schema, source.settings),
        graves = graves,
        linkedGatherOrderId = validId(source.linkedGatherOrderId, "work-order:")
            and source.linkedGatherOrderId or nil,
        pendingHaul = integer(source.pendingHaul, 0, 0, 999999),
        createdAt = math.max(0, finite(source.createdAt, 0)),
        updatedAt = math.max(0, finite(source.updatedAt, 0)),
        completedAt = source.completedAt ~= nil
            and math.max(0, finite(source.completedAt, 0)) or nil,
    }
end

local function normalizeProduction(source)
    if source == nil then return emptyProduction() end
    if type(source) ~= "table" or tonumber(source.version) ~= BaseLife.PRODUCTION_VERSION then
        local result = emptyProduction()
        local preserved = type(source) == "table"
            and stableCopy(source, 12, { count = 8192 }) or nil
        if preserved then
            result.quarantine = { reason = "unsupported_production_version", raw = preserved }
        end
        return result
    end
    local result = emptyProduction()
    result.nextOrderSerial = integer(source.nextOrderSerial, 1, 1, 999999)
    local limit = U() and U().config("productionOrderRecordLimit") or 16
    local unknown = {}
    local rows = {}
    for _, row in ipairs(type(source.orders) == "table" and source.orders or {}) do
        rows[#rows + 1] = row
    end
    -- A row quarantined by an older build returns to service once its
    -- operation is known again; otherwise it stays preserved verbatim.
    local quarantined = type(source.quarantine) == "table"
        and type(source.quarantine.orders) == "table" and source.quarantine.orders or {}
    for _, row in ipairs(quarantined) do rows[#rows + 1] = row end
    local seen = {}
    for _, row in ipairs(rows) do
        local order, reason = normalizeProductionOrder(row)
        if order and not seen[order.id] and #result.orders < limit then
            result.orders[#result.orders + 1] = order
            seen[order.id] = true
        elseif order == nil and reason == "unknown_operation" and #unknown < limit then
            local raw = stableCopy(row, 8, { count = 1024 })
            if raw then unknown[#unknown + 1] = raw end
        end
    end
    local counters = type(source.counters) == "table" and source.counters or {}
    for _, key in ipairs(BaseLife.PRODUCTION_COUNTERS) do
        result.counters[key] = integer(counters[key], 0, 0, 999999)
    end
    if type(source.quarantine) == "table" then
        local preserved = stableCopy(source.quarantine, 12, { count = 8192 })
        if type(preserved) == "table" then
            preserved.orders = nil
            -- Kahlua does not reliably publish next(); probe with pairs.
            for _ in pairs(preserved) do result.quarantine = preserved break end
        end
    end
    if #unknown > 0 then
        result.quarantine = result.quarantine or {}
        result.quarantine.orders = unknown
    end
    return result
end

local function normalizeBase(source)
    if type(source) ~= "table" or not validId(source.id, "base:") then return nil end
    local core = normalizePoint(source.core)
    if not core then return nil end
    local settings = type(source.settings) == "table" and source.settings or {}
    local stockTargets = {}
    for category, fallback in pairs(defaultStockTargets) do
        stockTargets[category] = integer(type(settings.stockTargets) == "table"
            and settings.stockTargets[category] or fallback, fallback, 0, 99)
    end
    local result = {
        id = source.id, name = cleanText(source.name, "Main Camp", 48), core = core,
        zones = {}, storages = {}, maintenanceTargets = {}, jobs = {}, completed = {},
        work = emptyWork(), production = emptyProduction(),
        settings = {
            defense = DEFENSE_POLICIES[settings.defense] and settings.defense or "rotation",
            workload = WORKLOAD_POLICIES[settings.workload] and settings.workload or "balanced",
            routines = settings.routines ~= false,
            autoMaintenance = settings.autoMaintenance ~= false,
            stockTargets = stockTargets,
        },
        createdAt = math.max(0, finite(source.createdAt, 0)),
    }
    local maximumZones = U() and U().config("baseMaxZones") or 24
    for _, row in ipairs(type(source.zones) == "table" and source.zones or {}) do
        local zone = normalizeZone(row)
        if zone and #result.zones < maximumZones then result.zones[#result.zones + 1] = zone end
    end
    local maximumStorages = U() and U().config("baseMaxStorages") or 32
    for _, row in ipairs(type(source.storages) == "table" and source.storages or {}) do
        local storage = normalizeStorage(row)
        if storage and #result.storages < maximumStorages then
            result.storages[#result.storages + 1] = storage
        end
    end
    local maximumTargets = U() and U().config("baseMaxMaintenanceTargets") or 64
    for _, row in ipairs(type(source.maintenanceTargets) == "table"
        and source.maintenanceTargets or {}) do
        local target = normalizeTarget(row)
        if target and #result.maintenanceTargets < maximumTargets then
            result.maintenanceTargets[#result.maintenanceTargets + 1] = target
        end
    end
    local maximumJobs = U() and U().config("baseMaxJobs") or 64
    for _, row in ipairs(type(source.jobs) == "table" and source.jobs or {}) do
        local job = normalizeJob(row)
        if job and job.state ~= "completed" and job.state ~= "cancelled"
            and #result.jobs < maximumJobs then result.jobs[#result.jobs + 1] = job end
    end
    for _, row in ipairs(type(source.completed) == "table" and source.completed or {}) do
        if type(row) == "table" and #result.completed < 24 then
            result.completed[#result.completed + 1] = stableCopy(row, 2, { count = 32 })
        end
    end
    result.work = normalizeWork(source.work)
    result.production = normalizeProduction(source.production)
    return result
end

local function normalize(source)
    local result = emptyDocument()
    if type(source) ~= "table" or tonumber(source.version) ~= BaseLife.VERSION then return result end
    result.nextBaseSerial = integer(source.nextBaseSerial, 1, 1, 999999)
    result.nextZoneSerial = integer(source.nextZoneSerial, 1, 1, 999999)
    result.nextStorageSerial = integer(source.nextStorageSerial, 1, 1, 999999)
    result.nextTargetSerial = integer(source.nextTargetSerial, 1, 1, 999999)
    result.nextObjectSerial = integer(source.nextObjectSerial, 1, 1, 999999)
    result.nextJobSerial = integer(source.nextJobSerial, 1, 1, 999999)
    for id, candidate in pairs(type(source.bases) == "table" and source.bases or {}) do
        local base = normalizeBase(candidate)
        if base and id == base.id then result.bases[id] = base end
    end
    -- Older version-1 documents predate object identities. Preserve them as
    -- explicitly unavailable legacy bindings, while ensuring any newer identity
    -- already present cannot collide with the next generated serial.
    for _, base in pairs(result.bases) do
        for _, rows in ipairs({ base.storages, base.maintenanceTargets }) do
            for _, row in ipairs(rows) do
                local serial = row.objectId and tonumber(string.match(row.objectId,
                    "^object:(%d+)$")) or nil
                if serial then result.nextObjectSerial = math.max(
                    result.nextObjectSerial, serial + 1) end
            end
        end
    end
    result.activeBaseId = validId(source.activeBaseId, "base:")
        and result.bases[source.activeBaseId] and source.activeBaseId or nil
    for id, candidate in pairs(type(source.residents) == "table" and source.residents or {}) do
        if type(id) == "string" and type(candidate) == "table"
            and result.bases[candidate.baseId] then
            result.residents[id] = {
                baseId = candidate.baseId,
                role = BaseLife.ROLES[candidate.role] and candidate.role or "generalist",
                duty = candidate.duty == true,
            }
        end
    end
    for id, value in pairs(type(source.restrictions) == "table" and source.restrictions or {}) do
        if type(id) == "string" and (value == "watch" or value == "quarantine") then
            result.restrictions[id] = value
        end
    end
    for _, row in ipairs(type(source.history) == "table" and source.history or {}) do
        if type(row) == "table" and #result.history < (U().config("baseHistoryLimit") or 96) then
            result.history[#result.history + 1] = stableCopy(row, 3, { count = 64 })
        end
    end
    return result
end

local function ensure()
    if type(document) ~= "table" then document = emptyDocument() end
    return document
end

local function nextId(field, prefix)
    local state = ensure()
    local serial = integer(state[field], 1, 1, 999999)
    state[field] = serial + 1
    return prefix .. tostring(serial)
end

local function objectReferenceContext(createIdentity)
    return {
        utility = U(),
        createIdentity = createIdentity == true,
        allocateId = createIdentity == true and function()
            return nextId("nextObjectSerial", "object:")
        end or nil,
    }
end

local function activeBase()
    local state = ensure()
    return state.activeBaseId and state.bases[state.activeBaseId] or nil
end

local function zoneContains(zone, point)
    return type(zone) == "table" and type(point) == "table" and zone.z == point.z
        and point.x >= zone.x1 and point.x <= zone.x2
        and point.y >= zone.y1 and point.y <= zone.y2
end

-- Prove rectangle containment against the union of all camp-area rectangles.
-- The sweep checks only Y bands where area membership can change, then merges
-- clipped integer X intervals. Runtime is bounded by baseMaxZones rather than by
-- the physical size of a player-drawn camp.
function BaseLife.zoneInsideAreaUnion(zone, areaZones)
    if type(zone) ~= "table" then return false end
    local x1, x2 = tonumber(zone.x1), tonumber(zone.x2)
    local y1, y2, z = tonumber(zone.y1), tonumber(zone.y2), tonumber(zone.z)
    if not x1 or not x2 or not y1 or not y2 or not z then return false end
    x1, x2 = math.min(x1, x2), math.max(x1, x2)
    y1, y2 = math.min(y1, y2), math.max(y1, y2)
    local source = areaZones
    if type(source) ~= "table" then
        local base = activeBase()
        source = base and base.zones or {}
    end
    local areas, cuts, cutSeen = {}, { y1, y2 + 1 }, {
        [tostring(y1)] = true, [tostring(y2 + 1)] = true,
    }
    for _, area in ipairs(source) do
        if type(area) == "table" and area.kind == "area" and tonumber(area.z) == z
            and tonumber(area.x1) and tonumber(area.x2)
            and tonumber(area.y1) and tonumber(area.y2) then
            local ax1, ax2 = math.min(area.x1, area.x2), math.max(area.x1, area.x2)
            local ay1, ay2 = math.min(area.y1, area.y2), math.max(area.y1, area.y2)
            if ax2 >= x1 and ax1 <= x2 and ay2 >= y1 and ay1 <= y2 then
                local clipped = {
                    x1 = math.max(x1, ax1), x2 = math.min(x2, ax2),
                    y1 = math.max(y1, ay1), y2 = math.min(y2, ay2),
                }
                areas[#areas + 1] = clipped
                for _, cut in ipairs({ clipped.y1, clipped.y2 + 1 }) do
                    local key = tostring(cut)
                    if not cutSeen[key] then
                        cuts[#cuts + 1], cutSeen[key] = cut, true
                    end
                end
            end
        end
    end
    if #areas == 0 then return false end
    table.sort(cuts)
    for index = 1, #cuts - 1 do
        local sampleY = cuts[index]
        if sampleY <= y2 then
            local intervals = {}
            for _, area in ipairs(areas) do
                if sampleY >= area.y1 and sampleY <= area.y2 then
                    intervals[#intervals + 1] = { area.x1, area.x2 }
                end
            end
            table.sort(intervals, function(a, b)
                if a[1] ~= b[1] then return a[1] < b[1] end
                return a[2] < b[2]
            end)
            local covered = x1 - 1
            for _, interval in ipairs(intervals) do
                if interval[1] > covered + 1 then break end
                covered = math.max(covered, interval[2])
                if covered >= x2 then break end
            end
            if covered < x2 then return false end
        end
    end
    return true
end

-- Lumber areas may extend a bounded distance beyond the camp boundary. The
-- reach band is every camp-area rectangle grown by productionLumberReach
-- tiles on the same floor. Lumber zones must lie inside that band, and only
-- lumber work may path across it.
local function lumberReach()
    local value = U() and tonumber(U().config("productionLumberReach")) or nil
    if value == nil or value ~= value then value = 30 end
    return math.max(0, math.min(64, math.floor(value)))
end

local function reachAreas(areaZones)
    local reach, result = lumberReach(), {}
    for _, area in ipairs(areaZones or {}) do
        if type(area) == "table" and area.kind == "area" and tonumber(area.x1)
            and tonumber(area.x2) and tonumber(area.y1) and tonumber(area.y2)
            and tonumber(area.z) then
            result[#result + 1] = {
                kind = "area", z = area.z,
                x1 = math.min(area.x1, area.x2) - reach, x2 = math.max(area.x1, area.x2) + reach,
                y1 = math.min(area.y1, area.y2) - reach, y2 = math.max(area.y1, area.y2) + reach,
            }
        end
    end
    return result
end

function BaseLife.lumberZoneReachable(zone, areaZones)
    if type(areaZones) ~= "table" then
        local base = activeBase()
        areaZones = base and base.zones or {}
    end
    return BaseLife.zoneInsideAreaUnion(zone, reachAreas(areaZones))
end

-- Allocation-free: navigation asks this for every admitted search node.
function BaseLife.withinWorkReach(value)
    local point, base = position(value), activeBase()
    if not point or not base then return false end
    local reach = lumberReach()
    for _, area in ipairs(base.zones) do
        if area.kind == "area" and area.z == point.z
            and point.x >= area.x1 - reach and point.x <= area.x2 + reach
            and point.y >= area.y1 - reach and point.y <= area.y2 + reach then
            return true
        end
    end
    return false
end

-- Navigation admission for camp work: ordinary work stays inside the camp
-- area, while lumber work (intent.workReach) may also use the reach band.
function BaseLife.admitsWork(value, intent)
    if BaseLife.isInside(value) then return true end
    return type(intent) == "table" and intent.workReach == true
        and BaseLife.withinWorkReach(value) == true
end

local function findById(rows, id)
    for index, row in ipairs(rows or {}) do
        if row.id == id then return row, index end
    end
    return nil
end

function BaseLife.create(square, name)
    local point = position(square)
    if not point then return false, "invalid_base_core" end
    local state = ensure()
    local base = activeBase()
    if base then
        base.core = point
        base.name = cleanText(name, base.name, 48)
        return true, base
    end
    local id = nextId("nextBaseSerial", "base:")
    base = normalizeBase({ id = id, name = name or "Main Camp", core = point, createdAt = now() })
    local radius = integer(U() and U().config("baseDefaultAreaRadius") or 6, 6, 2, 32)
    base.zones[1] = normalizeZone({
        id = nextId("nextZoneSerial", "zone:"), kind = "area", name = "Camp area",
        x1 = point.x - radius, y1 = point.y - radius,
        x2 = point.x + radius, y2 = point.y + radius, z = point.z, createdAt = now(),
    })
    state.bases[id], state.activeBaseId = base, id
    return true, base
end

function BaseLife.active()
    return activeBase()
end

function BaseLife.beginZone(kind, square)
    if not BaseLife.ZONE_TYPES[kind] then return false, "invalid_zone_type" end
    if not activeBase() then return false, "base_missing" end
    local point = position(square)
    if not point then return false, "invalid_zone_corner" end
    draftZone = { kind = kind, first = point }
    return true, "zone_started"
end

function BaseLife.cancelZone()
    draftZone = nil
    return true
end

function BaseLife.finishZone(square, name)
    if not draftZone then return false, "zone_not_started" end
    local base = activeBase()
    local second = position(square)
    if not base or not second or second.z ~= draftZone.first.z then
        return false, "invalid_zone_corner"
    end
    local maximum = U() and U().config("baseMaxZones") or 24
    if #base.zones >= maximum then return false, "zone_limit" end
    local zone = normalizeZone({
        id = nextId("nextZoneSerial", "zone:"), kind = draftZone.kind,
        name = name or draftZone.kind, x1 = draftZone.first.x, y1 = draftZone.first.y,
        x2 = second.x, y2 = second.y, z = second.z, createdAt = now(),
    })
    if BaseLife.REACH_ZONE_KINDS[zone.kind] then
        local tiles = (zone.x2 - zone.x1 + 1) * (zone.y2 - zone.y1 + 1)
        local limitKey = zone.kind == "burial" and "productionBurialMaximumTiles"
            or zone.kind == "pyre" and "productionPyreMaximumTiles"
            or "productionLumberMaximumTiles"
        if tiles > (U().config(limitKey) or 256) then
            return false, zone.kind .. "_zone_too_large"
        end
        if not BaseLife.lumberZoneReachable(zone, base.zones) then
            return false, zone.kind .. "_zone_out_of_reach"
        end
        -- A pyre starts real fire: refuse an unsafe site while it is drawn.
        if zone.kind == "pyre" and SC.Production
            and type(SC.Production.validatePyreZone) == "function" then
            local safe, unsafeReason = SC.Production.validatePyreZone(zone)
            if safe ~= true then return false, "pyre_unsafe:" .. tostring(unsafeReason) end
        end
    elseif zone.kind ~= "area" and not BaseLife.zoneInsideAreaUnion(zone, base.zones) then
        return false, "zone_outside_base_area"
    end
    base.zones[#base.zones + 1] = zone
    draftZone = nil
    return true, zone
end

function BaseLife.removeZone(id)
    local base = activeBase()
    local zone, index
    if base then zone, index = findById(base.zones, id) end
    if not index then return false, "unknown_zone" end
    for _, order in ipairs(base.work and base.work.orders or {}) do
        if order.zoneId == id and order.state ~= "completed" and order.state ~= "cancelled" then
            return false, "work_order_uses_zone"
        end
    end
    for _, order in ipairs(base.production and base.production.orders or {}) do
        if order.zoneId == id and order.state ~= "completed" and order.state ~= "cancelled" then
            return false, "production_order_uses_zone"
        end
    end
    if zone.kind == "area" then
        local remaining, areaCount = {}, 0
        for candidateIndex, candidate in ipairs(base.zones) do
            if candidateIndex ~= index then
                remaining[#remaining + 1] = candidate
                if candidate.kind == "area" then areaCount = areaCount + 1 end
            end
        end
        if areaCount < 1 then return false, "last_base_area" end
        for _, candidate in ipairs(remaining) do
            local contained
            if candidate.kind == "lumber" then
                contained = BaseLife.lumberZoneReachable(candidate, remaining)
            else
                contained = candidate.kind == "area"
                    or BaseLife.zoneInsideAreaUnion(candidate, remaining)
            end
            if not contained then return false, "base_area_in_use" end
        end
        local dependants = { base.core }
        for _, storage in ipairs(base.storages or {}) do dependants[#dependants + 1] = storage end
        for _, target in ipairs(base.maintenanceTargets or {}) do dependants[#dependants + 1] = target end
        for _, point in ipairs(dependants) do
            local pointZone = point and {
                x1 = point.x, x2 = point.x, y1 = point.y, y2 = point.y, z = point.z,
            } or nil
            if pointZone and not BaseLife.zoneInsideAreaUnion(pointZone, remaining) then
                return false, "base_area_in_use"
            end
        end
    end
    table.remove(base.zones, index)
    return true
end

function BaseLife.zoneDraft()
    return draftZone and stableCopy(draftZone, 2, { count = 16 }) or nil
end

function BaseLife.isInside(value, kind)
    local point, base = position(value), activeBase()
    if not point or not base then return false end
    local wanted = kind or "area"
    for _, zone in ipairs(base.zones) do
        if zone.kind == wanted and zoneContains(zone, point) then return true, zone end
    end
    return false
end

function BaseLife.zoneCenter(kind)
    local base = activeBase()
    if not base then return nil end
    for _, zone in ipairs(base.zones) do
        if zone.kind == kind then
            return {
                x = math.floor((zone.x1 + zone.x2) / 2),
                y = math.floor((zone.y1 + zone.y2) / 2), z = zone.z,
            }, zone
        end
    end
    return kind == "rally" and stableCopy(base.core, 1, { count = 4 }) or nil
end

function BaseLife.resolveObject(record)
    local references = R()
    if not references then return nil, "base_object_ref_unavailable" end
    return references.resolve(record, objectReferenceContext(false))
end

-- Direct player-issued work uses the same persistent object identity as base
-- storage and maintenance records.  Keeping allocation here gives every caller
-- one persisted serial source instead of inventing another index-based handle.
function BaseLife.describeObject(object, createIdentity)
    local references = R()
    if not references then return nil, "base_object_ref_unavailable" end
    return references.describe(object, objectReferenceContext(createIdentity == true))
end

function BaseLife.registerStorage(object, category)
    if not BaseLife.STORAGE_CATEGORIES[category] then return false, "invalid_storage_category" end
    local base = activeBase()
    local references = R()
    local descriptor, descriptorReason
    if references then
        descriptor, descriptorReason = references.describe(
            object, objectReferenceContext(true))
    else
        descriptorReason = "base_object_ref_unavailable"
    end
    if not base or not descriptor or not BaseLife.isInside(descriptor) then
        return false, not base and "base_missing"
            or descriptorReason or "storage_outside_base"
    end
    local container, ok = U().call(object, "getContainer")
    if not ok or not container then return false, "object_has_no_container" end
    for _, storage in ipairs(base.storages) do
        if storage.objectId == descriptor.objectId
            or (storage.objectId == nil and storage.x == descriptor.x
                and storage.y == descriptor.y and storage.z == descriptor.z
                and storage.objectIndex == descriptor.objectIndex) then
            storage.x, storage.y, storage.z = descriptor.x, descriptor.y, descriptor.z
            storage.objectIndex, storage.objectId = descriptor.objectIndex, descriptor.objectId
            storage.objectSignature = descriptor.objectSignature
            storage.category = category
            return true, storage
        end
    end
    local maximum = U().config("baseMaxStorages") or 32
    if #base.storages >= maximum then return false, "storage_limit" end
    descriptor.id = nextId("nextStorageSerial", "storage:")
    descriptor.category, descriptor.reserve, descriptor.reserves = category, 0, {}
    descriptor.withdrawals, descriptor.deposits, descriptor.createdAt = true, true, now()
    local storage = normalizeStorage(descriptor)
    base.storages[#base.storages + 1] = storage
    return true, storage
end

function BaseLife.removeStorage(id)
    local base = activeBase()
    local _, index
    if base then _, index = findById(base.storages, id) end
    if not index then return false, "unknown_storage" end
    for _, order in ipairs(base.work and base.work.orders or {}) do
        if order.destinationStorageId == id
            and order.state ~= "completed" and order.state ~= "cancelled" then
            return false, "work_order_uses_storage"
        end
    end
    for _, receipt in ipairs(base.work and base.work.receipts or {}) do
        if receipt.destinationStorageId == id
            and (receipt.markerCleanupPending == true
                or (receipt.phase ~= "delivered" and receipt.phase ~= "released"
                    and receipt.phase ~= "cancelled")) then
            return false, "work_receipt_uses_storage"
        end
    end
    for _, order in ipairs(base.production and base.production.orders or {}) do
        if (order.sourceStorageId == id or order.destinationStorageId == id)
            and order.state ~= "completed" and order.state ~= "cancelled" then
            return false, "production_order_uses_storage"
        end
    end
    table.remove(base.storages, index)
    return true
end

function BaseLife.setReserve(id, itemType, amount)
    local base = activeBase()
    local storage = base and findById(base.storages, id) or nil
    if not storage then return false, "unknown_storage" end
    amount = integer(amount, 0, 0, 9999)
    if itemType == nil or itemType == "" or itemType == "*" then
        storage.reserve = amount
    else
        storage.reserves[cleanText(itemType, "", 96)] = amount
    end
    return true, storage
end

function BaseLife.setStorageCategory(id, category)
    if not BaseLife.STORAGE_CATEGORIES[category] then
        return false, "invalid_storage_category"
    end
    local base = activeBase()
    local storage = base and findById(base.storages, id) or nil
    if not storage then return false, "unknown_storage" end
    storage.category = category
    return true, storage
end

function BaseLife.storageRows(category, withdrawals)
    local base, result = activeBase(), {}
    if not base then return result end
    for _, storage in ipairs(base.storages) do
        if (category == nil or storage.category == category)
            and (withdrawals ~= true or storage.withdrawals ~= false) then
            result[#result + 1] = storage
        end
    end
    return result
end

-- A deliberately narrow read model for overlays.  The full summary also audits
-- stock, residents, guards and jobs; calling that from a render-adjacent cache
-- refresh would do unrelated work merely because the player enabled outlines.
function BaseLife.visualRows()
    local base = activeBase()
    local result = { configured = base ~= nil, zoneRows = {}, storageRows = {} }
    if not base then return result end
    for _, zone in ipairs(base.zones or {}) do
        result.zoneRows[#result.zoneRows + 1] = {
            id = zone.id, kind = zone.kind, name = zone.name,
            x1 = zone.x1, y1 = zone.y1, x2 = zone.x2, y2 = zone.y2, z = zone.z,
        }
    end
    for _, storage in ipairs(base.storages or {}) do
        local row = {
            id = storage.id, category = storage.category,
        }
        local references = R()
        if references then references.copy(storage, row) end
        result.storageRows[#result.storageRows + 1] = row
    end
    return result
end

function BaseLife.resolveContainer(storage)
    local object, reason = BaseLife.resolveObject(storage)
    if not object then return nil, nil, reason end
    local container, ok = U().call(object, "getContainer")
    return ok and container or nil, object, ok and nil or "object_has_no_container"
end

function BaseLife.availableCount(storage, itemType)
    local container = BaseLife.resolveContainer(storage)
    if not container then return 0 end
    local count = 0
    for _, item in ipairs(U().inventoryItems(container, U().config("campStorageItemBudget") or 80)) do
        if itemType == nil or U().itemType(item) == itemType then count = count + 1 end
    end
    local reserve = itemType and storage.reserves[itemType] or nil
    reserve = reserve == nil and storage.reserve or reserve
    return math.max(0, count - integer(reserve, 0, 0, 9999))
end

function BaseLife.registerMaintenanceTarget(object, kind)
    local base = activeBase()
    local references = R()
    local descriptor, descriptorReason
    if references then
        descriptor, descriptorReason = references.describe(
            object, objectReferenceContext(true))
    else
        descriptorReason = "base_object_ref_unavailable"
    end
    if not base or not descriptor or not BaseLife.isInside(descriptor) then
        return false, not base and "base_missing"
            or descriptorReason or "target_outside_base"
    end
    kind = kind == "barricade" and "barricade" or "maintain"
    for _, row in ipairs(base.maintenanceTargets) do
        if row.objectId == descriptor.objectId
            or (row.objectId == nil and row.x == descriptor.x and row.y == descriptor.y
                and row.z == descriptor.z and row.objectIndex == descriptor.objectIndex) then
            row.x, row.y, row.z = descriptor.x, descriptor.y, descriptor.z
            row.objectIndex, row.objectId = descriptor.objectIndex, descriptor.objectId
            row.objectSignature = descriptor.objectSignature
            row.kind, row.enabled = kind, true
            return true, row
        end
    end
    if #base.maintenanceTargets >= (U().config("baseMaxMaintenanceTargets") or 64) then
        return false, "maintenance_target_limit"
    end
    descriptor.id = nextId("nextTargetSerial", "target:")
    descriptor.kind, descriptor.threshold, descriptor.enabled = kind, 65, true
    descriptor.createdAt = now()
    local row = normalizeTarget(descriptor)
    base.maintenanceTargets[#base.maintenanceTargets + 1] = row
    return true, row
end

function BaseLife.setMaintenanceTargetEnabled(id, enabled)
    local base = activeBase()
    local target = base and findById(base.maintenanceTargets, id) or nil
    if not target then return false, "unknown_maintenance_target" end
    target.enabled = enabled == true
    return true, target
end

function BaseLife.removeMaintenanceTarget(id)
    local base = activeBase()
    local _, index
    if base then _, index = findById(base.maintenanceTargets, id) end
    if not index then return false, "unknown_maintenance_target" end
    table.remove(base.maintenanceTargets, index)
    return true
end

local function workFor(base)
    if not base then return nil end
    if type(base.work) ~= "table" then base.work = emptyWork() end
    return base.work
end

local function workOrderIn(base, id)
    local work = workFor(base)
    return work and findById(work.orders, id) or nil
end

local function workReceiptIn(base, id)
    local work = workFor(base)
    return work and findById(work.receipts, id) or nil
end

local function orderIsTerminal(order)
    return order and (order.state == "completed" or order.state == "cancelled")
end

local function receiptIsTerminal(receipt)
    return receipt and (receipt.phase == "delivered" or receipt.phase == "released"
        or receipt.phase == "cancelled")
end

local function pruneWorkRows(work)
    local orderLimit = U().config("workOrderRecordLimit") or 32
    while #work.orders >= orderLimit do
        local removed = false
        for index, order in ipairs(work.orders) do
            local hasOpenReceipt = false
            for _, receipt in ipairs(work.receipts) do
                if receipt.orderId == order.id and (not receiptIsTerminal(receipt)
                    or receipt.markerCleanupPending == true) then
                    hasOpenReceipt = true
                    break
                end
            end
            if orderIsTerminal(order) and not hasOpenReceipt then
                for receiptIndex = #work.receipts, 1, -1 do
                    if work.receipts[receiptIndex].orderId == order.id then
                        table.remove(work.receipts, receiptIndex)
                    end
                end
                table.remove(work.orders, index)
                removed = true
                break
            end
        end
        if not removed then break end
    end
    local receiptLimit = U().config("workRecoveryMaxEntries") or 32
    while #work.receipts >= receiptLimit do
        local removed = false
        for index, receipt in ipairs(work.receipts) do
            if receiptIsTerminal(receipt) and receipt.accounted == true
                and receipt.markerCleanupPending ~= true then
                table.remove(work.receipts, index)
                removed = true
                break
            end
        end
        if not removed then break end
    end
end

local function nextWorkId(work, field, prefix)
    local serial = integer(work[field], 1, 1, 999999)
    work[field] = serial + 1
    return prefix .. tostring(serial)
end

local function gatheringZone(base, id)
    local zone = findById(base and base.zones or {}, id)
    if not zone or not BaseLife.GATHER_ZONE_KINDS[zone.kind] then return nil end
    local tiles = (zone.x2 - zone.x1 + 1) * (zone.y2 - zone.y1 + 1)
    if tiles > (U().config("workGatherMaximumTiles") or 256) then return nil end
    local contained = zone.kind == "lumber" and BaseLife.lumberZoneReachable(zone, base.zones)
        or BaseLife.zoneInsideAreaUnion(zone, base.zones)
    if not contained then return nil end
    return zone
end

local function gatheringStorage(base, id)
    local storage = findById(base and base.storages or {}, id)
    if not storage or storage.deposits == false then return nil end
    return storage
end

local function eligibleWorkers(base, source, prefix)
    local workers = normalizeWorkerIds(source)
    if #workers < 1 then return nil, prefix .. "_worker_missing" end
    for _, id in ipairs(workers) do
        local resident = ensure().residents[id]
        if not resident or resident.baseId ~= base.id then
            return nil, prefix .. "_worker_not_resident"
        end
        local restriction = ensure().restrictions[id]
        if restriction == "watch" or restriction == "quarantine" then
            return nil, prefix .. "_worker_restricted"
        end
        local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(id) or nil
        if not record or not record.actor or record.recruited ~= true then
            return nil, prefix .. "_worker_unavailable"
        end
    end
    return workers
end

local function eligibleGatherWorkers(base, source)
    return eligibleWorkers(base, source, "gather")
end

function BaseLife.workOrder(id)
    return workOrderIn(activeBase(), id)
end

function BaseLife.workOrders(includeTerminal)
    local result, work = {}, workFor(activeBase())
    for _, order in ipairs(work and work.orders or {}) do
        if includeTerminal == true or not orderIsTerminal(order) then result[#result + 1] = order end
    end
    return result
end

function BaseLife.workReceipt(id)
    return workReceiptIn(activeBase(), id)
end

function BaseLife.workReceipts(orderId, includeTerminal)
    local result, work = {}, workFor(activeBase())
    for _, receipt in ipairs(work and work.receipts or {}) do
        if (orderId == nil or receipt.orderId == orderId)
            and (includeTerminal == true or not receiptIsTerminal(receipt)) then
            result[#result + 1] = receipt
        end
    end
    return result
end

function BaseLife.allocateWorkReceipt(spec)
    local base, current = activeBase(), now()
    if not base then return false, "base_missing" end
    spec = type(spec) == "table" and spec or {}
    local order = workOrderIn(base, spec.orderId)
    if not order or orderIsTerminal(order) then return false, "work_order_unavailable" end
    local work = workFor(base)
    pruneWorkRows(work)
    if #work.receipts >= (U().config("workRecoveryMaxEntries") or 32) then
        return false, "work_recovery_limit"
    end
    local activeForOrder = 0
    for _, receipt in ipairs(work.receipts) do
        if receipt.orderId == order.id and not receiptIsTerminal(receipt) then
            activeForOrder = activeForOrder + 1
        end
    end
    if order.delivered + activeForOrder >= order.requested then
        return false, "gather_quota_reserved"
    end
    local copied = stableCopy(spec, 20, { count = 12288 }) or {}
    copied.id = nextWorkId(work, "nextReceiptSerial", "work-receipt:")
    copied.token = copied.id
    copied.itemType = order.itemType
    copied.destinationStorageId = order.destinationStorageId
    copied.phase = "selected"
    copied.owner = "world"
    copied.accounted = false
    copied.detachedProof = false
    copied.markerCleanupPending = false
    copied.markerCleanupAttempts = 0
    copied.markerCleanupNextRetryAt = 0
    copied.attempts = 0
    copied.createdAt, copied.updatedAt = current, current
    local receipt = normalizeWorkReceipt(copied)
    if not receipt then return false, "invalid_work_receipt" end
    work.receipts[#work.receipts + 1] = receipt
    order.updatedAt, order.blocker = current, nil
    bumpWorkConsistencyRevision()
    return true, receipt
end

function BaseLife.removeWorkReceipt(id)
    local base = activeBase()
    local receipt, index
    if base then receipt, index = findById(workFor(base).receipts, id) end
    if not receipt then return false, "unknown_work_receipt" end
    if not receiptIsTerminal(receipt) then return false, "work_receipt_not_terminal" end
    if receipt.markerCleanupPending == true then
        return false, "work_receipt_marker_cleanup_pending"
    end
    table.remove(base.work.receipts, index)
    bumpWorkConsistencyRevision()
    return true
end

function BaseLife.blockGatherOrder(id, reason)
    local order = workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    order.state, order.blocker, order.updatedAt = "blocked",
        cleanText(reason, "gather_blocked", 160), now()
    return true, order
end

local function removeGatherJobs(base, orderId, result, actorId)
    local removed = 0
    for index = #base.jobs, 1, -1 do
        local job = base.jobs[index]
        if job.type == "gather_materials" and type(job.target) == "table"
            and job.target.orderId == orderId
            and (actorId == nil or job.assignedId == actorId) then
            if result ~= nil then
                base.completed[#base.completed + 1] = {
                    id = job.id, type = job.type, actorId = job.assignedId,
                    completedAt = now(), result = cleanText(result, "completed", 96),
                }
                while #base.completed > 24 do table.remove(base.completed, 1) end
            end
            table.remove(base.jobs, index)
            removed = removed + 1
        end
    end
    return removed
end

function BaseLife.removeGatherWorkerJobs(orderId, actorId, result)
    local base = activeBase()
    if not base or type(orderId) ~= "string" or type(actorId) ~= "string" then
        return false, "gather_worker_job_context_missing"
    end
    local removed = removeGatherJobs(base, orderId,
        result or "gather_worker_removed", actorId)
    if removed > 0 then bumpWorkConsistencyRevision() end
    return true, removed
end

local function ensureGatherJobs(base, order)
    for _, workerId in ipairs(order.workers) do
        local exists = false
        for _, job in ipairs(base.jobs) do
            if job.type == "gather_materials" and job.assignedId == workerId
                and type(job.target) == "table" and job.target.orderId == order.id then
                exists = true
                break
            end
        end
        if not exists then
            local accepted, reason = BaseLife.enqueueJob({
                type = "gather_materials", priority = 3, assignedId = workerId,
                target = { orderId = order.id },
            })
            if accepted ~= true then return false, reason end
        end
    end
    return true
end

local function interruptGatherWorkers(order, reason)
    for _, workerId in ipairs(order and order.workers or {}) do
        local actor = U().resolveActor(workerId)
        if actor and SC.BaseWork and type(SC.BaseWork.cancel) == "function" then
            pcall(SC.BaseWork.cancel, actor, reason)
        elseif actor and SC.GatherWork and type(SC.GatherWork.cancelActor) == "function" then
            pcall(SC.GatherWork.cancelActor, actor, reason)
        end
    end
end

function BaseLife.createGatherOrder(spec)
    local base, current = activeBase(), now()
    spec = type(spec) == "table" and spec or {}
    if not base then return false, "base_missing" end
    local material = BaseLife.GATHER_MATERIALS[spec.material] and spec.material or nil
    if not material then return false, "unsupported_gather_material" end
    local zone = gatheringZone(base, spec.zoneId)
    if not zone then return false, "invalid_gather_work_zone" end
    local storage = gatheringStorage(base, spec.destinationStorageId)
    if not storage then return false, "invalid_gather_destination" end
    local container = BaseLife.resolveContainer(storage)
    if not container then return false, "destination_storage_unloaded" end
    local workers, workerReason = eligibleGatherWorkers(base, spec.workers)
    if not workers then return false, workerReason end
    local work, activeCount = workFor(base), 0
    for _, order in ipairs(work.orders) do
        if not orderIsTerminal(order) then activeCount = activeCount + 1 end
    end
    if activeCount >= (U().config("workMaximumOrders") or 8) then
        return false, "work_order_limit"
    end
    pruneWorkRows(work)
    if #work.orders >= (U().config("workOrderRecordLimit") or 32) then
        return false, "work_order_history_full"
    end
    local enabledDuty = {}
    for _, workerId in ipairs(workers) do
        local resident = ensure().residents[workerId]
        if resident.duty ~= true then
            if spec.enableDuty ~= true then return false, "gather_worker_off_duty" end
            resident.duty = true
            enabledDuty[#enabledDuty + 1] = workerId
        end
    end
    local order = normalizeWorkOrder({
        id = nextWorkId(work, "nextOrderSerial", "work-order:"),
        operation = "gather", material = material,
        zoneId = zone.id, destinationStorageId = storage.id,
        requested = integer(spec.requested, 12, 1, 100), delivered = 0,
        workers = workers, state = "running", createdAt = current, updatedAt = current,
    })
    work.orders[#work.orders + 1] = order
    local jobsReady, jobsReason = ensureGatherJobs(base, order)
    if not jobsReady then
        removeGatherJobs(base, order.id)
        table.remove(work.orders, #work.orders)
        for _, workerId in ipairs(enabledDuty) do ensure().residents[workerId].duty = false end
        return false, jobsReason
    end
    BaseLife.noteHistory("gather_order_started", {
        orderId = order.id, material = material, requested = order.requested,
        zoneId = zone.id, destinationStorageId = storage.id,
    })
    bumpWorkConsistencyRevision()
    return true, order, enabledDuty
end

function BaseLife.pauseGatherOrder(id, reason)
    local base, order = activeBase(), workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    if SC.WorkTransport and type(SC.WorkTransport.pauseOrder) == "function" then
        SC.WorkTransport.pauseOrder(id, reason or "gather_paused")
    end
    interruptGatherWorkers(order, reason or "gather_paused")
    order.state, order.blocker, order.updatedAt = "paused",
        cleanText(reason, "gather_paused", 160), now()
    for _, job in ipairs(base.jobs) do
        if job.type == "gather_materials" and type(job.target) == "table"
            and job.target.orderId == id then
            job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
        end
    end
    return true, order
end

function BaseLife.resumeGatherOrder(id)
    local base, order = activeBase(), workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    if type(order.workers) ~= "table" or #order.workers < 1 then
        order.state, order.blocker, order.updatedAt = "paused", "gather_worker_missing", now()
        return false, "gather_worker_missing"
    end
    order.state, order.blocker, order.updatedAt = "running", nil, now()
    local ready, reason = ensureGatherJobs(base, order)
    if not ready then
        order.state, order.blocker = "blocked", cleanText(reason, "job_restore_failed", 160)
        return false, reason
    end
    if SC.GatherWork and type(SC.GatherWork.retryOrder) == "function" then
        SC.GatherWork.retryOrder(id)
    end
    return true, order
end

function BaseLife.retryGatherOrder(id)
    local order = workOrderIn(activeBase(), id)
    if not order then return false, "unknown_work_order" end
    if orderIsTerminal(order) then
        if not SC.WorkTransport or type(SC.WorkTransport.retryCleanup) ~= "function" then
            return false, "work_cleanup_retry_unavailable"
        end
        -- A terminal order is immutable accounting history. Only re-arm its
        -- marker cleanup; never recreate jobs, change delivery totals, or turn
        -- completed/cancelled work back into a running order.
        return SC.WorkTransport.retryCleanup(id)
    end
    if SC.WorkTransport and type(SC.WorkTransport.retryOrder) == "function" then
        local ready, reason = SC.WorkTransport.retryOrder(id)
        if ready ~= true then return false, reason end
    end
    return BaseLife.resumeGatherOrder(id)
end

function BaseLife.changeGatherDestination(id, storageId)
    local base, order = activeBase(), workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    local storage = gatheringStorage(base, storageId)
    if not storage then return false, "invalid_gather_destination" end
    if not BaseLife.resolveContainer(storage) then return false, "destination_storage_unloaded" end
    interruptGatherWorkers(order, "gather_destination_changed")
    order.destinationStorageId, order.updatedAt, order.blocker = storage.id, now(), nil
    for _, receipt in ipairs(workFor(base).receipts) do
        if receipt.orderId == id and not receiptIsTerminal(receipt) then
            receipt.destinationStorageId, receipt.updatedAt = storage.id, now()
        end
    end
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.addGatherWorker(id, actorId)
    local base, order = activeBase(), workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    if #order.workers >= (U().config("workMaximumWorkersPerOrder") or 2) then
        return false, "gather_worker_limit"
    end
    for _, workerId in ipairs(order.workers) do
        if workerId == actorId then return true, order end
    end
    local workers, reason = eligibleGatherWorkers(base, { actorId })
    if not workers then return false, reason end
    order.workers[#order.workers + 1] = actorId
    local wasOnDuty = ensure().residents[actorId].duty == true
    ensure().residents[actorId].duty = true
    local ready, jobReason = ensureGatherJobs(base, order)
    if not ready then
        table.remove(order.workers, #order.workers)
        ensure().residents[actorId].duty = wasOnDuty
        return false, jobReason
    end
    order.updatedAt = now()
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.cancelGatherOrder(id)
    local base, order = activeBase(), workOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    if SC.WorkTransport and type(SC.WorkTransport.cancelOrder) == "function" then
        SC.WorkTransport.cancelOrder(id, "gather_cancelled")
    end
    interruptGatherWorkers(order, "gather_cancelled")
    order.state, order.blocker, order.updatedAt = "cancelled", nil, now()
    removeGatherJobs(base, id)
    BaseLife.noteHistory("gather_order_cancelled", {
        orderId = id, material = order.material, delivered = order.delivered,
    })
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.releaseGatherCargo(orderId, actorId)
    if not SC.WorkTransport or type(SC.WorkTransport.releaseCarriedCargo) ~= "function" then
        return false, "work_transport_unavailable"
    end
    return SC.WorkTransport.releaseCarriedCargo(orderId, actorId)
end

function BaseLife.accountGatherDelivery(orderId, receiptId)
    local base, order = activeBase(), workOrderIn(activeBase(), orderId)
    local receipt = workReceiptIn(base, receiptId)
    if not order or not receipt or receipt.orderId ~= orderId then
        return false, "work_receipt_mismatch"
    end
    if receipt.accounted == true then return true, order, "already_accounted" end
    if receipt.phase ~= "delivered" or receipt.owner ~= "destination" then
        return false, "work_delivery_unverified"
    end
    receipt.accounted, receipt.updatedAt = true, now()
    order.delivered = math.min(order.requested, order.delivered + 1)
    order.updatedAt, order.blocker = now(), nil
    if order.delivered >= order.requested then
        order.state, order.completedAt = "completed", now()
        removeGatherJobs(base, orderId, "gathered")
        BaseLife.noteHistory("gather_order_completed", {
            orderId = order.id, material = order.material, delivered = order.delivered,
        })
    elseif order.state == "blocked" then
        order.state = "running"
    end
    bumpWorkConsistencyRevision()
    return true, order, "delivery_accounted"
end

-- ---------------------------------------------------------------------------
-- Production orders (fell trees, saw planks, dig graves, bury the dead).
-- They share base jobs, worker rules and caps with gathering, but live in a
-- separate versioned document: gathering receipts stay single-material and
-- untouched, and production evidence is re-proved from the world each time.
-- ---------------------------------------------------------------------------

local function productionFor(base)
    if not base then return nil end
    if type(base.production) ~= "table" then base.production = emptyProduction() end
    return base.production
end

local function productionOrderIn(base, id)
    local production = productionFor(base)
    return production and findById(production.orders, id) or nil
end

-- Zone kinds that may lie in the bounded reach band around the camp.
BaseLife.REACH_ZONE_KINDS = { lumber = true, burial = true, pyre = true }

local function productionZone(base, schema, id)
    local zone = findById(base and base.zones or {}, id)
    if not zone or type(schema.zoneKinds) ~= "table" or not schema.zoneKinds[zone.kind] then
        return nil, "invalid_production_zone"
    end
    local tiles = (zone.x2 - zone.x1 + 1) * (zone.y2 - zone.y1 + 1)
    local limitKey = zone.kind == "burial" and "productionBurialMaximumTiles"
        or zone.kind == "pyre" and "productionPyreMaximumTiles"
        or "productionLumberMaximumTiles"
    if tiles > (U().config(limitKey) or 256) then return nil, "production_zone_too_large" end
    if BaseLife.REACH_ZONE_KINDS[zone.kind] then
        if not BaseLife.lumberZoneReachable(zone, base.zones) then
            return nil, zone.kind == "lumber" and "lumber_zone_out_of_reach"
                or "production_zone_out_of_reach"
        end
    elseif not BaseLife.zoneInsideAreaUnion(zone, base.zones) then
        return nil, "production_zone_outside_camp"
    end
    return zone
end

-- Work may continue in the reach band outside the camp when it is bound to a
-- lumber area, to a burial ground or pyre that actually lies outside the
-- camp, or when body collection includes the lumber areas.
function BaseLife.jobAllowsWorkReach(job)
    if type(job) ~= "table" or type(job.target) ~= "table" then return false end
    local base = activeBase()
    local order
    if job.type == "production" then order = productionOrderIn(base, job.target.orderId)
    elseif job.type == "gather_materials" then order = workOrderIn(base, job.target.orderId) end
    if not order then return false end
    if job.type == "production" and order.operation == "collect_bodies"
        and type(order.settings) == "table" and order.settings.fromLumber == true then
        return true
    end
    local zone = findById(base and base.zones or {}, order.zoneId)
    if zone == nil or BaseLife.REACH_ZONE_KINDS[zone.kind] ~= true then return false end
    return zone.kind == "lumber" or not BaseLife.zoneInsideAreaUnion(zone, base.zones)
end

local function pruneProductionRows(production)
    local limit = U().config("productionOrderRecordLimit") or 16
    while #production.orders >= limit do
        local removed = false
        for index, order in ipairs(production.orders) do
            if orderIsTerminal(order) then
                table.remove(production.orders, index)
                removed = true
                break
            end
        end
        if not removed then break end
    end
end

local function removeProductionJobs(base, orderId, result, actorId)
    local removed = 0
    for index = #base.jobs, 1, -1 do
        local job = base.jobs[index]
        if job.type == "production" and type(job.target) == "table"
            and job.target.orderId == orderId
            and (actorId == nil or job.assignedId == actorId) then
            if result ~= nil then
                base.completed[#base.completed + 1] = {
                    id = job.id, type = job.type, actorId = job.assignedId,
                    completedAt = now(), result = cleanText(result, "completed", 96),
                }
                while #base.completed > 24 do table.remove(base.completed, 1) end
            end
            table.remove(base.jobs, index)
            removed = removed + 1
        end
    end
    return removed
end

local function ensureProductionJobs(base, order)
    for _, workerId in ipairs(order.workers) do
        local exists = false
        for _, job in ipairs(base.jobs) do
            if job.type == "production" and job.assignedId == workerId
                and type(job.target) == "table" and job.target.orderId == order.id then
                exists = true
                break
            end
        end
        if not exists then
            local accepted, reason = BaseLife.enqueueJob({
                type = "production", priority = 3, assignedId = workerId,
                target = { orderId = order.id },
            })
            if accepted ~= true then return false, reason end
        end
    end
    return true
end

local function releaseBlockedProductionJobs(base, orderId)
    for _, job in ipairs(base.jobs) do
        if job.type == "production" and type(job.target) == "table"
            and job.target.orderId == orderId and job.state == "blocked" then
            job.state, job.retryAt, job.blocker = "pending", 0, nil
        end
    end
end

local function interruptProductionWorkers(order, reason)
    for _, workerId in ipairs(order and order.workers or {}) do
        local actor = U().resolveActor(workerId)
        if actor and SC.BaseWork and type(SC.BaseWork.cancel) == "function" then
            local called, cancelled, cancelReason = pcall(SC.BaseWork.cancel, actor, reason)
            if not called or cancelled ~= true then
                return false, cancelReason or cancelled or "production_interrupt_failed"
            end
        elseif actor and SC.Production and type(SC.Production.cancelActor) == "function" then
            local called, cancelled, cancelReason = pcall(SC.Production.cancelActor, actor, reason)
            if not called or cancelled ~= true then
                return false, cancelReason or cancelled or "production_interrupt_failed"
            end
        end
    end
    return true
end

local function forgetProductionRuntime(order)
    if SC.Production and type(SC.Production.forgetOrder) == "function" then
        pcall(SC.Production.forgetOrder, order.id, order.workers)
    end
end

function BaseLife.productionOrder(id)
    return productionOrderIn(activeBase(), id)
end

function BaseLife.productionOrders(includeTerminal)
    local result, production = {}, productionFor(activeBase())
    for _, order in ipairs(production and production.orders or {}) do
        if includeTerminal == true or not orderIsTerminal(order) then
            result[#result + 1] = order
        end
    end
    return result
end

function BaseLife.productionCounters()
    local production = productionFor(activeBase())
    local result = emptyProductionCounters()
    for _, key in ipairs(BaseLife.PRODUCTION_COUNTERS) do
        result[key] = production and integer(production.counters[key], 0, 0, 999999) or 0
    end
    return result
end

function BaseLife.dutyResidentIds()
    local base, result = activeBase(), {}
    if not base then return result end
    for id, resident in pairs(ensure().residents) do
        if resident.baseId == base.id and resident.duty == true then result[#result + 1] = id end
    end
    table.sort(result)
    while #result > 16 do table.remove(result) end
    return result
end

function BaseLife.createProductionOrder(spec)
    local base, current = activeBase(), now()
    spec = type(spec) == "table" and spec or {}
    if not base then return false, "base_missing" end
    local schema = type(spec.operation) == "string"
        and BaseLife.PRODUCTION_OPERATIONS[spec.operation] or nil
    if not schema then return false, "unsupported_production_operation" end
    local zone
    if schema.zoneKinds ~= nil then
        local zoneReason
        zone, zoneReason = productionZone(base, schema, spec.zoneId)
        if not zone then return false, zoneReason end
    end
    local settings = normalizeProductionSettings(schema, spec.settings)
    if spec.operation == "collect_bodies" and settings.fromCamp ~= true
        and settings.fromLumber ~= true then
        return false, "collect_sources_missing"
    end
    -- Burning happens only on a pyre that passes the fire-safety check now.
    if zone and zone.kind == "pyre" and SC.Production
        and type(SC.Production.validatePyreZone) == "function" then
        local safe, unsafeReason = SC.Production.validatePyreZone(zone)
        if safe ~= true then return false, "pyre_unsafe:" .. tostring(unsafeReason) end
    end
    local sourceStorage, destinationStorage
    if schema.source == true then
        sourceStorage = findById(base.storages, spec.sourceStorageId)
        if not sourceStorage or sourceStorage.withdrawals == false then
            return false, "invalid_production_source"
        end
        if not BaseLife.resolveContainer(sourceStorage) then return false, "production_source_unloaded" end
    end
    local needsDestination = schema.destination == true
        or (schema.destination == "optional" and settings.haulLogs == true)
    if needsDestination then
        destinationStorage = gatheringStorage(base, spec.destinationStorageId)
        if not destinationStorage then return false, "invalid_production_destination" end
        if not BaseLife.resolveContainer(destinationStorage) then
            return false, "destination_storage_unloaded"
        end
    end
    if sourceStorage and destinationStorage and sourceStorage.id == destinationStorage.id then
        return false, "production_storage_conflict"
    end
    local workers, workerReason = eligibleWorkers(base, spec.workers, "production")
    if not workers then return false, workerReason end
    local production, activeCount = productionFor(base), 0
    for _, order in ipairs(production.orders) do
        if not orderIsTerminal(order) then activeCount = activeCount + 1 end
    end
    if activeCount >= (U().config("productionMaximumOrders") or 6) then
        return false, "production_order_limit"
    end
    pruneProductionRows(production)
    if #production.orders >= (U().config("productionOrderRecordLimit") or 16) then
        return false, "production_order_history_full"
    end
    for _, workerId in ipairs(workers) do
        if ensure().residents[workerId].duty ~= true and spec.enableDuty ~= true then
            return false, "production_worker_off_duty"
        end
    end
    local serial = integer(production.nextOrderSerial, 1, 1, 999999)
    local order = normalizeProductionOrder({
        id = "production-order:" .. tostring(serial), operation = spec.operation,
        zoneId = zone and zone.id or nil,
        sourceStorageId = sourceStorage and sourceStorage.id or nil,
        destinationStorageId = destinationStorage and destinationStorage.id or nil,
        requested = spec.requested, completed = 0, workers = workers, state = "running",
        settings = settings, createdAt = current, updatedAt = current,
    })
    if not order then return false, "invalid_production_order" end
    local enabledDuty = {}
    for _, workerId in ipairs(workers) do
        local resident = ensure().residents[workerId]
        if resident.duty ~= true then
            resident.duty = true
            enabledDuty[#enabledDuty + 1] = workerId
        end
    end
    production.nextOrderSerial = serial + 1
    production.orders[#production.orders + 1] = order
    local jobsReady, jobsReason = ensureProductionJobs(base, order)
    if not jobsReady then
        removeProductionJobs(base, order.id)
        table.remove(production.orders, #production.orders)
        for _, workerId in ipairs(enabledDuty) do ensure().residents[workerId].duty = false end
        return false, jobsReason
    end
    BaseLife.noteHistory("production_order_started", {
        orderId = order.id, operation = order.operation, requested = order.requested,
        zoneId = order.zoneId,
    })
    bumpWorkConsistencyRevision()
    return true, order, enabledDuty
end

function BaseLife.blockProductionOrder(id, reason)
    local order = productionOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    order.state, order.blocker, order.updatedAt = "blocked",
        cleanText(reason, "production_blocked", 160), now()
    -- Runtime-only cadence: a restored blocked order re-checks at once.
    order.retryAt = now() + math.max(1000, U().config("productionBlockedRetryMs") or 30000)
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.reopenProductionOrder(id)
    local order = productionOrderIn(activeBase(), id)
    if not order or order.state ~= "blocked" then return false, "production_order_not_blocked" end
    order.state, order.blocker, order.updatedAt = "running", nil, now()
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.pauseProductionOrder(id, reason)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    local interrupted, interruptReason = interruptProductionWorkers(order,
        reason or "production_paused")
    if interrupted ~= true then return false, interruptReason or "production_interrupt_failed" end
    order.state, order.blocker, order.updatedAt = "paused",
        cleanText(reason, "production_paused", 160), now()
    for _, job in ipairs(base.jobs) do
        if job.type == "production" and type(job.target) == "table"
            and job.target.orderId == id then
            job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
        end
    end
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.resumeProductionOrder(id)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    if type(order.workers) ~= "table" or #order.workers < 1 then
        order.state, order.blocker, order.updatedAt = "paused", "production_worker_missing", now()
        return false, "production_worker_missing"
    end
    order.state, order.blocker, order.updatedAt = "running", nil, now()
    local ready, reason = ensureProductionJobs(base, order)
    if not ready then
        order.state, order.blocker = "blocked", cleanText(reason, "job_restore_failed", 160)
        return false, reason
    end
    releaseBlockedProductionJobs(base, id)
    if SC.Production and type(SC.Production.retryOrder) == "function" then
        SC.Production.retryOrder(id)
    end
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.retryProductionOrder(id)
    return BaseLife.resumeProductionOrder(id)
end

function BaseLife.cancelProductionOrder(id)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    local interrupted, interruptReason = interruptProductionWorkers(order, "production_cancelled")
    if interrupted ~= true then return false, interruptReason or "production_interrupt_failed" end
    order.state, order.blocker, order.updatedAt = "cancelled", nil, now()
    removeProductionJobs(base, id)
    forgetProductionRuntime(order)
    BaseLife.noteHistory("production_order_cancelled", {
        orderId = id, operation = order.operation, completed = order.completed,
    })
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.addProductionWorker(id, actorId)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    if #order.workers >= (U().config("workMaximumWorkersPerOrder") or 2) then
        return false, "production_worker_limit"
    end
    for _, workerId in ipairs(order.workers) do
        if workerId == actorId then return true, order end
    end
    local workers, reason = eligibleWorkers(base, { actorId }, "production")
    if not workers then return false, reason end
    order.workers[#order.workers + 1] = actorId
    local wasOnDuty = ensure().residents[actorId].duty == true
    ensure().residents[actorId].duty = true
    local ready, jobReason = ensureProductionJobs(base, order)
    if not ready then
        table.remove(order.workers, #order.workers)
        ensure().residents[actorId].duty = wasOnDuty
        return false, jobReason
    end
    order.updatedAt = now()
    bumpWorkConsistencyRevision()
    return true, order
end

-- Progress is recorded only after the production layer re-proved the vanilla
-- post-condition in the world; completion is a separate, explicit step so an
-- operation can finish its closing work (for example filling a grave).
function BaseLife.recordProductionProgress(id, amount)
    local order = productionOrderIn(activeBase(), id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    amount = integer(amount, 0, 0, 999)
    local previous = order.completed
    order.completed = math.min(order.requested, order.completed + amount)
    order.updatedAt, order.blocker = now(), nil
    if order.completed ~= previous then bumpWorkConsistencyRevision() end
    return true, order
end

function BaseLife.completeProductionOrder(id, result)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_production_order" end
    if order.completed < order.requested then return false, "production_quota_open" end
    order.state, order.completedAt, order.updatedAt, order.blocker = "completed", now(), now(), nil
    removeProductionJobs(base, id, result or order.operation)
    forgetProductionRuntime(order)
    BaseLife.noteHistory("production_order_completed", {
        orderId = order.id, operation = order.operation, completed = order.completed,
    })
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.noteProductionCounter(key, amount)
    local production = productionFor(activeBase())
    if not production then return false, "base_missing" end
    local known = false
    for _, counter in ipairs(BaseLife.PRODUCTION_COUNTERS) do
        if counter == key then known = true break end
    end
    if not known then return false, "unknown_production_counter" end
    local previous = integer(production.counters[key], 0, 0, 999999)
    production.counters[key] = math.min(999999, previous + integer(amount, 0, 0, 999))
    if production.counters[key] ~= previous then bumpWorkConsistencyRevision() end
    return true, production.counters[key]
end

function BaseLife.noteProductionGrave(id, point)
    local order = productionOrderIn(activeBase(), id)
    local normalized = type(point) == "table" and normalizePoint(point) or nil
    if not order or not normalized then return false, "invalid_production_grave" end
    for _, grave in ipairs(order.graves) do
        if grave.x == normalized.x and grave.y == normalized.y and grave.z == normalized.z then
            return true, order
        end
    end
    order.graves[#order.graves + 1] = normalized
    while #order.graves > 8 do table.remove(order.graves, 1) end
    bumpWorkConsistencyRevision()
    return true, order
end

function BaseLife.forgetProductionGrave(id, point)
    local order = productionOrderIn(activeBase(), id)
    local normalized = type(point) == "table" and normalizePoint(point) or nil
    if not order or not normalized then return false, "invalid_production_grave" end
    local removed = false
    for index = #order.graves, 1, -1 do
        local grave = order.graves[index]
        if grave.x == normalized.x and grave.y == normalized.y and grave.z == normalized.z then
            table.remove(order.graves, index)
            removed = true
        end
    end
    if removed then bumpWorkConsistencyRevision() end
    return true, order
end

function BaseLife.extendGatherOrder(id, amount)
    local base = activeBase()
    local order = workOrderIn(base, id)
    if not order or orderIsTerminal(order) then return false, "unknown_work_order" end
    amount = integer(amount, 0, 0, 999999)
    if amount < 1 then return false, "gather_extension_empty" end
    local accepted = math.min(amount, math.max(0, 100 - order.requested))
    local remainder = amount - accepted
    if accepted == 0 then return true, order, 0, remainder end
    order.requested = order.requested + accepted
    order.updatedAt = now()
    if order.state == "blocked" then
        order.state, order.blocker = "running", nil
        ensureGatherJobs(base, order)
        for _, job in ipairs(base.jobs) do
            if job.type == "gather_materials" and type(job.target) == "table"
                and job.target.orderId == id and job.state == "blocked" then
                job.state, job.retryAt, job.blocker = "pending", 0, nil
            end
        end
        if SC.GatherWork and type(SC.GatherWork.retryOrder) == "function" then
            SC.GatherWork.retryOrder(id)
        end
    end
    bumpWorkConsistencyRevision()
    return true, order, accepted, remainder
end

-- Felled logs stay vanilla world items. One linked gathering order moves
-- them under exact-item receipts instead of a second ledger. A gather child is
-- deliberately capped at 100 items; overflow is persisted on the production
-- order and split into further children instead of being silently discarded.
local function flushProductionHaul(base, order)
    local pending = integer(order.pendingHaul, 0, 0, 999999)
    local latest
    while pending > 0 do
        local linked = order.linkedGatherOrderId
            and workOrderIn(base, order.linkedGatherOrderId) or nil
        if linked and not orderIsTerminal(linked) then
            local extended, value, accepted, remainder = BaseLife.extendGatherOrder(
                linked.id, pending)
            if extended ~= true then return false, value end
            latest, pending = value, remainder
        end
        if pending > 0 then
            local chunk = math.min(100, pending)
            local ok, gather = BaseLife.createGatherOrder({
                material = "logs", requested = chunk, zoneId = order.zoneId,
                destinationStorageId = order.destinationStorageId, workers = order.workers,
                enableDuty = true,
            })
            if ok ~= true then
                order.pendingHaul, order.updatedAt = pending, now()
                bumpWorkConsistencyRevision()
                return false, gather
            end
            order.linkedGatherOrderId = gather.id
            latest, pending = gather, pending - chunk
        end
    end
    if order.pendingHaul ~= 0 then
        order.pendingHaul, order.updatedAt = 0, now()
        bumpWorkConsistencyRevision()
    end
    return true, latest
end

function BaseLife.flushProductionHaul(id)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or order.operation ~= "fell_trees" or orderIsTerminal(order) then
        return false, "unknown_production_order"
    end
    if type(order.settings) ~= "table" or order.settings.haulLogs ~= true
        or not order.destinationStorageId then
        return false, "production_haul_disabled"
    end
    if integer(order.pendingHaul, 0, 0, 999999) == 0 then return true, nil end
    return flushProductionHaul(base, order)
end

function BaseLife.linkProductionHaul(id, amount)
    local base = activeBase()
    local order = productionOrderIn(base, id)
    if not order or order.operation ~= "fell_trees" or orderIsTerminal(order) then
        return false, "unknown_production_order"
    end
    if type(order.settings) ~= "table" or order.settings.haulLogs ~= true
        or not order.destinationStorageId then
        return false, "production_haul_disabled"
    end
    amount = integer(amount, 0, 0, 999999)
    if amount < 1 then return false, "production_haul_empty" end
    order.pendingHaul = math.min(999999,
        integer(order.pendingHaul, 0, 0, 999999) + amount)
    order.updatedAt = now()
    bumpWorkConsistencyRevision()
    return flushProductionHaul(base, order)
end

function BaseLife.workRecoveryCursor(value)
    local work = workFor(activeBase())
    if not work then return 1 end
    if value ~= nil then work.recoveryCursor = integer(value, 1, 1, 999999) end
    return work.recoveryCursor
end

function BaseLife.enqueueJob(spec)
    local base = activeBase()
    spec = type(spec) == "table" and spec or {}
    if not base then return false, "base_missing" end
    if not BaseLife.JOB_TYPES[spec.type] then return false, "invalid_job_type" end
    local activeCount = 0
    for _, job in ipairs(base.jobs) do
        if job.state ~= "completed" and job.state ~= "cancelled" then activeCount = activeCount + 1 end
    end
    if activeCount >= (U().config("baseMaxJobs") or 64) then return false, "job_limit" end
    spec = stableCopy(spec, 4, { count = 128 }) or {}
    spec.id = nextId("nextJobSerial", "job:")
    spec.state, spec.createdAt, spec.updatedAt = "pending", now(), now()
    local job = normalizeJob(spec)
    base.jobs[#base.jobs + 1] = job
    return true, job
end

function BaseLife.job(id)
    local base = activeBase()
    return base and findById(base.jobs, id) or nil
end

function BaseLife.jobFor(actorId)
    local base = activeBase()
    if not base then return nil end
    local current = now()
    for _, job in ipairs(base.jobs) do
        if (job.state == "reserved" or job.state == "active") and job.reservedBy == actorId then
            if job.leaseUntil > current then return job end
            job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
        end
    end
    return nil
end

local function orderOwnedJob(job)
    return job.type == "gather_materials" or job.type == "production"
end

local function orderForJob(base, job)
    local orderId = type(job.target) == "table" and job.target.orderId or nil
    if job.type == "gather_materials" then return workOrderIn(base, orderId) end
    if job.type == "production" then return productionOrderIn(base, orderId) end
    return nil
end

local function jobScore(actorId, job)
    if orderOwnedJob(job) then
        local order = orderForJob(activeBase(), job)
        -- A blocked production order reopens itself once its job retry is
        -- due, so its job stays claimable exactly like a blocked gather job.
        if not order or (order.state ~= "running"
            and not (job.type == "production" and order.state == "blocked"
                and (tonumber(order.retryAt) or 0) <= now())) then
            return -math.huge
        end
        local assigned = false
        for _, workerId in ipairs(type(order.workers) == "table" and order.workers or {}) do
            if workerId == actorId then assigned = true break end
        end
        if not assigned then return -math.huge end
    end
    local resident = ensure().residents[actorId] or { role = "generalist" }
    local role = BaseLife.ROLES[resident.role] and resident.role or "generalist"
    local score = job.priority * 20 + ((roleAffinity[role] or {})[job.type] or 0)
    if job.assignedId == actorId then score = score + 100 end
    if job.assignedId ~= nil and job.assignedId ~= actorId then return -math.huge end
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(actorId) or nil
    local personality = record and type(record.state) == "table"
        and type(record.state.personality) == "table" and record.state.personality or nil
    local background = personality and personality.background or (record and record.background)
    if background and SC.Background and type(SC.Background.baseJobModifier) == "function" then
        score = score + SC.Background.baseJobModifier(background, job.type)
    end
    if record and record.actor and type(job.target) == "table" then
        score = score - math.min(20, U().distance(record.actor, job.target) * 0.2)
    end
    return score
end

function BaseLife.claimJob(actorId)
    local base, current = activeBase(), now()
    local resident = ensure().residents[actorId]
    if not base or not resident or resident.duty ~= true then return nil, "not_on_base_duty" end
    local restriction = ensure().restrictions[actorId]
    if restriction == "quarantine" or restriction == "watch" then
        return nil, "infection_restriction"
    end
    -- Restored or legacy rows may contain a gather job whose assigned worker
    -- has already left the order. Retire it once instead of letting duty-on
    -- repeatedly claim, fail and block the stale row.
    local staleRemoved = false
    for index = #base.jobs, 1, -1 do
        local job = base.jobs[index]
        if orderOwnedJob(job) then
            local order = orderForJob(base, job)
            local assigned = false
            for _, workerId in ipairs(order and type(order.workers) == "table"
                and order.workers or {}) do
                if workerId == job.assignedId then assigned = true break end
            end
            if not order or orderIsTerminal(order) or not assigned then
                table.remove(base.jobs, index)
                staleRemoved = true
            end
        end
    end
    if staleRemoved then bumpWorkConsistencyRevision() end
    local existing = BaseLife.jobFor(actorId)
    if existing then return existing, "existing_job" end
    local best, bestScore
    for _, job in ipairs(base.jobs) do
        if job.state == "reserved" and job.leaseUntil <= current then
            job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
        end
        if (job.state == "pending" or (job.state == "blocked" and job.retryAt <= current)) then
            local score = jobScore(actorId, job)
            if bestScore == nil or score > bestScore
                or (score == bestScore and tostring(job.id) < tostring(best.id)) then
                best, bestScore = job, score
            end
        end
    end
    if not best or bestScore == -math.huge then return nil, "no_base_job" end
    best.state, best.reservedBy = "reserved", actorId
    best.leaseUntil = current + (U().config("baseJobLeaseMs") or 45000)
    best.updatedAt, best.blocker = current, nil
    return best, "job_claimed"
end

function BaseLife.touchJob(id, actorId, state)
    local job = BaseLife.job(id)
    if not job or job.reservedBy ~= actorId then return false, "job_not_owned" end
    if state ~= nil and state ~= "reserved" and state ~= "active" then return false, "invalid_job_state" end
    job.state = state or job.state
    job.leaseUntil = now() + (U().config("baseJobLeaseMs") or 45000)
    job.updatedAt = now()
    return true, job
end

function BaseLife.releaseJob(id, actorId, reason)
    local job = BaseLife.job(id)
    if not job or (actorId ~= nil and job.reservedBy ~= actorId) then return false, "job_not_owned" end
    job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
    job.blocker = reason and cleanText(reason, "released", 160) or nil
    job.updatedAt = now()
    return true, job
end

function BaseLife.blockJob(id, actorId, reason, retryMs)
    local job = BaseLife.job(id)
    if not job or (actorId ~= nil and job.reservedBy ~= actorId) then return false, "job_not_owned" end
    job.state, job.reservedBy, job.leaseUntil = "blocked", nil, 0
    job.blocker = cleanText(reason, "blocked", 160)
    job.attempts, job.updatedAt = (job.attempts or 0) + 1, now()
    job.retryAt = now() + math.max(1000, integer(retryMs, U().config("baseJobRetryMs") or 10000))
    return true, job
end

function BaseLife.completeJob(id, actorId, result)
    local base = activeBase()
    local job, index
    if base then job, index = findById(base.jobs, id) end
    if not base or not job or (actorId ~= nil and job.reservedBy ~= actorId) then
        return false, "job_not_owned"
    end
    job.state, job.reservedBy, job.leaseUntil = "completed", nil, 0
    job.updatedAt, job.blocker = now(), nil
    base.completed[#base.completed + 1] = {
        id = job.id, type = job.type, actorId = actorId, completedAt = job.updatedAt,
        result = cleanText(result, "completed", 96),
    }
    while #base.completed > 24 do table.remove(base.completed, 1) end
    table.remove(base.jobs, index)
    return true, job
end

function BaseLife.cancelJob(id)
    local base = activeBase()
    local job, index
    if base then job, index = findById(base.jobs, id) end
    if not job then return false, "unknown_job" end
    if job.type == "gather_materials" and type(job.target) == "table"
        and job.target.orderId then
        return BaseLife.cancelGatherOrder(job.target.orderId)
    end
    if job.type == "production" and type(job.target) == "table"
        and job.target.orderId then
        return BaseLife.cancelProductionOrder(job.target.orderId)
    end
    job.state, job.reservedBy, job.leaseUntil = "cancelled", nil, 0
    job.updatedAt = now()
    table.remove(base.jobs, index)
    return true, job
end

function BaseLife.retryJob(id)
    local job = BaseLife.job(id)
    if not job then return false, "unknown_job" end
    if job.type == "gather_materials" and type(job.target) == "table"
        and job.target.orderId then
        return BaseLife.retryGatherOrder(job.target.orderId)
    end
    if job.type == "production" and type(job.target) == "table"
        and job.target.orderId then
        return BaseLife.retryProductionOrder(job.target.orderId)
    end
    if job.state ~= "blocked" then return false, "job_not_blocked" end
    job.state, job.retryAt, job.blocker = "pending", 0, nil
    job.updatedAt = now()
    return true, job
end

function BaseLife.assign(actorId, role, duty)
    local base = activeBase()
    if not base or type(actorId) ~= "string" then return false, "base_or_actor_missing" end
    role = BaseLife.ROLES[role] and role or "generalist"
    local resident = ensure().residents[actorId] or {}
    resident.baseId, resident.role = base.id, role
    if duty ~= nil then resident.duty = duty == true end
    ensure().residents[actorId] = resident
    return true, resident
end

function BaseLife.setDuty(actorId, enabled)
    local resident = ensure().residents[actorId]
    if not resident then
        local role = "generalist"
        local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(actorId) or nil
        local personality = record and type(record.state) == "table"
            and type(record.state.personality) == "table" and record.state.personality or nil
        local background = personality and personality.background or (record and record.background)
        if background and SC.Background and type(SC.Background.preferredRole) == "function" then
            local preferred = SC.Background.preferredRole(background)
            if BaseLife.ROLES[preferred] then role = preferred end
        end
        local ok, value = BaseLife.assign(actorId, role, enabled)
        return ok, value
    end
    if enabled ~= true and SC.WorkTransport
        and type(SC.WorkTransport.yieldActor) == "function" then
        pcall(SC.WorkTransport.yieldActor, actorId, "left_base_duty")
    end
    resident.duty = enabled == true
    if not resident.duty then
        local job = BaseLife.jobFor(actorId)
        if job then BaseLife.releaseJob(job.id, actorId, "left_base_duty") end
    end
    return true, resident
end

function BaseLife.resident(actorId)
    return ensure().residents[actorId]
end

function BaseLife.setRestriction(actorId, value)
    if value ~= nil and value ~= "watch" and value ~= "quarantine" then
        return false, "invalid_restriction"
    end
    ensure().restrictions[actorId] = value
    return true
end

function BaseLife.policies()
    local base = activeBase()
    return base and stableCopy(base.settings, 3, { count = 64 }) or nil
end

function BaseLife.setPolicy(key, value)
    local base = activeBase()
    if not base then return false, "base_missing" end
    if key == "defense" then
        if not DEFENSE_POLICIES[value] then return false, "invalid_defense_policy" end
        base.settings.defense = value
    elseif key == "workload" then
        if not WORKLOAD_POLICIES[value] then return false, "invalid_workload_policy" end
        base.settings.workload = value
    elseif key == "routines" or key == "autoMaintenance" then
        if type(value) ~= "boolean" then return false, "invalid_boolean_policy" end
        base.settings[key] = value
    else
        return false, "invalid_base_policy"
    end
    operationsCache = nil
    BaseLife.noteHistory("policy_changed", { policy = key, value = tostring(value) })
    return true, value
end

function BaseLife.guardStatus(actorId, current)
    local base = activeBase()
    if not base then return false, nil, 0 end
    local all, guards = {}, {}
    for id, resident in pairs(ensure().residents) do
        if resident.baseId == base.id and resident.duty == true
            and ensure().restrictions[id] == nil then
            all[#all + 1] = id
            if resident.role == "guard" then guards[#guards + 1] = id end
        end
    end
    table.sort(all)
    table.sort(guards)
    local policy = base.settings.defense
    if policy == "all_hands" then
        for _, id in ipairs(all) do if id == actorId then return true, actorId, #all end end
        return false, nil, #all
    end
    if policy == "role_based" then
        for _, id in ipairs(guards) do if id == actorId then return true, actorId, #guards end end
        return false, nil, #guards
    end
    local candidates = #guards > 0 and guards or all
    if #candidates == 0 then return false, nil, 0 end
    local shift = U() and U().config("baseGuardShiftMs") or 180000
    local index = (math.floor(finite(current, now()) / math.max(30000, shift)) % #candidates) + 1
    return candidates[index] == actorId, candidates[index], #candidates
end

local function hasZone(base, kind)
    for _, zone in ipairs(base.zones or {}) do if zone.kind == kind then return true end end
    return false
end

function BaseLife.auditOperations(force)
    local base, current = activeBase(), now()
    if not base then operationsCache = nil return nil, "base_missing" end
    local interval = U() and U().config("baseOperationsAuditIntervalMs") or 5000
    if force ~= true and operationsCache and operationsCache.baseId == base.id
        and current - (operationsCache.auditedAt or 0) < interval then
        return stableCopy(operationsCache, 5, { count = 512 })
    end
    local residents, roles = 0, {}
    for id, resident in pairs(ensure().residents) do
        if resident.baseId == base.id then
            residents = residents + 1
            roles[resident.role] = (roles[resident.role] or 0) + 1
        end
    end
    local counts, stores, unloaded = {}, {}, 0
    for _, storage in ipairs(base.storages or {}) do
        local category = storage.category
        if defaultStockTargets[category] ~= nil then
            stores[category] = (stores[category] or 0) + 1
            local container = BaseLife.resolveContainer(storage)
            if container then
                counts[category] = (counts[category] or 0)
                    + #U().inventoryItems(container,
                        U().config("baseOperationsStorageItemBudget") or 160)
            else
                unloaded = unloaded + 1
            end
        end
    end
    local stockRows, alerts, readiness, metrics = {}, {}, 0, 0
    local scale = math.max(1, residents)
    for _, category in ipairs({ "food", "water", "medical", "construction", "ammunition" }) do
        local perResident = integer(base.settings.stockTargets[category],
            defaultStockTargets[category] or 0, 0, 99)
        local targetScale = category == "ammunition" and math.max(1, roles.guard or 0) or scale
        local target = perResident * targetScale
        local count = counts[category] or 0
        local configured = (stores[category] or 0) > 0
        local status = not configured and "Unconfigured"
            or count >= target and "Ready" or "Low"
        stockRows[#stockRows + 1] = { category = category, count = count,
            target = target, stores = stores[category] or 0, status = status }
        if target > 0 then
            metrics = metrics + 1
            readiness = readiness + (configured and math.min(1, count / math.max(1, target)) or 0)
            if not configured then alerts[#alerts + 1] = "No " .. category .. " storage is marked."
            elseif count < target then alerts[#alerts + 1] = "Stored " .. category .. " is below target."
            end
        end
    end
    local coverage = {
        { role = "guard", required = residents >= 2 and 1 or 0, assigned = roles.guard or 0 },
        { role = "builder", required = residents >= 2 and 1 or 0, assigned = roles.builder or 0 },
        { role = "medic", required = residents >= 3 and 1 or 0, assigned = roles.medic or 0 },
        { role = "quartermaster", required = residents >= 4 and 1 or 0,
            assigned = roles.quartermaster or 0 },
    }
    for _, row in ipairs(coverage) do
        if row.required > 0 then
            metrics = metrics + 1
            readiness = readiness + math.min(1, row.assigned / row.required)
            if row.assigned < row.required then
                alerts[#alerts + 1] = "No companion currently covers the " .. row.role .. " role."
            end
        end
    end
    local zones = { rest = hasZone(base, "rest"), social = hasZone(base, "social"),
        guard = hasZone(base, "guard"), rally = hasZone(base, "rally") }
    if residents > 0 and not zones.rest then alerts[#alerts + 1] = "No rest zone is marked." end
    if residents >= 2 and not zones.guard then alerts[#alerts + 1] = "No guard zone is marked." end
    local _, selectedGuard, guardCandidates = BaseLife.guardStatus(nil, current)
    operationsCache = {
        baseId = base.id, auditedAt = current,
        readiness = metrics > 0 and math.floor((readiness / metrics) * 100 + 0.5) or 0,
        stock = stockRows, coverage = coverage, alerts = alerts, zones = zones,
        unloadedStores = unloaded, activeGuard = selectedGuard,
        guardCandidates = guardCandidates, policies = stableCopy(base.settings, 3, { count = 64 }),
    }
    return stableCopy(operationsCache, 5, { count = 512 })
end

function BaseLife.restriction(actorId)
    return ensure().restrictions[actorId]
end

function BaseLife.noteHistory(kind, fields)
    local row = stableCopy(fields, 3, { count = 48 }) or {}
    row.kind, row.at = cleanText(kind, "event", 48), now()
    local history = ensure().history
    history[#history + 1] = row
    while #history > (U().config("baseHistoryLimit") or 96) do table.remove(history, 1) end
    return row
end

function BaseLife.summary()
    local operations = BaseLife.auditOperations(false)
    local base = activeBase()
    local jobByActor = {}
    if base then
        for _, job in ipairs(base.jobs or {}) do
            if job.reservedBy then jobByActor[job.reservedBy] = job.type end
        end
    end
    local result = {
        configured = base ~= nil, name = base and base.name or nil,
        core = base and stableCopy(base.core, 1, { count = 4 }) or nil,
        zones = base and #base.zones or 0,
        storages = base and #base.storages or 0,
        residents = 0, duty = 0, jobs = { pending = 0, active = 0, blocked = 0 },
        rows = {}, zoneRows = {}, storageRows = {}, maintenanceRows = {},
        residentRows = {}, history = {}, operations = operations,
        workOrders = {}, workReceipts = 0,
        productionOrders = {}, productionCounters = BaseLife.productionCounters(),
    }
    for id, resident in pairs(ensure().residents) do
        if base and resident.baseId == base.id then
            result.residents = result.residents + 1
            if resident.duty then result.duty = result.duty + 1 end
            local record = SC.Registry and type(SC.Registry.byId) == "function"
                and SC.Registry.byId(id) or nil
            local name = record and record.actor and U().nameOf(record.actor) or id
            local guarding = select(1, BaseLife.guardStatus(id, now()))
            result.residentRows[#result.residentRows + 1] = {
                id = id, name = name, role = resident.role, duty = resident.duty == true,
                guarding = guarding == true, job = jobByActor[id],
            }
        end
    end
    table.sort(result.residentRows, function(a, b) return a.id < b.id end)
    if base then
        for _, zone in ipairs(base.zones) do
            result.zoneRows[#result.zoneRows + 1] = {
                id = zone.id, kind = zone.kind, name = zone.name,
                x1 = zone.x1, y1 = zone.y1, x2 = zone.x2, y2 = zone.y2, z = zone.z,
            }
        end
        for _, job in ipairs(base.jobs) do
            if job.state == "pending" then result.jobs.pending = result.jobs.pending + 1
            elseif job.state == "reserved" or job.state == "active" then
                result.jobs.active = result.jobs.active + 1
            elseif job.state == "blocked" then result.jobs.blocked = result.jobs.blocked + 1 end
            if job.state ~= "completed" and job.state ~= "cancelled" then
                result.rows[#result.rows + 1] = {
                    id = job.id, type = job.type, priority = job.priority, state = job.state,
                    reservedBy = job.reservedBy, blocker = job.blocker,
                }
            end
        end
        for _, storage in ipairs(base.storages) do
            result.storageRows[#result.storageRows + 1] = {
                id = storage.id, category = storage.category, reserve = storage.reserve,
                reserves = stableCopy(storage.reserves, 2, { count = 64 }),
                x = storage.x, y = storage.y, z = storage.z,
                objectIndex = storage.objectIndex, objectId = storage.objectId,
                deposits = storage.deposits ~= false,
                withdrawals = storage.withdrawals ~= false,
            }
        end
        for _, target in ipairs(base.maintenanceTargets) do
            result.maintenanceRows[#result.maintenanceRows + 1] = {
                id = target.id, kind = target.kind, enabled = target.enabled == true,
                threshold = target.threshold, x = target.x, y = target.y, z = target.z,
                objectIndex = target.objectIndex,
            }
        end
        local receiptCounts = {}
        for _, receipt in ipairs(workFor(base).receipts) do
            local counts = receiptCounts[receipt.orderId]
                or { carried = 0, pending = 0, phases = {}, cleanupPending = 0,
                    cleanupExhausted = 0 }
            if receipt.markerCleanupPending == true then
                counts.cleanupPending = counts.cleanupPending + 1
                if receipt.blocker == "work_marker_cleanup_exhausted" then
                    counts.cleanupExhausted = counts.cleanupExhausted + 1
                end
            end
            if not receiptIsTerminal(receipt) then
                result.workReceipts = result.workReceipts + 1
                if receipt.phase == "carried" or receipt.phase == "depositing" then
                    counts.carried = counts.carried + 1
                elseif receipt.phase == "quarantined" and receipt.owner == "actor" then
                    -- The exact native item is still in a live worker inventory.
                    -- Keep it visible as releasable cargo instead of hiding the
                    -- only player action that can safely clear its work claim.
                    counts.carried = counts.carried + 1
                else counts.pending = counts.pending + 1 end
                counts.phases[receipt.actorId] = {
                    phase = receipt.phase, blocker = receipt.blocker,
                }
            end
            receiptCounts[receipt.orderId] = counts
        end
        for _, order in ipairs(workFor(base).orders) do
            local counts = receiptCounts[order.id]
                or { carried = 0, pending = 0, phases = {}, cleanupPending = 0,
                    cleanupExhausted = 0 }
            if not orderIsTerminal(order) or order.state == "completed"
                or counts.carried > 0 or counts.pending > 0
                or counts.cleanupPending > 0 then
                local workerPhases = {}
                for _, workerId in ipairs(order.workers) do
                    local phase = counts.phases[workerId]
                    local workerRecord = SC.Registry and type(SC.Registry.byId) == "function"
                        and SC.Registry.byId(workerId) or nil
                    workerPhases[#workerPhases + 1] = {
                        id = workerId,
                        name = workerRecord and workerRecord.actor
                            and U().nameOf(workerRecord.actor) or workerId,
                        phase = phase and phase.phase
                            or (order.state == "running" and "seeking" or order.state),
                        blocker = phase and phase.blocker or nil,
                    }
                end
                result.workOrders[#result.workOrders + 1] = {
                    id = order.id, operation = order.operation, material = order.material,
                    itemType = order.itemType, zoneId = order.zoneId,
                    destinationStorageId = order.destinationStorageId,
                    requested = order.requested, delivered = order.delivered,
                    workers = stableCopy(order.workers, 2, { count = 8 }),
                    state = order.state, blocker = order.blocker,
                    carried = counts.carried, pendingReceipts = counts.pending,
                    cleanupPending = counts.cleanupPending,
                    cleanupExhausted = counts.cleanupExhausted,
                    workerPhases = workerPhases,
                }
            end
        end
        for _, order in ipairs(productionFor(base).orders) do
            if not orderIsTerminal(order) or order.state == "completed" then
                local workerPhases = {}
                for _, workerId in ipairs(order.workers) do
                    local workerRecord = SC.Registry and type(SC.Registry.byId) == "function"
                        and SC.Registry.byId(workerId) or nil
                    local phase = SC.Production and type(SC.Production.workerPhase) == "function"
                        and SC.Production.workerPhase(order.id, workerId) or nil
                    workerPhases[#workerPhases + 1] = {
                        id = workerId,
                        name = workerRecord and workerRecord.actor
                            and U().nameOf(workerRecord.actor) or workerId,
                        phase = order.state == "running" and (phase or "seeking") or order.state,
                    }
                end
                local schema = BaseLife.PRODUCTION_OPERATIONS[order.operation] or {}
                result.productionOrders[#result.productionOrders + 1] = {
                    id = order.id, operation = order.operation, unit = schema.unit,
                    zoneId = order.zoneId, sourceStorageId = order.sourceStorageId,
                    destinationStorageId = order.destinationStorageId,
                    requested = order.requested, completed = order.completed,
                    workers = stableCopy(order.workers, 2, { count = 8 }),
                    state = order.state, blocker = order.blocker,
                    settings = stableCopy(order.settings, 2, { count = 16 }),
                    linkedGatherOrderId = order.linkedGatherOrderId,
                    pendingHaul = order.pendingHaul,
                    workerPhases = workerPhases,
                }
            end
        end
    end
    for _, row in ipairs(ensure().history) do
        result.history[#result.history + 1] = stableCopy(row, 3, { count = 64 })
    end
    return result
end

function BaseLife.export()
    return stableCopy(ensure(), 20, { count = 65536 })
end

local function restoreFailure(path, detail)
    return false, "invalid base life state at " .. tostring(path) .. ": " .. tostring(detail)
end

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function denseArray(value, path, maximum)
    if type(value) ~= "table" then return restoreFailure(path, "expected dense array") end
    local count, highest = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or not finiteNumber(key) or key < 1
            or key ~= math.floor(key) then
            return restoreFailure(path .. "[" .. tostring(key) .. "]", "non-array key")
        end
        count, highest = count + 1, math.max(highest, key)
    end
    if highest ~= count then return restoreFailure(path, "sparse array") end
    if maximum ~= nil and count > maximum then return restoreFailure(path, "too many entries") end
    return true, count
end

local function configuredLimit(key, fallback)
    local raw = U() and U().config and tonumber(U().config(key)) or nil
    if raw == nil or raw ~= raw or raw < 0 or raw == math.huge or raw == -math.huge then
        return fallback
    end
    return math.floor(raw)
end

local function validPoint(value, path)
    if type(value) ~= "table" then return restoreFailure(path, "expected position") end
    for _, key in ipairs({ "x", "y", "z" }) do
        if not finiteNumber(value[key]) then
            return restoreFailure(path .. "." .. key, "expected finite number")
        end
    end
    return true
end

local function validRecordArray(value, path, maximum)
    local okay, countOrReason = denseArray(value, path, maximum)
    if not okay then return false, countOrReason end
    for index = 1, countOrReason do
        if type(value[index]) ~= "table" then
            return restoreFailure(path .. "[" .. tostring(index) .. "]", "expected record")
        end
    end
    return true, countOrReason
end

local function validWorkSource(base, path)
    local source = base.work
    if source == nil then return true end
    if type(source) ~= "table" then return restoreFailure(path, "expected work document") end
    if tonumber(source.version) ~= BaseLife.WORK_VERSION then
        local preserved, reason = stableCopy(source, 12, { count = 8192 })
        if preserved == nil then
            return restoreFailure(path, reason or "future work document unreadable")
        end
        return true
    end
    for _, field in ipairs({ "nextOrderSerial", "nextReceiptSerial", "recoveryCursor" }) do
        if not finiteNumber(source[field]) or source[field] < 1
            or source[field] ~= math.floor(source[field]) then
            return restoreFailure(path .. "." .. field, "expected positive integer")
        end
    end
    local okay, countOrReason = denseArray(source.orders, path .. ".orders",
        configuredLimit("workOrderRecordLimit", 32))
    if not okay then return false, countOrReason end
    local orderIds = {}
    for index = 1, countOrReason do
        local order = source.orders[index]
        if normalizeWorkOrder(order) == nil then
            return restoreFailure(path .. ".orders[" .. tostring(index) .. "]", "invalid work order")
        end
        if orderIds[order.id] then
            return restoreFailure(path .. ".orders[" .. tostring(index) .. "].id",
                "duplicate work order")
        end
        orderIds[order.id] = normalizeWorkOrder(order)
        local zone, storage = false, false
        for _, row in ipairs(base.zones or {}) do
            if row.id == order.zoneId and BaseLife.GATHER_ZONE_KINDS[row.kind] then
                zone = true
                break
            end
        end
        for _, row in ipairs(base.storages or {}) do
            if row.id == order.destinationStorageId and row.deposits ~= false then
                storage = true break
            end
        end
        local normalizedOrder = normalizeWorkOrder(order)
        local activeOrder = normalizedOrder and not orderIsTerminal(normalizedOrder)
        if activeOrder and not zone then
            return restoreFailure(path .. ".orders[" .. tostring(index) .. "].zoneId",
                "unknown work zone")
        end
        if activeOrder and not storage then
            return restoreFailure(path .. ".orders[" .. tostring(index)
                .. "].destinationStorageId", "unknown deposit storage")
        end
    end
    okay, countOrReason = denseArray(source.receipts, path .. ".receipts",
        configuredLimit("workRecoveryMaxEntries", 32))
    if not okay then return false, countOrReason end
    local receiptIds = {}
    for index = 1, countOrReason do
        local receipt = source.receipts[index]
        local normalizedReceipt = normalizeWorkReceipt(receipt)
        if normalizedReceipt == nil then
            return restoreFailure(path .. ".receipts[" .. tostring(index) .. "]",
                "invalid work receipt")
        end
        if receiptIds[receipt.id] then
            return restoreFailure(path .. ".receipts[" .. tostring(index) .. "].id",
                "duplicate work receipt")
        end
        receiptIds[receipt.id] = true
        local parent = orderIds[receipt.orderId]
        if not parent then
            return restoreFailure(path .. ".receipts[" .. tostring(index) .. "].orderId",
                "unknown work order")
        end
        if normalizedReceipt.itemType ~= parent.itemType then
            return restoreFailure(path .. ".receipts[" .. tostring(index) .. "].itemType",
                "work receipt material mismatch")
        end
        -- Receipt ownership is immutable history. A worker may leave the live
        -- assignment after releasing, cancelling or delivering its cargo, so
        -- only the receipt's own actor identity and ownership invariants belong
        -- in restore validation.
        if not validId(normalizedReceipt.actorId, "sc-") then
            return restoreFailure(path .. ".receipts[" .. tostring(index) .. "].actorId",
                "invalid work receipt actor")
        end
        if normalizedReceipt.markerCleanupPending == true then
            local cleanupStorageExists = false
            for _, row in ipairs(base.storages or {}) do
                if row.id == normalizedReceipt.destinationStorageId then
                    cleanupStorageExists = true
                    break
                end
            end
            if not cleanupStorageExists then
                return restoreFailure(path .. ".receipts[" .. tostring(index)
                    .. "].destinationStorageId", "unknown marker cleanup destination")
            end
        end
        if not receiptIsTerminal(normalizedReceipt)
            and normalizedReceipt.destinationStorageId ~= parent.destinationStorageId then
            return restoreFailure(path .. ".receipts[" .. tostring(index)
                .. "].destinationStorageId", "active work receipt destination mismatch")
        end
    end
    if source.quarantine ~= nil then
        local preserved, reason = stableCopy(source.quarantine, 12, { count = 8192 })
        if preserved == nil then return restoreFailure(path .. ".quarantine", reason) end
    end
    return true
end

local function validProductionSource(base, path)
    local source = base.production
    if source == nil then return true end
    if type(source) ~= "table" then return restoreFailure(path, "expected production document") end
    if tonumber(source.version) ~= BaseLife.PRODUCTION_VERSION then
        local preserved, reason = stableCopy(source, 12, { count = 8192 })
        if preserved == nil then
            return restoreFailure(path, reason or "future production document unreadable")
        end
        return true
    end
    if not finiteNumber(source.nextOrderSerial) or source.nextOrderSerial < 1
        or source.nextOrderSerial ~= math.floor(source.nextOrderSerial) then
        return restoreFailure(path .. ".nextOrderSerial", "expected positive integer")
    end
    local okay, countOrReason = denseArray(source.orders, path .. ".orders",
        configuredLimit("productionOrderRecordLimit", 16))
    if not okay then return false, countOrReason end
    local ids = {}
    for index = 1, countOrReason do
        local row = source.orders[index]
        local rowPath = path .. ".orders[" .. tostring(index) .. "]"
        if type(row) ~= "table" then return restoreFailure(rowPath, "expected record") end
        local order, reason = normalizeProductionOrder(row)
        if order == nil and reason ~= "unknown_operation" then
            return restoreFailure(rowPath, "invalid production order")
        end
        if order == nil then
            local raw, rawReason = stableCopy(row, 8, { count = 1024 })
            if raw == nil then return restoreFailure(rowPath, rawReason or "unreadable order") end
        end
        if ids[row.id] then return restoreFailure(rowPath .. ".id", "duplicate production order") end
        ids[row.id] = true
        if order and not orderIsTerminal(order) then
            local schema = BaseLife.PRODUCTION_OPERATIONS[order.operation]
            if schema.zoneKinds ~= nil then
                local zoneFound = false
                for _, zone in ipairs(base.zones or {}) do
                    if zone.id == order.zoneId and schema.zoneKinds[zone.kind] then
                        zoneFound = true
                        break
                    end
                end
                if not zoneFound then
                    return restoreFailure(rowPath .. ".zoneId", "unknown production zone")
                end
            end
            for _, field in ipairs({ "sourceStorageId", "destinationStorageId" }) do
                if order[field] ~= nil then
                    local storageFound = false
                    for _, storage in ipairs(base.storages or {}) do
                        if storage.id == order[field] then storageFound = true break end
                    end
                    if not storageFound then
                        return restoreFailure(rowPath .. "." .. field, "unknown production storage")
                    end
                end
            end
        end
    end
    if source.counters ~= nil then
        if type(source.counters) ~= "table" then
            return restoreFailure(path .. ".counters", "expected counter map")
        end
        for key, value in pairs(source.counters) do
            if type(key) ~= "string" or not finiteNumber(value) or value < 0
                or value ~= math.floor(value) then
                return restoreFailure(path .. ".counters[" .. tostring(key) .. "]",
                    "invalid production counter")
            end
        end
    end
    if source.quarantine ~= nil then
        local preserved, reason = stableCopy(source.quarantine, 12, { count = 8192 })
        if preserved == nil then return restoreFailure(path .. ".quarantine", reason) end
    end
    return true
end

local function validBaseSource(source, id, path)
    if type(source) ~= "table" or source.id ~= id or not validId(id, "base:") then
        return restoreFailure(path, "invalid base id")
    end
    local okay, reason = validPoint(source.core, path .. ".core")
    if not okay then return false, reason end
    if type(source.settings) ~= "table" then
        return restoreFailure(path .. ".settings", "expected settings")
    end
    if not DEFENSE_POLICIES[source.settings.defense] then
        return restoreFailure(path .. ".settings.defense", "invalid defense policy")
    end
    if not WORKLOAD_POLICIES[source.settings.workload] then
        return restoreFailure(path .. ".settings.workload", "invalid workload policy")
    end
    if type(source.settings.routines) ~= "boolean"
        or type(source.settings.autoMaintenance) ~= "boolean" then
        return restoreFailure(path .. ".settings", "policy flags must be boolean")
    end
    if type(source.settings.stockTargets) ~= "table" then
        return restoreFailure(path .. ".settings.stockTargets", "expected target map")
    end
    for category, amount in pairs(source.settings.stockTargets) do
        if defaultStockTargets[category] == nil or not finiteNumber(amount)
            or amount < 0 or amount > 99 or amount ~= math.floor(amount) then
            return restoreFailure(path .. ".settings.stockTargets[" .. tostring(category) .. "]",
                "invalid stock target")
        end
    end
    for category in pairs(defaultStockTargets) do
        if source.settings.stockTargets[category] == nil then
            return restoreFailure(path .. ".settings.stockTargets[" .. category .. "]",
                "missing stock target")
        end
    end

    local arrays = {
        { key = "zones", limit = configuredLimit("baseMaxZones", 24), normalizer = normalizeZone },
        { key = "storages", limit = configuredLimit("baseMaxStorages", 32), normalizer = normalizeStorage },
        { key = "maintenanceTargets", limit = configuredLimit("baseMaxMaintenanceTargets", 64),
            normalizer = normalizeTarget },
        { key = "jobs", limit = configuredLimit("baseMaxJobs", 64), normalizer = normalizeJob },
    }
    local ids = {}
    for _, specification in ipairs(arrays) do
        local arrayPath = path .. "." .. specification.key
        local arrayOkay, countOrReason = denseArray(source[specification.key], arrayPath,
            specification.limit)
        if not arrayOkay then return false, countOrReason end
        for index = 1, countOrReason do
            local row, rowPath = source[specification.key][index],
                arrayPath .. "[" .. tostring(index) .. "]"
            local normalized, normalizerCalled = nil, false
            normalizerCalled, normalized = pcall(specification.normalizer, row)
            if type(row) ~= "table" or not normalizerCalled or normalized == nil then
                return restoreFailure(rowPath, "invalid persisted entity")
            end
            if (specification.key == "storages" or specification.key == "maintenanceTargets")
                and ((row.objectId ~= nil and not validId(row.objectId, "object:"))
                    or (row.objectSignature ~= nil and type(row.objectSignature) ~= "string")) then
                return restoreFailure(rowPath .. ".objectId", "invalid object identity")
            end
            if ids[row.id] then return restoreFailure(rowPath .. ".id", "duplicate entity id") end
            ids[row.id] = true
            if specification.key == "storages" then
                if type(row.reserves) ~= "table" then
                    return restoreFailure(rowPath .. ".reserves", "expected reserve map")
                end
                local reserveCount = 0
                for itemType, amount in pairs(row.reserves) do
                    reserveCount = reserveCount + 1
                    if type(itemType) ~= "string" or itemType == "" or not finiteNumber(amount)
                        or amount < 0 or amount > 9999 or amount ~= math.floor(amount) then
                        return restoreFailure(rowPath .. ".reserves[" .. tostring(itemType) .. "]",
                            "invalid reserve")
                    end
                end
                if reserveCount > 64 then
                    return restoreFailure(rowPath .. ".reserves", "too many reserves")
                end
            elseif specification.key == "maintenanceTargets" then
                if row.kind ~= "barricade" and row.kind ~= "maintain" then
                    return restoreFailure(rowPath .. ".kind", "invalid maintenance kind")
                end
            elseif specification.key == "jobs" then
                if not JOB_STATES[row.state] then
                    return restoreFailure(rowPath .. ".state", "invalid job state")
                end
                if row.state == "completed" or row.state == "cancelled" then
                    return restoreFailure(rowPath .. ".state", "terminal job belongs in completed history")
                end
                if row.target ~= nil then
                    local targetCopy, targetReason = stableCopy(row.target, 3, { count = 64 })
                    if targetCopy == nil then
                        return restoreFailure(rowPath .. ".target", targetReason or "invalid target")
                    end
                end
            end
        end
    end
    okay, reason = validRecordArray(source.completed, path .. ".completed", 24)
    if not okay then return false, reason end
    for index = 1, reason do
        local rowCopy, rowReason = stableCopy(source.completed[index], 2, { count = 32 })
        if rowCopy == nil then
            return restoreFailure(path .. ".completed[" .. tostring(index) .. "]",
                rowReason or "invalid completed record")
        end
    end
    local workOkay, workReason = validWorkSource(source, path .. ".work")
    if not workOkay then return false, workReason end
    local productionOkay, productionReason = validProductionSource(source, path .. ".production")
    if not productionOkay then return false, productionReason end
    return true
end

local function validateRestoreSource(source)
    if type(source) ~= "table" or source.version ~= BaseLife.VERSION
        or type(source.bases) ~= "table" or type(source.residents) ~= "table"
        or type(source.restrictions) ~= "table" then
        return false, "invalid_base_life_state"
    end
    for _, field in ipairs({ "nextBaseSerial", "nextZoneSerial", "nextStorageSerial",
        "nextTargetSerial", "nextJobSerial" }) do
        local value = source[field]
        if not finiteNumber(value) or value < 1 or value ~= math.floor(value) then
            return restoreFailure("$.baseLife." .. field, "expected positive integer")
        end
    end
    if source.nextObjectSerial ~= nil then
        local value = source.nextObjectSerial
        if not finiteNumber(value) or value < 1 or value ~= math.floor(value) then
            return restoreFailure("$.baseLife.nextObjectSerial", "expected positive integer")
        end
    end
    for id, base in pairs(source.bases) do
        if type(id) ~= "string" then
            return restoreFailure("$.baseLife.bases[" .. tostring(id) .. "]", "non-string key")
        end
        local okay, reason = validBaseSource(base, id,
            "$.baseLife.bases[" .. id .. "]")
        if not okay then return false, reason end
    end
    if source.activeBaseId ~= nil and (type(source.activeBaseId) ~= "string"
        or source.bases[source.activeBaseId] == nil) then
        return restoreFailure("$.baseLife.activeBaseId", "unknown base reference")
    end
    for id, resident in pairs(source.residents) do
        local path = "$.baseLife.residents[" .. tostring(id) .. "]"
        if type(id) ~= "string" or id == "" or type(resident) ~= "table" then
            return restoreFailure(path, "invalid resident")
        end
        if type(resident.baseId) ~= "string" or source.bases[resident.baseId] == nil then
            return restoreFailure(path .. ".baseId", "unknown base reference")
        end
        if not BaseLife.ROLES[resident.role] then
            return restoreFailure(path .. ".role", "invalid resident role")
        end
        if type(resident.duty) ~= "boolean" then
            return restoreFailure(path .. ".duty", "expected boolean")
        end
    end
    for id, restriction in pairs(source.restrictions) do
        local path = "$.baseLife.restrictions[" .. tostring(id) .. "]"
        if type(id) ~= "string" or id == ""
            or (restriction ~= "watch" and restriction ~= "quarantine") then
            return restoreFailure(path, "invalid restriction")
        end
    end
    local okay, countOrReason = validRecordArray(source.history, "$.baseLife.history",
        configuredLimit("baseHistoryLimit", 96))
    if not okay then return false, countOrReason end
    for index = 1, countOrReason do
        local rowCopy, rowReason = stableCopy(source.history[index], 3, { count = 64 })
        if rowCopy == nil then
            return restoreFailure("$.baseLife.history[" .. tostring(index) .. "]",
                rowReason or "invalid history record")
        end
    end
    return true
end

function BaseLife.restore(source)
    if source == nil then
        document, draftZone, operationsCache = emptyDocument(), nil, nil
        return true, document
    end
    local stable, reason = stableCopy(source, 24, { count = 65536 })
    if stable == nil then return restoreFailure("$.baseLife", reason or "copy failed") end
    local valid, validationReason = validateRestoreSource(stable)
    if not valid then return false, validationReason end
    local normalized, candidate = pcall(normalize, stable)
    if not normalized or type(candidate) ~= "table" then
        return restoreFailure("$.baseLife", normalized and "normalization failed" or candidate)
    end
    document = candidate
    draftZone, operationsCache = nil, nil
    bumpWorkConsistencyRevision()
    return true, document
end

function BaseLife.reset()
    document, draftZone, operationsCache = emptyDocument(), nil, nil
    bumpWorkConsistencyRevision()
end

BaseLife.reset()

return BaseLife
