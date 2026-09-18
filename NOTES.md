# Engine notes and evidence

What the mod relies on in Project Zomboid **42.20.4**, how each fact was
established, and what is still unproven. Everything below was read from the
installed game at
`C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid` — shipped
`media/lua` sources, and `javap` disassembly of `projectzomboid.jar` where the
behaviour is in Java.

---

## Verified by reading the shipped game

### Item eligibility

`client/ISUI/ISInventoryPaneContextMenu.lua:199` — the mod reuses vanilla's own
predicate rather than keeping a type list that would drift:

```lua
testItem:getScriptItem():isItemType(ItemType.RADIO)
  and testItem:getDeviceData()
  and testItem:getDeviceData():getIsPortable()
```

### Control path

`client/RadioCom/ISRadioAction.lua`:

```lua
ISRadioAction:new(mode, character, device, secondaryItem)
  maxTime = 30, stopOnWalk = false, stopOnRun = true, ignoreHandsWounds = true

isValidToggleOnOff : getIsBatteryPowered() and getPower()>0 or canBePoweredHere()
isValidSetChannel  : getIsTurnedOn() and getPower()>0
isValidSetVolume   : getIsTurnedOn() and getPower()>0
```

Queued with `ISTimedActionQueue.add(...)`. `device` for a handheld is the `Radio`
`InventoryItem` itself, which is what the session binds to.

`RWMPanel:doWalkTo()` (`RadioWindowModules/RWMPanel.lua:43`) returns `true`
immediately when `deviceType == "InventoryItem"` — a carried radio has no
proximity requirement. The real gate is possession, so `Device.heldBy` checks
`item:getContainer():isInCharacterInventory(player)`.

### Channel units

kHz integers. `RWMGeneral.lua:80` renders `getChannel()/1000 .. " MHz"`, and
`RWMChannel.lua:398` sets `frequencyDivider = 1000`. Range is per-device via
`getMinChannelRange()` / `getMaxChannelRange()`.

The 0.2 MHz step comes from the preset editor:
`RWMChannel.lua:138` calls `editPresetPanel:setValues(..., 0.2, 2)` in MHz,
i.e. **200 raw units**. See README for why the mod tunes on that grid directly.

### Volume

0.0–1.0 float, quantised by the volume bar's own step count
(`RWMVolume.lua:82,121`). Mute is a *separate* action mode with its own sound
and restore level, so the mod does not reach 0 via `SetVolume` and does not
expose mute at all.

### Two vanilla defects the mod must not rely on

1. `isValidSetChannel` / `isValidSetVolume` / `isValidMuteMicrophone` all read
   `if (not self.secondaryItem) and type(self.secondaryItem)~="number"` where
   the author meant `or`. A truthy non-number therefore passes and reaches
   `setChannel()` / `setDeviceVolume()`. `isValidSetChannel` also rejects a
   legitimate `0`. **Every value is validated in `PZRL_Device` before an action
   is constructed.**
2. `stopOnRun = true` means a sprinting player cancels an already-accepted
   action. Reported as `cancelled`, never `applied`, and never retried.

### File sandbox

From `javap` on `zombie/Lua/LuaManager` and `LuaManager$GlobalObject`:

- `getFileWriter(name, create, append)` returns `null` unless the name contains
  no `..` **and** its extension is in
  `LuaManager.ALLOWED_FILE_EXTENSIONS = Set.of("ini","cfg","txt","log","json")`
  — case-sensitive, compared without the dot. Hence `.txt` everywhere.
- `getFileReader`, `getFileInput` and `getFileOutput` check **only** the `..`
  guard. The extension allowlist is not a security boundary.
- Everything resolves under `LuaManager.getLuaCacheDir()` =
  `ZomboidFileSystem.getCacheDir() + "/Lua"` → `<userdir>\Zomboid\Lua`.
  Parent directories are created, so `PZRL/<file>.txt` is a valid name.
- Both readers and writers are explicitly **UTF-8**
  (`StandardCharsets.UTF_8`), so no encoding negotiation is needed.
- `LuaFileWriter` exposes only `write(String)`, `writeln(String)`, `close()`.
  **There is no `flush()`** — `close()` is the flush, so every write is
  open → write → close.
