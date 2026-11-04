<!-- SPDX-License-Identifier: MIT -->

# Send home: driving validation

Dates: 2026-11-03–04. Branch: `living_fellows/0.26.95`, based on `8ea53d34`.
Project Zomboid 42.21.0; bridge protocol `42.21-isocompanion-29`.

Current status: the matched driving/carried-cargo save/reload/delivery live
acceptance passed on 2026-11-04. The final serial project gate passed all 30
stages after the detached-trade compatibility correction; detailed evidence is
below. Driving and delivery acceptance is complete within the recorded scope.

## Automated checks

Focused native, car, home-car, gameplay, persistence, UI, context-menu,
observation and normal/debug Lua checks pass. The UI contract has 94 checks,
including literal-percent handling through the installed translator's rules.
After the final-approach handoff change, and before the later Home delivery-reach
fix, the serial project gate passed
all 30 stages on 2026-11-04 in 847 seconds, including core, source/installer,
gameplay, navigation, UI, both NPC adapters, persona controls, Workshop
packaging and standalone packaging. The UI checks also cover the actual
`parking_home` phase and refusal of unsupported Home commands in terminal
radio menus and stale confirmations.
That log is `C:/ZOMBOID/outputs/send-home-02695/gate-drive-before-delivery-reach.log`.
The later delivery and reload hardening now has focused checks and the paired
live acceptance recorded below. Its fresh serial gate also passed all 30 stages.
The previous gate is retained at
`C:/ZOMBOID/outputs/send-home-02695/gate-drive-before-home-handoff.log`.
Historical standalone archive SHA-256 from that earlier gate:
`5ec5bd60f610684c8ad9fe7922014a81b21f46f9146a5280f51f96becb0ee68f`.
No installation, commit, push or publication was performed.

The earlier UI suite's only
failure was its phase extractor treating a compact `leg=="home"` comparison
as a phase assignment; the corrected extractor and regression pass.

Native tests exercise real SQLite commit visibility, missing/changed records,
exact stopped-car identity, attached arrival leases, reload receipts and final
world-exit cache cleanup. Nearby recall can recover from a failed write only
while the exact stopped, empty car remains owned by actual primary chunks.
That ownership is checked again immediately before joined-view release.
Remote handover still requires the committed vehicle receipt.

The new parking-alignment tests pass for physical turns, final forward
alignment, obstacle checks and motion/time bounds. The existing forward
approach check stays intact. Focused Lua integration tests pass; live alignment
and successful marked-parking acceptance remain pending.

A real-Prototype regression reproduced the watchdog cancelling a retained
`ordered_move` search at 9 seconds when Navigation displayed `recovering`.
Navigation reports a live search age independently of that display phase.
The watchdog now retains an active search until the existing 30-second search
and waypoint ceilings; recovering without a search, invalid ages, inactive goals,
unrelated actions and expired searches still recover. The baseline assertion
failed before the fix and passes afterward; Home, wood-mission, persistence,
decision, scheduler and Lua checks pass. This is a confirmed controller bug,
not yet proof of the cause of the live entrance stall.

The retained camp storage audit now revalidates its native list once per resumed
slice, preventing indexed reads after a remote chunk unload empties that list.
Its 253 budget checks pass, including shrink, replacement and unload/reload.
Pre-ack car-proof failures now abort their prepared arrival lease before allowing
recall or a fresh handover. Failed or durable aborts retain ownership; focused
Home and persistence tests pass. Successful all-dead cleanup releases an
unattached car-save ticket after native view teardown. An exact pre-ack all-dead
crew can reach normal corpse teardown instead of retrying living handover forever.
Native corpse-save failure retains its lease and attached car proof. Successful
teardown flushes the finalized death document before discarding held snapshots;
failed document writes retry without repeating native unload or recreating actors.

The live fixture has independent negative controls for missing or failed
pre-commit observations, stale/wrong-car receipts, changed cargo IDs,
duplicates, incomplete storage receipts and falsely delivered roadside cargo.
It performs bounded inventory audits and never creates replacement cargo.

## Live runs

Earlier live attempts and their findings are retained below
`build/live-sandbox-runs/` and are not release assets.

