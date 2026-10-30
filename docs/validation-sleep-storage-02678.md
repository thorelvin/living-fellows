<!-- SPDX-License-Identifier: MIT -->

# Sleeping and shelf artwork, 0.26.78 follow-up

30 October 2026, based on `b5f33d1f`.

The supplied Support report shows four residents at fatigue 0.829–1.0. Two
sleep checks report `no_available_bed`; two report `searching`, while the actors
read, sit, watch television or rest on the floor. The user confirmed marked
Rest areas on both floors. The report does not include the beds' tile models
or their access geometry, so the exact tester layout has not been reproduced.

## Bed discovery

Discovery required `SeatingManager.getTilePositionCount(object) > 0` even for
sprite-grid mattresses. Native inspection found intact bunk-bed tiles
`furniture_bedding_01_38` and `_39` with zero chair positions and valid
`BedGeometry.entry` results. They were classified as unavailable. Native
`ISGetOnBedAction` uses the mattress grid, not chair positions.

Explicit bed metadata plus a sprite grid now admits bed discovery; generic
chairs still require seating positions. The existing geometry, paired-half,
occupancy, safe-entry, danger and sleep-eligibility checks remain in force.
Gameplay tests cover a zero-chair-position bed, successful selection, a missing
half and decorative bed names without native geometry.

The native standard-bed scenario passes lying sleep, wake, get-up and walking
clear without recovery, with health 100. Its speech and zoom checks also pass.
The focused zero-chair bunk-bed scenario independently passes `Bob_Asleep`,
wake and get-up with health 100, retained collision and no actor recovery.
Its sleeping screenshot was inspected and shows the body on the lower
mattress. The tester's actual multi-floor camp still requires a retest.

The first native attempts exposed fixture limitations: the observer blocked
an entry in the seed bedroom, recovery could retain the old camp order when
testing another house, and the small bunk room lacked the original walk test's
two setup tiles. These were not treated as successful acceptance. The fixture
now logs rejected bed discovery, establishes its current actor/order after
placement, and has a focused zero-chair-position sleep/wake mode. The standard
scenario retains its longer walk-away and speech/zoom checks.

## Shelf artwork

Verified direct transfers bypassed vanilla
`ISInventoryTransferAction.perform`'s dirty-pane and
`ItemPicker.updateOverlaySprite` calls. Items could therefore be owned by the
shelf while its old empty artwork stayed visible.

After verified transfer or settled rollback, both native inventory panes are
invalidated and each world-container parent's overlay is refreshed once.
Characters and nested bags do not receive shelf overlays. This also repairs
the visuals when an already-transferred receipt is rechecked. Visual/UI errors
cannot undo or repeat the verified ownership transfer. Display follows the
game's normal overlay rules; this does not add new artwork to unsupported
shelf models.

The 17-check regression fails on the original empty-shelf case, then passes
with the fix. It covers deposits, last-item withdrawals, shelf-to-shelf moves,
rollback, idempotence, nested bags and failing UI/overlay callbacks. The native
API contract verifies the overlay and container methods. No live shelf
screenshot acceptance is claimed.

All 29 project stages passed in 160 seconds, including persistence, gameplay,
UI, ownership, navigation, combat, both adapters, packaging and installer
transactions. All 244 payload Lua files compile normally and in debug mode.
The final native-fixture-only adjustments do not change either production
module. The bridge binary, protocol and save schemas are unchanged.

The raw gate log, bed results and screenshots were removed from the tree in
0.26.80, because the repository does not keep playtest output. They remain in
history under `artifacts/bed-storage-02678/` at commit `d08b5a4c`.

Installed locally with the game closed, preserving the private native setup.
Installed source hashes match the verified files:

- SCDowntime.lua: `bbb8ec3117ad41b1138cf9224345361e3f5a0aa42da08db95f1cc1af73bb7dbb`.
- SCGameplayUtil.lua: `46ffcc398c56f6f38c273bb93e34b4966275adf870c182915d74efdb3b2cfc1c`.

These functional checks and the local installation preceded the metadata
bump for [release 0.26.79](validation-release-0.26.79.md). Workshop publication
is separate from this Git release.

## Five-minute natural observation of the user's latest save

At the user's request, a fresh copy of `LF-Skills5-Test-2026-10-29` ran at
normal game speed for 300,645 ms, with 298 observation samples. About 1.33
game hours elapsed. The save's enabled mods were retained. Neither companion
stats/orders/positions nor the observer's health were changed by the harness.
All 3,430 original save files match their pre-run SHA256 hashes.

None of the original four companions slept. Their tiredness began near zero
and ended at Tess 5.09%, Jill 4.75%, Sanghwa 4.13% and Xian 4.29%. Jill,
Sanghwa and Xian briefly used ordinary sitting activities. No bed sleep was
requested while they remained below the 30% minimum. A new wandering actor,
Lev Overbeck, also appeared naturally during the observation and did not sleep.

This local save predates the fatigue-persistence fix and omits saved fatigue
for all four companions. The natural observation therefore does **not**
reproduce the exhausted playtester case or establish automatic sleep at high
tiredness. The separate native standard-bed and bunk-bed checks above exercise
sleep entry and wake directly.

Raw summary, telemetry and events are in history at `d08b5a4c`, under
`artifacts/bed-storage-02678/natural-observation/`.
The full disposable world and console remain under
`build/live-sandbox-runs/SC-Harness-20261030-082613-bbd3364b`.

## Thirty-five-minute natural observation

The user requested a longer run. A fresh copy of the same local save ran at
normal speed for **2,100,124 ms**, with 2,080 samples and about 9.33 game hours
elapsed, from approximately 13:44 to 23:04. There were no forced companion
stats, orders, positions or observer healing. All 3,430 original save files
again match their pre-run SHA256 hashes. The runner timeout now permits long
observations with loading/exit allowance.

**Sanghwa autonomously entered bed sleep at about 32 minutes 32 seconds.**
The logs identify `downtime/sleeping_on_bed`, `rest_bed/waiting`, native
`isAsleep=true` and `isOnBed=true`. His tiredness peaked at 30.6% and declined
to 26.4% by the end. The automatically captured screenshot was visually
checked: his body is lying on the bedroom mattress, and his companion row
shows `Activity: Rest bed`.

Tess ended awake at 35.2%, Jill at 30.6% and Xian at 30.9%. Tess retained an
active farm job. The current policy permits ordinary sleep above 30% between
jobs; interrupting an owned job for exhaustion uses the 82% threshold. This
run confirms natural bed selection, entry and fatigue recovery for one saved
companion. It does not exercise 100% exhaustion or a full natural sleep/wake
cycle; Sanghwa was still asleep when the observation ended.

Raw summary, telemetry, events and screenshot are in history at `d08b5a4c`, under
`artifacts/bed-storage-02678/natural-observation-35min/`.
Full world and console:
`build/live-sandbox-runs/SC-Harness-20261030-083849-dd531c84`.
