# Voice polish plan

Status: implemented in the working tree on 2026-10-01. A cloned four-member
two-floor Search now completes its return (`SC-Harness-20261001-070450-d80ae95d`),
so the homecoming path is reachable. The speech bubble and final wording still
need a visible listening check. The route evidence is recorded in
`docs/companion-playtest-fix-queue.md`.

This covers the mechanical half of the voice work: text that turns into bad
English once a `%N` placeholder is filled, characters the game cannot draw, and
one new bucket of lines for the quietest part of the mod. The editorial half
(tone and wording heard in situ) is still Voice pack WP3, which should wait for
playtest observations.

## Scope and method

| Source | Spoken strings | Lines with `%N` |
| --- | ---: | ---: |
| `SCDialogue.lua` (pools, last words, status, crisis, faction) | ~1,200 | 164 |
| `SCBanter.lua` | ~460 | 41 |
| `SCQuirks.lua` (zombie recognition, rituals) | ~170 | 56 |
| `SCTales.lua` (tall tales) | ~75 | 44 |
| `SCDowntime.lua`, `SCProduction.lua`, `SCRelationship.lua`, others | ~1,500 | 89 |
| `UI.json` spoken `IGUI_` entries | — | 3 |
| **Total** | **3,487 in 320 topics** | **394 in 48 groups** |

Every pool line goes through `Dialogue.choose` → `interpolate`
(`SCDialogue.lua:2154`), which replaces `%1`…`%6` with the caller's
arguments. For each group, I traced the caller to find every value a
placeholder can receive, then read each line with those values in place.

A mechanical lint over all 3,487 strings found no doubled words, stray spaces
or duplicate lines within a topic. The problems are almost entirely in how
placeholders are filled.

## Findings

| # | Problem | Example as spoken today | Lines |
| --- | --- | --- | ---: |
| 1 | A fill at the start of a sentence stays lowercase | "my friend! They've got me!", "friend, am I going to die?", "the next road coming up.", "he used to be the…" | ~45 |
| 2 | Item names arrive in Title Case with no article | "Got Kitchen Knife! Hell yes.", "Broke the Hand Axe.", "Their Wedding Ring." | 81 |
| 3 | `interpolate` stops at a `nil` argument and keeps an empty one | a nil `%1` leaves `%2`/`%3` printed literally; an empty street gives "Crossing at ." | engine |
| 4 | Status answers get "-ing" phrases in lines built for a verb or noun | "finding another way to bandaging a wound", "That bandaging a wound attempt didn't work." | 10 |
| 5 | 92 action names have no readable label and fall back to the raw key | "I'm chop tree right now." | engine |
| 6 | Seconds are not singular-aware | "I'll try again in about 1 seconds." | 6 |
| 7 | Zombie recognition: home towns are raw lowercase keys | "the county deputy from muldraugh", "kind to me in west point" | 5 |
| 8 | Zombie recognition: role fallback does not fit "the/a %3" | "the someone from back home from Kentucky", "I knew a someone from back home named…" | 5 |
| 9 | Zombie recognition: "they" gets singular verbs; "old" doubles | "they was safe", "if they comes closer", "Our old old football coach" | 5 |
| 10 | Tall tales add their own preposition to a place that already has one | "Came out of nowhere at out in the open.", "at the woods", "don't go to out in the open anymore" | 3 |
| 11 | Faction standing and supply words do not fit the sentence | "We are trusted toward you.", "tolerated toward you", "with unknown supplies" | 4 |
| 12 | Plural supply labels break two singular lines | "Our medical supplies stock…", "There's not enough tools." | 2 |
| 13 | Grief fallback is capitalized but usually lands mid-sentence | "I keep thinking about Someone from our group." | 20 |
| 14 | Double-encoded em dash (mojibake) | `SCQuirks.lua:1213` "Look at youâ€”yellow, unbitten…" | 1 |
| 15 | Em dashes in speech may render as `?`; the game drew the `·` in place labels as `?` | "Single contact ahead ? nothing we can't handle." | 23 |

## Work package A — engine (code)

These fix the most lines for the least change and should land first.

