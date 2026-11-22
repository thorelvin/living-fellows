-- SPDX-License-Identifier: MIT
-- Disposable world. Exercise the floor hauler's route entry point during a
-- completed, still-claimable native Loot effect, then observe real movement.
local SC = SurvivorCompanion
local s = {phase="menu", notes={}, modals={}}

local function write(name, data)
    local file = assert(getFileWriter("pzo-haul-" .. name .. ".txt", true, false))
    file:write(data .. "\n")
    file:close()
end

local function phase(name)
    s.phase, s.at = name, getTimestampMs()
    write("progress", name .. "\n" .. table.concat(s.notes, "\n"))
end

local function approach(target, intent)
    -- SCFloorSort.approach accepts a free pickup square as soon as the native
    -- actor occupies it, including while its capsule is crossing the centre.
    if SC.GameplayUtil.sameSquare(s.actor,target) and SC.GameplayUtil.isSquareFree(target) then
        return true,"arrived"
    end
    local okay,why=SC.Navigation.requestAny(s.actor,{target},"walk",intent)
    if not okay then
        local nav=SC.Navigation.peek(s.actor) or {}
        local failure=nav.pathFailure or {}
        local pos=string.format("%.3f:%.3f",s.actor:getX(),s.actor:getY())
        local cx,cy=target:getX()+0.5,target:getY()+0.5
        local dx,dy=s.actor:getX()-cx,s.actor:getY()-cy
        s.notes[#s.notes+1]="failed_route="..pos.." to "..cx..":"..cy.." distance "..math.sqrt(dx*dx+dy*dy)
            .." camp "..tostring(SC.BaseLife.isInside(s.actor)).."/"..tostring(SC.BaseLife.isInside(target))
            .." reach "..tostring(SC.BaseLife.withinWorkReach(s.actor)).."/"..tostring(SC.BaseLife.withinWorkReach(target))
            .." pathIndex "..tostring(nav.pathIndex).." pathReason "..tostring(nav.pathReason)
            .." blocker "..tostring(nav.lastBlocker and nav.lastBlocker.type).." class "..tostring(failure.failureClass)
        for k,v in pairs(failure.rejections or {}) do s.notes[#s.notes+1]="rejected_"..tostring(k).."="..tostring(v) end
    end
    return okay,why
end

local function finish(ok, why)
    write("result", "result=" .. (ok and "PASS" or "FAIL") .. "\nphase=" .. s.phase
        .. "\nreason=" .. tostring(why) .. "\n" .. table.concat(s.notes, "\n"))
    s.phase = "done"
end

local function openStrip()
    local player=getSpecificPlayer(0)
    local x,y=math.floor(player:getX()), math.floor(player:getY())
    for dx=-18,18,3 do
        for dy=-18,18,3 do
            if math.abs(dx)+math.abs(dy)>5 then
                local open=true
                -- Include a margin on either side of the walking line to keep
                -- both capsule clearance and furniture out of the fixture.
                for ox=-1,3 do
                    for oy=-1,1 do
                        local q=getCell():getGridSquare(x+dx+ox,y+dy+oy,0)
                        if not q or q:getBuilding() or not SC.GameplayUtil.isClearActorSpawnSquare(q)
                            or not q:isFree(false) or q:getVehicleContainer() then open=false break end
                    end
                    if not open then break end
                end
                if open then
                    return getCell():getGridSquare(x+dx,y+dy,0),getCell():getGridSquare(x+dx+2,y+dy,0),
                        getCell():getGridSquare(x+dx+3,y+dy,0)
                end
            end
        end
    end
    error("no loaded open camp strip")
end

local function setup()
    local floorSquare, workSquare, crateSquare = openStrip()
    SC.BaseLife.reset()
    assert(SC.BaseLife.create(workSquare,"Haul handoff"))
    local base = SC.BaseLife.active()
    base.settings.autoMaintenance,base.settings.routines = false,false
    local crate = IsoThumpable.new(getCell(),crateSquare,"carpentry_01_16",false,{})
    crate:setIsContainer(true)
    crate:setContainer(ItemContainer.new("crate",crateSquare,crate))
    crateSquare:AddSpecialObject(crate)
    crateSquare:RecalcAllWithNeighbours(true)
    s.container,s.crateSquare = crate:getContainer(),crateSquare
    s.supply = assert(s.container:AddItem("Base.Nails"))
    s.goal,s.workSquare = floorSquare,workSquare
    local floorItem = assert(s.goal:AddWorldInventoryItem("Base.Nails",0.5,0.5,0))
    s.intent = {action="move_to_floor_item",targetSquare=s.goal,object=assert(floorItem:getWorldItem()),
        workCampOnly=true,workReach=true,arrivalDistance=0.45}
    s.ticket = assert(SC.Actor.beginSpawn(floorSquare,{recruited=true,
        identity={forename="Kelly",surname="Hauler",outfit="Generic01",gender="woman"}}))
    s.notes[#s.notes+1]="strip=" .. SC.GameplayUtil.squareKey(floorSquare) .. "/" .. SC.GameplayUtil.squareKey(workSquare)
    phase("spawn")
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function()
    SC.Scheduler.unregister("decision")
    getSpecificPlayer(0):teleportTo(6428.5,5449.5,0)
    phase("load")
end)

local function step()
    if s.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not s.modals[modal] then
            s.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    local now = getTimestampMs()
    assert(now-s.at<75000,"timed out, last movement: " .. tostring(s.move))
    if s.phase=="load" then
        if now-s.at<10000 or not SC.Persistence.restoreStatus() then return end
        setup()
    elseif s.phase=="spawn" then
        local actor,why = SC.Actor.pollSpawn(s.ticket)
        assert(actor or why=="spawn_pending",tostring(why))
        if not actor then return end
        s.actor = actor
        assert(SC.BaseLife.assign(SC.GameplayUtil.idOf(actor),"generalist",true))
        phase("approach_crate")
    elseif s.phase=="approach_crate" then
        local okay,why=approach(s.workSquare,{
            action="move_to_floor_item",targetSquare=s.workSquare,workCampOnly=true,workReach=true,arrivalDistance=0.45})
        s.move=why
        assert(okay,"open ground preflight: " .. tostring(why))
        if why~="arrived" then return end
        assert(SC.GameplayUtil.sameSquare(s.actor,s.workSquare),"worker reached the crate")
        SC.Navigation.cancel(s.actor,"at_crate")
        assert(SC.GameplayUtil.move(s.actor,"walk",{action="loot_container",container=s.container,
            item=s.supply,targetSquare=s.crateSquare,durationTicks=30}))
        s.token = assert(SC.NativeActions.visualToken(s.actor,"loot_container"))
        phase("loot")
    elseif s.phase=="loot" then
        local status = SC.NativeActions.visualStatus(s.actor,"loot_container")
        if status=="active" then s.observed=true return end
        assert(s.observed and status=="completed","unobserved Loot pose: " .. tostring(status))
        s.x,s.y = s.actor:getX(),s.actor:getY()
        phase("claim_window")
    elseif s.phase=="claim_window" or s.phase=="resume" then
        local okay,why = approach(s.goal,s.intent)
        if s.move~=why and #s.notes<30 then s.notes[#s.notes+1]=s.phase .. "=" .. tostring(why) end
        s.move = why
        assert(okay,"floor route rejected: " .. tostring(why))
        if s.phase=="claim_window" then
            if why=="path_searching" or why=="path_search_deferred" then return end
            assert(why=="waiting_for_visual_result","unexpected claim-window result: " .. tostring(why))
            assert(SC.NativeActions.visualToken(s.actor,"loot_container")==s.token,"claim token changed")
            local nav = assert(SC.Navigation.peek(s.actor))
            assert(not nav.nativeLease and not nav.multiGoalFailures[SC.GameplayUtil.squareKey(s.goal)])
            s.notes[#s.notes+1]="during_claim=" .. why
            phase("resume")
        elseif why=="arrived" then
            assert(SC.GameplayUtil.sameSquare(s.actor,s.goal))
            local dx,dy=s.actor:getX()-s.x,s.actor:getY()-s.y
            assert(dx*dx+dy*dy>1,"no actual displacement")
            s.notes[#s.notes+1]="arrived=" .. SC.GameplayUtil.squareKey(s.actor:getSquare())
            finish(true,"same companion waited for the native Loot claim, then reached the floor item")
        end
    end
end

Events.OnRenderTick.Add(function()
    if s.phase=="done" then return end
    local ok,why = pcall(step)
    if not ok then finish(false,why) end
end)
