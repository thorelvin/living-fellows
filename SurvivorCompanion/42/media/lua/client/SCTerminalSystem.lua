-- SPDX-License-Identifier: MIT
-- LARCH/OS security is pure Lua. The terminal owns persistence and native XP.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalSystem = {}
local System = SC.TerminalSystem
System.MEMORY_KEY = "LF_LarchOS"
System.COMPANY = "Larchfield Business Machines"
System.TITLE = "LARCH/OS 2.4"
System.XP = 5
System.LOCK_HOURS = 1
System.LOCK_PERCENT = 40
local WORDS = {
    "MARKET", "MASKED", "MASTER", "MANTLE", "MARBLE", "MARGIN",
    "PLANET", "PLANTS", "PLATES", "PLACED", "PLANES", "PLAYER",
    "SCREEN", "SCREWS", "SCROLL", "SCRIPT", "SWITCH", "SIGNAL",
    "STORED", "STORMS", "STONES", "STOVES", "STRAND", "STREAM",
    "FOLDER", "FORGED", "FORMER", "FORCED", "FOREST", "FORMAT",
    "GROUND", "GRAVEL", "GREASE", "GARDEN", "GARAGE", "GATHER",
    "LOCKED", "LOOKED", "LOADED", "LODGED", "LONGER", "LONELY",
    "LETTER", "LATTER", "LATELY", "LISTEN", "LITTLE", "LITTER",
}
local JUNK = "!@#$%^&*-=+;:,.?/|~"
local PAIRS = { { "[", "]" }, { "(", ")" }, { "{", "}" }, { "<", ">" } }

