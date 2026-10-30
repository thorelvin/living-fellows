# Accepted car-wash orders disappearing

2026-10-30, follow-up to 0.26.76.

The latest console/debug log has no car-wash progress records. A read-only decode of the user's saved `global_mod_data.bin` confirms Tess Nolan accepted `job:234` and `job:237`. Both appear in completed history with result `upkeep_supply_exhausted`, at 01:07:27 and 01:09:54 Oslo time. They are no longer queued. The source file hash before/after decoding is `80653b723f6d4e22dca60bb46725abf06ceb04c058592aeb9b371409eff1b30b`. No save data was edited.

The worker rechecks supplies with route validation after accepting an order. Failed selection incorrectly returned the completion flag. Sink failure reasons were also discarded. The old history cannot distinguish a missing vessel, a lost supply or an inaccessible sink/storage route; it does not prove which one Tess encountered.

The worker now retains an unfulfilled job and reports its preparation blocker. Empty preparation receipts retry every three minutes without exhausting attempts, including after reload. A borrowed vessel is returned and its exact ownership cleared before a dry/unreachable sink can enter that retry policy. Running native actions and ambiguous effects retain the existing recovery rules. Queue acceptance is now logged; paused jobs use the existing worker-specific blocked-job diagnostics. Already removed historical jobs are not recreated.

Regression coverage includes supplies removed after acceptance, inaccessible sink and storage routes, resumption of the same job after supplies/access return, dry-sink return of the exact vessel, three-minute retry persistence and exclusion of active native receipts. The new unreachable-sink regression fails against HEAD's old worker at check 50 and passes with the fix. Existing native wash/fill transfer, reserve, drinking-water protection, multi-sink and sliced-route scenarios still pass. Gameplay regressions pass.

Local evidence is under `build/control-inventory`: `latest-mod-data.json`, `car-wash-before.txt`, `car-wash-gameplay.txt` and `car-wash-project-gate.txt`. The decoder checks the inspected B42 Kahlua field types, every bucket boundary, full-file consumption and unchanged source hash. A live wash in the user's world has not been observed with this patch.

All 29 project stages passed in 120 seconds, including core, gameplay, UI, Lua compilation, packaging and installer transactions. With the game confirmed closed, `Install-Local.ps1 -NativeBridge` installed this fix and the pending tiredness-persistence, terminal access/layout/logo and interaction-audio changes. SHA256 comparison verified 15 changed payload/native files against the local installation. The bridge itself is unchanged. No commit or push was made for this follow-up.
