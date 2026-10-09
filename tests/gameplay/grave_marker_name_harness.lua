-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local work = SC.BaseWork
local crisis = SC.InfectionCrisis
local spriteName = "location_community_cemetary_01_38"

local function cross()
    local result = { data = {}, transmissions = 0 }
    function result:getSprite() return { getName = function() return spriteName end } end
    function result:getModData() return self.data end
    function result:setName(name) self.name = name end
    function result:transmitModData() self.transmissions = self.transmissions + 1 end
    return result
end

local marker = cross()
local square = { objects = { marker } }
local job = {
    id = "job:1", type = "build", recipeId = "WoodCross", face = 1,
    target = { square = square }, fallenName = "Sarah Shaw",
    fallenDisplayName = 'Sarah "Doc" Shaw',
}
assert(work._nameFallenMarkerForTests(job, square, spriteName) == true,
    "fallen cross must be nameable")
assert(marker.name == 'Sarah "Doc" Shaw'
    and marker.data.LF_FallenName == "Sarah Shaw"
    and marker.data.LF_FallenDisplayName == 'Sarah "Doc" Shaw'
    and marker.data.LF_FallenMarker == true and marker.transmissions == 1,
    "cross keeps raw identity and a visible decorated name")

local ordinary = cross()
assert(work._nameFallenMarkerForTests({ type = "build", recipeId = "WoodCross" },
    { objects = { ordinary } }, spriteName) == false
    and ordinary.name == nil and ordinary.data.LF_FallenMarker == nil,
    "ordinary crosses stay untouched")
assert(work._nameFallenMarkerForTests(job, { objects = { ordinary } }, "other_sprite") == false
    and ordinary.name == nil, "a different object cannot inherit the name")

work.recipeSprite = function() return spriteName end
local reconciled = work.reconcileBuildJob(job, nil)
assert(reconciled == true and SC_TEST_GRAVE_JOB_COMPLETED[1] == job.id
    and SC_TEST_GRAVE_JOB_COMPLETED[3] == "built",
    "a player-built queued cross is named before job completion")

local function item()
    local value = { type = "Base.Locket", name = "Lucky locket" }
    function value:getDisplayName() return self.name end
    function value:setName(name) self.name = name end
    return value
end

local saved = item()
local subject = {
    id = "sc-sarah", rawName = "Sarah Shaw",
    displayName = 'Sarah "Doc" Shaw', inventory = { saved },
}
local memorialCrisis = {
    id = "crisis:1", subjectId = subject.id, subjectName = subject.rawName,
    participants = {}, artifacts = {},
}
crisis._preserveKeepsakeForTests(memorialCrisis, subject, nil)
assert(memorialCrisis.artifacts.keepsake.storageId == "storage:1"
    and SC_TEST_MEMORIAL_CONTAINER[1] == saved
    and saved.type == "Base.Locket"
    and saved.name == 'Lucky locket (Sarah "Doc" Shaw)',
    "memorial storage keeps the exact item and shows its owner's full name")

local handed = item()
local secondSubject = {
    id = "sc-sarah-2", rawName = "Sarah Shaw",
    displayName = 'Sarah "Doc" Shaw', inventory = { handed },
}
local recipient = { id = "sc-recipient", inventory = {} }
SC_TEST_RECIPIENT = recipient
local handedCrisis = {
    id = "crisis:2", subjectId = secondSubject.id,
    subjectName = secondSubject.rawName,
    participants = { [recipient.id] = { stance = "protective" } },
    artifacts = {},
}
crisis._preserveKeepsakeForTests(handedCrisis, secondSubject, nil)
assert(handedCrisis.artifacts.keepsake.recipientId == recipient.id
    and recipient.inventory[1] == handed
    and handed.name == "Lucky locket",
    "recipient handoff leaves the item name unchanged")

print("GRAVE_MARKER_NAME_KAHLUA_PASS checks=6")
