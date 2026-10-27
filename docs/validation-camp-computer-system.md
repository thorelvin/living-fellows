<!-- SPDX-License-Identifier: MIT -->

# Camp computer system validation

Validated on 2026-10-27 against the pinned Project Zomboid 42.21.0 runtime.
The implementation ships on `living_fellows/0.26.71`, based on `a66bbf4b`.

## Scope

LARCH/OS adds a centred full-screen terminal with generated CRT glass and a
transparent monitor casing, large resolution-scaled text, an animated
1993-style POST, four persistent phosphor palettes,
whole-computer password recovery, a numbered mouse/keyboard menu, 340
original July 1993 entries across 85 previous owners, and 16 county/EMMA
reference files. Locks,
files, EMMA notes and operator memory travel in the game's `movableData`
furniture payload. Existing used EMMA computers retain access. First pickup
assigns unopened computers their original location's security state before
native furniture handling copies the payload.

Camp people, storage, jobs and expedition providers reject outside-computer
queries before reading camp records. Questions, synonyms, typo correction,
short-term context and presentation run locally in Lua. Source inspection
found no network or external-model calls in the terminal modules.

## Automated evidence

- The pure Kahlua harness exercises lock assignment across 1,000 seeds,
  Electrical difficulty, exact-position feedback, bracket bonuses, invalid
  guesses, one-hour lockout boundaries, persisted boards and malformed records.
  It also checks all archive profiles and board widths from 12 to 64 columns.
- Existing intent, context, typo, fixed-world answer, memory and input-fuzz
  regressions pass. Outside-camp provider tests throw if roster, job or
  expedition reads occur, so an access refusal cannot conceal a data read.
- The terminal UI suite passes its 59 existing checks, 92 system checks and
  283 presentation checks. Geometry-dependent check totals change with the
  number of wrapped menu rows.
  These cover whole-computer locks, click and keyboard input, files, one-time
  native XP calls, power loss, legacy access, native pickup-wrapper chaining,
  portable state, distinct computer identities and conversation cleanup.
  Presentation geometry uses ten viewport shapes from 640x480 through
  3840x2160, including narrow split views and ultrawide. It exercises four
  native font sizes with the actual display scaling applied. Content remains
  centred, and the header, transcript, hints and editable entry do not overlap.
  Drafts, sessions and history survive reflow. The body uses 32-pixel font
  height at 720p, 44 at 1080p and 88 at 4K; the native entry selects the
  closest available font, including the game's Massive font.
- Across 100,000 seeds purple remains about one percent, independently of
  password assignment, including when brand pairings apply. Fossoil receives
  aquamarine unless its seed selects rare purple. Old machines calibrate once
  without changing their lock or puzzle, and keep the result after movement
  and normalization. Rendering preserves brand hues and aspect ratios with
  consistent subdued brightness, scanlines and phosphor corner marks. The
  camp source sheet selects a single matching phosphor emblem. Repeated module
  loading preserves the source bounds; a failed texture draw releases its
  stencil so the remaining UI can render.
- CRT geometry is cached with the layout and remains inside the owning
  viewport. Controls fit inside the measured transparent opening at every
  tested size. The glass texture is drawn before live text; eight frame
  sections follow the children, omitting the centre. This preserves drafts,
  focus and world reads. The native `UIElement` render order was inspected
  to confirm the casing renders after child controls. No raster is drawn
  over the text or caret.
- Runtime transaction tests confirm world teardown invokes terminal cleanup.
  Rendering and typing checks confirm camp records are not rescanned each frame.
- Negative controls fail as intended when lockout enforcement, outside-camp
  provider barriers or the one-time XP guard are removed from temporary source
  copies. Production files were not changed for those runs. The real native
  run also exposed a Kahlua large-number remainder problem in the spinner:
  animation now uses elapsed time instead of epoch milliseconds. A regression
  test uses the original epoch-sized timestamp.
- The final project gate passes all 29 stages. This includes Lua compilation, native
  contracts, combat, both NPC adapters, UI, packaging and installer transactions.

Evidence is under `build/larchos-validation/`:
`fullscreen-final-project-gate.log`, `fullscreen-ui.log`,
`brand-integration-project-gate.log`, `brand-integration-ui.log`,
`crt-project-gate.log`, `crt-ui.log`,
`framed-final-project-gate.log`, `framed-ui.log`, `framed-assets.log`,
`office1993-project-gate.log`, `office1993-ui.log`, `office1993-assets.log`,
`epoch-regression-baseline.log`, `branding-reload-baseline.log` and the three
`negative-*.log` files. The native furniture pickup/placement
source was inspected to verify which mod-data payload travels with a computer;
the automated movement tests simulate that payload transfer.

## Native presentation acceptance

