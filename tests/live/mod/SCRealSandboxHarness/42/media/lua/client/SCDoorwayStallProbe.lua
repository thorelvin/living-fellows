-- SPDX-License-Identifier: MIT
-- Reproduce the reported threshold in a disposable save. Placement is fixture
-- setup only; production navigation and native collision own all measured motion.
local Probe = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCDoorwayStallProbe = Probe
local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...)
        local action = object[method]
        if type(action) == "function" then return action(object, ...) end
        return nil
    end, ...)
    if ok then return value end
    return nil
end
local function emit(kind, message) print("SC_DOORWAY|" .. kind .. "|" .. tostring(message)) end
local function point(object)
    return tostring(call(object,"getX")) .. "," .. tostring(call(object,"getY")) .. "," .. tostring(call(object,"getZ"))
end
local function dump(SC, actor)
    local U = SC.GameplayUtil
    for x = 12030, 12033 do for y = 6745, 6747 do
        local tile = U.gridSquare(x,y,0)
        emit("TILE", point(tile) .. " solid=" .. tostring(call(tile,"isSolid"))
            .. " free=" .. tostring(call(tile,"isFree",true)) .. " spawn=" .. tostring(call(tile,"isSafeToSpawn"))
            .. " room=" .. tostring(call(tile,"getRoom")))
        U.squareObjects(tile, function(object)
            local sprite = call(object,"getSprite")
            emit("OBJECT", point(tile) .. " " .. tostring(call(sprite,"getName"))
                .. " class=" .. tostring(object) .. " surface=" .. tostring(call(object,"getSurfaceOffset")))
        end,32)
    end end
    local ax, ay, az = actor:getX(), actor:getY(), actor:getZ()
    for _, direction in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
        for _, distance in ipairs({0.05,0.2,0.5,1}) do
            local x,y = ax+direction[1]*distance,ay+direction[2]*distance
            emit("CLEAR", direction[1] .. "," .. direction[2] .. " distance=" .. distance
                .. " sweep=" .. tostring(call(actor,"isCompanionMovementClear",x,y,az))
                .. " stand=" .. tostring(call(actor,"canStandAt",x,y,az)))
        end
    end
end
local function stage(SC, actor)
    SC.Navigation.reset(actor)
    SC.NativeActions.stopDirect(actor)
    local tile = SC.GameplayUtil.gridSquare(12031,6746,0)
    actor:getCurrentSquare():getMovingObjects():remove(actor)
    actor:setX(12031.983) actor:setY(6746.482) actor:setZ(0)
    actor:setLastX(actor:getX()) actor:setLastY(actor:getY())
    actor:setNextX(actor:getX()) actor:setNextY(actor:getY())
    actor:setCurrent(tile) tile:getMovingObjects():add(actor)
    SC.GameplayUtil.invalidateSpatial(actor)
