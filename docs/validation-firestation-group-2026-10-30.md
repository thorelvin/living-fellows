<!-- SPDX-License-Identifier: MIT -->

# Firestation group sleep follow-up

Follow-up to 0.26.82 commit `8d044e0d`, after a tester reported two sideways
sleepers and conversations interrupting their trip upstairs. Project Zomboid
42.21.0, Living Fellows alone, existing bridge protocol and save schemas.

## Reproduction and cause

The previous acceptance tested one companion at a time. The new group probe
uses three companions together in each original upstairs bedroom at Rosewood's
firestation, near `(8140,11738)`. It retains the native stairs, beds and walls,
and closes all ordinary door objects before each group's journey (36 in the
baseline, 38 in the final generated instance).

Baseline run `SC-Harness-20261030-210649-de4127ba` reproduced the problem in two
of six sleepers. Their forward direction matched the requested mattress axis,
but their animation angles remained `-2.08275` rather than `0` radians and
`-0.40770` rather than `1.57080` radians. Merely setting the future facing target
did not settle the rendered body before `PlayerOnBedState` locked turning.

`SCBedGeometry.configureEntryAction` now uses the stock
`setTargetAndCurrentDirection` method before the action requests the bed state.
This acts on the owned companion's action only; ordinary native entry, root
movement, sleeping and getting up remain in charge. No native JAR change is
needed for this follow-up.

Optional banter previously admitted `rest_bed` as a quiet activity, including
its approach phase. Banter now declines sleepers, active sleep approaches and
exhausted participants, including the gaps before a sleep activity acquires its
lease. Existing optional exchanges revalidate both participants before replying
and release their conversation positions when sleep takes priority. Explicit
player conversations and urgent combat speech retain their existing paths.

## Live checks

First fixed group run `SC-Harness-20261030-211318-3fd3cfed` passed all six
sleeping-direction checks. The companions walked downstairs-to-upstairs in
29–35 seconds, used three distinct beds in each room, retained health and left
the beds normally on cancellation. Angles matched the mattress axes throughout
15 seconds of settled group sleep; original native screenshots were inspected.

Final run `SC-Harness-20261030-211713-34ef80ad` passed **76 checks, 0 failures,
0 skips**, including fatigue recovery and the sleeping-bag, couch and upstairs
bunk paths:

| Native sleep case | Downstairs-to-sleep time | Result |
| --- | ---: | --- |
| Three companions in the first original bedroom | 30–32 s | All axes correct; three distinct beds |
| Three companions in the other original bedroom | 27–33 s | All axes correct; three distinct beds |
| Deployed sleeping bag | 31 s | Lying, aligned, healthy |
| Backup couch | 31 s | Supported native seated sleep |
| Upstairs bunk | 30 s | FootLeft entry, aligned, healthy on floor 1 |

The six group sleepers' fatigue fell from 1.0 to 0.979–0.988 during the observed
sleep. Every measured companion got up through normal cancellation and was
removed only after standing. Group, bag and bunk screenshots were inspected.

These probes drive production `Downtime.update` and exercise optional camp
conversation selection while the ordinary Decision scheduler is disabled.
Measured actors walk physically; only fixture spawning and the observer's
camera placement are scripted. This is not a natural overnight cycle or the
tester's unavailable save with its exact door sequence.

## Regressions and source-save isolation

The focused core and gameplay suites passed, including all four mattress
directions, ordinary/corrected metadata, setting the render angle before native
entry, emergency-fatigue conversation rejection, sleep-approach rejection and
an exchange interrupted by newly selected sleep. Existing ordinary seated
conversation checks remain active.

All 3,430 original source-save files match their pre-run SHA-256 hashes. The
unchanged bridge payload has SHA-256
`2a325b578aa70d6899a9a3b52632311ab9c48a79d377ece6ab519abdcd702487`.
The final project gate passed **29/29 stages in 162.8 seconds** (8 jobs),
including native controls, gameplay, UI, both compatibility adapters, installer
transactions and both distribution builds. `git diff --check` also passed.
Generated worlds, raw logs and screenshots remain under ignored
`build/firestation-group/` and `build/live-sandbox-runs/` paths.
