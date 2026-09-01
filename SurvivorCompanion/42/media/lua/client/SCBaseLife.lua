-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end

SC.BaseLife = SC.BaseLife or {}
local BaseLife = SC.BaseLife

BaseLife.VERSION = 1
BaseLife.ROLES = {
    generalist = true, guard = true, builder = true, quartermaster = true, medic = true,
}
BaseLife.ZONE_TYPES = {
    area = true, work = true, rest = true, social = true, guard = true,
    rally = true, quarantine = true,
}
BaseLife.STORAGE_CATEGORIES = {
    food = true, water = true, medical = true, tools = true, construction = true,
    crafting = true, weapons = true, ammunition = true, general = true,
    output = true, memorial = true,
}
BaseLife.JOB_TYPES = {
    haul = true, sort = true, fetch = true, repair = true, replace_bandage = true,
    craft_supply = true, barricade = true, maintain = true, build = true,
}

local JOB_STATES = {
    pending = true, reserved = true, active = true, blocked = true,
    completed = true, cancelled = true,
}
local roleAffinity = {
    generalist = { haul = 4, sort = 4, fetch = 4, repair = 3, replace_bandage = 2,
        craft_supply = 3, barricade = 2, maintain = 2, build = 2 },
    guard = { barricade = 4, maintain = 2, haul = 1, fetch = 1 },
    builder = { build = 10, barricade = 9, maintain = 8, repair = 5, fetch = 3 },
    quartermaster = { haul = 10, sort = 10, fetch = 9, craft_supply = 4 },
    medic = { replace_bandage = 10, fetch = 5, haul = 1 },
}

local document
local draftZone
local operationsCache

local DEFENSE_POLICIES = { rotation = true, role_based = true, all_hands = true }
local WORKLOAD_POLICIES = { essential = true, balanced = true, continuous = true }
local defaultStockTargets = {
    food = 3, water = 2, medical = 1, construction = 2, ammunition = 6,
}

local function U()
    return SC.GameplayUtil
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
        nextJobSerial = 1,
        bases = {},
        residents = {},
        restrictions = {},
        history = {},
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
    local point = normalizePoint(source)
    local objectIndex = integer(source.objectIndex, -1)
    if not point or objectIndex < 0 then return nil end
    local reserves = {}
    local count = 0
    for itemType, amount in pairs(type(source.reserves) == "table" and source.reserves or {}) do
        if type(itemType) == "string" and itemType ~= "" and count < 64 then
            reserves[cleanText(itemType, "", 96)] = integer(amount, 0, 0, 9999)
            count = count + 1
        end
    end
    return {
        id = source.id, x = point.x, y = point.y, z = point.z,
        objectIndex = objectIndex, category = source.category,
        reserve = integer(source.reserve, 0, 0, 9999), reserves = reserves,
        withdrawals = source.withdrawals ~= false, deposits = source.deposits ~= false,
        createdAt = math.max(0, finite(source.createdAt, 0)),
    }
end

