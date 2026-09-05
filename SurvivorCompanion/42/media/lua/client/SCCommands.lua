-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Positioning and type(require) == "function" then pcall(require, "SCPositioning") end
if not SC.Relationship and type(require) == "function" then pcall(require, "SCRelationship") end
if not SC.Personality and type(require) == "function" then pcall(require, "SCPersonality") end
if not SC.PersonalItems and type(require) == "function" then pcall(require, "SCPersonalItems") end
if not SC.Objectives and type(require) == "function" then pcall(require, "SCObjectives") end
if not SC.Journal and type(require) == "function" then pcall(require, "SCJournal") end
if not SC.BaseLife and type(require) == "function" then pcall(require, "SCBaseLife") end
if not SC.BaseWork and type(require) == "function" then pcall(require, "SCBaseWork") end
if not SC.StableValue and type(require) == "function" then pcall(require, "SCStableValue") end

SC.Commands = SC.Commands or {}
local Commands = SC.Commands
local states = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local followDistances = { [2] = true, [3] = true, [5] = true, [8] = true }
local moveModes = { copy = true, walk = true, sneak = true, jog = true }
local combatModes = { aggressive = true, defensive = true, passive = true }
local weaponPriorities = { best = true, melee = true, firearm = true, quiet = true }
local combatDoctrines = {
    stealth = true,
    close_defense = true,
    ranged_support = true,
    weapons_free = true,
}
local workModes = { auto = true, idle = true, craft = true }
local internalWorkModes = { auto = true, idle = true, craft = true, build = true }
local targetedWorkKinds = { barricade = true, remove_barricade = true, dismantle = true }
local groupStaging = false
local copyCommandState

local copyLimits = {
    profile = { maxDepth = 3, maxEntries = 64 },
    memories = { maxDepth = 5, maxEntries = 8192 },
    background = { maxDepth = 4, maxEntries = 128 },
    care = { maxDepth = 4, maxEntries = 192 },
    reveals = { maxDepth = 4, maxEntries = 128 },
    objectives = { maxDepth = 6, maxEntries = 512 },
    possessions = { maxDepth = 6, maxEntries = 256 },
    downtime = { maxDepth = 4, maxEntries = 128 },
    downtimeFacts = { maxDepth = 5, maxEntries = 4096 },
    summary = { maxDepth = 2, maxEntries = 64 },
}

local function strictCopy(value, limit, path)
    if not SC.StableValue or type(SC.StableValue.copyStrict) ~= "function" then
        return nil, "stable copy unavailable at " .. tostring(path or "$.commands")
    end
    return SC.StableValue.copyStrict(value, {
        maxDepth = limit.maxDepth,
        maxEntries = limit.maxEntries,
        path = path or "$.commands",
    })
end

local function requiredCopy(value, limit, path)
    local copied, reason = strictCopy(value, limit, path)
    if reason ~= nil then error(reason) end
    return copied
end

local stableDataKeys = {
    "SC_Recruited", "SC_FactionId", "SC_FactionRole", "SC_Order", "SC_FollowDistance", "SC_Scavenge", "SC_AllowOverload", "SC_MoveMode", "SC_MoveModeVersion",
    "SC_RideWithPlayer", "SC_CombatMode", "SC_CombatDoctrine", "SC_WeaponPriority", "SC_HoldFire",
    "SC_Group", "SC_Trust",
    "SC_Personality",
    "SC_Bond", "SC_Morale", "SC_Stress", "SC_TimeTogetherMs",
    "SC_CommandSerial", "SC_LastDowntime", "SC_AnchorX", "SC_AnchorY", "SC_AnchorZ",
    "SC_WorkMode", "SC_WorkX", "SC_WorkY", "SC_WorkZ", "SC_WorkObjectIndex",
    "SC_WorkInitialPlanks",
    "SC_WorkBaseJobId", "SC_WorkKind", "SC_WorkBarricadeSide",
    "SC_ReturnOrder", "SC_ReturnWorkMode",
}

local stableEntryKeys = {
    "recruited", "factionId", "factionRole", "factionLeader", "order", "followDistance", "scavenge", "allowOverload", "rideWithPlayer",
    "moveMode", "moveModeVersion", "combatMode", "combatDoctrine", "holdFire", "weaponPriority", "group", "trust", "bond", "morale", "stress",
    "timeTogetherMs", "memories", "background", "care", "reveals", "lastDowntime", "state",
    "personalityProfile", "objectives", "possessions",
    "workMode", "workTarget", "returnOrder", "returnWorkMode",
}

local function migratedDoctrine(explicit, combatMode, weaponPriority, holdFire)
    if combatDoctrines[explicit] then return explicit end
    if holdFire == true or combatMode == "passive" or weaponPriority == "quiet" then
        return "stealth"
    end
    if combatMode == "aggressive" then return "weapons_free" end
    if weaponPriority == "firearm" then return "ranged_support" end
    return "close_defense"
end

local function applyDoctrine(state, doctrine)
    if not combatDoctrines[doctrine] then return false end
    state.combatDoctrine = doctrine
    if doctrine == "stealth" then
        state.combatMode = "passive"
        state.weaponPriority = "quiet"
        state.holdFire = true
    elseif doctrine == "ranged_support" then
        state.combatMode = "defensive"
        state.weaponPriority = "firearm"
        state.holdFire = false
    elseif doctrine == "weapons_free" then
        state.combatMode = "aggressive"
        state.weaponPriority = "best"
        state.holdFire = false
    else
        state.combatMode = "defensive"
        state.weaponPriority = "best"
        state.holdFire = false
    end
    return true
end

local function rawModData(actor)
    local data, ok = U().call(actor, "getModData")
    if ok and type(data) == "table" then return data end
    return nil
end

local function teamDoctrineForPlayer(player)
    local data = rawModData(player)
    local value = type(data) == "table" and data.SC_TeamCombatDoctrine or nil
    if combatDoctrines[value] then return value end
    return SC.Config and SC.Config.get("defaultCombatDoctrine") or "close_defense"
end

local function storeTeamDoctrine(player, doctrine)
    if not combatDoctrines[doctrine] then return false, "invalid_combat_doctrine" end
    local data = rawModData(player)
    if type(data) ~= "table" then return false, "player_mod_data_unavailable" end
    data.SC_TeamCombatDoctrine = doctrine
    return true
end

local function valueFrom(source, names, fallback)
    if type(source) == "table" then
        for _, name in ipairs(names) do
            if source[name] ~= nil then return source[name] end
        end
    end
    return fallback
end

