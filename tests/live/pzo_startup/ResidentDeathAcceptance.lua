-- SPDX-License-Identifier: MIT
-- Loaded only in a disposable native save. The disk phase runs in a new client.
local SC = LivingFellows
local B, U = SC.BaseLife, SC.GameplayUtil
local s = {phase="menu",seen={},notes={}}
local function read(file)
    local input=getFileReader(file,false)
    if not input then return end
    local line=input:readLine();input:close();return line
end
local function write(file, body)
    local output=assert(getFileWriter(file,true,false));output:write(body.."\n");output:close()
end
local function record(key,value) s.notes[#s.notes+1]=key.."="..tostring(value) end
local function phase(name, ms)
    s.phase,s.untilMs=name,getTimestampMs()+(ms or 45000)
    write("pzo-resident-progress.txt",name.."\n"..table.concat(s.notes,"\n"))
end
local function finish(outcome,why)
    write("pzo-resident-result.txt","result="..outcome.."\nphase="..s.phase.."\nreason="..tostring(why)
        .."\nlast="..tostring(s.last).."\n"..table.concat(s.notes,"\n"))
    s.phase="done"
end
local function boards(window)
    local same=window:getBarricadeOnSameSquare()
    local far=window:getBarricadeOnOppositeSquare()
    return math.max(same and same:getNumPlanks() or 0,far and far:getNumPlanks() or 0)
end
local function findWindow()
    local at=s.player:getSquare()
    for r=0,12 do for dx=-r,r do for dy=-r,r do
        if math.max(math.abs(dx),math.abs(dy))==r then
            local q=getCell():getGridSquare(at:getX()+dx,at:getY()+dy,at:getZ())
            local objects=q and q:getObjects()
            for i=0,objects and objects:size()-1 or -1 do
                local w=objects:get(i)
                if instanceof(w,"IsoWindow") and boards(w)==0 and w:isBarricadeAllowed() then
                    local opposite=getCell():getGridSquare(q:getX()-(w:getNorth() and 0 or 1),
                        q:getY()-(w:getNorth() and 1 or 0),q:getZ())
                    for _,side in ipairs({q,opposite}) do
                        if side~=at and U.isClearActorSpawnSquare(side) and side:isFree(false) then
                            return w,side
                        end
                    end
                end
            end
        end
    end end end
    error("no accessible unfinished window in the loaded seed")
end
local function spawn(origin,name,avoid)
    for r=0,6 do for dx=-r,r do for dy=-r,r do
        if math.max(math.abs(dx),math.abs(dy))==r then
            local q=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
            if q and q~=s.player:getSquare() and q~=avoid and U.isClearActorSpawnSquare(q) and q:isFree(false) then
                local ticket=SC.Actor.beginSpawn(q,{recruited=true,identity={forename="Robin",surname=name,gender="woman",outfit="Generic01"}})
                if ticket then return ticket end
            end
        end
    end end end
    error("no available spawn tile for "..name)
end
local function poll()
    local actor,why=SC.Actor.pollSpawn(s.ticket);assert(actor or why=="spawn_pending",tostring(why));return actor
end
local function assign(actor,role)
    local id=assert(U.idOf(actor))
    assert(B.assign(id,role,true))
    assert(SC.Commands.issue(id,"base_duty",{},s.player))
    return id
end
local function job()
    for _,j in ipairs(B.active().jobs) do
        if j.type=="barricade" and j.target.maintenanceId==s.target then return j end
    end
end
local function staffing(wanted)
    local summary=B.summary()
    local names={}
    for _,row in ipairs(summary.residentRows) do
        assert(row.name and not row.name:match("^sc%-"),"raw identity displayed")
        names[row.id]=row.name
    end
    assert(summary.residents==wanted and summary.duty==wanted and names[s.liveId]
        and (wanted==2)==(names[s.deadId]~=nil),"staffing and on-duty counts")
    local root=SC.UI.open("base",s.liveId)
    root.detail:rebuild(false)
    local prefix=SC.UI.text("UI_SC_Base_StaffingRow","_ROW_"):match("^(.-)_ROW_")
    assert(prefix and #prefix>0,"staffing label translation missing")
    local labels, unique={},{}
    for _,child in pairs(root.detail.content.children or {}) do
        local value=child.tooltip
        if type(value)=="string" and value:sub(1,#prefix)==prefix and not unique[value] then
            assert(not value:find("sc-",1,true),"raw id in native Staffing widget")
            unique[value]=true;labels[#labels+1]=value
        end
    end
    table.sort(labels)
    local rendered=table.concat(labels,", ")
    assert(#labels==wanted and rendered:find(names[s.liveId],1,true)
        and (wanted==2)==(rendered:find("Robin Maintainer",1,true)~=nil),"native Staffing widget: "..rendered)
    record("staffing_panel",rendered)
    SC.UI.close()
    return names
end
local function guards(expected)
    local selected={}
    for n=0,3 do
        local on,id,count=B.guardStatus(s.liveId,n*180000+1)
        assert(count==expected and (id==s.liveId or expected==2 and id==s.deadId),"guard candidates")
        assert(on==(id==s.liveId),"guard duty reflects selected shift")
        selected[id]=true
    end
    assert(selected[s.liveId] and (expected==2)==(selected[s.deadId]==true),"native roster covers every guard shift")
end
local function think()
    local rt=U.actorState(s.live)
    assert(SC.Senses.snapshot(s.live,s.player,rt))
    SC.ActionSupervisor.update(s.live)
    local _,why=SC.Decision.update(s.live,s.player,rt,getTimestampMs())
    s.last=why
end
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start",120000) end)
local function step()
    if s.phase=="menu" then
        local modal=MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not s.seen[modal] then s.seen[modal]=true;modal:onClick(modal.yes) end
        return
    end
    assert(getTimestampMs()<s.untilMs,"native phase timed out")
    if s.phase=="start" then
        s.player=getSpecificPlayer(0)
        if not s.player or not s.player:getSquare() or not SC.Persistence.restoreStatus() then return end
        if read("pzo-world-mode.txt")=="disk-restored" then
            s.liveId,s.deadId,s.target=string.match(assert(read("pzo-resident-ids.txt")),"^(%S+) (%S+) (%S+)$")
            assert(s.deadId and s.target)
            phase("reload",90000);return
        end
        assert(SC.BaseWork.reset());B.reset()
        s.window,s.side=findWindow()
        local q=s.window:getSquare()
        assert(B.create(q,"Window crew"))
        B.active().settings.autoMaintenance=true
        B.active().settings.defense="rotation"
        B.active().settings.routines=false
        B.active().settings.workOutsideAtNight=true
        record("window",q:getX()..","..q:getY()..","..q:getZ())
        s.ticket=spawn(s.side,"Relief")
        phase("survivor-spawn")
    elseif s.phase=="survivor-spawn" then
        s.live=poll();if not s.live then return end
        s.liveId=assign(s.live,"generalist")
        local inv=s.live:getInventory()
        for _,kind in ipairs({"Base.Hammer","Base.Plank","Base.Plank","Base.Nails","Base.Nails","Base.Nails","Base.Nails"}) do
            assert(inv:AddItem(kind))
        end
        s.ticket=spawn(s.side,"Maintainer",s.live:getSquare())
        phase("maintainer-spawn")
    elseif s.phase=="maintainer-spawn" then
        s.dead=poll();if not s.dead then return end
        s.deadId=assign(s.dead,"maintainer")
        local ok,t=B.registerMaintenanceTarget(s.window,"barricade");assert(ok,tostring(t))
        s.target=t.id
        local names=staffing(2);guards(2)
        record("staffing_before",names[s.deadId].." + "..names[s.liveId].."; two on duty, both rotate")
        phase("assigned")
    elseif s.phase=="assigned" then
        SC.BaseWork.auditMaintenance(s.player)
        local j=job();if not j then return end
        assert(j.assignedId==s.deadId and boards(s.window)==0,"window assigned to on-duty maintainer")
        record("old_job",j.id.." owner="..s.deadId)
        s.dead:setGodMod(false);s.dead:getBodyDamage():ReduceGeneralHealth(110);s.dead:setHealth(0)
        if not s.dead:isDead() then s.dead:Kill(nil) end
        assert(s.dead:isDead(),"native death")
        phase("retirement",90000)
    elseif s.phase=="retirement" then
        if SC.Registry.byId(s.deadId) or B.resident(s.deadId) then return end
        assert(SC.BaseWork.workerUnregistered(s.deadId))
        local names=staffing(1);guards(1)
        record("staffing_after",names[s.liveId].."; one on duty, four guard shifts covered")
        phase("upkeep",120000)
    elseif s.phase=="upkeep" then
        SC.BaseWork.auditMaintenance(s.player)
        local j=job()
        if j then
            assert(j.assignedId~=s.deadId and j.reservedBy~=s.deadId,"dead worker released window")
            if not s.claimed then
                local picked=B.claimJob(s.liveId,function(row) return row.id==j.id end)
                if picked and picked.id==j.id and picked.reservedBy==s.liveId then
                    s.claimed=true;record("living_claim",picked.id.." owner="..s.liveId)
                end
            end
        end
        think()
        if boards(s.window)<1 then
            local current=getTimestampMs()
            if not s.traceAt or current-s.traceAt>2500 then
                local md=U.modData(s.live)
                write("pzo-resident-progress.txt",s.phase.."\n"..table.concat(s.notes,"\n")
                    .."\njob="..tostring(j and j.state)..", owner="..tostring(j and j.reservedBy)
                    ..", blocker="..tostring(j and j.blocker)..", decision="..tostring(s.last)
                    ..", order="..tostring(md.SC_Order)..", native="..tostring(SC.NativeActions.workKind(s.live)))
                s.traceAt=current
            end
            return
        end
        assert(s.claimed,"observed successor claim")
        record("native_boards",boards(s.window))
        assert(SC.Persistence.save(s.player),"durable camp roster")
        local doc=assert(ModData.getOrCreate(SC.Identity.worldSaveKey).document)
        assert(doc.baseLife.residents[s.liveId] and not doc.baseLife.residents[s.deadId]
            and not doc.companions[s.deadId],"saved roster and companion snapshot")
        write("pzo-resident-ids.txt",s.liveId.." "..s.deadId.." "..s.target)
        save(false);assert(SCSplitScreenProbe.flushGlobalModDataForWorldExit())
        s.savedAt=getTimestampMs();phase("saved")
    elseif s.phase=="saved" and getTimestampMs()-s.savedAt>3500 then
        finish("PASS","native death, roster, shifts and physical barricade saved")
    elseif s.phase=="reload" then
        local rec=SC.Registry.byId(s.liveId)
        if not rec or not rec.actor then return end
        assert(not B.resident(s.deadId) and not SC.Registry.byId(s.deadId) and not SC.Persistence.isPending(s.deadId),"dead resident returned after disk restart")
        local names=staffing(1);guards(1)
        local w
        for _,t in ipairs(B.active().maintenanceTargets) do
            if t.id==s.target then w=B.resolveObject(t) end
        end
        if not w then return end
        assert(boards(w)>0,"native barricade persisted")
        record("disk_reload",names[s.liveId].." on duty; resident absent="..s.deadId.." boards="..boards(w))
        finish("PASS","fresh game process restored the living crew and the physical window")
    end
end
Events.OnRenderTick.Add(function()
    if s.phase=="done" then return end
    local ok,why=pcall(step)
    if not ok then finish("FAIL",why) end
end)
