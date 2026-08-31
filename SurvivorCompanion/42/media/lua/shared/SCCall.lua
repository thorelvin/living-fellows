-- SPDX-License-Identifier: MIT

require "SCNamespace"

local SC = SurvivorCompanion
SC.Call = SC.Call or {}

local Call = SC.Call
local unpackFn = table.unpack or unpack

function Call.pack(...)
    return { n = select("#", ...), ... }
end

function Call.unpack(values, first, last)
    if type(values) ~= "table" then return end
    return unpackFn(values, first or 1, last or values.n or #values)
end

function Call.protected(callback, ...)
    if type(callback) ~= "function" then
        return false, "callback unavailable"
    end
    local values = Call.pack(pcall(callback, ...))
    if values[1] ~= true then
        return false, values[2]
    end
    return true, Call.unpack(values, 2, values.n)
end

function Call.method(object, name, ...)
    if object == nil then return false, "object unavailable" end
    local lookupOk, callback = pcall(function() return object[name] end)
    if not lookupOk then return false, tostring(callback) end
    if type(callback) ~= "function" then
        return false, "method unavailable: " .. tostring(name)
    end
    return Call.protected(callback, object, ...)
end

function Call.static(object, name, ...)
    if object == nil then return false, "object unavailable" end
    local lookupOk, callback = pcall(function() return object[name] end)
    if not lookupOk then return false, tostring(callback) end
    if type(callback) ~= "function" then
        return false, "static method unavailable: " .. tostring(name)
    end
    return Call.protected(callback, ...)
end

return Call
