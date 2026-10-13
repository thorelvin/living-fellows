# Markus Sloane's Last Fare — 0.26.40 implementation review

This updates `Living_Fellows_Markus_Taxi_Design_v2.md`, which reviewed 0.26.38.
The attached design remains the character and product brief. This document
records the 0.26.40 implementation order and what has actually been proved.

## Name and character

**Markus Sloane** is a good fit: short enough for the radio and destination
menus, distinct from the existing Vale, Voss, Mercer, and Kessler families, and
plausible for a driver who treats every rescue as a sale. Keep the original
dialogue seeds. His first ride is a customer acquisition expense, not charity.

## Current foundation

- The game has a stock `Base.CarTaxi` vehicle with four native seats, a taxi
  model, and blood/damage texture channels. Use this script first. The art
  channels and persistence of an authored worn look still need a live probe.
- `SCDriving` owns bounded road travel, block detection, safe parking and the
  native controller. The taxi reaches 50 km/h on clear straights during the
  occupied ride; ordinary companion driving remains capped at 30 km/h.
  `SCExpeditionRoute`
  supplies bounded mapped routes. `SCExpeditionCar` and `SCBaseLife` already
  validate base parking zones and car footprints. Taxi service should call
  their reusable checks, not copy expedition roster or split-screen logic.
- `SCVehicle` offers verified companion seat transactions. The ordinary player
  uses the game's own passenger entry. A driver must board before the player:
  `SCVehicle.preflightDriver` rightly rejects cars that already contain a
  human. A dedicated service boarding path may be needed if restoring a save
  with both occupants already seated; never weaken ordinary preflight.
- The standalone bridge candidate now uses protocol
  `42.21-isocompanion-23`. `driveStartWithPassenger` is a separate guarded
entry. It requires the exact local human in a real passenger seat of the
driver's car and rejects other non-companion occupants. The ordinary
`driveStart` guard still refuses human passengers. The taxi service now calls
this entry after verifying the booked passenger and fare.

## Stage A: passenger transport proof — passed locally

An isolated cloned-save test on 2026-10-13 spawned a stock `Base.CarTaxi`
with four native seats, then placed the real player in seat 1 with a native
companion at the wheel. The ordinary drive was rejected. The
passenger-authorized drive moved the taxi 22.04 tiles at 8.96 km/h with player
slot 0 unchanged. The taxi stopped and both occupants exited.
The 62-check core suite and live-harness static checks also passed. This
proves a local ride, not long-route streaming, reload recovery or the taxi
service as a whole. The retained run is under
`build/live-sandbox-runs/SC-Harness-20261013-150709-58eaf62a`.

The bridge contract must continue to reject another human occupant, a player
in seat 0, a changed car, or the booked player leaving the seat. Add live
negative controls for these before public service. The Lua driving job keeps
the exact passenger reference; the full service must bind it to a persisted
booking/vehicle generation before exposing a taxi action.

## First playable service slice

The radio booking ledger is now implemented in `SCTaxiBooking.lua`. It accepts
one request per save from the exact owned, powered, two-way portable handset,
including one carried in a bag. It keeps a generation and requested player
location, and supports status, pickup update and cancellation. It is captured
by the ordinary world save and restored after reload; invalid saved booking
data is quarantined by the persistence layer. The inventory submenu is now
visible in the local playtest build. It does not retune the radio or alter
rescue and expedition radio rules.

1. **Call.** Add an independent inventory context action for the *selected*
   owned, powered, two-way portable radio. Reuse the radio device checks in
   `SCOddballDistressRadio`, but treat Markus's reply as an abstract dispatcher:
   no 90 MHz rescue or expedition range rule, no forced expedition channel
   change. Validate the item again when the action runs. One outstanding
   booking per save, with repeat calls showing status rather than spawning
   another cab.
