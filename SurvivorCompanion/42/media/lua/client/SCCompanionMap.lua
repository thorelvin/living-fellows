-- SPDX-License-Identifier: MIT

require "ISUI/Maps/ISMiniMap"
require "ISUI/Maps/ISWorldMap"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.CompanionMap = SC.CompanionMap or {}

local CompanionMap = SC.CompanionMap
local installed = false
local originalMiniMapRender = nil
local miniMapRenderWrapper = nil
local originalWorldMapRender = nil
local worldMapRenderWrapper = nil
local factionHouseTexture = nil

local function U()
    return SC.GameplayUtil
end

local function firstName(record)
    local identity = type(record) == "table" and type(record.identity) == "table"
        and record.identity or nil
    if identity and type(identity.forename) == "string" and identity.forename ~= "" then
        return identity.forename
    end
    local full = record and record.actor and U().nameOf(record.actor) or "Survivor"
    return string.match(tostring(full), "^%s*([^%s]+)") or "Survivor"
end

function CompanionMap.rows()
    local rows = {}
    if not SC.Registry or type(SC.Registry.records) ~= "function" then return rows end
    for _, record in ipairs(SC.Registry.records() or {}) do
        local actor = type(record) == "table" and record.actor or nil
        if actor and record.recruited == true and not U().isDead(actor) then
            local x, y, z = U().position(actor)
            if x ~= nil and y ~= nil then
                rows[#rows + 1] = {
                    id = record.id, actor = actor, name = firstName(record),
                    x = x, y = y, z = z or 0,
                }
            end
        end
    end
    table.sort(rows, function(left, right)
        if left.name == right.name then return tostring(left.id) < tostring(right.id) end
        return tostring(left.name) < tostring(right.name)
    end)
    return rows
end

local function factionPosition(group)
    local location = type(group) == "table" and group.location or nil
    local coordinates = type(location) == "table" and location.coordinates or nil
    local house = type(group) == "table" and group.house or nil
    local anchor = type(house) == "table" and house.anchor or nil
    local source = type(coordinates) == "table" and coordinates or anchor
    if type(source) ~= "table" then return nil, nil, nil end
    local x, y, z = tonumber(source.x), tonumber(source.y), tonumber(source.z)
    if x == nil or y == nil then return nil, nil, nil end
    return x, y, z or 0
end

function CompanionMap.factionRows()
    local rows = {}
    if not SC.Factions or type(SC.Factions.list) ~= "function" then return rows end
    for _, group in ipairs(SC.Factions.list(true) or {}) do
        if type(group) == "table" and group.discovered == true
            and group.lifecycle ~= "destroyed" then
            local x, y, z = factionPosition(group)
            if x ~= nil and y ~= nil then
                rows[#rows + 1] = {
                    id = group.id,
                    name = tostring(group.name or "Faction"),
                    standing = group.standing,
                    x = x, y = y, z = z,
                }
            end
        end
    end
    table.sort(rows, function(left, right)
        if left.name == right.name then return tostring(left.id) < tostring(right.id) end
        return tostring(left.name) < tostring(right.name)
    end)
    return rows
end

local function worldToUI(map, row)
    local api = map and map.mapAPI or nil
    if not api then return nil, nil end
    local uiX, xOk = U().call(api, "worldToUIX", row.x, row.y)
    local uiY, yOk = U().call(api, "worldToUIY", row.x, row.y)
    uiX, uiY = tonumber(uiX), tonumber(uiY)
    if not xOk or not yOk or not uiX or not uiY then return nil, nil end
    return uiX, uiY
end