After repeated desktop-input failures, unattended runs use the existing isolated
`SCLoadingGateAgent`. It sets only the current loading state's `forceDone` flag
after `done` and `showedClickToSkip`, matching the installed mouse/joypad branch.
The native update still waits for the streamer and animations, then performs
the normal loading exit, player UI creation and camera setup. It neither
transforms bytecode nor changes actors, cameras, maps or arrival state. The
agent's start marker alone is not acceptance; real Lua/native gameplay and
scene checks remain required. This helper is test-only and is not shipped.

| Run | Outcome |
| --- | --- |
| `SC-Harness-20261103-220949-36e3c58f` | Stopped before setup: the isolated runner omitted the new driving fixture. Its filter was corrected. |
| `SC-Harness-20261103-221326-91ac6a1c` | Real crew, car, keys, cargo and public departure passed. The observer was nudged 0.216 m by native crowd separation, exceeding the walking probe's 0.2 m check. Driving now allows at most 0.75 m of drift without recentering or moving the observer. Larger drift and floor changes still fail. The screenshot also exposed three unescaped percent labels; corrected and regression-tested. |
| `SC-Harness-20261103-222047-7cfb0d90` | Driver physically boarded. The walking-only health helper incorrectly rejected a seated driver. Driving now allows native seating while retaining health, bleeding and death checks. |
| `SC-Harness-20261103-222649-ac73309a` | Both crew physically boarded and drove. The car failed at trees near Cabin Road, stopped its engine, obtained native save proof and safely unloaded the crew to walk on. The marked-parking goal was not completed. Native zombies attacked the blocked main observer; the run failed the movement check. No arrival or delivery pass is claimed. |
| `SC-Harness-20261103-224424-f28a663c` | Stopped before departure because native observer-invisibility setters refused the non-debug role. Installed bytecode confirms the capability gate. Home probes now use the runner's existing genuine single-player `-debug` launch condition and ordinary verified setters. |
| `SC-Harness-20261103-225120-9955212f` | Verified observer flags, physical two-person boarding, the actual south-on-Fifth/east-on-Oak route, about 227 m driving and road arrival. Parking then held with `parking_requires_arrived_drive` after the completed driving job was lost. The disposable client was saved and closed normally for diagnosis; no final summary, arrival or delivery pass is claimed. |
| `SC-Harness-20261103-230347-ea28769f` | Repeated the physical route with ownership/history diagnostics. The job was owned, managed and arrived at the road end. The first forward parking move was refused because the car was still angled across the short driveway; cancellation then retained an arrived outcome that masked the original refusal. The client was saved and closed normally. This is diagnostic evidence, not a parking pass. |
| `SC-Harness-20261103-232904-5ec701f3` | The physical road trip succeeded. Native alignment correctly refused obstructed manoeuvre space. The crew stopped and saved the car, exited safely and walked into camp. Remote handover, exact identities/items/health, solo release, dormant restore and primary revisit passed. The final audit then exposed an emptied retained storage list and an optional-method call in the test fixture. Both were fixed and focused tests pass. The client was closed normally; this is partial-return evidence, not completed marked-parking acceptance. |
| `SC-Harness-20261103-234543-cd37f5c6` | The conservative 12 m clear-circle fixture found no qualifying bay. Setup failed before dispatch. No parking or delivery pass is claimed; a straight-road bay fixture is being prepared without clearing world objects or weakening production checks. |
| `SC-Harness-20261103-235820-7e5cb9bc` | The two-lane straight-bay fixture also failed before dispatch. It overestimated both possible arrival lanes at a camp with limited legal parking reach. The fixture now models the actual signed lane and any appended width-5 driveway; public camp limits and native checks remain unchanged. |
| `SC-Harness-20261104-000231-f9d8ce59` | Roadside variant: public review, exact two-person boarding and real driving passed. Saved mid-drive after at least 25 m, flushed native ModData and exited normally. All 51 checks passed; completion and cold restore are still pending. |
| `SC-Harness-20261104-000658-500d350a` | A fresh process loaded the saved checkpoint, but desktop mouse/keyboard input and capture timed out at the start gate, including after reconnecting. No gameplay-resume pass is claimed. The runner eventually timed out and stopped its owned client. The preceding saved checkpoint remains unchanged. |
| `SC-Harness-20261104-063229-70c41517` | Root clicked the new start gate. Although the desktop request timed out, actual logs prove both exact crew restored, drove to the roadside stop, switched off the engine, exited and obtained native car-save proof. Both then stalled near the entrance at `12031,6753` for over seven minutes. No arrival pass is claimed. Normal close input also timed out; only the exact isolated-run PID, verified by its executable and command line, was stopped. Added bounded read-only navigation/gate diagnostics for the next run; their regression and debug compile pass. |
| `SC-Harness-20261104-064812-e6bcef31` | Diagnostic build loaded but remained at the start gate. The native window had slipped mostly below the desktop, leaving a 79-pixel strip; input, raise and maximize calls timed out. No gameplay result is claimed. Stopped only the verified isolated client; the intact mid-drive checkpoint remains available. |
| `SC-Harness-20261104-070952-88041836` | Loaded the same checkpoint with the watchdog fix and diagnostic trace. The desktop controller could read the game's native window controls but could not reliably raise or capture that window; a requested game capture instead showed an occluding foreground app. No gameplay-after-fix result is claimed. Stopped only the exact isolated client after verifying its PID and command line, then began the serial automated gate with all games closed. |
| `SC-Harness-20261104-074706-5b6a4009` | Controller recovered and the cold driving trip resumed. The car stopped, both crew exited, and native save proof completed. Final-approach diagnostics showed every Home gate clear and an exact core goal, but productive Lua searches reached about 85 nodes by 25.6 seconds and restarted at the outer 30-second waypoint limit. This prevented Navigation's existing overdue-search native fallback from running. Saved and closed normally (game exit 0); no completed return pass claimed. A verified Home-only 6-second pending-search bound now permits that existing guarded fallback before the watchdog. Focused real Navigation/traversal, decision, Home, persistence and normal/debug compilation checks pass. |
| `SC-Harness-20261104-081522-be78cd32` | **26 PASS, 0 failures, 0 skips.** Cold mid-drive restore resumed the same two companions and car. Native seat/travel continuity verified 220.56 m of physical driving. At f2321, the six-second search allowance handed off to the existing native lease; the leader then moved from 16.8 m to 6.3 m from the core. Both crew completed strict camp arrival, native solo release and dormant retirement by f2679, preserving eight exact native items each. The stopped-car proof attached successfully; a second native flush saved a dormant checkpoint and the client exited normally. Cold dormant revisit/cargo audit remains separate. |
| `SC-Harness-20261104-082152-7d07f12b` | Dormant checkpoint loaded, but the controller could not start play: native Raise, keyboard and capture requests timed out. The alternate Task Manager activation requested app access and timed out without approval. The runner stopped only its own client at the deadline. No cold-dormant gameplay or cargo result is claimed; the successful source checkpoint remains intact. |
| `SC-Harness-20261104-084523-37184e7c` | The same dormant source loaded successfully but remained at f0. Controller raise/capture requests could not start play, and the runner timed out and stopped only its isolated client. No cold-dormant result is claimed. The saved source from `081522` remains intact. |
| `SC-Harness-20261104-091156-08b2a347` | Loaded the dormant checkpoint after the 30-stage gate passed. Capture and native Raise requests timed out; the runner later closed its isolated client at the deadline. No gameplay or restoration pass is claimed. |
| `SC-Harness-20261104-101446-f3dd46c2` | Capture recovered and showed Click to Start, but both desktop click requests timed out. Closed only the verified disposable PID when a separate normal Steam launch appeared, avoiding two competing games. No gameplay pass is claimed. |
| `SC-Harness-20261104-102842-0f9f5a6a` | The existing isolated loading agent started normal gameplay successfully. Cold dormant crew restore, exact native items/health/names, primary-only restoration, stopped native car, unique exact roadside cargo, solo camera/wall/car checks and both actual base-duty resumptions passed. The probe then repeatedly restarted its sliced final cargo audit, resetting its own crew-stability timer; after waiting it falsely failed when normal base duty started work. Saved and exited normally. This is partial live evidence, not a completed acceptance summary. The test-only ordering fix now passes multi-slice, real crew interruption and missing-ID regressions plus live static/debug checks; production code is unchanged. |
| `SC-Harness-20261104-103628-0bba8cde` | **92 PASS, 0 failures, 2 skips.** Cold dormant restoration and the complete roadside return audit passed with the corrected probe. Both crew retained eight exact native items and their health/names, restored once through actual primary ownership, finished physical handover and resumed base duty. The exact native car remained stopped with both initial trunk roots still pending, not delivered. Native primary camera, four walls and two parked-car checks passed. Reviewed the actual solo, home-car and name PNGs: normal wall cutaway, visible car bodies (the return car is partly behind a tree), and a rendered returned HomeOne label. The skips are an optional minimap not present and the explicit reminder to inspect the pixels; the latter is resolved by this visual review. The game saved and exited normally. |
| `SC-Harness-20261104-104128-0dedc7ae` | Stopped before dispatch because the fixture found no clear straight bay. Its route helper ignored the configured direction and always chose 200 m west. Direction and bounded rejection diagnostics are being corrected in the test fixture; public parking reach and native clearance checks remain unchanged. No marked-parking or delivery pass is claimed. |
| `SC-Harness-20261104-105218-34ede0e9` | The corrected fixture requested 200 m east. Native routing reported `INCOMPLETE_MAP_DATA` before parking setup, and the setup deadline ended the run without dispatch. The native router uses this status for a disconnected mapped street graph; no unloaded-chunk workaround or alternate direction was substituted. Failed-route diagnostics now retain native status/reason and the actual target. |
| `SC-Harness-20261104-105833-98b2b785` | West-route diagnostics proved the camp's unchanged parking band ends at y6770, while the road center is y6773. The fixture admitted 130 layouts but rejected its oversized union rectangles, including a tree at `12023,6764` outside the car's actual corridor. It now reads native CarNormal dimensions, models directional early stopping and swept corridors, and tries every public-valid layout at each center within the same 64-unit work cap. Tests reject actual body/entry obstructions and unknown dimensions. No production guard or world object was changed. |
| `SC-Harness-20261104-111127-c61c87b5` | The corrected fixture selected a legal 9×7 bay. Both crew boarded with real keys and five exact trunk roots, drove 220.85 m and reached camp. Native parking refused the short final turn and its alignment attempt; the car was stopped, saved and safely exited, and the whole crew completed remote arrival, primary revisit and actual base duty. Cargo remained pending. The probe later failed while waiting for delivery after a companion began work. No marked-parking delivery pass is claimed. The happy-path fixture is being restricted to a longer, verified forward leg; the production cone and alignment guards remain unchanged. |
| `SC-Harness-20261104-112250-861a60b0` | A legal long-forward bay was selected. During its approach, the native car scan stopped for a tree beside the turning body. The crew safely exited and returned; cargo remained pending. The test fixture now covers the body's rotation radius during entry, while its final straight strip remains unchanged. No parking/delivery pass is claimed. |
| `SC-Harness-20261104-113850-46b8df9d` | **Physical marked parking succeeded.** The car reached `home_wait` inside the selected bay, stopped its engine and safely unloaded both crew. An approximately 80-second bounded exterior survey delayed the first walking waypoint, then ordinary walking completed whole-crew arrival and primary restoration after 232.44 m of real driving. The initial suspected goal/handoff defect was disproved: both goals remained the captured core and no handoff reset was applied. Delivery subsequently lost admission while a worker crossed y6751 between camp (ending y6750) and the legal parking area (starting y6752), before picking up trunk cargo. The run recorded 118 passes and one failure, then saved and exited normally. The later stop attempt refused because that process had already exited; no process was stopped. No delivery pass is claimed. A narrowly authorized Home-car delivery reach path is being investigated. |