2. **Pickup.** Select a ground-level road stop with a loaded vehicle footprint
   and an accessible passenger door. Spawn one `Base.CarTaxi` on a loaded road
   outside active views; verify its SQL identity, driver ticket, key, fuel,
   controller and direction. Use a short physical `SCDriving` approach. If a
   hidden loaded candidate or safe curb cannot be found, keep the booking
   pending and offer another stop. No visible teleport or drive through an
   unloaded chunk.
3. **Ride.** Markus boards the driver seat before player boarding. Depart only
   when the booked player occupies a real passenger seat; warn about a full
   car before inviting companion passengers. For the first slice, offer the
   active base's validated parking zone or an explicit nearby map pin. Quote
   the road distance, then run the ordinary bounded route and safe parking.
   Test player-centered streaming across multiple chunks. Stop at a safe curb
   if route planning, visibility or engine state becomes uncertain.
4. **Dropoff.** Stop and verify the vehicle footprint and usable exit, then let
   the player exit normally. Do not remove an occupied cab. Drive it out of
   every player view after confirming the fare and luggage; leave the visit
   recoverable if retirement cannot be verified. Stale callbacks carry a
   booking and visit generation and cannot create a second Markus.

This slice should ship only after a save/load test during pickup, while seated,
and during departure. If that recovery cannot be made reliable, retain the
service behind a private debug flag while the next stage is built.

## Fares and cab continuity

The recovery and fare ledgers are now staged in `SCTaxiCab.lua` and
`SCTaxiFares.lua`. A spawn attempt gets one durable visit token before any
vehicle exists. A claimed `Base.CarTaxi` is identified by its saved SQL ID
and an ownership marker; reload recovery only reconnects the same loaded
vehicle. If it is unloaded, the marker conflicts, or a spawn callback was
interrupted, a new cab is blocked. A later booking reuses a retained physical
cab only when its prior visit could not finish retirement. After verified
despawn it creates a new one. The base car-unloading job excludes active cabs.

Fares use a verified 42.21 jewelry type list. The first completed ride is
free; cancellation leaves that entitlement intact. Later receipts select the
lowest sufficient value from explicitly offered loose jewelry in the cab's
native part containers. Markus's initial stores are recorded at claim time,
and bags remain luggage. Reservations and settled payments refer to stable
item IDs and stay on the real items; a missing or duplicate item stops
settlement. Excess value becomes saved credit. Unknown customer property
blocks cab retirement. Save/restore retains the booking, cab binding, fare
receipt, credit, initial stores and paid-item identities.

The 2026-10-13 native passenger/fare run
`SC-Harness-20261013-165910-078c3e58` proved the first free fare, a paid ring
in a real glovebox, one-time settlement, and a saved receipt bound to taxi SQL
ID 23. A new game process loaded the retained clone in
`SC-Harness-20261013-170144-891b78a3` and found that same vehicle and paid
ring ID 491015968 with its settlement marker. The focused harness also covers
canceling an interrupted settlement and rejects malformed restored receipts.
These tests prove native cab and fare continuity across a cold restart; they
do not prove a resumed drive with passengers seated.

The service now accepts a radio booking internally, selects a loaded road
outside active player viewports, spawns one native cab and unrecruited Markus,
and drives a physical pickup and a bounded passenger trip. The retained live
run `SC-Harness-20261013-180031-26840fee` proved one call, a 36-tile approach,
a native passenger seat, a 28-tile ride, passenger exit and one free-fare
settlement. The driver-roster correction and map destination menu have focused
checks. The later run `SC-Harness-20261013-185356-3dc37cf8` proved radio
booking, a 36-tile pickup, native player seat, fare reservation and mid-ride
save. Its cold-reload clone `SC-Harness-20261013-192555-1190dbb7` restored
the exact native cab, rebuilt unrecruited Markus with his saved ID, resumed the
player's ride, and committed the free fare once after exit. The radio and map
destination menus are enabled in source for local playtest. A separate clone,
`SC-Harness-20261013-194938-1275f0eb`, then booked that same cab again. It
reserved one `Base.Necklace_Gold` in the glovebox for a 340.19-tile planned
route, physically drove 367.59 tiles, let the passenger exit, and committed
the exact necklace once. This proves one repeat paid ride beyond 200 tiles;
it does not yet prove arbitrary long routes or a paid mid-ride cold reload.

