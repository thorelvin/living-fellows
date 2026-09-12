-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
local Trade, Persistence = SC.Trade, SC.Persistence
local nextItemId = 7000

local function makeItem(itemType, options)
    local value = options or {}
    nextItemId = nextItemId + 1
    value.__class = value.__class or "InventoryItem"
    value.itemType = itemType
    value.nativeId = value.nativeId or nextItemId
    value.condition = value.condition or 10
    value.modData = value.modData or {}
    value.parts = value.parts or {}
    function value:getID() return self.nativeId end
    function value:getFullType() return self.itemType end
    function value:getCondition() return self.condition end
    function value:setCondition(amount) self.condition = amount end
    function value:isFavorite() return self.favorite == true end
    function value:setFavorite(enabled)
        if self.failFavoriteOnce then
            self.failFavoriteOnce = false
            error("injected favourite restore failure")
        end
        self.favorite = enabled == true
    end
    function value:getModData()
        if self.failModDataOnce then
            self.failModDataOnce = false
            error("injected marker failure")
        end
        return self.modData
    end
    function value:getInventory() return nil end
    function value:getContainer() return self.container end
    function value:getWorldItem() return self.worldItem end
    function value:getAllWeaponParts() return self.parts end
    function value:attachWeaponPart(part)
        if self.failAttachOnce then
            self.failAttachOnce = false
            error("injected weapon-part attachment failure")
        end
        self.parts[#self.parts + 1] = part
        part.container = nil
    end
    return value
end

local function makeInventory()
    local value = { items = {} }
    function value:getItems() return self.items end
    function value:AddItem(candidate)
        if type(candidate) ~= "table" then
            candidate = makeItem(candidate, {
                failFavoriteOnce = self.failGeneratedFavoriteOnce == true,
                failModDataOnce = self.failGeneratedModDataOnce == true,
            })
            self.failGeneratedFavoriteOnce = false
            self.failGeneratedModDataOnce = false
        end
        self.items[#self.items + 1] = candidate
        candidate.container = self
        return candidate
    end
    function value:Remove(candidate)
        if self.rejectRemove == true or self.rejectRemoveItem == candidate then return false end
        for index, current in ipairs(self.items) do
            if current == candidate then
                table.remove(self.items, index)
                candidate.container = nil
                return
            end
        end
    end
    return value
end

local function makeActor(id)
    local value = { __class = "IsoPlayer", id = id, inventory = makeInventory() }
    value.inventory.owner = value
    function value:getInventory() return self.inventory end
    return value
end

local player, resident = makeActor("recovery-player"), makeActor("recovery-resident")
local actors = { [resident.id] = resident }
local originalResolve, originalIdOf = SC.GameplayUtil.resolveActor, SC.GameplayUtil.idOf
SC.GameplayUtil.resolveActor = function(id) return actors[id], actors[id] and nil or "missing" end
SC.GameplayUtil.idOf = function(actor) return actor and actor.id or nil end

local function snapshotFor(recoveryId, itemType)
    local root = makeItem(itemType, {
        condition = 4, favorite = true,
        modData = {
            LF_TradeRecoveryId = recoveryId,
            LF_TradeRecoveryState = "original",
            payload = "preserved",
        },
    })
    root.parts[1] = makeItem("Base.Scope", {
        condition = 3, modData = { partPayload = "preserved" },
    })
    local snapshot, reason = Persistence.captureDetachedItem(root)
    check(snapshot ~= nil, "detached fixture captures: " .. tostring(reason))
    return snapshot
end

local function envelope(recoveryId, itemType, options)
    options = options or {}
    return {
        version = 1, serial = 1, cursorSerial = 0,
        entries = { {
            recoveryId = recoveryId, serial = 1, factionId = options.factionId or "recovery-test",
            recordedAt = SC_TEST_CLOCK, attempts = options.attempts or 0,
            phase = options.phase or "recovery_pending",
            detachedProof = options.detachedProof == true,
            sourceOwner = options.sourceOwner or { kind = "player" },
            destinationOwner = options.destinationOwner
                or { kind = "actor", id = resident.id },
            itemState = snapshotFor(recoveryId, itemType),
        } },
    }
end

local function countType(inventory, itemType)
    local count, found = 0, nil
    for _, candidate in ipairs(inventory.items) do
        if candidate:getFullType() == itemType then count, found = count + 1, candidate end
    end
    return count, found
end

-- Failure after the root marker and before full state completion must keep the
-- exact partial object until its removal is proven. A retry may not add a copy.
do
    local id, itemType = "lf-trade:integration:after", "Base.RecoveryRifleAfter"
    player.inventory.failGeneratedFavoriteOnce = true
    player.inventory.rejectRemove = true
    check(Trade.restore(envelope(id, itemType, { detachedProof = true })),
        "post-marker recovery fixture restores")
    Trade.recoverPending(player, 1, true)
    local count, partial = countType(player.inventory, itemType)
    check(count == 1 and partial.modData.LF_TradeRecoveryState == "building"
            and Trade.pendingRecoveryCount() == 1,
        "failed reconstruction retains one marked partial root")
    Trade.recoverPending(player, 1, true)
    check(select(1, countType(player.inventory, itemType)) == 1,
        "a rejected partial cleanup never creates a second root")
    player.inventory.rejectRemove = false
    local recovered = Trade.recoverPending(player, 1, true)
    count, partial = countType(player.inventory, itemType)
    check(recovered and count == 1 and #partial.parts == 1
            and partial.parts[1]:getFullType() == "Base.Scope"
            and partial.modData.payload == "preserved"
            and partial.modData.LF_TradeRecoveryId == nil
            and Trade.pendingRecoveryCount() == 0,
        "verified cleanup rebuilds exactly one complete root with its weapon part")
    player.inventory:Remove(partial)
end

-- Even a failure before the Lua marker is written has a persisted native ID.
-- A simulated restart must find and clean that exact identity before rebuilding.
do
    local id, itemType = "lf-trade:integration:before", "Base.RecoveryRifleBefore"
    player.inventory.failGeneratedModDataOnce = true
    player.inventory.rejectRemove = true
    check(Trade.restore(envelope(id, itemType, { detachedProof = true })),
        "pre-marker recovery fixture restores")
    Trade.recoverPending(player, 1, true)
    local saved = Trade.export()
    check(saved and saved.entries[1].reconstructionPartial == true
            and saved.entries[1].partialNativeId ~= nil
            and select(1, countType(player.inventory, itemType)) == 1,
        "pre-marker failure exports its exact native identity")
    check(Trade.restore(saved), "pre-marker recovery survives a simulated restart")
    Trade.recoverPending(player, 1, true)
    check(select(1, countType(player.inventory, itemType)) == 1,
        "restart retry does not duplicate an unmarked partial root")
    player.inventory.rejectRemove = false
    local recovered = Trade.recoverPending(player, 1, true)
    local count, rebuilt = countType(player.inventory, itemType)
    check(recovered and count == 1 and #rebuilt.parts == 1
            and Trade.pendingRecoveryCount() == 0,
        "native identity cleanup completes before one verified rebuild")
    player.inventory:Remove(rebuilt)
end

-- List membership and InventoryItem.getContainer must agree before a marker can
-- close the journal.
do
    local id, itemType = "lf-trade:integration:owner", "Base.RecoveryOwnerConflict"
    local saved = envelope(id, itemType, { detachedProof = false })
    local conflicting = makeItem(itemType, {
        modData = {
            LF_TradeRecoveryId = id,
            LF_TradeRecoveryState = "original",
        },
    })
    player.inventory:AddItem(conflicting)
    conflicting.container = resident.inventory
    check(Trade.restore(saved), "owner-conflict recovery fixture restores")
    local recovered = Trade.recoverPending(player, 1, true)
    check(not recovered and Trade.pendingRecoveryCount() == 1
            and conflicting.modData.LF_TradeRecoveryId == id,
        "a conflicting native owner pointer cannot falsely finish recovery")
    conflicting.container = player.inventory
    player.inventory:Remove(conflicting)
    Trade.reset()
end

-- Absence from the two original inventories after restart is not world-wide
-- absence. Without a durable detached proof, keep the snapshot quarantined.
do
    local id, itemType = "lf-trade:integration:third", "Base.RecoveryThirdContainer"
    local saved = envelope(id, itemType, {
        detachedProof = false,
        attempts = SC.Config.get("tradeRecoveryMaxAttempts") - 1,
    })
    local stash = makeInventory()
    local original = makeItem(itemType, {
        modData = {
            LF_TradeRecoveryId = id,
            LF_TradeRecoveryState = "original",
        },
    })
    stash:AddItem(original)
    check(Trade.restore(saved), "third-container recovery fixture restores")
    local recovered = Trade.recoverPending(player, 1, true)
    local quarantined = Trade.export()
    check(recovered and stash.items[1] == original
            and select(1, countType(player.inventory, itemType)) == 0
            and quarantined.entries[1].phase == "recovery_quarantined",
        "ambiguous absence quarantines the snapshot without duplicating a third-container item")
    Trade.reset()
end

SC.GameplayUtil.resolveActor, SC.GameplayUtil.idOf = originalResolve, originalIdOf
print("TRADE_PERSISTENCE_RECOVERY_PASS checks=" .. tostring(checks))
