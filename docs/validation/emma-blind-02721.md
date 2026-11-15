# Conversation validation, 0.27.21

H1 was independently authored from section 1 of the user's plan, before B/C
implementation. Its exact 145-turn file is retained as
`tests/fixtures/emma-talk-polish/blind-h.json`, SHA-256
`6a902430b8406e08a536f587ac09b1b12871c76fd269ea55b0cb18511f5ae3a9`.
It has 99 EMMA turns and 46 generic rare-computer turns. Every rare case runs
separately on SPIFFY, Ellis and Duty. Its contribution to the original-row
score is the mean of those three outcomes, never the best result. The weighted
denominator is therefore 435: three times 99, plus 138 rare executions.

The mapping and 80% gates for the weighted total, EMMA and the rare mean were
recorded before opening H1. First scaffolding replay
`harness-20261115-081912-b6d0e1` was invalid as an evaluation: it ignored the
author's descriptive setup and supplied the public camp's live clock,
residents and sensors to scenarios explicitly lacking them. It scored 57/435.
The corrected replay uses only supplied observations, makes the provided
descriptive context available as public context, and binds H1's two explicit
record fixtures. It never seeds a correct-answer handler or an action ticket.

The first correctly bound, untuned replay of C (`435d6e5b`) is
`harness-20261115-082458-10ac4c`: EMMA 26/99, rare 8/138, weighted 86/435
(19.8%), with zero ordinary care detections and zero false unlocks. That result
failed the blind gate. H1 became a development regression set. The later
426/435 (97.9%) replay in `harness-20261115-090549-bc0236` is tuning evidence,
not a fresh blind score.

The resulting shared reader stores one bounded public context and preserves
its subject across fragments, corrections and pending conversational answers.
It does not scan the map, operate equipment, grant access or save personal
conversation. Existing references, named patients, checked requests and
complete new questions retain their established paths. Private names and
health replies are excluded from public hooks. An ordinary warm follow-up
without a safety check is distinguished from an actual care detection; care
classification and response text are unchanged.

The three rare computers retain their rules and voices. Their own-word hooks
cover Kyle, the Smile Score, Ellis's appointment and doctor disclaimer, Marla,
Cole, coffee and Sector Nine. A claim of office is still not a credential.
Listing drawer contents cannot release the drawer. Recorded Duty status no
longer implies a current exterior observation. An accepted tone offer reaches
the existing local UI sound adapter; the playground uses a short local tone.

## Physical reference sources

