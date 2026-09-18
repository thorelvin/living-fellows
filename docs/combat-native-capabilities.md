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

| Question | Status |
|---|---|
| The states exist and are distinguishable | **available** |
| Which of them require root motion to be applied, and in which phase | **semantics-unverified** |
| Whether `doDeferredMovement()` is safe to call during each | **semantics-unverified** |

`SCNativeCompanion.consumeBridgeDeferredMovement()` currently applies root
motion **only** during verified traversal and discards the accumulator
otherwise, so any reaction needing displacement gets none. Extending that
allowlist is W2, and it is deliberately **not** done here: guessing which states
consume root motion risks applying displacement twice, which is worse than the
current under-application. The state list above narrows the question; a live
trace has to answer it.

---

## What this file is not

None of the above establishes visual correctness. Clip synchronisation, facing
during a grab, and callback ordering cannot be observed from a JAR. Those remain
the audit's **B4** live-engine requirements.
