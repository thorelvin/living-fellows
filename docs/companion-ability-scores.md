<!-- SPDX-License-Identifier: MIT -->

# Companion ability scores

How a companion's physical capability is decided, and why none of it is a
mod-side number.

**Runtime:** Project Zomboid 42.20.4. Every engine behaviour cited here was read
out of the installed `projectzomboid.jar` or the game's own generated script
data, not from documentation.

---

## The scores are vanilla perks

A companion has four ability scores, and all four are perks the engine already
reads:

| Score | What the engine does with it |
|---|---|
| **Strength** | Carry capacity, melee damage, the climbing score |
| **Fitness** | Stamina, endurance recovery, the climbing score |
| **Nimble** | Movement speed while aiming, the climbing score |
| **Sprinting** | Run speed |

Nothing is simulated twice. Raising a companion's Strength genuinely makes them
carry more and hit harder, because it is the same field the game reads for the
player. This is the same rule `SCVitals` follows for health and needs.

## How a companion is rolled

```
score = clamp(baseline + spread + profession/aptitude boost, floor, 10)
```

- **baseline** — Strength 5 and Fitness 5, which is what Build 42 gives every
  player at character creation (`IsoGameCharacter.applyTraits` seeds exactly
  those two at 5 before any trait is considered). Nimble and Sprinting start
  at 0, as they do for a player.
- **spread** — a weighted roll from −4 to +3, so two Lumberjacks are not the
  same person.
- **boost** — the profession and aptitude maps that already existed.
- **floor** — 3 for Strength and Fitness. See below.

The roll is driven by `abilitySeed`, stored on the background record the first
time it is created and persisted with it. A companion therefore rolls once and
stays that person through every reload; nothing about their body is stored
twice or recomputed differently on a later load.

### Why there is a floor

`getClimbingFailChanceFloat()` is `int(sqrt(2*Fitness + 2*Strength + 2*Nimble
− moodle penalties))`, and `ClimbOverWallState.setParams` turns a score of 0
plus any heavy-load moodle into an *unconditional* climb failure. A companion
who rolled badly enough would be stranded by the first fence they met — which
is precisely the 0.22.36 bug, arrived at by a different route. Vanilla lets a
player choose that for themselves; a generated survivor should not inherit it
by accident.

Across 4,000 rolled companions the floor binds for about 22% of them, and the
resulting climb success rate ranges from 67% to 83%. None can be stranded.

## Traits

Two kinds, both real `CharacterTrait` script objects.

**Band traits** are the ones Build 42 derives from a perk level. Its own
`LevelPerk` listener in `XpSystem/XpUpdate.lua` re-derives them whenever a perk
is levelled normally:

| Strength | 0–1 Weak · 2–4 Feeble · 5 — · 6–8 Stout · 9+ Strong |
|---|---|
| **Fitness** | 0–1 Unfit · 2–4 Out of Shape · 5 — · 6–8 Fit · 9+ Athletic |

The mod writes levels with `setPerkLevelDebug`, which does **not** fire that
event, so `SCBackground` applies the identical mapping itself. Keeping it
identical is the point: the traits the engine reads always agree with the
levels the mod wrote.

**Character traits** are rolled per companion from a curated pool, one pick per
axis (hands, poise, nerve, hearing, sight, skin, recovery, appetite, presence).
Every id, cost and exclusion in that pool is copied from the game's generated
`character_traits.txt`, and only traits the engine actually acts on are
offered — so a line on the character sheet always means something in play. The
picks respect vanilla's mutual exclusions, stay inside a points budget of ±6 so
nobody rolls as nine gifts or nine afflictions, and refuse traits that
contradict the profession (a Fire Officer is never Cowardly).

Traits are **not** persisted separately. They are reproduced from the same
persisted `abilitySeed`, so a reload rebuilds the same person from the same
record rather than storing the answer twice.

## The character sheet

**More → Character.** It reads the live actor, not the background record, so it
reports what the engine currently believes rather than what the mod intended at
spawn. It shows the four scores with their band, the companion's traits, and
any learned skill above zero.

## Tests

`tests/gameplay/gameplay_harness.lua` covers the floor, the spread's variation,
roll stability across a reload, the band mapping against the engine's own
table, the trait budget, exclusion handling, profession mismatches, and that
traits reach the actor rather than merely being computed. Each was
negative-control verified by breaking the behaviour and confirming the test
fails.

One of those controls earned its keep immediately: the first version of the
sheet read `invoke()` results in the wrong order — `SCBackground`'s helper
returns *value first*, `SCPersistence`'s returns *ok first* — so the sheet was
silently reporting an empty trait and skill list. The only thing that caught it
was asserting the traits were on the actor rather than asserting the sheet
rendered.
