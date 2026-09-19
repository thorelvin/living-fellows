<!-- SPDX-License-Identifier: MIT -->

# Navigation: why companions could not climb

Root-cause record for the fence/wall disengagement observed in the 0.22.35
playtest. Everything below was established against the pinned runtime, by
disassembling the installed `projectzomboid.jar` and by reading the engine's own
`DebugLog` output from that session — not from documentation or method names.

**Runtime inspected:** Project Zomboid 42.20.4,
`C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\projectzomboid.jar`
(64,514,905 bytes, the hash pinned in the runtime manifest).
**Session inspected:** the 0.22.35 playtest console log.
**Date:** 18 September 2026.

---

## The observation

Companions walked the length of a fence, attempting and failing to cross it,
for an entire session. Every combat decision downstream of it was `retreat` or
`escape`.

```
16  type=fence    reason=traversal_exited_without_destination
16  type=unknown  reason=native_path_failed
```

Each blocker line carried `anim=Bob_ClimbFence_Fail`. The companion's position
after each attempt was roughly one tile back from the portal
(`portal=-0.94/0.02`): it started the climb, failed, and was returned to the
near side.

## The engine's own verdict

`ClimbOverWallState.setParams` logs its roll. The session contains both the
player's and the companions':

| `ClimbWall failure chance 1 in N` | count | successes |
|---|---|---|
| `1 in 4` (the player) | 2 | 1 |
| `1 in 0` (companions) | 40 | **0** |

Forty companion wall-climbs, zero successes. Not bad luck — a certainty.

## Why the score was 0

`IsoGameCharacter.getClimbingFailChanceFloat()` is, from the bytecode:

```
c = 2*Fitness + 2*Strength + 2*Nimble
    - 5*ENDURANCE - 8*DRUNK - 8*HEAVY_LOAD - 5*PAIN
    (obese -25 / overweight -15; clumsy halves; awkward gloves halve, plain
     gloves +4; all-thumbs -4 / dextrous +4; burglar +4; gymnast +4)
    + nearbyZombieClimbPenalty()
return (int) sqrt(max(0, c))
```

The name is misleading: it is a *capability* score, used as a 1-in-N chance of
failing. The player's logged `4` is exactly `int(sqrt(2*5 + 2*5 + 2*0))` — the
Strength 5 / Fitness 5 every Build 42 character receives at creation. The
companions' `0` means they had none of it.

## Why a 0 score is fatal rather than merely unlucky

`ClimbOverWallState.setParams`, offsets 289–388:

```java
boolean success = false;
if (failChance > 0) {
    success = !Rand.NextBool(failChance);
} else if (moodles.getMoodleLevel(HEAVY_LOAD) == 0) {
    int strength = Math.max(1, getPerkLevel(Strength));
    DebugLog.log("ClimbWall bonus " + (strength + 1) + " of success when base chance is 0 when encumbered");
    success = Rand.Next(100) <= strength;
}
player.setClimbOverWallSuccess(success);
```

With a score of 0 and no heavy load, success is `Rand.Next(100) <= 1` — 2%.
With a score of 0 **and** any heavy-load moodle, success is unreachable.

That `bonus …` line appears **zero times** in the session's 40 companion
climbs, which is decisive: the companions were encumbered every single time, so
they took the branch that can only ever produce `false`.

Both halves of that trap were self-inflicted, and the first caused the second:
vanilla carry capacity scales with Strength, so a Strength 0 companion is
encumbered by a load a Strength 5 one carries comfortably.

## Where the missing perks came from

`SCBackground.applySkills` computed its baseline **inside** the loop over the
background's skill map:

```lua
for name, boost in pairs(skills) do
    local baseline = (name == "Strength" or name == "Fitness") and 5 or 0
    targets[name] = math.max(targets[name] or 0, clamp(baseline + boost, 0, 10))
end
```

So the vanilla baseline was applied only to a perk the profession already
boosted. **24 of the 31 backgrounds name neither Strength nor Fitness**, and
only 2 name both — so most companions spawned at 0/0 while every player starts
at 5/5. Climbing is the loudest symptom; the same two perks also drive carry
capacity, melee damage and endurance.

`SCPersistence.applySkills` then replayed the saved 0 over the top on restore,
so the defect survived a reload even once spawning was corrected.

## What changed

| Change | File |
|---|---|
| Seed the vanilla passive baseline before merging the background's boosts, so a background that names neither perk still spawns at Strength 5 / Fitness 5 | `SCBackground.lua` |
| Never let restore lower a passive perk below the level spawn seeded; earned progress above it still restores exactly | `SCPersistence.lua` |
| Escalate the blocked-edge hold after repeated exits-without-arrival, so a companion that genuinely cannot cross abandons the fence line instead of walking it | `SCNavigation.lua`, `SCConfig.lua` |

Each has a deterministic harness regression, and each regression was
negative-control verified by reverting the fix and confirming the test fails.

The third change matters independently of the first two: a climb is scored from
the **actor**, so retrying the neighbouring panel can never help. A companion
that is legitimately exhausted or overloaded must stop and route around, which
is what the escalation now forces.

## What this does not establish

The expected post-fix success rate is `1 - 1/4` ≈ 75% per attempt for an
unencumbered companion at the baseline, and a heavily overloaded companion will
still be unable to climb — that is vanilla's rule, and the correct answer there
is to shed weight, not to bypass the engine. Neither has been observed in play
yet.
