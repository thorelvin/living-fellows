-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ConstructionPlanner = SC.ConstructionPlanner or {}
local Planner = SC.ConstructionPlanner

local sprites = {}
local buildKinds = { wall = true, wall_frame = true, door = true,
    door_frame = true, floor = true }

local function note(player, message)
    if player and type(player.setHaloNote) == "function" then
        player:setHaloNote(tostring(message))
    end
end

local function translated(key, fallback)
    local value = type(getText) == "function" and getText(key) or nil
    if type(value) ~= "string" or value == "" or value == key then return fallback end
    return value
end

-- Player-facing text for a planning result. Internal reason codes belong in
-- logs; one without its own line gets the general refusal.
local reasonKeys = {
    build_outside_camp = "UI_SC_Base_Plan_OutsideCamp",
    barricade_outside_camp = "UI_SC_Base_Plan_OutsideCamp",
    build_target_unloaded = "UI_SC_Base_Plan_Unloaded",
    build_target_invalid = "UI_SC_Base_Plan_Blocked",
    barricade_target_invalid = "UI_SC_Base_Plan_Blocked",
    already_built = "UI_SC_Base_Plan_AlreadyBuilt",
    build_plan_overlaps = "UI_SC_Base_Plan_Overlaps",
    barricade_plan_overlaps = "UI_SC_Base_Plan_Overlaps",
    job_limit = "UI_SC_Base_Plan_JobLimit",
    barricade_full = "UI_SC_Base_Plan_BarricadeFull",
    close_target_first = "UI_SC_Base_Plan_CloseFirst",
    barricade_not_allowed = "UI_SC_Base_Plan_CannotBarricade",
    player_build_materials_or_target_invalid = "UI_SC_Base_Plan_PlayerMaterials",
    player_build_in_progress = "UI_SC_Base_Plan_PlayerBuilding",
    base_missing = "UI_SC_Base_Plan_NoCamp",
    build_recipe_missing = "UI_SC_Base_Plan_RecipeMissing",
    build_frame_recipe_missing = "UI_SC_Base_Plan_RecipeMissing",
    build_preview_unavailable = "UI_SC_Base_Plan_PreviewUnavailable",
    build_face_missing = "UI_SC_Base_Plan_PreviewUnavailable",
    build_cursor_unavailable = "UI_SC_Base_Plan_PreviewUnavailable",
}

function Planner.reasonText(reason)
    return translated(reasonKeys[tostring(reason)] or "UI_SC_Base_Plan_Failed",
        "That can't be planned right now.")
end

function Planner.acceptedText()
    return translated("UI_SC_Base_Plan_Accepted", "Construction planned.")
end

local function call(object, method, ...)
    if not object then return nil end
    local found, callable = pcall(function() return object[method] end)
    if not found or type(callable) ~= "function" then return nil end
    local okay, result = pcall(callable, object, ...)
    -- Keep a real false: getNorth() == false is a west-facing object.
    if not okay then return nil end
    return result
end

local function loadedSquare(x, y, z)
    local cell = type(getCell) == "function" and getCell() or nil
    return cell and call(cell, "getGridSquare", x, y, z) or nil
end

local function objectSprite(square, wanted)
    if not square or not wanted then return false end
    local objects = call(square, "getObjects")
    if not objects then return false end
    local count = tonumber(call(objects, "size")) or 0
    for index = 0, count - 1 do
        local object = call(objects, "get", index)
        local sprite = call(object, "getSprite")
        if call(sprite, "getName") == wanted then return true end
    end
    return false
end

