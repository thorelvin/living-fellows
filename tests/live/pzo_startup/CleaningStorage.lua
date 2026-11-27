-- SPDX-License-Identifier: MIT
-- Disposable native PZO world. Only fixture companions receive LF orders;
-- the game's zombie navigation is untouched.
local SC, s = LivingFellows, { phase = 'menu', checks = 0 }
local function write(name, text)
    local writer = assert(getFileWriter(name, true, false))
    writer:write(text); writer:close()
end
local function check(value, message)
    s.checks = s.checks + 1
    assert(value, 'cleaning storage ' .. s.checks .. ': ' .. message)
end
local function finish(okay, reason)
    if s.done then return end
    s.done = true
    local text = 'result=' .. (okay and 'PASS' or 'FAIL') .. '\nphase=' .. s.phase
        .. '\nreason=' .. tostring(reason) .. '\nchecks=' .. s.checks
        .. '\nlast_work=' .. tostring(s.work) .. '\nmax_tick_gap_ms=' .. tostring(s.maxGap)
        .. '\nmop_id=' .. tostring(s.mop and s.mop:getID())
        .. '\nbroom_id=' .. tostring(s.broom and s.broom:getID()) .. '\n'
    print('SC_PZO_CLEANING ' .. text)
    write('pzo-cleaning-result.txt', text)
end
local function phase(name, now)
    s.phase, s.at = name, now
    print('SC_PZO_CLEANING phase=' .. name)
    write('pzo-cleaning-progress.txt', name .. '\n')
end
local function crate(x, y, category)
    local sq = assert(getCell():getGridSquare(x, y, 0), 'crate square unloaded')
    local o = IsoThumpable.new(getCell(), sq, 'carpentry_01_16', false, {})
    o:setIsContainer(true); o:setContainer(ItemContainer.new('crate', sq, o))
    o:getContainer():setCapacity(100); o:getContainer():setExplored(true)
    sq:AddSpecialObject(o); sq:RecalcAllWithNeighbours(true)
    local okay, row = SC.BaseLife.registerStorage(o, category)
    check(okay, 'native ' .. category .. ' crate registered: ' .. tostring(row))
    return { row = row, container = o:getContainer(), object = o }
end
local function itemRole(item)
    check(item:hasTag(ItemTag.CLEAN_STAINS), item:getFullType() .. ' native cleaning tag')
    check(item:getCategory() == 'Weapon' and item:getDisplayCategory() == 'HouseholdWeapon',
        item:getFullType() .. ' reproduces the native weapon/display category')
    check(SC.BaseWork.classifyItem(item) == 'tools', item:getFullType() .. ' camp classifier uses Tools')
    check(SC.Logistics.itemCategory(item) == 'tools', item:getFullType() .. ' logistics classifier uses Tools')
end
Events.OnInitGlobalModData.Add(function()
    ModData.getOrCreate(SC.Identity.worldSaveKey).document = {
        schema = SC.Identity.saveSchema, companions = {}, factionActors = {} }
end)
Events.OnMainMenuEnter.Add(function()
    MainScreen.continueLatestSave('Sandbox', 'PzoRestoreFixture')
end)
local seen = {}
Events.OnRenderTick.Add(function()
    local modal = MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not seen[modal] then seen[modal] = true; modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister('decision')
    s.primary = assert(getSpecificPlayer(0))
    s.primary:teleportTo(6428.5, 5449.5, 0)
    phase('load', getTimestampMs())
end)
local function update()
    -- Decision normally admits BaseWork after this gate. The controlled job
    -- probe replaces unrelated decisions, but must still honor that pause.
    SC.ActionSupervisor.update(s.actor)
    if SC.NativeActions.pacingStatus(s.actor) then s.work = 'normal_action_pacing'; return end
    local okay, why = SC.BaseWork.update(s.actor, s.primary, { snapshot = { threatCount = 0, immediateCount = 0 } })
    s.work = tostring(okay) .. '/' .. tostring(why)
    local navigation = SC.Navigation.peek(s.actor)
    check(not navigation or not string.find(tostring(navigation.lastMovementReason), 'action_pacing:', 1, true),
        'repayment must not record a path rejection during normal pacing')
