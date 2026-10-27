<!-- SPDX-License-Identifier: MIT -->

# Companion computer downtime

27 October 2026. Working continuation after release commit `73560fe6` on
`living_fellows/0.26.71`. Lua-only behaviour for Project Zomboid 42.21.0
single-player; native protocol and save schemas are unchanged.

`SCComputerUse` offers a low-priority activity through `SCDowntime`. It probes
at most 81 loaded squares and 256 objects every 15 seconds per eligible idle
actor. Only powered, unlocked computers in the same camp room and floor
qualify. Camp routine policy, literacy, direct interaction topology and shared
reservations are rechecked at selection, approach, animation and completion.
The existing action supervisor owns navigation and the verified native Craft
hand-work pose. No second player window, keyboard ownership or camera slot is
created. The pose is reused native hand work, not a new typing animation.

A completed 18-second visit records one actual county/EMMA reference ID and
title through the normal downtime facts. It changes no inventory, wounds,
skills, password state, operator session count or private notes. The normal
ambient cooldown is ten real minutes. Failed approaches pause two minutes.
Opening a player terminal first cancels that machine's NPC user. Danger,
orders, power loss, invalid access, death, removed actors and reset release
the transient claim. Ownership is reconstructed after loading; unfinished
reading is never saved as completed.

Automated evidence covers the bounded search, camp and floor restrictions,
locks, disabled routines, literacy, blocked use positions, shared claims,
native-action acceptance, completion facts, player priority, danger, changed
orders, power loss, dead owners and reset. UI tests exercise the real terminal
eligibility method and player-opening handoff, including failed cancellation
and malformed portable data. Existing downtime, reading, radio, television,
combat, persistence and UI regressions are retained.

The terminal access checks also cover fresh computers with no prior player
session, corrupt system records and removed world objects. Missing archive
content cannot create a completed reading receipt. Native presence is checked
before any camp coordinate read on a removed object.

Logs are under `build/larchos-validation/` with `computer-downtime-` prefixes.
The full project gate passes all 29 stages, including normal/debug compilation
of 228 payload Lua files, native contracts, gameplay, UI, both adapters and
Workshop/standalone packaging. The 0.26.71 release checkpoint and its push
remain separate from this working continuation.

## Cloned-world native acceptance

A disposable clone of the existing Rising world used a real recruited
companion and an actual desktop world object. The test verified the fresh
computer's eligibility before initializing its system. The actor reached a
genuine native interaction position, retained the downtime supervisor token
and completed the real native timed-action pose. Its completed fact named an
existing reference file. Operator name, all private notes, session count and
the computer's owner archive remained unchanged.

Two further visits verified cancellation and a two-minute retry pause on
power loss, followed by player-priority cancellation releasing ownership.
The test temporarily took this actor off duty and drove its downtime updates
directly so ordinary scavenging could not claim it between scenarios. Other
actors and the native action supervisor kept running. Power was supplied only
to the temporary test computer, and the target was pinned to that exact
object. This validates native interaction and handoff mechanics, not extended
autonomous scheduling or a physical keyboard takeover.

Evidence: `artifacts/emma/native-acceptance/terminal-downtime-evidence.log` and
`emma-computer-downtime-active.png`. The test-only probe and launcher are
`artifacts/emma/terminal-downtime-native.lua` and
`run-terminal-downtime-native.ps1`. They are not part of the mod payload.
No source save, installed game or other player's view was changed.
