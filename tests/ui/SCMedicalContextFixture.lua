-- SPDX-License-Identifier: MIT
-- A native player's stock option may name its default display name "Bob".
-- The patient pointer, not the roster selection or that label, owns the check.
function require() return true end
MEDICAL_CONTEXT_TEST = { records = {}, checks = 0, opened = {}, originalCalls = {} }
local T = MEDICAL_CONTEXT_TEST
function T.check(value, message)
    T.checks = T.checks + 1
    assert(value, "medical context " .. T.checks .. ": " .. message)
end
function T.square(x, y, z)
    local square = { x = x, y = y, z = z or 0 }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    return square
end
function T.actor(id, name, x, y, companion)
    local actor = { id = id, name = name, square = T.square(x, y), companion = companion }
    function actor:getSquare() return self.square end
    function actor:getX() return self.square.x end
    function actor:getY() return self.square.y end
    function actor:getZ() return self.square.z end
    function actor:getDisplayName() return "Bob" end
    function actor:isDead() return false end
    function actor:getVehicle() return nil end
    function actor:setHaloNote(note) self.note = note end
    function actor:DistTo(other)
        return math.sqrt((self.square.x - other.square.x)^2 + (self.square.y - other.square.y)^2)
    end
    if companion then T.records[id] = { id = id, actor = actor, name = name, recruited = true } end
    return actor
end
T.doctor = T.actor("doctor", "Local survivor", 10, 10, false)
T.patient = T.actor("jill", "Jill Kelvin", 10, 11, true)
T.selected = T.actor("tess", "Tess Nolan", 13, 10, true)
T.human = T.actor("human", "Human player", 10, 11, false)
function getSpecificPlayer(index) return index == 0 and T.doctor or nil end
function getPlayer() return T.doctor end
function instanceof() return false end
function getText(key, argument, secondArgument)
    if key == "ContextMenu_Medical_Check" then return "Medical Check" end
    if key == "ContextMenu_GetCloser" then return tostring(argument) .. " needs to be closer." end
    if key == "UI_SC_Disabled_TooFar" then return "Move within " .. tostring(argument) .. " tiles to use this action." end
    if key == "UI_SC_MedicalCheck_TooFar" then return "Move within " .. tostring(secondArgument)
        .. " tiles of " .. tostring(argument) .. " for a medical check." end
    return key
end
Events = nil
ISToolTip = {}
function ISToolTip:new()
    return { initialise = function() end, setVisible = function(self, visible) self.visible = visible end }
end
function T.menu()
    local menu = { options = {}, additions = 0, player = 0,
        addGetUpOption = ISContextMenu.addGetUpOption, onGetUpAndThen = ISContextMenu.onGetUpAndThen }
    function menu:getOptionFromName(name)
        for _, option in ipairs(self.options) do if option.name == name then return option end end
    end
    function menu:addOption(name, target, callback, ...)
        self.additions = self.additions + 1
        local option = { name = name, target = target, onSelect = callback }
        local arguments = { ... }
        for index = 1, 10 do option["param" .. index] = arguments[index] end
        self.options[#self.options + 1] = option
        return option
    end
    return menu
end
local function originalMedical(worldObjects, requester, patient)
    T.originalCalls[#T.originalCalls + 1] = { worldObjects, requester, patient }
    return true, "vanilla_medical"
end
ISWorldObjectContextMenu = { onMedicalCheck = originalMedical }
ISInventoryPaneContextMenu = {}
-- Load installed ISContextMenu after this fixture; use its actual get-up wrapper
-- and only replace the timed-action effect with an observable completion seam.
ISPanel = {}
function ISPanel:derive(name) return { Type = name } end
ISWaitWhileGettingUp = {}
function ISWaitWhileGettingUp:new(character)
    local action = { character = character }
    function action:setOnComplete(callback, ...)
        self.callback, self.arguments = callback, { ... }
    end
    return action
end
ISTimedActionQueue = { add = function(action) T.getUpAction = action end }
function T.completeGetUp()
    local action = T.getUpAction
    T.getUpAction = nil
    return action.callback(unpack(action.arguments))
end
function T.vanillaOption(menu, worldObjects, patient, requester, wrapped)
    local option
    if wrapped then
        option = menu:addGetUpOption("Medical Check", worldObjects, originalMedical, requester or T.doctor, patient)
    else option = menu:addOption("Medical Check", worldObjects, originalMedical, requester or T.doctor, patient) end
    option.notAvailable = true
    option.toolTip = { description = getText("ContextMenu_GetCloser", patient:getDisplayName()) }
    return option
end
SurvivorCompanion = {
    Actor = { isCompanion = function(actor) return actor and actor.companion == true end },
    Registry = {
        idOf = function(actor) return actor.id end,
        byId = function(id) return T.records[id] end,
        -- Force the body-hit/floor-list gap: the companion remains registered,
        -- while the generic world-row picker produces no matching talk rows.
        living = function() return {} end,
    },
    GameplayUtil = { isZombie = function() return false end,
        instanceOf = function() return false end },
    UI = { text = getText, instance = { selectedId = T.selected.id },
        displayName = function(actor, fallback) return actor.name or fallback end,
        openHealth = function(patient, doctor)
            T.opened[#T.opened + 1] = { patient = patient, doctor = doctor }
            return true, "health_opened"
        end },
}
