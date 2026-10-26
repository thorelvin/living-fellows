-- SPDX-License-Identifier: MIT
local P, C = ProjectALife, ProjectALife.Combat
P.Reputation.configure({})
P.Perception.configure({})
P.Perception.engineCanSee = function(_, target) return target.visible ~= false end
-- Geometry reads are engine boundaries here. Live acceptance exercises the
-- actual world, line walker, doors and car windows.
P.LineOfFire.hasClearBoundary = function() return ALIFE_SOURCE_WALL ~= true end
P.LineOfFire.roundEdge = function() return ALIFE_SOURCE_WALL ~= true end
C.adapters, C.settings, C.metrics = {}, { bulletPenetration = false }, {}
C.dataOf = function(actor) return actor.md end
C.peekData = C.dataOf
C.nowMs = getTimestampMs
C.weaponFor = function(shell) return shell.weapon end
C.isRanged = function(weapon) return weapon.ranged == true end
C.isUnarmed = function() return false end
C.attackIncapacitated = function() return false end
C.muzzleOnTarget = function() return true end
C.faceTarget = function() end
C.maximumRange = function() return 20 end
C.meleeReachFor = function() return 2 end
C.capForPlayer = function(maximum) return maximum end
C.distanceSquared = function(a, b) return (a.x - b.x)^2 + (a.y - b.y)^2 end
C.clearAttackLine = function() return ALIFE_SOURCE_WALL ~= true end
C.vehicleOnLine = function() return false end
C.consumeRound = function(_, weapon) weapon.ammo = weapon.ammo - 1 return weapon.ammo >= 0 end
C.baseHitChance = function() return 10000 end
C.aimRamp = function() return 1 end
C.aimScaleFor = function() return 1 end
C.rangeFalloff = function() return 1 end
C.reportSound, C.presentShot, C.missCue = function() end, function() end, function() end
C.kindOf = function(body) return body.class == "IsoPlayer" and "player" or "actor" end
C.hitPartIndex = function() return 6 end
C.downedBonus = function() return 1 end
C.targetIsDown = function() return false end
P.Fairness.strikeRefusal = function() return nil end
local P_MAIN = ALIFE_TEST_PLAYER
P_MAIN.x, P_MAIN.y = 15, 5
function P_MAIN:isMoving() return false end
-- A native square list sufficient for the original A-Life line walker.
ALIFE_SOURCE_MOVING = {}
local grid = {}
function getCell() return grid end
function grid:getZombieList() return { size = function() return 0 end } end
function grid:getGridSquare(x, y)
    local moving = ALIFE_SOURCE_MOVING[x .. ":" .. y] or {}
    return { getMovingObjects = function()
        return { size = function() return #moving end, get = function(_, index) return moving[index + 1] end }
    end }
end
