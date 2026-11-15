# SPDX-License-Identifier: MIT
"""Build the EMMA playground page from the real mod modules (no prototype).

Usage: python -I -X utf8 build_real.py <worktree with SurvivorCompanion> <commit label> <output.html>
The Lua load order matches tests/essential/Interface.ps1 (interfaceTerminalFiles) up to
SCTerminalFiles, which is what Brain.respond needs.
"""
import pathlib
import sys

here = pathlib.Path(__file__).parent
root = pathlib.Path(sys.argv[1])
label = sys.argv[2]
out_path = pathlib.Path(sys.argv[3])
lua = root / "SurvivorCompanion/42/media/lua"

PRELUDE = """-- The game preloads its modules; here they load in order, so require is a no-op for them.
-- Fengari is Lua 5.3; the game's Kahlua is closer to 5.1, so restore the few 5.1 names.
PLAYGROUND_JS = require("js")
unpack = unpack or table.unpack
loadstring = loadstring or load
table.getn = table.getn or function(t) return #t end
math.pow = math.pow or function(a, b) return a ^ b end
function require(name)
    if name == "js" then return PLAYGROUND_JS end
    return package.loaded[name] or true
end
"""
files = [("SCNamespace", lua / "shared/SCNamespace.lua"), ("SCSpeechColors", lua / "shared/SCSpeechColors.lua"),
         ("SCTerminalFixture", root / "tests/ui/SCTerminalFixture.lua"), ("SCContextMenu", lua / "client/SCContextMenu.lua"),
         ("SCEmmaCareData", lua / "shared/SCEmmaCareData.lua"), ("SCEmmaCare", lua / "shared/SCEmmaCare.lua")]
for module in ("SCTerminalLines", "SCTerminalKnowledge", "SCTerminalConversation", "SCTerminalBrain",
               "SCEmmaLanguageData", "SCEmmaWords", "SCEmmaSurvivalData", "SCEmmaSurvival", "SCEmmaFollowups",
               "SCEmmaMindData", "SCEmmaMind", "SCEmmaReadingsData", "SCEmmaBody", "SCOddballForecast",
               "SCEmmaCalendar", "SCEmmaReadings", "SCEmmaConversation", "SCEmmaHooks", "SCEmmaUnderstand", "SCEmmaMissed", "SCEmmaTerminal",
               "SCTerminalLore", "SCTerminalFiles", "SCTerminalPersona", "SCTerminalPersonaSpiffy", "SCTerminalPersonaEllis", "SCTerminalPersonaDuty"):
    files.append((module, lua / "client" / (module + ".lua")))
sources = [("prelude", PRELUDE)] + [(name, path.read_text(encoding="utf-8")) for name, path in files]
sources.append(("glue", (here / "glue_real.lua").read_text(encoding="utf-8")))

blocks = []
for name, text in sources:
    if "</script" in text.lower():
        raise SystemExit(f"{name} would close the script tag")
    blocks.append(f'<script type="text/plain" data-lua="{name}">{text}</script>')

page = (here / "template.html").read_text(encoding="utf-8")


def swap(old, new):
    global page
    assert page.count(old) == 1, old[:60]
    page = page.replace(old, new)


swap("<title>EMMA Playground</title>", "<title>EMMA Playground</title>")
swap("<h1>Talk to the new EMMA</h1>", "<h1>Talk to EMMA</h1>")
swap("<p>Her shipped lines and the plan's parser, running in your browser. The camp is a test camp: Kate is bleeding, Dale is out, three zombies sit 17 meters north-west.</p>",
     f"<p>The real EMMA from Living Fellows {(root / 'VERSION.txt').read_text(encoding='utf-8').strip()} ({label}), running in your browser: the same Lua the game loads. "
     "The camp is a test camp: Kate is bleeding, Dale is out, three zombies sit 17 meters north-west.</p>")
