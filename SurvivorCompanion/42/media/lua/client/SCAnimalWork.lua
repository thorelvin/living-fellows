-- SPDX-License-Identifier: MIT
-- Native chicken work participates only through SCFarmWork's existing lane.
local SC = SurvivorCompanion
SC.AnimalWork = SC.AnimalWork or {}
local A = SC.AnimalWork
local scan, zoneCursor, knownBase, lastAudit = nil, 0, nil, -math.huge
local snapshots, claims = {}, {}
local refreshes = {}

A.species = {
    chicken = { kinds = { hen = true, cockerel = true, chick = true },
        feeds = { AnimalFeed = true, Grass = true, Hay = true, Vegetables = true,
            Fruits = true, Seeds = true, Nuts = true, Nut = true, Insect = true },
        hutch = "hutchhen", dawn = 7, dusk = 20 },
}

local function U() return SC.GameplayUtil end
local function C(key, fallback)
    local value = tonumber(U().config(key))
    return value and value == value and value or fallback
end
local function read(object, method, ...) return U().call(object, method, ...) end
local function value(object, method, ...)
    local result = read(object, method, ...)
    return result
end
local function n(object, method, ...) return tonumber(value(object, method, ...)) end
local function size(list) return SC.NativeList.size(list) end
local function at(list, i) return select(1, SC.NativeList.get(list, i)) end
local function now() return U().nowMs() end
local function support() return SC.FarmWork.animalSupport end
local function key(object)
    local x, y, z = U().position(object)
    if not x or not y or not z then return nil end
    return math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z)
end
local function time()
    if type(getGameTime) ~= "function" then return nil, nil end
    local okay, gt = pcall(getGameTime)
    if not okay then return nil, nil end
    return n(gt, "getTimeOfDay"), n(gt, "getWorldAgeHours")
end
local function enabled() return C("animalWorkEnabled", 1) == 1 end
local function document()
    return SC.BaseLife and SC.BaseLife.animalDocument and SC.BaseLife.animalDocument() or nil
end
local function note()
    if SC.BaseLife.noteWorkOwnershipMutation then SC.BaseLife.noteWorkOwnershipMutation() end
end

local function coverageStamp(base)
    local parts = {}
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" then
            parts[#parts + 1] = table.concat({ tostring(zone.id), zone.x1, zone.y1,
                zone.x2, zone.y2, zone.z }, ":")
        end
    end
    return table.concat(parts, "|")
end

local function workDay(object)
    local hour = time()
    return SC.BaseLife.isOutdoorSquare(U().squareOf(object)) ~= true
        or (SC.BaseLife.policies() or {}).workOutsideAtNight == true
        or hour ~= nil and hour >= A.species.chicken.dawn and hour < A.species.chicken.dusk
end

function A.isFeed(item)
    return item ~= nil and A.species.chicken.feeds[value(item, "getAnimalFeedType")] == true
        and value(item, "isRotten") ~= true
end

function A.feedAmount(item)
    if not A.isFeed(item) then return nil end
    local uses = n(item, "getCurrentUses")
    if uses then return math.max(0, uses * 0.1) end
    local hunger = n(item, "getHungerChange")
    return hunger and math.abs(hunger) or nil
end

-- Stable choice within one game-minute bucket, including after save/load.
function A.choose(actorId, crop, animal)
    if not crop then return animal end
    if not animal then return crop end
    local _, hours = time()
    if hours == nil then return crop end
    return U().stableHash(tostring(actorId) .. ":farm:" .. math.floor(hours * 60)) % 2 == 0
        and animal or crop
end

local function zoneFacts(zone)
    local x, y, z, w, h = n(zone, "getX"), n(zone, "getY"), n(zone, "getZ"),
        n(zone, "getW"), n(zone, "getH")
    local id = value(zone, "getId")
    if not id or not x or not y or not z or not w or not h
        or w < 1 or h < 1 or w * h > 256 then return nil end
    return { id = tostring(id), native = zone, x1 = x, y1 = y, z = z,
        x2 = x + w - 1, y2 = y + h - 1, width = w, total = w * h,
        index = 0, animals = {}, seen = {}, hutches = {}, troughs = {},
        hutchIndex = 0, complete = true, capacity = 0, hens = 0, roosters = 0, chicks = 0 }
end

local function contains(row, object)
    local x, y, z = U().position(object)
    return x and z == row.z and x >= row.x1 and x < row.x2 + 1
        and y >= row.y1 and y < row.y2 + 1
end

