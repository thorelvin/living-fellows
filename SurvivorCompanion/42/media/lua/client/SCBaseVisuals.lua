-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseVisuals = SC.BaseVisuals or {}

local Visuals = SC.BaseVisuals
local installed = false
local enabled = false
local focusKind = nil
local focusId = nil
local refreshDue = 0
local cachedZ = nil
local cachedZones = {}
local cachedStorages = {}
local highlightedObjects = {}
local lastReportAt = {}

local REFRESH_MILLIS = 400
local VIEW_DISTANCE = 48

local ZONE_COLORS = {
    area = { r = 0.92, g = 0.92, b = 0.86 },
    work = { r = 0.96, g = 0.48, b = 0.08 },
    rest = { r = 0.20, g = 0.52, b = 1.00 },
    social = { r = 0.18, g = 0.82, b = 0.32 },
    guard = { r = 0.94, g = 0.12, b = 0.10 },
    rally = { r = 1.00, g = 0.82, b = 0.08 },
    quarantine = { r = 0.70, g = 0.22, b = 0.92 },
}

local STORAGE_COLORS = {
    food = { r = 0.25, g = 0.86, b = 0.25 },
    water = { r = 0.12, g = 0.72, b = 1.00 },
    medical = { r = 1.00, g = 0.20, b = 0.20 },
    tools = { r = 0.96, g = 0.78, b = 0.15 },
    construction = { r = 1.00, g = 0.48, b = 0.08 },
    crafting = { r = 0.76, g = 0.56, b = 0.28 },
    weapons = { r = 0.92, g = 0.08, b = 0.08 },
    ammunition = { r = 0.80, g = 0.32, b = 0.10 },
    general = { r = 0.90, g = 0.90, b = 0.84 },
    output = { r = 0.96, g = 0.30, b = 0.78 },
    memorial = { r = 0.62, g = 0.66, b = 0.78 },
}

local function now()
    local utility = SC.GameplayUtil
    if utility and type(utility.nowMs) == "function" then return utility.nowMs() end
    return math.floor(os.clock() * 1000)
end

local function player()
    if type(getSpecificPlayer) == "function" then
        local ok, value = pcall(getSpecificPlayer, 0)
        if ok and value then return value end
    end
    if type(getPlayer) == "function" then
        local ok, value = pcall(getPlayer)
        if ok then return value end
    end
    return nil
end

local function numberMethod(object, methodName)
    local method = object and object[methodName] or nil
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object)
    value = ok and tonumber(value) or nil
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function playerPosition(subject)
    local x = numberMethod(subject, "getX")
    local y = numberMethod(subject, "getY")
    local z = numberMethod(subject, "getZ")
    if x == nil or y == nil or z == nil then return nil, nil, nil end
    return x, y, math.floor(z)
end

local function colorFor(colors, key)
    return colors[key] or { r = 0.92, g = 0.92, b = 0.86 }
end

local function humanize(value)
    local text = tostring(value or "")
    text = string.gsub(text, "_", " ")
    text = string.gsub(text, "^%l", string.upper)
    return text
end

local function translated(key, fallback)
    if type(getTextOrNull) == "function" then
        local ok, value = pcall(getTextOrNull, key)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    if type(getText) == "function" then
        local ok, value = pcall(getText, key)
        if ok and type(value) == "string" and value ~= "" and value ~= key then return value end
    end
    return fallback or key
end

local function nearPlayer(row, px, py, pz)
    if type(row) ~= "table" or tonumber(row.z) ~= pz then return false end
    local x1 = tonumber(row.x1) or tonumber(row.x)
    local y1 = tonumber(row.y1) or tonumber(row.y)
    local x2 = tonumber(row.x2) or x1
    local y2 = tonumber(row.y2) or y1
    if x1 == nil or y1 == nil then return false end
    local nearestX = math.max(math.min(px, math.max(x1, x2)), math.min(x1, x2))
    local nearestY = math.max(math.min(py, math.max(y1, y2)), math.min(y1, y2))
    local dx, dy = nearestX - px, nearestY - py
    return dx * dx + dy * dy <= VIEW_DISTANCE * VIEW_DISTANCE
end

local function clearObject(object)
    if not object then return end
    local method = object.setOutlineHighlight
    if type(method) == "function" then pcall(method, object, 0, false) end
end

local function clearHighlights()
    for _, object in ipairs(highlightedObjects) do clearObject(object) end
    highlightedObjects = {}
end

