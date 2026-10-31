-- SPDX-License-Identifier: MIT
-- Disposable clone only. Native Rosewood station doors, stairs and beds.
-- Observer/fixture placement is setup; measured travel uses normal navigation.
-- Local mattress clearance, if needed, belongs to production bed-exit recovery.
local Probe = {}
local function call(object, name, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[name](object, ...) end, ...)
    if ok then return value end
end
local function at(object)
    return tostring(call(object, "getX")) .. "," .. tostring(call(object, "getY"))
        .. "," .. tostring(call(object, "getZ"))
end
local function screenshot(H, suffix)
    pcall(function() getCore():TakeFullScreenshot(H.config.run_id .. "-firestation-" .. suffix) end)
end
local function addZone(SC, kind, x1, y1, x2, y2, z, name)
    local okay, reason = SC.BaseLife.beginZone(kind, { x = x1, y = y1, z = z })
    if not okay then return false, reason end
    return SC.BaseLife.finishZone({ x = x2, y = y2, z = z }, name)
end
local function safe(SC, square)
    return square and SC.GameplayUtil.isSquareFree(square)
        and call(square, "TreatAsSolidFloor") == true
        and call(square, "isSafeToSpawn") ~= false
        and not SC.Topology.squareHasStairs(square)
end
local function walkoutGoal(SC, actor)
    local U, choices = SC.GameplayUtil, {}
    local x, y, z = U.position(actor)
    local current = U.gridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    local room = call(current, "getRoom")
    for dx = -3, 3 do for dy = -3, 3 do
        local target = U.gridSquare(math.floor(x) + dx, math.floor(y) + dy, math.floor(z or 0))
        if target and call(target, "getRoom") == room and safe(SC, target)
            and U.isClearActorSpawnSquare(target) and U.distanceSq(actor, target) >= 2.25 then
            choices[#choices + 1] = target
        end
    end end
    table.sort(choices, function(a, b) return U.distanceSq(actor, a) < U.distanceSq(actor, b) end)
    return choices[1]
end
local function traceExit(SC, actor, bed, label)
    local targets, touching, why = {}, false, "no-bed"
    if bed then targets, touching, why = SC.BedGeometry.exitTargets(bed, actor) end
    local left, reason = SC.NativeActions.leaveSeating(actor)
    print("SC_REAL_SANDBOX|FIRESTATION_EXIT|" .. label .. " at=" .. at(actor)
        .. " bed=" .. at(call(bed, "getSquare")) .. " onbed=" .. tostring(actor:isOnBed())
        .. " context=" .. tostring(call(actor, "getCurrentActionContextStateName"))
        .. " owner=" .. tostring(call(actor, "getCompanionMovementOwner"))
        .. " touching=" .. tostring(touching) .. " targets=" .. #targets
        .. " geometry=" .. tostring(why) .. " left=" .. tostring(left) .. " reason=" .. tostring(reason))
    local U = SC.GameplayUtil
    local square = U.gridSquare(math.floor(actor:getX()), math.floor(actor:getY()), math.floor(actor:getZ()))
    U.squareObjects(square, function(object)
        local sprite = call(object, "getSprite")
        local props = call(sprite, "getProperties")
        print("SC_REAL_SANDBOX|FIRESTATION_EXIT_OBJECT|" .. label
            .. " sprite=" .. tostring(call(sprite, "getName"))
            .. " custom=" .. tostring(call(props, "get", "CustomName"))
            .. " bedtype=" .. tostring(call(props, "get", "BedType")))
    end, 12)
end
local function catalogueStep(H, SC, f, result)
    if not f.catalogue then
        local sprites = ArrayList.new(getSpriteManager(nil):getNamedMap():values())
        f.catalogue = { sprites = sprites, scanned = 0, beds = 0, missed = 0, groups = {} }
    end
    local c, kind = f.catalogue, SC.Downtime._furnitureForTests()
    for _ = 1, 128 do
        if c.scanned >= c.sprites:size() then
            result(c.missed == 0 and "PASS" or "FAIL", "bed_catalogue_classification",
                "native sprites=" .. c.scanned .. " semantic bed tiles=" .. c.beds
                    .. " not classified=" .. c.missed)
            return true
        end
        local sprite = c.sprites:get(c.scanned)
        c.scanned = c.scanned + 1
        local props = call(sprite, "getProperties")
        local custom, group = call(props, "get", "CustomName"), call(props, "get", "GroupName")
        local bedType = call(props, "get", "BedType")
        local text = string.lower(tostring(group or "") .. " " .. tostring(custom or ""))
        if bedType and (text:find("bed", 1, true) or text:find("bunk", 1, true)
            or text:find("mattress", 1, true) or text:find("sleeping", 1, true)
            or text:find("cot", 1, true) or text:find("stretcher", 1, true)
            or text:find("couch", 1, true) or text:find("sofa", 1, true)) then
            local name = sprite:getName()
            local object = IsoObject.new(f.ground[1], name, tostring(custom or group or ""))
            local classification = kind(object)
            local grid = call(sprite, "getSpriteGrid")
            c.beds = c.beds + 1
            if classification ~= "rest_bed" and not text:find("couch", 1, true)
                and not text:find("sofa", 1, true) then c.missed = c.missed + 1 end
            print("SC_REAL_SANDBOX|BED_CATALOGUE|sprite=" .. name .. " names=" .. text
                .. " bedType=" .. tostring(bedType) .. " kind=" .. tostring(classification)
                .. " grid=" .. tostring(call(grid, "getWidth")) .. "x" .. tostring(call(grid, "getHeight"))
                .. " facing=" .. tostring(call(SeatingManager.getInstance(), "getFacingDirection", object)))
        end
    end
    return false
end
local function prepareBackup(SC, f, kind)
    -- Only the disposable fixture changes: remove its bed pieces after the
    -- original-bedroom trials so an available normal bed cannot mask backup use.
    for _, object in ipairs(f.backupPieces or f.bedPieces) do
        local square = object:getSquare()
        if object:getObjectIndex() ~= -1 then square:RemoveTileObject(object) end
    end
    f.backupPieces = {}
    local target = SC.GameplayUtil.copyShallow(f.bedrooms[1])
    -- A removed IsoObject can lose its square; retain the original bed location.
    local x, y = f.originalBedX, f.originalBedY
    local sprite = getSprite(kind == "bag" and "camping_02_0"
        or kind == "bunk" and "furniture_bedding_01_84" or "furniture_seating_indoor_01_16")
    local grid = sprite:getSpriteGrid()
    for gy = 0, grid:getHeight() - 1 do for gx = 0, grid:getWidth() - 1 do
        local square = SC.GameplayUtil.gridSquare(x + gx, y + gy, 1)
        local piece = IsoObject.new(square, grid:getSprite(gx,gy):getName(),
            kind == "bag" and "Sleeping Bag" or kind == "bunk" and "Bunk Beds" or "Couch")
        square:AddTileObject(piece)
        f.backupPieces[#f.backupPieces+1] = piece
    end end
    target.bed, target.surface = f.backupPieces[1], kind
    f.bedrooms[f.index] = target
end
local beginTrial
local function beginGroup(H, SC, f, current, check, result, setPhase)
    f.groupRoom = (f.groupRoom or 0) + 1
    local target = f.bedrooms[f.groupRoom]
    if not target then
        -- Exercise the same entry-facing change on bags and an upstairs bunk,
        -- plus the couch path which must remain native seated sleep.
        f.index=2
        beginTrial(H,SC,f,current,check,result,setPhase)
        return
    end
    f.group, f.target = {}, target
    local base, old = SC.BaseLife.active(), {}
    for _, zone in ipairs(base.zones) do if zone.kind == "rest" then old[#old+1] = zone.id end end
    for _, id in ipairs(old) do SC.BaseLife.removeZone(id) end
    local okay, reason = addZone(SC, "rest", target.x1, target.y1, target.x2, target.y2, 1,
        "Three-person bedroom " .. f.groupRoom)
    if not check("firestation_group_zone_" .. f.groupRoom, okay == true, tostring(reason)) then
        setPhase("finish", current) return
    end
    for _, door in ipairs(f.doors) do
        call(door,"setLocked",false) call(door,"setLockedByKey",false)
        if call(door,"IsOpen") == true then call(door,"ToggleDoorSilent") end
    end
    local starts = {}
    for _, square in ipairs(f.ground) do if safe(SC,square) then starts[#starts+1]=square end end
    table.sort(starts,function(a,b)
        local ax,ay,bx,by=a:getX()-target.x1,a:getY()-target.y1,b:getX()-target.x1,b:getY()-target.y1
        return ax*ax+ay*ay > bx*bx+by*by
    end)
    for index=1,3 do
        local square=starts[index]
        local ticket=square and select(1,SC.Actor.beginSpawn(square,{recruited=true,
            identity={forename="Sleeper",surname="Group" .. f.groupRoom .. "_" .. index,
                gender=index==2 and "man" or "woman",outfit="Generic01"}}))
        if not check("firestation_group_ticket_" .. f.groupRoom .. "_" .. index,ticket~=nil,at(square)) then
            setPhase("finish",current) return
        end
        f.group[index]={ticket=ticket}
    end
    f.groupStartedAt, f.groupTraceAt = current, current
    setPhase("firestation_rest_group_spawn",current)
end
local function groupStep(H,SC,f,current,check,result,setPhase)
    local U=SC.GameplayUtil
    if H.phase=="firestation_rest_group_spawn" then
        local ready=true
        for index,row in ipairs(f.group) do
            if not row.actor then
                local actor,reason=SC.Actor.pollSpawn(row.ticket)
                if actor then
                    row.actor=actor
                    row.health=actor:getBodyDamage():getOverallBodyHealth()
                    SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
                    SC.BaseLife.setDuty(SC.Registry.idOf(actor),false)
                    actor:getStats():set(CharacterStat.FATIGUE,1)
                    actor:getStats():set(CharacterStat.HUNGER,0)
                    actor:getStats():set(CharacterStat.THIRST,0)
                elseif reason~="spawn_pending" or current-H.phaseStartedAt>20000 then
                    result("FAIL","firestation_group_spawn_" .. index,tostring(reason))
                    setPhase("finish",current) return
                else ready=false end
            end
        end
        if ready then setPhase("firestation_rest_group_walk",current) end
        return
    end
    if H.phase=="firestation_rest_group_wake" then
        local standing=true
        local trace = current >= (f.exitTraceAt or 0)
        for index,row in ipairs(f.group) do
            SC.Downtime.cancel(row.actor,"group_trial_complete")
            local touching = false
            if row.bed then
                local _, overlaps = SC.BedGeometry.exitTargets(row.bed, row.actor)
                touching = overlaps
            end
            if row.actor:isOnBed() or row.actor:isAsleep()
                or SC.NativeActions.seatingStatus(row.actor)~="standing"
                or touching == true then standing=false end
            if trace then traceExit(SC, row.actor, row.bed, "room=" .. f.groupRoom .. " actor=" .. index) end
        end
        if trace then f.exitTraceAt = current + 5000 end
        if standing then
            for index,row in ipairs(f.group) do
                check("firestation_group_remove_" .. f.groupRoom .. "_" .. index,
                    SC.Actor.remove(row.actor)==true,"awake and standing before removal")
            end
            beginGroup(H,SC,f,current,check,result,setPhase)
        elseif current-H.phaseStartedAt>25000 then
            screenshot(H, "blocked-exit-room-" .. f.groupRoom)
            result("FAIL","firestation_group_wake","group did not leave beds normally")
            setPhase("finish",current)
        end
        return
    end
    local allAsleep, records, beds = true, {}, {}
    for index,row in ipairs(f.group) do
        local actor=row.actor
        local okay,reason=SC.Downtime.update(actor,H.player,{snapshot={immediateCount=0,
            threatCount=0,player={danger=0},indoors=true}},"rest_bed")
        row.reason=reason
        records[#records+1]={actor=actor,runtime={snapshot={threatCount=0,immediateCount=0}}}
        local native=SC.NativeActions._bedRestForTests(actor) or {}
        if actor:isAsleep() then
            row.sleptAt=row.sleptAt or current
            row.bed = native.pose == "bed" and native.object or nil
            if native.object then beds[native.object]=true end
        else allAsleep=false end
        if current>=f.groupTraceAt then
            print("SC_REAL_SANDBOX|FIRESTATION_GROUP|room=" .. f.groupRoom .. " actor=" .. index
                .. " at=" .. at(actor) .. " state=" .. tostring(reason) .. " asleep=" .. tostring(actor:isAsleep())
                .. " facing=" .. tostring(native.bedEntry and native.bedEntry.facing)
                .. " entry=" .. tostring(actor:getVariableString("OnBedDirection"))
                .. " forward=" .. tostring(call(actor,"getDirectionAngleRadians"))
                .. " anim=" .. tostring(call(actor,"getAnimAngleRadians"))
                .. " aligned=" .. tostring(native.modelAligned) .. " failure=" .. tostring(native.failure))
        end
    end
    if current>=f.groupTraceAt then
        f.groupTraceAt=current+3000
        local _,campPulse=SC.Banter._socialForTests()
        campPulse(H.player,records,current)
    end
    if allAsleep then
        f.groupAllAsleepAt=f.groupAllAsleepAt or current
        if not f.groupPhotoReady then
            f.groupPhotoReady=true
            for _,square in ipairs(f.rooms[f.target.room].tiles) do
                if safe(SC,square) and U.squareOccupyingObject(square)==nil then
                    H.player:teleportTo(square:getX()+0.5,square:getY()+0.5,1) break
                end
            end
            -- Observation only: use the stock zoom control in this disposable
            -- cache so all three mattress poses are readable in the evidence.
            if (tonumber(call(getCore(),"getZoom",0)) or 1)>0.75 then
                for _=1,4 do call(getCore(),"doZoomScroll",0,-1) end
            end
        end
        if current-f.groupAllAsleepAt<15000 then return end
        local count=0 for _ in pairs(beds) do count=count+1 end
        check("firestation_group_distinct_beds_" .. f.groupRoom,count==3,"beds=" .. count)
        for index,row in ipairs(f.group) do
            local actor=row.actor
            local native=SC.NativeActions._bedRestForTests(actor) or {}
            local angle=call(actor,"getAnimAngleRadians")
            local facing=native.bedEntry and native.bedEntry.facing
            local vectors={N={0,-1},S={0,1},E={1,0},W={-1,0}}
            local vector=vectors[facing]
            local dot=angle and vector and math.cos(angle)*vector[1]+math.sin(angle)*vector[2]
            check("firestation_group_sleep_" .. f.groupRoom .. "_" .. index,
                actor:isOnBed() and actor:isAsleep() and actor:getZ()>=1
                    and actor:getBodyDamage():getOverallBodyHealth()>=row.health-0.01,
                "walk=" .. math.floor((row.sleptAt-f.groupStartedAt)/1000) .. "s at=" .. at(actor))
            check("firestation_group_axis_" .. f.groupRoom .. "_" .. index,
                dot and dot>0.98,"expected=" .. tostring(facing) .. " anim=" .. tostring(angle)
                    .. " dot=" .. tostring(dot))
            check("firestation_group_recovery_" .. f.groupRoom .. "_" .. index,
                native.modelAligned==true and U.characterStatValue(actor,"FATIGUE",1)<0.999,
                "modelAligned=" .. tostring(native.modelAligned)
                    .. " fatigue=" .. tostring(U.characterStatValue(actor,"FATIGUE",1)))
        end
        screenshot(H,"three-sleepers-room-" .. f.groupRoom)
        for _,row in ipairs(f.group) do SC.Downtime.cancel(row.actor,"group_sleep_verified") end
        f.groupAllAsleepAt,f.groupPhotoReady=nil,nil
        setPhase("firestation_rest_group_wake",current)
    elseif current-f.groupStartedAt>210000 then
        screenshot(H,"group-timeout-" .. f.groupRoom)
        result("FAIL","firestation_group_sleep","group timeout")
        setPhase("finish",current)
    end
    if not allAsleep then f.groupAllAsleepAt=nil end
end
beginTrial = function(H, SC, f, current, check, result, setPhase)
    f.index = f.index + 1
    if f.index == 3 then prepareBackup(SC, f, "bag") end
    if f.index == 4 then prepareBackup(SC, f, "couch") end
    if f.index == 5 then prepareBackup(SC, f, "bunk") end
    local target = f.bedrooms[f.index]
    if target == nil then
        check("firestation_all_bedrooms", f.index == 6,
            "completed selected trial range " .. tostring(f.firstTrial) .. "-5")
        setPhase("finish", current) return
    end
    f.target, f.opened, f.doorStates = target, {}, {}
    local base = SC.BaseLife.active()
    local old = {}
    for _, zone in ipairs(base.zones) do if zone.kind == "rest" then old[#old + 1] = zone.id end end
    for _, id in ipairs(old) do SC.BaseLife.removeZone(id) end
    local okay, zone = addZone(SC, "rest", target.x1, target.y1, target.x2, target.y2, 1,
        "Firestation bedroom " .. f.index)
    if not check("firestation_rest_zone_" .. f.index, okay == true, tostring(zone)) then
        setPhase("finish", current) return
    end
    -- All ordinary station doors start closed and usable in this route test.
    local closed = 0
    for _, door in ipairs(f.doors) do
        call(door, "setLocked", false) call(door, "setLockedByKey", false)
        if call(door, "IsOpen") == true then call(door, "ToggleDoorSilent") end
        f.doorStates[door] = call(door, "IsOpen") == true
        if not f.doorStates[door] then closed = closed + 1 end
    end
    if not check("firestation_closed_doors_" .. f.index, closed == #f.doors,
        "closed=" .. closed .. "/" .. #f.doors) then setPhase("finish",current) return end
    local best, distance
    for _, square in ipairs(f.ground) do
        local dx, dy = square:getX() - target.x1, square:getY() - target.y1
        local value = dx * dx + dy * dy
        if (not distance or value > distance) and safe(SC, square) then best, distance = square, value end
    end
    if not check("firestation_start_" .. f.index, best ~= nil, at(best)) then
        setPhase("finish", current) return
    end
    f.start = best
    f.ticket = select(1, SC.Actor.beginSpawn(best, { recruited = true,
        identity = { forename = "Rest", surname = "Station" .. f.index,
            gender = "woman", outfit = "Generic01" } }))
    if not check("firestation_spawn_ticket_" .. f.index, f.ticket ~= nil, at(best)) then
        setPhase("finish", current) return
    end
    result("PASS", "firestation_trial_fixture_" .. f.index,
        "start=" .. at(best) .. " target_room=" .. target.name
            .. " bed=" .. at(target.bed:getSquare()) .. " doors_closed=" .. #f.doors)
    setPhase("firestation_rest_spawn", current)
end
function Probe.step(H, current, check, result, setPhase)
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    if H.phase == "firestation_rest_setup" then
        if current - H.phaseStartedAt < 3000 then return end
        SC.Scheduler.unregister("decision")
        if H.config.firestation_rest_group=="true" and SC.UI then SC.UI.close() end
        H.firestationRest = { bedrooms = {}, roomBeds = {}, doors = {}, ground = {},
            seenDoors = {}, seenBeds = {}, bedPieces = {}, rooms = {}, upperTiles = 0, rawBeds = 0,
            firstTrial = tonumber(H.config.firestation_rest_first_trial) or 1,
            groupRoom = math.max(0, (tonumber(H.config.firestation_rest_first_trial) or 1) - 1),
            index = (tonumber(H.config.firestation_rest_first_trial) or 1) - 1 }
        H.player:teleportTo(8140, 11738, 0)
        setPhase("firestation_rest_load", current) return
    end
    local f = H.firestationRest
    if H.phase == "firestation_rest_load" then
        local building
        for dx = -6, 6 do for dy = -6, 6 do
            local square = U.gridSquare(8140 + dx, 11738 + dy, 0)
            building = building or call(square, "getBuilding")
        end end
        local definition = call(building, "getDef")
        if definition == nil then
            if current - H.phaseStartedAt > 45000 then
                result("FAIL", "firestation_loaded", "Rosewood building not streamed at 8140,11738")
                setPhase("finish", current)
            end
            return
        end
        f.building = building
        f.x1, f.y1 = definition:getX(), definition:getY()
        f.x2, f.y2 = definition:getX2(), definition:getY2()
        f.x, f.y, f.z = f.x1 - 1, f.y1 - 1, 0
        result("PASS", "firestation_loaded", "native bounds=" .. f.x1 .. "," .. f.y1
            .. "-" .. f.x2 .. "," .. f.y2)
        setPhase("firestation_rest_survey", current) return
    end
    if H.phase == "firestation_rest_survey" then
        local kind = SC.Downtime._furnitureForTests()
        for _ = 1, 96 do
            local square = U.gridSquare(f.x, f.y, f.z)
            if square then
                local room = call(square, "getRoom")
                if f.z == 1 and room then
                    f.upperTiles = f.upperTiles + 1
                    local row = f.rooms[room]
                    if not row then
                        local def = call(room, "getRoomDef")
                        row = { room = room, name = tostring(call(def, "getName") or room),
                            x1 = f.x, x2 = f.x, y1 = f.y, y2 = f.y, tiles = {} }
                        f.rooms[room] = row
                    end
                    row.x1, row.x2 = math.min(row.x1, f.x), math.max(row.x2, f.x)
                    row.y1, row.y2 = math.min(row.y1, f.y), math.max(row.y2, f.y)
                    row.tiles[#row.tiles + 1] = square
                end
                if call(square, "getBuilding") == f.building and f.z == 0 and safe(SC, square) then
                    f.ground[#f.ground + 1] = square
                end
                U.squareObjects(square, function(object)
                    if (U.instanceOf(object, "IsoDoor") or U.instanceOf(object, "IsoThumpable")
                        and call(object, "isDoor") == true) and not f.seenDoors[object] then
                        f.seenDoors[object] = true f.doors[#f.doors + 1] = object
                    end
                    if f.z == 1 and call(square, "getBuilding") == f.building
                        and kind(object) == "rest_bed" then
                        f.rawBeds = f.rawBeds + 1
                        f.bedPieces[#f.bedPieces+1] = object
                        local normalized, entry, entryReason = SC.BedGeometry.entry(object, H.player)
                        local sprite = object:getSprite()
                        local grid = sprite:getSpriteGrid()
                        local neighbors = {}
                        for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
                            local other = U.gridSquare(f.x + d[1], f.y + d[2], 1)
                            U.squareObjects(other, function(piece)
                                if kind(piece) == "rest_bed" then
                                    local ps = piece:getSprite()
                                    neighbors[#neighbors + 1] = at(other) .. ":" .. ps:getName()
                                        .. ":samegrid=" .. tostring(ps:getSpriteGrid() == grid)
                                end
                            end, 64)
                        end
                        print("SC_REAL_SANDBOX|FIRESTATION_BED|at=" .. at(square)
                            .. " sprite=" .. sprite:getName()
                            .. " facing=" .. tostring(call(SeatingManager.getInstance(), "getFacingDirection", object))
                            .. " tileFacing=" .. tostring(call(sprite:getProperties(), "get", "Facing"))
                            .. " grid=" .. grid:getWidth() .. "x" .. grid:getHeight()
                            .. " gridpos=" .. grid:getSpriteGridPosX(sprite) .. "," .. grid:getSpriteGridPosY(sprite)
                            .. " neighbors=" .. table.concat(neighbors, ";")
                            .. " entry=" .. tostring(entryReason))
                        normalized = normalized or object
                        if normalized and not f.seenBeds[normalized] then
                            f.seenBeds[normalized] = true
                            local room = call(square, "getRoom")
                            if room and not f.roomBeds[room] then
                                local def = call(room, "getRoomDef")
                                local bedSquare = normalized:getSquare()
                                local row = { room = room, bed = normalized,
                                    name = tostring(call(def, "getName") or room),
                                    x1 = bedSquare:getX(), x2 = bedSquare:getX(),
                                    y1 = bedSquare:getY(), y2 = bedSquare:getY() }
                                f.roomBeds[room] = row f.bedrooms[#f.bedrooms + 1] = row
                            end
                        end
                    end
                end, 64)
                local row = f.roomBeds[call(square, "getRoom")]
                if row then
                    row.x1, row.x2 = math.min(row.x1, f.x), math.max(row.x2, f.x)
                    row.y1, row.y2 = math.min(row.y1, f.y), math.max(row.y2, f.y)
                end
            end
            f.x = f.x + 1
            if f.x > f.x2 + 1 then f.x, f.y = f.x1 - 1, f.y + 1 end
            if f.y > f.y2 + 1 then f.x, f.y, f.z = f.x1 - 1, f.y1 - 1, f.z + 1 end
            if f.z > 1 then break end
        end
        if f.z <= 1 then return end
        local roomOrder = {}
        for _, room in pairs(f.rooms) do
            print("SC_REAL_SANDBOX|FIRESTATION_ROOM|name=" .. room.name .. " bounds="
                .. room.x1 .. "," .. room.y1 .. "-" .. room.x2 .. "," .. room.y2
                .. " tiles=" .. #room.tiles)
            if #room.tiles >= 9 then roomOrder[#roomOrder + 1] = room end
        end
        table.sort(roomOrder, function(a, b)
            if a.x1 ~= b.x1 then return a.x1 < b.x1 end return a.y1 < b.y1
        end)
        screenshot(H, "initial-fixture")
        if not check("firestation_fixture", #f.bedrooms >= 2 and #f.ground > 0,
            "bedrooms=" .. #f.bedrooms .. " doors=" .. #f.doors .. " ground=" .. #f.ground
                .. " upper=" .. f.upperTiles .. " raw_bed_segments=" .. f.rawBeds) then
            setPhase("finish", current) return
        end
        table.sort(f.bedrooms, function(a, b)
            if a.x1 ~= b.x1 then return a.x1 < b.x1 end return a.y1 < b.y1
        end)
        f.originalBedX, f.originalBedY = f.bedrooms[1].bed:getSquare():getX(),
            f.bedrooms[1].bed:getSquare():getY()
        -- The old camp and its original companions exist only in the clone.
        -- Replace zone geometry in this fixture, leaving native walls intact.
        local base = SC.BaseLife.active()
        base.zones = {}
        for z = 0, 1 do
            local okay, zone = addZone(SC, "area", f.x1 - 1, f.y1 - 1,
                f.x2 + 1, f.y2 + 1, z, "Rosewood firestation test floor " .. z)
            if not check("firestation_camp_floor_" .. z, okay == true, tostring(zone)) then
                setPhase("finish", current) return
            end
        end
        -- Remove only cloned-world zombies inside the controlled station scene.
        local zombies = getCell():getZombieList()
        for index = zombies:size() - 1, 0, -1 do
            local zombie = zombies:get(index)
            if zombie:getX() >= f.x1 - 8 and zombie:getX() <= f.x2 + 8
                and zombie:getY() >= f.y1 - 8 and zombie:getY() <= f.y2 + 8 then
                zombie:removeFromWorld() zombie:removeFromSquare()
            end
        end
        screenshot(H, "layout")
        setPhase("firestation_rest_catalogue", current) return
    end
    if H.phase == "firestation_rest_catalogue" then
        if catalogueStep(H, SC, f, result) then
            if H.config.firestation_rest_group=="true" then
                beginGroup(H,SC,f,current,check,result,setPhase)
            else beginTrial(H, SC, f, current, check, result, setPhase) end
        end
        return
    end
    if H.phase:find("firestation_rest_group_",1,true) then
        groupStep(H,SC,f,current,check,result,setPhase) return
    end
    if H.phase == "firestation_rest_spawn" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 20000 then
                result("FAIL", "firestation_spawn_" .. f.index, tostring(reason))
                setPhase("finish", current)
            end
            return
        end
        f.actor = actor
        f.healthStarted = actor:getBodyDamage():getOverallBodyHealth()
        local id = SC.Registry.idOf(actor)
        SC.Commands.issue(id, "stay", nil, H.player)
        SC.BaseLife.setDuty(id, false)
        actor:getStats():set(CharacterStat.FATIGUE, 1)
        actor:getStats():set(CharacterStat.HUNGER, 0)
        actor:getStats():set(CharacterStat.THIRST, 0)
        f.startedAt, f.traceAt, f.upper, f.hadActivity = current, current, false, false
        setPhase("firestation_rest_walk", current) return
    end
    local actor = f.actor
    if H.phase == "firestation_rest_photo" then
        SC.Downtime.update(actor, H.player, { snapshot = { immediateCount = 0,
            threatCount = 0, player = { danger = 0 }, indoors = true } }, "rest_bed")
        if current - H.phaseStartedAt < 6000 then return end
        local rest = SC.Downtime.peek(actor)
        local native = SC.NativeActions._bedRestForTests(actor) or {}
        check("firestation_settled_sleep_" .. f.index, actor:isAsleep(),
            "after 6s at=" .. at(actor) .. " facing=" .. tostring(native.bedEntry and native.bedEntry.facing)
                .. " kind=" .. tostring(actor:getVariableString("OnBedDirection"))
                .. " pose=" .. tostring(native.pose) .. " bed=" .. at(f.target.bed:getSquare())
                .. " modelAligned=" .. tostring(native.modelAligned)
                .. " alignmentFailure=" .. tostring(native.alignmentFailure)
                .. " fatigue=" .. U.characterStatValue(actor,"FATIGUE",-1))
        if native.pose == "bed" then
            check("firestation_model_alignment_" .. f.index, native.modelAligned == true,
                tostring(native.alignmentFailure or "render-only mattress alignment verified"))
        end
        screenshot(H, "sleep-" .. tostring(f.target.surface or "bedroom") .. "-" .. f.index)
        f.wakeBed = native.pose == "bed" and native.object or nil
        SC.Downtime.cancel(actor, "firestation_sleep_verified")
        setPhase("firestation_rest_wake", current) return
    end
    if H.phase == "firestation_rest_wake" then
        SC.Downtime.cancel(actor, "firestation_trial_complete")
        local touching = false
        if f.wakeBed then
            local _, overlaps = SC.BedGeometry.exitTargets(f.wakeBed, actor)
            touching = overlaps
        end
        if not actor:isAsleep() and not actor:isOnBed()
            and SC.NativeActions.seatingStatus(actor) == "standing" and touching ~= true then
            check("firestation_wake_" .. f.index, true, "awake and standing off the bed")
            f.walkout = walkoutGoal(SC, actor)
            if not check("firestation_walkout_goal_" .. f.index, f.walkout ~= nil, at(f.walkout)) then
                setPhase("finish", current) return
            end
            screenshot(H, "clear-exit-" .. f.index)
            setPhase("firestation_rest_walkout", current)
        elseif current - H.phaseStartedAt > 25000 then
            traceExit(SC, actor, f.wakeBed, "trial=" .. f.index)
            screenshot(H, "blocked-exit-trial-" .. f.index)
            result("FAIL", "firestation_wake_" .. f.index, "did not finish leaving bed")
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "firestation_rest_walkout" then
        local accepted, reason = SC.Navigation.request(actor, f.walkout, "walk", {
            action = "firestation_bed_walkout", requireSameSquare = true,
            snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
                player = { danger = 0 } },
        })
        if U.sameSquare(actor, f.walkout) then
            check("firestation_walkout_" .. f.index, true, "normal walking resumed at=" .. at(actor))
            screenshot(H, "walkout-" .. f.index)
            if not check("firestation_remove_" .. f.index, SC.Actor.remove(actor) == true,
                "measured actor removed after walking clear") then
                setPhase("finish", current) return
            end
            f.actor = nil
            beginTrial(H, SC, f, current, check, result, setPhase)
        elseif current - H.phaseStartedAt > 25000 then
            result("FAIL", "firestation_walkout_" .. f.index,
                "could not walk clear after waking: " .. tostring(accepted) .. "/" .. tostring(reason))
            setPhase("finish", current)
        end
        return
    end
    if H.phase ~= "firestation_rest_walk" then return end
    f.upper = f.upper or actor:getZ() >= 1
    for _, door in ipairs(f.doors) do
        local open = call(door, "IsOpen") == true
        if open and f.doorStates[door] ~= true then f.opened[door] = true end
        f.doorStates[door] = open
    end
    local okay, reason = SC.Downtime.update(actor, H.player, { snapshot = {
        immediateCount = 0, threatCount = 0, player = { danger = 0 }, indoors = true,
    } }, "rest_bed")
    local rest = SC.Downtime.peek(actor)
    local activity = rest and rest.active
    if activity then f.hadActivity = true end
    if current >= f.traceAt then
        f.traceAt = current + 2000
        local nav = SC.Navigation.status(actor) or {}
        local native = SC.NativeActions._bedRestForTests(actor) or {}
        local doorCount = 0
        for _ in pairs(f.opened) do doorCount = doorCount + 1 end
        print("SC_REAL_SANDBOX|FIRESTATION_REST_TRACE|trial=" .. f.index
            .. " at=" .. at(actor) .. " state=" .. tostring(reason)
            .. " active=" .. tostring(activity and activity.kind)
            .. " target=" .. at(activity and U.squareOf(activity.object))
            .. " nav=" .. tostring(nav.pathReason) .. "/" .. tostring(nav.lastMovementReason)
            .. " blocker=" .. tostring(nav.blockerType) .. " doors=" .. doorCount
            .. " fatigue=" .. U.characterStatValue(actor, "FATIGUE", -1)
            .. " bedFailure=" .. tostring(native.failure))
    end
    if actor:isAsleep() then
        local doorCount, doorText = 0, {}
        for door in pairs(f.opened) do
            doorCount = doorCount + 1 doorText[#doorText + 1] = at(door:getSquare())
        end
        local supportedPose = f.target.surface == "couch" and actor:isSittingOnFurniture() or actor:isOnBed()
        check("firestation_sleep_" .. f.index, okay == true and supportedPose
            and f.upper and activity and activity.kind == "rest_bed"
            and actor:getBodyDamage():getOverallBodyHealth() >= f.healthStarted - 0.01
            and call(actor:getCurrentSquare(), "getRoom") == f.target.room,
            "walked=" .. math.floor((current - f.startedAt) / 1000) .. "s native asleep="
                .. tostring(actor:isAsleep()) .. " bed=" .. tostring(actor:isOnBed())
                .. " surface=" .. tostring(f.target.surface or "original hospital bed")
                .. " doors=" .. doorCount .. " opened=" .. table.concat(doorText, ";"))
        for _, square in ipairs(f.rooms[f.target.room].tiles) do
            if safe(SC,square) and U.squareOccupyingObject(square)==nil
                and U.distance(actor,square)>2 then
                H.player:teleportTo(square:getX()+0.5,square:getY()+0.5,1) break
            end
        end
        setPhase("firestation_rest_photo", current)
    elseif current - f.startedAt > (f.hadActivity and 180000 or 25000) then
        screenshot(H, "failed-bedroom-" .. f.index)
        result("FAIL", "firestation_sleep_" .. f.index, "timeout at=" .. at(actor)
            .. " reason=" .. tostring(reason) .. " upper=" .. tostring(f.upper))
        setPhase("finish", current)
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCFirestationRestProbe = Probe
return Probe
