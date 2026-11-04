-- SPDX-License-Identifier: MIT
-- Clone-only fixture placement ends before Home.start. The outbound home walk,
-- save acknowledgement, actor retirement and later restoration are production
-- operations. No completion, streaming, ownership or visibility guard is forced.
local Probe = {}
local Radio=SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCHomeRadioProbe
if type(require)=="function" then
    local loaded,value=pcall(require,"SCHomeRadioProbe")
    if loaded and type(value)=="table" then Radio=value end
    Radio=Radio or SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCHomeRadioProbe
end
local Drive=SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCHomeDriveFixture
if type(require)=="function" then
    local loaded,value=pcall(require,"SCHomeDriveFixture")
    if loaded and type(value)=="table" then Drive=value end
    Drive=Drive or SCRealSandboxHarnessProbes and SCRealSandboxHarnessProbes.SCHomeDriveFixture
end
local function driving(H) return H.config.home_trip_transport=="drive" end
local CHECKPOINT = "LF_HomeTripAcceptance"
local FIXTURE_TARGET_TOLERANCE = 12
local RESUME_CHECKPOINT_STATES = {resume_active="walking",resume_midtrip="midtrip",
    resume_midtrip_save_dormant="midtrip",resume_dormant="dormant",resume_delivery="walking"}
local REMOTE_OBSERVER_PHASES = {home_trip_departure_setup=true,home_trip_drive_field_setup=true,
    home_trip_sheet=true,home_trip_dispatch=true,home_trip_resume=true,home_trip_walk=true,home_trip_radio=true,home_trip_dormant=true}
local function S() return SurvivorCompanion end
local function call(object, method, ...)
    if not object then return nil end
    local indexed, fn = pcall(function() return object[method] end)
    if not indexed or type(fn) ~= "function" then return nil end
    local okay, value = pcall(fn, object, ...)
    if okay then return value end
end
local function copy(value, depth)
    if type(value) ~= "table" then
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then return value end
        return nil
    end
    if (depth or 0) > 32 then error("home probe checkpoint too deep") end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child, (depth or 0) + 1) end
    return result
