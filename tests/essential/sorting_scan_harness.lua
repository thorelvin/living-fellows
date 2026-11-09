-- SPDX-License-Identifier: MIT
-- A late item and concurrent workers must survive bounded real selector calls.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local base, saved, sources, touched, resolved = SC.BaseLife, {}, {}, {}, 0
for _, key in ipairs({ "storageRows", "resolveContainer", "depositStorageRows", "storageAcceptsDeposit" }) do
    saved[key] = base[key]
end
local actor = f.actor("bounded-sort-worker", 1, 1, {})
local destination = { id = "storage:bounded-destination", category = "valuables", deposits = true }
destination.container = f.containerObject(actor.square, {})
for index = 1, 3 do
    local contents = {}
    for itemIndex = 1, 65 do contents[itemIndex] = f.item("Base.Paperclip", "Item", { weight = .01 }) end
    if index == 3 then contents[#contents+1] = f.item("Base.Money", "Item", { weight = .01 }) end
    for _, item in ipairs(contents) do
        function item:getFullType() touched[self] = true return self.itemType end
    end
    sources[index] = { id = "storage:bounded-" .. index, category = "general", withdrawals = true,
        container = f.containerObject(actor.square, contents) }
end
base.storageRows = function() return sources end
base.depositStorageRows = function(category) return category == "valuables" and { destination } or {} end
base.resolveContainer = function(row)
    if row ~= destination then resolved = resolved+1 end
    return row.container, row.container and row.container.owner
end
base.storageAcceptsDeposit = function() return true end
local jobs, found, pending = { { type = "sort" }, { type = "sort" } }, {}, 0
for _ = 1, 100 do
    for index, job in ipairs(jobs) do
        if not found[index] then
            touched, resolved = {}, 0
            local source, _, to, _, item, why = SC.BaseWork.sortTransfer(job, actor)
            local count = 0 for _ in pairs(touched) do count = count+1 end
            f.check(count <= 64 and resolved <= 2, "a sorting call bounds items and source resolutions")
            if source then
                found[index] = item
                f.check(source == sources[3] and to == destination and item:getFullType() == "Base.Money",
                    "interleaved scans reach the exact late item and matching destination")
            else
                f.check(why == "haul_scan_pending", "an unfinished sorting scan stays pending rather than empty")
                pending = pending+1
            end
        end
    end
    if found[1] and found[2] then break end
end
f.check(found[1] and found[1] == found[2] and pending > 0,
    "workers keep independent cursors despite shared rotating storage windows")
f.check(#sources[3].container.items == 66 and #destination.container.items == 0,
    "discovery preserves every exact item and performs no transfer")

-- Decision evaluation can consume the frame before an admitted worker reaches
-- this selector. Both workers must still advance their own retained windows.
local originalPerformance = SC.Performance
local performance = originalPerformance or {}
SC.Performance = performance
local originalClock, originalBudget = performance.preciseNowMs, performance.remainingBudgetMs
performance.preciseNowMs = function() return 0 end
performance.remainingBudgetMs = function() return 0 end
local starvedJobs, starvedFound = { { type = "sort" }, { type = "sort" } }, {}
for _ = 1, 100 do
    for index, job in ipairs(starvedJobs) do
        if not starvedFound[index] then
            touched, resolved = {}, 0
            local source, _, to, _, item, why = SC.BaseWork.sortTransfer(job, actor)
            local count = 0 for _ in pairs(touched) do count = count+1 end
            f.check(count > 0 and count <= 8 and resolved == 1,
                "an exhausted frame admits one bounded source window instead of starving")
            if source then
                starvedFound[index] = item
                f.check(source == sources[3] and to == destination and item == found[index],
                    "late workers retain independent cursors and select the exact item")
            else
                f.check(why == "haul_scan_pending", "late incomplete discovery stays pending")
            end
        end
    end
    if starvedFound[1] and starvedFound[2] then break end
end
f.check(starvedFound[1] and starvedFound[1] == starvedFound[2],
    "both workers finish despite every frame having no remaining allowance")

local retainedRows = base.storageRows
local lateMoney = f.item("Base.Money", "Item", { weight = .01 })
local lateSource = { id = "storage:late-source", category = "general", withdrawals = true,
    container = f.containerObject(actor.square, { lateMoney }) }
local unavailableRows = {
    { id = "storage:denied", category = "general", withdrawals = false, container = sources[3].container },
    { id = "storage:missing", category = "general", withdrawals = true },
    { id = "storage:empty", category = "general", withdrawals = true, container = f.containerObject(actor.square, {}) },
    lateSource,
}
base.storageRows = function() return unavailableRows end
local availabilityJob = { type = "sort" }
for _ = 1, 3 do
    local source, _, _, _, _, why = SC.BaseWork.sortTransfer(availabilityJob, actor)
    f.check(source == nil and why == "haul_scan_pending",
        "late scans advance past denied, missing and empty sources without claiming empty storage")
end
local availableSource, _, _, _, availableItem = SC.BaseWork.sortTransfer(availabilityJob, actor)
f.check(availableSource == lateSource and availableItem == lateMoney,
    "a source behind unavailable containers remains discoverable under exhausted budgets")
base.storageRows = retainedRows

-- A slow source lookup can use the local allowance before the first item.
-- Admit one item, then preserve the exact cursor and yield.
local clock = 0
performance.preciseNowMs = function() clock = clock+1 return clock end
performance.remainingBudgetMs = function() return 3 end
touched, resolved = {}, 0
local _, _, _, _, _, slowReason = SC.BaseWork.sortTransfer({ type = "sort" }, actor)
local slowCount = 0 for _ in pairs(touched) do slowCount = slowCount+1 end
f.check(slowReason == "haul_scan_pending" and slowCount == 1 and resolved == 1,
    "a slow lookup permits one item without replaying or overrunning the window")
f.check(#sources[3].container.items == 66 and #destination.container.items == 0,
    "late and slow scans never withdraw, duplicate or deposit their candidates")
performance.preciseNowMs, performance.remainingBudgetMs = originalClock, originalBudget
SC.Performance = originalPerformance

local withdrawnJob = { type = "sort" }
SC.BaseWork.sortTransfer(withdrawnJob, actor)
local removed = table.remove(sources, 3)
local finished
for _ = 1, 100 do
    local source, _, _, _, _, why = SC.BaseWork.sortTransfer(withdrawnJob, actor)
    f.check(source == nil, "a resumed scan cannot select an unmarked storage")
    if why ~= "haul_scan_pending" then finished = why break end
end
f.check(finished == "haul_scan_changed" and #removed.container.items == 66,
    "removing a source invalidates its pending scan without touching its stock")
-- A shelf's changing count must not restart its sweep in front of every
-- other source. A very large first shelf also gets only one fair quantum.
local churnItems = {}
for i = 1, 1000 do churnItems[i] = f.item("Base.Paperclip", "Item", { weight = .01 }) end
local busy = { id = "storage:busy", category = "general", withdrawals = true,
    container = f.containerObject(actor.square, churnItems) }
local later = { id = "storage:later", category = "general", withdrawals = true,
    container = f.containerObject(actor.square, { lateMoney }) }
base.storageRows = function() return { busy, later } end
SC.Performance = { preciseNowMs = function() return 0 end, remainingBudgetMs = function() return 0 end }
local churnJob, selectedAt = { type = "sort" }, nil
for i = 1, 20 do
    if #busy.container.items == 1000 then busy.container.items[1001] = f.item("Base.Paperclip", "Item")
    else table.remove(busy.container.items) end
    local source, _, _, _, item = SC.BaseWork.sortTransfer(churnJob, actor)
    if source then
        f.check(source == later and item == lateMoney, "count churn retains the exact later candidate")
        selectedAt = i; break
    end
end
f.check(selectedAt and selectedAt <= 3, "eight-item round robin reaches later storage despite a large changing first shelf")
f.check(later.container.items[1] == lateMoney and #destination.container.items == 0,
    "fair discovery neither withdraws nor duplicates stock")
base.depositStorageRows = function() return {} end
busy.container.items = { f.item("Base.Paperclip", "Item"), f.item("Base.Paperclip", "Item") }
base.storageRows = function() return { busy } end
local changedJob = { type = "sort" }
local precise = 0
SC.Performance.preciseNowMs = function() precise = precise + 1 return precise end
local _, _, _, _, _, changedWhy = SC.BaseWork.sortTransfer(changedJob, actor)
f.check(changedWhy == "haul_scan_pending", "slow source yields after its first real item")
busy.container.items[3] = f.item("Base.Paperclip", "Item")
for _ = 1, 8 do
    local _, _, _, _, _, reason = SC.BaseWork.sortTransfer(changedJob, actor)
    if reason ~= "haul_scan_pending" then changedWhy = reason; break end
end
f.check(changedWhy == "haul_scan_changed", "a changed unmatched sweep is retryable rather than falsely empty")
SC.Performance = originalPerformance
for key, value in pairs(saved) do base[key] = value end
print("SORTING_SCAN_PASS")