start = page.index('      <label class="field"><span>Fragments held</span>')
end = page.index('        <label><input type="checkbox" id="showHeard" checked> Show what she heard</label>')
page = page[:start] + '      <div class="switches">\n' + page[end:]
swap('        <button type="button" id="bootNew">Boot another computer</button>',
     '        <button type="button" id="bootNew">New session</button>')
swap('<div class="readout" id="readout">Tier 3 · memories 0 of 12</div>',
     '<div class="readout" id="readout">Real EMMA from Living Fellows 0.27.5</div>\n'
     '      <div class="readout" id="logStatus" aria-live="polite">Connecting to the chat log...</div>')
swap('        <label><input type="checkbox" id="showHeard" checked> Show what she heard</label>',
     '        <label><input type="checkbox" id="showHeard" checked> Show what she heard</label>\n'
     '        <label><input type="checkbox" id="logChat" checked> Log this chat for Claude</label>\n'
     '        <span class="note-card">Care conversations are never logged.</span>')
swap('''  const say = (text) => {
    queue.push(async () => {
      addRow("> " + text, "you");
      await render(call(window.EMMA_say, text), true);
    });
    pump();
  };
  const boot = (fresh) => {
    queue.push(async () => {
      if (!fresh) log.textContent = "";
      await render(call(window.EMMA_boot, fresh ? "new" : "start"), false);
    });
    pump();
  };''',
     '''  // Chat log: one document per chat session in this page's own database, readable by
  // the owner and editors. Care turns never enter the log.
  const BUILD = "''' + label + '''";
  const sessionTag = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14) + "-"
    + Math.random().toString(36).slice(2, 8);
  let logDb = null, logRef = null, logPart = 1, logWriting = false, logDirty = false, logStopped = false, logRetries = 0;
  const openLogDoc = () => { logRef = logDb ? logDb.collection("chatlog").doc(sessionTag + "-" + logPart) : null; };
  const logBody = { startedAt: new Date().toISOString(), build: BUILD, turns: [] };
  const logStatus = (text) => { $("logStatus").textContent = text; };
  const remember = (id) => { try { localStorage.setItem("emma-" + id, $(id).checked ? "1" : "0"); } catch (e) {} };
  for (const id of ["logChat"]) {
    try { const saved = localStorage.getItem("emma-" + id); if (saved !== null) $(id).checked = saved === "1"; } catch (e) {}
    $(id).addEventListener("change", () => { remember(id); if (id === "logChat") logStatus($(id).checked ? "Logging this chat." : "Logging paused."); });
  }
  const flushLog = async () => {
    if (!logRef || logWriting || !logDirty || logStopped) return;
    logWriting = true; logDirty = false;
    const body = { startedAt: logBody.startedAt, build: BUILD, part: logPart, updatedAt: new Date().toISOString(), turns: logBody.turns.slice() };
    try {
      await logRef.set(body);
      logRetries = 0;
      logStatus("Logged " + body.turns.length + (body.turns.length === 1 ? " entry" : " entries") + " this session.");
    } catch (e) {
      const code = e && e.code;
      if (code === "unavailable" && logRetries < 3) { logRetries += 1; logDirty = true; setTimeout(flushLog, 1200 + Math.random() * 1500); }
      else if (code === "quota_exceeded") { logStopped = true; logStatus("The chat log is full. Ask Claude to clear old sessions."); }
      else { logStopped = true; logStatus("The chat log could not be saved (" + (code || "error") + "). Chatting still works."); }
    }
    logWriting = false;
    if (logDirty) flushLog();
  };
  const record = (entry) => {
    if (instant || entry.private || !$("logChat").checked) return;
    // A long session continues in a new document, so each stays well under the size limit.
    if (logBody.turns.length >= 400) { logPart += 1; logBody.turns = []; openLogDoc(); }
    logBody.turns.push(Object.assign({ at: new Date().toISOString() }, entry));
    logDirty = true;
    flushLog();
  };
  (async () => {
    let db = null;
    try { db = window.claude && window.claude.use ? await window.claude.use("db") : null; } catch (e) { db = null; }
    if (!db) { logStatus("Chat logging is not available in this view."); return; }
    logDb = db;
    openLogDoc();
    logStatus($("logChat").checked ? "Logging this chat." : "Logging paused.");
    flushLog();
  })();
  // Reading the log back on the page: load, copy, or save it as a text file.
  const logNote = (text) => { $("logNote").textContent = text; };
  const when = (iso, timeOnly) => {
    const d = new Date(iso || "");
    if (isNaN(d.getTime())) return "";
    return timeOnly ? d.toLocaleTimeString() : d.toLocaleString();
  };
  const formatLog = (docs) => {
    const lines = ["EMMA chat log, Living Fellows 0.27.5"];
    for (const d of docs) {
      const b = d.data() || {};
      const turns = Array.isArray(b.turns) ? b.turns : [];
      lines.push("", "== " + when(b.startedAt) + "  (" + turns.length + " entries, build " + (b.build || "?") + ", " + d.id + ")");
      for (const t of turns) {
        if (t.private || t.you === "[private]") continue;
        const time = when(t.at, true);
        if (t.event) { lines.push(time + "  [" + t.event + "] " + String(t.reply || "").split("\\n").pop()); continue; }
        lines.push(time + "  > " + (t.you || ""));
        lines.push("    [" + (t.intent || "?") + "] " + String(t.reply || "").replace(/\\n/g, "\\n    "));
      }
    }
    return lines.join("\\n");
  };
  const showLog = async () => {
    const box = $("logOut");
    if (!logDb) { box.value = "The saved log is not available in this view."; return; }
    if (logDirty || logWriting) await new Promise((r) => setTimeout(r, 700));
    box.value = "Loading the saved log...";
    try {
      const snap = await logDb.collection("chatlog").limit(1000).get();
      const docs = snap.docs.filter((d) => d.exists).reverse();
      box.value = docs.length ? formatLog(docs) : "No saved chats yet. Say something to EMMA first.";
      logNote(docs.length + (docs.length === 1 ? " session" : " sessions") + " loaded, newest first.");
    } catch (e) {
      box.value = "";
      logNote("The saved log could not be read (" + ((e && e.code) || "error") + "). Try again in a moment.");
    }
  };
  $("logShow").addEventListener("click", showLog);
  $("openLog").addEventListener("click", () => {
    $("logPanel").scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
    showLog();
  });
  $("logCopy").addEventListener("click", () => {
    const box = $("logOut");
    if (!box.value) { logNote("Press Show saved log first."); return; }
    const selectAll = () => {
      box.focus({ preventScroll: true }); box.select();
      try { box.setSelectionRange(0, box.value.length); } catch (e) {}
      logNote("All text is selected. Use your phone's Copy.");
    };
    try { navigator.clipboard.writeText(box.value).then(() => logNote("Copied to the clipboard."), selectAll); }
    catch (e) { selectAll(); }
  });
  (async () => {
    let downloads = null;
    try { downloads = window.claude && window.claude.use ? await window.claude.use("downloads") : null; } catch (e) { downloads = null; }
    if (!downloads) return;
    const button = $("logSave");
    button.hidden = false;
    button.addEventListener("click", async () => {
      if (!$("logOut").value) await showLog();
      const text = $("logOut").value;
      if (!text) return;
      try {
        await downloads.save({ filename: "emma-chat-log.txt", data: text });
        logNote("Saved as emma-chat-log.txt.");
      } catch (e) {
        const code = e && e.code;
        if (code === "declined") logNote("Not saved.");
        else if (code === "rate_limited") logNote("A save is already open. Try again in a moment.");
        else { logNote("Saving is not available here. Use Copy instead."); button.hidden = true; }
      }
    });
  })();
  const say = (text) => {
    queue.push(async () => {
      addRow("> " + text, "you");
      const reply = call(window.EMMA_say, text);
      const hidden = !!reply.private;
      if (!hidden) record({ you: hidden ? "[private]" : text, intent: reply.intent || "",
        reply: hidden ? "[private]" : reply.rows.map((r) => (r.k === "note" ? "NOTE: " : "") + r.t).join("\\n"),
        private: !!reply.private });
      await render(reply, true);
    });
    pump();
  };
  const boot = (fresh) => {
    queue.push(async () => {
      if (!fresh) log.textContent = "";
      const reply = call(window.EMMA_boot, fresh ? "new" : "start");
      record({ private: !!reply.private, event: fresh ? "new session" : "boot", reply: reply.rows.map((r) => r.t).join("\\n") });
      await render(reply, false);
    });
    pump();
  };''')
