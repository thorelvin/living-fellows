Native PZO companion restore regression
======================================

Run scripts/Test-PzoCompanionRestore.ps1 under Windows PowerShell 5.1.
Prerequisites: the pinned Project Zomboid 42.22.2 runtime, Java 25 JDK, Python,
the unmodified official PZO V2.2 PZOptimEngine.jar, a complete single-player
seed save, and an owned copy of the game's media directory.

The PZO JAR must have SHA-256:
026de0512c6058e00f2df1f30d68c1acddeb6efee27877a6015a49f1da2d4d5b

Create the media snapshot once in a test directory, not inside the installed
game. Copy the complete media tree; a directory junction alone is insufficient
for the game's asset scan. Write snapshot-complete.txt beside that media folder
containing 42.22.2 after the copy completes. The runner makes ordinary directory
trees with hardlinks into this owned snapshot, never into installed media.
Keep the snapshot and the checkout's build directory on the same volume.

Example (replace the three input paths with existing local inputs):

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-PzoCompanionRestore.ps1 -PzoJar "<PZOptimEngine.jar>" -SeedSave "<complete save folder>" -MediaSnapshotRoot "<owned snapshot>/media"

The current checkout supplies the payload unless -PayloadProjectRoot is given.
Build-NativeBridge.ps1 -InstallIntoPayload must have produced its matching JAR.

The test keeps com/pzoptimizer/PZOEntrypoint as the native executable's main:

1. PZO discovers an approved LF bridge, exposes it to the real game and restores
   a native companion. The probe captures its complete record with marked cargo.
2. In the disposable PZO config, block that bridge. Import the captured record,
   wait 170 real seconds, then require waiting_environment, zero consumed attempts
   and the exact original record through synchronous and scheduled production saves.
   Invoke the stock game save to persist the real GlobalModData binary.
3. Approve the bridge in the fixture and restart the same save without reseeding
   GlobalModData. Require the complete saved record from disk, one healthy native
   companion with the same ID, and exactly one matching cargo receipt.
4. Disable PZO's Java loading in the fixture. Reach the real main menu with PZO
   active and SCBridge absent. This control must not be bypassed.

Fixture approval choices are explicit test inputs. The runner never edits the
user's PZO config or approves a JAR in the user's profile. It does not drive the
approval dialog. The optional PZO Lua settings mod is omitted; require_lua_mod is
false only in the clone. PZO's agent, discovery, approval decisions and entrypoint
dispatcher remain active and are checked in the captured PZO log.

The only test Java entry advances the game's click-to-start screen. It never
starts the LF bootstrap, exposes SCBridge, changes zombie navigation or supplies
a replacement Instrumentation object.

Fixtures and phase evidence remain under build/pzo-restore-*. The runner checks
the source save's full content fingerprint and installed launcher, bridge and
game-JAR hashes after the run. Native processes are stopped only when they belong
to that fixture's executable. Source assets, installed mods and player saves are
not installed into or opened for writing.

The retained game copy contains JRE and license junctions. Do not recursively
delete it with a cleanup tool that follows directory junctions.

Exit status is the result. The whole test must exit 0; an assertion failure or
timeout exits nonzero, including when some earlier phases passed.

Passenger reading regression
----------------------------
Run scripts/Test-PzoPassengerReading.ps1 with the same PzoJar, SeedSave and
MediaSnapshotRoot inputs. It uses the same isolated native PZO launcher and
loader, then creates a native car, companion driver, companion reader and a
primary player in another passenger seat. The car drives eight metres while
the production downtime controller keeps its native reading action active.
The pinned 220-page Carpentry volume must grant one 11-page chapter, retain
the exact marked book, and grant no extra pages when a second chapter is
interrupted by a native vehicle exit. Driver exclusion and a 60-second
post-interruption soak are included. The probe honors the production watchdog
window for vanilla moodle-adjusted action timing and records native maxTime.

Add -RevertReadingPose for the causal negative: only the pose opt-in is removed
from the staged disposable SCDowntime.lua. That run must exit nonzero and its
receipt must identify protected_pose_moved during vehicle motion. This switch
never changes the checkout or installed mod. Ordinary runs must exit zero.
The full seed-save and installed launcher/bridge/game-JAR fingerprints are
checked after either run. Receipts, console, PZO logs and the exact staged
payload remain under build/pzo-passenger-*.

Cleaning tools and storage regression
------------------------------------
Run scripts/Test-PzoCleaningStorage.ps1 with the same PzoJar, SeedSave and
MediaSnapshotRoot inputs. It creates four real crates on the field used by
the native tool-storage regression. Native Mop and Broom must retain their
Weapon/HouseholdWeapon game categories while both LF classifiers choose Tools.
The real supply planner must find a mop deliberately filed under Weapons; a
native companion must borrow it and bleach, remove real stains, spend one
cleaning dose and return both exact loans. Ordinary sorting jobs, one per item
type, must move that mop and a broom filed under Ammunition into Tools. General source
stays empty and a fifteen-second soak checks that the tools remain put.

Add -RevertClassification for the causal negative. It removes only the two
classification changes from the staged disposable Lua. The native classifier
assertion must fail and the script must exit nonzero. Both runs preserve the
checkout, installed game and complete seed-save fingerprint; evidence stays
under build/pzo-cleaning-*. The controlled probe holds unrelated AI choices but
honors Decision's normal action-pacing gate and the action supervisor before
admitting BaseWork; it does not shorten pauses or clear native ownership.

The native probe also rejects any navigation failure with action_pacing as its
cause. Add -RevertRepaymentPacing (independent of -RevertClassification) to remove
only the in-transaction repayment wait from the staged BaseWork. Native cleaning
must then fail that assertion at completion; normal runs must exit zero with no
such false path rejection. Both negative switches preserve the checkout.

Storage category hardening regression
------------------------------------
Run scripts/Test-PzoStorageCategories.ps1 with the same PzoJar, SeedSave and
MediaSnapshotRoot inputs. It checks every native instance against the 0.27.40
loadout-role baseline, 838 explicit shelf-purpose cases, and the production
floor-intake, car-unloading and logistics destination selectors. Native capacity
refusals remain refusals, including debug placeholders which reject all crates.
They are counted separately; classification is still required for those items.

Sixteen real registered crates provide the ordinary categories and intake/output
shelves. A native quartermaster sorts thirteen representative item types from
General source into their dedicated shelves, with one ordinary homogeneous job
per type. Exact item identities, native ownership, empty intake/output, worker
health and a fifteen-second stable-placement soak are required. The controlled
work driver honors action supervision and ordinary action pacing.

Use -AuditOnly to omit physical sorting. Use -BaselineClassifiers -AuditOnly
for the causal negative: the wrapper stages only SCBaseWork and SCLogistics
from commit 0951a9fe into the disposable payload. That commit must be available
locally. This run must exit nonzero on "Base.TireIron expected tools, got weapons";
an unrelated failure is not an accepted negative. Ordinary runs must exit zero.

Evidence remains under build/pzo-storage-hardening-* with raw catalogue output,
progress, final receipt, PZO/console logs and the staged payload. The complete
seed save and protected installed-file fingerprints must remain unchanged.
The standard JRE/license junction cleanup warning above also applies here.
