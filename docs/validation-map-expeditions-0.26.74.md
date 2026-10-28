<!-- SPDX-License-Identifier: MIT -->

# Map expedition validation — 0.26.74

28 October 2026. Branch `living_fellows/0.26.74`, based on `46a7d132`.
The native bridge is unchanged: `42.21-isocompanion-24`.

## Implemented scope

The companion planner and EMMA station share one map picker and target policy
for Scout, Search, Fish and Collect wood. Selection returns to review without
dispatching. Cancellation retains the draft; confirmation rechecks the target,
knowledge, crew, travel mode and normal route/vehicle requirements.

Manual targets permit 1,000 tiles walking or 5,000 driving from the current
leader. Beyond 200 tiles they require native visited or map-revealed knowledge.
Known-only building lists also use this knowledge. Automatic woodland and shore
discovery retain their existing range and knowledge rules. Manual logging stays
within the highlighted 32-tile work area and tries no more than three patches.

Manual itineraries use schema 8 and delegate their existing mission/cargo state
to schemas 3–7. Older schemas remain supported. Save restoration does not rerun
discovery from a crew member's new position or recreate cargo.

## Automated checks

The focused target suite passed **323 checks** covering the four mission kinds, road/direct walking and
driving, boundary distances, visited/revealed/unknown terrain, knowledge changes,
forged identities, bounded logging patches and map-session lifecycle. Extended
mission harnesses cover outbound, building-entry, search and inbound reload,
malformed schema-8 saves, legacy saves, wood tool loans and exact cargo identity.

The UI suite includes EMMA selection/review and cancellation protections, plus
12 combinations of four resolutions (1280×720 to 2560×1440) and three font
heights. It checks rotated map coordinates, banner/control bounds, native map
legend clearance and redraws without destination queries or new controls.

The complete project gate passed **29/29 stages** in 149 seconds after the
follow-car and sleep fixes below, including
normal/debug compilation of 239 Lua files, the core and UI suites, combat and
adapter regressions, source checks, installer transactions, and Workshop and
standalone packaging. Evidence: [full gate transcript](../artifacts/expedition-map/native-acceptance/project-gate.txt).

## Real-game evidence

The disposable camp clone uses Project Zomboid 42.21.0 and the current payload.
The native picker selected a real building through the actual map context menu,
returned to mission review and retained primary-player ownership. Native forest
metadata resolved three bounded local patches; fishing resolved a real mapped
bank using retained full-map data rather than depending on an enabled minimap.
The EMMA station also opened the real picker, cancelled back to its original
session, selected the destination and returned to a review bound to that
destination. No expedition or secondary player was created by these checks.

Sample distant target checks resolved an approximately 895-tile walking destination with an
approximately 1,015-tile road route and a 4,812-tile driving destination with an
approximately 6,335-tile road route. The bounded target search plus lookup and
route planning took 7–12 ms in those individual samples. These are metadata and
route checks, not completed long-distance trips or a sustained performance
benchmark. The fixture explicitly reveals selected squares to exercise native
map knowledge.

The walking scout physically reached and observed its selected building, then
returned. Immediately after solo-view restoration, the native lighting thread
crashed at `Lighting64.dll+0x23fd` with `EXCEPTION_ACCESS_VIOLATION`. The same
native call boundary was recorded during 0.26.72 computer-control acceptance.
This repetition does not prove the root cause or establish a clean baseline.
The map implementation does not ship a speculative lighting/view workaround.

Evidence:

- [Native UI and metadata results](../artifacts/expedition-map/native-acceptance/native-ui-evidence.txt)
- [Map picker screenshot](../artifacts/expedition-map/native-acceptance/expedition-map-picker.png)
- [Companion review screenshot](../artifacts/expedition-map/native-acceptance/expedition-map-review.png)
- [EMMA review screenshot](../artifacts/expedition-map/native-acceptance/expedition-map-station-review.png)
- [Scout observation and return](../artifacts/expedition-map/native-acceptance/scout-return-before-crash.txt)
- [Native crash excerpt](../artifacts/expedition-map/native-acceptance/lighting-return-crash.txt)
- [Runner and fixture scope](../artifacts/expedition-map/README.md)

## Acceptance status

Full return acceptance remains blocked by the native lighting crash. Complete
walking and driving round trips for all four mission types, near-limit trips,
native delivery placement and post-return kitchen walls, parked vehicles and
overhead names have not passed this checkpoint. Successful automated checks and
map screenshots do not replace those scenarios.

## Follow-car and sleeping-speaker reports

The screenshot reports were reproduced in the controlled Kahlua harness before
the fixes: exiting the lead car recovered an unloaded follow-car member beside
the player, and the speech executor accepted a sleeping companion's line.

Recovery now retains the original car anchor for Follow and Regroup as well as
posted orders. Tests cover the driver and a passenger, leaving the lead car,
waiting while the origin remains unloaded, recovering at the same car's door,
and clearing the anchor only after verified recovery. A moving car or blocked
loaded exit cannot use the timed bare-position fallback. The convoy tests also
retain the unloaded driver's assignment while preserving ordinary unreachable
car cancellation.

Sleep checks cover native overhead speech, selected dialogue, resolved replies
and needs narration. Suppressed lines do not consume dialogue history or create
a speech receipt; a still-current need can be voiced after waking. Existing
needs growth, alarm wake-up and ordinary conversation regressions pass.

These are automated reproductions; a new live two-car driving scenario is not
claimed. The native expedition-return blocker above is unchanged.

This Git checkpoint does not install the build locally or publish it to Steam Workshop.
