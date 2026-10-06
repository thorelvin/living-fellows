-- SPDX-License-Identifier: MIT

local work = SurvivorCompanion.BaseWork
local previousEntity = ISBuildIsoEntity
local names = {
    wall_frame = "WoodenWallFrame",
    wall = "WoodenWallLvl1",
    floor = "WoodFloorLvl1",
    door_frame = "WoodDoorFrameLvl1",
    door = "WoodenDoorLvl1",
    grave_marker = "WoodCross",
}
local infos = {}
for _, name in pairs(names) do
    local scriptName = name == "WoodenWallLvl1" and "Base." .. name or name
    infos[#infos + 1] = { getScript = function()
        return { getName = function() return scriptName end }
    end }
end
ISBuildIsoEntity = { GetAllBuildableEntities = function() return infos end }
for kind, name in pairs(names) do
    assert(work.recipeForKind(kind) == name,
        "the Build 42 entity script must resolve for " .. kind)
    assert(work.recipeInfo(name) ~= nil,
        "the selected entity must have build info for " .. kind)
end
ISBuildIsoEntity = previousEntity
