-- SPDX-License-Identifier: MIT
require "ISUI/ISContextMenu"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ContextMenu = SC.ContextMenu or {}
local M = SC.ContextMenu

local function tooltip(option, description)
    if not option or not description or description == "" then return end
    if not option.toolTip and type(ISToolTip) == "table" then
        option.toolTip = ISToolTip:new()
        option.toolTip:initialise()
        option.toolTip:setVisible(false)
    end
    if option.toolTip then option.toolTip.description = tostring(description) end
end

local function fit(menu, label)
    label = tostring(label or "")
    local okay, manager = pcall(function() return getTextManager() end)
    if not okay or not manager or not menu.font then return label end
    local width = 1280
    pcall(function() width = getPlayerScreenWidth(menu.player or 0) end)
    local maximum = math.max(120, math.min(440, width * .6)) - 48
    local function measure(value)
        local ok, result = pcall(function() return manager:MeasureStringX(menu.font, value) end)
        return ok and tonumber(result) or 0
    end
    if measure(label) <= maximum then return label end
    local shortened = label
    while #shortened > 0 and measure(shortened .. "…") > maximum do
        local cut = #shortened
        while cut > 1 and string.byte(shortened, cut) >= 128
            and string.byte(shortened, cut) < 192 do cut = cut - 1 end
        shortened = string.sub(shortened, 1, cut - 1)
    end
    return shortened .. "…"
end

local function decorate(menu, option, key, label)
    if not option then return nil end
    option.scLFContext, option.scMenuKey = true, key
    option.scFullLabel = tostring(label)
    if option.name ~= option.scFullLabel then tooltip(option, option.scFullLabel) end
    return option
end

local function rootOf(menu)
    while menu.parent and menu.parent.options do menu = menu.parent end
    return menu
end

local lfBackground = { r = .08, g = .08, b = .08, a = .96 }
local function restoreRender(menu, background, okay, ...)
    menu.backgroundColor = background
    if not okay then error((...), 0) end
    return ...
end
local function styleBackground(menu)
    if type(menu.render) ~= "function" or menu.render == menu.scLFBackgroundRender then return end
    local render = menu.render
    local function styled(self, ...)
        -- Native get()/getNew() pools entire submenu instances. Ownership must
        -- come from the current attached row, never a retained instance flag.
        for _, option in ipairs(self.parent and self.parent.options or {}) do
            if option.scLFContext and option.subOption
                and self.parent:getSubMenu(option.subOption) == self then
                local background = self.backgroundColor
                self.backgroundColor = lfBackground
                return restoreRender(self, background, pcall(render, self, ...))
            end
        end
        return render(self, ...)
    end
    menu.scLFBackgroundRender, menu.render = styled, styled
end

local function newChild(parent)
    -- Keep native submenu numbers stable for foreign entries. Reuse retired
    -- LF slots in place; the next native get() returns them to its normal pool.
    for _, child in pairs(rootOf(parent).instanceMap or {}) do
        if child.scLFMenuRetired and child.parent == nil then
            child:clear()
            child.parent, child.player = parent, parent.player
            child.scLFMenuRetired, child.forceVisible, child.wantMouseEvents = false, true, true
            if child.setFontFromOption then child:setFontFromOption() end
            if child.setX then child:setX(parent:getX()) child:setY(parent:getY()) end
            if child.setVisible then child:setVisible(false) end
            if child.addToUIManager then child:addToUIManager() end
            return child
        end
    end
    local child = ISContextMenu:getNew(parent)
    child.scLFMenuRetired = false
    return child
end

local function retire(menu)
    for _, option in ipairs(menu.options or {}) do
        if option.subOption then
            local child = menu:getSubMenu(option.subOption)
            if child then retire(child) end
        end
    end
    if menu.hideAndChildren then menu:hideAndChildren() end
    if menu.removeFromUIManager then menu:removeFromUIManager() end
    if menu.clear then menu:clear() else menu.options, menu.numOptions = {}, 1 end
    menu.parent, menu.scLFMenuRetired = nil, true
end

function M.action(menu, key, label, target, callback, ...)
    for _, option in ipairs(menu.options or {}) do
        if option.scLFContext and option.scMenuKey == key then
            option.name, option.target, option.onSelect = fit(menu, label), target, callback
            local arguments = { ... }
            for index = 1, 10 do option["param" .. index] = arguments[index] end
            option.notAvailable, option.isDisabled, option.toolTip = nil, nil, nil
            return decorate(menu, option, key, label)
        end
    end
    return decorate(menu, menu:addOption(fit(menu, label), target, callback, ...), key, label)
end

function M.group(menu, key, label)
    for _, option in ipairs(menu.options or {}) do
        if option.scLFContext and option.scMenuKey == key and option.subOption then
            return menu:getSubMenu(option.subOption)
        end
    end
    local option = M.action(menu, key, label, nil, nil)
    if (key == "squad" or key == "nearby") and type(getTexture) == "function" then
        option.iconTexture = getTexture("media/ui/group.png")
    end
    local child = newChild(menu)
    styleBackground(child)
    menu:addSubMenu(option, child)
    return child
end

function M.reason(option, description)
    if not option then return end
    option.isDisabled = true
    if option.scFullLabel and option.name ~= option.scFullLabel then
        description = option.scFullLabel .. "\n" .. tostring(description or "")
    end
    tooltip(option, description)
    return option
end

function M.removeOwned(menu, predicate)
    local removed = 0
    for index = #(menu.options or {}), 1, -1 do
        local option = menu.options[index]
        if option.scLFContext and (not predicate or predicate(option)) then
            if option.subOption and type(menu.getSubMenu) == "function" then
                local child = menu:getSubMenu(option.subOption)
                if child then retire(child) end
            end
            table.remove(menu.options, index)
            if menu.optionPool then table.insert(menu.optionPool, option) end
            removed = removed + 1
        end
    end
    for index, option in ipairs(menu.options or {}) do option.id = index end
    menu.numOptions = #(menu.options or {}) + 1
    if removed > 0 and type(menu.calcHeight) == "function" then menu:calcHeight() end
    if removed > 0 and type(menu.calcWidth) == "function" and type(menu.setWidth) == "function" then
        menu:setWidth(menu:calcWidth())
    end
    return removed
end

function M.prune(menu)
    return M.removeOwned(menu, function(option)
        if not option.scLFContext or not option.subOption then return false end
        local child = menu:getSubMenu(option.subOption)
        if not child then return true end
        M.prune(child)
        for _, row in ipairs(child.options or {}) do
            if not row.isDefaultOption then return false end
        end
        return true
    end)
end

-- The descendants of a newly-created LF group belong to its builders. Existing
-- builders can keep their native callbacks while receiving the same styling.
function M.finish(menu)
    for _, option in ipairs(menu.options or {}) do
        local label = option.scFullLabel or option.name
        option.scLFContext, option.scFullLabel = true, label
        option.name = fit(menu, label)
        if option.name ~= label then
            local reason = option.toolTip and option.toolTip.description
            tooltip(option, label .. (reason and reason ~= label and ("\n" .. reason) or ""))
        end
        if option.subOption then
            local child = menu:getSubMenu(option.subOption)
            if child then
                styleBackground(child)
                M.finish(child)
            end
        end
    end
    M.prune(menu)
    if type(menu.calcWidth) == "function" and type(menu.setWidth) == "function" then menu:setWidth(menu:calcWidth()) end
end

return M
