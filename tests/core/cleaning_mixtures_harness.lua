-- SPDX-License-Identifier: MIT
local SC, F = SurvivorCompanion, SC_TEST_WORK_TRANSPORT
local C, checks = SC.CleaningSupplies, 0
local actualTransfer, actualFinish = SC.NativeActions.startCleaningFluidTransfer, SC.NativeActions.finishWork
local function check(value, message)
    checks = checks + 1
    if not value then error("cleaning check " .. checks .. ": " .. message) end
end
local function near(a, b) return math.abs(a - b) < 0.0002 end
Fluid = { Water = "Water", TaintedWater = "TaintedWater", Bleach = "Bleach", CleaningLiquid = "CleaningLiquid" }
ItemTag = { CLEAN_STAINS = "clean_stains" }
ZomboidGlobals = { CleanBloodBleachAmount = 0.24999 }
local function vessel(kind, contents, capacity)
    local item, fc = F.item(kind), { contents = contents or {}, capacity = capacity or 10 }
    function fc:getAmount() local sum = 0 for _, value in pairs(self.contents) do sum = sum + value end return sum end
    function fc:getCapacity() return self.capacity end
    function fc:getSpecificFluidAmount(kind) return self.contents[kind] or 0 end
    function fc:contains(kind) return (self.contents[kind] or 0) > 0.0001 end
    function fc:isEmpty() return self:getAmount() < 0.0001 end
    function fc:isInputLocked() return self.locked == true end
    function fc:canAddFluid(kind) return not self.blocked or not self.blocked[kind] end
    function fc:isPoisonous() return false end -- Diluted cleaner must still be rejected as drinking water.
    function fc:isTainted() return self:contains("TaintedWater") end
    function fc:canPlayerEmpty() return true end
    function fc:getOwner() return item end
    function fc:getPrimaryFluid()
        local best, amount = "Water", -1
        for name, value in pairs(self.contents) do if value > amount then best, amount = name, value end end
        return { getFluidTypeString = function() return best end }
    end
    function fc:getPrimaryFluidAmount() return self:getSpecificFluidAmount(self:getPrimaryFluid():getFluidTypeString()) end
    function fc:adjustAmount(amount)
        local before = self:getAmount()
        for name, value in pairs(self.contents) do self.contents[name] = before > 0 and value * amount / before or 0 end
    end
    function item:getFluidContainer() return fc end
    function item:getActualWeight() return 0.2 + fc:getAmount() end
    item.fc = fc
    return item
end
local function transfer(source, bucket, amount)
    local a, b = source.fc, bucket.fc
    amount = math.min(amount, a:getAmount(), b:getCapacity() - b:getAmount())
    local before = a:getAmount()
    for name, value in pairs(a.contents) do
        local moved = value * amount / before
        a.contents[name], b.contents[name] = value - moved, (b.contents[name] or 0) + moved
    end
end
local native = { starts = 0, pending = nil, partial = nil }
local function scene(workers)
    local ctx = F.setup("logs", 1, workers)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    C.reset()
    native.starts, native.pending, native.partial = 0, nil, nil
    ctx.tool = F.item("Base.Mop")
    function ctx.tool:hasTag(tag) return tag == ItemTag.CLEAN_STAINS end
    function ctx.tool:isBroken() return false end
    ctx.storageObject.container:AddItem(ctx.tool)
    ctx.actor.square.stained = true
    function ctx.actor.square:haveStains() return self.stained end
    function ctx.actor:getMaxWeight() return self.maxWeight or 50 end
    SC.Downtime = {
        peek = function() return ctx.cleanActive and { active = { kind = "clean_base" } } or nil end,
        cancel = function() ctx.cleanActive = nil return true end,
        canCleanAt = function(actor, square, staged)
            if staged or C.carried(actor) then return true end
            return false, "cleaning_supplies_missing"
        end,
        update = function(actor, _, _, kind, square)
            if ctx.cleanActive and not square.stained then
                ctx.cleanActive = nil
                return true, "cleaned"
            end
            local tool, cleaner = C.carried(actor)
            check(tool and cleaner and kind == "clean_base", "a real cleaner and tool must be staged")
            cleaner.fc:adjustAmount(cleaner.fc:getAmount() - C.dose())
            square.stained = false
            ctx.cleanActive = true
            return true, "cleaned"
        end,
    }
    SC.NativeActions.startCleaningFluidTransfer = function(actor, source, bucket, amount, jobId, world)
        check(SC.BaseWork.canMixCleaning(actor, jobId, source, bucket, world), "only the exact owned preparation may pour")
        native.starts = native.starts + 1
        if native.partial then
            transfer(source, bucket, amount * native.partial)
            native.pending = { actor = actor, source = source, bucket = bucket,
                amount = amount * (1 - native.partial), jobId = jobId }
            native.partial = nil
        else transfer(source, bucket, amount) end
        return true, "cleaning_mix_timed_action_started"
    end
    SC.NativeActions.isWorkActive = function(actor) return native.pending ~= nil and native.pending.actor == actor end
    SC.NativeActions.finishWork = function() return true end
    SC.NativeActions.workJobId = function(actor) return native.pending and native.pending.jobId end
    SC.NativeActions.workKind = function() return native.pending and "cleaning_mix" end
    SC.NativeActions.cancelWork = function() native.pending = nil return true end
    return ctx
