-- SPDX-License-Identifier: MIT
-- Demand-driven metadata discovery. Pump objects are inspected only on arrival.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.FuelStations = SC.FuelStations or {}
local S = SC.FuelStations
local searches = {}
local function call(object, method, ...)
    local value, okay = SC.GameplayUtil.call(object, method, ...)
    if okay then return value end
end
function S.isStation(place)
    if type(place) ~= "table" or not place.groundFloor then return false end
    if place.kind == "gas_station" then return true end
    for _, name in ipairs(place.rooms or {}) do
        if name == "fossoil" or name == "gas2go" or name == "gasstore"
            or name == "gasstorage" or name == "gasstation" then return true end
    end
    return false
end
function S.describe(place, actor)
    local b = place.bounds
    local x, y = SC.GameplayUtil.position(actor)
    local anchor = { x = math.floor((b.x+b.x2)/2), y = math.floor((b.y+b.y2)/2), z = 0 }
    local location = SC.Factions and SC.Factions.describeLocation and SC.Factions.describeLocation(anchor)
    local street = location and location.nearestStreet and location.nearestStreet.name
    local label = "Gas station" .. (street and " near "..street or "")
    return { id = place.id, kind = "gas_station", label = string.sub(label,1,80),
        bounds = { x=b.x,y=b.y,x2=b.x2,y2=b.y2 }, anchor=anchor, groundFloor=true,
        distance = x and math.ceil(math.sqrt((anchor.x-x)^2+(anchor.y-y)^2)) or 0,
        knowledge = "pump_unconfirmed" }
end
function S.atPoint(at, actor)
    local direct = SC.ExpeditionPlaces.atPoint(at)
    if S.isStation(direct) then return S.describe(direct,actor) end
    local rows = SC.ExpeditionPlaces.nearby(at.x,at.y,64,4096,true)
    local best, distance
    for _, place in ipairs(rows or {}) do
        if S.isStation(place) then
            local b=place.bounds
            local dx=math.max(b.x-at.x,0,at.x-b.x2)
            local dy=math.max(b.y-at.y,0,at.y-b.y2)
            local d=dx*dx+dy*dy
            if d<=64*64 and (not distance or d<distance) then best,distance=place,d end
        end
    end
    return best and S.describe(best,actor) or nil
end
function S.candidates(actor, refresh, origin)
    local x,y,z=SC.GameplayUtil.position(actor)
    if origin then x,y,z=origin.x,origin.y,origin.z end
    if not x or math.floor(z+0.05)~=0 then return nil,"fuel_station_ground_floor" end
    local key=math.floor(x/200)..":"..math.floor(y/200)
    if refresh then searches[key]=nil end
    local scan=searches[key]
    if not scan then
        -- Rings of 400-square metadata sectors, never a 5,000-tile world scan.
        scan={ x=math.floor(x),y=math.floor(y),sectors={},index=1,seen={},sites={} }
        for ring=0,13 do
            for dy=-ring,ring do for dx=-ring,ring do
                if math.max(math.abs(dx),math.abs(dy))==ring then
                    scan.sectors[#scan.sectors+1]={x=math.max(0,math.min(30000,scan.x+dx*400)),
                        y=math.max(0,math.min(30000,scan.y+dy*400))}
                end
            end end
        end
        searches[key]=scan
    end
    if not scan.done then
        -- One bounded native query per call. The caller owns scheduling.
        local sector=scan.sectors[scan.index]
        if sector then
            local rows,why=SC.ExpeditionPlaces.nearby(sector.x,sector.y,200,4096,true)
            if not rows then return nil,why end
            for _,place in ipairs(rows) do
                if S.isStation(place) and not scan.seen[place.id] then
                    scan.seen[place.id]=true
                    local site=S.describe(place,actor)
                    site.distance=math.ceil(math.sqrt((site.anchor.x-scan.x)^2+(site.anchor.y-scan.y)^2))
                    if site.distance<=5000 and SC.ExpeditionTargets.known(site.anchor) then
                        scan.sites[#scan.sites+1]=site
                    end
                end
            end
            scan.index=scan.index+1
        end
        -- A nearby result is enough to offer a choice; additional stations can
        -- still be found on demand if its pumps prove unusable.
        scan.done=scan.index>#scan.sectors or #scan.sites>=8
    end
    table.sort(scan.sites,function(a,b)
        return a.distance==b.distance and a.id<b.id or a.distance<b.distance
    end)
    if #scan.sites==0 then return nil,scan.done and "fuel_station_missing" or "fuel_station_scan_pending" end
    return scan.sites, scan.done and nil or "fuel_station_scan_pending"
end
function S.pump(object)
    local sprite=call(object,"getSprite")
    local properties=sprite and call(sprite,"getProperties")
    if not properties then return false end
    -- getPipedFuelAmount initializes native stock and can add signage. Do not
    -- call it on every world object merely to discover pump tiles.
    if IsoPropertyType and IsoPropertyType.FUEL_AMOUNT then
        return call(properties,"has",IsoPropertyType.FUEL_AMOUNT)==true
    end
    return call(properties,"has","fuelAmount")==true or call(properties,"Is","fuelAmount")==true
end
function S.powered(pump)
    local square=call(pump,"getSquare")
    return square and (call(square,"hasGridPower")==true
        or SandboxVars and SandboxVars.AllowExteriorGenerator==true and call(square,"haveElectricity")==true) or false
end
function S.scanSite(site, state)
    local b=site.bounds
    local left,top=math.max(0,b.x-32),math.max(0,b.y-32)
    local width,height=math.min(192,b.x2-b.x+65),math.min(192,b.y2-b.y+65)
    state.scan=state.scan or 0
    state.pumps=state.pumps or {}
    local inspected=0
    while state.scan<width*height and inspected<64 do
        local index=state.scan
        state.scan,inspected=index+1,inspected+1
        local square=SC.GameplayUtil.gridSquare(left+index%width,top+math.floor(index/width),0)
        if square then
            local objects=call(square,"getObjects")
            for i=0,math.min(255,SC.GameplayUtil.listSize(objects))-1 do
                local object=SC.GameplayUtil.listGet(objects,i)
                if S.pump(object) and #state.pumps<64 then state.pumps[#state.pumps+1]=object end
            end
        end
    end
    return state.scan>=width*height,state.pumps
end
function S.generators(pump,state)
    local p=call(pump,"getSquare")
    state=state or {}
    state.generators,state.generatorSeen=state.generators or {},state.generatorSeen or {}
    local result,seen=state.generators,state.generatorSeen
    if not p then return result end
    -- Native generators must actually cover the chosen pump. No global object
    -- enumeration and no invented power state.
    state.generatorScan=state.generatorScan or 0
    local inspected=0
    while state.generatorScan<41*41 and inspected<64 do
        local n=state.generatorScan
        state.generatorScan,inspected=n+1,inspected+1
        local dx,dy=n%41-20,math.floor(n/41)-20
        local square=SC.GameplayUtil.gridSquare(p:getX()+dx,p:getY()+dy,0)
        local generator=square and call(square,"getGenerator")
        if generator and not seen[generator] then seen[generator]=true result[#result+1]=generator end
    end
    if state.generatorScan<41*41 then return nil end
    table.sort(result,function(a,b)
        local ar,br=call(a,"isActivated")==true,call(b,"isActivated")==true
        if ar~=br then return ar end
        return SC.GameplayUtil.distance(p,a)<SC.GameplayUtil.distance(p,b)
    end)
    return result
end
function S.reset() searches={} end
return S
