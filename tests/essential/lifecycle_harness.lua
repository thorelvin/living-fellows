-- SPDX-License-Identifier: MIT
-- Actual action/actor owners; provider callbacks stand in only for native removal.
local SC = SurvivorCompanion
local S, A, checks = SC.ActionSupervisor, SC.Actor, 0
local function check(value, label)
    checks = checks + 1
    assert(value, "essential lifecycle " .. checks .. ": " .. label)
end
local function actor(id)
    local value = { id = id, x = 10, y = 10, z = 0,
        modData = { SC_Id = id, SC_Recruited = true } }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getModData() return self.modData end
    function value:isDead() return self.dead == true end
    return value
end
S.reset(nil, "essential_fixture")
local first, other, primary = actor("sc-first"), actor("sc-other"), actor("primary")
local originalPlayerAction = { name = "player action" }
local playerQueue = ISTimedActionQueue.getTimedActionQueue(primary)
playerQueue.current, playerQueue.queue = originalPlayerAction, { originalPlayerAction }
function getSpecificPlayer(index) return index == 0 and primary or nil end

local cancelReady, cancellations = false, 0
local resource = {}
local work = assert(S.begin(first, { owner = "work", action = "carry", ignoreRetry = true,
    onCancel = function() cancellations = cancellations + 1 return cancelReady end }))
check(S.reserve(work, resource, "original cargo"), "the exact resource belongs to one action")
local foreign = assert(S.begin(other, { owner = "work", action = "other work", ignoreRetry = true }))
check(not S.cancel(first, "new_order") and S.current(first) == work
    and S.reservationCount(first) == 1, "unsettled cancellation retains its owner and original reservation")
cancelReady = true
check(S.cancel(first, "new_order") and cancellations == 2 and S.current(first) == nil
    and S.current(other) == foreign, "only accepted cancellation releases the affected actor")

local transaction = assert(S.begin(first, { owner = "logistics", action = "deposit",
    ignoreRetry = true, requiresVisual = true }))
check(not S.transition(transaction, "committing"), "unverified animation cannot commit an inventory change")
check(S.transition(transaction, "animating") and S.markVisualVerified(transaction)
    and S.transition(transaction, "committing"), "verified native visual grants one commit boundary")
local mutations = 0
check(S.commit(transaction, function() mutations = mutations + 1 return true, "moved", { id = "original" } end),
    "the physical mutation records its exact receipt")
check(not S.commit(transaction, function() mutations = mutations + 1 return true end) and mutations == 1,
    "a repeated commit cannot repeat the physical effect")
check(S.transition(transaction, "verifying") and S.complete(transaction, "stored")
    and S.reservationCount(first) == 0, "verification reaches one clean terminal state")

local removes, retireCancelled = 0, 0
check(A._setProviderForTests({ testOnly = true,
    isActor = function(_, value) return value ~= primary end,
    remove = function() removes = removes + 1 return removes > 1 end }), "the fixture provides only native lifecycle results")
check(SC.Registry.register(first, { id = first.id }) and SC.Registry.register(other, { id = other.id }),
    "companions are registered independently of the primary player")
local retiring = assert(S.begin(first, { owner = "work", action = "retiring", ignoreRetry = true,
    onCancel = function() retireCancelled = retireCancelled + 1 return true end }))
S.reserve(retiring, {}, "retiring resource")
check(not A.remove(first) and A.ownershipSnapshot().actorCleanups == 1,
    "failed native removal retains its exact cleanup obligation")
check(A.remove(first) and removes == 2 and retireCancelled == 1
    and A.ownershipSnapshot().actorCleanups == 0 and S.actorStateCount(first) == 0,
    "retry removes only the original actor without replaying completed action cleanup")
check(S.current(other) == foreign and playerQueue.current == originalPlayerAction
    and playerQueue.queue[1] == originalPlayerAction and getSpecificPlayer(0) == primary,
    "companion retirement leaves the other owner, player action queue and player identity intact")
S.cancel(other, "fixture_done", nil, true)
SC.Registry.reset()
check(S.leakedReservations() == 0, "the lifecycle leaves no orphaned reservations")

-- Diagonal cars can overlap a tile that vanilla isFree still accepts.
local exitCar, neighborCar = {}, {}
local tiles = {}
local function exitTile(x, y, vehicle)
    local tile = { x = x, y = y, vehicle = vehicle }
    function tile:getX() return self.x end
    function tile:getY() return self.y end
    function tile:getZ() return 0 end
    function tile:isSolid() return false end
    function tile:isSolidTrans() return false end
    function tile:TreatAsSolidFloor() return true end
    function tile:isFree() return true end
    function tile:getVehicleContainer() return self.vehicle end
    tiles[x .. ":" .. y] = tile
    return tile
end
local insideCar = exitTile(10, 10, exitCar)
local insideNeighbor = exitTile(11, 10, neighborCar)
local clearExit = exitTile(10, 11)
function exitCar:getX() return 10 end
function exitCar:getY() return 10 end
function exitCar:getZ() return 0 end
function exitCar:getCell() return { getGridSquare = function(_, x, y) return tiles[x .. ":" .. y] end } end
function exitCar:getEnterSeatDistance(_, x, y)
    if math.floor(x) == 10 and math.floor(y) == 10 then return 0.1 end
    if math.floor(x) == 11 and math.floor(y) == 10 then return 0.2 end
    return 0.3
end
local exits = SC.Vehicle.safeExitSquares(exitCar, 0)
check(exits and #exits == 1 and exits[1] == clearExit,
    "native exit selection skips both its own and a neighboring vehicle footprint")
clearExit.vehicle = neighborCar
check(SC.Vehicle.safeExitSquares(exitCar, 0) == nil,
    "a fully blocked passenger door waits instead of placing the companion inside a car")
;(function()
    -- Exercise the real instance adapter at the irreversible hutch boundary.
    local queueApi,doorApi=ISTimedActionQueue,ISToggleHutchDoor
    local queue={queue={}}
    ISTimedActionQueue={getTimedActionQueue=function() return queue end,
        add=function(action) queue.current,queue.queue=action,{action} end}
    local toggles,cleanups,stops=0,0,0
    local closed,allow=false,true
    local worker={getInventory=function() return {} end,
        getPrimaryHandItem=function() end,getSecondaryHandItem=function() end}
    ISToggleHutchDoor={new=function(_,subject)
        return {character=subject,isValid=function() return true end,
            complete=function() toggles=toggles+1 closed=true return true end,
            perform=function() cleanups=cleanups+1 end,
            forceStop=function() stops=stops+1 end}
    end}
    local intent={operation="animal_close",object={},validate=function() return not closed end,
        beforeCommit=function() return allow end}
    check(SC.NativeActions.startAnimal(worker,intent),"native door adapter queues the exact Farmer action")
    local action=queue.current
    allow=false
    check(action:complete()==false and toggles==0 and stops==1,
        "an invalidated roost proof stops the native door effect")
    allow=true
    check(action:complete()==true and action:complete()==true and toggles==1,
        "repeated native completion cannot toggle a closed hutch back open")
    action:perform()
    check(cleanups==1 and stops==1,"successful commit still permits native queue and sound cleanup")
    SC.NativeActions.resetWork(worker)
    ISTimedActionQueue,ISToggleHutchDoor=queueApi,doorApi
end)()

SC_TEST_REPORT = "Essential lifecycle: " .. checks .. " ownership/isolation checks passed"
