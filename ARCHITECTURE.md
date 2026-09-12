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
- `SCNativeCombatActions` and `SCNativeWorkActions` own action-family selection
  after admission. Combat impact/RNG and timed work/needs state machines remain
  colocated with their polling, cancellation, and rollback APIs in
  `SCNativeActions`; the family handlers cannot bypass those callbacks.
- `SCNativeMovementActions` owns the final provider-versus-direct path/vector
  dispatch after supported-intent and native-busy validation; the guarded facade
  retains movement admission and the verified native primitives.
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
- `SCWorkTransport` owns persistent work cargo receipts and the strong transfer
  boundary shared by gathering and ordinary base hauling. Exact transactional
  membership uses native `ItemContainer.contains()` independently of the
  routine 256-item AI scan budget and must agree with
  `InventoryItem.getContainer()`; capacity is fail-closed;
  delivery accounting is exactly once; save/restart reconstruction requires
  explicit detached proof; ambiguous or third-party ownership quarantines
  without copying. Reconstruction creates and journals the exact native object
  before insertion, so mutation-then-throw failures retain a cleanup/recovery
  anchor. Its runtime native references are rebuilt from evidence and never
  enter the BaseLife save document.
- `SCVitals` observes native `BodyDamage`, moodles, XP, Knox state, hunger, thirst, and death. It persists native needs with the same bounded record but does not implement parallel health or infection.
- `SCPersistence` owns the world-scoped Global ModData key `SC_WorldV1` with document schema 3, strict path-aware values, pending transactional restores, and save preservation while actor creation is unavailable. Character replacement after player death therefore keeps companions, factions, bases, and community state. Restore first copies and validates the complete envelope without publishing state. An envelope that cannot be copied exactly, or has malformed required buckets, blocks restore/save and leaves the original world document untouched. Copyable but schema-invalid actor and subsystem values are quarantined, never activated, and re-emitted unchanged on the next valid save. Scheduled saves stage subsystem exports, resumable strict copies and resumable actor inventories in 0.75 ms background slices on a fixed 50 ms background pulse, verify each actor's exact inventory/equipment identity sequence before and after capture, and publish only one fully validated document. Churn retries twice; a five-second job deadline preserves the prior document and delays the next attempt by five seconds. `OnSave` cancels staging and performs the existing fresh synchronous atomic capture. Deterministic provider failures use bounded backoff and terminal quarantine with explicit manual retry. A record quarantined after unverified native removal is excluded from runtime work and saved from its last verified stable snapshot instead of recapturing the uncertain actor.
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
  250 ms; overflow above 8192 or bridge failure falls back to the bounded Lua
  producer without publishing partial negative evidence. Fallback negative
  native-roster evidence requires matching complete identity passes and is
  invalidated by count changes, incoherent passes, or same-count identity churn.
  `SCSenses` alone resolves live sight, hearing, world squares, and publishes
  snapshots.
- `SCSpawn` performs bounded, loaded-square, unseen, collision, occupancy, and nearby-zombie validation.
- `SCNeeds` samples positive native hunger/thirst deltas and rebates half while preserving every negative vanilla food/drink effect. It selects only conservative safe food and clean water, and dispatches the real Build 42 eat, bottle-drink, or water-source timed action.
- `SCLogistics` inventories the companion recursively and requests one missing construction item at a time from `SCEncounter`'s reserved player-opened camp-storage boundary. Unknown world containers are never considered camp storage.
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
- `SCSenses` records close threats by cardinal sector. `SCCombat` combines those sectors with immediate range, wounds, endurance, weapon readiness, and nearby healthy support; a hold/recovery threshold prevents attack-retreat oscillation. A player-persistent, team-wide Rules of Engagement doctrine selects Stealth, Close Defense, Ranged Support, or Weapons Free without bypassing retreat or friendly-fire gates. Safe break-contact decisions may alternate a bounded shove or covering shot with movement.
- `SCNet` is an inert future authority boundary; multiplayer fails closed.

Gameplay modules use `SC.Actor.setMovement(actor, mode, intent)`. The adapter normalizes jog/run, derives vectors from `nextSquare`/`targetSquare`, routes engine paths, and dispatches equip/reload/combat/window/vehicle/medical/downtime intents. Cosmetic human timed actions are effect-free; their caller owns inventory/body mutation and proceeds only after the native timed action starts. This avoids applying vanilla effects twice.

