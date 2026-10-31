<!-- SPDX-License-Identifier: MIT -->

# 0.26.84 grid-control and companion validation

Implementation baseline: `4645246fa0822c8cc3593d2c1cefa07f7463e520`
on `living_fellows/0.26.83`, released on `living_fellows/0.26.84`,
Project Zomboid 42.21.0 single-player. The acceptance runs below began during
0.26.83 development; the unreleased work ships together as 0.26.84.
The original grid acceptance used bridge protocol `42.21-isocompanion-24`, SHA-256
`2a325b578aa70d6899a9a3b52632311ab9c48a79d377ece6ab519abdcd702487`.
The subsequent companion-care changes rebuild the bridge with half-rate awake
fatigue; the current payload uses the same protocol and SHA-256
`9733da8faa27d782cd8a679acb37df458e3fcc52b44b32f08e25e7f72be60efe`.

## 0.26.84 release verification

All release metadata now identifies 0.26.84. The complete project gate was run
again on `living_fellows/0.26.84`: **29 of 29 stages passed** in **163.1 seconds**
(166 seconds including setup). Evidence is in
`build/release-0.26.84/project-gate.txt`. Workshop and standalone packaging both
passed for 0.26.84; release synchronization and whitespace checks passed too.
The source bridge, freshly built bridge and prepared local installation payload
have the same SHA-256 shown above. The local package retains the existing
private development launcher and debug configuration.
The existing `SC_WorldV1` schema 3 is unchanged. Grid records use their own
`LF_GridControl` schema 1 bucket; unknown or malformed records are preserved.

## Automated checks

The grid-phase project gate passed **29 of 29 stages** in 162.9 seconds
(`Test-Project.ps1 -Jobs 8`, 166 seconds including setup), after the native-radio,
compact-layout and installation-ownership corrections.

- Grid state tests: **128 checks**, including all seven 40-tile boundaries,
  five-link capacity, generator-only setup, permanent machine/radio identity,
  skill bands, individual controller cracks, pause/resume and unloaded catch-up.
  The accepted assembly is pinned during setup; an externally exchanged radio
  cannot complete a link against the original radio's identity.
- Save coverage separates world task records from portable checkpoints.
  Connection displays use canonical progress after reload. A crack completed
  while its computer is unloaded releases that computer on the next contact.
- Heat and ownership tests cover exact 24/48-hour runs from cold, the 5% start
  surge, early stops, 7-to-3-day cooling, full-cold restart, bounded native
  leases, foreign changes and interrupted paired-save recovery.
- **Eight negative controls** each failed its intended assertion: idle service,
  heat rate, unlimited lease, foreign ownership, missing radio, outside-camp
  cracking, missing generator and lost progress.
- Radio tests: **37 checks**, plus **four inventory-context checks**. They cover
  equipped ownership, secondary-hand selection, TV rejection, source power and
  access, channel/range/microphone checks, native receipt identity, expiry,
  dropped devices, death, errors and idempotent event registration.
- Grid UI: **33 checks**, including current-window confirmation, cancellation,
  one-shot tickets, equipment revalidation, bounded open-page refresh, drawing
  without world queries and at most five visible local-service shortcuts.
- EMMA grid phrasing: **39 checks**. Live controller questions take precedence
  over the static guide card. Plain power, electricity, grid and fuel questions
  retain their existing supply handler.
- Live-harness static checks: **150 assertions**. Release synchronization and
  whitespace checks passed. Existing gameplay, navigation, ownership,
  persistence, Bandits and A-Life stages passed in the full gate.

## Native grid runs

All runs used separate save copies, the actual engine ambient manager
(`-EngineSound`, with only the copied sound settings muted), LF alone,
`-NoSteam` and an isolated source bridge. The production code has no test seams.
Fixture task timestamps were advanced instead of waiting three to five days.

