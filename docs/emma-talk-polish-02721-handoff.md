# Conversation work paused — 0.27.21

Paused by the user on 2026-11-15: a critical bug takes priority. Do not resume
dialogue implementation until the user resumes it. Phase D and the plan are
unfinished. The manual playground session is explicitly deferred.

## Workspace and checkpoint

- Repository: `C:\ZOMBOID\work\horde-safe-ground-02715`
- Branch: `living_fellows/0.27.21`
- Code/test checkpoint: `e589b191` — includes the failing final H6 gate.
- Plan: `C:\ZOMBOID\plan-emma-talk-polish.md`
- Progress: `docs/emma-talk-polish-progress.md`
- Full evaluation record: `docs/validation/emma-blind-02721.md`

A, E, F, G, H, B and C are checkpointed. D adds bounded shared public context
and answer planning for EMMA, SPIFFY, Ellis and Duty. It handles definitions
provided in a reply, choices, prerequisites, proposed uses, rehearsal, written
records and private conversational roles. Existing care and action handlers
retain their boundaries. No zombie navigation is changed. The user's current
save was not used by the native smoke checks.

## What passed, and what did not

All five existing release checks passed before the final H6 gate was added:
`build/test-results/20261115-125714-68555d`, 496.6 seconds. Scores were real
72/72, variants 275/288, predicted EMMA 188/188, persona 41/41, rephrase chains
7/7 and locks 74/74. The older corpus retains 5,217/5,417 fitting replies,
care 528/528, zero false alarms and zero protected-input changes. The prior
626 passing-row checkpoint remains intact. The bridge JAR is unchanged.

Opened H1–H5 pass their automatic gates. Independent review accepts all 130
H5 development replies, with two later changed replies accepted separately.
These are improvements on opened sets, not fresh blind success.

The final H6 set was written by a new agent who saw only section 1. Its 80
single-turn conversations produce 130 replies after every rare case is run
on all three voices. The first frozen candidate fails:

| Assessment | EMMA | SPIFFY | Ellis | Duty | Rare mean | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| Automatic | 8/55 | 8/25 | 8/25 | 9/25 | 25/75 | 49/240 |
| Independent meaning review | 8/55 | 4/25 | 4/25 | 4/25 | 12/75 | 36/240 |

There are zero false care detections or unlocks. Both assessments fail the
registered 80% gates. All 130 meaning verdicts are present and their input
hash matches the captured replies. No production changes or H6 tuning
followed the first evaluation. H6 is now wired into Interface; the follow-up
`build/test-results/20261115-131330-21187d` fails at that gate as intended.
This checkpoint is not release-ready.

## Resume after the critical bug

1. Review the critical-bug changes before touching dialogue code. Preserve the
   strict rule against issuing zombie paths, waypoints, flags or navigation
   states. Keep all changes to companion positioning on the LF side.
2. Read the H6 meaning verdicts and actual replies listed below. Group failures
   by missing meaning or routing behavior. The samples already inspected show
   ordinary terms such as advisory, offline, a lock combination and carried
   load remaining unexplained; repeating the previous sentence is not enough.
3. Improve ordinary word meaning, inflections and context-appropriate senses,
   plus useful practical continuations. Connect a short question to the actual
   public subject and the appropriate reference facet. Avoid another series
   of literal whole-sentence exceptions. Keep work bounded and retain source
   qualifications, uncertainty, privacy and the original checked commands.
4. Recheck the seven rephrase chains, public suites, all three rare voices,
   care/lookalikes and all prior passing IDs. Use meaning review as well as
   word contracts: H5 demonstrated that topical quotations can pass keywords
   while failing the user's question. Do not weaken needs to make a score pass.
5. Preserve every first-result failure. H1–H6 have now been opened; tuned
   replays must be labelled development results. Decide any further fresh
   validation only after the general defects are fixed, rather than repeatedly
   requesting new sets and treating opened-set success as generalization.
6. Run the final five-check release gate only after focused checks are useful.
   Raise cumulative passing-row floors only from a passing report. Rebuild the
   playground; its user session remains deferred until the user chooses it.

Focused native test command, from the repository in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '.\scripts\Test-EmmaTalkPolish.ps1' -Harness @('emma_context_harness','emma_talk_blind6_harness') -Baseline }"
```

`-Baseline` records failures and exits successfully; inspect the receipt's
individual results. Final release command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Project.ps1 -Release
```

## Retained local artifacts

These paths are relative to the repository and ignored by Git. Keep them for
reproduction; none contains actual user care. Private-flagged role replies
are synthetic audit fixtures and must stay out of public diagnostics.

- First H6 native result: `build/emma-talk-polish/harness-20261115-130602-4478d5/`
- H6 registration, all 349 source hashes: `build/emma-phase-d/h6-protocol.json`
- Exact first engine archive: `build/emma-phase-d/frozen-h6-payload.zip`
- First replies: `build/emma-phase-d/private-semantic-review/h6-frozen-first-replies.json`
- Native comparison: `build/emma-phase-d/private-semantic-review/h6-frozen-first-native-comparison.json`
- Independent verdicts: `build/emma-talk-polish/blind-h6/semantic-first-verdicts.json`
- H5 opened-set review: `build/emma-talk-polish/blind-h5/semantic-development-a.json`
- H5 two-reply delta: `build/emma-talk-polish/blind-h5/semantic-development-b-delta.json`
- Native cold load: `build/live-sandbox-runs/SC-Harness-20261115-125219-23ff35c7/`
- Playground: `C:\ZOMBOID\plan-emma-probe\web\emma-playground-0.27.21-phase-d.html`

The playground embeds 39 real Lua modules and passes four-voice, privacy and
JavaScript syntax checks. Browser visual testing was unavailable under the
earlier local-file policy block; no workaround was used. The native cold load
passes 15 terminal fixture turns and ten observation checks in a cloned test
save, not a rendered-terminal user flow. Native test-run directories contain
junctions: do not recursively delete them as ordinary disposable folders.
