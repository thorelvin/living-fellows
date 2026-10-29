<!-- SPDX-License-Identifier: MIT -->

# Computer hardening and Larchfield BIOS

29 October 2026, on `living_fellows/0.26.75` after `5145af5c`.

The original Larchfield bitmap appears before the existing POST diagnostics.
A 750 ms stencil reveal, restrained scanlines and a 1.4 second firmware stage
lead into the unchanged 3.2 second memory/hardware sequence. EMMA starts
afterward; Enter skips both stages. The existing boot recording retains its
owned handle and can finish over the welcome screen. Missing or failed image
draws release clipping and fall back to text rather than stopping startup.

The asset is loaded once and drawn with the existing keyed monochrome logo
shader. Green, golden sand, aquamarine and purple use the same bitmap with
their own text palette; its black backing does not become a separate panel.
Animation runs inside the current CRT layout and creates no player view,
per-frame world queries or additional native bridge methods. Asset provenance
and the generation prompt are in [the art record](terminal-bios-art.json).

## Hardening findings

- A live window could process more input after its saved access table was
  replaced, then overwrite replacement memory on close. Input and the
  watchdog now validate the live record, computer type and main operator.
  Stale windows close without exporting their old notes. Direct opening and
  timed use also require an actual computer. Radio cleanup exceptions cannot
  prevent keyboard release and ordinary window removal.
- Hardware validation admitted non-finite generations, item IDs and weights,
  and did not validate saved audio/power scalars. Those records now fail
  validation before native serialization or transfer. The saved payload is
  retained, furniture pickup is refused, and invalid or unpowered receiver
  projections are stopped.
- Radio stop discarded its scan lease before restoring and saving the old
  frequency, while furniture pickup ignored a failed restoration. Failed
  restoration now keeps a pending retry, shown as **Restore pending**; polling
  cannot advance it, another scan cannot replace it, and pickup or factory
  reset cannot discard it.
  Successful retry releases the lease. Intentional external retuning retains
  its previous protection against overwriting another owner's channel.

Regressions cover replaced records and notes, changed operators/objects,
cleanup errors, non-finite saved values, refused pickup, failed retuning and
retry, all four BIOS palettes and failed image draws. Existing power-loss,
confirmation, exact-item transfer, radio, security, reset and keyboard tests
also pass.

The additional serialization-failure test verifies that a channel restored in
the native receiver is not released until its exact handset payload is saved.
Factory reset preserves both OS and radio memory while that save is pending;
retry after the storage failure clears it normally.

The full project gate passed **29/29 stages**, with 243 payload Lua files
compiled in normal and debug modes. Final stages took 122.5 seconds, 126 seconds
overall. The bridge binary and save schemas are unchanged by this pass.
The gate record is [retained here](../artifacts/emma/native-acceptance/terminal-bios-project-gate.log).

## Native acceptance

`artifacts/emma/run-terminal-bios-native.ps1` uses the existing disposable
clone, a real powered desktop and the native Use computer action. It verifies
the image reveal, native keyed renderer, POST ordering, EMMA handoff, Enter
skip, ordinary close and absence of a second player. Screenshots come from
the game's framebuffer. Native aquamarine, sand and purple captures were
inspected; green tinting and responsive layout are covered by UI tests.

- [Reveal](../artifacts/emma/native-acceptance/emma-bios-reveal-aqua.png)
- [Aquamarine BIOS](../artifacts/emma/native-acceptance/emma-bios-aqua.png)
- [Golden sand BIOS](../artifacts/emma/native-acceptance/emma-bios-sand.png)
- [Purple BIOS](../artifacts/emma/native-acceptance/emma-bios-purple.png)
- [POST](../artifacts/emma/native-acceptance/emma-bios-post.png)
- [EMMA after startup](../artifacts/emma/native-acceptance/emma-bios-welcome.png)
- [Native BIOS results](../artifacts/emma/native-acceptance/terminal-bios-evidence.log)

The existing native radio scenario was rerun against this hardening pass. Real
RF distribution rejected wrong-channel and out-of-range transmissions and
accepted an in-range transmission on the tuned channel. Scan/hold, native
presets, notebook input and handset blob identity passed. Removal restored the
original frequency, unavailable-radio commands remained safe, and remounting
preserved the same handset. See [the radio results](../artifacts/emma/native-acceptance/terminal-bios-radio-evidence.log).

The BIOS runner disables native audio; sound lifecycle is covered by the
existing UI sound tests. The older FMOD fixture now schedules its POST check
from the configured duration rather than a hard-coded timestamp. This pass
does not claim a new native audio test or new expedition-return acceptance.
The main game profile and user saves are outside these cloned runs.
