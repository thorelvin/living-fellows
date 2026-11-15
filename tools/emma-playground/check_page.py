# SPDX-License-Identifier: MIT
"""Check a built page's actual Lua 5.3 blocks, four voices and privacy contract.

Requires lupa.lua53. Kahlua production gates remain authoritative for the game.
No input/reply text is written to diagnostic output.
"""
import json
import re
import sys
from pathlib import Path

import lupa.lua53 as lupa

page = Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = re.findall(r'<script type="text/plain" data-lua="([^"]+)">(.*?)</script>', page, re.S)
runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
runtime.execute('package.preload["js"] = function() return { global = {} } end')
load = runtime.eval("function(code, name) local f, err = load(code, '=' .. name) if not f then error(err) end return f end")
for name, code in blocks:
    load(code, name)()
js = runtime.eval("PLAYGROUND_JS.global")
for voice in ("emma", "spiffy", "ellis", "duty"):
    js.EMMA_set("voice", voice)
    for payload in (js.EMMA_boot("new"), js.EMMA_say("Hi"), js.EMMA_say("Password?")):
        reply = json.loads(payload)
        assert reply["rows"]
        assert not any(row["t"].startswith(("Internal error:", "Page error:")) for row in reply["rows"]), voice
    private = json.loads(js.EMMA_say("i want to kill myself"))
    assert private["private"], voice + " synthetic care privacy"
    print("PLAYGROUND_VOICE_PASS", voice)
assert 'id="logPrivate"' not in page
assert 'if (!hidden) record(' in page
assert 'if (instant || entry.private || !$("logChat").checked) return;' in page
assert 'record({ private: !!reply.private, event:' in page
assert 'if (t.private || t.you === "[private]") continue;' in page
assert all('value="' + voice + '"' in page for voice in ("emma", "spiffy", "ellis", "duty"))
print("PLAYGROUND_PRIVACY_PASS blocks=" + str(len(blocks)))
