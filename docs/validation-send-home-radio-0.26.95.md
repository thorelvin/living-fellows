# Send Home: radio acceptance, 0.26.95

The Phase 3 change adds portable-radio Come back, Hold, Status and Push on to
the existing Home trip. The driving/delivery acceptance remains recorded in
`validation-send-home-drive-0.26.95.md`; this record covers radio control.

## Automated checks

Root ran all checks serially, with a 256 MB / two-CPU Java limit and no game
running alongside them. Focused gameplay, persistence, Home UI, Home car,
managed driving, live-probe regressions and normal/debug Lua compilation pass.
The final project gate is recorded below after live acceptance.

The focused regressions cover:

- Exact main-player/trip/leader/device binding, equipment, power, battery,
  two-way mode, channel, mute and both directions' range.
- One queued call; no action without both native command and return-text
  receipts; no replay after cancellation or changing the physical radio.
- Exceptions before the command receipt, before the return acknowledgement,
  and inside authorized application. Only request-owned temporary fields are
  cleared; unrelated report ownership is preserved.
- Queued-call cancellation, reset and save/reload without replaying a command
  or retaining temporary authorization.
- Call-time recall coordinates, whole-crew Follow/solo release, Hold then
  Come back, blocked-route decisions and legacy expedition isolation.
- Driving Hold verifies a stationary engine-off car and preserves seats and
  cargo. Push on creates a fresh managed route; cold restore revalidates actual
  car/crew state. Missing seats can brake only the exact owned managed job;
  stale actors, cars, drivers and supervisor tokens cannot stop another job.
- Narrow radio-card layout, missing-link explanations, pending controls,
  dated reports, stale-trip callbacks, native replies superseding old local
  notices and no premature success note.
- Live-observer controls reject stale ACK IDs/verbs, unacknowledged calls,
  replaced cargo identities and a running engine.

## Live method

Every run clones `LF-Skills5-Test-2026-10-29`; the seed and installed mod are
untouched. One real client runs at 1280 × 720, 30 FPS, with a 3 GB heap and four
CPU limit. The existing loading gate enters the world without desktop input.

Two ordinary LF recruits receive real powered native walkies before departure.
After the first run, the radio fixture also gives each recruit a real
one-handed Machete before capturing item/health baselines and dispatching. No
skills or health are changed, no zombies are removed, and no travelling crew,
car or cargo is teleported, recreated or topped up. The fixed observer uses
clone-only ghost/invisible flags, restored before final screenshots.

The deferred recruited-actor fixture bypasses the ordinary Recruit command's
final diary hook. The final fixture calls that same production recruitment
callback before its inventory baseline; it does not force diary decisions,
create replacement books or drive the background scheduler.

The public Send Home sheet starts the trip. After actual movement the probe
checks a real channel mismatch, Status, Hold, Push on, a second Hold, and Come
back. Every queued call checks the busy refusal and its exact native return
acknowledgement. Driving adds actual crew-seat ownership, engine-off holds,
same-car resumed movement, and a bounded exact cargo identity/location audit.
Recall must finish with the original healthy unseated actors following at the
captured call point, one native instance each, and the main player's solo view.

### Initial unarmed run

`SC-Harness-20261104-150824-fe55382e`: 69 PASS, 1 FAIL, 1 SKIP. All five radio
orders received native acknowledgements; both walking holds were stationary
and Push on produced actual movement. The run failed the unchanged healthy
leader criterion during a real zombie encounter on recall (the UI showed 99%
health). The recruit was not healed and the result is retained as a failure.
The skip records a bounded public review retry, not a missing radio proof.

### Walking recall

`SC-Harness-20261104-152020-c9bbba95`: 71 PASS, 1 FAIL, 1 review-retry SKIP.
All orders were acknowledged and the original living crew returned to Follow
and solo view. The strict inventory check failed on a newly created item.
Read-only inspection of the saved native player blob identified that exact
item as the leader's authored diary, with the matching `SC_PersonalOwnerId`
and `:diary:1` key. It is normal diary initialization, not a replaced cargo
item. This result is retained as a failed fixture run.