- There is **no rename and no file-delete API** anywhere in `GlobalObject`.

Consequences, which drive `PZRL_Mailbox`: the mod cannot publish atomically.
`getFileWriter(name, true, false)` truncates on open, and the interval until
`close()` is a window in which the host can read a partial file. The mod
therefore alternates between `state_a.txt` and `state_b.txt` and never truncates
the slot holding the newest complete document; the host takes the highest
sequence that passes framing, length and checksum. The host *can* write
atomically (`os.replace`), so the single `cmd.txt` needs no slots.

### Globals used

All confirmed present in `LuaManager$GlobalObject`:
`getTimestampMs()` (= `System.currentTimeMillis()`), `isGamePaused()`,
`isClient()`, `isServer()`, `getNumActivePlayers()`, `getSpecificPlayer(int)`.
Events `OnTick`, `OnGameStart`, `OnPlayerDeath` and
`OnFillInventoryObjectContextMenu` all exist in `LuaEventManager`.

---

## Tested

- **Kahlua compile gate** — all six mod `.lua` files compile in the game's own
  VM via `projectzomboid.jar`.
- **Kahlua behaviour gate** — `tests/codec_harness.lua` runs inside that VM.
  Besides the codec's own rules it asserts that Kahlua's framing and checksum
  match the Python host's **byte for byte** (hardcoded constants from
  `pzrl_host.checksum`). Confirmed the harness fails when an expected value is
  wrong, so a pass means something.
- **Host end-to-end** — `tests/test_host.py`, 98 checks against the real HTTP
  server over a temporary mailbox: command round trip, torn-write recovery,
  staleness, credential disclosure, broker single-flight and idempotency,
  outcome recovery, target identity, hostile input, and protocol mismatch.
- **Live path** — with the host running against the real
  `C:\Users\thore\Zomboid\Lua\PZRL`, a hand-written state document produced the
  correct page state, a `set_channel` produced a well-formed `cmd.txt`, and
  those exact bytes were then parsed successfully **inside Kahlua**.

---

## Not tested — needs the game running

Everything where the mod touches the engine. These paths are written against
verified signatures but have not been executed:

- `ISRadioAction` actually applying a change, and the postcondition observer
  seeing it. (The volume tolerance is no longer the ±0.05 guess described in
  earlier versions: `DeviceData` stores the float it is given, quantisation is
  a display concern in the volume bar, so the window is now half the protocol's
  three-decimal precision. See the 0.3.0 table below.)
- `Device.heldBy` against a radio in a nested bag, in the hotbar, and equipped
  in a hand slot. Only the plain-inventory case is reasoned about.
- Whether `getIsPortable()` is true for every handheld the player expects
  (walkie-talkie vs HAM).
- Frame cost of the synchronous `getFileReader`/`getFileWriter` calls at 4 Hz
  and 2 Hz on the game thread. **No measurement has been taken.** If it stalls,
  reduce the cadence — do not add a Java bridge.
- `stopOnRun` cancellation producing `cancelled` rather than a hung pending.
- Behaviour across save reload, player death and split-screen refusal.