| Run | Result | Evidence |
| --- | --- | --- |
| `SC-Harness-20261030-224416-dabde200` | 37 pass, 0 fail, 0 skip | All seven sites contain native transformer tiles. A real outdoor PC, mounted walkie-talkie, backup battery and generator passed setup. Battery-only setup was refused. The bound computer retained power after its generator stopped. Native pickup and radio removal were refused. Contact settled the crack, restored hydro power and powered 17/17 sampled switches and 1/1 fridge. The energized clone was saved. |
| `SC-Harness-20261030-224900-8c4af890` | 20 pass, 0 fail, 0 skip | A second client loaded that saved clone. The native lease, heat and hydro state agreed. Its 17 switches and one fridge retained power. Reaching the heat limit restored the original shutoff, cut native hydro and removed power from all samples. Restart while warm was refused. |
| `SC-Harness-20261030-232743-b1e1ac37` | 47 pass, 0 fail, 0 skip | Repeated all seven sites, physical setup, catch-up and breaker checks. The real equipped handset received EMMA's exact report. A 120-second closed-terminal interval left crack progress untouched; interaction then completed the task. Native power again supplied 17 switches and one fridge and cut all of them at trip. |

Native screenshots were inspected for the substation header, energized grid
page and blackout. The Knox Valley Power mark uses the terminal's own colour;
text, bars and controls stayed within the CRT screen. Raw logs, saves and
screenshots remain ignored build artifacts.

## Idle cost and radio acceptance

With the grid off, 1,000 `GridControl.pulse()` calls made **zero clock, sandbox,
power or grid-square reads**, and did no cracking work. Unrelated radio traffic
and expired requests likewise perform no grid queries. Only an energized grid
uses the existing one-second callback for its breaker timer. Cooling and
controller work settle on interaction; there is no closed-computer survey.

The final run's 120-second interval collected **119 samples**. The computer was
closed; the companion panel and vanilla handheld-radio window remained open,
as visible in the final capture. The initial event label overstated this as all
menus closed and has been corrected. Grid-only idle
callback p95 was **0.001900 ms**, with **0.002200 ms maximum**. The entire existing
computer-services callback, including mounted radio receivers, measured
**0.502900 ms p95 / 0.700400 ms maximum**. This is not a zero-cost claim for the
radio service. The 0.26.81 ordinary-camp sample was 0.585 ms p95, but its crew
activity differs, so these runs do not establish an overall FPS improvement.

The first added native radio attempt (`SC-Harness-20261030-232036-f0225da8`)
failed receipt validation and exposed a layout omission. The native equipped
radio reports sentinel coordinates `-1/-1`; the correction accepts those only
with the exact expected receiving device, retaining source-coordinate checks
for the six-argument fallback. The page now prioritizes crack progress and
restart wait over optional text. Dedicated regressions and the final native
run cover both corrections.

## Limits and retained behaviour

The player selected **last-known-power catch-up**. An unloaded generator's exact
fuel-exhaustion time is not reconstructed. A newly observed outage pauses
further progress, completed progress stays saved, and moving/removing the source
explicitly pauses it. The duration is fixed at crack start using the player or
the best living resident of the active camp.

Native shutoff changes also influence unloaded fridge ageing, so food first
loaded during a restored-power window can be fresher. This is the retained
engine behaviour, not an item recreation or a separate refrigeration system.
Other programs' power-setting changes cause LF to stand down. Worlds configured
never to lose electricity retain that setting and hide grid control.

Natural multi-day fuel history, zombie reactions to generator noise/burglar
alarms, and a companion actively cooking across the breaker boundary have not
had dedicated live acceptance. The grid probes quiet nearby zombies and suspend
ordinary decision scheduling to isolate the power checks. They do not establish
an overall camp FPS improvement or replace ordinary combat/cooking acceptance.

The original 3,430-file source save matched its pre-run hashes. No installed mod,
real save, user sound option or Workshop
publication was changed by these checks. The local Field Guide source has the
new LARCH/GRID instructions; publishing remains separate.

## Companion care follow-up, 31 October

The supplied 0.26.82 support report shows the following companion's current
decision ending in `vehicle_transaction_rejected:retry_exhausted`, with four
boarding failures. That confirms the permanent retry stop. The report does not
retain the underlying reasons for those four failures, so it does not establish
whether the original obstruction was a door, route or seat. Failure diagnostics
now include the reason for future reports.

Boarding keeps its four-attempt budget, then permits another group after a
three-minute real-time pause. A new Follow command or moving and parking the
same car at least two tiles away also permits a fresh attempt. Resets apply only
to that actor's boarding target. Existing ownership, rollback, stationary-car,
seat and native passenger-door checks still run. While waiting, Follow holds
beside the car rather than reporting failure and falling through to scavenging.