local function worldValid(recipeId, face, target, player, entities)
    local info = SC.BaseWork and SC.BaseWork.recipeInfo(recipeId) or nil
    if not info or type(ISBuildIsoEntity) ~= "table" then
        return false, "build_recipe_missing"
    end
    local key = tostring(recipeId) .. ":" .. tostring(face)
    local entity = entities[key]
    if not entity then
        local inventory = call(player, "getInventory")
        if not inventory or not ArrayList or type(ArrayList.new) ~= "function" then
            return false, "build_preview_unavailable"
        end
        local containers = ArrayList.new()
        containers:add(inventory)
        local okay, created = pcall(ISBuildIsoEntity.new, ISBuildIsoEntity,
            player, info, face, containers)
        if not okay or not created then return false, "build_preview_unavailable" end
        entity = created
        entity.player = player:getPlayerNum()
        entities[key] = entity
    end
    entity.previousStageObject = nil
    -- Vanilla's placement checks read entity.north, which getSprite() sets.
    -- getFace() alone does not initialize the orientation.
    call(entity, "getSprite")
    local buildFace = call(entity, "getFace")
    if not buildFace then return false, "build_face_missing" end
    local width = tonumber(call(buildFace, "getWidth")) or 1
    local height = tonumber(call(buildFace, "getHeight")) or 1
    local layers = tonumber(call(buildFace, "getzLayers")) or 1
    for zz = 0, layers - 1 do
        for xx = 0, width - 1 do
            for yy = 0, height - 1 do
                local tile = call(buildFace, "getTileInfo", xx, yy, zz)
                if tile and (call(tile, "getSpriteName") or call(tile, "isBlocking")) then
                    local square = loadedSquare(target.x + xx, target.y + yy, target.z + zz)
                    if not square then return false, "build_target_unloaded" end
                    local valid = call(entity, "isValidPerSquare", square, tile,
                        zz == 0, yy > 0, xx > 0)
                    if valid ~= true then return false, "build_target_invalid" end
                end
            end
        end
    end
    return true
end

local function stagesFor(kind, face, target, player, entities)
    local final = SC.BaseWork and SC.BaseWork.recipeForKind(kind) or nil
    if not final then return nil, "build_recipe_missing" end
    if kind == "wall" or kind == "door" then
        local frameKind = kind == "wall" and "wall_frame" or "door_frame"
        local frame = SC.BaseWork.recipeForKind(frameKind)
        if not frame then return nil, "build_frame_recipe_missing" end
        local finalSprite = SC.BaseWork.recipeSprite(final, face)
        local square = loadedSquare(target.x, target.y, target.z)
        if objectSprite(square, finalSprite) then return nil, "already_built" end
        local finalValid = worldValid(final, face, target, player, entities)
        if finalValid == true then return { final } end
        local frameValid, frameReason = worldValid(frame, face, target, player, entities)
        if frameValid ~= true then return nil, frameReason end
        return { frame, final }
    end
    local valid, reason = worldValid(final, face, target, player, entities)
    if valid ~= true then return nil, reason end
    return { final }
end

local function cursorEndpoint(z)
    local mx = type(getMouseXScaled) == "function" and getMouseXScaled()
        or type(getMouseX) == "function" and getMouseX() or nil
    local my = type(getMouseYScaled) == "function" and getMouseYScaled()
        or type(getMouseY) == "function" and getMouseY() or nil
    if mx == nil or my == nil then return nil end
    local x, y
    if type(ISCoordConversion) == "table"
        and type(ISCoordConversion.ToWorld) == "function" then
        x, y = ISCoordConversion.ToWorld(mx, my, z)
    elseif type(IsoUtils) == "table" and type(IsoUtils.XToIso) == "function" then
        x, y = IsoUtils.XToIso(mx, my, z), IsoUtils.YToIso(mx, my, z)
    end
    if tonumber(x) and tonumber(y) then
        return { x = math.floor(x), y = math.floor(y), z = z }
    end
    return nil
end

local function lineTargets(kind, first, last, face, flipped)
    local rows = {}
    local dx, dy = last.x - first.x, last.y - first.y
    if kind == "wall" or kind == "wall_frame" then
        if math.abs(dx) >= math.abs(dy) and dx ~= 0 then
            face = flipped and 4 or 2
            for x = math.min(first.x, last.x), math.max(first.x, last.x) do
                rows[#rows + 1] = { target = { x = x, y = first.y, z = first.z },
                    face = face }
            end
        elseif dy ~= 0 then
            face = flipped and 3 or 1
            for y = math.min(first.y, last.y), math.max(first.y, last.y) do
                rows[#rows + 1] = { target = { x = first.x, y = y, z = first.z },
                    face = face }
            end
        end
    end
    if #rows == 0 then rows[1] = { target = first, face = face } end
    return rows
end
Planner.lineTargets = lineTargets