The first playtest should watch the console for `[PZRL]` lines and check
`Zomboid\Lua\PZRL\` fills with `state_a.txt` / `state_b.txt`.

---

## Deliberately absent

No audio of any kind. No received-text captions: `OnDeviceText` in 42.20.4 is
`(_guid, _interactCodes, _x, _y, _z, _line)` where `_guid` is a *media-line*
GUID used for `isKnownMediaLine` de-duplication and the coordinates are the
speaking device's position — which for a carried radio is just the player's
position. `DeviceData.currentMediaLine` is a protected field with no accessor.
So **the adapter investigated here** has no way to attribute received text to a
specific device, and the feature is not offered rather than offered wrongly.
That is a limitation of this event path as inspected on 42.20.4 — not a proof
that no future approach could work.

No preset creation, editing or deletion: the preset list is the player's saved
data, and a mod has no business rewriting it to reach a frequency.

---

## Security fixes

### BF-01 — the manifest published the pairing key (fixed in 0.2.1)

`/manifest.webmanifest` is served without authentication and carried the key in
`start_url`, so any device that could reach the port could read the credential
without scanning the QR. Introduced when the home-screen install support was
added, because a standalone launch needs `start_url` to work and the key was
the obvious way to make it do so.

Fixed by serving one credential-free manifest to every caller and letting a
standalone launch re-use the key the page already stored, with in-page
re-pairing when it has none. Keys are now 128-bit, and any key shorter than
that is treated as exposed and retired on the next start.

Covered by tests: every public route is swept for the key (including error
bodies and headers), the manifest is asserted byte-identical for anonymous and
paired callers, and the migration/rotation paths are exercised directly.

---

## Reliability fixes (0.3.0)

Addresses BF-02 through BF-10 of the 0.2 review. What changed, and what is
still not proven:

| ID | Change |
|---|---|
| BF-02 | `host/pzrl_broker.py`. One outstanding command, admitted under a single lock. Idempotent by client request id; the same id with a different payload is refused. Receipts survive the response and are fetchable at `/api/result`, so a phone that slept through an outcome recovers instead of resending. The active receipt is persisted before emission, so a crash around the file replace is reconciled rather than forgotten. Envelopes carry an acceptance deadline the mod enforces. |
| BF-03 | The mod keeps the actual `ISRadioAction` via per-instance overrides — no global patch, no touched game files. `applied` now requires the owned action to have run *and* the device to show the requested state. Power re-reads immediately before toggling, so a manual flip completes as a verified no-op instead of inverting. Queue-wait and executing time are separate, and both freeze while paused. An unestablished outcome reports `unknown`, never `cancelled`. |
| BF-04 | Every mutation carries the epoch and binding the browser displayed; the host compares rather than substituting current values. The pending record captures the exact item, player and binding. Preset clicks carry the list revision and expected frequency, so a reordered list gives `stale_preset`. `controlRevision` now tracks observed controllable state and still ignores battery drain. |
| BF-05 | Command sequence starts above the highest value on disk instead of from the clock. State identity is (epoch, sequence). An existing file is *unverified* until a heartbeat advances, so yesterday's mailbox with the game closed leaves controls disabled. The POST path enforces staleness, pause and link status. A real OS lock on the mailbox directory stops a second host. |
| BF-06 | `close()` is the flush boundary, so its failure is a failed publication and the A/B slot does not rotate. Consecutive failures are counted separately from lifetime diagnostics and reset on success; the threshold now triggers bounded backoff with retry instead of permanent shutdown. |
| BF-07 | One awaited poll with a timeout and generation check, so a slow response cannot restore state after a rebind. Preset buttons are included in `disableAll()`. Receipts are processed before radio rendering, so results resolve after an unlink. Keyboard volume commits; a cancelled dial gesture discards its draft. |
| BF-08 | Command type is validated before the set lookup (an array used to raise). Non-finite and oversized numbers refused, protocol version enforced at both ends, auth header validated before `compare_digest`, `Host` checked against what this server serves and `Origin` against that. |
| BF-09 | Scheduling is by elapsed milliseconds, not callback count: 250 ms commands, 500 ms state. At most one due operation per callback, so resuming from a stall cannot burst file I/O. |
| BF-10 | Off-grid nudges step to the next *legal* grid point (88500 → 88600 / 88400). An unreadable channel range is omitted rather than exported as 0..0. Power is modelled as battery / mains / unpowered / unknown, and only the first shows a percentage. |

### Still not verified against a running game

The owned-action work is the largest untested surface. Specifically:

- That per-instance overrides on `ISRadioAction` survive `ISTimedActionQueue`'s
  handling — the methods are shadowed on the instance, which is sound Lua, but
  it has not been executed in the engine.
- Whether `forceStop` or `stop` is the correct cancellation entry point in
  42.20.4, and whether stopping an action mid-queue is safe.
- Whether a mains-powered radio can report `getPower() == 0` while working,
  which would make the tuning/volume guard refuse a working device.
- The queue-wait and executing timeouts (20 s / 8 s) are chosen, not measured.
- Nested bags, hotbar and equipped slots for possession.
- Frame cost of the file I/O at the new cadence. **Still unmeasured.**

The automated gates cover the transport, protocol, broker and browser logic
against fakes. A passing gate here does not prove an engine hook is correct.