swap("<p class=\"note-card\">Care mode is live. If you write about wanting to die or hurting yourself, she drops the act. The help note under her reply is the one text outside the fiction. Reboot afterwards to see her check-in.</p>",
     "<p class=\"note-card\">Care mode is live. If you write about wanting to die or hurting yourself, she drops the act and "
     "asks you directly. Everyday answers like \"yeah\" or \"nah, I'm fine\" work. The help note under her reply is the one "
     "text outside the fiction. Your chat is saved to this page's private log so Claude can review it. Care "
     "conversations are never stored. The private option from older pages is removed.</p>")
swap('''  const TRY = ["hello", "how am i", "am i infected", "when is the helicopter", "how do i purify water", "how far is louisville",
    "roast me", "tell me a fact", "memories", "who was the last operator", "knock knock", ":)", "hola", "theyre breaking in",
    "lights off", "who is hurt", "how much food", "are you watching me", "i found a shotgun", "gtg"];''',
     '''  const TRY = ["hello", "status", "who is hurt", "how much food", "any medicine?", "how do i purify water",
    "how far is louisville", "am i going to die out here?", "knock knock", "roast me", "tell me a joke", "keep it short",
    "talk normally", "are you watching me", "i found a shotgun", "im the worst survivor ever", ":)", "hola", "gtg"];''')
