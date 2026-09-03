-- SPDX-License-Identifier: MIT

local Bridge = SurvivorCompanion and SurvivorCompanion.UIBridge
assert(Bridge, "SCUIBridge must be loaded before this test")

local inventory = { marker = "companion-inventory" }
local square = { marker = "live-square" }
local actor = {}

function actor:getSquare()
    return square
end

function actor:isDead()
    return false
end

function actor:getInventory()
    return inventory
end

function actor:getModData()
    return { SC_Id = "sc-bridge-test" }
end

local invalidActor = {
    getSquare = actor.getSquare,
    isDead = actor.isDead,
    getInventory = actor.getInventory,
    getModData = actor.getModData,
}

SurvivorCompanion.Actor = {
    isCompanion = function(subject)
        return subject ~= invalidActor
    end,
}

local player = { distance = 3 }

function player:DistTo(subject)
    assert(subject ~= nil)
    return self.distance
end

function player:getPlayerNum()
    return 0
end

local lootPage = {
    inventoryPane = {},
    isCollapsed = true,
    visible = false,
    clearedMaximum = false,
    raised = false,
}

function lootPage:setNewContainer(container)
    self.inventoryPane.inventory = container
end

function lootPage:setVisible(visible)
    self.visible = visible
end

function lootPage:getIsVisible()
    return self.visible
end

function lootPage:clearMaxDrawHeight()
    self.clearedMaximum = true
end

function lootPage:bringToTop()
    self.raised = true
end

getPlayerLoot = function(playerNum)
    assert(playerNum == 0)
    return lootPage
end

local opened, reason = Bridge.openInventory(actor, player)
assert(opened == true and reason == nil)
assert(lootPage.inventoryPane.inventory == inventory)
assert(lootPage.visible == true)
assert(lootPage.isCollapsed == false)
assert(lootPage.clearedMaximum == true)
assert(lootPage.collapseCounter == -40)
assert(lootPage.raised == true)

-- Loot-pane restore transaction (review 1.4): borrowing the player's loot pane
-- for a companion inventory must be reversible.
-- Case 1: while we still own the pane it is put back to its prior state (the
-- fixture pane was hidden and collapsed before we borrowed it).
local restored, restoreReason = Bridge.restoreInventory()
assert(restored == true and restoreReason == "restored")
assert(lootPage.visible == false, "restore hides the pane it found hidden")
assert(lootPage.isCollapsed == true, "restore recollapses the pane it found collapsed")
local noop, noopReason = Bridge.restoreInventory()
assert(noop == true and noopReason == "not_owned", "a second restore is a no-op")

-- Case 2: the player selected another container after we opened the companion
-- inventory -> restore must leave their choice untouched.
lootPage.inventoryPane.inventory = nil
lootPage.visible = false
lootPage.isCollapsed = true
assert(Bridge.openInventory(actor, player) == true)
local playerContainer = { name = "player_selected" }
lootPage.inventoryPane.inventory = playerContainer
local kept, keptReason = Bridge.restoreInventory()
assert(kept == true and keptReason == "player_changed_container",
    "restore never clobbers a container the player selected afterwards")
assert(lootPage.inventoryPane.inventory == playerContainer, "the player's container is left intact")

player.distance = 5
local tooFar, tooFarReason, limit = Bridge.openInventory(actor, player)
assert(tooFar == false)
assert(tooFarReason == "UI_SC_Disabled_TooFar")
assert(limit == 4)
player.distance = 3

local noPlayer, noPlayerReason = Bridge.openInventory(actor, nil)
assert(noPlayer == false and noPlayerReason == "UI_SC_Disabled_NoPlayer")

local invalid, invalidReason = Bridge.openInventory(invalidActor, player)
assert(invalid == false and invalidReason == "UI_SC_Disabled_InvalidActor")

local actorWithoutInventory = {
    getSquare = actor.getSquare,
    isDead = actor.isDead,
    getModData = actor.getModData,
}
local missingInventory, missingInventoryReason = Bridge.openInventory(actorWithoutInventory, player)
assert(missingInventory == false and missingInventoryReason == "UI_SC_Disabled_NoInventory")

local requestedTab = nil
local requestedId = nil
local requestedDescription = nil
local function openHealth(tab, id, description)
    requestedTab = tab
    requestedId = id
    requestedDescription = description
    return {
        collapsed = false,
        selectedId = id,
        selectedRow = { actor = actor },
        detail = { tab = tab, displayedCompanionId = id },
        isVisible = function() return true end,
    }
end

local healthOpened, healthReason = Bridge.openHealth(actor, player, openHealth, function(subject, doctor)
    assert(subject == actor and doctor == player)
    return { name = "Mock Companion" }
end)
assert(healthOpened == true and healthReason == nil)
assert(requestedTab == "loadout")
assert(requestedId == "sc-bridge-test")
assert(requestedDescription.id == "sc-bridge-test")
assert(requestedDescription.actor == actor)

local noOpHealth, noOpReason = Bridge.openHealth(actor, player, function()
    return {
        collapsed = true,
        selectedId = "sc-bridge-test",
        detail = { tab = "loadout" },
        isVisible = function() return true end,
    }
end)
assert(noOpHealth == false and noOpReason == "UI_SC_Disabled_HealthUnavailable")
