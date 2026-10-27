<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.72 checkpoint

27 October 2026. Branch `living_fellows/0.26.72`, based on `0d8791e6`.

This checkpoint includes EMMA building controls, physical radio and battery
upgrades, expedition-station commands, reading/security layout fixes, and
plain-language job advice with safe pickup retries. Lua and the rebuilt native
bridge ship together; bridge protocol remains `42.21-isocompanion-24`.

Release metadata is synchronized across VERSION.txt, both mod.info files,
SC.Identity, the READMEs, Workshop description and issue-template example.
The complete project gate passed **29/29 stages** after this version bump,
including normal/debug Lua compilation and Workshop/standalone packages.
Evidence: `artifacts/emma/native-acceptance/release-0.26.72-gate.log`.

Real-game checks ran against this implementation before the version-only bump.
Hardware installation/removal, door clearance and movement, mounted world-radio
reception, generator services, blackout/backup power, targeted alarms, physical
furniture moves and two-process save/reload passed. See
[computer-controls validation](validation-computer-controls.md) and
[computer-reading validation](validation-computer-reading.md) for exact scope,
screenshots and evidence.

Full expedition-return acceptance is incomplete: a native Lighting64 crash
occurred during solo-view restoration, and a driving return remained at
roadside fallback awaiting reunion. Large-business profiling, native
bank/police and shutter scenarios, and long-running routines need more live
coverage. Individual fridge isolation is not implemented. These limits are
preserved in the release notes; passing automated checks does not replace them.

This is a Git checkpoint. It does not publish to Steam Workshop or claim a new
live run of the release-number-only change. The locally installed build remains
the same tested implementation identified as 0.26.71 until reinstalled.
