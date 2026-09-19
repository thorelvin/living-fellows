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

## Attack continuation phase (CB-01)

The audit's blocker was: *"Determine the actual ordering from the installed JAR
and traces; do not assume an event's name proves that it runs before or after
zombie postupdate."* Established from the pinned JAR.

| Fact | Evidence |
|---|---|
| `IsoZombie.postUpdateInternal()` ends with `canSeeTarget = isTargetVisible()` | Bytecode offsets 435-440 |
| It zeroes `targetSeenTime` in the same breath when visibility is lost | Offsets 443-461 |
| `isTargetVisible()` cannot find a companion outside `players[]` | The detached-actor design; the existing adapter already depends on it |
| Lua's `OnTick` fires **after** the world update in the same frame | `IngameState.update()` calls `IsoWorld.update()` at offset 1067 and `onTick()` at offset 1331 |

**The phase was already correct; the cadence was not.** Restoring visibility
from `OnTick` lands after postupdate and is read by the next frame's graph
update, which is exactly right. But the restore was reached through
`serviceRecord`, on the budgeted decision lane: `decisionCriticalIntervalMs` is
50 ms, with capped actors per callback and a 2 ms frame budget, while a frame is
roughly 16 ms. The bit is cleared **every frame** and was restored roughly every
third frame at best — so for most frames the attack graph saw an invisible
target, exited `AttackState`, and the next service asked it to start again.
That re-entry loop is the lunge/bite-start stutter the audit predicted.

**Changed.** `SCBridge.sustainZombieAttack` is the maintenance half on its own:
it revalidates the pair and writes `canSeeTarget` and `targetSeenTime`, and
touches neither the `ActionContext` nor the state machine, so a refresh cannot
re-enter. `startZombieAttack` now builds on it, so both halves share one
eligibility check. `ZombieAttack.sustainPulse` runs that maintenance once per
frame from the runtime tick over a bounded registry of pairs a resolve pass
already validated — never the world, never the zombie list — with entries aged
out by expiry and dropped immediately on a structural refusal.

**Not established by this work:** that the stutter is gone in play. The cause is
proved from the JAR and the mod's own configuration; the *symptom* needs the
live trace the audit's B4 asks for. `SCCombatTrace` exists to capture it:
enable it from the debug tab and the console reports entries per second, with
an explicit `RE-ENTRY STUTTER` marker when the rate says the graph is still
dropping and restarting attacks.

---

## Incoming impact lifecycle (CB-04, CB-05)

Build 42.20.4's zombie attack has a real episode lifecycle, all of it readable:

| Stage | What the engine does |
|---|---|
| `AttackState.enter()` | `attackOutcome = "start"`; clears `AttackDidDamage` and `ZombieBiteDone` |
| `animEvent SetAttackOutcome` | sets `attackOutcome` to `"success"` or `"fail"` |
| `Zombie_Bite_Success` @ 20% | fires `AttackCollisionCheck` |
| the collision handler | resolves the victim as **`zombie.target`**, calls `BodyDamage.AddRandomDamageFromZombie` on it, writes the result into the `AttackDidDamage` variable |
| clip end | `ZombieBiteDone = true` |
| `AttackState.exit()` | clears `AttackOutcome`, `AttackType`, `PlayerHitReaction` |

**The engine's damage path does reach a detached companion.** It looks the
victim up through the zombie's own target, not through the local `players[]`
array. This corrects the module's previous premise. So `AttackDidDamage` being
*present at all* is a receipt that victim processing ran, and its value is the
verdict — which makes "processed, no injury" a real protected result that must
be terminal, not a reason to re-wound.

**The five facts CB-04 asks to separate**, and how each is read:

| Fact | Signal |
|---|---|
| outcome selected | `getAttackOutcome()` → `start` / `success` / `fail` |
| impact emitted | the success clip running past its 20% collision event |
| victim processing executed | `AttackDidDamage` variable **present** |
| defence/protection outcome | present and `false` |
| injury applied | present and `true`, or `getAttackDidDamage()` |

The resolver now produces exactly one terminal receipt per episode:
`native_injury`, `processed_without_injury` and `attack_failed` are terminal
with no fallback; `processing_omitted` (clip finished, no verdict — the
handler's own guards refused) applies the fallback once; and
`processing_unobserved` applies it once after a bounded grace and *says so*,
rather than guessing silently.

**CB-05** is fixed by taking the episode boundary from the engine. `"start"` is
written by `AttackState.enter()`, so it is a true boundary; the old code reset
`swing.resolved` whenever a sampled predicate over target, distance and outcome
went false, in **two** places — the landing check and, more damagingly, the
target-flicker path. A lock that flickered off for one pass reopened a resolved
swing, and the same native episode could wound again once the reswing floor
elapsed. Neither reset remains.

---

## What this file is not

None of the above establishes visual correctness. Clip synchronisation, facing
during a grab, and callback ordering cannot be observed from a JAR. Those remain
the audit's **B4** live-engine requirements.
