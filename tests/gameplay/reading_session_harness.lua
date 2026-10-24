-- SPDX-License-Identifier: MIT
local SC, checks = SurvivorCompanion, 0
local D, S = SC.Downtime, SC.ActionSupervisor
local function check(value, message)
    checks = checks + 1
    assert(value, "reading session " .. checks .. ": " .. message)
end
local candidate = D._readingForTests()
local _, _, _, begin, _, _, _, _, _, _, _, stateFor = D._furnitureForTests()
local quiet = { snapshot = { threatCount = 0, immediateCount = 0 } }
local function start(actor, activity)
    local accepted, why = begin(actor, stateFor(actor), activity,
        actor.commands, SC_READING_CLOCK)
    check(accepted, "reading starts: " .. tostring(why))
    return S.current(actor)
end
local function at(actor, elapsed)
    SC_READING_CLOCK = actor.visual.at + elapsed
    S.update(actor)
    return D.update(actor, nil, quiet, "read")
end
local function pages(actor, book)
    return (actor.data.SC_ReadingPages or {})[book:getFullType()] or 0
end
do
    local book = SC_READING_BOOK("Duration")
    local actor = SC_READING_ACTOR("reader:duration", { book })
    local activity = candidate(actor, { book })
    SC_READING_RANDOM.values = { 60000 }
    local callsBefore = SC_READING_RANDOM.calls
    local token = start(actor, activity)
    check(activity.durationMs == 60000
            and actor.lastIntent.durationMs == activity.durationMs,
        "the inclusive one-minute endpoint reaches the native Read request")
    check(SC_READING_RANDOM.calls == callsBefore + 1
            and SC_READING_RANDOM.low == 60000 and SC_READING_RANDOM.high == 180001,
        "a new session samples one inclusive 60000-through-180000ms duration")
    check(token.deadlines.animating > activity.durationMs,
        "the supervisor deadline outlasts the longer reading animation")
    at(actor, 6000)
    check(D.peek(actor).active == activity and pages(actor, book) == 0,
        "the former six-second endpoint gives no early page reward")
    at(actor, 13000)
    check(S.isCurrent(token) and D.peek(actor).active == activity,
        "reading survives the former twelve-second animation deadline")
    at(actor, 24000)
    check(D.peek(actor).active == activity and pages(actor, book) == 0,
        "the former twenty-four-second chapter no longer finishes reading early")
    at(actor, activity.durationMs - 1)
    check(D.peek(actor).active == activity and pages(actor, book) == 0
            and activity.durationMs == 60000 and SC_READING_RANDOM.calls == callsBefore + 1,
        "polling keeps the same session duration and never samples it again")
    at(actor, activity.durationMs)
    check(D.peek(actor).active == nil and pages(actor, book) == 5
            and S.current(actor) == nil,
        "one longer completed chapter grants the existing five-percent page increment")
    SC_READING_RANDOM.values = { 180000, 90000 }
    activity = candidate(actor, { book })
    start(actor, activity)
    check(activity.durationMs == 180000 and actor.lastIntent.durationMs == 180000
            and SC_READING_RANDOM.calls == callsBefore + 2,
        "the same reader can independently choose the inclusive three-minute endpoint next")
    at(actor, activity.durationMs - 1)
    check(D.peek(actor).active == activity and pages(actor, book) == 5,
        "the longest chapter remains active until its full three minutes end")
    at(actor, activity.durationMs)
    check(D.peek(actor).active == nil and pages(actor, book) == 10,
        "a three-minute chapter still grants one chapter of page progress")
    activity = candidate(actor, { book })
    start(actor, activity)
    check(activity.durationMs == 90000 and SC_READING_RANDOM.calls == callsBefore + 3,
        "each subsequent session samples a fresh independent duration")
    D.cancel(actor, "fixture_done")
end
do
    local previous = SC.Config._values.downtimeActivityMs
    SC.Config._values.downtimeActivityMs = 9000
    local book = SC_READING_BOOK("Configured")
    local actor = SC_READING_ACTOR("reader:configured", { book })
    local activity = candidate(actor, { book })
    SC_READING_RANDOM.values = { 120000 }
    start(actor, activity)
    check(activity.durationMs == 120000 and actor.lastIntent.durationMs == 120000,
        "ordinary action timing does not rescale the chosen one-to-three-minute chapter")
    D.cancel(actor, "fixture_done")
    SC.Config._values.downtimeActivityMs = previous
    local writer = SC_READING_ACTOR("reader:diary")
    local callsBefore = SC_READING_RANDOM.calls
    start(writer, { kind = "write_diary", fact = {} })
    check(writer.lastIntent.durationMs == previous and SC_READING_RANDOM.calls == callsBefore,
        "the shared Read pose does not lengthen or randomize diary writing")
    D.cancel(writer, "fixture_done")
