<!-- SPDX-License-Identifier: MIT -->

# Changelog

## 0.22.8 - Reliability playtest candidate

- Added one actor-wide supervisor for movement and timed actions, with explicit ownership, completion, cancellation, retry, rollback, and support evidence.
- Fixed drawn melee weapons failing to swing: the bridge now exposes and verifies Build 42.20.4's native `AttackType`, the action adapter performs the real player attack preflight/authorization, and melee followers safely close the final gap instead of kiting forever.
- Fixed companion (and hostile-faction NPC) melee swings connecting but dealing no damage: Build 42's swing-collision anim event only resolves a hit for the local player, so a non-local actor animated and found targets but never applied damage. The native actor now drives the collision check itself on that event, using the `AttackType` the swing animation carries so the hit passes the engine's stance filter and lands.
- Companions now clear a jammed firearm by racking it (the same action the player's firearm menu uses) before firing or reloading, instead of standing on a dead gun. Verified end to end alongside firing, magazine reloads, and reusing a reloaded weapon.
- Restricted the "catch up to the player" chunk-unload recovery to following companions. A companion set to stay, guard, or base duty is no longer teleported across the map when the player walks out of range; its record is kept intact so it reloads at its post when the player returns.
- Fixed a teleport-recovered companion appearing to vanish: it still showed on the minimap, could be looted, and drew zombies to its tile, but stood invisible and never moved. The recovery restored the actor's square and render model but never returned it to the cell object list the update scheduler iterates, so it was never ticked (which also let its render alpha fade out). Recovery now reschedules the actor, so it moves and stays visible immediately after a teleport.
- Fixed zombies ignoring companions — following them but never biting. Build 42's zombie vision only scans the local `players[]` array, so a detached companion is never "seen": its target-lock decayed every frame (the zombie just walked toward it) and, even when a swing resolved, the bite is written by the victim's local-player-gated processing that never runs for a non-local actor. Companions now refresh the same seen-flesh timer continuous vision keeps (holding the lock without altering zombie AI) and take real BodyDamage wounds from a landed attack — bites can infect and turn them, while scratches and lacerations wound and bleed without infecting.
- Added zombie pull-downs: when enough zombies pile onto a companion at once, they can grab and drag it to the ground (resisted by the companion's traits), pinning it while it is torn at. There is a grace window to save a downed companion — thin the swarm and it is freed, bloodied but alive; leave it and the pack drags it down for good.
- Fixed on-foot ranged companions drawing and swinging a melee weapon: the ranged-support doctrine now selects the firearm whether or not the companion is seated, so an approaching zombie no longer flips the pick to melee when the saved weapon priority is stale.
- Fixed companions becoming invisible while still present (visible only on the minimap, "body never returns" after a teleport or chunk reload): the native actor now forces full render opacity each update, since the vanilla visibility fade never raised its alpha.
- Fixed companions being under-simulated and, when stationary, effectively frozen (idle animations, attacks that started but never landed, "just standing there doing nothing"): a manually constructed non-local actor was only placed in the cell's deferred add list, so Build 42's update scheduler stopped ticking it. The runtime now keeps every live companion in the cell object list each frame, so they are simulated like normal characters and melee swings resolve their hit.
- Made medical care, downtime, scavenging, logistics, vehicle seating, equipment, and loadout changes transactional instead of applying partial effects.
- Hardened navigation recovery with bounded retries, temporary failed-edge blacklists, native blocker classification, and detailed recovery evidence.
- Made bootstrap hooks, runtime startup/reset, registry writes, return-tuple handling, and mutable record ownership transactional and idempotent.
- Replaced partial save copies with strict path-aware copies. Uncopyable envelopes block overwrite, while copyable invalid records and failed subsystem documents remain quarantined and recoverable without losing their untouched raw value.
- Added bounded restore backoff and manual retry for deterministic incompatibilities.
- Kept failed native cleanup actors reachable and retryable, and hard-gated every reflection-dependent Build 42.20.4 method before spawning.
- Rebuilt local/native installation as one hash-verified transaction with rollback at every commit boundary and safe refusal of ambiguous legacy launcher state.
- Unified configuration views, provider identifiers, scheduler metrics, faction limits, Java/Lua list access, and checked transaction helpers.
- Bounded the dynamic perception cache with incremental expiry sweeping, and added source-only CI plus a trusted real-JAR compatibility workflow.

## 0.22.7 - Public playtest candidate

- Added capability-aware combat readiness using injuries, endurance, panic, pain, fatigue, stress, morale, carry load, skills, weapon quality, support, threat directions, footing, and escape quality.
- Improved target distribution, stamina preservation, side/rear threat priority, shove-and-ground decisions, melee spacing, kiting, and retreat selection.
- Added deliberate firearm sight-picture timing without delaying immediate defensive fire.
- Hardened movement ownership, choke-point reservations, native path telemetry, obstacle memory, stuck recovery, escape priority, and Copy player movement.
- Expanded varied, situational English dialogue and combat calls with safe cadence and real sound consequences.
- Added persistent households, faction relations, contracts, recruitment trials, living bases, grief, personality, and transactional save schema 2.
- Added the public standalone Windows package with reversible `Install.bat` and `Uninstall.bat` support. The installer never modifies `projectzomboid.jar` and verifies launcher rollback in an isolated build test.
- Retained Steam Workshop support through ZombieBuddy 2.3.3 or newer.

Earlier implementation history and subsystem-level changes remain documented in [SurvivorCompanion/README.txt](SurvivorCompanion/README.txt).
