-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
local originalSelect = ISInventoryPage.selectContainer
local originalSetNew = ISInventoryPage.setNewContainer

SC.Runtime.start()
-- The same mod id can be installed twice at once -- a local build and a
-- Workshop staging copy -- and a playtest log that does not name the build it
-- came from cannot be read against the right source.
do
    local banner
    for _, entry in ipairs(SC.Diagnostics.reports) do
        if entry.subsystem == "runtime" and entry.message == "started" then banner = entry end
    end
    check(banner ~= nil and type(banner.detail) == "string"
            and string.find(banner.detail,
                "release=" .. tostring(SC.Identity.release), 1, true) ~= nil
            and string.find(banner.detail,
                "protocol=" .. tostring(SC.Identity.bridgeProtocol), 1, true) ~= nil
            and string.find(banner.detail, "schema-" .. tostring(SC.Identity.saveSchema),
                1, true) ~= nil,
        "a started runtime does not say which build it is: "
            .. tostring(banner and banner.detail))
end
local disposalsAfterFirstStart = SC.Actor.disposeCalls
local generationAfterFirstStart = SC.State.generation
SC.Runtime.start()
check(SC.Actor.disposeCalls == disposalsAfterFirstStart
        and SC.Persistence.restoreCalls == 1
        and SC.State.generation == generationAfterFirstStart
        and SC.FactionContracts.removeCalls == 0
        and SC.FactionContracts.resetCalls == 0,
    "repeated same-world start preserves actors and performs no second initialization")
check(SC.Runtime.reset(true) == true,
    "explicit world boundary resets an idempotently started runtime")
SC_TEST_CLOCK = 32001
isClient = function() return true end
SC.Runtime.start()
isClient = function() return false end
local ownSelect = ISInventoryPage.selectContainer
local ownSetNew = ISInventoryPage.setNewContainer
local state = SC.Runtime.containerHookState()
check(state.selectInstalled and state.setNewInstalled,
    "runtime owns both inventory-page wrappers after start")
local fixturePlayer = getPlayer()
check(fixturePlayer.haloNotes == 2
    and string.find(fixturePlayer.haloMessages[1], "TRANSLATED PROVIDER NOTICE", 1, true) ~= nil
    and fixturePlayer.haloMessages[2] == "TRANSLATED MULTIPLAYER NOTICE",
    "provider and multiplayer failures emit translated rate-limited in-game notices")

local page = { onCharacter = false, inventoryPane = {} }
local container = {}
check(ownSelect(page, { inventory = container }) == "selected" and SC.Encounter.opened == 1,
    "select wrapper preserves the original result and emits the narrow signal")
check(ownSetNew(page, container) == "changed" and SC.Encounter.opened == 2,
    "set-new wrapper preserves the original result and emits the narrow signal")

local newerSelect = function(self, button)
    self.newerWrapperCalled = true
    return ownSelect(self, button)
end
ISInventoryPage.selectContainer = newerSelect
local disposalsBeforeReset = SC.Actor.disposeCalls
local blockedReset, blockedReason = SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(blockedReset == false
        and string.find(tostring(blockedReason), "wrapper chain changed", 1, true) ~= nil
        and SC.Actor.disposeCalls == disposalsBeforeReset,
    "foreign wrapper ownership blocks teardown before native or Lua state changes")
check(ISInventoryPage.selectContainer == newerSelect and state.selectDeferred,
    "reset never clobbers a wrapper installed later by another mod")
check(ISInventoryPage.setNewContainer == ownSetNew and state.setNewInstalled,
    "teardown preflight leaves every owned wrapper installed on chain conflict")

ISInventoryPage.selectContainer = ownSelect
disposalsBeforeReset = SC.Actor.disposeCalls
SC.Runtime.reset(true)
state = SC.Runtime.containerHookState()
check(SC.Actor.disposeCalls == disposalsBeforeReset + 1,
    "cleanup retry disposes native actors after wrapper ownership is restored")
check(ISInventoryPage.selectContainer == originalSelect and not state.selectInstalled
    and not state.selectDeferred,
    "deferred removal completes after the newer owner releases the method chain")

SC.Runtime.start()
local generationBeforeFailure = SC.State.generation
local registryResetsBeforeFailure = SC.Registry.resetCalls
local actorResetsBeforeFailure = SC.Actor.resetCalls
local persistenceResetsBeforeFailure = SC.Persistence.resetCalls
SC.Actor.disposeResult = false
local failedReset, failedReason = SC.Runtime.reset(true)
check(failedReset == false
    and string.find(tostring(failedReason), "injected native cleanup failure", 1, true) ~= nil,
    "unverified native teardown fails the reset transaction")
