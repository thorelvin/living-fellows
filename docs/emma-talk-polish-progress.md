<!-- SPDX-License-Identifier: MIT -->
# Talking with Living Fellows: implementation evidence

Objective: implement `C:\ZOMBOID\plan-emma-talk-polish.md` in full. The user's
2026-11-15 instruction selects `living_fellows/0.27.21` as the work branch.
Starting commit: `84123716` on `living_fellows/0.27.20`.

The plan's complete scope remains required. Phase completion is unproven until
its production behavior, negative controls and required artifacts are verified.
No care turn from the user's conversations may enter a corpus, report or log.
Zombie navigation remains native under `AGENTS.md`.

Build sequence: A, E, F, G, H, B, C, D. H is the live companion verification
after G. Each phase retains a separate evidence checkpoint on the work branch.
Release packaging and playground rebuilding remain required deliverables.

| Requirement | Required evidence | State |
|---|---|---|
| A baseline: seven computer harnesses | Actual results against the production load order, before behavior changes | Recorded, repaired, wired and passing |
| 3.1 real talk | All recovered visible turns, prior-reply context, generated variants and seven replay chains; care excluded; baseline committed before behavior | Done: 72 turns, 288 variants, seven chains |
| Predictions | 188 EMMA and 41 persona turns; persona reply-content scoring; per-row non-regression baseline | Phase A baseline and floor done; final targets remain pending |
| 3.14 locks | All lock kinds including Story, EMMA, Search, Rival and password locks; >=95%, exact-password/code safety, negative controls | Done: 74/74; wrong/unheard codes, menu digits and exact passwords checked |
| 3.3 questions | One-turn expectations, help-me answers, person cancellation, expanded yes/no; unchanged care | Done |
| 3.8-3.9 misses | Every miss offers useful choices; once-session menu; bounded context-aware suggestions and logging; negative controls | Done for Phase A; hooks/noun-index integration continues in B/C |
| 3.12 persona quick fixes | Question/name guard, semantic repeat identity, all seven harnesses in Interface | Done; own-word hooks and role-play remain B |
| Phase A verification | Improved baseline scores with no lost passing row, care 100%, Windows PowerShell 5.1 full gate, rebuilt playground | Full release gate and headless checks pass; browser visual check/user session pending |
| V7 baseline | Real Kahlua 60-day simulator, separate game/real clocks, metrics and sample-week transcript before new speech | Done; historical pre-V1 replay and current facts-only replay match exactly |
| V1 ledger | Flat facts and witnesses, observed event producers, 96 history/24 landmarks, small memory references, old-save and malformed-field restore | Done; 36 ledger checks and full release gate pass |
| V3 scenes | 3-6 tagged beats, 2-3 speakers, personality/relation branches, one party scene, shared budget, immediate cancellation, two-clock scheduling | Done; focused gates and full release checks pass |
| V5 relationships | Reason-matched arguments, bounded grudges, reconciliation, modest companion comfort | Done; focused gates and full release checks pass |
| V4 aftermath | One deferred group reaction per death, close call, homecoming or fought-off alarm; affected speaker first | Done; 26/26 simulated events and full release checks pass |
| V2 recall | Evidence packets and named tokens, real places/relative dates, knowledge and told-by discipline, place/anniversary/similarity/Memory/camp triggers | Done; 53 focused checks, strict soak and final release gate pass |
| V6 variety | Persisted bounded hashes/counts, least-heard selection, half-pool/up-to-eight window, age/tier layers, additional background stories | Done; 244 focused checks, strict soak and full release gate pass |
| Voice content | Approximately 700-800 new lines plus clean twins; scene/recall/aftermath/argument depth and immersion lint | 834 unique lines plus clean twins; 3,772 scene/content checks pass |
| Voice gates | 12.5%-33.3% specific recall, zero false claims, >=3-day no-repeat for pools >=8, scene shape/cadence, aftermath coverage, grief windows, bounded work/save | Strict 60-day run and 17 negative controls pass; wired into Behaviour |
| H | Cloned-camp live check, readable transcript, tuning | Done; two native observations, transcript and clock correction recorded below |
| 3.2 hooks | Declared/derived hooks for all EMMA/persona reply pools, facet and pronoun resolution, salient-term lint with negative control | Done in B; C expands the catalog to the practical reference |
| 3.6-3.7 world and roles | Lore facets, checked place facts, non-roster why/how, session-only role memory, practical conditions, persona roles | Done in B; final persona/content targets remain D |
| 3.11 weather | Condition/season-tagged quips, truthful selection and filter-removal negative control | Done in B; native cloud provider and filter removal control pass |
| 3.4-3.5 topics | Once-built bounded noun/synonym index and six facets; complete requested survival coverage; verified Build 42.22 source comments | Done in C: 637 entries, 27 topics, source receipt, cold-load smoke and full release gate |
| 3.10/3.13 | Guide/fact repetition handling, requested new situations, companion identity, contextual counts, real-life kindness, no private persistence | Done in C; focused Interface and full release gate pass |
| D | Independent sealed holdout >=80%, real-talk >=90%/wrong <=3%, predictions >=85%, persona >=95%, all chains converge by second turn, care 100% and no existing-corpus regression | Public targets pass; frozen blind content review and final checkpoint pending |
| Playground | Real modules rebuilt after every phase, all four persona choices, browser verification and user session | Rebuilt through D; four-voice/privacy checks pass; visual/user session explicitly deferred |

