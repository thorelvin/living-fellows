-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
-- review 3.4: the native target-coord contract. An explicit targetKind is
-- authoritative; otherwise the caller's inference decides, so a tile centers on
-- +0.5 while an exact world position is never shifted.
local centerTargetOnTile = SC.NativeActions._centerTargetOnTileForTests
check(type(centerTargetOnTile) == "function", "target-centring contract seam is exposed")
check(centerTargetOnTile({ targetKind = "square" }, false) == true,
    "an explicit square target kind forces tile centring regardless of inference")
check(centerTargetOnTile({ targetKind = "world" }, true) == false,
    "an explicit world target kind suppresses tile centring regardless of inference")
check(centerTargetOnTile({}, true) == true and centerTargetOnTile({}, false) == false,
    "with no explicit kind the caller's inference is used unchanged")
check(centerTargetOnTile(nil, true) == true,
    "a missing intent falls back to the caller's inference")
local centreActor = { x = 10.5, y = 20.5, z = 0 }
local tileCorner = { x = 10, y = 20, z = 0 }
local atSquare = SC.GameplayUtil.arrived(centreActor, tileCorner, {
    targetKind = "square", distance = 0.1,
})
local atWorld = SC.GameplayUtil.arrived(centreActor, tileCorner, {
    targetKind = "world", distance = 0.1,
})
check(atSquare == true and atWorld == false,
    "shared arrival centres square targets without shifting exact world coordinates")

;(function()
    -- Review F02: cancelling a tracked needs action cleared the actor's whole
    -- timed-action queue, which also removes whatever a vanilla or third-party
    -- action had queued behind ours -- and restoring our own borrowed item does
    -- not give them their place back. Cancel exactly what this record owns, as
    -- cancelWork already does.
    local NA = SC.NativeActions
    check(type(NA) == "table" and type(NA.cancelNeeds) == "function",
        "native actions exposes needs cancellation")
    local needsActor = { __class = "IsoPlayer" }
    function needsActor:getModData() self.data = self.data or {} return self.data end
    local ourAction = { character = needsActor, action = "drink" }
    local theirAction = { character = needsActor, action = "someone_elses" }
    local queue = { current = ourAction, list = { ourAction, theirAction } }
    function queue:removeFromQueue(timedAction)
        for index, value in ipairs(self.list) do
            if value == timedAction then table.remove(self.list, index) return end
        end
    end
    local previousQueueApi = ISTimedActionQueue
    local cleared = 0
    ISTimedActionQueue = {
        getTimedActionQueue = function() return queue end,
        clear = function() cleared = cleared + 1 queue.list = {} queue.current = nil end,
    }
    NA.resetNeeds(needsActor)
    check(NA._trackNeedsForTests(needsActor, { timedAction = ourAction, kind = "drink" }),
        "a needs record can be installed for cancellation")
    local ok = NA.cancelNeeds(needsActor, "danger")
    ISTimedActionQueue = previousQueueApi
    check(ok == true, "cancelling a tracked needs action succeeds")
    check(cleared == 0, "cancelling a needs action never clears the whole queue")
    check(#queue.list == 1 and queue.list[1] == theirAction,
        "an unrelated queued action survives a needs cancellation: " .. tostring(#queue.list))
end)()

print("NATIVE_ACTION_CONTRACT_PASS checks=" .. tostring(checks))
