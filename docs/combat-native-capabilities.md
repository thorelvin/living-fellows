<!-- SPDX-License-Identifier: MIT -->

# Combat: native capability matrix

Evidence for the combat audit's blocker **B2** ("inspect native behaviour, not
just method existence"). Everything below was established against the pinned
runtime, by disassembling and reflecting on the installed
`projectzomboid.jar` — not from documentation or method names.

**Runtime inspected:** Project Zomboid 42.20.4,
`C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\projectzomboid.jar`
(64,514,905 bytes, the hash pinned in the runtime manifest).
**Date:** 18 September 2026.

Status values are the audit's: **available** (present and its behaviour is
established), **semantics-unverified** (present, behaviour not established),
**absent**.

---

## Wound application (CB-08)

| Capability | Status | Evidence |
|---|---|---|
| `BodyPart.setScratched(boolean, boolean)` | **available** | Second argument is **`forceNoInfection`**, not a weapon flag. Bytecode: `iload_2; ifne <return>` guards `invokevirtual generateZombieInfection:(I)V` with literal `7`. Passing `false` therefore rolls a 7% Knox infection. |
| `BodyPart.setCut(boolean)` | **available** | Delegates to `setCut(z, true)`, so the one-argument form never infects. |
| `BodyPart.setCut(boolean, boolean)` | **available** | Second argument is also `forceNoInfection`: the same `iload_2; ifne` guard wraps `generateZombieInfection`. |
| `BodyPart.generateZombieInfection(int)` | **available** | `Rand.Next(100) < arg` sets `isInfected`, then honours `SandboxOptions.lore.transmission` (cleared for values 2 and 4) and converts to `isFakeInfected` when `mortality == 7`. |
| `BodyPart.setDeepWounded(boolean)` | **available** | A distinct, more severe injury than a cut. Not the correct mapping for a laceration. |
| `BodyPart.setWoundInfectionLevel(float)` | **available** | Independent of the infection roll; this is the field restore should write. |

**Consequence:** both `SCZombieAttack.applyWound` and `SCVitals.applyPart`
passed `false`, so scratches infected on application *and* re-rolled infection
on every vitals restore. Fixed; regressions added in the gameplay and core
harnesses, each negative-control verified.

---

## Paired grapple lifecycle (CB-03)

The audit asked whether a real native grapple exists and is reachable from a
non-local companion. **It does, and it is.**

`zombie.core.skinnedmodel.IGrappleable` is a complete paired lifecycle, and
`IsoGameCharacter implements IGrappleableWrapper`, which supplies public
default implementations. `IsoZombie` is grapple-capable on the other side.

Resolved by reflection on `zombie.characters.IsoPlayer`:

| Method | Status | Returns |
|---|---|---|
| `isBeingGrappled()` | **available** | `boolean` |
| `isBeingGrappledBy(IGrappleable)` | **available** | `boolean` |
| `getGrappledBy()` | **available** | `IGrappleable` |
| `getGrappledByType()` | **available** | `String` |
| `isGrappling()` / `isGrapplingTarget(...)` / `getGrapplingTarget()` | **available** | pair from the attacker's side |
| `canBeGrappled()` | **available** | `boolean` |
| `isPerformingGrappleGrabAnimation()` | **available** | `boolean` |
| `isPerformingAnyGrappleAnimation()` | **available** | `boolean` |
| `getGrappleResult()` | **available** | `String` |
| `Grappled(...)` / `AcceptGrapple` / `RejectGrapple` / `LetGoOfGrappled` / `GrapplerLetGo` | **semantics-unverified** | declared on the interface; entry/exit behaviour for a *non-local* actor has not been exercised |
| `resetGrappleStateToDefault(String)` | **semantics-unverified** | not exercised |

Native states that exist alongside it:
`GrappledThrownIntoContainerState`, `GrappledThrownOutWindowState`,
`GrappledThrownOverFenceState`.

**What changed so far:** reading the pair is now done from the engine
(`ZombieAttack.nativeGrapple`), `isGrabbed` reports `native` or `synthetic`
rather than conflating them, and the synthetic pin **stands down entirely**
while a native pair is held so the two damage authorities can never run
concurrently. The synthetic fallback is retained, as the audit requires, until
a native replacement can demonstrably hurt and release a non-local victim.

**Not yet done:** driving entry/exit through the native API (W4). That needs the
`semantics-unverified` rows above exercised in a running game.

---

## Reaction states and root motion (CB-02)

