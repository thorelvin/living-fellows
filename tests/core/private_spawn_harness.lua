-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local moving = {}
function moving:size() return 0 end
function moving:get() return nil end

local cell = {}
local square = { x = 25, y = 0, z = 0 }
function square:getChunk() return {} end
function square:isSolid() return false end
function square:isSolidTrans() return false end
function square:TreatAsSolidFloor() return true end
function square:isFree() return true end
function square:isSafeToSpawn() return true end
function square:isCanSee() return false end
function square:getMovingObjects() return moving end
function square:getCell() return cell end
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end
function cell:getGridSquare() return square end

local player = {}
function player:getX() return 0 end
function player:getY() return 0 end
function player:getZ() return 0 end
function player:getCell() return cell end
function player:getPlayerNum() return 0 end

SC.Registry = { living = function() return {} end }
SC.Vehicle = { storedCount = function() return 0 end }
local identities = {}
local profiles = {}
local spawnedActors = {}
local bridgeChecks = 0
SC.Actor = {
    checkBridge = function()
        bridgeChecks = bridgeChecks + 1
        return true, "fixture provider ready"
    end,
    spawn = function(_, profile)
        identities[#identities + 1] = profile.identity
        profiles[#profiles + 1] = profile
        local spawned = { identity = profile.identity, x = 12, y = 0, z = 0 }
        function spawned:getX() return self.x end
        function spawned:getY() return self.y end
        function spawned:getZ() return self.z end
        spawnedActors[#spawnedActors + 1] = spawned
        return spawned
    end,
}

check(SC.Config.get("experimentalNpcPlayerActor") == false,
    "unsafe raw IsoPlayer fallback remains disabled")
check(SC.Config.get("debugSpawnEnabled") == true
    and SC.Config.get("debugSpawnIntervalMs") == 60000
    and SC.Config.get("debugSpawnMinDistance") == 8
    and SC.Config.get("debugSpawnMaxDistance") == 15
    and SC.Config.get("debugDiscoveryDistance") == 6,
    "private manual-spawn provider settings and discovery gate are enabled")
local first = SC.Spawn.generateIdentity()
local second = SC.Spawn.generateIdentity()
check(first.forename ~= "" and first.surname ~= "" and first.gender ~= nil
    and type(first.outfit) == "string" and first.outfit ~= "",
    "bounded identity has safe fields")
check(first.forename ~= second.forename or first.surname ~= second.surname,
    "identity generator avoids immediate duplicates")
SC.Spawn.reset()
local deterministic = SC.Spawn.generateIdentity()
SC.Spawn.reset()
local deterministicAgain = SC.Spawn.generateIdentity()
check(deterministic.forename == deterministicAgain.forename
    and deterministic.surname == deterministicAgain.surname
    and deterministic.gender == deterministicAgain.gender,
    "identity fallback is deterministic after reset")

SC.Spawn.reset()
local recoveringRuntime = { active = false, disabledReason = "bridge exposure pending" }
local recovered = SC.Spawn.debugPulse(player, recoveringRuntime, 0)
check(recovered == true and recoveringRuntime.active == true
    and recoveringRuntime.disabledReason == nil and bridgeChecks == 2,
    "debug pulse recovers after delayed native bridge exposure")
SC.Spawn.reset()
local spawnedAtZero = SC.Spawn.debugPulse(player, {}, 0)
local blockedAt59999 = SC.Spawn.debugPulse(player, {}, 59999)
local spawnedAt60000 = SC.Spawn.debugPulse(player, {}, 60000)
check(spawnedAtZero == true and blockedAt59999 == false and spawnedAt60000 == true,
    "manual debug helper retains a bounded cooldown when invoked directly")
check(#identities == 3 and identities[1].forename ~= nil and identities[1].surname ~= nil,
    "generated identity reaches transactional Actor spawn")
check(#profiles == 3 and profiles[1].debugSpawn == true
    and profiles[1].debugDiscovered == false and identities[1].debugSpawn == nil,
    "debug lifecycle provenance reaches Actor without contaminating identity")
local debugRecord = {
    id = "sc-private-debug",
    identity = identities[1],
    runtime = { debugSpawn = true, debugDiscovered = false },
}
SC.Registry.idOf = function(candidate)
    return candidate == spawnedActors[1] and debugRecord.id or nil
end
SC.Registry.byId = function(id)
    return id == debugRecord.id and debugRecord or nil
end
check(SC.Spawn.isDebugActor(spawnedActors[1])
    and SC.Spawn.isDebugProtected(spawnedActors[1]),
    "private actor is protected before player discovery")
local description = SC.Spawn.debugDescription(spawnedActors[1], player)
check(type(description) == "string" and string.find(description, "sc%-private%-debug")
    and string.find(description, "distance=12%.0"),
    "debug diagnostics identify actor, position, and player distance")
check(SC.Spawn.markDebugDiscovered(spawnedActors[1])
    and not SC.Spawn.isDebugProtected(spawnedActors[1]),
    "first discovery releases private despawn protection exactly once")
check(bridgeChecks == 4, "debug pulse checks provider readiness before native spawn attempts")

print("PRIVATE_SPAWN_KAHLUA_PASS checks=" .. tostring(checks))
