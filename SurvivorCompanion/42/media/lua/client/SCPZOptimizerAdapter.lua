-- SPDX-License-Identifier: MIT
-- Native class presence matters: PZOptimizer can be installed without an enabled Lua mod.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.PZOptimizerAdapter = SC.PZOptimizerAdapter or {}
local Adapter = SC.PZOptimizerAdapter
local state, reason = "absent", "PZOptimizer has not been checked"

function Adapter.initialize()
    local requested = not SC.UserOptions or SC.UserOptions.get("pzOptimizerCompatibility") ~= false
    local okay, nextState, nextReason = pcall(function()
        SCBridge.configurePZOptimizerAdapter(requested)
        return SCBridge.getPZOptimizerAdapterState(), SCBridge.getPZOptimizerAdapterReason()
    end)
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
    pcall(function() calls = SCBridge.getPZOptimizerInlineCalls() end)
    return { state = state, reason = reason, inlineCalls = calls }
end

function Adapter.reset()
    pcall(function() SCBridge.configurePZOptimizerAdapter(false) end)
    state, reason = "disabled", "World stopped"
    return true
end

return Adapter