Independent blind set H was authored from section 1 only in
`build/emma-talk-polish/blind-h`. Its first results and the subsequent independent
rounds are recorded in `docs/validation/emma-blind-02721.md`.

## Baseline checkpoint (before production changes)

Starting commit `84123716`; actual game Kahlua VM, full production terminal load
order. The original public export and the prior session's public-only transcript
contain **72** turns (36 + 2 + 34), rather than the plan's stated 71. Every
recovered public turn is retained. Care and private note entries were excluded
before fixture extraction; a private preceding reply is never copied.

| Set | Correct / total |
|---|---|
| Real turns, reply contracts | 42 / 72 |
| Generated public variants | 159 / 288 |
| EMMA predictions | 74 / 188 |
| Persona predictions, content contracts | 18 / 41 |
| Rephrase chains converging by turn two | 4 / 7 |
| Expanded lock predictions | 23 / 74 |

The plan's older percentages used different scoring and a different release;
they are not substituted for this observed baseline. Frozen passing row IDs in
`tests/fixtures/emma-talk-polish/baseline.json` prohibit row-level regressions.
The new corpus runs in Interface before any production changes land.

Scoring correction: the first evaluator incorrectly counted an unresolved noun
echo as a content answer. The original run's recorded intents identify those
14 invalid row matches and one invalid trapping-chain match. They are excluded
from the corrected baseline above; every valid original passing row is kept.
This corrects the measurement, not a production regression.

Seven-harness run: system and lore pass. Terminal, knowledge and conversation
expect some older routes (help versus help_me, reference versus survival guide,
and overlapping farming guides); grid expects a controller response where the
production parser chooses its shutoff reference; persona expects Ellis to
reflect a line now handled by care. These failures were preserved in
`build/emma-talk-polish/harness-20261115-010430-30bd65` before repairs.

The sealed independent H set has 145 turns in 60 conversations. SHA256:
`6a902430b8406e08a536f587ac09b1b12871c76fd269ea55b0cb18511f5ae3a9`.

## Phase A checkpoint

Real turns improve to 44/72, variants 166/288, EMMA predictions 78/188,
personas 18/41 by content, chains 4/7, locks 74/74. The frozen row floor now
also retains Phase A passes. B/C/D still owe the plan's final accuracy targets.

All five release checks pass under Windows PowerShell 5.1, including the seven
older harnesses: `build/test-results/20261115-013924-6915c0` (333.2 seconds).
The six base-parser/archive harnesses retain their historical module isolation;
the production parser and all four care routes run in the full-load groups.
Persona tests now assert the shared private care contract rather than obsolete
literal wording, and use neutral statements to test ordinary reflection.

