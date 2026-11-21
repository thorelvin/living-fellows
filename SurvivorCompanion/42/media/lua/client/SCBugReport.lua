-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCDiagnostics"

local SC = SurvivorCompanion
local report = {}
SC.BugReport = report

local issueForm = "https://github.com/thorelvin/living-fellows/issues/new?template=bug_report.yml"
local maxUrlLength = 4000
local maxFieldLength = 500

local function readString(callback, ...)
    local ok, value = SC.Call.protected(callback, ...)
    if ok and type(value) == "string" then return value end
    return ""
end

local function normalizeName(text)
    return (string.lower(text):gsub("[%s_%-]+", " "))
end

local function hasName(text, value)
    if type(value) ~= "string" or value == "" then return false end
    local needle = normalizeName(value):match("^%s*(.-)%s*$")
    if needle == "" then return false end
    local start = 1
    while start <= #text do
        local first, last = string.find(text, needle, start, true)
        if not first then return false end
        if not text:sub(first - 1, first - 1):match("[%w]")
            and not text:sub(last + 1, last + 1):match("[%w]") then return true end
        start = first + 1
    end
    return false
end

local function hasPrivateInput(value)
    local text = value:lower()
    -- A path may be relative, quoted or contain spaces. Ask for an edit before
    -- building a URL instead of guessing where a pasted path ends.
    if text:find("[/\\@]") or text:find("%%%x%x") or text:find("[%w_%-]%.[%a]")
        or text:find("%a:[^%s]") or text:find("user[%s_%-]*name%s*[:=]")
        or text:find("save[%s_%-]*name%s*[:=]") or text:find("user%s*name%s+is%s")
        or text:find("save%s+name%s+is%s") or text:find("as%s+user%s+") then return true end
    local words = " " .. text:gsub("[^%w:=]+", " ") .. " "
    for _, label in ipairs({"user", "profile", "save"}) do
        if words:find(" " .. label .. "%s*[:=]") or words:find(" " .. label .. " named ")
            or words:find(" " .. label .. " called ") or words:find(" " .. label .. " is called ")
            or words:find(" " .. label .. " name%s*[:=]") then return true end
    end
    local normalized = normalizeName(text)
    local save = readString(getCurrentSaveName):gsub("\\", "/"):gsub("/+$", "")
    local home = readString(getMyDocumentFolder):lower():gsub("\\", "/")
    if hasName(normalized, save:match("([^/]+)$"))
        or hasName(normalized, home:match("/users/([^/]+)") or home:match("/home/([^/]+)"))
        or hasName(normalized, readString(getCurrentUserProfileName))
        or hasName(normalized, readString(getClientUsername))
        or hasName(normalized, readString(getCurrentUserSteamID)) then return true end
    local gotPlayer, player = SC.Call.protected(getPlayer)
    if gotPlayer and player then
        for _, getter in ipairs({"getUsername", "getDisplayName"}) do
            local ok, name = SC.Call.method(player, getter)
            if ok and hasName(normalized, name) then return true end
        end
    end
    return false
end

local function input(value)
    if type(value) ~= "string" then return nil end
    local text = value:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", " ")
    return text:match("^%s*(.-)%s*$")
end

local function version(value)
    if type(value) == "string" and #value <= 24
        and (value:match("^%d+%.%d+%.%d+$") or value:match("^%d+%.%d+$")) then return value end
    return "unavailable"
end

local function gameBuild()
    -- The pause screen includes the patch and revision. getGameVersion() on
    -- Build 42 only returns the family (e.g. 42.22). Integrity notes on the
    -- same menu line may contain other text; export only validated tokens.
    local _, core = SC.Call.protected(getCore)
    local ok, display = SC.Call.method(core, "getVersion")
    if ok and type(display) == "string" then
        local first, revision = display:match("^(%S+)%s*(%S*)")
        if version(first) ~= "unavailable" and first:match("^%d+%.%d+%.%d+$") then
            if #revision >= 7 and #revision <= 40 and revision:match("^%x+$") then
                return first .. " " .. revision
            end
            return first
        end
    end
    local gotBuild, build = SC.Call.method(core, "getGameAndBuildVersion")
    if gotBuild and version(build) ~= "unavailable" then return build end
    local family = version(readString(getGameVersion))
    if family:match("^%d+%.%d+$") then return family .. " (patch unavailable)" end
    return family
