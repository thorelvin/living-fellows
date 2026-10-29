-- SPDX-License-Identifier: MIT
-- Bed entry is walking, not construction of a new actor in an open area.
do
    local SC=SurvivorCompanion
    local oldU,oldList,oldManager=SC.GameplayUtil,SC.NativeList,SeatingManager
    local tiles,room,grid={},{},{}
    local function key(x,y) return x..":"..y end
    for x=8,13 do for y=8,12 do
        local sq={x=x,y=y,z=0,objects={},moving={},clear=false}
        function sq:getRoom() return room end
        function sq:getObjects() return self.objects end
        function sq:getMovingObjects() return self.moving end
        tiles[key(x,y)]=sq
    end end
    local function half(x,gx)
        local sprite={gx=gx}
        function sprite:getSpriteGrid() return grid end
        local bed={square=tiles[key(x,10)]}
        function bed:getSquare() return self.square end
        function bed:getSprite() return sprite end
        bed.square.objects[1]=bed
        return bed
    end
    local bed=half(10,0) half(11,1)
    function grid:getSpriteGridPosX(sprite) return sprite.gx end
    function grid:getSpriteGridPosY() return 0 end
    SeatingManager={getInstance=function() return {getFacingDirection=function() return "E" end} end}
    SC.NativeList={size=function(list)return #list end,get=function(list,i)return list[i+1]end}
    local entry=tiles[key(10,9)] entry.clear=true
    local actor={square=entry,x=10.5,y=9.5,z=0}
    SC.GameplayUtil={
        call=function(object,method,...)
            local fn=object and object[method]
            if type(fn)~="function" then return nil,false end
            local ok,value=pcall(fn,object,...) return value,ok
        end,
        squareOf=function(object)return object.square end,
        position=function(object)return object.x,object.y,object.z end,
        gridSquare=function(x,y)return tiles[key(x,y)]end,
        squareOccupyingObject=function(sq)return not sq.clear and bed or nil end,
        isClearActorSpawnSquare=function(sq)
            return false,sq==entry and (sq.failure or "unsafe_to_spawn") or "furniture_occupied"
        end,
    }
    local normalized,point=SC.BedGeometry.entry(bed,actor)
    assert(normalized==bed and point and math.floor(point.y)==9,
        "a clear bed entry in a cramped bedroom must not require eight connected spawn tiles")
    entry.moving={actor}
    assert(SC.BedGeometry.entry(bed,actor)==bed,"the actor may use its own clear entry tile")
    entry.moving={{}}
    assert(SC.BedGeometry.entry(bed,actor)==nil,"a different actor still blocks the bed entry")
    entry.moving={} entry.failure="missing_floor"
    assert(SC.BedGeometry.entry(bed,actor)==nil,"missing floor never becomes a bed entry")
    entry.failure="solid"
    assert(SC.BedGeometry.entry(bed,actor)==nil,"solid tiles never become a bed entry")
    SC.GameplayUtil,SC.NativeList,SeatingManager=oldU,oldList,oldManager
    print("TIGHT_BED_GEOMETRY_PASS checks=5")
end
