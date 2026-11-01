-- SPDX-License-Identifier: MIT
-- Controlled job-controller acceptance in disposable saves. BaseWork, navigation,
-- storage ownership and native timed actions are real; unrelated AI decisions
-- are held so legacy loadouts/jobs cannot consume the fixture's test supplies.
local Probe = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCCleaningMixturesProbe = Probe
local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...) return object[method](object, ...) end, ...)
    if okay then return value end
end
local function amount(item) return tonumber(call(call(item, "getFluidContainer"), "getAmount")) or 0 end
local function near(a, b) return math.abs(a - b) < 0.002 end
local function stash(SC, container, holder, predicate)
    for _, item in ipairs(SC.GameplayUtil.inventoryItems(container, 4096)) do
        if not predicate or predicate(item) then
            if SC.GameplayUtil.transferItemVerified(container, holder, item) ~= true then return false end
        end
    end
    return true
end
local function add(container, kind, fluids)
    local item = container:AddItem(kind)
    local fc = call(item, "getFluidContainer")
    if fc and fluids then
        fc:Empty()
        for name, litres in pairs(fluids) do fc:addFluid(Fluid[name], litres) end
    end
    return item
end
local function stain(square)
    local okay = pcall(addBloodSplat, square, 20)
    return okay and call(square, "haveStains") == true
end
local function besideWater(SC, actor, base)
    local U, inspected = SC.GameplayUtil, 0
    for _, zone in ipairs(base.zones) do
        if zone.kind == "area" then
            for x = zone.x1, zone.x2 do
                for y = zone.y1, zone.y2 do
                    inspected = inspected + 1
                    if inspected > 4000 then return nil end
                    local square = U.gridSquare(x, y, zone.z)
                    local chosen
                    if square then U.squareObjects(square, function(source)
                        if not SC.CleaningSupplies.sourceUsable(source) then return true end
                        local _, access = U.directInteractionAccess(actor, source)
                        for _, standing in ipairs(access or {}) do
                            if U.isSquareFree(standing) and not U.squareOccupyingObject(standing)
                                and SC.BaseLife.isInside(standing) then
                                for dx = -1, 1 do
                                    for dy = -1, 1 do
                                        local nearby = U.gridSquare(x + dx, y + dy, zone.z)
                                        if nearby then U.squareObjects(nearby, function(object)
                                            local container = call(object, "getContainer")
                                            if not container then return true end
                                            local _, sides = U.directInteractionAccess(actor, object)
                                            for _, side in ipairs(sides or {}) do
                                                if U.sameSquare(side, standing) then
                                                    local okay, storage = SC.BaseLife.registerStorage(object, "tools")
                                                    if okay then
                                                        chosen = { storage = storage, container = container,
                                                            square = standing, source = source }
                                                        return false
                                                    end
                                                end
                                            end
                                            return true
                                        end, 24) end
                                        if chosen then return false end
                                    end
                                end
                            end
                        end
                        return true
                    end, 24) end
                    if chosen then return chosen end
                end
            end
        end
    end
