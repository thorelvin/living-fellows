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
function square:getRoom() return self.room end
function cell:getGridSquare() return square end

local player = {}
function player:getX() return 0 end
function player:getY() return 0 end
function player:getZ() return self.z or 0 end
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
do
    local roof = setmetatable({ z = 1 }, { __index = square })
    local originalLookup, originalEncounter = cell.getGridSquare, SC.Encounter
    function cell:getGridSquare(_, _, z) return z == 1 and roof or square end
    SC.Encounter = { chooseSpawnSquare = function() return roof end }
    player.z = 1
    local selected = SC.Spawn.chooseSquare(player, {})
    player.z, cell.getGridSquare, SC.Encounter = nil, originalLookup, originalEncounter
    check(selected == square,
        "final validation rejects an upper-floor roof and fallback samples ground level")
end
do
    local oldNavigation = SC.Navigation
    square.room = { name = "bank" }
    SC.Navigation = { spawnAccessible = function() return false end }
    local sealed = SC.Spawn.chooseSquare(player, {})
    SC.Navigation.spawnAccessible = function() return true end
    local reachable = SC.Spawn.chooseSquare(player, {})
    square.room, SC.Navigation = nil, oldNavigation
    check(sealed == nil and reachable == square,
        "indoor encounters remain valid only when a real exit route can be found")
end
local recoveringRuntime = { active = false, disabledReason = "bridge exposure pending" }
local recovered = SC.Spawn.productionPulse(player, recoveringRuntime, 700000)
check(recovered == true and attempts == 3 and recoveringRuntime.active == true
    and recoveringRuntime.disabledReason == nil,
    "production cadence recovers after delayed native bridge exposure")

check(SC.Config.get("spawnMinDistance") == 50
        and SC.Config.get("spawnMaxDistance") == 110
        and SC.Config.get("encounterDespawnRadius") > 110,
    "production survivors spawn at doubled range without immediate distance despawn")
local recruitedRecords = {}
local stored = 0
SC.Registry.records = function() return recruitedRecords end
SC.Vehicle.storedCount = function() return stored end
local function recruit()
    recruitedRecords[#recruitedRecords + 1] = {
        recruited = true, actor = { isDead = function() return false end },
    }
end
check(SC.Spawn.productionDelayMultiplier() == 1,
    "an empty group retains the sandbox encounter cadence")
for _ = 1, 4 do recruit() end
check(SC.Spawn.productionDelayMultiplier() == 3,
    "four recruited companions triple the encounter delay")
for _ = 5, 8 do recruit() end
check(SC.Spawn.productionDelayMultiplier() == 7,
    "large groups slow new survivor arrivals faster than small groups")
recruitedRecords[8].actor.isDead = function() return true end
recruitedRecords[7].runtime = { inactive = true }
stored = 2
check(SC.Spawn.productionDelayMultiplier() == 7,
    "dead and inactive companions are excluded while vehicle-stored companions count")
stored = 0
while #recruitedRecords > 4 do table.remove(recruitedRecords) end
SC.Spawn.reset()
check(SC.Spawn.productionPulse(player, { active = true }, 1000000) == false
        and SC.Spawn.productionPulse(player, { active = true }, 1179999) == false
        and SC.Spawn.productionPulse(player, { active = true }, 1180000) == true
        and SC.Spawn.productionPulse(player, { active = true }, 2079999) == false
        and SC.Spawn.productionPulse(player, { active = true }, 2080000) == true,
    "recruited-group delay applies after loading and between production attempts")

print("PRODUCTION_SPAWN_KAHLUA_PASS checks=" .. tostring(checks))
