<!-- SPDX-License-Identifier: MIT -->

# Send home: Phase 0 and Phase 1 validation

Date: 2026-11-03. Branch: `living_fellows/0.26.95`, based on `8ea53d34`.
Project Zomboid 42.21.0, native protocol `42.21-isocompanion-28`.

Scope is distant view teardown and walking/UI. Driving, radio recall and the
later field-guide update remain separate phases. Ground-floor departure and
camp core, at most four travellers, and a 1,000-meter walking limit apply.

## Automated checks

- Home-trip gameplay: roster and occupied-view blockers, complete surviving
  crew arrival, nearby recall, changed camp, bounded route planning, and active
  save compatibility. Leader/follower casualty cases require a ready, retained
  corpse before handover and preserve the surviving crew's obligations.
- Persistence: fresh capture and durable acknowledgement before detachment;
  failed writes/cancellation/retry; partial detachment; fresh unrelated-world
  saves during retirement; exact item IDs; primary-owned restoration; and
  command serial continuity through real restore initialization.
- Native bridge: remote arrival, public exposure and lighting retirement/
  lifecycle tests pass. Existing joined-view release checks are unchanged.
- UI: narrow layout, fixed footer/blocker, changing roster between preview and
  Send, cached review, observed leader information, and information versus
  nearby command authority. Unrelated global field work stays off the active
  home crew's card.
- Negative controls must fail for five travellers, leader-only arrival and
  omission of the blocker label; they leave production source unchanged.
- Final serial project gate: 30/30 passed, including all 93 core harnesses,
  gameplay, UI, source/installer, live-harness static, both NPC adapters,
  persona controls, Workshop packaging and standalone packaging.

Focused checks were rerun after the casualty and stale-preview fixes: gameplay,
UI, real-UI observation, live probe regression, normal/debug Lua compilation,
live Lua compilation and release synchronization all passed.

## Completed live walking scenario

Runs retained below `build/live-sandbox-runs/`, outside version control:

| Run | Result |
| --- | --- |
| `SC-Harness-20261103-195734-cc49e9e3` | Three fresh native recruits, ordinary squad assignment, public review/Send button, walking departure about 191 m from camp, save after about 25 m: 51 passes, zero failures. |
| `SC-Harness-20261103-200247-7919f63d` | Cold mid-trip resume, about 169 m newly sampled movement with continuity checks, full crew arrival, distant handover, primary-only revisit, exact items/vitals/names/no duplicates, and all three returning to real base duty: 55 passes, zero failures, one separate pixel-review reminder. |
| `SC-Harness-20261103-201101-637316f8` | Independent cold mid-trip resume through the same real walking path, then save/flush/normal quit after verified dormant arrival while the main player remains about 199 m away: 26 passes, zero failures. |
| `SC-Harness-20261103-201539-bf854326` | Cold dormant reload: all three remain absent/pending until primary camp ownership, then exact items/vitals/names and one native instance each, surviving handover ownership, four wall/two car checks and all three returning to base duty: 51 passes, zero failures, one separate pixel-review reminder. |
| `SC-Harness-20261103-202157-5f4a4792` | Repeated cold dormant reload after pending-handover UI filtering: 51 passes, zero failures, one pixel-review reminder. |
| `SC-Harness-20261103-202848-42344ed7` | Single native recruit from about 191 m out, public sheet/Send, physical walk and complete remote arrival, exact nine-item restoration, actual base duty, and a final panel-free scene: 60 passes, zero failures, one pixel-review reminder. |
| `SC-Harness-20261103-210027-0ddd2af1` | Final three-person dormant reload and base-duty verification, followed by separate postproof car/name camera positions: 62 passes, zero failures, two separate review/minimap reminders. |

The second run verified all 26 arrival inventory items (9, 8 and 9) retain
their exact native IDs, types and conditions through dormant restoration.
Each restored actor has one scheduled native instance and the same stable LF
identity. The main player's native identity, player slot and camera return to
solo; secondary chunks and lighting retire. Four native wall witnesses match
their original primary-view state. Both original stopped vehicles retain their
SQL identities, remain stopped and report visible.

The source save and installed mod are untouched. The original companions remain
in each cloned world. Fixture positioning occurs before dispatch and when the
main player revisits; crew travel is production movement, without a movement
hook or teleport during the mission. No supplies or arrival result are invented.
Camp shortages appear in the debrief, and the normal integration eventually
returns all three to actual base duty.

## Screenshot review and limits

The three-person review sheet, the final duty/debrief and the single-person
panel-free scene were reviewed. The selected crew, route, fixed Send/Back footer
and arrival/shortage reporting fit the docked panel. After the settled duty
capture the card correctly says everyone is on base duty, with zero supplies
restocked and the real shortages listed. The scene shows the house's living/
kitchen area cutting away and rendering correctly with the actual main player.

The first scene did not frame both parked cars and the returned names fully.
A final cloned run completed the same original-pose assertions and actual base
duty, then moved only the main observer onto existing free, primary-owned ground
near each car and the first returned companion. These camera fixtures run after
the mission is idle and all required work is verified; no crew, car, inventory,
lighting or visibility flag is changed. The postproof captures show both original
cars rendering clearly, and all three returned bodies with their `HomeOne`,
`HomeThree` and `HomeTwo` overhead names. Pixel review passed for those images.

The final harness summary keeps its separate manual pixel-review reminder and
an optional minimap-API skip. Neither is a gameplay failure. The reviewed images
are unobscured. After the full gate, only the test probe's camera sequence and
its regression changed; probe regression, normal/debug live Lua checks and the
complete live-harness static suite were rerun successfully before this live run.

Unmodified PNG copies are retained outside version control at
`C:/ZOMBOID/outputs/send-home-02695/`: `send-home-review-three.png`,
`send-home-debrief.png`, `send-home-solo-scene.png`,
`send-home-returned-cars.png`, `send-home-returned-cars-2.png` and
`send-home-returned-names.png`.

- Live casualty/reanimation, driving and radio scenarios are not claimed.

Final gate evidence: `C:/ZOMBOID/outputs/send-home-02695/gate-final.log`,
`PROJECT_TEST_PASS`, exit 0, about 1,074 seconds with `jobs=1`. No game client
ran alongside it. The standalone package passed at version `0.26.95` with
SHA-256 `ecc05d05e18c35cd9dca7ad73f610e0b2e71fb504f1b34c30534c1da3bc45c74`.

The rebuilt source and payload bridge JARs match:
`72db9db962fe4cb290b875deedb55b7e1e3c526d2a9d5e3a8ea36d7d0511fd2e`.
