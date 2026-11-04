-- SPDX-License-Identifier: MIT
-- Disposable-save setup ends before public Send. After dispatch this module
-- only reads native cars, seats, items, save receipts and permitted storage.
local D = {}
local function S() return SurvivorCompanion end
local function call(object, method, ...)
    if not object then return nil end
    local indexed,callback=pcall(function() return object[method] end)
    if not indexed or type(callback)~="function" then return nil end
    local okay, value = pcall(callback,object,...)
    if okay then return value end
end
local function point(object)
    local x,y,z=tonumber(call(object,"getX")),tonumber(call(object,"getY")),tonumber(call(object,"getZ"))
    return x and y and {x=x,y=y,z=z or 0} or nil
end
local function gap(a,b) return a and b and math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) or math.huge end
local function copy(value)
    if type(value)~="table" then
        if type(value)=="string" or type(value)=="number" or type(value)=="boolean" then return value end
        return nil
    end
    local result={} for key,child in pairs(value) do result[key]=copy(child) end return result
end
local function owns(at)
    local okay,value=pcall(SCSplitScreenProbe.primaryAreaContains,math.floor(at.x),math.floor(at.y),0)
    return okay and value==true
end
local function roadTile(square)
    local sprite=call(call(square,"getFloor"),"getSprite")
    local name=call(sprite,"getName")
    return type(name)=="string" and string.find(name,"blends_street_",1,true)~=nil
        or call(call(square,"getZone"),"getType")=="Nav"
end
local function clearSquare(x,y)
    local U=S().GameplayUtil local square=U.gridSquare(x,y,0)
    if not square then return nil,"unloaded_ground" end
    if not owns({x=x,y=y}) then return nil,"outside_primary" end
    if call(square,"isOutside")~=true then return nil,"not_outside" end
    for _,method in ipairs({"getRoom","getBuilding","getRoofHideBuilding","getVehicleContainer"}) do
        if call(square,method) then return nil,method end
    end
    if call(square,"HasTree")==true then return nil,"tree" end
    if not U.isSquareFree(square) then return nil,"blocked_floor" end
    if U.squareOccupyingObject(square) then return nil,"occupying_object" end
    if U.movingBlocker(square) then return nil,"moving_blocker" end
    for z=1,2 do
        local above=U.gridSquare(x,y,z)
        if above and (call(above,"getFloor") or call(above,"getRoom") or call(above,"getBuilding")) then return nil,"upper_structure_"..z end
    end
    return square
end
local MANOEUVRE_RADIUS=12
local function manoeuvreCell(x,y)
    local U=S().GameplayUtil local square,reason=clearSquare(x,y)
    if not square then return false,reason end
    if call(square,"TreatAsSolidFloor")~=true then return false,"ground_floor_missing" end
    local east,south=U.gridSquare(x+1,y,0),U.gridSquare(x,y+1,0)
    if not east or not south then return false,"neighbour_unloaded" end
    if call(east,"TreatAsSolidFloor")~=true or call(south,"TreatAsSolidFloor")~=true then return false,"neighbour_floor_missing" end
    if call(square,"isBlockedTo",east)~=false then return false,"east_edge_blocked_or_unknown" end
    if call(square,"isBlockedTo",south)~=false then return false,"south_edge_blocked_or_unknown" end
    return true
end
local function roadProjection(route,at)
    local best,distance,heading,width,run,selected
    for index=2,#route.points do local a,b=route.points[index-1],route.points[index]
        local dx,dy=b.x-a.x,b.y-a.y local length=dx*dx+dy*dy
        local t=length>0 and math.max(0,math.min(1,((at.x-a.x)*dx+(at.y-a.y)*dy)/length)) or 0
        local p={x=a.x+dx*t,y=a.y+dy*t,z=0} local d=gap(p,at)
        if not distance or d<distance then
            best,distance=p,d
            local size=math.sqrt(length)
            heading=size>0 and {x=-dx/size,y=-dy/size} or nil
            width=math.max(tonumber(a.width) or 0,tonumber(b.width) or 0) run,selected=size,index
        end
    end
    return best,distance,heading,width,run,selected
end
local function carNormalBody()
    local manager=type(getScriptManager)=="function" and getScriptManager()
    local script=call(manager,"getVehicle","Base.CarNormal")
    if call(script,"getFullName")~="Base.CarNormal" then return nil,"car_normal_dimensions_unavailable" end
    local extents=call(script,"getExtents")
    local width,length=tonumber(call(extents,"x")),tonumber(call(extents,"z"))
    if not width or not length or not (width>.5 and width<=20 and length>1 and length<=40) then
        return nil,"car_normal_dimensions_unavailable"
    end
    -- getExtents already is the native body's scaled size. No model-scale
    -- multiplication, guessed CarNormal dimensions or spawned-car dependency.
    return {halfWidth=width*.5,halfLength=length*.5,width=width,length=length}
end
local function arrivalModel(route,target,body)
    local road,_,heading,width,run,segment=roadProjection(route,target)
    if not road or not heading then return nil end
    -- The cached route goes from camp to the field; roadProjection returns
    -- the opposite tangent, matching the crew's actual homeward direction.
    local lane=width>=6 and math.min(width*.25,width*.5+1-(body and body.halfWidth or 0)-.2) or 0
    local entryCentre={x=road.x-heading.y*lane,y=road.y+heading.x*lane,z=0}
    local goal={x=road.x,y=road.y,z=0} local mappedHeading=heading local mappedWidth=width
    local distance=gap(road,target) local into=math.min(8,distance-2)
    local driveway=into>=3
    if driveway then
        -- SCDriving's home exit carries the road route 3..8 m toward the
        -- bay at width 5. That final tangent uses the centreline, not a lane.
        heading={x=(target.x-road.x)/distance,y=(target.y-road.y)/distance}
        goal={x=road.x+heading.x*into,y=road.y+heading.y*into,z=0}
        width,lane=5,0
    end
    return {road=road,heading=heading,width=width,run=run,mappedWidth=mappedWidth,mappedHeading=mappedHeading,
        entryCentre=entryCentre,goal=goal,laneOffset=lane,driveway=driveway,segment=segment,
        centre={x=goal.x-heading.y*lane,y=goal.y+heading.x*lane,z=0}}