end
local function fixture(H, check, result)
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local base = SC.BaseLife.active()
    if not base then return nil end
    local record, leastLoad
    for _, row in ipairs(SC.Registry.snapshot()) do
        if row.recruited and row.actor and not U.isDead(row.actor) and U.squareOf(row.actor) then
            local _, _, ratio = U.carryLoad(row.actor)
            if leastLoad == nil or ratio < leastLoad then record, leastLoad = row, ratio end
        end
    end
    if not record then return nil end
    local actor = record.actor
    for _, row in ipairs(SC.Registry.snapshot()) do
        if row.recruited and row.actor then
            SC.BaseWork.cancel(row.actor, "cleaning_fixture")
            SC.Decision.cancelWork(row.actor, "cleaning_fixture")
            SC.Commands.issue(row.id, "stay", {}, H.player)
        end
    end
    base.settings.autoMaintenance, base.settings.routines, base.settings.workload = false, false, "essential"
    for index = #base.jobs, 1, -1 do
        local job = base.jobs[index]
        if job then SC.BaseLife.cancelJob(job.id) end
    end
    local selected = besideWater(SC, actor, base)
    for _, row in ipairs(selected and {} or SC.BaseLife.storageRows(nil, true)) do
        local object = SC.BaseLife.resolveObject(row)
        local container = SC.BaseLife.resolveContainer(row)
        local at, squares = U.directInteractionAccess(actor, object)
        if container and row.z == 0 then
            for _, square in ipairs(squares or {}) do
                if U.isSquareFree(square) and not U.squareOccupyingObject(square)
                    and SC.BaseLife.isInside(square) then
                    selected = { storage = row, container = container, square = square }
                    break
                end
            end
        end
        if selected then break end
    end
    if not check("cleaning_fixture_storage", selected ~= nil, "needs accessible registered storage") then return false end
    for _, row in ipairs(base.storages) do row.withdrawals = row == selected.storage end
    local holder = instanceItem("Base.Bag_DuffelBag")
    if not holder then holder = instanceItem("Base.Bag_Schoolbag") end
    if not check("cleaning_fixture_holder", holder ~= nil and holder:getInventory() ~= nil,
        "preserve original items in a native bag") then return false end
    selected.holder, selected.actor, selected.record = holder, actor, record
    actor:setPrimaryHandItem(nil)
    actor:setSecondaryHandItem(nil)
    check("cleaning_fixture_sequestered", stash(SC, selected.container, holder:getInventory())
        and stash(SC, actor:getInventory(), holder:getInventory(), function(item)
            return call(actor, "isEquippedClothing", item) ~= true
        end), "source save untouched; exact pre-existing items retained")
    local placed = H.placeCombatActor(actor, { x = selected.square:getX() + 0.5,
        y = selected.square:getY() + 0.5, z = selected.square:getZ() })
    check("cleaning_fixture_placed", placed == true, "staged once before timed work")
    selected.tool = selected.container:AddItem("Base.Mop")
    selected.index, selected.cleaned = 0, 0
    SC.BaseLife.assign(record.id, "maintainer", true)
    SC.Commands.issue(record.id, "base_duty", {}, H.player)
    local ordinaryDecision = SC.Decision.update
    SC.Decision.update = function(subject, player, runtime, current)
        if H.phase ~= "cleaning_mixtures_run" then
            return ordinaryDecision(subject, player, runtime, current)
        end
        if subject == actor then
            local handled, reason = SC.BaseWork.update(subject, player, runtime)
            selected.lastWork = tostring(handled) .. "/" .. tostring(reason)
            return handled, reason
        end
        return true, "cleaning_probe_idle"
    end
    SC.CleaningSupplies.reset()
    local weight, capacity = U.carryLoad(actor)
    result("PASS", "cleaning_fixture", "worker=" .. record.id .. " storage=" .. selected.storage.id
        .. " load=" .. weight .. "/" .. capacity .. " original gear retained in native holder; controlled BaseWork acceptance")
    return selected
