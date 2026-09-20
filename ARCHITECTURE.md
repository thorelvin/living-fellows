<!-- SPDX-License-Identifier: MIT -->

# Architecture

## Runtime shape

All project Lua lives under the single global `SurvivorCompanion` table. `SCBootstrap.lua` loads core and gameplay modules, transactionally installs every long-lived lifecycle, faction, contract, map, save, game-start, and main-menu hook, and starts `SCRuntime.lua`. A failed install rolls back every hook acquired by that attempt and verifies the postcondition; repeated install/start calls remain idempotent. Runtime owns exactly one production `Events.OnTick` callback. It registers staggered decision, vitals, vehicle, restore, production-encounter spawn, private-debug spawn, UI refresh, and persistence work with `SCScheduler.lua`. `SCPerformance.lua` measures the 2 ms frame target, enforces shared work-unit quotas, profiles systems/actors, and raises a bounded load level during sustained pressure. Optional native-call tracing adds decision-subsystem, item-capture, edge-classification and UI-rebuild scopes; it is disabled by default so production calls do not pay instrumentation cost. Its only production cache namespace, `perception-square`, uses dynamic square/actor keys and is therefore protected by configured per-namespace and total entry caps plus a bounded incremental expiry sweep. The scheduler always runs critical combat/survival lanes before high, normal and background work; expensive perception, route, scavenging and production-house jobs retain their frontier across frames. Production encounter cadence is bounded independently of the private debug guarantee and still fails closed when no actor provider passes its gate. If the Java global appears after Lua bootstrap, the bounded spawn pulse rechecks the bridge and activates the runtime without requiring a reload.

Lifecycle reset first preflights pending action, spawn, persistence, registry, and native-actor ownership. It removes the central tick and focused inventory-container hook only after teardown can commit, then clears runtime Java-object references, resets decision/UI/core modules, and detaches on main-menu entry. A failed native removal or persistence cancellation keeps its management reference and blocks the destructive reset for a later retry. Runtime save remains disabled until startup and the complete persistence restore transaction have committed. `SCUI.scheduledRefresh()` is invoked only by the scheduler. Player container selection is observed by a narrow `ISInventoryPage` method wrapper and forwarded to `SCEncounter.onPlayerContainerOpened` without world polling.

## Core boundaries

- `SCActor` selects a version-pinned provider, validates native components, owns transactional spawn/removal, and is the only gameplay movement/action entry point.
- `SCActionSupervisor` is the actor-wide owner graph for Living Fellows work. It admits one exclusive action owner, records phase/deadline/receipt history, queues urgent survival work at checked cancellation boundaries, and permits an externally owned vanilla/third-party action only as a read-only busy state. Medical, locomotion, decision, and native-action adapters publish exactly-once terminal outcomes through this graph.
- `SCNativeActions` interprets every movement or action intent and reports success only after the native state/action was verified.
- `SCNativeTraversalActions` implements verified window, fence, wall, sheet-rope,
  and downed-state transitions. Every request still enters through
  `SCNativeActions.dispatch`; pacing, activity ownership, interruption, seating,
  and effect-claim guards remain centralized and execute before the handler.
- `SCNativeVisualActions` implements effect-free human signals, room sweeps,
  facing, conversation poses, and player-posture mirroring. Timed visual effect
  ownership and cancellation remain in the guarded `SCNativeActions` facade.
- `SCBanter` owns bounded party flavor and small social encounters. It remembers
  new-survivor pairs for the session, selects only calm visible non-hostile
  meetings, and stages both first greetings and occasional camp exchanges
  through `SCPositioning`; delayed replies, speaker quiet time, and party/actor/
  pair cooldowns prevent overlapping conversations. Its interior-state lane
  samples native `STRESS`, PANIC moodle transitions, and smoker-only
  `NICOTINE_WITHDRAWAL` for speech; deaf actors suppress sound dread, recent
  overrun refusal wins arbitration, and one rotating actor per pulse bounds the
  work. The lane never writes relationship state or affects decisions.
