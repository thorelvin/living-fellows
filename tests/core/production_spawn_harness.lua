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

SC.Registry = {
    living = function() return {} end,
    records = function() return {} end,
}
SC.Vehicle = { storedCount = function() return 0 end }
local attempts = 0
SC.Actor = {
    checkBridge = function() return true, "fixture provider ready" end,
    spawn = function(_, profile)
        attempts = attempts + 1
        return { identity = profile.identity }
    end,
}

check(SC.Config.get("debugSpawnEnabled") == false,
    "release regression runs with debug spawning disabled")
check(SC.Config.get("productionEncounterEnabled") == true,
    "normal production encounter cadence is enabled")
SC.Spawn.reset()
local initial = SC.Spawn.productionPulse(player, { active = true }, 0)
local early = SC.Spawn.productionPulse(player, { active = true }, 59999)
local first = SC.Spawn.productionPulse(player, { active = true }, 60000)
local cooldown = SC.Spawn.productionPulse(player, { active = true }, 359999)
local second = SC.Spawn.productionPulse(player, { active = true }, 360000)
check(initial == false and early == false and first == true and cooldown == false and second == true,
    "production encounters honor initial delay and bounded attempt cooldown")
check(attempts == 2, "production cadence reaches real spawn without the debug flag")
local recoveringRuntime = { active = false, disabledReason = "bridge exposure pending" }
local recovered = SC.Spawn.productionPulse(player, recoveringRuntime, 700000)
check(recovered == true and attempts == 3 and recoveringRuntime.active == true
    and recoveringRuntime.disabledReason == nil,
    "production cadence recovers after delayed native bridge exposure")

print("PRODUCTION_SPAWN_KAHLUA_PASS checks=" .. tostring(checks))