end
function Probe.step(H,current,check,result,setPhase)
    local SC,U = SurvivorCompanion,SurvivorCompanion.GameplayUtil
    if H.phase == "doorway_stall_setup" then
        if current-H.phaseStartedAt<8000 then return end
        local chosen
        for _, row in ipairs(SC.Registry.snapshot()) do
            emit("RESTORED",row.id .. " recruited=" .. tostring(row.recruited) .. " at=" .. point(row.actor))
            if row.actor and not U.isDead(row.actor) and U.squareOf(row.actor) then
                if not chosen and row.recruited then chosen=row end
                if row.id=="sc-1.792881659967E9-1-843943" then chosen=row break end
            end
        end
        if not chosen then
            if current-H.phaseStartedAt>20000 then check("doorway_worker",false,"no restored actor") setPhase("finish",current) end
            return
        end
        local actor=chosen.actor
        SC.Downtime.cancel(actor,"doorway_fixture")
        SC.Decision.cancelWork(actor,"doorway_fixture")
        SC.ActionSupervisor.cancel(actor,"doorway_fixture",nil,true)
        local decision=SC.Decision.update
        SC.Decision.update=function(value,...)
            if value==actor and H.phase~="finish" then return true,"doorway_fixture" end
            return decision(value,...)
        end
        H.doorway={actor=actor,id=chosen.id,health=U.nativeHealth(actor),inventory=actor:getInventory(),setupAt=current}
        setPhase("doorway_stall_place",current)
        return
    end
    local f=H.doorway
    if H.phase=="doorway_stall_place" then
        if SC.NativeActions.leaveSeating(f.actor)~=true then
            if current-f.setupAt>15000 then check("doorway_standing",false,"native get-up did not settle") setPhase("finish",current) end
            return
        end
        stage(SC,f.actor)
        f.goal=U.gridSquare(12028,6729,0)
        check("doorway_goal",f.goal~=nil,"reported goal " .. point(f.goal))
        emit("STAGED","actor=" .. f.id .. " at=" .. point(f.actor) .. " goal=" .. point(f.goal))
        dump(SC,f.actor)
        f.started,f.nextAt,f.traceAt=current,current,current
        setPhase("doorway_stall_run",current)
        return
    end
    if current<f.nextAt then return end
    f.nextAt=current+100
    if H.config.doorway_stall_delay_input=="true" and not f.delayComplete then
        if f.lastDelayedX then
            local step=math.sqrt((f.actor:getX()-f.lastDelayedX)^2+(f.actor:getY()-f.lastDelayedY)^2)
            if not check("doorway_delayed_step_cap",step<=0.11,"native displacement=" .. step) then
                setPhase("finish",current) return
            end
        end
        f.lastDelayedX,f.lastDelayedY=f.actor:getX(),f.actor:getY()
        if f.actor:getX()>=12032.3 then
            check("doorway_delayed_input_crossed",true,"physical threshold crossed after " .. tostring(f.accepted or 0) .. " inputs")
            check("doorway_delayed_identity",SC.Registry.byId(f.id).actor==f.actor and f.actor:getInventory()==f.inventory,"same actor/inventory")
            f.delayComplete, f.started = true, current
            SC.NativeActions.stopDirect(f.actor)
            emit("ROUTE_CONTINUES","from actual crossing position " .. point(f.actor))
            return
        end
        local accepted,why=SC.Actor.setMovement(f.actor,"walk",{action="move",dx=1,dy=0,urgent=true})
        if accepted and why=="moving" then
            f.accepted=(f.accepted or 0)+1
            f.firstInputAt=f.firstInputAt or current
            -- Controlled main-thread load after a valid input, before the
            -- native actor's next update. Never used outside this test mod.
            local untilAt=getTimestampMs()+350
            while getTimestampMs()<untilAt do end
        end
        emit("DELAY","at=" .. point(f.actor) .. " accepted=" .. tostring(accepted) .. " why=" .. tostring(why)
            .. " physics=" .. tostring(call(f.actor,"getCompanionCollisionDiagnostic")))
        if current-(f.firstInputAt or f.started)>8000 then
            check("doorway_delayed_input_crossed",false,"input accepted but no threshold crossing after " .. tostring(f.accepted or 0) .. " requests")
            setPhase("finish",current)
        end
        return
    end
    local accepted,why=SC.Navigation.request(f.actor,f.goal,"walk",{action="move_to",player=H.player})
    if current>=f.traceAt then
        f.traceAt=current+1000
        local nav=SC.Navigation.status(f.actor) or {}
        emit("MOVE","ms=" .. (current-f.started) .. " at=" .. point(f.actor) .. " accepted=" .. tostring(accepted)
            .. " why=" .. tostring(why) .. " last=" .. tostring(nav.lastMovementReason)
            .. " owner=" .. tostring(call(f.actor,"getCompanionMovementOwner"))
            .. " anim=" .. tostring(call(f.actor,"getCompanionActiveAnimationNames"))
            .. " physics=" .. tostring(call(f.actor,"getCompanionCollisionDiagnostic")))
    end
    local arrived = U.arrived(f.actor,f.goal,{targetKind="square",distance=0.6})
    if arrived then
        check("doorway_arrived",true,"native route arrived in " .. (current-f.started) .. " ms")
        check("doorway_identity",SC.Registry.byId(f.id).actor==f.actor and f.actor:getInventory()==f.inventory,"same native actor and inventory")
        setPhase(H.config.bed_exit_tables_probe=="true" and "bed_exit_tables_setup" or "finish",current)
    elseif current-f.started>=90000 then
        dump(SC,f.actor)
        check("doorway_arrived",false,"90s without arrival at " .. point(f.actor))
        setPhase("finish",current)
    end
end
return Probe