The four-voice playground was rebuilt from production modules and checked in
Lua 5.3, including care privacy on all four voices. Its local file is
`C:\ZOMBOID\plan-emma-probe\web\emma-playground-0.27.21-phase-a.html`.
Browser visual verification is unperformed: the browser tool explicitly rejected
local `file:` navigation. No workaround was attempted. A user session has been
requested and remains pending. Release ZIPs were built as 0.27.21; work continues
on this branch under the user's release instruction.

## Phase E checkpoint

The authoritative 60-day baseline uses registered actors with SurvivorDesc
names. It was replayed against archived pre-V1 sources (`a3e1f563`) after those
fixture corrections. Hash `1537253361`: 4,506 lines, 1,078 two-beat scenes,
3,653 repeats inside three game days, zero specific recall and no group
aftermaths. The current V1 implementation reproduces the entire speech hash.
See `docs/validation/voice-soak-baseline.md` and its sample-week transcript.

The ledger keeps separate participants and witnesses, flat names and details,
96 recent rows, 24 permanent landmarks and bounded on-screen told-by receipts.
Companion memories hold event IDs. Producers cover introductions, recruitment,
observed bites, player restriction/release (with accepted cover distinguished),
expedition returns with verified cargo counts, fought-off alarms, closed
graves, first camp nights and day 7/30/100 milestones. Symptom-only infection
does not manufacture a witnessed bite. Old saves never gain invented past
milestones. Existing diary adapters retain the event's optional detail tokens.

The restore harness loads a document exported by the actual 0.27.18 modules
and compares every old field. Malformed optional facts are quarantined without
mutating the input. A legal full ledger exposed the old copy-entry limit; the
bounded budget is now 65,536 entries, with all individual store caps retained.
The full-capacity world remains saveable. All 36 ledger checks pass.

All five Windows PowerShell 5.1 release checks pass:
`build/test-results/20261115-023417-0dbfb7` (330.9 seconds). The exact comparison
passes in `build/voice-soak/20261115-023417-e69405`. Phase E adds no authored
companion speech. F/G still owe the scene, recall, repeat, aftermath and tone
targets; zero tagged-tone errors in legacy untagged speech proves none of them.

## Phase F checkpoint

The generalized scene occupies the existing `party.exchange` slot. Authored
turns accept explicit reply tags; B branches by personality and pair tension.
The engine supports three to six beats and two or three speakers. Default camp
cards have four beats. Starts use two game hours and a three-minute active wall
clock floor, both scaled by the existing chatter option. Paused time earns no
cooldown credit. Scenes spend the existing party budget and exclude work and
guard orders. Existing idle face poses are the only optional movement.

The focused harness passes 2,687 checks, including catalog/clean-twin
lint, three/six-beat boundaries, wrong-tag and missing-knowledge controls,
danger/order/urgent-speech cancellation, paused-time scheduling, bounded saved
grudges, early reconciliation after shared escape, modest comfort and four
aftermath families. New danger restarts the thirty-second calm interval.
All 581 authored lines have clean twins. No new zombie navigation is involved.

Argument requests use actual pair memories. A generic worked-together memory
cannot become a bad run. Bite, flight, food and door accusations additionally
require a ledger row known to both people, identifying the accused as the
source; food must explicitly belong to the shared reserve. These reason
adapters do not infer a concealed bite from private infection state or create
new theft/door/fleeing simulations. The existing run producer supplies the
currently observed run reason. Shoves remain rare, nearby, healthy-companion
outcomes of the existing autonomy action, after speech finishes.

The 60-day development run records 723 completed scenes (all four beats),
26/26 event reactions, no unsupported recall receipts and no reply-tag errors.
Exact repeats and the final recall share still fail their eventual G gates;
this phase does not claim those targets. Evidence:
`build/voice-soak/20261115-031039-3fc7c2`. The simulator's alarm outcome was
corrected to the actual producer's `all_clear`; the frozen pre-V1 baseline
remains unchanged. Lifecycle and Interface checks pass in
`build/test-results/20261115-030334-96cc74`.