### A1. Rewrite `interpolate` as a single pass (`SCDialogue.lua:2154`)

- Replace the `ipairs` loop with one `gsub("%%(%d)", …)` that looks up
  `arguments[n]` directly. This ends the `nil`-hole problem and cannot
  re-substitute a `%2` that happens to appear inside an argument.
- Treat `nil` and `""` as missing. If any marker is still unfilled, `choose`
  should skip that line and try another candidate, then `options.fallback`. If
  nothing fits, it should not speak and should write one bounded diagnostic
  (`dialogue_argument_missing`, with the topic). Never speak a raw `%N`.

### A2. Capitalize a fill that starts a sentence

In the same pass, uppercase only the first letter of a fill that sits at the
start of the line or after `.`, `!` or `?` plus a space (also after a leading
`*action*`). Leave the rest of the fill alone. This fixes most of finding 1:
last words, crisis, banter, road junctions, status answers and recognition
pronouns.

### A3. `U.itemPhrase(itemOrName)` in `SCGameplayUtil.lua`

Turns a display name into a phrase that reads correctly mid-sentence:

- Drop a trailing parenthetical: "Canned Beans (Opened)" → "canned beans".
- Lowercase common words. Keep possessive brands ("Spiffo's"), all-caps
  words, and a small keep-case list.
- Article: "some" for plurals and mass nouns (water, rice, flour, bleach,
  ammunition, gasoline and similar); "an" before a vowel sound, with the usual
  exceptions (uniform, used, one); otherwise "a". Container phrases keep their
  own article: "Box of Nails" → "a box of nails".
- Keep the existing fallback "something".
- Callers: loot reactions (`SCEncounter.lua:1579`, 68 lines), broken tools
  (`SCProduction.lua:1409`, 6 lines), mementos (`SCDowntime.lua` respects,
  7 lines). Tall-tale weapons are already lowercased and used after "my".
- Two lines need the bare noun rather than the article form, "Broke the %1."
  and "That's the end of this %1." Pass a second argument (`%2` = bare noun)
  or reword them to "Broke %1." and "That's the end of %1."
- Check first: `task.itemName` is `"unopened"` while a container is unread
  (`SCEncounter.lua:1633`). Confirm that the loot reaction only runs after the
  item has been read (`:2294`). Otherwise it could say "Found unopened."

### A4. Label every action for status answers (`SCRelationship.lua:505`)

- Add labels for the supervisor actions a player can actually ask about. Among
  the 92 unlabelled names, some that are clearly spoken: `chop_tree` "chopping
  a tree", `dig_grave` "digging a grave", `bury_body` "burying someone",
  `burn_body` "tending a pyre", `eat_food` "eating", `drink_item`/`drink_source`
  "getting a drink", `barricade` "barricading", `dismantle` "taking something
  apart", `guard_patrol` "patrolling", `hide_indoors` "staying out of sight",
  `investigate_sound` "checking a noise".
- Add prefix labels for families such as `farm_*` ("tending the farm") and
  `logistics_*`.
- Change the fallback from the raw key to "busy with a job".
- Add a static test that collects every `action = "…"` handed to the supervisor
  and fails when one has no label.

### A5. Singular-aware seconds

`doing.failed` passes a bare number. Pass a phrase instead ("1 second",
"12 seconds"), and change the lines from "about %2 seconds" to "about %2".

### A6. Guard test: a render matrix

Add one harness that renders every registered pool line with that topic's
edge-case fills and asserts:

- no leftover `%N`;
- no lowercase letter at a sentence start;
- no doubled spaces, and no space before `.`;
- ASCII only.

Edge-case fills to include: nil, an empty string, a long name, "they", a
plural item, a mass noun, a vowel-initial item, a street with no name, and
every home, role, standing and supply value.

This single test is what keeps the other work packages fixed; the scratch
inventory used for this audit becomes redundant once it exists. Per project
rule, prove each check fails when its fix is reverted.

## Work package B — fill sources (code)

