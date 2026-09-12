-- SPDX-License-Identifier: MIT

if type(require) == "function" then pcall(require, "SCNamespace") end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Call = SC.Call or {}

local Call = SC.Call
local unpackFn = table.unpack or unpack
local methodCache = {}
local staticCache = {}
local nativeCallTracer = nil

local function lookupMember(object, name)
    return object[name]
end

-- Kahlua exposes one stable metatable per Java class. Cache only successful
-- Java lookups: Lua fixtures may install instance-specific functions, and a
-- missing Java method may become available after a bridge exposure generation.
local function resolveMethod(object, name)
    if object == nil then return false, "object unavailable" end
    if type(object) ~= "table" then
        local metatable = getmetatable(object)
        if metatable ~= nil then
            local byName = methodCache[metatable]
            local cached = byName and byName[name] or nil
            if cached ~= nil then return true, cached, true end
            local lookupOk, callback = pcall(lookupMember, object, name)
            if not lookupOk then return false, tostring(callback) end
            if type(callback) ~= "function" then
                return false, "method unavailable: " .. tostring(name)
            end
            if byName == nil then
                byName = {}
                methodCache[metatable] = byName
            end
            byName[name] = callback
            return true, callback, true
        end
    end
    local lookupOk, callback = pcall(lookupMember, object, name)
    if not lookupOk then return false, tostring(callback) end
    if type(callback) ~= "function" then
        return false, "method unavailable: " .. tostring(name)
    end
    return true, callback, false
end

local function resolveStatic(object, name)
    if object == nil then return false, "object unavailable" end
    if type(object) ~= "table" then
        local metatable = getmetatable(object)
        if metatable ~= nil then
            local byName = staticCache[metatable]
            local cached = byName and byName[name] or nil
            if cached ~= nil then return true, cached, true end
            local lookupOk, callback = pcall(lookupMember, object, name)
            if not lookupOk then return false, tostring(callback) end
            if type(callback) ~= "function" then
                return false, "static method unavailable: " .. tostring(name)
            end
            if byName == nil then
                byName = {}
                staticCache[metatable] = byName
            end
            byName[name] = callback
            return true, callback, true
        end
    end
    local lookupOk, callback = pcall(lookupMember, object, name)
    if not lookupOk then return false, tostring(callback) end
    if type(callback) ~= "function" then
        return false, "static method unavailable: " .. tostring(name)
    end
    return true, callback, false
end

local function traceNative(name, isNative)
    if isNative and nativeCallTracer ~= nil then nativeCallTracer(name) end
end

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
    local resolved, callback, isNative = resolveMethod(object, name)
    if not resolved then return false, callback end
    traceNative(name, isNative)
    local count = select("#", ...)
    if count == 0 then return pcall(callback, object) end
    if count == 1 then
        local a = ...
        return pcall(callback, object, a)
    end
    if count == 2 then
        local a, b = ...
        return pcall(callback, object, a, b)
    end
    if count == 3 then
        local a, b, c = ...
        return pcall(callback, object, a, b, c)
    end
    return pcall(callback, object, ...)
end

function Call.static(object, name, ...)
    local resolved, callback, isNative = resolveStatic(object, name)
    if not resolved then return false, callback end
    traceNative(name, isNative)
    local count = select("#", ...)
    if count == 0 then return pcall(callback) end
    if count == 1 then
        local a = ...
        return pcall(callback, a)
    end
    if count == 2 then
        local a, b = ...
        return pcall(callback, a, b)
    end
    if count == 3 then
        local a, b, c = ...
        return pcall(callback, a, b, c)
    end
    return pcall(callback, ...)
end

-- Value-first adapter used by gameplay code. Its ordering and fixed four-value
-- tail intentionally match the historical U.call contract.
function Call.value(object, name, ...)
    local resolved, callback, isNative = resolveMethod(object, name)
    if not resolved then return nil, false end
    traceNative(name, isNative)
    local count = select("#", ...)
    local ok, a, b, c, d
    if count == 0 then ok, a, b, c, d = pcall(callback, object)
    elseif count == 1 then
        local x = ...
        ok, a, b, c, d = pcall(callback, object, x)
    elseif count == 2 then
        local x, y = ...
        ok, a, b, c, d = pcall(callback, object, x, y)
    elseif count == 3 then
        local x, y, z = ...
        ok, a, b, c, d = pcall(callback, object, x, y, z)
    else ok, a, b, c, d = pcall(callback, object, ...) end
    if not ok then return nil, false, tostring(a) end
    return a, true, b, c, d
end

function Call.resetMethodCache()
    methodCache = {}
    staticCache = {}
    return true
end

function Call.setNativeCallTracer(callback)
    nativeCallTracer = type(callback) == "function" and callback or nil
    return nativeCallTracer ~= nil
end

return Call
