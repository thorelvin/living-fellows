-- SPDX-License-Identifier: MIT
local U, checks = SurvivorCompanion.GameplayUtil, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "container visuals " .. checks .. ": " .. message)
end
local function container(parent)
    local value = { items = {}, parent = parent }
    function value:getItems() return self.items end
    function value:getParent() return self.parent end
    function value:getContainingItem() return self.bag end
    function value:setDrawDirty(dirty) self.drawDirty = dirty end
    function value:contains(item)
        for _, candidate in ipairs(self.items) do if candidate == item then return true end end
        return false
    end
    function value:AddItem(item)
        if self.reject then return nil end
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function value:Remove(item)
        for index, candidate in ipairs(self.items) do
            if candidate == item then table.remove(self.items, index) item.container = nil return end
        end
    end
    if parent then parent.container = value end
    return value
end
local shelf, sourceShelf = { __class = "IsoObject" }, { __class = "IsoObject" }
local actor = { __class = "IsoGameCharacter" }
local carried, destination, source = container(actor), container(shelf), container(sourceShelf)
local exact = { getFullType = function() return "Base.Nails" end }
local updates, observed = {}, {}
ItemPicker = { updateOverlaySprite = function(parent)
    updates[#updates + 1] = parent
    observed[parent] = #parent.container.items
    parent.overlay = #parent.container.items > 0 and "stocked" or nil
end }
ISInventoryPage = {}
carried:AddItem(exact)
check(U.transferItemVerified(carried, destination, exact), "deposit succeeds")
check(shelf.overlay == "stocked" and observed[shelf] == 1,
    "deposit into an initially empty shelf refreshes the vanilla overlay after ownership is verified")
check(#updates == 1 and updates[1] == shelf and carried.drawDirty and destination.drawDirty,
    "both inventory panes are dirty while only the map shelf gets an overlay")
check(ISInventoryPage.renderDirty == true, "native inventory page is refreshed")

updates, ISInventoryPage.renderDirty = {}, false
check(U.transferItemVerified(destination, carried, exact), "withdrawal succeeds")
check(shelf.overlay == nil and observed[shelf] == 0 and #updates == 1,
    "taking the last item clears the shelf overlay")
check(U.transferItemVerified(carried, source, exact), "source shelf is stocked")
updates = {}
check(U.transferItemVerified(source, destination, exact), "shelf-to-shelf transfer succeeds")
check(sourceShelf.overlay == nil and shelf.overlay == "stocked" and #updates == 2,
    "both world containers reflect the final transfer")

-- A rejected destination must show the rolled-back owner, without duplicating cargo.
source.reject = true
updates = {}
local moved, reason = U.transferItemVerified(destination, source, exact)
check(not moved and reason == "destination_add_failed_rolled_back", "failed add rolls back")
check(shelf.overlay == "stocked" and sourceShelf.overlay == nil
    and destination:contains(exact) and not source:contains(exact),
    "rollback refresh observes exact restored ownership")
source.reject = nil

updates = {}
check(U.transferItemVerified(carried, destination, exact), "already-completed receipt remains idempotent")
check(#destination.items == 1 and shelf.overlay == "stocked", "receipt replay never duplicates the item")
ItemPicker.updateOverlaySprite = function() error("injected visual callback failure") end
check(U.transferItemVerified(destination, carried, exact) and carried:contains(exact),
    "visual callback failure cannot undo or repeat a completed transfer")

local bag = container(shelf)
bag.bag = {}
updates = {}
ItemPicker.updateOverlaySprite = function(parent) updates[#updates + 1] = parent end
check(U.transferItemVerified(carried, bag, exact), "bag transfer succeeds")
check(#updates == 0 and bag.drawDirty, "nested bags do not repaint the containing world shelf")
ISInventoryPage = setmetatable({}, { __newindex = function() error("injected inventory UI failure") end })
check(U.transferItemVerified(bag, carried, exact) and carried:contains(exact),
    "inventory UI failure cannot turn a verified transfer into a failed receipt")
SC_TEST_REPORT = "CONTAINER_VISUALS_PASS checks=" .. checks
