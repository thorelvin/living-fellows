<!-- SPDX-License-Identifier: MIT -->

# Bandits2 adapter validation — 25 October 2026

Candidate based on `living_fellows/0.26.68`, baseline `125b9adf`.
Included in `living_fellows/0.26.69`; final release-build checks are recorded in
[validation-0.26.69.md](validation-0.26.69.md). Historical live bridge hashes below
identify the tested builds and are retained unchanged.
Target: Project Zomboid **42.21.0 single-player**, official Workshop item
**3268487204**, mod ID **Bandits2**, selected **42.21** payload, Workshop
manifest **5253675913699781222**. This records compatibility evidence, not
approval of every scenario in the original acceptance matrix.

## Inspected dependency

SHA-256 fingerprints are relative to `42.21/media/lua`:

| File | SHA-256 |
| --- | --- |
| `shared/BanditUtils.lua` | `AB2908394B3EE9BEA198754085090FB5F818EEFB16D902DF83F084C9F047E894` |
| `client/BanditPlayer.lua` | `98F59643B2532CC310E565ABE9529075805E4C0FD382F28B47B6B2886C3D4C1F` |
| `client/BanditUpdate.lua` | `7C202DC0CBBCB2C4251A277B87FE1A3B454CA69021B7D9A9B0E0FFC032242287` |
| `shared/PlayerDamageModel.lua` | `C8811516BCF9E62908D22A40230CD5D569AE96E1B71D5D4948EBA9C93B768108` |
| `server/BanditServerCommands.lua` | `379C0E06DC4A9941509BDA8CDF445A1F3FE2BB8CEFBA9646CCB091F9A88F7C51` |

Bandits' single-player identity function returns `1` for every `IsoPlayer`,
including LF's native subclass. The adapter corrects this within Bandits'
interfaces. It does not register LF as real players. The installed dependency
is read directly for source-contract tests and copied unchanged to disposable
live sandboxes; no third-party source is added to this repository.

## Automated checks

- Adapter harness: **57 checks** covering unique and stale aliases, native-list
  isolation, owned secondary-slot deduplication, fresh native list wrappers,
  cache invalidation, ownership markers, incomplete brains, reanimation,
  Off/absent/unsupported states, late dependency availability, idempotence,
  teardown and another mod replacing a hook.
- Damage isolation: nested callbacks, unrelated commands, post-commit errors,
  application-time immunity and despawn. No replay or duplicate health loss.
- Installed-source contract: **131 checks** execute the original Bandits
  identity, player lookup, three damage models and server wound handler under
  game-bundled Kahlua. Seeded armored/unarmored controls match body-part wounds,
  blood, clothing holes and health exactly. These are source fixtures, not
  rendered combat, animation, vehicle-window or infection acceptance.
- Production perception tests cover hostile human observations, protected
  neutral firing lanes, stale hostility and zombie-steering exclusion alongside
  existing A-Life regressions. Household last-seen pursuit and retreat doctrine
  have explicit behavior checks.
- Full project gate: **28/28 passed** on the final production candidate
  (114 seconds including the runtime/build prologue). Existing combat,
  perception, ownership, persistence, UI, field-work and packaging suites pass.
  Both normal and debug payloads compile: **214 Lua files**. Later changes to
  the reload-only diagnostic are checked by the live harness suite separately.

Reproduce the source checks:

```powershell
./tests/gameplay/run_bandits_adapter_tests.ps1 -RequireBanditsSource
./scripts/Test-Project.ps1
```

When the optional dependency is unavailable, the project gate explicitly skips
the installed-source portion; the independent adapter tests still run.

## Historical initial live evidence

All runs use disposable clones of `Rising/2026-10-16_23-11-25` with ordinary
zombies retained. Only LF, the harness and an unchanged private Bandits copy
are enabled. The normal preset and original save remain input only. Candidate
bridge SHA-256: `90C8A0DFFD0179C5ACB403258D43C9BE8DEA182B1783C8584EA9EF22B86DDACC`.
Protocol `42.21-isocompanion-24`; no native adapter changes.

The encounter fixture requests one stock armed clan member through Bandits'
own spawner, sets its initial facing, invokes one explicit stock bare-hand
wound transaction and a confirmed-aggression notification, then observes
ordinary AI. The controlled wound is excluded from natural incoming counts.
There is no zombie clearing, resurrection, healing or scripted hit outcome.

| Run | Evidence | Result |
| --- | --- | --- |
| `SC-Harness-20261025-164509-72aab32a` | Saved camp companion; one outgoing LF hit and one natural incoming stock wound callback. Primary identity and native player membership unchanged. | Pass, 17 checks |
| `SC-Harness-20261025-165939-aa14b59d` | Independent, unrecruited household member created through the faction service; one outgoing LF hit and two natural incoming melee callbacks. Exact LF wound routing; primary unaffected by that controlled callback. | Pass, 19 checks |
| `SC-Harness-20261025-170120-30e15982` | Corey Biggs created through the authored Strange Folk service; identity, neutral classification, stock wound routing and retaliation pass. Natural incoming attack was not observed within three minutes; the Bandit remained in movement near a fence. | Combat acceptance failed; no two-way pass claimed |
| `SC-Harness-20261025-171223-9852f9a5` | Corey scene repeated with a verified open approach. 41 LF hit events against the Bandit and one natural incoming melee callback against LF. Corey's controlled native wound callback targets his exact actor. Player identity and native membership unchanged. | Pass, 19 checks |
| `SC-Harness-20261025-171013-a9f4ee4c` | Native cohorts of 1, 4 and 16 LF actors alongside one active stock Bandit, comparing targeting-list queries with the adapter removed and restored. Native player slots unchanged. | Pass, 15 checks |
| `SC-Harness-20261025-171828-2e0ce2f5` | Reload of the first Corey scene rejected its synthetic `witness` site; the save schema requires `roamer`. This was a test-fixture error, not alias migration. | Fail; fixture corrected |
| `SC-Harness-20261025-172330-4ecabd0e` | New native Corey scene with a valid `roamer` site and one neutral stock Bandit; ordinary game save on exit. | Pass, 16 checks |
| `SC-Harness-20261025-172456-2d0494b6` | Reload of that Bandits-enabled clone. Corey's previous UUID resolves through the reconstructed LF alias; the native Bandit retains foreign ownership. Main identity and native slots unchanged. | Pass, 11 checks |

The hit observer counts all LF attackers against the spawned Bandit; natural
incoming counts cover the LF crew. These counters do not establish that the
selected character personally delivered or received every natural attack.

The performance fixture replaces only the cloned LF roster through the actor
ownership service and constructs real native actors. It retains ordinary
zombies and runs the neutral stock Bandit's AI. Each sample has a one-second
settling interval and three seconds of 200 list queries per frame:

