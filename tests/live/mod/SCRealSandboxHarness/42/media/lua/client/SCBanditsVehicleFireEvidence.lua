-- SPDX-License-Identifier: MIT
-- Observe unchanged stock bullet/vehicle-part handling; never replay a ray.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local Shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
local call, unpackValues = Shared.call, unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function parts(car)
    local rows, count = {}, call(car, "getPartCount")
    if type(count) ~= "number" or count < 1 or count > 512 then return nil end
    for index = 0, count - 1 do
        local part = call(car, "getPartByIndex", index)
        local id = call(part, "getId")
        if id then rows[id] = { item = call(part, "getInventoryItem"), condition = call(part, "getCondition") } end
    end
    return rows
end
local function observe(f, before, after, stopped)
    f.fireCalls = (f.fireCalls or 0) + 1
    if not before.parts or not after.parts then f.failure = "native vehicle part snapshot unavailable" return end
    for _, value in ipairs({ before.health, after.health, before.requests, after.requests }) do
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            f.failure = "native health/damage receipt snapshot unavailable" return
        end
    end
    if type(before.health) ~= "number" or type(after.health) ~= "number"
        or type(before.requests) ~= "number" or type(after.requests) ~= "number" then
        f.failure = "native health/damage receipt snapshot unavailable" return
    end
    local damaged = {}
    for id, prior in pairs(before.parts) do
        local current = after.parts[id]
        if current and prior.item ~= nil and current.item == prior.item
            and type(prior.condition) == "number" and type(current.condition) == "number"
            and current.condition > 0 and current.condition < prior.condition then damaged[#damaged + 1] = id end
    end
    local protected = stopped == false and #damaged > 0 and before.health == after.health
        and before.requests == after.requests
    if protected then f.vehicleBlocks = (f.vehicleBlocks or 0) + 1 end
    if before.exposed == true and after.health < before.health and after.requests > before.requests
        and after.lastVictim == "lf:" .. tostring(f.id) and after.lastModel == "BulletHit" then
        f.exposedBulletWounds = (f.exposedBulletWounds or 0) + 1
    end
    print("SC_REAL_SANDBOX|VEHICLE_NATIVE_BULLET|stopped=" .. tostring(stopped == false)
        .. "|damaged_parts=" .. table.concat(damaged, ",") .. "|parts=" .. tostring(before.health) .. "->" .. tostring(after.health)
        .. "|requests=" .. tostring(before.requests) .. "->" .. tostring(after.requests)
        .. "|lf_in_square=" .. tostring(before.lfListed) .. "|main_in_square=" .. tostring(before.mainListed)
        .. "|vehicle_blocks=" .. tostring(f.vehicleBlocks or 0)
        .. "|actual_exposed=" .. tostring(before.exposed) .. "|exposed_wounds=" .. tostring(f.exposedBulletWounds or 0))
end
local function listed(actor)
    local square = call(actor, "getSquare")
    local list = call(square, "getMovingObjects")
    if not list then return nil end
    for index = 0, list:size() - 1 do if list:get(index) == actor then return true end end
    return false
end
local function snapshot(f)
    local status = SurvivorCompanion.BanditsAdapter.status()
    return { parts = parts(f.car), health = Shared.partsHealth(f.actor),
        lfListed = listed(f.actor), mainListed = listed(f.primary and f.primary.player),
        requests = status.bulletHits, lastVictim = status.lastVictim, lastModel = status.lastModel }
end
function Probe.cleanup(f)
    f.fireObserving = false
    if f.manageOwner and f.manageOwner.ManageLineOfFire == f.manageWrapper then
        f.manageOwner.ManageLineOfFire = f.manageOriginal
    end
end
function Probe.install(f)
    local owner, original = BanditUtils, BanditUtils and BanditUtils.ManageLineOfFire
    if type(original) ~= "function" then return false, "stock bullet ray unavailable" end
    f.fireObserving, f.vehicleBlocks, f.fireCalls = true, 0, 0
    local wrapper = function(shooter, victim, ...)
        if not f.fireObserving or not f.bandits[shooter] or victim ~= f.actor then return original(shooter, victim, ...) end
        local before = snapshot(f)
        before.exposed = type(f.exposureClear) == "function" and f.exposureClear(shooter) == true
        local values = pack(pcall(original, shooter, victim, ...))
        if not values[1] then
            f.failure = "stock vehicle bullet ray failed: " .. tostring(values[2])
            Probe.cleanup(f)
            error(values[2], 0)
        end
        observe(f, before, snapshot(f), values[2])
        return unpackValues(values, 2, values.n)
    end
    f.manageOwner, f.manageOriginal, f.manageWrapper = owner, original, wrapper
    owner.ManageLineOfFire = wrapper
    return true
end
Probe.parts, Probe.observe = parts, observe
SCRealSandboxHarnessProbes.SCBanditsVehicleFireEvidence = Probe
return Probe