local function cachedSprite(name)
    if type(name) ~= "string" or name == "" then return nil end
    if sprites[name] then return sprites[name] end
    local sprite
    -- Native build previews load a private ghost sprite. A world sprite from
    -- getSprite is only a fallback when this constructor is unavailable.
    if IsoSprite and type(IsoSprite.new) == "function" then
        local okay, created = pcall(IsoSprite.new)
        if okay and created and type(created.LoadSingleTexture) == "function"
            and pcall(created.LoadSingleTexture, created, name) then
            sprite = created
        end
    end
    if not sprite and type(getSprite) == "function" then
        local okay, existing = pcall(getSprite, name)
        if okay then sprite = existing end
    end
    sprites[name] = sprite
    return sprite
end

function Planner.renderBuildGhost(recipeId, faceNumber, x, y, z, color, alpha)
    local face = SC.BaseWork and SC.BaseWork.recipeFace(recipeId, faceNumber) or nil
    if not face then return false end
    local rendered = false
    local width = tonumber(call(face, "getWidth")) or 1
    local height = tonumber(call(face, "getHeight")) or 1
    local layers = tonumber(call(face, "getzLayers")) or 1
    for zz = 0, layers - 1 do
        for xx = 0, width - 1 do
            for yy = 0, height - 1 do
                local tile = call(face, "getTileInfo", xx, yy, zz)
                local sprite = cachedSprite(call(tile, "getSpriteName"))
                if sprite and type(sprite.RenderGhostTileColor) == "function" then
                    sprite:RenderGhostTileColor(x + xx, y + yy, z + zz,
                        color.r, color.g, color.b, alpha)
                    rendered = true
                end
            end
        end
    end
    return rendered
end

local function barricadeGhostTile(row)
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    if not x or not y or not z then return nil end
    -- Vanilla BarricadePlanks uses W/N on the object's square. For E/S its
    -- build action starts on the west/north adjacent square, then advances
    -- by +1 to find the door in BuildRecipeCode.barricade.OnIsValidPlanks.
    if row.north == false then
        return row.side == "opposite" and "carpentry_01_0" or "carpentry_01_8",
            row.side == "opposite" and x - 1 or x, y, z
    end
    return row.side == "opposite" and "carpentry_01_1" or "carpentry_01_9",
        x, row.side == "opposite" and y - 1 or y, z
end

function Planner.renderBarricadeGhost(row, color, alpha)
    local name, x, y, z = barricadeGhostTile(row)
    local sprite = cachedSprite(name)
    if not sprite or type(sprite.RenderGhostTileColor) ~= "function" then return false end
    sprite:RenderGhostTileColor(x, y, z, color.r, color.g, color.b, alpha)
    return true
end