| Native LF actors | Queries without / with | Total query time without / with | Mean frame interval without / with |
| --- | --- | --- | --- |
| 1 | 36,000 / 36,200 | 18 / 91 ms | 16.659 / 16.672 ms |
| 4 | 36,200 / 36,000 | 12 / 104 ms | 16.650 / 16.654 ms |
| 16 | 36,400 / 36,200 | 16 / 105 ms | 16.652 / 16.672 ms |

This is a controlled query benchmark, not a large-battle frame-time guarantee.
An earlier performance fixture started before the saved roster finished
restoring and correctly failed its population check; the final fixture allows
a settling interval before constructing and validating its cohorts.

Logs, summaries, private payloads and screenshots are retained locally under
`build/live-sandbox-runs/<run>/cache`. Screenshots give visual context; native
events establish hit and wound delivery. Earlier unsuccessful harness
iterations are retained too. They exposed native ArrayList wrapper behavior,
Kahlua's missing `next`, delayed overall-health updates and an upstream
individual-spawner issue; none are counted as acceptance passes.

After the runs, the original save's `players.db`, `vehicles.db`,
`global_mod_data.bin` and the user's `latestSave.ini` still match their recorded
SHA-256 hashes. Bandits remains absent from the normal enabled preset and the
original save's mod list. The installed dependency's critical fingerprints
match the inspected files. All isolated game clients exited.

Reproduce encounters with `-BanditsLFRole saved`, `household` or `strange_folk`:

```powershell
./scripts/Invoke-LiveSandboxTests.ps1 -BanditsAdapterProbe -BanditsLFRole household `
  -LivingFellowsOnly -NoSteam -IsolatedSourceBridge -TimeoutSeconds 360
