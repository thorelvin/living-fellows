-- SPDX-License-Identifier: MIT
-- Native armor observations; damage and armor rolls remain with the game/mod.
local Armor = {}
local function holes(visual)
    local total = 0
    if not visual then return nil end
    for index = 0, BloodBodyPartType.ToIndex(BloodBodyPartType.MAX) - 1 do
        total = total + visual:getHole(BloodBodyPartType.FromIndex(index))
    end
    return total
end
function Armor.equip(actor)
    local item = actor:getInventory():AddItem("Base.Vest_BulletPolice")
    if not item then return nil, "native police vest unavailable" end
    actor:setWornItem(item:getBodyLocation(), item)
    if not actor:isEquippedClothing(item) then return nil, "native vest was not equipped" end
    return { actor = actor, item = item, id = item:getID(), visual = item:getVisual(),
        condition = item:getCondition(), lfBlocks = 0, lfWounds = 0, banditProtectedHits = 0, bandits = {} }
end
function Armor.lfSnapshot(armor)
    local item, actor = armor.item, armor.actor
    return { id = item:getID(), condition = item:getCondition(), holes = holes(item:getVisual()),
        same = item:getVisual() == armor.visual and item:getID() == armor.id
            and item:getContainer() == actor:getInventory() and actor:isEquippedClothing(item),
        defense = actor:getBodyPartClothingDefense(BodyPartType.ToIndex(BodyPartType.Torso_Upper), false, true) }
end
function Armor.banditSnapshot(actor)
    local visuals = actor:getItemVisuals()
    for index = 0, visuals:size() - 1 do
        local visual = visuals:get(index)
        local name = visual:getItemType()
        if type(name) == "string" and string.find(name, "Base.Vest_Bullet", 1, true) then
            return { visual = visual, name = name, holes = holes(visual),
                -- Stock Bandits uses native item visuals, not LF inventory
                -- objects. Preserve that model; never invent an item identity.
                physicalItem = visual:getInventoryItem(),
                defense = actor:getBodyPartClothingDefense(BodyPartType.ToIndex(BodyPartType.Torso_Upper), false, true) }
        end
    end
end
function Armor.prepareBandits(f)
    for actor in pairs(f.bandits) do
        local snapshot = Armor.banditSnapshot(actor)
        if not snapshot or snapshot.defense <= 0 then return false, "stock Bandit native armor not ready" end
        f.armor.bandits[actor] = snapshot
        print("SC_REAL_SANDBOX|ARMOR_BANDIT|type=" .. snapshot.name .. "|defense=" .. snapshot.defense
            .. "|holes=" .. snapshot.holes .. "|physical_item=" .. tostring(snapshot.physicalItem))
    end
    return true
end
function Armor.observeShot(f, before, after, requests, status, healthBefore, healthAfter)
    if not before or not after then return end
    if not before.same or not after.same or after.condition > before.condition then
        f.failure = "LF armor identity/condition changed outside native damage semantics"
        return
    end
    local matched = status.bulletHits > requests and status.lastVictim == "lf:" .. f.id and status.lastModel == "BulletHit"
    if matched and healthBefore and healthAfter then
        if healthAfter == healthBefore and before.holes and after.holes and after.holes > before.holes then
            f.armor.lfBlocks = f.armor.lfBlocks + 1
        elseif healthAfter < healthBefore then
            f.armor.lfWounds = f.armor.lfWounds + 1
        end
        print("SC_REAL_SANDBOX|ARMOR_LF_SHOT|item=" .. after.id .. "|same=" .. tostring(after.same)
            .. "|condition=" .. before.condition .. "->" .. after.condition
            .. "|holes=" .. before.holes .. "->" .. after.holes
            .. "|parts=" .. healthBefore .. "->" .. healthAfter .. "|blocks=" .. f.armor.lfBlocks)
    end
end
function Armor.observeHit(f, actor, bodyPart)
    local original = f.armor.bandits[actor]
    if not original then return end
    if actor:isDead() or actor:getHealth() <= 0 then return end
    local current = Armor.banditSnapshot(actor)
    if not current or current.visual ~= original.visual or current.name ~= original.name then
        f.failure = "stock Bandit armor visual identity changed during hit"
        return
    end
    if (bodyPart == BodyPartType.Torso_Upper or bodyPart == BodyPartType.Torso_Lower)
        and current.defense > 0 then f.armor.banditProtectedHits = f.armor.banditProtectedHits + 1 end
    print("SC_REAL_SANDBOX|ARMOR_BANDIT_HIT|type=" .. current.name .. "|same_visual=true|body=" .. tostring(bodyPart)
        .. "|defense=" .. current.defense .. "|holes=" .. original.holes .. "->" .. current.holes
        .. "|protected_hits=" .. f.armor.banditProtectedHits)
end
function Armor.accepted(f)
    local state = Armor.lfSnapshot(f.armor)
    return state.same and state.condition <= f.armor.condition and f.armor.lfBlocks > 0
        and f.armor.lfWounds > 0 and f.armor.banditProtectedHits > 0
end
function Armor.detail(f)
    return "; LF armor blocks=" .. f.armor.lfBlocks .. "; uncovered LF wounds=" .. f.armor.lfWounds
        .. "; native armored Bandit torso hits=" .. f.armor.banditProtectedHits
end
SCRealSandboxHarnessProbes.SCBanditsArmorEvidence = Armor
return Armor