end
do
    local book = SC_READING_BOOK("Borrowed")
    local source = SC_READING_INVENTORY({ book })
    local shelf = { x = 10.5, y = 11.5, z = 0 }
    local actor = SC_READING_ACTOR("reader:borrowed")
    actor.data.SC_ReadingPages = { [book:getFullType()] = 95 }
    local activity = { kind = "read", item = book, fact = { activity = "read" },
        borrowedFrom = source, borrowedOwner = shelf }
    SC_READING_RANDOM.values = { 180000 }
    start(actor, activity)
    check(book.container == actor.inventory and actor.lastIntent.durationMs == 180000,
        "library checkout keeps the exact book for the full selected three-minute chapter")
    at(actor, 6000)
    check(book.container == actor.inventory and pages(actor, book) == 95,
        "an unfinished native chapter cannot return or credit the borrowed book early")
    at(actor, activity.durationMs)
    check(pages(actor, book) == 100 and book.container == source
            and book.data.SC_BookLoan == nil and actor.finishedTitle == book,
        "the last verified chapter returns the exact finished loan to its shelf")
end
do
    local book = SC_READING_BOOK("Danger")
    local actor = SC_READING_ACTOR("reader:danger", { book })
    start(actor, candidate(actor, { book }))
    SC_READING_CLOCK = SC_READING_CLOCK + 7000
    D.update(actor, nil, { snapshot = { immediateCount = 1 } }, "read")
    check(D.peek(actor).active == nil and S.current(actor) == nil
            and actor.visual == nil and pages(actor, book) == 0
            and book.container == actor.inventory,
        "danger immediately interrupts a long chapter without pages or lost gear")
    local nextBook = SC_READING_BOOK("Order")
    local ordered = SC_READING_ACTOR("reader:ordered", { nextBook })
    start(ordered, candidate(ordered, { nextBook }))
    ordered.commands.commandSerial = ordered.commands.commandSerial + 1
    D.update(ordered, nil, quiet, "read")
    check(D.peek(ordered).active == nil and S.current(ordered) == nil
            and ordered.visual == nil and pages(ordered, nextBook) == 0,
        "a newer player order interrupts the long chapter immediately")
end
do
    local book = SC_READING_BOOK("Illiterate")
    local picture = SC_READING_BOOK("Picture")
    picture.tags = { PICTUREBOOK = true }
    local actor = SC_READING_ACTOR("reader:illiterate", { book, picture })
    actor.traits = { [CharacterTrait.ILLITERATE] = true }
    check(candidate(actor, { book }) == nil
            and candidate(actor, { picture }).item == picture,
        "the longer session preserves existing Illiterate and picture-book eligibility")
end
do
    local book = SC_READING_BOOK("BorrowedInterrupted")
    local source = SC_READING_INVENTORY({ book })
    local shelf = { x = 10.5, y = 11.5, z = 0 }
    local actor = SC_READING_ACTOR("reader:borrowed_interrupted")
    start(actor, { kind = "read", item = book, fact = { activity = "read" },
        borrowedFrom = source, borrowedOwner = shelf })
    SC_READING_CLOCK = SC_READING_CLOCK + 6000
    D.cancel(actor, "new_player_order")
    check(book.container == actor.inventory and #source.items == 0
            and book.data.SC_BookLoan.finished == false and pages(actor, book) == 0,
        "an interrupted unfinished loan stays the exact carried book with no page credit")
end
do
    SkillBook = { Carpentry = { perk = "Carpentry", maxMultiplier1 = 3 } }
    local book = SC_READING_BOOK("Skill")
    function book:getSkillTrained() return "Carpentry" end
    function book:getLvlSkillTrained() return 1 end
    function book:getMaxLevelTrained() return 2 end
    local actor = SC_READING_ACTOR("reader:skill", { book })
    function actor:getPerkLevel() return 0 end
    function actor:getXp() return { getMultiplier = function() return self.multiplier or 0 end } end
    function addXpMultiplier(reader, _, multiplier) reader.multiplier = multiplier end
    local activity = candidate(actor, { book })
    start(actor, activity)
    at(actor, activity.durationMs)
    check(pages(actor, book) == 5 and (actor.multiplier or 0) == 0,
        "random reading time does not multiply skill-book page rewards")
    SC_READING_CLOCK = SC_READING_CLOCK + 1
    activity = candidate(actor, { book })
    start(actor, activity)
    at(actor, activity.durationMs)
    check(pages(actor, book) == 10 and math.abs(actor.multiplier - 0.3) < 0.001,
        "the second long chapter grants the existing ten-percent skill multiplier step")
    SkillBook, addXpMultiplier = nil, nil
end
do
    local book = SC_READING_BOOK("Stalled")
    local actor = SC_READING_ACTOR("reader:stalled", { book })
    local activity = candidate(actor, { book })
    local token = start(actor, activity)
    actor.visual.stalled = true
    SC_READING_CLOCK = SC_READING_CLOCK + token.deadlines.animating + 1
    S.update(actor)
    check(S.current(actor) == nil and D.peek(actor).active == nil
            and actor.visual == nil and pages(actor, book) == 0,
        "a stalled long chapter still has a finite watchdog and releases ownership")
end
SC_TEST_REPORT = "READING_SESSION_PASS checks=" .. tostring(checks)