- `SCDialogue` owns deterministic candidate assembly and anti-repetition. Every
  actor retains its bounded per-topic history; common combat, danger, and signal
  lines additionally use a bounded party history only within the configured
  eight-tile hearing radius. Voice and mood variants remain actor-specific, and
  a fallback to actor-local memory guarantees that a small pool cannot starve.
  Optional register lines intersect the existing voice and mood axes without
  creating a new personality dimension; combat excludes aftermath registers
  while another live threat, player danger, or an overrun retreat remains.
- `SCDowntime` may select unread literature carried by the actor or borrow one
  exact item from nearby marked camp storage, prioritizing the dedicated
  `literature` category before its bounded fallback scan. The storage scan is bounded,
  withdrawal policy, reserves, personal items, and work cargo are respected,
  and every terminal path attempts to return that exact object to its source;
  retaining it on the actor is the lossless fallback if the source rejects it.
- `SCNativeCombatActions` and `SCNativeWorkActions` own action-family selection
  after admission. Combat impact/RNG and timed work/needs state machines remain
  colocated with their polling, cancellation, and rollback APIs in
  `SCNativeActions`; the family handlers cannot bypass those callbacks.
- `SCNativeMovementActions` owns the final provider-versus-direct path/vector
  dispatch after supported-intent and native-busy validation; the guarded facade
  retains movement admission and the verified native primitives.
- `SCWorkRoutes` owns the session-local candidate memory for repeated companion
  work trips. It stores only flat coordinates, caps the shared cache at 32 route
  variants, and can join a nearby proven suffix through a bounded open segment.
  `SCNavigation` remains authoritative: short fixed targets must prove an
  exact-cost open line, and every retained route edge is reclassified against
  current topology, hazards, safehouse, camp and actor policy immediately before
  movement. A changed route cools down and returns to the ordinary resumable A*
  path; combat, survival, moving and stealth-scored requests never use this cache.
- `SCRegistry` owns UUID maps and the `sc-` identity prefix.
- `SCBaseObjectRef` owns the persistent `LF_BaseObjectId` reference contract for
  camp storage and maintenance objects: bounded describe/copy/normalize/resolve
  operations, no read-side identity allocation, and fail-closed legacy records.
  `SCBaseLife` retains the base document, serial allocation, save schema, and its
  existing public resolver facade.
- `SCGatherWork` owns the resumable, camp-bounded floor scan for exact
  `Base.Log` and `Base.Plank` wrappers. It retains only cursor/cooldown runtime
  state, yields by square and object budgets, distinguishes incomplete evidence
  from proven absence, and delegates every mutation to `SCWorkTransport`.
- `SCFarmWork` owns bounded scans of marked Farm areas and dispatches the real
  Build 42 plow, sow, water, compost, cure, harvest, and water-fill actions. It
  rotates the scan budget across every Farm area and selects the highest-priority
  candidate in the slice, so multiple fields share attention deterministically.
  It maintains persisted receipts for exact borrowed supplies and harvested output,
  resumes or reconciles work after save/load from native plot and inventory
  postconditions, preserves a dynamic replanting seed reserve, restricts remote
  work to daylight, and never plows ground that was not already a farm plot.
  Its event speech uses deterministic chance plus actor/party cooldowns, remains
  silent near threats, and never participates in action admission or completion.