All five Windows PowerShell 5.1 release checks pass in
`build/test-results/20261115-031039-a49bbe` (336.4 seconds). The focused scene
receipt is `build/voice-soak/20261115-031008-700acb`. Phase F's four-voice
playground was rebuilt and passes all four Lua/privacy checks at
`C:\ZOMBOID\plan-emma-probe\web\emma-playground-0.27.21-phase-f.html`.
The user will test the playground later; work on G continues meanwhile.

## Phase G checkpoint

Spoken recall uses the diary compiler's named tokens, evidence prerequisites
and assertion receipts. First-hand participants/witnesses can teach listeners
only facts actually used in their accepted spoken packet. Heard accounts save
the teller and those fields; an unspoken date remains unknown. Retellings are
explicit hearsay and cannot seed another person's first stored account. The
fourth beat remains available to a listener who cannot independently recall
the event. Death memories use supportive replies rather than factual quibbles.

Place triggers compare stable native building/zone bounds, anniversaries fire
at a week/month, and a new close call can bring up an older one. Talk Memory
uses the weighted ledger. Confirmed-kill episodes retain a count/weapon only
when their locations/weapons support that claim; a witness must see the whole
sequence to quote its count. Restoring history clears the recall cache.

Saved speech variety uses compact hashes, least-heard selection and a widened
window. Four bounded daily filters protect the three-day interval after exact
count entries are evicted. The record stays below two KB per companion and
never enters strict-copied command state. The only added command fields are
three existing-style reveal flags. Professions, fears and values have 37 new
continuations, gated by measured game time together and relationship tier;
busy routine/follow pools have day 7/30/100 layers. Reveals commit on delivery.

The final strict run produces 4,307 lines, including 815 specific recalls
(18.9%). Individual shares are 18.8%, 20.2% and 17.8%. There are no large-pool repeat
violations, unsupported claims, speaker/tag/cadence errors, grief-tone errors
or paused utterances. All 723 scenes complete four beats, and all 26 events
receive one group reaction. Eight reloads and eight five-minute pauses are
included. See `docs/validation/voice-soak-02721.md` and its readable week.

All five release checks passed in
`build/test-results/20261115-041001-aa7da4` (394.8 seconds). A final clock check
found that a pause can stop callbacks; active credit now also uses game
progress/day length, and the no-callback pause negative control passes. The
final release gate passes with that correction in
`build/test-results/20261115-041738-898805` (392.0 seconds), including the full
60-day strict simulation in Behaviour and the combined maximum ledger/pairs/
heard-facts/64-companion voice save. The four-voice Phase G
playground was rebuilt and passes its Lua/privacy checks. Browser visual
verification remains unavailable under the earlier local-file policy block.

## Phase H checkpoint

The native engine check is complete. An eleven-minute normal-speed cloned-camp
observation passed ten checks and completed a four-beat comfort scene. A second
400-second accelerated observation passed eleven checks and completed another;
two interrupted scenes yielded to actual storage/scavenging work. Starts kept
the three-minute active-time floor. See `docs/validation/voice-native-02721.md`
for the transcript, scope and limits. The current user save was not loaded.

Native Kahlua exposed a multiple-return error in the new day-length clock
reader. The reader now takes exactly one value, and both focused harnesses
provide the real numeric getter. Interruption diagnostics identify the speech
or owned action that stopped a scene. The read-only observer remains a test
helper rather than shipped mod code.

All five Windows PowerShell 5.1 release checks pass in
`build/test-results/20261115-050300-9f0334` (461.5 seconds). The Phase H
four-voice playground passes its Lua/privacy checks at
`C:\ZOMBOID\plan-emma-probe\web\emma-playground-0.27.21-phase-h.html`.
The user will test later and explicitly asked work to continue. B/C/D remain.

## Phase B checkpoint