```

## Adapter hardening follow-up

The follow-up adds **58 adversarial regression checks**, alongside the existing
57 adapter checks and 131 installed-source checks. A pre-fix run reproduced
the ownership crash on invalid input. The hardening suite covers:

- Late-loaded identity and damage interfaces, automatic bounded retries,
  replaced module tables and hooks, and stopping retries after reset.
- Wrappers retained by another mod across reset, weak identity tombstones for
  retired actors, and releasing victim/shooter references from inactive command
  closures. Nested or retained command chains keep their original behavior.
- Reset and reinitialization during damage, handler loss, post-commit errors
  after teardown, exact victim/model receipts, immunity and expired contacts.
- Invalid lists, throwing list getters, partial brain/task state, opaque Java
  userdata, malformed witness rows and non-finite or invalid wound numbers.
- Failure of optional retaliation after the original callback completed.
  Its original return values survive, the integration stops, and it never
  repeats the completed hit.

The production behavior regression also verifies that a stale Bandits contact
cannot trigger retreat after hostility ends. Valid damage calculations still
match the installed dependency's original functions exactly. The native bridge
and save schemas are unchanged.
Additional production checks exercise actual neutral bystanders in both ranged
and melee human-combat lanes. This uncovered a missing snapshot argument in the
human attack path; the lane check now receives its protected actors. Party
protection also reads the registry's record snapshot, fixing an iteration that
mistook the `living()` actor array for records.

The final hardening candidate passes **all 28 project gate stages** (89 seconds
including the runtime/build prologue), with all 246 focused Bandits assertions
included. Evidence: `build/bandits-adapter-tests/hardening-project-gate-final.log`.

The repeated native benchmark `SC-Harness-20261025-183246-c05d32bb` passes all
15 checks on the hardened candidate. Query costs increased with the protected
interface checks, while measured mean frame intervals remained near 16.7 ms:

| Native LF actors | Queries without / with | Query time without / with | Mean frame interval without / with |
| --- | --- | --- | --- |
| 1 | 36,200 / 36,200 | 19 / 208 ms | 16.644 / 16.689 ms |
| 4 | 36,000 / 36,200 | 21 / 207 ms | 16.704 / 16.683 ms |
| 16 | 36,400 / 36,200 | 13 / 218 ms | 16.619 / 16.661 ms |

The same controlled-workload limits apply; these numbers do not establish
large-battle performance or a frame-rate guarantee. The watchdog remains stopped
between the fixture's explicit reset and reinitialization, so the samples
without the adapter actually run without its wrappers.

Fresh household encounters provide these separate observations:

| Run | Outcome | Interpretation |
| --- | --- | --- |
| `SC-Harness-20261025-182009-3d6256cc` | Stock Bandit landed multiple natural melee callbacks and killed the household member; zero outgoing LF hits. Controlled exact-victim wound routing and retaliation passed. | Failed the two-way-in-one-fight criterion; incoming combat and LF death were observed. |
| `SC-Harness-20261025-182511-081ddebd` | Household scene produced seven LF hits and killed the Bandit before a natural incoming wound. Traces showed hostile relation, knife attacks and normal attack execution. | Failed the same two-way criterion; outgoing combat and Bandits death were observed. |
| `SC-Harness-20261025-183655-e1e4661d` | Saved camp companion scene produced 12 LF hits and killed the Bandit before a natural incoming wound; controlled exact-victim wound routing and retaliation passed. | Failed the two-way criterion; saved-crew outgoing combat observed. |

Neither run is relabeled as a two-way pass. The directions were observed in
separate fights, without healing, forced hits or altered loadouts. The second
run uses the protected/cached native method lookup introduced during hardening.

## Rendered firearm investigation and further hardening

The daylight fixture now uses a fresh native LF actor, a normal Police or
Veteran background, an actual pistol and magazines, and two unchanged Officers
profiles. It uses production orders and equipment selection. No aiming skill,
health, accuracy, damage or Bandits attack timers are overridden.

Initial scenes exposed a broader LF firearm problem: normal zombies were also
missed. Read-only bridge diagnostics at `OnWeaponSwingHitPoint` showed that
42.21 filled the non-local actor's ballistic cursor point from a human player's
reticle. Native firearm filtering also consumes shared `CombatManager` muzzle
scratch vectors, which can belong to a different character's aiming pass.

The candidate now supplies the companion's selected target as input to its own
Java and Bullet reticles during the stock shot callback. It asks the native
muzzle calculation to refresh the shared ray for that shot. Both contexts are
restored in `finally`; player slots, mouse input, target lists, hit rolls and
wound amounts are not assigned by the bridge. Changing the Java point alone
did not restore gun hits. Native physics input was also necessary in the
rendered comparison. The adapter itself remains Lua; this prerequisite ships
with the rebuilt LF bridge, protocol `42.21-isocompanion-24` unchanged.

| Run | Result |
| --- | --- |
| `SC-Harness-20261025-191207-ec611231` | Natural stock Bandits bullet wounds reached the exact LF alias. LF fired 11 rounds without a verified hit. Full case failed. |
| `SC-Harness-20261025-191738-16e016fd` | Normal Police background, Aiming 4; 15 LF rounds without a hit. Natural incoming bullet wounds observed. Full case failed. |
| `SC-Harness-20261025-192912-bec1ebf3` | Ordinary-zombie control also failed to land firearm hits. This isolated the outgoing problem from human classification. |
| `SC-Harness-20261025-194305-8c665702` | Fixture error: it called a protected hand-model method through Lua. Corrected to the bridge's native readiness diagnostic; no combat result claimed. |
| `SC-Harness-20261025-194934-40367172` | Corrected readiness; 15 LF rounds, zero outgoing hits; natural incoming stock bullet wounds. Failed. |
| `SC-Harness-20261025-195420-2e954267` | Original ordinary-zombie aim control failed; shot-time muzzle/cursor geometry retained. |
| `SC-Harness-20261025-200020-27c4be1e` | Java cursor correction alone failed the ordinary-zombie control. |
| `SC-Harness-20261025-200636-60b4d16e` | Shared-ray refresh without Bullet cursor input still failed the firearms predicate. Later melee damage is not counted as firearm evidence. |
| `SC-Harness-20261025-201113-518b81e4` | With Java/Bullet input and native-ray scoping: nine exact-actor `Base.Pistol` hit events, real ammunition consumption and Bandits health loss. Both Officers died before shooting. Full two-way case still failed. |
| `SC-Harness-20261025-201536-4143674a` | Passed natural two-way firearms with Bandits loaded before LF. Normal Veteran background (Aiming 2), four LF pistol hit events, 13 LF rounds and three Bandits rounds; stock bullet wounds reached the exact LF alias. No controlled damage callbacks. Main player, count and slot values stayed unchanged. |
| `SC-Harness-20261025-202147-5b73b10b` | Current cleanup-guarded bridge: seven confirmed LF pistol hits, nine rounds, both Officers killed before incoming fire. Full same-fight case failed. |
| `SC-Harness-20261025-202532-fe5b1517` | Current bridge against four stock Officers: nine LF rounds without a verified hit; 27 Bandits rounds and native bullet wounds killed LF. Full case failed. Formation selection now also checks flank edges, rather than only free flank squares. |
| `SC-Harness-20261025-204025-100cda98` | Flank-edge-checked four-Officer scene on `4FD1F5A2…`: 12 LF pistol hits, 15 LF rounds and one Bandits round; no native incoming LF wound. Full same-fight case failed. |

Those two runs used bridge SHA-256
`E9C54A90F545B3DF0116068940EF8898932260DC6306032CB8623AB4CEEFCD48`.
The original installed bridge and Bandits payload were not changed.
Further cleanup hardening rejects a reticle scope after its controller is
released, so a pooled controller's new owner cannot be overwritten. A real-JAR
regression covers that transition. Current bridge SHA-256:
`4FD1F5A2BE11EEF6DEF345DEB506ACB5997E8C9FFD91E10C4A3269F97CFD02DE`.

Further adapter checks reject a natively removed LF actor even if its registry,
square and positive health have not yet been cleared. Its weak alias remains
reserved, but lookup, target publication and wounds are refused. The focused
suite now passes **260 checks**: 57 adapter, 72 hardening and 131 original-source
assertions. The live-verdict harness has 12 adversarial traces, including wrong
victims, stale model counters, missing health loss and changed native slots.
Player snapshots copy slot values, rather than retaining the mutable engine
array. The fixture also refuses to continue after observer death and retires
pooled target objects instead of following a reused zombie reference.

A further negative control reproduced a stale alias becoming the main player
through a foreign fallback lookup retained after reset. Retired lookup wrappers
now reserve the LF prefix and return nothing. Retired damage wrappers refuse
standalone LF calls, but can delegate inside a fresh synchronous scope for the
same victim/model, lifetime and permission. This keeps legitimate foreign
wrapper chains working after reinitialization without sending an unrouted LF
wound. Real-player calls retain their original return values. Both reproduced
failures and their passing controls are retained under
`build/bandits-adapter-tests/retained-*-negative-control.log` and
`retained-alias-hardening.log`.

Real-JAR controls reproduce native cursor/range rejection and verify nested
restoration of the scoped reticle and shared muzzle values. All **83 core
harnesses** pass. The full **28-stage project gate** passes on the rebuilt
candidate (115 seconds after retained-hook hardening):
`build/bandits-adapter-tests/adapter-hardening-final-project-gate.log`.
Rendered scenario coverage remains tracked in
[the acceptance ledger](bandits-live-acceptance.md); this gate does not close
its remaining live cases.

The final native query benchmark `SC-Harness-20261025-203534-1e38b029` passes
all 15 checks with the 260-check adapter and cleanup-guarded bridge. One stock
Bandit runs alongside real LF cohorts, and normal player slots stay unchanged.

| Native LF actors | Queries without / with | Query time without / with | Mean frame interval without / with |
| --- | --- | --- | --- |
| 1 | 36,200 / 36,200 | 37 / 421 ms | 16.650 / 16.661 ms |
| 4 | 36,200 / 35,800 | 36 / 427 ms | 16.639 / 16.775 ms |
| 16 | 23,200 / 23,000 | 12 / 279 ms | 26.200 / 26.439 ms |

This is a controlled query workload, not a battle or FPS guarantee. The
16-actor scene is slower in both modes; fewer frames also mean fewer query
batches. The measured enabled/disabled frame differences are approximately
0.011, 0.136 and 0.239 ms respectively. This does not waive mixed-threat or
expedition acceptance. After the runs, all four original-save baseline hashes
and the five dependency source fingerprints still match; the normal preset
and original save continue to exclude Bandits2.

## Ordinary LF firearm verification without Bandits

An explicit `-CompanionFirearmsProbe` runs the same production actor, orders,
equipment selection and ordinary-zombie scene with **Bandits2 absent**. The
run manifest and runtime both verify absence; it does not define substitute
Bandits interfaces. The comparison uses fresh clones of the same input save,
normal Police background (native Aiming 4), real pistols/magazines and normal
zombies. Skills, accuracy, damage and health are not overridden.

| Run | Bridge | Observed native pistol results |
| --- | --- | --- |
| `SC-Harness-20261025-204949-194922fd` | Original `90C8A0DF…` | 0 hits from 28 rounds over 30 seconds; no native hit candidates. Expected failing baseline. |
| `SC-Harness-20261025-205253-f82c2421` | Scoped aim `4FD1F5A2…` | 2 exact-actor pistol hit events from 17 rounds over about 20 seconds. Functional improvement, but many moving-target misses remained. |
| `SC-Harness-20261025-210023-11f8d379` | Chest aim `82AC1A73…` | 7 exact-actor pistol hit events from 8 rounds; both original test zombies dead after about five seconds. LF remained alive and native player slots/identity stayed unchanged. |
| `SC-Harness-20261025-210700-c0a4ec84` | Same chest-aim bridge, normal Unemployed background | Native Aiming **0**, with no skill overrides: 4 exact-actor pistol hit events from 5 rounds; both test zombies dead after about three seconds. LF remained alive; main-player identity/slots unchanged. |
| `SC-Harness-20261026-012111-effa470c` | Same chest-aim bridge, normal Unemployed background, four ordinary zombies | Native Aiming **0**: 5 exact-actor pistol hit events from 16 rounds over 30 seconds. All five matched completed native impact receipts (serials 9, 10, 12, 13 and 14). LF survived; native player identity/slots/count stayed unchanged. |

The physical Bullet ray now aims at a standing character's native chest
height (`getAimOriginPosZ`); the Java broad-phase cursor remains at its floor
coordinate. Prone targets retain low physical aim. Previously the Bullet
camera ray pointed at the floor between walking targets' feet. A real-JAR
control checks both standing and prone heights and still verifies scoped
restoration and released-controller protection. All 83 core harnesses pass.
The firearm verdict harness now has 15 adversarial traces, including execution
with every Bandits interface absent and refusal to credit spent ammo alone.
The rebuilt candidate passes all **28 project gate stages** (114 seconds):
`build/bandits-adapter-tests/regular-lf-firearms-project-gate.log`.

These are individual rendered observations, not an average accuracy estimate:
the fresh actors and normal zombie movement involve game randomness. Death
counts describe the test targets; the exact-actor pistol events are the direct
shooting evidence. No damage model was invoked by the fixture. The normal
preset, original save and installed game bridge remain unchanged.

The four-zombie repeat confirms functioning ordinary LF shooting under a
larger threat load, rather than establishing a typical accuracy percentage.
Two tracked zombies died, but only one had this LF's firearm-hit evidence;
other camp defenders joined the fight, so the second death is not credited to
the tested shooter. The observer was wounded during the scene. The final
screenshot was inspected, and the runtime and manifest both confirm Bandits
was absent. This is a firearm check, not a claim of successful base defense.
After this repeat, all **28 project gate stages** passed again (121 seconds):
`build/bandits-adapter-tests/regular-lf-final-verification-project-gate.log`.
All four original-save hashes still match their baseline; the installed bridge
remains `D7AC97D3…`, while these results use the isolated `82AC1A73…` candidate.

Reproduce the ordinary LF scene:

```powershell
./scripts/Invoke-LiveSandboxTests.ps1 -CompanionFirearmsProbe `
  -BanditsLFProfession policeofficer -LivingFellowsOnly -NoSteam `
  -IsolatedSourceBridge -TimeoutSeconds 420
