-- SPDX-License-Identifier: MIT
local U = SurvivorCompanion.GameplayUtil
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("container capacity check " .. checks .. ": " .. message) end
end
local actor = {}
local item = { getFullType = function() return "Base.Cabbage" end,
    getUnequippedWeight = function() return 0.3 end,
    getActualWeight = function() return 0.1 end }
local nativeCalls, detailCalls = 0, 0
local trunk = {}
function trunk:hasRoomFor(who, what)
    nativeCalls = nativeCalls + 1
    check(who == actor and what == item, "native check receives worker and exact item")
    return self.allowed
end
function trunk:getCapacityWeight() detailCalls = detailCalls + 1 return self.used end
function trunk:getCapacity() detailCalls = detailCalls + 1 return 155 end
function trunk:getEffectiveCapacity(who)
    check(who == actor, "effective capacity uses worker traits")
    return self.effective
end
function trunk:getFreeCapacity(who)
    check(who == actor, "free capacity uses worker traits")
    return math.max(0, self.effective - self.used)
end
function trunk:isItemAllowed() error("accept callbacks must not run twice") end
trunk.allowed, trunk.used, trunk.effective = true, 84.7, 201
check(U.containerHasRoom(trunk, actor, item) == true, "Organized trunk with space accepts crop")
check(nativeCalls == 1 and detailCalls == 0, "success uses only one native call")
trunk.allowed = false
local allowed, reason, info = U.containerHasRoom(trunk, actor, item)
check(not allowed and reason == "destination_item_rejected", "room does not override native rejection")
check(info.used == 84.7 and info.baseCapacity == 155 and info.effectiveCapacity == 201
    and info.itemWeight == 0.3, "refusal details distinguish actual capacity and incoming weight")
trunk.used = 200.9
allowed, reason = U.containerHasRoom(trunk, actor, item)
check(not allowed and reason == "destination_full", "measured shortage reports full")
trunk.used, trunk.effective = 100, 108
allowed, reason = U.containerHasRoom(trunk, actor, item)
check(not allowed and reason == "destination_item_rejected", "Disorganized room still respects native rejection")
trunk.used = 107.9
check(select(2, U.containerHasRoom(trunk, actor, item)) == "destination_full",
    "Disorganized effective shortage is used instead of base capacity")

local bulky = { getUnequippedWeight = function() return 12 end,
    getActualWeight = function() return 0.1 end }
local nested = { hasRoomFor = function() return false end,
    getFreeCapacity = function() return 10 end }
check(select(2, U.containerHasRoom(nested, actor, bulky)) == "destination_full",
    "nested cargo uses unequipped weight including contents")
local unknown = { hasRoomFor = function() return false end }
check(select(2, U.containerHasRoom(unknown, actor, item)) == "capacity_unavailable",
    "unknown capacity is not called full")
check(select(2, U.containerHasRoom({}, actor, item)) == "capacity_unavailable",
    "missing native method cannot manufacture acceptance or full")
check(select(2, U.containerHasRoom({ hasRoomFor = function() error("fixture") end }, actor, item))
    == "capacity_unavailable", "failed native call is retryable, not full")
check(select(2, U.containerHasRoom({ hasRoomFor = function() return nil end }, actor, item))
    == "capacity_unavailable", "nonboolean native result is unavailable")
check(select(2, U.containerHasRoom(trunk, nil, item)) == "capacity_context_missing",
    "missing actor cannot use player capacity")
local rounded = { hasRoomFor = function() return false end,
    getCapacityWeight = function() return 84.704 end,
    getEffectiveCapacity = function() return 85 end }
check(select(2, U.containerHasRoom(rounded, actor, item)) == "destination_item_rejected",
    "fallback free space follows native hundredth-weight rounding")
local invalid = { hasRoomFor = function() return false end,
    getFreeCapacity = function() return math.huge end }
check(select(2, U.containerHasRoom(invalid, actor, item)) == "capacity_unavailable",
    "invalid capacity cannot be reported as full")
check(SurvivorCompanion.WorkTransport.hasRoom(unknown, actor, item) == false
    and select(2, SurvivorCompanion.WorkTransport.hasRoom(unknown, actor, item)) == "capacity_unavailable",
    "work transport propagates unavailable reason")
print("CONTAINER_CAPACITY_PASS checks=" .. checks)
