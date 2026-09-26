-- SPDX-License-Identifier: MIT
-- A survivor who owns a flashlight and walks into a dark house in the dark.
--
-- Companions carried torches and never used them. Nothing in the mod looked at
-- how much light there was, so a companion cleared a basement at three in the
-- morning by feel, with two working flashlights and four spare batteries in
-- its bag. When a torch did run flat there was nothing to notice it, either.
--
-- This module is the whole of that behaviour and it is deliberately small:
--
--   darkness   -- how dark it is here, from the weather and the clock
--   light      -- the best torch this survivor is carrying
--   battery    -- a spare, and the verified swap that uses one
--   observe    -- the upkeep pass, run beside whatever else it is doing
--
-- Carrying a light is not an activity. A companion can walk, fight and loot
-- with a torch in its off hand, so this runs in the observation phase of every
-- decision round rather than competing for the one behaviour slot. It never
-- moves the actor, never touches the primary hand, and never changes what is
-- in a hand while an exclusive action owns the actor -- so it cannot take a
-- weapon out of a companion's hand mid-swing or unpick another action's own
-- hand bookkeeping.
--
-- Turning a light on and off is free and always allowed. Changing what is in a
-- hand is not, and is gated on the supervisor being idle.
local SC = SurvivorCompanion
SC.Lighting = SC.Lighting or {}
local Lighting = SC.Lighting

Lighting.VERSION = 1

local function U() return SC.GameplayUtil end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function config(key, fallback)
    local utility = U()
    if utility == nil or type(utility.config) ~= "function" then return fallback end
    return finite(utility.config(key), fallback)
end

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

-- ------------------------------------------------------------------ darkness

-- Daylight from the climate model rather than the clock alone, because a
-- thunderstorm at two in the afternoon is darker than a clear evening and the
-- game already knows that. The clock is the fallback for when it does not.
local function ambientDarkness()
    local utility = U()
    if type(getClimateManager) == "function" then
        local ok, climate = pcall(getClimateManager)
        if ok and climate ~= nil then
            local daylight, called = utility.call(climate, "getDayLightStrength")
            daylight = called and finite(daylight, nil) or nil
            if daylight ~= nil then return clamp01(1 - clamp01(daylight)), "daylight" end
            local night
            night, called = utility.call(climate, "getNightStrength")
            night = called and finite(night, nil) or nil
            if night ~= nil then return clamp01(night), "night_strength" end
        end
    end
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local hour, called = utility.call(gameTime, "getTimeOfDay")
            hour = called and finite(hour, nil) or nil
            if hour ~= nil then
                hour = hour % 24
                local dusk = config("lightingDuskHour", 19)
                local dawn = config("lightingDawnHour", 6)
                if hour >= dusk or hour < dawn then return 1, "clock_night" end
                -- The hour either side of the boundary is the awkward one.
                if hour >= dusk - 1 or hour < dawn + 1 then return 0.55, "clock_twilight" end
                return 0, "clock_day"
            end
        end
    end
    return 0, "unknown"
end

-- How dark it is where this companion is standing. Indoors counts for a lot:
-- an unlit interior room is night at any hour, which is why a companion
-- searching a windowless back room at noon still wants a torch.
function Lighting.darkness(actor)
    local utility = U()
    local value, source = ambientDarkness()
    local square = utility.squareOf(actor)
    if square ~= nil then
        -- Somewhere already lit -- a powered base, a lit room, standing inside
        -- the player's own torch beam -- needs no second torch.
        local level, levelOk = utility.call(square, "getLightLevel", 0)
        level = levelOk and finite(level, nil) or nil
        if level ~= nil and level >= config("lightingAmbientLitLevel", 0.55) then
            return 0, source .. "+already_lit"
        end
        local outside, outsideOk = utility.call(square, "isOutside")
        if outsideOk and outside == false then
            value = clamp01(value + config("lightingIndoorDarkness", 0.35))
            source = source .. "+indoor"
            -- A measured light level is evidence of darkness in its own right,
            -- not only of brightness. It was used to veto a torch and never to
            -- call for one, so the daylight outside decided an interior: at
            -- noon a windowless room came to 0.35 against a 0.62 threshold and
            -- a companion stood in the dark with a working flashlight. Trusted
            -- indoors only, where the reading is what the companion can
            -- actually see by; outdoors a stale or uncomputed zero would light
            -- torches in broad daylight.
            if level ~= nil and level < config("lightingIndoorDarkLevel", 0.35) then
                value = math.max(value, config("lightingIndoorDarkFloor", 0.7))
                source = source .. "+measured_dark"
            end
        end
    end
    return value, source
