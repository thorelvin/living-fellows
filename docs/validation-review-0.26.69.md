<!-- SPDX-License-Identifier: MIT -->

# 0.26.69 review follow-up

26 October 2026. Code findings 1–3 from `C:/ZOMBOID/review-0.26.69-report.md`, reviewed against `11eb3571` on `living_fellows/0.26.69`. The changes remain in the changelog's Unreleased section; this follow-up keeps the existing version and branch.

## Cornered defence

The no-escape branch in `SCFactionBehavior.updateHumanCombat` previously stopped the actor and returned handled on every tick. With an external human excluded from zombie reflexes, a cornered companion could never defend itself.

When retreat has no destination, a visible human within shove/melee reach or confirmed to be attacking the companion now falls through to ordinary human combat. Distant passive Stealth contacts and unseen threats retain the stationary response. The original escape path, Hold Fire, protected firing lanes, native attack recovery and household pursuit limits still apply.

The gameplay suite exercises both Bandits and A-Life, with no escape candidates and no cached retreat assignment: healthy Stealth and health-30 aggressive actors shove at contact distance; distant passive and unseen attackers do not trigger pursuit. Substituting the reviewed `SCFactionBehavior` fails at the intended cornered-Stealth assertion with `human_retreat_position_unavailable`.

## Optional-mod scan costs

Each adapter retains the dependency-presence result from initialization. Proven absence returns false from `owns` before reading native actor markers or mod data. Reset clears that result. Until initialization, ownership stays conservative so partially initialized humans remain protected. Enabled-but-Off and unsupported integrations retain their human classification.

`external_human_fastpath_harness.lua` runs the real utility, facts cache and both adapters. Its **418 checks** count zero adapter marker/mod-data reads and zero activated-mod queries across repeated ordinary-zombie classification and facts-cache hits in two absent-mod worlds. Enabled partial actors remain human, and changing an ordinary zombie into either kind of NPC takes effect in the same frame, before a cached zombie observation can be reused. The check before the facts cache therefore remains intact.

Substituting both reviewed adapters fails the intended zero-native-read assertion. Both adapters also have explicit Off/classification regressions.

## Native aim metadata

The native actor's lazy `BallisticAccess` holder resolves controller, vector and Bullet members once. It also caches the target-height and weapon-range methods used during aiming. Class resolution avoids initialization, so looking up Bullet metadata cannot start native physics while the bridge loads. Missing members keep the existing fallback path.

The real-game-JAR control verifies the cached members, missing-interface fallbacks, chest/prone heights, native reticle filtering, nested restoration and released-controller ownership. Player identity, slots and cleanup controls pass. A compiled-bytecode audit of nine aiming/model-preparation/restoration methods finds **zero** class or member lookup calls in those paths.

The rebuilt payload bridge is SHA-256 `BAC3AF36859F1A8C74A1DF68F62B2D2BCE6FAA0EA5C5F1BD300F7754121F2AD5`, protocol `42.21-isocompanion-24`. Its source and packaged JAR ship together.

## Evidence

- Focused gameplay, adapter and installed-source suites pass. A-Life: 55 contract, 35 hardening and 928 upstream-source checks. Bandits: 58 contract, 72 hardening and 131 upstream-source checks.
- Negative controls: `build/review-0.26.69/negative-cornered.log` and `negative-absent-mods.log`; reproduction script `Run-NegativeControls.ps1` in the same directory.
- Real-JAR control: `build/review-0.26.69/native-control.log`.
- Bytecode and audit: `build/review-0.26.69/SCNativeCompanion-bytecode.txt` and `ballistic-lookup-audit.log`.
- Full gate: **29 of 29 stages pass in 186.4 seconds** (`build/review-0.26.69/project-gate.log`; 189 seconds including preparation). Includes native isolation and cleanup, both NPC adapters, 215 production Lua files in normal/debug modes, UI, both distributions and installer transactions.

The performance evidence here is counted ownership reads and cached metadata, rather than an FPS estimate. Native pistol and bat acceptance from before this metadata-only refactor remains recorded in [the A-Life validation](validation-project-alife.md).