end
local function plan(ctx)
    local result, reason
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        result, reason = C.plan(ctx.actor)
        if result or reason ~= "cleaning_supplies_scanning" then return result, reason end
    end
    error("bounded cleaning discovery never completed")
end
local function queue(ctx)
    local okay, job = SC.BaseLife.requestCleaning(ctx.actor.square)
    check(okay, "cleaning request must be admitted: " .. tostring(job))
    return job
end
local function run(ctx, job, count)
    local reason
    for _ = 1, count or 180 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        _, reason = SC.BaseWork.update(ctx.actor, nil, {})
        if not SC.BaseLife.job(job.id) then
            check(ctx.cleanActive ~= true, "a completed job settles the native cleaning owner before loan return")
            return true
        end
        if job.state == "blocked" then return false, job.blocker end
    end
    return false, reason
end
for _, cleaner in ipairs({ "Bleach", "CleaningLiquid" }) do
    for _, water in ipairs({ "Water", "TaintedWater" }) do
        local ctx = scene()
        local concentrate = vessel("Base." .. cleaner, { [cleaner] = 1 }, 1)
        local bucket = vessel("Base.BucketEmpty", {}, 10)
        local donor = vessel("Base.BucketWood", { [water] = 3 }, 10)
        for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
        local selection = plan(ctx)
        check(selection and selection.mode == "prepare" and selection.liquid.item == bucket,
            cleaner .. "/" .. water .. " chooses preparation")
        local job = queue(ctx)
        local completed, why = run(ctx, job)
        check(completed, "prepared cleaning completes: " .. tostring(why))
        check(native.starts == 2 and near(concentrate.fc:getAmount(), 0.900004), "one exact water and cleaner transfer")
        check(near(C.inspect(bucket).ratio, 0.05), "native-dose use preserves five percent concentration")
        check(ctx.storageObject.container:contains(bucket) and ctx.storageObject.container:contains(concentrate)
            and ctx.storageObject.container:contains(donor), "all exact borrowed vessels return")
        for _ = 2, 8 do
            ctx.actor.square.stained = true
            local nextJob = queue(ctx)
            check(run(ctx, nextJob), "leftover mixture is reused")
        end
        check(native.starts == 2 and bucket.fc:getAmount() < 0.0002
            and near(concentrate.fc:getAmount(), 0.9), "eight tiles cost only one hundred ml concentrate: starts="
                .. native.starts .. " bucket=" .. bucket.fc:getAmount() .. " concentrate=" .. concentrate.fc:getAmount())
        for _, item in ipairs({ ctx.tool, bucket, donor, concentrate }) do
            for _, marker in pairs(C.MARKERS) do check(item.modData[marker] == nil, "no leaked cleaning claim") end
        end
    end
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local premix = vessel("Mod.UnlabelledBottle", { Water = 0.99, CleaningLiquid = 0.01 }, 1)
    for _ = 1, 150 do ctx.storageObject.container:AddItem(F.item("Base.Nails")) end
    for _, item in ipairs({ concentrate, bucket, premix }) do ctx.storageObject.container:AddItem(item) end
    local first, reason = C.plan(ctx.actor)
    check(first == nil and reason == "cleaning_supplies_scanning", "a partial scan cannot trigger undiluted fallback")
    local selection = plan(ctx)
    check(selection and selection.mode == "mixed" and selection.liquid.item == premix,
        "a late stored mixture wins over concentrate and an empty bucket")
    check(SC.Needs.isSafeWaterItem(premix) == false, "a non-poisonous water-dominant cleaner is never drunk")
    local job = queue(ctx)
    check(run(ctx, job) and native.starts == 0 and near(concentrate.fc:getAmount(), 1), "stored mix needs no new batch")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    ctx.storageObject.container:AddItem(concentrate)
    check(plan(ctx).mode == "undiluted", "no bucket permits the chosen undiluted fallback")
    check(run(ctx, queue(ctx)) and near(concentrate.fc:getAmount(), 1 - C.dose()), "fallback keeps native cost")
