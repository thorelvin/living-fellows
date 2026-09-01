<!-- SPDX-License-Identifier: MIT -->

# Changelog

## 0.22.8 - Reliability playtest candidate

- Added one actor-wide supervisor for movement and timed actions, with explicit ownership, completion, cancellation, retry, rollback, and support evidence.
- Fixed drawn melee weapons failing to swing: the bridge now exposes and verifies Build 42.20.4's native `AttackType`, the action adapter performs the real player attack preflight/authorization, and melee followers safely close the final gap instead of kiting forever.
- Fixed on-foot ranged companions drawing and swinging a melee weapon: the ranged-support doctrine now selects the firearm whether or not the companion is seated, so an approaching zombie no longer flips the pick to melee when the saved weapon priority is stale.
- Fixed companions becoming invisible while still present (visible only on the minimap, "body never returns" after a teleport or chunk reload): the native actor now forces full render opacity each update, since the vanilla visibility fade never raised its alpha. This also keeps the actor fully simulated instead of being throttled toward a near-frozen update rate.
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
