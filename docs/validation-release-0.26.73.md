<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.73 checkpoint

28 October 2026. Branch `living_fellows/0.26.73`, based on `ca9ed421`.

This release shortens ordinary follower sitting breaks, interrupts seating
when the leader moves nearby, preserves native standing transitions and adds
read-only rest diagnostics. The companion Status tab now shows live Stamina
and Tiredness percentages directly below Thirst. Unavailable readings show
Unknown; stamina measures remaining endurance and tiredness measures fatigue.

Release metadata is synchronized across VERSION.txt, both mod.info files,
SC.Identity, the READMEs, Workshop description and issue-template example.
The native bridge remains unchanged at protocol `42.21-isocompanion-24`,
with no save schema change.

The final project gate passed **29/29 stages** after the version bump and
Status changes, including 237 payload files compiled in normal and debug
modes, gameplay, UI, compatibility, installer transactions and both release
packages. Evidence: [release gate](../artifacts/emma/native-acceptance/release-0.26.73-gate.log).

The follower policy also passed 51 focused checks and real-game acceptance
before the release-number and Status-only changes. The native run verified
the pause delay, 15-second rest, completed standing, repeat cooldown and
interruption by a nearby walking leader. Its stock furniture object and
screenshot limitations are recorded in the
[follower validation](validation-follower-sitting.md). The existing UI suite
and compiler checks passed; no new live Status screenshot is claimed.

This checkpoint does not install into the player's mod folder or publish to
Steam Workshop. It adds no new expedition-return acceptance; the outstanding
lighting and roadside reunion limits in the
[previous release checkpoint](validation-release-0.26.72.md) remain applicable.
