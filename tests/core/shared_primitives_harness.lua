-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Call = SC.Call
local Transaction = SC.Transaction
local NativeList = SC.NativeList

local function expect(condition, message)
    if not condition then error(message or "expectation failed") end
end

local function expectEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

-- Protected calls and transactions must preserve nil holes and trailing nils.
local noReturns = Call.pack(Call.protected(function() end))
expectEqual(noReturns.n, 1, "no-return protected tuple count")
expectEqual(noReturns[1], true, "no-return protected status")

local oneNil = Call.pack(Call.protected(function() return nil end))
expectEqual(oneNil.n, 2, "single-nil protected tuple count")
expectEqual(oneNil[1], true, "single-nil protected status")
expect(oneNil[2] == nil, "single nil is retained")

local nilReason = Call.pack(Call.protected(function() return nil, "reason" end))
expectEqual(nilReason.n, 3, "nil-reason protected tuple count")
expectEqual(nilReason[1], true, "nil-reason protected status")
expect(nilReason[2] == nil, "nil-reason first value")
expectEqual(nilReason[3], "reason", "nil-reason detail")

local sparseNumbers = Call.pack(Call.protected(function() return 1, nil, 3 end))
expectEqual(sparseNumbers.n, 4, "sparse protected tuple count")
expectEqual(sparseNumbers[2], 1, "sparse first result")
expect(sparseNumbers[3] == nil, "sparse middle nil")
expectEqual(sparseNumbers[4], 3, "sparse final result")

local protected = Call.pack(Call.protected(function()
    return "first", nil, "third", nil
end))
expectEqual(protected.n, 5, "protected tuple count")
expectEqual(protected[1], true, "protected status")
expectEqual(protected[2], "first", "protected first value")
expect(protected[3] == nil, "protected nil hole")
expectEqual(protected[4], "third", "protected third value")
expect(protected[5] == nil, "protected trailing nil")

local protectedSideEffects = 0
local thrown = Call.pack(Call.protected(function()
    protectedSideEffects = protectedSideEffects + 1
    error("protected fixture failure")
end))
expectEqual(thrown.n, 2, "thrown protected tuple count")
expectEqual(thrown[1], false, "thrown protected status")
expect(string.find(tostring(thrown[2]), "protected fixture failure", 1, true) ~= nil,
    "thrown protected reason")
expectEqual(protectedSideEffects, 1, "thrown callback executes once")

local instanceSideEffects = 0
local instance = {
    fail = function(self)
        instanceSideEffects = instanceSideEffects + 1
        error("instance fixture failure")
    end,
}
local instanceResult = Call.pack(Call.method(instance, "fail"))
expectEqual(instanceResult[1], false, "failed instance method status")
-- Build 42.20.4's Kahlua runtime replaces an explicit Lua error raised from a
-- callback with a table receiver by its own non-empty method-dispatch reason.
-- The safety contract here is visible failure plus exactly one invocation;
-- Java method exceptions retain their native diagnostic text.
expect(type(instanceResult[2]) == "string" and instanceResult[2] ~= "",
    "failed instance method exposes a reason")
expectEqual(instanceSideEffects, 1,
    "failed instance method is not retried with another receiver convention")

local staticSideEffects = 0
local static = {
    fail = function()
        staticSideEffects = staticSideEffects + 1
        error("static fixture failure")
    end,
}
local staticResult = Call.pack(Call.static(static, "fail"))
expectEqual(staticResult[1], false, "failed static method status")
expect(type(staticResult[2]) == "string" and staticResult[2] ~= "",
    "failed static method exposes a reason")
expectEqual(staticSideEffects, 1,
    "failed static method is not retried as an instance method")

local committed = Call.pack(Transaction.run(function()
    return true, "value", nil, "tail"
end, function()
    error("rollback must not run for a successful transaction")
end))
expectEqual(committed.n, 5, "transaction tuple count")
expectEqual(committed[1], true, "transaction status")
expectEqual(committed[2], true, "commit status value")
expectEqual(committed[3], "value", "commit payload")
expect(committed[4] == nil, "transaction nil hole")
expectEqual(committed[5], "tail", "transaction trailing payload")

