<!-- SPDX-License-Identifier: MIT -->

# 0.26.81 validation - idle computer services

The report describes stutter with all LF menus closed in a two-story firehouse,
dating from the computer updates. The tester's save and recent log were not
available. The measurements below use fresh clones of the existing four-person
camp, rather than claiming to reproduce that particular firehouse.

The first EMMA commit added on-demand handlers, without an idle tick. Later
computer services surveyed up to 256 nearby squares per callback, spanning the
player's floor and the floors above and below. A regression test reproduced
1,024 grid reads and 12 power checks across four idle pulses. With its isolated
non-radio fixture, the corrected test records zero grid and power reads.

At the user's request, closing the terminal now pauses device discovery,
security sensors and scheduled computer routines and stops its siren/PA.
Mounted radios remain the exception. Load/place events restore their exact
saved hardware; ordinary objects use `hasModData` without allocating metadata
or examining computer properties. These events share bootstrap's transactional
installation, rollback and removal. Idle UPS batteries are not polled and do not
lose charge for idle hours when a computer is reopened.

House details are cached on use. Device discovery proceeds through at most 16
loaded squares per step, respects a shared background deadline and resumes across
frames while the terminal is open. Saved device records supply a cached sorted
array; a renamed or newly discovered device invalidates that array. Commands
retain their native identity, location and permission checks. No save schema or
native bridge change was needed.

Two-minute, speed-1 observations with both LF windows explicitly closed:

| Run | Computer-service p95 | Maximum |
| --- | ---: | ---: |
| Baseline `SC-Harness-20261030-174301-2825ae46` | 5.940 ms | 11.110 ms |
| Final `SC-Harness-20261030-182342-575d12ee` | 0.585 ms | 4.115 ms |

The shared callback also includes mounted-radio work and cleanup of requested
generator jobs; its total is not an assertion of zero CPU cost. Both runs
verified that the windows stayed closed. The final run passed 10 checks with
zero failures or skips, and produced no Lua exceptions. The profiler reports
recent percentiles over at most 120 samples per metric and maxima since reset.

This fixes the confirmed idle-computer work, not all camp performance. Other AI
callbacks remained expensive: final base work reached 35.378 ms and decision
evaluation reached 10.939 ms. Whole-mod recent p95 was 4.663 ms in the baseline
and 10.252 ms in the final sample, with different ordinary crew activity; these
observations do not establish an overall FPS improvement or resolve the tester's
entire firehouse report.

The full follow-up project gate passed **29 of 29 stages in 161 seconds**.
Regression coverage includes idle behavior, two-floor scan resumption, cached
device arrays, native-shaped upstairs radio restoration and placement, unchanged
radio identities, UPS idle charge and bootstrap callback ownership/removal.
The first gate exposed a missing pair of event fixtures; those fixtures were
updated to represent the real LoadGridsquare/OnObjectAdded interfaces and the
full gate then passed. Raw profiling logs remain outside Git.

These profiles and the 161-second gate used this behavior before the release
metadata was bumped from 0.26.80 to 0.26.81. The live runs used disposable cloned
worlds; the original save remained unchanged. Final 0.26.81 release checks are
recorded below.

## Final 0.26.81 release checks

The canonical release bump passed `test_release_sync.py`, retaining native bridge
protocol `42.21-isocompanion-24` and the existing save schemas. The final
`Test-Project.ps1 -Jobs 8` run passed **29 of 29 stages in 161 seconds**, including
native/runtime contracts, core, gameplay, UI, lifecycle, live-harness static,
adapter, installer and both distribution-package checks. `git diff --check`
also passed. This release operation commits and pushes Git source; it does not
install the new build or upload to Steam Workshop.
