# Expedition place lookup probe — 27 September 2026

## Purpose

Test whether Build 42.20.4 can supply bounded expedition destination
candidates by building type and nearest street without inventing numbered
addresses. The user's source save at the Riverside gas station was cloned for
each live run. The metadata probes did not start an expedition; the later
known-place Scout did. None altered the source save.

## Implementation

`SCExpeditionPlaces.nearby(x, y, radius, limit)` queries the installed
`IsoMetaGrid.getBuildingsIntersecting` within at most 150 tiles and returns at
most 128 read-only candidate descriptions. Each candidate carries a footprint
key, bounds, center point, classified room-name set, and the existing
`SCFactions.describeLocation` nearest-street result. A police, fire, gas
station, store, or residential classification is a **candidate inferred from
room names**, not an authored business name or observed player fact. Unknown or
ambiguous room sets stay unclassified. No address number is fabricated.
Street lookup runs only after sorting and applying the requested result limit.

The center point is useful to identify a building. It is **not** guaranteed
to be inside its floor plan or to be a reachable entrance. Mission routing
must select an accessible approach independently. The footprint key is
provisional for the current map version; map updates can change it.

`SCExpeditionPlaces.loadedApproach(place, actor)` checks the building's floor
range, then tests at most 12 loaded, free exterior squares beside its actual
ground-floor footprint with the ordinary actor-aware navigator. It returns
only a scoped exterior approach. It never claims that the entrance is open,
that the interior is accessible, or that the route will remain clear later.
Unloaded edges and absent paths return distinct unavailable reasons. A
basement-only building cannot be selected as a surface approach.

`SCExpeditionPlaces.targetableNearby` is the selector-facing query. The Living
Fellows sandbox option **Expedition destination choices** defaults to **All
nearby**. It offers ground-floor buildings inferred from map metadata, marks
each `map_metadata_unconfirmed`, and omits raw room names. **Known places
only** uses `SCExpeditionPlaces.knownNearby`: a ground-floor candidate is
shown only when an actual loaded
interior square belonging to that building reports `isSeen(0)` for the player.
Its displayed type is inferred only from room names on those seen interior
squares; unseen room names cannot classify it. The returned copy omits raw
room names. This currently covers player-seen
interiors; learned locations from radio reports, annotated maps, signage, or
other save history still need their own evidence and policy.

## Live evidence

The focused cloned-save run
`build/live-sandbox-runs/SC-Harness-20260927-192126-9c60cf8b/` passed 19
checks with no failure. Querying `(6100, 5280)` with radius 80 returned 27
building records. The native metadata identified:

| Type | Sample tile | Footprint key | Distinctive room names |
| --- | --- | --- | --- |
| Police | `(6081, 5255)` | `6077:5233:6090:5265` | `armory`, `policegarage`, `policeoffice` |
| Fire station | `(6119, 5257)` | `6115:5246:6141:5266` | `firegarage`, `firestorage` |
| Gas station | `(6080, 5308)` | `6074:5299:6086:5318` | `fossoil`, `gasstore`, `gasstorage` |

All three exact buildings appeared in the bounded candidate list with their
expected classifications. The nearest street for these samples was `W Main
St`. Two ordinary residences in the same list had bedroom/kitchen room sets
and were described as houses without house numbers. The game's Riverside
`spawnpoints.lua` labels the police and fire occupational spawn tiles in the
opposite way; the room metadata was used as the classification evidence.

The first diagnostic run, `SC-Harness-20260927-191557-6db3ab48`, established
the actual room names and exposed that spawnpoint-label mismatch. Run
`SC-Harness-20260927-191821-dce91da0` made classification and bounded-query
membership explicit assertions. The final run repeated them after moving
street lookup behind the sorted result limit.
The core suite passed 47/47 harnesses, including 25 place-lookup checks; the
gameplay static suite passed 910 assertions.

## Loaded approach and known-place Scout

The floor and approach run
`build/live-sandbox-runs/SC-Harness-20260927-192948-d68f8f37/` showed that
the second police footprint at `6077:5236:6091:5265` is basement-only
(`-1:-1`). The surface police footprint is `0:3`, the fire station is `0:2`,
and the gas station is `0:0`. From the Riverside player, the native pathfinder
found an exterior approach to the fire station at `(6114, 5257)` in 55 path
nodes and one to the gas station at `(6084, 5298)` in 15 nodes. The surface
police building returned `approach_no_loaded_path` under the probe's bounded
candidate search; that is **not** proof it is globally inaccessible.

