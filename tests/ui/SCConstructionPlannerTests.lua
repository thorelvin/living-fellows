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
local square = { x = 4, y = 5, z = 0 }
local player = { slot = 1 }
function player:getPlayerNum() return self.slot end
function player:getInventory() return {} end
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

SC.BaseLife, SC.BaseWork = formerLife, formerWork
ISBuildIsoEntity, ISBuildingObject = formerEntity, formerObject
ISInventoryPaneContextMenu, getCell = formerPane, formerCell
