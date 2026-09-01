-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Supervisor = SC.ActionSupervisor
local assertions = 0

local function check(condition, message)
    assertions = assertions + 1
    if not condition then error("SUPERVISOR_SOAK_TEST_FAILED: " .. tostring(message)) end
end

local function actor(id)
    local value = { id = id, x = 0, y = 0, z = 0, modData = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getModData() return self.modData end
    return value
end

local actorCounts = { 1, 4, 8, 16 }
local ticksPerPopulation = 10000
local totalTransactions, totalCommits, totalUrgentDispatches = 0, 0, 0

for _, population in ipairs(actorCounts) do
    Supervisor.reset(nil, "soak_population_start")
    local actors = {}
    for index = 1, population do
        actors[index] = actor("soak-" .. tostring(population) .. "-" .. tostring(index))
    end

    for tick = 1, ticksPerPopulation do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 1
        for index, candidate in ipairs(actors) do
            Supervisor.update(candidate)
            if (tick + index) % 29 == 0 then
                local resource = {}
                local token = assert(Supervisor.begin(candidate, {
                    owner = "soak", action = "transaction", targetKey = tostring(tick),
                    ignoreRetry = true,
                }))
                check(Supervisor.reserve(token, resource, "soak-resource") == true,
                    "soak reservation is acquired")
                check(Supervisor.transition(token, "approaching") == true
                        and Supervisor.transition(token, "settling") == true
                        and Supervisor.transition(token, "animating") == true
                        and Supervisor.transition(token, "committing") == true,
                    "soak transaction follows the legal pre-commit graph")
                local callbackCount = 0
                check(Supervisor.commit(token, function()
                    callbackCount = callbackCount + 1
                    return true, "soak_committed", { tick = tick, actor = index }
                end) == true and callbackCount == 1,
                    "soak commit callback executes exactly once")
                check(Supervisor.commit(token, function()
                    callbackCount = callbackCount + 1
                    return true
                end) ~= true and callbackCount == 1,
                    "soak double-commit fault cannot repeat a mutation")
                check(Supervisor.transition(token, "verifying") == true
                        and Supervisor.complete(token, "soak_verified") == true,
                    "soak transaction verifies and terminates")
                totalTransactions = totalTransactions + 1
                totalCommits = totalCommits + callbackCount
            elseif index == 1 and tick % 997 == 0 then
                local token = assert(Supervisor.begin(candidate, {
                    owner = "fault", action = "invalid_order", ignoreRetry = true,
                }))
                local accepted, reason = Supervisor.transition(token, "verifying")
                check(accepted ~= true
                        and reason == "illegal_phase_transition:selected:verifying",
                    "invalid-order fault is rejected deterministically")
                Supervisor.cancel(candidate, "fault_injected", nil, true)
            elseif index == 1 and tick % 701 == 0 then
                local token = assert(Supervisor.begin(candidate, {
                    owner = "fault", action = "urgent_commit", ignoreRetry = true,
                }))
                Supervisor.transition(token, "committing")
                local queued = Supervisor.queueUrgent(candidate, {
                    owner = "survival", action = "retreat",
                    dispatch = function()
                        totalUrgentDispatches = totalUrgentDispatches + 1
                        return true, "soak_urgent_dispatched"
                    end,
                })
                check(queued == true, "urgent fault queues behind commit")
                Supervisor.commit(token, { tick = tick })
                Supervisor.transition(token, "verifying")
                Supervisor.complete(token, "urgent_owner_done")
                check(Supervisor.urgentStatus(candidate).state == "dispatched",
                    "urgent fault dispatch is observable after commit")
            end
        end
    end

    local health = Supervisor.health()
    check(health.active == 0 and health.reservations == 0
            and health.leakedReservations == 0,
        "population " .. tostring(population) .. " leaves no action ownership leaks")
end

check(totalTransactions > 0 and totalCommits == totalTransactions,
    "soak retains one physical commit per completed transaction")
check(totalUrgentDispatches > 0,
    "soak exercises eventual urgent dispatch")
Supervisor.reset(nil, "soak_complete")

print("SUPERVISOR_SOAK_PASS assertions=" .. tostring(assertions)
    .. " transactions=" .. tostring(totalTransactions)
    .. " urgent=" .. tostring(totalUrgentDispatches))