| Where | Change |
| --- | --- |
| Road junctions, `SCExpeditionPrototype.lua:2721` | Treat an empty `crossing.street` as missing, so "the next road" is used (A2 capitalizes it). |
| Grief fallbacks, `SCAutonomy.lua:819`, `SCRelationship.lua:612/647` | "Someone from our group" → "someone from our group". A2 capitalizes it at a sentence start. |
| Recognition home, `SCQuirks.lua:283` | Use the display names in `Study.HOMES` (`SCDowntime.lua:1314`). Better, move that map to `SCBackground` as `homeLabel(key)` and use it in both places. |
| Recognition role, `SCQuirks.lua:282` | Fallback role "neighbor" instead of "someone from back home"; rename "old football coach" to "football coach". Both then fit "the %3", "a %3" and "Our old %3". |
| Tall tales, `SCTales.lua:595/619` | Pass two place forms: `%1` a noun ("the woods"; "open ground" for open places) and a new `%6`, a location phrase ("in the woods", "out in the open", "on the road", "on a farm", "at the gas station", "in somebody's house"). |
| Faction status, `SCFactionContracts.lua:840` | Map standing to a phrase: Trusted "on good terms with you", Tolerated "willing to deal with you", Wary "wary of you", Hostile "hostile to you". Map supplies: Stable "steady", Low "low", Critical "critical", Unknown "uncertain". |

## Work package C — line rewrites (text)

Assumes A2 (sentence-start capitals) and B are in place.

### Status answers (`SCDialogue.lua:1026-1059`)

| Topic | Before | After |
| --- | --- | --- |
| doing.active | I'm working on %1. | I'm busy %1. |
| doing.target | I'm working on %1 near %2. | I'm busy %1 near %2. |
| doing.target | I'm handling %1 by %2. | I'm %1 over by %2. |
| doing.waiting | I haven't abandoned it. I'm waiting on %1. | I haven't abandoned it. I'm still waiting to finish %1. |
| doing.waiting (steady) | Waiting on %1. It seems committed to taking its time. | Still waiting to finish %1. It seems committed to taking its time. |
| doing.recovering | That route failed. I'm finding another way to %1. | That route failed. I'm finding another way. Still %1. |
| doing.recovering | I'm still on it. I need a safer route for %1. | I'm still %1. I just need a safer route. |
| doing.recovering (steady) | Finding another way to %1. The first way had opinions. | Still %1, by another route. The first one had opinions. |
| doing.failed | That %1 attempt didn't work. I'm waiting %2 seconds before another try. | That attempt at %1 didn't work. I'm waiting %2 before another try. |
| doing.failed (all) | … about %2 seconds … | … about %2 … (see A5) |

### Zombie recognition (`SCQuirks.lua:1079-1153`)

| Before | After |
| --- | --- |
| %1? No. Couldn't be. Still—watch that walker. | %1? No. Couldn't be. Still, watch that walker. |
| Tell me that isn't %1. %2 was our %3. Stay sharp. | Tell me that isn't %1. Our %3, once. Stay sharp. |
| %1 used to wave from across the road. Now %2 is crossing it dead. | %1 used to wave from across the road. Now that walker is crossing it dead. |
| Looks like %1. Doesn't matter—I'm putting %5 down if %2 comes closer. | Looks like %1. Doesn't matter. I'm putting %5 down if that walker comes closer. |
| %1 was kind to me in %4. Watch that walker—please. | %1 was kind to me in %4. Watch that walker. Please. |
| Possible match: %1, %3. Identification changes nothing—walker ahead. | Possible match: %1, %3. Identification changes nothing. Walker ahead. |
| %1? No. No, %2 was safe. Wasn't %2? | %1? No. No, %1 got out. Didn't %2? |
| %1, is that— no. Keep your distance from it. | %1, is that... no. Keep your distance from it. |
| Not %1. Shame—I had a speech ready. | Not %1. Shame. I had a speech ready. |

### Tall tales (`SCTales.lua`)

| Before | After |
| --- | --- |
| %2 of 'em. Came out of nowhere at %1. | %2 of 'em. Came out of nowhere, %6. |
| And that's why I don't go to %1 anymore. | And that's why I stay away from %1 now. |
| Point is, don't ever mess with me at %1. | Point is, don't ever mess with me %6. |

