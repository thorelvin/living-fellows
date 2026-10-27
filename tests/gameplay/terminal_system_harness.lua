-- SPDX-License-Identifier: MIT
local System, Files = SurvivorCompanion.TerminalSystem, SurvivorCompanion.TerminalFiles
local checks = 0
local function check(value, reason) checks = checks + 1 assert(value, reason) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end
local locked = 0
for seed = 1, 1000 do
    local state = System.create(seed, "police", false, false)
    if state.locked then locked = locked + 1 end
    check(not System.create(seed, "police", true, false).locked, "new camp computers are accessible")
    check(not System.create(seed, "police", false, true).locked, "existing EMMA access is preserved")
    check(Files.get(state.archive).kind == "police", "a police computer has police files")
end
check(locked == 400, "exactly forty percent of uniform seeds outside camp are locked")
local owners, count = {}, 0
for _, profile in ipairs(Files.all()) do
    check(not owners[profile.id], "archive identities are unique")
    owners[profile.id] = true
    check(#profile.entries == 4, "each initial owner has four entries")
    local previous = ""
    for _, entry in ipairs(profile.entries) do
        check(entry.date:match("^1993%-07%-%d%d$") and entry.date >= previous
            and entry.date <= "1993-07-09", "entries follow a July 1993 timeline")
        check(#entry.title < 80 and #entry.text < 1024 and not entry.text:find("[^\032-\126]"),
            "original archive text is bounded and ASCII")
        previous, count = entry.date, count + 1
    end
end
check(count == 516 and #Files.all()==129, "129 previous owners provide 516 original entries")
for name, kind in pairs({ policestorage = "police", medicaloffice = "clinic",
    hospitalroom = "clinic", insuranceoffice = "office", bedroom = "home", unknown = "general" }) do
    check(Files.classify(name) == kind, "room classification: " .. name)
end
check(System.likeness("MARKET", "MASKED") == 4
    and System.likeness("SCREEN", "SCREEN") == 6
    and System.likeness("ABCDEF", "FEDCBA") == 0, "feedback counts matching positions")
local lastWords, lastTries = 100, 0
for skill = 0, 10 do
    local state = System.create(20, "home", false, false)
    local p = System.ensurePuzzle(state, skill)
    check(#p.words <= lastWords and p.maximum >= lastTries, "Electrical skill makes recovery easier")
    lastWords, lastTries = #p.words, p.maximum
    for _, width in ipairs({ 12, 20, 31, 32, 48, 64 }) do
        for _, row in ipairs(System.board(state, width)) do
            check(#row.text <= width, "the recovery screen fits its text columns")
            for _, span in ipairs(row.spans) do
                check(row.text:sub(span.start, span.start + span.length - 1) == span.value,
                    "click targets match displayed words and brackets")
            end
        end
    end
end
local state = System.create(20, "office", false, false)
local p = System.ensurePuzzle(state, 0)
local initialWords, answer, archive = table.concat(p.words, ","), p.answer, state.archive
local wrong
for _, word in ipairs(p.words) do if word ~= p.answer then wrong = word break end end
local before = p.tries
check(System.act(state, "not a candidate", 100) == "invalid" and p.tries == before, "invalid input costs no attempt")
check(System.act(state, wrong, nil) == "clock_unavailable" and p.tries == before,
    "an unreadable clock cannot spend an attempt or invent a lockout deadline")
local code, score = System.act(state, wrong, 100)
check(code == "wrong" and score == System.likeness(wrong, answer), "a valid wrong guess returns true likeness")
check(System.act(state, wrong, 100) == "repeat" and p.tries == before - 1, "repeated guesses do not spend attempts")
local groups = System.brackets(state)
check(System.act(state, groups[1], 100) == "removed" and not p.removed[answer],
    "a hidden group removes a wrong candidate, never the password")
local removed
for word in pairs(p.removed) do removed = word end
before = p.tries
check(System.act(state, removed, 100) == "removed_word" and p.tries == before,
    "an eliminated candidate cannot consume an attempt")
check(System.act(state, groups[4], 100) == "restored" and p.tries == p.maximum,
    "the recovery group restores attempts")
for _, word in ipairs(p.words) do
    if word ~= answer and p.guessed[word] == nil and not p.removed[word] then
        System.act(state, word, 100)
        if p.lockoutUntil then break end
    end
end
check(p.tries == 0 and p.lockoutUntil == 101, "failure locks the computer for one game hour")
check(System.act(state, answer, 100.999) == "lockout" and state.locked, "the correct word cannot bypass a lockout")
state = System.normalize(copy(state))
p = state.puzzle
check(state and System.status(state, nil) == "lockout", "reload preserves the lockout and waits for a game clock")
check(System.status(state, 101) == "locked" and p.tries == p.maximum, "attempts return exactly at the game-time deadline")
check(table.concat(p.words, ",") == initialWords and p.answer == answer and state.archive == archive,
    "the same puzzle and files survive timeout and reload")
check(System.act(state, groups[4], 101) == "used", "timeout does not replenish spent bracket bonuses")
check(System.act(state, answer, 101) == "success" and not state.locked and p.guessed[answer] == 6,
    "a verified password unlocks the machine")
check(System.act(state, answer, 101) == "open", "repeating success cannot trigger another unlock")
check(System.normalize(copy(state)).locked == false, "unlocked status survives reload")
local malformed = copy(state)
malformed.puzzle.answer = "BROKEN"
check(System.normalize(malformed) == nil, "an absent answer rejects the record rather than rerolling")
malformed = copy(state)
malformed.schema = 999
check(System.normalize(malformed) == nil, "unsupported schemas fail closed")
malformed = copy(state)
malformed.seed = 0/0
check(System.normalize(malformed) == nil, "nonfinite identities are rejected")
malformed = copy(state)
malformed.puzzle.guessed.unrelated = { recursive = malformed }
local clean = System.normalize(malformed)
check(clean and clean.puzzle.guessed.unrelated == nil, "normalization reads only bounded known fields")
SC_TEST_REPORT = (SC_TEST_REPORT and (SC_TEST_REPORT .. "; ") or "")
    .. "LARCH/OS security and archive harness: " .. checks .. " checks passed"
