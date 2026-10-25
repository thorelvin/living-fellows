<!-- SPDX-License-Identifier: MIT -->

# 0.26.68 validation

Date: 25 October 2026. Branch: `living_fellows/0.26.68`. Target: Project Zomboid 42.21.0, single-player.

The expedition watchdog preserves a live ordered-move path search within its existing thirty-second waypoint allowance. Ordinary stalled movement still recovers after eight seconds. The private driving probe reads passive action history, records navigation and car failures, allows a longer observation budget without extending the mission timer, and fails immediately on crew death.

## Automated checks

- `scripts/Test-Project.ps1 -Jobs 2`: **27 of 27 stages passed**, 193 seconds total. This includes actual-runtime Kahlua execution, native compatibility, navigation and storage regressions, UI checks, live-harness fixture checks, Workshop and standalone packaging, and installer transactions. Log: `build/release-0.26.68/project-gate.log`.
- Release metadata agrees across `VERSION.txt`, Lua, mod descriptors, documentation and the rebuilt Java 17 bridge. Protocol remains `42.21-isocompanion-24`; save schemas are unchanged.
- Bridge SHA-256: `90c8a0dffd0179c5acb403258d43c9be8dea182b1783c8584ea9ef22b86ddacc`. Comparing all 74 archive entries with the 0.26.67 bridge found only the version manifest changed; native class bytes are identical.
- The new watchdog regression fails against the released 0.26.67 controller and passes with the patch. It also checks ordinary eight-second recovery, the thirty-second planning ceiling and an unrelated planner receiving no exemption.

## Live findings and limits

The [driving investigation](driving-expedition-investigation-0.26.67.md) records the original failed trip and three additional cloned-save runs, including a repeat with this watchdog fix before the version metadata bump. Those are actual game sessions with real tree removal, native log pickup and physical trunk loading. They are separate from the controlled logic fixtures in the project gate. No additional live expedition was run solely for the metadata bump.

The approach improved in the patched repeat, but **driving return acceptance remains failed**. A blocked return route caused car abandonment in one run. A survival/medical interruption caused crew unloading near zombies and three deaths in another. The watchdog fix does not resolve those return-safety failures. The source save's recorded data fingerprints remain unchanged.
