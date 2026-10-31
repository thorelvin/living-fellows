-- SPDX-License-Identifier: MIT
-- Uses the gameplay world's inventory, command, logistics and combat services.
function SC_WEAPON_SELECTION_REGRESSIONS(f)
    local SC, checks, actors = SurvivorCompanion, 0, {}
    local function check(ok, message)
        checks = checks + 1
        f.check(ok, "weapon selection: " .. message)
    end
    local function fighter(items)
        local value = f.actor("sc-weapon-selection-" .. tostring(#actors + 1), -12, 14, {
            inventory = f.inventory(items),
        })
        actors[#actors + 1] = value
        f.registry[value.id] = value
        return value
    end
    local function choose(value, preference, distance, pressure)
        return SC.Combat.preferredWeapon(value, preference or "best", distance or 4, pressure or 0)
    end
    local function refresh(value)
        SC.InventoryIndex.release(value)
        SC.Combat.reset(value)
        SC.Logistics.reset(value)
    end
    local function weaponLimits(audit, target, keep)
        -- Role profiles are shared configuration, never mutate them in a test.
        local profile = {}
        for key, value in pairs(audit.profile) do profile[key] = value end
        profile.target, profile.keep = {}, {}
        for key, value in pairs(audit.profile.target) do profile.target[key] = value end
        for key, value in pairs(audit.profile.keep) do profile.keep[key] = value end
        profile.target.weapon, profile.keep.weapon = target, keep
        audit.profile = profile
    end
    do
        -- Build 42's getAmmoType is an object whose tostring is base:bullets_38;
        -- only its item key matches the rounds in a bag.
        local revolver = f.item("Base.TestRevolver", "Weapon", {
            ranged = true, damage = 3, range = 10, maxAmmo = 6, ammoType = "Base.TestRounds",
        })
        local value = fighter({ revolver })
        check(tostring(revolver:getAmmoType()) ~= "Base.TestRounds", "the fixture's ammo type is not an item name")
        check(not SC.Combat.weaponOperational(value, revolver), "an empty revolver with no rounds is unusable")
        local round = f.item("Base.TestRounds", "Item")
        value.inventory:AddItem(round)
        refresh(value)
        check(SC.Combat.weaponOperational(value, revolver), "an empty revolver reloads from loose rounds")
        value.primary = revolver
        local accepted, reason = SC.Combat.maintainFirearm(value, revolver)
        check(accepted == true and reason ~= "no_usable_firearm", "the reload is actually requested")
        value.inventory:Remove(round)
        refresh(value)
        check(not SC.Combat.weaponOperational(value, revolver), "using the last round makes it unusable again")
        local rejected, why = SC.Combat.maintainFirearm(value, revolver)
        check(rejected == false and why == "no_usable_firearm", "no rounds means no reload attempt")
    end
    do
        local rifle = f.item("Base.TestRifle", "Weapon", {
            ranged = true, damage = 5, range = 16, maxAmmo = 20,
            magazineType = "Base.TestClip", ammoType = "Base.TestRounds",
        })
        local blade = f.item("Base.HuntingKnife", "Weapon", { damage = 1.4 })
        local rounds = f.item("Base.TestRounds", "Item")
        local value = fighter({ rifle, blade, rounds })
        value.primary = rifle
        check(not SC.Combat.weaponOperational(value, rifle), "loose rounds without a magazine cannot reload a magazine-fed gun")
        check(choose(value, "firearm") == blade, "an unusable preferred gun gives way to a working melee weapon")
        local clip = f.item("Base.TestClip", "Item", { ammo = 0, maxAmmo = 20 })
        value.inventory:AddItem(clip)
        refresh(value)
        check(SC.Combat.weaponOperational(value, rifle), "an actual empty magazine and compatible rounds permit reloading")
        check(choose(value, "firearm", 10) == rifle, "a reloadable preferred firearm can be prepared at a safe distance")
        check(choose(value, "firearm", 1.2) == blade, "a ready melee weapon wins over reloading at contact range")
        check(choose(value, "firearm", 4, 3) == blade, "nearby crowd pressure also prevents choosing a reload over a ready melee weapon")
        local pistol = f.item("Base.Pistol", "Weapon", { ranged = true, damage = 1, range = 8, ammo = 3, maxAmmo = 15 })
        value.inventory:AddItem(pistol)
        refresh(value)
        check(choose(value, "firearm", 4) == pistol, "a ready pistol in range wins over a stronger rifle needing a reload")
        check(choose(value, "firearm", 12) == rifle, "a short-range pistol does not prevent preparing the rifle beyond pistol range")
        value.inventory:Remove(clip)
        refresh(value)
        function rifle:isContainsClip() return true end
        check(SC.Combat.weaponOperational(value, rifle), "an installed magazine can be replenished from loose rounds")
        value.inventory:Remove(rounds)
        check(not SC.Combat.weaponOperational(value, rifle), "an installed empty magazine alone is not usable ammunition")
        rifle.jammed = true
        check(not SC.Combat.weaponOperational(value, rifle), "a jam does not make an empty gun operational")
        value.inventory:Remove(pistol)
        refresh(value)
        check(choose(value, "firearm") == blade, "an empty jammed gun never suppresses the usable backup")
        rifle.ammo = 1
        check(SC.Combat.weaponOperational(value, rifle), "a loaded jammed gun remains recoverable")
        check(choose(value, "firearm", 1) == blade, "unjamming is deferred in favour of a ready close-range weapon")
    end
    do
        local rifle = f.item("Base.TestRifle", "Weapon", {
            ranged = true, maxAmmo = 20, magazineType = "Base.TestClip", ammoType = "Base.TestRounds",
        })
        local foreignClip = f.item("OtherMod.TestClip", "Item", { ammo = 8, maxAmmo = 20 })
        local foreignRounds = f.item("OtherMod.TestRounds", "Item")
        -- Reproduce the native short getType() while retaining distinct modules.
        function foreignClip:getType() return "TestClip" end
        function foreignRounds:getType() return "TestRounds" end
        local value = fighter({ rifle, foreignClip, foreignRounds })
        check(not SC.Combat.weaponOperational(value, rifle), "matching short names from another module cannot supply a qualified gun")
        local clip = f.item("Base.TestClip", "Item", { ammo = 0, maxAmmo = 20 })
        value.inventory:AddItem(clip)
        refresh(value)
        check(not SC.Combat.weaponOperational(value, rifle), "a matching empty magazine cannot use another module's rounds")
        rifle.magazineType, rifle.ammoType = "TestClip", "TestRounds"
        check(SC.Combat.weaponOperational(value, rifle), "unqualified script types retain legacy short-name matching")
        rifle.magazineType, rifle.ammoType = "Base.TestClip", "Base.TestRounds"
        clip.ammo = 3
        check(SC.Combat.weaponOperational(value, rifle), "an exact compatible loaded magazine works without loose ammunition")
        -- Leave a stale index entry and even a stale native container pointer.
        for index, candidate in ipairs(value.inventory.items) do
            if candidate == clip then table.remove(value.inventory.items, index) break end
        end
        check(not SC.Combat.weaponOperational(value, rifle), "a stale magazine reference cannot lend ammunition after removal")
    end
    do
        local pistol = f.item("Base.Pistol", "Weapon", { ranged = true, ammo = 0, maxAmmo = 15 })
        function pistol:haveChamber() return true end
        function pistol:isRoundChambered() return self.chambered == true end
        local value = fighter({ pistol })
        pistol.chambered = true
        check(SC.Combat.weaponOperational(value, pistol), "the final chambered round is usable even when magazine ammo is zero")
        check(choose(value, "firearm") == pistol, "the final chambered round participates in selection")
        pistol.chambered, pistol.ammo = false, 2
        local accepted = SC.Combat.maintainFirearm(value, pistol)
        check(accepted and value.lastIntent and value.lastIntent.action == "unjam", "magazine rounds with an empty chamber dispatch the native rack action")
        pistol.ammo = 0
        accepted = SC.Combat.maintainFirearm(value, pistol)
        check(not accepted, "maintenance refuses a dry gun without reload supplies")
    end
    do
        local broken = f.item("Base.BrokenAxe", "Weapon", { condition = 0, damage = 100 })
        local inert = f.item("Base.InertWeapon", "Weapon", { damage = 0 })
        local worn = f.item("Base.WornAxe", "Weapon", { condition = 1, conditionMax = 10, damage = 2.5 })
        local sound = f.item("Base.SoundAxe", "Weapon", { damage = 1.9 })
        local invalid = f.item("Base.InvalidWeapon", "Weapon", { damage = 0 / 0 })
        local value = fighter({ broken, inert, worn, sound, invalid })
        check(not SC.Combat.weaponOperational(value, broken), "broken weapons are excluded")
        check(not SC.Combat.weaponOperational(value, inert), "objects with no damage are excluded")
        check(choose(value, "melee") == sound, "a sound comparable weapon beats a nearly broken high-damage alternative")
        value.primary = broken
        check(not SC.Combat.primaryWeaponUsable(value), "a broken equipped weapon cannot block readiness")
        value.inventory:Remove(sound)
        value.primary = sound
        refresh(value)
        check(not SC.Combat.primaryWeaponUsable(value) and choose(value, "melee") ~= sound,
            "a hand pointer is not proof that the actor still owns the weapon")
    end
    do
        local heavy = f.item("Base.HeavyClub", "Weapon", { damage = 2.4, weight = 5, weaponCategories = { "Blunt" } })
        local light = f.item("Base.LightClub", "Weapon", { damage = 1.8, weight = 0.6, weaponCategories = { "Blunt" } })
        local value = fighter({ heavy, light })
        check(choose(value, "melee") == heavy, "a rested companion can prefer a stronger heavy weapon")
        value.endurance, value.fatigue = 0.1, 0.95
        check(choose(value, "melee") == light, "an exhausted companion chooses a useful lighter weapon")
        local axe = f.item("Base.Axe", "Weapon", { damage = 1.8, weight = 0.6, weaponCategories = { "Axe" } })
        value.inventory:Remove(heavy)
        value.inventory:AddItem(axe)
        value.endurance, value.fatigue, value.perks = 1, 0, { Axe = 8, Blunt = 0 }
        refresh(value)
        check(choose(value, "melee") == axe, "relevant weapon skill breaks a comparison between similar weapons")
    end
    do
        local spade = f.item("Base.Shovel", "Weapon", { damage = 1.1, tags = { DIG_GRAVE = true } })
        local axe = f.item("Base.Axe", "Weapon", { damage = 2 })
        local value = fighter({ spade, axe })
        check(SC.Combat.equipExactWeapon(value, spade), "an explicit exact equip is accepted")
        check(choose(value, "melee") == spade, "an explicit usable tool choice is preserved")
        check(SC.Commands.issue(value.id, "set_combat_doctrine", { doctrine = "weapons_free" }, f.player), "combat doctrine command is accepted")
        check(choose(value, "melee") == spade, "changing doctrine preserves the player's exact equipment choice")
        check(SC.Commands.issue(value.id, "set_weapon_priority", { priority = "melee" }, f.player), "a fresh weapon priority command is accepted")
        check(value.primary == axe and spade:getModData().SC_ManualEquipFor == nil,
            "changing weapon priority clears the old exact pin and equips the preferred weapon")
        local outsider = f.item("Base.ForeignPin", "Weapon", { damage = 0.5 })
        value.inventory:AddItem(outsider)
        outsider:getModData().SC_ManualEquipFor = "another-companion"
        SC.Combat.clearManualWeapon(value)
        check(outsider:getModData().SC_ManualEquipFor == "another-companion", "clearing manual choice leaves another actor's mark alone")
    end
    do
        local fillers = {}
        for index = 1, 245 do fillers[#fillers + 1] = f.item("Base.Filler" .. index, "Item", { weight = 0.001 }) end
        local axe = f.item("Base.Axe", "Weapon", { damage = 2 })
        fillers[#fillers + 1] = axe
        local value = fighter(fillers)
        value.primary = axe
        axe:getModData().SC_ManualEquipFor = value.id
        SC.Combat.clearManualWeapon(value)
        check(axe:getModData().SC_ManualEquipFor == nil, "the current primary's manual pin clears even beyond the bounded inventory scan")
        local upgrade = f.item("Base.NewAxe", "Weapon", { damage = 3 })
        value.inventory:AddItem(upgrade)
        value.primary = upgrade
        axe:getModData().SC_ManualEquipFor = value.id
        axe:getModData().SC_ManualEquipSerial = value.modData.SC_ManualWeaponSerial
        SC.Combat.clearManualWeapon(value)
        check(axe:getModData().SC_ManualEquipFor == value.id, "the inventory budget does not expand to find an off-scan old pin")
        value.inventory.items = { axe, upgrade }
        refresh(value)
        check(choose(value, "melee") == upgrade, "an off-scan pin stays invalid after it becomes visible to the scanner again")
        SC.Combat.reset(value)
        SC.Commands.reset(value)
        check(choose(value, "melee") == upgrade, "manual generation invalidation survives runtime state reconstruction")
    end
    do
        local members, pins, upgrades = {}, {}, {}
        for index = 1, 2 do
            pins[index] = f.item("Base.Shovel", "Weapon", { damage = 0.5, tags = { DIG_GRAVE = true } })
            upgrades[index] = f.item("Base.Axe", "Weapon", { damage = 2 })
            members[index] = fighter({ pins[index], upgrades[index] })
            members[index].modData.SC_Group = "weapon-tests"
            check(SC.Commands.issue(members[index].id, "stay", nil, f.player), "group member's persisted command state is initialized")
            check(SC.Combat.equipExactWeapon(members[index], pins[index]), "group member's manual choice is established")
        end
        local oldLiving = SC.GameplayUtil.registryLiving
        SC.GameplayUtil.registryLiving = function() return members end
        members[2].modDataProxy = setmetatable({}, {
            __index = function(_, key) return members[2].modData[key] end,
            __newindex = function() error("injected group weapon commit failure") end,
        })
        local accepted = SC.Commands.issueGroup("weapon-tests", "set_weapon_priority", { priority = "melee" }, f.player)
        members[2].modDataProxy = nil
        SC.GameplayUtil.registryLiving = oldLiving
        check(not accepted and members[1].primary == pins[1] and members[2].primary == pins[2]
            and pins[1]:getModData().SC_ManualEquipFor == members[1].id
            and pins[2]:getModData().SC_ManualEquipFor == members[2].id,
            "a failed group commit changes no weapons or manual pins")
        SC.GameplayUtil.registryLiving = function() return members end
        accepted = SC.Commands.issueGroup("weapon-tests", "set_weapon_priority", { priority = "melee" }, f.player)
        SC.GameplayUtil.registryLiving = oldLiving
        check(accepted and members[1].primary == upgrades[1] and members[2].primary == upgrades[2]
            and pins[1]:getModData().SC_ManualEquipFor == nil and pins[2]:getModData().SC_ManualEquipFor == nil,
            "a successful group priority command clears both old pins and equips both upgrades")
    end
    do
        local pistol = f.item("Base.Pistol", "Weapon", { ranged = true, ammo = 5, maxAmmo = 15, range = 8 })
        local knife = f.item("Base.HuntingKnife", "Weapon", { damage = 1.5 })
        local value = fighter({ pistol, knife })
        value.primary = pistol
        local target = f.zombie(-8, 14, { target = value })
        local snapshot = { threats = { { actor = target, visible = true, distanceSq = 16 } },
            threatCount = 1, immediateCount = 0, pressure = 0, escapeSquares = {}, allies = {},
            player = { actor = f.player, danger = 0 }, time = getTimestampMs(), reflexTime = getTimestampMs() }
        local runtime = { snapshot = snapshot }
        SC.Combat.update(value, f.player, runtime)
        local state = SC.Combat.peek(value)
        check(state and state.weaponCache and state.weaponCache.item == pistol, "a ready firearm populates the tactical weapon cache")
        local misses = state.weaponCacheMisses
        SC.Combat.update(value, f.player, runtime)
        check((state.weaponCacheHits or 0) > 0 and state.weaponCacheMisses == misses,
            "an unchanged healthy firearm reuses its cached choice")
        pistol.condition = 5
        SC.Combat.update(value, f.player, runtime)
        check(state.weaponCacheMisses > misses, "live wear invalidates the cached weapon choice")
        misses = state.weaponCacheMisses
        value.endurance = 0.1
        SC.Combat.update(value, f.player, runtime)
        check(state.weaponCacheMisses > misses, "a stamina-band change invalidates the tactical choice")
        pistol.ammo = 0
        SC.Combat.update(value, f.player, runtime)
        check(state.weaponCache.item == knife, "an emptied gun falls back even before the inventory cache expires")
        target.dead = true
    end
    do
        local knife = f.item("Base.HuntingKnife", "Weapon", { damage = 0.5 })
        local axe = f.item("Base.Axe", "Weapon", { damage = 2 })
        local value = fighter({ knife, axe })
        value.primary, value.modData.SC_Order, value.modData.SC_WeaponPriority = knife, "follow", "melee"
        local audit = SC.Logistics.status(value)
        check(audit.weaponReady == true, "a follower notices a substantially better carried weapon before combat")
        refresh(value)
        value.modData.SC_Order = "base_duty"
        audit = SC.Logistics.status(value)
        check(audit.weaponReady ~= true and value.primary == knife, "base workers' usable work tools are not replaced by an idle upgrade")
        value.modData.SC_Order = "follow"
        refresh(value)
        local oldCurrent = SC.ActionSupervisor.current
        SC.ActionSupervisor.current = function(subject)
            if subject == value then return { owner = "protected-test-work" } end
            return oldCurrent(subject)
        end
        audit = SC.Logistics.status(value)
        SC.ActionSupervisor.current = oldCurrent
        check(audit.weaponReady ~= true, "a usable hand weapon does not interrupt an active supervised action just to upgrade")
    end
    do
        local broken = f.item("Base.BrokenAxe", "Weapon", { condition = 0, weight = 4 })
        local empty = f.item("Base.TestPistol", "Weapon", { ranged = true, maxAmmo = 15 })
        local axe = f.item("Base.Axe", "Weapon", { damage = 2, weight = 2 })
        local value = fighter({ broken, empty })
        local audit = SC.Logistics.audit(value)
        weaponLimits(audit, 2, 1)
        check(SC.Logistics.canTake(value, axe, "weapon", audit), "raw inventory counts do not block acquiring the first usable weapon")
        check(not SC.Logistics.canTake(value, empty, "weapon", audit), "ordinary opportunistic loot excludes an unusable gun")
        check(SC.Logistics.canTake(value, empty, "weapon", audit, "weapon"), "an explicit expedition weapons request can still collect an unloaded gun")
        value.inventory:AddItem(axe)
        refresh(value)
        audit = SC.Logistics.audit(value)
        weaponLimits(audit, 1, 1)
        local surplus = SC.Logistics.selectSurplus(value, audit)
        check(surplus and surplus.item ~= axe, "surplus selection preserves the only operational weapon ahead of inert extras")
    end
    for _, value in ipairs(actors) do
        SC.Commands.reset(value)
        SC.Combat.reset(value)
        SC.Logistics.reset(value)
        SC.ActionSupervisor.reset(value)
        f.registry[value.id] = nil
        for index = #value.square.moving, 1, -1 do
            if value.square.moving[index] == value then table.remove(value.square.moving, index) end
        end
    end
    print("WEAPON_SELECTION_PASS checks=" .. tostring(checks))
    SC_WEAPON_SELECTION_CHECKS = checks
end
