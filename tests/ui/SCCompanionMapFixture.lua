-- SPDX-License-Identifier: MIT

require = function(name)
    assert(name == "ISUI/Maps/ISMiniMap")
    return true
end

UIFont = { Small = "Small" }

local records = {}
SCCompanionMapFixture = {
    records = records,
    baseRenderCount = 0,
    reports = {},
}

ISMiniMapInner = {
    render = function(self)
        SCCompanionMapFixture.baseRenderCount = SCCompanionMapFixture.baseRenderCount + 1
        self.baseRendered = true
    end,
}

getTextManager = function()
    return {
        MeasureStringX = function(_, _, value)
            return #tostring(value or "") * 6
        end,
    }
end

SurvivorCompanion = {
    Registry = {
        records = function() return records end,
    },
    Diagnostics = {
        report = function(...)
            SCCompanionMapFixture.reports[#SCCompanionMapFixture.reports + 1] = { ... }
        end,
    },
    GameplayUtil = {
        call = function(object, methodName, ...)
            local method = object and object[methodName] or nil
            if type(method) ~= "function" then return nil, false end
            local ok, value = pcall(method, object, ...)
            if not ok then return nil, false end
            return value, true
        end,
        isDead = function(actor) return actor.dead == true end,
        position = function(actor) return actor.x, actor.y, actor.z end,
        nameOf = function(actor) return actor.name end,
    },
}