- `SCProduction` owns finite base production orders through a small operation
  registry: `fell_trees`, `saw_planks`, `dig_graves` and `bury_bodies`. Each
  operation is a descriptor plus an adapter; `SCBaseLife` owns the persisted
  schema (`base.production`, its own version, unknown operations quarantined
  and re-emitted unchanged). Every effect comes from the real vanilla timed
  action queued through the `SCNativeWorkActions` family (`ISChopTreeAction`,
  `ISHandcraftAction` with the pinned `SawLogs` inputs, `ISEmptyGraves` through
  a companion build action, `ISBuryCorpse`, `ISFillGrave`); progress counts
  only after the post-condition is re-proved in the world (tree gone, exactly
  the new planks, both grave halves, body removed and grave count raised,
  grave filled). Sawing retains a bounded actor receipt containing the order,
  input identity and pre-action plank count; completed effects are reconciled
  before cancellation and after restore, while cargo markers make adoption
  idempotent. Burial claims both its exact body and grave and commits one
  outcome per target; its bounded pass skips open graves with no eligible body
  and automatic digging admits only sites near one. A chop watchdog enables vanilla's own 1500 ms `ChopTree`
  event emulation only after native events are disproved for the session, and
  disables it on the first native hit. Scans are resumable and square-budgeted,
  candidates back off and exhaust, loud work refuses visible threats, rest and
  action time are capped, and blocked orders re-check on a 30-second cadence.
  The native facade's pacing pause and busy/visual rejections are waits: they
  never cool down or exhaust a work target. Lumber areas may lie in a bounded
  reach band (`productionLumberReach`, 30 tiles) around the camp-area union.
  A new `fell_trees` order treats all valid Lumber areas as a pool: the selector
  counts visible standing trees, subtracts unfinished tree commitments, and uses
  stable zone ids to break ties before persisting the chosen zone on the order.
  `SCBaseLife.admitsWork` admits that band only for intents marked
  `workReach` (felling and lumber-area gathering), `SCNavigation`/`SCWorkRoutes`
  use it for every camp-work admission site, and `SCBaseWork` lets only lumber
  jobs continue there; outside the camp no new tree is started at night.
  Felled logs stay vanilla world items and are moved by linked gathering
  children over the lumber zone. Each child remains capped at 100; overflow is
  persisted on the production order and split into later children without lost
  demand. Production lifecycle/progress/grave/cargo mutations share the same
  monotonic scheduled-save consistency barrier as gathering receipts. Burial ceremonies add one prayer or gallows line
  per grave, chosen by personality and mood.
- `SCWorkTransport` owns persistent work cargo receipts and the strong transfer
  boundary shared by gathering and ordinary base hauling. Exact transactional
  membership uses native `ItemContainer.contains()` independently of the
  routine 256-item AI scan budget and must agree with
  `InventoryItem.getContainer()`; capacity is fail-closed;
  delivery accounting is exactly once; save/restart reconstruction requires
  explicit detached proof; ambiguous or third-party ownership quarantines
  without copying. Reconstruction creates and journals the exact native object
  before insertion, so mutation-then-throw failures retain a cleanup/recovery
  anchor. Receipt actor identity is immutable history and is deliberately
  separate from the order's current worker list; only running orders require a
  live assignment. Storage withdrawals revalidate reserves at the synchronous
  commit boundary. Successful terminal receipts release native references
  immediately, while a failed marker removal enters a separately bounded,
  durable cleanup phase that pins the destination until resolved. Runtime
  native references are rebuilt from evidence and never enter the BaseLife save
  document.
- Private diaries are four modules. `SCDiaryText` is a pure, deterministic
  compiler: it selects a complete authored passage whose declared evidence
  holds, avoids repeating a recent meaning or structure, and renders literal
  tokens that may not contain control characters. It never reads game state or
  consumes RNG. `SCDiaryCatalog` holds the reviewed passages in four voices,
  each with its evidence prerequisites and a statement of what it asserts.
  `SCDiaryItem` owns the physical `LivingFellows.PrivateDiary` payload
  (`LF_Diary`, schema 1). Every entry is its own bounded string, because Build
  42.20.4 saves ModData strings with a signed 16-bit length. Appends are
  revision-checked, idempotent by entry id, and read back before success.
  `SCDiary` owns the world subsystem `diaries`: a one-time saved diarist
  decision and voice, a bounded inbox of verified experiences with durable
  source receipts, callback anchors, and style history. Owning subsystems
  report only verified outcomes: recruitment, `SCMedical`'s verified dressings
  with their real helper, the writer's own visible wounds and felt fever from
  `SCMedical.assess` (never hidden Knox state), `SCInfectionCrisis` knowledge
  paths and outcomes, grief-proven deaths, and the recorded shared escape.
  `SCDowntime` offers a `write_diary` activity (the verified human read pose)
  only when a truthful draft exists and the exact book and a pen are carried.
  The page commits only after that supervised action completes, the author,
  calendar day, candidate and exact book revision are rechecked, and the book
  accepts the append. Only then does controller state change and
  `SCDiary.contentRevision()` advance. Scheduled persistence binds that
  revision like the base work revision, so a page written mid-capture forces a
  fresh capture. Confirmed native death freezes the author after grief and
  before actor retirement. The book is never recreated and never written
  remotely, and it stays readable with no author record. `SCDiaryUI` is an
  item-bound, read-only, plain-text reader that asks for confirmation before
  opening a living author's diary.
