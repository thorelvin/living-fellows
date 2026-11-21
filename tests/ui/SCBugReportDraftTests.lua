-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local report, diagnostic = SC.BugReport, SC.Diagnostics
local calls, checks = 0, 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function has(text, part) return string.find(text, part, 1, true) ~= nil end
local function build(what, steps)
    local draft, why = report.buildDraft(what or "The passenger froze.", steps or "Stop the car.")
    assert(draft, why)
    return draft
end
function getCurrentSaveName() return "C:\\Users\\Desk Patron\\Saves\\Sandbox\\Autumn_Hollow\\" end
function getMyDocumentFolder() return "C:\\Users\\Desk Patron\\Zomboid" end
function getCurrentUserProfileName() return "Lantern-Owner" end
function getClientUsername() return "Ezra_9" end
function getCurrentUserSteamID() return "76561199999999999" end
function getPlayer() return {getUsername = function() return "Dot.Name+" end,
    getDisplayName = function() return "Survivor Seven" end} end
function getGameVersion() return "42.22.2" end
SCBridge = {getProtocol = function() return "42.22-isocompanion-34" end,
    openBugReportDraft = function(url)
        calls = calls + 1
        SC_TEST_OPENED_LINK = url
        return true
    end}

diagnostic.reset()
local note = string.char(0xD83C, 0xDFB5)
local what = "The caf" .. string.char(0xE9) .. " & the radio froze?"
local steps = "Open #1 = 100%.\r\nPress + again " .. note
local normal = build(what, steps)
check(calls == 0, "review must not open a browser")
check(has(normal.body, what) and has(normal.body, "Open #1 = 100%.\nPress + again " .. note), "exact readable fields")
check(has(normal.body, normal.title) and has(normal.body, "\n" .. SC.Identity.release)
    and has(normal.body, "\n42.22.2") and has(normal.body, "No recent entries."), "preview metadata")
check(has(normal.url, "https://github.com/thorelvin/living-fellows/issues/new?template=bug_report.yml&title="),
    "fixed repository issue form")
check(has(normal.url, "&problem=The%20caf%C3%A9%20%26%20the%20radio%20froze%3F&reproduce="),
    "encoded exact problem, Unicode and delimiter")
check(has(normal.url, "Open%20%231%20%3D%20100%25.%0APress%20%2B%20again%20%F0%9F%8E%B5&mod-version="),
    "encoding preserves reproduction steps, line break and supplementary character")
check(has(normal.url, "&game-version=42.22.2&logs=") and has(normal.body, "Bridge protocol (loaded): 42.22-isocompanion-34")
    and has(normal.body, "Bridge protocol (expected): " .. SC.Identity.bridgeProtocol), "observed and expected protocols")
check(report.openDraft(normal) and calls == 1 and normal.url == SC_TEST_OPENED_LINK,
    "one explicit open passes the exact reviewed URL")

for _, private in ipairs({
    "Open \\\\Storage Box\\backups\\My Save.", "Open c:\\Users\\Test Name\\world.",
    "Look in /home/Test Name/world.", "Search ~/my game.", "Open file:///etc/hosts.",
    "Open saves/My Game.", "Look in ..\\crash", "Failed on SecretWorld.db", "Failed on secret.x",
    "AUTUMN HOLLOW", "Autumn_Hollow", "Autumn-Hollow", "desk patron", "LANtern Owner",
    "EzRA_9", "Dot.Name+", "surVIVOr\tseven", "76561199999999999",
    "Reach @player", "Email foo@example.org", "Open https://example.org/x", "See www.example.org",
    "See %2Fhidden%2Fthing", "username: Someone", "save name=private", "my save named Another Place",
    "my user name is Bob", "It affects user: AnonymousNell.", "my profile=private", "On save: Broccoli Hollow",
    "my save is called Elm Street", "try as user Oakes", "Early" .. string.char(3) .. "control",
}) do
    local draft, why = report.buildDraft("The radio froze", private)
    check(draft == nil and type(why) == "string" and not has(why, private), "private steps reached draft: " .. private)
    check(report.buildDraft(private, "Press once") == nil, "private title or body")
end
check(build("The Lantern Ownerless lamp broke", "Open it.").url ~= nil, "embedded ordinary words")
check(report.buildDraft("   ", "Press once") == nil and report.buildDraft("It froze", "\n") == nil, "empty fields")
check(report.buildDraft(string.rep("a", 501), "Wait") == nil, "oversized field")
local long = string.rep(string.char(0x754C), 420)
check(report.buildDraft(long, long) == nil, "limit measured after URL encoding")

for index = 1, 7 do
    diagnostic.report("persistence", "PrivateActor" .. index, "restore record quarantined", "C:/hidden/name")
end
diagnostic.report("private-unknown-system", "HiddenActor", "private problem", "HiddenSave")
diagnostic.report("handover", "person", "radio restore failed", "PrivateSave")
diagnostic.report("handover", "person", "view teardown pending", "same printed key is cooling down")
diagnostic.report("vehicle", "playername", "Unknown Secret Message", "/home/RealName")
local lines = diagnostic.recentReportLines()
check(#lines == 5 and lines[3] == "[persistence] restore record quarantined"
    and lines[4] == "[handover] radio restore failed" and lines[5] == "[vehicle] Diagnostic reported",
    "latest five printable, recognized lines in chronological order")
lines[1] = "should not mutate history"
local withLogs = build()
check(has(withLogs.body, "[handover] radio restore failed") and has(withLogs.body, "[vehicle] Diagnostic reported"),
    "recent diagnostic summaries enter preview and URL")
for _, secret in ipairs({"PrivateActor", "private-unknown-system", "Secret Message", "Secret%20Message", "hidden",
    "RealName", "playername", "HiddenActor", "PrivateSave", "mutate"}) do
    check(not has(withLogs.body, secret) and not has(withLogs.url, secret), "raw diagnostic private: " .. secret)
end
diagnostic.clearReportLines()
check(has(build().body, "No recent entries."), "new session clears report lines")
SCBridge.getProtocol = function() return "42.22-isocompanion-35 SecretName" end
getGameVersion = function() return "/home/bad" end
local invalid = build()
check(has(invalid.body, "Bridge protocol (loaded): unavailable") and has(invalid.body, "Project Zomboid version\nunavailable")
    and not has(invalid.body, "SecretName") and not has(invalid.url, "home"), "metadata only admits version grammar")
SCBridge = nil
function getGameVersion() return "42.22.2" end
local missing = build()
check(has(missing.body, "Bridge protocol (loaded): unavailable") and has(missing.body, "\n42.22.2"),
    "missing bridge keeps current game build")
function getGameVersion() return "42.22" end
function getCore() return {getVersion = function() return "42.22.2 3d39148846 integrity /home/private" end} end
local nativeBuild = build()
check(has(nativeBuild.url, "&game-version=42.22.2%203d39148846&logs=") and not has(nativeBuild.body, "integrity"),
    "native menu patch and revision preserved, integrity data omitted")
function getCore() return {getGameAndBuildVersion = function() return "42.22.3" end} end
check(has(build().url, "&game-version=42.22.3&logs="), "patch fallback without integrity string")
getCore = nil
check(has(build().body, "42.22 (patch unavailable)"), "older API exposes family only")
local opened, why = report.openDraft(missing)
check(not opened and type(why) == "string" and calls == 1, "missing opener is recoverable without uploading")
SC_TEST_REPORT = "Bug report draft PASS checks=" .. tostring(checks)