end
local function bodyEnvelope(at,heading,body)
    local ax=math.abs(heading.x)*(body.halfLength+.15)+math.abs(heading.y)*(body.halfWidth+.15)
    local ay=math.abs(heading.y)*(body.halfLength+.15)+math.abs(heading.x)*(body.halfWidth+.15)
    return {x1=at.x-ax,x2=at.x+ax,y1=at.y-ay,y2=at.y+ay}
end
local function sweptCorridor(from,to,heading,body,rotationRadius)
    local dx,dy=to.x-from.x,to.y-from.y
    local along=dx*heading.x+dy*heading.y local across=-dx*heading.y+dy*heading.x
    local long,wide=math.max(body.halfLength+.15,rotationRadius or 0),
        math.max(1.25,body.halfWidth+.15,rotationRadius or 0)
    local c={origin=from,heading=heading,lo=math.min(0,along)-long,hi=math.max(0,along)+long,
        left=math.min(0,across)-wide,right=math.max(0,across)+wide}
    c.bounds={x1=math.huge,x2=-math.huge,y1=math.huge,y2=-math.huge}
    for _,a in ipairs({c.lo,c.hi}) do for _,b in ipairs({c.left,c.right}) do
        local px,py=from.x+heading.x*a-heading.y*b,from.y+heading.y*a+heading.x*b
        c.bounds.x1,c.bounds.x2=math.min(c.bounds.x1,px),math.max(c.bounds.x2,px)
        c.bounds.y1,c.bounds.y2=math.min(c.bounds.y1,py),math.max(c.bounds.y2,py)
    end end
    return c
end
local function corridorCell(layout,x,y)
    if not layout.corridors then return true end
    for _,c in ipairs(layout.corridors) do
        local dx,dy=x+.5-c.origin.x,y+.5-c.origin.y local h=c.heading
        local along,across=dx*h.x+dy*h.y,-dx*h.y+dy*h.x
        local half=.5*(math.abs(h.x)+math.abs(h.y))
        if along+half>=c.lo and along-half<=c.hi and across+half>=c.left and across-half<=c.right then return true end
    end
    return false
