-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
end

local SC = SurvivorCompanion
SC.Transaction = SC.Transaction or {}
local Transaction = SC.Transaction

-- Execute one checked state transition. Rollback is mandatory and its result
-- is reported separately without replacing the triggering failure.
function Transaction.run(commit, rollback)
    if type(commit) ~= "function" or type(rollback) ~= "function" then
        return false, "transaction requires commit and rollback callbacks"
    end
    local committed = SC.Call.pack(pcall(commit))
    if committed[1] == true and committed[2] ~= false then
        return true, SC.Call.unpack(committed, 2, committed.n)
    end
    local reason = committed[1] == true and committed[3] or committed[2]
    reason = tostring(reason or "transaction commit failed")
    local rolledBack = SC.Call.pack(pcall(rollback))
    if rolledBack[1] ~= true or rolledBack[2] == false then
        local rollbackReason = rolledBack[1] == true and rolledBack[3] or rolledBack[2]
        return false, reason, tostring(rollbackReason or "transaction rollback failed")
    end
    return false, reason
end

-- Small multi-step variant for lifecycle ownership. Each successful step is
-- rolled back in reverse order if a later step fails.
function Transaction.steps(steps)
    if type(steps) ~= "table" then return false, "transaction steps are required" end
    for index, step in ipairs(steps) do
        if type(step) ~= "table" or type(step.commit) ~= "function"
            or type(step.rollback) ~= "function" then
            return false, "invalid transaction step " .. tostring(index)
        end
    end
    local acquired = {}
    for _, step in ipairs(steps) do
        local values = SC.Call.pack(pcall(step.commit))
        if values[1] ~= true or values[2] == false then
            local reason = values[1] == true and values[3] or values[2]
            local rollbackFailures = {}
            for acquiredIndex = #acquired, 1, -1 do
                local prior = acquired[acquiredIndex]
                local rolled = SC.Call.pack(pcall(prior.rollback))
                if rolled[1] ~= true or rolled[2] == false then
                    rollbackFailures[#rollbackFailures + 1] = tostring(
                        rolled[1] == true and rolled[3] or rolled[2])
                end
            end
            return false, tostring(reason or "transaction step failed"),
                #rollbackFailures > 0 and table.concat(rollbackFailures, "; ") or nil
        end
        acquired[#acquired + 1] = step
    end
    return true
end

return Transaction
