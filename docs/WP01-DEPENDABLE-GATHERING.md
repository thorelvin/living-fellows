<!-- SPDX-License-Identifier: MIT -->

# WP01 — dependable gathering and delivery

## Player contract

The Base view can create a finite order for 1–100 logs or planks. The player
selects one existing camp work zone, one loaded registered storage with deposits
enabled, and one recruited resident; a second resident can be added later.
The default quantity is 12.

Workers scan only loaded squares in that work zone. They select an existing
`Base.Log` or `Base.Plank` floor item, approach it, play the effect-free human
loot pose, collect the exact item, approach the selected storage, play the same
interaction family, and deposit it. Existing storage stock never advances the
counter. The Base view shows delivered/requested progress, carried cargo,
blockers, pause/resume/retry, destination change, cancellation and explicit
cargo release. Each assigned worker also reports the current receipt phase
(seeking, approaching, delivering, depositing or recovery).

## Ownership contract

Each selected item receives a persistent `work-receipt:*` identity and
work-specific ModData marker. A receipt records the order, actor, native item
identity, exact source coordinate, exact destination storage, item snapshot,
phase, proven owner, accounting state, retry state and timestamps.

Every mutation is synchronous and accepts native calls only as invocation
receipts. Success requires agreement between bounded exact list membership and
`InventoryItem.getContainer()`. Destination capacity must be readable through
the installed `ItemContainer.hasRoomFor(IsoGameCharacter, InventoryItem)`
signature. Unknown evidence fails closed.

The durable phases are `selected`, `carried`, `depositing`, `recovery`,
`delivered`, `released`, `cancelled` and `quarantined`. Delivery is counted once
only after the exact item is proven in the selected destination. Reconstruction
is permitted only for a receipt that persisted explicit detached proof; a
third owner, owner-pointer conflict or ambiguous absence quarantines without
creating a copy. A paused floor selection is released. Cancelled carried cargo
remains protected until the player explicitly releases its verified marker.
Actor retirement preserves the one native cargo owner and quarantines it.

When reconstruction is authorized, the exact `InventoryItemFactory` object is
journaled before insertion into an inventory. Build identity is attached before
native-ID inspection, and a mutation-then-throw/nil result enters exact cleanup
or recovery instead of becoming an untracked copy. Cleanup preserves a reachable
root whenever a generated child or weapon part cannot be proven removed.

Trade, quest, favourite, personal and other active work items are excluded.
`SCPersonalItems.isProtected` delegates to the work receipt boundary, so
scavenging, packing, crafting and ordinary item consumers cannot steal active
work cargo. Existing base hauling uses the same strong container-transfer
postcondition.

## Scheduling and limits

- Work zone: at most 256 tiles and completely inside the union of camp areas.
- Work routes: interaction candidates and every Lua route edge must remain in
  the camp union; unrestricted native multi-goal/fallback routing is disabled
  for ordinary gathering (survival movement keeps its existing policy).
- Scan slice: at most 16 squares and 32 world wrappers; the cursor resumes on a
  later decision and distinguishes `pending`, proven empty and incomplete.
- Candidate retry: 15-second exponential cooldown, dormant after 3 verified
  pre-pickup failures until the player chooses Retry/Rescan.
- Orders: at most 8 active and 32 retained records.
- Workers: at most 2 per order, with quota reservation preventing over-delivery.
- Receipts: at most 32 recovery records, 2 recovery attempts per maintenance
  pulse, exponential backoff capped at 5 seconds, and 8 automatic attempts.
  Exhaustion stops in quarantine; proven detached evidence is retained for an
  explicit player retry, while verified native cargo can instead be released.
  Unloaded/incomplete ownership evidence polls at the cap without consuming a
  failure attempt, so an ordinary chunk unload cannot age into false quarantine.
- Diagnostics: cumulative scanned-square/object/yield/candidate counts plus
  reservation, collection, delivery, recovery, reconstruction and quarantine
  counts are available without retaining native world objects in persistence.

## Persistence compatibility

The existing BaseLife document version remains readable. A missing work section
normalizes to an empty version-1 work document. A future work-section version is
preserved under quarantine instead of being activated or silently discarded.
Orders, receipts and the rotating recovery cursor live in world-scoped BaseLife
state. Runtime item and wrapper references are cleared on reset and rebuilt only
from native ownership evidence.

## Verification

`tests/core/work_transport_harness.lua` loads the real BaseLife, persistence,
transport, gathering and BaseWork dispatcher. It covers successful exact
delivery, material filtering, pre-existing stock, two-worker quota contention,
tail candidates beyond one scan slice, unreadable native lists, no-op removal,
owner-pointer conflict, save while carrying, proven detached reconstruction,
bounded recovery exhaustion/manual retry, third-container quarantine, full
destination, protected items, unrelated inventory, pause, actor retirement,
explicit quarantined-cargo release, fair recovery and old/future work schemas.
The existing trade recovery harness runs in the same core gate to guard the
shared item codec.

The Java contract gate reflects the exact installed Build 42.20.4 capacity
signature plus `InventoryItemFactory.CreateItem(String)` and native-object
insertion. Static gameplay gates verify production module exports, exact item
types, bounded scan settings and dispatcher wiring. A real in-game sandbox run
remains a separate maintainer step because it launches Project Zomboid against
a disposable cloned save; implementation work must not modify a normal save.

### Acceptance evidence status

The coupled Kahlua fixture directly exercises G01–G18 where the state can be
made deterministic, including replacement identity, selected/carried reload,
new-vs-existing delivery accounting, contention, failure evidence, protection,
destination editing and bounded/manual recovery. Production predicates and the
existing coupled suites cover the G19 consumer boundary, G20/G22/G25 lifecycle
wiring, G26 fair service, G27 bookkeeping caps, G29 schema handling and G30
trade/persistence/hauling regressions. The project response harness retains its
1/4/8/16-actor thresholds.

The real animation/render loop, corpse transfer, player-death reload, actual
chunk unload/return, time acceleration and mixed-load delivery throughput in
G12 and G21–G24/G28/G30 remain **unexecuted**, not passed. They require the
protected disposable live-sandbox procedure below; headless success is not
reported as live-game evidence.

## Manual disposable-save checklist

1. Register a camp storage and draw a small work zone containing loose logs and
   planks. Put unrelated stock in the destination.
2. Start a one-worker order, observe approach/pickup/deposit, and verify only
   the matching floor item advances progress.
3. Repeat with two workers and a quantity of one; verify only one reserves the
   last slot.
4. Save while one item is carried, reload the clone, and verify one delivery
   with no duplicate at the source, worker or destination.
5. Fill the destination, unload/reload the source edge, pause/resume/cancel, and
   retire a carrying worker. Verify readable blockers and exactly one owner.
6. Record gathering diagnostics and frame behavior alongside the existing
   1/4/8/16-actor response profile. Transport diagnostics include pending
   receipt count, oldest waiting age, and successful deliveries per minute.