- `SCVitals` observes native `BodyDamage`, moodles, XP, Knox state, hunger, thirst, and death. It persists native needs with the same bounded record but does not implement parallel health or infection. Its public CharacterStat readers are read-only. `SCVitalsTrace` is an off-by-default developer probe that reports a fixed stat vector plus `SystemDisabler.doCharacterStats`, rate-limited per actor and capped at 32 actors. Native environmental `STRESS` and `NICOTINE_WITHDRAWAL` are never aggregated into the persisted relationship `state.stress`; they are separate domains.
- `SCPersistence` owns the world-scoped Global ModData key `SC_WorldV1` with document schema 3, strict path-aware values, pending transactional restores, and save preservation while actor creation is unavailable. Character replacement after player death therefore keeps companions, factions, bases, and community state. Restore first copies and validates the complete envelope without publishing state. An envelope that cannot be copied exactly, or has malformed required buckets, blocks restore/save and leaves the original world document untouched. Copyable but schema-invalid actor and subsystem values are quarantined, never activated, and re-emitted unchanged on the next valid save; `tradeRecovery` uses the same canonical save/restore/retry owner definition rather than a separate retry map. Scheduled saves stage subsystem exports, resumable strict copies and resumable actor inventories in 0.75 ms background slices on a fixed 50 ms background pulse, verify each actor's exact inventory/equipment identity sequence before and after capture, then synchronously revalidate the complete registry lifecycle, all active ownership sequences, actor and virtual vehicle state, and trade-recovery state immediately before the one atomic publication. Inventory walks re-read live list sizes between resumable slices. Churn retries twice; an owner whose inventory moved between its capture and the commit barrier is recaptured alone within the same retry budget, its staged copy replaced, and the complete barrier repeated. A 20-second live-work deadline, extended by pause or stall gaps up to a two-minute hard cap, preserves the prior document on expiry and delays the next attempt by five seconds. `OnSave` cancels staging and performs the existing fresh synchronous atomic capture. Deterministic provider failures use bounded backoff and terminal quarantine with explicit manual retry. A record quarantined after unverified native removal is excluded from runtime work and saved from its last verified stable snapshot instead of recapturing the uncertain actor.
- `SCTrade` owns item transfer authorization and a durable per-item recovery journal. Native reconstruction progresses through `original`, `building`, and `verified`: the factory-created object is journaled before inventory insertion, every generated identity receives a build marker before optional native-ID reads, and `SCPersistence` recaptures the completed root and weapon parts before publication. Recovery closes only after the exact item is compensated to its intended source and both list membership and `InventoryItem.getContainer()` agree. A destination-held half trade, an unlocated partial reconstruction, or absence without persisted detached proof remains unresolved rather than becoming a successful rollback or a copied item. Death rewrites referenced live actors to terminal `retired` descriptors before registry release. Active retries use bounded backoff and a persisted rotating cursor; a restored runtime gets a fresh availability window for asynchronously spawned owners. Quarantined records consume no automatic scheduler work, block neither unrelated factions nor unmarked items, and expire under a separate age/count cap so terminal evidence cannot exhaust the live recovery journal forever.
- `SCVehicle` owns a capacity-aware passenger manifest, assigns only installed non-driver seats, revalidates a changed seat map before entry, and leaves overflow followers active in a bounded wait state. It exposes a non-mutating seat preflight and prefers verified native seating. A virtual-seat fallback is permitted only after native rejection or a verified native rollback; it stores a stable record for later restoration beside the vehicle. Native entry is never described as atomically reversible. Passenger firearm authorization additionally requires a ranged doctrine, an open or broken side window, a doctrine-specific speed ceiling, and a shared vehicle firing cadence.
- `SCAllegiance` is the pure, direction-sensitive relationship policy for party,
  faction, neutral, and hostile actors. `SCFactions` alone resolves mutable
  registry/group facts and retains the public relationship facade.