local function integer(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge
        or value < minimum or value > maximum then return nil end
    return math.floor(value)
end
local function hours(value)
    value = tonumber(value)
    return value and value == value and value >= 0 and value < 100000000 and value or nil
end
local function rng(seed)
    local state = seed
    return function(count)
        state = (state * 48271) % 2147483647
        return (state % count) + 1
    end
end
local function settings(skill)
    skill = integer(skill, 0, 10) or 0
    return math.max(6, 16 - math.floor(skill / 2) * 2), 4 + math.floor(skill / 3)
end
local function tokens(seed)
    local pick, result = rng(seed), {}
    for index, pair in ipairs(PAIRS) do
        local body = ""
        for _ = 1, 4 do
            local at = pick(#JUNK)
            body = body .. JUNK:sub(at, at)
        end
        result[index] = pair[1] .. body .. pair[2]
    end
    return result
end

function System.create(seed, kind, insideCamp, legacy, identity, brand)
    seed = integer(seed, 1, 2147483646) or 1
    return { schema = 1, seed = seed, identity = identity or ("pc:" .. seed),
        archive = SC.TerminalFiles.choose(kind, seed, brand).id,
        theme = SC.TerminalPresentation.themeFor(seed),
        locked = not insideCamp and not legacy and seed % 100 < System.LOCK_PERCENT,
        xpAwarded = false }
end

function System.ensurePuzzle(state, skill)
    if state.puzzle then return state.puzzle end
    skill = integer(skill, 0, 10) or 0
    local count, tries = settings(skill)
    local pick, pool, words = rng(state.seed), {}, {}
    for index, word in ipairs(WORDS) do pool[index] = word end
    for index = 1, count do words[index] = table.remove(pool, pick(#pool)) end
    state.puzzle = { skill = skill, words = words, answer = words[pick(#words)],
        tries = tries, maximum = tries, guessed = {}, removed = {}, used = {} }
    return state.puzzle
end

function System.normalize(saved)
    if type(saved) ~= "table" or saved.schema ~= 1 then return nil end
    local seed = integer(saved.seed, 1, 2147483646)
    if not seed or not SC.TerminalFiles.get(saved.archive)
        or type(saved.identity) ~= "string" or #saved.identity == 0 or #saved.identity > 96
        or saved.identity:find("[%c]")
        or type(saved.locked) ~= "boolean" then return nil end
    if saved.theme ~= nil and not SC.TerminalPresentation.THEMES[saved.theme] then return nil end
    local clean = { schema = 1, seed = seed, identity = saved.identity, archive = saved.archive,
        theme = saved.theme or SC.TerminalPresentation.themeFor(seed),
        locked = saved.locked, xpAwarded = saved.xpAwarded == true }
    if saved.brand ~= nil then
        if type(saved.brand) ~= "string" or #saved.brand > 80 or not saved.brand:match("^[%w_ %-]+$") then return nil end
        clean.brand = saved.brand
    end
    clean.paletteVersion = integer(saved.paletteVersion, 1, SC.TerminalPresentation.PALETTE_VERSION)
    if saved.puzzle == nil then return clean end
    local p = saved.puzzle
    if type(p) ~= "table" then return nil end
    local skill = integer(p.skill, 0, 10)
    if not skill then return nil end
    local count, maximum = settings(skill)
    if type(p.words) ~= "table" or type(p.answer) ~= "string"
        or not integer(p.tries, 0, maximum) then return nil end
    local puzzle = { skill = skill, words = {}, answer = p.answer,
        tries = math.floor(p.tries), maximum = maximum, guessed = {}, removed = {}, used = {} }
    local seen, found = {}, false
    for index = 1, count do
        local word = p.words[index]
        if type(word) ~= "string" or #word ~= 6 or not word:match("^[A-Z]+$")
            or seen[word] then return nil end
        seen[word], puzzle.words[index] = true, word
        if word == p.answer then found = true end
        if type(p.guessed) == "table" then
            puzzle.guessed[word] = integer(p.guessed[word], 0, 6)
        end
        if word ~= p.answer and type(p.removed) == "table" and p.removed[word] == true then
            puzzle.removed[word] = true
        end
    end
    if not found then return nil end
    for index = 1, #PAIRS do
        puzzle.used[index] = type(p.used) == "table" and p.used[index] == true or nil
    end
    if p.lockoutUntil ~= nil then
        puzzle.lockoutUntil = hours(p.lockoutUntil)
        if not puzzle.lockoutUntil then return nil end
    end
    if clean.locked and puzzle.tries == 0 and not puzzle.lockoutUntil then return nil end
    clean.puzzle = puzzle
    return clean
end

function System.factoryReset(state)
    local clean = System.normalize(state)
    if not clean or clean.locked then return nil end
    -- Keep the physical machine, access recovery and one-time XP ledger.
    -- A blank archive prevents discovery from assigning another old owner.
    clean.archive, clean.brand = "_factory", "_camp"
    clean.paletteVersion = SC.TerminalPresentation.PALETTE_VERSION
    return clean
end

function System.status(state, now)
    if not state.locked then return "open" end
    local p = state.puzzle
    if p and p.lockoutUntil then
        now = hours(now)
        if not now or now < p.lockoutUntil then return "lockout" end
        -- Keep the same words, guesses, removed candidates and spent brackets.
        p.lockoutUntil, p.tries = nil, p.maximum
    end
    return "locked"
end

function System.likeness(a, b)
    local count = 0
    for index = 1, math.min(#a, #b) do
        if a:sub(index, index) == b:sub(index, index) then count = count + 1 end
    end
    return count
end

function System.act(state, raw, now)
    if not state.locked then return "open" end
    if not hours(now) then return "clock_unavailable" end
    if System.status(state, now) == "lockout" then return "lockout" end
    local p = state.puzzle
    if not p then return "unavailable" end
    if type(raw) ~= "string" or #raw > 96 then return "invalid" end
    raw = string.upper(raw:match("^%s*(.-)%s*$"))
    for index, token in ipairs(tokens(state.seed)) do
        if raw == token then
            if p.used[index] then return "used" end
            p.used[index] = true
            if index == #PAIRS then
                p.tries = p.maximum
                return "restored"
            end
            for _, word in ipairs(p.words) do
                if word ~= p.answer and not p.removed[word] and p.guessed[word] == nil then
                    p.removed[word] = true
                    return "removed"
                end
            end
            return "no_candidates"
        end
    end
    if p.removed[raw] then return "removed_word" end
    for _, word in ipairs(p.words) do
        if raw == word then
            if raw == p.answer then
                p.guessed[raw] = 6
                state.locked = false
                return "success"
            end
            if p.guessed[raw] ~= nil then return "repeat", p.guessed[raw] end
            local likeness = System.likeness(raw, p.answer)
            p.guessed[raw], p.tries = likeness, p.tries - 1
            if p.tries <= 0 then p.lockoutUntil = now + System.LOCK_HOURS end
            return p.tries <= 0 and "failed" or "wrong", likeness
        end
    end
    return "invalid"
end

-- Stable screen and explicit hit spans; arbitrary junk never becomes an action.
function System.board(state, columns)
    local p = state.puzzle
    if not p then return {} end
    columns = math.max(12, math.min(64, math.floor(columns or 60)))
    local across = columns >= 32 and 2 or 1
    local cell = math.floor((columns - 5) / across)
    local pick, entries, rows = rng(state.seed), {}, {}
    for _, word in ipairs(p.words) do
        entries[#entries + 1] = { value = word, disabled = p.removed[word] == true,
            tried = p.guessed[word] ~= nil }
    end
    for index, token in ipairs(tokens(state.seed)) do
        entries[#entries + 1] = { value = token, disabled = p.used[index] == true }
    end
    for first = 1, #entries, across do
        local row = { text = string.format("%04X ", 1024 + (#rows * columns)), spans = {} }
        for offset = 0, across - 1 do
            local entry = entries[first + offset]
            if entry then
                local text = ""
                for _ = 1, cell do
                    local at = pick(#JUNK)
                    text = text .. JUNK:sub(at, at)
                end
                local at = pick(math.max(1, cell - #entry.value + 1))
                local shown = entry.disabled and string.rep(".", #entry.value) or entry.value
                row.spans[#row.spans + 1] = { start = #row.text + at, length = #entry.value,
                    value = entry.value, disabled = entry.disabled, tried = entry.tried }
                row.text = row.text .. text:sub(1, at - 1) .. shown .. text:sub(at + #shown)
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end

function System.brackets(state) return tokens(state.seed) end