Public-reply hooks cover EMMA's language/glitch pools, the dated archive and all
three persona pools. Their static lint and removal controls pass. Complete
questions and persona commands keep their own path. Archive facets retain
honest limits, known geography is checked against the installed game text,
and bare lore continuation advances through the existing related-file reader.
Session role claims use each voice and cannot supply access credentials.
Private names, notes, care and roles do not enter public hook/miss receipts.

Weather quips now use truthful sky/season/temperature/daylight conditions;
cloud cover has a native reader and missing data cannot imply clear skies.
Unverified heat, sound and track claims are retired. Removing the real filter
produces invalid selections in its negative control. See
`docs/validation/emma-hooks-02721.md` for scope and evidence.

The release gate passes all five checks in
`build/test-results/20261115-053555-daec88` (447.6 seconds). Focused hook checks:
4,131 over 2,783 authored entries. Public scores: real 48/72, variants 179/288,
EMMA predictions 82/188, personas 19/41, chains 5/7, locks 74/74. All 407 passing
rows are retained as the new cumulative floor. The final target gates still
belong to C/D. The rebuilt Phase B playground passes four-voice/privacy checks;
the user's deferred playground test remains deferred. C/D remain unfinished.

## Phase C checkpoint

The 637-entry bounded noun index reaches 27 practical topics with six facets.
In-world answers precede marked exact instructions; repeated exact requests
remain a short summary rather than alternating back to the same recipe.
Named injuries, contextual counts, fire, visitors, camp moves, broadcasts,
generator readings and expedition contact retain their subjects. Existing
checked requests and relationship follow-ups retain their original readers.
Kindness and grief are private. See `docs/validation/emma-reference-02721.md`.

All 27 topics cite checked sources. The verifier records 32 source hashes and
14 selected exact facts from installed Build 42.22.2. A disposable native cold
load passes all topics and a three-turn reference flow after catching and
fixing the missing “one” pronoun. It does not claim rendered-terminal coverage.

The full Windows PowerShell 5.1 release gate passes all five checks in
`build/test-results/20261115-080638-878f07` (456.9 seconds). Public scores:
72/72 real, 268/288 variants, 186/188 EMMA, 19/41 personas, 7/7 chains, 74/74
locks. All 626 passing row IDs are retained without removing the prior 407.
The older corpus improves to 5,217/5,417 (96.31%), with 100 wrong routes,
care 528/528, zero false alarms and zero protected-input changes. Its three
published regression sets all pass. Hook/reference checks total 4,681/606.

The Phase C four-voice playground passes its Lua/privacy checks. The user's
manual test stays deferred. D remains: rare-computer content, the sealed
holdout, final gates and release delivery. The holdout is still unopened.

## Phase D checkpoint — unfinished

The shared bounded public-context reader and answer planner now handle
definitions, alternatives, procedures, conditions, corrections and private
conversational roles across all four voices. The native context, hook,
reference and persona checks pass. Opened H1–H5 pass their automatic gates;
all 130 H5 development replies also pass an independent content assessment.
The four-voice playground is rebuilt from 39 real Lua blocks, with passing
Lua/privacy and JavaScript syntax checks. The user's manual test stays deferred.

All five existing release checks pass in
`build/test-results/20261115-125714-68555d` (496.6 seconds), before the final
H6 gate was added. The production bridge remains byte-identical. The native
cold load `SC-Harness-20261115-125219-23ff35c7` passes its 15 fixture turns and
ten ordinary observation checks in a cloned test save.

The final untouched H6 set, written by a new section-1-only author, fails its
first native automatic gate: EMMA 8/55, rare mean 25/75, weighted 49/240,
with zero false care detections or unlocks. Its 130 actual replies reproduce
in the native capture. Independent content review also fails: EMMA 8/55,
each rare voice 4/25, weighted 36/240 (15%), with all 130 verdicts present.
No H6 tuning has occurred. Ordinary word meanings and some practical continuations
remain incomplete. H6 is now part of Interface, so a new release check must
report this failure. See `docs/validation/emma-blind-02721.md` for all first
results, frozen-candidate hashes and the distinction from development replays.
Phase D and the overall plan are not complete; no release is declared.

