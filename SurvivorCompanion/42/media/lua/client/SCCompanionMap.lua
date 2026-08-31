-- SPDX-License-Identifier: MIT

require "ISUI/Maps/ISMiniMap"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.CompanionMap = SC.CompanionMap or {}

local CompanionMap = SC.CompanionMap
local installed = false
local originalRender = nil
local renderWrapper = nil

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

local function drawMarker(map, row, occupied)
    local api = map and map.mapAPI or nil
    if not api then return false end
    local uiX, xOk = U().call(api, "worldToUIX", row.x, row.y)
    local uiY, yOk = U().call(api, "worldToUIY", row.x, row.y)
    uiX, uiY = tonumber(uiX), tonumber(uiY)
    if not xOk or not yOk or not uiX or not uiY then return false end
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
    local textWidth = math.max(24, #tostring(row.name or "") * 6)
    if type(getTextManager) == "function" then
        local manager = getTextManager()
        local measured, measuredOk = U().call(manager, "MeasureStringX", UIFont.Small, row.name)
        if measuredOk and tonumber(measured) then textWidth = tonumber(measured) end
    end
    local maximumX = math.max(2, width - textWidth - 2)
    labelX = math.max(2, math.min(maximumX, labelX))
    map:drawText(row.name, labelX + 1, labelY + 1,
        0.04, 0.04, 0.04, 0.95, UIFont.Small)
    map:drawText(row.name, labelX, labelY,
        0.98, 0.88, 0.88, 1.00, UIFont.Small)
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

function CompanionMap.install()
    if installed then return true, "already_installed" end
    if type(ISMiniMapInner) ~= "table" then return false, "minimap_class_unavailable" end
    originalRender = ISMiniMapInner.render
    renderWrapper = function(self, ...)
        if type(originalRender) == "function" then originalRender(self, ...) end
        local ok, rendered, reason = pcall(CompanionMap.render, self)
        if not ok and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("companion-minimap", nil,
                "companion minimap overlay failed", rendered)
        elseif ok and rendered ~= true and reason ~= "minimap_api_unavailable"
            and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("companion-minimap", nil,
                "companion minimap overlay unavailable", reason)
        end
    end
    ISMiniMapInner.render = renderWrapper
    installed = true
    return true, "installed"
end

function CompanionMap.remove()
    if not installed then return true, "not_installed" end
    if type(ISMiniMapInner) == "table" and ISMiniMapInner.render == renderWrapper then
        ISMiniMapInner.render = originalRender
    elseif SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("companion-minimap", nil,
            "minimap hook removal deferred", "another wrapper owns the render chain")
        return false, "render_chain_changed"
    end
    originalRender, renderWrapper, installed = nil, nil, false
    return true, "removed"
end

function CompanionMap.isInstalled()
    return installed
end

return CompanionMap