end
local function nextCase(f, current, check)
    local SC = SurvivorCompanion
    local stats = f.actor:getStats()
    -- This is controlled native-action acceptance, not a hunger/sleep test.
    -- Keep real health and damage enabled; set ordinary needs only at setup.
    stats:set(CharacterStat.HUNGER, 0.05)
    stats:set(CharacterStat.THIRST, 0.05)
    stats:set(CharacterStat.FATIGUE, 0.05)
    stats:set(CharacterStat.ENDURANCE, 1)
    if f.items then
        for _, item in ipairs(f.items) do
            if call(item, "getContainer") == f.container then
                SC.GameplayUtil.transferItemVerified(f.container, f.holder:getInventory(), item)
            end
        end
    end
    f.index, f.cleaned, f.job, f.queued, f.started, f.nextAt = f.index + 1, 0, nil, false, current, current + 1000
    f.items, f.bucket, f.concentrate, f.donor = {}, nil, nil, nil
    if f.index > 4 then return false end
    f.name = ({ "sink_bleach", "tainted_cleaning_liquid", "stored_mix", "undiluted" })[f.index]
    if f.name == "stored_mix" then
        f.bucket = add(f.container, "Base.BucketEmpty", { CleaningLiquid = 0.1, Water = 1.9 })
        f.concentrate = add(f.container, "Base.Bleach", { Bleach = 1 })
    elseif f.name == "sink_bleach" then
        f.bucket = add(f.container, "Base.BucketEmpty", {})
        f.concentrate = add(f.container, "Base.Bleach", { Bleach = 1 })
    elseif f.name == "tainted_cleaning_liquid" then
        f.bucket = add(f.container, "Base.BucketEmpty", {})
        f.concentrate = add(f.container, "Base.CleaningLiquid2", { CleaningLiquid = 0.5 })
        f.donor = add(f.container, "Base.BucketWood", { TaintedWater = 3 })
    else f.concentrate = add(f.container, "Base.Bleach", { Bleach = 1 }) end
    for _, item in ipairs({ f.concentrate, f.bucket or false, f.donor or false }) do
        if item then f.items[#f.items + 1] = item end
    end
    f.before, f.donorBefore, f.batchChecked = amount(f.concentrate), amount(f.donor), nil
    check("cleaning_" .. f.name .. "_supplies", f.concentrate ~= nil and (f.index == 4 or f.bucket ~= nil), "native items")
    SC.CleaningSupplies.reset()
    return true
end
function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "cleaning_mixtures_setup" then
        if current - H.phaseStartedAt < 8000 then return end
        H.cleaningMixtures = fixture(H, check, result)
        if not H.cleaningMixtures then
            if H.cleaningMixtures == false or current - H.phaseStartedAt > 20000 then
                check("cleaning_fixture_worker", false, "camp=" .. tostring(SC.BaseLife.active())
                    .. " roster=" .. #SC.Registry.snapshot())
                setPhase("finish", current)
            end
            return
        end
        nextCase(H.cleaningMixtures, current, check)
        setPhase("cleaning_mixtures_run", current)
        return
    end
    local f = H.cleaningMixtures
    if not f then setPhase("finish", current) return end
    if current - f.started > 300000 then
        check("cleaning_" .. f.name .. "_deadline", false, "cleaned=" .. f.cleaned)
        setPhase("finish", current) return
    end
    if current >= (f.traceAt or 0) then
        f.traceAt = current + 5000
        local job = f.job and SC.BaseLife.job(f.job)
        local decision = SC.Decision.peek(f.actor) or {}
        print("SC_REAL_SANDBOX|CLEANING_PROGRESS|" .. f.name .. " cleaned=" .. f.cleaned
            .. " job=" .. tostring(job and job.state) .. "/" .. tostring(job and job.blocker)
            .. " prep=" .. tostring(job and job.target.cleanPreparation and job.target.cleanPreparation.stage)
            .. " native=" .. tostring(SC.NativeActions.workKind(f.actor))
            .. " controller=" .. tostring(f.lastWork)
            .. " intent=" .. tostring(decision.intent) .. " bucket=" .. amount(f.bucket)
            .. " cleaner=" .. amount(f.concentrate))
        if job and job.state == "pending" then
            local plan, why = SC.CleaningSupplies.plan(f.actor, job)
            local info = SC.CleaningSupplies.inspect(f.bucket)
            local eligible, blocked = SC.Downtime.canCleanAt(f.actor, f.square, true)
            print("SC_REAL_SANDBOX|CLEANING_READY|plan=" .. tostring(plan and plan.mode) .. " why=" .. tostring(why)
                .. " tool=" .. tostring(SC.CleaningSupplies.tool(f.tool)) .. " info=" .. tostring(info and info.known)
                .. "/" .. tostring(info and info.cleanerAmount) .. "/" .. tostring(info and info.waterAmount)
                .. " eligible=" .. tostring(eligible) .. "/" .. tostring(blocked)
                .. " inside=" .. tostring(SC.BaseLife.isInside(f.actor)) .. " load=" .. tostring(SC.GameplayUtil.carryLoad(f.actor)))
        end
    end
    if f.job then
        local job = SC.BaseLife.job(f.job)
        if job and job.state == "blocked" then
            check("cleaning_" .. f.name .. "_blocked", false, tostring(job.blocker))
            setPhase("finish", current) return
        end
        if job then
            local prep = job.target.cleanPreparation
            if prep and not f.modeChecked then
                f.modeChecked = true
                if not check("cleaning_" .. f.name .. "_mode", prep.mode == (f.name == "stored_mix" and "mixed"
                    or f.name == "undiluted" and "undiluted" or "prepare"), tostring(prep.mode)) then
                    setPhase("finish", current) return
                end
                if f.name == "sink_bleach" then
                    check("cleaning_sink_source", prep.waterSource ~= nil,
                        "real fixed water source " .. tostring(prep.waterSource and prep.waterSource.sprite))
                end
            end
            if prep and prep.mode == "prepare" and prep.stage == "ready" and not f.batchChecked then
                f.batchChecked = true
                local info = SC.CleaningSupplies.inspect(f.bucket)
                check("cleaning_" .. f.name .. "_prepared", info and near(info.amount, 2)
                    and near(info.cleanerAmount, 0.1) and near(info.waterAmount, 1.9),
                    "native mixture=" .. tostring(info and info.amount) .. " cleaner=" .. tostring(info and info.cleanerAmount))
            end
            return
        end
        f.cleaned, f.job, f.nextAt = f.cleaned + 1, nil, current
        check("cleaning_" .. f.name .. "_tile_" .. f.cleaned,
            call(f.square, "haveStains") == false, "native stain removal")
        if f.cleaned >= (f.index == 4 and 1 or 8) then
            local expected = f.name == "stored_mix" and 0 or f.name == "undiluted" and SC.CleaningSupplies.dose() or 0.1
            check("cleaning_" .. f.name .. "_accounting", near(f.before - amount(f.concentrate), expected),
                "spent=" .. (f.before - amount(f.concentrate)) .. " expected=" .. expected)
            if f.donor then
                check("cleaning_" .. f.name .. "_water_accounting", near(f.donorBefore - amount(f.donor), 1.9),
                    "native water spent=" .. (f.donorBefore - amount(f.donor)))
            end
            if f.bucket then check("cleaning_" .. f.name .. "_mixture_accounting", amount(f.bucket) < 0.002,
                "eight native doses spent about two litres; remaining=" .. amount(f.bucket)) end
            for _, item in ipairs(f.items) do
                check("cleaning_" .. f.name .. "_returned_" .. item:getID(), f.container:contains(item), "same native item")
                for _, marker in pairs(SC.CleaningSupplies.MARKERS) do
                    check("cleaning_" .. f.name .. "_released_" .. item:getID() .. marker,
                        item:getModData()[marker] == nil, "reservation released")
                end
            end
            f.modeChecked = nil
            if not nextCase(f, current, check) then setPhase("finish", current) end
            return
        end
    end
    if current < f.nextAt then return end
    if not check("cleaning_" .. f.name .. "_stain_" .. (f.cleaned + 1), stain(f.square), "real blood splat") then
        setPhase("finish", current) return
    end
    local accepted, job = SC.BaseLife.requestCleaning(f.square)
    if not check("cleaning_" .. f.name .. "_queued_" .. (f.cleaned + 1), accepted == true, tostring(job)) then
        setPhase("finish", current) return
    end
    job.assignedId = f.record.id
    f.job = job.id
end
return Probe
