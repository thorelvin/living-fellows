<!-- SPDX-License-Identifier: MIT -->

# Gallery, workshop and leisure terminals

28 October 2026, `living_fellows/0.26.74`, after `9b27e043`.

Six transparent original headers expand the catalogue to 224 distinct
identities: 208 named marks and 16 camp/sector emblems. Names and visual
references were checked against the installed 42.21.0 stock adverts.

| Identity | Screen | Artwork |
| --- | --- | --- |
| Art Gallery of Louisville | Sand | Ivory condensed lettering, wine frame |
| Home Sweet Gnome | Aqua | Pale blue/ivory lettering, terracotta hat |
| Circuital Healing | Aqua | Neutral segmented lettering, phosphor tint |
| Irvington Speedway | Sand | Ivory racing wordmark, red accent |
| Sunset Pines Funeral Home | Sand | Ivory and gold serif mark, pine outline |
| Roxy's Roller Rink | Aqua | Aqua and mauve lettering, skate outline |

The assets live in `SurvivorCompanion/42/media/textures/Terminal/` under the
IDs `ArtGalleryLouisville`, `HomeSweetGnome`, `CircuitalHealing`,
`IrvingtonSpeedway`, `SunsetPines` and `RoxysRollerRink`, with `.png` suffixes.
The built-in imagegen tool produced each selected bitmap. All six are copied
unchanged from its output; there is no scripted colour conversion, matte or
foreground removal. The first Gnome blue was rejected after native inspection
and lightened with imagegen. A first Sunset Pines design was also rejected in
favour of flat ink. Final prompts, generator inputs, selected source paths,
hashes and alpha bounds are recorded in
`artifacts/emma/research/places-logo-jobs.json` and
`docs/terminal-community-art-manifest.json`.

Seven appended owner archives add 28 original July entries: gallery
conservation, a gnome workshop, an electronics repair bench, race management,
gate security, funeral arrangements and a rink counter. Speedway security
rooms receive gate records rather than generic prison stories. Existing owner
IDs stay in their earlier positions. Staff names and incidents are original
mod fiction; the adverts establish the businesses, not these biographies.
The catalogue now contains 568 personal entries across 142 owners.

Six business reference cards and eight outbreak fragments bring the reference
catalogue to 150 files, including 34 fragments. New accounts include *July
mittens*, *The fourth switch*, *Parking bay six* and *Last collected*. They
retain the unverified-archive label, July date gates and related-file browsing.
They make no claim about current supplies, safe routes or an infection cause.

Five specific advert keys support new site recognition. The census finds four
desktops at the gallery, two at Home Sweet Gnome and 33 around Speedway rooms;
it finds none at Roxy's or Sunset Pines. The latter identities still support
same-room signs, explicit metadata and computers placed at those premises.
Circuital Healing's rectangle includes other tenants, so it is deliberately
excluded: its identity requires an own-room sign or explicit metadata. The
Pondview shopping centre and Leafhill office-rental advert remain excluded.
The census now records 68 curated advert keys, 67 rectangles, 346 unambiguous
rectangle candidates and 29 exact-room candidates among 3,536 desktops.
These are static assignment candidates, not guaranteed live placements.

Automated checks passed:

- Brain/world: 12,278 assertions; security/archive: 6,253.
- Lore/branding: 2,167; knowledge: 3,753.
- UI suite: 93 cases; 1,052 reference-menu assertions, reaching all 150 files
  through full and narrow layouts. Factory reset still passes its 24 checks.
- Own-room sign recognition, cross-wall refusal, private-room exclusion,
  matching archive kinds, Speedway security and rare-purple eligibility.
- Six source-identical RGBA assets with transparent margins, no backing keys
  and alpha bounds derived by the existing metadata tool.

The final project gate passed **29/29 stages**: 142.2 seconds for the stages,
145 seconds overall. All 241 payload Lua files compiled in normal and debug
configurations; Workshop and standalone packaging checks passed.

Native acceptance used the existing disposable clone with game 42.21.0 and
bridge protocol `42.21-isocompanion-24`. Its real powered desktop handled all
14 new topic aliases through terminal input without changing its saved owner.
At the clone's date, 147 of 150 reference files were available; the three
future reports stayed hidden. Six logo/archive previews and two purple
variants were captured from the actual framebuffer at 1280×720, font height
32. All five personal-file shortcuts fit. Site assignment was checked by the
headless production logic and census, not by visiting all six sites in-game.
No taxi, expedition or secondary view was started.

Reproduction: `artifacts/emma/run-terminal-civic-tests.ps1`,
`tests/ui/run_ui_tests.ps1`, `artifacts/emma/run-terminal-places-native.ps1` and
`artifacts/emma/terminal-places-native.lua`. Supporting source evidence is in
`artifacts/emma/research/places-sources.json`; inspected captures and logs are
under `artifacts/emma/native-acceptance/emma-places-*` and
`terminal-places-*`. No save schema or runtime network behaviour changes.
