<!-- SPDX-License-Identifier: MIT -->

# Navigation: why companions did not feel hedges

Root-cause record for the foliage observation in the 0.24.0 playtest.
Everything below was established against the pinned runtime, by disassembling
the installed `projectzomboid.jar` and by reading the game's own tile
definitions and animation sets — not from documentation or method names.

**Runtime inspected:** Project Zomboid 42.20.4,
`C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\projectzomboid.jar`
(64,514,905 bytes, the hash pinned in the runtime manifest).
**Date:** 19 September 2026.

---

## The observation

> "Tyreese ran thru a hedge i had to slow walk thru. So they dont detect these."

The player is slowed to a push-through walk by a hedge. The companion crossed
the same tile without losing a step.

## How a hedge slows the player

A hedge is not an obstacle the engine tests against. It is a property on the
square, and the whole effect is animation-owned.

**1. The tile declares itself.** The `f_bushes_2_*` tiles in
`media/newtiledefinitions.tiles` and `media/tiledefinitions_erosion.tiles`
carry `Movement=HedgeLow` or `Movement=HedgeHigh` alongside `Bush` and
`MoveType=Vegitation`.

**2. The character reads that property.**
`IsoGameCharacter.isInTrees2(boolean)` fetches
`getCurrentSquare().getProperties().get("Movement")` and returns true for
`HedgeLow` or `HedgeHigh`, case-insensitively. A tree square qualifies too,
but only above size 2. `isInTreesNoBush()` is `isInTrees2(true)`.

**3. That answer is an animation variable.**
`IsoGameCharacter.registerVariableCallbacks()` registers `intrees` as a
**read-only callback bound directly to `isInTreesNoBush`** (bootstrap method 43
resolves to `REF_invokeVirtual IsoGameCharacter.isInTreesNoBush:()Z`). There is
no setter and no local-player gate: the variable is correct for any character,
companions included.

**4. The state machine swaps the clip.**
`AnimSets/player/movement/inTrees.xml` and `AnimSets/player/run/inTrees.xml`
require `intrees == true` and play `Bob_WalkTrees` / `Bob_RunTrees`, scaled by
the `WalkSpeedTrees` variable.

**5. The clip is the speed.** `PathFindBehavior2.moveToPoint` sizes each step
from `IsoGameCharacter.getDeferredMovement()` — the active clip's own root
motion — and applies it with `moveUnmodded`. A slower clip *is* a slower
character. Nothing multiplies a distance by a "hedge factor" anywhere in the
engine.

## Why the companion was immune

The companion is not immune to steps 1–4. It is immune to step 5.

`SCNativeCompanion` deliberately omits `IsoPlayer.updateInternal2()`, the
local-input update. Engine-path movement still runs through
`PathFindState` → `PathFindBehavior2`, so **a companion on an engine path was
already slowed correctly**. But most companion movement is a *direct* step:
`SCNativeActions.directMove` sends a fixed per-frame distance
(`walkDistance = 0.045`, `runDistance = 0.075` in `SCConfig.lua`) through
`MoveForward`, which `applyBridgeMovement` applies from the update window.
Nothing between the Lua decision and the physics body consulted the animation,
so terrain had no effect on it at all — not hedges, not trees.

`consumeBridgeDeferredMovement()` discards the root-motion accumulator for
ordinary locomotion (it is applied only while a native traversal or reaction
state owns the body), so the slower clip could not reach the body by that route
either.

Two smaller findings along the way, both dead ends worth recording so they are
not re-investigated:

- `IsoGameCharacter.slowFactor` is **not** the foliage mechanism. Only
  `AttackState`, `IsoGameCharacter` itself and `SlowFactorPacket` reference
  `setSlowFactor`; it is the combat/grapple slow.
- `WalkSpeedTrees` is set only in `IsoPlayer.updateInternal2()`, so a companion
  never has it. That is harmless: `AnimNode.getSpeedScale` falls back to
  `getVariableFloat(name, 1.0f)`, and `calculateInTreesSpeed()` returns 1.0 for
  anyone who is not a Park Ranger or Lumberjack.

## The fix

`SCNativeCompanion.foliageSpeedFactor` scales the distance of a **direct** step
only. `applyBridgeMovement` is its single caller, it stands down while a native
state owns the body, and engine-path movement never reaches it — so nothing is
slowed twice.

| square | factor |
|---|---|
| not `isInTreesNoBush()` | 1.0 |
| tree | `IsoTree.getSlowFactor(this)` — 0.8 for a sapling, 0.5 for a full tree, including the Park Ranger (×1.5) and Lumberjack (×1.2) bonuses |
| hedge or tall bush | `FOLIAGE_SLOW_FACTOR` = 0.5, the engine's own strongest foliage slow |

The factor is clamped to `(0, 1]`: foliage may never speed a companion up, and
a broken factor must never strand one inside a hedge.

Route choice was wrong for a second, independent reason.
`SCNavigation.squareHasBush` scanned a square's objects for the `canBeCut`
sprite flag, which no hedge tile carries — so `navigationBushPenalty` never
fired on one and the router had no reason to go around. It now asks the engine
first (`IsoGridSquare:hasBush()`), then checks the square's `Movement` property
for `HedgeLow`/`HedgeHigh`, and only then falls back to the object sweep.

## Coverage

- `SCIsoCompanionControlTest` — `foliageSpeedFactor` across open ground, hedge,
  sapling, a profession bonus above 1.0, an unusable tree factor and a broken
  hedge factor, plus proof that the factor actually shortens a bounded step.
  Verified by negative control: forcing the factor to 1.0 fails the suite.
- `gameplay_harness.lua` — a hedge declared only by its `Movement` property, and
  vegetation reported only by the engine's `hasBush()`, are both detoured
  around. Verified by negative control, and the hedge case asserts the same
  route crosses those squares before the property is applied.
- `SCRealSandboxHarness` — `native_foliage_slows_direct_step` finds a real
  loaded hedge square, places the companion on it and reads the engine's own
  `isInTreesNoBush()` and the applied factor back out of the running game.
