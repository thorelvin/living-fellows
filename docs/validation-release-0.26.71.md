<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.71 validation

27 October 2026. Branch `living_fellows/0.26.71`, based on `a66bbf4b`.
Target: Project Zomboid 42.21.0, single-player. Existing save schemas and
native bridge protocol `42.21-isocompanion-24` are retained.

The full project gate passed **29/29 stages** in 136 seconds. This includes
the pinned native runtime, source and release synchronization, Lua normal and
debug compilation, core/gameplay/navigation/combat, both NPC adapters, UI,
Workshop/standalone packaging and installer transaction regressions.
Log: `build/larchos-validation/release-0.26.71-project-gate.log`.

The native bridge and its sources ship together. Payload SHA-256:
`322fc8017dd4bfc968d63e0948280688f74fe77eedd1aa3f1778a4cdd7649c8e`.
Version metadata, the README badge, mod metadata, payload README and Workshop
description all identify 0.26.71.

The completed EMMA pass covers 340 owner entries, 16 county/EMMA files and
195 terminal logo identities. A disposable cloned world rendered the full
catalogue in its paired colours and purple, plus all reference pages and four
complete CRT colour examples. Thirty-four native captures and compact logs
are retained under `artifacts/emma/native-acceptance/`. All 18 selected outputs
in the expanded artwork manifest match the original generator bytes.
Detailed scope and acceptance boundaries are in
[the computer validation](validation-camp-computer-system.md).

Native furniture pickup/reload/hacking XP and terminal-driven physical
medical/refuelling outcomes remain separate live scenarios. Companion use
of computers during downtime is not included in this release checkpoint.
No local game installation or Steam upload was performed for this checkpoint.
