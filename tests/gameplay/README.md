# Clean-room gameplay tests

The Lua harnesses in this folder run inside the Kahlua compiler and runtime
bundled with Project Zomboid. They are wired as groups in the release gate
(`tests\essential\<Domain>.ps1`): routine groups in every run, the rest marked
`Extended` and run by every `-Release` gate. `test_gameplay_static.py` checks
static subsystem contracts and runs in `scripts\Test-Source.ps1`, so Source CI
runs it too.

The production helper `SCGameplayUtil.lua` is narrowly scoped to gameplay. It
contains bounded Java-list adapters, coordinate/inventory helpers, dynamic
core-service resolution, diagnostic rate limiting and per-actor subsystem
circuit breakers. It owns no lifecycle event and registers no recurring work.

Run from PowerShell:

```powershell
.\scripts\Test-Project.ps1 -Check Behaviour -Extended   # one domain, all groups
.\scripts\Run-TestGroups.ps1 -Name '*home*'             # selected groups by name
python .\tests\gameplay\test_gameplay_static.py          # static contracts only
```

`tests\gameplay\run_alife_adapter_tests.ps1` and `run_bandits_adapter_tests.ps1`
remain for the optional contracts against an installed copy of those mods.