The companion-led run
`build/live-sandbox-runs/SC-Harness-20260927-193233-564abfb8/` passed 29
checks with zero failures. The original saved leader, from its own position,
resolved the same fire building to `(6114, 5257)` with a 53-node exterior
path. The ordinary Scout mission accepted that selected coordinate, walked
the actual leader and two original followers about 57.4 tiles from the rally,
observed six visible exterior squares at `(6114, 5258)`, and walked home.
The debrief recorded a complete bounded observation; the primary player
remained slot 0, the second view was released, maximum observed leader step
was 0.095 tiles, and maximum follower gap was 12.03 tiles. No setup teleport
or radio was required. This run used the existing test-only quiet zombie
fixture to isolate route and selection behavior.

The corrected knowledge query passed 40 live checks in
`build/live-sandbox-runs/SC-Harness-20260927-195536-de0447f2/`: 15 of the 27
metadata candidates had a player-seen interior square in this save. The gas
station, surface police building, and fire station remained classified from
the names of seen rooms; raw room names and basement-only entries were absent
from the projected list. A focused core check changed the only seen room to a
generic bathroom while leaving a hidden police room in metadata, and the
displayed type correctly became `Building`.

The final known-place run
`build/live-sandbox-runs/SC-Harness-20260927-195658-4f45f185/` passed 27
live checks with no failure. Its test planner selected the fire station from
`knownNearby` rather than raw metadata, rechecked a 53-node exterior path
from the original saved leader, and completed the same three-member Scout
trip. It observed six visible exterior squares at `(6114, 5257)`, reached
58.35 tiles from its start, returned beside the stationary player, and
released the second view. The largest measured update step was 0.105 tiles
and largest follower gap 12.05 tiles. The quiet threat fixture remained on.

After adding the sandbox option, the focused cloned-save run
`build/live-sandbox-runs/SC-Harness-20260927-200519-e1eebb0e/` passed every
live check. With the default option, `targetableNearby` offered 22 ground-floor
map-derived candidates in the same Riverside area; setting **Known places
only** offered 15 player-seen candidates. The internal metadata query held 27
building footprints, including basement-only records that cannot be surface
targets. Both selectable lists omitted raw room names. The source save and
launcher configuration remained unchanged. The core suite passed 47/47
harnesses and the gameplay static suite passed 910 assertions after the change.

A further read-only survey, `SC-Harness-20260927-200900-0dcacc65`, found seven
ground-floor candidates absent from the player-seen list. Two had a loaded
exterior path from the gas station. The test planner selected the nearer
reachable unvisited footprint `6156:5236:6174:5266` and its exterior approach
at `(6155, 5264)`. In the quiet-fixture three-member Scout run
`SC-Harness-20260927-201116-b31ad2dc`, the original leader walked about 82.4
tiles from its start, observed five visible exterior squares, and returned to
the stationary player. Slot 1 was released; maximum observed movement step was
0.099 tiles and maximum follower gap was 12.37 tiles. A second run with the
quiet fixture off, `SC-Harness-20260927-201548-cbd0382a`, reached the same
building, observed six exterior squares, and returned with slot 1 released.
Its maximum observed movement step was 0.169 tiles and follower gap 12.11
tiles. Neither run entered the building, proved a natural zombie encounter,
or searched its interior. Both used disposable save clones.

## Remaining gates

- The sandbox option and selectable-candidate query now exist, but no
  player-facing destination picker is built. Map-derived targets must stay
  clearly marked as unconfirmed in that future UI. Known-only currently means
  loaded player-seen interiors; radio reports, annotated maps, signage, and
  other save history are not yet knowledge sources.
- No street-to-house-number registry exists in the game API or this prototype.
  A named street can describe a selected building, but cannot resolve an
  arbitrary `23 Oak St` request.
- A building candidate is not a safe or supported expedition destination
  until a reachable approach, map ownership, bounded area admission, and
  return itinerary have passed. Local fire-station and initially unvisited
  building exterior trips now pass; door access at the unvisited building,
  interior search, observed natural danger and longer routes do not. No
  road-scale search was attempted.
- Classification needs a broader survey of vanilla and map-mod room naming,
  and a deliberate policy for mixed-use, multi-floor, and adjacent structures.

The private mission core now has `placeCandidates` and `startAtPlace`. It
rechecks the current targetable list and loaded exterior approach before
assigning the team, and saves the selected place description with its
`map_metadata_unconfirmed` or `player_seen_interior` qualifier. This is a
backend seam for the future picker; it does not change the remaining live
evidence or make interior access certain.