local function snapshotState(actor, entry)
    local utility = U()
    local data = rawModData(actor)
    local persisted = type(entry) == "table" and type(entry.state) == "table"
        and entry.state or {}
    local persistedOrder = type(persisted.order) == "table" and persisted.order
        or (type(entry) == "table" and type(entry.order) == "table" and entry.order or {})
    local persistedPersonality = type(persisted.personality) == "table"
        and persisted.personality
        or (type(entry) == "table" and type(entry.personality) == "table"
            and entry.personality or {})
    local persistedDowntime = type(persisted.downtime) == "table" and persisted.downtime
        or (type(entry) == "table" and type(entry.downtime) == "table" and entry.downtime or {})
    local persistedObjectives = type(persisted.objectives) == "table" and persisted.objectives
        or (type(entry) == "table" and type(entry.objectives) == "table" and entry.objectives or {})
    local persistedPossessions = type(persisted.possessions) == "table" and persisted.possessions
        or (type(entry) == "table" and type(entry.possessions) == "table" and entry.possessions or {})
    local stableProfile = requiredCopy(valueFrom(entry, { "personalityProfile" },
        persistedPersonality.profile or {}), copyLimits.profile,
        "$.commands.personalityProfile") or {}
    local stableMemories = requiredCopy(valueFrom(entry, { "memories" },
        valueFrom(data, { "SC_Memories" }, persistedPersonality.memories or {})),
        copyLimits.memories, "$.commands.memories") or {}
    local stableBackground = requiredCopy(valueFrom(entry, { "background" },
        persistedPersonality.background), copyLimits.background,
        "$.commands.background")
    local stableCare = requiredCopy(valueFrom(entry, { "care" }, persistedPersonality.care),
        copyLimits.care, "$.commands.care")
    local stableReveals = requiredCopy(valueFrom(entry, { "reveals" },
        persistedPersonality.reveals), copyLimits.reveals, "$.commands.reveals")
    local stableObjectives = requiredCopy(persistedObjectives, copyLimits.objectives,
        "$.commands.objectives") or {}
    local stablePossessions = requiredCopy(persistedPossessions, copyLimits.possessions,
        "$.commands.possessions") or {}
    local stableLastDowntime = requiredCopy(valueFrom(entry, { "lastDowntime" },
        valueFrom(data, { "SC_LastDowntime" }, persistedDowntime.lastCompleted)),
        copyLimits.downtime, "$.commands.lastDowntime")
    local flatOrder = type(entry) == "table" and type(entry.order) == "string"
        and entry.order or nil
    local flatPersonality = type(entry) == "table" and type(entry.personality) == "string"
        and entry.personality or nil
    -- Registry membership means that we own the actor; it does not mean that
    -- the player recruited them. An explicit record is authoritative during
    -- spawn/restore, including an explicit false value.
    local recruited = valueFrom(entry, { "recruited", "isRecruited" }, nil)
    if recruited == nil then
        recruited = valueFrom(data, { "SC_Recruited" }, false)
    end
    local defaultOrder = recruited and "follow" or "wander"
    local state = {
        recruited = recruited == true,
        factionId = type(entry) == "table" and entry.factionId
            or type(data) == "table" and data.SC_FactionId or nil,
        factionRole = type(entry) == "table" and entry.factionRole
            or type(data) == "table" and data.SC_FactionRole or nil,
        order = valueFrom(data, { "SC_Order" }, flatOrder or persistedOrder.current or defaultOrder),
        followDistance = tonumber(valueFrom(data, { "SC_FollowDistance" },
            valueFrom(entry, { "followDistance" }, persistedOrder.followDistance
                or utility.config("followDistance") or 3))) or 3,
        scavenge = valueFrom(data, { "SC_Scavenge" },
            valueFrom(entry, { "scavenge" }, persistedOrder.scavenge == true)) == true,
        allowOverload = valueFrom(data, { "SC_AllowOverload" },
            valueFrom(entry, { "allowOverload" }, persistedOrder.allowOverload == true)) == true,
        rideWithPlayer = valueFrom(data, { "SC_RideWithPlayer" },
            valueFrom(entry, { "rideWithPlayer" }, persistedOrder.rideWithPlayer ~= false)) ~= false,
        workMode = valueFrom(data, { "SC_WorkMode" },
            valueFrom(entry, { "workMode" }, persistedOrder.workMode or "auto")),
        moveMode = valueFrom(data, { "SC_MoveMode" },
            valueFrom(entry, { "moveMode" }, persistedOrder.movementMode
                or (recruited and "copy" or "walk"))),
        moveModeVersion = tonumber(valueFrom(data, { "SC_MoveModeVersion" },
            valueFrom(entry, { "moveModeVersion" }, persistedOrder.movementModeVersion))) or 0,
        combatMode = valueFrom(data, { "SC_CombatMode" },
            valueFrom(entry, { "combatMode", "combatStance" },
                persistedOrder.combatStance or "defensive")),
        combatDoctrine = valueFrom(data, { "SC_CombatDoctrine" },
            valueFrom(entry, { "combatDoctrine" }, persistedOrder.combatDoctrine)),
        weaponPriority = valueFrom(data, { "SC_WeaponPriority" },
            valueFrom(entry, { "weaponPriority" }, persistedOrder.weaponPriority or "best")),
        holdFire = valueFrom(data, { "SC_HoldFire" },
            valueFrom(entry, { "holdFire" }, persistedOrder.holdFire == true)) == true,
        group = valueFrom(data, { "SC_Group" }, valueFrom(entry, { "group" }, persisted.group)),
        personality = valueFrom(data, { "SC_Personality" },
            flatPersonality or persistedPersonality.archetype or "steady"),
        personalityProfile = stableProfile,
        trust = tonumber(valueFrom(data, { "SC_Trust" },
            valueFrom(entry, { "trust" }, persistedPersonality.trust or 0))) or 0,
        bond = tonumber(valueFrom(data, { "SC_Bond" },
            valueFrom(entry, { "bond" }, persistedPersonality.bond or 0))) or 0,
        morale = tonumber(valueFrom(data, { "SC_Morale" },
            valueFrom(entry, { "morale" }, persistedPersonality.morale or 55))) or 55,
        stress = tonumber(valueFrom(data, { "SC_Stress" },
            valueFrom(entry, { "stress" }, persistedPersonality.stress or 12))) or 12,
        memories = stableMemories,
        background = stableBackground,
        care = stableCare,
        reveals = stableReveals,
        timeTogetherMs = tonumber(valueFrom(data, { "SC_TimeTogetherMs" },
            valueFrom(entry, { "timeTogetherMs" }, persistedPersonality.timeTogetherMs or 0))) or 0,
        lastEncouragedAt = tonumber(persistedPersonality.lastEncouragedAt) or 0,
        objectives = stableObjectives,
        possessions = stablePossessions,
        commandSerial = tonumber(valueFrom(data, { "SC_CommandSerial" }, 0)) or 0,
        lastDowntime = stableLastDowntime,
        returnOrder = valueFrom(data, { "SC_ReturnOrder" },
            valueFrom(entry, { "returnOrder" }, persistedOrder.returnOrder)),
        returnWorkMode = valueFrom(data, { "SC_ReturnWorkMode" },
            valueFrom(entry, { "returnWorkMode" }, persistedOrder.returnWorkMode)),
    }
    if not followDistances[state.followDistance] then state.followDistance = 3 end
    -- Version 2 introduces Copy player as the recruited-companion default.
    -- Existing saves have no policy marker, so migrate them once instead of
    -- silently preserving the old implementation default of Walk forever.
    if state.recruited and state.moveModeVersion < 2 then
        state.moveMode = "copy"
    elseif not moveModes[state.moveMode] then
        state.moveMode = state.recruited and "copy" or "walk"
    end
    state.moveModeVersion = 2
    if not combatModes[state.combatMode] then state.combatMode = "defensive" end
    if not weaponPriorities[state.weaponPriority] then state.weaponPriority = "best" end
    state.combatDoctrine = migratedDoctrine(state.combatDoctrine, state.combatMode,
        state.weaponPriority, state.holdFire)
    if not internalWorkModes[state.workMode] then state.workMode = "auto" end
    if not workModes[state.returnWorkMode] then state.returnWorkMode = nil end
    if SC.Relationship and type(SC.Relationship.initialize) == "function" then
        SC.Relationship.initialize(actor, state)
    end
    if SC.Personality and type(SC.Personality.initialize) == "function" then
        state.personalityProfile = SC.Personality.initialize(
            utility.idOf(actor), state.background, state.personalityProfile)
        state.personality = state.personalityProfile.archetype
    end
    local anchorX = valueFrom(data, { "SC_AnchorX" }, nil)
    local anchorY = valueFrom(data, { "SC_AnchorY" }, nil)
    local anchorZ = valueFrom(data, { "SC_AnchorZ" }, nil)
    if type(anchorX) ~= "number" or type(anchorY) ~= "number" then
        -- Restore path: a freshly created actor has no SC_Anchor* mod-data yet, so
        -- fall back to the saved order anchor before defaulting to no post (R2-03).
        local savedAnchor = type(persistedOrder.anchor) == "table" and persistedOrder.anchor or nil
        if savedAnchor and type(savedAnchor.x) == "number" and type(savedAnchor.y) == "number" then
            anchorX, anchorY, anchorZ = savedAnchor.x, savedAnchor.y, savedAnchor.z
        end
    end
    if type(anchorX) == "number" and type(anchorY) == "number" then
        state.anchor = { x = anchorX, y = anchorY, z = anchorZ or 0 }
    end
    local persistedTarget = valueFrom(entry, { "workTarget" }, persistedOrder.workTarget)
    local workX = valueFrom(data, { "SC_WorkX" },
        type(persistedTarget) == "table" and persistedTarget.x or nil)
    local workY = valueFrom(data, { "SC_WorkY" },
        type(persistedTarget) == "table" and persistedTarget.y or nil)
    local workZ = valueFrom(data, { "SC_WorkZ" },
        type(persistedTarget) == "table" and persistedTarget.z or nil)
    local objectIndex = valueFrom(data, { "SC_WorkObjectIndex" },
        type(persistedTarget) == "table" and persistedTarget.objectIndex or nil)
    local initialPlanks = valueFrom(data, { "SC_WorkInitialPlanks" },
        type(persistedTarget) == "table" and persistedTarget.initialPlanks or 0)
    local baseJobId = valueFrom(data, { "SC_WorkBaseJobId" },
        type(persistedTarget) == "table" and persistedTarget.baseJobId or nil)
    local workKind = valueFrom(data, { "SC_WorkKind" },
        type(persistedTarget) == "table" and persistedTarget.kind or "barricade")
    local barricadeSide = valueFrom(data, { "SC_WorkBarricadeSide" },
        type(persistedTarget) == "table" and persistedTarget.barricadeSide or nil)
    if type(workX) == "number" and type(workY) == "number"
        and tonumber(objectIndex) ~= nil then
        state.workTarget = {
            x = workX,
            y = workY,
            z = tonumber(workZ) or 0,
            objectIndex = math.floor(tonumber(objectIndex)),
            initialPlanks = math.max(0, math.floor(tonumber(initialPlanks) or 0)),
            baseJobId = type(baseJobId) == "string" and baseJobId or nil,
            barricadeSide = barricadeSide == "same" and "same"
                or barricadeSide == "opposite" and "opposite" or nil,
            kind = targetedWorkKinds[workKind] and workKind or "barricade",
        }
    end
    return state
end

local function initializeCharacterState(actor, state)
    if SC.PersonalItems and type(SC.PersonalItems.ensure) == "function" then
        local possessions, reason = SC.PersonalItems.ensure(actor, state.possessions)
        if not possessions then return false, reason or "personal_item_initialization_failed" end
        state.possessions = possessions
    end
    if SC.Objectives and type(SC.Objectives.initialize) == "function" then
        SC.Objectives.initialize(actor, state)
    end
    return true
end

local function stateFor(actor, entry)
    local state = states[actor]
    if not state then
        if entry == nil and type(SC.Registry) == "table"
            and type(SC.Registry.byId) == "function" then
            local data = rawModData(actor)
            local id = type(data) == "table" and data.SC_Id or nil
            if type(id) == "string" then
                local ok, resolved = pcall(SC.Registry.byId, id)
                if ok then entry = resolved end
            end
        end
        state = snapshotState(actor, entry)
        local initialized, reason = initializeCharacterState(actor, state)
        if not initialized and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("character-depth", U().idOf(actor), reason)
        end
        states[actor] = state
    end
    return state
end

local function writeStable(actor, entry, state)
    local stableWorkTarget
    if type(state.workTarget) == "table" and type(state.workTarget.x) == "number"
        and type(state.workTarget.y) == "number"
        and tonumber(state.workTarget.objectIndex) ~= nil then
        stableWorkTarget = {
            x = state.workTarget.x,
            y = state.workTarget.y,
            z = tonumber(state.workTarget.z) or 0,
            objectIndex = math.floor(tonumber(state.workTarget.objectIndex)),
            initialPlanks = math.max(0,
                math.floor(tonumber(state.workTarget.initialPlanks) or 0)),
            baseJobId = type(state.workTarget.baseJobId) == "string"
                and state.workTarget.baseJobId or nil,
            barricadeSide = state.workTarget.barricadeSide == "same" and "same"
                or state.workTarget.barricadeSide == "opposite" and "opposite" or nil,
            kind = targetedWorkKinds[state.workTarget.kind]
                and state.workTarget.kind or "barricade",
        }
    end
    -- Validate and detach every nested value before touching actor mod-data or
    -- the registry record. A failed copy therefore cannot commit a shortened
    -- objective, possession, or personality document.
    local prior = type(entry) == "table" and type(entry.state) == "table"
        and entry.state or {}
    local priorPersonality = type(prior.personality) == "table"
        and prior.personality or {}
    local priorDowntime = type(prior.downtime) == "table" and prior.downtime or {}
    local stableProfile = requiredCopy(state.personalityProfile or priorPersonality.profile or {},
        copyLimits.profile, "$.commands.personalityProfile") or {}
    local stableMemories = requiredCopy(type(state.memories) == "table" and state.memories
        or priorPersonality.memories or {}, copyLimits.memories,
        "$.commands.memories") or {}
    local stableBackground = requiredCopy(type(state.background) == "table" and state.background
        or priorPersonality.background or {}, copyLimits.background,
        "$.commands.background") or {}
    local stableCare = requiredCopy(type(state.care) == "table" and state.care
        or priorPersonality.care or {}, copyLimits.care, "$.commands.care") or {}
    local stableReveals = requiredCopy(type(state.reveals) == "table" and state.reveals
        or priorPersonality.reveals or {}, copyLimits.reveals,
        "$.commands.reveals") or {}
    local stableObjectives = requiredCopy(state.objectives or prior.objectives or {},
        copyLimits.objectives, "$.commands.objectives") or {}
    local stablePossessions = requiredCopy(state.possessions or prior.possessions or {},
        copyLimits.possessions, "$.commands.possessions") or {}
    local stableLastDowntime = requiredCopy(state.lastDowntime,
        copyLimits.downtime, "$.commands.lastDowntime")
    local stableDowntimeFacts = requiredCopy(priorDowntime.facts or {},
        copyLimits.downtimeFacts, "$.commands.downtime.facts") or {}
    local data = U().modData(actor)
    if data then
        data.SC_Recruited = state.recruited
        data.SC_FactionId = state.factionId
        data.SC_FactionRole = state.factionRole
        data.SC_Order = state.order
        data.SC_FollowDistance = state.followDistance
        data.SC_Scavenge = state.scavenge
        data.SC_AllowOverload = state.allowOverload
        data.SC_RideWithPlayer = state.rideWithPlayer
        data.SC_MoveMode = state.moveMode
        data.SC_MoveModeVersion = state.moveModeVersion
        data.SC_CombatMode = state.combatMode
        data.SC_CombatDoctrine = state.combatDoctrine
        data.SC_WeaponPriority = state.weaponPriority
        data.SC_HoldFire = state.holdFire
        data.SC_Group = state.group
        data.SC_Personality = state.personality
        data.SC_Trust = state.trust
        data.SC_Bond = state.bond
        data.SC_Morale = state.morale
        data.SC_Stress = state.stress
        data.SC_TimeTogetherMs = state.timeTogetherMs
        data.SC_CommandSerial = state.commandSerial
        data.SC_LastDowntime = stableLastDowntime
        data.SC_WorkMode = state.workMode
        data.SC_ReturnOrder = state.returnOrder
        data.SC_ReturnWorkMode = state.returnWorkMode
        if state.anchor then
            data.SC_AnchorX, data.SC_AnchorY, data.SC_AnchorZ = state.anchor.x, state.anchor.y, state.anchor.z
        else
            data.SC_AnchorX, data.SC_AnchorY, data.SC_AnchorZ = nil, nil, nil
        end
        if stableWorkTarget then
            data.SC_WorkX, data.SC_WorkY, data.SC_WorkZ = stableWorkTarget.x,
                stableWorkTarget.y, stableWorkTarget.z
            data.SC_WorkObjectIndex = stableWorkTarget.objectIndex
            data.SC_WorkInitialPlanks = stableWorkTarget.initialPlanks
            data.SC_WorkBaseJobId = stableWorkTarget.baseJobId
            data.SC_WorkKind = stableWorkTarget.kind
            data.SC_WorkBarricadeSide = stableWorkTarget.barricadeSide
        else
            data.SC_WorkX, data.SC_WorkY, data.SC_WorkZ = nil, nil, nil
            data.SC_WorkObjectIndex = nil
            data.SC_WorkInitialPlanks = nil
            data.SC_WorkBaseJobId = nil
            data.SC_WorkKind = nil
            data.SC_WorkBarricadeSide = nil
        end
    end
    if type(entry) == "table" then
        entry.state = {
            order = {
                current = state.order,
                followDistance = state.followDistance,
                scavenge = state.scavenge,
                allowOverload = state.allowOverload,
                rideWithPlayer = state.rideWithPlayer,
                movementMode = state.moveMode,
                movementModeVersion = state.moveModeVersion,
                combatStance = state.combatMode,
                combatDoctrine = state.combatDoctrine,
                holdFire = state.holdFire,
                weaponPriority = state.weaponPriority,
                workMode = state.workMode,
                workTarget = stableWorkTarget,
                returnOrder = state.returnOrder,
                returnWorkMode = state.returnWorkMode,
            },
            group = state.group,
            personality = {
                archetype = state.personality,
                profile = stableProfile,
                trust = state.trust,
                bond = state.bond,
                morale = state.morale,
                stress = state.stress,
                memories = stableMemories,
                background = stableBackground,
                care = stableCare,
                reveals = stableReveals,
                timeTogetherMs = tonumber(state.timeTogetherMs) or 0,
                lastEncouragedAt = tonumber(state.lastEncouragedAt) or 0,
            },
            objectives = stableObjectives,
            possessions = stablePossessions,
            downtime = {
                lastCompleted = stableLastDowntime,
                facts = stableDowntimeFacts,
            },
        }
        entry.recruited = state.recruited
        entry.factionId = state.factionId
        entry.factionRole = state.factionRole
        entry.factionLeader = state.factionId ~= nil and state.factionRole == "leader"
        entry.order = state.order
        entry.followDistance = state.followDistance
        entry.scavenge = state.scavenge
        entry.allowOverload = state.allowOverload
        entry.rideWithPlayer = state.rideWithPlayer
        entry.moveMode = state.moveMode
        entry.moveModeVersion = state.moveModeVersion
        entry.combatMode = state.combatMode
        entry.combatDoctrine = state.combatDoctrine
        entry.holdFire = state.holdFire
        entry.weaponPriority = state.weaponPriority
        entry.group = state.group
        entry.trust = state.trust
        entry.bond = state.bond
        entry.morale = state.morale
        entry.stress = state.stress
        entry.timeTogetherMs = state.timeTogetherMs
        entry.personalityProfile = stableProfile
        entry.objectives = stableObjectives
        entry.possessions = stablePossessions
        entry.memories = stableMemories
        entry.background = stableBackground
        entry.care = stableCare
        entry.reveals = stableReveals
        entry.lastDowntime = stableLastDowntime
        entry.workMode = state.workMode
        entry.workTarget = stableWorkTarget
        entry.returnOrder = state.returnOrder
        entry.returnWorkMode = state.returnWorkMode
    end