local rollbackCalls = 0
local ok, primaryReason, rollbackReason = Transaction.run(function()
    return false, "primary failure"
end, function()
    rollbackCalls = rollbackCalls + 1
    return false, "rollback failure"
end)
expectEqual(ok, false, "failed transaction status")
expectEqual(primaryReason, "primary failure", "primary failure retained")
expectEqual(rollbackReason, "rollback failure", "rollback failure retained")
expectEqual(rollbackCalls, 1, "rollback call count")

-- Validate every step before acquiring ownership, and roll acquired steps back
-- exactly once in reverse order when a later commit fails.
local invalidCommits = 0
ok, primaryReason = Transaction.steps({
    {
        commit = function() invalidCommits = invalidCommits + 1 return true end,
        rollback = function() return true end,
    },
    { commit = function() return true end },
})
expectEqual(ok, false, "invalid step status")
expectEqual(primaryReason, "invalid transaction step 2", "invalid step reason")
expectEqual(invalidCommits, 0, "invalid transaction must not acquire state")

local sequence = {}
ok, primaryReason = Transaction.steps({
    {
        commit = function() sequence[#sequence + 1] = "commit-1" return true end,
        rollback = function() sequence[#sequence + 1] = "rollback-1" return true end,
    },
    {
        commit = function() sequence[#sequence + 1] = "commit-2" return true end,
        rollback = function() sequence[#sequence + 1] = "rollback-2" return true end,
    },
    {
        commit = function() sequence[#sequence + 1] = "commit-3" return false, "stop" end,
        rollback = function() sequence[#sequence + 1] = "rollback-3" return true end,
    },
})
expectEqual(ok, false, "multi-step failure status")
expectEqual(primaryReason, "stop", "multi-step failure reason")
expectEqual(table.concat(sequence, ","),
    "commit-1,commit-2,commit-3,rollback-2,rollback-1",
    "multi-step rollback order")

-- The same zero-based interface must work for ordinary Lua arrays and native
-- list-shaped objects without retrying a failed method through another path.
local luaList = { "alpha", "beta", "gamma" }
expectEqual(NativeList.size(luaList), 3, "Lua list size")
local child, available = NativeList.get(luaList, 1)
expectEqual(child, "beta", "Lua list item")
expectEqual(available, true, "Lua list availability")

local nativeGets = 0
local nativeList = {
    values = { "one", "two", "three" },
    size = function(self) return 3 end,
    get = function(self, index)
        nativeGets = nativeGets + 1
        return self.values[index + 1]
    end,
}
expectEqual(NativeList.size(nativeList), 3, "native list size")
child, available = NativeList.get(nativeList, 2)
expectEqual(child, "three", "native list item")
expectEqual(available, true, "native list availability")
expectEqual(nativeGets, 1, "native get is invoked once")

local failedGets = 0
local failedNativeList = {
    "fallback-must-not-be-used",
    size = function() return 1 end,
    get = function()
        failedGets = failedGets + 1
        error("fixture native get failure")
    end,
}
child, available = NativeList.get(failedNativeList, 0)
expect(child == nil and available == false,
    "failed native getter is not retried through Lua-array fallback")
expectEqual(failedGets, 1, "failed native getter call count")

local visited = {}
ok, primaryReason = NativeList.each(nativeList, function(value, index)
    visited[#visited + 1] = tostring(index) .. ":" .. tostring(value)
    return index < 1
end)
expectEqual(ok, true, "native list iteration status")
expectEqual(primaryReason, 2, "native list early-stop count")
expectEqual(table.concat(visited, ","), "0:one,1:two", "native list iteration")

print("SHARED_PRIMITIVES_PASS tuple=true transaction=true rollback=reverse native-list=true")