end

-- ------------------------------------------------------------- light sources

-- A light is something the game will actually light up: it has to emit and it
-- has to have a switch. Candles and lit lanterns are deliberately excluded --
-- they are their own item pair with their own recipes, and a companion
-- fumbling one is a fire.
function Lighting.isLight(item)
    if item == nil then return false end
    local utility = U()
    local strength, strengthOk = utility.call(item, "getLightStrength")
    if not strengthOk or (finite(strength, 0) or 0) <= 0 then return false end
    local switchable, switchOk = utility.call(item, "canBeActivated")
    if not switchOk or switchable ~= true then return false end
    return true
end

-- Has power now. canEmitLight is the engine's own answer and accounts for a
-- drained battery, so a flat torch is never chosen over a working one.
function Lighting.hasCharge(item)
    if item == nil then return false end
    local utility = U()
    local emits, ok = utility.call(item, "canEmitLight")
    if ok then return emits == true end
    -- No engine answer: fall back to the drainable's own uses.
    local empty, emptyOk = utility.call(item, "isEmptyUses")
    if emptyOk then return empty ~= true end
    return true
end

function Lighting.isActive(item)
    if item == nil then return false end
    local active, ok = U().call(item, "isActivated")
    return ok and active == true
end

-- Every torch this survivor is carrying, brightest working one first, and the
-- flat ones after them so a battery swap still has something to swap into.
function Lighting.lightSources(actor)
    local utility = U()
    local inventory = utility.inventory(actor)
    if inventory == nil then return {} end
    local budget = math.floor(config("lightingInventoryBudget", 120))
    local found = {}
    for _, item in ipairs(utility.inventoryItemsDeep(inventory, budget, 8)) do
        if Lighting.isLight(item) then
            found[#found + 1] = {
                item = item,
                charged = Lighting.hasCharge(item),
                strength = finite(select(1, utility.call(item, "getLightStrength")), 0),
                name = lower(utility.itemType(item)),
            }
        end
    end
    table.sort(found, function(left, right)
        if left.charged ~= right.charged then return left.charged end
        if left.strength ~= right.strength then return left.strength > right.strength end
        return left.name < right.name
    end)
    return found
end

-- ----------------------------------------------------------------- batteries

function Lighting.isBattery(item)
    if item == nil then return false end
    local itemType = lower(U().itemType(item))
    if itemType == "" then return false end
    -- A car battery is thirty kilos and belongs in a vehicle.
    if string.find(itemType, "carbattery", 1, true) ~= nil then return false end
    return string.find(itemType, "battery", 1, true) ~= nil
end

-- A spare with something left in it. Prefers the emptiest usable one, because
-- vanilla copies the battery's charge into the torch and a half-dead cell is
-- better spent than kept.
function Lighting.spareBattery(actor)
    local utility = U()
    local inventory = utility.inventory(actor)
    if inventory == nil then return nil end
    local budget = math.floor(config("lightingInventoryBudget", 120))
    local best, bestCharge = nil, nil
    for _, item in ipairs(utility.inventoryItemsDeep(inventory, budget, 8)) do
        if Lighting.isBattery(item) then
            local empty, emptyOk = utility.call(item, "isEmptyUses")
            if not emptyOk or empty ~= true then
                local charge = finite(select(1, utility.call(item, "getCurrentUsesFloat")), 1)
                if best == nil or charge < bestCharge then best, bestCharge = item, charge end
            end
        end
    end
    return best
end

-- Which container actually holds this item. A spare found by the deep scan
-- may be loose or in a bag, and only its own container can give it up.
function Lighting.containerOf(actor, item)
    local utility = U()
    local container, ok = utility.call(item, "getContainer")
    if ok and container ~= nil then return container end
    return utility.inventory(actor)
end