Core regressions reproduce exhaustion, the pause boundary, a new command, a
changed parking position and reservation cleanup. The real Follow controller
fixture checks the command serial, waiting behaviour, native-range approach,
inside-seat entry and exit. These are automated fixtures; this follow-up did
not load the tester's firehouse save or run a new live vehicle scene.

Natural awake fatigue gain is multiplied by 0.5 in the native bridge. Its
15-check test covers traits, endurance, sandbox/day/speed multipliers, sitting,
pause, sleep, death and retaining native fatigue reductions. Sleep recovery and
saved fatigue are unchanged. The updated bridge must ship with these Lua files.

Water handling uses fluid contents and refill compatibility for portable
containers up to three litres, including modded vessels without bottle names.
Poisoned, tainted, incompatible and bulk-hauling containers retain their safety
rules. Drinking and water gear compare the empty shell's weight, using the
verified 42.21 script-item weight methods. Restocking also considers current
water content, and surplus shedding prefers empty vessels before safe water.
Base sorting uses the same classification. The new gameplay fixture checks
generic filled/empty vessels, unsafe contents, bulk containers, light-shell
selection, shelving and potable-water priority.

The current Java/Lua build retains protocol `42.21-isocompanion-24`. No save
schema or installed local copy was changed by this follow-up.
The completed follow-up gate passed **29 of 29 stages** in **165.7 seconds**
(168 seconds including setup), including the new water and boarding fixtures,
the native fatigue checks, existing persistence/combat regressions and both
distribution packages. `git diff --check` and release synchronization passed.

## Companion weapon selection hardening

Automatic selection now distinguishes recoverable firearms from firearms ready
to fire. A ready gun in range wins over a stronger gun needing a reload or rack;
at contact range or under crowd pressure, a ready melee backup wins over firearm
preparation. An exact player-selected weapon remains authoritative while usable.
Condition, relevant weapon skill, stamina and fatigue affect comparison, with a
small preference for the held weapon to avoid insignificant swaps.

Reload viability requires an actual compatible magazine for magazine-fed guns,
or an installed magazine plus compatible loose rounds. Qualified item types do
not accept matching names from other modules. Empty jams are not ammunition,
and the final chambered round remains usable. An empty chamber with magazine
rounds requests the existing native rack action. Inventory ownership is checked
by identity, including nested bags and cached references, before selection and
equipment; foreign hand pointers and stale ammunition entries are rejected.

Changing weapon priority invalidates the previous manual choice. A persisted
generation also invalidates old pins outside the bounded inventory scan; legacy
pins start at generation zero. Capture and actor reconstruction explicitly
preserve that generation alongside weapon priority; inventory receipts preserve
each item's pin. Group orders change equipment only after every
member commits, retaining the existing rollback behaviour. Followers check for
a better carried weapon at most every 1.5 seconds, without replacing usable
base-work tools or preempting a supervised action just to upgrade. No world
survey or new per-frame service was added. Ordinary weapon scavenging and
surplus decisions account for operational weapons rather than raw item counts.
Explicit expedition weapon requests retain their unloaded-weapon allowance.

The gameplay suite includes new weapon-selection regressions for magazines,
module-qualified ammunition, live ammo removal, chamber state, wear, stamina,
skills, manual orders, off-scan pins, group commit/rollback, cache reuse and
invalidation, idle readiness and retaining a usable surplus backup. The
character-depth persistence checks also reconstruct an actor with an active pin
and an older invalid pin, retaining their distinct generations. The
human-combat fixtures were corrected to give their held weapons real inventory
ownership. The former empty-jam regression now uses a loaded jam at a safe
distance; new cases verify empty-jam and close-range fallback behaviour.

These are automated Kahlua gameplay checks against the pinned 42.21 runtime,
not a new live-world combat acceptance run. This pass makes no further native
bridge, protocol, save schema, local installation or user-save changes.

The final full project gate passed **29 of 29 stages** in **166.2 seconds**
(169 seconds including setup), including both adapter suites, gameplay,
character-depth persistence and both packages. Evidence is recorded in
`build/weapon-hardening/project-gate-final.txt`. `git diff --check` and release
synchronization also passed. The companion-care bridge payload remains
`9733da8faa27d782cd8a679acb37df458e3fcc52b44b32f08e25e7f72be60efe`.