Subsequent marked-parking runs `SC-Harness-20261104-115553-05af605f`
and `SC-Harness-20261104-120901-38fa28d9` physically parked and completed
whole-crew arrival, view retirement and primary restoration, but failed the
delivery deadline. In the latter run, all four receipts still referred to
their real trunk items; no stored cargo was reported. The leader's repeated
bounded indoor searches toward the trunk expired before Loot began. The
follower's old formation-search age is retained status, not evidence of
continuous active searching. No lost native player-slot ownership was found.
The Home-specific work-reach change is under test; delivery is not accepted.

Focused delivery hardening checks now pass for:

- Exact Home cargo ownership across the bounded gap between camp and marked
  parking, including rejected wrong cars, cargo identities and camp changes.
- Runtime destination retention per exact receipt, preventing an expired
  storage survey from starving the trunk approach. Permission, capacity,
  category, loaded object and container remain checked each update.
- Locked Home trunks using the existing key, boarding, delayed native unlock
  and exit sequence. A native `false` lock value is preserved, and unreadable
  locks or unverified writes cannot authorize cargo transfer.

Existing generic delivery, wood delivery, parked-car unloading and field-work
regressions pass. Home gameplay/persistence, shipping Lua normal/debug
compilation, the live probe/fixture regressions and live static checks pass.
The full project gate must still be rerun after these production changes.