local function textWidth(value)
    local width = math.max(24, #tostring(value or "") * 6)
    if type(getTextManager) == "function" then
        local manager = getTextManager()
        local measured, measuredOk = U().call(manager, "MeasureStringX", UIFont.Small, value)
        if measuredOk and tonumber(measured) then width = tonumber(measured) end
    end
    return width
end

local function drawMarker(map, row, occupied)
    local uiX, uiY = worldToUI(map, row)
    if not uiX or not uiY then return false end
    local width, height = tonumber(map.width) or 0, tonumber(map.height) or 0
    if uiX < 3 or uiY < 3 or uiX > width - 3 or uiY > height - 3 then return false end

    -- The dot remains at the exact actor position. Only the label moves when
    -- several companions occupy the same tile or vehicle seat cluster.
    map:drawRect(uiX - 4, uiY - 4, 8, 8, 0.92, 0.08, 0.01, 0.01)
    map:drawRect(uiX - 2, uiY - 2, 4, 4, 1.00, 0.92, 0.08, 0.08)
    local labelX, labelY = uiX + 6, uiY - 7
    local lane = math.floor(uiX / 24) .. ":" .. math.floor(uiY / 12)
    local collision = tonumber(occupied[lane]) or 0
    occupied[lane] = collision + 1
    labelY = labelY + collision * 11
    if labelY > height - 12 then labelY = uiY - 9 - collision * 11 end
    labelY = math.max(1, math.min(math.max(1, height - 12), labelY))
    local measuredWidth = textWidth(row.name)
    local maximumX = math.max(2, width - measuredWidth - 2)
    labelX = math.max(2, math.min(maximumX, labelX))
    map:drawText(row.name, labelX + 1, labelY + 1,
        0.04, 0.04, 0.04, 0.95, UIFont.Small)
    map:drawText(row.name, labelX, labelY,
        0.98, 0.88, 0.88, 1.00, UIFont.Small)
    return true
end

local function drawFactionMarker(map, row, occupied)
    local uiX, uiY = worldToUI(map, row)
    if not uiX or not uiY then return false end
    local width, height = tonumber(map.width) or 0, tonumber(map.height) or 0
    if uiX < 10 or uiY < 10 or uiX > width - 10 or uiY > height - 10 then return false end

    if factionHouseTexture == nil and type(getTexture) == "function" then
        factionHouseTexture = getTexture("media/ui/LootableMaps/map_house.png")
    end
    if factionHouseTexture == nil then return false end

    local red, green, blue = 0.18, 0.16, 0.13
    if row.standing == "Hostile" then red, green, blue = 0.68, 0.08, 0.06 end
    map:drawTextureScaled(factionHouseTexture, uiX - 8, uiY - 8, 16, 16,
        1.00, red, green, blue)

    local lane = math.floor(uiX / 32) .. ":" .. math.floor(uiY / 12)
    local collision = tonumber(occupied[lane]) or 0
    occupied[lane] = collision + 1
    local labelY = uiY + 9 + collision * 11
    if labelY > height - 12 then labelY = uiY - 20 - collision * 11 end
    labelY = math.max(1, math.min(math.max(1, height - 12), labelY))
    local measuredWidth = textWidth(row.name)
    local labelX = math.max(2, math.min(math.max(2, width - measuredWidth - 2),
        uiX - measuredWidth / 2))
    map:drawText(row.name, labelX + 1, labelY + 1,
        0.96, 0.94, 0.88, 0.96, UIFont.Small)
    map:drawText(row.name, labelX, labelY,
        red, green, blue, 1.00, UIFont.Small)
    return true
end

function CompanionMap.render(map)
    if map == nil or map.mapAPI == nil then return false, "minimap_api_unavailable" end
    local occupied, drawn = {}, 0
    for _, row in ipairs(CompanionMap.rows()) do
        if drawMarker(map, row, occupied) then drawn = drawn + 1 end
    end
    return true, drawn
end

function CompanionMap.renderFactions(map)
    if map == nil or map.mapAPI == nil then return false, "worldmap_api_unavailable" end
    local occupied, drawn = {}, 0
    for _, row in ipairs(CompanionMap.factionRows()) do
        if drawFactionMarker(map, row, occupied) then drawn = drawn + 1 end
    end
    -- Exposed as a cheap live-harness/read-only diagnostic. This proves that the
    -- actual ISWorldMap render hook completed, rather than only that rows exist.
    CompanionMap.lastFactionDrawCount = drawn
    return true, drawn
end

local function reportOverlayFailure(system, message, okay, rendered, reason, unavailable)
    if not SC.Diagnostics or type(SC.Diagnostics.report) ~= "function" then return end
    if not okay then
        SC.Diagnostics.report(system, nil, message .. " failed", rendered)
    elseif rendered ~= true and reason ~= unavailable then
        SC.Diagnostics.report(system, nil, message .. " unavailable", reason)
    end
end

function CompanionMap.install()
    if installed then return true, "already_installed" end
    if type(ISMiniMapInner) ~= "table" or type(ISWorldMap) ~= "table" then
        return false, "map_class_unavailable"
    end
    originalMiniMapRender = ISMiniMapInner.render
    miniMapRenderWrapper = function(self, ...)
        if type(originalMiniMapRender) == "function" then originalMiniMapRender(self, ...) end
        local ok, rendered, reason = pcall(CompanionMap.render, self)
        reportOverlayFailure("companion-minimap", "companion minimap overlay",
            ok, rendered, reason, "minimap_api_unavailable")
    end
    originalWorldMapRender = ISWorldMap.render
    worldMapRenderWrapper = function(self, ...)
        if type(originalWorldMapRender) == "function" then originalWorldMapRender(self, ...) end
        local ok, rendered, reason = pcall(CompanionMap.renderFactions, self)
        reportOverlayFailure("faction-worldmap", "faction world-map overlay",
            ok, rendered, reason, "worldmap_api_unavailable")
    end
    ISMiniMapInner.render = miniMapRenderWrapper
    ISWorldMap.render = worldMapRenderWrapper
    installed = true
    return true, "installed"
end

function CompanionMap.remove()
    if not installed then return true, "not_installed" end
    if type(ISMiniMapInner) ~= "table" or ISMiniMapInner.render ~= miniMapRenderWrapper
        or type(ISWorldMap) ~= "table" or ISWorldMap.render ~= worldMapRenderWrapper then
        if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("companion-map", nil,
                "map hooks removal deferred", "another wrapper owns a render chain")
        end
        return false, "render_chain_changed"
    end
    ISMiniMapInner.render = originalMiniMapRender
    ISWorldMap.render = originalWorldMapRender
    originalMiniMapRender, miniMapRenderWrapper = nil, nil
    originalWorldMapRender, worldMapRenderWrapper = nil, nil
    factionHouseTexture, installed = nil, false
    return true, "removed"
end

function CompanionMap.isInstalled()
    return installed
end

return CompanionMap
