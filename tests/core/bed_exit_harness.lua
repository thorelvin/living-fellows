-- SPDX-License-Identifier: MIT
-- Native-shaped two-tile beds, solid seams, real geometry and exit controller.
local SC, checks = SurvivorCompanion, 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "bed exit " .. checks .. ": " .. message)
end
local function list(values)
    return { size = function() return #values end, get = function(_, index) return values[index + 1] end }
end
local function scene()
    local tiles, room, chunk, grid = {}, {}, {}, {}
    local function key(x, y) return x .. ":" .. y end
    local cell = { reads = 0 }
    function cell:getGridSquare(x, y, z)
        self.reads = self.reads + 1
        return z == 1 and tiles[key(x, y)] or nil
    end
    getCell = function() return cell end
    for x = 8, 14 do for y = 8, 14 do
        local tile = { x = x, y = y, z = 1, room = room, floor = true, blocked = true,
            objects = {}, moving = {}, walls = {}, windows = {}, doors = {}, fences = {} }
        function tile:getX() return self.x end
        function tile:getY() return self.y end
        function tile:getZ() return self.z end
        function tile:getRoom() return self.room end
        function tile:getCell() if not self.unloaded then return cell end end
        function tile:getChunk() if not self.unloaded then return chunk end end
        function tile:getObjects() return list(self.objects) end
        function tile:getMovingObjects() return list(self.moving) end
        function tile:getVehicleContainer() return self.vehicle end
        function tile:HasStairs() return self.stairs == true end
        function tile:TreatAsSolidFloor() return self.floor end
        function tile:isSolid() return self.bed == true or self.blocked end
        function tile:isSolidTrans() return false end
        function tile:isFree() return not self:isSolid() and not self.selfOccupied end
        function tile:isSafeToSpawn() return self.unsafe ~= true end
        function tile:isBlockedTo(other) return self.walls[other] == true end
        function tile:isWindowTo(other) return self.windows[other] == true end
        function tile:isDoorTo(other) return self.doors[other] == true end
        function tile:isHoppableTo(other) return self.fences[other] == true end
        function tile:testCollideAdjacent(_, dx, dy)
            local target = tiles[key(self.x + dx, self.y + dy)]
            return not target or target:isSolid() or self:isBlockedTo(target)
        end
        tiles[key(x, y)] = tile
    end end
    function grid:getWidth() return 1 end
    function grid:getHeight() return 2 end
    function grid:getSpriteGridPosX() return 0 end
    function grid:getSpriteGridPosY(sprite) return sprite.gy end
    local function bed(x, y)
        local pieces = {}
        for gy = 0, 1 do
            local sprite = { gy = gy }
            function sprite:getSpriteGrid() return grid end
            function sprite:getName() return "furniture_bedding_01_" .. self.gy end
            function sprite:getProperties() return { get = function(_, name)
                if name == "CustomName" then return "Hospital Bed" end
                if name == "BedType" then return "goodBed" end
            end } end
            local piece = { square = tiles[key(x, y + gy)] }
            function piece:getSquare() return self.square end
            function piece:getSprite() return sprite end
            function piece:isMoveAble() return true end
            function piece:getSurfaceOffset() return 30 end
            function piece:setSatChair(value) self.sat = value end
            piece.square.bed, piece.square.blocked = true, false
            piece.square.objects[#piece.square.objects + 1] = piece
            pieces[#pieces + 1] = piece
        end
        return pieces
    end
    local pieces = bed(10, 10)
    local neighbor = bed(12, 10) -- Same sprite grid, a different placed mattress.
    local actor = { px = 10.5, py = 10.5, square = tiles["10:10"], inventory = {}, health = 100,
        collidable = false, context = "idle", owner = "none" }
    function actor:getX() return self.px end
    function actor:getY() return self.py end
    function actor:getZ() return 1 end
    function actor:getWidth() return 0.3 end
    function actor:getCurrentSquare() return self.square end
    function actor:getSquare() return self.square end
    function actor:isDead() return self.dead == true end
    function actor:isOnBed() return self.onBed == true end
    function actor:isSittingOnFurniture() return false end
    function actor:isSitOnGround() return false end
    function actor:getCurrentActionContextStateName() return self.context end
    function actor:getCompanionMovementOwner() return self.owner end
    function actor:getSitOnFurnitureObject() return self.object end
    function actor:setSitOnFurnitureObject(value) self.object = value end
    function actor:setCollidable(value) self.collidable = value end
    function actor:isCollidable() return self.collidable end
    function actor:setIgnoreMovement(value) self.ignoreMovement = value end
    function actor:setBlockMovement(value) self.blockMovement = value end
    function actor:setVariable(name, value) self[name] = value end
    local recoveries, originalCargo = 0, actor.inventory
    SC.Actor = { recover = function(value, target)
        check(value == actor and value.inventory == originalCargo and value.health == 100,
            "recovery retains the original living actor and exact inventory")
        recoveries = recoveries + 1
        if not actor.noopRecovery then
            actor.px, actor.py, actor.square = target.x + 0.5, target.y + 0.5, target
            SC.GameplayUtil.invalidateSpatial(actor)
        end
        return true
    end }
    return { actor = actor, pieces = pieces, neighbor = neighbor, tiles = tiles, room = room, cell = cell,
        exit = tiles["10:12"], count = function() return recoveries end }
end
local function startExit(f)
    f.actor.onBed, f.actor.object, f.actor.context = true, f.pieces[1], "onbed"
    check(not SC.NativeActions.leaveSeating(f.actor) and f.actor.object == f.pieces[1],
        "native get-up retains the actual bed reference")
    f.actor.context = "getup"
    check(not SC.NativeActions.leaveSeating(f.actor), "recovery waits through the real get-up pose")
    f.actor.context, f.actor.onBed = "idle", false
    SC_TEST_CLOCK = SC_TEST_CLOCK + 1500
end
do
    local f = scene()
    f.exit.blocked = false
    check(f.tiles["10:10"]:testCollideAdjacent(f.actor, 0, 1, 0), "solid mattress seam reproduces the old adjacent-tile refusal")
    local targets, touching = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    check(touching and #targets == 1 and targets[1] == f.exit, "the foot-side opening is found through this bed's own second segment")
    local okay, why = SC.NativeActions.leaveSeating(f.actor)
    check(okay and f.actor.square == f.exit and f.actor.collidable,
        "an orphaned bed-edge follower recovers to the clear floor centre: " .. tostring(why))
    check(f.cell.reads < 200, "recovery probes a bounded local footprint")
end
for _, barrier in ipairs({ "walls", "windows", "doors", "fences" }) do
    local f = scene()
    f.exit.blocked = false
    f.tiles["10:10"][barrier][f.tiles["10:11"]] = true
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "recovery never crosses a real " .. barrier .. " edge within the mattress")
end
for _, obstruction in ipairs({ "floor", "unloaded", "stairs", "vehicle", "body", "furniture" }) do
    local f = scene()
    f.exit.blocked = false
    local foot = f.tiles["10:11"]
    if obstruction == "floor" then foot.floor = false
    elseif obstruction == "unloaded" then foot.unloaded = true
    elseif obstruction == "stairs" then foot.stairs = true
    elseif obstruction == "vehicle" then foot.vehicle = {}
    elseif obstruction == "body" then foot.moving = { { isCollidable = function() return true end } }
    else foot.objects[#foot.objects + 1] = { isMoveAble = function() return true end } end
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "a bed segment with " .. obstruction .. " is never a recovery corridor")
end
do
    local f = scene()
    f.exit.blocked, f.exit.room = false, {}
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0, "exit stays in the same upstairs room")
    f.exit.room = f.room
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0, "a blocked exit pauses instead of scanning every frame")
    SC_TEST_CLOCK = SC_TEST_CLOCK + 1001
    check(SC.NativeActions.leaveSeating(f.actor) and f.count() == 1, "a newly clear exit is retried automatically after the pause")
end
do
    local f = scene()
    f.exit.blocked, f.exit.unsafe = false, true
    local targets = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    check(#targets == 0, "a narrow other-tile exit cannot bypass native spawn safety")
    f.tiles["9:10"].blocked = false
    targets = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    check(#targets == 1 and targets[1] == f.tiles["9:10"],
        "a native-rejected narrow exit cannot hide another usable side of the bed")
    startExit(f)
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.05, f.exit
    check(SC.NativeActions.leaveSeating(f.actor) and f.count() == 1,
        "an existing actor can recenter its narrow aisle even when native spawning rejects it")
end
do
    local f = scene()
    f.tiles["13:10"].blocked = false
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "another identical bed cannot be crossed to reach distant clear floor")
end
do
    local f = scene()
    local tableTile, clearSide = f.tiles["11:10"], f.exit
    tableTile.blocked, clearSide.blocked = false, false
    tableTile.objects = { { getSurfaceOffset = function() return 30 end,
        isMoveAble = function() return true end } }
    local targets, touching = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    check(touching and #targets == 1 and targets[1] == clearSide,
        "a bedside table blocks its exit side while the other mattress end remains usable")
    check(SC.NativeActions.leaveSeating(f.actor) and f.actor.square == clearSide,
        "a table beside the bed is avoided instead of stepped through on get-up")
end
do
    local f = scene()
    f.exit.blocked = false
    startExit(f)
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.05, f.exit
    f.exit.selfOccupied, f.exit.moving = true, { f.actor }
    check(SC.NativeActions.leaveSeating(f.actor) and f.actor.py == 12.5 and f.count() == 1,
        "a stock 0.05-tile ejection is recentered until the entire collision capsule clears")
end
do
    local f = scene()
    f.exit.blocked = false
    startExit(f)
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.5, f.exit
    check(SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "an already clear native exit needs no corrective movement")
end
do
    local f = scene()
    f.exit.blocked = false
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.5, f.exit
    local position = SC.GameplayUtil.position
    SC.GameplayUtil.position = function(value)
        if value == f.actor then return 10.5, 10.5, 1 end
        return position(value)
    end
    local _, touching = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    SC.GameplayUtil.position = position
    check(touching == false, "a stale decision-batch position cannot pull a clear actor back onto the mattress")
end
for _, blocked in ipairs({ false, true }) do
    local f = scene()
    f.exit.blocked = false
    startExit(f)
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.05, f.exit
    f.exit.moving = { f.actor, { isCollidable = function() return true end } }
    local nextFloor = f.tiles["11:12"]
    nextFloor.blocked = false
    f.exit.doors[nextFloor] = blocked
    local okay = SC.NativeActions.leaveSeating(f.actor)
    if blocked then
        check(not okay and f.count() == 0, "a crowded edge exit still cannot cross a door")
    else
        check(okay and f.actor.square == nextFloor and f.count() == 1,
            "two sleepers sharing an aisle tile do not permanently block bed-edge clearance")
    end
end
do
    local f = scene()
    f.exit.blocked = false
    startExit(f)
    f.actor.px, f.actor.py, f.actor.square = 10.5, 12.05, f.exit
    f.exit.objects = { { isMoveAble = function() return true end } }
    f.tiles["11:12"].blocked = false
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "the aisle recovery does not cross unrelated furniture at its source")
end
do
    local f = scene()
    f.exit.blocked = false
    f.actor.noopRecovery = true
    local okay, why = SC.NativeActions.leaveSeating(f.actor)
    check(not okay and why == "standing_from_bed_exit_unverified" and f.count() == 1,
        "a provider reporting success without moving the actor cannot release the exit gate")
