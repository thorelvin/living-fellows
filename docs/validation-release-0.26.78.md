<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.78 checkpoint

30 October 2026. Branch `living_fellows/0.26.78`, based on `d61fb037`.

Includes tiredness/stamina persistence, computer upgrade material selection in
crowded inventories and bags, readable shortages, camp-only report visibility,
measured password rendering and hit targets, bold hover feedback, click/login
audio, corrected generic office branding and retryable car-wash preparation.
The individual validation records describe the reproductions and limitations:

- [Companion needs across reloads](validation-vitals-reload-02676.md).
- [Upgrade materials and ownership](validation-terminal-materials-02676.md).
- [Password recovery and office logo](validation-terminal-recovery-layout-02676.md).
- [Hover and interaction audio](validation-terminal-input-feedback-02676.md).
- [Accepted car-wash orders disappearing](validation-car-wash-retry-02676.md).

Release metadata is synchronized across VERSION.txt, SC.Identity, both mod.info
files, both READMEs, the Workshop description and issue-template example.
The native bridge remains at protocol `42.21-isocompanion-24` for Project Zomboid
42.21.0, with SHA256
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.
The bridge binary and document schema 3 are unchanged. Legacy vitals fields
remain optional; previously omitted fatigue/stamina cannot be reconstructed.

After the version bump, all **29 project stages passed** in 115 seconds
(112.1 seconds for the stages). This includes 244 Lua files compiled normally
and in debug mode, core/gameplay/UI regressions, persistence, ownership,
navigation, combat, both NPC adapters, packaging and installer transactions.
Retained evidence: [release gate](../artifacts/releases/0.26.78/project-gate.txt).

The functional changes were installed locally under the preceding 0.26.76
identity before this metadata bump; 15 installed files matched source hashes.
This release request commits and pushes Git; it does not upload to Workshop
or reinstall the new version identity. There is no new live car-wash,
terminal visual/audio or save/quit/relaunch acceptance. The previously
documented fresh-actor bed-alignment and expedition-return rendering cases
have no new acceptance in this checkpoint.
