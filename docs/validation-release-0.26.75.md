<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.75 checkpoint

29 October 2026. Branch `living_fellows/0.26.75`, based on `1aae8165`.

This release adds the LARCH/WAVE radio desk to computers with a mounted
walkie-talkie. Native tuning, presets, reception, scanning and the listening
notebook share the existing terminal and checked station actions. Hardware
removal, outages and invalid tuning requests retain their regression coverage.

It also fixes the reported sleep regression after 0.26.72: cramped bedrooms
can provide valid bedside access, settled double-bed poses retain their
mattress alignment, and exhausted companions leave passive seating or long
downtime activities for an available bed. Native occupancy, danger and get-up
checks remain in force.

Release metadata is synchronized across VERSION.txt, both mod.info files,
SC.Identity, the READMEs, Workshop description and issue-template example.
The paired native bridge was rebuilt at protocol `42.21-isocompanion-24` for
Project Zomboid 42.21.0. No save schema change. Bridge SHA-256:
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.

The full project gate passed **29/29 stages after the version bump**, including
243 Lua files compiled in normal and debug modes, gameplay, UI, ownership,
persistence, both compatibility adapters, installer transactions and Workshop
and standalone packaging. Stages took 118.9 seconds; the overall run took
122 seconds. Evidence: [release gate](../artifacts/releases/0.26.75/project-gate.txt).

The native radio and sleep scenarios were completed before the metadata-only
version bump. Their exact coverage, screenshots and results are recorded in
the [radio validation](validation-terminal-radio.md) and
[sleep validation](validation-bed-sleep.md). The sleep run verified chair exit,
occupied-pillow rejection, lying sleep, decreasing fatigue at full health and
alarm wake in one marked Rest bedroom. It does not claim every bed facing or
a full overnight sleep.

This checkpoint adds no new driving or secondary-to-solo acceptance; the
previously documented native Lighting64 return failure remains unresolved.
Local installation and Steam Workshop publication are separate steps.