end

local function snapshotStorage(actor, entry)
    local snapshot = { data = {}, entry = {} }
    local data = rawModData(actor)
    if type(data) == "table" then
        for _, key in ipairs(stableDataKeys) do
            snapshot.data[key] = { present = rawget(data, key) ~= nil, value = rawget(data, key) }
        end
    end
    if type(entry) == "table" then
        for _, key in ipairs(stableEntryKeys) do
            snapshot.entry[key] = { present = rawget(entry, key) ~= nil, value = rawget(entry, key) }
        end
    end
    return snapshot
end

local function restoreStorage(actor, entry, snapshot)
    local data = rawModData(actor)
    if type(data) == "table" then
        for _, key in ipairs(stableDataKeys) do
            local value = snapshot.data[key]
            if value and value.present then rawset(data, key, value.value)
            else rawset(data, key, nil) end
        end
    end
    if type(entry) == "table" then
        for _, key in ipairs(stableEntryKeys) do
            local value = snapshot.entry[key]
            if value and value.present then rawset(entry, key, value.value)
            else rawset(entry, key, nil) end
        end
    end
end

local function positionTable(value)
    local x, y, z = U().position(value)
    if not x then return nil end
    return { x = x, y = y, z = z or 0, square = U().squareOf(value) }
end

local function markCommand(actor, entry, state)
    state.commandSerial = (state.commandSerial or 0) + 1
    state.lastCommandAt = U().nowMs()
    if groupStaging then return end
    writeStable(actor, entry, state)
    if SC.Downtime and type(SC.Downtime.cancel) == "function" then
        pcall(SC.Downtime.cancel, actor, "command")
    end
    if SC.Decision and type(SC.Decision.cancelWork) == "function" then
        pcall(SC.Decision.cancelWork, actor, "new_command")
    end
    if SC.Encounter and type(SC.Encounter.cancelScavenge) == "function" then
        pcall(SC.Encounter.cancelScavenge, actor, "new_command")
    end
    if SC.Logistics and type(SC.Logistics.reset) == "function" then
        pcall(SC.Logistics.reset, actor)
    end
end

local function resolve(id)
    if type(id) ~= "string" or id == "" then return nil, nil, "invalid_id" end
    local actor, entry = U().resolveActor(id)
    if not actor then return nil, nil, "unknown_companion" end
    if U().isDead(actor) then return nil, entry, "dead" end
    return actor, entry, nil
end

local function clearWorkState(state)
    if state.workMode == "build" then state.workMode = state.returnWorkMode or "auto" end
    state.workTarget = nil
    state.returnOrder = nil
    state.returnWorkMode = nil
end

local function setOrder(actor, entry, state, order, anchor)
    local id = U().idOf(actor)
    if not groupStaging and state.order == "base_duty" and order ~= "base_duty" and SC.BaseLife
        and type(SC.BaseLife.setDuty) == "function" then
        pcall(SC.BaseLife.setDuty, id, false)
        -- Leaving base duty must also cancel any in-flight base job (e.g. a queued
        -- barricade), or it lingers blocked in a following companion's work queue
        -- out in the field. setDuty releases the claim; this clears the queued action.
        if SC.BaseWork and type(SC.BaseWork.cancel) == "function" then
            pcall(SC.BaseWork.cancel, actor, "left_base_duty")
        end
    end
    clearWorkState(state)
    state.order = order
    state.tacticalTarget = nil
    state.pendingInteraction = nil
    if anchor then state.anchor = positionTable(anchor) end
    if order == "follow" or order == "regroup" then state.anchor = nil end
    markCommand(actor, entry, state)
    return true, order
end

local function handleBaseDuty(actor, entry, state)
    if not SC.BaseLife or type(SC.BaseLife.active) ~= "function"
        or SC.BaseLife.active() == nil then return false, "base_missing" end
    local id = U().idOf(actor)
    local resident = type(SC.BaseLife.resident) == "function" and SC.BaseLife.resident(id) or nil
    local role = resident and resident.role or "generalist"
    local assigned, reason = SC.BaseLife.assign(id, role, true)
    if assigned ~= true then return false, reason end
    clearWorkState(state)
    state.order = "base_duty"
    state.anchor = U().copyShallow(SC.BaseLife.active().core)
    state.tacticalTarget, state.pendingInteraction = nil, nil
    markCommand(actor, entry, state)
    return true, "base_duty"
end

local function handleSetBaseRole(actor, entry, state, payload)
    if not SC.BaseLife or type(SC.BaseLife.assign) ~= "function" then
        return false, "base_life_unavailable"
    end
    local role = type(payload) == "table" and payload.role or payload
    if type(role) ~= "string" or not SC.BaseLife.ROLES[role] then
        return false, "invalid_base_role"
    end
    local resident = type(SC.BaseLife.resident) == "function"
        and SC.BaseLife.resident(U().idOf(actor)) or nil
    local assigned, reason = SC.BaseLife.assign(U().idOf(actor), role,
        resident and resident.duty == true or state.order == "base_duty")
    if assigned ~= true then return false, reason end
    markCommand(actor, entry, state)
    return true, "base_role_" .. role
end

local function handleWorkMode(actor, entry, state, payload)
    local mode = type(payload) == "table" and payload.mode or payload
    if not workModes[mode] then return false, "invalid_work_mode" end
    if state.order == "work" then
        state.order = "stay"
        state.anchor = positionTable(actor)
        state.workTarget = nil
        state.returnOrder = nil
        state.returnWorkMode = nil
    end
    state.workMode = mode
    markCommand(actor, entry, state)
    return true, "work_mode_" .. mode
end

local function barricadeTarget(actor, payload)
    local object = type(payload) == "table" and payload.object or payload
    if object == nil or not U().hasMethod(object, "getBarricadeForCharacter") then
        return nil, nil, "invalid_barricade_target"
    end
    local square = U().loadedSquare(object)
    local index, indexOk = U().call(object, "getObjectIndex")
    if not square or not indexOk or tonumber(index) == nil or tonumber(index) < 0 then
        return nil, nil, "unloaded_barricade_target"
    end
    local allowed, allowedOk = U().call(object, "isBarricadeAllowed")
    local canBarricade, canOk = U().call(object, "getCanBarricade")
    if (not allowedOk or allowed ~= true) and (not canOk or canBarricade ~= true) then
        return nil, nil, "barricade_not_allowed"
    end
    local open, openOk = U().call(object, "IsOpen")
    if openOk and open == true then return nil, nil, "close_target_first" end
    local existing, existingOk = U().call(object, "getBarricadeForCharacter", actor)
    if existingOk and existing then
        local canAdd, canAddOk = U().call(existing, "canAddPlank")
        if canAddOk and canAdd ~= true then return nil, nil, "barricade_full" end
    end
    return object, square, nil
end

local function handleBarricade(actor, entry, state, payload)
    local object, square, reason = barricadeTarget(actor, payload)
    if not object then return false, reason end
    local position = positionTable(square)
    local objectIndex = select(1, U().call(object, "getObjectIndex"))
    local existing = select(1, U().call(object, "getBarricadeForCharacter", actor))
    local initialPlanks = 0
    if existing then
        local count, countOk = U().call(existing, "getNumPlanks")
        if countOk and tonumber(count) then initialPlanks = math.max(0, math.floor(tonumber(count))) end
    end
    local previousOrder = state.order == "work" and state.returnOrder or state.order
    if previousOrder ~= "follow" and previousOrder ~= "stay" and previousOrder ~= "guard"
        and previousOrder ~= "base_duty" then
        previousOrder = "stay"
    end
    state.returnOrder = previousOrder
    state.returnWorkMode = state.workMode == "build"
        and (workModes[state.returnWorkMode] and state.returnWorkMode or "auto")
        or (workModes[state.workMode] and state.workMode or "auto")
    state.order = "work"
    state.workMode = "build"
    state.tacticalTarget = nil
    state.pendingInteraction = nil
    state.workTarget = {
        object = object,
        x = position.x,
        y = position.y,
        z = position.z,
        objectIndex = math.floor(tonumber(objectIndex)),
        initialPlanks = initialPlanks,
        baseJobId = type(payload) == "table" and payload.baseJobId or nil,
        kind = "barricade",
    }
    markCommand(actor, entry, state)
    return true, "barricade_ordered"
end

local function targetedWorkObject(actor, payload, kind)
    local object = type(payload) == "table" and payload.object or payload
    if object == nil then return nil, nil, "invalid_" .. tostring(kind) .. "_target" end
    local square = U().loadedSquare(object)
    local index, indexOk = U().call(object, "getObjectIndex")
    if not square or not indexOk or tonumber(index) == nil or tonumber(index) < 0 then
        return nil, nil, "unloaded_" .. tostring(kind) .. "_target"
    end
    if kind == "remove_barricade" then
        if not U().hasMethod(object, "getBarricadeForCharacter") then
            return nil, nil, "invalid_remove_barricade_target"
        end
        local barricaded, barricadedOk = U().call(object, "isBarricaded")
        if not barricadedOk or barricaded ~= true then
            return nil, nil, "target_is_not_barricaded"
        end
    elseif kind == "dismantle" then
        local isThumpable = false
        if type(instanceof) == "function" then
            local ok, value = pcall(instanceof, object, "IsoThumpable")
            isThumpable = ok and value == true
        end
        local dismantlable, dismantlableOk = U().call(object, "isDismantable")
        if not isThumpable or not dismantlableOk or dismantlable ~= true then
            return nil, nil, "target_is_not_dismantlable"
        end
    else
        return nil, nil, "unsupported_targeted_work"
    end
    return object, square, nil
