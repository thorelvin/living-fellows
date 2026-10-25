-- SPDX-License-Identifier: MIT
-- Exercise the shared Lua owner and the actual no-argument render hook. Native
-- frame compatibility/application is independently covered against the game JAR.
local SC, View = SurvivorCompanion, SurvivorCompanion.ViewSession
local function check(value, message)
    if not value then error("view session restore: " .. message) end
end
local primary, companion, slot = {}, {}, nil
local trace, hooks, oldCallbacks, reports = {}, {}, {}, {}
local polls, promotions, adds, removes = 0, 0, 0, 0
local nativePending, primaryFrame, stableFrames = false, false, 0
local forcedStatus, throwPoll, throwAdd, throwRemove
local nativeReason = "fixture_failure"
local render = {}
function render.Add(callback)
    adds = adds + 1
    check(#hooks == 0, "one release owns at most one render listener")
    hooks[1], oldCallbacks[#oldCallbacks + 1] = callback, callback
    trace[#trace + 1] = "hook"
    if throwAdd then error("hook install interrupted") end
end
function render.Remove(callback)
    removes = removes + 1
    if throwRemove then error("hook removal interrupted") end
    check(hooks[1] == callback, "only the owned listener is removed")
    hooks = {}
end
Events = { OnPostRender = render }
function getSpecificPlayer(index)
    if index == 0 then return primary end
    if index == 1 then return slot end
end
local clock = {}
function clock:setY(y)
    check(y == 10, "solo clock anchor restored")
    trace[#trace + 1] = "clock"
end
UIManager = {
    getClock = function() return clock end,
    resize = function()
        check(slot == nil and View.owner() == nil, "resize occurs after native release")
        trace[#trace + 1] = "resize"
    end,
}
SCBridge = { restoreExpeditionZoom = function()
    trace[#trace + 1] = "zoom"
    return true
end }
SC.Diagnostics = { report = function(subsystem, actor, message, detail)
    check(subsystem == "view_restore" and actor == nil,
        "render recovery reports through one bounded subsystem diagnostic")
    reports[#reports + 1] = { message = message, detail = detail }
end }
SCSplitScreenProbe = {
    promote = function(actor)
        promotions = promotions + 1
        nativePending, slot = false, actor
        return actor
    end,
    isLeader = function(actor) return actor ~= nil and actor == slot end,
    pollPrimaryViewRestore = function(...)
        check(select("#", ...) == 0, "OnPostRender has no player argument")
        polls = polls + 1
        check(slot == nil and View.owner() == nil, "poll only follows a released view")
        check(trace[#trace] == "hook", "zoom and HUD resize precede render follow-up")
        if throwPoll then error("native render failure") end
        if forcedStatus then return forcedStatus end
        if not nativePending then return "cancelled" end
        if not primaryFrame then return "waiting" end
        stableFrames = stableFrames + 1
        if stableFrames < 2 then return "waiting" end
        nativePending = false
        return "applied"
    end,
    releaseDiagnostics = function() return "restoreReason=" .. nativeReason end,
}
local function release(mode, worldExit)
    slot, nativePending, stableFrames = nil, worldExit ~= true, 0
    trace = { "native_release" }
    check(View.released(mode, 2, worldExit), "shared release commits once")
end
local function renderOnce()
    local callback = hooks[1]
    if callback then callback() end
end
local function begin(mode)
    primaryFrame = false
    check(View.claim(mode or "expedition", companion), "claim LF companion view")
end

-- Incompatible bridges fail before ownership, native promotion or UI changes.
local normalPoll = SCSplitScreenProbe.pollPrimaryViewRestore
SCSplitScreenProbe.pollPrimaryViewRestore = nil
check(select(2, View.claim("base_watch", companion)) == "local_view_restore_bridge_unavailable"
    and promotions == 0 and View.owner() == nil,
    "old native JAR cannot enter a view lacking restoration capability")
slot = companion
check(select(2, View.adopt("expedition", companion, 2)) == "local_view_restore_bridge_unavailable"
    and View.owner() == nil, "restored views require the same native render capability")
slot = nil
SCSplitScreenProbe.pollPrimaryViewRestore = normalPoll
Events.OnPostRender = nil
check(select(2, View.claim("expedition", companion)) == "local_view_restore_event_unavailable"
    and promotions == 0, "missing render event fails before native promotion")
Events.OnPostRender = render

begin()
local beforeWrongModeTrace = table.concat(trace, ",")
local beforeWrongModeSlot = View.slotSqlId()
local beforeWrongModeAdds, beforeWrongModeRemoves = adds, removes
check(select(2, View.released("base_watch", 42)) == "companion_view_owner_mismatch"
    and View.owner() == "expedition" and slot == companion
    and View.slotSqlId() == beforeWrongModeSlot and #hooks == 0
    and table.concat(trace, ",") == beforeWrongModeTrace
    and adds == beforeWrongModeAdds and removes == beforeWrongModeRemoves,
    "wrong release owner cannot clear the live view, remember another slot or change HUD/hooks")
release("expedition")
check(table.concat(trace, ",") == "native_release,zoom,clock,resize,hook"
    and polls == 0 and #hooks == 1,
    "release restores zoom and solo HUD before installing deferred listener")
check(select(2, View.released("expedition", 2)) == "companion_view_owner_mismatch"
    and adds == 1, "duplicate release cannot add or rearm another recovery")
renderOnce()
check(View.primaryRestoreDiagnostic().status == "waiting" and #hooks == 1,
    "foreign viewport callback leaves compatibility decisions to native guard")
primaryFrame = true
renderOnce()
check(View.primaryRestoreDiagnostic().pending and #hooks == 1,
    "first primary render must settle before native application")
renderOnce()
check(View.primaryRestoreDiagnostic().status == "applied" and #hooks == 0
    and polls == 3 and adds == 1 and removes == 1,
    "stable primary render applies once and removes listener")
oldCallbacks[1]()
check(polls == 3 and #reports == 0, "late removed callbacks cannot repeat recovery")
local saved = View.export()
check(saved.schema == 1 and saved.slotSqlId == 2 and saved.pending == nil,
    "transient render recovery does not change the saved view descriptor")

begin()
release("expedition")
forcedStatus, primaryFrame = "applied", true
local firstEligiblePoll = polls
renderOnce()
check(polls == firstEligiblePoll + 1 and #hooks == 0
    and View.primaryRestoreDiagnostic().status == "applied",
    "Lua permits application on the first later frame accepted by native")
forcedStatus = nil

begin("base_watch")
release("base_watch")
check(table.concat(trace, ",") == "native_release,clock,resize,hook",
    "Base Watch uses the same render boundary after its solo HUD restore")
local stale = hooks[1]
local beforePoll = polls
begin("expedition")
check(#hooks == 0 and View.primaryRestoreDiagnostic().status == "cancelled"
    and nativePending == false, "new promotion cancels previous deferred recovery")
stale()
check(polls == beforePoll, "new view cannot poll or restore a stale release")
release("expedition", true)
check(#hooks == 0 and nativePending == false,
    "world exit release never installs a live-world render listener")

begin()
release("expedition")
stale, beforePoll = hooks[1], polls
check(View.reset(), "reset shared owner")
stale()
check(#hooks == 0 and polls == beforePoll,
    "reset removes and invalidates an unfinished old-world callback")

begin()
release("expedition")
forcedStatus = "cancelled"
renderOnce()
check(#hooks == 0 and View.primaryRestoreDiagnostic().status == "cancelled"
    and #reports == 0, "native world or primary identity change cancels quietly")
forcedStatus = nil

begin()
release("expedition")
stale, beforePoll = hooks[1], polls
local beforeTimeoutReports, beforeTimeoutAdds = #reports, adds
forcedStatus = "waiting"
for _ = 1, 59 do renderOnce() end
check(View.primaryRestoreDiagnostic().pending and #hooks == 1
    and polls == beforePoll + 59 and adds == beforeTimeoutAdds
    and #reports == beforeTimeoutReports,
    "native-incompatible frames keep one listener without recreating the release or HUD")
nativeReason, forcedStatus = "primary_frame_timeout", "failed"
renderOnce()
check(not View.primaryRestoreDiagnostic().pending and #hooks == 0
    and View.primaryRestoreDiagnostic().status == "failed"
    and #reports == beforeTimeoutReports + 1
    and string.find(reports[#reports].detail, "primary_frame_timeout", 1, true),
    "bounded native frame failure terminates the hook and preserves its timeout reason")
stale()
check(polls == beforePoll + 60 and #reports == beforeTimeoutReports + 1,
    "a late primary callback cannot revive timed-out native lighting recovery")
forcedStatus, nativeReason = nil, "fixture_failure"

for _, outcome in ipairs({ "failed", "unexpected", "exception" }) do
    begin()
    release("expedition")
    stale, beforePoll = hooks[1], polls
    local previousReports = #reports
    forcedStatus, throwPoll = outcome, outcome == "exception"
    renderOnce()
    check(#hooks == 0 and View.primaryRestoreDiagnostic().status == "failed"
        and #reports == previousReports + 1,
        "terminal " .. outcome .. " detaches and reports one diagnostic")
    if outcome == "failed" then
        check(string.find(reports[#reports].detail, "fixture_failure", 1, true),
            "native failure diagnostic preserves its concrete restore reason")
    end
    stale()
    check(polls == beforePoll + 1 and #reports == previousReports + 1,
        "terminal failure never retries teardown or native renderer work")
    forcedStatus, throwPoll = nil, nil
end

begin()
throwAdd = true
local previousReports = #reports
release("expedition")
check(View.owner() == nil and #hooks == 0 and #reports == previousReports + 1,
    "hook install failure leaves completed release committed and reports once")
throwAdd = false

begin()
release("expedition")
stale, beforePoll, previousReports = hooks[1], polls, #reports
throwRemove, forcedStatus = true, "failed"
renderOnce()
stale()
check(polls == beforePoll + 1 and #reports == previousReports + 1
    and not View.primaryRestoreDiagnostic().pending,
    "failed hook removal leaves callback inert instead of repeating renderer resets")
throwRemove, forcedStatus, hooks = false, nil, {}

for _ = 1, 5 do
    begin()
    release("expedition")
    primaryFrame = true
    renderOnce()
    renderOnce()
    check(#hooks == 0 and View.primaryRestoreDiagnostic().status == "applied",
        "repeated view cycles each own one finite render follow-up")
end
check(View.reset(), "final cleanup")
print("view session render restore harness passed")