local function inspectAnimal(row, animal)
    local id = n(animal, "getAnimalID")
    if not id or id < 0 then row.complete = false return end
    if row.seen[id] then return end
    row.seen[id] = true
    if #row.animals >= 128 then row.complete = false return end
    local kind = value(animal, "getAnimalType")
    if not A.species.chicken.kinds[kind] then row.mixed = true return end
    local data, ok = read(animal, "getModData")
    if not ok or type(data) ~= "table" then row.complete = false return end
    if data.lfOddballGroupId or data.lfWendellGroupId then row.protected = true end
    if (n(animal, "getHealth") or 0) <= 0 then return end
    local baby, babyOkay = read(animal, "isBaby")
    local name, nameOkay = read(animal, "getCustomName")
    local held, heldOkay = read(animal, "isHeld")
    local age = n(animal, "getAge")
    local animalData = value(animal, "getData")
    local female, femaleOkay = read(animalData, "isFemale")
    if not babyOkay or not nameOkay or not heldOkay or not femaleOkay or not age then
        row.complete = false
    end
    row.animals[#row.animals + 1] = { id = id, kind = kind, baby = baby == true,
        name = name, held = held, age = age, female = female,
        oddball = data.lfOddballGroupId ~= nil or data.lfWendellGroupId ~= nil }
    if baby == true then row.chicks = row.chicks + 1
    elseif female == true then row.hens = row.hens + 1
    else row.roosters = row.roosters + 1 end
end

local function allowedBudget(kind, count)
    if SC.Performance and SC.Performance.claimUnits then
        return SC.Performance.claimUnits(kind, count)
    end
    return count
end
local function outOfTime(start)
    local remaining = SC.Performance and SC.Performance.remainingBudgetMs()
    return SC.Performance and (SC.Performance.preciseNowMs() - start >= 1.5
        or remaining ~= nil and remaining <= 0)
end