end

local function handleTargetedWork(actor, entry, state, payload, kind)
    local object, square, reason = targetedWorkObject(actor, payload, kind)
    if not object then return false, reason end
    local position = positionTable(square)
    local objectIndex = select(1, U().call(object, "getObjectIndex"))
    local previousOrder = state.order == "work" and state.returnOrder or state.order
    if previousOrder ~= "follow" and previousOrder ~= "stay" and previousOrder ~= "guard"
        and previousOrder ~= "base_duty" then
        previousOrder = "stay"
    end
    state.returnOrder = previousOrder
    state.returnWorkMode = state.workMode == "build"
        and (workModes[state.returnWorkMode] and state.returnWorkMode or "auto")
        or (workModes[state.workMode] and state.workMode or "auto")
    state.order = "work"
    state.workMode = "build"
    state.tacticalTarget = nil
    state.pendingInteraction = nil
    state.workTarget = {
        object = object,
        x = position.x,
        y = position.y,
        z = position.z,
        objectIndex = math.floor(tonumber(objectIndex)),
        kind = kind,
        barricadeSide = kind == "remove_barricade" and type(payload) == "table"
            and payload.barricadeSide or nil,
    }
    markCommand(actor, entry, state)
    return true, kind .. "_ordered"
end

local function handleFinishWork(actor, entry, state)
    if state.order ~= "work" or state.workMode ~= "build"
        or type(state.workTarget) ~= "table"
        or targetedWorkKinds[state.workTarget.kind] ~= true then
        return false, "no_verified_targeted_work"
    end
    local completedTarget = state.workTarget
    local completedKind = completedTarget.kind
    if SC.Objectives and type(SC.Objectives.noteEvent) == "function" then
        SC.Objectives.noteEvent(state, "worked", { activity = completedKind })
    end
    local baseJobId = state.workTarget.baseJobId
    local nextOrder = state.returnOrder
    if nextOrder ~= "follow" and nextOrder ~= "stay" and nextOrder ~= "guard"
        and nextOrder ~= "base_duty" then
        nextOrder = "stay"
    end
    state.order = nextOrder
    state.workMode = workModes[state.returnWorkMode] and state.returnWorkMode or "auto"
    state.workTarget = nil
    state.returnOrder = nil
    state.returnWorkMode = nil
    state.tacticalTarget = nil
    state.pendingInteraction = nil
    if nextOrder == "stay" and not state.anchor then state.anchor = positionTable(actor) end
    if nextOrder == "follow" then state.anchor = nil end
    if baseJobId and SC.BaseLife and type(SC.BaseLife.completeJob) == "function" then
        SC.BaseLife.completeJob(baseJobId, U().idOf(actor), "barricaded")
    end
    if (completedKind == "remove_barricade" or completedKind == "dismantle")
        and SC.Factions and type(SC.Factions.atPosition) == "function"
        and type(SC.Factions.noteOffense) == "function" then
        local faction = SC.Factions.atPosition(completedTarget)
        if faction then SC.Factions.noteOffense(faction.id, "barricade", 1) end
    end
    markCommand(actor, entry, state)
    return true, "work_finished"
end

local function handleFollow(actor, entry, state, payload, player)
    return setOrder(actor, entry, state, "follow")
end

local function handleCautiousFollow(actor, entry, state)
    clearWorkState(state)
    state.order = "follow"
    state.anchor = nil
    state.moveMode = "sneak"
    state.moveModeVersion = 2
    state.scavenge = true
    state.tacticalTarget = nil
    state.pendingInteraction = nil
    markCommand(actor, entry, state)
    return true, "cautious_follow"
end

local function handleStay(actor, entry, state)
    return setOrder(actor, entry, state, "stay", actor)
end

local function handleGuard(actor, entry, state, payload)
    local anchor = type(payload) == "table" and (payload.square or payload.target) or nil
    return setOrder(actor, entry, state, "guard", anchor or actor)
end

local function handleRegroup(actor, entry, state)
    return setOrder(actor, entry, state, "regroup")
end

local function handleRetreat(actor, entry, state)
    return setOrder(actor, entry, state, "retreat")
end

local function handleFollowDistance(actor, entry, state, payload)
    local value = type(payload) == "table" and payload.distance or payload
    value = tonumber(value)
    if not followDistances[value] then return false, "invalid_follow_distance" end
    state.followDistance = value
    markCommand(actor, entry, state)
    return true, "follow_distance"
end

local function handleScavenge(actor, entry, state, payload)
    local value = payload
    if type(payload) == "table" then value = payload.enabled end
    if type(value) ~= "boolean" then return false, "invalid_boolean" end
    state.scavenge = value
    markCommand(actor, entry, state)
    return true, value and "scavenge_on" or "scavenge_off"
end

local function handleAllowOverload(actor, entry, state, payload)
    local value = payload
    if type(payload) == "table" then value = payload.enabled end
    if type(value) ~= "boolean" then return false, "invalid_boolean" end
    state.allowOverload = value
    if SC.Logistics and type(SC.Logistics.reset) == "function" then
        SC.Logistics.reset(actor)
    end
    markCommand(actor, entry, state)
    return true, value and "overload_allowed" or "overload_disallowed"
end

local function handleRideWithPlayer(actor, entry, state, payload)
    local value = payload
    if type(payload) == "table" then value = payload.enabled end
    if type(value) ~= "boolean" then return false, "invalid_boolean" end
    state.rideWithPlayer = value
    if not groupStaging and SC.Vehicle and type(SC.Vehicle.invalidateManifests) == "function" then
        SC.Vehicle.invalidateManifests()
    end
    markCommand(actor, entry, state)
    return true, value and "ride_with_player_on" or "ride_with_player_off"
end

local function handleMoveMode(actor, entry, state, payload)
    local value = type(payload) == "table" and payload.mode or payload
    if not moveModes[value] then return false, "invalid_move_mode" end
    state.moveMode = value
    state.moveModeVersion = 2
    markCommand(actor, entry, state)
    return true, value
end

local function handleCombatMode(actor, entry, state, payload)
    local value = type(payload) == "table" and payload.mode or payload
    if not combatModes[value] then return false, "invalid_combat_mode" end
    state.combatMode = value
    markCommand(actor, entry, state)
    return true, value
end

local function handleCombatDoctrine(actor, entry, state, payload)
    local value = type(payload) == "table"
        and (payload.doctrine or payload.mode) or payload
    if not applyDoctrine(state, value) then return false, "invalid_combat_doctrine" end
    markCommand(actor, entry, state)
    if groupStaging then return true, value end
    if SC.Combat and type(SC.Combat.equipPreferred) == "function" then
        local preferred = value == "ranged_support" and "firearm"
            or value == "stealth" and "quiet" or state.weaponPriority
        pcall(SC.Combat.equipPreferred, actor, preferred)
    end
    return true, value
end

local function handleWeaponPriority(actor, entry, state, payload)
    local value = type(payload) == "table" and payload.priority or payload
    if not weaponPriorities[value] then return false, "invalid_weapon_priority" end
    state.weaponPriority = value
    markCommand(actor, entry, state)
    if groupStaging then return true, value end
    if SC.Combat and type(SC.Combat.equipPreferred) == "function" then
        local ok, equipped, equipReason, equipDetails = pcall(
            SC.Combat.equipPreferred, actor, value)
        if ok and equipped == true then
            return true, equipReason or "weapon_equipped", equipDetails
        end
        return true, equipped == false and "weapon_priority_equip_deferred"
            or "weapon_priority_saved", {
                equipReason = ok and equipReason or equipped,
                weaponName = type(equipDetails) == "table" and equipDetails.weaponName or nil,
            }
    end
    return true, "weapon_priority_saved"
end

local function handleHoldFire(actor, entry, state)
    applyDoctrine(state, "stealth")
    markCommand(actor, entry, state)
    return true, "hold_fire"
end

local function handleFireAtWill(actor, entry, state)
    if state.combatDoctrine == "stealth" then
        applyDoctrine(state, "close_defense")
    else
        state.holdFire = false
    end
    markCommand(actor, entry, state)
    return true, "fire_at_will"
end

local function handleHoldFirePolicy(actor, entry, state, payload)
    local value = payload
    if type(payload) == "table" then value = payload.enabled end
    if type(value) ~= "boolean" then return false, "invalid_boolean" end
    state.holdFire = value
    markCommand(actor, entry, state)
    return true, value and "hold_fire" or "fire_at_will"
end

local function commandTarget(payload)
    if type(payload) ~= "table" then return payload end
    return payload.square or payload.target or payload.object or payload
end

local function resolvedMoveMode(state, player)
    if SC.Positioning and type(SC.Positioning.resolveMoveMode) == "function" then
        return SC.Positioning.resolveMoveMode(state.moveMode, player)
    end
    return state.moveMode == "copy" and "walk" or state.moveMode
end

local function handleMoveTo(actor, entry, state, payload, player)
    local target = commandTarget(payload)
    local square = U().loadedSquare(target)
    if not square or not U().isSquareFree(square) then return false, "invalid_destination" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then return false, "navigation_unavailable" end
    local accepted, status = SC.Navigation.request(actor, square,
        resolvedMoveMode(state, player), {
        action = "ordered_move",
        targetSquare = square,
    })
    if not accepted then return false, status or "movement_rejected" end
    clearWorkState(state)
    state.order = "move_to"
    state.tacticalTarget = positionTable(square)
    markCommand(actor, entry, state)
    return true, status or "moving"
end

local function handleDoor(actor, entry, state, payload, player, action)
    local object = type(payload) == "table" and (payload.object or payload.door) or payload
    if not object then return false, "missing_door" end
    if not SC.Navigation then return false, "navigation_unavailable" end
    if U().distance(actor, object) > 1.75 then
        local square = U().squareOf(object)
        if not square then return false, "invalid_door" end
        if type(SC.Navigation.request) ~= "function" then return false, "navigation_unavailable" end
        local accepted, status = SC.Navigation.request(actor, square,
            resolvedMoveMode(state, player), {
            action = "approach_interaction",
            pendingAction = action,
            object = object,
            targetSquare = square,
        })
        if not accepted then return false, status or "approach_rejected" end
        clearWorkState(state)
        state.pendingInteraction = { object = object, action = action }
        state.order = "interact"
        markCommand(actor, entry, state)
        return true, status or "approaching_interaction"
    end
    if type(SC.Navigation.interact) ~= "function" then return false, "navigation_unavailable" end
    local accepted, status = SC.Navigation.interact(actor, object, action)
    if not accepted then return false, status or "interaction_rejected" end
    markCommand(actor, entry, state)
    return true, status or action
end

local function handleCheckRoom(actor, entry, state, payload)
    local target = commandTarget(payload)
    local square = U().loadedSquare(target)
    if not square then return false, "invalid_room_target" end
    local _, _, actorZ = U().position(actor)
    local _, _, targetZ = U().position(square)
    if math.floor(actorZ or 0) ~= math.floor(targetZ or 0) then return false, "room_check_wrong_floor" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then return false, "navigation_unavailable" end
    local accepted, status = SC.Navigation.request(actor, square, "sneak", {
        action = "check_room",
        orderedFloor = math.floor(targetZ or 0),
        targetSquare = square,
    })
    if not accepted then return false, status or "room_check_rejected" end
    clearWorkState(state)
    state.order = "check_room"
    state.tacticalTarget = positionTable(square)
    markCommand(actor, entry, state)
    return true, status or "checking_room"
end

