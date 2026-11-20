-- SPDX-License-Identifier: MIT
-- Physical lock props share the manual's desk-surface/free-floor placement.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local Physical={} SC.TerminalLockPhysical=Physical
function Physical.place(item,object)
    if not item or not object then return nil end
    local U=SC.ControlUtil
    local tile=U.square(object) local surface=0
    for _,candidate in ipairs(U.list(U.call(tile,"getObjects"),64)) do
        if candidate~=object then surface=math.max(surface,tonumber(U.call(candidate,"getSurfaceOffsetNoTable")) or 0) end
    end
    if surface<=0 then
        local x,y,z=U.position(object) local cell=type(getCell)=="function" and getCell()
        if not x then return nil end
        tile=nil
        for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0},{1,1},{-1,1},{1,-1},{-1,-1}}) do
            local candidate=cell and U.call(cell,"getGridSquare",x+d[1],y+d[2],z)
            if candidate and U.call(candidate,"TreatAsSolidFloor")==true and SC.GameplayUtil.isSquareFree(candidate) then tile=candidate break end
        end
    end
    if not tile then return nil end
    U.call(tile,"AddWorldInventoryItem",item,.5,.5,surface/96)
    local world=U.call(item,"getWorldItem")
    return world and U.square(world)==tile and world or nil
end
return Physical