-- No whole-world animal census. Rectangle coverage, square animals and hutch
-- occupants each resume their own cursor; unknown evidence is never absence.
local function advance(row)
    local start = SC.Performance and SC.Performance.preciseNowMs() or 0
    local squares = allowedBudget("scavengeSquares", 16)
    local animalBudget = math.min(32, math.max(1, C("animalAuditAnimalBudget", 32)))
    while row.index < row.total and squares > 0 and animalBudget > 0 do
        if outOfTime(start) then return false end
        local x = row.x1 + row.index % row.width
        local y = row.y1 + math.floor(row.index / row.width)
        if SC.BaseLife.isInside({ x = x, y = y, z = row.z }) ~= true then
            row.rejected = true return true
        end
        local square = U().gridSquare(x, y, row.z)
        if not square then row.complete = false end
        local animals, available = read(square, "getAnimals")
        if square and not available then row.complete = false end
        local count = size(animals)
        row.animalIndex = row.animalIndex or 0
        while row.animalIndex < count and animalBudget > 0 do
            inspectAnimal(row, at(animals, row.animalIndex))
            row.animalIndex, animalBudget = row.animalIndex + 1, animalBudget - 1
        end
        if row.animalIndex < count then return false end
        row.index, row.animalIndex, squares = row.index + 1, nil, squares - 1
    end
    if row.index < row.total then return false end
    if not row.objectsRead then
        if value(row.native, "isFullyStreamed") ~= true then row.complete = false end
        for _, spec in ipairs({ { "getHutchs", row.hutches }, { "getTroughs", row.troughs } }) do
            local objects, okay = read(row.native, spec[1])
            if not okay or size(objects) > 8 then row.complete = false return true end
            local seen = {}
            for i = 0, size(objects) - 1 do
                local object = at(objects, i)
                if spec[1] == "getHutchs" then object = value(object, "getHutch") end
                if object and not seen[object] and contains(row, object) then
                    spec[2][#spec[2] + 1], seen[object] = object, true
                end
            end
        end
        row.objectsRead = true
    end
    while row.hutchIndex < #row.hutches and animalBudget > 0 do
        if outOfTime(start) then return false end
        local hutch = row.hutches[row.hutchIndex + 1]
        if not row.iterator then
            if hutch.type ~= A.species.chicken.hutch then row.mixed = true end
            local capacity = n(hutch, "getMaxAnimals")
            if not capacity then row.complete = false return true end
            row.capacity = row.capacity + capacity
            local occupants = value(hutch, "getAnimalInside")
            local values = value(occupants, "values")
            row.iterator = value(values, "iterator")
            if row.iterator == nil then row.complete = false return true end
        end
        while value(row.iterator, "hasNext") == true and animalBudget > 0 do
            inspectAnimal(row, value(row.iterator, "next"))
            animalBudget = animalBudget - 1
        end
        local more, okay = read(row.iterator, "hasNext")
        if not okay then row.complete = false return true end
        if more == true then return false end
        row.iterator, row.hutchIndex = nil, row.hutchIndex + 1
    end
    return row.hutchIndex >= #row.hutches
end

local function openJob(base, object)
    local targetKey = key(object)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "farm" and job.target and job.target.animal
            and job.target.deviceKey == targetKey
            and job.state ~= "completed" and job.state ~= "cancelled" then return true end
    end
    return false
end

local function candidateAt(row, operation, object, priority)
    local x, y, z = U().position(object)
    return { animal = true, operation = operation, priority = priority or 4,
        zoneId = "animal:" .. row.id, nativeZoneId = row.id,
        deviceKey = key(object), x = math.floor(x), y = math.floor(y), z = z }
end

local function deviceCandidate(row, base)
    local low, high = C("animalFeedLowPercent", 25) / 100,
        C("animalFeedHighPercent", 90) / 100
    local best
    for _, trough in ipairs(row.troughs) do
        if not openJob(base, trough) and workDay(trough) then
            local water, capacity = n(trough, "getWater"), n(trough, "getMaxWater")
            if water and capacity and capacity > 0 and water < capacity * low then
                local result = candidateAt(row, "animal_water", trough, 5)
                result.high = capacity * high
                return result
            end
            local container = value(trough, "getContainer")
            local items = value(container, "getItems")
            if container and size(items) <= 64 then
                local feed, maxFeed = n(trough, "getCurrentFeedAmount"), n(trough, "getMaxFeed")
                if feed and maxFeed and maxFeed > 0 and feed < maxFeed * low and not best then
                    best = candidateAt(row, "animal_feed", trough)
                    best.high = maxFeed * high
                end
            end
        end
    end
    return best
end

function A.candidate(base)
    if not enabled() or not document() then return nil end
    if base ~= knownBase then A.reset() knownBase = base end
    if now() - lastAudit < 250 then return nil end
    lastAudit = now()
    if not scan then
        if not DesignationZoneAnimal or not DesignationZoneAnimal.getAllZones then return nil end
        local okay, zones = pcall(DesignationZoneAnimal.getAllZones)
        if not okay or size(zones) == 0 then return nil end
        zoneCursor = zoneCursor % size(zones)
        scan = zoneFacts(at(zones, zoneCursor))
        zoneCursor = zoneCursor + 1
        if not scan then return nil end
    end
    if not advance(scan) then return nil end
    local row = scan
    scan = nil
    if row.rejected or not row.complete or row.protected or row.mixed
        or #row.animals == 0 then snapshots[row.id] = nil return nil end
    row.auditedAt, row.coverageStamp = now(), coverageStamp(base)
    snapshots[row.id] = row
    local doc = document()
    local count, oldest, oldestAt = 0, nil, math.huge
    for id, saved in pairs(doc.zones) do
        count = count + 1
        if (tonumber(saved.auditedAt) or 0) < oldestAt then
            oldest, oldestAt = id, tonumber(saved.auditedAt) or 0
        end
    end
    if not doc.zones[row.id] and count >= math.min(8, C("animalMaxZones", 8)) then
        doc.zones[oldest], snapshots[oldest] = nil, nil
    end
    local saved = doc.zones[row.id] or { cooldowns = {} }
    saved.hens, saved.roosters, saved.chicks = row.hens, row.roosters, row.chicks
    saved.capacity, saved.auditedAt = row.capacity, row.auditedAt
    saved.cooldowns = type(saved.cooldowns) == "table" and saved.cooldowns or {}
    doc.zones[row.id] = saved
    note()
    local selected = deviceCandidate(row, base)
    if selected then
        local cooldown = saved.cooldowns[selected.deviceKey]
        if cooldown and (cooldown.untilMs > now()
            or cooldown.failures >= 3 and now() - cooldown.at < 60000) then return nil end
    end
    return selected
end

local function findDevice(target)
    local row = snapshots[target.nativeZoneId]
    local base = SC.BaseLife.active()
    if not row or now() - row.auditedAt > 30000 or row.coverageStamp ~= coverageStamp(base)
        or value(row.native, "isFullyStreamed") ~= true then
        if not DesignationZoneAnimal or not DesignationZoneAnimal.getZoneById then
            return nil, "animal_audit_pending"
        end
        local okay, zone = pcall(DesignationZoneAnimal.getZoneById, tonumber(target.nativeZoneId))
        if not okay or not zone then return nil, "animal_zone_missing" end
        local pending = refreshes[target.nativeZoneId] or zoneFacts(zone)
        if not pending then return nil, "animal_zone_unavailable" end
        refreshes[target.nativeZoneId] = pending
        if not advance(pending) then return nil, "animal_audit_pending" end
        refreshes[target.nativeZoneId] = nil
        if pending.rejected or not pending.complete or pending.protected or pending.mixed then
            snapshots[target.nativeZoneId] = nil
            return nil, "animal_zone_unavailable"
        end
        pending.auditedAt, pending.coverageStamp = now(), coverageStamp(base)
        snapshots[target.nativeZoneId], row = pending, pending
    end
    for _, list in ipairs({ row.troughs, row.hutches }) do
        for _, object in ipairs(list) do
            if key(object) == target.deviceKey and U().squareOf(object)
                and contains(row, object) and SC.BaseLife.isInside(object) == true then return object, row end
        end
    end
    return nil, "animal_device_unavailable"
end

local function claim(actor, job)
    local target, current = job.target, now()
    local id, active = U().idOf(actor), 0
    for k, held in pairs(claims) do
        if held.expires <= current then claims[k] = nil
        elseif held.zone == target.nativeZoneId and held.actor ~= id then active = active + 1 end
    end
    local held = claims[target.deviceKey]
    if held and (held.actor ~= id or held.job ~= job.id) or active >= 2 then return false end
    claims[target.deviceKey] = { actor = id, job = job.id,
        zone = target.nativeZoneId, expires = current + 30000 }
    return true
end

local function release(actor, job)
    local held = claims[job.target.deviceKey]
    if held and held.actor == U().idOf(actor) and held.job == job.id then
        claims[job.target.deviceKey] = nil
    end
end

local function fail(actor, job, reason)
    local doc = document()
    local saved = doc and doc.zones[job.target.nativeZoneId]
    if saved then
        local old = saved.cooldowns[job.target.deviceKey] or { failures = 0 }
        old.failures = math.min(3, old.failures + 1)
        old.at, old.untilMs = now(), now() + 15000 * 2 ^ (old.failures - 1)
        saved.cooldowns[job.target.deviceKey] = old
        note()
    end
    release(actor, job)
    return false, reason, true
end

function A.borrowWasConsumed(receipt)
    local job = SC.BaseLife.job(receipt.jobId)
    if not job or not job.target or job.target.operation ~= "animal_feed" then return false end
    local object = findDevice(job.target)
    local container = object and value(object, "getContainer")
    local items = value(container, "getItems")
    if not container or size(items) > 64 then return false end
    for i = 0, size(items) - 1 do
        local item = at(items, i)
        local data = U().modData(item)
        if data and data[SC.FarmWork.ITEM_MARKER] == receipt.id
            and value(item, "getContainer") == container
            and value(container, "contains", item) == true then
            support().unmark(item, receipt.id)
            return true
        end
    end
    return false
end

function A.canUse(actor, job, object, item)
    local held = claims[job.target.deviceKey]
    local current = findDevice(job.target)
    if not enabled() or U().isDead(actor) or current ~= object
        or not held or held.actor ~= U().idOf(actor) or held.job ~= job.id
        or held.expires <= now() or support().threat(actor) then return false end
    if not workDay(object) then return false end
    local resident = SC.BaseLife.resident(U().idOf(actor))
    if not resident or resident.role ~= "farmer" or resident.duty ~= true then return false end
    if item and not U().inventoryContains(U().inventory(actor), item) then return false end
    return SC.BaseLife.job(job.id) == job
end

local function begin(actor, job, state, object, item, operation)
    local supervisor = SC.ActionSupervisor
    local token, reason = supervisor.begin(actor, { owner = "work",
        action = "farm_" .. operation, targetKey = job.id, targetLabel = "chicken pen",
        priority = supervisor.Priority.WORK, ignoreRetry = true, interruptible = true })
    if not token then return false, reason end
    if SC.Navigation then SC.Navigation.cancel(actor, "animal_interaction") end
    local stopped, stopReason = SC.NativeActions.stopDirect(actor)
    if not stopped then supervisor.fail(token, stopReason) return false, stopReason end
    supervisor.transition(token, "committing")
    local before = operation == "animal_water" and n(object, "getWater")
        or operation == "fill_water" and support().waterUses(item)
        or n(object, "getCurrentFeedAmount")
    local started, detail = supervisor.commit(token, function()
        if operation == "fill_water" then
            return SC.NativeActions.startFarm(actor, { operation = "fill_water",
                item = item, object = object })
        end
        return SC.NativeActions.startAnimal(actor, { operation = operation, item = item,
            object = object, high = job.target.high,
            validate = function() return A.canUse(actor, job, object, item) end })
    end)
    if not started then supervisor.fail(token, detail) return false, detail end
    supervisor.transition(token, "verifying")
    supervisor.complete(token, "animal_native_started")
    state.animalWork = { operation = operation, before = before, startedAt = now(),
        object = object, item = item }
    return true, "farm_" .. operation .. "_active"
end

local function reconcileFeed(job, state)
    if not state.borrowed then return true end
    local receipt = SC.BaseLife.farmReceipt(state.borrowed.receiptId)
    if receipt and A.borrowWasConsumed(receipt) then
        SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "consumed", blocker = false })
        state.borrowed = nil
    end
    return true