Exact game instructions still use the 27-topic reference and its installed
42.22.2 source receipt. Broad in-world physical guidance is also checked against
primary sources: direct pressure and circulation checks against the
[Red Cross bleeding guidance](https://www.redcross.org/take-a-class/resources/learn-first-aid/bleeding-life-threatening-external),
rest and fluids against [NHS fever guidance](https://www.nhs.uk/symptoms/fever-in-adults/),
suspect cans against [USDA food-safety guidance](https://ask.fsis.usda.gov/article/Is-food-in-damaged-cans-dangerous),
and enclosed-generator hazards against [CPSC guidance](https://www.cpsc.gov/Safety-Education/Safety-Guides/Carbon-Monoxide-Home/Generators-and-Engine-Driven-Tools).
These checks do not claim that circulation, can bulging or other physical
details add new game mechanics. No third-party source text or game files are
redistributed.

## Fresh H2 round

Because H1 was opened for tuning, the same independent author prepared a
second sealed round without seeing code, scores, other corpora or other plan
sections. H2 has 80 new turns in 32 conversations: 55 EMMA and 25 generic rare.
All scenario facts are explicit in the preceding public reply; there is no
hidden prose setup. Its sealed SHA-256 is
`0c44a5b703cf2cef5ed4396809bdaa3df7e5e1bf508a325ba4547b828719881a`.
The same all-three-voices mapping and content/safety gates apply. The first
frozen-candidate result was recorded before inspection or tuning:
`harness-20261115-094752-e7f481`: EMMA 7/55, SPIFFY 2/25, Ellis 1/25,
Duty 3/25, rare mean 6/75, weighted 27/240 (11.25%). There were zero ordinary
care detections and zero false unlocks. The production manifest was verified
unchanged across this first evaluation. H2 failed and is now a development
regression set; replay improvements cannot be reported as fresh blind success.

The failure exposed the difference between a fixed topic dictionary and a
reader for the actual preceding public text. The shared reader now indexes
bounded content words, ordinary inflections and a small set of word relations.
It selects source sentences with neighbouring qualifications, carries that
source across excerpt answers, and explicitly retains unknown information.
It can explain an unfamiliar word defined only in the preceding reply. Existing
practical facet answers and warnings retain priority. New complete subjects,
checked actions, named patients, idle expiry and private replies keep their
boundaries. No passage is read from private notes or saved to the world.

The first native-Kahlua development replay with this reader is
`harness-20261115-100222-234ac8`: H1 398/435 (91.5%); H2 207/240 (86.25%),
including EMMA 47/55 and all three rare voices 22/25. Both have zero ordinary
care detections and false unlocks. These are opened-set regression results.
The public suites passed in that replay; a separate context control caught
the fuel-warning priority defect, which was corrected before release checks.

## Fresh H3 round

The independent author next returned 80 new turns (55 EMMA, 25 generic rare)
in 30 conversations, using section 1 and its own earlier authoring context.
SHA-256: `3372559cdc9ccec5f2b11dfcc458264f66e4e567742477fc3c5dc0249cb26d0a`.
Its first frozen native-Kahlua run, before human inspection, is
`harness-20261115-103049-971113`: EMMA 26/55, SPIFFY 5/25, Ellis 6/25,
Duty 9/25; rare mean 20/75, weighted 98/240 (40.83%). No ordinary care
detections or false unlocks occurred. The production manifest remained
unchanged. This also failed. H3 is retained as a development regression set;
none of the three first-run failures is replaced by a post-tuning score.

The subsequent shared reader separates handler-owned facts and procedures from
unclassified public passages. Existing readers get first use of their own
metadata; a passage fallback cannot replace a live clock, a story answer or
an access procedure. Ordinary definitions and short corrections can retain
their source without treating a mentioned noun as a new unrelated topic.
Excerpt repeats have a bounded query hash, and an unresolved rephrase does
not immediately erase the preceding public source. No raw user input is
stored in that hash state.

Machine nicknames, imagined appearance, conversational corrections and offered
roles now have explicit short continuations. Nicknames do not rename the
operator or programme. Personal descriptions and role replies stay private.
New ordinary reference entries cover fastening, tool fit and the meaning of
sound; they do not add recipes or world operations.

## Fresh H4 round

H4's first frozen result is also retained, before inspection:
`harness-20261115-110513-c9887b`: EMMA 41/55, SPIFFY 17/25, Ellis 18/25,
Duty 17/25; rare mean 52/75, weighted 175/240 (72.92%). It had no ordinary
care detections or false unlocks and an unchanged production manifest. Its
80-turn file has SHA-256
`420e11eb6f070126af5c88e34f68ce080ab9169df5e4a149a1d78fb2c1f62db4`.
It failed and became a development set. The author was asked to sample section
1 naturally, allowing topics to recur rather than requiring novel vocabulary;
it received no implementation or score feedback.

These misses exposed two shared-core issues. Offered practical choices now
retain the selected topic and facet across clarification. Persona spelling
correction remains local to their own rules: the shared reader sees the actual
typed words, so an unfamiliar `stove` cannot become `store` before reference
resolution. Conversational call signs are bounded, private session identifiers,
with no radio transmission or access effect. A request for formal wording
produces a text example, not a dispatched order.

## Frozen H5 and independent content review

H5 has 80 turns in 30 conversations (55 EMMA and 25 generic rare), SHA-256
`dffbdfc3afa31837279a701887ec6e06c51b78059a40fb60e83787267cbd5732`.
Its first native-Kahlua automated result is
`harness-20261115-112956-819e5f`: EMMA 44/55, SPIFFY 16/25, Ellis 17/25,
Duty 16/25; rare mean 49/75, weighted 181/240 (75.42%). No ordinary care
detections or false unlocks occurred. The production manifest remained
unchanged. This automated result failed and remains recorded.

Before any H5 inspection or tuning, the independent author was asked to
evaluate every actual reply by meaning against the already written needs,
context and forbidden claims. It receives neither implementation nor automated
labels or scores. Both apparent successes and misses are reviewed, rather than
only requesting leniency for failed word checks. A source quotation must
actually answer the need or provide a useful specific clarification. This
separate review failed: EMMA 27/55 and each rare voice 15/25, giving 72/130
useful replies and a weighted 126/240 (52.5%). It does not overwrite the
automated result. The difference exposed a limitation in the word contracts:
repeating a relevant paragraph could satisfy them without answering the turn.

The review transcript is another native replay of the frozen first candidate.
All 130 per-turn automated outcomes reproduce exactly, and all 348 production
file hashes are unchanged. No reply required privacy redaction in H5. The
corpus and first-candidate archive remain untouched. The full independent
verdict file is retained under `build/emma-talk-polish/blind-h5/`.

The subsequent answer planner applies supplied public facts to the question:
definitions, conditional proposals, selected alternatives, ordered steps,
explicit prohibitions, practical checks and the limits of unverified facts.
It distinguishes rehearsal and written records from physical work. Public
example facts can support a private conversational role without granting
credentials. It has no actor, provider, persistence or action-dispatch calls.
This is development on opened H1–H5. Independent content review of its 130
actual development replies accepts all 130 against the prewritten needs; a
later definition refinement changes two replies and both are accepted in a
separate delta review. Public text reproduces byte for byte in native Kahlua;
the nine synthetic private role replies have matching normalized checksums.
These are opened-set improvements, rather than fresh blind evidence.

## Fresh H6 result: release gate remains failed

A new independent author saw only section 1, with no implementation, prior
corpora, scores or feedback. H6 has 80 conversations and 80 turns: 55 EMMA and
25 generic rare, expanded to 130 actual replies. Each conversation has one
literal previous reply and one new input. It tests short-turn meaning rather
than multi-turn continuity; the seven chains and H1–H5 retain that coverage.
Its exact file is `tests/fixtures/emma-talk-polish/blind-h6.json`, SHA-256
`eaa0a658546fc693daec2e823b8b411750290a80fa9052df7166e195052952fc`.

All 349 production Lua/JAR files were frozen and archived before the set was
compiled or inspected. The registered gates require at least 80% for EMMA,
the three-voice rare mean and the weighted total in both automatic and
independent semantic assessment, with zero false care detections or unlocks.
The engine manifest digest is
`f2e0e62167b5e07fad0e36b1b37ca277d0d441357b87ad103b478645391026ec`
(SHA-256 of the compact, sorted JSON path-to-file-digest mapping).

The first native replay, `harness-20261115-130602-4478d5`, failed: EMMA 8/55,
SPIFFY 8/25, Ellis 8/25, Duty 9/25; rare mean 25/75 and weighted 49/240
(20.42%). There are no ordinary care detections or false unlocks. A second
native replay captures all 130 actual replies, reproduces all first outcomes,
and matches the internal review transcript, including the one synthetic
private role reply's normalized checksum. The production manifest is unchanged.
The independent content verdict also fails: EMMA 8/55 and each rare voice
4/25; rare mean 12/75, weighted 36/240 (15%), and 20/130 useful actual replies.
All 130 verdict IDs are present, with no duplicates, and the review's input
hash matches the captured transcript. Root inspected sample needs after the
automatic result was recorded while that review was running; no tuning
followed the inspection. The frozen candidate remains the review subject.

The sampled failures include ordinary meanings absent from the last reply:
advisory, offline and a lock combination. Relevant repetition often fails to
explain them, and some practical follow-ups still need a useful next step.
H6 is wired into Interface so this required failure cannot disappear behind a
passing release summary. The earlier five-check pass below predates this gate.
No release readiness or fresh blind success is claimed.

## Release-check checkpoint

All five existing Windows PowerShell 5.1 checks passed in
`build/test-results/20261115-125714-68555d` (496.6 seconds, 23 direct JVMs),
including opened H1–H5 and the added procedure, negated-date, question-marker
and literal-exit controls. This run precedes H6's first evaluation and wiring.
The new required blind gate fails as recorded above; phase D is unfinished.
The follow-up Interface run, `build/test-results/20261115-131330-21187d`,
fails at H6 as intended (128.0 seconds). No production changes followed the
frozen candidate. Work is paused at the user's request for a critical bug.
The final four-voice playground embeds 39 real Lua blocks and passes its Lua,
privacy and JavaScript syntax checks. The user's manual session is deferred.

## Native module check

The first D cold-load clone (`SC-Harness-20261115-102057-d22b14d6`) exposed a
new public passage inheriting the preceding guide's target. Its ordinary
ten observation checks passed, but its terminal smoke failed; it is not a
passing terminal receipt. After correcting ownership, the next clone
`SC-Harness-20261115-104809-b3e7bff8` passed the terminal smoke: 27 topics,
637 index entries and eight public fixture turns across all four voices.
Its ten ordinary observation checks also passed. Later persona-priority and
example-request refinements are covered by the Kahlua release gate. This
native smoke proves cold loading and pure dialogue, not a rendered terminal.
The helper is test-only; neither clone changes the user's current save or
installed game. No companion or zombie navigation is issued by the helper.

The later clone `SC-Harness-20261115-112524-50504550` passes the expanded
15-turn smoke, including offered map/water topics and the original word
`stove` on every rare voice. All ten observation checks pass. The following
call-sign clearing refinement is covered by the context and release harnesses.

## Opened H6 development during the requested hour

The user resumed `3080f858` for 13:18:48–14:18:48 UTC on 2026-11-15.
The 0.27.21 startup hotfix `d72b3fea` is retained. All first-result artifacts
above remain immutable; the historical pause statements describe that time.

The candidate adds a bounded 41-entry ordinary-meaning table and pure reader,
practical facets, supplied spatial/list relations and reported conversation
facts. It preserves original source words before typo correction and supplied
definitions before ordinary senses. Personal counts/location remain private;
public list arithmetic is explicitly reported rather than live inventory.
No providers, persistence, actor actions or navigation are added by the reader.
Primary sources checked for canned-food and charcoal advice:
[USDA](https://ask.fsis.usda.gov/article/How-long-can-you-keep-canned-goods),
[CPSC](https://www.cpsc.gov/Safety-Education/Safety-Education-Centers/Carbon-Monoxide-Information-Center/Charcoal).
These do not claim exact Build 42 recipes.

Hour-A independent review accepts 126/130 actual replies. Its four failures
are task confusion between lighting and torch repair, plus the three rare
voices failing to explain a switch. Those four corrected hour-B replies are
independently accepted in a separate delta. The other 126 texts/privacy flags
are unchanged. Combined verdict: EMMA 55/55, each rare voice 25/25,
weighted 240/240. These are opened development scores, not fresh blind success.

Artifacts: `build/emma-talk-polish/blind-h6/semantic-hour-a.json`,
`semantic-hour-b-delta.json`, `semantic-hour-b-combined.json`; actual replies
under `build/emma-phase-d/private-semantic-review/`. The hour-B candidate
manifest digest is `ecd7d6c653d68fd00a83016394a23c943fb44250a43960d1f5349d72a91363a4`.
All 130 replies match native Kahlua, using exact public text and normalized
private checksums. The final hour capture has zero text/privacy differences
from hour B; its review input SHA-256 is
`24c8fdda123fbac905aba6805eaf6c6998d72dc741c0995d2270c07b57353e70`.
Only synthetic fixtures are used. Private-flagged bodies remain internal.

All five release checks pass in `build/test-results/20261115-145300-3be5db`
(516.3 seconds, 23 direct JVMs). Public scores: real 72/72, variants 275/288,
EMMA predictions 188/188, personas 41/41, chains 7/7, locks 74/74. Core remains
5,217/5,417 fitting, care 528/528, false care alarms zero, protected changes
zero. The final core comparison has zero losses against phase C. The floor
now retains 1,481 passing IDs, including all prior 626; context has 127 checks.

A later priority guard initially regressed four H6 rows; Interface receipt
`20261115-151011-8a87d9` correctly fails the retained-ID floor. Corrections
distinguish exact term definitions, containment questions and missing facets.
Final Interface receipt `20261115-151347-c96cf5` passes in 218.9 seconds
(two direct JVMs), including the raised 1,481-ID floor and all opened H1–H6
automatic gates. This targeted run follows the final priority corrections;
the five-check release receipt above precedes them. No Java or non-dialogue
runtime source changed between the two receipts.

Native clone `SC-Harness-20261115-150334-eff5f74a` passes its explicit
`LF_EMMA_REFERENCE_NATIVE` smoke (20 turns, four voices, 27 topics,
637 index entries, 41 meanings), plus ten observation checks. It uses a
disposable test-seed clone, not the user's save. The last priority guards are
verified separately by Interface; this is not rendered-terminal coverage.
The rebuilt playground embeds 41 real Lua modules and passes four-voice and
privacy checks. Manual user testing remains deferred. D and the overall plan
remain unfinished; see the handoff for unresolved ambiguity and validation work.

## Phase D resumption after e699c83a

The user resumed Phase D after the one-hour checkpoint. Comparing all 757
opened H1–H5 replies against the earlier pre-hour engine found six changed
replies and one lost automatic pass: the candle follow-up selected battery
lighting instead of the later candle precaution. Independent review accepted
five of those six meanings, failing the candle reply and flagging an estimate
answer that drifted from food planning to travel.

The cause of the candle loss was general: the public passage stores up to
900 characters, but `Brain.tokens` silently applied the 160-character query
limit when readers examined that passage. Public readers now request the
bounded 900-character limit; ordinary query tokenization remains 160.
Supplied definitions later in a passage also retain their contextual sense.
Nickname declarations are anchored so a why-question or negation cannot
become a declaration. Context checks grow from 127 to 157, with actual-reply
negative controls for the lost precaution and unchanged query/source bounds.

All five release checks pass in `20261115-152959-bbeba1` (522.7 seconds,
23 JVMs). Scores are real 72/72, variants 276/288, predicted 188/188,
personas 41/41, chains 7/7, locks 74/74. Core remains 5,217/5,417 fitting,
care 528/528, zero false alarms and zero protected changes. The raised floor
retains 1,495 passing IDs and all prior 1,481. The core comparison loses zero
previously fitting rows.

The correction changes 16 opened replies: independent review accepts 12 and
rejects four, with no new semantic regressions or lost useful qualifications.
The failures already existed before the correction: H2R04-3 on each rare
voice does not accept the carry-less plan; H4E02-3 does not address the window
question. Three fitting split-load answers remain weak because total weight
is implicit. These findings are retained rather than hidden by automatic
passes. H1/H3/H6 replies and privacy flags are byte-identical; H6 retains its
130 independent judgments. H5's three changed replies all fit.

Internal review receipts: `build/emma-talk-polish/opened-resumed-semantic-delta.json`
and `opened-resumed-b-semantic-delta.json`; actual synthetic input/output
comparisons remain under `build/emma-phase-d/private-semantic-review/`.

### H7 registration, before authoring and evaluation

One new independent author receives only section 1 and neutral schema/count
instructions, in a fresh agent with no inherited conversation. The candidate
was frozen before the author began: 351 Lua/JAR files, manifest digest
`5d82f6f76ee53e506e368d6aef915ceb23d97752675578386f98729dadcc86c2`.
The immutable protocol/archive are under `build/emma-talk-polish/blind-h7/`.
The source is `section-1-only.md`, SHA-256
`7c1bef2ae3d2940dc781b59a4cf8b8feefb2eaf6ebe6ce45e700737e836f5bd6`.

Design: 32 sequential conversations, 80 turns (22 EMMA conversations/55 turns,
ten rare conversations/25 turns). Rare cases run on every rare voice. Gates
remain 80% for EMMA, rare mean and weighted total, in both automatic and
independent meaning assessment, with zero ordinary false-care detections or
unlocks. No implementation is changed during the first evaluation. H1–H6
remain opened sets, and this new result cannot erase their earlier failures.
The author receives no implementation, dialogue outcomes or prior corpora;
a status-only message says that the candidate's ordinary release checks pass.

## H7 first result and opened development

The sealed 32-conversation/80-turn H7 file has SHA-256
`c84bce5ea8621d658bf37da8955800a86160711c82edee950d943dd16c10d1c5`.
It produces 130 actual replies across the four voices. First native receipt:
`harness-20261115-154745-5f9a0a`. Automatic scores are EMMA 16/55,
SPIFFY 7/25, Ellis 7/25, Duty 8/25; rare 22/75, weighted 70/240.
Independent content review accepts EMMA 5/55 and each rare voice 4/25:
rare 12/75, weighted 27/240, 17/130 fitting replies. Both registered gates
fail. False care detections and unlocks are zero. All 130 verdict IDs and
their input hash are verified, and actual replies reproduce in native Kahlua.
The engine manifest is unchanged before and after this first evaluation.

The original binding also exposed two test artifacts: a supplied previous
reply left the visit at turn zero, and a fresh unspecified operator was named
"Test". The test now counts the preceding turn and uses a generic operator.
A separate replay after the turn-binding correction still fails. The original
receipts remain untouched; binding corrections do not turn them into passes.

Development adds ordinary meaning facets and one bounded foreground task
frame. It supports reported quantities, subtraction, constraints on a draft,
source explanations, roleplay tasks and fiction continuity. It never saves
drafts, scans inventory, consumes supplies or operates actors. Another item
cannot inherit the active item's count. Private draft text is handled before
clause splitting and credential/command readers, with care and clause-level
distress retaining priority. All new care controls are synthetic and their
bodies are excluded from diagnostic output. The note helper preserves the
supplied words when formatting lines; it does not claim general summarization.

General physical reference was checked against
[USDA date-label guidance](https://ask.fsis.usda.gov/article/Is-the-dating-of-shelf-stable-foods-required-by-federal-law),
[Utah Emergency Management on insulation](https://dem.utah.gov/shelter-clothing-and-fire/),
[USGS on capillarity](https://www.usgs.gov/water-science-school/science/capillary-action-and-water),
and [RHS on bean supports](https://www.rhs.org.uk/vegetables/beans-for-drying/grow-your-own).
The USGS passage was available in the search extract; direct opening required
JavaScript. These support general explanations, not new Build 42 mechanics or
exact recipes. The existing 27-topic installed-game source verification is
unchanged.

Independent development-C review accepts 128/130, rejecting two door replies.
A changed-reply audit of older sets finds four new semantic regressions despite
passing keywords: bread in a cold-meal example becomes staling, and a silent
radio's power question becomes reception troubleshooting. Required context
restores those four texts/privacy flags byte for byte; a separate content
review accepts all four restorations. Five earlier H1 needs remain unmet
(H007-2; H045-1 on all rare voices; H045-2 on Ellis). They are not claimed fixed.

An initial ten-reply delta review exposed automatic-result fields; its report
records that limitation. A separate reviewer then receives a clean transcript
without automatic fields. That review flags overstatements and a missing
status answer. After wording corrections, all ten final clean replies fit.
The other 120 texts/privacy flags are byte-identical to the independently
reviewed development-C replies. The verified combined final verdict is
EMMA 55/55 and each rare voice 25/25, weighted 240/240, raw 130/130.
Artifacts: `build/emma-talk-polish/blind-h7/semantic-first-verdicts.json`,
`semantic-development-c.json`, `semantic-final-b-clean-delta.json`,
`semantic-final-c-clean-delta.json`, and `semantic-final-c-combined.json`.
The final actual-reply transcript hash is
`f484ee830c30180cf0bbe09d9c62d13fe9cce609151976911701efa9f85958f4`.

Final native automatic score remains EMMA 54/55, rare 75/75, weighted
237/240, with zero false care or unlocks. All 130 final replies match native
Kahlua: exact public text and normalized checksums for 16 private replies.
The one keyword miss remains a miss; neither its needs nor its contract is
weakened. H7 is required by Interface. All seven sets are now opened, and the
improvement is development evidence rather than fresh blind success.

All five release checks pass in `20261115-165948-46224c` (522.1 seconds,
23 JVMs). After final wording changes, Interface passes in
`20261115-171240-633382` (222.4 seconds, two JVMs). Scores: real 72/72,
variants 276/288, predictions 188/188, personas 41/41, chains 7/7, locks 74/74.
Core remains 5,217/5,417 fitting, care 528/528, false alarms zero and protected
changes zero. Context checks grow to 257. The floor retains 1,625 IDs,
including every earlier 1,495. The new module and table remain bounded;
the source JAR is unchanged and no navigation source is modified.

Final source manifest: 352 Lua/JAR files, digest
`8cd024534a6a0958e2392c6de504c2234dd778d6100bc4f18e4a58055af5b6e5`.
The rebuilt playground embeds 42 real Lua modules; the manual session stays
deferred. The user requires a stop/report after the final hour ending
16:31:45 UTC. D is not declared complete or released.

### Final local verification receipts

The raised 1,625-ID floor passes all eight native public/blind harnesses in
`build/emma-talk-polish/harness-20261115-171927-41fc8d` (`Baseline=false`).
The final four-voice playground API also passes private draft entry, requested
line count, command-like prose and cancellation. Inline JavaScript syntax
passes. The cold payload's 352 production Lua/JAR files match the source bytes.

Direct standalone packaging initially hits the Windows process command-length
limit when the Lua compiler receives all long absolute filenames. Rebuilding
with the verified short junction `C:\ZOMBOID\d21` to this checkout succeeds.
The final standalone ZIP SHA-256 is
`b75a59e98578b011569f7f99fcb71a4d37a009bab8811ca0c04bc84f58baa76f`.
The compilation passes 351 Lua files in normal/debug modes. This is a local
package, not publication. The short junction is retained for this build path;
the underlying long-argument compiler limitation remains a tooling follow-up.

Native clone `SC-Harness-20261115-172512-61d21a9b` passes the explicit terminal
smoke: 44 turns (32 public, 12 private), four voices, 27 topics, 637 reference
entries and 56 meanings. The invocation used the broader default live harness,
rather than observation-only mode. That broader run FAILS five gameplay
checks: native direct-path progress/arrival, room-entry sweep, door-crossing
round trip, and melee recovery (delay about 11 seconds; target was dead).
It must not be represented as a passing overall native run.
The event log is retained under its cache's
`Lua/SurvivorCompanionHarness/events.log`. These are companion movement/combat
checks; this dialogue change does not modify navigation code. Their cause is
not established. A same-seed comparison with the prior checkpoint is needed
before attributing them to a regression or to dynamic test blockers.

The source is a disposable kitchen test seed, not the user's current save.
The terminal helper itself performs pure conversation; the broader harness
does spawn/move test companions and run other gameplay checks in the clone.
No installed game or source save is modified. Retain the failed receipt and
triage it before a release; do not change zombie navigation as a recovery.
