<!-- SPDX-License-Identifier: MIT -->

# LARCH/WAVE radio desk

28 October 2026, `living_fellows/0.26.74`, after `1aae8165`.

The program is a page inside the existing terminal frame. Mounting a working
two-way radio exposes it through Local services; `open radio` also opens it.
The five terminal-home shortcuts remain unchanged. Radio Desk has six controls
per main page, using three columns at wide sizes and two at narrower sizes.
Presets, heard stations and notebook entries are paged. Native framebuffer
inspection corrected the notebook button height so its text fits the border.

`SCTerminalRadio.lua` owns bounded software memory, reception and scan state.
`SCTerminalRadioUI.lua` owns presentation, commands and hit testing. Native
state is polled every 250 ms while the page is active; explicit user commands
revalidate and refresh it immediately. Rendering reads
cached values and animates 24 segmented bars, peak caps, waveform or reception
blocks. The visual is driven by actual receive activity, not PCM/FFT analysis.
It uses the current phosphor palette, including purple, and adds no bitmap
assets, external service or hosted model.

The installed 42.21.0 `IsoWaveSignal.AddDeviceText` implementation supplies
`guid, codes, x, y, z, text, device` to `OnDeviceText`. The handler binds the
exact native receiver object, mounted item, generation and powered computer;
matching coordinates alone are insufficient. Static channel catalogues are
not enumerated for discovery. A station name is consulted only after actual
reception. Recorded-media entries do not discover live channels. Received
text is displayed as data and cannot execute EMMA commands.

The native handset owns tuning, presets and microphone state. Its mounted
payload retains exact item identity; the existing hardware serialization owns
all transfers. Speaker volume uses the existing saved monitor-volume setting.
Radio software memory uses the optional `movableData.LF_LarchWave` schema-1
bucket: 48 snippets of at most 360 characters, 32 heard frequencies and one
bounded acknowledged report. No native receivers or actors enter persistence.
Factory reset clears this bucket while preserving hardware and native presets.

Scanning uses saved presets or 200 native-unit steps (0.2 MHz), with three
real seconds per position and a 5,000-position ceiling. It never transmits
discovery pings. Actual reception holds a frequency; Continue advances even
while that reception remains active. A previous channel's decaying signal
flag cannot invent a discovery on the next channel. Closing, leaving, saving
or furniture pickup stops a scan and restores its previous tuning when the
same mounted item still owns it. Power loss restores configuration where
possible. Hardware installation/removal stops the scan before changing its
generation or serializing the transferable handset. External tuning and changed missions invalidate
the old scan; no removed radio is retuned through a stale reference.

Active missions default to the team channel and require confirmation before
scanning. Tickets bind the exact receiver, item, generation, channel and
mission, in addition to the existing window/access checks and expiry. Finished
missions do not retain scanning restrictions. Report, recall and Marcus
shortcuts delegate to existing checked station services and require Y/N.
The Last report view contains only an acknowledgement at this PC, rather than
exposing another station's cached expedition report outside camp.

Automated UI tests cover actual-shaped device presets, rename/limits, tuning,
speaker/microphone separation, scan stepping and hold, Continue, external
retuning, range limits, missing/broken hardware, power loss, changed
generation, mission consent/replacement/completion, exact-device reception,
recordings, bounded history, inert received instructions, local reports,
factory reset and serialization-shaped persistence. Five viewport sizes cover
the radio, scanner, audio, station list, notebook, reading, team and library
pages. Drawing and throttled updates are checked for zero extra native reads.

Native acceptance uses the existing disposable cloned save, a real powered
desktop and its exact mounted handset on game 42.21.0 with bridge protocol
`42.21-isocompanion-24`. Inputs enter through the terminal. Fixtures use the
native receiver text path to verify the device event and animation, scan hold,
native preset rename, keyboard notebook reading, serialized handset ID/presets
and reopen persistence. Seven 1280×720 captures cover bars, waveform, scan hold,
notebook, an entry, Team / Marcus and purple. No expedition or taxi was
launched, no secondary view was created, and full furniture movement or
disk-save/relaunch was not repeated in this acceptance run. Actual report and
taxi delivery remain the existing services' responsibility; their UI routing
is tested with checked service spies, not claimed as a new live journey.

An additional native `ZomboidRadio.DistributeTransmission` check passed:
wrong-frequency and out-of-range traffic did not enter the notebook, while
an in-range transmission on the selected frequency did. The fixture sender
uses different X and Y coordinates from the receiver because vanilla's
self-transmission suppression rejects a source sharing either coordinate.
An earlier fixture with the same Y coordinate was corrected; no production
RF bypass or native receiver workaround was introduced.

The hardening project gate passed 29/29 stages, in 141.2 seconds for stages and
144 seconds overall. All 243 payload Lua files compiled in normal and debug
configurations. The bridge JAR and protocol are unchanged by this feature.

## Hardening review

Reviewed commits `1aae8165`, `9b27e043` and `ebea218d`, plus the pending
LARCH/WAVE implementation. Three reproducible issues in that pending feature
were fixed:

- Unmute and preset commands could index missing hardware or a cleared
  snapshot after an outage or radio removal. Commands now revalidate access
  and refresh the native snapshot before reading either.
- Removing a scanning radio serialized its temporary scan channel. Adding a
  backup battery could also replace the scan runtime before restoring tuning.
  Hardware changes now stop the scan while its original receiver still owns
  the channel, before any generation or ownership change.
- An out-of-band manual tuning request stopped the active scan before
  validating the requested frequency. Only accepted tuning now replaces it.

All three failures were reproduced by regression tests before their fixes. The UI
suite now covers unavailable-radio commands and the real hardware module's
scan-to-removal and scan-to-backup-installation paths, including exact handset
identity and saved listening frequency. Bed, speech, map-expedition, ownership
and persistence regressions passed in the full gate. This review does not
reclassify the previously recorded native secondary-view return crash as fixed.

The native hardening run also passed: an invalid frequency retained the live
scan, removal restored its original frequency before returning the exact
handset, unavailable-radio commands completed without exceptions, and remount
retained that handset ID and channel. The cloned character initially had a
full inventory, which correctly refused removal. The final fixture temporarily
reserved capacity within the native limit of 100, preserving any displaced
items in a native container and restoring them in the same tick. Production
capacity checks remain in force; automated tests retain full-inventory refusal.

Reproduction: `tests/ui/run_ui_tests.ps1`,
`artifacts/emma/run-terminal-radio-native.ps1` and
`artifacts/emma/terminal-radio-native.lua`. Selected captures and logs live in
`artifacts/emma/native-acceptance/emma-radio-*` and `terminal-radio-*`.
