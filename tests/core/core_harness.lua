-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
check(type(SC) == "table" and SC.Identity.worldSaveKey == "SC_WorldV1"
        and SC.Identity.saveSchema == 3, "namespace identity")
do
    local values = SC.Call.pack(SC.Call.protected(function()
        return "first", nil, "third", nil
    end))
    check(values.n == 5 and values[1] == true and values[2] == "first"
            and values[3] == nil and values[4] == "third" and values[5] == nil,
        "protected calls preserve sparse and trailing return values exactly")
    local exact = { one = 1, two = 2, three = 3 }
    local copied, copyReason = SC.StableValue.copyStrict(exact, {
        maxDepth = 2, maxEntries = 4, path = "$.exact",
    })
    local rejected, rejectReason = SC.StableValue.copyStrict(exact, {
        maxDepth = 2, maxEntries = 3, path = "$.over",
    })
    check(copied and copied.three == 3 and copyReason == nil and rejected == nil
            and string.find(tostring(rejectReason), "limit exceeded", 1, true),
        "strict stable copies succeed at the exact boundary and reject one over")
    -- Game code writes some item modData from Java: torn sheets keep their
    -- filterLife as a boxed Float. The test runner provides one, and a plain
    -- Java object, as the real userdata they are in game.
    local foreign = { filterLife = SC_TEST_BOXED_FLOAT, handle = SC_TEST_JAVA_OBJECT, kept = "yes" }
    local strictCopy, strictReason = SC.StableValue.copyStrict(foreign, {
        maxDepth = 2, maxEntries = 8, path = "$.item.modData",
    })
    local lenient, lenientReason = SC.StableValue.copyStrict(foreign, {
        maxDepth = 2, maxEntries = 8, path = "$.item.modData", foreignScalars = true,
    })
    check(type(SC_TEST_BOXED_FLOAT) == "userdata" and type(SC_TEST_JAVA_OBJECT) == "userdata"
            and strictCopy == nil
            and string.find(tostring(strictReason), "unsupported userdata", 1, true) ~= nil
            and lenient ~= nil and lenientReason == nil and lenient.filterLife == 0.75
            and lenient.handle == nil and lenient.kept == "yes",
        "a boxed Java number in item modData copies as a number and other Java objects are left out: "
            .. tostring(lenientReason))
end
local immutable = pcall(function() SC.Config.defaults.frameBudgetMs = 99 end)
check(not immutable and SC.Config.get("frameBudgetMs") == 3, "configuration is immutable")
do
    local priorSandbox = SandboxVars
    SandboxVars = { LivingFellows = {
        EncountersEnabled = false, EncounterFrequency = 4, MaxCompanions = 9,
        CompanionNeedsRate = 0.75, HouseholdSpawnsEnabled = false,
        HouseholdDailyChance = 17, MaxHouseholds = 1, UIOpacity = 0.44,
        ShowCompanionNames = false, ExpeditionDestinationScope = 2,
    } }
    local refreshed = SC.Config.refreshSandbox()
    check(refreshed and SC.Config.get("productionEncounterEnabled") == false
        and SC.Config.get("productionSpawnCooldownMs") == 120000
        and SC.Config.get("maxCompanions") == 9
        and SC.Config.get("needsRateMultiplier") == 0.75
        and SC.Config.get("factionEnabled") == false
        and SC.Config.get("factionDailySpawnChancePercent") == 17
        and SC.Config.get("factionMaxHouseholds") == 1
        and SC.Config.get("uiPanelOpacity") == 0.44
        and SC.Config.get("companionNameLabels") == false
        and SC.Config.get("expeditionDestinationScope") == "known_only",
        "sandbox options override the single canonical runtime configuration")
    SandboxVars = priorSandbox
    SC.Config.refreshSandbox()
    check(SC.Config.get("maxCompanions") == 16 and SC.Config.get("factionMaxHouseholds") == 3
        and SC.Config.get("companionNameLabels") == true
        and SC.Config.get("expeditionDestinationScope") == "all_nearby",
        "sandbox refresh clears stale overrides when no options are available")
end

local scheduled = 0
local schedulerClock = 0
SC.Scheduler._setClock(function() return schedulerClock end)
check(SC.Scheduler.register("core-test", 10, 5, function() scheduled = scheduled + 1 end),
    "scheduler accepts a valid task")
SC.Scheduler.tick()
schedulerClock = 10
SC.Scheduler.tick()
check(scheduled == 1, "scheduler invokes due task once")
check(not SC.Scheduler.dueFor("sc-a", "sense", 100, 0), "stable staggering defers initial lane")

do
    for _ = 1, 3 do
        SC.Diagnostics.guard("breaker-test", "sc-a", function() error("injected failure") end)
    end
    check(SC.Diagnostics.isDisabled("breaker-test", "sc-a"), "circuit breaker opens")
    local breakerClock = SC_TEST_CLOCK
    SC_TEST_CLOCK = SC_TEST_CLOCK + SC.Config.get("runtime", "circuitBreakerResetMs") + 1
    check(not SC.Diagnostics.isDisabled("breaker-test", "sc-a"),
        "circuit breaker becomes half-open after its reset window")
    local recovered, recoveredValue = SC.Diagnostics.guard("breaker-test", "sc-a",
        function() return "recovered" end)
    local recoveredSnapshot = SC.Diagnostics.snapshot()["breaker-test:sc-a"]
    check(recovered and recoveredValue == "recovered" and recoveredSnapshot.state == "closed"
        and recoveredSnapshot.consecutiveFailures == 0 and recoveredSnapshot.recoveries == 1,
        "successful half-open probe closes and resets the circuit")
    for _ = 1, 4 do SC.Diagnostics.report("notice-test", "sc-a", "ordinary warning") end
    check(not SC.Diagnostics.isDisabled("notice-test", "sc-a"),
        "ordinary diagnostics do not disable a runtime subsystem")
    SC_TEST_CLOCK = breakerClock
end


print("CORE_KAHLUA_PASS checks=" .. tostring(checks))