end
do
    local ctx = scene()
    local bucket = vessel("Base.BucketEmpty", { Water = 0.95 }, 10)
    local concentrate = vessel("Base.CleaningLiquid2", { CleaningLiquid = 1 }, 1)
    ctx.storageObject.container:AddItem(bucket)
    ctx.storageObject.container:AddItem(concentrate)
    check(plan(ctx).mode == "prepare", "a partly filled bucket supplies its own water")
    check(run(ctx, queue(ctx)) and native.starts == 1, "existing water is preserved and only concentrate is added")
    local unknown = vessel("Base.Bucket", { Water = 1, Petrol = 0.1 }, 10)
    check(C.inspect(unknown).known == false, "unknown extra contents cannot be diluted")
    check(C.inspect(vessel("Base.Bucket", { Water = 1, Bleach = 0.1, CleaningLiquid = 0.1 }, 10)).usable == false,
        "two different cleaners are never treated as an approved mix")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { TaintedWater = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.4
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    check(native.pending ~= nil, "partial native transfer remains owned")
    local saved = SC.BaseLife.export()
    native.pending = nil -- Reload loses the timed action, not its physical fluid changes.
    check(SC.BaseLife.restore(saved), "preparation stage and exact receipts survive reload")
    job = SC.BaseLife.job(job.id)
    check(run(ctx, job), "reload resumes only the remaining fluid amount")
    check(near(concentrate.fc:getAmount(), 0.9) and near(donor.fc:getAmount(), 1.100076),
        "partial replay neither duplicates water nor double-spends cleaner")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.5
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    local before = bucket.fc:getAmount()
    check(SC.WorkTransport.foreignProtected(bucket, ctx.actor), "an in-flight bucket is protected from other jobs")
    check(SC.BaseLife.cancelJob(job.id), "cancellation stops the exact native pour and settles every loan")
    check(native.pending == nil and near(bucket.fc:getAmount(), before)
        and ctx.storageObject.container:contains(bucket), "cancellation preserves partial mixture without replay")
end

do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    ctx.storageObject.container:AddItem(concentrate)
    ctx.storageObject.container:AddItem(bucket)
    local source = vessel("Fixture.Sink", { Water = 4 }, 4)
    function source:getSquare() return ctx.source end
    function source:hasWater() return self.fc:getAmount() > 0 end
    function source:getFluidAmount() return self.fc:getAmount() end
    function source:isTaintedWater() return false end
    function source:getObjectIndex() return 0 end
    function source:getSpriteName() return "fixture_sink" end
    ctx.source.objects[#ctx.source.objects + 1] = source
    check(SC.BaseLife.beginZone("area", ctx.source), "fixed-source fixture begins a persisted camp area")
    check(SC.BaseLife.finishZone(ctx.source, "Sink area"), "fixed-source fixture marks its camp area")
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.4
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    check(native.pending and job.target.cleanPreparation.waterSource,
        "reload fixture reaches a partially completed fixed-source fill")
    local saved = SC.BaseLife.export()
    native.pending = nil
    local restored, restoreReason = SC.BaseLife.restore(saved)
    check(restored, "fixed-source progress and loans survive loading: " .. tostring(restoreReason))
    check(run(ctx, SC.BaseLife.job(job.id)), "interrupted filling resumes before the concentrate pour")
    check(near(source.fc:getAmount(), 2.1) and near(concentrate.fc:getAmount(), 0.9)
        and near(bucket.fc:getAmount(), 2 - C.dose()), "fill reload transfers only the missing water and cleaner")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local full = vessel("Base.BucketEmpty", { Water = 10 }, 10)
    ctx.storageObject.container:AddItem(concentrate)
    ctx.storageObject.container:AddItem(full)
    check(plan(ctx).mode == "undiluted" and full.fc:getAmount() == 10,
        "a full bucket is never spilled to make headroom")
    local bucket = vessel("Base.BucketWood", {}, 10)
    ctx.storageObject.container:AddItem(bucket)
    C.reset()
    ctx.actor.maxWeight = 8
    local selection = plan(ctx)
    check(selection.mode == "undiluted" or selection.mode == "prepare" and selection.volume < 2,
        "heavy water donors cannot force an overloaded two-litre batch")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local water = vessel("Base.WaterBottle", { Water = 0.9 }, 1)
    for _, item in ipairs({ concentrate, bucket, water }) do ctx.storageObject.container:AddItem(item) end
    local selection = plan(ctx)
    check(selection.mode == "prepare" and selection.volume < 2 and selection.volume >= C.dose(),
        "a short water supply reduces the batch without adding imaginary water")
    check(run(ctx, queue(ctx)), "a reduced batch still cleans a real job")
end
do
    local ctx = scene()
    ctx.storageObject.container:AddItem(F.item("Base.Soap2"))
    ctx.storageObject.container:AddItem(vessel("Base.BucketEmpty", {}, 10))
    ctx.storageObject.container:AddItem(vessel("Base.WaterBottle", { Water = 1 }, 1))
    local selection, why = plan(ctx)
    check(selection == nil and why == "cleaning_cleaner_missing", "soap bars do not invent a fluid recipe")
end
do
    local ctx = scene()
    -- More than a second of bounded discovery must not reset its own cursor.
    for _ = 1, 800 do ctx.storageObject.container:AddItem(vessel("Mod.Flask", { Water = 0.5 }, 1)) end
    local mix = vessel("Mod.FinalBottle", { Water = 0.475, Bleach = 0.025 }, 1)
    ctx.storageObject.container:AddItem(mix)
    local selection = plan(ctx)
    check(selection and selection.mode == "mixed" and selection.liquid.item == mix,
        "large fluid inventories finish their retained survey and find a late mixture")
end
do
    local ctx = scene(2)
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    SC_TEST_CLOCK = SC_TEST_CLOCK + 100
    SC.BaseWork.update(ctx.actor, nil, {})
    local other = ctx.actors[2]
    check(C.available({ item = bucket, container = ctx.storageObject.container, storageId = ctx.storage.id }, other) == false,
        "a second companion cannot claim the first worker's selected bucket")
    local waterBefore, cleanerBefore = bucket.fc:getAmount(), concentrate.fc:getAmount()
    check(SC.BaseLife.cancelJob(job.id), "a selected preparation can be cancelled")
    check(bucket.fc:getAmount() == waterBefore and concentrate.fc:getAmount() == cleanerBefore,
        "cancelling selection adds no further fluid effects")
end
do
    local ctx = scene()
    local mixed = vessel("Base.BucketEmpty", { Water = 1.9, Bleach = 0.1 }, 10)
    function mixed:getActualWeight() return 1 end
    function mixed:getUnequippedWeight() return 3 end
    function ctx.tool:getActualWeight() return 6 end
    ctx.actor.maxWeight = 8
    ctx.storageObject.container:AddItem(mixed)
    local selection, why = plan(ctx)
    check(selection == nil and why == "cleaning_carry_capacity_low",
        "tool plus full fluid encumbrance is checked together, not just shell weights")
end
do
    local ctx = scene()
    local contaminated = vessel("Base.WateredCan", { Water = 1.9, Bleach = 0.1 }, 10)
    ctx.actor.inventory:AddItem(contaminated)
    check(SC.FarmWork.carriedWaterContainer(ctx.actor, true) == nil,
        "a water-dominant cleaner is not a farming water supply")
    check(SC.BaseWork.classifyItem(contaminated) == "tools", "sorting recognises cleaner contents before the vessel's type")
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.5
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    check(native.pending ~= nil, "uncertain transfer fixture reached an owned partial pour")
    bucket.fc.contents = {} -- Simulate a contradictory external change, not another pour.
    native.pending = nil
    local completed, why = run(ctx, job)
    check(completed == false and why == "cleaning_mixture_transfer_unverified"
        and not SC.BaseLife.jobAutoRetry(job) and native.starts == 1,
        "contradictory donor/bucket changes stop for reconciliation without replay")
end
do
    local ctx = scene()
    local mix = vessel("Base.BucketEmpty", { TaintedWater = 1.9, CleaningLiquid = 0.1 }, 10)
    ctx.storageObject.container:AddItem(mix)
    plan(ctx)
    local job = queue(ctx)
    for _ = 1, 40 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if ctx.actor.inventory:contains(mix) then break end
    end
    local before = mix.fc:getAmount()
    check(SC.BaseFuel.prepareActorRetirement(ctx.actor), "death retirement releases cleaning item markers")
    check(ctx.actor.inventory:contains(mix) and mix.fc:getAmount() == before,
        "retirement leaves the exact bucket and contents on the actor for native corpse ownership")
    for _, marker in pairs(C.MARKERS) do check(mix.modData[marker] == nil, "death cannot leave a live cleaning reservation") end
end
-- A worker lost part way through a batch takes the exact vessels with it. The
-- reopened job must plan afresh, or it fails forever and auditCleaning, which
-- waits for any open cleaning job, stops cleaning the whole camp.
for _, viaRecovery in ipairs({ true, false }) do
    local ctx = scene(2)
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.5
    for _ = 1, 60 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        local prep = job.target.cleanPreparation
        if prep and prep.stage == "water" and prep.nativePending == true then break end
    end
    check(job.target.cleanPreparation and job.target.cleanPreparation.nativePending == true,
        "the fixture loses its worker in the middle of a pour")
    native.pending = nil
    local gone, survivor = SC.GameplayUtil.idOf(ctx.actor), ctx.actors[2]
    check(SC.BaseFuel.prepareActorRetirement(ctx.actor), "the lost worker's markers are released")
    if viaRecovery then
        local oldUnregistered = SC.BaseWork.workerUnregistered
        SC.BaseWork.workerUnregistered = function(id) return id == gone end
        check(SC.BaseWork.reconcileExpiredJob(job, gone), "the expired lease settles")
        SC.BaseWork.workerUnregistered = oldUnregistered
        check(job.target.cleanPreparation == nil, "recovery forgets the lost batch with its receipts")
    else
        -- A save already caught in this state, from before the recovery fix.
        job.target.cleanLoans, job.assignedId = nil, nil
    end
    job.state, job.reservedBy, job.leaseUntil = "pending", nil, 0
    local replacement = vessel("Base.BucketEmpty", { Water = 1.9, Bleach = 0.1 }, 10)
    local spareTool = F.item("Base.Mop")
    function spareTool:hasTag(tag) return tag == ItemTag.CLEAN_STAINS end
    function spareTool:isBroken() return false end
    ctx.storageObject.container:AddItem(replacement)
    ctx.storageObject.container:AddItem(spareTool)
    ctx.actor = survivor
    C.reset()
    local completed, why = run(ctx, job)
    check(completed, "the survivor finishes the reopened job from fresh supplies: " .. tostring(why))
end
do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Mod.FilteredBucket", { Water = 0.95 }, 2)
    bucket.fc.blocked = { Bleach = true }
    ctx.storageObject.container:AddItem(concentrate)
    ctx.storageObject.container:AddItem(bucket)
    check(plan(ctx).mode == "undiluted", "a bucket that rejects cleaner is not a preparation path")
    bucket.fc.blocked, bucket.fc.locked = nil, true
    C.reset()
    check(plan(ctx).mode == "undiluted", "an input-locked bucket is never filled or emptied")
    check(bucket.fc:getAmount() == 0.95, "incompatible bucket contents remain untouched")
end

do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local clean = vessel("Base.BucketWood", { Water = 3 }, 10)
    local tainted = vessel("Mod.WaterContainer", { TaintedWater = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, clean, tainted }) do ctx.storageObject.container:AddItem(item) end
    local selection = plan(ctx)
    check(selection.mode == "prepare" and selection.water.item == tainted,
        "compatible tainted water is preferred even when clean water appears first")
    ctx.storage.reserves = { ["Base.Bleach"] = 1 }
    check(C.available(selection.concentrate, ctx.actor) == false,
        "stock protection is revalidated after planning and before any withdrawal")
    C.reset()
    local blocked, why = plan(ctx)
    check(blocked == nil and why == "cleaning_cleaner_missing" and concentrate.fc:getAmount() == 1,
        "protected concentrate is never consumed for a new batch")
    ctx.storage.reserves, ctx.storage.withdrawals = nil, false
    C.reset()
    check(plan(ctx) == nil and bucket.fc:getAmount() == 0, "unavailable storage cannot supply a preparation")
end

do
    local ctx = scene()
    local last = ctx.storageObject
    for _ = 1, 12 do
        last = F.storage(ctx.destinationSquare)
        check(SC.BaseLife.registerStorage(last, "general"), "bounded survey fixture registers shelves")
        for _ = 1, 80 do last.container:AddItem(F.item("Base.Nails")) end
    end
    local mix = vessel("Mod.LastShelfBottle", { Water = 0.475, Bleach = 0.025 }, 1)
    last.container:AddItem(mix)
    local oldResolve, oldGet = SC.BaseLife.resolveContainer, SC.GameplayUtil.listGet
    local itemLists = { [ctx.actor.inventory:getItems()] = true }
    for _, storage in ipairs(ctx.base.storages) do
        itemLists[oldResolve(storage):getItems()] = true
    end
    local touched, reads = {}, 0
    SC.BaseLife.resolveContainer = function(storage)
        if storage then touched[storage.id] = true end
        return oldResolve(storage)
    end
    SC.GameplayUtil.listGet = function(values, index)
        if itemLists[values] then reads = reads + 1 end
        return oldGet(values, index)
    end
    local deferred, deferredReason = C.plan(ctx.actor, nil, function() return 0 end)
    check(deferred == nil and deferredReason == "cleaning_supplies_scanning" and reads == 0,
        "an exhausted maintenance budget yields before inventory discovery")
    local selected, why
    for _ = 1, 100 do
        touched, reads = {}, 0
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        selected, why = C.plan(ctx.actor)
        local containers = 0
        for _ in pairs(touched) do containers = containers + 1 end
        check(containers <= 4 and reads <= 64,
            "each retained discovery slice touches at most four shelves and 64 items: shelves=" .. containers .. " reads=" .. reads)
        if selected or why ~= "cleaning_supplies_scanning" then break end
    end
    check(selected and selected.liquid.item == mix, "bounded discovery eventually reaches the last shelf")
    SC.BaseLife.resolveContainer, SC.GameplayUtil.listGet = oldResolve, oldGet
end

do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    ctx.storageObject.container:AddItem(concentrate)
    ctx.storageObject.container:AddItem(bucket)
    local source = { square = ctx.source }
    function source:getSquare() return self.square end
    function source:hasWater() return true end
    function source:getFluidAmount() return 10 end
    function source:isTaintedWater() return false end
    function source:getObjectIndex() return 0 end
    function source:getSpriteName() return "fixture_sink" end
    ctx.source.objects[#ctx.source.objects + 1] = source
    ctx.base.zones[#ctx.base.zones + 1] = {
        kind = "area", x1 = 0, x2 = 0, y1 = 1, y2 = 1, z = 0,
    }
    local oldAccess, oldRequest = SC.GameplayUtil.directInteractionAccess, SC.Navigation.requestAny
    SC.GameplayUtil.directInteractionAccess = function(actor, object)
        if object == source then return false, { ctx.source }, "fixture_route_needed" end
        return oldAccess(actor, object)
    end
    SC.Navigation.requestAny = function(actor, targets, mode, intent)
        if intent and intent.action == "move_to_cleaning_water" then return true, "waiting_for_companion_clearance" end
        return oldRequest(actor, targets, mode, intent)
    end
    check(plan(ctx).mode == "prepare", "a fixed source is considered before fallback")
    local job = queue(ctx)
    local completed, why = run(ctx, job, 600)
    check(completed, "an unreachable water source settles loans and falls back: " .. tostring(why))
    check(#job.target.cleanRejectedWater == 1 and native.starts == 1
        and near(concentrate.fc:getAmount()+bucket.fc:getAmount(), 1 - C.dose())
        and near(bucket.fc:getAmount(),0.1),
        "a pending water route preserves the concentrate-first pour and falls back without replay")
    SC.GameplayUtil.directInteractionAccess, SC.Navigation.requestAny = oldAccess, oldRequest
end

do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.5
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    check(native.pending ~= nil, "victim identity fixture reached a measured pour")
    local record = SC.Registry.byId(SC.GameplayUtil.idOf(ctx.actor))
    local oldActor = record.actor
    record.actor = nil -- An alias cannot authorize a stale native body.
    check(not SC.BaseWork.canMixCleaning(ctx.actor, job.id, donor, bucket, false),
        "the registry must still own the exact action actor")
    record.actor = oldActor
    function ctx.actor:isDead() return true end
    check(not SC.BaseWork.canMixCleaning(ctx.actor, job.id, donor, bucket, false),
        "a dead actor cannot continue a queued fluid transfer")
end

do
    local ctx = scene()
    local concentrate = vessel("Base.Bleach", { Bleach = 1 }, 1)
    local bucket = vessel("Base.BucketEmpty", {}, 10)
    local donor = vessel("Base.BucketWood", { Water = 3 }, 10)
    for _, item in ipairs({ concentrate, bucket, donor }) do ctx.storageObject.container:AddItem(item) end
    plan(ctx)
    local job = queue(ctx)
    native.partial = 0.5
    for _ = 1, 100 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if native.pending then break end
    end
    function ctx.actor:getPrimaryHandItem() return self.primary end
    function ctx.actor:getSecondaryHandItem() return self.secondary end
    function ctx.actor:setPrimaryHandItem(item) self.primary = item end
    function ctx.actor:setSecondaryHandItem(item) self.secondary = item end
    local oldQueue, oldWrapper, oldAction, oldFluid = ISTimedActionQueue, ISFluidContainer, ISFluidTransferAction, FluidContainer
    local queue = { queue = {} }
    ISTimedActionQueue = {
        getTimedActionQueue = function(actor) check(actor == ctx.actor, "queue belongs to the exact LF worker") return queue end,
        add = function(action) queue.current, queue.queue[1] = action, action end,
    }
    ISFluidContainer = { new = function(_, fc)
        return { getOwner = function() return fc:getOwner() end, getFluidContainer = function() return fc end }
    end }
    ISFluidTransferAction = { new = function(_, actor, a, _, b, _, amount)
        return { character = actor, source = a, target = b, amount = amount }
    end }
    FluidContainer = { CanTransfer = function() return true end }
    job.target.cleanPreparation.stage = "water" -- Exercise the water adapter after concentrate-first preparation.
    local before = bucket.fc:getAmount()
    local started, why = actualTransfer(ctx.actor, donor, bucket, 0.95, job.id, false)
    check(started, "measured native adapter queues successfully: " .. tostring(why))
    local action = queue.current
    check(action.amount == 0.95 and bucket.fc:getAmount() == before,
        "adapter passes the measured amount without scripted fluid deductions")
    check(action:isValid(), "native instance accepts its own actor and exact vessels")
    bucket.fc.contents.Bleach, bucket.fc.contents.CleaningLiquid = 0.001, 0.001
    job.target.cleanPreparation.cleanerName = "CleaningLiquid"
    check(not action:isValid(), "a second cleaner added during the action invalidates the exact native instance")
    bucket.fc.contents.Bleach, bucket.fc.contents.CleaningLiquid = nil, nil
    job.target.cleanPreparation.cleanerName = "Bleach"
    action.character = {}
    check(not action:isValid(), "native instance rejects a different actor")
    action.character = ctx.actor
    local target = action.target
    action.target = action.source
    check(not action:isValid(), "native instance rejects a changed receiver")
    action.target = target
    local original = action.source
    action.source = target
    check(not action:isValid(), "native instance rejects a changed donor")
    action.source = original
    queue.current, queue.queue = nil, {}
    check(actualFinish(ctx.actor), "native adapter restores the worker's original hands")
    check(ctx.actor.primary == nil and ctx.actor.secondary == nil, "temporary bucket equipment is released")
    ISFluidTransferAction.new=function(_,actor,a,_,b,_,amount)
        return {character=actor,source=a,target=b,amount=amount,
            update=function(self) transfer(self.source:getOwner(),self.target:getOwner(),0.2) end,
            complete=function(self) transfer(self.source:getOwner(),self.target:getOwner(),0.1) return true end,
            forceStop=function(self) self.stopped=true end}
    end
    local proof={version=1,credit=0}
    check(actualTransfer(ctx.actor,donor,bucket,0.95,job.id,false,proof),"paired native transfer starts")
    action=queue.current; action:update()
    donor.fc.contents.Water=donor.fc.contents.Water-0.25 -- Native auto-drinking between callbacks.
    action:complete()
    check(near(proof.credit,0.3) and not proof.uncertain,
        "paired receipt measures only native pours, excluding independent donor consumption")
    queue.current,queue.queue=nil,{}
    check(actualFinish(ctx.actor),"paired pour releases its original hands")
    before=bucket.fc:getAmount()
    local oldTake = ISTakeWaterAction
    local source = { square = ctx.actor.square }
    function source:getSquare() return self.square end
    function source:hasWater() return true end
    function source:getFluidAmount() return 9 end
    function source:hasFluid() return true end
    function source:isTaintedWater() return true end
    function source:getObjectIndex() return #self.square.objects - 1 end
    function source:getSpriteName() return "fixture_fill_source" end
    source.square.objects[#source.square.objects + 1] = source
    job.target.cleanPreparation.waterSource = {
        x = source.square.x, y = source.square.y, z = source.square.z,
        index = source:getObjectIndex(), sprite = source:getSpriteName(),
    }
    ISTakeWaterAction = { new = function(_, actor, item, object, tainted)
        return { character = actor, item = item, waterObject = object, waterTaintedCL = tainted,
            waterUnit = 9, startUsedAmount = item.fc:getAmount(),
            getDuration = function(self) return self.waterUnit * 100 + 30 end }
    end }
    started, why = actualTransfer(ctx.actor, source, bucket, 0.95, job.id, true)
    check(started, "fixed-source adapter queues successfully: " .. tostring(why))
    action = queue.current
    check(action.waterUnit == 0.95 and near(action.endUsedAmount, before + 0.95)
        and near(action.maxTime, 125) and action.waterTaintedCL == true
        and bucket.fc:getAmount() == before,
        "native fill quantity and duration are capped to the missing water, preserving taint")
    check(action:isValid(), "fixed-source fill validates the exact bucket and source")
    action.waterObject = {}
    check(not action:isValid(), "fixed-source fill rejects a changed water object")
    action.waterObject, action.item = source, donor
    check(not action:isValid(), "fixed-source fill rejects a changed bucket")
    action.item = bucket
    queue.current, queue.queue = nil, {}
    check(actualFinish(ctx.actor), "fixed-source fill restores its hand equipment")
    ISTakeWaterAction = oldTake
    ISTimedActionQueue, ISFluidContainer, ISFluidTransferAction, FluidContainer = oldQueue, oldWrapper, oldAction, oldFluid
end

SC_TEST_REPORT = "CLEANING_MIXTURES_PASS checks=" .. checks
print(SC_TEST_REPORT)
