-- SPDX-License-Identifier: MIT
-- Disposable real camp stock, storage transactions and native wash actions.
-- The shipping controllers own movement, queues, transformations and deposits.
local Probe = {}
local function countOpen(base)
    local result = 0
    for _, job in ipairs(base.jobs or {}) do
        if job.type == 'wash_dressings' and job.state ~= 'completed' and job.state ~= 'cancelled' then
            result = result + 1
        end
    end
    return result
end
local function refreshContext(s, check)
    local SC = SurvivorCompanion
    local context = SC.GameplayUtil.actorState(s.actor)
    local snapshot = SC.Senses.snapshot(s.actor, s.primary, context)
    check(type(snapshot)=='table' and snapshot.valid==true, 'native camp receives an actual valid world observation')
    check(SC.Medical.canTreatNow(s.actor, snapshot)==true,
        'actual loaded camp remains semi-safe; threats='..tostring(snapshot.threatCount)..'; close='..tostring(snapshot.closeThreatCount))
    return context
end
local function freeSquares(origin, actor)
    local U, result = SurvivorCompanion.GameplayUtil, {}
    for radius = 2, 5 do
        for dx = -radius, radius do for dy = -radius, radius do
            if math.abs(dx) == radius or math.abs(dy) == radius then
                local square = getCell():getGridSquare(origin:getX()+dx, origin:getY()+dy, origin:getZ())
                if square and U.isSquareFree(square) and not U.squareOccupyingObject(square)
                    and U.distanceSq(square, actor) > 1 then
                    local separated = true
                    for _, prior in ipairs(result) do if U.distanceSq(square, prior) < 4 then separated = false end end
                    if separated then result[#result+1] = square; if #result == 2 then return result end end
                end
            end
        end end
    end
    return result
end
local function crate(square, category, check)
    local object = IsoThumpable.new(getCell(), square, 'carpentry_01_16', false, {})
    object:setIsContainer(true); object:setContainer(ItemContainer.new('crate', square, object))
    local container = object:getContainer()
    container:setCapacity(100); container:setExplored(true)
    square:AddSpecialObject(object); square:RecalcAllWithNeighbours(true)
    local okay, row = SurvivorCompanion.BaseLife.registerStorage(object, category)
    check(okay, 'native camp registers its '..category..' storage: '..tostring(row))
    return { object=object, container=container, row=row }
end
local function observe(s, check)
    local SC, state = SurvivorCompanion, s.campAcceptance
    local batch = state.job and state.job.target and state.job.target.dressingBatch
    if batch then
        check(#batch.ids <= 8, 'native camp receipt never exceeds eight selected stock identities')
        if not state.selected then
            state.selected, state.selectedCount = {}, #batch.ids
            for index, id in ipairs(batch.ids) do
                check(state.originals[id] ~= nil and batch.types[index]=='Base.BandageDirty',
                    'the saved batch selects an exact dirty identity from its registered source')
                state.selected[id] = true
            end
        end
        for index, id in ipairs(batch.ids) do
            if id ~= 0 and batch.washed[index] then
                check(batch.types[index]=='Base.Bandage' and not state.originals[id],
                    'native replacement publishes a distinct clean identity in the same receipt slot')
                state.outputIds[id] = true
            end
        end
    end
    if SC.NativeActions.workKind(s.actor)=='wash_bandage' then state.sawNativeWash=true end
    check(state.personal:getContainer()==s.actor:getInventory()
        and state.personal:getFullType()=='Base.BandageDirty', 'personal carried lookalike remains untouched throughout camp work')
    check(state.protected:getContainer()==state.source.container
        and state.protected:getFullType()=='Base.BandageDirty', 'quest-protected source stock remains untouched throughout camp work')
end
function Probe.step(s, check, note, phase)
    local SC, actor, now = SurvivorCompanion, s.actor, getTimestampMs()
    if s.phase=='acceptance-camp-start' then
        -- A single fixture population reset in the disposable cloned save.
        -- Later danger is observed normally and must fail the safety check.
        check(not s.campPopulationPrepared, 'camp fixture population is prepared exactly once')
        s.campPopulationPrepared = true
        local zombies, removed = getCell():getZombieList(), 0
        for index=zombies:size()-1,0,-1 do
            local zombie = zombies:get(index)
            zombie:removeFromWorld(); zombie:removeFromSquare()
            if zombies:contains(zombie) then zombies:remove(zombie) end
            check(not zombies:contains(zombie), 'fixture removal retires the loaded native zombie actor')
            removed = removed + 1
        end
        note('camp_fixture_loaded_zombies_removed_once='..removed..'; navigation_paths_flags_states_unchanged=true')
        SC.Senses.reset(actor)
        phase('acceptance-camp-prepared')
    elseif s.phase=='acceptance-camp-prepared' then
        if now-s.at<1000 then return end
        local downtime = SC.Downtime.peek(actor)
        if downtime and downtime.active then
            check(SC.Downtime.cancel(actor, 'camp_medical_fixture'), 'active personal downtime releases through its own controller')
        end
        downtime = SC.Downtime.peek(actor)
        check(not downtime or not downtime.active, 'no personal downtime activity remains before camp acceptance')
        local nativeKind = SC.NativeActions.workKind(actor)
        check(nativeKind==nil or s.carriedWash and SC.NativeActions.ownsDowntimeAction(actor,s.carriedWash.activity),
            'camp fixture only releases its own carried-wash native record')
        check(SC.NativeActions.cancelWork(actor, 'camp_medical_fixture'), 'personal native owner releases before camp acceptance')
        check(SC.BaseWork.reset(actor), 'prior camp work state releases before native acceptance')
        SC.BaseLife.reset(); SC.BandageWashing.reset()
        local entries = assert(SC.BandageWash.inventoryEntries(actor))
        for _, row in ipairs(entries) do
            if SC.BandageWash.cleanType(row.item) or SC.BandageWash.isClean(row.item)
                or row.item:getFluidContainer() then row.source:Remove(row.item) end
        end
        actor:getBodyDamage():RestoreToFullHealth()
        local source = assert(s.findSource(), 'real loaded clean camp water source exists')
        local core = source:getSquare()
        check(SC.BaseLife.create(core, 'Native medical washing camp'), 'real companion camp is created')
        local base = SC.BaseLife.active()
        base.settings.autoMaintenance, base.settings.routines, base.settings.workload = false, false, 'essential'
        base.settings.workOutsideAtNight = true
        local squares = freeSquares(core, actor)
        check(#squares==2, 'two native storage fixture squares are free near the proven sink')
        local stock, medical = crate(squares[1], 'general', check), crate(squares[2], 'medical', check)
        local protected = assert(stock.container:AddItem('Base.BandageDirty'))
        protected:getModData().LF_QuestItem = true
        local originals = {}
        for _=1,9 do
            local item = assert(stock.container:AddItem('Base.BandageDirty')); originals[item:getID()] = item
        end
        local personal = assert(actor:getInventory():AddItem('Base.BandageDirty'))
        personal:setFavorite(true)
        personal:getModData().SC_PersonalOwnerId, personal:getModData().SC_PersonalKey = SC.Registry.idOf(actor), 'camp-medical-control'
        local id = assert(SC.Registry.idOf(actor))
        check(SC.BaseLife.assign(id, 'medic', true), 'native resident receives the medic role')
        check(SC.Commands.issue(id, 'base_duty', {}, s.primary), 'native medic receives camp duty')
        local stats = actor:getStats()
        stats:set(CharacterStat.HUNGER,0.05); stats:set(CharacterStat.THIRST,0.05)
        stats:set(CharacterStat.FATIGUE,0.05); stats:set(CharacterStat.ENDURANCE,1)
        s.campAcceptance = { base=base, source=stock, medical=medical, originals=originals,
            protected=protected, personal=personal, audit={}, outputIds={}, deadline=now+150000,
            context=refreshContext(s, check) }
        phase('acceptance-camp-audit')
    elseif s.phase=='acceptance-camp-audit' then
        local state = s.campAcceptance
        check(now<state.deadline, 'bounded native camp audit finishes within its deadline')
        state.context = refreshContext(s, check)
        local okay, result, pending = SC.BandageWashing.audit(state.base, nil, state.audit)
        if not okay then
            check(pending==true, 'camp audit only waits on its bounded water or stock scan: '..tostring(result))
            return
        end
        state.job = result
        check(type(result)=='table' and result.type=='wash_dressings' and result.priority==4,
            'shipping audit creates its priority-four wash job')
        check(result.target.sourceId==state.source.row.id and countOpen(state.base)==1,
            'native camp audit selects its exact registered dirty stock source')
        local duplicate, why = SC.BandageWashing.audit(state.base, nil, {})
        check(not duplicate and why=='dressing_wash_already_queued' and countOpen(state.base)==1,
            'the actual open camp job suppresses duplicate washing jobs')
        phase('acceptance-camp-running')
    elseif s.phase=='acceptance-camp-running' then
        local state = s.campAcceptance
        check(now<state.deadline, 'native camp fetch/wash/deposit completes within150 seconds; last='..tostring(state.last))
        state.context = refreshContext(s, check)
        SC.ActionSupervisor.update(actor)
        if not SC.NativeActions.pacingStatus(actor) then
            local okay, why = SC.BaseWork.update(actor, s.primary, state.context)
            state.last = tostring(okay)..'/'..tostring(why)
        end
        observe(s, check)
        check(state.job.state~='blocked' and state.job.state~='cancelled',
            'native camp job retains normal ownership: '..tostring(state.job.blocker)..'; '..tostring(state.last))
        if state.job.state~='completed' then return end
        check(state.selectedCount==8 and state.sawNativeWash, 'camp worker fetches eight exact inputs and executes native washing')
        check(state.job.target.dressingBatch==nil and countOpen(state.base)==0,
            'completed native washing releases its saved batch and open-job claim')
        local remaining = 0
        for id, original in pairs(state.originals) do
            if state.selected[id] then
                check(not SC.GameplayUtil.containerContainsIdentity(state.source.container, original)
                    and not SC.GameplayUtil.containerContainsIdentity(actor:getInventory(), original),
                    'selected original dirty native item is consumed rather than shelved')
            else
                check(original:getContainer()==state.source.container, 'ninth eligible dirty stock identity remains at its source')
                remaining = remaining + 1
            end
        end
        check(remaining==1 and s.count(state.source.container,'Base.BandageDirty')==2,
            'batch cap leaves exactly the ninth input and protected source control')
        local outputItems, unique = state.medical.container:getItems(), {}
        check(outputItems:size()==8, 'Medical storage receives exactly eight native replacement items')
        for index=0,outputItems:size()-1 do
            local output = outputItems:get(index); local id = output:getID()
            check(output:getFullType()=='Base.Bandage' and not state.originals[id] and not unique[id],
                'each Medical deposit is a distinct actual clean native replacement')
            check(output:getModData().LF_DressingWashJob==nil and not SC.BandageWashing.reserved(output),
                'each delivered native output releases only its completed wash claim')
            unique[id] = true
        end
        check(SC.BaseLife.storage(state.medical.row.id)==state.medical.row and state.medical.row.category=='medical',
            'all replacement deposits use the current registered Medical category')
        check(SC.NativeActions.workKind(actor)==nil and SC.NativeActions.visualStatus(actor,'loot_container')~='active',
            'finished native camp work releases its action and Loot pose')
        note('acceptance_camp_batch=8; eligible_stock_remaining=1; medical_native_outputs=8; dedup=true; personal_and_quest_controls_untouched=true')
        return true
    end
end
return Probe