- `SCThreatSet` owns bounded threat de-duplication, emergency-first retention,
  deterministic ranking, posture/fence subsets, and overflow accounting.
  `SCPerceptionScan` owns the cached horizontal/vertical frontier, persistent
  cursors, job creation, origin rebasing, and scan-budget description. Protocol
  8 copies a coherent flat actor/x/y/z zombie snapshot on the main thread every
  250 ms; all numeric raw-table values are normalized to Kahlua Lua numbers,
  and malformed output, overflow above 8192 or bridge failure falls back to the
  bounded Lua producer without publishing partial negative evidence. Snapshot
  cadence is separate from the identity revision used for negative evidence, so
  stable large rosters can finish their observer scan while a latest-position
  spatial validation catches actors that move into range. Fallback negative
  native-roster evidence requires matching complete identity passes and is
  invalidated by count changes, incoherent passes, or same-count identity churn.
  `SCSenses` alone resolves live sight, hearing, world squares, and publishes
  snapshots.
- `SCSpawn` performs bounded, loaded-square, unseen, collision, occupancy, and nearby-zombie validation.
- `SCNeeds` samples positive native hunger/thirst deltas and rebates half while preserving every negative vanilla food/drink effect. It selects only conservative safe food and clean water, and dispatches the real Build 42 eat, bottle-drink, or water-source timed action. Its narration observes native hunger, thirst, and fatigue in three severity bands, queues only upward threshold crossings, clears stale pending lines when the need improves, and defers speech during danger or cooldowns. It changes no stat or decision.
- `SCLogistics` inventories the companion recursively and requests one missing construction item at a time from `SCEncounter`'s reserved camp-storage boundary: marked base storage inside the base (never memorial storage, never below its reserve) and player-opened containers away from it. Unknown world containers and unmarked containers inside the base are never considered camp storage. Literature and farming supplies are distinct loadout/storage classes: unprotected books and magazines are proactively deposited only into an in-range marked `literature` container, while seed, farm tools, compost, water cans, and crop treatments are proactively deposited only into marked `farming` storage. Without a matching destination they remain carried; the ordinary overload path may still use its established safe fallbacks.
- `SCPathSearch` owns the resumable A* heap, search jobs, deterministic ties,
  bounded expansion, path reconstruction, and failure classification behind a
  world adapter. `SCNavTraffic` owns group-passage queues, stable waiter order,
  choke-corridor and next-step reservations, leases, expiry, and cancellation;
  it admits movement but never issues it. `SCNavTraversal` owns shared object
  reservations plus the door, window, empty-frame, fence, approach-alignment,
  and owned-door-close state machines; native requests still pass through the
  existing gameplay movement boundary. `SCNavigation` retains geometry/cost
  policy, bounded outdoor egress, movement ownership, stair choke reservations,
  blind-corner observation, and a 64-square loop-erased indoor entry trail. Its
  separately bounded exterior search is refreshed on a cooldown and never scans
  unloaded world data without a node/radius cap. Tree trunk squares are
  non-passable detours; neighbouring tree clearance is costly, while cuttable
  bushes remain expensive but legal terrain. Full-square/moved/wall thumpables, directional
  stairs/slopes, actor crowds, safehouse boundaries, and native collision
  evidence are classified independently. Failed directed edges expire from a
  per-actor blacklist; blocker diagnostics retain type, object, square, actor
  state, and recovery result.
- `SCSenses` records close threats by cardinal sector. `SCCombat` combines those sectors with immediate range, wounds, endurance, weapon readiness, and nearby healthy support; a hold/recovery threshold prevents attack-retreat oscillation. Its overrun result also carries the deterministic dominant positive cause, with categorical immediate/sector/stamina hazards taking precedence and support excluded because it only lowers risk. On the transition into an autonomous overrun, `SCBanter` may voice that exact cause through the companion's personality register under long actor and party cooldowns; speech probability never affects the decision, and a spoken refusal retains the ordinary combat bark's hearing/world-sound consequence. A player-persistent, team-wide Rules of Engagement doctrine selects Stealth, Close Defense, Ranged Support, or Weapons Free without bypassing retreat or friendly-fire gates. Safe break-contact decisions may alternate a bounded shove or covering shot with movement.
- `SCNet` is an inert future authority boundary; multiplayer fails closed.