end
local function parkingLayouts(route,x,y,body)
    if type(body)~="table" or type(body.halfWidth)~="number" or type(body.halfLength)~="number"
        or not (body.halfWidth>0 and body.halfWidth<=10 and body.halfLength>0 and body.halfLength<=20) then
        return {},"car_normal_dimensions_unavailable"
    end
    local target={x=x+.5,y=y+.5,z=0} local arrival=arrivalModel(route,target,body)
    if not arrival then return {},"projection_missing" end
    if arrival.run<12 then return {},"segment_short",arrival end
    if arrival.mappedWidth<6 then return {},"segment_narrow",arrival end
    if math.max(math.abs(arrival.heading.x),math.abs(arrival.heading.y))<.995 then return {},"approach_diagonal",arrival end
    local road,heading=arrival.road,arrival.heading
    local horizontal=math.abs(heading.x)>math.abs(heading.y)
    local early={x=arrival.centre.x-heading.x*1.5,y=arrival.centre.y-heading.y*1.5,z=0}
    local entryEarly={x=arrival.entryCentre.x-arrival.mappedHeading.x*1.5,
        y=arrival.entryCentre.y-arrival.mappedHeading.y*1.5,z=0}
    local envelope,earlier=bodyEnvelope(arrival.centre,heading,body),bodyEnvelope(early,heading,body)
    local final=bodyEnvelope(target,heading,body)
    local forwardDistance=(target.x-arrival.centre.x)*heading.x+(target.y-arrival.centre.y)*heading.y
    local lateralDistance=math.abs((target.x-arrival.centre.x)*heading.y-(target.y-arrival.centre.y)*heading.x)
    local turnRadius
    if arrival.driveway and (math.abs(heading.x-arrival.mappedHeading.x)>0.000001
        or math.abs(heading.y-arrival.mappedHeading.y)>0.000001) then
        -- The body rotates between these tangents. Its corner radius, not
        -- its unrotated half-width, bounds the actual entry/driveway sweep.
        turnRadius=math.sqrt(body.halfLength^2+body.halfWidth^2)+.15
    end
    local result={}
    for _,length in ipairs({11,9,13}) do for _,breadth in ipairs({7,9}) do
        local halfLong,halfWide=(length-1)/2,(breadth-1)/2
        local hx,hy=horizontal and halfLong or halfWide,horizontal and halfWide or halfLong
        local zone={kind="parking",x1=x-hx,x2=x+hx,y1=y-hy,y2=y+hy,z=0}
        local function fits(box)
            return box.x1>=zone.x1+.1 and box.x2<=zone.x2+.9 and box.y1>=zone.y1+.1 and box.y2<=zone.y2+.9
        end
        local contains=fits(envelope) and fits(earlier)
        local straight=fits(final)
        for _,at in ipairs({arrival.centre,early}) do
            local dx,dy=target.x-at.x,target.y-at.y local distance=math.sqrt(dx*dx+dy*dy)
            local forward=dx*heading.x+dy*heading.y local lateral=math.abs(dx*heading.y-dy*heading.x)
            if distance<.5 or distance>15 or forward/distance<.75 or lateral>.75 then straight=false end
        end
        if contains or straight then
            local corridors={sweptCorridor(entryEarly,arrival.entryCentre,arrival.mappedHeading,body,turnRadius),
                sweptCorridor(early,arrival.centre,heading,body,turnRadius)}
            if arrival.driveway then
                corridors[#corridors+1]=sweptCorridor(arrival.entryCentre,arrival.road,arrival.mappedHeading,body,turnRadius)
                corridors[#corridors+1]=sweptCorridor(arrival.road,arrival.goal,heading,body,turnRadius)
            end
            if not contains then corridors[#corridors+1]=sweptCorridor(early,target,heading,body) end
            local bounds={x1=math.huge,x2=-math.huge,y1=math.huge,y2=-math.huge}
            for _,c in ipairs(corridors) do
                bounds.x1,bounds.x2=math.min(bounds.x1,c.bounds.x1),math.max(bounds.x2,c.bounds.x2)
                bounds.y1,bounds.y2=math.min(bounds.y1,c.bounds.y1),math.max(bounds.y2,c.bounds.y2)
            end
            bounds={x1=math.floor(bounds.x1),x2=math.ceil(bounds.x2)-1,y1=math.floor(bounds.y1),y2=math.ceil(bounds.y2)-1}
            result[#result+1]={zone=zone,road=road,heading=heading,length=length,width=breadth,arrival=arrival,
                rationale=contains and "normal_arrival_body_fits" or "clear_forward_approach",
                bounds=bounds,corridors=corridors,body=body,forwardDistance=forwardDistance,lateralDistance=lateralDistance,
                turnRadius=turnRadius}
        end
    end end
    return result,#result==0 and "body_or_forward_approach_does_not_fit" or nil,arrival
end
local function scanDiagnostic(scan,stage,reason,x,y,layout)
    local stats=scan.diagnostics
    if not stats then stats={counts={},samples={},sampleCounts={}} scan.diagnostics=stats end
    reason=string.sub(tostring(reason or "unknown"),1,64)
    local key=stage..":"..reason
    if stats.counts[key]~=nil then stats.counts[key]=stats.counts[key]+1
    elseif (stats.reasonCount or 0)<24 then stats.counts[key]=1 stats.reasonCount=(stats.reasonCount or 0)+1
    else stats.other=(stats.other or 0)+1 end
    local limit=stage=="corridor" and 4 or 1
    if #stats.samples<8 and (stats.sampleCounts[stage] or 0)<limit then
        stats.sampleCounts[stage]=(stats.sampleCounts[stage] or 0)+1
        stats.samples[#stats.samples+1]=stage.."@"..tostring(x)..","..tostring(y)..":"..reason
            ..(layout and ":"..layout.length.."x"..layout.width or "")
    end
    return stats
end
local function parkingDiagnostic(scan,route,anchor,label,base)
    local stats=scan.diagnostics or {} local rows={"status="..tostring(label),"anchor="..anchor.x..","..anchor.y,
        "candidates="..tostring(stats.candidates or 0),"admitted="..tostring(stats.admitted or 0),
        "cells="..tostring(stats.cells or 0),"layoutAttempts="..tostring(stats.layoutAttempts or 0),
        "otherReasons="..tostring(stats.other or 0),"routePoints="..#route.points}
    if stats.body then rows[#rows+1]="body="..stats.body.width.."x"..stats.body.length end
    local areas=0
    for _,zone in ipairs(base and base.zones or {}) do if zone.kind=="area" then
        areas=areas+1
        rows[#rows+1]="area"..areas.."="..zone.x1..","..zone.y1..".."..zone.x2..","..zone.y2..","..tostring(zone.z)
        if areas>=8 then break end
    end end
    local keys={} for key in pairs(stats.counts or {}) do keys[#keys+1]=key end table.sort(keys)
    for _,key in ipairs(keys) do rows[#rows+1]=key.."="..stats.counts[key] end
    local segments={} for index in pairs(stats.segmentCounts or {}) do segments[#segments+1]=index end table.sort(segments)
    for _,index in ipairs(segments) do rows[#rows+1]="selectedSegment"..index.."="..stats.segmentCounts[index] end
    for index,value in ipairs(stats.samples or {}) do rows[#rows+1]="sample"..index.."="..value end
    for index=2,math.min(#route.points,9) do local a,b=route.points[index-1],route.points[index]
        local dx,dy=b.x-a.x,b.y-a.y local length=math.sqrt(dx*dx+dy*dy)
        rows[#rows+1]="segment"..index.."="..a.x..","..a.y..">"..b.x..","..b.y
            ..":width="..math.max(tonumber(a.width) or 0,tonumber(b.width) or 0)..":run="..length
    end
    local p=stats.projection
    if p then rows[#rows+1]="projection="..tostring(p.segment)..":width="..p.mappedWidth..":run="..p.run
        ..":mappedHeading="..p.mappedHeading.x..","..p.mappedHeading.y..":approach="..p.heading.x..","..p.heading.y end
    return table.concat(rows,"|")
end
local function nextPoint(scan)
    local r,i=scan.radius or 0,scan.index or 0
    if r==0 then scan.radius,scan.index=1,0 return scan.x,scan.y end
    if r>scan.maximum then return nil end
    local side,offset=math.floor(i/(2*r)),i%(2*r)
    local dx,dy
    if side==0 then dx,dy=-r+offset,-r elseif side==1 then dx,dy=r,-r+offset
    elseif side==2 then dx,dy=r-offset,r else dx,dy=-r,r-offset end
    scan.index=i+1 if scan.index>=8*r then scan.radius,scan.index=r+1,0 end
    return scan.x+dx,scan.y+dy
end
local function patch(scan,admit)
    -- Each candidate, bay square or manoeuvre-circle cell consumes one unit.
    -- No poll scans more than 64 units, including rejected candidates.
    for _=1,64 do
        if not scan.patch then
            local x,y=nextPoint(scan) if not x then return false,scan.failureReason or "no_existing_clear_7x7_patch" end
            local stats=scan.diagnostics or scanDiagnostic(scan,"scan","started",x,y)
            stats.candidates=(stats.candidates or 0)+1
            local accepted,room,layout,layouts=admit(x,y)
            if accepted then
                if layouts and #layouts>6 then return false,"parking_layout_limit" end
                stats.admitted=(stats.admitted or 0)+1
                if layout then stats.layoutAttempts=(stats.layoutAttempts or 0)+1 end
                scan.patch={x=x,y=y,index=0,room=room,layout=layout,layouts=layouts,layoutIndex=1}
            end
        else
            local p=scan.patch
            if p.layout then
                local bounds=p.layout.bounds local width=bounds.x2-bounds.x1+1
                local x,y=bounds.x1+p.index%width,bounds.y1+math.floor(p.index/width)
                local clear,why=true,nil
                if corridorCell(p.layout,x,y) then
                    scan.diagnostics.cells=(scan.diagnostics.cells or 0)+1
                    clear,why=manoeuvreCell(x,y)
                end
                if not clear then
                    scanDiagnostic(scan,"corridor",why,x,y,p.layout)
                    scan.failureReason="no_existing_clear_straight_parking_bay"
                    if p.layouts and p.layoutIndex<#p.layouts then
                        p.layoutIndex=p.layoutIndex+1 p.layout=p.layouts[p.layoutIndex] p.index=0
                        scan.diagnostics.layoutAttempts=scan.diagnostics.layoutAttempts+1
                    else scan.patch=nil end
                else
                    p.index=p.index+1
                    if p.index==width*(bounds.y2-bounds.y1+1) then return true,{x=p.x,y=p.y,z=0,layout=p.layout} end
                end
            elseif p.index<49 then
                local dx,dy=math.floor(p.index/7)-3,p.index%7-3
                local clear,why=clearSquare(p.x+dx,p.y+dy)
                if not clear then scanDiagnostic(scan,"patch",why,p.x+dx,p.y+dy) scan.patch=nil else p.index=p.index+1 end
            elseif not p.room then return true,{x=p.x,y=p.y,z=0}
            else
                local room=p.room
                if not p.roomX then
                    p.roomX,p.roomY=math.floor(room.x-MANOEUVRE_RADIUS),math.floor(room.y-MANOEUVRE_RADIUS)
                end
                local x,y=p.roomX,p.roomY
                local dx=math.max(math.abs(x+.5-room.x)-.5,0)
                local dy=math.max(math.abs(y+.5-room.y)-.5,0)
                local inside=dx*dx+dy*dy<=MANOEUVRE_RADIUS*MANOEUVRE_RADIUS
                local clear,why=true,nil
                if inside then clear,why=manoeuvreCell(x,y) end
                if not clear then
                    scanDiagnostic(scan,"manoeuvre",why,x,y)
                    scan.failureReason="no_existing_clear_manoeuvre_room" scan.patch=nil
                else
                    p.roomY=p.roomY+1
                    if p.roomY>math.ceil(room.y+MANOEUVRE_RADIUS) then
                        p.roomY=math.floor(room.y-MANOEUVRE_RADIUS) p.roomX=p.roomX+1
                    end
                    if p.roomX>math.ceil(room.x+MANOEUVRE_RADIUS) then return true,{x=p.x,y=p.y,z=0,room=room} end
                end
            end
        end
    end
    return nil,"bounded_patch_scan_pending"
end
local function runtime(f) f._homeDrive=f._homeDrive or {} return f._homeDrive end
local function routeOut(H,f)
    local r=runtime(f) if r.route then return r.route,nil,r.native end
    local core=f.camp and f.camp.core
    if not core then return nil,"camp_core_missing" end
    local directions={north={0,-1},east={1,0},south={0,1},west={-1,0}}
    local direction=directions[H.config.home_trip_direction or "east"]
    local distance=tonumber(H.config.home_trip_distance) or 200
    if not direction or not (distance>=150 and distance<=350) then return nil,"invalid_home_trip_departure_option" end
    r.routeTarget={x=core.x+direction[1]*distance,y=core.y+direction[2]*distance,z=0}
    local route,reason,native=S().ExpeditionRoute.planFromPoint(core,r.routeTarget)
    if route and native and tonumber(native.exitX) and tonumber(native.exitY) then r.route,r.native=route,native end
    return r.route,reason or (not r.route and "native_road_exit_missing"),r.native or native
end
local function routeUnavailable(H,f,t,reason,native)
    local r=runtime(f) local rows={"stage=camp"}
    local function field(key,value)
        rows[#rows+1]=key.."="..string.sub(string.gsub(tostring(value),"[|\r\n]","_"),1,128)
    end
    field("reason",reason) field("nativeStatus",native and native.status) field("nativeReason",native and native.reason)
    local core,target=f.camp and f.camp.core,r.routeTarget
    field("core",core and core.x..","..core.y..","..tostring(core.z))
    field("target",target and target.x..","..target.y..","..tostring(target.z))
    field("direction",H.config.home_trip_direction or "east") field("distance",H.config.home_trip_distance or 200)
    local line=table.concat(rows,"|")
    if line==r.lastRouteDiagnostic and t<(r.nextRouteDiagnosticAt or 0) then return end
    r.lastRouteDiagnostic,r.nextRouteDiagnosticAt=line,t+10000
    print("SC_REAL_SANDBOX|HOME_ROUTE_UNAVAILABLE|"..line)
    local writer=type(getFileWriter)=="function" and getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
    if writer then writer:writeln("route_unavailable|"..line);writer:close() end
end
local function trunk(vehicle)
    local _,container,reason=S().Vehicle.cargoPart(vehicle)
    return container,reason
end
local function roots(container,create)
    local items=call(container,"getItems") local result,seen={},{}
    if not items or items:size()>256 then return nil,"trunk_roots_unavailable_or_over_256" end
    for index=0,items:size()-1 do
        local item=items:get(index) local id=S().GameplayUtil.itemStableId(item,create==true)
        local nativeId=tonumber(call(item,"getID")) local itemType=call(item,"getFullType")
        if not id or not nativeId or not itemType or seen[nativeId] then return nil,"trunk_identity_missing_or_duplicate" end
        seen[nativeId]=true result[#result+1]={id=id,nativeId=nativeId,itemType=itemType}
    end
    return result
end
local function sameRoots(expected,actual)
    if not expected or not actual or #expected~=#actual then return false end
    local byId={} for _,row in ipairs(actual) do byId[row.nativeId]=row end
    for _,row in ipairs(expected) do local got=byId[row.nativeId]
        if not got or got.id~=row.id or got.itemType~=row.itemType then return false end
    end
    return true
end
local function loaded(f)
    return f.drive and f.drive.sqlId and S().Vehicle.loadedBySqlId(f.drive.sqlId) or nil
end
local function reportSummary()
    local report=S().ExpeditionPrototype.lastDebrief()
    return report and report.kind=="home" and report.integration
        and S().ExpeditionIntegration.summary(report.integration) or nil
end
function D.enabled(H) return H.config.home_trip_transport=="drive" end
function D.departureTarget(H,f)
    local route,reason,native=routeOut(H,f)
    return route and {x=tonumber(native.exitX),y=tonumber(native.exitY),z=0} or nil,reason
end
function D.prepareCamp(H,f,t,check,result)
    local B,r=S().BaseLife,runtime(f)
    f.drive=f.drive or {variant=H.config.home_trip_stop or "parking"}
    if f.drive.variant~="parking" and f.drive.variant~="roadside" then return false,"invalid_home_trip_stop" end
    if not r.removedParking then
        local ids={} for _,zone in ipairs(B.active().zones or {}) do if zone.kind=="parking" then ids[#ids+1]=zone.id end end
        for _,id in ipairs(ids) do local okay,reason=B.removeZone(id) if not okay then return false,reason end end
        r.removedParking=true
        result("PASS","home_drive_clone_parking_marks","removed "..#ids.." existing marks through BaseLife.removeZone; no cars moved")
        return nil,"parking_marks_prepared"
    end
    if not r.storageReady then
        if not r.checkedStorageRows then
            for _,row in ipairs(B.depositStorageRows("general")) do
                local okay=B.storageAcceptsDeposit(row)
                if okay then r.storageReady=true break end
            end
            r.checkedStorageRows=true
            if not r.storageReady then return nil,"checking_existing_general_storage" end
        end
        if not r.storageReady then
            local core=f.camp.core
            r.storageScan=r.storageScan or {x=math.floor(core.x),y=math.floor(core.y),maximum=40}
            for _=1,64 do
                if r.storageObjects then
                    local object=r.storageObjects:get(r.storageIndex) r.storageIndex=r.storageIndex+1
                    if r.storageIndex>=r.storageObjects:size() then r.storageObjects=nil end
                    if object and call(object,"getContainer") then
                        local marked=false for _,row in ipairs(B.active().storages or {}) do
                            if B.resolveObject(row)==object then marked=true break end
                        end
                        if not marked then local okay,why=B.registerStorage(object,"general")
                            if not okay then return false,why end r.storageReady=true break
                        end
                    end
                else
                    local x,y=nextPoint(r.storageScan) if not x then return false,"no_actual_general_storage_at_camp" end
                    local square=S().GameplayUtil.gridSquare(x,y,0)
                    if square and owns({x=x,y=y}) and B.isInside(square) then
                        local objects=call(square,"getObjects")
                        if objects and objects:size()>0 and objects:size()<=64 then r.storageObjects,r.storageIndex=objects,0 end
                    end
                end
            end
            if not r.storageReady then return nil,"general_storage_scan_pending" end
        end
        result("PASS","home_drive_real_general_storage","existing permitted camp container; no items created or cleared in storage")
        return nil,"general_storage_prepared"
    end
    if f.drive.variant=="roadside" or r.parkingReady then return true end
    local profile=H.config.home_trip_parking_profile or "long_forward"
    if profile~="long_forward" and profile~="any" then return false,"invalid_home_trip_parking_profile" end
    f.drive.parkingProfile=profile
    if not r.vehicleBody then
        local body,why=carNormalBody() if not body then return false,why end
        r.vehicleBody=body
    end
    local route,reason,native=routeOut(H,f)
    if not route then routeUnavailable(H,f,t,reason,native) return nil,reason end
    local anchor={x=tonumber(native.entryX) or route.points[1].x,y=tonumber(native.entryY) or route.points[1].y,z=0}
    r.campScan=r.campScan or {x=math.floor(anchor.x),y=math.floor(anchor.y),maximum=24,
        failureReason="no_existing_clear_straight_parking_bay"}
    local okay,at=patch(r.campScan,function(x,y)
        if gap({x=x,y=y},anchor)>24 then scanDiagnostic(r.campScan,"candidate","outside_24m",x,y) return false end
        if not B.withinWorkReach({x=x,y=y,z=0}) then scanDiagnostic(r.campScan,"candidate","outside_work_reach",x,y) return false end
        local layouts,why,arrival=parkingLayouts(route,x,y,r.vehicleBody)
        r.campScan.diagnostics.projection=arrival
        if arrival then
            local stats=r.campScan.diagnostics
            stats.segmentCounts=stats.segmentCounts or {}
            if stats.segmentCounts[arrival.segment] then stats.segmentCounts[arrival.segment]=stats.segmentCounts[arrival.segment]+1
            elseif (stats.segmentCount or 0)<8 then stats.segmentCounts[arrival.segment]=1 stats.segmentCount=(stats.segmentCount or 0)+1 end
        end
        if #layouts==0 then scanDiagnostic(r.campScan,"layout",why,x,y) end
        local legal={}
        for _,layout in ipairs(layouts) do
            -- This acceptance scene needs room to finish the road turn before
            -- the precise forward leg. Keep the general native0.5..15 model
            -- above; never silently substitute its short candidates here.
            if profile=="long_forward" and (layout.rationale~="clear_forward_approach"
                or layout.forwardDistance<7 or layout.forwardDistance>12 or layout.lateralDistance>.75) then
                scanDiagnostic(r.campScan,"profile","requires_forward_7_to_12m",x,y,layout)
            else
                local valid,reason=B.parkingZoneValid(layout.zone)
                if valid==true then legal[#legal+1]=layout
                else scanDiagnostic(r.campScan,"public_zone",reason or "rejected",x,y,layout) end
            end
        end
        if #legal>0 then return true,nil,legal[1],legal end
        return false
    end)
    if r.campScan.diagnostics then r.campScan.diagnostics.body=r.vehicleBody end
    if okay~=nil or t>=(r.nextParkingDiagnosticAt or 0) then
        r.nextParkingDiagnosticAt=t+10000
        local line=parkingDiagnostic(r.campScan,route,anchor,okay==true and "selected" or okay==false and "exhausted" or "pending",B.active())
            .."|direction="..tostring(H.config.home_trip_direction or "east").."|distance="..tostring(H.config.home_trip_distance or 200)
            .."|profile="..profile
        print("SC_REAL_SANDBOX|HOME_PARKING_SCAN|"..line)
        local writer=type(getFileWriter)=="function" and getFileWriter("SurvivorCompanionHarness/home-trip.log",true,true)
        if writer then writer:writeln("parking_scan|"..line);writer:close() end
    end
    if okay~=true then return okay,at end
    local selected=at.layout local bounds=selected.zone
    local first=S().GameplayUtil.gridSquare(bounds.x1,bounds.y1,0)
    local last=S().GameplayUtil.gridSquare(bounds.x2,bounds.y2,0)
    local begun,why=B.beginZone("parking",first) if not begun then return false,why end
    local finished,zone=B.finishZone(last,"Home drive acceptance parking") if not finished then return false,zone end
    f.drive.parkingZoneId,r.parkingReady=type(zone)=="table" and zone.id or nil,true
    f.drive.parkingLayout=copy(selected)
    result("PASS","home_drive_empty_parking","existing clear "..selected.length.."x"..selected.width.." road-parallel bay; "..selected.rationale
        .."; bounds="..bounds.x1..","..bounds.y1..".."..bounds.x2..","..bounds.y2
        .."; road="..selected.road.x..","..selected.road.y.."; heading="..selected.heading.x..","..selected.heading.y
        .."; expected="..selected.arrival.centre.x..","..selected.arrival.centre.y.."; lane="..selected.arrival.laneOffset
        .."; driveway="..tostring(selected.arrival.driveway).."; profile="..profile
        .."; finalForward="..selected.forwardDistance.."; finalLateral="..selected.lateralDistance
        .."; turnRadius="..tostring(selected.turnRadius))
    return true
end
function D.prepareField(H,f,t,check,result)
    if S().HomeTrip.current() then return false,"fixture_setup_after_dispatch_forbidden" end
    local r=runtime(f) local U=S().GameplayUtil
    if not r.vehicleBody then
        local body,why=carNormalBody() if not body then return false,why end
        r.vehicleBody=body
    end
    if not r.vehicle then
        local route,reason=routeOut(H,f) if not route then return nil,reason end
        local target=D.departureTarget(H,f) local leader=f.records and f.records[1] and f.records[1].actor
        r.fieldScan=r.fieldScan or {x=math.floor(target.x),y=math.floor(target.y),maximum=20}
        local okay,at=patch(r.fieldScan,function(x,y)
            local square=U.gridSquare(x,y,0)
            return gap({x=x,y=y},target)<=20 and gap({x=x,y=y},point(leader))<=24 and roadTile(square)
        end)
        if okay~=true then return okay,at end
        local dx,dy,best=0,0,math.huge
        for index=2,#route.points do local a,b=route.points[index-1],route.points[index]
            local distance=gap(at,b) if distance<best and gap(a,b)>1 then best,dx,dy=distance,a.x-b.x,a.y-b.y end
        end
        if dx==0 and dy==0 then return false,"road_heading_missing" end
        local direction=math.abs(dx)>=math.abs(dy) and (dx>=0 and IsoDirections.E or IsoDirections.W)
            or (dy>=0 and IsoDirections.S or IsoDirections.N)
        local spawned,vehicle=pcall(addVehicleDebug,"Base.CarNormal",direction,nil,U.gridSquare(at.x,at.y,0))
        if not spawned or not vehicle or not call(vehicle,"getSquare") then return false,"actual_car_spawn_failed" end
        local forward=call(vehicle,"getForwardVector",Vector3f.new())
        local dot=forward and (forward:x()*dx+forward:z()*dy)/math.sqrt(dx*dx+dy*dy) or -1
        if dot<.65 then return false,"spawned_car_does_not_face_camp:"..tostring(dot) end
        r.vehicle,r.spawnedAt=vehicle,t
        local tank=call(vehicle,"getPartById","GasTank") local capacity=tonumber(call(tank,"getContainerCapacity"))
        if not capacity or capacity<=0 then return false,"native_gas_tank_missing" end
        call(tank,"setContainerContentAmount",capacity)
        local battery=call(call(vehicle,"getBattery"),"getInventoryItem")
        if not battery then return false,"native_battery_missing" end call(battery,"setCurrentUsesFloat",1.0)
        call(vehicle,"setTrunkLocked",false)
        return nil,"spawned_car_settling"
    end
    local vehicle=r.vehicle local sqlId=tonumber(call(vehicle,"getSqlId"))
    if t-r.spawnedAt<1000 or not sqlId or sqlId<1 or S().Vehicle.loadedBySqlId(sqlId)~=vehicle
        or S().Vehicle.isStationary(vehicle)~=true then return nil,"waiting_actual_car_identity_and_settle" end
    if not r.stocked then
        local main=call(f.primary or H.player,"getInventory")
        local leader=f.records and f.records[1] and f.records[1].actor local inventory=call(leader,"getInventory")
        local first,spare=call(vehicle,"createVehicleKey"),call(vehicle,"createVehicleKey")
        if not first or not spare or first==spare or call(first,"getID")==call(spare,"getID") then return false,"two_native_keys_missing" end
        if call(first,"getKeyId")~=call(vehicle,"getKeyId") or call(spare,"getKeyId")~=call(vehicle,"getKeyId") then return false,"native_key_mismatch" end
        if not U.inventoryContains(main,first) then call(main,"AddItem",first) end
        if not U.inventoryContains(main,spare) then call(main,"AddItem",spare) end
        local transferred,why=U.transferItemVerified(main,inventory,spare)
        if not transferred or not U.inventoryContains(main,first) then return false,why or "primary_spare_key_missing" end
        local container,reason=trunk(vehicle) if not container then return false,reason end
        for _=1,2 do local item=call(main,"AddItem","Base.NailsBox")
            if not item then return false,"native_nails_box_creation_failed" end
            local moved,why=U.transferItemVerified(main,container,item) if not moved then return false,why end
        end
        local cargo,why=roots(container,true) if not cargo then return false,why end
        f.drive.vehicle,f.drive.sqlId,f.drive.cargo=vehicle,sqlId,cargo
        f.drive.startPosition,f.drive.travelled=point(vehicle),0
        r.lastPosition,r.lastAt=f.drive.startPosition,t
        f.drive.primaryKeyNativeId,f.drive.leaderKeyNativeId=call(first,"getID"),call(spare,"getID")
        r.stocked=true
        result("PASS","home_drive_real_car_keys_cargo","SQL="..sqlId.."; two real keys; native verified key + 2 NailsBox transfers; trunk roots="..#cargo)
    end
    f.selection.travelMode,f.selection.vehicle,f.selection.vehicleSqlId="drive",vehicle,sqlId
    f.selection.vehicleName=S().ExpeditionCar.displayName(vehicle)
    return true
end
function D.sample(H,f,t,active,check,result)
    if not f.drive then return false,"drive_checkpoint_missing" end
    local vehicle=loaded(f) if not vehicle then return true end
    local r,at=runtime(f),point(vehicle)
    if not at then return false,"native_car_position_unreadable" end
    if r.lastPosition then
        local step=gap(at,r.lastPosition) local seconds=math.max(0,(t-r.lastAt)/1000)
        if step>math.max(20,seconds*15) then return false,"native_car_big_jump:"..step end
        f.drive.travelled=(f.drive.travelled or 0)+step
    end
    r.lastPosition,r.lastAt=at,t
    f.drive.maximumDisplacement=math.max(f.drive.maximumDisplacement or 0,gap(at,f.drive.startPosition))
    local trip=active and active.scout and active.scout.vehicle
    if trip and tonumber(trip.sqlId)~=f.drive.sqlId then return false,"active_car_sql_identity_changed" end
    if trip and trip.state=="driving_home" then
        local seated=0
        for _,member in ipairs(f.crew or {}) do local record=S().Registry.byId(member.id) local actor=record and record.actor
            local seat=actor and tonumber(call(vehicle,"getSeat",actor))
            if actor and call(actor,"getVehicle")==vehicle and seat and seat>=0 and call(vehicle,"getCharacter",seat)==actor then seated=seated+1 end
        end
        f.drive.sawDriving=true
        if seated>=math.min(2,#f.crew) then f.drive.sawCrewSeated=true end
    end
    return true
end
function D.beforeCommit(f,active)
    local vehicle=loaded(f) local container=vehicle and trunk(vehicle) local cargo,why=roots(container,false)
    if not vehicle or S().Vehicle.isStationary(vehicle)~=true or call(vehicle,"isEngineRunning")~=false then return false,"car_not_stopped_engine_off_before_commit" end
    if not sameRoots(f.drive.cargo,cargo) then return false,why or "trunk_changed_before_commit" end
    local home=active and active.scout and active.scout.home local receipt=home and home.carSaveReceipt
    if not S().HomeTrip.validCarReceipt(receipt,f.drive.sqlId) or gap(receipt,point(vehicle))>.75 then
        return false,"native_car_save_receipt_missing_or_mismatched_before_commit"
    end
    f.drive.beforeCommit={position=point(vehicle),cargo=cargo,carSaveReceipt=copy(receipt),
        vehicleState=active.scout.vehicle and active.scout.vehicle.state}
    return true,"loaded stopped car, exact native trunk roots and native save receipt captured"
end
local function commitProof(f)
    local drive=f.drive
    if not drive then return false,"drive_commit_capture_missing" end
    if drive.commitCaptureFailure~=nil then return false,"drive_commit_capture_failed:"..tostring(drive.commitCaptureFailure) end
    local before=drive.beforeCommit
    if type(before)~="table" or type(before.position)~="table" then return false,"drive_commit_capture_missing" end
    for _,axis in ipairs({"x","y","z"}) do local value=before.position[axis]
        if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false,"drive_commit_pose_invalid" end
    end
    local report=S().ExpeditionPrototype.lastDebrief()
    if not report or report.kind~="home" or report.vehicleSqlId~=drive.sqlId then return false,"drive_commit_report_sql_mismatch" end
    local receipt,actual=before.carSaveReceipt,report.carSaveReceipt
    if not S().HomeTrip.validCarReceipt(receipt,drive.sqlId) or not S().HomeTrip.validCarReceipt(actual,drive.sqlId) then
        return false,"drive_commit_native_receipt_invalid"
    end
    for _,key in ipairs({"version","sqlId","tagUUID","x","y","z","worldVersion","byteLength","sha256"}) do
        if receipt[key]~=actual[key] then return false,"drive_commit_native_receipt_stale" end
    end
    if gap(receipt,before.position)>.75 or math.abs(receipt.z-before.position.z)>.25 then return false,"drive_commit_receipt_pose_mismatch" end
    if type(drive.cargo)~="table" or #drive.cargo<2 or #drive.cargo>256
        or not sameRoots(drive.cargo,before.cargo)
        or not sameRoots(drive.cargo,report.integration and report.integration.items) then return false,"drive_commit_exact_cargo_mismatch" end
    return true
end
local function auditRoots(H,f)
    local SC,B=S(),S().BaseLife local containers,labels,owners={},{},{}
    local function add(container,label)
        if container and not labels[container] then labels[container]=label containers[#containers+1]=container end
    end
    local cars=SC.Vehicle.loadedVehicles()
    if type(cars)~="table" or #cars>4096 then return nil,"native_vehicle_list_unavailable" end
    local count=0 for _,car in ipairs(cars) do
        if tonumber(call(car,"getSqlId"))==f.drive.sqlId then count=count+1 end
        add(trunk(car),car==loaded(f) and "trunk" or "other_car")
    end
    if count~=1 then return nil,"restored_car_sql_count:"..count end
    add(call(f.primary or H.player,"getInventory"),"primary")
    for _,record in ipairs(SC.Registry.snapshot() or {}) do
        local inventory=call(record.actor,"getInventory")
        add(inventory,"crew")
        if inventory then owners[inventory]=record.id end
    end
    for _,row in ipairs(B.active().storages or {}) do
        local container=B.resolveContainer(row)
        local permitted=B.storageAcceptsDeposit(row,container)==true
        add(container,permitted and "storage" or "unpermitted_storage")
    end
    return {containers=containers,labels=labels,owners=owners,cursor=1,index=0,found={},queued={},work=0}
end
local function audit(H,f,key)
    local r=runtime(f) local job=r[key]
    if not job then
        local why
        job,why=auditRoots(H,f)
        if not job then return false,why end
        r[key]=job
    end
    local wanted={} for _,row in ipairs(f.drive.cargo or {}) do wanted[row.nativeId]=row end
    for _=1,64 do
        local container=job.containers[job.cursor]
        if not container then
            local holders,owners={},{}
            for nativeId,row in pairs(wanted) do local live={}
                for _,item in ipairs(job.found[nativeId] or {}) do local holder=call(item,"getContainer")
                    if holder and S().GameplayUtil.inventoryContains(holder,item) then live[#live+1]=item end
                end
                if #live>1 then return false,"duplicate_live_cargo_native_id:"..nativeId end
                if #live==0 then r[key]=nil return nil,"waiting_exact_native_cargo_location:"..nativeId end
                local item=live[1]
                if call(item,"getFullType")~=row.itemType or S().GameplayUtil.itemStableId(item,false)~=row.id then return false,"cargo_native_identity_changed:"..nativeId end
                local container=call(item,"getContainer")
                holders[nativeId]=job.labels[container] or "nested_or_unmarked"
                owners[nativeId]=job.owners[container]
            end
            r[key]=nil return true,holders,owners
        end
        local items=call(container,"getItems")
        if not items or job.index>=items:size() then job.cursor,job.index=job.cursor+1,0
        else
            local item=items:get(job.index) job.index=job.index+1 job.work=job.work+1
            if job.work>16384 then return false,"native_cargo_audit_over_16384_items" end
            local id=tonumber(call(item,"getID"))
            if wanted[id] then local list=job.found[id] or {} local seen=false
                for _,old in ipairs(list) do if old==item then seen=true end end
                if not seen then list[#list+1]=item end job.found[id]=list
            end
            local nested=call(item,"getInventory") or call(item,"getItemContainer")
            if nested and not job.labels[nested] then
                if #job.containers>=256 then return false,"native_cargo_audit_over_256_containers" end
                job.labels[nested]="nested_or_unmarked" job.containers[#job.containers+1]=nested
            end
        end
    end
    return nil,"bounded_native_cargo_audit_pending"
end
function D.auditDelivery(H,f)
    return audit(H,f,"deliveryDiagnosticAudit")
end
function D.afterRestored(H,f,t,check,result)
    local proved,reason=commitProof(f) if not proved then return false,reason end
    local vehicle=loaded(f) if not vehicle then return nil,"waiting_same_sql_car_loaded" end
    local before=f.drive.beforeCommit
    local at=point(vehicle)
    if not before or gap(at,before.position)>.75 or not at or math.abs(at.z-before.position.z)>.25 or call(vehicle,"isEngineRunning")~=false
        or S().Vehicle.isStationary(vehicle)~=true then return false,"restored_native_car_pose_or_engine_changed" end
    local okay,holders=audit(H,f,"restoreAudit") if okay~=true then return okay,holders end
    local summary=reportSummary()
    for _,row in ipairs(f.drive.cargo) do
        if f.drive.variant=="roadside" and holders[row.nativeId]~="trunk" then return false,"roadside_cargo_left_trunk" end
        if f.drive.variant=="parking" and holders[row.nativeId]~="trunk" and holders[row.nativeId]~="storage"
            and holders[row.nativeId]~="crew" then return false,"restored_cargo_in_unpermitted_holder" end
    end
    if f.drive.variant=="roadside" and (not summary or summary.stored~=0 or summary.trunkPending~=#f.drive.cargo) then return false,"roadside_receipt_claimed_unloading" end
    result("PASS","home_drive_restored_real_car_cargo","same native SQL, stopped pose/engine, unique exact cargo IDs and actual permitted holders")
    return true
end
function D.checkFinal(H,f,t,check,result)
    local proved,reason=commitProof(f) if not proved then return false,reason end
    if not f.drive.sawDriving or not f.drive.sawCrewSeated or (f.drive.travelled or 0)<=20
        or (f.drive.maximumDisplacement or 0)<=20 then return false,"physical_car_travel_or_native_crew_seats_not_observed" end
    local okay,holders=audit(H,f,"finalAudit") if okay~=true then return okay,holders end
    local summary=reportSummary() if not summary then return nil,"waiting_home_integration_summary" end
    for _,row in ipairs(f.drive.cargo) do
        local expected=f.drive.variant=="roadside" and "trunk" or "storage"
        if holders[row.nativeId]~=expected then return nil,"waiting_exact_cargo_"..expected end
    end
    if f.drive.variant=="roadside" then
        if summary.stored~=0 or summary.trunkPending~=#f.drive.cargo then return false,"roadside_unload_receipt_mismatch" end
    else
        if summary.trunkPending~=0 or summary.stored<#f.drive.cargo then return nil,"waiting_verified_storage_receipts" end
        for _,receipt in ipairs(summary.items or {}) do
            if receipt.stored~=true then return nil,"waiting_verified_storage_receipts" end
        end
    end
    result("PASS","home_drive_physical_cargo_final",f.drive.variant.."; SQL="..f.drive.sqlId.."; travel="..f.drive.travelled.."; exact roots="..#f.drive.cargo)
    return true
end
D._tests={call=call,patch=patch,manoeuvreRadius=MANOEUVRE_RADIUS,parkingLayouts=parkingLayouts,arrivalModel=arrivalModel,
    carNormalBody=carNormalBody,corridorCell=corridorCell,
    parkingDiagnostic=parkingDiagnostic}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCHomeDriveFixture=D
return D
