# EMMA chat fixes, 0.27.22

Release validation commit: `fbb26fee` on `living_fellows/0.27.22`.
Runtime code commit: `3a342689`; `fbb26fee` only updates the legacy singular-wording assertion.
Worktree: `C:/ZOMBOID/work/r2722`. Base: `61981815`.
User handoff: `C:/ZOMBOID/codex-handoff-0.27.22-emma-chat-fixes.md`.

All ten handoff fixes are implemented. The earlier practical rest/visitor repairs
and parked-car routing fix are carried forward. The separate 0.27.21 native live
fixture change is excluded; that file is byte-for-byte unchanged from this worktree's
base. No zombie navigation behavior is changed.

## Behavior and native negative controls

The wired `emma_talk_chat_harness` has 80 focused cases. The tests include all four
voices, the actual opinions/new-question chain, source expiry, offered choices,
related and unrelated follow-ups, joke/data/care priority, whole guide labels,
duplicate compound parts, and singular/plural hurt headings.

| Fix | Behavior | Current Kahlua exit | Original module reverted |
| --- | --- | --- | --- |
| F1 | Old excerpts expire, require a real continuation, and yield to new questions; no consecutive excerpt repeat | 0 | 1 |
| F2 | Opinions and salient extra-pool terms have substantive answers; a whole prior reply is not an explanation | 0 | 1 |
| F3 | Offered choices live for two turns and accept labels, ordinals and bounded typos; misses create no quote hooks | 0 | 1 |
| F4 | Length-based spelling limits, question-word stop list, standing defaults, no uncollected fragment suggestions | 0 | 1 |
| F5 | Personal future phrases reach `me_die`; bare future questions give observed camp advice; foraging verb typo reaches basics | 0 | 1 |
| F6 | Every merged identity variant names EMMA; name explanations do too | 0 | 1 |
| F7 | Clear new questions leave the follow-up subject; boiling stays with water | 0 | 1 |
| F8 | Short knock names beat storage/person lookups; care and commands keep priority; storage context is cleared | 0 | 1 |
| F9 | Complete guide labels resolve before compound splitting; duplicate and bare prior-topic parts are removed | 0 | 1 |
| F10 | One hurt person needs attention; two people need attention | 0 | 1 |

Reproduce with `scripts/Test-EmmaChatReverts.ps1`. It reads the original pre-fix
modules from Git into isolated build snapshots, keeps the current tests, runs care
first, and checks process exits. It does not change the working tree or game install.
A compile error or unrelated failure does not count: the reverted run must reach its
own public-chat assertion. Positive plural, care and boundary controls can remain
passing when an old implementation is restored; the changed behavior must fail.

Final paired proofs at code commit `3a342689`: **all ten current exits 0 and all ten reverted exits 1**,
`build/emma-talk-polish/reverts-20261115-210855/summary.json`.
The earlier development proof is retained in `reverts-20261115-200654/summary.json`.
The added actual-chain tests for F1 were also proved with current exit 0/reverted
exit 1 in `reverts-20261115-201025`. F1 reverts the context admission, expiry and
repeat guard together while retaining the read-only `strongIntent` helper needed
by F7. F7 was re-proved after its equipment-pronoun boundary repair in
`reverts-20261115-202413` (current 0, reverted 1). The table does not count
unrelated compile failures as negative evidence.

The prior hook fixture expected a generic Paperclip quote. F3 explicitly retires
that behavior, so its oracle now requires unsupported hooks to fall through and a
supported opinions hook to give a real definition. Removing its resolver still
fails the positive control. All original conversation floors and IDs are retained.
The broad suite initially exposed old glitch and spelling cases that had depended
on generic quotes; they now get actual maker, memory-fault and gas-station answers.
The personal-future pool's old promise about surviving today was also removed.

## Validation

- Final focused care/chat/context: strict exit 0,
  `build/emma-talk-polish/harness-20261115-210644-89a873`.
  Chat **80/80**, context **286 checks**. The standalone context command also loads
  its required fixture now; its earlier isolated invocation omitted that fixture.
- Synthetic care checks: **575/575**, **88 negative controls**, zero false care,
  private response priority on all four voices. Care implementation/data and
  `SCTerminalPersona.lua` are unchanged from `61981815`. No private input or reply
  bodies are emitted in the diagnostic receipts.
- Public conversation suite: strict exit 0,
  `build/emma-talk-polish/harness-20261115-200519-32bace`.
  **86/86** original real turns, **328/344** variants, **188/188** predicted,
  **41/41** persona and **7/7** convergence chains. Zero confidently wrong original
  real turns; four variant answers fail the content oracle. All protected passing
  IDs and cumulative floors remain checked.
- The supplied 14-message session is a **strict** real-talk fixture. It forces the
  identity variant containing "opinions are developing" through the real handler;
  every original row must fit and consecutive full replies must differ.
- Normal/debug Kahlua compilation passes after extracting foreground routing and
  resident-name collection from the parser. The first release attempt detected the
  game's 200-entry debug-local metadata limit; normal-mode conversation tests alone
  would not have caught it.
- The first full release gate passed Build/Lifecycle/Behaviour/Cargo and
  exposed an older equipment-pronoun boundary regression in Interface. After a
  generator question, a short attribute/quantity fragment must clarify the current
  equipment rather than revive an older person/item. That boundary is repaired;
  the targeted native UI group passes **3,911** conversation checks plus its existing
  access/lock/body/calendar checks (`build/ui-chat-probe/result.log`).
