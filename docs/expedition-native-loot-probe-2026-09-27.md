# Exact native loot in the remote split-screen area

The private Build 42.20.4 probe used a disposable clone of the Riverside save.
It moved an original saved companion to a remote, loaded site for this test.
The relocation was a test fixture; it was not a completed travel mission.

In `SC-Harness-20260927-041413-1811a3c0`, the existing Encounter search
owner selected `Base.WeldingMask` with native item ID `2090704567` from a
stocked world container at `6580,5328`. The source initially contained that
exact Java item. After the native loot action, the source no longer contained
it, the companion inventory held the same object and ID, and
`SC.Encounter.status.lastLoot.verified` was true. The item was marked in
modData with the run token solely for this persistence probe. The companion
inventory snapshot was saved successfully.

The verifier cloned that saved run and reloaded it in
`SC-Harness-20260927-043509-89581eb9`. The saved document had exactly one
marked item on the same companion ID. The Riverside player then visited the
remote area, loading 3,721 ordinary world squares and 54 containers. There
was exactly one marked welding mask in that companion's restored inventory,
no marked copy in those containers, and no world copy with the original native
item ID. The restored inventory item received a new native ID, as normal item
restoration recreates the Java object. The player retained slot 0 and the
companion was active after visitation. This satisfies the fixed-site W05
source-debit, save, reload, and visit gate.

The first restart initially showed three active records at Riverside because
the remote companion's saved square was not loaded. That is a deferred restore,
not evidence that the member was lost. Player visitation loaded the square and
the record materialized with its item. This does not implement automatic
expedition restart or prove W08 interruption safety. Travel, return, unload,
and roster persistence remain separate gates.

Events and console logs for both runs are retained under
`build/live-sandbox-runs/` with the run IDs above. The original Riverside save
and installed launcher were not modified.

A later joined local run, `SC-Harness-20260927-145358-d8448d70`, started
beside the player, walked the saved leader and two followers to a stocked
Riverside cupboard, looted one exact native `Base.FiberglassTape`, walked
back, and released slot 1. Its source count fell from 14 to 13 and the
same native item ID (`1367551867`) remained in the leader's inventory at
home. This closes the local travel/search/return integration probe; the
long remote mission and save/reload of cargo acquired on that journey still
need their own proof.
