<!-- SPDX-License-Identifier: MIT -->

# Sending companions home

Walking and driving on `living_fellows/0.26.95`, based on `8ea53d34`.

Recruited companions on Follow or Regroup can walk back to camp. Open **Send
home…** in their quick orders, or **Group: go home…** in the Squad tab. Review
up to four eligible travellers, their leader and the road or direct route in
one sheet. Excluded members are named; blockers remain visible beside the
fixed Send/Back buttons. The leader uses the existing companion view and zoom.

Initial limits are ground-floor departure and camp core, and routes of at
most 1,000 meters walking or 5,000 meters driving.
Base Watch, expeditions and another home trip share the same view reservation.
Seeing the crew through that view provides information, but direct recall
still requires the main player's actual nearby position and line of sight.

Every expected surviving member must be physically inside the captured camp
before handover. Their real inventories are preserved. Cleanup of surplus and
restocking use the existing permitted-storage policy, and remain pending while
camp is unloaded. The debrief reports those obligations separately from arrival;
it does not claim delivered supplies or base duty before verified work.

## Driving home

Choose **Drive** in the same sheet, or right-click a nearby car and choose
**Send home in this car**. Cars within 30 meters of the leader are listed.
The crew needs a real key, installed seats, usable wheels and engine, and
enough fuel for the reviewed road route. Your car is allowed while you are
outside it. Other occupants and a moving car block departure.

They use a fitting marked camp parking area, or a mapped road outside the
camp boundary within 40 meters of the core. They stop the engine, get out
through safe exits and walk into camp. A failed car follows the same safe
stop and walking fallback. The view remains reserved until the whole
surviving crew arrives.

The trip records the trunk's original item identities. Marked parking allows
normal physical unloading into permitted storage. Roadside cargo stays in
the trunk and remains pending until the car is moved into marked parking.
The debrief distinguishes arriving home, resuming duty and delivering cargo.
Saving during unloading retains the carried cargo's native identity. A worker
keeps its selected destination while fetching cargo, with access and capacity
checked again before each step.

Before the companion view can leave the stopped car, a native save barrier
queues the ordinary vehicle write and verifies its committed database record.
Its receipt survives reload alongside the trip; it never recreates a missing
car or missing cargo. Nearby cancellation also preserves the car's ownership.

## Changing a trip

**Call off trip** is a direct order when the main player is near the leader on
the same floor and has line of sight. The whole surviving crew must gather at
the player before the view closes and Follow resumes. Watching the companion
view does not grant this nearby authority.

Remote orders use equipped, powered portable two-way radios on the main player
and the leader, tuned to the same channel and within range in both directions.
The card keeps one call pending while it waits for the actual received reply.
It does not apply an order from a button press alone.

- **Come back** records the caller's position for the return. A driving crew
  first stops safely, gets out and preserves the stopped car before returning
  on foot. The car and its trunk cargo stay at that stop.
- **Hold** pauses the journey. A driving crew keeps its chosen car and cargo
  while stopping safely; **Push on** resumes the journey when it is safe.
- **Status** records the leader's returned report and its time. Out-of-sight
  position and travel state remain reported information, rather than live facts.
- **Push on** is available for a held or blocked trip. It requests continuation
  or a fresh route attempt; it does not bypass a changed camp or physical obstacle.

The player must meet a recalled crew at the call's recorded position. A remote
recall ends with ordinary regrouping rather than camp delivery or restocking.

## Distant handover

The existing joined-view release guard remains unchanged. A separate native
lease verifies the exact crew and captures the reserved slot. Persistence writes
fresh crew snapshots, a finalized idle trip and the cleanup/restock obligation,
then synchronously flushes GlobalModData before removing any native actor.
Retained corpse chunks use the existing native save barrier first.

The durable boundary transfers ownership to the dormant snapshots. Only that
crew stops acting or exchanging items during native retirement; other actors
continue and save their current state. Partial cleanup retains the exact lease
and retries. Before durability, a failed capture/write can abort, capture the
current active world and prepare again without reusing stale positions.

Secondary map closure follows verified native detachment. Tagged dormant
snapshots restore only when the actual primary map owns their camp squares;
a residual secondary cache is insufficient. Remote inventory snapshots retain
verified native item IDs, including nested bags and attachments. Legacy
inventory restoration stays compatible.

## Verification

Automated coverage includes roster/view/camp/floor/route blockers, complete-crew
arrival, nearby recall, active save/reload, failed capture/flush, moved-crew retry,
partial detachment, fresh unrelated inventory saves, primary-only cold restore,
native item IDs, transfer isolation and narrow UI geometry. Negative controls
must reject five travellers, leader-only arrival and a missing blocker label.

`SCHomeTripProbe` drives the real UI and mission in disposable cloned
worlds. It supports one to three travellers, mid-trip save/resume and dormant
save/resume. It records native IDs, medical state, duplicate counts, primary
ownership, pending handover and actual base duty. Native screenshots provide
separate evidence for solo walls, parked cars and overhead names.

Three-person walking live acceptance passed through a mid-trip reload, physical camp
entry, distant solo-view release, a cold dormant reload, exact item restoration
and actual base duty. See
[the validation record](validation-send-home-0.26.95.md) for the completed
scenarios, remaining limits and evidence.

Driving live acceptance passed for marked parking and roadside return. A paired
two-person run also saved with an original cargo item in a companion's hands,
reloaded that same clone with exact item identities and health, stored all four
original trunk items, and resumed both companions' base duty. The walk around
parked cars was slow under the bounded debug harness and remains a performance
polish candidate. Scope, individual runs and gate status are recorded in
[the driving validation record](validation-send-home-drive-0.26.95.md).

Walking and driving radio recalls also passed in cloned saves. Actual native
command and reply receipts, stationary holds, same-car driving resumption,
original crew/item/health preservation, retained trunk cargo and the settled
solo view were verified. The Field Guide includes a real Holding screenshot.
See [the radio validation record](validation-send-home-radio-0.26.95.md) for
completed scenarios, earlier fixture failures and the final gate result.
