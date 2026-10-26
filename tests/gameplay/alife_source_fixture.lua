-- SPDX-License-Identifier: MIT
-- Native boundaries only; the runner loads the unchanged original A-Life Lua.
local P = ProjectALife
P.Interop = nil
ALIFE_SOURCE_STORES = {}
ModData = { getOrCreate = function(key)
    ALIFE_SOURCE_STORES[key] = ALIFE_SOURCE_STORES[key] or {}
    return ALIFE_SOURCE_STORES[key]
end }
P.Catalog = {
    faction = function(id) return { id = id, factionId = id } end,
    npc = function() return { general = { awareness = 5 } } end,
}
P.RelationLayers = {
    forget = function() end,
    towardPlayer = function(faction) return faction.id end,
    towardFaction = function() return "neutral" end,
    professionOf = function() return nil end,
}
P.CustomProfiles = { newcomer = { awareness = 5 } }
P.SquadTactics = {}
P.Settings = { current = { npcDamagePercent = 72, extraWoundPercent = 0, bluntFracturePercent = 0 } }
P.DifficultyPreset = { damagePercent = function() return 72 end }
P.Weapons = { isAutomatic = function() return false end }
P.Animations = { current = {}, apply = function() return true end }
P.Endurance = { consumeAttack = function() end }
P.Voice = { play = function() end }
P.AudioPolicy = { playFrom = function() end, allowsNPC = function() return false end }
P.Speech = { combatBark = function() end }
P.NPCHitRelay = { ready = function() return true end, beginAttack = function() end, prepareAttack = function() end }
P.ShellSimulation = { standardHealth = function() return 100 end }
function getGameTime() return { getHour = function() return 12 end, getWorldAgeHours = function() return 24 end } end
function getOnlinePlayers() return { size = function() return #ALIFE_TEST_PLAYERS end, get = function(_, index) return ALIFE_TEST_PLAYERS[index + 1] end } end
ALIFE_SOURCE_SEED = 1
function ZombRand(low, high)
    if high == nil then high, low = low, 0 end
    ALIFE_SOURCE_SEED = (ALIFE_SOURCE_SEED * 16807) % 2147483647
    return low + math.floor(ALIFE_SOURCE_SEED / 2147483647 * (high - low))
end
BodyPartType = { FromIndex = function(index) return index end, ToIndex = function(index) return index end, Torso_Upper = 6 }
function ALIFE_SOURCE_BODY(actor, armor)
    local body = { owner = actor, parts = {}, hits = 0, clothingHoles = 0 }
    for index = 0, 16 do
        local part = { health = 100, cut = false, deep = false, scratched = false, bullet = false }
        function part:getHealth() return self.health end
        function part:SetHealth(value) self.health = value end
        function part:ReduceHealth(value) self.health = self.health - value end
        function part:AddDamage(value) self:ReduceHealth(value) end
        function part:isCut() return self.cut end
        function part:isDeepWounded() return self.deep end
        function part:setCut(value) self.cut = value end
        function part:setDeepWounded(value) self.deep = value end
        function part:setCutTime() end
        function part:setDeepWoundTime() end
        function part:setBleeding(value) self.bleeding = value end
        function part:setScratched(value) self.scratched = value end
        function part:setHaveBullet(value) self.bullet = value end
        body.parts[index] = part
    end
    function body:getParentChar() return self.owner end
    function body:getBodyPart(index) return self.parts[index] end
    function body:DamageFromWeapon(weapon, index)
        if ALIFE_SOURCE_BEFORE_NATIVE then ALIFE_SOURCE_BEFORE_NATIVE(self.owner) end
        index = tonumber(index)
        if index == nil or index < 0 then index = ZombRand(17) end
        self.hits = self.hits + 1
        local part = self.parts[index]
        local blocked = (armor or 0) > ZombRand(100)
        self.clothingHoles = self.clothingHoles + (blocked and 0 or 1)
        if not blocked then
            part:ReduceHealth(weapon.damage * (0.75 + ZombRand(100) / 100))
            part.cut, part.deep, part.bleeding = true, true, true
            part.bullet = weapon.ranged == true
        end
    end
    function body:AddDamage(index, value)
        self.fallbacks = (self.fallbacks or 0) + 1
        self.parts[index]:ReduceHealth(value)
    end
    actor.body = body
    return body
end
function ALIFE_SOURCE_WEAPON(ranged)
    local weapon = { ranged = ranged, damage = 12, ammo = 100 }
    function weapon:isRanged() return self.ranged end
    function weapon:isAimedFirearm() return self.ranged end
    function weapon:getFullType() return self.ranged and "Base.Pistol" or "Base.Crowbar" end
    function weapon:getMinDamage() return 1 end
    function weapon:getMaxDamage() return 2 end
    function weapon:getType() return self.ranged and "Pistol" or "Crowbar" end
    function weapon:getCategories() return {} end
    function weapon:getSwingAnim() return "Bat" end
    function weapon:isTwoHandWeapon() return false end
    function weapon:getSoundRadius() return 20 end
    function weapon:getZombieHitSound() return "Hit" end
    return weapon
end
