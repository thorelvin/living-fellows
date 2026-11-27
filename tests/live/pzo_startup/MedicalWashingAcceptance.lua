-- SPDX-License-Identifier: MIT
-- Disposable native acceptance fixture. Production owns queues and all effects.
local SC = LivingFellows
local function clearSupplies(actor)
    local entries = assert(SC.BandageWash.inventoryEntries(actor))
    for _, row in ipairs(entries) do
        if SC.BandageWash.cleanType(row.item) or SC.BandageWash.isClean(row.item)
            or row.item:getFluidContainer() then row.source:Remove(row.item) end
    end
end
local function water(root, kind, amount)
    local item = assert(root:AddItem('Base.WaterBottle'))
    local fluid = assert(item:getFluidContainer())
    fluid:Empty(); fluid:addFluid(kind, amount)
    return item, fluid
end
local function step(s, check, note, phase)
    local actor, U, N, W, D = s.actor, SC.GameplayUtil, SC.NativeActions, SC.BandageWash, SC.Downtime
    local now = getTimestampMs()
    if s.phase == 'acceptance-wash-start' then
        check(N.cancelWork(actor, 'medical_wash_fixture'), 'previous native work releases before wash acceptance')
        D.cancel(actor, 'medical_wash_fixture')
        clearSupplies(actor)
        actor:getBodyDamage():RestoreToFullHealth()
        local source = assert(s.findSource(), 'loaded clean world source required for personal batch')
        local targets = SC.Navigation.interactionTargets(actor, source, {requireDirectAccess=true})
        check(type(targets)=='table' and #targets>0, 'native water source has a companion interaction tile')
        local target = targets[1]
        actor:teleportTo(target:getX()+0.5, target:getY()+0.5, target:getZ())
        s.washSource = source
        phase('acceptance-wash-world-setup')
    elseif s.phase == 'acceptance-wash-world-setup' then
        if N.pacingStatus and N.pacingStatus(actor) then
            check(now - (s.at or now) < 30000, 'medical result pacing settles before personal washing')
            return
        end
        check(U.directInteractionAccess(actor, s.washSource)==true, 'native companion stands in direct source reach')
        local root = actor:getInventory()
        s.washBag = assert(root:AddItem('Base.Bag_Schoolbag')):getInventory()
        s.washDirty = {assert(s.washBag:AddItem('Base.BandageDirty')), assert(s.washBag:AddItem('Base.RippedSheetsDirty'))}
        s.washDirty[1]:setFavorite(true); s.washDirty[1]:setName('Native medical acceptance'); s.washDirty[1]:setCustomName(true)
        local stateFor = select(12, D._furnitureForTests())
        local state = stateFor(actor)
        state.washSourceSurvey = {complete=true,source=s.washSource,square=s.washSource:getSquare(),
            originKey=U.squareKey(actor:getSquare()),expiresAt=now+90000}
        local pick = select(9, D._washForTests())
        local activity = pick(actor, {}, state, now, {threatCount=0,immediateCount=0})
        check(activity and activity.score==85 and #activity.washBatch==2, 'production personal candidate pins exact two-item batch at score85')
        local commands = SC.Commands.peek(actor); commands.order='stay'
        local begin = select(11, D._washForTests())
        local okay, why = begin(actor, state, activity, commands, now)
        check(okay, 'production personal batch starts stock native action: '..tostring(why))
        s.washActivity, s.washState, s.washDeadline = activity, state, now+90000
        phase('acceptance-wash-world-running')
    elseif s.phase == 'acceptance-wash-world-running' then
        check(now<s.washDeadline, 'personal native batch finishes within90 seconds')
        D.update(actor, s.primary, {snapshot={threatCount=0,immediateCount=0}})
        if s.washState.active then return end
        local activity = s.washActivity
        check(activity.fact.washedCount==2, 'production visit verifies both native replacements')
        check(s.count(s.washBag,'Base.Bandage')==1 and s.count(s.washBag,'Base.RippedSheets')==1,
            'both exact native outputs return to original carried bag')
        check(not U.containerContainsIdentity(s.washBag,s.washDirty[1]) and not U.containerContainsIdentity(s.washBag,s.washDirty[2]),
            'consumed dirty identities are absent after personal batch')
        local named
        for i=0,s.washBag:getItems():size()-1 do
            local item=s.washBag:getItems():get(i)
            if item:getFullType()=='Base.Bandage' then named=item end
        end
        check(named and named:isFavorite() and named:isCustomName() and named:getName()=='Native medical acceptance',
            'native personal replacement preserves favorite and custom name')
        note('acceptance_personal_batch=2; outputs_same_bag=true; native_visual_queue=true')
        phase('acceptance-wash-carried-setup')
    elseif s.phase == 'acceptance-wash-carried-setup' then
        if N.pacingStatus and N.pacingStatus(actor) then
            check(now - (s.at or now) < 30000, 'personal batch result pacing settles before carried washing')
            return
        end
        clearSupplies(actor)
        local root=actor:getInventory()
        local dirty=assert(s.washBag:AddItem('Base.BandageDirty'))
        local vessel,tainted=water(root,Fluid.TaintedWater,1)
        local reserve,clean=water(root,Fluid.Water,1)
        local protected,protectedFluid=water(root,Fluid.Water,1)
        protected:setFavorite(true)
        local plan=W.carriedWaterPlan(actor)
        check(plan and plan.item==vessel, 'production carried water policy selects exact tainted vessel')
        local activity=assert(W.makeActivity(actor,dirty,{waterPlan=plan}))
        check(SC.NativeCareActions.prepare(actor,activity), 'production carried branch prepares exact input and vessel')
        local okay,why=N.startDowntimeAction(actor,activity,function()
            return W.waterPlanValid(actor,activity.washWaterPlan)
                and W.isInputAllowed(actor,activity.item,nil,nil,activity.washInputEntry)
        end)
        check(okay,'production carried branch queues stock handcraft: '..tostring(why))
        s.carriedWash={activity=activity,dirty=dirty,vessel=vessel,tainted=tainted,clean=clean,protected=protectedFluid,deadline=now+60000}
        phase('acceptance-wash-carried-running')
    elseif s.phase == 'acceptance-wash-carried-running' then
        local row=s.carriedWash
        check(now<row.deadline,'carried native wash finishes within60 seconds')
        if N.isWorkActive(actor) then return end
        local settled=N.finishWork(actor)
        if settled~=true then return end
        local activity=row.activity
        check(activity.nativeCompleted==true and activity.resultVerification and activity.resultVerification.verified,
            'production carried effect has exact verified transformation receipt')
        check(math.abs(row.tainted:getAmount()-0.5)<0.0001 and math.abs(row.clean:getAmount()-1)<0.0001
            and math.abs(row.protected:getAmount()-1)<0.0001,'only pinned tainted vessel loses0.5L')
        check(activity.nativeOutput and U.containerContainsIdentity(s.washBag,activity.nativeOutput)
            and not U.containerContainsIdentity(s.washBag,row.dirty),'exact carried native replacement returns to original bag')
        note('acceptance_carried_wash=0.5L_tainted; clean_and_protected_controls_untouched=true; same_bag=true')
        return true
    end
end
return {step=step}
