-- SPDX-License-Identifier: MIT
-- Native class presence matters: PZOptimizer can be installed without an enabled Lua mod.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.PZOptimizerAdapter = SC.PZOptimizerAdapter or {}
local Adapter = SC.PZOptimizerAdapter
local state, reason = "absent", "PZOptimizer has not been checked"

-- The bridge can be missing or older than this file. When ZombieBuddy loads the
-- bridge JAR, SCBridge is not published yet at the main menu. Look each method up
-- before calling it: Kahlua prints a full stack trace even for an error that pcall
-- catches, so pcall alone still filled players' logs.
local function hasNative(...)
    if SCBridge == nil then return false end
    local count = select("#", ...)
    for index = 1, count do
        if not SCBridge[select(index, ...)] then return false end
    end
    return true
end

function Adapter.initialize()
    local requested = not SC.UserOptions or SC.UserOptions.get("pzOptimizerCompatibility") ~= false
    local okay, nextState, nextReason = false, nil, nil
    if hasNative("configurePZOptimizerAdapter", "getPZOptimizerAdapterState", "getPZOptimizerAdapterReason") then
        okay, nextState, nextReason = pcall(function()
            SCBridge.configurePZOptimizerAdapter(requested)
            return SCBridge.getPZOptimizerAdapterState(), SCBridge.getPZOptimizerAdapterReason()
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
    if hasNative("getPZOptimizerInlineCalls") then
        pcall(function() calls = SCBridge.getPZOptimizerInlineCalls() end)
    end
    return { state = state, reason = reason, inlineCalls = calls }
end

function Adapter.reset()
    if hasNative("configurePZOptimizerAdapter") then
        pcall(function() SCBridge.configurePZOptimizerAdapter(false) end)
    end
    state, reason = "disabled", "World stopped"
    return true
end

return Adapter