local function vehicleAction(actor, entry, state, payload, player, action)
    local vehicle
    if type(payload) == "table" then vehicle = payload.vehicle else vehicle = payload end
    if action == "board_vehicle" and not vehicle and player then
        vehicle = select(1, U().call(player, "getVehicle"))
    elseif action == "exit_vehicle" and not vehicle then
        vehicle = select(1, U().call(actor, "getVehicle"))
    end
    if not vehicle then return false, "vehicle_unavailable" end
    if action == "exit_vehicle" and SC.Vehicle
        and type(SC.Vehicle.isStationary) == "function" then
        local stopped, stopReason = SC.Vehicle.isStationary(vehicle)
        if stopped ~= true then return false, stopReason or "vehicle_moving" end
    end
    if not U().move(actor, "walk", {
        action = action,
        vehicle = vehicle,
        seat = type(payload) == "table" and payload.seat or nil,
        transactional = true,
        immediateCommand = true,
        playerCommand = true,
    }) then return false, action .. "_rejected" end
    markCommand(actor, entry, state)
    return true, action
end

local function callUI(methodName, ...)
    local ui = SC.UI
    if type(ui) ~= "table" then return false end
    local method = ui[methodName]
    if type(method) ~= "function" then return false end
    local ok, result = pcall(method, ...)
    if not ok then ok, result = pcall(method, ui, ...) end
    return ok and result == true
end

local function handleOpenInventory(actor, entry, state, payload, player)
    if callUI("openInventory", actor, player) then return true, "inventory_opened" end
    return false, "ui_unavailable"
end

local function handleOpenHealth(actor, entry, state, payload, player)
    if callUI("openHealth", actor, player) then return true, "health_opened" end
    return false, "ui_unavailable"
end

local function handleEmote(actor, entry, state, payload)
    local emote = type(payload) == "table" and payload.emote or payload
    if not SC.Relationship or type(SC.Relationship.playEmote) ~= "function" then
        return false, "emote_unavailable"
    end
    return SC.Relationship.playEmote(actor, emote)
end

local function handleRecruit(actor, entry, state, payload, player)
    if state.factionId ~= nil or type(entry) == "table" and entry.factionId ~= nil then
        return false, "faction_members_cannot_be_recruited"
    end
    if state.recruited then return true, "already_recruited" end
    state.recruited = true
    state.order = "follow"
    state.rideWithPlayer = true
    state.moveMode = "copy"
    state.moveModeVersion = 2
    applyDoctrine(state, teamDoctrineForPlayer(player))
    state.trust = math.max(state.trust or 0, 1)
    if SC.Relationship and type(SC.Relationship.noteEvent) == "function" then
        SC.Relationship.noteEvent(state, "recruited", {
            trust = 4, bond = 2, morale = 3, counter = "recruited",
        })
    end
    markCommand(actor, entry, state)
    if SC.Vehicle and type(SC.Vehicle.invalidateManifests) == "function" then
        SC.Vehicle.invalidateManifests()
    end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "team.recruit", nil, nil,
            { state = state, fallback = U().text("IGUI_SC_Recruit_Response", "All right. I will come with you.") })
    else
        U().say(actor, U().text("IGUI_SC_Recruit_Response", "All right. I will come with you."))
    end
    return true, "recruited"
end

local function handleDismiss(actor, entry, state)
    if SC.FactionRecruitment and type(SC.FactionRecruitment.originForActor) == "function" then
        local origin = SC.FactionRecruitment.originForActor(U().idOf(actor))
        if origin and origin.status == "trial"
            and type(SC.FactionRecruitment.returnNow) == "function" then
            return SC.FactionRecruitment.returnNow(origin.factionId, nil, true)
        end
    end
    if not U().move(actor, "walk", { action = "leave_group", dismissed = true }) then
        return false, "dismiss_rejected"
    end
    state.recruited = false
    if SC.BaseLife and type(SC.BaseLife.setDuty) == "function" then
        pcall(SC.BaseLife.setDuty, U().idOf(actor), false)
    end
    clearWorkState(state)
    state.order = "dismissed"
    state.anchor = nil
    markCommand(actor, entry, state)
    if SC.Vehicle and type(SC.Vehicle.invalidateManifests) == "function" then
        SC.Vehicle.invalidateManifests()
    end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "team.dismiss", nil, nil,
            { state = state, fallback = U().text("IGUI_SC_Dismiss_Response", "I understand. Take care.") })
    else
        U().say(actor, U().text("IGUI_SC_Dismiss_Response", "I understand. Take care."))
    end
    return true, "dismissed"
end

local function handleSetGroup(actor, entry, state, payload)
    local group = type(payload) == "table" and payload.group or payload
    if group ~= nil and type(group) ~= "string" then return false, "invalid_group" end
    if group == "" then group = nil end
    state.group = group
    markCommand(actor, entry, state)
    return true, "group_set"
end