Gameplay modules use `SC.Actor.setMovement(actor, mode, intent)`. The adapter normalizes jog/run, derives vectors from `nextSquare`/`targetSquare`, routes engine paths, and dispatches equip/reload/combat/window/vehicle/medical/downtime intents. Cosmetic human timed actions are effect-free; their caller owns inventory/body mutation and proceeds only after the native timed action starts. This avoids applying vanilla effects twice.

## Native actor-provider hard gate

`SCLauncher` starts `SCBootstrap` before delegating to the unmodified `MainScreenState.main`. `SCExposure` publishes the versioned `SCBridge` API and the otherwise-unexposed, version-pinned `zombie.AttackType` enum into Kahlua; readiness requires `SHOVE`, `STOMP`, `SHOT`, and `MELEE_SWING`, so Lua never guesses an attack type. `SCBridge` only creates the original final `SCNativeCompanion extends IsoPlayer` class in single-player with no split-screen and no occupied extra local-player slots. Lua requests creation asynchronously: a daemon performs only the queue hand-off, then Project Zomboid constructs the actor on its next main-loop pass after the originating `LuaJavaInvoker` frame has unwound. This is required because the stock `IsoPlayer` constructor synchronously fires `OnCreateLivingCharacter`, and re-entering Kahlua from the exposed bridge call can corrupt Build 42.20.4's pooled return-value state. The actor constructor sets NPC mode and reserved internal index 3 but never writes the static player array or singleton.

Protocol 8 also exposes three main-thread-only bulk readers. `captureItemFacts` copies scalar item/Food/drainable/key/weapon/magazine state into one reused Kahlua table while graph-shaped ModData, fluids, visuals, parts and nested inventories remain under Lua validation. `fillEdgeFacts` batches version-pinned square and barrier facts while Lua retains safehouse, key, capability, reservation, hazard and cost policy. `fillZombieSnapshot` publishes the coherent roster described above. Java normalizes every raw numeric table value to `Double`, and Lua validates the complete expected type contract before accepting item or zombie bulk output. All three fail closed into the existing Lua paths; no Kahlua table or game object crosses to a worker thread. Successful Java methods are cached by Java metatable and name only for the active bootstrap generation, while synchronous decision read batches reuse positions/squares only until that callback returns.

Creation requires a loaded square plus native BodyDamage, Moodles, XP, emitter, and HumanVisual. The `IsoPlayer` subtype supplies those native human components, but its local-player update controller is never entered. The sole exception is a synchronous, `volatile` wall-climb outcome context: `isLocalPlayer()` is true only while `ClimbOverWallState.setParams()` rolls vanilla success/struggle/fail, is cleared in `finally`, and never publishes the actor into a player slot, singleton, camera, or local update controller. Every inherited `triggerContextualAction` overload is overridden to refuse the local player's `ContextualAction` hook, whose stock handlers resolve `getSpecificPlayer(getIndex())` and would queue the player's timed actions; companion climbs call `climbOverFence`, `climbThroughWindow` and the wall entry directly, and only while the stock action graph can consume the climb event. During construction, the bridge snapshots and temporarily clears only the `OnCreateLivingCharacter` callback list, then restores the identical references and order before proceeding; this prevents third-party player hooks from entering Kahlua inside the NPC constructor. Version-pinned reflective calls invoke `IsoGameCharacter.updateInternal`, `IsoPlayer.updateWhileInVehicle`, and `IsoPlayer.checkActionGroup`; bridge readiness validates all three exact signatures before any spawn. Java snapshots all four static player slots, `numPlayers`, the singleton, and the camera character across every update and recovery. Recruited companions can be reattached to a verified loaded square after chunk unload, while neutral unloaded encounters retire normally. Any other mutation or native failure freezes the companion and latches a diagnostic. World removal is postcondition-verified, and failed cleanup retains strong bridge/Lua ownership plus retry evidence. Lua reads bridge protocol `42.20-isocompanion-9` from `SC.Identity` and rejects stale loaders.

