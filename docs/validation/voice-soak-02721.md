<!-- SPDX-License-Identifier: MIT -->
# Companion voice depth: 0.27.21

The 60-day camp runs the production Lua chooser, scene scheduler, history and
save adapters in the game's Kahlua VM. Native world discovery is replaced by
a known camp boundary and three harmless reading actions. This is a simulated
camp, not the live-save acceptance check.

| Measure | Frozen pre-V1 code | Current implementation |
|---|---:|---:|
| Spoken lines | 4,506 | 4,307 |
| Specific save-event recall | 0 | 815 (18.9%) |
| Companion recall shares | 0% each | 18.8%, 20.2%, 17.8% |
| Unsupported recall claims | 0 identified | 0 |
| Repeats under three game days, pools >=8 | 3,653 | 0 |
| Scenes | 1,078, all two beats | 723, all four beats |
| Major events with one completed reaction | 0/26 | 26/26 |
| Speaker, reply-tag or cadence errors | Legacy shape only | 0 |
| Tagged teasing inside three-day grief window | Unclassified | 0 |
| Light references to the dead before day seven | Unclassified | 0 |
| Speech during paused updates | Not exercised | 0 |
| Largest packed record including conservative overhead | None | 1,593 bytes |

Final evidence: `build/test-results/20261115-041738-898805/Behaviour-lua.log`,
speech hash `426241491`. Eight weekly reloads and eight five-minute pauses are exercised.
Game time advances 24 times faster than active wall time. Seventeen negative
controls reject broken shares, knowledge, repetition, scene shapes/cadence,
aftermath coverage, tone, pause handling and save bounds. The final clock fix
also tests a pause in which callbacks stop entirely, using day length to bound
the credit earned by observed game progress. All five release checks pass in
that run (392.0 seconds). The earlier development replay had 4,301 lines and
820 recalls; the final clock calculation changes the deterministic schedule.

The frozen baseline was replayed after the harness extensions against archived
pre-V1 sources (`a3e1f563`): `build/voice-soak/20261115-041331-4fccbf` still
produces hash `1537253361`. Historical sources do not receive the new pause
injection or any new production module. The baseline speech was not rewritten.

Specific recall is checked independently against the actual retained ledger
and speaker's knowledge. The named-token compiler supplies packet receipts.
Listeners retain which details were actually spoken, including whether a date
was given, and the first-hand teller's name. Retellings remain hearsay and do
not seed new first-hand knowledge. Restore invalidates cached world history.

Optional speech uses compact counted hashes and four daily Bloom filters.
The filters can conservatively delay a fresh line, and prevent a recent line
from reappearing after its exact-count entry is evicted. Smaller pools retain
their bounded variety window; their minimum observed repeat distance is six
game hours. Immediate threat and withdrawal explanations retain availability.
No actual speech text or per-order history is stored in command fields.

The content census records 834 unique authored lines, plus clean twins,
including all 25 profession, six fear and six value continuations. Busy follow
and routine pools have day 7/30/100 and trusted/close/family layers. Deeper
background stories require measured game time together as well as the tier;
old saves do not gain invented time together. A reveal commits only after
accepted speech. All new content passes ASCII, placeholder and immersion lint.

The sample week is in `voice-soak-02721-week.txt`. Reviewing it led to warmer
death-memory replies, explicit event wording, sentence capitalization and
wider listener/closing pools. A story is skipped before starting when no fresh
reply or closing is available. Ordinary camp cards can use that speech slot.
The native cloned-camp check and its transcript remain the next phase.
