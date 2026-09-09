-- SPDX-License-Identifier: MIT

require = function(name)
    error("SCBaseVisuals must not depend on server-side helper modules: " .. tostring(name))
end

UIFont = { Small = "Small" }

local function event()
    local value = { callback = nil }
    value.Add = function(callback)
        assert(value.callback == nil)
        value.callback = callback
    end
    value.Remove = function(callback)
        assert(value.callback == callback)
        value.callback = nil
    end
    return value
end

Events = {
    OnRenderTick = event(),
    OnPreUIDraw = event(),
}

local fixture = {
    clock = 1000,
    mouseX = 140,
    mouseY = 160,
    lines = {},
    circles = {},
    labels = {},
    reports = {},
    draft = nil,
}
SCBaseVisualsFixture = fixture

local player = { x = 10, y = 10, z = 0 }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
fixture.player = player

function getSpecificPlayer(index)
    assert(index == 0)
    return player
end
function getPlayer() return player end
function getMouseX() return fixture.mouseX end
function getMouseY() return fixture.mouseY end

ISCoordConversion = {
    ToWorld = function(x, y)
        return x / 10, y / 10
    end,
    ToScreen = function(x, y)
        return x * 10, y * 10
    end,
}

function renderIsoLine(x1, y1, z1, x2, y2, z2, thickness, red, green, blue, alpha)
    fixture.lines[#fixture.lines + 1] = {
        x1 = x1, y1 = y1, z1 = z1, x2 = x2, y2 = y2, z2 = z2,
        thickness = thickness, red = red, green = green, blue = blue, alpha = alpha,
    }
end

function renderIsoCircle(x, y, z, radius, segments, thickness, red, green, blue, alpha)
    fixture.circles[#fixture.circles + 1] = {
        x = x, y = y, z = z, radius = radius, segments = segments,
        thickness = thickness, red = red, green = green, blue = blue, alpha = alpha,
    }
end

local textManager = {}
function textManager:DrawStringCentre(font, x, y, value, red, green, blue, alpha)
    fixture.labels[#fixture.labels + 1] = {
        font = font, x = x, y = y, value = value,
        red = red, green = green, blue = blue, alpha = alpha,
    }
end
function getTextManager() return textManager end

local core = {}
function core:getScreenWidth() return 1920 end
function core:getScreenHeight() return 1080 end
function getCore() return core end

local translations = {
    UI_SC_Base_Storage_food = "Food",
    UI_SC_Base_Storage_medical = "Medical",
    UI_SC_Base_Zone_work = "Work",
}
function getTextOrNull(key) return translations[key] end
function getText(key) return translations[key] or key end

local function storageObject()
    local object = { calls = {} }
    local function record(self, name, ...)
        self.calls[#self.calls + 1] = { name = name, args = { ... } }
    end
    function object:setHighlighted(...) record(self, "setHighlighted", ...) end
    function object:setHighlightColor(...) record(self, "setHighlightColor", ...) end
    function object:setOutlineHighlight(...) record(self, "setOutlineHighlight", ...) end
    function object:setOutlineHighlightCol(...) record(self, "setOutlineHighlightCol", ...) end
    return object
end

fixture.foodObject = storageObject()
fixture.upperObject = storageObject()
fixture.summary = {
    configured = true,
    zoneRows = {
        { id = "zone:area", kind = "area", name = "Camp area",
            x1 = 8, y1 = 8, x2 = 18, y2 = 18, z = 0 },
        { id = "zone:work", kind = "work", name = "Workshop",
            x1 = 12, y1 = 12, x2 = 14, y2 = 14, z = 0 },
        { id = "zone:upper", kind = "rest", name = "Upstairs",
            x1 = 8, y1 = 8, x2 = 10, y2 = 10, z = 1 },
        { id = "zone:far", kind = "guard", name = "Far guard",
            x1 = 200, y1 = 200, x2 = 202, y2 = 202, z = 0 },
    },
    storageRows = {
        { id = "storage:food", category = "food",
            x = 13, y = 13, z = 0, objectIndex = 2,
            objectId = "object:food", objectSignature = "fixture|food|container",
            object = fixture.foodObject },
        { id = "storage:upper", category = "medical",
            x = 9, y = 9, z = 1, objectIndex = 3,
            objectId = "object:upper", objectSignature = "fixture|upper|container",
            object = fixture.upperObject },
    },
}

SurvivorCompanion = {
    GameplayUtil = {
        nowMs = function() return fixture.clock end,
    },
    Diagnostics = {
        report = function(...)
            fixture.reports[#fixture.reports + 1] = { ... }
        end,
    },
    BaseLife = {
        summary = function() return fixture.summary end,
        visualRows = function() return fixture.summary end,
        resolveObject = function(record)
            if type(record.objectId) ~= "string" then
                return nil, "legacy_object_identity_unavailable"
            end
            return record.object
        end,
        zoneDraft = function() return fixture.draft end,
        isInside = function(point)
            return point.z == 0 and point.x >= 8 and point.x <= 18
                and point.y >= 8 and point.y <= 18
        end,
        zoneInsideAreaUnion = function(zone)
            return zone.z == 0 and zone.x1 >= 8 and zone.x2 <= 18
                and zone.y1 >= 8 and zone.y2 <= 18
        end,
    },
}
