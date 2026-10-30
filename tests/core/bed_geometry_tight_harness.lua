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

do
    local SC = SurvivorCompanion
    local previousU, previousList, previousManager = SC.GameplayUtil, SC.NativeList, SeatingManager
    local checks = 0
    local function check(value, message) checks = checks + 1 assert(value, message) end
    for _, facing in ipairs({ "N", "S", "E", "W" }) do
        local vertical = facing == "N" or facing == "S"
        local tiles, room, grid = {}, {}, {}
        local width, height = vertical and 1 or 2, vertical and 2 or 1
        for x = 1, 8 do for y = 1, 8 do
            local tile = { x=x, y=y, z=1, objects={} }
            function tile:getRoom() return room end
            function tile:getObjects() return self.objects end
            function tile:getMovingObjects() return self.moving or {} end
            tiles[x .. ":" .. y] = tile
        end end
        function grid:getWidth() return width end
        function grid:getHeight() return height end
        function grid:getSpriteGridPosX(sprite) return sprite.gx end
        function grid:getSpriteGridPosY(sprite) return sprite.gy end
        local parts = {}
        for gy = 0, height - 1 do for gx = 0, width - 1 do
            local sprite = { gx=gx, gy=gy }
            function sprite:getSpriteGrid() return grid end
            local props = { get=function(_, name) return name == "Facing" and facing
                or name == "BedType" and "goodBed" or name == "CustomName" and "Hospital Bed" or nil end }
            function sprite:getProperties() return props end
            local bed = { x=4+gx, y=4+gy, z=1, square=tiles[(4+gx) .. ":" .. (4+gy)] }
            function bed:getSquare() return self.square end
            function bed:getSprite() return sprite end
            bed.square.objects[1] = bed
            parts[#parts+1] = bed
        end end
        local nativeFacing = vertical and "W" or "N"
        SeatingManager = { getInstance=function() return {
            getFacingDirection=function() return nativeFacing end,
        } end }
        SC.NativeList = { size=function(list) return #list end, get=function(list,i) return list[i+1] end }
        SC.GameplayUtil = {
            call=function(object,method,...)
                local fn=object and object[method]
                if type(fn)~="function" then return nil,false end
                local okay,value=pcall(fn,object,...) return value,okay
            end,
            squareOf=function(object) return object.square end,
            position=function(object) return object.x,object.y,object.z end,
            gridSquare=function(x,y) return tiles[x .. ":" .. y] end,
            squareOccupyingObject=function(tile) return tile.objects[1] end,
            isClearActorSpawnSquare=function(tile) return tile and #tile.objects==0 and not tile.blocked end,
        }
        local first, entry = SC.BedGeometry.entry(parts[1], nil)
        local second, other = SC.BedGeometry.entry(parts[2], nil)
        check(first and first==second and entry and other and entry.facing==facing
            and entry.correctedFacing==true, "hospital orientation " .. facing .. " normalizes either half")
        check(#SC.BedGeometry.segments(parts[1])==2, "physical halves share one claim")
        local character = { x=entry.x, y=entry.y, z=entry.z }
        function character:setVariable(name,value) self[name]=value end
        function character:faceLocationF(x,y) self.aimX,self.aimY=x,y end
        function character:setTargetAndCurrentDirection(x,y)
            self.renderX,self.renderY=x,y
        end
        local action = { character=character, bed=first, start=function(self)
            self.startedFacingX,self.startedFacingY=self.character.renderX,self.character.renderY
            self:setWhileSittingDirection()
        end }
        SC.BedGeometry.configureEntryAction(action,entry)
        action:setBeforeSitDirection()
        check(character.OnBedDirection==entry.entryKind, "entry action uses the selected side")
        action:setWhileSittingDirection()
        local dx,dy=character.renderX,character.renderY
        check((facing=="N" and dy<0 or facing=="S" and dy>0
            or facing=="E" and dx>0 or facing=="W" and dx<0), "sleep pose follows the verified mattress")
        character.renderX,character.renderY=-dy,dx
        action:start()
        check(action.startedFacingX==dx and action.startedFacingY==dy,
            "the rendered body faces along the bed before OnBed locks turning")
        local ordinary={character=character,bed=first,start=function(self)
            self.startedFacingX,self.startedFacingY=self.character.renderX,self.character.renderY
        end}
        SC.BedGeometry.configureEntryAction(ordinary,{facing=facing,correctedFacing=false})
        character.renderX,character.renderY=-dy,dx
        ordinary:start()
        check(ordinary.startedFacingX==dx and ordinary.startedFacingY==dy,
            "ordinary bed metadata also settles the render angle before native entry")
        check(nativeFacing==(vertical and "W" or "N"), "native/global facing remains unchanged")
        local hx,hy=first.x,first.y
        if facing=="N" then hy=hy+1 elseif facing=="S" then hy=hy-1
        elseif facing=="W" then hx=hx+1 else hx=hx-1 end
        local boundary=tiles[hx .. ":" .. hy]
        boundary.getRoom=function() return nil end
        local normalized,safeEntry=SC.BedGeometry.entry(parts[1],nil)
        check(normalized and safeEntry and safeEntry.entryKind:find("Foot",1,true),
            "an upstairs head boundary requires a foot-side native clip")
        for _=1,3 do
            if not safeEntry then break end
            tiles[math.floor(safeEntry.x) .. ":" .. math.floor(safeEntry.y)].blocked=true
            normalized,safeEntry=SC.BedGeometry.entry(parts[1],nil)
        end
        check(normalized==nil,"blocked foot entries never fall back to a clip beyond the upstairs floor")
        boundary.getRoom=function() return room end
        for _,tile in pairs(tiles) do tile.blocked=nil end
        local props = { BedType="averageBed", CustomName="Couch" }
        local cushion = { getProperties=function() return {get=function(_,key) return props[key] end} end }
        SeatingManager.getInstance=function() return {getTilePositionCount=function() return 2 end} end
        check(SC.BedGeometry.sleepPriority(cushion)==3,"native numeric seat count permits a backup couch")
        local seated={isSittingOnFurniture=function() return true end}
        cushion.square=tiles["2:2"]
        cushion.square.moving={seated}
        check(SC.BedGeometry.occupant(cushion,{})==seated,
            "a seated or sleeping couch occupant protects the complete couch")
        cushion.square.moving={}
        props.CustomName="Sleeping Bag"
        check(SC.BedGeometry.sleepPriority(cushion)==2,"deployed sleeping bag has second preference")
        props.CustomName="Chair"
        check(SC.BedGeometry.sleepPriority(cushion)==nil,"a native chair remains a chair")
        SeatingManager.getInstance=function() return {getFacingDirection=function() return nativeFacing end} end
        parts[2].square.objects={}
        check(SC.BedGeometry.entry(parts[1],nil)==nil, "a missing physical half is still rejected")
    end
    SC.GameplayUtil,SC.NativeList,SeatingManager=previousU,previousList,previousManager
    SC_TEST_REPORT = (SC_TEST_REPORT or "") .. "; HOSPITAL_BED_AXIS_PASS checks=" .. checks
    print("HOSPITAL_BED_AXIS_PASS checks=" .. checks)
end
