--[[
PZ Radio Link -- inventory context menu.

The eligibility test is vanilla's own, taken from
client/ISUI/ISInventoryPaneContextMenu.lua:199 -- a RADIO-typed script item with
DeviceData that reports itself portable. No separate type allowlist is kept,
because a list would drift from the game's.

Only the clicked item is examined. No inventory is scanned to build a device list.
]]

PZRL = PZRL or {}

local ContextMenu = {}
PZRL.ContextMenu = ContextMenu

ContextMenu._installed = false

local function onLink(item, player)
    local ok, reason = PZRL.Session.bind(player, item)
    if ok then
        print("[PZRL] linked radio as " .. tostring(reason))
    else
        print("[PZRL] link refused: " .. tostring(reason))
    end
end

local function onUnlink()
    PZRL.Session.clear("unlinked_by_player")
    print("[PZRL] radio unlinked")
end

function ContextMenu.fill(playerIndex, context, items)
    if type(items) ~= "table" or context == nil then return end
    if not PZRL.Session.modeSupported() then return end

    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end

    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" and type(entry.items) == "table" then item = entry.items[1] end
        if item ~= nil and PZRL.Device.isSupported(item) then
            if PZRL.Session.isBoundTo(item) then
                context:addOption("Unlink from phone", item, onUnlink)
            elseif PZRL.Device.heldBy(item, player) then
                context:addOption("Link to phone", item, onLink, player)
            else
                local option = context:addOption("Link to phone (carry it first)", nil, nil)
                if option then option.notAvailable = true end
            end
            return
        end
    end
end

-- Placed radios (IsoRadio) come through the world menu instead. Only the
-- clicked objects are examined; no square or chunk is scanned.
function ContextMenu.fillWorld(playerIndex, context, worldobjects, test)
    if test then return end
    if type(worldobjects) ~= "table" or context == nil then return end
    if not PZRL.Session.modeSupported() then return end

    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end

    for _, object in ipairs(worldobjects) do
        if PZRL.Device.kindOf(object) == PZRL.Device.WORLD then
            if PZRL.Session.isBoundTo(object) then
                context:addOption("Unlink from phone", object, onUnlink)
            elseif PZRL.Device.reachable(object, player, PZRL.Device.WORLD) then
                context:addOption("Link to phone", object, onLink, player)
            else
                local option = context:addOption("Link to phone (stand closer)", nil, nil)
                if option then option.notAvailable = true end
            end
            return
        end
    end
end

function ContextMenu.install()
    if ContextMenu._installed then return true end
    if Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(ContextMenu.fill)
        ContextMenu._installed = true
    end
    if Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(ContextMenu.fillWorld)
    end
    return ContextMenu._installed
end

ContextMenu.install()

return ContextMenu