`SC-Harness-20261104-152800-6ab2bd4c` failed before departure while waiting
30 seconds for background diary initialization. No radio trip was exercised.
The fixture now runs the normal recruitment hook before the baseline rather
than depending on background scheduling. The strict identity and
item-count checks are unchanged.

`SC-Harness-20261104-153221-8102a2c4`: **80 PASS, 0 FAIL, 1 review-retry
SKIP**, normal client exit. Status, both stationary Holds, actual resumed
movement and Come back all received exact native acknowledgements. Both
original companions returned unseated to Follow at the captured call point,
one native actor each, with the same ten item IDs/types/conditions and identical
actor/body-part health. The native main-player solo checks passed.

The immediate final PNG still contains the preceding split-screen frame; it
is not claimed as solo pixel evidence. The observer now waits at least one
second and 30 real rendered frames after release before that screenshot. The
accepted Holding PNG is used in the Field Guide (original SHA-256
`387059ded50a13d86d52b3d55db3be562589e5da0480efaa1bd02ea10f83755b`).

A subsequent independent review found Hold-after-Come-back could leave recall
movement active. Focused walking and driving regressions now verify that Hold
suppresses both travel and finish, Push on keeps the captured recall target,
and a new Come back retargets. Driving Hold is refused during the already
active physical stop/unseat stage. The final driving run below uses these
fixes; that additional command sequence is automated evidence, not claimed as
part of the earlier walking live scenario.

### Driving recall

`SC-Harness-20261104-154019-98e05904`: **226 PASS assertions, 0 FAIL, 0
SKIP**, normal client exit. Some identity assertions repeat while the bounded
cargo audit advances; this is not a count of distinct scenarios.

- Both exact crew actors occupied their assigned native seats in the real
  car (SQL 111). Both two-second engine-off holds drifted only about 0.00049 m.
- Push on retained that same car and both physical seat owners, then moved
  another 8.05 m before the second Hold and Come back.
- The original crew returned unseated to Follow with unchanged health and
  exactly the original eleven and ten inventory items, including native IDs,
  types and conditions. No camp integration or delivery was claimed.
- The same car remained stationary with its engine off. The retained bounded
  audit found each original cargo item exactly once in that trunk, matching
  native ID, stable ID and type: 166126833, 1289368451, 1319723524, 1214239642.
- After at least one second and 30 rendered frames, native diagnostics showed
  one player, empty secondary slot, primary instance/camera/frame, completed
  primary view restore and retired secondary lighting. The actual final PNG
  shows one full-width world view and both returned companions' overhead names.

The driving Holding PNG was also inspected: all four radio controls fit at
1280 × 720, with the disabled Hold explanation and the explicit warning that
Come back leaves the stopped car and cargo behind. The dated report retains
its actual received state rather than claiming a newer transmission.

## Field Guide and final gate

Chapter 17, “Sending Someone Home”, includes the accepted real driving review
and delivered-cargo screenshots, the accepted Holding screenshot, and walking/driving/radio requirements and
truthful pending-cargo behavior. Its canonical HTML fragments and generated
self-contained manual are updated. The final builder passes with 116 embedded
images and 79 unique IDs; release/protocol references match 0.26.95 and
`42.21-isocompanion-29`. No publication is performed by this task.

Final Phase 3 project gate: **30/30 PASS**, serial throttle 1, 715.6 seconds
for the stages (718 seconds including runtime preflight), exit 0. Core,
source, gameplay, navigation, storage, combat, UI, live-harness static,
Bandits, A-Life, terminal persona, Workshop and standalone checks all pass.

The immutable result log is
`C:/ZOMBOID/outputs/send-home-02695/gate-after-radio-acceptance.log`, SHA-256
`3047887f2a49d0a180be5c1e425970ed6836913878937307a51c8c86e0d05e70`.
The standalone validation package reports SHA-256
`68df5405bef3f990fe293cc39076f6b39d76bff1a45897df49e49d7bb7ce292f`.
The native bridge is unchanged from accepted Phase 2, SHA-256
`142325e87da9c8aa0a4e198d7d995493540f75305678b19fbfc06b71ae1b77c9`.

Final process inspection finds no Project Zomboid/Java client or test JVM
left running. Installation, commit, push and Field Guide publication were
not part of this Phase 3 implementation task.
