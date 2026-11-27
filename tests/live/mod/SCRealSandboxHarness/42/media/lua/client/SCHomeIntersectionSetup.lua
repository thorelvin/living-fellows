-- SPDX-License-Identifier: MIT
-- Clone-only preparation before the public Home review; no trial movement writes.
local Setup={}
function Setup.warm(H,t,result)
    local SC=LivingFellows
    local state=H.homeCampGeometry
    if state and state.ready then return true end
    if not state then state={at=t,checked=0,stableAt=t};H.homeCampGeometry=state end
    if t-state.at>45000 then return false,"camp geometry did not settle before departure" end
    local camp=SC.HomeTrip.captureCamp(SC.BaseLife.active())
    if not camp then return false,"real ground camp unavailable" end
    local margin=tonumber(H.config.home_trip_camp_margin) or 0
    if margin>0 and not state.marginMarked then
        local a=camp.arrival
        local okay,why=SC.BaseLife.beginZone("area",{x=a.x1-margin,y=a.y1-margin,z=0})
        if okay then okay,why=SC.BaseLife.finishZone({x=a.x2+margin,y=a.y2+margin,z=0},"Home test approach") end
        if not okay then return false,tostring(why) end
        state.marginMarked=true
        result("PASS","home_trip_clone_approach_area","public camp area includes "..margin
            .." m of approach before departure; original core, areas and storage retained")
    end
    state.checked=state.checked+SC.BaseLife.autoExtendFloors(24)
    camp=SC.HomeTrip.captureCamp(SC.BaseLife.active())
    if state.fingerprint~=camp.fingerprint then
        state.fingerprint=camp.fingerprint state.stableAt=t state.checked=0
    end
    local tiles=0
    for _,zone in ipairs(SC.BaseLife.active().zones or {}) do
        if zone.kind=="area" then tiles=tiles+(zone.x2-zone.x1+1)*(zone.y2-zone.y1+1) end
    end
    if state.checked<tiles*2 or t-state.stableAt<3000 then return nil,"warming native camp stairs" end
    state.ready=true
    result("PASS","home_trip_camp_geometry_ready","public autoExtendFloors completed before snapshot; "
        .."checked="..state.checked.." tiles="..tiles.." fingerprint="..state.fingerprint)
    return true
end
function Setup.arm(actor)
    local inventory=actor:getInventory()
    local weapon=inventory and inventory:AddItem("Base.Crowbar")
    if not weapon then return false,"native crowbar creation failed" end
    actor:setPrimaryHandItem(weapon)
    actor:setSecondaryHandItem(weapon)
    return actor:getPrimaryHandItem()==weapon and LivingFellows.GameplayUtil.inventoryContains(inventory,weapon),
        "one actual crowbar before departure/inventory capture; no skill, health or zombie changes"
end
return Setup
