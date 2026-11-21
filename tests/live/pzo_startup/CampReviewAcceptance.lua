-- SPDX-License-Identifier: MIT
-- Disposable native PZO acceptance. Driven through the real camp controllers.
local SC = SurvivorCompanion
local s = {phase="menu", notes={}, seen={}}
local function evidence(key, value)
    s.notes[#s.notes+1] = key.."="..tostring(value)
end
local function write(file, data)
    local out = assert(getFileWriter(file, true, false))
    out:write(data.."\n")
    out:close()
end
local function phase(name, limit)
    s.phase, s.untilMs = name, getTimestampMs()+(limit or 30000)
    write("pzo-camp-review-progress.txt", name.."\n"..table.concat(s.notes,"\n"))
end
local function finish(result, reason)
    write("pzo-camp-review-result.txt","result="..result.."\nphase="..s.phase
        .."\nreason="..tostring(reason).."\nlast="..tostring(s.last).."\n"..table.concat(s.notes,"\n"))
    s.phase="done"
end
local function context(actor)
    local runtime=SC.GameplayUtil.actorState(actor)
    local snap=SC.Senses.snapshot(actor,s.primary,runtime)
    assert(snap and snap.valid,"no world snapshot")
    return runtime
end
local function squares()
    local origin=s.primary:getSquare()
    local same,all={},{}
    for dx=-5,5 do for dy=-5,5 do
        local q=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
        if q and SC.GameplayUtil.isClearActorSpawnSquare(q) and q:isFree(false) then
            all[#all+1]=q
            if q:getRoom()==origin:getRoom() then same[#same+1]=q end
        end
    end end
    for _,rows in ipairs({same,all}) do
        for _,a in ipairs(rows) do for _,b in ipairs(rows) do
            local distance=SC.GameplayUtil.distanceSq(a,b)
            if distance>=16 and distance<=36 then return a,b end
        end end
    end
    error("no suitable clear native floor")
end
local function spawn(q,name,apart)
    local opts={recruited=true,identity={forename="Camp",surname=name,gender="woman",outfit="Generic01"}}
    local function attempt(candidate)
        if candidate and candidate~=s.primary:getSquare() and SC.GameplayUtil.isClearActorSpawnSquare(candidate)
            and (not apart or SC.GameplayUtil.distanceSq(candidate,apart)>=16) then
            return SC.Actor.beginSpawn(candidate,opts)
        end
    end
    local ticket=attempt(q)
    if ticket then return ticket end
    local origin=s.primary:getSquare()
    for radius=1,8 do for dx=-radius,radius do for dy=-radius,radius do
        if math.abs(dx)==radius or math.abs(dy)==radius then
            local tile=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            ticket=attempt(tile)
            if ticket then return ticket end
        end
    end end end
    error("no safe square for "..name)
end
local function poll(ticket)
    local actor,why=SC.Actor.pollSpawn(ticket)
    assert(actor or why=="spawn_pending",tostring(why))
    return actor
end
local function register(actor,role)
    local id=assert(SC.GameplayUtil.idOf(actor))
    assert(SC.BaseLife.assign(id,role,true))
    assert(SC.Commands.issue(id,"base_duty",{},s.primary))
    return id
end
local function makeCamp(core)
    assert(SC.BaseLife.create(core or s.primary:getSquare(),"Camp review fixture"))
    s.base=SC.BaseLife.active()
    s.base.settings.autoMaintenance=true
    s.base.settings.routines=false
    s.base.settings.workload="essential"
    s.base.settings.workOutsideAtNight=true
end
local function jobOf(kind,owner)
    for _,j in ipairs(s.base.jobs) do
        if j.type==kind and j.assignedId==owner and j.state~="completed" and j.state~="cancelled" then return j end
    end
end
local function kill(actor)
    actor:setGodMod(false)
    actor:getBodyDamage():ReduceGeneralHealth(110)
    actor:setHealth(0)
    if not actor:isDead() then actor:Kill(nil) end
    assert(actor:isDead(),"native death")
end
local function retire(actor,id)
    if SC.BaseWork.workerUnregistered(id) then return true end
    local okay,why=SC.Actor.retireDead(actor)
    s.last=why
    return okay and SC.BaseWork.workerUnregistered(id)
end
local function foodStore()
    local u=SC.GameplayUtil
    local origin=s.medic:getSquare()
    local q
    for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
        local tile=getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
        if tile and tile:getRoom()==origin:getRoom() and tile:isFree(false)
            and not u.squareOccupyingObject(tile) and u.directInteractionAccess(s.medic,tile) then q=tile;break end
    end
    assert(q,"no adjacent directly accessible shelf tile")
    -- Keep the real camp scanner on the cooking station and the first chef's
    -- post. Nearby house cupboards in this seed can be behind closed doors.
    local original=s.base.zones[1].id
    assert(SC.BaseLife.beginZone("area",origin))
    assert(SC.BaseLife.finishZone(q,"Kitchen"))
    assert(SC.BaseLife.beginZone("area",s.chef:getSquare()))
    assert(SC.BaseLife.finishZone(s.chef:getSquare(),"First chef position"))
    assert(SC.BaseLife.removeZone(original))
    local object=IsoThumpable.new(getCell(),q,"carpentry_01_16",false,{})
    object:setIsContainer(true)
    object:setContainer(ItemContainer.new("crate",q,object))
    local store=object:getContainer()
    store:setCapacity(100)
    store:setExplored(true)
    q:AddSpecialObject(object)
    q:RecalcAllWithNeighbours(true)
    assert(u.directInteractionAccess(s.medic,object),"chef has direct access to actual meal container")
    evidence("kitchen","chef="..origin:getX()..","..origin:getY().." shelf="..q:getX()..","..q:getY().." direct_access=true")
    local ok,row=SC.BaseLife.registerStorage(object,"fresh_food")
    assert(ok and SC.BaseLife.resolveContainer(row)==store,tostring(row))
    return store
end
local function drive(actor)
    SC.ActionSupervisor.update(actor)
    if not SC.NativeActions.pacingStatus(actor) then
        local _,why=SC.BaseWork.update(actor,s.primary,context(actor))
        s.last=why
    end
end
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start",120000) end)
local function step()
    if s.phase=="menu" then
        local modal=MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not s.seen[modal] then s.seen[modal]=true;modal:onClick(modal.yes) end
        return
    end
    assert(getTimestampMs()<s.untilMs,"native fixture phase timed out")
    if s.phase=="start" then
        s.primary=getSpecificPlayer(0)
        if not s.primary or not s.primary:getSquare() then return end
        assert(SC.BaseWork.reset())
        SC.BaseLife.reset()
        SC.MedicalVisits.reset()
        makeCamp()
        s.a,s.b=squares()
        s.ticket=spawn(s.a,"Patient")
        phase("patient-spawn")
    elseif s.phase=="patient-spawn" then
        s.patient=poll(s.ticket)
        if not s.patient then return end
        s.ticket=spawn(s.b,"Medic",s.patient)
        phase("medic-spawn")
    elseif s.phase=="medic-spawn" then
        s.medic=poll(s.ticket)
        if not s.medic then return end
        s.patientId=register(s.patient,"generalist")
        s.medicId=register(s.medic,"medic")
        s.medic:getBodyDamage():RestoreToFullHealth()
        s.patient:getBodyDamage():RestoreToFullHealth()
        for _,who in ipairs({s.patient,s.medic}) do
            for _,row in ipairs(assert(SC.BandageWash.inventoryEntries(who))) do
                if SC.Medical.dressingRank(row.item,true) or SC.MedicKit.isKit(row.item) then row.source:Remove(row.item) end
            end
        end
        s.dressing=assert(s.medic:getInventory():AddItem("Base.Bandage"))
        local part=s.patient:getBodyDamage():getBodyPart(BodyPartType.Foot_R)
        part:setScratchTime(20)
        part:setBleeding(false)
        part:setBleedingTime(0)
        part:setBandaged(true,0,false,"Base.Bandage")
        SC.Medical.invalidate(s.patient)
        phase("visit")
    elseif s.phase=="visit" then
        context(s.patient)
        context(s.medic)
        SC.MedicalVisits.audit(s.base,function() return math.huge end,{})
        local j=jobOf("replace_bandage",s.medicId)
        if not j then return end
        assert(j.target.patientId==s.patientId)
        s.visit=j
        drive(s.medic)
        local care=SC.Medical.peek(s.medic)
        if not care or not care.supervisorToken then return end
        assert(care.patient==s.patient and SC.ActionSupervisor.isCurrent(care.supervisorToken))
        assert(SC.ActionSupervisor.isReserved(s.dressing),"reserved exact dressing")
        s.care=care
        evidence("mid_visit",j.id.." patient="..s.patientId.." medic="..s.medicId.." dressing="..s.dressing:getID())
        kill(s.patient)
        phase("patient-retire")
    elseif s.phase=="patient-retire" then
        if not retire(s.patient,s.patientId) then return end
        phase("medic-release")
    elseif s.phase=="medic-release" then
        drive(s.medic)
        if jobOf("replace_bandage",s.medicId) then return end
        assert(not SC.Medical.peek(s.medic) and not SC.ActionSupervisor.isCurrent(s.care.supervisorToken))
        assert(not SC.Medical.treatmentHolder(s.patient) and not SC.ActionSupervisor.isReserved(s.dressing))
        assert(s.medic:getInventory():contains(s.dressing))
        assert(SC.BaseLife.abandon())
        assert(not SC.BaseLife.active())
        evidence("patient_retired","visit closed, exact dressing preserved, supervisor and claim released, camp abandoned")
        makeCamp(s.medic:getSquare())
        s.a,s.b=squares()
        s.ticket=spawn(s.a,"FirstChef")
        phase("chef-spawn")
    elseif s.phase=="chef-spawn" then
        s.chef=poll(s.ticket)
        if not s.chef then return end
        s.store=foodStore()
        s.firstId=register(s.chef,"chef")
        for _,kind in ipairs({"Base.Bowl","Base.Tomato","Base.Lettuce","Base.Carrots"}) do
            local item=assert(s.medic:getInventory():AddItem(kind))
            if item.setAge then item:setAge(0) end
        end
        phase("first-cook")
    elseif s.phase=="first-cook" then
        local ok,why=SC.ChefWork.ensureAutomaticJob(s.chef,SC.BaseLife.resident(s.firstId))
        s.last=why
        s.firstJob=jobOf("cook",s.firstId)
        if not s.firstJob then return end
        assert(s.firstJob.target.manual==false)
        evidence("queued_first_cook",s.firstJob.id.." chef="..s.firstId.." state="..s.firstJob.state)
        kill(s.chef)
        phase("chef-retire")
    elseif s.phase=="chef-retire" then
        if not retire(s.chef,s.firstId) then return end
        s.medicId=register(s.medic,"chef")
        phase("second-cook")
    elseif s.phase=="second-cook" then
        SC.BaseLife.auditJobRecovery()
        local ok,why=SC.ChefWork.ensureAutomaticJob(s.medic,SC.BaseLife.resident(s.medicId))
        s.last=why
        s.replacement=jobOf("cook",s.medicId)
        if not s.replacement then return end
        assert(not jobOf("cook",s.firstId) and s.replacement.id~=s.firstJob.id and s.replacement.target.manual==false)
        evidence("replacement_automatic",s.replacement.id.." chef="..s.medicId)
        phase("meal",210000)
    elseif s.phase=="meal" then
        drive(s.medic)
        if not s.diag or getTimestampMs()>s.diag then
            s.diag=getTimestampMs()+2000
            write("pzo-camp-review-progress.txt","meal="..tostring(s.last).." state="..tostring(s.replacement.state).." cook="..tostring(s.replacement.target.cookPhase).." reason="..tostring(s.replacement.reason).."\n"..table.concat(s.notes,"\n"))
        end
        for _,item in ipairs(SC.GameplayUtil.inventoryItems(s.store,200)) do
            if SC.ChefWork.isPrepared(item) and not jobOf("cook",s.medicId) then
                evidence("meal_stored",item:getFullType().." exact_id="..item:getID())
                finish("PASS","surviving medic resumed camp work and stored an automatic meal")
                return
            end
        end
    end
end
Events.OnRenderTick.Add(function()
    if s.phase=="done" then return end
    local ok,why=pcall(step)
    if not ok then finish("FAIL",why) end
end)
