-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Base = SC.BaseLife
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "sorting storage " .. checks .. ": " .. message)
end

-- Exercise the real native-count dispatch, not the simplified worker fixture.
local scans, queried = 0, nil
local native = {
    getCountType = function(_, kind) queried = kind; return 30 end,
    getItems = function() scans = scans + 1; error("native count must avoid a Lua item scan") end,
}
local resolve = Base.resolveContainer
Base.resolveContainer = function(storage) return storage.container end
local storage = {container = native, reserve = 4, reserves = {["Base.Money"] = 7}}
check(Base.availableCountExact(storage, "Base.Money") == 23 and queried == "Base.Money" and scans == 0,
    "native full-type count preserves exact reserves without enumerating a shelf")
check(Base.availableCountExact(storage, "Mod.Money") == 26 and queried == "Mod.Money",
    "native count receives the module-qualified type unchanged")
storage.reserves["Base.Money"] = 40
check(Base.availableCountExact(storage, "Base.Money") == 0, "reserve larger than stock never goes negative")
local function item(kind) return {getFullType = function() return kind end} end
storage = {reserve = 1, container = {getItems = function() return {
    item("Base.Money"), item("Base.Money"), item("Mod.Money"),
} end}}
check(Base.availableCountExact(storage, "Base.Money") == 1,
    "containers lacking the native API retain the exact full-type fallback")
check(Base.availableCountExact(storage) == 2, "untyped counts retain the existing fallback and reserve")
storage.container.getCountType=function() error("unqualified names have different native matching rules") end
check(Base.availableCountExact(storage,"Money")==0,
    "unqualified names retain exact-match semantics instead of matching across modules")
Base.resolveContainer = resolve

-- Round-trip through the production document validator/normalizer. Twenty
-- native IDs plus floor-routing history must survive its bounded target copy.
Base.restore(nil)
local square = {getX = function() return 2 end, getY = function() return 2 end, getZ = function() return 0 end}
check(Base.create(square, "Sorting save fixture"), "create a valid production camp")
local base = Base.active()
local ids, failures = {}, {}
for n = 1, 20 do ids[n] = 1000 + n end
for n = 1, 32 do failures["storage:" .. n] = true end
base.jobs = {
    {id = "job:1", type = "sort_floor", state = "pending", assignedId = "worker:1", target = {
        zoneId = "zone:1", floorCargo = {zoneId = "zone:1", itemId = ids[1], x = 2, y = 2, z = 0},
        floorStack = {ids = ids}, failedFloorDestinations = failures,
    }},
    {id = "job:2", type = "sort", state = "pending", assignedId = "worker:1", target = {
        stockBatch = {ids = ids, sourceId = "storage:1", destinationId = "storage:2",
            owner = "worker:1", phase = "deposit", assigned = true},
    }},
}
local doc = Base.export()
doc.nextJobSerial = 3
local restored, reason = Base.restore(doc)
check(restored, "production document restores stack receipts: " .. tostring(reason))
local jobs = Base.active().jobs
check(jobs[1].target and #jobs[1].target.floorStack.ids == 20
    and jobs[1].target.failedFloorDestinations["storage:32"] == true
    and jobs[1].target.floorCargo.itemId == 1001,
    "floor stack and all failed destinations survive normalization together")
check(jobs[2].target and #jobs[2].target.stockBatch.ids == 20
    and jobs[2].target.stockBatch.owner == "worker:1",
    "shelf stack preserves twenty IDs and its owner through production normalization")
SC_TEST_REPORT = "SORTING_STORAGE_PASS checks=" .. checks
print(SC_TEST_REPORT)
