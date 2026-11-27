-- SPDX-License-Identifier: MIT
-- Real companions and full-square furniture in a disposable camp. Pause only
-- the decision service so the requester's next turn can arrive late.
local SC = LivingFellows
local s = { phase="menu", modals={}, notes={} }
local U, N = SC.GameplayUtil, SC.Navigation

local function write(name, text)
    local f = assert(getFileWriter("pzo-crowd-" .. name .. ".txt",true,false))
    f:write(text .. "\n")
    f:close()
end
local function note(key, value)
    s.notes[#s.notes+1] = key .. "=" .. tostring(value)
end
local function phase(name)
    s.phase, s.deadline = name, getTimestampMs()+45000
    write("progress",name .. "\n" .. table.concat(s.notes,"\n"))
end
local function finish(result, reason)
    if s.worker and s.blocker then
        note("end_worker",s.worker:getX() .. "," .. s.worker:getY())
        note("end_blocker",s.blocker:getX() .. "," .. s.blocker:getY())
    end
    write("result","result=" .. result .. "\nphase=" .. s.phase .. "\nreason=" .. tostring(reason)
        .. "\nlast_request=" .. tostring(s.why) .. "\nlast_yield=" .. tostring(s.yield)
        .. "\n" .. table.concat(s.notes,"\n"))
    s.phase = "done"
end
local function pos(actor)
    return tostring(actor:getX()) .. "," .. tostring(actor:getY()) .. "," .. tostring(actor:getZ())
end
local function findAisle(player)
    local origin = player:getSquare()
    for r=5,18 do
        for dx=-r,r do
            for dy=-r,r do
                if math.max(math.abs(dx),math.abs(dy)) == r then
                    local x,y,z = origin:getX()+dx,origin:getY()+dy,origin:getZ()
                    local function get(i,j) return getCell():getGridSquare(x+i,y+j,z) end
                    local clear = true
                    for i=-1,4 do
                        for j=-1,1 do
                            local q = get(i,j)
                            if not q or not q:isOutside() or not q:isFree(false) or U.squareOccupyingObject(q)
                                or U.movingBlocker(q,player) or i>0 and U.edgeBlocked(get(i-1,j),q) then clear=false break end
                        end
                        if not clear then break end
                    end
                    if clear then return get end
                end
            end
        end
    end
    error("no clear ground for aisle")
end
local function block(square)
    local shelf = IsoThumpable.new(getCell(),square,"carpentry_02_68",false,{})
    shelf:setBlockAllTheSquare(true)
    shelf:setCanPassThrough(false)
    square:AddSpecialObject(shelf,square:getObjects():size())
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
    assert(not U.isSquareFree(square),"shelf must block its square")
end
local function spawn(q, name)
    return assert(SC.Actor.beginSpawn(q,{recruited=true,
        identity={forename=name,surname="Camp",gender="woman",outfit="Generic01"}}))
end
local function request()
    local okay, why = N.request(s.worker,s.goal,"walk",s.intent)
    s.why = why
    return okay,why
end
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox","PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start") end)
local function step()
    if s.phase == "menu" then
        local modal=MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not s.modals[modal] then
            s.modals[modal]=true
            modal:onClick(modal.yes)
        end
        return
    end
    local now = getTimestampMs()
    assert(now < s.deadline,"timeout during " .. s.phase)
    if s.phase == "start" then
        local player=getSpecificPlayer(0)
        if not player or not player:getSquare() or not SC.Persistence.restoreStatus() then return end
        SC.Scheduler.unregister("decision")
        s.grid=findAisle(player)
        SC.BaseLife.reset()
        assert(SC.BaseLife.create(s.grid(0,0),"Aisle camp"))
        block(s.grid(-1,0))
        for i=-1,3 do
            block(s.grid(i,-1))
            if i~=1 then block(s.grid(i,1)) end
        end
        s.t1=spawn(s.grid(0,0),"Kelly")
        phase("worker")
    elseif s.phase == "worker" then
        local actor, why=SC.Actor.pollSpawn(s.t1)
        assert(actor or why=="spawn_pending",tostring(why))
        if not actor then return end
        s.worker, s.t2=actor,spawn(s.grid(1,0),"Mike")
        phase("blocker")
    elseif s.phase == "blocker" then
        local actor, why=SC.Actor.pollSpawn(s.t2)
        assert(actor or why=="spawn_pending",tostring(why))
        if not actor then return end
        s.blocker,s.goal=actor,s.grid(3,0)
        for _,member in ipairs({s.worker,s.blocker}) do
            assert(SC.BaseLife.assign(U.idOf(member),"generalist",true))
            N.cancel(member,"fixture_ready")
        end
        s.forWorker={allies={{actor=s.blocker}},immediateCount=0,pressure=0}
        s.forBlocker={allies={{actor=s.worker}},immediateCount=0,pressure=0}
        s.intent={action="move_to_base_storage",movementPriority=70,workCampOnly=true,workReach=true,
            continuousApproach=true,snapshot=s.forWorker}
        note("worker",pos(s.worker))
        note("blocker",pos(s.blocker))
        note("goal",pos(s.goal))
        phase("meet")
    elseif s.phase == "meet" then
        request()
        local nav=N.peek(s.worker)
        if not nav or nav.yieldBlocker~=s.blocker then return end
        assert(U.sameSquare(s.blocker,s.grid(1,0)),"blocker must occupy the aisle")
        s.since=nav.yieldSince
        note("observed",s.why)
        phase("quiet")
    elseif s.phase == "quiet" then
        if U.nowMs()-s.since<2400 then return end
        note("interval_ms",U.nowMs()-s.since)
        local okay,why=request()
        local session=SC.NavTraffic.pollYield(s.worker,U.nowMs(),s.forWorker)
        assert(okay and session and session.blocker==s.blocker,"late turn issued no clearance: " .. tostring(why))
        s.bay=session.clearance or N.peek(s.blocker).crowdMove.square
        s.session=session
        note("clearance",pos(s.bay))
        phase("pass")
    elseif s.phase == "pass" then
        if s.last and now-s.last < 75 then return end
        s.last=now
        local _,why=N.serviceCrowdYield(s.blocker,s.forBlocker)
        s.yield=why
        if not s.firstHold and why == "holding_clearance_for_passage" then
            s.firstHold = true
            note("first_hold",pos(s.blocker))
            note("first_hold_in_bay",U.sameSquare(s.blocker,s.bay))
        end
        request()
        if s.session.ended and not s.sessionEnd then
            s.sessionEnd=true
            note("clearance_end",s.session.endReason)
            note("request_at_end",s.why)
        end
        if not s.moved and not U.sameSquare(s.blocker,s.grid(1,0)) then
            s.moved=true
            note("blocker_moved",pos(s.blocker))
        end
        if not s.reachedBay and U.sameSquare(s.blocker,s.bay) then
            s.reachedBay=true
            note("bay_reached",pos(s.blocker))
        end
        if s.moved and U.sameSquare(s.worker,s.goal) then
            note("worker_arrived",pos(s.worker))
            finish("PASS","blocker left the aisle and the priority worker reached its goal")
        end
    end
end
Events.OnRenderTick.Add(function()
    if s.phase=="done" then return end
    local ok,why=pcall(step)
    if not ok then finish("FAIL",why) end
end)
