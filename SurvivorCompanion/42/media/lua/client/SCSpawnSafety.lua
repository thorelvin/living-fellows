-- SPDX-License-Identifier: MIT
-- One bounded, off-screen preparation pass. Never an ongoing zombie aura.
require "SCNamespace"
require "SCGameplayUtil"
local SC=SurvivorCompanion
SC.SpawnSafety=SC.SpawnSafety or {}
local S=SC.SpawnSafety
local function U() return SC.GameplayUtil end
-- Strange Folk scenes pass allowTargeting: a walker already chasing someone
-- inside the scene must not survive to break its quiet start.
function S.canClear(zombie,player,allowTargeting)
    if not U().isZombie(zombie) or U().isDead(zombie)
        or U().isCorpseProxy and U().isCorpseProxy(zombie) then return false end
    if SC.Actor and SC.Actor.isCompanion and SC.Actor.isCompanion(zombie) then return false end
    -- Never dissolve somebody's active fight or a visible actor.
    if not allowTargeting and select(1,U().call(zombie,"getTarget"))~=nil then return false end
    if player then
        if U().canSee(player,zombie)==true then return false end
        local sq=U().squareOf(zombie)
        local num=select(1,U().call(player,"getPlayerNum"))
        if type(num)=="number" and select(1,U().call(sq,"isCanSee",num))==true then return false end
    end
    return true
end
function S.begin(square,player,radius)
    local x,y,z=U().position(square)
    if not x or z~=0 then return nil,"spawn_safety_square_unavailable" end
    radius=math.max(0,math.min(30,math.floor(tonumber(radius) or 8)))
    local cell=select(1,U().call(square,"getCell"))
    if not cell then return nil,"spawn_safety_cell_unavailable" end
    return {x=x,y=y,z=z,radius=radius,player=player,cell=cell,dx=-radius,dy=-radius,
        phase="scan",items={},known={},started=U().nowMs(),removed=0,index=1}
end
local function inside(job,zombie)
    local x,y,z=U().position(zombie)
    return x and z==job.z and (x-job.x)^2+(y-job.y)^2<=job.radius^2
end
function S.step(job)
    if type(job)~="table" then return "failed","spawn_safety_job_unavailable" end
    if U().nowMs()-job.started>30000 then return "failed","spawn_safety_timed_out" end
    local squares,objects=0,0
    while job.phase=="scan" and squares<128 and objects<64 do
        if job.list then
            local size=select(1,U().call(job.list,"size")) or 0
            if job.listIndex>=size then job.list=nil
            else
                local zombie=select(1,U().call(job.list,"get",job.listIndex))
                job.listIndex=job.listIndex+1;objects=objects+1
                if zombie and U().isZombie(zombie) and not U().isDead(zombie)
                    and not (U().isCorpseProxy and U().isCorpseProxy(zombie)) and inside(job,zombie) then
                    if not S.canClear(zombie,job.player) then return "failed","spawn_safety_active_threat" end
                    if not job.known[zombie] then
                        if #job.items>=512 then return "failed","spawn_safety_population_limit" end
                        job.known[zombie]=true;job.items[#job.items+1]=zombie
                    end
                end
            end
        elseif job.dx>job.radius then job.phase="clear"
        else
            local dx,dy=job.dx,job.dy
            job.dy=job.dy+1
            if job.dy>job.radius then job.dy=-job.radius;job.dx=job.dx+1 end
            squares=squares+1
            if dx*dx+dy*dy<=job.radius^2 then
                local sq=select(1,U().call(job.cell,"getGridSquare",job.x+dx,job.y+dy,job.z))
                job.list=select(1,U().call(sq,"getMovingObjects"));job.listIndex=0
            end
        end
    end
    -- Removal changes native lists: inspect first, then mutate the retained
    -- identities, with a fresh ownership/visibility check immediately before it.
    local applied=0
    while job.phase=="clear" and job.index<=#job.items and applied<16 do
        local zombie=job.items[job.index];job.index=job.index+1;applied=applied+1
        if inside(job,zombie) and not U().isDead(zombie) then
            if not S.canClear(zombie,job.player) then return "failed","spawn_safety_changed" end
            local _,world=U().call(zombie,"removeFromWorld")
            local _,square=U().call(zombie,"removeFromSquare")
            if not world or not square then return "failed","spawn_safety_removal_failed" end
            job.removed=job.removed+1
        end
    end
    if job.phase=="clear" and job.index>#job.items then return "ready",job.removed end
    return "pending","spawn_safety_preparing"
end
return S
