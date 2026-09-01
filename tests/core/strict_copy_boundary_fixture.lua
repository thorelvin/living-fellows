-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion

SC.Commands = nil
SC.FactionContracts = nil
SC.FactionRecruitment = nil
SC.Relationship = nil
SC.Personality = nil
SC.PersonalItems = nil
SC.Objectives = nil
SC.Journal = nil
SC.BaseLife = nil
SC.BaseWork = nil
SC.Dialogue = nil
SC.FactionLife = nil
SC.Trade = nil
SC.Persistence = nil

SC_STRICT_COPY_RECORDS = {}
SC_STRICT_COPY_GROUPS = {}
SC_STRICT_COPY_NOW = 7200000

local settings = {
    defaultOrder = "follow",
    followDistance = 3,
    defaultCombatStance = "defensive",
    defaultCombatDoctrine = "close_defense",
    defaultWeaponPriority = "best",
    maxCompanions = 16,
    factionContractHistoryLimit = 32,
    factionContractMemoryLimit = 64,
    factionContractPromiseLimit = 24,
    factionNotificationLimit = 24,
    factionNotificationFlagLimit = 96,
    factionContractDeadlineHours = 48,
    factionContractCooldownHours = 24,
    factionGuestAccessHours = 12,
    factionContractThreatRadius = 18,
    factionContractThreatMinLoadedSquares = 64,
    factionContractTargetDistance = 24,
    factionContractPulseIntervalMs = 2500,
    factionRecruitmentTrialMinHours = 6,
    factionRecruitmentTrialMaxHours = 24,
    factionRecruitmentExtensionHours = 12,
    factionRecruitmentCooldownHours = 72,
    factionRecruitmentContractsRequired = 2,
    factionTradeDistance = 6,
    factionRecruitmentEnabled = true,
    debugSpawnEnabled = true,
}

SC.Config = {
    get = function(first, second)
        return settings[second or first]
    end,
}

local function call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then return nil, false end
    local ok, value = pcall(object[method], object, ...)
    if not ok then return value, false end
    return value, true
end

SC.GameplayUtil = {
    call = call,
    nowMs = function() return SC_STRICT_COPY_NOW end,
    config = function(key) return settings[key] end,
    modData = function(actor)
        if type(actor.data) ~= "table" then actor.data = {} end
        return actor.data
    end,
    idOf = function(actor) return actor and actor.id or nil end,
    resolveActor = function(id)
        local row = SC_STRICT_COPY_RECORDS[id]
        return row and row.actor or nil, row and row.entry or nil,
            row and nil or "unknown_companion"
    end,
    copyShallow = function(source)
        local result = {}
        for key, value in pairs(source or {}) do result[key] = value end
        return result
    end,
    registryLiving = function()
        local result = {}
        for _, row in pairs(SC_STRICT_COPY_RECORDS) do
            if row.actor then result[#result + 1] = row.actor end
        end
        return result
    end,
    safeSubsystem = function(_, _, callback)
        local ok, a, b, c = pcall(callback)
        if not ok then return false, a end
        return true, a, b, c
    end,
    isDead = function(actor) return actor and actor.dead == true end,
    distance = function() return 0 end,
    canSee = function() return true end,
    text = function(_, fallback) return fallback end,
    say = function() return true end,
    position = function(value)
        return tonumber(value and value.x) or 0, tonumber(value and value.y) or 0,
            tonumber(value and value.z) or 0
    end,
    gridSquare = function() return nil end,
    squareMovingObjects = function() return true end,
    isZombie = function() return false end,
    squareOf = function() return nil end,
    move = function() return true end,
    stop = function() return true end,
}

SC.Factions = {
    group = function(id) return SC_STRICT_COPY_GROUPS[id] end,
    list = function()
        local result = {}
        for _, group in pairs(SC_STRICT_COPY_GROUPS) do result[#result + 1] = group end
        return result
    end,
    adjustStanding = function() return true end,
    forceStanding = function(id, standing)
        local group = SC_STRICT_COPY_GROUPS[id]
        if group then group.standing = standing return true end
        return false
    end,
    member = function(groupOrId, memberKey)
        local group = type(groupOrId) == "table" and groupOrId
            or SC_STRICT_COPY_GROUPS[groupOrId]
        for _, member in ipairs(group and group.members or {}) do
            if member.key == memberKey then return member end
        end
        return nil
    end,
    memberIsPresent = function(member)
        return member and member.alive ~= false and member.away == nil
            and member.departed ~= true
    end,
    presentCount = function(groupOrId)
        local group = type(groupOrId) == "table" and groupOrId
            or SC_STRICT_COPY_GROUPS[groupOrId]
        local count = 0
        for _, member in ipairs(group and group.members or {}) do
            if member.alive ~= false and member.away == nil and member.departed ~= true then
                count = count + 1
            end
        end
        return count
    end,
}

SC.Registry = {
    byId = function(id)
        local row = SC_STRICT_COPY_RECORDS[id]
        return row and { id = id, actor = row.actor, recruited = false,
            factionId = row.factionId } or nil
    end,
}

function getGameTime()
    return {
        getWorldAgeHours = function() return SC_STRICT_COPY_NOW / 3600000 end,
    }
end

function getPlayer() return nil end

