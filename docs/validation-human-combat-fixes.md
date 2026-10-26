<!-- SPDX-License-Identifier: MIT -->

# Human combat recovery validation

26 October 2026. Unreleased working changes on `living_fellows/0.26.69`, based on `c4f4df4d9ef28b34584c86e1923526a3543096d1`. Target: Project Zomboid 42.21.0, single-player. No version, native bridge or save-schema change.

The review found three faults: human-only threats left retreat without escape candidates, distant Bandits repeatedly preempted treatment despite the companion's engagement rules, and human combat dispatched firearm attacks without reloading or selecting an available weapon fallback.

## Checks

`tests/gameplay/human_combat_regressions.lua` runs inside the existing gameplay integration world, using the production perception, topology, decision, action-supervisor, inventory-index and combat modules. Native action dispatch is recorded by the fixture; it does not simulate a completed physical reload or wound treatment.

Coverage includes:

- Human-only escape discovery through full and reflex perception, Stealth and low-health retreat, mixed human/zombie danger, moving visible humans with cached observations and geometry, dead contacts and quiet-work deferral. Human threats remain outside undead counts.
- Distant Bandits under Close Defense, Ranged Support and Stealth, a real supervised medical transaction, actual attacks on the companion or main player, nearby contacts, zombie pressure, Weapons Free and a direct Retreat order.
- Reload, jam clearance, a loaded firearm attack, compatible ammunition in bags, empty/incompatible magazines, a carried melee fallback, rejected native actions, Hold Fire and immediate shove defense. Dispatch does not create ammunition or change cargo ownership.

The negative controls substitute the original production sources from the base commit while retaining the new tests. Each must fail at its intended assertion: missing human-only escape candidates, a distant Bandit preempting treatment, and an empty gun failing to request a reload. All three controls passed. Logs and the reproduction script are under `build/human-combat-fixes/`.

`scripts/Test-Project.ps1 -Jobs 2` passed all **28 of 28 stages** on the final sources in **187 seconds**, including runtime/build preparation. Both normal and debug compilation passed for all **214 production Lua files**. The gate includes the new gameplay regressions, existing combat/perception/ownership/persistence checks, Bandits source validation, UI, installer transactions and both distribution packages. Final log: `build/human-combat-fixes/project-gate-final.log`. `git diff --check` also passed.

## Limits

These are automated integration checks against the game's Kahlua runtime, not new live-world acceptance. Native shooting accuracy, full Bandits live acceptance, driving return safety and the reported persistent moonwalking remain subject to their existing validation records. This initial review preceded local installation or publication.

The subsequent [shooting and melee follow-up](validation-project-alife.md#shooting-blocker-follow-up) adds native target-model preparation, per-frame ballistic aim and human attack recovery/spacing fixes. It records completed household pistol/bat and ordinary LF pistol acceptance, the rebuilt bridge hash and the later 29-stage gate. The initial review and automated counts above describe the earlier change set.
