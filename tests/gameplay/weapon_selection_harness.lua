-- SPDX-License-Identifier: MIT
-- Subject scenarios use the same native-shaped fixture as the essential checks.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog = f.makeSquare, f.squares, f.movementLog
SC_WEAPON_SELECTION_REGRESSIONS(f)
print("SUBJECT_PASS checks=" .. tostring(f.checks()))