```

For the four-zombie novice repeat, use `-BanditsLFProfession unemployed` and
`-BanditsCombatants 4` with the same remaining flags.

Current chest-aim bridge SHA-256:
`82AC1A73D3E0756209E380274184B1F69082584F475F8882CF06A1DD34A8D18B`.
It requires repeating the remaining Bandits combat acceptance on that build.

## Close-combat scenes on the chest-aim build

Dedicated melee, unarmed and infected scenes use ordinary actors and stock
Bandits clans. Exact native Smack/Push callbacks are observed through a
temporary read-only wrapper: it calls the original once, preserves sparse
returns and propagates errors without replay. Thirty-two adversarial observer
checks cover exact victims/models, real bitten-part changes, actual shove
reactions, unexpected damage, main-player leakage and teardown. These checks
verify the recorder; rendered clients supply the combat evidence.

Scene weapons are actual items. Prior weapons are dropped transactionally
with their native identities preserved, rather than deleted. The melee scene
uses a real Rolling Pin; unarmed/bite scenes use empty hands. Actors keep
their normal stats and health. Stock profiles, attack decisions, timing and
damage remain unchanged. The ordinary zombie population is retained.

| Run | Evidence and verdict |
| --- | --- |
| `SC-Harness-20261025-211511-95da8848` | Four-Officer firearm scene with normal Close Defense orders on `82AC1A73…`: LF fired four rounds without a confirmed hit; 23 Bandits rounds and exact-victim wounds killed LF. Full same-fight verdict failed. |
| `SC-Harness-20261025-212313-ce892b49` | **Passed recruited LF two-way melee on `82AC1A73…`.** Two exact-actor Rolling Pin hit events caused Bandits health loss. A naturally invoked stock Smack/MeleeHit wounded `lf:sc-1.792959889351E9-1-352545`, reducing body-part health from 1700 to 1680.4227. Main health stayed unchanged during that callback. LF survived; native player identity/slots/count unchanged. No damage callback was invoked by the fixture. |
| `SC-Harness-20261025-212644-77092d32` | Unarmed fixture requested four Karate profiles, but the original spawner draws each profile once and that clan has only two. Setup failed; no combat pass claimed. The fixture now honors that stock profile limit and records requested/actual counts. |
| `SC-Harness-20261025-213115-13d28644` | Two stock Karate Bandits: 23 LF shoves produced actual native reactions without added health loss; 17 stock BareHandHit wounds reached the exact LF actor. The Bandits never chose their Push action before LF died. Full unarmed verdict failed; incoming shove remains open. Primary identity/slots/count and callback damage isolation passed. |
| `SC-Harness-20261025-213821-614667ff` | Four stock Cannibals, three with native Infected expertise: seven stock melee wounds reached LF before death; no bite was chosen at normal weapon spacing. Both the ordinary-zombie and hostile-human perception lanes were observed, with no Bandits entering undead threats. Full bite verdict failed. The next fixture stages initial contact inside the stock bite/shove distance thresholds before hostility; subsequent decisions remain native. |
| `SC-Harness-20261025-214033-a044296c` | Lifecycle fixture stopped before its assertions because it addressed the command name as a global table. The actual binding is `sendClientCommand`; the fixture now snapshots that function. No lifecycle pass claimed. |
| `SC-Harness-20261025-214237-67e7e6f5` | **Passed native infected bite and mixed threat lanes on `82AC1A73…`.** Four unchanged Cannibals had native Infected expertise. A naturally chosen stock Smack/Bite against `lf:sc-1.792961054119E9-1-465902` changed the bitten-part count from zero to one; its health stayed unchanged during that exact bite callback. Two preceding native melee wounds also reached LF. Both ordinary-zombie and hostile-human perception lanes were observed, with no Bandits in undead threats. LF survived; primary identity/slots/count unchanged. Initial close spacing was staged once before hostility; no attack tasks or damage callbacks were invoked by the fixture. |
| `SC-Harness-20261025-214508-abab75da` | Native-client alias, repeated initialization, actual Mods Off/on, missing-interface diagnostic/recovery, retired lookup, reset/reinitialize and main-player/command isolation checks passed with Bandits loaded first. The despawn fixture failed because `removeFromWorld()` alone retains native square membership; it now performs the normal paired world/square removal before testing the alias guard. Full lifecycle verdict failed. |
| `SC-Harness-20261025-214800-57ec8485` | **Passed native unarmed/shove exchange on `82AC1A73…`.** Two unchanged Karate Bandits started at a verified 0.3999-tile contact distance. Stock Push produced LF stagger with body-part health 1700 before and after. Two stock BareHandHit wounds reached `lf:sc-1.79296137756E9-1-799640`. LF's native BareHands shove caused an actual target reaction without health loss. LF survived; main-player damage isolation and native identity/slots/count passed. Only initial placement was staged; the original AIs chose all actions. |
| `SC-Harness-20261025-215008-3eee9ed6` | Normal Police LF (native Aiming 4) landed five exact-actor pistol hits from seven rounds and killed both stock Officers. They fired zero rounds, so the full two-way firearm verdict failed. LF survived and native player identity/slots stayed unchanged. This confirms outgoing fire on the current bridge, not a reciprocal exchange. |
| `SC-Harness-20261025-215332-8c120f02` | **Passed native-client lifecycle sequence on the current adapter/bridge, Bandits loaded first.** A fresh real LF actor resolved exactly once. Three repeated initializations kept the same wrappers. The real Mods Off/on option removed/restored LF targeting. A temporarily unavailable required command produced the readable Support diagnostic and recovered after restoration. Reset/reinitialization left retired lookups inert. Paired native world/square removal rejected the alias before registry cleanup; normal removal retained that rejection. Main-player identity/slots/count and `sendClientCommand` stayed unchanged. No damage callback was invoked. |
| `SC-Harness-20261025-215549-34ad93fd` | **Passed natural two-way firearms on `82AC1A73…`.** Normal Police LF (Aiming 4) landed two exact-actor pistol hits from six rounds. Stock Officers fired three rounds; the original Shoot callback wounded `lf:sc-1.792961845615E9-1-475737`, reducing body-part health from 1700 to 1656.3025 with one matching BulletHit request. The recorder invokes the original once and requires the health change inside that exact callback, rejecting unrelated wounds or stale counters. Thirteen adversarial recorder checks cover those cases, sparse returns, errors and retained hooks. Primary identity/slots/count remained unchanged. No controlled damage callbacks were invoked. Bandits' startup volume-report dialog obscures the center of the retained screenshot; the native hit/wound logs provide the direct combat evidence. Later visual scenes dismiss only that known report through its normal dialog callback, retaining sound settings. |
| `SC-Harness-20261025-215757-41621906` | Resident scene stopped before equipment or combat because the first loaded resident had no open eight-tile approach at its current position. The fixture now tries the other existing loaded residents before failing; no resident combat pass claimed. |
| `SC-Harness-20261025-220045-a52ea492` | **Passed strengthened native infected acceptance on `82AC1A73…`.** One stock Bite created a new bitten body part on `lf:sc-1.79296214138E9-1-394193`. Both production threat lanes were observed. All Bandits returned `ZombieFacts.zombie=false`, the gate used before zombie engagement/bite assistance, and remained absent from undead threats. Four native Bandits Push reactions preserved LF health during each callback; three native melee wounds reached LF. LF survived and main identity/slots/count stayed unchanged. Initial sub-tile contact placement was staged once before hostility; no attack task or damage callback was forced. |
| `SC-Harness-20261025-220256-760995f7` | All existing residents lacked an open eight-tile line at their current positions, so the repeat stopped before combat. That geometry was stricter than this close-combat scene needs. The fixture now verifies a five-tile combat corridor and finds the observer a separate nearby clear tile; residents remain at their existing positions. The known Bandits startup report was dismissed through its own normal dialog callback, with sound settings unchanged. |
| `SC-Harness-20261025-220641-6cc6cd31` | No resident had the five-tile straight corridor either; no combat pass claimed. The fixture now uses a bounded search within three tiles for two clear staging squares connected by open, traversable edges, plus a separate nearby observer tile. Existing residents are not moved or healed. |
| `SC-Harness-20261025-221047-a5f09e44` | The bounded local scene successfully staged two stock Bandits near an existing resident. The selected resident produced no hit/wound exchange before one target retired. The recorder then incorrectly continued classifying that retired native shell, which can be pooled as an ordinary zombie. The observer now excludes retired targets from encounter classification and incoming evidence, with adversarial checks. Resident combat remains unverified; later traces include selected orders/positions and each live target's visibility, marker and distance. |
| `SC-Harness-20261025-221930-57e18c29` | Existing resident personally landed one Rolling Pin hit and caused damage; hostile Bandits entered the human-threat lane and stayed excluded from zombie consumers. No incoming melee wound reached that resident within two minutes. Base duty resumed, and the surviving target moved out of sight. The retired-target recorder guard worked. Full reciprocal verdict failed. The next close-combat resident scene explicitly toggles duty off through the public API; sustained on-duty defense remains a separate requirement. |
| `SC-Harness-20261025-222613-684743fa` | **Passed independent household melee on `82AC1A73…`.** Unrecruited actor `lf:sc-1.792963670853E9-1-712550`, affiliation `faction-household-119690-1`, personally landed four Rolling Pin hits. One stock Smack/MeleeHit reduced its body-part health from 1700 to 1674.1177; stock Push caused stagger without added health loss. LF survived, the Bandits human-threat/native-facts classification was correct and primary identity/slots/count stayed unchanged. Existing weapons were physically dropped with their native identities preserved. |
| `SC-Harness-20261025-222935-4bf9ee07` | **Passed rendered two-way armored combat on `82AC1A73…`.** A real LF police vest, ID `1286701038`, retained identity through one native armor deflection: condition 10→7, holes 0→1, body-part health unchanged during that exact Shoot callback. A separate shot caused a real LF wound. Three LF pistol torso hits retained each stock ArmyDesert armor visual and native bullet defense 100. LF fired six rounds and Bandits three; main identity/slots/count unchanged. Stock Bandits uses item visuals without physical inventory armor before death; the test retains this ownership model rather than inventing item IDs. Its generated corpse items still require LC10 persistence proof. |
| `SC-Harness-20261025-223246-c9711af5` | Authored unrecruited Corey Biggs personally landed 13 Rolling Pin hit events and saw Bandits as human threats. Body health fell, but no stock Smack/MeleeHit wound was observed for him; the full reciprocal melee verdict failed. No incoming melee credit was inferred from health loss alone. The next local scene prefers opposing clear approaches to avoid locking both opponents inside one forward stagger arc. |
| `SC-Harness-20261025-223607-238e14e4` | **Passed resident reciprocal melee with stronger native ownership proof on `82AC1A73…`.** Existing recruited resident `lf:sc-1.792185247907E9-1-189736` landed nine Rolling Pin hits; native collision receipts independently confirmed that her own impacts damaged the exact targeted Bandit. Stock Smack/MeleeHit reduced her body-part health from 1700 to 1685.8195. She survived; both human classification and native-facts exclusion passed, with unchanged primary identity/slots/count. Although setup requested duty off, the actual equipment report and combat traces show duty on/base duty; the result is recorded against that observed state. |
| `SC-Harness-20261025-224646-743cb406` | Four-opponent Corey scene stopped before spawning because the roaming actor moved during equipment preparation and occupied an earlier staging tile. The fixture now refreshes connected clear approaches immediately before spawning and once before hostility, placing neutral test Bandits at clear tile centers. The observer remains farther away; all post-hostility attacks and movement remain native. No combat pass claimed. |
| `SC-Harness-20261025-225607-cceed4fc` | **Passed authored Strange Folk reciprocal melee on `82AC1A73…`.** Unrecruited Corey Biggs, `lf:sc-1.792965481145E9-1-501193`, affiliation `faction-oddball-119690-1`, landed one Rolling Pin hit with exact native collision damage proof. Stock Smack/MeleeHit reduced his body-part health from 1700 to 1682.9669. He survived, human-threat/native-facts classification stayed correct and primary identity/slots/count unchanged. Four unchanged Officers were staged once at verified connected opposing approaches while neutral. After hostility, movement and attack choices remained native. |
| `SC-Harness-20261025-230424-eea8d0f8` | Public Base Watch start/close and ordinary player walks into the kitchen and back outdoors passed native visibility/counter checks with Bandits enabled. Kitchen south-cutaway flags and car 46 native visibility passed. Screenshots were obscured by the startup report. The compatibility identity sampler and report dismissal did not run because the enabled flag was missing from the harness INI, despite the correct run manifest. The runner now emits that flag; this run does not count as completed pixel/alias acceptance. |
| `SC-Harness-20261025-231320-208f3bd1` | **Passed Base Watch return component with active Bandits on `82AC1A73…`.** Public watch start/close, normal native player paths into the kitchen/outdoors and advancing primary visibility counters passed. All 52 identity samples retained main ID 1 and exactly one living leader entry without duplicates. Manual review of watch-joined, kitchen-after-watch and car-settled PNGs confirms actual split view, restored full solo view, the kitchen south wall cutting away and both yellow taxi/black sedan visible. Nearby Scarlet's overhead name is visible. Watched Jill remained outside primary LOS; her name is not claimed as verified. No resident position/job/health, parked-car state or visibility flags were forced. This is Base Watch evidence, not expedition-return acceptance. |

The outgoing recorder now correlates each exact-LF native hit event with the
bridge's completed collision serial, target and actual-damage receipt. A nearby
ally's damage, candidate-only collision, failed future serial or hit on another
object cannot establish this actor's outgoing damage. Nineteen adversarial
firearm-verdict traces cover this contract; melee shares the same observer.
Fifteen armor-evidence checks reject stale requests, absent clothing damage,
wrong victims/models and changed item identities, while allowing native death
to transfer visuals to a corpse.

The final-bridge query benchmark `SC-Harness-20261025-224106-18d0c5f4` passes
all 15 checks on `82AC1A73…`, with the current adapter and native player isolation.
One stock Bandit remains active alongside actual native LF cohorts.

| LF actors | Queries without / with | Query time without / with | Mean frame interval without / with |
| --- | --- | --- | --- |
| 1 | 36,200 / 36,200 | 29 / 426 ms | 16.633 / 16.650 ms |
| 4 | 36,200 / 36,400 | 26 / 429 ms | 16.667 / 16.641 ms |
| 16 | 24,200 / 23,000 | 19 / 289 ms | 24.992 / 26.465 ms |

These are sequential three-second samples of 200 queries per frame, not a
battle or FPS guarantee. The 16-actor scene runs more slowly in both modes;
its enabled/disabled difference includes normal world/AI variation and cannot
all be assigned to the adapter. Fewer frames also produce fewer queries.

After all role, armor and Base Watch recorder changes, the full project gate
passes **28/28 stages in 91 seconds**:
`build/bandits-adapter-tests/role-armor-view-project-gate.log`. This includes
260 adapter/source checks, 19 firearm-verdict traces, 32 close observers,
14 shot observers, 15 armor-evidence checks, eight added view-identity controls
and 150 live-harness static contracts. Native bridge hash remains `82AC1A73…`.
All four original-save baseline hashes still match. The installed bridge is
unchanged; this candidate has not been installed, committed or published.

After the recorder changes, the full project gate passed all **28 stages** in
**89 seconds**, including the 260 adapter/installed-source checks, 32 close
observer checks, 15 firearm-verdict traces and 14 native-shot observer checks.
The report is `build/bandits-adapter-tests/combat-acceptance-project-gate.log`.
The candidate bridge remains `82AC1A73…`. All four original-save baseline hashes
and five dependency fingerprints match; normal presets still exclude Bandits2
and the installed bridge remains `D7AC97D3…`. All isolated game clients exited.

## Remaining acceptance

### Native stopped-car window protection

`SC-Harness-20261025-234942-af1e09d8` passes the native melee window case on
bridge `82AC1A73…`. A fresh recruited LF boarded the saved car's front passenger
seat through the public boarding command. The actual main player occupied the
driver seat, preserving the ordinary ride-with-player policy. One unchanged
ArmyDesert Bandit chose its own attacks; no attack task or damage callback was
invoked by the fixture.

- Closed glass: three original Smack callbacks lowered intact window condition
  without lowering LF body-part health inside those callbacks. The first was
  condition 98→76 with health 1700→1700.
- Open intact glass: condition stayed 76; the original MeleeHit wounded the
  exact LF alias, lowering summed body-part health 1700→1594.7000.
- After the window was closed again, stock attacks broke the remaining glass.
  A later native hit through the broken window lowered health
  1572.3148→1443.4109. No window repair or healing occurred. Ongoing bleeding
  between callbacks was not credited as another attack.
- LF remained in native seat 1, the car stayed stationary with its engine off,
  and main identity, player slots/count and callback damage isolation held.

The screenshot was inspected: both camp cars render, and the stock soldier is
beside the black sedan's passenger window. The recorder has 14 adversarial
checks, including stale/wrong-victim receipts and repeated task hits. This is
melee protection evidence; solid-wall and vehicle bullet paths remain open.

Two earlier fixture failures are retained: `233809-ae0acc7a` incorrectly indexed
Build 42's vehicle Set; `234706-70322e97` boarded LF with the player still on foot,
causing the normal stopped-car exit policy to end the scene before combat.
Neither is counted as a combat pass. The fixture now uses the production
loaded-vehicle helper and actual driver/passenger seating.

### Protected firing-lane scenes

The private native fixture creates one neutral Karate Bandit and one unchanged
loyal Bandits Companion, plus normal zombies and an LF with a real pistol. The
two humans are placed only before the combat phase. Read-only observation of
the real `Combat.friendlyFireBlocked()` calls requires their actual positions
on a target ray and membership in `Senses.protectedActors`. It rejects party
conversion, LF hit events on either bystander and native hostility drift. A
normal public Move here order may then request a flank; it never teleports a
combatant or replaces an attack decision.

| Run | Native evidence and remaining limitation |
| --- | --- |
| `SC-Harness-20261025-235217-7a0c6f88` | Setup stopped because native spawn safety counted a bystander on its own staging tile as an obstruction. The helper now permits only the same existing occupant, with static geometry, furniture and other bodies still excluded. No combat pass claimed. |
| `SC-Harness-20261025-235511-f8481ba0` | Actual production vetoes observed for both neutral and loyal humans; LF spent no rounds. The later-shot predicate timed out, so the full fixture failed. |
| `SC-Harness-20261025-235955-f06cc256` | Four ordinary zombies. The production gate vetoed the neutral 22 times and the loyal Companion 135 times. Across 394 samples, both remained external protected humans rather than allies; no LF bystander hit or escalation occurred. After the public flank order LF spent 17 rounds and emitted one exact-actor pistol hit event. The other combatants killed the remaining targets. No matching intended-target native damage receipt was confirmed, so the broader fixture failed. The event is retained as directional evidence, without claiming verified damage from it. |
| `SC-Harness-20261026-000557-2ffcd568` | Setup stopped on a staging tile occupied by a roaming actor. Staging now checks five bounded alternatives before combat, retaining all body/furniture/static collision exclusions. No combat pass claimed. |
| `SC-Harness-20261026-000848-4a006c55` | Native hit events targeted ordinary zombies other than the selected aim target: health 1→0 and 1→0.935500. The intended-target receipt correctly refused both as intended-target hits. A later animation event saw a blocked lane, but that event-only check did not reconcile the spent round/native target; the full fixture failed and is not evidence of confirmed collateral damage. |
| `SC-Harness-20261026-001555-9b2ace44` | LF caused a native kill in completed collision 11, with its exact native attacker identity. The new shot counter used an event-local ammo snapshot after vanilla had already consumed the round, so it never established a safe shot and the fixture failed. This event-order defect was in the private recorder; no gameplay behavior was changed to pass it. |
| `SC-Harness-20261026-001931-78209fb0` | **Passed protected bystanders and subsequent native fire on `82AC1A73…`.** The actual production gate vetoed each bystander 24 times. A normal Move here flank order then allowed 11 consumed pistol rounds; every reconciled gun event had a clear native aim lane. LF hit an ordinary zombie, lowering health 1→0.70206475 in completed native attempt/collision 11; its native ID remained 90 and `getAttackedBy()` was the exact LF actor. The actual hit zombie differed from the selected target, so it is credited as an actual native hit rather than falsely relabeled as an intended-target hit. Neither Bandit entered LF's registry/allies, received an LF hit or became hostile. Primary identity/slots/count held. Screenshot inspected. |

The recorder now distinguishes the aim target from the actual hit body. A
native hit event must occur inside this LF's in-flight collision; the same
attempt must complete, the actual victim's native ID must remain fixed, its
health must fall, and its native attacker must still be LF. Another attacker,
a stale/failed receipt, a recycled shell or ambiguous fire damage cannot pass.
Vanilla `ISReloadWeaponAction.onShoot` runs earlier on the same swing event, so
consumed shots are reconciled against the preceding rendered ammo/chamber
sample and the completed receipt. A swing event alone supplies no shot proof.
Native aim coordinates are verified separately from mutable AI target state.

Thirty-four Kahlua checks cover the lane recorder, false/stale contexts,
actual-hit ownership, consumed shots and safe initial placement. The initial
vehicle/lane update passed all 28 project stages in
122 seconds: `build/bandits-adapter-tests/vehicle-and-lane-project-gate.log`.
After the completed native bystander case and recorder corrections, the final
full gate passed all 28 stages in 119 seconds:
`build/bandits-adapter-tests/native-window-protected-lane-final-gate.log`.
The four original-save hashes and five Bandits source fingerprints still
match, and Bandits remains absent from the normal preset and original save.
The installed native bridge is unchanged.

### Solid walls and vehicle bullet cover

`SC-Harness-20261026-004012-75e40d2f` passes the solid-wall case on
`82AC1A73…`. The fixture found the actual solid edge from 12041,6739 to
12041,6738. Native topology rejected doors, windows and fences as substitutes;
the original Bandits LOS function returned blocked for 20 samples, without LF
firing or receiving a wound through that wall. After a public Move here order,
the actors' LOS opened through normal gameplay. LF landed one verified native
pistol hit from three consumed rounds, in collision serial 3. No actor was
repositioned after hostility and no damage callback was invoked by the fixture.
The main player's identity, slots and count stayed unchanged. The screenshot
was inspected: the garage, both parked cars and Jake's overhead name render.
The evidence does not claim LF completed the requested outdoor move; LF was
still in the garage at the final image.

The vehicle bullet observer calls the original `ManageLineOfFire` once. A
vehicle block requires its stop result, actual damage to a surviving original
part, unchanged LF health and no new LF BulletHit request. Armor deflection,
misses and destroyed/replaced parts cannot satisfy that predicate. Stock random
part selection is retained, without imposing melee window rules on bullets.

| Run | Vehicle bullet evidence and limitation |
| --- | --- |
| `SC-Harness-20261026-002954-dc0a274a` | Nineteen actual vehicle-part blocks, including doors, engine door, tires and glass. No seated LF wound before the deadline, so the broader fixture failed. |
| `SC-Harness-20261026-003503-d112fbfc` | One actual vehicle-part block, then LF completed a public native exit. The attacker closed to melee distance and no exact native LF bullet wound was confirmed. Fixture failed; unrelated health changes are not credited as bullet wounds. Native moving-object snapshots confirmed both LF and main player were present in their squares. |
| `SC-Harness-20261026-004246-104b086c` | After a public exit and jog/stealth Move here order, LF remained behind the sedan in the inspected image. Fifty-seven stock vehicle-part blocks were observed, with no LF wound in those callbacks. This proves continued cover, not the required exposed-wound transition; the broader fixture failed. |
| `SC-Harness-20261026-005042-b3234c0a` | LF completed a normal exit and moved on foot. The attacker closed to melee range; no exact native LF bullet wound was confirmed before the deadline. Failed. |
| `SC-Harness-20261026-005755-0143698c` | A real new car was placed away from camp defenders. The passenger door was locked, so boarding failed before combat. The next fixture used the normal driver-seat Unlock door action. |
| `SC-Harness-20261026-010221-e5db9ebd` | Native boarding succeeded. The fixture's late distance gate did not retain its spawned Bandit; it never entered the combat phase. Failed. |
| `SC-Harness-20261026-010948-d205e9a0`, `011419-bad55cb5` | Native boarding succeeded, but setup could not select a gun position. An on-foot geometry predicate unnecessarily rejected the intended car footprint. No combat pass is claimed. |
| `SC-Harness-20261026-012907-ee408d11` | A stock gunshot damaged surviving front-left glass, without LF health loss or a bullet request. LF exited normally, but no destination satisfied the fixture's exposure constraints. Failed. |
| `SC-Harness-20261026-013342-7555f02b` | One native car block, then a public exit and Move here. LF fired despite Hold Fire; the Bandit died/retired before the required exposed wound. This revealed the human-combat policy bug described below, rather than passing the scene. |
| `SC-Harness-20261026-014404-0f560aea` | With the Hold Fire fix, LF spent zero rounds and moved toward the public destination. One car block preceded two exact native BulletHit wounds to LF after exiting: body-part health 1700→1656.302505 and 1655.408257→1633.559517. Both wounds occurred while LF remained near vehicle cover, so neither satisfies the stricter vehicle-free exposure predicate. The attacker subsequently closed to melee. Failed. |
| `SC-Harness-20261026-014921-a1117939` | Hold Fire retained zero rounds; LF physically reached its walking destination. One car block and an exact native LF bullet wound were observed, but the wound occurred before LF left the car neighborhood. Stock targeting then selected main-player ID 1; the attacker died/retired without the required vehicle-free wound. Failed. |
| `SC-Harness-20261026-015352-af9175f0` | Main exited and a normal native Walk to action was queued. Main did not get away and was attacked, while LF stayed near its exit tile in repeated path searches. One vehicle block and zero spent LF rounds were retained; no LF bullet wound was confirmed. Failed. |
| `SC-Harness-20261026-015939-266ae058` | Preparation failed before combat: the floor-drop API returned an inventory item, but the observer setup treated it as a world object. The next fixture instead verifies `item:getWorldItem():getItem()` and the unchanged native item ID; the three new ownership regressions pass. |
| `SC-Harness-20261026-020257-f594b33f` | Before hostility, 226 real surplus observer items were physically dropped with exact world-item and ID checks. Main's load fell 207.209595→9.125002 against its unchanged native limit of 12. The native exit/walk setup still failed to get Main away; Bandits targeted Main in melee while LF repeatedly requested paths from the exit tile. One car block, zero LF rounds and no LF bullet wound. Failed; overload alone does not explain the movement failure. |

The exposure observer checks LF's actual on-foot position inside the original
native bullet callback, including Bandits' final two-tile ray neighborhood.
A requested vehicle-free destination alone cannot pass. Its ray uses floor
tiles for fractional actor positions; missing cells fail the check. The next
fixture also asks Main to exit and walk back through ordinary native timed
actions, so the stock closest-player rule can retain LF as its target.
No actor is teleported after hostility. Twenty-seven vehicle/placement and
twenty-five native-ray observer checks pass, along with twelve wall-scene
checks. The native damage, accuracy and attack queues remain original.

### Hold Fire against human threats

The previous human-combat path checked the combat doctrine but omitted the
separate Hold Fire flag. A gun could also fall through a melee branch and
still fire through the native weapon. Human combat now refuses that firearm,
retains close shove defense and lets Decision continue the existing public
Move here order through its normal tactical path when immediate zombie
pressure or encirclement does not prohibit that handoff. Medical and retreat
decisions retain their existing priority. Native firearm dispatch rechecks
Hold Fire before a provider or native attack can start.

The new gameplay regression fails against the retained pre-fix payload from
`013342-7555f02b` at “Hold Fire blocks a loaded firearm against a hostile human
even with Weapons Free doctrine.” It passes with the correction. The native
repeat `014404-0f560aea` retained zero spent LF rounds while LF actually walked
and received stock bullet wounds. Full vehicle acceptance still failed for
the separate exposure condition above. The full project gate passed all
**28 stages** (121 seconds):
`build/bandits-adapter-tests/human-hold-fire-project-gate.log`.

The additional close-defense regression verifies that a companion holding a
loaded gun still dispatches a shove at an immediate human attacker under Hold
Fire. It and the full gameplay suite pass in
`build/bandits-adapter-tests/human-hold-fire-shove-gameplay.log`.

Movement handoff is still under investigation. `020257-f594b33f` contains
repeated `urgent_queued`, `survival_reassess_released` and `path_searching`
states. `SCDecision.survivalNeedsImmediateControl()` treats any human threat as
urgent, and `holdOwnedActivityOrPacing()` can cancel owned movement for that
condition. The next diagnostic needs the exact native/supervised owner, action
and navigation goal before changing this policy. Main's ordinary native Walk
to also failed, so the current evidence does not establish a single cause for
both movement failures. Existing medical, grab and close-threat interruptions
must remain active; no broad survival exemption has been added.

All four original-save baseline hashes and five Bandits source fingerprints
still match. Bandits remains absent from the user's normal preset and original
save, and the installed bridge is unchanged. The audit is retained in
`build/bandits-adapter-tests/human-hold-fire-input-invariants.json`.

The adapter is implemented, but these release acceptance items remain open:
the vehicle bullet-to-exposed-wound transition; witnessed
escalation; exhaustive authored Strange Folk immunity cases;
native save/reload with precise inventories and corpse contents; the full
lifecycle matrix beyond activation in both load orders; prolonged mixed zombie/Bandits base defense; walking and driving
expeditions with Bandits, followed by wall, vehicle and name-label inspection.

The existing expedition return-safety failures described in the
[driving investigation](driving-expedition-investigation-0.26.67.md) remain a
prerequisite for driving-with-Bandits acceptance. Neither a passing source
fixture nor a simple native melee exchange closes those issues.
