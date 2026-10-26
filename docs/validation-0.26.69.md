<!-- SPDX-License-Identifier: MIT -->

# 0.26.69 validation

Date: 26 October 2026. Branch: `living_fellows/0.26.69`. Target: Project Zomboid 42.21.0, single-player.

This release includes the optional Bandits2 adapter, companion firearm input and standing-target aim corrections, human Hold Fire enforcement and right-click storage unmarking. The packaged Lua and native bridge share version 0.26.69; bridge protocol remains `42.21-isocompanion-24`. Save schemas are unchanged.

## Release build

- Rebuilt using Java 17. Packaged bridge SHA-256: `d86dcb1831f29332d6b3e511265877a49c2cc452d88bc68798a55cbe13343194`.
- Comparing the rebuilt release with the preceding `82AC1A73…` candidate found only the version manifest changed. All native class bytes are identical. The comparison is retained in `build/release-0.26.69/bridge-version-comparison.json`.
- `scripts/Test-Project.ps1 -Jobs 2`: **28 of 28 stages passed**, 190 seconds including the runtime/build prologue. This includes native compatibility, ownership, perception, persistence, combat, field work, UI, source hygiene, installer transactions and both distribution packages. Log: `build/release-0.26.69/project-gate.log`.
- Both normal and debug Kahlua compilation passed for all **214 production Lua files**. The adapter suite passed **57 identity/lifecycle checks, 72 hardening checks and 131 checks against the installed original Bandits source**. The storage world-menu suite passed all **18 checks**; UI static contracts passed all **93 tests**.

## Scope and live evidence

The [Bandits validation record](validation-bandits2.md) and [live acceptance ledger](bandits-live-acceptance.md) distinguish source fixtures from completed native scenarios. Ordinary LF shooting with Bandits absent has verified native hits on the same native class bytes; these individual runs do not establish a general accuracy percentage.

Storage's public context-menu tests cover exact container identity, confirmation/cancellation, layouts hidden or visible, disabled deposit/withdrawal permissions, cleanup outside a changed camp boundary, Base Watch edit restrictions, guarded busy-storage rejection and UI refresh. Unmarking calls the existing BaseLife removal API and leaves world containers and contents in place.

Full Bandits live acceptance remains incomplete, including the exposed vehicle-fire transition, sustained mixed-threat defense, exact corpse-content/reload evidence and expedition return scenarios. Existing driving return-safety failures remain open. The reported persistent isometric moonwalking was not reproduced in the available local save and is not claimed fixed; [the facing investigation](investigation-facing-0.26.68.md) records the passive released-build check and the missing affected-session details.

These release preparations do not install the build locally or upload it to Steam Workshop.
