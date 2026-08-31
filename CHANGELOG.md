<!-- SPDX-License-Identifier: MIT -->

# Changelog

## 0.22.8 - Reliability playtest candidate

- Added one actor-wide supervisor for movement and timed actions, with explicit ownership, completion, cancellation, retry, rollback, and support evidence.
- Made medical care, downtime, scavenging, logistics, vehicle seating, equipment, and loadout changes transactional instead of applying partial effects.
- Hardened navigation recovery with bounded retries, temporary failed-edge blacklists, native blocker classification, and detailed recovery evidence.
- Made bootstrap hooks, runtime startup/reset, registry writes, return-tuple handling, and mutable record ownership transactional and idempotent.
- Replaced partial save copies with strict path-aware copies. Invalid records and failed subsystem documents remain quarantined and recoverable instead of disappearing on the next save.
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