Also check whether a tale can start with a single kill. If it can, "%2
zombies, one of me" reads "1 zombies"; give count 1 its own wording, or require
two kills before a tale forms.

### Faction households (`SCDialogue.lua:1918-1995`)

| Before | After |
| --- | --- |
| We are %1 toward you. Supplies are %2. | We are %1. Supplies are %2. |
| Our position toward you is %1, and our stores are %2. | As for you, we are %1. Our stores are %2. |
| Right now relations are %1. Supply levels remain %2. | Right now we are %1. Supply levels remain %2. |
| The house stands. We are %1 toward you, with %2 supplies. | The house stands. We are %1, and our supplies are %2. |
| Our %1 stock is almost gone. | Our stock of %1 is almost gone. |
| There's not enough %1. That's our problem right now. | We don't have enough %1. That's our problem right now. |

### Minor, optional

- "I went through my %5 like it owed me money." reads oddly with "bare
  hands". It is harmless; leave it for the WP3 editorial pass.
- "%1. It is wet, and I refuse to ask why." (gross loot) says "it" for plural
  items. Also left for WP3.

## Work package D — characters the game may not draw

1. Fix the mojibake at `SCQuirks.lua:1213`: "Look at youâ€”yellow, unbitten,
   and coming with me." → "Look at you. Yellow, unbitten, and coming with me."
