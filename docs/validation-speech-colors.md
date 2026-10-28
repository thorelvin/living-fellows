<!-- SPDX-License-Identifier: MIT -->

# Living Fellows speaker colours

28 October 2026, `living_fellows/0.26.74`, based on `9b27e043`.
Project Zomboid 42.21.0 single-player; protocol `42.21-isocompanion-24` retained.

## Behaviour and persistence

All LF-owned people use one of twelve soft speaker colours. Colour identifies
the person; it does not indicate friendship, hostility or urgency. Small casts
favour separated hues, with balanced reuse after twelve assignments. An LF ID
breaks ties deterministically. Existing valid assignments take priority.

The optional `speechColorKey` follows registry admission, actor spawn profiles,
save capture/restore, household snapshots, hibernation and recruitment. Restore
prepares missing assignments in stable ID order before asynchronous spawning.
Invalid cosmetic values are repaired without rejecting the person. Save schemas,
inventories and actor ownership are unchanged.

Options > Mods > Living Fellows > **Speech colours** offers **Speaker colours**
(default) and **White text**. It is a local preference. Visible lines finish with
their original colour; later lines use the new setting. Saved keys remain intact.
Name tags retain their blue/gold selection treatment. Terminal text, player
speech and other mods' actors retain their existing styling.

## Native isolation

`emitCompanionSpeech(text,r,g,b,durationMs)` guards and emits once, with the same
real-time reading window as ordinary speech. All inherited chat overloads reach
one guarded full-overload implementation; explicit font/formatting arguments
pass through unchanged. Lua never retries a rejected or throwing modern call.
An older native bridge keeps guarded white speech and one Support diagnostic.
Stock hearing, distance and room muffling can still grey or scramble a caption;
speaker colours do not bypass those rules.

Refresh extends only this emission's existing newest viewport rows. Reflection
metadata is cached once, with at most four row checks per live lease. It never
calls `SayDebug`, reparses text, creates an unheard row or revives history. A
companion-only generation counter prevents a recycled identical native row from
inheriting an old lease. Missing refresh access logs once and leaves native fade
in control. Expiry and sleep release references; the existing cleanup still
clears native speech. Name clearance uses the existing screen-space renderer.

## Checks and limits

Automated checks cover palette validation, minimum contrast, separated small
casts, exhaustion, reordered restore preparation, malformed keys, replacement
actors, member/snapshot mirrors and the local white option. Production registry,
capture and restore-profile tests check the new field. Existing household,
recruitment, persistence and compatibility suites remain part of the full gate.

Native tests cover all overload paths, RGB/fonts/formatting, exact-once emission,
repeated words, recycled history rows, heard/unheard/deaf viewports, expiry, sleep
and cleanup. The game-JAR exposure/cleanup tests retain their existing coverage.

Live scope: a cloned camp, four existing people and twelve additional test
companions; per-person native save captures; lookup batches at 1, 4 and 16
actors; short, multiline and wrapped speech through every enabled zoom; two UI
font settings; daylight grass, night and a bright interior; and the white option.
Decision/movement are held for repeatable comparisons. These are speech/render
tests, not autonomous household, driving or combat acceptance. Lookup timings
are bounded warm batches, not an end-to-end AI performance benchmark.

The speaker's own name remains below its bubble. In the deliberately crowded
16-person fixture, other people's labels can still intersect long dialogue.
This change does not add cross-actor bubble/name collision avoidance.

The twelve colours have at least **12.3:1 contrast against black**. This is a
palette calculation, not a WCAG claim about translucent text over every game
background. The native outline/backdrop remains. Colour-vision review uses the
[Machado et al. model](https://doi.org/10.1109/TVCG.2009.113), with the published
matrices verified against [colorspacious](https://raw.githubusercontent.com/njsmith/colorspacious/master/colorspacious/cvd.py).
Some hues converge under those simulations; the names, positions and white
option remain available. Simulations do not replace user accessibility testing.
This follows the guidance to [avoid colour-only information](https://gameaccessibilityguidelines.com/ensure-no-essential-information-is-conveyed-by-a-fixed-colour-alone/)
and [retain text/background contrast](https://gameaccessibilityguidelines.com/provide-high-contrast-between-text-ui-and-background/).

The separate secondary-view attempt reproduced **`Lighting64.dll+0x23fd`** on
return to solo, after the primary-view restoration reported completion. This
existing native return failure remains unresolved. Secondary row behaviour is
tested automatically; live return-to-solo acceptance is **not passed**. No camera,
lighting or vehicle changes are included in this patch.

Final run records and representative original screenshots are retained in
`artifacts/speech-colors/acceptance`; all 54 solo-matrix originals remain under
`build/speech-colors/native-font-*`. Local installation and publishing are outside
this implementation run.

## Recorded result

- Full project gate: **29/29 passed**, 139.2 seconds for stages, 142 seconds total.
  Both normal and debug compilation passed for 241 Lua files. The dedicated Lua
  speaker-colour harness passed 64 assertions; native RGB/history/sleep checks,
  game-JAR exposure/cleanup, Bandits, A-Life and persistence regressions passed.
- Solo live matrix: **54 original captures**, including **42 zoom samples**;
  Small UI font heights 19 and 16 pixels. Both visual audits passed. All four
  source speaker colours were detected in each four-person capture; early/late
  native mint glyphs retained their colour after more than eight seconds.
- Colour-vision simulations were reviewed for protanopia, deuteranopia and
  tritanopia. The softer hues converge as expected; native outlines and names
  remain legible. Unscaled zoom crops and original day/night/white/interior
  screenshots were inspected. The dense-roster overlap limit above remains.
- Native bridge SHA-256:
  `7322d4b685fe2f09d177e3591488968cf1fa088cd2ae133d3cf6631161d95b52`.
- Secondary-view return: **not passed**, existing Lighting64 native crash.

[Full gate](../artifacts/speech-colors/acceptance/project-gate.txt),
[font 2 native evidence](../artifacts/speech-colors/acceptance/font-2-evidence.txt),
[font 6 native evidence](../artifacts/speech-colors/acceptance/font-6-evidence.txt),
[four speakers](../artifacts/speech-colors/acceptance/colour-four-speakers.png),
[white option](../artifacts/speech-colors/acceptance/colour-white-option.png),
[night](../artifacts/speech-colors/acceptance/colour-night.png),
[interior](../artifacts/speech-colors/acceptance/colour-bright-floor.png),
[return crash](../artifacts/speech-colors/acceptance/secondary-return-crash.log).