end

function A.cancel(actor, job, state, reason)
    if state.animalWork then
        local stopped, detail = SC.NativeActions.cancelWork(actor, reason or "animal_cancelled")
        if not stopped then return false, detail end
        reconcileFeed(job, state)
        state.animalWork = nil
    end
    release(actor, job)
    return true
end

function A.update(actor, baseState, job, runtime, state)
    local target, S = job.target, support()
    local object, row = findDevice(target)
    if not object then
        if row ~= "animal_audit_pending" then return fail(actor, job, row) end
        return true, row
    end -- bounded audit re-establishes native references after load
    if not claim(actor, job) then return true, "animal_work_reserved" end
    if not enabled() or S.threat(actor, runtime) then
        local okay, reason = A.cancel(actor, job, state, "animal_work_interrupted")
        if not okay then return false, reason end
        state.animalReturn = true
    end
    if state.animalWork then
        local work = state.animalWork
        if SC.NativeActions.isWorkActive(actor) then
            if now() - work.startedAt > 120000 then
                A.cancel(actor, job, state, "animal_action_timeout")
                return fail(actor, job, "animal_action_timeout")
            end
            return true, "farm_" .. work.operation .. "_active"
        end
        local finished, detail = SC.NativeActions.finishWork(actor)
        if not finished then return fail(actor, job, detail) end
        reconcileFeed(job, state)
        local verified = work.operation == "animal_feed" and not state.borrowed
            or work.operation == "animal_water" and (n(object, "getWater") or -1) > work.before
            or work.operation == "fill_water" and S.waterUses(work.item) > work.before
        state.animalWork = nil
        if not verified then return fail(actor, job, "animal_action_incomplete") end
        if work.operation == "fill_water" then return true, "animal_water_container_filled" end
        local amount = target.operation == "animal_water" and n(object, "getWater")
            or n(object, "getCurrentFeedAmount")
        state.animalReturn = amount ~= nil and amount >= target.high
    end
    if state.animalReturn then
        local settled, reason, pending = S.settle(actor, baseState, state)
        if not settled then return pending == true, reason end
        release(actor, job)
        SC.BaseLife.completeJob(job.id, U().idOf(actor), "chicken_care")
        return true, "farm_job_complete"
    end
    local supply = state.borrowed or state.carriedWaterSupply
    if not supply then
        local predicate = target.operation == "animal_water" and S.waterPredicate
            or function(item)
                local amount = A.feedAmount(item)
                local current = n(object, "getCurrentFeedAmount")
                return amount and amount > 0 and current and current + amount <= target.high
            end
        return S.borrow(actor, baseState, job, state, predicate,
            target.operation == "animal_water" and { "farming", "water" } or { "farming" },
            target.operation == "animal_water" and "water" or "chicken_feed")
    end
    if not A.canUse(actor, job, object, supply.item) then
        return fail(actor, job, "animal_care_unavailable")
    end
    if target.operation == "animal_water" and S.waterUses(supply.item) <= 0 then
        local source, reason = S.findWater(actor, state, row)
        if not source then return reason == "water_source_scanning", reason, reason ~= "water_source_scanning" end
        local status, detail = S.approach(actor, U().squareOf(source), source)
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        return begin(actor, job, state, source, supply.item, "fill_water")
    end
    local status, detail = S.approach(actor, U().squareOf(object), object)
    if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
    return begin(actor, job, state, object, supply.item, target.operation)
end

function A.reset(actor)
    if actor then
        for k, held in pairs(claims) do if held.actor == U().idOf(actor) then claims[k] = nil end end
    else
        scan, snapshots, claims, refreshes = nil, {}, {}, {}
        knownBase, zoneCursor, lastAudit = nil, 0, -math.huge
    end
end

return A