local Cursor = nil
local function cursorClass()
    if Cursor then return Cursor end
    if type(ISBuildingObject) ~= "table"
        or type(ISBuildingObject.derive) ~= "function" then return nil end
    Cursor = ISBuildingObject:derive("SCConstructionCursor")
    function Cursor:new(player, kind, object, side)
        local value = {}
        setmetatable(value, self)
        self.__index = self
        value:init()
        value.character, value.player = player, player:getPlayerNum()
        value.kind, value.object, value.side = kind, object, side
        value.nSprite = (kind == "wall" or kind == "wall_frame") and 2 or 1
        value.skipBuildAction, value.noNeedHammer = true, true
        value.flipped = false
        return value
    end
    function Cursor:rotateMouse() end
    function Cursor:rotateKey(key)
        if getCore():isKey(KeybindId.ROTATE_BUILDING, key) then
            if self.kind == "barricade" then
                self.side = self.side == "same" and "opposite" or "same"
            else
                self.nSprite = self.nSprite % 4 + 1
                self.flipped = not self.flipped
            end
            self.previewKey = nil
        end
    end
    function Cursor:getSprite()
        if self.kind == "barricade" then
            local name = barricadeGhostTile({ x = 0, y = 0, z = 0,
                side = self.side, north = call(self.object, "getNorth") == true })
            return name
        end
        local recipe = SC.BaseWork.recipeForKind(self.kind)
        return recipe and SC.BaseWork.recipeSprite(recipe, self.nSprite) or nil
    end
    function Cursor:preview(square, force)
        if not square then return {}, false, "build_target_unloaded" end
        if self.kind == "barricade" then
            local targetSquare = call(self.object, "getSquare")
            local sideMethod = self.side == "same"
                and "getBarricadeOnSameSquare" or "getBarricadeOnOppositeSquare"
            local barricade = call(self.object, sideMethod)
            local valid = targetSquare == square
                and SC.BaseLife.isInside(square)
                and SC.GameplayUtil.hasMethod(self.object, sideMethod)
                and (call(self.object, "isBarricadeAllowed") == true
                    or call(self.object, "getCanBarricade") == true)
                and call(self.object, "IsOpen") ~= true
                and (not barricade or call(barricade, "canAddPlank") == true)
            return {}, valid == true, valid and nil or "barricade_target_invalid"
        end
        local first = { x = square:getX(), y = square:getY(), z = square:getZ() }
        local dragging = self.isLeftDown or self.build
        local anchorKey = first.x .. ":" .. first.y .. ":" .. first.z
        if self.dragAnchorKey ~= anchorKey then self.lastDragEndpoint = nil end
        self.dragAnchorKey = anchorKey
        local last = dragging and cursorEndpoint(first.z)
            or self.lastDragEndpoint or first
        last = last or first
        if dragging then self.lastDragEndpoint = last end
        local cacheKey = table.concat({ self.kind, first.x, first.y, first.z,
            last.x, last.y, self.nSprite, tostring(self.flipped) }, ":")
        local current = SC.GameplayUtil and SC.GameplayUtil.nowMs
            and SC.GameplayUtil.nowMs() or math.floor(os.clock() * 1000)
        if not force and self.previewKey == cacheKey
            and current - (self.previewAt or 0) < 300 then
            return self.cachedPlacements, self.cachedValid, self.cachedReason
        end
        local placements = lineTargets(self.kind, first, last,
            self.nSprite, self.flipped)
        if #placements > 32 then return placements, false, "job_limit" end
        local allValid, reason = true, nil
        local entities = {}
        for _, placement in ipairs(placements) do
            placement.kind = self.kind
            local stages, why = stagesFor(self.kind, placement.face,
                placement.target, self.character, entities)
            placement.stages = stages or { SC.BaseWork.recipeForKind(self.kind) }
            if not stages or not SC.BaseLife.isInside(placement.target) then
                placement.valid = false
                allValid, reason = false, why or "build_outside_camp"
            else
                local accepted, overlapReason = SC.BaseLife.validateBuildPlan({ placement })
                placement.valid = accepted == true
                if not placement.valid then
                    allValid, reason = false, overlapReason
                end
            end
        end
        if allValid then
            local accepted, wholeReason = SC.BaseLife.validateBuildPlan(placements)
            allValid, reason = accepted == true, wholeReason
        end
        self.previewKey, self.previewAt = cacheKey, current
        self.cachedPlacements, self.cachedValid, self.cachedReason =
            placements, allValid, reason
        return placements, allValid, reason
    end
    function Cursor:isValid(square)
        local placements, valid, reason = self:preview(square)
        self.previewPlacements, self.previewReason = placements, reason
        return valid
    end
    function Cursor:render(x, y, z, square)
        local placements, valid = self:preview(square)
        self.previewPlacements = placements
        local color = valid and { r = 0.24, g = 0.70, b = 1.00 }
            or { r = 1.00, g = 0.16, b = 0.12 }
        if self.kind == "barricade" then
            local target = call(self.object, "getSquare")
            Planner.renderBarricadeGhost({
                x = call(target, "getX"), y = call(target, "getY"),
                z = call(target, "getZ"),
                side = self.side, north = call(self.object, "getNorth") == true },
                color, 0.85)
        else
            for index = 1, math.min(#placements, 32) do
                local placement = placements[index]
                local tint = placement.valid and color
                    or { r = 1.00, g = 0.16, b = 0.12 }
                local target = placement.target
                Planner.renderBuildGhost(SC.BaseWork.recipeForKind(self.kind),
                    placement.face, target.x, target.y, target.z, tint, 0.65)
            end
        end
    end
    function Cursor:tryBuild(x, y, z)
        local square = loadedSquare(x, y, z)
        local placements, valid, reason = self:preview(square, true)
        if not valid then note(self.character, Planner.reasonText(reason)) return nil end
        local okay, result
        if self.kind == "barricade" then
            okay, result = SC.BaseLife.enqueueBarricadePlan(self.object, self.side)
        else
            okay, result = SC.BaseLife.enqueueBuildPlan(placements)
        end
        note(self.character, okay and Planner.acceptedText()
            or Planner.reasonText(result))
        self:reinit()
        self.lastDragEndpoint, self.dragAnchorKey = nil, nil
        if SC.BaseVisuals and type(SC.BaseVisuals.refresh) == "function" then
            SC.BaseVisuals.refresh()
        end
        return nil
    end
    return Cursor
end

Planner._cursorClassForTests = cursorClass
function Planner._resetCursorForTests() Cursor = nil end

function Planner.start(kind, player)
    if not buildKinds[kind] or not player then return false, "invalid_build_kind" end
    local class = cursorClass()
    if not class or not SC.BaseLife or not SC.BaseWork then
        return false, "build_cursor_unavailable"
    end
    local recipe = SC.BaseWork.recipeForKind(kind)
    if not recipe or not SC.BaseWork.recipeInfo(recipe) then
        return false, "build_recipe_missing"
    end
    local cell = type(getCell) == "function" and getCell() or nil
    if not cell or type(cell.setDrag) ~= "function" then
        return false, "build_cursor_unavailable"
    end
    cell:setDrag(class:new(player, kind), player:getPlayerNum())
    return true, "build_cursor_started"
end

function Planner.startBarricade(object, player)
    if not object or not player or not SC.BaseLife then
        return false, "barricade_target_missing"
    end
    local square = call(object, "getSquare")
    if not square or not SC.BaseLife.isInside(square) then
        return false, "barricade_outside_camp"
    end
    local north = call(object, "getNorth") == true
    local side = north and player:getY() < square:getY() and "opposite"
        or not north and player:getX() < square:getX() and "opposite"
        or "same"
    local class = cursorClass()
    local cell = type(getCell) == "function" and getCell() or nil
    if not class or not cell then return false, "build_cursor_unavailable" end
    cell:setDrag(class:new(player, "barricade", object, side), player:getPlayerNum())
    return true, "barricade_cursor_started"
end

function Planner.buildSegment(player, jobId)
    if not player or not SC.BaseLife or not SC.BaseWork then
        return false, "player_build_unavailable"
    end
    local job = SC.BaseLife.job(jobId)
    if not job or job.type ~= "build" then return false, "unknown_build_job" end
    if job.reservedBy == nil then
        local reconciled = SC.BaseWork.reconcileBuildJob(job, nil)
        if reconciled == true then
            return true, "already_built"
        end
    end
    local square = loadedSquare(job.target.x, job.target.y, job.target.z)
    local info = SC.BaseWork.recipeInfo(job.recipeId)
    if not square or not info then return false, "build_target_unloaded" end
    local containers = type(ISInventoryPaneContextMenu) == "table"
        and type(ISInventoryPaneContextMenu.getContainers) == "function"
        and ISInventoryPaneContextMenu.getContainers(player)
        or nil
    if not containers then
        if not ArrayList or type(ArrayList.new) ~= "function" then
            return false, "player_build_unavailable"
        end
        containers = ArrayList.new()
        containers:add(player:getInventory())
    end
    local entity = ISBuildIsoEntity:new(player, info, job.face, containers)
    if entity then entity.player = player:getPlayerNum() end
    if not entity or entity:isValid(square) ~= true then
        return false, "player_build_materials_or_target_invalid"
    end
    local taken, reason = SC.BaseLife.takeOverBuild(jobId)
    if not taken then return false, reason end
    -- Use the vanilla player movement, recipe consumption and build animation.
    local okay, action = pcall(ISBuildingObject.tryBuild, entity,
        job.target.x, job.target.y, job.target.z)
    if not okay or not action then
        SC.BaseLife.releaseManualBuild(jobId, "player_build_not_started")
        return false, okay and "player_build_not_started" or tostring(action)
    end
    local function settle()
        entity:onActionComplete()
        local current = SC.BaseLife.job(jobId)
        if not current then return end
        local built = SC.BaseWork.reconcileBuildJob(current, nil)
        if built ~= true then
            SC.BaseLife.releaseManualBuild(jobId, "player_build_interrupted")
        end
    end
    action:setOnComplete(settle, nil)
    action:setOnCancel(settle, nil)
    return true, "player_build_started"
end

return Planner