`SC-Harness-20261104-124039-338731fa` automatically entered gameplay, then
refused the diagnostic delivery replay on its first frame because the car was
not yet available to the stopped-car check. It recorded ten passes and one
failure, saved and exited normally; it proves neither delivery nor a full trip.
Diagnostic warm-up handling is being corrected without weakening car identity
or pose checks. The separate fresh-drive attempt is recorded below.

`SC-Harness-20261104-124349-b9f315b6` automatically started, drove and parked
successfully, then safely refused Home handover because unrelated original
companion `sc-1.792509015635E9-1-314954` had no verified stable position.
The first global-save abort occurred at frame 1420, before Home arrival
preparation around frame 7142. Repeated save attempts retained the prior
snapshot. After the blocker persisted, only this exact owned clone process was
terminated to release resources; it wrote no acceptance summary and is not a
pass. No cargo or crew was recreated, moved or discarded to clear the blocker.
Verified restoration-anchor hardening was subsequently added and passed its
focused lifecycle checks: only the exact committed, native-health-verified
actor can seed the runtime position. No saved-coordinate substitution or
replacement actor is used.

Further runs on 2026-11-04:

- `SC-Harness-20261104-130109-beabbfda`: automatic start and bounded natural
  loading worked. Diagnostic setup refused an ordinary personal inventory
  without the historical exact-native-ID marker. The diagnostic now labels
  that unavailable personal proof explicitly; cargo proof remains strict.
