<!-- SPDX-License-Identifier: MIT -->
# Computer conversation playground

This preserves the original `plan-emma-probe/web/build_real.py` workflow in the
repository. It embeds the real production modules, the original camp fixture,
and the four voices. It does not call an AI service.

Build with Python:

```powershell
python tools/emma-playground/build_real.py C:/ZOMBOID/work/horde-safe-ground-02715 phase-D-0.27.21 C:/ZOMBOID/plan-emma-probe/web/emma-playground-0.27.21-phase-d.html
```

Open the resulting HTML in a browser. Select EMMA, SPIFFY, Dr. Ellis or Duty
Officer. A voice change starts a fresh session. The optional public chat log
uses the original artifact host's database when available. Care, private notes,
and private replies are always excluded, including on errors and reboot. Older
private log entries are omitted from log exports.

`check_page.py` loads the embedded blocks in `lupa.lua53` and checks all four
voices and the logging guards. The project's Interface check separately runs
the authoritative game Kahlua VM. Headless checks do not replace browser visual
verification or the user's conversation session.