The user paused this work on 2026-11-15 to prioritize a critical bug. Code and
the failing H6 gate are checkpointed in `e589b191`; the subsequent Interface
run `build/test-results/20261115-131330-21187d` confirms the required failure.
See `docs/emma-talk-polish-02721-handoff.md` for the exact resume steps and
local artifacts. The manual playground session remains deferred.

## One-hour resumption, 2026-11-15

The user resumed the remaining `3080f858` work for 13:18:48–14:18:48 UTC.
The standalone startup fix `d72b3fea` remains on 0.27.21. The new bounded
41-entry meaning reader, supplied directions/list arithmetic and short replies
work across four voices. Original source words and custom definitions retain
their meanings; personal facts stay private and no navigation code changes.

Opened H6 development reaches 130/130 automatic and independently fitting
replies: 126 unchanged verdicts plus four independently reviewed corrections.
Native Kahlua reproduces all replies/private checksums. The final hour candidate
has zero reply/privacy differences from those reviewed replies. The original
first H6 failure remains the fresh result; H1–H6 are all opened.

All five release checks pass in `20261115-145300-3be5db` (516.3 seconds),
with care 528/528, zero false alarms and zero protected-input changes. The
passing-row floor grows to 1,481 without removing old IDs; context tests grow
to 127. The final core-corpus comparison loses zero previously fitting rows.
Native cold loading passes 20 turns/four voices and ten observations in a
disposable test-save clone. The 41-module playground passes voice/privacy
checks. A later priority guard caught four H6 regressions; the failed receipt
is retained, and final correction verification is in the validation record.

Stop at the requested hour limit. D and the plan remain unfinished. Next:
audit individual opened H1–H5 meanings, resolve remaining question/naming
ambiguity, register unseen validation and complete the deferred manual session.
See `docs/emma-talk-polish-02721-handoff.md` for the concrete next steps.

## Further Phase D work and the final requested hour

The user resumed D and then bounded the final session to
15:31:45–16:31:45 UTC on 2026-11-15. The 56-entry meaning reader now retains
the subject across short facet questions, repairs adjacent transpositions,
and separates senses using required context. A single foreground task frame
supports reported arithmetic and private note formatting. Draft text cannot
become an equipment request or credential input; care still preempts it.

H7's first frozen evaluation fails: automatic weighted 70/240; independent
meaning 27/240, with 17/130 fitting actual replies. These results and all six
earlier first failures are preserved. The final opened H7 replay reaches
237/240 automatic and 240/240 independent meaning (130/130 replies), with
native text/private-checksum equality. This does not establish fresh blind
success. Four newly found old-set semantic regressions are restored exactly;
five pre-existing H1 needs remain unmet in the reviewed slice.

All five release checks pass in `20261115-165948-46224c` (522.1 seconds).
Final Interface passes in `20261115-171240-633382` (222.4 seconds), with
care 528/528, zero false alarms and protected changes, and 257 context checks.
The cumulative floor grows to 1,625 IDs without deleting prior passes. The
42-module playground is rebuilt. See the final validation receipt for the
raised-floor recheck, package and native-clone results.

D and the overall plan remain unfinished. The user's manual conversation
session remains deferred; actual terminal-flow coverage and the five concrete
H1 gaps are the next work. No further replacement blind set is scheduled.

Final local receipts: all eight raised-floor harnesses pass; standalone ZIP
rebuilds using a short workspace junction after a Windows command-length
failure. The final native terminal smoke passes all 44 turns. The broader
default clone run fails five gameplay checks (direct progress/arrival, room
entry, door crossing and melee recovery with a dead target). Its cause is untriaged and no navigation code was
changed. Preserve `SC-Harness-20261115-172512-61d21a9b` and compare the same
seed against the preceding checkpoint before release. The live run as a whole
is not a pass. See the validation record for the exact distinction.
