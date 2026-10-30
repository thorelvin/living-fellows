<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.79 checkpoint

30 October 2026. Branch `living_fellows/0.26.79`, based on `b5f33d1f`.

This release admits native sprite-grid beds that have no chair-seating
positions, including the tested bunk bed. Existing access and geometry checks
still reject blocked or damaged beds. Verified companion inventory transfers
now refresh native container artwork and inventory panes after completion or
settled rollback. The observation harness retains saved player health and
supports longer runs with sleep telemetry.

Metadata is synchronized across VERSION.txt, SC.Identity, both mod.info files,
the READMEs, Workshop description and issue-template example. The native bridge
remains at protocol `42.21-isocompanion-24` for Project Zomboid 42.21.0, SHA256
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.
The bridge binary and save schemas are unchanged.

After the version bump, **all 29 project stages passed in 108 seconds**
(105.3 seconds for the stages), including 244 Lua files compiled normally and
in debug mode, gameplay, native API contracts, persistence, ownership,
navigation, combat, UI, both NPC adapters, packaging and installer transactions.
The container-visual regression has 17 assertions, covering exact transfer,
withdrawal, rollback, duplicate receipts, bags and visual callback failures.
[Release gate](../artifacts/releases/0.26.79/project-gate.txt).

Live checks preceded the metadata-only version bump and used the unchanged
production sleep/storage modules. The standard-bed test passes sleep, wake,
get-up and walking clear. The focused zero-chair-position bunk-bed test passes
native sleep and wake with health/collision retained and no actor recovery.
Screenshots were inspected. A five-minute natural observation started with
near-zero tiredness and produced no sleep. In the 35-minute normal-speed run,
Sanghwa chose a bed at about 32 minutes 32 seconds and recovered from 30.6%
tiredness to 26.4%, remaining asleep at the end. All 3,430 original save files
retained their hashes. See the [investigation and evidence](validation-sleep-storage-02678.md).

The exact playtester camp, 100% exhaustion and a full natural sleep/wake cycle
remain unverified. This does not resolve the previously documented fresh-actor
alignment or expedition-return rendering cases. Shelf refresh is covered by
the regression and native API contract; no live shelf screenshot acceptance
is claimed.

The functional fixes were installed locally under the preceding 0.26.78
identity. This Git release does not reinstall the new version label or publish
to Steam Workshop.
