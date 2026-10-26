-- SPDX-License-Identifier: MIT
local Armor = SCRealSandboxHarnessProbes.SCBanditsArmorEvidence
local checks, hole, condition, id, equipped = 0, 0, 10, 42, true
local function expect(value, why)
    checks = checks + 1
    assert(value, "armor evidence " .. checks .. ": " .. why)
end
BloodBodyPartType = { MAX = 3, ToIndex = function(value) return value end, FromIndex = function(value) return value end }
BodyPartType = { Torso_Upper = 6, Torso_Lower = 7, Head = 0, ToIndex = function(value) return value end }
local inventory, visual, item, actor = {}, {}, {}, {}
visual.getHole = function(_, part) return part == 1 and hole or 0 end
item.getID = function() return id end
item.getCondition = function() return condition end
item.getVisual = function() return visual end
item.getContainer = function() return inventory end
actor.getInventory = function() return inventory end
actor.isEquippedClothing = function() return equipped end
actor.getBodyPartClothingDefense = function() return 100 end
local function fixture()
    hole, condition, id, equipped = 0, 10, 42, true
    return { id = "sc-armor", armor = { actor = actor, item = item, id = 42, visual = visual, condition = 10,
        lfBlocks = 0, lfWounds = 0, banditProtectedHits = 0, bandits = {} } }
end
local status = { bulletHits = 1, lastVictim = "lf:sc-armor", lastModel = "BulletHit" }
local f = fixture()
local before = Armor.lfSnapshot(f.armor)
hole, condition = 1, 7
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.armor.lfBlocks == 1 and not f.failure, "native hole/condition change with unchanged health proves armor deflection")
expect(not Armor.accepted(f), "LF armor alone cannot satisfy both sides of rendered armor acceptance")
before = Armor.lfSnapshot(f.armor)
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1690)
expect(f.armor.lfWounds == 1, "an actual native wound remains distinct from armor deflection")
f.armor.banditProtectedHits = 1
expect(Armor.accepted(f), "both sides and native uncovered damage with stable identity can pass")
id = 43
expect(not Armor.accepted(f), "replacement item identity cannot pass")
f = fixture()
before = Armor.lfSnapshot(f.armor)
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.armor.lfBlocks == 0, "a routed request without a new clothing hole is insufficient")
hole = 1
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 1, status, 1700, 1700)
expect(f.armor.lfBlocks == 0, "stale native request counts cannot prove a block")
status.lastVictim = "lf:other"
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.armor.lfBlocks == 0, "another victim's request cannot prove LF armor")
status.lastVictim = "lf:sc-armor"
status.lastModel = "MeleeHit"
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.armor.lfBlocks == 0, "another damage model cannot prove firearm armor")
status.lastModel = "BulletHit"
id = 99
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.failure ~= nil, "changed native item identity fails the scene")
f = fixture()
before = Armor.lfSnapshot(f.armor)
condition = 11
Armor.observeShot(f, before, Armor.lfSnapshot(f.armor), 0, status, 1700, 1700)
expect(f.failure ~= nil, "unexplained condition repair fails the recorder")
local banditVisual = { getItemType = function() return "Base.Vest_BulletDesert" end,
    getHole = function() return 0 end, getInventoryItem = function() return nil end }
local visuals = { size = function() return 1 end, get = function() return banditVisual end }
local bandit = { getItemVisuals = function() return visuals end, getBodyPartClothingDefense = function() return 100 end,
    isDead = function() return false end, getHealth = function() return 1 end }
f = fixture()
f.bandits = { [bandit] = true }
expect(Armor.prepareBandits(f), "stock native visual armor is retained without inventing an inventory item")
Armor.observeHit(f, bandit, BodyPartType.Head)
expect(f.armor.banditProtectedHits == 0, "uncovered Bandit body part cannot prove torso armor")
Armor.observeHit(f, bandit, BodyPartType.Torso_Upper)
expect(f.armor.banditProtectedHits == 1 and not f.failure, "native armored torso impact retains the original visual")
bandit.isDead = function() return true end
visuals.size = function() return 0 end
Armor.observeHit(f, bandit, BodyPartType.Torso_Upper)
expect(not f.failure and f.armor.banditProtectedHits == 1, "native death can transfer visuals to the corpse without false live evidence")
print("BANDITS_ARMOR_EVIDENCE_PASS checks=" .. checks)
