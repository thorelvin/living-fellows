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

BF-06: close() is the flush boundary, so its failure means the document did not
land. Reporting success and rotating the slot after a failed close would put the
protected copy under the next write. Failures are also counted consecutively
rather than for the lifetime of the session, so intermittent I/O errors cannot
accumulate into permanent shutdown -- transport backs off and retries instead.
]]

PZRL = PZRL or {}

local Mailbox = {}
PZRL.Mailbox = Mailbox

Mailbox.DIR = "PZRL"
Mailbox.COMMAND_FILE = "PZRL/cmd.txt"
Mailbox.STATE_FILES = { "PZRL/state_a.txt", "PZRL/state_b.txt" }
Mailbox.MAX_LINE_BYTES = 20480

-- Backoff instead of a one-way kill switch. After this many consecutive
-- failures transport pauses, then retries on a slow probe; a single success
-- clears it.
Mailbox.FAULT_BACKOFF_AT = 5
Mailbox.BACKOFF_MS = 4000
Mailbox.MAX_BACKOFF_MS = 60000

Mailbox._stateSlot = 1
Mailbox._stateSeq = 0
Mailbox._lastCommandSeq = -1
Mailbox._consecutiveFaults = 0
Mailbox._lifetimeFaults = 0
Mailbox._retryAt = 0
Mailbox._backoff = Mailbox.BACKOFF_MS
Mailbox._loggedFaults = 0

local function now()
    return getTimestampMs()
end

local function faulted(reason)
    Mailbox._consecutiveFaults = Mailbox._consecutiveFaults + 1
    Mailbox._lifetimeFaults = Mailbox._lifetimeFaults + 1
    if Mailbox._loggedFaults < 3 then
        Mailbox._loggedFaults = Mailbox._loggedFaults + 1
        print("[PZRL] mailbox fault: " .. tostring(reason))
    end
    if Mailbox._consecutiveFaults >= Mailbox.FAULT_BACKOFF_AT then
        Mailbox._retryAt = now() + Mailbox._backoff
        Mailbox._backoff = math.min(Mailbox._backoff * 2, Mailbox.MAX_BACKOFF_MS)
    end
    return nil, reason
end

local function succeeded()
    if Mailbox._consecutiveFaults > 0 then
        Mailbox._consecutiveFaults = 0
        Mailbox._backoff = Mailbox.BACKOFF_MS
        Mailbox._retryAt = 0
        Mailbox._loggedFaults = 0
    end
end

-- True while backing off. Transport skips this cycle; it is not disabled.
function Mailbox.backingOff()
    return Mailbox._retryAt > 0 and now() < Mailbox._retryAt
end

function Mailbox.diagnostics()
    return {
        consecutive = Mailbox._consecutiveFaults,
        lifetime = Mailbox._lifetimeFaults,
        backingOff = Mailbox.backingOff(),
    }
end

--[[
Reads at most three lines. Note the honest limitation: readLine() has already
pulled the whole line into memory before the length is checked, so this bounds
what we *keep* and parse, not what the engine allocates. The engine exposes no
bounded read, so the producer-side payload cap is the real control.
]]
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
    succeeded()
    return PZRL.Codec.parse(result[1], result[2], result[3])
end

-- Returns true only when the bytes are known to have reached the file. close()
-- is the flush boundary, so a close failure means the document did not land.
local function writeFramed(path, text)
    local writer = nil
    local opened = pcall(function()
        writer = getFileWriter(path, true, false)
    end)
    if not opened or writer == nil then return faulted("writer_rejected") end

    local wroteOk, wroteErr = pcall(function() writer:write(text) end)
    local closedOk, closedErr = pcall(function() writer:close() end)

    if not wroteOk then return faulted(wroteErr) end
    if not closedOk then return faulted(closedErr) end
    succeeded()
    return true
end

-- Publishes into the slot that is NOT currently newest, and rotates only after
-- a confirmed close, so a failed publication cannot leave the protected copy as
-- the next write target.
function Mailbox.publishState(pairs_)
    if Mailbox.backingOff() then return false end
    local seq = Mailbox._stateSeq + 1
    local text, err = PZRL.Codec.frame(seq, pairs_)
    if text == nil then return faulted(err) end
    local target = Mailbox.STATE_FILES[Mailbox._stateSlot]
    if not writeFramed(target, text) then return false end
    Mailbox._stateSeq = seq
    Mailbox._stateSlot = (Mailbox._stateSlot == 1) and 2 or 1
    return true
end

-- A fresh game session must publish sequences above whatever survived from the
-- previous one, or the host would keep preferring an old slot.
function Mailbox.seedStateSequence()
    local highest = 0
    for _, path in ipairs(Mailbox.STATE_FILES) do
        local _, seq = readFramed(path)
        if type(seq) == "number" and seq > highest then highest = seq end
    end
    Mailbox._stateSeq = highest
end

function Mailbox.commandWatermark()
    return Mailbox._lastCommandSeq
end

-- Returns (fields, seq) for a command document not seen before, or nil. A
-- replayed or stale sequence is dropped here rather than in the handler, so a
-- stuck host cannot re-trigger an action by rewriting the same file.
function Mailbox.pollCommand()
    if Mailbox.backingOff() then return nil end
    local fields, seq = readFramed(Mailbox.COMMAND_FILE)
    if fields == nil then return nil end
    if type(seq) ~= "number" then return nil end
    if seq <= Mailbox._lastCommandSeq then return nil end
    Mailbox._lastCommandSeq = seq
    return fields, seq
end

-- A fresh game session must not inherit the previous one's watermark, and must
-- not act on a file written before it started.
function Mailbox.beginSession()
    Mailbox._stateSlot = 1
    Mailbox._lastCommandSeq = -1
    Mailbox._consecutiveFaults = 0
    Mailbox._retryAt = 0
    Mailbox._backoff = Mailbox.BACKOFF_MS
    Mailbox._loggedFaults = 0
    Mailbox.seedStateSequence()
    local fields, seq = readFramed(Mailbox.COMMAND_FILE)
    if fields ~= nil and type(seq) == "number" then
        -- Consume whatever is already on disk without executing it.
        Mailbox._lastCommandSeq = seq
    end
end

return Mailbox