-- Player-initiated care: preflight the hand-bandage here (a treatable wound, a
-- bandage in the player's inventory, and range), then hand off to SC.PlayerCare to
-- walk the player in and run the timed action. The native queueing lives in
-- SC.PlayerCare (loaded only in-game); without it -- e.g. a headless harness -- the
-- command fails closed rather than pretending to treat.
local function handleBandage(actor, entry, state, payload, player)
    if not player then return false, "player_unavailable" end
    if not SC.Medical or type(SC.Medical.playerBandagePreflight) ~= "function" then
        return false, "medical_unavailable"
    end
    local ready, reason = SC.Medical.playerBandagePreflight(actor, player)
    if not ready then return false, reason or "cannot_bandage" end
    if SC.PlayerCare and type(SC.PlayerCare.queueBandage) == "function" then
        local queued, queueReason = SC.PlayerCare.queueBandage(player, actor)
        return queued == true, queued == true and (queueReason or "bandage_started")
            or (queueReason or "bandage_not_started")
    end
    return false, "ui_unavailable"
end

local handlers = {
    bandage = handleBandage,
    follow = handleFollow,
    cautious_follow = handleCautiousFollow,
    stay = handleStay,
    guard = handleGuard,
    base_duty = handleBaseDuty,
    set_base_role = handleSetBaseRole,
    regroup = handleRegroup,
    retreat = handleRetreat,
    set_follow_distance = handleFollowDistance,
    set_scavenge = handleScavenge,
    set_allow_overload = handleAllowOverload,
    set_ride_with_player = handleRideWithPlayer,
    set_work_mode = handleWorkMode,
    set_move_mode = handleMoveMode,
    set_combat_mode = handleCombatMode,
    set_combat_doctrine = handleCombatDoctrine,
    set_weapon_priority = handleWeaponPriority,
    set_hold_fire = handleHoldFirePolicy,
    hold_fire = handleHoldFire,
    fire_at_will = handleFireAtWill,
    move_to = handleMoveTo,
    open_door = function(actor, entry, state, payload, player)
        return handleDoor(actor, entry, state, payload, player, "open_door")
    end,
    close_door = function(actor, entry, state, payload, player)
        return handleDoor(actor, entry, state, payload, player, "close_door")
    end,
    check_room = handleCheckRoom,
    barricade = handleBarricade,
    remove_barricade = function(actor, entry, state, payload)
        return handleTargetedWork(actor, entry, state, payload, "remove_barricade")
    end,
    dismantle = function(actor, entry, state, payload)
        return handleTargetedWork(actor, entry, state, payload, "dismantle")
    end,
    finish_work = handleFinishWork,
    board_vehicle = function(actor, entry, state, payload, player)
        return vehicleAction(actor, entry, state, payload, player, "board_vehicle")
    end,
    exit_vehicle = function(actor, entry, state, payload, player)
        return vehicleAction(actor, entry, state, payload, player, "exit_vehicle")
    end,
    open_inventory = handleOpenInventory,
    open_health = handleOpenHealth,
    emote = handleEmote,
    recruit = handleRecruit,
    dismiss = handleDismiss,
    set_group = handleSetGroup,
}

local function inventorySummary(actor)
    local utility = U()
    local counts = { bandages = 0, food = 0, water = 0, ammunition = 0 }
    for _, item in ipairs(utility.inventoryItems(utility.inventory(actor), 120)) do
        local itemType = string.lower(utility.itemType(item))
        local category, categoryOk = utility.call(item, "getCategory")
        category = categoryOk and string.lower(tostring(category)) or ""
        if string.find(itemType, "bandage", 1, true) or string.find(itemType, "rippedsheet", 1, true) then
            counts.bandages = counts.bandages + 1
        end
        if category == "food" then counts.food = counts.food + 1 end
        if string.find(itemType, "water", 1, true) then counts.water = counts.water + 1 end
        if string.find(itemType, "ammo", 1, true) or string.find(itemType, "bullet", 1, true)
            or string.find(itemType, "shell", 1, true) then counts.ammunition = counts.ammunition + 1 end
    end
    return counts
end

local function currentActivity(actor, state)
    if SC.Encounter and type(SC.Encounter.activity) == "function" then
        local ok, activity = pcall(SC.Encounter.activity, actor)
        if ok and activity then return activity end
    end
    if SC.Decision and type(SC.Decision.peek) == "function" then
        local decision = SC.Decision.peek(actor)
        if decision and decision.current then return decision.current end
    end
    if SC.Downtime and type(SC.Downtime.peek) == "function" then
        local downtime = SC.Downtime.peek(actor)
        if downtime and downtime.active then return downtime.active.kind end
    end
    if SC.Combat and type(SC.Combat.peek) == "function" then
        local combat = SC.Combat.peek(actor)
        if combat and combat.active then return combat.lastAction or "combat" end
    end
    return state.order or "idle"
end

local function currentIntent(actor)
    if SC.Decision and type(SC.Decision.peek) == "function" then
        local decision = SC.Decision.peek(actor)
        if decision then return decision.intent or decision.current end
    end
    return nil
end

local function woundSummaries(wounds)
    local result = {}
    for index = 1, math.min(type(wounds) == "table" and #wounds or 0, 32) do
        local wound = wounds[index]
        result[#result + 1] = {
            name = wound.name,
            index = wound.index,
            bleeding = wound.bleeding == true,
            bitten = wound.bitten == true,
            infected = wound.infected == true,
            bandaged = wound.bandaged == true,
            dirtyBandage = wound.dirtyBandage == true,
            scratched = wound.scratched == true,
            cut = wound.cut == true,
            deepWound = wound.deepWound == true,
            burned = wound.burned == true,
            fractured = wound.fractured == true,
            severity = tonumber(wound.severity) or 0,
        }
    end
    return result
end

local function stableSummaryCopy(value, path)
    local copied, reason = strictCopy(value, copyLimits.summary,
        path or "$.commands.summary")
    if reason ~= nil then
        return { unavailable = true, copyError = reason }
    end
    return copied
end

-- Read-only query in the behavioral sense: it does not create command state,
-- write mod data, reserve objects, move actors, or change any subsystem.
function Commands.describe(companionId, player)
    local actor, entry = U().resolveActor(companionId)
    if not actor then
        return {
            id = companionId,
            name = U().text("UI_SC_UnknownCompanion", "Unknown companion"),
            actor = nil,
            health = 0,
            hunger = nil,
            thirst = nil,
            distance = math.huge,
            order = "unavailable",
            activity = "unavailable",
            combatMode = "defensive",
            combatDoctrine = teamDoctrineForPlayer(player),
            holdFire = true,
            followDistance = U().config("followDistance") or 3,
            scavenge = false,
            allowOverload = false,
            rideWithPlayer = true,
            workMode = "auto",
            group = nil,
            bond = 0,
            morale = 0,
            stress = 0,
            relationshipTier = "cautious",
            mood = "steady",
            currentNeed = "unavailable",
            recentMemory = U().text("IGUI_SC_Memory_None", "I do not have much to say about that yet."),
            profession = U().text("UI_SC_Value_Unknown", "Unknown"),
            aptitude = U().text("UI_SC_Value_Unknown", "Unknown"),
            backgroundLabel = U().text("UI_SC_Value_Unknown", "Unknown"),
            timeTogetherHours = 0,
            knoxInfected = false,
            knox = U().text("UI_SC_Status_Unavailable", "Unavailable"),
            status = U().text("UI_SC_Status_Unavailable", "Unavailable"),
            alive = false,
            available = false,
        }
    end
    local state = states[actor] or snapshotState(actor, entry)
    local affiliation = SC.Factions and type(SC.Factions.affiliation) == "function"
        and SC.Factions.affiliation(entry or actor) or nil
    local alive = not U().isDead(actor) and U().nativeHealth(actor) > 0
    local medical
    if SC.Medical and type(SC.Medical.assess) == "function" then
        local ok, value = pcall(SC.Medical.assess, actor)
        if ok then medical = value end
    end
    medical = medical or { health = U().nativeHealth(actor), wounds = {}, woundCount = 0, knoxInfected = false, infectionLevel = 0 }
    local supplies = inventorySummary(actor)
    local load
    if SC.Logistics and type(SC.Logistics.audit) == "function" then
        local ok, value = pcall(SC.Logistics.audit, actor)
        if ok and type(value) == "table" then load = value end
    end
    local status = SC.Medical and type(SC.Medical.statusText) == "function"
        and SC.Medical.statusText(actor) or (alive and "Stable" or "Dead")
    local knox = medical.knoxInfected
        and (U().text("UI_SC_Status_Knox", "Knox symptoms") .. " (" .. tostring(math.floor(medical.infectionLevel or 0)) .. "%)")
        or U().text("UI_SC_Status_NoKnox", "No Knox symptoms")
    local relationship = {}
    if SC.Relationship and type(SC.Relationship.summary) == "function" then
        relationship = SC.Relationship.summary(actor, state, {
            health = medical.health,
            hunger = U().characterStatValue(actor, "HUNGER", 0),
            thirst = U().characterStatValue(actor, "THIRST", 0),
            woundCount = medical.woundCount,
            supplies = supplies,
            ammunition = supplies.ammunition,
            knox = knox,
            knoxInfected = medical.knoxInfected == true,
        }) or {}
    end
    local autonomy = {}
    if SC.Autonomy and type(SC.Autonomy.summary) == "function" then
        local ok, value = pcall(SC.Autonomy.summary, actor)
        if ok and type(value) == "table" then autonomy = value end
    end
    local vehicleStatus
    if SC.Vehicle and (type(SC.Vehicle.statusFor) == "function"
        or type(SC.Vehicle.manifestStatus) == "function") then
        local statusMethod = SC.Vehicle.statusFor or SC.Vehicle.manifestStatus
        local ok, value = pcall(statusMethod, actor, player)
        if ok and type(value) == "table" then vehicleStatus = value end
    end
    local scavengeStatus
    if SC.Encounter and type(SC.Encounter.status) == "function" then
        local ok, value = pcall(SC.Encounter.status, actor)
        if ok and type(value) == "table" then scavengeStatus = value end
    end
    local actionSummary
    if SC.ActionSupervisor and type(SC.ActionSupervisor.summary) == "function" then
        local ok, value = pcall(SC.ActionSupervisor.summary, actor)
        if ok and type(value) == "table" then actionSummary = value end
    end
    local nativeSeated = vehicleStatus and (vehicleStatus.status == "in_vehicle"
        or vehicleStatus.status == "waiting_safe_exit") or false
    local result = {
        id = companionId,
        name = U().nameOf(actor),
        actor = actor,
        health = medical.health,
        hunger = U().characterStatValue(actor, "HUNGER", 0),
        thirst = U().characterStatValue(actor, "THIRST", 0),
        distance = player and U().distance(actor, player) or math.huge,
        order = state.order,
        activity = actionSummary and actionSummary.active == true
            and actionSummary.action or currentActivity(actor, state),
        actionSummary = actionSummary,
        intent = currentIntent(actor),
        combatMode = state.combatMode,
        combatDoctrine = state.combatDoctrine,
        holdFire = state.holdFire,
        followDistance = state.followDistance,
        scavenge = state.scavenge,
        scavengeStatus = scavengeStatus,
        allowOverload = state.allowOverload,
        rideWithPlayer = state.rideWithPlayer,
        vehicleStatus = vehicleStatus,
        workMode = state.workMode,
        group = state.group,
        knox = knox,
        knoxInfected = medical.knoxInfected == true,
        status = status,
        alive = alive,
        -- Neutral encounters are still available for conversation/recruitment.
        -- Individual team commands apply their own recruited-only gate.
        available = alive and (U().squareOf(actor) ~= nil or nativeSeated),
        recruited = state.recruited,
        factionId = affiliation and affiliation.factionId or state.factionId,
        factionRole = affiliation and affiliation.role or state.factionRole,
        factionStanding = affiliation and affiliation.standing or nil,
        factionMember = affiliation ~= nil or state.factionId ~= nil,
        moveMode = state.moveMode,
        moveModeVersion = state.moveModeVersion,
        weaponPriority = state.weaponPriority,
        wounds = woundSummaries(medical.wounds),
        woundCount = medical.woundCount,
        supplies = supplies,
        ammunition = supplies.ammunition,
        loadWeight = load and load.weight or nil,
        loadCapacity = load and load.capacity or nil,
        loadRatio = load and load.ratio or nil,
        loadRole = load and load.role or nil,
        equippedWeapon = (function()
            local primary, primaryOk = U().call(actor, "getPrimaryHandItem")
            return primaryOk and primary and U().itemName(primary) or nil
        end)(),
        personality = state.personality,
        personalityProfile = stableSummaryCopy(state.personalityProfile,
            "$.commands.summary.personalityProfile"),
        profession = relationship.profession,
        aptitude = relationship.aptitude,
        backgroundLabel = relationship.backgroundLabel,
        trust = state.trust,
        bond = relationship.bond or state.bond,
        morale = relationship.morale or state.morale,
        stress = relationship.stress or state.stress,
        relationshipTier = relationship.relationshipTier or "cautious",
        mood = autonomy.grief and "grieving" or relationship.mood or "steady",
        currentNeed = relationship.currentNeed or "ready",
        recentMemory = relationship.recentMemory,
        stressResponse = autonomy.stressResponse,
        stressResponseLabel = autonomy.stressResponseLabel,
        joyResponse = autonomy.joyResponse,
        joyResponseLabel = autonomy.joyResponseLabel,
        boredom = autonomy.boredom,
        topThoughts = stableSummaryCopy(autonomy.topThoughts, "$.commands.summary.topThoughts"),
        currentExpectation = autonomy.currentExpectation,
        activeEpisode = autonomy.activeEpisode,
        inspiration = autonomy.inspiration,
        pendingRequest = stableSummaryCopy(autonomy.pendingRequest,
            "$.commands.summary.pendingRequest"),
        grief = stableSummaryCopy(autonomy.grief, "$.commands.summary.grief"),
        lossCount = tonumber(autonomy.lossCount) or 0,
        background = stableSummaryCopy(relationship.background or state.background,
            "$.commands.summary.background"),
        timeTogetherHours = relationship.timeTogetherHours or 0,
        -- Only a bounded count belongs in the roster summary: the full memories
        -- array is nested one level deeper than the summary's maxDepth and grows
        -- past its value budget, so copying it threw "stable value limit exceeded"
        -- on every UI refresh once a companion had ~13 memories (breaking that
        -- roster entry). No summary consumer read the array -- the memory view uses
        -- state.memories directly -- so expose just the count.
        memoryCount = type(state.memories) == "table" and #state.memories or 0,
        lastDowntime = stableSummaryCopy(state.lastDowntime,
            "$.commands.summary.lastDowntime"),
        objectives = nil,
        possessions = nil,
    }
    if SC.Journal and type(SC.Journal.build) == "function" then
        result.journal = SC.Journal.build(actor, state, result)
        result.objectives = stableSummaryCopy(result.journal.objective,
            "$.commands.summary.objectives")
        result.possessions = {
            keepsake = stableSummaryCopy(result.journal.keepsake,
                "$.commands.summary.possessions.keepsake"),
        }
    end
    return result
end

local conversationActions = {
    doing = true,
    status = true,
    needs = true,
    memory = true,
    background = true,
    opinion = true,
    relationship = true,
    encourage = true,
    praise = true,
    plans = true,
}

local recruitedConversationActions = {
    relationship = true,
    encourage = true,
    praise = true,
}

local function showConversation(actor, entry, state, id, action, player)
    if recruitedConversationActions[action] and not state.recruited then
        return false, "not_recruited"
    end
    if not SC.Relationship or type(SC.Relationship.respond) ~= "function" then
        return false, "relationship_unavailable"
    end
    local description = Commands.describe(id, player)
    local staged, copyReason = copyCommandState(state)
    if not staged then return false, "command_state_copy_failed:" .. tostring(copyReason) end
    local storageBefore = snapshotStorage(actor, entry)
    local ok, sentence, emote, changed, reason = pcall(
        SC.Relationship.respond, action, actor, player, staged, description)
    if not ok or type(sentence) ~= "string" or sentence == "" then
        restoreStorage(actor, entry, storageBefore)
        return false, ok and (reason or "conversation_rejected") or sentence
    end
    if changed == true then
        local persisted, persistenceReason = pcall(writeStable, actor, entry, staged)
        if not persisted then
            restoreStorage(actor, entry, storageBefore)
            return false, persistenceReason
        end
        states[actor] = staged
        state = staged
    end
    if action == "encourage" and changed == true and SC.LifeEvents
        and type(SC.LifeEvents.emit) == "function" then
        SC.LifeEvents.emit("encouraged", {
            sourceId = "player:local", participants = { U().idOf(actor) },
        })
    end
    if action == "encourage" and SC.Autonomy and type(SC.Autonomy.offerSupport) == "function" then
        pcall(SC.Autonomy.offerSupport, actor)
    end
    U().say(actor, sentence)
    local stagedConversation = false
    if SC.Positioning and type(SC.Positioning.beginConversation) == "function" then
        local called, accepted = pcall(SC.Positioning.beginConversation, actor, player, {
            action = action,
            emote = emote,
            stress = state.stress,
        })
        stagedConversation = called and accepted == true
    end
    if not stagedConversation and type(emote) == "string"
        and type(SC.Relationship.playEmote) == "function" then
        pcall(SC.Relationship.playEmote, actor, emote)
    end
    if action == "status" then
        if not callUI("showStatus", description) then callUI("open", "Overview", id, description) end
        return true, description
    end
    if action == "memory" then callUI("showMemory", id, state.memories) end
    return true, sentence
end

local function issueOne(companionId, command, payload, player)
    local actor, entry, reason = resolve(companionId)
    if not actor then return false, reason end
    if type(command) ~= "string" then return false, "invalid_command" end
    local state = stateFor(actor, entry)
    if state.factionId ~= nil or type(entry) == "table" and entry.factionId ~= nil then
        return false, "faction_members_use_faction_interactions"
    end
    if conversationActions[command] then
        return showConversation(actor, entry, state, companionId, command, player)
    end
    local handler = handlers[command]
    if not handler then return false, "unsupported_command" end
    if not state.recruited and command ~= "recruit" and command ~= "dismiss" then return false, "not_recruited" end
    local before, copyReason = copyCommandState(state)
    if not before then return false, "command_state_copy_failed:" .. tostring(copyReason) end
    local storageBefore = snapshotStorage(actor, entry)
    local ok, a, b, c = U().safeSubsystem("commands", actor, function()
        return handler(actor, entry, state, payload, player)
    end)
    if not ok or a ~= true then
        states[actor] = before
        restoreStorage(actor, entry, storageBefore)
        if not ok then return false, a end
        return false, b
    end
    return a, b, c
end

local function groupPayload(payload)
    if type(payload) ~= "table" then return payload end
    local copy = {}
    for key, value in pairs(payload) do
        if key ~= "scope" and key ~= "group" then copy[key] = value end
    end
    return copy
end

local groupableCommands = {
    follow = true,
    stay = true,
    guard = true,
    regroup = true,
    retreat = true,
    set_follow_distance = true,
    set_scavenge = true,
    set_allow_overload = true,
    set_ride_with_player = true,
    set_work_mode = true,
    set_move_mode = true,
    set_combat_mode = true,
    set_combat_doctrine = true,
    set_weapon_priority = true,
    set_hold_fire = true,
    hold_fire = true,
    fire_at_will = true,
}

local function validatePayload(command, payload)
    if not groupableCommands[command] then return false, "non_groupable" end
    if command == "set_follow_distance" then
        local value = type(payload) == "table" and payload.distance or payload
        if not followDistances[tonumber(value)] then return false, "invalid_follow_distance" end
    elseif command == "set_scavenge" or command == "set_allow_overload"
        or command == "set_ride_with_player" or command == "set_hold_fire" then
        local value = payload
        if type(payload) == "table" then value = payload.enabled end
        if type(value) ~= "boolean" then return false, "invalid_boolean" end
    elseif command == "set_move_mode" then
        local value = type(payload) == "table" and payload.mode or payload
        if not moveModes[value] then return false, "invalid_move_mode" end
    elseif command == "set_work_mode" then
        local value = type(payload) == "table" and payload.mode or payload
        if not workModes[value] then return false, "invalid_work_mode" end
    elseif command == "set_combat_mode" then
        local value = type(payload) == "table" and payload.mode or payload
        if not combatModes[value] then return false, "invalid_combat_mode" end
    elseif command == "set_combat_doctrine" then
        local value = type(payload) == "table"
            and (payload.doctrine or payload.mode) or payload
        if not combatDoctrines[value] then return false, "invalid_combat_doctrine" end
    elseif command == "set_weapon_priority" then
        local value = type(payload) == "table" and payload.priority or payload
        if not weaponPriorities[value] then return false, "invalid_weapon_priority" end
    elseif command == "set_base_role" then
        local value = type(payload) == "table" and payload.role or payload
        if not SC.BaseLife or not SC.BaseLife.ROLES[value] then
            return false, "invalid_base_role"
        end
    end
    return true
end

local function groupMembers(group)
    local members = {}
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = states[actor] or snapshotState(actor)
        if state.recruited and state.group == group then
            members[#members + 1] = { actor = actor, id = U().idOf(actor), state = state }
        end
    end
    table.sort(members, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return members
end

local function teamMembers()
    local members = {}
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = states[actor] or snapshotState(actor)
        if state.recruited then
            members[#members + 1] = { actor = actor, id = U().idOf(actor), state = state }
        end
    end
    table.sort(members, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return members
end

copyCommandState = function(state)
    local copy = U().copyShallow(state)
    if state.anchor then copy.anchor = U().copyShallow(state.anchor) end
    if state.tacticalTarget then copy.tacticalTarget = U().copyShallow(state.tacticalTarget) end
    if state.pendingInteraction then copy.pendingInteraction = U().copyShallow(state.pendingInteraction) end
    if state.workTarget then copy.workTarget = U().copyShallow(state.workTarget) end
    local fields = {
        { "personalityProfile", copyLimits.profile },
        { "memories", copyLimits.memories },
        { "background", copyLimits.background },
        { "care", copyLimits.care },
        { "reveals", copyLimits.reveals },
        { "objectives", copyLimits.objectives },
        { "possessions", copyLimits.possessions },
        { "lastDowntime", copyLimits.downtime },
    }
    for _, specification in ipairs(fields) do
        local key, limit = specification[1], specification[2]
        if state[key] ~= nil then
            local copied, reason = strictCopy(state[key], limit, "$.commands." .. key)
            if reason ~= nil then return nil, reason end
            copy[key] = copied
        end
    end
    return copy
end

local function issueMemberSetAtomic(members, command, payload, player)
    local cleanPayload = groupPayload(payload)
    local valid, validationReason = validatePayload(command, cleanPayload)
    if not valid then return false, validationReason, {} end
    if #members == 0 then return true, "issued", {} end

    -- Resolve and validate the complete target set before changing any member.
    local plans = {}
    for _, member in ipairs(members) do
        local actor, entry, reason = resolve(member.id)
        if not actor then return false, reason, {} end
        local current = states[actor] or stateFor(actor, entry)
        if not current.recruited then return false, "not_recruited", {} end
        local before, beforeReason = copyCommandState(current)
        if not before then
            return false, "group_prevalidation:command_state_copy_failed:"
                .. tostring(beforeReason), {}
        end
        local staged, stagedReason = copyCommandState(current)
        if not staged then
            return false, "group_prevalidation:command_state_copy_failed:"
                .. tostring(stagedReason), {}
        end
        plans[#plans + 1] = {
            actor = actor,
            id = member.id,
            entry = entry,
            before = before,
            storage = snapshotStorage(actor, entry),
            staged = staged,
        }
    end

    -- Apply every reversible order to detached state first. No persistence,
    -- navigation, actor action, or downtime cancellation occurs in this phase.
    local results = {}
    for _, plan in ipairs(plans) do
        groupStaging = true
        local ok, accepted, reason = pcall(
            handlers[command],
            plan.actor,
            plan.entry,
            plan.staged,
            cleanPayload,
            player
        )
        groupStaging = false
        if not ok or accepted ~= true then
            local failure = ok and reason or accepted
            results[#results + 1] = { id = plan.id, ok = false, reason = failure }
            return false, "group_prevalidation:" .. tostring(failure), results
        end
        results[#results + 1] = { id = plan.id, ok = true, reason = reason }
    end

    -- Persist the staged states. A failure restores every member's exact prior
    -- command state and stable storage, including the member that failed.
    for index, plan in ipairs(plans) do
        local persisted, persistenceError = pcall(writeStable, plan.actor, plan.entry, plan.staged)
        if not persisted then
            for _, rollback in ipairs(plans) do
                states[rollback.actor] = rollback.before
                restoreStorage(rollback.actor, rollback.entry, rollback.storage)
            end
            results[index].ok = false
            results[index].reason = persistenceError
            return false, "group_rollback:persistence_failed", results
        end
        states[plan.actor] = plan.staged
    end
    -- All members persisted; only now apply the cross-subsystem base-duty release.
    -- Doing it inside the commit loop above meant a later member's write failure
    -- rolled back command state and storage but left an earlier member's BaseLife
    -- resident duty cleared -- order=base_duty with resident duty=false (R2-04).
    if SC.BaseLife and type(SC.BaseLife.setDuty) == "function" then
        for _, plan in ipairs(plans) do
            if plan.before.order == "base_duty" and plan.staged.order ~= "base_duty" then
                pcall(SC.BaseLife.setDuty, plan.id, false)
            end
        end
    end
    if SC.Downtime and type(SC.Downtime.cancel) == "function" then
        for _, plan in ipairs(plans) do pcall(SC.Downtime.cancel, plan.actor, "command") end
    end
    if SC.Decision and type(SC.Decision.cancelWork) == "function" then
        for _, plan in ipairs(plans) do pcall(SC.Decision.cancelWork, plan.actor, "group_command") end
    end
    if command == "set_ride_with_player" and SC.Vehicle
        and type(SC.Vehicle.invalidateManifests) == "function" then
        SC.Vehicle.invalidateManifests()
    end
    return true, "issued", results
end

local function issueGroupAtomic(group, command, payload, player)
    if type(group) ~= "string" or group == "" then return false, "invalid_group", {} end
    local members = groupMembers(group)
    if #members == 0 then return false, "no_group_members", {} end
    return issueMemberSetAtomic(members, command, payload, player)
end

local function issueTeamDoctrine(payload, player)
    local cleanPayload = groupPayload(payload)
    local doctrine = type(cleanPayload) == "table"
        and (cleanPayload.doctrine or cleanPayload.mode) or cleanPayload
    if not combatDoctrines[doctrine] then return false, "invalid_combat_doctrine", {} end
    if type(rawModData(player)) ~= "table" then
        return false, "player_mod_data_unavailable", {}
    end
    local members = teamMembers()
    local accepted, reason, results = issueMemberSetAtomic(
        members, "set_combat_doctrine", cleanPayload, player)
    if not accepted then return false, reason, results end
    local stored, storeReason = storeTeamDoctrine(player, doctrine)
    if not stored then return false, storeReason, results end
    if SC.Combat and type(SC.Combat.equipPreferred) == "function" then
        local preferred = doctrine == "ranged_support" and "firearm"
            or doctrine == "stealth" and "quiet" or nil
        if preferred then
            for _, member in ipairs(members) do
                pcall(SC.Combat.equipPreferred, member.actor, preferred)
            end
        end
    end
    return true, doctrine, results
end

local function issueGroupVehicle(group, command, payload, player)
    if type(group) ~= "string" or group == "" then return false, "invalid_group", {} end
    if command ~= "board_vehicle" and command ~= "exit_vehicle" then
        return false, "unsupported_group_vehicle_command", {}
    end
    local cleanPayload = groupPayload(payload)
    local vehicle
    if type(cleanPayload) == "table" then vehicle = cleanPayload.vehicle else vehicle = cleanPayload end
    if command == "board_vehicle" and not vehicle and player then
        vehicle = select(1, U().call(player, "getVehicle"))
    end
    if command == "board_vehicle" and not vehicle then return false, "vehicle_unavailable", {} end
    local actorService = SC.Actor
    if type(actorService) ~= "table" or type(actorService.setMovement) ~= "function" then
        return false, "actor_executor_unavailable", {}
    end
    local members = groupMembers(group)
    if #members == 0 then return false, "no_group_members", {} end

    -- Fix and validate the complete member set before starting any native
    -- action. Vehicle entry/exit is not rollback-safe after an executor accepts
    -- it, so the result explicitly reports partial non-rollback completion.
    local plans = {}
    for _, member in ipairs(members) do
        local actor, entry, reason = resolve(member.id)
        if not actor then return false, reason, {} end
        local memberVehicle = vehicle
        if command == "exit_vehicle" then
            memberVehicle = select(1, U().call(actor, "getVehicle"))
            if not memberVehicle then return false, "member_not_in_vehicle:" .. tostring(member.id), {} end
        end
        plans[#plans + 1] = {
            actor = actor,
            entry = entry,
            id = member.id,
            vehicle = memberVehicle,
        }
    end

    local results = {}
    for index, plan in ipairs(plans) do
        local memberPayload = type(cleanPayload) == "table" and U().copyShallow(cleanPayload) or {}
        memberPayload.vehicle = plan.vehicle
        local accepted, reason = issueOne(plan.id, command, memberPayload, player)
        results[#results + 1] = {
            id = plan.id,
            ok = accepted == true,
            reason = reason,
            rollback = false,
        }
        if not accepted then
            return false, index > 1 and "group_partial_nonrollback" or "group_rejected", results
        end
    end
    return true, "issued_nonrollback", results
end

function Commands.issue(companionId, command, payload, player)
    if type(payload) == "table" and payload.scope == "team" then
        if command ~= "set_combat_doctrine" then
            return false, "unsupported_team_command", {}
        end
        return issueTeamDoctrine(payload, player)
    end
    if type(payload) == "table" and payload.scope == "group" then
        if command == "board_vehicle" or command == "exit_vehicle" then
            return issueGroupVehicle(payload.group, command, payload, player)
        end
        return issueGroupAtomic(payload.group, command, payload, player)
    end
    return issueOne(companionId, command, payload, player)
end

function Commands.teamCombatDoctrine(player)
    return teamDoctrineForPlayer(player)
end

function Commands.setTeamCombatDoctrine(player, doctrine)
    return issueTeamDoctrine({ doctrine = doctrine, scope = "team" }, player)
end

function Commands.conversation(companionId, action, player)
    if not conversationActions[action] and action ~= "recruit" and action ~= "dismiss" then
        return false, "unsupported_conversation"
    end
    return Commands.issue(companionId, action, nil, player)
end

function Commands.issueGroup(group, command, payload, player)
    return issueGroupAtomic(group, command, payload, player)
end

function Commands.whistle(player)
    if not player or U().isDead(player) then return false, "invalid_player" end
    local x, y, z = U().position(player)
    if type(addSound) == "function" then pcall(addSound, player, x, y, z, 24, 35) end
    if SC.Senses and type(SC.Senses.hear) == "function" then
        SC.Senses.hear(player, x, y, z, 24, 35, "whistle")
    end
    local results, count = {}, 0
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = states[actor] or snapshotState(actor)
        if state.recruited and (state.order == "follow" or state.order == "regroup") then
            local id = U().idOf(actor)
            local ok, reason = Commands.issue(id, "regroup", nil, player)
            results[#results + 1] = { id = id, ok = ok, reason = reason }
            if ok then count = count + 1 end
        end
    end
    return true, "whistle", count, results
end

local handSigns = {
    follow = { emote = "followme", command = "follow" },
    hold = { emote = "freeze", command = "stay" },
    regroup = { emote = "comehere", command = "regroup" },
    cautious = { emote = "followbehind", command = "cautious_follow" },
    move_out = { emote = "moveout", command = "follow" },
    cease_fire = { emote = "ceasefire", command = "hold_fire" },
    fire = { emote = "signalfire", command = "fire_at_will" },
    fall_back = { emote = "comefront", command = "retreat" },
}

function Commands.isHandSign(sign)
    return type(sign) == "string" and handSigns[sign] ~= nil
end

function Commands.handSign(player, sign)
    local specification = handSigns[sign]
    if not player or not specification or U().isDead(player) then return false, "invalid_signal" end
    local _, playerEmoteOk = U().call(player, "playEmote", specification.emote)
    if not playerEmoteOk then return false, "player_emote_unavailable" end
    local results, count = {}, 0
    for _, actor in ipairs(U().registryLiving(U().config("maxCompanions") or 16)) do
        local state = states[actor] or snapshotState(actor)
        if state.recruited and U().canSee(actor, player) then
            local id = U().idOf(actor)
            local ok, reason = Commands.issue(id, specification.command, nil, player)
            results[#results + 1] = { id = id, ok = ok, reason = reason }
            if ok then
                count = count + 1
                if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
                    pcall(SC.Relationship.playEmote, actor, "signalok")
                end
            end
        end
    end
    return true, sign, count, results
end

function Commands.peek(actor)
    if not actor then return nil end
    return states[actor] or stateFor(actor)
end

function Commands.persist(actor)
    if not actor then return false, "invalid_actor" end
    local state = states[actor] or stateFor(actor)
    local _, entry = U().resolveActor(U().idOf(actor))
    local storage = snapshotStorage(actor, entry)
    local ok, reason = pcall(writeStable, actor, entry, state)
    if not ok then restoreStorage(actor, entry, storage) end
    return ok == true, ok and "state_persisted" or reason
end

local function transitionFactionMembership(actor, specification, player)
    if actor == nil or type(specification) ~= "table" then
        return false, "invalid_faction_transition"
    end
    local id = U().idOf(actor)
    local resolved, entry, reason = resolve(id)
    if resolved == nil or resolved ~= actor then return false, reason or "unknown_companion" end
    local current = states[actor] or stateFor(actor, entry)
    if specification.expectedFactionId ~= nil
        and current.factionId ~= specification.expectedFactionId
        and (type(entry) ~= "table" or entry.factionId ~= specification.expectedFactionId) then
        return false, "faction_membership_changed"
    end
    if specification.expectedRecruited ~= nil
        and current.recruited ~= specification.expectedRecruited then
        return false, "recruitment_state_changed"
    end

    local before, beforeReason = copyCommandState(current)
    if not before then
        return false, "faction_transition_copy_failed:" .. tostring(beforeReason)
    end
    local storage = snapshotStorage(actor, entry)
    local staged, stagedReason = copyCommandState(current)
    if not staged then
        return false, "faction_transition_copy_failed:" .. tostring(stagedReason)
    end
    staged.recruited = specification.recruited == true
    staged.factionId = type(specification.factionId) == "string"
        and specification.factionId or nil
    staged.factionRole = type(specification.factionRole) == "string"
        and specification.factionRole or nil
    staged.order = specification.order or (staged.recruited and "follow" or "faction_duty")
    staged.anchor = nil
    staged.tacticalTarget = nil
    staged.pendingInteraction = nil
    staged.workTarget = nil
    staged.returnOrder = nil
    staged.returnWorkMode = nil
    if staged.recruited then
        staged.rideWithPlayer = true
        staged.workMode = workModes[staged.workMode] and staged.workMode or "auto"
        applyDoctrine(staged, teamDoctrineForPlayer(player))
    else
        staged.group = nil
        staged.scavenge = false
        staged.allowOverload = false
        staged.rideWithPlayer = false
        staged.workMode = "build"
        applyDoctrine(staged, "close_defense")
    end
    staged.commandSerial = (tonumber(staged.commandSerial) or 0) + 1
    staged.lastCommandAt = U().nowMs()

    local persisted, persistenceError = pcall(writeStable, actor, entry, staged)
    if not persisted then
        states[actor] = before
        restoreStorage(actor, entry, storage)
        return false, "faction_transition_rollback:" .. tostring(persistenceError)
    end
    states[actor] = staged
    if SC.BaseLife and type(SC.BaseLife.setDuty) == "function" then
        pcall(SC.BaseLife.setDuty, id, false)
    end
    if SC.Downtime and type(SC.Downtime.cancel) == "function" then
        pcall(SC.Downtime.cancel, actor, "faction_transition")
    end
    if SC.Decision and type(SC.Decision.cancelWork) == "function" then
        pcall(SC.Decision.cancelWork, actor, "faction_transition")
    end
    if SC.Vehicle and type(SC.Vehicle.invalidateManifests) == "function" then
        SC.Vehicle.invalidateManifests()
    end
    return true, staged
end

function Commands.beginFactionTrial(actor, origin, player)
    if type(origin) ~= "table" or type(origin.factionId) ~= "string"
        or type(origin.memberKey) ~= "string" then
        return false, "invalid_recruitment_origin"
    end
    local accepted, result = transitionFactionMembership(actor, {
        expectedFactionId = origin.factionId,
        expectedRecruited = false,
        recruited = true,
        factionId = nil,
        factionRole = nil,
        order = "follow",
    }, player)
    if not accepted then return false, result end
    if SC.Relationship and type(SC.Relationship.noteEvent) == "function" then
        SC.Relationship.noteEvent(result, "faction_trial_started", {
            trust = 2, bond = 1, morale = 1, counter = "factionTrialStarted",
        })
        Commands.persist(actor)
    end
    return true, "faction_trial_started"
end

function Commands.returnFactionTrial(actor, origin)
    if type(origin) ~= "table" or type(origin.factionId) ~= "string"
        or type(origin.factionRole) ~= "string" then
        return false, "invalid_recruitment_origin"
    end
    local accepted, result = transitionFactionMembership(actor, {
        expectedRecruited = true,
        recruited = false,
        factionId = origin.factionId,
        factionRole = origin.factionRole,
        order = "faction_duty",
    })
    if not accepted then return false, result end
    return true, "returned_to_household"
end

function Commands.completeFactionTrial(actor, origin, player)
    if type(origin) ~= "table" or type(origin.factionId) ~= "string" then
        return false, "invalid_recruitment_origin"
    end
    local accepted, result = transitionFactionMembership(actor, {
        expectedRecruited = true,
        recruited = true,
        factionId = nil,
        factionRole = nil,
        order = "follow",
    }, player)
    if not accepted then return false, result end
    if SC.Relationship and type(SC.Relationship.noteEvent) == "function" then
        SC.Relationship.noteEvent(result, "faction_recruited", {
            trust = 5, bond = 5, morale = 4, counter = "factionRecruitmentJoined",
        })
        Commands.persist(actor)
    end
    return true, "joined_permanently"
end

function Commands.noteDowntime(actor, fact)
    if not actor or type(fact) ~= "table" then return false end
    local state = stateFor(actor)
    state.lastDowntime = U().copyShallow(fact)
    if SC.Relationship and type(SC.Relationship.noteWork) == "function" then
        SC.Relationship.noteWork(state, fact)
    end
    if SC.Objectives and type(SC.Objectives.noteEvent) == "function" then
        SC.Objectives.noteEvent(state, "worked", fact)
    end
    local _, entry = U().resolveActor(U().idOf(actor))
    writeStable(actor, entry, state)
    return true
end

function Commands.observeRelationship(actor, player, snapshot)
    if not actor or not player or not SC.Relationship
        or type(SC.Relationship.observe) ~= "function" then return false end
    local state = stateFor(actor)
    local memoryBefore = type(state.memories) == "table" and #state.memories or 0
    local ok, relationshipChanged, reason = pcall(
        SC.Relationship.observe, actor, player, snapshot, state)
    local changed = ok and relationshipChanged == true
    if ok and relationshipChanged == true and SC.Objectives
        and type(SC.Objectives.noteEvent) == "function" then
        local memoryAfter = type(state.memories) == "table" and #state.memories or memoryBefore
        for index = memoryBefore + 1, memoryAfter do
            local memory = state.memories[index]
            if type(memory) == "table" then
                changed = SC.Objectives.noteEvent(state, memory.kind, memory) or changed
            end
        end
    end
    if SC.PersonalItems and type(SC.PersonalItems.observe) == "function" then
        local possessions, possessionChanged = SC.PersonalItems.observe(actor, state.possessions)
        state.possessions = possessions or state.possessions
        changed = possessionChanged == true or changed
    end
    if SC.Objectives and type(SC.Objectives.update) == "function" then
        changed = SC.Objectives.update(actor, state) or changed
    end
    if not changed then return false, ok and reason or relationshipChanged end
    local _, entry = U().resolveActor(U().idOf(actor))
    local persisted, persistenceReason = pcall(writeStable, actor, entry, state)
    return persisted == true, persisted and reason or persistenceReason
end

function Commands.export(actor)
    if not actor then return nil end
    local ok, state = pcall(function()
        return states[actor] or snapshotState(actor)
    end)
    if not ok then return nil, "command_export_copy_failed:" .. tostring(state) end
    local detached, copyReason = copyCommandState(state)
    if not detached then
        return nil, "command_export_copy_failed:" .. tostring(copyReason)
    end
    return {
        recruited = detached.recruited,
        factionId = detached.factionId,
        factionRole = detached.factionRole,
        order = detached.order,
        followDistance = detached.followDistance,
        scavenge = detached.scavenge,
        allowOverload = detached.allowOverload,
        rideWithPlayer = detached.rideWithPlayer,
        workMode = detached.workMode,
        workTarget = detached.workTarget,
        returnOrder = detached.returnOrder,
        returnWorkMode = detached.returnWorkMode,
        moveMode = detached.moveMode,
        moveModeVersion = detached.moveModeVersion,
        combatMode = detached.combatMode,
        combatDoctrine = detached.combatDoctrine,
        weaponPriority = detached.weaponPriority,
        holdFire = detached.holdFire,
        group = detached.group,
        personality = detached.personality,
        personalityProfile = detached.personalityProfile,
        trust = detached.trust,
        bond = detached.bond,
        morale = detached.morale,
        stress = detached.stress,
        memories = detached.memories,
        background = detached.background,
        care = detached.care,
        reveals = detached.reveals,
        timeTogetherMs = detached.timeTogetherMs,
        objectives = detached.objectives,
        possessions = detached.possessions,
        lastDowntime = detached.lastDowntime,
    }
end

function Commands.restore(actor, record)
    if not actor or type(record) ~= "table" then return false, "invalid_command_record" end
    local copied, state = pcall(snapshotState, actor, record)
    if not copied then
        return false, "command_restore_copy_failed:" .. tostring(state)
    end
    local initialized, reason = initializeCharacterState(actor, state)
    if not initialized then return false, reason end
    local previous = states[actor]
    local storage = snapshotStorage(actor, record)
    local persisted, persistenceReason = pcall(writeStable, actor, record, state)
    if not persisted then
        states[actor] = previous
        restoreStorage(actor, record, storage)
        return false, "command_restore_commit_failed:" .. tostring(persistenceReason)
    end
    states[actor] = state
    return true
end

function Commands.reset(actor)
    if actor then states[actor] = nil else states = setmetatable({}, { __mode = "k" }) end
    if SC.Relationship and type(SC.Relationship.reset) == "function" then
        SC.Relationship.reset(actor)
    end
    if SC.Objectives and type(SC.Objectives.reset) == "function" then
        SC.Objectives.reset(actor)
    end
    if SC.PersonalItems and type(SC.PersonalItems.reset) == "function" then
        SC.PersonalItems.reset(actor)
    end
end

return Commands