2. Replace the 23 em dashes in speech (17 in `SCDialogue.lua` combat, grab and
   loot lines, 6 in `SCQuirks.lua`) with ASCII. Use " - " where the line wants
   a beat ("I'm pinned - help!", which matches the existing "No, no, no - %1,
   HELP!"), or a full stop where two sentences meet.
3. Before changing the five em dashes in `UI.json` labels (base defense modes,
   CQB role, horde progress), check in game whether the UI font draws them.
4. The render-matrix test (A6) enforces ASCII-only speech from then on.

## Where companions are quiet

Lines per topic family (all sources):

| Family | Lines | Topics |
| --- | ---: | ---: |
| banter | 492 | 32 |
| combat | 256 | 14 |
| last words | 240 | 4 |
| study | 218 | 53 |
| crisis | 163 | 14 |
| danger | 145 | 7 |
| … | | |
| **expedition** | **37** | **3** |

Expeditions are the headline feature and the longest stretch of play with
companions, yet they have 37 lines: departure (20), road junctions (12) and
search arrival (5). These moments are completely silent:

- the squad turning home (time up, supplies found, horde with no detour, site
  unreachable, radio recall);
- the squad reaching you again at the end;
- a horde detour starting;
- sheltering in a house (radio text only, no speech);
- a long off-road stretch;
- a Search that found nothing.

The biggest silent moment is the homecoming. The squad walks up to you after
a trip that may have taken hours, and `Expedition.finishAtPlayer` ends the
mission without anyone saying a word. That is the new bucket below. The other
moments are good follow-up buckets (see "Later buckets").

## Work package E — new bucket: `expedition.homecoming`

### When it fires

- **Hook:** in `Expedition.finishAtPlayer` (`SCExpeditionPrototype.lua:2988`),
  after the leader view is released and `mission.terminal = "returned"` is
  set, before `mission = nil`.
- **Only when nobody was lost.** Every roster member must be alive, present in
  `mission.survivors`, and within the 12-tile assembly check. A casualty skips
  this bucket; grief and mourning already own that moment, and several lines
  below say everyone made it.
- **Speaker:** the leader if alive and within speaking distance of the player,
  otherwise a random other survivor. One line per mission. Use
  `pcall(SC.Dialogue.say, speaker, "expedition.homecoming")` as the junction
  callout does.
- **Neutral about results.** Scout missions bring nothing back and a Search can
  come back empty, so no line claims supplies or success. The debrief panel
  carries the facts.
- **Neutral about place.** The squad returns to wherever you are, which may not
  be a base, so no line mentions home, doors or windows as facts.
- **No placeholders.** Plain ASCII, straight apostrophes.

### The 20 lines

The pool follows the existing shape: 12 common lines plus 2 for each voice. A
speaker therefore draws from 14 candidates, which is enough to avoid repeats
across several trips.

```lua
["expedition.homecoming"] = {
    common = {
        "We're back. Everybody who left is standing right here.",
        "Told you. We leave together, we come back together.",
        "That's the trip. Count heads. We're all here.",
        "Made it back. Somebody tell me there's coffee.",
        "Back in one piece. Several pieces, technically, all still attached.",
        "The road let us go. I'm not going to ask why.",
        "Back before the county changed its mind about us.",
        "We're back. Give us a minute, then you get the full report.",
        "Boots off soon. Stories later. Most of them true.",
        "Every one of us walked back. Somebody write that down.",
        "Kentucky tried its best. We came back anyway.",
        "Good to see a face that isn't trying to bite me.",
    },
    brave = {
        "Back already. The road should've tried harder.",
        "Out and back. Point me at the next one.",
    },
    cautious = {
        "We're back. I checked behind us twice. Keep an eye on the road anyway.",
        "Made it. I'll relax once there's a locked door between us and the road.",
    },
    caring = {
        "We're back, all of us. Now let me look at you for a change.",
        "Everyone made it. I kept counting the whole way.",
    },
    practical = {
        "Squad's back, headcount matches. Report when you're ready.",
        "Returned with everyone we left with. That's the number that matters.",
    },
},
```

"We leave together, we come back together" answers the departure line
"We leave together. We come back together. That's the deal."

### Tests

- In the expedition restart harness:
  - a full-roster `finishAtPlayer` produces exactly one `expedition.homecoming`
    line from the leader;
  - a roster with a casualty produces none;
  - a failed release (`return_view_release_failed`) produces none.
- A static check that the pool has 20 ASCII lines and no placeholders.
- A negative control for each check.
- One visible check in a cloned save: the line should appear over the
  returning companion's head, not the player's, and be readable before the
  view closes.

## Later buckets (not planned in detail)

| Topic | Moment | Notes |
| --- | --- | --- |
| `expedition.turn_home.<reason>` | `startReturnFromSite` | One small pool per reason: time up, quantity met, observed, horde with no detour, unreachable, radio recall. |
| `expedition.homecoming.loss` | `finishAtPlayer` with a casualty | Short and quiet; hand over to the existing mourning. |
| `expedition.detour` | a horde avoidance route is accepted | "Horde on the road. We go around." |
| `expedition.search_arrival` | already exists with 5 lines | Grow to 12 or more. |

## Suggested order

1. **A1, A2 and A6:** the engine fix plus the guard test. Largest effect, and
   everything after it is checked automatically.
2. **A3 and B:** fill sources: item phrases, homes, roles, tale places,
   faction phrases, empty streets, grief fallback.
3. **C and D:** line rewrites and ASCII cleanup.
4. **A4 and A5:** action labels and seconds.
5. **E:** the homecoming bucket, then a cloned-save check.
6. Changelog entry. No save-format or persistence changes are involved.

## Open checks for the playtest

- Whether the speech bubble font draws em dashes (decides D2's urgency for
  `UI.json`).
- The loot reaction runs after the inventory transfer and now rejects an
  unread `unopened` source. A one-kill tall tale now tells at least two kills
  in its exaggeration; zero kills remains zero.
- How the homecoming line reads when the squad arrives while you are fighting
  or driving. Consider skipping it when the player has an immediate threat.

## Implementation checks

- The gameplay Kahlua harness passes with a render sweep of registered speech
  pools, item phrase cases, missing-marker negative controls, and the 20-line
  ASCII homecoming pool.
- The static action inventory covers 99 literal action names and passes with
  an unknown-action negative control. It runs in the source and core gates.
- The restart harness verifies that casualty and failed-release returns stay
  silent and an intact release speaks once from the leader. Its later scout
  path assertion still fails on the pre-existing loaded-leg fixture; the core
  run finishes 48 of 49 harnesses.
- A cloned-save two-floor Search reached and looted upstairs, then stalled on
  descent. No in-game homecoming bubble was observed. The full-squad stair
  transition and visible homecoming check remain open until that route works.