- `SC-Harness-20261104-130506-ea4b6113`: 118 passes, one failure. The complete
  drive, marked parking, stopped engine, whole-crew return, retirement, primary
  restoration and wall/car checks passed without the previous save abort.
  One of five original cargo roots reached storage before the explicit
  180-second delivery deadline. This is partial delivery, not acceptance.
- `SC-Harness-20261104-132129-abba4313`: 67 passes, one failure, five skips.
  The saved-delivery diagnostic physically stored three of four exact original
  roots. The probe then incorrectly rejected an already observed base-duty
  companion doing its ordinary barricade job because it read residents from
  the active base instead of the top-level document. That lookup is corrected
  without relaxing actual duty, actor, job, lease or target checks. The last
  trace was a separate storage survey; it does not establish a doorway defect.
- `SC-Harness-20261104-134244-c9ba8c70`: 47 passes, one failure. Automatic
  startup and normal review passed, but the probe did not observe a queued
  public Send action. No post-callback state was recorded, so the precise
  decline is unproven. A later, unvalidated retry experiment was kept outside
  the worktree as a draft; the last focused-tested probe remains in use.

Current hardening also preserves native inventory IDs through a local capture
context for pending Home members, including unfinished cargo after a manual
order. Real capture/validation/restore and cross-actor/error-isolation checks
pass. Productive camp-work trunk searches now have the same bounded 75-second
allowance as storage, retaining the idle lease, CPU slices and navigation
policies. Their real Navigation regressions pass.

The focused Home gameplay/persistence, inventory identity, restore lifecycle,
generic/wood delivery, parked unloading, field-work, navigation, probe and
fixture checks pass, as do normal/debug Lua compilation and live static checks.
At that earlier boundary the physical pickup/save checkpoint had only headless
coverage, and later Lua changes still needed the full gate. Automatic startup
was restored and the owned games were closed. The subsequently resumed paired
live acceptance and final gate are recorded below.

The seed save, installed mod and original companions remain untouched.
Fixture placement and physical stock setup happen before dispatch. The remote
test observer alone uses native invisibility, restored before revisit and final
screenshots; there is no healing, God mode or zombie removal. Crew
movement, driving, boarding, parking, storage transfers and view release use
production paths. Roadside return and cold restoration are accepted; full
Phase 2's later marked-parking delivery result is recorded below.

## Completed paired driving and delivery acceptance