check(SC.State.generation == generationBeforeFailure
    and SC.Registry.resetCalls == registryResetsBeforeFailure
    and SC.Actor.resetCalls == actorResetsBeforeFailure
    and SC.Persistence.resetCalls == persistenceResetsBeforeFailure,
    "failed native teardown preserves registry, actor, persistence, and generation state")
check(SC.State.active == false
    and string.find(tostring(SC.State.disabledReason), "native companion teardown", 1, true) ~= nil,
    "failed native teardown disables runtime with an actionable reason")
SC.Actor.disposeResult = true
check(SC.Runtime.reset(true) == true
    and SC.Registry.resetCalls == registryResetsBeforeFailure + 1
    and SC.Actor.resetCalls == actorResetsBeforeFailure + 1,
    "verified cleanup retry allows the reset transaction to commit")

-- Vararg/return safety (review 1.3): the wrappers must forward every argument and
-- preserve every return value, so a Build update or another mod that adds
-- parameters or returns multiple values is never silently corrupted.
ISInventoryPage.selectContainer = function(self, a, b, c)
    self.echoArgs = { a, b, c }
    return "r1", "r2", nil, 4
end
SC.Runtime.start()
local varargWrapper = ISInventoryPage.selectContainer
local echoPage = { onCharacter = true, inventoryPane = {} }
local r1, r2, r3, r4 = varargWrapper(echoPage, "A", "B", "C")
check(echoPage.echoArgs ~= nil and echoPage.echoArgs[1] == "A"
        and echoPage.echoArgs[2] == "B" and echoPage.echoArgs[3] == "C",
    "wrapper forwards every extra argument to the original method")
check(r1 == "r1" and r2 == "r2" and r3 == nil and r4 == 4,
    "wrapper preserves every return value, including a nil among trailing values")
SC.Runtime.reset(true)

