-- SPDX-License-Identifier: MIT
-- A shovel has an explicitly valid secondary home in Weapons. The farmer
-- must borrow/return that exact tool before switching to the seed packet.
local SC, F = SurvivorCompanion, FarmLifecycleFixture
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
SC_TEST_REPORT = 'FARM_STORAGE_PASS checks=' .. checks
print(SC_TEST_REPORT)
