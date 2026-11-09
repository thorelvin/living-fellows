-- SPDX-License-Identifier: MIT
-- Native class presence matters: PZOptimizer can be installed without an enabled Lua mod.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.PZOptimizerAdapter = SC.PZOptimizerAdapter or {}
local Adapter = SC.PZOptimizerAdapter
local state, reason = "absent", "PZOptimizer has not been checked"

function Adapter.initialize()
    local requested = not SC.UserOptions or SC.UserOptions.get("pzOptimizerCompatibility") ~= false
    local bridge = SCBridge
    local okay, nextState, nextReason = false
    if bridge and type(bridge.configurePZOptimizerAdapter) == "function"
        and type(bridge.getPZOptimizerAdapterState) == "function"
        and type(bridge.getPZOptimizerAdapterReason) == "function" then
        okay, nextState, nextReason = pcall(function()
            bridge.configurePZOptimizerAdapter(requested)
            return bridge.getPZOptimizerAdapterState(), bridge.getPZOptimizerAdapterReason()
        end)
    end
    if not okay then
        nextState, nextReason = "unsupported", "Native PZOptimizer adapter is unavailable; update the LF bridge"
    end
    if state ~= nextState or reason ~= nextReason then
        state, reason = nextState, nextReason
        if state == "unsupported" and SC.Diagnostics then
            SC.Diagnostics.report("pzoptimizer-adapter", nil, "PZOptimizer adapter unavailable", reason)
        end
        print("[LivingFellows] PZOptimizer adapter: " .. tostring(state) .. " - " .. tostring(reason))
    end
    return state == "active"
end

function Adapter.status()
    local calls = 0
    local bridge = SCBridge
    if bridge and type(bridge.getPZOptimizerInlineCalls) == "function" then
        pcall(function() calls = bridge.getPZOptimizerInlineCalls() end)
    end
    return { state = state, reason = reason, inlineCalls = calls }
end

function Adapter.reset()
    -- A Lua reset clears native globals before OnMainMenuEnter. Even a caught
    -- nil-bridge access is printed as an exception by the game VM.
    local bridge = SCBridge
    if bridge and type(bridge.configurePZOptimizerAdapter) == "function" then
        pcall(function() bridge.configurePZOptimizerAdapter(false) end)
    end
    state, reason = "disabled", "World stopped"
    return true
end

return Adapter