The existing live sandbox runner prepared a disposable cloned world from the
local Rising save. The source save was read-only input, and updated Lua and
art were copied only into the clone. Its isolated bridge ran with Steam,
audio and voice disabled. The test fixture creates a desktop at the cloned
player's position and supplies power for that object only. It explicitly
selects brands and colours to check presentation; it does not validate
automatic company assignment at those locations.

The earlier presentation run completed these checks with the real 42.21.0
renderer and native text-entry widget:

- Full-screen POST and green, golden-sand, aquamarine and purple screens at
  1280x720; purple chat and file menus at 1920x1080.
- Native textbox callbacks for immediate number selection, Tab focus,
  ordinary numbers in chat, draft preservation, Enter submission, Escape
  navigation and keyboard release on closing. These invoke the native
  callbacks, rather than injecting physical keyboard events.
- All 198 catalog textures load: 183 stock references and fifteen local
  assets. The camp sheet displays one emblem, keeping its original green
  colour on a purple terminal.
- Live reflow between resolutions and into a simulated narrow viewport.
  The latter overrides viewport dimensions only; it is not an actual
  split-screen session and does not change player or camera ownership.

The monitor/desktop limits the requested 3840x2160 game window to
2564x1421. Native evidence records that actual size; true 4K geometry is
covered headlessly, not claimed as a native 4K screenshot. PNGs exported
through the game and the evidence log are in
`artifacts/emma/native-acceptance/`, with `fullscreen-` filenames for the
final layout. The test-only probe is
`artifacts/emma/terminal-native-acceptance.lua`; it is not shipped in the mod.

The follow-up branding run exports `branded-` screenshots. It verifies the
Fossoil/aquamarine pairing, shows Fossoil against both aquamarine and golden
sand, and checks the common treatment on Finnegan, ValuTech, the research
fallback and the camp emblem. These are native game captures, not mockups.
The metadata generator reads alpha bounds for all 198 logos and records 168
colour pairings; neutral marks retain a seeded choice. This work is entirely
offline at runtime. Neither image analysis nor generation runs inside the game.

The earlier CRT follow-up completed eleven native captures with `crt-` filenames,
including the green camp terminal at 1920x1080. Raster lines remain visible
across the header, logos, menu, chat and native input. Green, sand, aquamarine
and purple share the effect. Boot, resize, narrow-view reflow and all native
keyboard callback checks passed again. The native source confirms parent
post-render runs after child controls, so the input receives the same glass
overlay. That paint treatment was subsequently replaced by the generated
glass and casing below.

The generated skin uses two original 1586x992 PNGs in
`media/textures/Terminal/Skin/`: opaque neutral scanline glass and an RGBA
beige Larchfield casing. The current casing was generated from scratch with
no reference images. It has a straight lower bezel, a left power switch and
indicator, side vents and right brightness/contrast wheels. The original
olive asset is retired in `artifacts/emma/art-history/` and is not shipped in
the active skin or used as the base for this design. Source prompts and filenames are recorded in
`docs/terminal-skin-art.json`. The read-only asset check
`artifacts/emma/research/verify_terminal_skin.py` verifies their dimensions,
transparent opening, dark neutral glass and file hashes. Image pixels are
unchanged from the generator outputs. The casing is drawn in eight sections
with its centre omitted; the corners and power switch retain their proportions
while the middle edges expand. Content is inset from the rounded screen lip.

The final `framed-` capture set contains eleven native screenshots: first
boot, aquamarine and sand Fossoil, neutral Finnegan, green ValuTech, purple
chat/files, the camp emblem, narrow reflow and the green camp terminal.
Preloading the two skin textures during client Lua startup fixes their
asynchronous upload appearing after the first POST text. The final cold-start
capture includes both textures from the first boot screen. Native keyboard
callbacks and all 198 logo loads pass. The final project gate passes 29/29
stages in 139 seconds; the source save and installed game were not modified.

The current original 1993 frame uses the `office1993-` capture prefix. Its
measured screen bounds and frame cuts were updated to preserve the wordmark,
power switch, side vents and thumbwheels during resizing. The separate glass
texture and terminal controls are retained. The asset check confirms the
screen opening remains transparent and the frame geometry matches the PNG.
Eleven native captures, all four colours, first boot, files, chat, reflow and
keyboard callbacks pass with this original frame. The complete project gate
passes 29/29 stages in 137 seconds. Current screenshots and evidence use the
`office1993-` prefix; the earlier `framed-` and `crt-` sets are historical.

## Startup audio

The supplied `System Initialization (1).mp3` is registered as the local,
non-looping `LFTerminalBoot` UI sound. The packaged Ogg Vorbis preserves all
363,528 source frames, 48 kHz stereo and 7.5735-second duration, with no
trimming, normalization or resampling. Original and game-file hashes are in
`docs/terminal-boot-audio.json`; the supplied MP3 is retained under
`artifacts/emma/audio-source/`.