Player-side reaction states present in the runtime:

```
PlayerHitReactionState      PlayerHitReactionPVPState   StaggerBackState
PlayerFallDownState         PlayerFallingState          PlayerGetUpState
PlayerOnGroundState         PlayerSitOnGroundState
```

### How the engine actually applies root motion

`IsoPlayer.updateInternal2()` calls `doDeferredMovement()` **unconditionally** —
there is no state guard at the call site. The method guards itself:

| Guard, in order | Effect |
|---|---|
| `hasAnimationPlayer()` | returns if absent |
| `GameClient.client` + `HitReactionNetworkAI` branches | multiplayer only |
| `isAnimationUpdatingThisFrame()` | returns if not — this is the engine's own "exactly once per simulation step" |
| `getPath2() != null`, not a climb state | reconciles against the path, or returns without applying |
| `WalkTowardState` | clamps root motion to the path-follow vector |
| `GameClient.client` block (offsets 262–468) | **entirely skipped in single-player** |
| `isGrappling() \|\| isBeingGrappled()` | **adds `getGrappleOffset()` to the movement vector** |

Two conclusions, both from the pinned JAR:

1. **The engine already prevents double application.** Path-owned movement is
   reconciled inside `doDeferredMovement`, which is why vanilla can call it
   unconditionally. The bridge's traversal-only allowlist re-implements that
   decision more narrowly and discards reaction displacement as a side effect.
2. **A grapple needs the accumulator.** `getGrappleOffset()` is what holds a
   grappled victim in position against its grappler. Discarding it during a
   grapple pulls the paired animation apart: the clip plays while the collision
   body stays put.

The multiplayer block, although skipped in single-player, is still evidence of
engine intent: it is an allowlist of states where root motion *is* applied for
a remote zombie, and it names `StaggerBackState`, `ZombieHitReactionState`,
`ZombieFallDownState`, `ZombieFallingState` and `ZombieOnGroundState`. The
non-local **player** list in the same block is narrower —
`CollideWithWallState`, `PlayerGetUpState`, `BumpedState`.

| Question | Status |
|---|---|
| The reaction states exist and are distinguishable | **available** |
| `doDeferredMovement()` is self-guarding and safe to call while a grapple holds | **available** |
| Grapple offset requires the accumulator | **available** |
| Which *reaction* states (hit, stagger, falldown) need it for a non-local companion in single-player | **available** |

**Done (W2, CB-02 closed).** `SCNativeCompanion.getCompanionMovementOwner()` is
now the single coherent answer to who owns the companion's body this frame,
ordered `grapple > reaction > traversal > attack > tactical > manual > path`.
Root-motion consumption, path advancement, manual movement, aim and
movement-facing all consult it, so they can no longer disagree.

The doubling concern that blocked this is resolved rather than accepted: while
an exclusive native owner holds the actor, `advanceBridgePath()` and
`applyBridgeMovement()` both stand down, so the engine's root motion is the
*only* displacement applied. That is what makes applying it correct instead of
a second translation.

The reaction set is ten exact state names, matched whole:
`PlayerHitReactionState`, `PlayerHitReactionPVPState`, `StaggerBackState`,
`PlayerFallDownState`, `PlayerFallingState`, `PlayerGetUpState`,
`PlayerOnGroundState`, `PlayerSitOnGroundState`, `BumpedState`,
`CollideWithWallState`. `SCNativeApiSignatureTest` resolves every one against
the installed game, so a rename cannot quietly turn the classifier into one
that matches nothing.

**Verified in `SCIsoCompanionControlTest.testNativeReactionOwnership`,** which
drives the real state instances: root motion translates the body in each
reaction, path advancement and a stale combat target are both refused, child
states are recognised, a reaction outranks traversal, and the classifier
rejects near-miss names. Root motion, path and facing were each
negative-control verified.

**Explicitly not verified:** manual-movement gating.
`isCompanionMovementClear()` refuses every direction in the control-test world,
so `applyBridgeMovement` cannot translate the actor whether or not the gate
exists — an assertion there would pass for the wrong reason. The test records
this as a skip and *fails if the harness world ever becomes walkable*, rather
than claiming coverage it does not have. The gate is the same `nativeOwnsBody()`
call proven for the other three paths.

---

## What this file is not

None of the above establishes visual correctness. Clip synchronisation, facing
during a grab, and callback ordering cannot be observed from a JAR. Those remain
the audit's **B4** live-engine requirements.