## Native actor-provider hard gate

`SCLauncher` starts `SCBootstrap` before delegating to the unmodified `MainScreenState.main`. `SCExposure` publishes the versioned `SCBridge` API and the otherwise-unexposed, version-pinned `zombie.AttackType` enum into Kahlua; readiness requires `SHOVE`, `STOMP`, `SHOT`, and `MELEE_SWING`, so Lua never guesses an attack type. `SCBridge` only creates the original final `SCNativeCompanion extends IsoPlayer` class in single-player with no split-screen and no occupied extra local-player slots. Lua requests creation asynchronously: a daemon performs only the queue hand-off, then Project Zomboid constructs the actor on its next main-loop pass after the originating `LuaJavaInvoker` frame has unwound. This is required because the stock `IsoPlayer` constructor synchronously fires `OnCreateLivingCharacter`, and re-entering Kahlua from the exposed bridge call can corrupt Build 42.20.4's pooled return-value state. The actor constructor sets NPC mode and reserved internal index 3 but never writes the static player array or singleton.

Protocol 8 also exposes three main-thread-only bulk readers. `captureItemFacts` copies scalar item/Food/drainable/key/weapon/magazine state into one reused Kahlua table while graph-shaped ModData, fluids, visuals, parts and nested inventories remain under Lua validation. `fillEdgeFacts` batches version-pinned square and barrier facts while Lua retains safehouse, key, capability, reservation, hazard and cost policy. `fillZombieSnapshot` publishes the coherent roster described above. All three fail closed into the existing Lua paths; no Kahlua table or game object crosses to a worker thread. Successful Java methods are cached by Java metatable and name only for the active bootstrap generation, while synchronous decision read batches reuse positions/squares only until that callback returns.

Creation requires a loaded square plus native BodyDamage, Moodles, XP, emitter, and HumanVisual. The `IsoPlayer` subtype supplies those native human components, but its local-player update controller is never entered. The sole exception is a synchronous, `volatile` wall-climb outcome context: `isLocalPlayer()` is true only while `ClimbOverWallState.setParams()` rolls vanilla success/struggle/fail, is cleared in `finally`, and never publishes the actor into a player slot, singleton, camera, or local update controller. During construction, the bridge snapshots and temporarily clears only the `OnCreateLivingCharacter` callback list, then restores the identical references and order before proceeding; this prevents third-party player hooks from entering Kahlua inside the NPC constructor. Version-pinned reflective calls invoke `IsoGameCharacter.updateInternal`, `IsoPlayer.updateWhileInVehicle`, and `IsoPlayer.checkActionGroup`; bridge readiness validates all three exact signatures before any spawn. Java snapshots all four static player slots, `numPlayers`, the singleton, and the camera character across every update and recovery. Recruited companions can be reattached to a verified loaded square after chunk unload, while neutral unloaded encounters retire normally. Any other mutation or native failure freezes the companion and latches a diagnostic. World removal is postcondition-verified, and failed cleanup retains strong bridge/Lua ownership plus retry evidence. Lua reads bridge protocol `42.20-isocompanion-8` from `SC.Identity` and rejects stale loaders.

The native subtype also mirrors aiming into Build 42's authoritative NPC `AIComponent` and owns `DeltaX`/`DeltaY` only for explicit tactical movement. This selects the stock IsoPlayer backward/diagonal/side-step animation blends without entering the local input controller. Every short manual step first calls the subtype's door-aware `PolygonalMap2.lineClearCollide` bridge; engine pathing remains authoritative when continuous geometry rejects the step. Lua enables tactical movement only for a collision-validated, flat, visible retreat edge and clears it before engine pathing, vegetation, doors, windows, stairs, or ordinary stop. Normal attack aiming remains independent.

The old raw-`IsoPlayer` provider remains disabled behind `experimentalNpcPlayerActor=false` as a non-production diagnostic fallback and is never enabled by the private installer.

## Prototype boundary

`bridge/src/prototype` and `bridge/src/test` are audit/test inputs, never release inputs. Production Java lives under `bridge/src/main`; the build verifies that the JAR contains only `survivorcompanion` classes and no compile stubs or `zombie/*` classes. The payload owns exactly one versioned bridge JAR and forbids loose `.class` files.