-- A companion's inventory has to survive the loot pane rebuilding its own
-- container list. That rebuild happens every time the player turns or steps
-- onto a new square, and it only lists containers it can find in the world --
-- so the companion was absent every time, `found` came out false, and the
-- pane fell back to backpacks[1], the floor. Opening a companion's inventory
-- and moving the mouse closed it; dragging an item over it, which turns the
-- player, dropped the item on the ground.
;(function()
    SC.Runtime.start()
    check(SC_RUNTIME_FIXTURE.refreshCount() == 1,
        "a started runtime owns exactly one inventory-refresh handler")

    local companionInventory = { items = {} }
    local otherInventory = { items = {} }
    local companion = {}
    function companion:getDescriptor()
        return { getForename = function() return "Sam" end,
                 getSurname = function() return "Vance" end }
    end
    local borrowedFor = nil
    local savedBridge = SC.UIBridge
    local savedGetTexture = getTexture
    local backpackIcon = {}
    getTexture = function(key)
        check(key == "Item_Backpack_Black", "companion uses the stock backpack icon")
        return backpackIcon
    end
    SC.UIBridge = {
        borrowedInventory = function(page)
            if borrowedFor ~= nil and page ~= borrowedFor then return nil end
            return companionInventory, companion
        end,
        -- SCUIBridge is not loaded in this harness; what matters here is that
        -- whatever it names the container is what the button is called.
        borrowedInventoryLabel = function(actor)
            return actor == companion and "Sam Vance" or "wrong actor"
        end,
    }

    local function lootPage()
        local page = { onCharacter = false, backpacks = { { inventory = otherInventory } } }
        function page:addContainerButton(inventory, texture, name, tooltip)
            local button = { inventory = inventory, texture = texture,
                name = name, tooltip = tooltip }
            self.backpacks[#self.backpacks + 1] = button
            return button
        end
        return page
    end

    local page = lootPage()
    SC_RUNTIME_FIXTURE.fireRefresh(page, "buttonsAdded")
    check(#page.backpacks == 2 and page.backpacks[2].inventory == companionInventory
            and page.backpacks[2].name == "Sam Vance"
            and page.backpacks[2].texture == backpackIcon,
        "the companion whose inventory is open is put back into the rebuilt container list")

    local rebuilding = lootPage()
    rebuilding.inventoryPane = { inventory = companionInventory }
    function rebuilding:setNewContainer(inventory)
        self.inventoryPane.inventory = inventory
        self.inventory = inventory
    end
    SC_RUNTIME_FIXTURE.fireRefresh(rebuilding, "begin")
    SC_RUNTIME_FIXTURE.fireRefresh(rebuilding, "buttonsAdded")
    rebuilding.inventoryPane.inventory = otherInventory -- vanilla's one-to-two fallback
    SC_RUNTIME_FIXTURE.fireRefresh(rebuilding, "end")
    check(rebuilding.inventoryPane.inventory == companionInventory,
        "a refresh keeps the open companion selected when vanilla falls back to Ground")

    rebuilding.inventoryPane.inventory = otherInventory -- deliberate player selection
    SC_RUNTIME_FIXTURE.fireRefresh(rebuilding, "begin")
    SC_RUNTIME_FIXTURE.fireRefresh(rebuilding, "end")
    check(rebuilding.inventoryPane.inventory == otherInventory,
        "a deliberate selection of another container is not overridden")

    -- Only in the phase that runs before the selection is resolved, and never
    -- twice for one rebuild.
    SC_RUNTIME_FIXTURE.fireRefresh(page, "buttonsAdded")
    check(#page.backpacks == 2, "a container already in the list is not added again")
    local earlyPage = lootPage()
    SC_RUNTIME_FIXTURE.fireRefresh(earlyPage, "begin")
    SC_RUNTIME_FIXTURE.fireRefresh(earlyPage, "end")
    check(#earlyPage.backpacks == 1,
        "the companion is added in the phase the selection is resolved from, and no other")

    -- The player's own inventory page is not a loot pane and is left alone.
    local characterPage = lootPage()
    characterPage.onCharacter = true
    SC_RUNTIME_FIXTURE.fireRefresh(characterPage, "buttonsAdded")
    check(#characterPage.backpacks == 1, "the player's own inventory page is untouched")

    -- Nothing borrowed, nothing added.
    SC.UIBridge = { borrowedInventory = function() return nil end }
    local idlePage = lootPage()
    SC_RUNTIME_FIXTURE.fireRefresh(idlePage, "buttonsAdded")
    check(#idlePage.backpacks == 1,
        "a loot pane nobody borrowed keeps exactly the containers vanilla found")

    local withinOneTile = true
    SC.UIBridge = {
        borrowedInventory = function() return nil end,
        nearbyInventories = function(primary)
            check(primary == getPlayer(), "nearby inventory uses the main player")
            return withinOneTile and {
                { container = companionInventory, actor = companion },
            } or {}
        end,
        borrowedInventoryLabel = function() return "Sam Vance" end,
    }
    local automatic = lootPage()
    automatic.inventoryPane = { inventory = otherInventory }
    function automatic:setNewContainer(inventory)
        self.inventoryPane.inventory = inventory
    end
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "begin")
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "buttonsAdded")
    check(#automatic.backpacks == 2
            and automatic.backpacks[2].inventory == companionInventory
            and automatic.backpacks[2].name == "Sam Vance",
        "an adjacent companion appears as a named backpack in the loot pane")
    automatic.inventoryPane.inventory = companionInventory
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "end")
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "begin")
    automatic.backpacks = { { inventory = otherInventory } }
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "buttonsAdded")
    automatic.inventoryPane.inventory = otherInventory
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "end")
    check(automatic.inventoryPane.inventory == companionInventory,
        "an automatic companion selection survives vanilla's list rebuild")
    withinOneTile = false
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "begin")
    automatic.backpacks = { { inventory = otherInventory } }
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "buttonsAdded")
    automatic.inventoryPane.inventory = otherInventory
    SC_RUNTIME_FIXTURE.fireRefresh(automatic, "end")
    check(#automatic.backpacks == 1
            and automatic.inventoryPane.inventory == otherInventory,
        "the icon and selected container go away when the companion leaves")

    -- A handler that throws would break the player's whole inventory window.
    SC.UIBridge = { borrowedInventory = function() error("injected bridge failure") end }
    local brokenPage = lootPage()
    SC_RUNTIME_FIXTURE.fireRefresh(brokenPage, "buttonsAdded")
    check(#brokenPage.backpacks == 1,
        "a failing companion-container hook does not escape into the inventory window")

    SC.UIBridge = savedBridge
    getTexture = savedGetTexture
    SC.Runtime.reset(true)
    check(SC_RUNTIME_FIXTURE.refreshCount() == 0,
        "resetting the runtime gives the inventory-refresh event back")
end)()

print("RUNTIME_HOOK_KAHLUA_PASS checks=" .. tostring(checks))
