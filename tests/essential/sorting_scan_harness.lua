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
    return row.container, row.container.owner
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
local withdrawnJob = { type = "sort" }
SC.BaseWork.sortTransfer(withdrawnJob, actor)
local removed = table.remove(sources, 3)
local finished
for _ = 1, 100 do
    local source, _, _, _, _, why = SC.BaseWork.sortTransfer(withdrawnJob, actor)
    f.check(source == nil, "a resumed scan cannot select an unmarked storage")
    if why ~= "haul_scan_pending" then finished = why break end
end
f.check(finished == "no_sortable_supply" and #removed.container.items == 66,
    "removing a source invalidates its pending scan without touching its stock")
for key, value in pairs(saved) do base[key] = value end
print("SORTING_SCAN_PASS")
