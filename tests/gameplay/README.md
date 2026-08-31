# Clean-room gameplay tests

`run_gameplay_tests.ps1` compiles and executes the independently authored Lua
harness with the Kahlua compiler/runtime bundled by Project Zomboid 42.20.4,
then checks static subsystem contracts.

The harness currently exercises 113 runtime assertions, including rejecting
Actor/navigation/UI adapters, bounded stuck recovery, B42 LOS and CharacterStat
contracts, multistory combat safety, group rollback on a later member, and
medical/scavenge/downtime inventory rollback. The static audit adds 119 source
and interface assertions.

The production helper `SCGameplayUtil.lua` is narrowly scoped to gameplay. It
contains the single fallback configuration table, bounded Java-list adapters,
coordinate/inventory helpers, dynamic core-service resolution, diagnostic rate
limiting, and per-actor subsystem circuit breakers. It owns no lifecycle event
and registers no recurring work.

Run from PowerShell:

```powershell
.\tests\gameplay\run_gameplay_tests.ps1
```
