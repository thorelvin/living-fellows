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
| A baseline: seven computer harnesses | Actual results against the production load order, before behavior changes | Recorded: 2 pass, 5 fail; repair/wiring pending |
| 3.1 real talk | All 71 visible turns, prior-reply context, generated variants and seven replay chains; care excluded; baseline committed before behavior | Pending |
| Predictions | 188 EMMA and 41 persona turns; persona reply-content scoring; per-row non-regression baseline | Pending |
| 3.14 locks | All lock kinds including Story, EMMA, Search, Rival and password locks; >=95%, exact-password/code safety, negative controls | Pending |
| 3.3 questions | One-turn expectations, help-me answers, person cancellation, expanded yes/no; unchanged care | Pending |
| 3.8-3.9 misses | Every miss offers useful choices; once-session menu; bounded context-aware suggestions and logging; negative controls | Pending |
| 3.12 persona quick fixes | Question/name guard, semantic repeat identity, all seven harnesses in Interface | Pending |
| Phase A verification | Improved baseline scores with no lost passing row, care 100%, Windows PowerShell 5.1 full gate, rebuilt playground | Pending |
| V7 baseline | Real Kahlua 60-day simulator, separate game/real clocks, metrics and sample-week transcript before new speech | Pending |
| V1 ledger | Flat facts and witnesses, observed event producers, 96 history/24 landmarks, small memory references, old-save and malformed-field restore | Pending |
| V3 scenes | 3-6 tagged beats, 2-3 speakers, personality/relation branches, one party scene, shared budget, immediate cancellation, two-clock scheduling | Pending |
| V5 relationships | Reason-matched arguments, bounded grudges, reconciliation, modest companion comfort | Pending |
| V4 aftermath | One deferred group reaction per death, close call, homecoming or fought-off alarm; affected speaker first | Pending |
| V2 recall | Evidence packets and named tokens, real places/relative dates, knowledge and told-by discipline, place/anniversary/similarity/Memory/camp triggers | Pending |
| V6 variety | Persisted bounded hashes/counts, least-heard selection, half-pool/up-to-eight window, age/tier layers, additional background stories | Pending |
| Voice content | Approximately 700-800 new lines plus clean twins; scene/recall/aftermath/argument depth and immersion lint | Pending |
| Voice gates | 12.5%-33.3% specific recall, zero false claims, >=3-day no-repeat for pools >=8, scene shape/cadence, aftermath coverage, grief windows, bounded work/save | Pending |
| H | Cloned-camp live check, readable transcript, tuning | Pending |
| 3.2 hooks | Declared/derived hooks for all EMMA/persona reply pools, facet and pronoun resolution, salient-term lint with negative control | Pending |
| 3.6-3.7 world and roles | Lore facets, checked place facts, non-roster why/how, session-only role memory, practical conditions, persona roles | Pending |
| 3.11 weather | Condition/season-tagged quips, truthful selection and filter-removal negative control | Pending |
| 3.4-3.5 topics | Once-built bounded noun/synonym index and six facets; complete requested survival coverage; verified Build 42.22 source comments | Pending |
| 3.10/3.13 | Guide/fact repetition handling, requested new situations, companion identity, contextual counts, real-life kindness, no private persistence | Pending |
| D | Independent sealed holdout >=80%, real-talk >=90%/wrong <=3%, predictions >=85%, persona >=95%, all chains converge by second turn, care 100% and no existing-corpus regression | Pending |
| Playground | Real modules rebuilt after every phase, all four persona choices, browser verification and user session | Pending |

Independent blind set H is being authored from section 1 only in
`build/emma-talk-polish/blind-h`. Its content must stay unopened until Phase D.

## Baseline checkpoint (before production changes)

Starting commit `84123716`; actual game Kahlua VM, full production terminal load
order. The original public export and the prior session's public-only transcript
contain **72** turns (36 + 2 + 34), rather than the plan's stated 71. Every
recovered public turn is retained. Care and private note entries were excluded
before fixture extraction; a private preceding reply is never copied.

| Set | Correct / total |
|---|---|
| Real turns, reply contracts | 45 / 72 |
| Generated public variants | 170 / 288 |
| EMMA predictions | 74 / 188 |
| Persona predictions, content contracts | 18 / 41 |
| Rephrase chains converging by turn two | 5 / 7 |
| Expanded lock predictions | 23 / 74 |

The plan's older percentages used different scoring and a different release;
they are not substituted for this observed baseline. Frozen passing row IDs in
`tests/fixtures/emma-talk-polish/baseline.json` prohibit row-level regressions.
The new corpus runs in Interface before any production changes land.

Seven-harness run: system and lore pass. Terminal, knowledge and conversation
expect some older routes (help versus help_me, reference versus survival guide,
and overlapping farming guides); grid expects a controller response where the
production parser chooses its shutoff reference; persona expects Ellis to
reflect a line now handled by care. These failures were preserved in
`build/emma-talk-polish/harness-20261115-010430-30bd65` before repairs.

The sealed independent H set has 145 turns in 60 conversations. SHA256:
`6a902430b8406e08a536f587ac09b1b12871c76fd269ea55b0cb18511f5ae3a9`.
