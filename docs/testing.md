<!-- SPDX-License-Identifier: MIT -->

# Testing Living Fellows

The routine gate has five checks. It exercises production code against the
pinned Project Zomboid runtime, without launching the game.

For 42.22.2, use JDK 17 to build the bridge and JDK 25 to compile tests against
the game classes. Set `JAVA_HOME` to JDK 17 and `SC_TEST_JAVA_HOME` to JDK 25.
The test runner uses the game's bundled Java 25 runtime without changing it.

```powershell
.\scripts\Test-Project.ps1
.\scripts\Test-Project.ps1 -Check Cargo
.\scripts\Test-Project.ps1 -Check Lifecycle,Behaviour
.\scripts\Test-Project.ps1 -Release
```

`-GameRoot` selects the installed game. `-Serial` is retained for existing
commands; routine and release runs are serial by default. Missing or different
game files fail prerequisites. A focused run prints `FOCUSED_TEST_PASS`, never
a full-project pass. Failed prerequisites leave dependent checks **not run**.

| Check | Authoritative production proof |
|---|---|
| Build | Pinned runtime, release metadata, reproducible bridge, actual native API/number/exposure contracts, all shipped Lua compiling normally and with debug enabled. |
| Lifecycle | Independent actor/action owners, exact arrival save/reload and pending cleanup; isolated native player/companion, lighting, arrival and vehicle-save boundaries. |
| Behaviour | Bounded following and door access, physical strike barriers and once-only wound ownership; meals, stamina, sleep recovery/interruption and exact medical treatment. |
| Cargo | Safe kit packing, reviewed whole-crew home trip, actual wood collection, exact storage transfers, full storage/retry/reload, and taxi identity/payment recovery. |
| Interface | Selected-actor commands, truthful read-only cached status, terminal access/confirmation/keys, closed-window radio-only service, and packaged content references. |

## Isolation and resources

The gate compiles shared Java tools once. Lua scenarios use fresh environments
and threads within each check's JVM; ordered fixture and production files
within a scenario share that world. Native global-state tests have separate
JVMs. A scenario must not depend on an earlier scenario's actors or clock.

Test children run hidden at BelowNormal priority, with a 256 MB Java heap and
two processors. The shared launcher defaults to one worker and prevents nested
automatic pools. Tests write only into scratch/build directories and isolated
installer fixtures. They do not install into the player's game or open it.

Each run prints five results and durations, then the evidence directory under
`build/test-results`. That directory retains command output and `summary.json`,
including elapsed time, direct game-JVM launches and each check's status.
Elapsed time includes prerequisite checks, a fresh bridge build and tool
compilation. Release and live timings are separate from the routine target.

## Source CI and release validation

`scripts/Test-Source.ps1` needs Python and PowerShell, not a game installation.
It validates script syntax, release identity and packaged content references.
It reports `SOURCE_TEST_PASS` with native/game/installer coverage explicitly
false. Build uses its metadata subset; Interface uses its content subset.

`-Release` runs all five checks. Build additionally runs representative
installer publication, ownership, rollback and restoration cases, and creates
both Workshop and standalone packages. It cannot be combined with a partial
check selection. Builders reuse normal/debug compilation only through a
per-run receipt whose payload, compiler and runtime hashes still match.
Standalone builder commands perform their own validation when used separately.

## Focused regressions and live acceptance

Use these deeper suites when changing the corresponding feature, rather than
adding them back to every routine run:

| Area | On-demand command |
|---|---|
| Native/core and persistence | `tests/core/run_core_tests.ps1 -SkipSharedSourceChecks -Jobs 1` |
| Extended gameplay subjects | `tests/gameplay/run_gameplay_tests.ps1` |
| Home trips | `tests/gameplay/run_gameplay_tests.ps1 -HomeTripOnly` |
| Terminal and interface variations | `tests/ui/run_ui_tests.ps1` |
| Installer failure boundaries | `tests/core/test_installer.ps1 -Jobs 1` |
| Bandits / A-Life interoperability | `tests/gameplay/run_bandits_adapter_tests.ps1` / `run_alife_adapter_tests.ps1` |
| Distinct Strange Folk mechanics | `tests/core/run_oddball_encounter_tests.ps1 -Jobs 1` |
| Live acceptance tools: syntax/load only | `tests/live/run_live_harness_static.ps1` |

The core command rebuilds the bridge unless `-SkipNativeBridge` is supplied
after a matching fresh build. Existing specialist suites remain beside their
fixtures; deleted overlap is available in Git history, not an archive tree.

For engine-sensitive changes, also run a short matching-build cloned-save
acceptance: two companions versus three zombies for combat, one relevant
return/delivery for driving or actor lifecycle, and walls/cars/names after
solo-view restoration for rendering. Record the outcome, relevant exact
identities and necessary screenshots. Probe compilation is not live acceptance.
Capture a game screenshot whenever a distinct blocker is encountered, pairing
it with the actor, position, target, reason and log timestamp. Frame the blocked
actor and nearby obstacle where possible; do not count a blank or obscured
capture as visual evidence. Capture the recovery as well. Repeated samples of
the same continuing block need not create duplicate images. Include the trip leg
and a sequence or timestamp in filenames so a return block cannot overwrite an
outbound capture.
Test-infrastructure-only changes require no live run.

## Keeping the gate small

Add a compact regression to the check that owns the behaviour. Preserve genuine
product failures such as refused transfers, incomplete saves and rollback.
Avoid assertions about source fragments, helper order, exact prose, minimum
test counts, screenshot choreography or mutants of another test's inputs.
New test runners require a production gap the existing fixtures cannot cover.

The routine target is under two minutes on the reference PC. Measure fresh-tool
and warm repeat runs with the same resource limits; do not omit compilation or
hide a slow release run inside that measurement.

## Consolidation measurements

Baseline: committed `b28945ce`, the existing 30-stage serial result. Both new
routine measurements include fresh scratch tools and a fresh bridge build;
the warm measurement is an immediate repeat, without evicting OS file caches.

| Measure | Before | After |
|---|---:|---:|
| Default checks | 30 stages | 5 checks |
| Routine elapsed time | 755 s | 51.3 s fresh / 50.1 s repeat |
| Release profile | included in the old gate | 186.7 s, all five passed |
| Maintained source lines in `tests/` and `bridge/src/test/` | 204,580 | 166,384 |
| Source files in those directories | 525 | 538 smaller subject/fixture files |
| Successful Kahlua runner processes | 214 | 4, with fresh environments per group |

The new routine run launches 23 game JVMs directly, including compilation and
isolated native contracts. Bridge-building tools run separately. There are no
automatic source-mutant runs. Net maintained test reduction is **38,196 lines**.

The affected extended UI and gameplay suites passed. Core passed 97/98 cases;
the extracted key-recovery fixture was corrected and passed its focused rerun.
After final review, the stronger before/after compilation-input guard passed a
focused Build run. A Windows PowerShell 5.1 timeout check terminated both the
owned wrapper and descendant process in 2.75 seconds. Missing-runtime and
partial-release invocations failed correctly, with dependent checks not run.

Evidence is under `build/test-results/20261104-212329-f38ad7`,
`20261104-212420-a2b528` and `20261104-212510-f95751`. Migration-specific logs
are in `C:/ZOMBOID/outputs/consolidation-*.log`. These consolidation measurements
precede the 0.26.97 release; no live game was launched for them. Release validation
and the expedition fixes are recorded in `docs/validation-release-02697.txt`.