Fifteen UI checks cover once-per-window playback, refresh/repeated-start
requests, natural POST completion, Enter skip, close, power loss, world exit,
unrelated UI sounds, muted audio and device errors. The sound uses the native
UI manager and game volume, with no world emitter or zombie-noise request.

A dedicated cloned-world run enabled native audio. FMOD started a positive
owned handle at sound volume 0.4, kept playing after normal POST completed,
finished without looping, and stopped an active second playback on close.
Evidence is `artifacts/emma/native-acceptance/boot-audio-evidence.log`; the
test-only probe is `artifacts/emma/terminal-boot-audio-native.lua`. The source
save and installed game were not changed. Automated logs are
`build/larchos-validation/boot-audio-ui.log` and
`build/larchos-validation/boot-audio-project-gate.log`.

The walkie-talkie booking action also uses the supplied clip, registered
separately as `LFTaxiRadioCall` so terminal cleanup cannot stop a radio call.
Playback follows a newly accepted request only; invalid radios, duplicate
requests and status checks do not replay it. Cancellation and context-hook
removal stop its owned handle, preserving other UI sounds. Audio failure
cannot reject a valid booking. Taxi fare/recovery/context regressions pass.

The native radio-audio run exercised the actual inventory-menu callback and
FMOD with an isolated accepted-dispatch result. No cab was dispatched by the
fixture. It verified playback, duplicate suppression, natural completion and
cancellation cleanup. Evidence is
`artifacts/emma/native-acceptance/taxi-radio-audio-evidence.log`; the probe is
`artifacts/emma/taxi-radio-audio-native.lua`. Focused and complete checks are
in `build/larchos-validation/taxi-audio-focused.log` and
`build/larchos-validation/taxi-audio-project-gate.log`.

## Remaining acceptance and planned work

Native furniture pickup/placement, save/reload and actual Electrical XP
still need in-game confirmation. The automated tests simulate the portable
furniture payload and XP calls; the presentation run does not replace those
security and persistence scenarios. Physical keyboard interaction also
remains a separate user check.

