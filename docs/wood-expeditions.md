<!-- SPDX-License-Identifier: MIT -->

# Wood collection expeditions

In Expeditions, choose **Collect wood**, a crew and a walking or driving route.
Request 1, 2, 4, 8, 12 or 24 raw logs; the default is 12. **Full load** fills
safe available cargo space with a ceiling of 256 verified log receipts. Each
expedition makes one round trip. It does not saw planks or bundle logs.

The planner searches Forest and DeepForest metadata outside camp within
1,000 tiles in bounded slices. Readable forest names describe direction and
nearby streets when available. Metadata is provisional: the crew verifies
loaded mature trees on arrival and can try up to three sites.
Driving discovery continues past inland patches that lack a suitable road stop;
its selected patches stay within 64 tiles of the parked car. Longer log carries
still require safe equipped-bag capacity.

Before leaving, a cutter collects a usable axe from permitted shared camp
supplies. Missing equipment pauses preparation and retries automatically.
The crew must be able to transport at least one log while retaining tools
and essentials. Walking uses actual inventory and equipped bag capacity;
driving crews physically carry logs to their trunk. A solo cutter also hauls.

Tree cutting uses native work animations, tree damage and physical drops.
Only verified Base.Log pickups count. Branches, twigs and tree removal alone
do not satisfy a request. New cutting stops when the request is filled, cargo
is full, the return timer expires, night policy forbids work, danger intervenes
or no usable axe remains. The crew brings back available cargo and reports
the partial result.

**Collected**, **Carried** and **Stored** are separate counts. Returning to
camp does not complete delivery. Automatic destinations prefer a permitted
Log Yard, then Construction storage, then General storage. The trip's stopped,
verified car can be unloaded after roadside fallback when it remains within
camp work reach. Distant or unavailable cargo remains pending.

Log Yards arrange up to four physical logs per tile in aligned stacks and rows,
finishing a partial stack before starting another tile. Each log stays available
for normal pickup and use. Already loaded yard stock straightens when inspected;
the placement is saved with the original items. Tying a stack still uses the
existing four-log, two-rope recipe.

Full or inaccessible storage pauses delivery for three minutes, preserves the
exact cargo and automatically tries again. **Retry wood delivery** allows an
immediate manual attempt. Delivery remains required when **Restock and resume
base duty** is off. Borrowed axes return before optional restocking.

A delivery ends without storing a log once no crew member or the loaded trip
car still holds it: you took it from the trunk, it stayed on a fallen
companion, or the companion left the group. A borrowed axe stops being owed
when its borrower no longer carries it or its source storage is unmarked.
While a companion is still loading in or the car is out of reach, the cargo
stays pending. Logs and axes from a finished delivery are ordinary items again.

Mission schema 7 saves work progress, native cargo identities, tool loans and
delivery retries. Wood integration version 2 supports at most 256 logs. Older
missions and version 1 search/fishing deliveries retain their existing limits.
Reload never creates replacement cargo when ownership is ambiguous.

The shared logging primitives also serve ordinary field clearing. Field work
keeps its Follow order, leader distance and clearing rules; expedition workers
receive their own mission context and share tree and item ownership claims.

The optional Viewpoint compatibility query reads
`viewpoint.core.View.enabled`. It suppresses overhead companion names only
while 3D is active and preserves the player's saved name-label preference.
Install the rebuilt native bridge and matching Lua payload together.

## Verification

The full project gate passed all 27 stages, including ordinary field-work
regressions and the native Viewpoint flag/exposure tests. Focused wood fixtures
cover forest discovery, tools and claims, quota contention, native ownership,
bag/trunk capacity, interruptions, death, cancellation, save/reload and delivery
retry. The actual Viewpoint mod is not installed in this test environment, so
3D rendering has not been visually checked.

Walking clone `SC-Harness-20261024-210442-c57607a6` passed 52 checks with no
failures or skips. The public mission traveled to woodland, rejected an empty
first patch, removed one mature native tree and observed four physical raw-log
IDs. It picked up the requested one log, placed that exact object in the Log
Yard and returned its exact borrowed axe to the original supply container.
Scarlet remained healthy, the car engine was off and the view returned to solo.
The trip and delivery took approximately seven minutes.

Driving clone `SC-Harness-20261024-221951-83933110` completed the public mission
with two requested logs. It rejected two empty patches, cut a real tree at the
third, physically shuttled both exact logs into the saved car's trunk and drove
home. The normal parking fallback left the verified stopped car within camp
work reach; the crew unloaded both original log objects into the Log Yard and
returned the same axe to its source. Scarlet remained healthy, the engine was
off and the companion view was released. The trip and delivery took about
eleven minutes. The final native bridge also passed all 27 project gate stages.

That cargo acceptance run explicitly enabled the quiet-site fixture, which
removed 21 nearby zombies after arrival while leaving road travel, trees,
cargo and crew stats untouched. The separate natural run
`SC-Harness-20261024-214221-d1a0c02b` reached the third forest and felled a tree,
then withdrew when zombies approached before pickup. Four real ground logs
remained, collected stayed zero, and the engine was switched off on return.
Another return-failure run preserved its two trunk logs as pending cargo when
the car was abandoned outside camp work reach. These investigations are not
reported as completed cargo-delivery acceptance runs.

The seed had no usable axe among its permitted camp supplies. The explicitly
enabled disposable equipment fixture supplied one real native axe in existing
permitted Weapons storage after finding Tools storage full. It retained the
saved equipped bag, crew, trees, vehicle, health and permissions. The unmodified
seed was also observed pausing preparation for a missing axe. These test changes
do not affect the user's save.

Reproduce each mode in a fresh cloned save with:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -WoodExpeditionProbe `
    -WoodExpeditionTravelMode walk -WoodExpeditionStockEquipment `
    -SeedSave $SeedSavePath -GameMode Rising -TimeoutSeconds 900 `
    -IsolatedSourceBridge -HiddenWindow -NoSteam
```

Use `drive` for the driving run, with `-WoodExpeditionQuietSite` to isolate
cargo acceptance from danger withdrawal. Quiet-site cleanup defaults off,
runs only after site arrival or during work, and reports each removal.
This probe expects the test seed's saved Scarlet and car SQL46.
Omit `-WoodExpeditionStockEquipment` to keep
all saved equipment unchanged. The fixture surveys real supplies first, creates
at most one axe only when missing, and equips a real empty bag only when needed
and the back slot is free. It never creates logs or trees, moves crew by teleport,
changes health or forces a mission to finish. Audit logs and queued screenshots
remain in the run's disposable cache; inspect the resulting PNGs separately.
