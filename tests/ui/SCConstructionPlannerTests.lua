-- SPDX-License-Identifier: MIT

local planner = SurvivorCompanion.ConstructionPlanner
assert(planner ~= nil)

local horizontal = planner.lineTargets("wall", { x = 10, y = 20, z = 0 },
    { x = 13, y = 21, z = 0 }, 2, false)
assert(#horizontal == 4 and horizontal[1].target.x == 10
    and horizontal[4].target.x == 13 and horizontal[4].target.y == 20
    and horizontal[1].face == 2,
    "wall drag must produce a straight, inclusive run")
local vertical = planner.lineTargets("wall", { x = 10, y = 20, z = 0 },
    { x = 11, y = 17, z = 0 }, 1, true)
assert(#vertical == 4 and vertical[1].target.y == 17
    and vertical[4].target.y == 20 and vertical[1].face == 3,
    "rotated wall drag must use the opposite edge")
local single = planner.lineTargets("door", { x = 4, y = 5, z = 0 },
    { x = 9, y = 5, z = 0 }, 4, false)
assert(#single == 1 and single[1].face == 4,
    "doors must remain single segment plans")

local SC = SurvivorCompanion
local formerLife, formerWork = SC.BaseLife, SC.BaseWork
local formerEntity, formerObject = ISBuildIsoEntity, ISBuildingObject
local formerPane, formerCell = ISInventoryPaneContextMenu, getCell
local formerArrayList = ArrayList
local square = { x = 4, y = 5, z = 0 }
local player = { slot = 1, inventory = {} }
function player:getPlayerNum() return self.slot end
function player:getInventory() return self.inventory end
local job = { id = "job:1", type = "build", state = "pending",
    target = { x = 4, y = 5, z = 0 }, recipeId = "wood_wall", face = 2 }
local entity
SC.BaseLife = {
    job = function(id) assert(id == job.id); return job end,
    takeOverBuild = function(id)
        assert(id == job.id and job.state == "pending")
        job.state = "manual"
        return true, job
    end,
    releaseManualBuild = function(id, reason)
        assert(id == job.id and reason == "player_build_interrupted")
        job.state = "pending"
        return true, job
    end,
}
SC.BaseWork = {
    recipeInfo = function(id) assert(id == "wood_wall"); return {} end,
    reconcileBuildJob = function() return false, "build_not_present" end,
}
ISBuildIsoEntity = {
    new = function(_, actor)
        assert(actor == player)
        entity = { player = nil }
        function entity:isValid(target)
            assert(target == square and self.player == player.slot)
            return true
        end
        function entity:onActionComplete() self.cleaned = true end
        return entity
    end,
}
local action = {}
function action:setOnComplete(callback) self.complete = callback end
function action:setOnCancel(callback) self.cancel = callback end
ISBuildingObject = {
    tryBuild = function(value, x, y, z)
        assert(value == entity and value.player == player.slot
            and x == 4 and y == 5 and z == 0)
        return action
    end,
}
ISInventoryPaneContextMenu = { getContainers = function(actor)
    assert(actor == player)
    return { actor:getInventory() }
end }
getCell = function() return { getGridSquare = function(_, x, y, z)
    assert(x == 4 and y == 5 and z == 0)
    return square
end } end

local started, reason = planner.buildSegment(player, job.id)
assert(started == true and reason == "player_build_started"
    and job.state == "manual" and entity.player == 1,
    "player takeover must bind the native local player before build validation")
assert(type(action.cancel) == "function" and type(action.complete) == "function")
action.cancel()
assert(entity.cleaned == true and job.state == "pending",
    "cancelled native build must release the blueprint for another worker")

-- Planned barricades use vanilla's upright plank sprites on the target face.
local formerRender, formerSprite, formerIsoSprite, formerUtility =
    renderIsoLine, getSprite, IsoSprite, SC.GameplayUtil
ISBuildingObject = { derive = function()
    local class = {}
    class.__index = class
    function class:init() end
    function class:reinit() end
    return class
end }
renderIsoLine = function()
    error("barricade previews must not draw ground-level lines")
