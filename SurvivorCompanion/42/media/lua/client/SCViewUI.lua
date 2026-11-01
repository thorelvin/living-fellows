-- SPDX-License-Identifier: MIT
-- Retire known player panels belonging to released LF companion views only.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local ViewUI = {}
SC.ViewUI = ViewUI
local retiredKeys = setmetatable({}, { __mode = "k" })
local viewActors = setmetatable({}, { __mode = "k" })
local knownPanels = { SSBar = true, ISDesignationZonePanel = true }

local function call(object, method, ...)
    if not object then return nil end
    local indexed, fn = pcall(function() return object[method] end)
    if not indexed or type(fn) ~= "function" then return nil end
    local okay, value = pcall(fn, object, ...)
    if okay then return value end
end

local function ownedRetiredPanel(panel, primary, secondary)
    if type(panel) ~= "table" or not knownPanels[panel.Type] then return false end
    local actor = panel.player
    if not actor or actor == primary or actor == secondary
        or not SCBridge or type(SCBridge.isCompanion) ~= "function" then return false end
    if viewActors[actor] then return true end
    local okay, owned = pcall(SCBridge.isCompanion, actor)
    return okay and owned == true
end

function ViewUI.remember(actor)
    if not actor or not SCBridge or type(SCBridge.isCompanion) ~= "function" then return end
    local okay, owned = pcall(SCBridge.isCompanion, actor)
    if okay and owned == true then viewActors[actor] = true end
end

function ViewUI.cleanup()
    local list = UIManager and UIManager.UI
    if not list or type(getSpecificPlayer) ~= "function" then return 0 end
    local primary, secondary = getSpecificPlayer(0), getSpecificPlayer(1)
    local luaList = type(list) == "table"
    local count = luaList and #list or call(list, "size")
    if type(count) ~= "number" then return 0 end
    local panels = {}
    -- Snapshot before removals shift the native ArrayList. This scan runs only
    -- at view lifecycle boundaries, never as an idle/per-frame service.
    for offset = 0, math.min(count, 2048) - 1 do
        local element = luaList and list[offset + 1] or call(list, "get", offset)
        local panel = type(element) == "table" and element or call(element, "getTable")
        if ownedRetiredPanel(panel, primary, secondary) then panels[#panels + 1] = panel end
    end
    for _, panel in ipairs(panels) do
        local actor = panel.player
        -- SimpleStatus retains its private bar after slot teardown and its
        -- global hotkey handler can otherwise add that obsolete bar again.
        -- Guard this instance; other actors and the mod's functions stay intact.
        if panel.Type == "SSBar" and type(panel.handleKey) == "function"
            and retiredKeys[panel] ~= actor then
            local original = panel.handleKey
            panel.handleKey = function(self, ...)
                if self.player == actor then return end
                return original(self, ...)
            end
            retiredKeys[panel] = actor
        end
        call(panel, "setVisible", false)
        call(panel, "removeFromUIManager")
        if panel.Type == "ISDesignationZonePanel" then
            call(actor, "setSeeDesignationZone", false)
            -- Vanilla removeInventoryUI omits zoneUI. Detach only its exact
            -- released panel, including the singleton's stale network callback.
            if type(getPlayerData) == "function" then
                local okay, data = pcall(getPlayerData, 1)
                if okay and data and data.zoneUI == panel then data.zoneUI = nil end
            end
            if ISDesignationZonePanel and ISDesignationZonePanel.instance == panel then
                local primaryPanel = type(getPlayerZoneUI) == "function" and getPlayerZoneUI(0) or nil
                ISDesignationZonePanel.instance = primaryPanel and primaryPanel.player == primary
                    and primaryPanel or nil
            end
        end
    end
    return #panels
end

return ViewUI