local function normalizeTarget(source)
    if type(source) ~= "table" or not validId(source.id, "target:") then return nil end
    local point = normalizePoint(source)
    local objectIndex = integer(source.objectIndex, -1)
    if not point or objectIndex < 0 then return nil end
    local kind = source.kind == "barricade" and "barricade" or "maintain"
    return {
        id = source.id, kind = kind, x = point.x, y = point.y, z = point.z,
        objectIndex = objectIndex, threshold = integer(source.threshold, 65, 1, 100),
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
    return result
end

local function normalize(source)
    local result = emptyDocument()
    if type(source) ~= "table" or tonumber(source.version) ~= BaseLife.VERSION then return result end
    result.nextBaseSerial = integer(source.nextBaseSerial, 1, 1, 999999)
    result.nextZoneSerial = integer(source.nextZoneSerial, 1, 1, 999999)
    result.nextStorageSerial = integer(source.nextStorageSerial, 1, 1, 999999)
    result.nextTargetSerial = integer(source.nextTargetSerial, 1, 1, 999999)
    result.nextJobSerial = integer(source.nextJobSerial, 1, 1, 999999)
    for id, candidate in pairs(type(source.bases) == "table" and source.bases or {}) do
        local base = normalizeBase(candidate)
        if base and id == base.id then result.bases[id] = base end
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

local function activeBase()
    local state = ensure()
    return state.activeBaseId and state.bases[state.activeBaseId] or nil
end

local function zoneContains(zone, point)
    return type(zone) == "table" and type(point) == "table" and zone.z == point.z
        and point.x >= zone.x1 and point.x <= zone.x2
        and point.y >= zone.y1 and point.y <= zone.y2
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
    if zone.kind ~= "area" then
        local corners = {
            { x = zone.x1, y = zone.y1, z = zone.z }, { x = zone.x2, y = zone.y1, z = zone.z },
            { x = zone.x1, y = zone.y2, z = zone.z }, { x = zone.x2, y = zone.y2, z = zone.z },
        }
        for _, corner in ipairs(corners) do
            local inside = false
            for _, area in ipairs(base.zones) do
                if area.kind == "area" and zoneContains(area, corner) then inside = true break end
            end
            if not inside then return false, "zone_outside_base_area" end
        end
    end
    base.zones[#base.zones + 1] = zone
    draftZone = nil
    return true, zone
end

function BaseLife.removeZone(id)
    local base = activeBase()
    local _, index = base and findById(base.zones, id) or nil
    if not index then return false, "unknown_zone" end
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

local function objectDescriptor(object)
    local point = position(object)
    local utility = U()
    local index, ok
    if utility then index, ok = utility.call(object, "getObjectIndex") end
    if not point or not ok or finite(index, nil) == nil or tonumber(index) < 0 then
        return nil
    end
    return { x = point.x, y = point.y, z = point.z, objectIndex = integer(index, -1) }
end

function BaseLife.resolveObject(record)
    if type(record) ~= "table" then return nil end
    local utility = U()
    local square = utility and utility.gridSquare(record.x, record.y, record.z) or nil
    if not square then return nil end
    local found
    utility.squareObjects(square, function(object)
        local index, ok = utility.call(object, "getObjectIndex")
        if ok and integer(index, -2) == integer(record.objectIndex, -1) then
            found = object
            return false
        end
    end, 64)
    return found
end

function BaseLife.registerStorage(object, category)
    if not BaseLife.STORAGE_CATEGORIES[category] then return false, "invalid_storage_category" end
    local base = activeBase()
    local descriptor = objectDescriptor(object)
    if not base or not descriptor or not BaseLife.isInside(descriptor) then
        return false, base and "storage_outside_base" or "base_missing"
    end
    local container, ok = U().call(object, "getContainer")
    if not ok or not container then return false, "object_has_no_container" end
    for _, storage in ipairs(base.storages) do
        if storage.x == descriptor.x and storage.y == descriptor.y and storage.z == descriptor.z
            and storage.objectIndex == descriptor.objectIndex then
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
    local _, index = base and findById(base.storages, id) or nil
    if not index then return false, "unknown_storage" end
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

function BaseLife.resolveContainer(storage)
    local object = BaseLife.resolveObject(storage)
    if not object then return nil, nil end
    local container, ok = U().call(object, "getContainer")
    return ok and container or nil, object
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
    local base, descriptor = activeBase(), objectDescriptor(object)
    if not base or not descriptor or not BaseLife.isInside(descriptor) then
        return false, base and "target_outside_base" or "base_missing"
    end
    kind = kind == "barricade" and "barricade" or "maintain"
    for _, row in ipairs(base.maintenanceTargets) do
        if row.x == descriptor.x and row.y == descriptor.y and row.z == descriptor.z
            and row.objectIndex == descriptor.objectIndex then
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

local function jobScore(actorId, job)
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
    job.state, job.reservedBy, job.leaseUntil = "cancelled", nil, 0
    job.updatedAt = now()
    table.remove(base.jobs, index)
    return true, job
end

function BaseLife.retryJob(id)
    local job = BaseLife.job(id)
    if not job then return false, "unknown_job" end
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
        rows = {}, storageRows = {}, residentRows = {}, history = {}, operations = operations,
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
                x = storage.x, y = storage.y, z = storage.z,
            }
        end
    end
    for _, row in ipairs(ensure().history) do
        result.history[#result.history + 1] = stableCopy(row, 3, { count = 64 })
    end
    return result
end

function BaseLife.export()
    return stableCopy(ensure(), 7, { count = 8192 })
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
    local stable, reason = stableCopy(source, 12, { count = 8192 })
    if stable == nil then return restoreFailure("$.baseLife", reason or "copy failed") end
    local valid, validationReason = validateRestoreSource(stable)
    if not valid then return false, validationReason end
    local normalized, candidate = pcall(normalize, stable)
    if not normalized or type(candidate) ~= "table" then
        return restoreFailure("$.baseLife", normalized and "normalization failed" or candidate)
    end
    document = candidate
    draftZone, operationsCache = nil, nil
    return true, document
end

function BaseLife.reset()
    document, draftZone, operationsCache = emptyDocument(), nil, nil
end

BaseLife.reset()

return BaseLife
