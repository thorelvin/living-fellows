-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.UIBounds = SC.UIBounds or {}
local Bounds = SC.UIBounds

Bounds.defaults = {
    collapsedWidth = 54,
    collapsedMaxWidth = 84,
    collapsedWidthRatio = 0.022,
    collapsedHeight = 112,
    collapsedMaxHeight = 148,
    collapsedHeightRatio = 0.06,
    expandedRatio = 0.32,
    expandedMinWidth = 380,
    expandedMaxWidth = 560,
    expandedDefaultHeight = 600,
    expandedMinHeight = 360,
    safeVerticalMargin = 40,
    defaultEdgeRatio = 0.25,
}

function Bounds.collapsedSize(screenWidth, screenHeight)
    local d = Bounds.defaults
    local width = Bounds.clamp(
        Bounds.round(screenWidth * d.collapsedWidthRatio),
        d.collapsedWidth,
        d.collapsedMaxWidth)
    local height = Bounds.clamp(
        Bounds.round(screenHeight * d.collapsedHeightRatio),
        d.collapsedHeight,
        d.collapsedMaxHeight)
    return width, height
end

function Bounds.clamp(value, minimum, maximum)
    if maximum < minimum then
        return minimum
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function Bounds.round(value)
    return math.floor(value + 0.5)
end

function Bounds.normalizeDock(side)
    if side == "left" then
        return "left"
    end
    return "right"
end

function Bounds.expandedWidth(screenWidth, savedWidth)
    local d = Bounds.defaults
    local requested = tonumber(savedWidth)
    if not requested then
        requested = Bounds.round(screenWidth * d.expandedRatio)
    end
    return Bounds.clamp(Bounds.round(requested), d.expandedMinWidth, d.expandedMaxWidth)
end

function Bounds.expandedHeight(screenHeight, savedHeight)
    local d = Bounds.defaults
    local maximum = screenHeight - (d.safeVerticalMargin * 2)
    local requested = tonumber(savedHeight) or d.expandedDefaultHeight
    local minimum = math.min(d.expandedMinHeight, maximum)
    return Bounds.clamp(Bounds.round(requested), minimum, maximum)
end

function Bounds.collapsedRect(screenWidth, screenHeight, dockSide, savedY)
    local d = Bounds.defaults
    local side = Bounds.normalizeDock(dockSide)
    local width, height = Bounds.collapsedSize(screenWidth, screenHeight)
    local maximumY = screenHeight - d.safeVerticalMargin - height
    local defaultY = Bounds.round(screenHeight * d.defaultEdgeRatio)
    local y = Bounds.clamp(tonumber(savedY) or defaultY, d.safeVerticalMargin, maximumY)
    local x = 0
    if side == "right" then
        x = screenWidth - width
    end
    return {
        x = x,
        y = Bounds.round(y),
        width = width,
        height = height,
        dockSide = side,
    }
end

function Bounds.expandedRect(screenWidth, screenHeight, dockSide, savedY, savedWidth, savedHeight)
    local d = Bounds.defaults
    local side = Bounds.normalizeDock(dockSide)
    local width = Bounds.expandedWidth(screenWidth, savedWidth)
    local height = Bounds.expandedHeight(screenHeight, savedHeight)
    local maximumY = screenHeight - d.safeVerticalMargin - height
    local y = Bounds.clamp(tonumber(savedY) or d.safeVerticalMargin, d.safeVerticalMargin, maximumY)
    local x = 0
    if side == "right" then
        x = screenWidth - width
    end
    return {
        x = x,
        y = Bounds.round(y),
        width = width,
        height = height,
        dockSide = side,
    }
end

function Bounds.resizedRect(screenWidth, screenHeight, dockSide, y, width, height)
    return Bounds.expandedRect(screenWidth, screenHeight, dockSide, y, width, height)
end

return Bounds
