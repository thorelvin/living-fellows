<!-- SPDX-License-Identifier: MIT -->

# 0.26.67 work-order validation

Wood delivery can finish without crediting missing cargo as stored, while live cargo stays tracked after inventory rearrangement. Living crew receive preparation tools after a leader handoff. Daylight rules agree across departure, travel and chopping. Nearby car unloading uses the same physical capacity policy as loading, and large stores receive time for their initial bounded discovery pass.

## Baseline and scope

At the start of this work, the clean local `living_fellows/0.26.66` branch and GitHub both pointed to `c131af55000298ed62409c907c8045f86facd752`. This includes the newer work-voice and delivery changes following the work order's `ef2846be` review baseline. All seven findings remained applicable. Those newer changes are retained on `living_fellows/0.26.67`.

## Findings

| ID | Status | Change and regression evidence |
| --- | --- | --- |
| LF-01 | Fixed | `SCExpeditionIntegration.lua` persists an optional terminal `released` outcome independently of `stored`. Tools and optional restocking become reachable after every log is stored or conclusively released. `SCExpeditionPrototype.lua` removes released receipt protection even while an axe keeps the trip open. Wood integration tests cover a missing log with a carried axe, duty without an axe, mixed outcomes, save/reload, automatic retry and actual controller queue pruning. |
| LF-02 | Fixed | A changed cached source triggers one fresh location lookup. Irreversible settlement additionally requires a fresh complete inspection of tracked holders, bounded to 4,096 items and 64 containers per holder. Incomplete, unreadable or unresolved holders keep delivery pending. The real controller's export and report pruning paths are tested after a player moves the exact log into a bag within 100 ms of caching; later physical delivery frees the queue slot. Unreadable, over-budget and broken-list cases stay unknown across save/reset. |
| LF-03 | Fixed | `SCExpeditionWood.outsideWorkAllowed()` reads actual time of day and the night-work policy. Preparation, travel recall and worker safety share it; elapsed world hours still control trip durations. Mission tests use the real seven-hour offset, exercise 06:00 and 21:00 boundaries, midnight and night-work permission, and verify that delayed departure resets duration correctly. |
| LF-04 | Fixed | Preparation filters for living registered actors, prefers the current leader, replaces a dead borrower's pending transaction and revalidates a prepared cutter. Verified tool commits are journaled before transient teardown. Worker tests cover a corpse's usable axe, borrower death, daylight waiting, no eligible actor, an interrupted physical commit and persisted loans. The real controller handoff is also tested without reordering the roster. |
| LF-05 | Fixed | Bag-held borrowed axes stage by exact verified ownership into the main inventory before using the actual `SCBaseWork.returnToStorage` contract. The work-transport harness loads the production logging, wood, transport and storage helpers. It covers exact return, idempotency, physical capacity, failed staging, external ownership and stale nested membership. |
| LF-06 | Fixed | The public carry helper accepts a car/destination context and validates both ends of a short shuttle. The actual delivery dispatcher passes the selected storage, retains physical limits and rejects a distant replacement destination after pickup. Heavy-only crews require a nearby permitted home destination before departure. Tests exercise safe limit 10, axe weight 3 and log weight 9 through the real dispatcher and real carry helper, plus distant storage, full inventory and ordinary walking. |
| LF-07 | Fixed | `SCEncounter.siteDiscoverySeconds()` uses the live cursor's footprint/floors and configured scan quotas. The controller adds one initial allowance capped at 600 normal-speed seconds, converted using the configured day length and capped by the overall return deadline. The new integrated gameplay harness runs the actual scanner and controller against the 81-by-81 store and shelf at cursor 4,051 on both 60- and 120-minute days. It verifies physical shelf approach and opening, small/empty stores, threats, cancellation, return deadline and at most 28 probes per beat. |

The durable regressions are in `tests/core/wood_expedition_integration_harness.lua`, `tests/core/expedition_wood_harness.lua`, `tests/core/expedition_wood_mission_harness.lua`, `tests/core/work_transport_harness.lua` and `tests/gameplay/expedition_search_deadline_harness.lua`. Both runner scripts wire them into the project gate.

## Validation

- Focused production-module harnesses pass in Project Zomboid 42.21.0's actual Kahlua runtime, including 132 wood integration checks and 80 physical wood checks. These are controlled logic fixtures, with native-shaped objects and action outcomes supplied by the tests.
- The native bridge builds reproducibly with Java 17: 22 packaged classes, version `0.26.67`, protocol `42.21-isocompanion-24`, target 42.21.0. No native behavior or protocol change was required by these findings.
- `scripts/Test-Project.ps1 -Jobs 2`: all 27 stages passed in 194 seconds, including real-runtime Kahlua execution, native compatibility, source/static checks, UI, existing field-work regressions, live-probe fixture checks, Workshop/standalone packaging and installer transaction tests. The live-probe fixtures are logic checks rather than an interactive game session.
- A separate baseline check substituted the original `0.26.66` controller into the integrated store regression and reproduced termination before the loaded shelf. The `0.26.67` controller passes that scenario.
- Shipped bridge SHA-256: `D7AC97D30782BC52B2E61DF36BF0A43D248E16B3C10AB9F8A4EE3B7D525EA6B2`.

No new interactive or cloned-save game expedition was run for this work order. The Kahlua results establish logic behavior and the project gate checks native compatibility; they do not establish live animation, JNI or end-to-end world behavior. A walking and driving wood trip with tool return, plus a large-store search, remain useful live follow-ups.

Existing expedition schema 7 and wood integration version 2 remain unchanged. Older records without `released` normalize to unfinished cargo. Search and fishing quantities are unchanged. No missing log or axe is recreated.
