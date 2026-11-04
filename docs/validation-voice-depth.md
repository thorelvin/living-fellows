<!-- SPDX-License-Identifier: MIT -->

# Voice-depth validation

Date: 2026-11-04. Branch: `feature/voice-depth`, based on published
`living_fellows/0.26.95` at `27057aa6`.
Project Zomboid 42.21.0; native protocol and release metadata unchanged.

## Automated results

- Normal and debug compilation pass for all eight changed client Lua modules.
- The focused Kahlua harness passes 49,494 assertions over 97 target topics and
  1,031 lines. Every personality/mood combination has at least eight eligible
  lines. Raw and clean versions are checked for ASCII, profanity handling,
  duplicates, placeholder completion and the rendered 18-word limit.
- Actual alarm dispatch covers contextual priority, both all-clear outcomes,
  missing-pool fallback, the pure action-owner read, and once-per-patient wound
  calls. Wounds require an awake witness within ten meters, on the same floor
  and with line of sight. A witness does not acquire unheard alarm information.
- Talk dispatch covers 69% versus 67% fatigue, higher-priority medical/food/
  water needs, base duty, physical camp presence, Follow outside camp, cached
  danger and readable fallbacks.
- Disposal covers shared outfit routing, weather/time, the ordinary speech
  chance, actor and party cooldowns, quiet work near threats, 100% milestone
  admission, tally five/ten but not six, body identity receipts, camp switching,
  real camp export/restore and day rollover. Receipt limits retain existing
  camp entries and reject expansion beyond eight camps per body.
- Study covers first and repeated outfit openings, missing-pool fallback,
  day rollover and weight-two night/rain middle candidates. All 23 supported
  outfit groups survive save normalization; invalid keys/time are rejected.
- The existing production harness and full gameplay suite pass against the
  final implementation.
- All 21 mutation controls pass against the final implementation: each of the 17
  new hooks was disabled separately, plus a malformed clean twin or placeholder
  in each of the four areas. Every mutant failed its intended assertion;
  production files retained their original hashes.

## Final project gate

**Passed: 30/30**, `scripts/Test-Project.ps1 -Serial`, exit 0, approximately
764 seconds including the fresh reproducible native bridge build. This covers
core, source/installer, gameplay and mutation controls, navigation, storage,
perception, combat barriers, UI, live-harness static checks, both NPC adapters,
persona controls, Workshop packaging and standalone packaging.

One test chain was used, launched below normal priority; Java was capped at
a 256 MB heap, two active processors and Serial GC.

The earlier standalone core invocation used `-SkipNativeBridge` before this
new worktree had generated its ignored build directory, and stopped at the
missing-build preflight. It did not run core tests. The final gate built the
bridge first and completed core successfully.

The rebuilt and shipped bridge JARs have the same SHA-256:
`142325e87da9c8aa0a4e198d7d995493540f75305678b19fbfc06b71ae1b77c9`.
The installed game runtime passed the pinned 42.21.0 check with JAR SHA-256
`e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33`.

Local evidence: `C:/ZOMBOID/outputs/voice-depth/` (`voice.log`, `production.log`,
`lua.log`, `lua-debug.log`, `negative.log` and `gate-final.log`).

## Scope

No live-game acceptance is claimed for this task. Tests exercise the actual
Lua selectors, speech admission and persistence with deterministic world and
actor fixtures; they do not prove subjective in-game voice variety. No game
session, local installation or guide publication was part of this validation.
