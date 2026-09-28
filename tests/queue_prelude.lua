-- Loaded before the game's own timed-action files so they can run outside the
-- engine. Only what those files touch on the paths the harness drives is faked;
-- the queue and action logic under test is the shipped Lua, unmodified.

require = function() end
instanceof = function() return false end
getTimestampMs = function() return 0 end
isServer = function() return false end
isClient = function() return false end
MoodleType = { UNHAPPY = "UNHAPPY", DRUNK = "DRUNK" }
ISLogSystem = { logAction = function() end }

-- Stand-in for the Java LuaTimedActionNew: begin() creates one per action, and
-- its forceStop() calls back into the Lua table's stop(), as the engine does.
LuaTimedActionNew = {
    new = function(tbl, character)
        local handle = { tbl = tbl, started = true }
        function handle:forceStop() self.tbl:stop() end
        function handle:isStarted() return self.started end
        return handle
    end,
}

-- ISTimedActionQueue.lua keys a table on these engine singletons at load time.
for _, name in ipairs({ "ClimbThroughWindowState", "ClimbOverFenceState",
        "ClimbOverWallState", "ClimbSheetRopeState", "ClimbDownSheetRopeState",
        "CloseWindowState", "OpenWindowState" }) do
    local instance = { name = name }
    _G[name] = { instance = function() return instance end }
end

-- Registration only; the harness drives the queue directly, never by tick.
Events = setmetatable({}, { __index = function() return { Add = function() end } end })

PZRL = PZRL or {}
