-- SPDX-License-Identifier: MIT
-- Distinct subject regressions retained from the former gameplay monolith.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog, squareKey = f.makeSquare, f.squares, f.movementLog, f.squareKey
function SurvivorCompanion.__testSafeVehiclePolicyExit()
    local previousVehicleAdapter = SurvivorCompanion.Vehicle
    local previousMedicalAdapter = SurvivorCompanion.Medical
    local previousSensesAdapter = SurvivorCompanion.Senses
    local safeExitVehicle = { speed = 30 }
    SurvivorCompanion.Vehicle = {
        isStationary = function(candidate)
            return candidate.speed <= 0.5,
                candidate.speed <= 0.5 and nil or "vehicle is moving"
        end,
    }
    SurvivorCompanion.Medical = {
        assess = function()
            return { health = 100, alive = true, critical = false,
                needsBandage = false, downed = false, bleedingCount = 0 }
        end,
    }
    SurvivorCompanion.Senses = {
        snapshot = function()
            return { threats = {}, threatCount = 0, immediateCount = 0,
                escapeSquares = {}, allies = {}, sounds = {}, player = { danger = 0 } }
        end,
    }
    local safeExitActor = actor("sc-decision-safe-exit", -6, -2, {})
    local safeExitPlayer = actor("sc-decision-safe-player", -6, -1, {
        recruited = false, body = bodyDamage(100),
    })
    safeExitPlayer.modData.SC_Recruited = false
    registry[safeExitActor.id] = safeExitActor
    safeExitActor.vehicle = safeExitVehicle
    safeExitPlayer.vehicle = safeExitVehicle
    check(SurvivorCompanion.Commands.issue(safeExitActor.id, "stay", nil, safeExitPlayer)
            and SurvivorCompanion.Commands.issue(safeExitActor.id, "set_ride_with_player",
                { enabled = false }, safeExitPlayer),
        "Ride with player can be disabled while a non-following companion is seated")
    local safeExitRuntime = {
        snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
            escapeSquares = {}, allies = {}, player = { danger = 0 } },
    }
    local movingHandled = false
    for _ = 1, 5 do
        movingHandled = SurvivorCompanion.Decision.update(safeExitActor, safeExitPlayer, safeExitRuntime)
        if SurvivorCompanion.Decision.peek(safeExitActor).intent == "waiting_for_safe_exit" then break end
        f.clock = f.clock + 301
    end
    check(movingHandled and safeExitActor.lastIntent == nil
            and SurvivorCompanion.Decision.peek(safeExitActor).intent == "waiting_for_safe_exit",
        "disabling Ride while moving waits without issuing an unsafe exit: handled="
            .. tostring(movingHandled) .. " action="
            .. tostring(safeExitActor.lastIntent and safeExitActor.lastIntent.action)
            .. " intent=" .. tostring(SurvivorCompanion.Decision.peek(safeExitActor).intent))
    safeExitVehicle.speed = 0
    local stoppedHandled = false
    for _ = 1, 5 do
        f.clock = f.clock + 301
        stoppedHandled = SurvivorCompanion.Decision.update(safeExitActor, safeExitPlayer, safeExitRuntime)
        if safeExitActor.lastIntent and safeExitActor.lastIntent.action == "exit_vehicle" then break end
    end
    check(stoppedHandled and safeExitActor.lastIntent
            and safeExitActor.lastIntent.action == "exit_vehicle",
        "the disabled Ride policy exits automatically once the vehicle is stationary")
    safeExitPlayer.vehicle = nil
    registry[safeExitActor.id] = nil
    SurvivorCompanion.Decision.reset(safeExitActor)
    SurvivorCompanion.Commands.reset(safeExitActor)
    SurvivorCompanion.Vehicle = previousVehicleAdapter
    SurvivorCompanion.Medical = previousMedicalAdapter
    SurvivorCompanion.Senses = previousSensesAdapter
end
SurvivorCompanion.__testSafeVehiclePolicyExit()
SurvivorCompanion.__testSafeVehiclePolicyExit = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
