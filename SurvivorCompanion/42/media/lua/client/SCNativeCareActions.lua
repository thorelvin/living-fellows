-- SPDX-License-Identifier: MIT

-- Native effects for quiet personal chores. No replacement items, condition
-- bonuses, water deductions or cleanliness changes are applied by this module.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.NativeCareActions = SC.NativeCareActions or {}
local Care = SC.NativeCareActions
local function U() return SC.GameplayUtil end
local function call(object, method, ...) return U().call(object, method, ...) end
local function rows(list, limit)
    local result = {}
    if not list then return result end
    local size, okay = call(list, "size")
    if okay then
        if tonumber(size) == nil or size > (limit or 240) then return nil end
        for i = 0, size - 1 do result[#result + 1] = select(1, call(list, "get", i)) end
    elseif type(list) == "table" then
        if #list > (limit or 240) then return nil end
        for _, value in ipairs(list) do result[#result + 1] = value end
    else return nil end
    return result
end
local function protected(actor, item, purpose)
    return not SC.PersonalItems or not SC.PersonalItems.isProtected
        or SC.PersonalItems.isProtected(item, actor, purpose or "craft_material") == true
end
local function contains(actor, item)
    if not item then return false end
    local root = U().inventory(actor)
    local holder = select(1, call(item, "getContainer"))
    local outer = select(1, call(item, "getOutermostContainer"))
    return holder ~= nil and (holder == root or outer == root)
        and U().containerContainsIdentity(holder, item) == true
end
local function unique(items)
    local result, seen = {}, {}
    for _, item in ipairs(items or {}) do
        if not seen[item] then seen[item] = true; result[#result + 1] = item end
    end
    return result
end
local function sameItems(left, right)
    if #left ~= #right then return false end
    local have = {}
    for _, item in ipairs(left) do have[item] = true end
    for _, item in ipairs(right) do if not have[item] then return false end end
    return true
end
local function repairInputs(actor, item, fixing, fixer)
    local uses, read = call(fixing, "countUses", actor, fixer, item)
    local required, requiredOK = call(fixer, "getNumberOfUse")
    if not read or not requiredOK or (tonumber(uses) or 0) < (tonumber(required) or math.huge) then return nil end
    local global = select(1, call(fixing, "getGlobalItem"))
    if global and not select(1, call(fixing, "haveGlobalItem", actor)) then return nil end
    local skills = rows(select(1, call(fixer, "getFixerSkills")), 16)
    if not skills then return nil end
    for _, skill in ipairs(skills) do
        local name = select(1, call(skill, "getSkillName"))
        local needed = select(1, call(skill, "getSkillLevel"))
        local perk = Perks and Perks.FromString and Perks.FromString(name)
        local level, levelOK = call(actor, "getPerkLevel", perk)
        if not perk or not levelOK or (tonumber(level) or 0) < (tonumber(needed) or math.huge) then return nil end
    end
    local inputs, okay = call(fixing, "getRequiredItems", actor, fixer, item)
    inputs = okay and rows(inputs, 32) or nil
    if not inputs or #inputs == 0 then return nil end
    inputs = unique(inputs)
    for _, material in ipairs(inputs) do
        if material == item or not contains(actor, material) or protected(actor, material) then return nil end
    end
    return inputs
end
local function fixesFor(item)
    if not FixingManager or not FixingManager.getFixes then return nil end
    local okay, list = pcall(FixingManager.getFixes, item)
    return okay and rows(list, 32) or nil
end

local function javaList(items)
    if not ArrayList or not ArrayList.new then return nil end
    local result = ArrayList.new()
    for _, item in ipairs(items) do result:add(item) end
    return result
end
local function recipeFor(name)
    if type(getScriptManager) ~= "function" then return nil end
    local manager = getScriptManager()
    return select(1, call(manager, "getCraftRecipe", name))
        or select(1, call(manager, "getCraftRecipe", string.match(name, "[^%.]+$")))
end

-- Build 42.22 moved melee repairs to handcraft recipes. Pin only permitted
-- carried ingredients; the native logic checks quantities, skill and surface.
local function craftRepair(actor, item, items)
    if not HandcraftLogic or not HandcraftLogic.new then return nil end
    for _, name in ipairs({ "Base.FixWithDuctTape", "Base.FixWithAdhesiveTape",
        "Base.FixWithWoodGlue", "Base.FixWithGlue", "Base.FixWithZipties" }) do
        local recipe = recipeFor(name)
        local inputs = recipe and rows(select(1, call(recipe, "getInputs")), 4)
        if inputs and #inputs == 2 then
            local manual, materials, valid, targetFound = {}, {}, true, false
            for _, input in ipairs(inputs) do
                local chosen = {}
                local keep = select(1, call(input, "isKeep"))
                local io = select(1, call(recipe, "getIndexForIO", input))
                local needed = tonumber((select(1, call(input, "getIntAmount")))) or 0
                if keep == true and needed == 1 and select(1, call(input, "canUseItem", item, actor)) == true then
                    chosen, targetFound = { item }, true
                elseif keep == false and needed > 0 then
                    for _, material in ipairs(items) do
                        if material ~= item and contains(actor, material) and not protected(actor, material)
                            and select(1, call(input, "canUseItem", material, actor)) == true then
                            local uses = tonumber((select(1, call(material, "getCurrentUses")))) or 1
                            if uses > 0 then
                                chosen[#chosen+1], materials[#materials+1] = material, material
                                needed = needed - uses
                                if needed <= 0 then break end
                            end
                        end
                    end
                    if needed > 0 then valid = false end
                else valid = false end
                if tonumber(io) == nil then valid = false else manual[io] = chosen end
            end
            if valid and targetFound then
                local logic = HandcraftLogic.new(actor, nil, nil)
                local surface = recipe:isAnySurfaceCraft() and logic:findCraftSurface(actor, 2) or nil
                if surface then logic:setIsoObject(surface) end
                logic:setContainers(javaList({ U().inventory(actor) }))
                logic:setRecipe(recipe); logic:setManualSelectInputs(true); logic:clearManualInputs()
                for io, selected in pairs(manual) do
                    if not logic:setManualInputsFor(recipe:getIOForIndex(io), javaList(selected)) then valid = false end
                end
                if valid and logic:canPerformCurrentRecipe() then
                    return { kind="repair", score=43, item=item, recipeName=name, repairManual=manual,
                        craftSurface=surface,
                        materials=unique(materials), material=materials[1],
                        fact={activity="repair",itemType=U().itemType(item)} }
                end
            end
        end
    end
end

function Care.repairCandidate(actor, items)
    for _, item in ipairs(items or {}) do
        local condition = select(1, call(item, "getCondition"))
        local maximum = select(1, call(item, "getConditionMax"))
        if contains(actor, item) and tonumber(maximum) and maximum > 0
            and tonumber(condition) and condition / maximum < 0.65
            and (U().instanceOf(item, "HandWeapon") or U().hasMethod(item, "getMaxDamage")) then
            for i, fixing in ipairs(fixesFor(item) or {}) do
                for j, fixer in ipairs(rows(select(1, call(fixing, "getFixers")), 32) or {}) do
                    local materials = repairInputs(actor, item, fixing, fixer)
                    if materials then
                        return { kind = "repair", score = 43, item = item,
                            fixingNum = i - 1, fixerNum = j - 1, fixing = fixing, fixer = fixer,
                            materials = materials, material = materials[1],
                            fact = { activity = "repair", itemType = U().itemType(item) } }
                    end
                end
            end
            local crafted = craftRepair(actor, item, items)
            if crafted then return crafted end
        end
    end
end

function Care.craftCandidate(actor, items)
    local rag, wood, sheet, splints = nil, nil, nil, 0
    local rags = { ["Base.RippedSheets"] = true, ["Base.RippedSheetsDirty"] = true,
        ["Base.DenimStrips"] = true, ["Base.DenimStripsDirty"] = true,
        ["Base.LeatherStrips"] = true, ["Base.LeatherStripsDirty"] = true }
    local woods = { ["Base.Plank"] = true, ["Base.TreeBranch2"] = true, ["Base.WoodenStick2"] = true }
    for _, item in ipairs(items or {}) do
        if contains(actor, item) then
            local kind = U().itemType(item)
            if kind == "Base.Splint" then splints = splints + 1 end
            if not protected(actor, item) then
                if rags[kind] and not rag then rag = item end
                if woods[kind] and not wood then wood = item end
                if kind == "Base.Sheet" and not sheet then sheet = item end
            end
        end
    end
    local recipe, output, scraps, score
    if splints < 2 and rag and wood then
        recipe, output, scraps, score = "Base.MakeSplint", "Base.Splint", { rag, wood }, 51
    elseif sheet then
        recipe, output, scraps, score = "Base.CraftSheetRope", "Base.SheetRope", { sheet }, 27
    end
    if recipe then return { kind = "craft_supply", recipeName = recipe, outputType = output,
        scraps = scraps, score = score, fact = { activity = "craft_supply", itemType = output } } end
end

local handled = { repair = true, craft_supply = true, wash_self = true,
    shower = true, wash_equipment = true, wash_bandage = true }
function Care.handles(kind) return handled[kind] == true end

-- Native actions collect soaps from the actor, never the local player. Filter
-- and reserve their exact list before starting, including soap held in a bag.
function Care.prepare(actor, activity)
    local inputs = {}
    if activity.item then inputs[#inputs + 1] = activity.item end
    if activity.kind == "repair" then
        for _, item in ipairs(activity.materials or {}) do inputs[#inputs + 1] = item end
    elseif activity.kind == "craft_supply" then
        for _, item in ipairs(activity.scraps or {}) do inputs[#inputs + 1] = item end
    elseif activity.kind ~= "wash_bandage" then
        local soaps, okay = call(U().inventory(actor), "getSoapList", nil, activity.kind == "wash_equipment")
        soaps = okay and rows(soaps, 64) or nil
        if not soaps then return false, "native_wash_soap_list_unavailable" end
        activity.soaps = {}
        for _, item in ipairs(soaps) do
            if contains(actor, item) and not protected(actor, item) then
                activity.soaps[#activity.soaps + 1] = item
                inputs[#inputs + 1] = item
            end
        end
    end
    activity.nativeInputs = unique(inputs)
    return true
end

function Care.valid(actor, activity)
    if not U().isValidActor(actor) or U().isDead(actor) then return false end
    if activity.craftSurface then
        local index = select(1, call(activity.craftSurface, "getObjectIndex"))
        if tonumber(index) == nil or index < 0 or not U().sameFloor(actor, activity.craftSurface)
            or U().distance(actor, activity.craftSurface) >= 3 then return false end
    end
    for _, item in ipairs(activity.nativeInputs or {}) do
        if not contains(actor, item) then return false end
        if item ~= activity.item and protected(actor, item) then return false end
    end
    if activity.kind == "repair" then
        if activity.recipeName then
            local recipe = recipeFor(activity.recipeName)
            if not recipe then return false end
            for io, items in pairs(activity.repairManual or {}) do
                local input = select(1, call(recipe, "getIOForIndex", io))
                for _, item in ipairs(items) do
                    if not input or select(1, call(input, "canUseItem", item, actor)) ~= true then return false end
                end
            end
            return true
        end
        local fixing = (fixesFor(activity.item) or {})[(activity.fixingNum or -1) + 1]
        local fixer = fixing and (rows(select(1, call(fixing, "getFixers")), 32) or {})[(activity.fixerNum or -1) + 1]
        if fixing ~= activity.fixing or fixer ~= activity.fixer then return false end
        local inputs = repairInputs(actor, activity.item, fixing, fixer)
        return inputs ~= nil and sameItems(inputs, activity.materials)
    elseif activity.kind == "craft_supply" then
        for _, item in ipairs(activity.scraps or {}) do if protected(actor, item) then return false end end
    elseif activity.kind == "wash_bandage" then
        if protected(actor, activity.item, "wash_bandage") then return false end
    end
    return true
end

local bandageRecipes = { ["Base.BandageDirty"] = "Base.Clean Bandage",
    ["Base.RippedSheetsDirty"] = "Base.Clean Rag", ["Base.DenimStripsDirty"] = "Base.Clean Denim Strips",
    ["Base.LeatherStripsDirty"] = "Base.Clean Leather Strips" }
local function load(name) if type(require) == "function" then pcall(require, name) end end

-- Returns an ordinary stock timed action and the method that owns its effects.
-- The facade stages inputs and guards that one method on this instance only.
function Care.create(actor, activity, context)
    local action, effect = nil, "complete"
    if activity.kind == "repair" then activity.conditionBefore = select(1, call(activity.item, "getCondition")) end
    if activity.kind == "repair" and not activity.recipeName then
        load("TimedActions/ISFixAction")
        if not ISFixAction then return nil, "native_repair_unavailable" end
        action = ISFixAction:new(actor, activity.item, activity.fixingNum, activity.fixerNum)
    elseif activity.kind == "craft_supply" or activity.kind == "repair" then
        load("Entity/TimedActions/ISHandcraftAction")
        local recipe = context.recipe(activity.recipeName)
        if not recipe or not ISHandcraftAction then return nil, "native_care_recipe_unavailable" end
        local inputs = rows(select(1, call(recipe, "getInputs")), 4)
        if not inputs or #inputs ~= (activity.kind == "repair" and 2 or #activity.scraps) then return nil, "native_care_recipe_changed" end
        local manual = {}
        for index, input in ipairs(inputs) do
            local count = select(1, call(input, "getIntAmount"))
            local keep = select(1, call(input, "isKeep"))
            local io = select(1, call(recipe, "getIndexForIO", input))
            if tonumber(io) == nil then return nil, "native_care_recipe_changed" end
            if activity.kind == "repair" then
                if not activity.repairManual[io] then return nil, "native_care_recipe_changed" end
                manual[io] = context.list(activity.repairManual[io])
            else
                if count ~= 1 or keep ~= false then return nil, "native_care_recipe_changed" end
                manual[io] = context.list({ activity.scraps[index] })
            end
        end
        action = ISHandcraftAction:new(actor, recipe, context.list({ U().inventory(actor) }), activity.craftSurface, nil, manual, nil, nil, 1, 0)
        effect = "performRecipe"
    elseif activity.kind == "wash_self" or activity.kind == "shower" then
        load("TimedActions/ISWashClothing"); load("TimedActions/ISWashYourself")
        if not ISWashYourself then return nil, "native_self_wash_unavailable" end
        action = ISWashYourself:new(actor, activity.object)
        action.soaps = context.list(activity.soaps or {})
        action.maxTime = action:getDuration()
    else
        load("TimedActions/ISCleanBandage"); load("TimedActions/ISWashClothing")
        if activity.kind == "wash_bandage" then
            local manager = type(getScriptManager) == "function" and getScriptManager()
            local recipe = manager and select(1, call(manager, "getRecipe", bandageRecipes[U().itemType(activity.item)]))
            if recipe and ISCleanBandage then
                action = ISCleanBandage:new(actor, activity.item, activity.object, recipe)
            end
            activity.rootBefore = {}
            for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do activity.rootBefore[item] = true end
        end
        if not action then
            if not ISWashClothing then return nil, "native_clothing_wash_unavailable" end
            if activity.kind == "wash_bandage" and select(1, call(activity.item, "getItemAfterCleaning")) ~= activity.cleanType then
                return nil, "native_bandage_recipe_unavailable"
            end
            local blood = tonumber((select(1, call(activity.item, "getBloodLevel")))) or 0
            local dirt = tonumber((select(1, call(activity.item, "getDirtiness")))) or 0
            if U().instanceOf(activity.item, "Clothing") or U().instanceOf(activity.item, "InventoryContainer") then
                local clothing = select(1, call(activity.item, "getBloodClothingType"))
                local parts = BloodClothingType and BloodClothingType.getCoveredParts(clothing)
                blood = 0
                for _, part in ipairs(rows(parts, 32) or {}) do
                    blood = blood + (tonumber((select(1, call(activity.item, "getBlood", part)))) or 0)
                end
            end
            action = ISWashClothing:new(actor, activity.object, activity.item, blood, dirt, true)
            action.soaps = context.list(activity.soaps or {})
            action.noSoap = ISWashClothing.GetSoapRemaining(action.soaps) <= 0
            action.maxTime = action:getDuration()
        end
    end
    return action, effect
end

function Care.after(actor, activity, action, context)
    if activity.kind == "repair" then
        activity.fact.repairImproved = (tonumber((select(1, call(activity.item, "getCondition")))) or 0)
            > (tonumber(activity.conditionBefore) or 0)
    elseif activity.kind == "craft_supply" then
        local created = context.list({})
        local _, okay = call(action.logic, "getCreatedOutputItems", created)
        local outputs = okay and rows(created, 4) or nil
        if not outputs or #outputs ~= 1 or U().itemType(outputs[1]) ~= activity.outputType then return false end
        activity.nativeOutput = outputs[1]
    elseif activity.kind == "wash_bandage" then
        local output
        if contains(actor, activity.item) then return false end
        for _, item in ipairs(U().inventoryItems(U().inventory(actor), 4096)) do
            if not activity.rootBefore[item] and U().itemType(item) == activity.cleanType then
                if output then return false end
                output = item
            end
        end
        if not output then return false end
        activity.nativeOutput = output
        local favorite = select(1, call(activity.item, "isFavorite"))
        if favorite then call(output, "setFavorite", true) end
        if select(1, call(activity.item, "isCustomName")) then
            local name = select(1, call(activity.item, "getName"))
            call(output, "setName", name)
        end
    end
    return true
end

return Care
