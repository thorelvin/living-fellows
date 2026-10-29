<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.76 checkpoint

29 October 2026. Branch `living_fellows/0.26.76`, based on `6863ee42`.

This checkpoint includes expanded EMMA conversation, bounded short-term topic
memory, live-data follow-ups and clearer name disambiguation. It also retains a
combat approach's proven flank and fixes repeated/overbroad bed discovery.
The [conversation validation](validation-emma-conversation.md) and
[combat investigation](validation-combat-02675.md) describe the exact tests and
their limits, including retained native evidence.

Release metadata is synchronized across VERSION.txt, both mod.info files,
SC.Identity, the READMEs, Workshop description and issue-template example.
The native bridge is unchanged at protocol `42.21-isocompanion-24`, for
Project Zomboid 42.21.0. No save schema change. Bridge SHA-256:
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.

The full project gate passed **29/29 stages after the version bump**, including
244 Lua files compiled in normal and debug modes, gameplay, navigation,
perception, UI, both NPC adapters, ownership/persistence, installer transactions
and Workshop/standalone packaging. Stages took 108.3 seconds; the overall run
took 111 seconds. Evidence:
[release gate](../artifacts/releases/0.26.76/project-gate.txt).
Native acceptance ran before the metadata-only version bump. The retained
combat/search changes passed 29 project stages; twenty native combat trials
and the existing-companion chair-to-bed control have their individual results
in the combat investigation. The tired mallet/wrench trials include partial
clears and do not demonstrate a higher overall kill rate.

Two limitations remain explicit:

- The fresh-actor sleep probe can enter a bed animation but fail the bridge's
  bounded mattress-alignment check. Existing-companion sleep succeeds. The
  failed probe is retained; this checkpoint does not claim to fix that case.
- The previously documented native Lighting64 expedition-return failure has
  no new driving or secondary-to-solo acceptance in this checkpoint.

This request prepares and pushes the Git branch. Local installation and Steam
Workshop publication are separate steps.
