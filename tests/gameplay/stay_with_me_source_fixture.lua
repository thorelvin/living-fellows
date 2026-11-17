-- SPDX-License-Identifier: MIT
-- Loads original downloaded files; only the game's native boundary is modelled.
function isServer() return true end
function isClient() return false end
UIFont = {}
function getActivatedMods() return { contains = function(_, key) return key == "Bridge" end } end
Events = setmetatable({}, { __index = function(owner, name)
    local event = { Add = function() end, Remove = function() end }
    rawset(owner, name, event)
    return event
end })