Companion computer downtime remains planned in
[the computer guide](camp-computer.md#what-is-implemented). Expanded authored
lore is implemented and verified below.

## Confirmed requests and live records

Implemented `SCTerminalActions.lua` with fixed medic, generator/car refuel
and blocked-job retry requests. Native game objects never enter the text
parser. A private, ephemeral confirmation binds the current main-player
window, computer access record, camp object and exact target identity. It
expires after 120 real seconds. Cancellation, another input, session teardown
or power loss discards it. Execution consumes consent before calling any
domain API, including error and reentrant paths.

Refuelling uses `SC.GeneratorRefuel.queue` / `SC.VehicleRefuel.queue`; work
uses `SC.BaseLife.retryJob`. Medical requests select a loaded, recruited,
non-expedition camp helper by native Doctor skill and call the existing
`SC.Medical.treat` path with its real runtime after checking care eligibility.
Those paths retain supplies, safety, claims, inventory and action ownership.
No extra health deduction, item creation or direct cargo mutation is added.

People reports now include native skills, wound details, bandage state and
needs. Low health without a visible wound does not imply a bandage will help.
Stock reports use the bounded, cached operations audit and disclose unfinished
audits or unloaded stores. Alarm reports explicitly describe their session
limit. Expedition reports use the existing observation/radio projection;
returned deliveries retain collected/carried/stored/pending/unknown counts,
borrowed tool debt and retry timing. Delivery output is capped at eight trips.

The UI suite adds 39 request checks: no side effects before Yes, No/new-input
cancellation, expiry, camp/access changes, exact job/car/patient identity,
departed medics, changed readiness, consumed-ticket replay, exceptions and
nested execution. Brain/world fixtures cover the new records and camp-access
barriers. Logs: `build/larchos-validation/pc-actions-ui.log` and
`pc-actions-gameplay.log` in the same directory.

Native acceptance used the disposable cloned world and a real, inert cleaning
job created through `BaseLife.enqueueJob` and paused with `blockJob`. Native
text entry produced the confirmation; No left it blocked, Yes requeued it
through `retryJob`, replay failed, and the fixture cancelled its job afterward.
This verifies real job submission, not completion of physical refuelling or
medical treatment. Medical and skill screens rendered with actual camp records
and 16 native perk readings. The fixture supplies power only for its temporary
desk; it does not test a real socket or generator connection.

Evidence: `artifacts/emma/native-acceptance/terminal-actions-evidence.log` and
the `confirmation-prompt.png`, `medical-report.png`, `skill-report.png` images.
The probe and launcher are `artifacts/emma/terminal-actions-native.lua` and
`run-terminal-actions-native.ps1`. Physical medical/refuelling outcomes remain
covered by existing domain regressions, with dedicated terminal-driven live
scenarios still pending.

## Camp logo colour correction

The header previously selected the green row of the camp atlas for every
screen. It now selects the existing green, sand or aquamarine source region;
purple uses a new transparent generated variant. Source PNG pixels remain
unchanged. Business logo colours and the computer's saved palette remain
unchanged. Provenance and exact rectangles are in
`docs/terminal-camp-logo-colours.json`; six presentation regressions cover the
four regions, purple texture bounds and business identity retention.

The cloned native run captured all four matching camp palettes in
`artifacts/emma/native-acceptance/camp-logo-{aqua,sand,purple,green}.png`.
All four were visually inspected. The complete project gate passes 29/29;
final output is `build/larchos-validation/pc-feature-project-gate.log`.

## Expanded lore and complete logo catalogue

The 2026-10-27 expansion adds 75 original owner profiles to the original ten:
85 owners, 340 distinct July 1993 entries and more than two dozen contexts.
Sixteen county and EMMA reference files are available after unlocking any
computer. They are clearly labelled archived fiction rather than current
world facts. References are grouped three per page so every visible menu
option keeps a single-digit shortcut at 720p. Opening a long file scrolls to
its heading. Existing saved archive IDs, puzzles and notes remain intact.

The branding catalogue has 210 source rectangles and 195 canonical terminal
identities: 179 named marks and 16 camp/sector emblems. Aliases remove duplicate
newspaper marks, home-ad fragments and car/reporter photos from automatic
selection. Eight new firms, four sector emblems and transparent adaptations
cover the gaps. The stock textures remain game-supplied; generated asset
references and prompts are in `docs/terminal-expanded-art-manifest.json`.

Automatic branding reads explicit object branding, unambiguous room names,
same-floor signs in the same room, and curated native advert rectangles.
Sign searches visit at most 81 squares and 512 objects. Generic offices,
mixed tenants, private rooms above shops and whole-mall adverts do not
arbitrarily acquire a firm's identity. Named firms prefer an appropriate
owner archive; newspapers use print-reporting stories. Every lookup occurs
during initialization, not per frame.

The read-only installed-map audit in
`artifacts/emma/research/terminal-coverage.json` records 40 verified advert
keys covering 41 native rectangles, with source SHA-256 fingerprints. The
3,536-desktop census contains 29 exact branded-room candidates and 195
unambiguous advert-rectangle candidates. These groups can overlap and are
not a claim that every generic office has a known company. Same-room signs
and final runtime assignment are covered separately by the fixtures.

`SCTerminalLogoRenderer` adds a scoped UI shader for flat backing removal,
dark-ink readability and paired phosphor. Normal screens retain chromatic
brand inks; purple uses matching monochrome. Outline and fill remain
distinct, including small black subtitles. Each draw restores the previous
shader in a `finally` block. Native unit checks cover failure, nesting,
foreign-thread rejection, invalid arguments and balanced push/pop state.
The packaged bridge SHA-256 is
`322fc8017dd4bfc968d63e0948280688f74fe77eedd1aa3f1778a4cdd7649c8e`.

The Kahlua lore harness validates unique records, date/text bounds, all
contexts, named archives, legacy identity retention, advert boundaries,
private-room exclusions, mixed tenants, aliases, same-room sign bounds and
malformed optional definitions. UI checks read all 16 references by number,
cross every page, verify Escape/focus and preserve owner/security state on
reopen. Existing brain, security, actions and presentation suites also pass.

The disposable 42.21.0 cloned-world run rendered all 195 identities in both
their paired palette and purple, with 11,812 successful native shader draws
in the final run.
All 26 catalogue pages were visually reviewed. It assigned the expected
dentistry archive, opened owner/reference files through native textbox
callbacks, traversed all six reference pages and retained the owner after
reopening. Four complete company screens demonstrate sand, aqua, green and
purple against the actual CRT glass. All 34 captures and the evidence log
are in `artifacts/emma/native-acceptance/` with `emma-lore-` filenames and
`terminal-lore-evidence.log`. The probe and launcher are
`artifacts/emma/terminal-lore-native.lua` and `run-terminal-lore-native.ps1`.

Presentation fixtures select brands and supply power only to their temporary
desk. They invoke native keyboard callbacks, not physical key injection.
These checks do not replace the remaining furniture, real XP or physical
medical/refuelling scenarios described above. The source save and installed
game are unchanged. Companion computer downtime remains unimplemented.

The complete project gate passes all 29 stages; current output is
`build/larchos-validation/expanded-lore-project-gate.log`.