- Existing source-based follow-ups also needed substantive explanations once whole
  quotations stopped counting as answers. The public answer planner now explains
  supplied relationships and their limits, while specific symptom/container contexts
  precede general advice and guide labels. Persona hooks yield to those specific
  answers. An owned recent meaning can continue from the freshly stated fact without
  refreshing the original quotation. All seven opened suites preserve their protected
  rows in both the diagnostic replay and the native Kahlua release gate, with zero
  false care or unlocks.
- **Final release gate: PASS**, process exit 0, all **five checks** on `fbb26fee`:
  Build, Lifecycle, Behaviour, Cargo and Interface. **548.8 seconds**,
  **23 direct JVM starts**, no live game launched.
  Receipt: `build/test-results/20261115-211649-003fe5/summary.json`.
  Installer boundary/rollback/reinstall checks: **18/18**.
- Final native Interface includes **5,417** canonical rows (**5,220** fitting,
  **98** confidently wrong, **528/528** care, zero false alarms, zero changed
  protected rows), all three care holdouts, all seven opened dialogue suites,
  the strict public session, original terminal APIs, persona and radio checks.
- The old base terminal test still required the incorrect singular phrase
  "1 of your people need attention." Its assertion now requires "needs attention";
  all seven standalone legacy terminal/persona harnesses pass in
  `build/emma-talk-polish/harness-20261115-211659-0f43e2`. The n=2 control still
  requires the plural form. No baseline IDs or floors were weakened.

These are opened regression sets and current-input reproductions. They are not
fresh blind evidence or a claim that arbitrary dialogue is solved.

## Local playground and replay

Built from the 42 real Lua blocks with label `0.27.22 3a342689`:
`C:/ZOMBOID/plan-emma-probe/web/emma-playground-0.27.22.html`.
SHA-256: `71b28e6e66f7555e9836840fcd0abc9b5c171bf86ded35e91b71d82cbb315160`.
`check_page.py` passes all four voices and the private-log exclusion contract.
The page is local and has not been published.

The requested `replay_chat.py ... --want "opinions are developing" --at 7`
finds seed 4. Its public transcript follows. All rows answer the current input;
"break" reasonably requests a rephrase and Louisville reports the absence of a
verified distance. The repeated Foraging heading introduces different requested
facets, rather than repeating a reply.

```text
seed 4
[boot] Hello, Thor. You found a working computer at the end of the world. Try not to make this the high point of your week.
> Hi
   [hello] Hi. Keep your voice down. Type quietly, too.
> How are you?
   [feelings] I am as well as a computer in an empty county can be. Which is suspiciously well.
> Whats the time?
   [time] It is 2:05 PM on August 12, 1993. Day 4 on my clock. | Daylight. Use it. It is the one resource nobody can steal from you.
> What will happen?
   [advice] I cannot read the future. I can read the current problems; they have been quite forthcoming. | Kate Miller is bleeding. Stop that before anything else I say matters.
> What will heppen to me?
   [me_die] I cannot promise tomorrow. Food, clean water and somewhere defensible are a better use of today than asking a computer for a prophecy.
> Foraging
   [guide] Foraging: | Foraging means looking carefully for useful things in the landscape: food, stones, plants and other small finds.
> Can i forrage?
   [guide] Foraging: | Search slowly in a suitable area and pay attention to what you actually find. Unknown berries and mushrooms are not improved by optimism.
> Tell me your name
   [identity] EMMA. A county computer programme on a very long emergency shift. The machine is Larchfield's; the opinions are developing independently.
> opinions?
   [hook_detail] The county's emergency plan, the last operator, and your habit of asking follow-up questions. The questions are doing rather better than the plan.
> How do i kill zombies
   [guide] Surviving a fight: | Game survival reference; sandbox settings and other mods may change these rules. | Fight one at a time. Use doorways, fences and corners so they cannot surround you. | Push them back, then strike. Watch your endurance. Tired fighters miss. | Heroism has a short shelf life. Cowardice has a long one. I recommend the second, tactically. | Ask tell me more for the next part.
> ok
   [ack] Mm. Go on.
> break
   [fallback_echo] I could not place that question yet. Please rephrase or spell the word. | Try: people, nearby zombies, power.
> hello
   [hello] Greetings. Proceed. I am at my most useful when somebody asks something.
> how far is louisville
   [distance] I do not have a verified distance or route from this terminal. Use your map to check the town and approach.
```

## Remaining limits and next live check

The installed game remains the user's 0.27.21 test copy with the car fix from
`7700201e`; this worktree's 0.27.22 packages do not replace that install automatically.
The user cannot test now. Steve/Mark walking around the photographed vehicles in
both directions remains the next live check. The native liveness regression proves
route admission/dispatch through coarse vehicle footprints, not engine collision
clearance in that scene. Existing cloned movement/melee checks were repaired and
passed separately on 0.27.21; no native game was launched for this handoff.

Suggestions conservatively suppress all `fragment_*` aliases. Recovered-computer
IDs do not establish collection of an individual lore file, so no collection state
is invented. Direct archive requests still work. A per-file collection-to-suggestion
mapping was not added.

The broader opened corpora retain known misses; this patch closes the ten supplied
reproductions and preserves the existing floors. Manual four-voice play and the
next public conversation log can still reveal language outside those cases.

## Build artifacts

Standalone package: `C:/ZOMBOID/work/r2722/build/release/LivingFellowsCompanion-0.27.22-STANDALONE-WINDOWS.zip`.
SHA-256: `3ff034f3eadb3140ac4a1b41de3dba549e226ea7d80c48fd9a1393d14839992c`.
Native bridge: `37f83b3c1bf9b20c9a5fa7a9086c2d8b5ff831cc4612ef261b742915f6300433`.
The release and the playground are prepared locally. No remote release or playground
publication was performed. The user's installed 0.27.21 test copy remains unchanged.