-- Put a fresh cell in a flat torch.
--
-- Vanilla does this as a crafting recipe whose code copies the battery's
-- charge into the torch and destroys the battery. A companion cannot run the
-- player's crafting UI, so the same two effects are applied directly -- and,
-- as everywhere else here that mutates inventory, the effect is verified
-- before the item is spent and rolled back if the engine did not take it. A
-- swap that silently ate a battery and left the torch flat would be worse than
-- no swap at all.
function Lighting.swapBattery(actor, torch)
    local utility = U()
    if torch == nil then return false, "no_torch" end
    if Lighting.hasCharge(torch) then return false, "torch_not_empty" end
    local battery = Lighting.spareBattery(actor)
    if battery == nil then return false, "no_spare_battery" end
    -- The cell that gets spent has to be the cell that gets removed, and a
    -- spare found by the deep scan may be sitting in a rucksack rather than
    -- loose. Removing it from the root inventory instead is not an error the
    -- engine reports: the call succeeds, nothing is taken out of the bag, and
    -- "is it still in the root inventory" answers no because it never was.
    -- The torch would charge and the battery would survive, over and over.
    local owner = Lighting.containerOf(actor, battery)
    if owner == nil then return false, "battery_owner_unknown" end
    if utility.containerContainsIdentity(owner, battery) ~= true then
        return false, "battery_not_held"
    end

    local before = finite(select(1, utility.call(torch, "getCurrentUsesFloat")), 0)
    local _, copied = utility.call(torch, "setCurrentUsesFrom", battery)
    if not copied then return false, "native_charge_transfer_unavailable" end
    if not Lighting.hasCharge(torch) then
        utility.call(torch, "setCurrentUsesFloat", before)
        return false, "native_charge_transfer_unverified"
    end

    -- Only now is the cell spent. A battery is a drainable, so Use() would
    -- take one tick's worth off it rather than consuming the cell -- it has to
    -- be removed outright, exactly as the recipe's destroy mode does, and out
    -- of the container that actually holds it.
    utility.call(owner, "Remove", battery)
    if utility.containerContainsIdentity(owner, battery) ~= false then
        utility.call(torch, "setCurrentUsesFloat", before)
        return false, "battery_not_consumed"
    end
    utility.diagnostic("lighting", actor,
        "action=battery_swap torch=" .. tostring(utility.itemType(torch)))
    return true, "battery_swapped"
end

-- --------------------------------------------------------- hands and switch

local function busy(actor)
    local supervisor = SC.ActionSupervisor
    if type(supervisor) ~= "table" or type(supervisor.current) ~= "function" then
        return false
    end
    local ok, record = pcall(supervisor.current, actor)
    return ok and record ~= nil
end

function Lighting.equipped(actor, item)
    if item == nil then return false end
    local utility = U()
    if select(1, utility.call(actor, "getPrimaryHandItem")) == item then return true end
    return select(1, utility.call(actor, "getSecondaryHandItem")) == item
end

-- The off hand only. A torch never displaces a weapon, and a companion holding
-- something in both hands keeps hold of it -- which is exactly what the player
-- has to do.
function Lighting.equipLight(actor, torch)
    local utility = U()
    if torch == nil then return false, "no_torch" end
    if Lighting.equipped(actor, torch) then return true, "already_equipped" end
    local primary, primaryOk = utility.call(actor, "getPrimaryHandItem")
    if primaryOk and primary ~= nil then
        local twoHanded, twoHandedOk = utility.call(primary, "isTwoHandWeapon")
        if twoHandedOk and twoHanded == true then return false, "hands_full" end
    end
    local previous, previousOk = utility.call(actor, "getSecondaryHandItem")
    if previousOk and previous ~= nil then return false, "off_hand_occupied" end
    local _, assigned = utility.call(actor, "setSecondaryHandItem", torch)
    if not assigned then return false, "native_equip_unavailable" end
    local verified, verifiedOk = utility.call(actor, "getSecondaryHandItem")
    if not verifiedOk or verified ~= torch then
        if previousOk then utility.call(actor, "setSecondaryHandItem", previous) end
        return false, "native_equip_unverified"
    end
    return true, "equipped"
end