end
local function step()
    if s.done or s.phase == 'menu' then return end
    local now = getTimestampMs()
    if s.lastTick and s.phase ~= 'load' then s.maxGap = math.max(s.maxGap or 0, now - s.lastTick) end
    s.lastTick = now
    if s.phase == 'load' then
        if now - s.at < 12000 then return end
        check(SCBridge and PZOEngine and SC.Actor.checkBridge(true), 'actual PZO and native companion provider')
        SC.BaseLife.reset()
        local centre = assert(getCell():getGridSquare(6428, 5449, 0))
        check(SC.BaseLife.create(centre, 'Native cleaning storage'), 'native camp created')
        local base = SC.BaseLife.active()
        base.settings.autoMaintenance, base.settings.routines, base.settings.workload = false, false, 'essential'
        s.weapons, s.ammo = crate(6433, 5446, 'weapons'), crate(6433, 5449, 'ammunition')
        s.tools, s.general = crate(6433, 5452, 'tools'), crate(6436, 5452, 'general')
        s.mop = assert(s.weapons.container:AddItem('Base.Mop'))
        s.broom = assert(instanceItem('Base.Broom'))
        itemRole(s.mop); itemRole(s.broom)
        s.bleach = assert(s.tools.container:AddItem('Base.Bleach'))
        local fluid = assert(s.bleach:getFluidContainer())
        fluid:Empty(); fluid:addFluid(Fluid.Bleach, 1)
        s.before = fluid:getAmount()
        local spawn = assert(getCell():getGridSquare(6430, 5450, 0))
        s.ticket = assert(SC.Actor.beginSpawn(spawn, { recruited = true,
            identity = { forename = 'Cleaning', surname = 'Tester', gender = 'woman', outfit = 'Generic01' } }))
        phase('spawn', now)
    elseif s.phase == 'spawn' then
        local actor, why = SC.Actor.pollSpawn(s.ticket)
        if not actor then check(why == 'spawn_pending' and now - s.at < 15000, tostring(why)); return end
        s.actor, s.id = actor, assert(SC.Registry.idOf(actor))
        check(SC.BaseLife.assign(s.id, 'maintainer', true), 'native worker assigned')
        check(SC.Commands.issue(s.id, 'base_duty', {}, s.primary), 'native worker ordered to camp duty')
        local stats = actor:getStats()
        stats:set(CharacterStat.HUNGER, 0.05); stats:set(CharacterStat.THIRST, 0.05)
        stats:set(CharacterStat.FATIGUE, 0.05); stats:set(CharacterStat.ENDURANCE, 1)
        SC.CleaningSupplies.reset()
        phase('supplies', now)
    elseif s.phase == 'supplies' then
        local plan, why = SC.CleaningSupplies.plan(s.actor)
        if not plan then check(why == 'cleaning_supplies_scanning' and now - s.at < 30000, tostring(why)); return end
        check(plan.tool.item == s.mop and plan.tool.storageId == s.weapons.row.id,
            'real cleaning planner finds the exact mop on the Weapons shelf')
        check(plan.liquid.item == s.bleach and plan.mode == 'undiluted', 'real native cleaner selected')
        s.square = s.actor:getSquare()
        addBloodSplat(s.square, 20)
        check(s.square:haveStains(), 'native stains added')
        local okay, job = SC.BaseLife.requestCleaning(s.square)
        check(okay, 'native cleaning request accepted: ' .. tostring(job))
        job.assignedId = s.id; s.cleanJob = job.id
        phase('clean', now)
    elseif s.phase == 'clean' then
        update()
        local job = SC.BaseLife.job(s.cleanJob)
        if job then
            check(job.state ~= 'blocked' and now - s.at < 100000,
                'native cleaning pending: ' .. tostring(job.blocker) .. '/' .. tostring(s.work)); return
        end
        check(not s.square:haveStains(), 'native cleaning removed the stains')
        check(s.mop:getContainer() == s.weapons.container and s.bleach:getContainer() == s.tools.container,
            'exact cleaning loans returned to their recorded source shelves')
        local spent = s.before - s.bleach:getFluidContainer():getAmount()
        check(math.abs(spent - SC.CleaningSupplies.dose()) < 0.002, 'exactly one native cleaning dose spent: ' .. spent)
        for _, item in ipairs({ s.mop, s.bleach }) do
            for _, marker in pairs(SC.CleaningSupplies.MARKERS) do
                check(item:getModData()[marker] == nil, 'native cleaning loan released ' .. marker)
            end
        end
        s.ammo.container:AddItem(s.broom)
        local okay, job = SC.BaseLife.enqueueJob({ type = 'sort', priority = 4, target = {} })
        check(okay, 'ordinary sorting request accepted')
        job.assignedId = s.id; s.sortJob, s.sortJobs = job.id, 1
        phase('sort', now)
    elseif s.phase == 'sort' then
        update()
        if s.mop:getContainer() ~= s.tools.container or s.broom:getContainer() ~= s.tools.container then
            local job = SC.BaseLife.job(s.sortJob)
            -- One ordinary sort job owns one homogeneous stack. The camp
            -- queues another job for a different item type on its next pass.
            if not job then
                check(s.sortJobs == 1, 'at most two ordinary sorting batches are needed')
                local okay, nextJob = SC.BaseLife.enqueueJob({ type = 'sort', priority = 4, target = {} })
                check(okay, 'second ordinary sorting batch accepted')
                nextJob.assignedId = s.id; s.sortJob, s.sortJobs = nextJob.id, s.sortJobs + 1
                return
            end
            check(job and job.state ~= 'blocked' and now - s.at < 100000,
                'native sorting pending: ' .. tostring(job and job.blocker) .. '/' .. tostring(s.work)); return
        end
        check(s.weapons.container:getItems():isEmpty() and s.ammo.container:getItems():isEmpty(),
            'misfiled native mop and broom leave both weapon/ammunition crates')
        check(s.general.container:getItems():isEmpty(), 'sorting does not refill General source')
        check(s.actor:getBodyDamage():getOverallBodyHealth() >= 99.9, 'native worker stayed healthy')
        phase('soak', now)
    elseif s.phase == 'soak' then
        update()
        check(s.mop:getContainer() == s.tools.container and s.broom:getContainer() == s.tools.container,
            'native identities remain in Tools without a sorting loop')
        if now - s.at >= 15000 then finish(true, 'native classification, wrong-shelf loan, cleaning dose, repayment and corrective sorting') end
    end
end
Events.OnTick.Add(function()
    if s.done then return end
    local okay, why = pcall(step)
    if not okay then finish(false, why) end
end)
