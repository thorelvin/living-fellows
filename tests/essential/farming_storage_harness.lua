-- SPDX-License-Identifier: MIT
-- A shovel has an explicitly valid secondary home in Weapons. The farmer
-- must borrow/return that exact tool before switching to the seed packet.
local SC, F = LivingFellows, FarmLifecycleFixture
local checks = 0
local function check(value, reason)
    checks = checks + 1
    assert(value, 'farm storage ' .. checks .. ': ' .. reason)
end
SC.FarmWork.reset(); F.reset()
local actor = F.actor('farm-storage-worker', 0, 1)
local plant = F.plant({ state='dead', harvestable=false })
F.square(1, 1, plant)
local shovel = F.item('Base.Shovel', 20, { tags={DIG_PLOW=true} })
local seed = F.item('Base.TomatoSeed', 21, { category='Food' })
local _, source = F.addStorage('storage:dual-tool', 'weapons', { shovel })
local _, seeds = F.addStorage('storage:seeds', 'farming', { seed })
local job = F.job('replant', 1, 1, { id='job:storage-replant', actorId=actor.id, cropType='Tomato' })
local state = {}
SC.FarmWork.update(actor, {}, job, state)
check(shovel.container == actor.inventory and seed.container == seeds,
    'farmer borrows its exact shovel from Weapons while retaining the seed source')
SC.FarmWork.update(actor, {}, job, state)
check(F.native[actor] and F.native[actor].active, 'ordinary native plow work starts')
plant.state='plow'; F.native[actor].active=false
SC.FarmWork.update(actor, {}, job, state)
F.returnMode='pending'; SC.FarmWork.update(actor, {}, job, state)
check(shovel.container == actor.inventory and seed.container == seeds,
    'a pending return cannot advance to sowing or steal a second supply')
F.returnMode='complete'
for _=1,4 do SC.FarmWork.update(actor, {}, job, state) end
check(shovel.container == source and F.nativeStarts[#F.nativeStarts].intent.operation == 'sow'
    and F.nativeStarts[#F.nativeStarts].intent.item == seed,
    'the exact shovel returns to Weapons before the seed is used')

-- Manure collection uses the same dual-use rule. A rake kept on Weapons is a
-- valid home that sorting leaves alone, so the farmer must find it there.
local rake = F.item('Base.Rake', 30, { tags={TAKE_DUNG=true} })
local _, rack = F.addStorage('storage:dual-rake', 'weapons', { rake })
local digger = F.actor('farm-manure-worker', 0, 2)
local manureJob = F.job('manure', 0, 2, { id='job:storage-manure', actorId=digger.id })
local manureState, why = {}, nil
for _=1,6 do
    if manureState.borrowed then break end
    _, why = SC.FarmWork.animalSupport.borrow(digger, {}, manureJob, manureState,
        SC.ManureWork.isTool, SC.ManureWork.TOOL_CATEGORIES, 'manure_tool')
end
check(rake.container == digger.inventory and manureState.borrowed
    and manureState.borrowed.item == rake and manureState.borrowed.container == rack,
    'manure collection borrows the exact rake kept on Weapons (' .. tostring(why) .. ')')

local FarmWork = SC.FarmWork
local function startWatering()
    FarmWork.reset()
    F.reset()
    local worker = F.actor("plot-worker", 0.5, 0.5)
    local crop = F.plant({ waterLvl = 20, waterNeeded = 80 })
    F.square(12, 3, crop)
    local can = F.item("Base.WateredCan", 44, { fluidAmount = 5, fluidCapacity = 8 })
    local _, home = F.addStorage("storage:watering", "farming", { can })
    local water = F.job("water", 12, 3, { id = "job:watering", uses = 2 })
    local handled, why = FarmWork.update(worker, {}, water, {})
    check(handled and why == "farm_supply_taken" and can.container == worker.inventory,
        "working can is borrowed from the marked crate")
    return worker, crop, can, home, water
end

local request, peek, cancel = SC.Navigation.requestAny, SC.Navigation.peek, SC.Navigation.cancel
local reply, cancelled = "path_searching", 0
SC.Navigation.requestAny = function() return true, reply end
SC.Navigation.peek = function() return { goalAction = "move_to_farm_plot" } end
SC.Navigation.cancel = function() cancelled = cancelled + 1 return true end
local worker, crop, can, home, water = startWatering()
local started = F.clock
FarmWork.update(worker, {}, water, {})
F.clock, reply = started + 15000, "path_budget_deferred"
FarmWork.update(worker, {}, water, {})
worker.x, F.clock, reply = 0.9, started + 29999, "path_searching"
local handled, reason, terminal = FarmWork.update(worker, {}, water, {})
check(handled and not terminal and can.container == worker.inventory,
    "a retry, budget yield, and short positional correction retain the original deadline")
F.clock = started + 30000
handled, reason, terminal = FarmWork.update(worker, {}, water, {})
check(handled == false and terminal == true and reason == "farm_water_plot_unreachable",
    "the original deadline expires across path retries")
check(cancelled == 1 and can.container == home and can.fluidAmount == 5
        and can.modData[FarmWork.ITEM_MARKER] == nil and F.receipts[1].phase == "returned"
        and crop.waterLvl == 20 and #F.nativeStarts == 0,
    "blocking releases the route and returns the same full can before reporting failure")

worker, crop, can, home, water = startWatering()
FarmWork.update(worker, {}, water, {})
for _, x in ipairs({-1.5, 3.5}) do
    worker.x, F.clock = x, F.clock + 20000
    handled, reason, terminal = FarmWork.update(worker, {}, water, {})
    check(handled and not terminal and can.container == worker.inventory,
        "real travel, including a detour, gives the worker time to reach the crop")
end
worker.x, worker.y, F.clock = 11.5, 3.5, F.clock + 20000
handled, reason = FarmWork.update(worker, {}, water, {})
check(handled and reason == "farm_water_started" and #F.nativeStarts == 1,
    "a progressing walk can start native watering beyond the first deadline")

worker, crop, can, home, water = startWatering()
local restore = SC.BaseWork.restoreToStorage
SC.BaseWork.restoreToStorage = function() return false, "destination_full" end
FarmWork.update(worker, {}, water, {})
F.clock = F.clock + 30000
handled, reason, terminal = FarmWork.update(worker, {}, water, {})
check(handled == false and terminal and reason == "farm_water_plot_unreachable"
        and can.container == worker.inventory and can.modData[FarmWork.ITEM_MARKER] ~= nil
        and F.receipts[1].phase == "recovery",
    "a full crate hands the exact loan to recovery and releases the worker")
local _, eligible = FarmWork.jobModifier(worker.id, water, {}, { actor = worker })
check(not eligible, "a manual retry cannot borrow again while the first can is in recovery")
SC.BaseWork.restoreToStorage = restore
FarmWork.audit(F.base)
_, eligible = FarmWork.jobModifier(worker.id, water, {}, { actor = worker })
check(eligible and can.container == home and F.receipts[1].phase == "returned",
    "recovery returns the exact can once and makes the job eligible again")
SC.Navigation.requestAny, SC.Navigation.peek, SC.Navigation.cancel = request, peek, cancel

SC_TEST_REPORT = 'FARM_STORAGE_PASS checks=' .. checks
print(SC_TEST_REPORT)