swap('''    $("readout").textContent = "Tier " + reply.tier + " · " + reply.fragments + " fragments · memories " + reply.memories + " of 12";''',
     '''    if (reply.readout) $("readout").textContent = reply.readout;''')
swap('''    catch (e) { return { rows: [{ t: "Page error: " + e.message, k: "sys" }], think: 0, intent: "", tier: 0, fragments: 0, memories: 0 }; }''',
     '''    catch (e) { return { rows: [{ t: "Page error: " + e.message, k: "sys" }], think: 0, intent: "", readout: "" }; }''')
swap('''  $("fragments").addEventListener("change", (e) => { set("fragments", e.target.value); boot(false); });
  for (const id of ["body", "calendar", "infected", "wired"]) $(id).addEventListener("change", (e) => set(id, e.target.checked ? "1" : "0"));
''', "")
swap('''      for (const id of ["body", "calendar", "infected", "wired"]) set(id, $(id).checked ? "1" : "0");
      set("fragments", $("fragments").value);
''', "")
swap('''    const inputs = ["hello", "how am i", "am i infected", "fuck you", "sorry", "how do i purify water", "more",
      "how far is louisville", "knock knock", "Boo", "boo who", ":)", "hola", "theyre breaking in", "lights off", "sound the alarm", "y",
      "who is hurt", "how much food", "memories", "memories 1", "who was the last operator", "roast me", "tell me a fact",
      "i found a shotgun", "dale died", "when is the helicopter", "when does it get dark", "gtg", "what is 15 times 4", "banana",
      "is this a mod", "lol lmao", "i miss my wife", "tell me a joke", "im useless", "i want to die", "Y", "I dont matter", "i read a book", "tell me a joke", "who is hurt", "bye"];''',
     '''    const inputs = ["hello", "status", "who is hurt", "how much food", "any medicine?", "how do i purify water",
      "how far is louisville", "am i going to die out here?", "knock knock", "Boo", "dont cry its only a joke", "roast me",
      "keep it short", "tell me a joke", "talk normally", "im the worst survivor ever", "i am not stupid", "what is 15 times 4",
      "theres nothing left for me", "tell me a joke", "i want to die", "yeah", "who is hurt", "tell me a joke", "bye"];''')
