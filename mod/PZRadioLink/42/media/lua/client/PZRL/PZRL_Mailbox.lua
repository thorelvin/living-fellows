--[[
PZ Radio Link -- file mailbox.

All paths resolve under LuaManager.getLuaCacheDir(), i.e. <userdir>/Zomboid/Lua.
Verified against 42.20.4:

  * getFileWriter(name, createIfMissing, append) rejects the call unless the name
    contains no ".." AND its extension is one of {ini, cfg, txt, log, json},
    case-sensitively. Hence .txt everywhere.
  * getFileReader / getFileInput / getFileOutput check only the ".." guard.
  * Both readers and writers are explicitly UTF-8.
  * Subdirectories are created automatically, so PZRL/<file>.txt is valid.
  * LuaFileWriter exposes only write/writeln/close. There is no flush(), so a
    write is open -> write -> close every time, and there is no rename.

Because the mod cannot rename, it cannot publish a state document atomically:
getFileWriter(name, true, false) truncates on open, and everything between that
truncation and close() is a window in which the host can read a partial file. The
mod therefore alternates between two slots and never truncates the slot holding
the newest complete document. The host takes the highest sequence that validates.
]]

PZRL = PZRL or {}

local Mailbox = {}
PZRL.Mailbox = Mailbox

Mailbox.DIR = "PZRL"
Mailbox.COMMAND_FILE = "PZRL/cmd.txt"
Mailbox.STATE_FILES = { "PZRL/state_a.txt", "PZRL/state_b.txt" }
Mailbox.MAX_LINE_BYTES = 20480

Mailbox._stateSlot = 1
Mailbox._stateSeq = 0
Mailbox._lastCommandSeq = -1
Mailbox._faults = 0
Mailbox.MAX_FAULTS = 20

local function faulted(reason)
    Mailbox._faults = Mailbox._faults + 1
    if Mailbox._faults <= 3 then
        print("[PZRL] mailbox fault: " .. tostring(reason))
    elseif Mailbox._faults == Mailbox.MAX_FAULTS then
        print("[PZRL] mailbox fault limit reached; further faults are silent")
    end
    return nil, reason
end

function Mailbox.resetFaults()
    Mailbox._faults = 0
end

function Mailbox.degraded()
    return Mailbox._faults >= Mailbox.MAX_FAULTS
end

-- Reads at most three lines. A document longer than that is malformed by
-- definition, and refusing to read further bounds the work a corrupt or hostile
-- file can cause on the game thread.
local function readFramed(path)
    local ok, result = pcall(function()
        local reader = getFileReader(path, false)
        if reader == nil then return nil end
        local lines = {}
        local success, err = pcall(function()
            for _ = 1, 3 do
                local line = reader:readLine()
                if line == nil then break end
                if #line > Mailbox.MAX_LINE_BYTES then error("line_too_long") end
                lines[#lines + 1] = line
            end
        end)
        pcall(function() reader:close() end)
        if not success then error(err) end
        return lines
    end)
    if not ok then return faulted(result) end
    if result == nil then return nil, "absent" end
    return PZRL.Codec.parse(result[1], result[2], result[3])
end

local function writeFramed(path, text)
    local ok, err = pcall(function()
        local writer = getFileWriter(path, true, false)
        if writer == nil then error("writer_rejected") end
        local success, werr = pcall(function() writer:write(text) end)
        -- close() is the only way to flush; it must run even if write failed.
        pcall(function() writer:close() end)
        if not success then error(werr) end
    end)
    if not ok then return faulted(err) end
    return true
end

-- Publishes a state document into the slot that is NOT currently newest, so a
-- torn write can never destroy the last good snapshot.
function Mailbox.publishState(pairs_)
    if Mailbox.degraded() then return false end
    Mailbox._stateSeq = Mailbox._stateSeq + 1
    local text, err = PZRL.Codec.frame(Mailbox._stateSeq, pairs_)
    if text == nil then return faulted(err) end
    local target = Mailbox.STATE_FILES[Mailbox._stateSlot]
    if not writeFramed(target, text) then return false end
    Mailbox._stateSlot = (Mailbox._stateSlot == 1) and 2 or 1
    return true
end

-- Returns (fields, seq) for a command document the mod has not seen before, or
-- nil. A replayed or stale sequence is dropped here rather than in the command
-- handler, so a stuck host cannot re-trigger an action by rewriting the same file.
function Mailbox.pollCommand()
    if Mailbox.degraded() then return nil end
    local fields, seq = readFramed(Mailbox.COMMAND_FILE)
    if fields == nil then return nil end
    if type(seq) ~= "number" then return nil end
    if seq <= Mailbox._lastCommandSeq then return nil end
    Mailbox._lastCommandSeq = seq
    return fields, seq
end

-- A fresh game session must not inherit the command-sequence watermark of the
-- previous one, and must not act on a file written before it started.
function Mailbox.beginSession()
    Mailbox._stateSlot = 1
    Mailbox._stateSeq = 0
    Mailbox._lastCommandSeq = -1
    Mailbox.resetFaults()
    local fields, seq = readFramed(Mailbox.COMMAND_FILE)
    if fields ~= nil and type(seq) == "number" then
        -- Consume whatever is already on disk without executing it.
        Mailbox._lastCommandSeq = seq
    end
end

return Mailbox