function Lighting.stowLight(actor, torch)
    local utility = U()
    if torch == nil then return false, "no_torch" end
    Lighting.setActive(actor, torch, false)
    local secondary, secondaryOk = utility.call(actor, "getSecondaryHandItem")
    if not secondaryOk or secondary ~= torch then return true, "not_in_off_hand" end
    utility.call(actor, "setSecondaryHandItem", nil)
    if select(1, utility.call(actor, "getSecondaryHandItem")) == torch then
        return false, "native_unequip_unverified"
    end
    return true, "stowed"
end

-- The switch. Free, instant, and the one part of this that is safe to do at
-- any time -- including while an exclusive action owns the actor, because it
-- changes nothing that action is holding.
function Lighting.setActive(actor, item, wanted)
    local utility = U()
    if item == nil then return false, "no_light" end
    wanted = wanted == true
    if Lighting.isActive(item) == wanted then return true, "unchanged" end
    local _, switched = utility.call(item, "setActivated", wanted)
    if not switched then return false, "native_switch_unavailable" end
    if Lighting.isActive(item) ~= wanted then return false, "native_switch_unverified" end
    -- Vanilla pairs the switch with its sound and, in a networked game, a sync
    -- call. Both are best-effort: a missing global must not fail the switch.
    if type(syncItemActivated) == "function" then pcall(syncItemActivated, actor, item) end
    utility.call(item, "playActivateDeactivateSound")
    return true, wanted and "lit" or "doused"
end

-- -------------------------------------------------------------------- upkeep

-- Two thresholds, not one. A single boundary makes a companion flick its torch
-- on and off through the whole of dusk, and every flick is a sound.
function Lighting.wantsLight(actor, lit)
    local darkness = Lighting.darkness(actor)
    if lit == true then return darkness > config("lightingDouseDarkness", 0.45) end
    return darkness >= config("lightingLightDarkness", 0.62)
end

-- The light currently in a hand, if any.
function Lighting.heldLight(actor)
    local utility = U()
    local secondary = select(1, utility.call(actor, "getSecondaryHandItem"))
    if Lighting.isLight(secondary) then return secondary end
    local primary = select(1, utility.call(actor, "getPrimaryHandItem"))
    if Lighting.isLight(primary) then return primary end
    return nil
end

function Lighting.observe(actor, player, runtime, snapshot, commands, now)
    local utility = U()
    if utility == nil or not utility.isValidActor(actor) then return false, "invalid_actor" end
    now = finite(now, nil) or utility.nowMs()
    if not utility.isDue(actor, "lighting", config("lightingIntervalMs", 3000), now) then
        return false, "not_due"
    end

    local held = Lighting.heldLight(actor)
    if not Lighting.wantsLight(actor, held ~= nil and Lighting.isActive(held)) then
        if held == nil then return false, "no_light_needed" end
        if Lighting.isActive(held) then
            Lighting.setActive(actor, held, false)
            utility.diagnostic("lighting", actor, "action=douse reason=light_enough")
        end
        -- Leave a doused torch in the off hand while an action owns the actor;
        -- putting it away is a hand change like any other.
        if not busy(actor) then Lighting.stowLight(actor, held) end
        return true, "doused"
    end

    if held ~= nil then
        if not Lighting.hasCharge(held) and not Lighting.swapBattery(actor, held) then
            -- Nothing to put in it. Look for another torch that still works
            -- before giving up on the dark.
            if not busy(actor) then Lighting.stowLight(actor, held) end
            held = nil
        end
        if held ~= nil then
            if Lighting.isActive(held) then return true, "already_lit" end
            local lit = Lighting.setActive(actor, held, true)
            return lit == true, lit and "lit" or "switch_failed"
        end
    end

    if busy(actor) then return false, "actor_busy" end
    for _, record in ipairs(Lighting.lightSources(actor)) do
        local torch = record.item
        if not Lighting.hasCharge(torch) then Lighting.swapBattery(actor, torch) end
        if Lighting.hasCharge(torch) then
            local equipped, equipReason = Lighting.equipLight(actor, torch)
            if equipped then
                if Lighting.setActive(actor, torch, true) then
                    utility.diagnostic("lighting", actor,
                        "action=light torch=" .. tostring(utility.itemType(torch)))
                    return true, "lit"
                end
                Lighting.stowLight(actor, torch)
            elseif equipReason == "hands_full" or equipReason == "off_hand_occupied" then
                return false, equipReason
            end
        end
    end
    return false, "no_working_light"
end
