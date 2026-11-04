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
SC_TEST_REPORT = "Essential lifecycle: " .. checks .. " ownership/isolation checks passed"