The matched live pair below passes the driving, marked-parking, ordinary
carried-cargo save/reload, physical delivery and duty acceptance. This combines
fresh driving evidence from the first process with cold-reload and final
delivery evidence from the second; the replay alone is not fresh-driving proof.

| Run | Result | Evidence |
| --- | --- | --- |
| `SC-Harness-20261104-140423-ce49f743` | 118 PASS, 0 failures, 0 skips | Two real seated crew drove 232.693 m with continuity checks, parked in the marked bay, stopped the engine, safely exited and completed whole-crew remote handover. Dormant/restored 8+8 native inventory IDs, health, primary-only ownership, solo map release, walls and parked-car checks passed. An ordinary LF save then verified one original cargo root physically carried by a member; the truthful `delivery` checkpoint and native flush passed, followed by normal world save and game exit. |
| `SC-Harness-20261104-141600-bbfcc4e8` | 69 PASS, 0 failures, 3 expected skips | Loaded the exact parent save. Revalidated the carried-item witness and matching Home trip, car and crew; restored 9+8 exact native items (the extra item is cargo), unchanged health and one native actor per member. All four original roots ended uniquely in permitted storage, with stored=4, pending=0, released=0, complete=true; both members resumed actual base duty. The same car remained stopped and engine-off. Normal save and exit completed. |

The child's skips are the bounded natural car-load wait, bounded crew-load
wait, and explicit diagnostic-replay scope. There is no unavailable personal
native-ID proof skip. Both halves used matching bridge and relevant Lua payloads;
the child manifest names the parent's exact target save as its source.

The common car is SQL 111; the common trip is
`1793797558888:1565020449`. Exact original cargo verified across both runs:

| Item | Native ID | Final result |
| --- | --- | --- |
| Duct tape | 447871954 | Unique item in permitted storage |
| Ratchet | 110182878 | Unique item in permitted storage |
| Nails box | 2045209642 | Unique item in permitted storage |
| Nails box | 1002387756 | Unique item in permitted storage |

Reviewed the actual parent solo-return PNG and child completed-delivery PNG:
normal primary house cutaway, living returned bodies, and a debrief reporting
four cargo items stored and base duty. Restock shortages are stated explicitly
rather than supplied artificially. The completed screenshot is retained at
`C:/ZOMBOID/outputs/send-home-02695/send-home-driving-delivered.png`.
Earlier roadside wall/car/name pixel evidence remains in its recorded run.

The final project gate found a separate detached-trade compatibility regression:
`NativeList.get()` returned an availability boolean as an extra Lua argument,
which the new item-capture function mistook for a context. Exact capture now
requires a table context. Legacy detached captures ignore the extra boolean
as before; Home's explicit table-context path is unchanged. Added trade capture
and factory-ID restore coverage passes, along with Home inventory/persistence
and normal/debug compilation checks. The failed gate was stopped and archived
as `gate-before-trade-context-fix.log`. The fresh serial gate then passed all
30 stages in 717.5 seconds (720 seconds including runtime preflight), with
throttle 1 and exit 0. Its immutable log is
`C:/ZOMBOID/outputs/send-home-02695/gate-after-driving-delivery-acceptance.log`.
Core, source/installer, gameplay, navigation, cargo, UI, both NPC adapters,
EMMA/persona controls, Workshop packaging and standalone packaging passed.
The gate's standalone validation archive SHA-256 is
`786dfd281529432bbfb24378e43c41f1b7fe787ab8b996ee6a63dcde456db2c1`.

Scope is a controlled two-person, one-car clone with one original cargo root
held at the save boundary. Prior walking, mid-drive and roadside runs provide
their separately recorded coverage. This pair does not establish every death,
fleet or nested-cargo scenario. Walking around the parked cars was slow under
the bounded debug workload; a driving-only final-approach optimization remains
a performance candidate and was not applied during these runs.

All owned test game processes exited. The installed mod and seed save were
not changed. No installation, commit, push or publication was performed.
Phase 2 driving and delivery acceptance is complete within the scope above.

Current source and payload bridge hashes match:
`142325e87da9c8aa0a4e198d7d995493540f75305678b19fbfc06b71ae1b77c9`.

Phase 0/1 walking evidence is recorded separately in
[validation-send-home-0.26.95.md](validation-send-home-0.26.95.md).
