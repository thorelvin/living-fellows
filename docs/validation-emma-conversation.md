<!-- SPDX-License-Identifier: MIT -->

# EMMA conversation and short-term memory

29 October 2026, `living_fellows/0.26.75`, continuing from `6863ee42`.

EMMA adds 38 two-part operating-help topics and 18 conversation subjects,
bringing the conversational directory to 42 subjects. Eight jokes, four
short stories and four poems add original variants to the existing pools.
Instructional wording supports normalization, conservative typo recovery
and unambiguous subject terms; current facts keep their existing live lanes.

`SCTerminalConversation.lua` owns static help and bounded temporary threads.
It retains eight subjects and sixteen operator questions. A subject expires
after 24 intervening turns; ten real minutes idle or a reversed clock clears
both the new thread and legacy pronoun/reference fields. The terminal supplies
its existing UI clock. Brief close/reopen uses the same PC's cached session;
world teardown discards sessions. Temporary memory is not exported to the
computer's portable save bucket. Saved notes remain independent.

Person references retain LF identity and re-resolve current roster entries.
Duplicate exact names, shared first names and fuzzy ties ask for a full name
or a numbered choice typed in chat. A group does not invent a singular
referent. Needs include current stamina and tiredness, while mood and skill
questions use the corresponding recorded fields. A removed actor cannot be
replaced by another actor reusing its name.

Item follow-ups retain the item and an optional operator-supplied quantity,
but read storage again on every check. Incomplete audits do not certify a
shortfall. Negative, fractional, malformed grouped, overflowing and
scientific-notation targets are not silently converted into an integer
prefix. There is no recipe inference from an unspecific "enough?".

Recent-topic return, conversational recap, correction prefixes and further
detail are read-only. Requests and confirmation tickets are never retained
as executable subjects. An explicit medic request using a pronoun still
creates a fresh proposal through existing preparation and confirmation.
Arithmetic follow-ups use a small fixed set of numeric operations; input is
never evaluated as code. Distant-place follow-ups preserve archive uncertainty
instead of substituting the local zombie count.

## Automated verification

- The pinned-game Kahlua harness covers every new help alias and conversational
  prompt, natural instructional wording, current count changes, quantities,
  corrections, pronouns, groups, exact and fuzzy ambiguity, actor replacement,
  topic return, arithmetic, finite limits, idle expiry and unchanged notes.
- UI tests cover a brief close/reopen, current stock, streamed needs, machine
  identity at reused coordinates, loss of camp access and real UI-clock expiry.
  All 13 new UI checks passed alongside the existing security, recovery,
  confirmed-action, factory-reset, reading, radio and layout regressions.
- The full project gate passed **29/29 stages** in 150 seconds overall.
  All **244 payload Lua files** compiled in normal and debug configurations.
  Bridge source, binary, protocol and save schemas are unchanged.

Gate output: [project gate](../artifacts/emma/native-acceptance/emma-conversation-project-gate.log).

## In-game acceptance

The runner uses a fresh disposable copy of the previously prepared Rising
world and the actual office computer at `12035,6739,0`. The copied main
character has the explicitly requested test skills; companion readings are
read from the native world provider. No source save, installed mod, preset
or main-profile files are modified.

Passed on Project Zomboid 42.21.0 with protocol `42.21-isocompanion-24`:

- Jill's actual LF identity survives a thank-you and a tiredness/stamina query.
- Brief logoff/reopen preserves the subject; a skill follow-up reads her
  current recorded skills and recap contains the preceding question.
- Scanner operating help advances to its second part.
- "Is it safe?" after Louisville retains the archive's uncertainty.
- Read-only conversation creates no action ticket; closing releases the
  terminal and leaves no secondary player view.

Native output: [acceptance results](../artifacts/emma/native-acceptance/emma-conversation-evidence.log).
Native framebuffer captures: [needs after acknowledgement](../artifacts/emma/native-acceptance/emma-conversation-needs.webp)
and [history after reopening](../artifacts/emma/native-acceptance/emma-conversation-history.webp).
The capture runner holds each window long enough for the rendered frames;
an earlier immediate-capture attempt retained the preceding world frame and
was superseded. Full-resolution originals remain in the disposable run, with
hashes recorded in [capture provenance](../artifacts/emma/native-acceptance/emma-conversation-captures.json).
This acceptance does not launch a new expedition or taxi, fit hardware,
retest RF distribution, or claim cross-reload conversation persistence.