local function resolveStorage(record)
    if not SC.BaseLife or type(SC.BaseLife.resolveObject) ~= "function" then return nil end
    local ok, object = pcall(SC.BaseLife.resolveObject, record)
    return ok and object or nil
end

local function refreshCache(force)
    local subject = player()
    local px, py, pz = playerPosition(subject)
    if not subject or px == nil then
        clearHighlights()
        cachedZones, cachedStorages, cachedZ = {}, {}, nil
        return false
    end
    local current = now()
    if force ~= true and current < refreshDue and cachedZ == pz then return true end
    refreshDue, cachedZ = current + REFRESH_MILLIS, pz
    clearHighlights()
    cachedZones, cachedStorages = {}, {}
    if not SC.BaseLife then return false end
    local source = type(SC.BaseLife.visualRows) == "function"
        and SC.BaseLife.visualRows or SC.BaseLife.summary
    if type(source) ~= "function" then return false end
    local ok, summary = pcall(source)
    if not ok or type(summary) ~= "table" or summary.configured ~= true then return false end
    for _, zone in ipairs(type(summary.zoneRows) == "table" and summary.zoneRows or {}) do
        if nearPlayer(zone, px, py, pz) then
            cachedZones[#cachedZones + 1] = zone
        end
    end
    for _, storage in ipairs(type(summary.storageRows) == "table" and summary.storageRows or {}) do
        if nearPlayer(storage, px, py, pz) then
            local object = resolveStorage(storage)
            if object then
                cachedStorages[#cachedStorages + 1] = { record = storage, object = object }
                highlightedObjects[#highlightedObjects + 1] = object
            end
        end
    end
    return true
end

local function bounds(row)
    local x1, y1 = tonumber(row.x1), tonumber(row.y1)
    local x2, y2 = tonumber(row.x2), tonumber(row.y2)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    local minimumX, maximumX = math.min(x1, x2), math.max(x1, x2) + 1
    local minimumY, maximumY = math.min(y1, y2), math.max(y1, y2) + 1
    return minimumX, minimumY, maximumX, maximumY
end

local function renderRectangle(row, color, thickness, alpha)
    if type(renderIsoLine) ~= "function" then return false end
    local x1, y1, x2, y2 = bounds(row)
    local z = tonumber(row.z)
    if not x1 or z == nil then return false end
    renderIsoLine(x1, y1, z, x2, y1, z, thickness, color.r, color.g, color.b, alpha)
    renderIsoLine(x2, y1, z, x2, y2, z, thickness, color.r, color.g, color.b, alpha)
    renderIsoLine(x2, y2, z, x1, y2, z, thickness, color.r, color.g, color.b, alpha)
    renderIsoLine(x1, y2, z, x1, y1, z, thickness, color.r, color.g, color.b, alpha)
    return true
end

local function applyStorageHighlight(entry)
    local record, object = entry.record, entry.object
    local color = colorFor(STORAGE_COLORS, record.category)
    if focusKind == "storage" and focusId == record.id then
        color = { r = 1.00, g = 1.00, b = 1.00 }
    end
    local method = object.setOutlineHighlight
    if type(method) == "function" then method(object, 0, true) end
    method = object.setOutlineHighlightCol
    if type(method) == "function" then method(object, 0, color.r, color.g, color.b, 1.00) end
end

local function screenToWorld(x, y, z)
    if type(ISCoordConversion) == "table"
        and type(ISCoordConversion.ToWorld) == "function" then
        return ISCoordConversion.ToWorld(x, y, z)
    end
    if type(IsoUtils) == "table" and type(IsoUtils.XToIso) == "function"
        and type(IsoUtils.YToIso) == "function" then
        return IsoUtils.XToIso(x, y, z), IsoUtils.YToIso(x, y, z)
    end
    return nil, nil
end

local function draftEndpoint(draft)
    if type(draft) ~= "table" or type(draft.first) ~= "table"
        or (type(getMouseXScaled) ~= "function" and type(getMouseX) ~= "function")
        or (type(getMouseYScaled) ~= "function" and type(getMouseY) ~= "function") then
        return nil
    end
    local mouseX = type(getMouseXScaled) == "function" and getMouseXScaled() or getMouseX()
    local mouseY = type(getMouseYScaled) == "function" and getMouseYScaled() or getMouseY()
    local ok, x, y = pcall(screenToWorld, mouseX, mouseY, draft.first.z)
    if not ok or tonumber(x) == nil or tonumber(y) == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = draft.first.z }
end

local function draftIsValid(draft, endpoint)
    if draft.kind == "area" then return true end
    if not SC.BaseLife or type(SC.BaseLife.isInside) ~= "function" then return false end
    local x1, x2 = math.min(draft.first.x, endpoint.x), math.max(draft.first.x, endpoint.x)
    local y1, y2 = math.min(draft.first.y, endpoint.y), math.max(draft.first.y, endpoint.y)
    for _, point in ipairs({
        { x = x1, y = y1, z = endpoint.z }, { x = x2, y = y1, z = endpoint.z },
        { x = x1, y = y2, z = endpoint.z }, { x = x2, y = y2, z = endpoint.z },
    }) do
        local ok, inside = pcall(SC.BaseLife.isInside, point)
        if not ok or inside ~= true then return false end
    end
    return true
end

local function currentDraft()
    if not SC.BaseLife or type(SC.BaseLife.zoneDraft) ~= "function" then return nil end
    local ok, draft = pcall(SC.BaseLife.zoneDraft)
    return ok and draft or nil
end

function Visuals.renderWorld()
    local draft = currentDraft()
    if enabled then
        refreshCache(false)
        for _, zone in ipairs(cachedZones) do
            local focused = focusKind == "zone" and focusId == zone.id
            renderRectangle(zone, colorFor(ZONE_COLORS, zone.kind),
                focused and 3.0 or 1.35, focused and 0.98 or 0.70)
        end
        for _, entry in ipairs(cachedStorages) do pcall(applyStorageHighlight, entry) end
    end
    if draft and type(draft.first) == "table" then
        local subject = player()
        local _, _, pz = playerPosition(subject)
        if pz == tonumber(draft.first.z) then
            local endpoint = draftEndpoint(draft)
            if endpoint then
                local preview = {
                    x1 = draft.first.x, y1 = draft.first.y,
                    x2 = endpoint.x, y2 = endpoint.y, z = endpoint.z,
                }
                local valid = draftIsValid(draft, endpoint)
                local color = valid and colorFor(ZONE_COLORS, draft.kind)
                    or { r = 1.00, g = 0.08, b = 0.04 }
                renderRectangle(preview, color, 2.25, 0.92)
                if type(renderIsoCircle) == "function" then
                    renderIsoCircle(draft.first.x + 0.5, draft.first.y + 0.5,
                        draft.first.z, 0.24, 12, 2, color.r, color.g, color.b, 0.95)
                    renderIsoCircle(endpoint.x + 0.5, endpoint.y + 0.5,
                        endpoint.z, 0.24, 12, 2, color.r, color.g, color.b, 0.95)
                end
            end
        end
    end
    return true
end

local function screenPosition(x, y, z)
    local ok, sx, sy
    if type(ISCoordConversion) == "table"
        and type(ISCoordConversion.ToScreen) == "function" then
        ok, sx, sy = pcall(ISCoordConversion.ToScreen, x, y, z)
    elseif type(IsoUtils) == "table" and type(IsoUtils.XToScreen) == "function"
        and type(IsoUtils.YToScreen) == "function"
        and type(getCameraOffX) == "function" and type(getCameraOffY) == "function" then
        ok, sx, sy = pcall(function()
            return IsoUtils.XToScreen(x, y, z, 0) - getCameraOffX(),
                IsoUtils.YToScreen(x, y, z, 0) - getCameraOffY()
        end)
    else
        return nil, nil
    end
    sx, sy = ok and tonumber(sx) or nil, ok and tonumber(sy) or nil
    if sx == nil or sy == nil then return nil, nil end
    return sx, sy
end

local function drawLabel(value, x, y, z, color, occupied)
    local sx, sy = screenPosition(x, y, z)
    if not sx then return false end
    local core = type(getCore) == "function" and getCore() or nil
    local width = core and numberMethod(core, "getScreenWidth") or 0
    local height = core and numberMethod(core, "getScreenHeight") or 0
    sy = sy - 48
    if sx < 0 or sy < 0 or (width > 0 and sx > width) or (height > 0 and sy > height) then
        return false
    end
    local lane = math.floor(sx / 96) .. ":" .. math.floor(sy / 14)
    local collision = tonumber(occupied[lane]) or 0
    occupied[lane] = collision + 1
    sy = sy + collision * 13
    local manager = type(getTextManager) == "function" and getTextManager() or nil
    if not manager or type(manager.DrawStringCentre) ~= "function" then return false end
    manager:DrawStringCentre(UIFont.Small, sx + 1, sy + 1, value, 0.02, 0.02, 0.02, 0.94)
    manager:DrawStringCentre(UIFont.Small, sx, sy, value, color.r, color.g, color.b, 1.00)
    return true
end

function Visuals.renderLabels()
    if not enabled then return true end
    refreshCache(false)
    local occupied = {}
    for _, zone in ipairs(cachedZones) do
        local x1, y1, x2, y2 = bounds(zone)
        if x1 then
            local label = tostring(zone.name or translated(
                "UI_SC_Base_Zone_" .. tostring(zone.kind), humanize(zone.kind)))
            if focusKind == "zone" and focusId == zone.id then label = "> " .. label .. " <" end
            drawLabel(label, (x1 + x2) / 2, (y1 + y2) / 2, zone.z,
                colorFor(ZONE_COLORS, zone.kind), occupied)
        end
    end
    for _, entry in ipairs(cachedStorages) do
        local row = entry.record
        local label = translated("UI_SC_Base_Storage_" .. tostring(row.category),
            humanize(row.category))
        if focusKind == "storage" and focusId == row.id then label = "> " .. label .. " <" end
        drawLabel(label, row.x + 0.5, row.y + 0.5, row.z,
            colorFor(STORAGE_COLORS, row.category), occupied)
    end
    return true
end

local function reportFailure(system, detail)
    local current = now()
    if current - (lastReportAt[system] or -10000) < 5000 then return end
    lastReportAt[system] = current
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report(system, nil, "base visualization render failed", detail)
    end
end

function Visuals.onRenderTick()
    local ok, reason = pcall(Visuals.renderWorld)
    if not ok then reportFailure("base-visuals-world", reason) end
end

function Visuals.onPreUIDraw()
    local ok, reason = pcall(Visuals.renderLabels)
    if not ok then reportFailure("base-visuals-labels", reason) end
end

function Visuals.setEnabled(value)
    enabled = value == true
    refreshDue = 0
    if not enabled then
        focusKind, focusId = nil, nil
        clearHighlights()
        cachedZones, cachedStorages, cachedZ = {}, {}, nil
    end
    return true, enabled
end

function Visuals.toggle()
    return Visuals.setEnabled(not enabled)
end

function Visuals.focus(kind, id)
    if kind ~= "zone" and kind ~= "storage" then return false, "invalid_focus_kind" end
    if type(id) ~= "string" or id == "" then return false, "invalid_focus_id" end
    focusKind, focusId = kind, id
    enabled, refreshDue = true, 0
    return true, id
end

function Visuals.refresh()
    refreshDue = 0
    return true
end

function Visuals.status()
    return {
        enabled = enabled, focusKind = focusKind, focusId = focusId,
        visibleZones = #cachedZones, visibleStorages = #cachedStorages,
    }
end

function Visuals.reset()
    Visuals.setEnabled(false)
    refreshDue = 0
    lastReportAt = {}
    return true
end

function Visuals.install()
    if installed then return true, "already_installed" end
    if type(Events) ~= "table" or type(Events.OnRenderTick) ~= "table"
        or type(Events.OnPreUIDraw) ~= "table"
        or type(Events.OnRenderTick.Add) ~= "function"
        or type(Events.OnRenderTick.Remove) ~= "function"
        or type(Events.OnPreUIDraw.Add) ~= "function"
        or type(Events.OnPreUIDraw.Remove) ~= "function" then
        return false, "render_events_unavailable"
    end
    local worldOk, worldReason = pcall(Events.OnRenderTick.Add, Visuals.onRenderTick)
    if not worldOk then return false, tostring(worldReason) end
    local labelsOk, labelsReason = pcall(Events.OnPreUIDraw.Add, Visuals.onPreUIDraw)
    if not labelsOk then
        pcall(Events.OnRenderTick.Remove, Visuals.onRenderTick)
        return false, tostring(labelsReason)
    end
    installed = true
    return true, "installed"
end

function Visuals.remove()
    if not installed then
        Visuals.reset()
        return true, "not_installed"
    end
    local labelsOk, labelsReason = pcall(Events.OnPreUIDraw.Remove, Visuals.onPreUIDraw)
    local worldOk, worldReason = pcall(Events.OnRenderTick.Remove, Visuals.onRenderTick)
    if not labelsOk or not worldOk then
        if labelsOk and not worldOk then
            pcall(Events.OnPreUIDraw.Add, Visuals.onPreUIDraw)
        elseif worldOk and not labelsOk then
            pcall(Events.OnRenderTick.Add, Visuals.onRenderTick)
        end
        return false, tostring(not labelsOk and labelsReason or worldReason)
    end
    installed = false
    Visuals.reset()
    return true, "removed"
end

function Visuals.isInstalled()
    return installed
end

return Visuals