end

local function protocol(value)
    if type(value) == "string" and #value <= 48 and value:match("^%d+%.%d+%-isocompanion%-%d+$") then return value end
    return "unavailable"
end

local function logs()
    local ok, observed = SC.Call.static(SCBridge, "getProtocol")
    local lines = {
        "Bridge protocol (loaded): " .. protocol(ok and observed),
        "Bridge protocol (expected): " .. protocol(SC.Identity.bridgeProtocol),
        "Recent Living Fellows log:",
    }
    local recent = SC.Diagnostics.recentReportLines()
    if #recent == 0 then lines[#lines + 1] = "No recent entries." end
    for _, line in ipairs(recent) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

-- Kahlua strings contain Java UTF-16 code units. GitHub expects UTF-8 bytes
-- in query parameters, including four-byte sequences for supplementary text.
local function encode(value)
    local result = {}
    local function byte(n)
        result[#result + 1] = string.format("%%%02X", n)
    end
    local index = 1
    while index <= #value do
        local c = string.byte(value, index)
        local char = value:sub(index, index)
        index = index + 1
        if c >= 0xD800 and c <= 0xDBFF then
            local low = index <= #value and string.byte(value, index) or 0
            if low < 0xDC00 or low > 0xDFFF then return nil end
            c = (c - 0xD800) * 1024 + low - 0xDC00 + 0x10000
            index = index + 1
        elseif c >= 0xDC00 and c <= 0xDFFF then
            return nil
        end
        if c < 128 and char:match("^[%w%.~_%-]$") then
            result[#result + 1] = char
        elseif c < 128 then
            byte(c)
        elseif c < 2048 then
            byte(192 + math.floor(c / 64))
            byte(128 + c % 64)
        elseif c < 65536 then
            byte(224 + math.floor(c / 4096))
            byte(128 + math.floor(c / 64) % 64)
            byte(128 + c % 64)
        else
            byte(240 + math.floor(c / 262144))
            byte(128 + math.floor(c / 4096) % 64)
            byte(128 + math.floor(c / 64) % 64)
            byte(128 + c % 64)
        end
    end
    return table.concat(result)
end

function report.buildDraft(what, steps)
    what, steps = input(what), input(steps)
    if not what or what == "" or not steps or steps == "" then
        return nil, "Describe what happened and enter the steps you took."
    end
    if #what > maxFieldLength or #steps > maxFieldLength then
        return nil, "Keep each answer within 500 characters."
    end
    local combined = what .. "\n" .. steps
    if combined:gsub("\n", " "):find("%c") or hasPrivateInput(combined) then
        return nil, "Remove names, file paths, links or contact details, then review again."
    end
    local firstLine = what:match("^[^\n]+")
    local last = math.min(65, #firstLine)
    if firstLine:byte(last) >= 0xD800 and firstLine:byte(last) <= 0xDBFF then last = last - 1 end
    local title = "[Bug] " .. firstLine:sub(1, last)
    local values = {
        {"title", "Issue title", title},
        {"problem", "What happened", what},
        {"reproduce", "Steps to reproduce", steps},
        {"mod-version", "Living Fellows version", version(SC.Identity.release)},
        {"game-version", "Project Zomboid version", gameBuild()},
        {"logs", "Logs and media", logs()},
    }
    local url, preview = {issueForm}, {}
    for _, field in ipairs(values) do
        local encoded = encode(field[3])
        if not encoded then return nil, "Edit the unreadable character and review again." end
        url[#url + 1] = "&" .. field[1] .. "=" .. encoded
        preview[#preview + 1] = field[2] .. "\n" .. field[3]
    end
    local link = table.concat(url)
    if #link > maxUrlLength then return nil, "This link is too long. Shorten an answer and review again." end
    return {title = title, body = table.concat(preview, "\n\n"), url = link}
end

function report.openDraft(draft)
    if type(draft) == "table" and type(draft.url) == "string" then
        local ok, opened = SC.Call.static(SCBridge, "openBugReportDraft", draft.url)
        if ok and opened == true then return true end
    end
    return false, "The browser could not open. Copy the draft link to open it yourself."
end

return report
