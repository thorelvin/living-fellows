<!-- SPDX-License-Identifier: MIT -->

# Follower sitting and rest handoff

28 October 2026, following the 0.26.72 report of the first companion sitting
too often. The supplied Support snapshot catches Bob on Follow, standing,
without an active action or scheduler exception. It does not contain rest
timestamps or fatigue/endurance readings, so it cannot establish the exact
frequency or posture in that session.

A controller reproduction identified permissive behaviour: a fresh actor
could select a chair for 25-85 game minutes, keep sitting while its leader
moved nearby, and retain the posture after the rest finished. Floor rests
were offered from fatigue even though sitting does not replace sleep.

The change applies the following policy to followers on foot:

- Wait for a sustained 15-second leader pause before starting quiet activity.
- Ordinary chair rests last 15 real seconds, then stand. Their repeat cooldown
  lasts three minutes after completion; interruption also retains the cooldown
  already set when the rest began.
- Native movement or a position change interrupts active rests and passive
  seating, including while the leader stays inside the follow radius.
- Below 65% endurance, genuine recovery may last up to one minute and ends
  when native endurance reaches 90%. It never manufactures stamina or lowers
  fatigue. Follower floor rests require low endurance.
- A chair selected for reading, writing, TV or radio settles for 1.5 seconds
  before the follow-up. Seated reading remains possible, and movement releases
  its passive posture too.

Camp sleep, camp leisure and shared-vehicle passenger reading retain their
existing policy. A different supervisor owner, including medical care, is
protected from the follower-resume hook. All standing uses the existing native
seating exit and action-supervisor release paths. No save schema or native
bridge change is required.

Support now reports each companion's downtime kind/phase, real and game-time
duration, fatigue, endurance, follower-pause reason and repeat cooldown. The
snapshot does not initialise commands, create an idle controller, select an
activity or alter its timers.

Completion keeps the rest controller until the native get-up transition has
finished, releasing its stationary-pose protection before native root motion.
Cancellation retains a pending exit for subsequent polls, even if the leader
stops again. Merely having an eligible book does not extend an ordinary
follower chair rest; a specifically selected seated follow-up keeps the pose.

## Verification

The focused follower-sitting harness has 51 checks using the real Downtime and
ActionSupervisor modules. It covers stillness delay, real/game clocks, repeat
cooldown, native movement flags and position-only movement, active and passive
seating, recovery completion and maximum duration, floor eligibility, explicit
orders, danger, shared-car passengers, medical ownership and asynchronous
get-up completion/cancellation. Existing seat
route and reading-session checks also pass.

The gameplay suite passes, including decision arbitration, camp sleep and
seated reading regressions. The final full project gate passes all 29 stages,
including core/Support diagnostics, 119 decision-arbitration checks, normal
and debug Lua compilation, packaging and installer checks.
The final native acceptance passes. It uses a real
companion, stock seat and player walk action in the existing disposable
clone; its second controlled chair entry bypasses candidate cooldown only to
exercise interruption without waiting three minutes. Production cooldown is
checked separately.

The selected native object is `fixtures_bathroom_01_0`, accepted by the stock
SeatingManager. The run verifies the stillness delay, entered furniture pose,
15-second rest, completed native standing, repeat cooldown and interruption by
a real `ISWalkToTimedAction` inside the follow radius. All screenshots are
unaltered engine captures; a pre-existing character panel partly obscures the
scene, so the native pose and supervisor assertions are the primary evidence.

The native bridge is unchanged at SHA256
`26b1c9eafafcbdbf8c7f772cb6ffcabebf6d9dfc997bbf2c653c54d4528a7de8`.
This validation run did not install into the player's mod folder.

- [Full project gate](../artifacts/emma/native-acceptance/follower-sitting-project-gate.log)
- [Native evidence](../artifacts/emma/native-acceptance/follower-sitting-evidence.log)
- [Seated pause](../artifacts/emma/native-acceptance/emma-follower-sitting-short-pause.png)
- [Finished pause](../artifacts/emma/native-acceptance/emma-follower-sitting-finished.png)
- [Standing after nearby leader movement](../artifacts/emma/native-acceptance/emma-follower-sitting-follow-resumed.png)