end
for _, owner in ipairs({ "attack", "grapple", "traversal", "corpse_drag" }) do
    local f = scene()
    f.exit.blocked, f.actor.owner = false, owner
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0 and not f.actor.collidable,
        "native " .. owner .. " retains ownership of the actor")
end
do
    local f = scene()
    f.actor.dead = true
    check(SC.NativeActions.leaveSeating(f.actor) and f.count() == 0, "death releases exit state without moving the body")
end
do
    local f = scene()
    function f.actor:getX() return nil end
    local targets, touching, why = SC.BedGeometry.exitTargets(f.pieces[1], f.actor)
    check(#targets == 0 and touching == true and why == "bed_exit_position_unavailable",
        "unknown physical coordinates cannot be reported as a verified clear exit")
    check(not SC.NativeActions.leaveSeating(f.actor) and f.count() == 0,
        "missing coordinates keep the exit gated instead of inventing a displacement")
end
do
    local f = scene()
    for _, piece in ipairs(f.pieces) do
        local sprite = piece:getSprite()
        function sprite:getProperties() return { get = function(_, name)
            if name == "CustomName" then return "Bedside Table" end
        end } end
    end
    check(SC.NativeActions.seatingStatus(f.actor) == "standing" and f.count() == 0,
        "bedding-sheet bedside furniture is never misclassified as a bed")
end
do
    local f = scene()
    f.exit.blocked = false
    startExit(f)
    f.actor.square, f.actor.px, f.actor.py = f.neighbor[1]:getSquare(), 12.5, 10.5
    local original = SC.BedGeometry.exitTargets
    SC.BedGeometry.exitTargets = function(bed, actor)
        if actor.square == f.exit then return {}, false end
        if bed == f.pieces[1] then return { f.exit }, true end
        return {}, true
    end
    local okay = SC.NativeActions.leaveSeating(f.actor)
    SC.BedGeometry.exitTargets = original
    check(okay and f.actor.square == f.exit,
        "the exit controller retains the entered bed when a different bed is now underfoot")
end
SC_TEST_REPORT = "BED_EXIT_PASS checks=" .. checks .. " native-seam=true capsule=true ownership=true bounded=true"
