<!-- SPDX-License-Identifier: MIT -->

# Expedition map acceptance

`native-map-probe.lua` exercises the real world-map picker, companion planner
and EMMA station without launching a mission. It checks native map knowledge,
building/forest/shore metadata, cancellation, draft retention, read-only review
and primary-player ownership, then saves game screenshots.

`native-map-trip-probe.lua` launches a normal walking scout with a selected
building. It requires a real observation and a return, then waits in solo view
before accepting the run. A crash or a return without observing is a failure.

Run `run-native.ps1` for the UI scenario, or add `-Trip` for the scout scenario.
The runner requires the prepared disposable camp clone and loading agent named
in the script. It copies the current payload only into that clone, launches an
owned hidden process and stops that process in `finally`. It never installs
into the player's game or edits the original save. Local full captures are in
`build/expedition-map/native`; selected evidence is retained here.

The fixture reveals selected map squares explicitly to test read-map knowledge.
The EMMA check uses the clone's original desktop, supplies physical installation
parts and raises the fixture player's Electrical skill if needed. It moves the
fixture player to the desktop; the expedition trip moves its crew normally.
These provisions do not establish discovery, survival or equipment acceptance.

The scout return reproduced a native Lighting64 access violation. See the
[validation report](../../docs/validation-map-expeditions-0.26.74.md) for passed
checks and outstanding live scenarios. A UI pass is not a driving-return pass.
