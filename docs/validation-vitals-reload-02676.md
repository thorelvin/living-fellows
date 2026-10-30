# Companion tiredness and stamina across reloads

2026-10-30, follow-up to 0.26.76.

The persistent vitals record captured and restored hunger and thirst, but omitted native `FATIGUE` and `ENDURANCE`. LF reconstructs its actors when loading, so tiredness and stamina reverted to new-actor defaults. The omission also affected replacement actors restored from those snapshots during runtime recovery.

`SCVitals.capture` now saves `fatigue` and `endurance`. `SCVitals.apply` writes both through the native CharacterStat API and verifies each resulting value. The fields are optional, so existing schema-3 saves remain supported without a migration. Records that never saved these values cannot recover their previous tiredness or stamina; the next save made with the fix records their current values.

The dedicated regression failed on the old implementation at the first capture assertion. With the fix, all **42 assertions pass**, covering tiredness 0, 0.46, 0.83 and 1 across three fresh-actor restore cycles, reduced stamina, later recovery, legacy records, ignored setters and native setter errors. The persistence transaction harness additionally checks that the fields survive document import and re-save while a companion remains unloaded.

Full project gate: **29/29 passed**, 175 seconds. Existing persistence, gameplay, sleep, combat, native isolation and packaging checks pass; all 244 payload Lua files compile normally and in debug mode. Output: `build/vitals-reload/project-gate.txt`. Native bridge source, payload and protocol remain unchanged.

No live save/quit/relaunch acceptance was run. After the game closed on 2026-10-30, the combined follow-ups passed all 29 project stages and were installed locally. The installed vitals source matches the tested file. This fix is included in [release 0.26.78](validation-release-0.26.78.md).