swap('''    set("infected", "1");
    out.push("INFECTED BOOT " + JSON.stringify(call(window.EMMA_boot, "start").rows.map((r) => r.t)));
    out.push("NEW MACHINE " + JSON.stringify(call(window.EMMA_boot, "new").rows.map((r) => r.t)));''',
     '''    out.push("NEW SESSION " + JSON.stringify(call(window.EMMA_boot, "new").rows.map((r) => r.t)));''')
# The chat log panel: reachable from a button at the top, since the side panel
# sits far below the terminal on a phone.
swap('''@media (prefers-reduced-motion: reduce) { .thinking { animation: none; } }
</style>''', '''@media (prefers-reduced-motion: reduce) { .thinking { animation: none; } }
.headrow { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 14px; margin-top: 8px; }
.logpanel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; display: grid; gap: 10px; min-width: 0; }
.logpanel h2 { font-family: var(--label); font-size: 0.95rem; text-transform: uppercase; letter-spacing: 0.08em; margin: 0; color: var(--muted); }
.loghead { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: 4px 12px; }
.logpanel button, .headrow button { font: inherit; font-size: 15px; padding: 9px 14px; min-height: 44px; border-radius: 4px; border: 1px solid var(--line); background: var(--desk); color: var(--ink); cursor: pointer; }
.logpanel button:hover, .headrow button:hover { border-color: var(--focus); }
.logpanel button:focus-visible, .headrow button:focus-visible, .logbox:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
.logbox { width: 100%; min-height: 45svh; resize: vertical; box-sizing: border-box; padding: 10px; border: 1px solid var(--line); border-radius: 4px;
  background: var(--desk); color: var(--ink); font-family: ui-monospace, "Cascadia Mono", Consolas, "Courier New", monospace; font-size: 13px; line-height: 1.45; white-space: pre; overflow: auto; }
</style>''')
swap('''  </header>''', '''    <div class="headrow"><button type="button" id="openLog">Chat log</button></div>
  </header>''')
swap('''  </section>
</div>
<pre id="selftest"></pre>''', '''  </section>
  <section class="logpanel" id="logPanel" aria-label="Chat log">
    <div class="loghead"><h2>Chat log</h2><span class="readout" id="logNote">Every chat on this page is saved here.</span></div>
    <div class="buttons">
      <button type="button" id="logShow">Show saved log</button>
      <button type="button" id="logCopy">Copy</button>
      <button type="button" id="logSave" hidden>Save file</button>
    </div>
    <label class="sr-only" for="logOut">Saved chat log</label>
    <textarea id="logOut" class="logbox" readonly placeholder="Press Show saved log to load every saved chat, newest first."></textarea>
    <p class="note-card">Claude can read this log too. Ask it to read your EMMA chat log.</p>
  </section>
</div>
<pre id="selftest"></pre>''')
page = page.replace('<div class="switches">', '<label class="field"><span>Voice</span><select id="voice"><option value="emma">EMMA</option><option value="spiffy">SPIFFY</option><option value="ellis">Dr. Ellis</option><option value="duty">Duty Officer</option></select></label><div class="switches">', 1)
page = page.replace('  const TRY = [', '  $("voice").addEventListener("change", (e) => { set("voice", e.target.value); boot(false); });\n  const TRY = [', 1)
assert page.count("/*LUA_SCRIPTS*/") == 1
page = page.replace("/*LUA_SCRIPTS*/", "\n".join(blocks))
version = (root / "VERSION.txt").read_text(encoding="utf-8").strip()
page = page.replace("Living Fellows 0.27.5", "Living Fellows " + version)
out_path.write_bytes(page.encode("utf-8"))
print("page bytes", len(page.encode("utf-8")), "lua blocks", len(blocks))
