<!-- SPDX-License-Identifier: MIT -->

# Choose an expedition destination on the map

Choose a squad, leader and mission in **Expeditions**, then select **Choose on
map**. Right-click a building or shoreline and choose **Select**.
The highlighted footprint or marker shows the actual destination. Selection
returns to the mission review; **Launch expedition** sends the crew.

The same picker is available from an EMMA expedition station. Ordinary map
context actions can also open a plan for a selected location.

Walking permits map targets within **1,000 tiles** of the selected leader;
driving permits **5,000 tiles**. Beyond 200 tiles, the target must be on terrain
you have visited or revealed by reading maps. The range uses the map marker;
the route may be longer and must still pass its normal checks. Driving needs
a suitable parked car, access to the road and enough fuel for both legs plus
reserve. A map marker does not confirm supplies, trees or a safe entrance.

Within 200 tiles, nearby unexplored buildings remain available with **All
nearby**. **Known places only** now accepts visited and map-revealed locations,
including buildings whose interiors you have not entered. Turning off map fog
does not make an unknown destination eligible.

**Browse nearby locations** retains the existing building and fishing lists.
**Find woodland automatically** retains the existing 1,000-tile forest search.
Automatic fishing and woodland discovery keep their existing knowledge rules.

For fishing, the picker searches within 32 tiles of the click for a plausible
bank. Check the highlighted landing point before selecting it. The crew checks
actual water and access on arrival. The minimap may be disabled.

For wood, choose **Choose logging area on map**, then click two opposite
corners. Drag to pan and scroll to zoom. The outline shows the exact cutting
area, up to **128 × 128 tiles**; choose **Use area**, **Redraw** or **Cancel**.
The entire area must meet range and exploration limits and avoid protected
camp ground. Mature native trees qualify even without Forest map metadata.

The crew works through the whole rectangle in small cells, checking actual
trees on arrival. It stops at the requested quantity, carrying limit, return
time or a safety interruption. It never cuts outside the outline or switches
forests, and returns partial cargo if the remaining cells are empty or
inaccessible. Tree counts are not promised for unloaded ground.

Driving shows a proposed roadside stop and its **64-tile hauling circle**.
The entire rectangle must fit inside it. If it cannot, move or shrink the
selection, or choose walking. Stops remain provisional until the ground loads;
crews do not move the car to expand the work area. Existing log quantities,
the 256-log full-load ceiling and storage-delivery requirements remain in use.

Escape, Back or closing the map leaves your previous destination intact.
Editing the crew, travel mode or vehicle keeps the pin and requires a fresh
review. An incompatible target stays visible with an explanation.

The turn-home choices are **1, 2, 4, 8, 12 or 24 game hours**. Travel counts
toward this allowance, so leave time for work. Existing equipment-preparation
waits pause departure; the timer does not start when work begins at the site.

Manual missions retain expedition save schema 8, with version 2 descriptors
for new logging rectangles and their work progress. Existing point targets
and three-patch missions retain their original bounds and behaviour. Reloading
preserves checked cells, borrowed axes, pending pickups and exact cargo.
