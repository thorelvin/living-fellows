-- SPDX-License-Identifier: MIT
-- Native-shaped controls for executing the installed dependency's original
-- functions. No third-party source or saved world data is copied here.
function getWorld() return { getGameMode = function() return "Sandbox" end } end
IsoPlayer = { getPlayers = function() return BANDITS_TEST_REAL_LIST end }
function instanceof(actor, kind)
    return actor ~= nil and (kind == "IsoPlayer" and actor.bandit ~= true
        or kind == "IsoZombie" and actor.bandit == true)
end
function GetBanditModDataPlayers() return { OnlinePlayers = {} } end
function getSpecificPlayer(index) if index == 0 then return BANDITS_TEST_PLAYER end end
Events = setmetatable({}, { __index = function(t, key)
    local event = { Add = function() end, Remove = function() end }
    t[key] = event
    return event
end })
BodyPartType, BloodBodyPartType = {}, {}
local names = { "Foot_R", "Foot_L", "LowerLeg_R", "LowerLeg_L", "UpperLeg_R", "UpperLeg_L",
    "Groin", "Neck", "Head", "Torso_Lower", "Torso_Upper", "UpperArm_R", "UpperArm_L",
    "ForeArm_R", "ForeArm_L", "Hand_R", "Hand_L" }
for index, name in ipairs(names) do
    BodyPartType[name] = { index = index - 1 }
    BloodBodyPartType[name] = BodyPartType[name]
end
function BodyPartType.ToIndex(part) return part.index end
function BloodBodyPartType.FromIndex(index) return index end
CharacterStat = {}
BanditCompatibility = { Splash = function() end, PlayerVoiceSound = function() end }
function ZombRand() return 0 end
function ZombRandFloat(a, b) return (a + b) / 2 end
function BANDITS_SOURCE_BODY(actor)
    local parts = ArrayList.new()
    for _, name in ipairs(names) do
        local kind = BodyPartType[name]
        local part = { kind = kind }
        function part:getType() return self.kind end
        function part:setScratched(value) self.scratched = value end
        function part:setCut(value) self.cut = value end
        function part:generateDeepWound() self.deepWound = true end
        function part:setHaveBullet(value) self.bullet = value end
        parts:add(part)
    end
    local body = { health = 100, parts = parts }
    function body:getOverallBodyHealth() return self.health end
    function body:ReduceGeneralHealth(value) self.health = self.health - value end
    function body:getBodyParts() return self.parts end
    function body:getBodyPart(kind) return self.parts:get(kind.index) end
    function actor:getBodyDamage() return body end
    function actor:getStats() return {} end
    function actor:getBodyPartClothingDefense() return self.armour or 0 end
    function actor:addBlood() self.blood = true end
    function actor:addHole() self.holes = (self.holes or 0) + 1 end
    function actor:isRunning() return false end
    function actor:isSprinting() return false end
    return body
end