end
local function point(actor)
    local x, y, z = call(actor, "getX"), call(actor, "getY"), call(actor, "getZ")
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return {x=x,y=y,z=z}
end
local function gap(a,b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
local function primaryFixed(f)
    local at=point(f.primary)
    -- Native collision separation can nudge a blocked observer beside the
    -- boarding crew. Bound that drift to less than one tile; never move or
    -- recenter the observer during production travel.
    return at and f.departure and math.abs(at.z-f.departure.z)<=.2
        and gap(at,f.departure)<=(f.drive and .75 or .2)
end
local function observerStatus(f)
    return "dead="..tostring(call(f.primary,"isDead"))..";ghost="..tostring(call(f.primary,"isGhostMode"))
        ..";invisible="..tostring(call(f.primary,"isInvisible"))..";protected="..tostring(f.observerProtected==true)
end
local function protectObserver(f)
    if f.ghost==nil then f.ghost=call(f.primary,"isGhostMode") end
    if f.invisible==nil then f.invisible=call(f.primary,"isInvisible") end
    if type(f.ghost)~="boolean" or type(f.invisible)~="boolean" then return false,"observer_original_flags_unavailable" end
    -- Only the test's main observer is protected. A joined view may reset
    -- native flags, so the owned remote phase reapplies them when needed.
    local ghost,invisible=call(f.primary,"isGhostMode"),call(f.primary,"isInvisible")
    if f.observerProtected and (ghost~=true or invisible~=true) then
        f.observerFlagResets=(f.observerFlagResets or 0)+1
        f.lastObserverResetBefore=observerStatus(f)
    end
    if ghost~=true then call(f.primary,"setGhostMode",true) end
    if invisible~=true then call(f.primary,"setInvisible",true) end
    f.observerProtected=true
    return call(f.primary,"isGhostMode")==true and call(f.primary,"isInvisible")==true,observerStatus(f)
end
local function restoreObserver(f)
    if f.invisible~=nil then call(f.primary,"setInvisible",f.invisible) end
    if f.ghost~=nil then call(f.primary,"setGhostMode",f.ghost) end
    f.observerProtected=false
end
local function routeCaptureLine(route,reason,native,circles)
    local points=type(route)=="table" and route.points or {}
    local rows={"reason="..tostring(reason),"native="..tostring(type(native)=="table" and native.status),"points="..#points}
    local selected={}
    for index=1,math.min(3,#points) do selected[#selected+1]=index end
    for index=4,#points-1 do
        local a,b,c=points[index-1],points[index],points[index+1]
        local dx,dy,ex,ey=b.x-a.x,b.y-a.y,c.x-b.x,c.y-b.y
        if math.abs(dx*ey-dy*ex)>.01 or dx*ex+dy*ey<0 then
            if #selected<31 then selected[#selected+1]=index end
        end
    end
    if #points>1 and selected[#selected]~=#points then selected[#selected+1]=#points end
    for _,index in ipairs(selected) do local at=points[index]
        rows[#rows+1]="p"..index.."="..tostring(at.x)..","..tostring(at.y)
    end
    for index=1,math.min(8,#(circles or {})) do local circle=circles[index]
        rows[#rows+1]="circle"..index.."="..tostring(circle.x)..","..tostring(circle.y)..","..tostring(circle.radius)
    end
    return table.concat(rows,"|")
end
local function stopRouteCapture(f)
    if f.routeModule and f.routeModule.planAvoidingAll==f.routeObserver then f.routeModule.planAvoidingAll=f.originalRouteAvoiding end
    f.routeObserver=nil
end
local function captureRoutes(f)
    local route=S().ExpeditionRoute
    if f.routeObserver or not route or type(route.planAvoidingAll)~="function" then return end
    f.routeModule,f.originalRouteAvoiding=route,route.planAvoidingAll
    f.routeObserver=function(actor,target,circles)
        local planned,reason,native=f.originalRouteAvoiding(actor,target,circles)
        -- Logging must not change the original planner's result or failure.
        pcall(function()
            local line=routeCaptureLine(planned,reason,native,circles)
            if line~=f.lastRouteCaptureLine then
                f.lastRouteCaptureLine=line
                print("SC_REAL_SANDBOX|HOME_ROUTE_AVOID|"..line)
                local writer=getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
                if writer then writer:writeln("route_avoid|"..line);writer:close() end
            end
        end)
        return planned,reason,native
    end
    route.planAvoidingAll=f.routeObserver
end
local function readDriveStatus(active)
    local driving=S().Driving
    local actor=active and active.scout and active.scout.vehicle and active.leader and active.leader.actor
    if not actor or not driving or type(driving.status)~="function" then return nil end
    local okay,status=pcall(driving.status,actor)
    if not okay or type(status)~="table" then return nil end
    local rows={}
    for _,key in ipairs({"mode","state","turnState","turnLegs","backward","forward","speedKmh","steering",
            "centerDistance","obstacleDistance","obstacleKind","backoffs"}) do
        local value=status[key] local kind=type(value)
        if kind=="number" or kind=="boolean" or kind=="string" then rows[#rows+1]=key.."="..string.sub(tostring(value),1,64) end
    end
    return table.concat(rows,";"),tostring(status.mode)..":"..tostring(status.state)..":"..tostring(status.turnState)..":"..tostring(status.backward)
end
local function driveOwnershipLine(actor)
    local rows={}
    local function fields(prefix,value,keys)
        if type(value)~="table" then rows[#rows+1]=prefix.."=none" return end
        for _,key in ipairs(keys) do
            local source=key=="leaseCurrent" and "owned" or key
            rows[#rows+1]=prefix.."."..key.."="..string.sub(tostring(value[source]),1,128)
        end
    end
    local driving,supervisor=S().Driving,S().ActionSupervisor
    local job
    if driving and type(driving.jobStatus)=="function" then
        local okay,value=pcall(driving.jobStatus,actor) if okay then job=value end
    end
    fields("job",job,{"phase","result","reason","parked","managed","leaseCurrent",
        "firstParkingRefusal","parkingAlignmentReason","alignmentAttempts"})
    -- current()/snapshot() service update() and could cancel the very lease
    -- being diagnosed. The pure job.owned flag and four history rows suffice.
    if supervisor and type(supervisor.history)=="function" then
        local okay,history=pcall(supervisor.history,actor,4)
        if okay and type(history)=="table" then
            local first=math.max(1,#history-3)
            for index=first,#history do fields("history"..(index-first+1),history[index],
                {"event","owner","action","phase","reason"}) end
        end
    end
    return table.concat(rows,";")
end
local function observeDriveStatus(f,active)
    local line,signature=readDriveStatus(active)
    if not line then return end
    f.lastDriveStatusLine=line
    local car=active.scout.vehicle
    signature=signature..":"..tostring(car.state)..":"..tostring(car.blocker)
    if signature==f.lastDriveStatusSignature then return end
    f.lastDriveStatusSignature=signature f.nativeDriveChanges=(f.nativeDriveChanges or 0)+1
    pcall(function()
        local at=point(active.leader.actor)
        f.lastDriveOwnershipLine=driveOwnershipLine(active.leader.actor)
        line="frame="..tostring(f.frames)..";at="..tostring(at and at.x)..","..tostring(at and at.y)
            ..";carState="..tostring(car.state)..";refusal="..tostring(car.blocker)..";"..line..";"..f.lastDriveOwnershipLine
        print("SC_REAL_SANDBOX|HOME_NATIVE_DRIVE|"..line)
        local writer=getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
        if writer then writer:writeln("native_drive|"..line);writer:close() end
    end)
end
local function name(actor)
    return S().Names and S().Names.displayName(actor) or call(actor,"getFullName")
end
local function walkTraceLine(active)
    if type(active)~="table" then return nil end
    local rows,SC={},S()
    local function field(key,value)
        local kind=type(value)
        local text=(kind=="string" or kind=="number" or kind=="boolean" or value==nil)
            and tostring(value) or "unavailable"
        rows[#rows+1]=key.."="..string.sub(string.gsub(text,"[;|\r\n]","_"),1,96)
    end
    local function position(key,value)
        if type(value)~="table" then field(key,nil) return end
        field(key,tostring(value.x)..","..tostring(value.y)..","..tostring(value.z))
    end
    local current
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs)=="function" then
        local okay,value=pcall(SC.GameplayUtil.nowMs) if okay and type(value)=="number" then current=value end
    end
    local function age(at) return current and type(at)=="number" and math.max(0,current-at) or nil end
    local scout=active.scout or {}
    local home=scout.home or {}
    local actor=active.leader and active.leader.actor
    local at,core=point(actor),home.camp and home.camp.core
    field("walk.leader",active.leader and active.leader.id)
    position("walk.at",at)
    position("walk.core",core)
    field("walk.coreDistance",at and core and gap(at,core) or nil)
    position("walk.waypoint",active.testWaypoint)
    field("walk.waypointDistance",at and active.testWaypoint and gap(at,active.testWaypoint) or nil)
    position("walk.lastStalledTarget",scout.lastStalledTarget)
    field("walk.blocker",home.blocker)
    field("walk.lastPlanFailure",scout.lastPlanFailure)
    field("walk.lastRoadFailure",scout.lastRoadFailure)
    field("walk.replans",scout.replans)
    field("walk.bestDistance",scout.bestDistanceToWaypoint)
    field("walk.progressAgeMs",age(scout.lastProgressAt))
    field("walk.waypointAgeMs",age(scout.waypointStagedAt))
    field("walk.returnRetryMs",current and type(scout.returnRetryAt)=="number" and math.max(0,scout.returnRetryAt-current) or nil)
    field("gate.homeRelease",active.homeRelease~=nil)
    field("gate.committed",active.homeRelease and active.homeRelease.committed)
    field("gate.recalling",home.recalling==true)
    local coreLoaded
    if type(core)=="table" and type(core.x)=="number" and type(core.y)=="number" and type(core.z)=="number"
        and type(getCell)=="function" then
        -- One native lookup, without a planner, route scan or cached-state write.
        local okay,cell=pcall(getCell)
        if okay and cell then
            local read,square=pcall(function() return cell:getGridSquare(math.floor(core.x),math.floor(core.y),math.floor(core.z)) end)
            if read then coreLoaded=square~=nil end
        end
    end
    field("gate.coreLoaded",coreLoaded)
    field("gate.technical",active.technicalIssue and active.technicalIssue.reason)
    field("gate.cohesion",active.cohesionHold~=nil)
    field("gate.cohesionReason",type(active.cohesionHold)=="table" and active.cohesionHold.reason or nil)
    field("gate.pause",scout.pause~=nil)
    field("gate.pauseReason",scout.pause and scout.pause.reason)
    if actor and SC.HomeTrip and type(SC.HomeTrip.finalApproachFor)=="function" then
        local okay,value=pcall(SC.HomeTrip.finalApproachFor,actor)
        if okay then field("walk.finalApproach",value) else field("walk.finalApproach","unavailable") end
    end
    -- status() reads retained navigation state and a clock only; unlike a
    -- request it cannot advance a search, lease, recovery or native action.
    if actor and SC.Navigation and type(SC.Navigation.status)=="function" then
        local okay,value=pcall(SC.Navigation.status,actor)
        if okay and type(value)=="table" then
            for _,key in ipairs({"active","phase","action","target","stuckAttempts","pathReason","pathSearchAgeMs",
                "expandedNodes","terminalReason","terminalRetryMs","lastMovementReason","blockerType","actorState",
                "recoveryResult","searchSliceBudgetMs","searchSliceBudgetReason"}) do field("nav."..key,value[key]) end
        else field("nav.status","unavailable") end
    end
    if actor and SC.Decision and type(SC.Decision.peek)=="function" then
        local okay,value=pcall(SC.Decision.peek,actor)
        if okay and type(value)=="table" then
            field("decision.current",value.current) field("decision.intent",value.intent)
            field("decision.handledAgeMs",age(value.lastHandledAt))
        else field("decision.status","unavailable") end
    end
    if actor then
        -- There is no pure current-owner accessor. Label the bounded history
        -- honestly; current/snapshot/summary would service and alter ownership.
        field("walk.ownerRead","history_only")
        rows[#rows+1]="walk.ownership="..string.sub(driveOwnershipLine(actor),1,2048)
    end
    return table.concat(rows,";")
end
function Probe.deliveryTraceLine(integration,crew)
    local SC=S() local rows={}
    local function field(key,value)
        local kind=type(value)
        local text=(kind=="string" or kind=="number" or kind=="boolean" or value==nil) and tostring(value) or "unavailable"
        rows[#rows+1]=key.."="..string.sub(string.gsub(text,"[;|\r\n]","_"),1,96)
    end
    local current
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs)=="function" then
        local okay,value=pcall(SC.GameplayUtil.nowMs)
        if okay and type(value)=="number" then current=value end
    end
    local summary
    if integration and SC.ExpeditionIntegration and type(SC.ExpeditionIntegration.summary)=="function" then
        local okay,value=pcall(SC.ExpeditionIntegration.summary,integration)
        if okay and type(value)=="table" then summary=value end
    end
    for _,key in ipairs({"trunkPending","stored","pending","carried","released","complete"}) do
        field("delivery."..key,summary and summary[key])
    end
    local carId=integration and integration.carId local car
    field("delivery.car.expectedSqlId",carId)
    if carId~=nil and SC.Vehicle and type(SC.Vehicle.loadedBySqlId)=="function" then
        local okay,value=pcall(SC.Vehicle.loadedBySqlId,carId) if okay then car=value end
    end
    field("delivery.car.loaded",car~=nil)
    if car then
        field("delivery.car.sqlId",call(car,"getSqlId"))
        for _,entry in ipairs({{"x","getX"},{"y","getY"},{"z","getZ"},{"speedKph","getCurrentSpeedKmHour"},
            {"engineRunning","isEngineRunning"},{"trunkLocked","isTrunkLocked"}}) do field("delivery.car."..entry[1],call(car,entry[2])) end
        if SC.Vehicle and type(SC.Vehicle.isStationary)=="function" then
            local okay,stationary,reason=pcall(SC.Vehicle.isStationary,car)
            if okay then field("delivery.car.stationary",stationary) else field("delivery.car.stationary","unavailable") end
            field("delivery.car.stationaryReason",reason)
        end
        if SC.VehicleUnload and type(SC.VehicleUnload.eligible)=="function" then
            local okay,eligible,info=pcall(SC.VehicleUnload.eligible,car)
            field("delivery.car.unloadEligible",okay and eligible or false)
            field("delivery.car.unloadReason",not okay and "eligibility_read_failed" or eligible~=true and info or nil)
            if okay and eligible==true and type(info)=="table" then field("delivery.car.parkingZoneId",info.zoneId) end
        else field("delivery.car.unloadEligible","unavailable") end
    else field("delivery.car.unloadEligible","unavailable") field("delivery.car.unloadReason","car_not_loaded") end
    local unfinished=0
    local items=summary and type(summary.items)=="table" and summary.items or {}
    for index=1,math.min(256,#items) do
        local row=items[index]
        if type(row)=="table" and row.stored~=true and row.released~=true then
            unfinished=unfinished+1
            for _,key in ipairs({"nativeId","itemType","carrierKind","carrierId","reason"}) do field("delivery.receipt"..unfinished.."."..key,row[key]) end
            if unfinished>=6 then break end
        end
    end
    for index=1,math.min(4,#crew) do
        local member=crew[index] local actor=member.actor local prefix="delivery.crew"..index
        field(prefix..".id",member.id)
        if actor and SC.Navigation and type(SC.Navigation.status)=="function" then
            local okay,value=pcall(SC.Navigation.status,actor)
            if okay and type(value)=="table" then
                for _,key in ipairs({"phase","action","target","pathReason","pathSearchAgeMs","pathFailureClass","searchSliceBudgetMs","searchSliceBudgetReason","expandedNodes","terminalReason",
                    "actorState","recoveryResult","blockerType","lastMovementReason"}) do
                    field(prefix..".nav."..key,value[key])
                end
            else field(prefix..".nav.status","unavailable") end
        end
        -- This existing helper is explicitly read-only: known stock behavior
        -- getters and the companion path-status getter, without servicing it.
        if actor and SC.NativeActions and type(SC.NativeActions.pathTelemetry)=="function" then
            local okay,value=pcall(SC.NativeActions.pathTelemetry,actor)
            if okay and type(value)=="table" then
                for _,key in ipairs({"available","status","active","pending","moving","stopping","shouldBeMoving","hasStartedMoving",
                    "turningToObstacle","movingUsingPathFind","pathNextIsSet","pathNextX","pathNextY"}) do field(prefix..".nativePath."..key,value[key]) end
            else field(prefix..".nativePath.available",false) end
        end
        if actor and SC.Decision and type(SC.Decision.peek)=="function" then
            local okay,value=pcall(SC.Decision.peek,actor)
            if okay and type(value)=="table" then
                for _,key in ipairs({"current","intent","lastReason"}) do field(prefix..".decision."..key,value[key]) end
                field(prefix..".decision.handledAgeMs",current and type(value.lastHandledAt)=="number"
                    and math.max(0,current-value.lastHandledAt) or nil)
            else field(prefix..".decision.status","unavailable") end
        end
        local supervisor=SC.ActionSupervisor
        if actor and supervisor and type(supervisor.history)=="function" then
            local okay,history=pcall(supervisor.history,actor,2)
            if okay and type(history)=="table" then
                local first=math.max(1,#history-1)
                for row=first,#history do
                    local event=history[row]
                    if type(event)=="table" then for _,key in ipairs({"event","owner","action","phase","reason"}) do
                        field(prefix..".history"..(row-first+1).."."..key,event[key])
                    end end
                end
            end
        end
    end
    return table.concat(rows,";")
end
function Probe.captureBlockerTraceLine(active)
    local home=active and active.scout and active.scout.home
    local blocker=home and home.blocker or active and (active.blocker or active.technicalIssue and active.technicalIssue.reason)
    local id=type(blocker)=="string" and string.match(blocker,"active companion capture failed: ([^%s:;|]+)")
    if not id or #id>128 then return nil end
    local SC=S() local rows={}
    local function field(key,value)
        rows[#rows+1]="capture.actor."..key.."="..string.sub(string.gsub(tostring(value),"[;|\r\n]","_"),1,96)
    end
    local record=SC.Registry and SC.Registry.byId and SC.Registry.byId(id)
    local actor=record and record.actor local runtime=record and record.runtime or {}
    field("id",id) field("present",record~=nil) field("currentSquarePresent",call(actor,"getCurrentSquare")~=nil)
    -- Raw coordinates are printed only. They never select an anchor, square,
    -- recovery target or save position, especially while native membership fails.
    field("rawXYZ",tostring(call(actor,"getX"))..","..tostring(call(actor,"getY"))..","..tostring(call(actor,"getZ")))
    field("stablePositionPresent",type(runtime.lastStablePosition)=="table")
    field("stableSnapshotPresent",type(runtime.lastStableSnapshot)=="table") field("inactive",runtime.inactive)
    local now=SC.GameplayUtil and SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs()
    field("positionUnstableRemainingMs",type(now)=="number" and type(runtime.positionUnstableUntil)=="number"
        and math.max(0,runtime.positionUnstableUntil-now) or nil)
    if actor and SC.Actor and type(SC.Actor.validateNative)=="function" then
        local okay,valid,reason=pcall(SC.Actor.validateNative,actor)
        if okay then field("nativeValid",valid) field("nativeReason",reason)
        else field("nativeReason","validation_read_unavailable") end
    end
    return table.concat(rows,";")
end
local function trace(f,label)
    local rows={label,"phase="..tostring(f.phase),"primary="..tostring(call(f.primary,"getX"))..","..tostring(call(f.primary,"getY"))}
    rows[#rows+1]="observer="..observerStatus(f)
    rows[#rows+1]="observerFlagResets="..tostring(f.observerFlagResets or 0)..";before="..tostring(f.lastObserverResetBefore)
    rows[#rows+1]="setupTarget="..tostring(f.target and f.target.x)..","..tostring(f.target and f.target.y)..","..tostring(f.target and f.target.z)
    rows[#rows+1]="setupRemaining="..tostring(gap(point(f.primary),f.target))
    rows[#rows+1]="revisitRemaining="..tostring(gap(point(f.primary),f.homePose))
    local active=S().HomeTrip and S().HomeTrip.current and S().HomeTrip.current()
    rows[#rows+1]="driveStatus="..tostring(readDriveStatus(active) or f.lastDriveStatusLine)
    rows[#rows+1]="mission="..tostring(active and active.scout and active.scout.phase)
    if active then
        rows[#rows+1]=walkTraceLine(active)
        rows[#rows+1]=Probe.captureBlockerTraceLine(active)
    end
    local trip=active and active.scout and active.scout.vehicle
    if trip then
        local car=S().Vehicle and S().Vehicle.loadedBySqlId(trip.sqlId)
        local at=point(car)
        rows[#rows+1]="car="..tostring(trip.sqlId).."/"..tostring(trip.state).."@"..tostring(at and at.x)..","..tostring(at and at.y)
            ..";engine="..tostring(call(car,"isEngineRunning"))..";speed="..tostring(call(car,"getCurrentSpeedKmHour"))
            ..";blocker="..tostring(trip.blocker or active.scout.home and active.scout.home.blocker)
    end
    local native="unavailable"
    if SCSplitScreenProbe and SCSplitScreenProbe.releaseDiagnostics then
        local okay,value=pcall(SCSplitScreenProbe.releaseDiagnostics)
        if okay then native=value end
    end
    rows[#rows+1]="native="..tostring(native)
    local expedition=S().ExpeditionPrototype local debrief
    if expedition and type(expedition.lastDebrief)=="function" then
        local okay,value=pcall(expedition.lastDebrief)
        if okay then debrief=value end
    end
    local integration=active and active.integration or debrief and debrief.integration
    local deliveryCrew={}
    for _,member in ipairs(f.crew or {}) do
        local record=S().Registry.byId(member.id)
        local actor=record and record.actor
        rows[#rows+1]=member.id.."@"..tostring(call(actor,"getX"))..","..tostring(call(actor,"getY"))
            ..","..tostring(call(actor,"getZ"))..";pending="..tostring(S().Persistence.isPending(member.id))
        local commands=S().Commands local command
        if actor and commands and type(commands.peek)=="function" then
            local okay,value=pcall(commands.peek,actor)
            if okay then command=value end
        end
        if #deliveryCrew<4 then deliveryCrew[#deliveryCrew+1]={id=member.id,actor=actor} end
        for _,handover in ipairs(integration and integration.members or {}) do
            if handover.id==member.id then
                rows[#rows+1]="handover="..member.id..";expectedSerial="..tostring(handover.commandSerial)
                    ..";actualSerial="..tostring(command and command.commandSerial)
                    ..";duty="..tostring(handover.dutyDone).."/"..tostring(handover.dutyReason)
                    ..";cleanup="..tostring(handover.cleanupDone).."/"..tostring(handover.cleanupReason)
            end
        end
    end
    if f.drive and not active and f.phase=="home_trip_duty" then rows[#rows+1]=Probe.deliveryTraceLine(integration,deliveryCrew) end
    local line=table.concat(rows,"|")
    print("SC_REAL_SANDBOX|HOME_TRIP|"..line)
    local writer=getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
    if writer then writer:writeln(line);writer:close() end
    return line
end
local function hideDebugConsole()
    local hidden=0
    pcall(function()
        local list=UIManager and UIManager.UI
        if not list then return end
        local count=call(list,"size") local indexed=type(count)=="number"
        if not indexed then count=type(list)=="table" and #list or 0 end
        if count<0 or count~=count then return end
        for index=0,math.min(128,math.floor(count))-1 do
            local element=indexed and call(list,"get",index) or list[index+1]
            if element and string.find(tostring(element),"UIDebugConsole@",1,true) then
                call(element,"setVisible",false) hidden=hidden+1
            end
        end
    end)
    return hidden
end
local function screenshot(H,label,result)
    hideDebugConsole()
    local filename=tostring(H.config.run_id).."-home-trip-"..label..".png"
    local okay,why=pcall(function() getCore():TakeFullScreenshot(filename) end)
    result(okay and "PASS" or "FAIL","home_trip_png_"..label,
        filename.."; queued native screenshot; pixels require review; "..tostring(why))
end
local function hideMiniMap(result)
    local okay,map=false,nil
    if type(getPlayerMiniMap)=="function" then okay,map=pcall(getPlayerMiniMap,0) end
    if not okay or not map then
        result("SKIP","home_trip_photo_minimap","no supported existing primary minimap; no map created")
        return
    end
    -- The installed ISMiniMap.ToggleMiniMap uses this public removal operation.
    -- Avoid its separate MiniMap.StartVisible setting write in this clone photo.
    local hidden,why=pcall(function() map:removeFromUIManager() end)
    result(hidden and call(map,"isReallyVisible")==false and "PASS" or "SKIP","home_trip_photo_minimap",
        "existing primary minimap removed without changing saved settings; "..tostring(why))
end
local function healthy(actor,allowSeated)
    local body=call(actor,"getBodyDamage")
    return actor and call(actor,"isDead")==false and call(actor,"isBridgeHealthy")==true
        and (tonumber(call(body,"getOverallBodyHealth")) or 0)>=95
        and call(body,"getNumPartsBleeding")==0 and (allowSeated==true or call(actor,"getVehicle")==nil)
end
local function preflightDiagnostic(H,label)
    local SC=S()
    local writer=getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
    local function emit(detail)
        local line="preflight="..label.."|"..detail
        print("SC_REAL_SANDBOX|HOME_PREFLIGHT|"..line)
        if writer then writer:writeln(line) end
    end
    local records=SC.Registry.snapshot()
    local document=SC.Persistence.lastDocument()
    local savedCount=0
    for _ in pairs(document and document.companions or {}) do
        savedCount=savedCount+1 if savedCount>=4096 then break end
    end
    local restored,reason,blocked=SC.Persistence.restoreStatus()
    local pending=SC.Persistence.pendingSnapshot()
    emit("registry="..#records.."|saved_companions="..savedCount
        .."|pending_count="..SC.Persistence.pendingCount().."|restore_committed="..tostring(restored)
        .."|restore_reason="..tostring(reason).."|save_blocked="..tostring(blocked)
        .."|primary="..tostring(call(H.player,"getX"))..","..tostring(call(H.player,"getY")))
    for index=1,math.min(#records,16) do
        local record=records[index] local actor=record.actor local body=call(actor,"getBodyDamage")
        local command=actor and SC.Commands.peek(actor)
        local methodKind="nil"
        if actor then
            local okay,value=pcall(function() return type(actor.isBridgeHealthy) end)
            methodKind=okay and value or "read_error"
        end
        emit("row="..index.."|id="..tostring(record.id).."|recruited="..tostring(record.recruited)
            .."("..type(record.recruited)..")|actor="..tostring(actor)
            .."|active="..tostring(actor and SC.Registry.isActive(actor,record.id))
            .."|dead="..tostring(call(actor,"isDead")).."|bridgeHealthy="..tostring(call(actor,"isBridgeHealthy"))
            .."|bridgeHealthyMethod="..methodKind.."|bridgeFailure="..tostring(call(actor,"getBridgeFailure"))
            .."|bodyHealth="..tostring(call(body,"getOverallBodyHealth"))
            .."|actorHealth="..tostring(call(actor,"getHealth")).."|bleeding="..tostring(call(body,"getNumPartsBleeding"))
            .."|vehicle="..tostring(call(actor,"getVehicle")).."|order="..tostring(command and command.order)
            .."|commandRecruited="..tostring(command and command.recruited)
            .."|inactive="..tostring(record.runtime and record.runtime.inactive)
            .."|removalPending="..tostring(record.runtime and record.runtime.removalPending)
            .."|xyz="..tostring(call(actor,"getX"))..","..tostring(call(actor,"getY"))..","..tostring(call(actor,"getZ")))
    end
    local ids={} for id in pairs(pending or {}) do ids[#ids+1]=id end table.sort(ids)
    for index=1,math.min(#ids,16) do
        local id=ids[index] local entry=pending[id]
        emit("pending_id="..tostring(id).."|status="..tostring(entry.status).."|reason="..tostring(entry.reason)
            .."|attempts="..tostring(entry.attempts).."|remoteHeld="..tostring(entry.remoteHeld)
            .."|restorePrimaryOnly="..tostring(entry.restorePrimaryOnly).."|hasSpawnTicket="..tostring(entry.hasSpawnTicket)
            .."|failureClass="..tostring(entry.failureClass))
    end
    if writer then writer:close() end
end
local function itemRows(actor)
    local rows,seen,count={},{},0
    local visit
    visit=function(item)
        if seen[item] then return false,"same native item appears twice" end
        seen[item]=true count=count+1
        if count>8192 then return false,"inventory proof exceeds bound" end
        local id=call(item,"getID")
        if type(id)~="number" or rows[tostring(id)] then return false,"unreadable/duplicate native item ID" end
        rows[tostring(id)]={id=id,type=call(item,"getFullType"),condition=call(item,"getCondition")}
        local nested=call(item,"getInventory")
        local items=nested and call(nested,"getItems")
        if items then for index=0,items:size()-1 do
            local okay,why=visit(items:get(index)) if not okay then return false,why end
        end end
        local parts=call(item,"getAllWeaponParts")
        if parts then for index=0,parts:size()-1 do
            local okay,why=visit(parts:get(index)) if not okay then return false,why end
        end end
        return true
    end
    local items=call(call(actor,"getInventory"),"getItems")
    if not items then return nil,"native inventory unavailable" end
    for index=0,items:size()-1 do
        local okay,why=visit(items:get(index)) if not okay then return nil,why end
    end
    return rows
end
local function sameItems(expected,actual)
    if type(expected)~="table" or type(actual)~="table" then return false,"inventory proof unavailable" end
    local total=0
    for id,row in pairs(expected) do
        total=total+1
        local got=actual[id]
        if not got or got.id~=row.id or got.type~=row.type or got.condition~=row.condition then
            return false,"native item changed/lost: "..tostring(id).." "..tostring(row.type)
        end
    end
    for id,row in pairs(actual) do if not expected[id] then return false,"extra native item: "..id.." "..tostring(row.type) end end
    return true,"same exact native IDs/types/conditions; count="..total
end
local function savedItems(inventory)
    if type(inventory)~="table" or inventory.preserveNativeIds~=true then return nil,"exact native-ID save marker missing" end
    local result={}
    local function visit(nodes)
        for _,node in ipairs(nodes or {}) do
            if type(node.nativeId)~="number" or result[tostring(node.nativeId)] then return false end
            result[tostring(node.nativeId)]={id=node.nativeId,type=node.type,condition=node.condition}
            if not visit(node.children) or not visit(node.weaponParts) then return false end
        end
        return true
    end
    if not visit(inventory.roots) then return nil,"saved native item IDs missing/duplicated" end
    return result
end
local function healthSame(expected,actual)
    if type(expected)~="table" or type(actual)~="table" then return false,"vitals proof unavailable" end
    for _,key in ipairs({"health","overallHealth"}) do
        if type(expected[key])~="number" or type(actual[key])~="number"
            or math.abs(expected[key]-actual[key])>.2 then return false,key.." differs" end
    end
    if expected.infected~=actual.infected or #(expected.parts or {})~=#(actual.parts or {}) then return false,"body identity/infection differs" end
    for index,part in ipairs(expected.parts or {}) do
        local got=actual.parts[index] or {}
        if math.abs((part.health or 0)-(got.health or -100))>.2 then return false,"body-part health differs: "..index end
        for key,value in pairs(part) do
            if type(value)=="boolean" and got[key]~=value then return false,"body-part flag differs: "..index.."/"..key end
        end
    end
    return true,"same actor/overall/part health and injury/infection flags; native needs continue normally"
end
local function captureActor(actor)
    local items,why=itemRows(actor)
    if not items then return nil,why end
    local vitals,reason=S().Vitals.capture(actor)
    if not vitals then return nil,reason end
    return {items=items,vitals=copy(vitals),name=name(actor),position=point(actor)}
end
local function nativeCounts(crew)
    local wanted,counts={},{}
    for _,member in ipairs(crew) do wanted[member.id]=true counts[member.id]=0 end
    local set=getCell():getObjectList()
    if not set or set:size()>16384 or not ArrayList then return nil,"native scheduler collection unavailable/unbounded" end
    local okay,list=pcall(function() return ArrayList.new(set) end)
    if not okay or not list then return nil,"native scheduler copy unavailable" end
    for index=0,list:size()-1 do
        local actor=list:get(index)
        if call(actor,"hasModData")==true then
            local data=call(actor,"getModData") local id=data and data.SC_Id
            if wanted[id] then counts[id]=counts[id]+1 end
        end
    end
    return counts
end
local function nativeSolo(f)
    return getSpecificPlayer(0)==f.primary and getSpecificPlayer(1)==nil
        and getSpecificPlayer(2)==nil and getSpecificPlayer(3)==nil
        and IsoPlayer.getInstance()==f.primary and SCSplitScreenProbe.isReleased()==true
end
local function cleanup(f)
    if not f then return end
    restoreObserver(f)
    stopRouteCapture(f)
    if f.postRender and Events.OnPostRender then Events.OnPostRender.Remove(f.postRender) end
    if f.commitObserver and S().Persistence.commitRemoteArrival==f.commitObserver then
        S().Persistence.commitRemoteArrival=f.originalCommit
    end
    if f.spawnTicket then
        pcall(S().Actor.cancelSpawn,f.spawnTicket)
        f.spawnTicket=nil
    end
    if f.blocked then call(f.primary,"setBlockMovement",f.originalBlock);f.blocked=false end
end
local function finish(H,f,t,result,phase,failed,detail)
    -- A dead main player may stop normal pulses before finish_wait runs.
    -- Restore test-owned flags and hooks immediately on every finish path.
    restoreObserver(f)
    stopRouteCapture(f)
    if failed then result("FAIL",failed,tostring(detail));screenshot(H,"failed-"..failed,result) end
    trace(f,failed or "complete")
    H.homeTripAcceptance=f
    f.finishAt,f.finishFrame=t,f.frames or 0
    phase("home_trip_finish_wait",t)
end
local function primaryOwns(at)
    local okay,owned=pcall(SCSplitScreenProbe.primaryAreaContains,math.floor(at.x),math.floor(at.y),math.floor(at.z))
    return okay and owned==true
end
local function safeNear(at,radius,used,maximumDistance)
    for distance=0,radius do for dx=-distance,distance do for dy=-distance,distance do
        if math.max(math.abs(dx),math.abs(dy))==distance then
            local x,y=math.floor(at.x)+dx,math.floor(at.y)+dy
            local key=x..":"..y
            local square=getCell():getGridSquare(x,y,0)
            if not (used and used[key]) and primaryOwns({x=x,y=y,z=0}) and square
                and (not maximumDistance or gap({x=x+.5,y=y+.5},at)<=maximumDistance
                    and gap({x=x,y=y},at)<=maximumDistance)
                and (not maximumDistance or S().GameplayUtil.isSquareFree(square))
                and S().GameplayUtil.isSafeSpawnSquare(square) then
                if used then used[key]=true end
                return square
            end
        end
    end end end
end
local function moveFixture(H,f,target,withCrew)
    local here=point(f.primary) local remaining=gap(here,target)
    if remaining<=FIXTURE_TARGET_TOLERANCE then return true end
    for _,advance in ipairs({math.min(32,remaining),math.min(16,remaining),math.min(8,remaining)}) do
        local at={x=here.x+(target.x-here.x)*advance/remaining,y=here.y+(target.y-here.y)*advance/remaining,z=0}
        local square=safeNear(at,5,{})
        if square then
            local used={[square:getX()..":"..square:getY()]=true}
            local crewSquares={}
            if withCrew then
                for index=1,#f.crew do
                    crewSquares[index]=safeNear({x=square:getX()+index*2,y=square:getY()+2,z=0},5,used)
                    if not crewSquares[index] then return false,"no separate loaded crew floor" end
                end
            end
            f.primary:teleportTo(square:getX()+.5,square:getY()+.5,0)
            if withCrew then for index,member in ipairs(f.crew) do
                local record=S().Registry.byId(member.id)
                if not record or record.actor~=member.actor then return false,"setup lost original recruited actor" end
                local okay,reason=S().Actor.recover(member.actor,crewSquares[index])
                if okay~=true then return false,"clone-only fixture recovery failed: "..tostring(reason) end
                S().Commands.issue(member.id,"stay",nil,f.primary)
            end end
            if gap(point(f.primary),target)<=FIXTURE_TARGET_TOLERANCE then return true end
            return nil,"advanced over already primary-loaded floor"
        end
    end
    return nil,"waiting for a safe primary-loaded fixture step"
end
-- Normal camp work may begin while another traveller/cargo is still settling.
-- It can continue an already observed duty proof, never create that proof.
local function dutyWorkCurrent(f,member,record,command)
    if not f.dutyReported or f.dutyReported[member.id]~=true then return false,"base_duty_not_observed" end
    local SC=S() local actor=record and record.actor
    if not actor or record.id~=member.id or not f.dutyActors or f.dutyActors[member.id]~=actor
        or not SC.Registry.isActive(actor,member.id) or not healthy(actor) then return false,"duty_actor_changed_or_unhealthy" end
    if not command or command.order~="work" or command.returnOrder~="base_duty"
        or command.workMode~="build" then return false,"not_duty_build_work" end
    local base=SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or not f.camp or base.id~=f.camp.id or not SC.HomeTrip.campUnchanged
        or SC.HomeTrip.campUnchanged(f.camp)~=true or SC.BaseLife.isInside(actor)~=true then return false,"duty_camp_changed_or_outside" end
    -- Residents belong to BaseLife's document, not the active base. active()
    -- already initialized that document; snapshotResident now only copies it.
    local snapshot=SC.BaseLife.snapshotResident and SC.BaseLife.snapshotResident(member.id)
    local resident=type(snapshot)=="table" and snapshot.present==true and snapshot.value
    if type(resident)~="table" or resident.baseId~=base.id or resident.duty~=true then return false,"resident_not_on_duty" end
    local target=command.workTarget
    if type(target)~="table" or target.kind~="barricade" or type(target.baseJobId)~="string"
        or target.baseJobId=="" or type(target.objectId)~="string" or target.objectId==""
        or (target.barricadeSide~=nil and target.barricadeSide~="same" and target.barricadeSide~="opposite") then return false,"unsupported_duty_work_target" end
    local job=SC.BaseLife.job and SC.BaseLife.job(target.baseJobId)
    if not job or job.id~=target.baseJobId or job.type~="barricade" or job.reservedBy~=member.id
        or (job.state~="reserved" and job.state~="active") then return false,"duty_job_not_owned" end
    local now=SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs()
    local lease=job.leaseUntil
    if type(now)~="number" or now~=now or math.abs(now)==math.huge
        or type(lease)~="number" or lease~=lease or math.abs(lease)==math.huge or lease<=now then return false,"duty_job_lease_expired" end
    local expected=job.target
    if type(expected)~="table" or expected.objectId~=target.objectId
        or expected.barricadeSide~=target.barricadeSide then return false,"duty_job_target_changed" end
    for _,axis in ipairs({"x","y","z"}) do
        local value=target[axis]
        if type(value)~="number" or value~=value or math.abs(value)==math.huge or expected[axis]~=value then return false,"duty_job_target_changed" end
    end
    for _,key in ipairs({"objectIndex","objectSignature"}) do
        if expected[key]~=nil and expected[key]~=target[key] then return false,"duty_job_target_changed" end
    end
    if not SC.BaseLife.barricadeJobCurrent
        or SC.BaseLife.barricadeJobCurrent(job.id,member.id,target.objectId)~=true then return false,"duty_barricade_no_longer_current" end
    return true,"verified_duty_barricade"
end
local function dutyCommandDetail(member,command,reason)
    local base=S().BaseLife and S().BaseLife.active and S().BaseLife.active()
    local snapshot=base and S().BaseLife.snapshotResident and S().BaseLife.snapshotResident(member.id)
    local resident=type(snapshot)=="table" and snapshot.present==true and snapshot.value
    local residentDuty=type(resident)=="table" and resident.duty
    if type(resident)~="table" then residentDuty="missing" end
    local target=command and type(command.workTarget)=="table" and command.workTarget
    return member.id.." order="..tostring(command and command.order)
        ..";returnOrder="..tostring(command and command.returnOrder)..";workMode="..tostring(command and command.workMode)
        ..";baseJobId="..tostring(target and target.baseJobId)
        ..";residentDuty="..tostring(residentDuty)..";workProof="..tostring(reason)
end
local function photoContext(f)
    if not f.dutyProofGranted or not nativeSolo(f) or S().HomeTrip.current()~=nil then return false end
    if S().ViewSession and S().ViewSession.owner and S().ViewSession.owner()~=nil then return false end
    for _,member in ipairs(f.crew or {}) do
        local record=S().Registry.byId(member.id)
        local command=record and record.actor and S().Commands.peek(record.actor)
        if not record or not record.actor or not S().Registry.isActive(record.actor,member.id)
            or not command or (command.order~="base_duty" and not dutyWorkCurrent(f,member,record,command)) then return false end
    end
    return true
end
local function photoPoint(f,job)
    local object
    if job.kind=="car" then
        object=job.witness and S().Vehicle and S().Vehicle.loadedBySqlId(job.witness.sqlId)
        if not object or call(object,"isEngineRunning")~=false
            or math.abs(tonumber(call(object,"getCurrentSpeedKmHour")) or 100)>=.1
            or gap(point(object),job.witness.position)>.05 then return nil,"saved stopped car witness unavailable or moved" end
    else
        local record=S().Registry.byId(job.id)
        object=record and record.actor
    end
    local at=point(object)
    if not at or math.abs(at.z)>.2 or not primaryOwns(at) then return nil,"target has no actual primary-owned ground position" end
    return at
end
local function checkpoint(f,state)
    if f.mode=="resume_delivery" then return ModData.get(CHECKPOINT) end
    local cp=ModData.getOrCreate(CHECKPOINT)
    cp.schema,cp.state,cp.camp,cp.homePose=1,state,copy(f.camp),copy(f.homePose)
    cp.departure,cp.primarySqlId,cp.crew=copy(f.departure),f.primarySqlId,{}
    cp.controlled=f.controlled==true
    cp.walls,cp.cars=copy(f.walls),copy(f.cars)
    for index,member in ipairs(f.crew) do cp.crew[index]={id=member.id,name=member.name} end
    cp.arrival,cp.atSave,cp.primaryPose=copy(f.arrival),copy(f.atSave),point(f.primary)
    cp.drive=f.drive and copy(f.drive) or nil
    cp.deliveryCarryWitness=state=="delivery" and copy(f.deliveryCarryWitness) or nil
    cp.observerOriginalInvisible,cp.observerOriginalGhost=f.invisible,f.ghost
    return cp
end
local function saveCheckpoint(H,f,t,check,result,phase,state)
    if state~="delivery" then checkpoint(f,state) end
    local okay,document=S().Runtime.save()
    if not check("home_trip_"..state.."_lf_save",okay==true,tostring(document)) then
        finish(H,f,t,result,phase,"home_trip_checkpoint_failed",state) return
    end
    if state=="delivery" then
        local verified,reason=Probe.verifySavedDelivery(document,f.deliveryCarryWitness,f.drive,f.crew)
        if not check("home_trip_delivery_saved_native_carry",verified==true,reason) then
            finish(H,f,t,result,phase,"home_trip_delivery_checkpoint_identity",reason) return
        end
        checkpoint(f,state)
    end
    local flushed,value=pcall(SCSplitScreenProbe.flushGlobalModDataForWorldExit)
    if not check("home_trip_"..state.."_native_flush",flushed and value==true,tostring(value)) then
        finish(H,f,t,result,phase,"home_trip_checkpoint_flush_failed",state) return
    end
    screenshot(H,state.."-saved",result)
    result("PASS","home_trip_"..state.."_checkpoint","new process must use resume_"..state.."; normal harness quit saves native world")
    finish(H,f,t,result,phase)
end
local function observeArrival(f)
    f.originalCommit=S().Persistence.commitRemoteArrival
    f.commitObserver=function(actors,camp,token,integration)
        if f.drive and Drive and Drive.beforeCommit then
            local active=S().HomeTrip.current()
            local captured,reason=Drive.beforeCommit(f,active)
            if captured~=true then
                f.drive.commitCaptureFailure=reason or "car commit observation failed"
            end
        end
        local before,complete={},true
        for _,actor in ipairs(actors or {}) do
            local id=S().Registry.idOf(actor)
            local captured=id and captureActor(actor)
            if not captured then complete=false break end
            before[id]=captured
        end
        if complete then f.arrivalCandidate=before end
        local okay,reason=f.originalCommit(actors,camp,token,integration)
        if okay==true then f.arrival=f.arrivalCandidate end
        return okay,reason
    end
    S().Persistence.commitRemoteArrival=f.commitObserver
end
local function scenery(f)
    f.walls,f.cars={},{}
    local p=f.homePose
    for dx=-10,10 do for dy=-10,10 do
        local square=getCell():getGridSquare(math.floor(p.x)+dx,math.floor(p.y)+dy,0)
        local properties=call(square,"getProperties")
        for _,flag in ipairs({{IsoFlagType.cutN,1},{IsoFlagType.cutW,2}}) do
            if #f.walls<4 and properties and call(properties,"has",flag[1])==true then
                local value=call(square,"getPlayerCutawayFlag",0,getTimestampMs())
                if type(value)=="number" then f.walls[#f.walls+1]={x=square:getX(),y=square:getY(),bit=flag[2],hidden=math.floor(value/flag[2])%2==1} end
            end
        end
    end end
    local vehicles=S().Vehicle.loadedVehicles()
    for _,vehicle in ipairs(vehicles or {}) do
        local at=point(vehicle)
        if #f.cars<6 and gap(at,p)<=45 and call(vehicle,"isEngineRunning")==false
            and math.abs(tonumber(call(vehicle,"getCurrentSpeedKmHour")) or 100)<.1 then
            local square=call(vehicle,"getSquare") or call(vehicle,"getCurrentSquare")
            local alpha=tonumber(call(vehicle,"getAlpha",0)) or 0
            local target=tonumber(call(vehicle,"getTargetAlpha",0)) or 0
            if call(square,"isSeen",0)==true and alpha>.05 and target>.05 then
                f.cars[#f.cars+1]={sqlId=call(vehicle,"getSqlId"),position=at}
            end
        end
    end
end
local function checkScenery(f,check,result)
    for index,wall in ipairs(f.walls or {}) do
        local square=getCell():getGridSquare(wall.x,wall.y,0)
        local flags=call(square,"getPlayerCutawayFlag",0,getTimestampMs())
        check("home_trip_solo_wall_"..index,type(flags)=="number" and (math.floor(flags/wall.bit)%2==1)==wall.hidden,
            "same primary pose/native wall; flags="..tostring(flags).." bit="..wall.bit.." before="..tostring(wall.hidden))
    end
    if #(f.walls or {})==0 then result("SKIP","home_trip_solo_wall_witness","no real wall witness at original primary pose; PNG review remains required") end
    for index,row in ipairs(f.cars or {}) do
        local vehicle=S().Vehicle.loadedBySqlId(row.sqlId)
        local square=call(vehicle,"getSquare") or call(vehicle,"getCurrentSquare")
        local unchanged=gap(point(vehicle),row.position)<.05 and call(vehicle,"isEngineRunning")==false
        local visible=call(square,"isSeen",0)==true and (tonumber(call(vehicle,"getAlpha",0)) or 0)>.05
            and (tonumber(call(vehicle,"getTargetAlpha",0)) or 0)>.05
        check("home_trip_solo_car_"..index,vehicle~=nil and unchanged and visible,
            "same stopped native car SQL="..tostring(row.sqlId).." unchanged="..tostring(unchanged).." visible="..tostring(visible))
    end
    if #(f.cars or {})==0 then result("SKIP","home_trip_solo_car_witness","no initially primary-visible stopped car; none manufactured") end
end
function Probe.validateDeliveryPersonalSave(saved,id)
    if type(saved)~="table" or saved.id~=id or saved.recruited~=true or type(saved.identity)~="table" then return false,"invalid_saved_crew_record" end
    local vitals=saved.vitals
    if type(vitals)~="table" or type(vitals.parts)~="table" or #vitals.parts>64 or type(vitals.infected)~="boolean" then return false,"invalid_saved_crew_vitals" end
    for _,key in ipairs({"health","overallHealth"}) do
        local value=vitals[key]
        if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false,"invalid_saved_crew_vitals" end
    end
    for _,part in ipairs(vitals.parts) do
        if type(part)~="table" or type(part.health)~="number" or part.health~=part.health or math.abs(part.health)==math.huge then return false,"invalid_saved_crew_vitals" end
    end
    local inventory=saved.inventory
    if type(inventory)~="table" or inventory.schema~=2 or inventory.complete~=true or type(inventory.roots)~="table"
        or type(inventory.equipment)~="table" or type(inventory.count)~="number" or inventory.count%1~=0
        or inventory.count<0 or inventory.count>2048 or #inventory.roots>2048
        or (inventory.preserveNativeIds~=nil and type(inventory.preserveNativeIds)~="boolean") then return false,"invalid_saved_crew_inventory" end
    local validator=S().Persistence.validateDetachedItem
    if type(validator)~="function" then return false,"saved_inventory_validator_unavailable" end
    local ids,total={},0
    local visit
    visit=function(nodes)
        for _,node in ipairs(nodes or {}) do
            if type(node.id)~="string" or ids[node.id] then return false end
            ids[node.id]=true
            if not visit(node.children) or not visit(node.weaponParts) then return false end
        end
        return true
    end
    for _,root in ipairs(inventory.roots) do
        local clean,why=validator({schema=2,complete=true,roots={root},equipment={},preserveNativeIds=inventory.preserveNativeIds})
        if not clean then return false,why end
        total=total+clean.count
        if total>2048 or not visit(clean.roots) then return false,"invalid_saved_crew_inventory" end
    end
    if total~=inventory.count then return false,"saved_inventory_count_mismatch" end
    for _,key in ipairs({"primary","secondary"}) do
        local ref=inventory.equipment[key]
        if ref~=nil and (type(ref)~="string" or not ids[ref]) then return false,"saved_equipment_reference_invalid" end
    end
    for _,key in ipairs({"worn","attached"}) do
        local entries=inventory.equipment[key]
        if entries~=nil and (type(entries)~="table" or #entries>2048) then return false,"saved_equipment_reference_invalid" end
        for _,entry in ipairs(entries or {}) do
            if type(entry)~="table" or not ids[entry.id] or type(entry.location)~="string" then return false,"saved_equipment_reference_invalid" end
        end
    end
    return true
end
function Probe.verifySavedDelivery(document,witness,drive,crew)
    if type(witness)~="table" or type(witness.members)~="table" or not drive or witness.carId~=drive.sqlId
        or type(witness.tripId)~="string" or witness.tripId=="" then return false,"carried_checkpoint_missing" end
    local trip=document and document.expedition
    local report=trip and trip.debrief
    if not report or report.kind~="home" or report.vehicleSqlId~=drive.sqlId or not report.integration
        or report.integration.tripId~=witness.tripId then return false,"carried_saved_trip_mismatch" end
    local members,original,seen={},{},{}
    for _,member in ipairs(crew or {}) do members[member.id]=true end
    for _,row in ipairs(drive.cargo or {}) do original[row.nativeId]=row end
    local carriers,count=0,0
    for id,rows in pairs(witness.members) do
        carriers=carriers+1
        if carriers>4 or not members[id] or type(rows)~="table" or #rows<1 or #rows>256 then return false,"carried_checkpoint_member_invalid" end
        local saved=document.companions and document.companions[id]
        local valid,why=Probe.validateDeliveryPersonalSave(saved,id)
        if not valid then return false,why end
        if saved.inventory.preserveNativeIds~=true then return false,"carried_member_save_lacks_native_ids:"..id end
        for _,row in ipairs(rows) do
            local expected=original[row.nativeId]
            if not expected or expected.id~=row.id or expected.itemType~=row.itemType or seen[row.nativeId] then return false,"carried_checkpoint_original_identity_changed" end
            local found=0
            for _,node in ipairs(saved.inventory.roots) do
                if node.nativeId==row.nativeId and node.type==row.itemType and type(node.modData)=="table"
                    and node.modData.LF_ItemStableId==row.id then found=found+1 end
            end
            if found~=1 then return false,"carried_native_root_not_saved_exactly:"..tostring(row.nativeId) end
            seen[row.nativeId]=true count=count+1
            if count>256 then return false,"carried_checkpoint_over_limit" end
        end
    end
    return count>0,count>0 and ("original carried native roots saved exactly="..count) or "carried_checkpoint_empty"
end
function Probe.resumeDeliveryContext(H,f,cp)
    local SC=S() local home,expedition=SC.HomeTrip,SC.ExpeditionPrototype
    if type(cp)~="table" or cp.schema~=1 or (cp.state~="walking" and cp.state~="delivery") then return false,"walking_or_delivery_checkpoint_required" end
    if not driving(H) or type(cp.drive)~="table" or type(f.drive)~="table" then return false,"drive_checkpoint_required" end
    local id=f.drive.sqlId
    if type(id)~="number" or id~=id or id<1 or id%1~=0 then return false,"drive_sql_id_invalid" end
    if not home.campUnchanged or home.campUnchanged(f.camp)~=true then return false,"captured_camp_changed" end
    local primary=point(f.primary)
    if not primary or math.abs(primary.z)>.05 or not primaryOwns(primary) or not primaryOwns(f.camp.core)
        or gap(primary,f.camp.core)>40 or SCSplitScreenProbe.debugPlayerSqlId(f.primary)~=f.primarySqlId then return false,"primary_camp_or_identity_changed" end
    local soloOkay,solo=pcall(nativeSolo,f)
    if not soloOkay or not solo or home.current()~=nil or expedition.current()~=nil
        or SC.BaseWatch.current()~=nil or SC.ViewSession.owner()~=nil then return false,"active_view_or_mission" end
    local report=expedition.lastDebrief()
    local integration=report and report.integration
    if not report or report.kind~="home" or report.endReason~="home" or report.vehicleSqlId~=id
        or not report.camp or report.camp.fingerprint~=f.camp.fingerprint
        or type(integration)~="table" or integration.kind~="home" or integration.carId~=id
        or type(integration.tripId)~="string" or integration.tripId=="" or #integration.tripId>128
        or not home.validCarReceipt or home.validCarReceipt(report.carSaveReceipt,id)~=true then return false,"matching_home_debrief_required" end
    local document=SC.Persistence.lastDocument()
    local savedTrip=document and document.expedition
    local savedReport=savedTrip and savedTrip.debrief
    if not savedTrip or savedTrip.state~="idle" or type(savedTrip.deliveries)~="table" or #savedTrip.deliveries>64
        or not savedReport or savedReport.kind~="home"
        or savedReport.vehicleSqlId~=id or not savedReport.integration or savedReport.integration.carId~=id
        or savedReport.integration.tripId~=integration.tripId then return false,"saved_home_trip_mismatch" end
    local pending=0
    for index=1,math.min(64,#(savedTrip.deliveries or {})) do
        local row=savedTrip.deliveries[index]
        if row.tripId==integration.tripId and row.kind=="home" and row.carId==id then pending=pending+1 end
    end
    if pending~=1 then return false,"saved_pending_delivery_mismatch" end
    local cargo=f.drive.cargo
    if type(cargo)~="table" or #cargo<1 or #cargo>256 or type(integration.items)~="table"
        or #integration.items~=#cargo then return false,"original_cargo_mismatch" end
    local wanted,seen={},{}
    for _,row in ipairs(cargo) do
        if type(row.nativeId)~="number" or row.nativeId~=row.nativeId or math.abs(row.nativeId)==math.huge
            or row.nativeId%1~=0 or wanted[row.nativeId] or type(row.id)~="string" or row.id==""
            or type(row.itemType)~="string" or row.itemType=="" then return false,"original_cargo_identity_invalid" end
        wanted[row.nativeId]=row
    end
    for _,row in ipairs(integration.items) do
        local original=wanted[row.nativeId]
        if not original or seen[row.nativeId] or original.id~=row.id or original.itemType~=row.itemType then return false,"pending_cargo_identity_mismatch" end
        seen[row.nativeId]=true
    end
    local summary=SC.ExpeditionIntegration.summary(integration)
    if not summary or (tonumber(summary.pending) or 0)<1 then return false,"no_pending_cargo" end
    local car=SC.Vehicle.loadedBySqlId(id) local at=point(car) local receipt=report.carSaveReceipt
    if not car then return nil,"delivery_car_not_loaded:sql="..id end
    local actualId=call(car,"getSqlId")
    if actualId~=id then return false,"saved_car_sql_mismatch:expected="..id..";actual="..tostring(actualId) end
    if not at then return nil,"delivery_car_position_pending:sql="..id end
    if gap(at,receipt)>.75 or math.abs(at.z-receipt.z)>.25 then
        return false,"saved_car_receipt_pose_mismatch:actual="..at.x..","..at.y..","..at.z..";saved="..receipt.x..","..receipt.y..","..receipt.z
    end
    local engine=call(car,"isEngineRunning")
    if engine~=false then return false,"saved_car_engine_mismatch:running="..tostring(engine) end
    local stationary,motionReason=SC.Vehicle.isStationary(car)
    if stationary~=true then return false,"saved_car_stationary_mismatch:"..tostring(motionReason) end
    local speed=tonumber(call(car,"getCurrentSpeedKmHour"))
    if not speed or speed~=speed or math.abs(speed)==math.huge or math.abs(speed)>.1 then return false,"saved_car_speed_mismatch:"..tostring(speed) end
    if not primaryOwns(at) then return nil,"delivery_car_primary_area_pending:sql="..id end
    if type(f.crew)~="table" or #f.crew<1 or #f.crew>4 or type(integration.members)~="table"
        or #integration.members~=#f.crew then return false,"saved_crew_mismatch" end
    local members,expected={},{}
    for _,row in ipairs(integration.members) do
        if type(row.id)~="string" or members[row.id] then return false,"saved_crew_mismatch" end
        members[row.id]=true
    end
    for _,member in ipairs(f.crew) do
        if not members[member.id] or expected[member.id] then return false,"saved_crew_mismatch" end
        local record=SC.Registry.byId(member.id) local actor=record and record.actor
        local actorAt=point(actor)
        local saved=document.companions and document.companions[member.id]
        local rows,why
        if saved then rows,why=savedItems(saved.inventory) end
        if not record or not actor then return nil,"delivery_crew_not_loaded:"..tostring(member.id) end
        local actualId=SC.Registry.idOf(actor)
        if record.id~=member.id or actualId and actualId~=member.id or record.recruited==false then return false,"saved_crew_identity_mismatch:"..tostring(member.id) end
        if SC.Persistence.isPending(member.id) then return nil,"delivery_crew_restore_pending:"..tostring(member.id) end
        if not actorAt then return nil,"delivery_crew_position_pending:"..tostring(member.id) end
        if record.recruited~=true or not healthy(actor) or not SC.Registry.isActive(actor,member.id) or actualId~=member.id
            or not (SC.BaseLife.isInside(actor)
                or SC.BaseLife.withinWorkReach and SC.BaseLife.withinWorkReach(actor)==true) then return false,"current_crew_unavailable:"..tostring(member.id) end
        if not primaryOwns(actorAt) then return nil,"delivery_crew_primary_area_pending:"..tostring(member.id) end
        local valid,issue=Probe.validateDeliveryPersonalSave(saved,member.id)
        if not valid then return false,"saved_crew_inventory_unavailable:"..tostring(issue or why) end
        local ordinary=saved.inventory.preserveNativeIds~=true
        if not rows and not ordinary then return false,"saved_crew_inventory_unavailable:"..tostring(why) end
        expected[member.id]={items=rows,vitals=copy(saved.vitals),personalNativeIdsUnavailable=ordinary,personalNativeReason=why}
    end
    local counts,why=nativeCounts(f.crew)
    for _,member in ipairs(f.crew) do
        if not counts or counts[member.id]==0 then return nil,"delivery_crew_native_pending:"..tostring(member.id)..";"..tostring(why) end
        if counts[member.id]~=1 then return false,"crew_native_count:"..tostring(counts[member.id]) end
    end
    if cp.state=="delivery" then
        if not cp.deliveryCarryWitness or cp.deliveryCarryWitness.tripId~=integration.tripId then return false,"carried_checkpoint_trip_mismatch" end
        local valid,why=Probe.verifySavedDelivery(document,cp.deliveryCarryWitness,f.drive,f.crew)
        if not valid then return false,why end
    end
    return true,{report=report,expected=expected,members=members,tripId=integration.tripId}
end
function Probe.deliveryReplayFinal(H,f)
    local report=S().ExpeditionPrototype.lastDebrief()
    local integration=report and report.integration
    if not report or report.kind~="home" or report.vehicleSqlId~=f.drive.sqlId or not integration
        or integration.tripId~=f.deliveryTripId or integration.carId~=f.drive.sqlId then return false,"delivery_replay_trip_changed" end
    local car=S().Vehicle.loadedBySqlId(f.drive.sqlId) local at=point(car)
    if not car or call(car,"getSqlId")~=f.drive.sqlId or not at or call(car,"isEngineRunning")~=false
        or S().Vehicle.isStationary(car)~=true or gap(at,report.carSaveReceipt)>.75
        or math.abs(at.z-report.carSaveReceipt.z)>.25 then return false,"delivery_replay_stopped_car_changed" end
    local summary=S().ExpeditionIntegration.summary(integration)
    if not summary or summary.pending~=0 or summary.stored~=#f.drive.cargo or summary.complete~=true then return nil,"waiting_reload_delivery_receipts" end
    local expected={} for _,row in ipairs(f.drive.cargo) do expected[row.nativeId]=row end
    local seen={}
    if #summary.items~=#f.drive.cargo then return false,"delivery_replay_receipts_changed" end
    for _,row in ipairs(summary.items) do
        local original=expected[row.nativeId]
        if not original or seen[row.nativeId] or original.id~=row.id or original.itemType~=row.itemType
            or row.stored~=true or row.released==true then return false,"delivery_replay_receipts_changed" end
        seen[row.nativeId]=true
    end
    if not Drive or not Drive.auditDelivery then return false,"delivery_replay_audit_unavailable" end
    local ready,holders=Drive.auditDelivery(H,f)
    if ready~=true then return ready,holders end
    for _,row in ipairs(f.drive.cargo) do if holders[row.nativeId]~="storage" then return nil,"waiting_reload_exact_permitted_storage" end end
    return true,"reload delivery only; exact original cargo stored with verified receipts"
end
local function observeRestored(f,check)
    f.restored=f.restored or {}
    for _,member in ipairs(f.crew) do
        if not f.restored[member.id] then
            local record=S().Registry.byId(member.id)
            if record and record.actor and S().Registry.isActive(record.actor,member.id) then
                local actor=record.actor local actual,why=captureActor(actor)
                local diagnostic=f.mode=="resume_delivery"
                local expected=diagnostic and f.deliveryExpected and f.deliveryExpected[member.id] or f.arrival and f.arrival[member.id]
                if expected and expected.name and expected.name~=member.name then
                    trace(f,"name-change "..member.id..";departure="..tostring(member.name)..";arrival="..tostring(expected.name))
                end
                local prefix=diagnostic and "home_trip_delivery_reload_" or "home_trip_restored_"
                local complete=check(prefix.."identity_"..member.id,healthy(actor) and S().Registry.idOf(actor)==member.id,
                    "same recruited stable ID; restored native object="..tostring(actor))
                if diagnostic and expected and expected.personalNativeIdsUnavailable then
                    complete=check(prefix.."current_native_inventory_"..member.id,actual and type(actual.items)=="table",
                        "actual current native inventory present; old personal native-ID comparison explicitly unavailable") and complete
                else
                    local same,detail=sameItems(expected and expected.items,actual and actual.items)
                    complete=check(prefix.."native_items_"..member.id,same,detail or why) and complete
                end
                if diagnostic and actual and actual.items then
                    f.deliveryNativeIds=f.deliveryNativeIds or {}
                    local unique=true
                    for id in pairs(actual.items) do
                        if f.deliveryNativeIds[id] and f.deliveryNativeIds[id]~=member.id then unique=false end
                        f.deliveryNativeIds[id]=member.id
                    end
                    complete=check(prefix.."unique_native_items_"..member.id,unique,"no native inventory ID shared by the restored crew") and complete
                end
                local medical,medicalDetail=healthSame(expected and expected.vitals,actual and actual.vitals)
                complete=check(prefix.."health_"..member.id,medical,medicalDetail) and complete
                complete=check(prefix.."name_"..member.id,actual and expected and (diagnostic or actual.name==expected.name)
                    and type(actual.name)=="string" and actual.name~="",
                    "durable arrival name="..tostring(expected and expected.name).."; restored native name="..tostring(actual and actual.name)
                        .."; screenshot required for rendered label") and complete
                local command=S().Commands.peek(actor)
                local obligation
                if not diagnostic then obligation=S().ExpeditionPrototype.integrationFor(actor) end
                local inCamp=S().BaseLife.isInside(actor) or diagnostic and S().BaseLife.withinWorkReach and S().BaseLife.withinWorkReach(actor)==true
                complete=check(prefix.."handover_owned_"..member.id,inCamp
                    and (diagnostic and f.deliveryMembers[member.id] or command and command.order=="base_duty" or obligation and obligation.kind=="home"),
                    "order="..tostring(command and command.order).."; physical cleanup/restock pending="..tostring(obligation~=nil)) and complete
                complete=check(prefix.."primary_gate_"..member.id,actual and primaryOwns(actual.position),"saved camp entered the primary map") and complete
                f.restored[member.id]=not diagnostic or complete
                if diagnostic and complete then member.actor=actor end
            end
        end
    end
    for _,member in ipairs(f.crew) do if not f.restored[member.id] then return false end end
    return true
end
local function checkPhysicalTravel(f,check,result)
    if f.mode=="resume_dormant" then return true end
    if f.drive then
        return check("home_trip_physical_home_drive",f.drive.sawDriving==true and f.drive.sawCrewSeated==true
            and (f.drive.travelled or 0)>=20 and f.continuityFailed~=true,
            "real native crew seats="..tostring(f.drive.sawCrewSeated).."; driven meters="..tostring(f.drive.travelled)
                .."; continuity failed="..tostring(f.continuityFailed==true))
    end
    local travelled=f.travelled or 0
    local detail="view observed="..tostring(f.sawSecondView).." physical distance newly sampled="..tostring(travelled)
        .." samples="..tostring(f.samples).." continuity failed="..tostring(f.continuityFailed==true)
        .." fresh arrival capture="..tostring(f.arrival~=nil)
    if f.mode=="resume_active" then
        if travelled<=.5 and f.continuityFailed~=true then
            result("SKIP","home_trip_physical_resume_segment",detail.."; insufficient new movement for final-approach proof; lifecycle checks continue")
            return true
        end
        return check("home_trip_physical_resume_segment",travelled>.5 and f.sawSecondView==true
            and f.continuityFailed~=true and f.arrival~=nil,detail)
    end
    return check("home_trip_physical_home_walk",travelled>=20 and f.sawSecondView==true
        and f.continuityFailed~=true and f.arrival~=nil,detail)
end
local function beginDeparture(H,f,t,check,result,phase)
    if driving(H) and not f.drivePrepared then phase("home_trip_drive_camp_setup",t) return end
    if f.mode=="radio" and (not Radio or not Radio.provision(H,f,check)) then
        finish(H,f,t,result,phase,"home_radio_fixture_unavailable","real native kit could not be prepared before departure") return
    end
    if f.mode=="radio" and not Radio.ready(f) then
        f.radio.prepareAt=f.radio.prepareAt or t
        if t-f.radio.prepareAt>=30000 then finish(H,f,t,result,phase,"home_radio_recruit_initialization","normal diary creation did not settle before baseline") return end
        if H.phase~="home_trip_radio_prepare" then phase("home_trip_radio_prepare",t) end
        return
    end
    local directions={north={0,-1},east={1,0},south={0,1},west={-1,0}}
    local direction=directions[H.config.home_trip_direction or "east"]
    local distance=tonumber(H.config.home_trip_distance) or 200
    if not check("home_trip_departure_option",direction and distance>=150 and distance<=350,"150..350m; default200") then finish(H,f,t,result,phase) return end
    f.target={x=f.camp.core.x+direction[1]*distance+.5,y=f.camp.core.y+direction[2]*distance+.5,z=0}
    if driving(H) then
        local target,why=Drive.departureTarget(H,f)
        if not target then finish(H,f,t,result,phase,"home_trip_drive_mapped_departure",why) return end
        f.target=target
    end
    f.setupBaseline={}
    scenery(f) screenshot(H,"camp-before",result)
    for _,member in ipairs(f.crew) do
        S().BaseWork.cancel(member.actor,"home_probe_clone_setup")
        local okay,why=S().Commands.issue(member.id,"stay",nil,H.player)
        if okay~=true then finish(H,f,t,result,phase,"home_trip_setup_stay",why) return end
        local baseline,reason=captureActor(member.actor)
        if not baseline then finish(H,f,t,result,phase,"home_trip_setup_identity_capture",reason) return end
        f.setupBaseline[member.id]=baseline
    end
    local protected,why=protectObserver(f)
    if not check("home_trip_main_observer_protected",protected==true,why) then finish(H,f,t,result,phase) return end
    captureRoutes(f) observeArrival(f)
    phase("home_trip_departure_setup",t)
end
local function holdOriginals(H,f,t,result)
    f.originalStay,f.originalStayRetry,f.originalStayReport=f.originalStay or {},f.originalStayRetry or {},f.originalStayReport or {}
    for _,record in ipairs(S().Registry.snapshot()) do
        if record.recruited and record.actor and not call(record.actor,"isDead") and not f.controlledIds[record.id] then
            f.originalStay[record.id]=f.originalStay[record.id] or record.actor
            local command=S().Commands.peek(record.actor)
            if (not command or command.order~="stay") and t>=(f.originalStayRetry[record.id] or 0) then
                f.originalStayRetry[record.id]=t+1000
                local accepted,reason=S().Commands.issue(record.id,"stay",nil,H.player)
                local status=accepted==true and "stay" or "pending"
                if f.originalStayReport[record.id]~=status then
                    f.originalStayReport[record.id]=status
                    result(accepted==true and "PASS" or "SKIP","home_trip_original_stay_"..record.id,
                        "ordinary Stay "..status.."; "..tostring(reason).."; no forced lifecycle cleanup")
                end
            end
        end
    end
end
function Probe.resumeDeliverySetup(H,f,cp,t,check,result,phase)
    local ready,proof=Probe.resumeDeliveryContext(H,f,cp)
    if ready==nil then
        f.deliveryResumeStartedAt=f.deliveryResumeStartedAt or t
        if t-f.deliveryResumeStartedAt>=20000 then
            finish(H,f,t,result,phase,"home_trip_delivery_replay_load_deadline",proof)
            return
        end
        if f.deliveryResumeReason~=proof then
            result("SKIP","home_trip_delivery_replay_loading",proof.."; bounded20s natural load/restore wait; no world changes")
            f.deliveryResumeReason=proof
        end
        f.deliveryResumeRetryAt=t+1000
        if H.phase~="home_trip_delivery_resume_wait" then phase("home_trip_delivery_resume_wait",t) end
        return
    end
    if not check("home_trip_delivery_replay_context",ready==true,tostring(ready and proof.tripId or proof)) then finish(H,f,t,result,phase) return end
    f.deliveryExpected,f.deliveryMembers,f.deliveryTripId=proof.expected,proof.members,proof.tripId
    for id,expected in pairs(proof.expected) do
        if expected.personalNativeIdsUnavailable then
            result("SKIP","home_trip_delivery_reload_personal_native_ids_unavailable_"..id,
                "diagnostic only: saved personal native-ID proof unavailable; current healthy identity/inventory and exact trunk cargo remain checked; "..tostring(expected.personalNativeReason))
        end
    end
    if not observeRestored(f,check) then finish(H,f,t,result,phase,"home_trip_delivery_replay_crew","saved current crew inventory/health did not match actual native actors") return end
    restoreObserver(f)
    result("SKIP","home_trip_delivery_diagnostic_only","replaying pending delivery after reload; original checkpoint and precommit evidence unchanged; no full-trip acceptance claimed")
    f.returnedAt,f.returnedFrame=t,f.frames
    phase("home_trip_restored",t)
end
local function setup(H,t,check,result,phase)
    local SC=S() local mode=H.config.home_trip_mode or "walk"
    local f={primary=H.player,mode=mode,crew={},frames=0,startedAt=t,nextMoveAt=t,
        ghost=call(H.player,"isGhostMode"),invisible=call(H.player,"isInvisible")}
    H.homeTripAcceptance=f
    if mode=="save_delivery" and (not driving(H) or H.config.home_trip_stop=="roadside") then
        finish(H,f,t,result,phase,"home_trip_delivery_checkpoint_mode","pickup checkpoint requires a fresh parking drive") return
    end
    if driving(H) and not check("home_trip_drive_fixture_available",Drive~=nil,"test-only physical field-car fixture") then finish(H,f,t,result,phase) return end
    if not check("home_trip_capabilities",SC.HomeTrip and SC.HomeTrip.remoteAvailable()
        and type(SCSplitScreenProbe.primaryAreaContains)=="function","production remote lease/persistence/primary-owned restoration APIs") then
        finish(H,f,t,result,phase) return
    end
    f.postRender=function() f.frames=f.frames+1 end Events.OnPostRender.Add(f.postRender)
    f.primarySqlId=SCSplitScreenProbe.debugPlayerSqlId(H.player)
    f.originalBlock=call(H.player,"isBlockMovement") or false
    if RESUME_CHECKPOINT_STATES[mode] then
        local cp=ModData.get(CHECKPOINT) local expected=RESUME_CHECKPOINT_STATES[mode]
        if not check("home_trip_saved_checkpoint",cp and cp.schema==1 and (cp.state==expected or mode=="resume_delivery" and cp.state=="delivery"),"mode="..mode) then finish(H,f,t,result,phase) return end
        f.camp,f.homePose,f.departure,f.arrival,f.atSave=copy(cp.camp),copy(cp.homePose),copy(cp.departure),copy(cp.arrival),copy(cp.atSave)
        f.walls,f.cars=copy(cp.walls),copy(cp.cars)
        f.drive=copy(cp.drive)
        if mode~="resume_delivery" then
            if type(cp.observerOriginalInvisible)=="boolean" then f.invisible=cp.observerOriginalInvisible end
            if type(cp.observerOriginalGhost)=="boolean" then f.ghost=cp.observerOriginalGhost end
        end
        f.crew=copy(cp.crew) f.primarySqlId=cp.primarySqlId f.controlled=cp.controlled==true
        if mode=="resume_delivery" then
            return Probe.resumeDeliverySetup(H,f,cp,t,check,result,phase)
        end
        if not primaryOwns(f.camp.core) then
            local protected,why=protectObserver(f)
            if not check("home_trip_resumed_observer_protected",protected==true,why) then finish(H,f,t,result,phase) return end
        else restoreObserver(f) end
        captureRoutes(f) observeArrival(f)
        trace(f,"resume-checkpoint state="..tostring(cp.state)..";saved-departure="..tostring(f.departure and f.departure.x)
            ..","..tostring(f.departure and f.departure.y)..","..tostring(f.departure and f.departure.z))
        phase(mode~="resume_dormant" and "home_trip_resume" or "home_trip_dormant",t)
        return
    end
    local wanted=tonumber(H.config.home_trip_members) or 1
    if not check("home_trip_crew_option",wanted==1 or wanted==2 or wanted==3,"requested="..wanted) then finish(H,f,t,result,phase) return end
    if not check("home_trip_no_prior_view",SC.ExpeditionPrototype.current()==nil and SC.BaseWatch.current()==nil
        and SC.ViewSession.owner()==nil and getSpecificPlayer(1)==nil,"refuse existing expedition/watch; no reset") then finish(H,f,t,result,phase) return end
    f.camp=SC.HomeTrip.captureCamp(SC.BaseLife.active()) f.homePose=point(H.player)
    if not check("home_trip_real_ground_camp",f.camp~=nil and f.homePose and math.abs(f.homePose.z)<.05
        and primaryOwns(f.camp.core) and gap(f.homePose,f.camp.core)<=40,
        "existing camp loaded by primary within40m; primary ground floor required") then finish(H,f,t,result,phase) return end
    if H.config.home_trip_controlled=="true" then
        f.controlled,f.wanted,f.spawnIndex,f.originalStay,f.controlledIds=true,wanted,1,{},{}
        holdOriginals(H,f,t,result)
        result("PASS","home_trip_controlled_fixture_selected",
            "clone-only public deferred spawn of "..wanted.." new recruited LF actors; original crew retained, ordinary Stay attempted; no healing/removal; any radio kit is separately disclosed before departure")
        preflightDiagnostic(H,"controlled_originals")
        phase("home_trip_controlled_spawn",t) return
    end
    for _,record in ipairs(SC.Registry.snapshot()) do
        if #f.crew<wanted and record.recruited and healthy(record.actor) and SC.Registry.isActive(record.actor,record.id) then
            f.crew[#f.crew+1]={id=record.id,actor=record.actor,name=name(record.actor)}
        end
    end
    preflightDiagnostic(H,"crew_selection")
    if not check("home_trip_existing_healthy_crew",#f.crew==wanted,"found="..#f.crew.."; no crew spawned or stocked") then finish(H,f,t,result,phase) return end
    beginDeparture(H,f,t,check,result,phase)
end
function Probe.restoredStep(H,f,t,check,result,phase)
    local restored=observeRestored(f,check)
    if not restored then
        if t-H.phaseStartedAt>60000 then finish(H,f,t,result,phase,"home_trip_restore_deadline","saved crew did not restore after primary genuinely loaded camp") end
        return
    end
    if t-f.returnedAt<2500 or f.frames-f.returnedFrame<60 then return end
    local counts,why=nativeCounts(f.crew)
    for _,member in ipairs(f.crew) do
        check("home_trip_single_restored_native_"..member.id,counts and counts[member.id]==1 and not S().Persistence.isPending(member.id),
            "native scheduled count="..tostring(counts and counts[member.id]).."; no pending replacement; "..tostring(why))
    end
    if f.drive and Drive then
        local ready,why
        if f.mode=="resume_delivery" then
            if not Drive.auditDelivery then ready,why=false,"delivery_replay_audit_unavailable"
            else
                ready,why=Drive.auditDelivery(H,f)
                if ready==true then
                    for _,row in ipairs(f.drive.cargo) do
                        local holder=why[row.nativeId]
                        if holder~="trunk" and holder~="crew" and holder~="storage" then ready,why=false,"delivery_replay_unpermitted_cargo_holder" break end
                    end
                end
            end
        else ready,why=Drive.afterRestored(H,f,t,check,result) end
        if ready==false then finish(H,f,t,result,phase,"home_trip_drive_restored_car",why) return end
        if ready~=true then
            if t-H.phaseStartedAt>60000 then finish(H,f,t,result,phase,"home_trip_drive_restore_deadline",why) end
            return
        end
    end
    check("home_trip_primary_identity_after_revisit",nativeSolo(f) and SCSplitScreenProbe.debugPlayerSqlId(f.primary)==f.primarySqlId,
        "same player singleton/SQL row, solo slot count and released secondary map")
    if f.mode~="resume_delivery" then checkScenery(f,check,result) end
    screenshot(H,f.mode=="resume_delivery" and "delivery-reloaded" or "revisited-solo",result)
    f.dutyReported,f.dutyActors={},{} phase("home_trip_duty",t)
end
function Probe.dutyTimeoutMs(H)
    local value=tonumber(H and H.config and H.config.home_trip_duty_timeout_ms)
    if not value or value~=value or math.abs(value)==math.huge or value<1000 then return 180000 end
    return math.min(600000,math.floor(value))
end
function Probe.saveDeliveryPickup(H,f,t,check,result,phase)
    local SC=S()
    if not f.drive or type(f.drive.cargo)~="table" or #f.drive.cargo<1 or #f.drive.cargo>256
        or type(f.drive.beforeCommit)~="table" or f.drive.commitCaptureFailure~=nil
        or not Drive or not Drive.auditDelivery or not nativeSolo(f) or SC.HomeTrip.current()~=nil
        or SC.ExpeditionPrototype.current()~=nil or SC.BaseWatch.current()~=nil or SC.ViewSession.owner()~=nil then
        finish(H,f,t,result,phase,"home_trip_delivery_checkpoint_context","pickup requires released solo camp context") return true
    end
    local report=SC.ExpeditionPrototype.lastDebrief()
    local car=SC.Vehicle.loadedBySqlId(f.drive.sqlId)
    if not report or report.kind~="home" or report.vehicleSqlId~=f.drive.sqlId or not report.integration
        or not SC.HomeTrip.validCarReceipt(report.carSaveReceipt,f.drive.sqlId) or not car
        or call(car,"getSqlId")~=f.drive.sqlId or call(car,"isEngineRunning")~=false or SC.Vehicle.isStationary(car)~=true
        or math.abs(tonumber(call(car,"getCurrentSpeedKmHour")) or math.huge)>.1 then
        finish(H,f,t,result,phase,"home_trip_delivery_checkpoint_car","same saved stopped native car required") return true
    end
    local ready,holders,owners=Drive.auditDelivery(H,f)
    if ready==false then finish(H,f,t,result,phase,"home_trip_delivery_checkpoint_cargo",holders) return true end
    if ready~=true then return false end
    local members={} for _,member in ipairs(f.crew) do members[member.id]=true end
    local witness={tripId=report.integration.tripId,carId=f.drive.sqlId,members={}}
    local count=0
    for _,row in ipairs(f.drive.cargo) do
        local id=owners and owners[row.nativeId]
        if holders[row.nativeId]=="crew" and members[id] then
            local record=SC.Registry.byId(id)
            if record and record.actor and SC.Registry.isActive(record.actor,id) and SC.Registry.idOf(record.actor)==id and healthy(record.actor) then
                witness.members[id]=witness.members[id] or {}
                witness.members[id][#witness.members[id]+1]=copy(row) count=count+1
            end
        end
    end
    if count==0 then return false end
    f.deliveryCarryWitness=witness
    saveCheckpoint(H,f,t,check,result,phase,"delivery")
    return true
end
function Probe.dutyStep(H,f,t,check,result,phase)
    if f.mode=="save_delivery" and Probe.saveDeliveryPickup(H,f,t,check,result,phase) then return end
    local all=true local waiting={}
    f.dutyActors=f.dutyActors or {}
    for _,member in ipairs(f.crew) do
        local record=S().Registry.byId(member.id) local actor=record and record.actor
        local command=actor and S().Commands.peek(actor)
        local direct=command and command.order=="base_duty" and S().BaseLife.isInside(actor)
        local continued,workReason=false,nil
        if not direct then continued,workReason=dutyWorkCurrent(f,member,record,command) end
        if direct or continued then
            if direct then f.dutyActors[member.id]=actor end
            if not f.dutyReported[member.id] then
                f.dutyReported[member.id]=true
                check("home_trip_real_base_duty_"..member.id,true,"production physical cleanup/restock resumed actual base duty")
            end
        else
            all=false
            f.dutyReported[member.id],f.dutyActors[member.id]=nil,nil
            local commandDetail=dutyCommandDetail(member,command,workReason)
            local obligation=actor and S().ExpeditionPrototype.integrationFor(actor)
            if not obligation or obligation.kind~="home" then
                finish(H,f,t,result,phase,"home_trip_handover_obligation_lost",commandDetail) return
            end
            local summary=S().ExpeditionIntegration.summary(obligation)
            local detail="physical home obligation remains queued"
            for _,row in ipairs(summary.members or {}) do if row.id==member.id then
                local shortages={}
                for category,amount in pairs(row.shortages or {}) do shortages[#shortages+1]=category.."="..amount end
                detail="cleanup="..tostring(row.cleanupDone).."/"..tostring(row.cleanupReason)
                    ..";duty="..tostring(row.dutyDone).."/"..tostring(row.dutyReason)
                    ..";shortages="..table.concat(shortages,",")
            end end
            waiting[#waiting+1]={id=member.id,detail=detail..";"..commandDetail}
        end
    end
    -- Settle the actual crew before starting the sliced cargo audit. A
    -- pending audit is not a new crew-state break and must not restart
    -- this clock (or start a fresh audit after its first successful pass).
    if all then
        if not f.dutyReadyAt then
            f.dutyReadyAt,f.dutyReadyFrame=t,f.frames
            return
        end
        if t-f.dutyReadyAt<1000 or f.frames-f.dutyReadyFrame<2 then return end
    else
        f.dutyReadyAt,f.dutyReadyFrame=nil,nil
        if f._homeDrive then f._homeDrive.finalAudit=nil end
    end
    if all and f.drive and Drive then
        local delivered,why
        if f.mode=="resume_delivery" then delivered,why=Probe.deliveryReplayFinal(H,f)
        else delivered,why=Drive.checkFinal(H,f,t,check,result) end
        if delivered==false then finish(H,f,t,result,phase,"home_trip_drive_final_cargo",why) return end
        if delivered~=true then
            all=false
            waiting[#waiting+1]={id="car",detail=why or "waiting for physical trunk delivery"}
        elseif f.mode=="save_delivery" then
            finish(H,f,t,result,phase,"home_trip_delivery_pickup_not_observed","cargo completed without a verified carried-root checkpoint") return
        end
    end
    if not all and t-H.phaseStartedAt<Probe.dutyTimeoutMs(H) then return end
    if not all and f.drive then
        finish(H,f,t,result,phase,"home_trip_drive_delivery_deadline",waiting[1] and waiting[1].detail or "drive crew did not finish verified handover")
        return
    end
    if not all then for _,row in ipairs(waiting) do
        result("SKIP","home_trip_real_base_duty_pending_"..row.id,row.detail.."; no supplies or cleanup result fabricated")
    end end
    if all then restoreObserver(f) end
    if all and f.mode=="resume_delivery" then
        result("PASS","home_trip_reload_delivery_complete","diagnostic reload delivery only; actual crew duty and unique original native cargo in permitted storage with every receipt verified")
        screenshot(H,"delivery-reload-complete",result)
        finish(H,f,t,result,phase)
        return
    end
    screenshot(H,all and "base-duty" or "cleanup-pending",result)
    if all then
        f.dutyProofGranted=true
        f.dutyUiShotAt,f.dutyUiShotFrame=t,f.frames
        phase("home_trip_scene_ui_wait",t)
        return
    end
    result("SKIP","home_trip_pixel_review_required","review camp-before, walking, home-dormant, revisited-solo and duty PNGs for walls, stopped cars and rendered names")
    checkpoint(f,"cleanup_pending") finish(H,f,t,result,phase)
end
function Probe.publicSendRoot(f)
    local opened=S().UI.open("groups",f.crew[1].id)
    local current=S().UI.instance
    return current and current.detail and current or opened
end
function Probe.publicSendPending(root)
    if S().HomeTrip.current()~=nil then return true end
    local current=S().UI.instance
    for _,candidate in ipairs({current or root,root}) do
        local sheet=candidate and candidate.detail and candidate.detail.homeTripSheet
        if sheet and sheet.sendPending==true then return true end
    end
    return false
end
function Probe.publicSendState(root)
    local detail=root and root.detail local sheet=detail and detail.homeTripSheet local review=sheet and sheet.review
    local function short(value) return string.sub(string.gsub(tostring(value),"[|\r\n]","_"),1,48) end
    local text="sheet="..tostring(sheet~=nil)..";pending="..tostring(sheet and sheet.pending)..";sendPending="..tostring(sheet and sheet.sendPending)
        ..";revision="..tostring(sheet and sheet.revision)..";canStart="..tostring(review and review.canStart)
        ..";blocker="..short(review and review.blocker)..";notice="..short(sheet and sheet.reviewNotice)
        ..";error="..short(review and review.error or sheet and sheet.error)..";feedback="..short(detail and detail.feedback)
    return string.sub(string.gsub(text,"[|\r\n]","_"),1,320)
end
function Probe.retryPublicSend(H,f,t,root,result,phase,why)
    if Probe.publicSendPending(root) then f.sendRoot=root phase("home_trip_dispatch",t) return true end
    local detail=root and root.detail local sheet=detail and detail.homeTripSheet
    if sheet and sheet.review and sheet.review.canStart==false and sheet.review.blocker
        and sheet.review.blocker~="home_review_changed" then return false end
    local changed=sheet and (sheet.pending==true or sheet.review and sheet.review.blocker=="home_review_changed"
        or sheet.reviewNotice and sheet.reviewNotice~=f.sendAttemptNotice
        or f.sendAttemptRevision~=nil and sheet.revision~=f.sendAttemptRevision)
    if not changed then return false end
    if (f.sendAttempts or 0)>=3 or t-f.publicSendStartedAt>=15000 then
        finish(H,f,t,result,phase,"home_trip_public_send_retry_limit",why..";"..Probe.publicSendState(root)) return true
    end
    result("SKIP","home_trip_public_send_review_retry","attempt="..tostring(f.sendAttempts)..";"..why..";"..Probe.publicSendState(root))
    if sheet.pending~=true and S().UIHomeTrip.invalidate then
        local okay,reason=pcall(S().UIHomeTrip.invalidate,detail)
        if not okay then finish(H,f,t,result,phase,"home_trip_public_review_invalidate",reason) return true end
    end
    f.reviewShotAt,f.reviewShotFrame,f.reviewReadySheet,f.reviewReadyReview,f.reviewReadyRevision,f.reviewReadyKey=nil,nil,nil,nil,nil,nil
    if H.phase~="home_trip_sheet" then phase("home_trip_sheet",t) end
    return true
end
function Probe.publicSheetStep(H,f,t,check,result,phase)
    f.publicSendStartedAt=f.publicSendStartedAt or H.phaseStartedAt
    if t-f.publicSendStartedAt<1800 then return end
    local root=Probe.publicSendRoot(f)
    if Probe.publicSendPending(root) then f.sendRoot=root phase("home_trip_dispatch",t) return end
    if t-f.publicSendStartedAt>=15000 then
        finish(H,f,t,result,phase,"home_trip_public_review_deadline",Probe.publicSendState(root)) return
    end
    local sheet=root and root.detail and root.detail.homeTripSheet
    if sheet and sheet.pending==false and sheet.review and sheet.review.canStart==false and sheet.review.blocker
        and sheet.review.blocker~="home_review_changed" then
        finish(H,f,t,result,phase,"home_trip_public_review_blocked",Probe.publicSendState(root)) return
    end
    if not sheet or sheet.pending~=false or not sheet.review or sheet.review.canStart~=true then
        f.reviewShotAt,f.reviewShotFrame=nil,nil
        return
    end
    if f.reviewReadySheet~=sheet or f.reviewReadyReview~=sheet.review or f.reviewReadyRevision~=sheet.revision
        or f.reviewReadyKey~=sheet.reviewAvailabilityKey then f.reviewShotAt,f.reviewShotFrame=nil,nil end
    if not f.reviewShotAt then
        check("home_trip_scheduled_sheet_review",true,"normal scheduled UI review; "..Probe.publicSendState(root))
        local draft=S().HomeTrip.draft(f.selection,true)
        if not check("home_trip_public_review",draft.canStart==true,"blocker="..tostring(draft.blocker).." distance="..tostring(draft.distance)) then finish(H,f,t,result,phase) return end
        screenshot(H,(f.sendAttempts or 0)==0 and "review" or "review-retry-"..((f.sendAttempts or 0)+1),result)
        f.reviewShotAt,f.reviewShotFrame=t,f.frames
        f.reviewReadySheet,f.reviewReadyReview,f.reviewReadyRevision,f.reviewReadyKey=sheet,sheet.review,sheet.revision,sheet.reviewAvailabilityKey
        return
    end
    if t-f.reviewShotAt<500 or f.frames-f.reviewShotFrame<2 then return end
    root=Probe.publicSendRoot(f)
    if Probe.publicSendPending(root) then f.sendRoot=root phase("home_trip_dispatch",t) return end
    sheet=root and root.detail and root.detail.homeTripSheet
    if sheet~=f.reviewReadySheet or not sheet or sheet.pending~=false or not sheet.review or sheet.review.canStart~=true or sheet.review~=f.reviewReadyReview
        or sheet.revision~=f.reviewReadyRevision or sheet.reviewAvailabilityKey~=f.reviewReadyKey then
        f.reviewShotAt,f.reviewShotFrame=nil,nil return
    end
    f.sendAttempts=(f.sendAttempts or 0)+1
    f.sendAttemptRevision,f.sendAttemptNotice=sheet.revision,sheet.reviewNotice
    local before=Probe.publicSendState(root) local detail=root.detail
    local okay,reason=pcall(S().UIHomeTrip.onButton,detail,{scHomeAction="send"})
    root=Probe.publicSendRoot(f) f.sendRoot=root
    local diagnostic="attempt="..f.sendAttempts..";returned="..string.sub(tostring(reason),1,80)..";detailChanged="..tostring(not root or root.detail~=detail)
        ..";sheetChanged="..tostring(not root or not root.detail or root.detail.homeTripSheet~=sheet)..";after="..Probe.publicSendState(root)..";before="..before
    if not okay then finish(H,f,t,result,phase,"home_trip_public_send_error",diagnostic) return end
    if Probe.publicSendPending(root) then
        check("home_trip_public_send_queued",true,diagnostic)
        phase("home_trip_dispatch",t) return
    end
    if not Probe.retryPublicSend(H,f,t,root,result,phase,diagnostic) then finish(H,f,t,result,phase,"home_trip_public_send_queued",diagnostic) end
end
local function advance(H,t,check,result,phase)
    if H.phase~="home_trip_finish_wait" and call(H.player,"isDead")==true then
        local f=H.homeTripAcceptance or {primary=H.player,crew={},phase=H.phase}
        finish(H,f,t,result,phase,"home_trip_main_observer_dead",observerStatus(f)) return
    end
    if H.phase=="home_trip_setup" then
        if not H.homeTripPreflightLogged then
            H.homeTripPreflightLogged=true
            preflightDiagnostic(H,"first_setup_tick")
        end
        local mode=H.config.home_trip_mode or "walk"
        if not RESUME_CHECKPOINT_STATES[mode] then
            local ready=0
            for _,record in ipairs(S().Registry.snapshot()) do
                if record.recruited and healthy(record.actor) and S().Registry.isActive(record.actor,record.id) then ready=ready+1 end
            end
            local waiting=H.config.home_trip_controlled=="true" and (not S().BaseLife.active() or #S().Registry.snapshot()==0)
                or H.config.home_trip_controlled~="true" and (not S().BaseLife.active() or ready<(tonumber(H.config.home_trip_members) or 1))
            if waiting
                and t-H.phaseStartedAt<20000 then return end
        end
        return setup(H,t,check,result,phase)
    end
    local f=H.homeTripAcceptance
    if not f then result("FAIL","home_trip_fixture_missing",H.phase);phase("finish",t) return end
    f.phase=H.phase
    if H.phase=="home_trip_finish_wait" then
        if t-f.finishAt>=500 and (not f.postRender or f.frames-f.finishFrame>=2) then cleanup(f);phase("finish",t) end
        return
    end
    if H.phase=="home_trip_delivery_resume_wait" then
        if t<(f.deliveryResumeRetryAt or 0) then return end
        return Probe.resumeDeliverySetup(H,f,ModData.get(CHECKPOINT),t,check,result,phase)
    end
    if f.observerProtected then
        if REMOTE_OBSERVER_PHASES[H.phase] then
            local protected,why=protectObserver(f)
            if not protected then finish(H,f,t,result,phase,"home_trip_main_observer_flags",why) return end
        else restoreObserver(f) end
    end
    if t-f.startedAt>(tonumber(H.config.home_trip_timeout_ms) or 900000) then finish(H,f,t,result,phase,"home_trip_deadline",H.phase) return end
    if t>=(f.nextTraceAt or 0) then f.nextTraceAt=t+10000 trace(f,"pulse") end
    if f.controlled and (H.phase=="home_trip_controlled_spawn" or H.phase=="home_trip_departure_setup" or H.phase=="home_trip_drive_camp_setup") then
        holdOriginals(H,f,t,result)
    end
    if H.phase=="home_trip_radio_prepare" then
        beginDeparture(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_drive_camp_setup" then
        local prepared,why=Drive.prepareCamp(H,f,t,check,result)
        if prepared==false then finish(H,f,t,result,phase,"home_trip_drive_camp_fixture",why) return end
        if prepared~=true then
            if t-H.phaseStartedAt>60000 then finish(H,f,t,result,phase,"home_trip_drive_camp_fixture_deadline",why) end
            return
        end
        f.camp=S().HomeTrip.captureCamp(S().BaseLife.active())
        f.drivePrepared=true
        beginDeparture(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_controlled_spawn" then
        if not f.spawnTicket then
            local square=safeNear({x=f.homePose.x+f.spawnIndex*3,y=f.homePose.y+3,z=0},6,{})
            if not check("home_trip_controlled_floor_"..f.spawnIndex,square~=nil and S().BaseLife.isInside(square),"separate free primary-owned existing camp floor") then finish(H,f,t,result,phase) return end
            local reason
            f.spawnTicket,reason=S().Actor.beginSpawn(square,{recruited=true,identity={
                forename=({"HomeOne","HomeTwo","HomeThree"})[f.spawnIndex],surname="Tester",gender="woman",outfit="Generic01"}})
            if not check("home_trip_controlled_spawn_request_"..f.spawnIndex,f.spawnTicket~=nil,tostring(reason)) then finish(H,f,t,result,phase) return end
            f.spawnStarted=t return
        end
        local actor,reason=S().Actor.pollSpawn(f.spawnTicket)
        if not actor and reason=="spawn_pending" and t-f.spawnStarted<20000 then return end
        if not check("home_trip_controlled_spawn_"..f.spawnIndex,actor~=nil,tostring(reason)) then finish(H,f,t,result,phase) return end
        f.spawnTicket=nil
        local id=S().Registry.idOf(actor) local record=id and S().Registry.byId(id)
        local weight=tonumber(call(call(actor,"getInventory"),"getCapacityWeight"))
        local maximum=tonumber(call(actor,"getMaxWeight"))
        if not check("home_trip_controlled_healthy_"..f.spawnIndex,record and record.recruited==true
            and S().Registry.isActive(actor,id) and healthy(actor) and weight and maximum and weight<maximum,
            "new production LF recruit="..tostring(id).." bodyHealth="..tostring(call(call(actor,"getBodyDamage"),"getOverallBodyHealth"))
                .." load="..tostring(weight).."/"..tostring(maximum).."; original vanilla factory items only") then finish(H,f,t,result,phase) return end
        f.crew[#f.crew+1]={id=id,actor=actor,name=name(actor)}
        f.controlledIds[id]=true
        local stayed,why=S().Commands.issue(id,"stay",nil,f.primary)
        if not check("home_trip_controlled_stay_"..f.spawnIndex,stayed==true,tostring(why)) then finish(H,f,t,result,phase) return end
        f.spawnIndex=f.spawnIndex+1
        if f.spawnIndex<=f.wanted then return end
        for original,object in pairs(f.originalStay) do
            local current=S().Registry.byId(original)
            if not check("home_trip_original_retained_"..original,current and current.actor==object,
                "same original saved native actor; no replacement/removal") then finish(H,f,t,result,phase) return end
        end
        preflightDiagnostic(H,"controlled_crew_ready")
        beginDeparture(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_departure_setup" then
        if t<f.nextMoveAt then return end f.nextMoveAt=t+1000
        local done,why=moveFixture(H,f,f.target,true)
        if done==false then finish(H,f,t,result,phase,"home_trip_clone_setup",why) return end
        if not done then
            if t-H.phaseStartedAt>90000 then finish(H,f,t,result,phase,"home_trip_loaded_departure_deadline",why) end
            return
        end
        f.departure=point(f.primary) f.records={}
        for _,member in ipairs(f.crew) do
            local record=S().Registry.byId(member.id)
            local okay,reason=S().Commands.issue(member.id,"follow",nil,f.primary)
            if okay~=true then finish(H,f,t,result,phase,"home_trip_setup_follow",reason) return end
            f.records[#f.records+1]=record
        end
        if not check("home_trip_remote_departure",gap(f.departure,f.camp.core)>=140 and not primaryOwns(f.camp.core),
            "camp distance="..gap(f.departure,f.camp.core).."; real camp outside primary streaming area") then finish(H,f,t,result,phase) return end
        f.selection={records=f.records,leaderId=f.crew[1].id,travelMode=H.config.home_trip_travel_mode or "straight"}
        if f.controlled and #f.crew>=2 then
            local function groupOf(record)
                local state=record.actor and S().Commands.peek(record.actor)
                if state then return state.group end
                return record.group
            end
            local chosen
            for _,candidate in ipairs({"charlie","bravo","alpha"}) do
                local used=false
                for _,record in ipairs(S().Registry.snapshot()) do
                    if groupOf(record)==candidate then used=true break end
                end
                if not used then chosen=candidate break end
            end
            if not check("home_trip_controlled_unused_squad",chosen~=nil,"unused Charlie/Bravo/Alpha required; original memberships retained") then finish(H,f,t,result,phase) return end
            local expected={}
            for _,member in ipairs(f.crew) do
                expected[member.id]=true
                local okay,reason=S().Commands.issue(member.id,"set_group",{group=chosen},f.primary)
                if not check("home_trip_controlled_squad_"..member.id,okay==true,tostring(chosen).."; ordinary set_group; "..tostring(reason)) then finish(H,f,t,result,phase) return end
            end
            local count,onlyCrew=0,true
            for _,record in ipairs(S().Registry.snapshot()) do
                if groupOf(record)==chosen then
                    count=count+1
                    if not expected[record.id] then onlyCrew=false end
                end
            end
            if not check("home_trip_controlled_exact_squad",onlyCrew and count==#f.crew,
                tostring(chosen).."; members="..count.."; only controlled crew="..tostring(onlyCrew)) then finish(H,f,t,result,phase) return end
            f.selection.group=chosen
        end
        if driving(H) then phase("home_trip_drive_field_setup",t) return end
        local opened=S().UIHomeTrip and S().UIHomeTrip.openSheet(f.selection)
        if not check("home_trip_review_sheet",opened==true,"same public Send home sheet") then finish(H,f,t,result,phase) return end
        phase("home_trip_sheet",t)
    elseif H.phase=="home_trip_drive_field_setup" then
        local prepared,why=Drive.prepareField(H,f,t,check,result)
        if prepared==false then finish(H,f,t,result,phase,"home_trip_drive_field_fixture",why) return end
        if prepared~=true then
            if t-H.phaseStartedAt>90000 then finish(H,f,t,result,phase,"home_trip_drive_field_fixture_deadline",why) end
            return
        end
        for _,member in ipairs(f.crew) do
            local captured,reason=captureActor(member.actor)
            if not captured then finish(H,f,t,result,phase,"home_trip_drive_departure_inventory",reason) return end
            f.setupBaseline[member.id]=captured
        end
        local opened=S().UIHomeTrip and S().UIHomeTrip.openSheet(f.selection)
        if not check("home_trip_drive_review_sheet",opened==true,"same public sheet; selected field car and actual crew") then finish(H,f,t,result,phase) return end
        phase("home_trip_sheet",t)
    elseif H.phase=="home_trip_sheet" then
        return Probe.publicSheetStep(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_dispatch" then
        local active=S().HomeTrip.current()
        if not active then
            f.publicSendStartedAt=f.publicSendStartedAt or H.phaseStartedAt
            local root=Probe.publicSendRoot(f) f.sendRoot=root
            if t-f.publicSendStartedAt>=15000 then finish(H,f,t,result,phase,"home_trip_scheduled_start",Probe.publicSendState(root)) return end
            if Probe.publicSendPending(root) then return end
            if Probe.retryPublicSend(H,f,t,root,result,phase,"scheduled departure returned for review") then return end
            if t-H.phaseStartedAt>1000 then finish(H,f,t,result,phase,"home_trip_scheduled_start",Probe.publicSendState(root)) end
            return
        end
        if not check("home_trip_public_start",#active.roster==#f.crew and active.scout.kind=="home",
            "normal scheduled UI update starts the exact reviewed crew") then finish(H,f,t,result,phase) return end
        f.dispatchedAt=t f.lastPoint=point(f.crew[1].actor) f.lastPointAt=t f.travelled=0 f.samples=0
        f.primary:setBlockMovement(true) f.blocked=true
        if f.mode=="radio" then phase("home_trip_radio",t)
        else checkpoint(f,"walking") phase("home_trip_walk",t) end
    elseif H.phase=="home_trip_radio" then
        return Radio.step(H,f,t,check,result,phase,{finish=finish,screenshot=screenshot,
            healthy=healthy,primaryFixed=primaryFixed,nativeSolo=nativeSolo,
            captureActor=captureActor,sameItems=sameItems,healthSame=healthSame,restoreObserver=restoreObserver,
            nativeCounts=nativeCounts,drive=Drive})
    elseif H.phase=="home_trip_resume" then
        local active=S().HomeTrip.current()
        if not active or active.restoring or getSpecificPlayer(1)==nil then
            if t-H.phaseStartedAt>90000 then finish(H,f,t,result,phase,"home_trip_resume_deadline","production cold restore did not resume") end
            return
        end
        if not check("home_trip_resumed_exact_roster",#active.roster==#f.crew and active.scout.kind=="home","production saved home mission, no duplicate start") then finish(H,f,t,result,phase) return end
        f.resumeInitial={}
        for _,member in ipairs(f.crew) do
            local record=S().Registry.byId(member.id)
            if not record or not healthy(record.actor,f.drive~=nil) or not S().ExpeditionPrototype.isMemberId(member.id) then
                finish(H,f,t,result,phase,"home_trip_resumed_member",member.id) return
            end
            member.actor=record.actor
            local initial={name=name(record.actor),position=point(record.actor)}
            f.resumeInitial[member.id]=initial
            trace(f,"resume-member "..member.id..";departure-name="..tostring(member.name)..";initial-restored-name="..tostring(initial.name)
                ..";initial-restored-position="..tostring(initial.position and initial.position.x)..","..tostring(initial.position and initial.position.y)
                ..","..tostring(initial.position and initial.position.z)..";saved-departure-displacement="..tostring(gap(initial.position,f.departure)))
        end
        screenshot(H,"resumed-walking",result)
        f.dispatchedAt=t f.lastPoint=point(f.crew[1].actor) f.lastPointAt=t f.travelled=0 f.samples=0
        f.primary:setBlockMovement(true) f.blocked=true phase("home_trip_walk",t)
    elseif H.phase=="home_trip_walk" then
        local active=S().HomeTrip.current()
        if not active then
            f.closedAt=t f.closedFrame=f.frames
            if f.blocked then f.primary:setBlockMovement(f.originalBlock);f.blocked=false end
            phase("home_trip_dormant",t) return
        end
        observeDriveStatus(f,active)
        local actor=active.leader and active.leader.actor local at=point(actor)
        if f.drive and Drive then
            local okay,reason=Drive.sample(H,f,t,active,check,result)
            if okay==false then finish(H,f,t,result,phase,"home_trip_drive_continuity",reason) return end
        end
        if not healthy(actor,f.drive~=nil) then finish(H,f,t,result,phase,"home_trip_living_leader","leader damaged/dead/unresolved; corpse safety is not bypassed") return end
        if getSpecificPlayer(1)==actor then f.sawSecondView=true end
        if at and f.lastPoint then
            local delta=gap(at,f.lastPoint)
            if delta>math.max(4,(t-f.lastPointAt)*(f.drive and .06 or .006)) then
                f.continuityFailed=true
                finish(H,f,t,result,phase,"home_trip_physical_continuity","unexpected position jump="..delta) return
            end
            f.travelled=f.travelled+delta f.samples=f.samples+1
        end
        f.lastPoint,f.lastPointAt=at,t
        if not primaryFixed(f) then finish(H,f,t,result,phase,"home_trip_primary_fixed","primary moved beyond bounded native collision drift during production travel") return end
        if not f.walkShot and f.travelled>=20 then f.walkShot=true screenshot(H,"walking",result) end
        if f.mode=="save_midtrip" and f.travelled>=25 and gap(at,f.camp.core)>=60 then
            f.atSave={}
            for _,member in ipairs(f.crew) do f.atSave[member.id]=captureActor(S().Registry.byId(member.id).actor) end
            saveCheckpoint(H,f,t,check,result,phase,"midtrip") return
        end
        if t-H.phaseStartedAt>600000 then finish(H,f,t,result,phase,"home_trip_walk_deadline",active.technicalIssue and active.technicalIssue.reason or active.scout.phase) end
    elseif H.phase=="home_trip_dormant" then
        if S().HomeTrip.current()~=nil or not nativeSolo(f) then
            if t-H.phaseStartedAt>30000 then finish(H,f,t,result,phase,"home_trip_remote_teardown_deadline",SCSplitScreenProbe.releaseDiagnostics()) end
            return
        end
        if t-H.phaseStartedAt<2000 then return end
        local okay=true local counts,why=nativeCounts(f.crew)
        for _,member in ipairs(f.crew) do
            okay=check("home_trip_dormant_identity_"..member.id,S().Registry.byId(member.id)==nil and S().Persistence.isPending(member.id)
                and counts and counts[member.id]==0,"no registered/native scheduled duplicate; pending snapshot; "..tostring(why)) and okay
            local doc=S().Persistence.lastDocument() local saved=doc and doc.companions and doc.companions[member.id]
            local rows,reason=saved and savedItems(saved.inventory)
            local expected=f.arrival and f.arrival[member.id]
            local same,detail=sameItems(expected and expected.items,rows)
            okay=check("home_trip_durable_native_items_"..member.id,saved and saved.restorePrimaryOnly==true and same,detail or reason) and okay
        end
        okay=check("home_trip_native_solo_release",nativeSolo(f),SCSplitScreenProbe.releaseDiagnostics()) and okay
        okay=check("home_trip_camp_still_remote",not primaryOwns(f.camp.core),"primary remained far away after arrival") and okay
        okay=checkPhysicalTravel(f,check,result) and okay
        screenshot(H,"home-dormant",result)
        if not okay then finish(H,f,t,result,phase) return end
        if f.mode=="save_dormant" or f.mode=="resume_midtrip_save_dormant" then
            saveCheckpoint(H,f,t,check,result,phase,"dormant") return
        end
        restoreObserver(f)
        f.nextMoveAt=t phase("home_trip_revisit",t)
    elseif H.phase=="home_trip_revisit" then
        observeRestored(f,check)
        if t<f.nextMoveAt then return end f.nextMoveAt=t+1000
        local done,why=moveFixture(H,f,f.homePose,false)
        if done==false then finish(H,f,t,result,phase,"home_trip_revisit_setup",why) return end
        if not done then
            if t-H.phaseStartedAt>120000 then finish(H,f,t,result,phase,"home_trip_revisit_deadline",why) end
            return
        end
        -- The final pose is the original, already-loaded square; native camera
        -- and wall state are allowed to settle without any cache invalidation.
        f.primary:teleportTo(f.homePose.x,f.homePose.y,f.homePose.z)
        f.returnedAt=t f.returnedFrame=f.frames phase("home_trip_restored",t)
    elseif H.phase=="home_trip_restored" then
        return Probe.restoredStep(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_duty" then
        return Probe.dutyStep(H,f,t,check,result,phase)
    elseif H.phase=="home_trip_scene_ui_wait" then
        if t-f.dutyUiShotAt<500 or f.frames-f.dutyUiShotFrame<2 then return end
        local root=S().UI and S().UI.instance
        local hidden,reason=pcall(function() root:setVisible(false) end)
        if not check("home_trip_scene_panel_hidden",hidden and call(root,"isVisible")==false,
            "existing panel hidden without changing collapsed settings; "..tostring(reason)) then finish(H,f,t,result,phase) return end
        hideMiniMap(result)
        local core=getCore() local zoom=call(core,"getZoom",0)
        if not check("home_trip_scene_zoom_available",type(zoom)=="number" and zoom==zoom and zoom>0 and zoom<=10,
            "native primary zoom="..tostring(zoom)) then finish(H,f,t,result,phase) return end
        -- Match vanilla Tutorial/Steps.lua's quarter-step zoom-out sequence,
        -- bounded to the requested scene depth and at most eight wheel steps.
        local steps=math.min(8,math.max(0,math.floor((1.5-zoom)/.25)))
        local zoomed,why=pcall(function() for _=1,steps do core:doZoomScroll(0,1) end end)
        if not check("home_trip_scene_zoom_prepared",zoomed,"vanilla zoom-out steps="..steps.." from="..zoom.."; "..tostring(why)) then finish(H,f,t,result,phase) return end
        f.sceneAt,f.sceneFrame=t,f.frames
        phase("home_trip_scene_wait",t)
    elseif H.phase=="home_trip_scene_wait" then
        if t-f.sceneAt<500 or f.frames-f.sceneFrame<2 then return end
        local root=S().UI and S().UI.instance
        if not check("home_trip_scene_panel_still_hidden",call(root,"isVisible")==false,"unobscured native scene; collapsed settings untouched") then finish(H,f,t,result,phase) return end
        screenshot(H,"solo-scene",result)
        f.photoJobs={}
        if f.drive and f.drive.beforeCommit then
            f.photoJobs[#f.photoJobs+1]={kind="car",label="home-car-scene",witness={sqlId=f.drive.sqlId,position=f.drive.beforeCommit.position}}
        end
        for index=1,math.max(1,math.min(2,#(f.cars or {}))) do
            f.photoJobs[#f.photoJobs+1]={kind="car",label=index==1 and "car-scene" or "car-scene-"..index,witness=f.cars and f.cars[index]}
        end
        for index=1,math.min(4,#(f.crew or {})) do
            f.photoJobs[#f.photoJobs+1]={kind="name",label=index==1 and "name-scene" or "name-scene-"..index,id=f.crew[index].id}
        end
        f.photoIndex,f.photoAt,f.photoFrame=1,t,f.frames
        phase("home_trip_photo_next",t)
    elseif H.phase=="home_trip_photo_next" then
        if t-f.photoAt<500 or f.frames-f.photoFrame<2 then return end
        local job=f.photoJobs[f.photoIndex]
        if not job then
            result("SKIP","home_trip_pixel_review_required","review original-pose walls/cars and postproof solo-scene/car-scene/name-scene PNGs; observer photos change only the main camera fixture")
            checkpoint(f,"complete") finish(H,f,t,result,phase) return
        end
        local ready=photoContext(f)
        local at,why
        if ready then at,why=photoPoint(f,job) else why="requires completed actual duty, restored crew and released solo context" end
        local square=at and safeNear(at,3,{},3)
        if not square then
            result("SKIP","home_trip_photo_"..job.label,why or "no existing safe primary-owned observer floor within3m; nothing moved")
            f.photoIndex,f.photoAt,f.photoFrame=f.photoIndex+1,t,f.frames
            return
        end
        f.photoDestination={x=square:getX(),y=square:getY(),z=0}
        f.primary:teleportTo(square:getX()+.5,square:getY()+.5,0)
        f.photoAt,f.photoFrame=t,f.frames
        phase("home_trip_photo_wait",t)
    elseif H.phase=="home_trip_photo_wait" then
        if t-f.photoAt<500 or f.frames-f.photoFrame<2 then return end
        local job=f.photoJobs[f.photoIndex] local here=point(f.primary)
        local reached=here and math.floor(here.x)==f.photoDestination.x and math.floor(here.y)==f.photoDestination.y
        if not reached and t-f.photoAt<3000 then return end
        local at,why
        if photoContext(f) then at,why=photoPoint(f,job) else why="solo/duty photo context no longer available" end
        if reached and at and primaryOwns(here) and gap(here,at)<=3 then
            result("PASS","home_trip_photo_"..job.label,"postproof main observer only; target distance="..gap(here,at).."; actual target="..at.x..","..at.y)
            screenshot(H,job.label,result)
        else
            result("SKIP","home_trip_photo_"..job.label,why or "observer/target did not remain on primary-owned floor within3m; no scene manufactured")
        end
        f.photoIndex,f.photoAt,f.photoFrame=f.photoIndex+1,t,f.frames
        phase("home_trip_photo_next",t)
    end
end
function Probe.step(H,t,check,result,phase)
    local okay,why=pcall(advance,H,t,check,result,phase)
    if not okay then
        local f=H.homeTripAcceptance or {primary=H.player,crew={},phase=H.phase}
        finish(H,f,t,result,phase,"home_trip_probe_error",why)
    end
end
Probe._tests={sameItems=sameItems,savedItems=savedItems,healthSame=healthSame,gap=gap,moveFixture=moveFixture,
    resumeDelivery=Probe.resumeDeliveryContext,deliveryReplayFinal=Probe.deliveryReplayFinal,
    fixtureTargetTolerance=FIXTURE_TARGET_TOLERANCE,observeRestored=observeRestored,checkPhysicalTravel=checkPhysicalTravel,trace=trace,primaryFixed=primaryFixed,healthy=healthy,
    protectObserver=protectObserver,restoreObserver=restoreObserver,cleanup=cleanup,captureRoutes=captureRoutes,stopRouteCapture=stopRouteCapture,routeCaptureLine=routeCaptureLine,
    observeDriveStatus=observeDriveStatus,hideDebugConsole=hideDebugConsole,walkTraceLine=walkTraceLine,
    setDriveForTests=function(value) local previous=Drive Drive=value return previous end}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCHomeTripProbe=Probe
return Probe