`SCViewControl` implements bounded Peek and Watch tiers without changing camera ownership. The rebindable hold action follows the selected roster companion; the context-menu Watch action latches a validated companion until Stop watching, target loss, floor/range failure, or teardown. The central frame tick eases `IsoCamera.cameras[0].deferedX/deferedY` toward that actor through `SCBridge.setViewOffset` and back to zero on release. Both Lua and Java enforce a sixteen-tile radial bound, and Lua requires the same floor. The bridge rejects non-finite coordinates and writes only the deferred offsets, leaving player slots, the singleton, camera character and the independent `rightClickX/Y` aim lean untouched. Build 42.20.4's current `PlayerCamera.center()` assigns `offX/tOffX` together, so its apparent `/15` update does not ease this surface; smoothing is intentionally owned by Lua and uses real elapsed time.

`SCSteering` is the paired cursor-control tier and adds no native API. Its rebindable hold action converts the mouse position to loaded ground on the selected actor's floor, acquires `player_control/steer` through `SCActionSupervisor` at `PLAYER` priority, and refreshes the ordinary `SC.Actor.setMovement` path with a bounded native movement target. It never calls `MoveForward` or `setCompanionMovementTarget` directly. Work/travel owners may be preempted through their rollback, protected native activity may refuse acquisition, and `COMBAT_RESCUE`/`SURVIVAL` owners preempt steering. The cancellation callback stops the old movement vector before a new owner is admitted; stale-token detection deliberately does not stop the newer owner.

WP-D remains inside existing command and combat boundaries. Guard Here passes the immutable clicked-square payload into the established Guard order and patrol radius. Positive and negative zombie designations are transient live-object instructions on command state: `SCCombat.scoreTargets` applies a bounded signed score before its ordinary stable sort, while an attacker already in immediate danger range overrides the negative instruction and live LOS validation, doctrine admission, viable target/action selection and overrun assessment remain later mandatory gates. Designations expire after twelve seconds and are never exported or persisted. A new player-requested focus that reaches an overrun refusal requests the reliable speech path without changing the deterministic decision.

WP-E extends that same transient designation rather than creating an obedience mode. Relationship trust/bond contributes a bounded overrun-threshold term only for a player-requested target. Repeating Focus on the same target within four seconds creates one push episode, spends persistent morale/stress once, and adds a second relationship-derived bounded term. Both positive terms clamp away when there is no escape or no healthy support. A verified pushed kill improves bond; health lost during the episode reduces trust and records the injury. Extra clicks renew the same serial and cannot charge or credit it twice. All combat arithmetic stays deterministic.

Player-assigned objectives reuse the existing `commands.objectives` persistence bucket. The active assignment is marked `assignedByPlayer`; an existing self-chosen active goal moves to the additive `personal` slot and is restored when the assignment completes. The right-click menu derives its choices from `SCObjectives`, and all progress, bonuses and completion continue through the established objective paths.

The native subtype also mirrors aiming into Build 42's authoritative NPC `AIComponent` and owns `DeltaX`/`DeltaY` only for explicit tactical movement. This selects the stock IsoPlayer backward/diagonal/side-step animation blends without entering the local input controller. Every short manual step first calls the subtype's door-aware `PolygonalMap2.lineClearCollide` bridge; engine pathing remains authoritative when continuous geometry rejects the step. Lua enables tactical movement only for a collision-validated, flat, visible retreat edge and clears it before engine pathing, vegetation, doors, windows, stairs, or ordinary stop. Normal attack aiming remains independent.

The old raw-`IsoPlayer` provider remains disabled behind `experimentalNpcPlayerActor=false` as a non-production diagnostic fallback and is never enabled by the private installer.

## Prototype boundary

`bridge/src/prototype` and `bridge/src/test` are audit/test inputs, never release inputs. Production Java lives under `bridge/src/main`; the build verifies that the JAR contains only `survivorcompanion` classes and no compile stubs or `zombie/*` classes. The payload owns exactly one versioned bridge JAR and forbids loose `.class` files.