The repeat pickup from the player's original position exposed a road-planner
false positive. The selected stop produced a 0.50-tile route for the saved cab;
the native driver attempted nine alternating turn legs and returned
`turn_failed` (`SC-Harness-20261013-202309-3ffa5b84`). Pickup selection now
checks the actual cab's route entry and exit against its current location and
the proposed stop. A replay skipped that degenerate route and began a
166.50-tile approach, but a later replan returned `no_route`
(`SC-Harness-20261013-204408-85cc9443`). That pickup remains unreliable.
Another repeat paid run, `SC-Harness-20261013-203802-2c54f237`, completed
337.02 tiles of physical driving and committed the gold necklace once. At that
point the cab remained parked. The later departure implementation now keeps
Markus at the wheel after delivery.

The occupied taxi ride now requests 50 km/h on clear straight roads. Other
managed companion drives remain capped at 30 km/h. The native follower looks
far enough ahead to brake for corners and obstacles at the higher speed. The
cloned 336.97-tile paid ride `SC-Harness-20261013-211143-09d452c5` measured
49.23 km/h with the wheel nearly straight, slowed through bends, delivered
the player, and committed the necklace once. An earlier trial stopped with
`route_blocked` near the pickup; the service fails safely on that outcome, but
the pickup route remains a separate reliability issue.

After settlement, Markus takes a bounded road route away from the drop-off.
The service waits for every passenger to leave and rejects any unknown customer
luggage before departure. Once the cab is at least 30 tiles away and outside
every local player's view, it stops, Markus exits, and the game's vehicle
removal function despawns that exact empty car. The ownership and fare ledgers
retire only after native removal is verified. Credit and the used first-ride
promotion survive for the next call, which spawns a new cab. If a route or
removal is uncertain, the physical cab stays recoverable instead of creating
a duplicate. The cloned paid ride `SC-Harness-20261013-213146-c2b6f347`
measured 37.58 tiles of departure travel and verified that the native cab and
driver were gone. The focused harness also verifies that a remaining rider or
customer luggage prevents departure.

Keep v2's ordinary-container payment: loose jewelry in the taxi glovebox,
seat storage or trunk, with the first completed ride free. Do not silently
take jewelry from the player's pockets or inside a bag. The fare module must
observe verified transfers or require an explicit offer if provenance is
unknown, then reserve exact physical items against a receipt. At dropoff,
commit once; on cancellation, leave the exact items available for retrieval
or preserve a refund claim. The existing car-unloading job must ignore the
service cab. A free trip cannot be consumed by a failed pickup. Paid mid-ride
reloads and interrupted transfers still need live checks before release.

Use the stock taxi's blood/damage channels if live application and save/load
prove reliable. Keep real fuel, parts, stores and damage authoritative during
each visit. Never delete a car with passenger luggage still inside.

## Defer until proved

- **Street catalogue and inter-town trips:** first prove the base/map pin
  route. The existing router's regional limits remain; page street results
  and segment long trips later.
- **Window-side pistol fire:** Markus may carry a pistol now, but native
  vehicle attacks are unverified for this non-local driver. Do not advertise
  firing from the cab until an ammo/hit/ownership live probe passes.
- **Pickup clearing:** reuse existing small-group contact behavior only after
  a door-zone safety and pedestrian test. Move a dangerous pickup instead of
  turning the cab into an unlimited zombie-clearing service.
- **Custom taxi art/armor:** stock `Base.CarTaxi` supplies the sign and yellow
  shell. Damage overlays are cosmetic until confirmed. A bullbar or custom
  armor must have real vehicle mechanics before its text promises protection.

The release gate is a complete booking → hidden approach → real ride → safe
dropoff → luggage-safe departure → reload cycle, plus ordinary expedition and
companion-driving regression tests. The Stage A live probe alone is not that
gate.