end
local ghosts = {}
IsoSprite = { new = function()
    return { LoadSingleTexture = function(self, name) self.name = name end,
        RenderGhostTileColor = function(self, x, y, z, r, g, b, alpha)
        ghosts[#ghosts + 1] = { name = self.name, x = x, y = y, z = z,
            r = r, g = g, b = b, alpha = alpha }
        end }
end }
getSprite = function() error("ghosts should use a private native sprite") end
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end
local window = {}
function window:getNorth() return false end
function window:getSquare() return square end
function window:getBarricadeOnSameSquare() return nil end
function window:getBarricadeOnOppositeSquare() return nil end
function window:isBarricadeAllowed() return true end
function window:IsOpen() return false end
SC.BaseLife = { isInside = function() return true end }
SC.GameplayUtil = { hasMethod = function(object, method)
    return type(object[method]) == "function"
end }
planner._resetCursorForTests()
local cursor = planner._cursorClassForTests():new(player, "barricade", window, "same")
cursor:render(10, 10, 0, square)
assert(cursor:getSprite() == "carpentry_01_8"
        and #ghosts == 1 and ghosts[1].name == "carpentry_01_8"
        and ghosts[1].x == 4 and ghosts[1].y == 5
        and ghosts[1].alpha == 0.85,
    "west-facing cursor ghost must use the native plank on its target door")
local blue = { r = 0.2, g = 0.7, b = 1 }
assert(planner.renderBarricadeGhost({ x = 4, y = 5, z = 0,
        north = false, side = "opposite" }, blue, 0.5)
        and ghosts[2].name == "carpentry_01_0"
        and ghosts[2].x == 3 and ghosts[2].y == 5,
    "opposite west face uses the native east plank on the west square")
assert(planner.renderBarricadeGhost({ x = 4, y = 5, z = 0,
        north = true, side = "same" }, blue, 0.5)
        and ghosts[3].name == "carpentry_01_9"
        and ghosts[3].x == 4 and ghosts[3].y == 5,
    "same north face uses the native north plank")
assert(planner.renderBarricadeGhost({ x = 4, y = 5, z = 0,
        north = true, side = "opposite" }, blue, 0.5)
        and ghosts[4].name == "carpentry_01_1"
        and ghosts[4].x == 4 and ghosts[4].y == 4,
    "opposite north face uses the native south plank on the north square")
-- Planning results are shown as translated text, never as internal codes.
local formerGetText = getText
getText = function(key) return "T:" .. key end
assert(planner.reasonText("build_outside_camp") == "T:UI_SC_Base_Plan_OutsideCamp"
        and planner.reasonText("an_internal_code") == "T:UI_SC_Base_Plan_Failed"
        and planner.acceptedText() == "T:UI_SC_Base_Plan_Accepted",
    "planning results map to translated text")
function player:setHaloNote(value) self.halo = value end
function window:isBarricadeAllowed() return false end
cursor:tryBuild(4, 5, 0)
assert(player.halo == "T:UI_SC_Base_Plan_Blocked",
    "an invalid barricade plan shows translated text, not its reason code: "
        .. tostring(player.halo))

-- The native build validator reads self.north. Resolving the face without
-- initializing that direction made north-facing walls fail at valid squares.
SC.BaseLife.validateBuildPlan = function() return true end
SC.GameplayUtil.nowMs = function() return 1000 end
SC.BaseWork = {
    recipeForKind = function() return "wood_frame" end,
    recipeInfo = function() return {} end,
}
ArrayList = { new = function()
    return { values = {}, add = function(self, value)
        self.values[#self.values + 1] = value
    end }
end }
ISBuildIsoEntity = { new = function(_, _, _, face, containers)
    assert(containers and containers.values
        and containers.values[1] == player:getInventory(),
        "Build 42 preview needs a native-style container list")
    local value = { nSprite = face }
    function value:getSprite() self.north = self.nSprite == 2 end
    function value:getFace()
        return { getWidth = function() return 1 end,
            getHeight = function() return 1 end,
            getzLayers = function() return 1 end,
            getTileInfo = function()
                return { getSpriteName = function() return "wall_fixture" end }
            end }
    end
    function value:isValidPerSquare()
        assert(self.north == true, "north orientation must precede validation")
        return true
    end
    return value
end }
getCell = function() return { getGridSquare = function() return square end } end
local northCursor = planner._cursorClassForTests():new(player, "wall_frame")
northCursor.nSprite = 2
local placements, valid = northCursor:preview(square, true)
assert(valid == true and #placements == 1,
    "a clear north-facing wall frame must be plannable")
getText = formerGetText

planner._resetCursorForTests()
renderIsoLine, getSprite, IsoSprite, SC.GameplayUtil =
    formerRender, formerSprite, formerIsoSprite, formerUtility

SC.BaseLife, SC.BaseWork = formerLife, formerWork
ISBuildIsoEntity, ISBuildingObject = formerEntity, formerObject
ISInventoryPaneContextMenu, getCell = formerPane, formerCell
ArrayList = formerArrayList
