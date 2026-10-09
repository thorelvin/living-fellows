-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Diary = SC.Diary
local author = SC.Registry.byId("sc-tom")
local subject = SC.Registry.byId("sc-ruth")
assert(author and subject, "the diary fixture must provide two companions")
subject.identity = { forename = "Ruth", surname = "Park", gender = "female" }
subject.actor = subject
assert(SC.Names.setNickname(subject, "Scout", "player") == true,
    "the subject accepts a public nickname")

local writer = Diary.writerFor(author)
writer.candidates, writer.receipts, writer.subjectMentions = {}, {}, {}
assert(Diary.noteFallenBurial(author, "Ruth Park", subject.id) == true,
    "the author can record a named burial")
assert(writer.candidates[1].tokens.subject == "Ruth"
    and writer.candidates[1].subjectId == subject.id,
    "first reference uses the given name and keeps the subject identity")

DIARY_TEST_HOURS = math.max(DIARY_TEST_HOURS + 24, writer.nextWriteHours + 24)
SC_TEST_CLOCK = SC_TEST_CLOCK + 60000
local activity = Diary.writeActivity(author, SC_TEST_CLOCK)
assert(activity and activity.diary and activity.diary.draft,
    "the first reference is ready to become a page")
assert(string.find(activity.diary.draft.text, "Ruth", 1, true),
    "the first page actually mentions the subject")
assert(Diary.commitWrite(author, activity.diary) == true,
    "the first reference is committed to the diary")
assert(writer.subjectMentions[1] == subject.id,
    "a written mention records that this author has used the name")

assert(Diary.noteMercyKilling(author, {
    id = "nickname-mercy-1", subjectId = subject.id, subjectName = "Ruth Park",
}) == true, "a second subject event is recorded")
assert(writer.candidates[#writer.candidates].tokens.subject == "Scout",
    "a later reference uses the nickname from this author's perspective")

local saved = Diary.export()
assert(Diary.restore(saved) == true, "nickname mention history round trips")
writer = Diary.writerFor(author)
assert(Diary.noteMercyKilling(author, {
    id = "nickname-mercy-2", subjectId = subject.id, subjectName = "Ruth Park",
}) == true, "the restored author can record another event")
assert(writer.candidates[#writer.candidates].tokens.subject == "Scout",
    "the restored author remembers using the nickname")

saved.writers[author.id].subjectMentions = nil
assert(Diary.restore(saved) == true, "a writer saved before mention tracking restores")
writer = Diary.writerFor(author)
assert(Diary.noteMercyKilling(author, {
    id = "nickname-mercy-3", subjectId = subject.id, subjectName = "Ruth Park",
}) == true, "a legacy author can still record an event")
assert(writer.candidates[#writer.candidates].tokens.subject == "Ruth",
    "legacy writers start with the safe first-name form")

print("NICKNAME_DIARY_KAHLUA_PASS checks=11")
