-- SPDX-License-Identifier: MIT
-- Exercise the public world menu and callback arguments, including two
-- containers sharing one tile. BaseLife's real removal guards have gameplay tests.
local T, SC = MEDICAL_CONTEXT_TEST, LivingFellows
local checks, removed, visualRefreshes, uiRefreshes = 0, {}, 0, 0
local shown, remote, inside, blocked, pending = false, false, true, false, nil
local function check(value, why)
    checks = checks + 1
    assert(value, "storage context " .. checks .. ": " .. why)
end
local basicMenu = T.menu
T.menu = function()
    local menu = basicMenu()
    function menu:addSubMenu(option, child) option.submenu = child end
    return menu
end
ISContextMenu.getNew = function() return T.menu() end
local square = T.square(11, 11)
local function container()
    local object = { items = { {}, {} } }
    function object:getSquare() return square end
    function object:getContainer() return self.items end
    function object:getObjectIndex() return 3 end
    return object
end
local marked, other = container(), container()
local storage = { id = "storage:7", category = "memorial", withdrawals = false, deposits = false,
    x = 11, y = 11, z = 0, objectIndex = 3 }
local resolved, rows = marked, { storage }
SC.BaseLife = {
    active = function() return {} end,
    isInside = function() return inside end,
    withinWorkReach = function() return false end,
    zoneDraft = function() return nil end,
    constructionAt = function() return {} end,
    storageRows = function() return rows end,
    resolveObject = function(row) return row == storage and resolved or nil end,
    resolveContainer = function(row)
        if row == storage and resolved then return resolved:getContainer(), resolved end
    end,
    storageCompartments = function(object)
        return { { container = object:getContainer(), index = 0 } }
    end,
    removeStorage = function(id)
        removed[#removed + 1] = id
        if blocked then return false, "work_order_uses_storage" end
        if #rows == 0 then return false, "unknown_storage" end
        rows = {}
        return true
    end,
}
SC.BaseVisuals = { status = function() return { enabled = shown } end,
    refresh = function() visualRefreshes = visualRefreshes + 1 end }
SC.BaseWatch = { isRemote = function() return remote end }
SC.UI.confirmBaseAction = function(message, execute) pending = { message = message, execute = execute } end
SC.UI.refresh = function() uiRefreshes = uiRefreshes + 1 end
SC.UI.baseFailureReason = function(reason) return "readable:" .. tostring(reason) end
local function find(menu, key)
    for _, option in ipairs(menu.options) do
        if option.name == key then return option end
        if option.submenu then
            local found = find(option.submenu, key)
            if found then return found end
        end
    end
end
local function menuFor(object, test)
    local menu = T.menu()
    SC.UIContext.fillWorldObjectContextMenu(0, menu, { object }, test)
    return menu
end
local function select(option)
    option.onSelect(option.target, option.param1, option.param2, option.param3)
end
local option = find(menuFor(marked), "UI_SC_Base_UnmarkStorage")
check(option and not option.notAvailable, "registered storage can be unmarked with the layout hidden and both access permissions off")
check(#removed == 0 and pending == nil, "opening the world menu does not remove a registration or open confirmation")
check(find(menuFor(other), "UI_SC_Base_UnmarkStorage") == nil,
    "an unmarked container sharing the same square and object index never inherits the marked container's action")
select(option)
check(pending and pending.message == "UI_SC_Base_RemoveStorageConfirm" and #removed == 0,
    "selecting Unmark storage asks for the existing storage confirmation before dispatch")
pending = nil -- Player cancels.
check(#rows == 1 and #removed == 0, "cancelling leaves the marking intact")
shown = true
check(find(menuFor(marked), "UI_SC_Base_UnmarkStorage") ~= nil, "layout visibility never controls storage removal availability")
shown, inside = false, false
check(find(menuFor(marked), "UI_SC_Base_UnmarkStorage") ~= nil,
    "a marked container outside a changed camp boundary still exposes removal")
check(find(menuFor(other), "UI_SC_Context_BaseLife") == nil,
    "an unrelated outside-camp container does not open base management")
check(find(menuFor(marked), "UI_SC_Base_MarkStorage") == nil,
    "outside-camp cleanup does not allow new storage registration outside camp")
inside, remote = true, true
check(find(menuFor(marked), "UI_SC_Base_UnmarkStorage") == nil, "remote Base Watch cannot edit local storage")
remote = false
select(option)
remote = true
pending.execute()
check(#removed == 0 and #rows == 1, "a view change while confirmation is open rechecks the normal local-edit guard")
remote, blocked = false, true
select(option)
pending.execute()
check(#removed == 1 and removed[1] == storage.id and #rows == 1,
    "confirmation routes the exact persistent storage ID through BaseLife's guarded removal")
check(T.doctor.note == "UI_SC_Base_ActionFailed", "a busy registration reports failure instead of pretending to unmark it")
blocked = false
local items = marked.items
select(option)
pending.execute()
check(#removed == 2 and #rows == 0, "successful confirmation removes the registration")
check(marked:getContainer() == items and #items == 2 and other:getContainer() ~= items,
    "the world container and exact item objects are left untouched")
check(visualRefreshes == 2 and uiRefreshes == 2, "both management UI and layout refresh after the guarded action")
check(find(menuFor(marked), "UI_SC_Base_UnmarkStorage") == nil, "removed storage no longer offers Unmark")
rows, resolved = { storage }, nil
check(find(menuFor(marked), "UI_SC_Base_UnmarkStorage") == nil,
    "unresolved or ambiguous persistent identity cannot unmark a different clicked object")

local direct = find(menuFor(other), "UI_SC_Base_MarkStorage")
local directTools = direct and find(direct.submenu, "UI_SC_Base_Storage_tools")
check(directTools and directTools.param2.container == other:getContainer(),
    "a one-compartment crate keeps direct category selection")

local appliance = container()
function appliance:getContainer() return nil end
function appliance:getContainerCount() return 2 end
local fridge = { getType = function() return "fridge" end }
local freezer = { getType = function() return "freezer" end }
local labels = { IGUI_ContainerTitle_fridge = "Fridge", IGUI_ContainerTitle_freezer = "Freezer" }
getTextOrNull = function(key) return labels[key] end
local fixtureText = SC.UI.text
SC.UI.text = function(key, first, second)
    if key == "UI_SC_Base_StorageCompartmentNumbered" then
        return first .. " (" .. second .. ")"
    end
    return fixtureText(key, first, second)
end
local registrations = {}
rows = {}
SC.BaseLife.storageCompartments = function(object)
    if object ~= appliance then return {} end
    return { { container = fridge, index = 0 }, { container = freezer, index = 1 } }
end
SC.BaseLife.registerStorage = function(object, category, selected)
    local row = { id = "storage:" .. tostring(#rows + 1), category = category }
    rows[#rows + 1] = row
    registrations[row.id] = { object = object, container = selected, category = category }
    return true, row
end
SC.BaseLife.resolveContainer = function(row)
    local data = registrations[row.id]
    if data then return data.container, data.object end
end
SC.BaseLife.resolveObject = function(row)
    return registrations[row.id] and registrations[row.id].object or nil
end
local function exactRemove(id)
    removed[#removed + 1] = id
    for index, row in ipairs(rows) do
        if row.id == id then table.remove(rows, index) return true end
    end
    return false, "unknown_storage"
end
SC.BaseLife.removeStorage = exactRemove

local choices = find(menuFor(appliance), "UI_SC_Base_MarkStorage")
check(choices and #choices.submenu.options == 2,
    "a multi-compartment appliance with no primary getter still exposes both compartments")
local fridgeMenu = find(choices.submenu, "Fridge")
local freezerMenu = find(choices.submenu, "Freezer")
check(fridgeMenu and freezerMenu, "the world menu uses native fridge and freezer titles")
select(find(fridgeMenu.submenu, "UI_SC_Base_Storage_fresh_food"))
select(find(freezerMenu.submenu, "UI_SC_Base_Storage_food"))
local fridgeMark, freezerMark = rows[1], rows[2]
check(registrations[fridgeMark.id].container == fridge and fridgeMark.category == "fresh_food"
    and registrations[freezerMark.id].container == freezer and freezerMark.category == "food",
    "both category callbacks carry the exact native compartment and its chosen category")

function fridge:getCustomName() return "Food drawer" end
function freezer:getCustomName() return "Food drawer" end
local options = menuFor(appliance)
choices = find(options, "UI_SC_Base_MarkStorage")
check(find(choices.submenu, "Food drawer (1)") and find(choices.submenu, "Food drawer (2)"),
    "duplicate custom names display the original native compartment numbers")
local unmark = find(options, "UI_SC_Base_UnmarkStorage")
local exactFreezer = unmark and find(unmark.submenu, "Food drawer (2)")
check(exactFreezer ~= nil, "the freezer has an independent unmark option")
select(exactFreezer)
pending.execute()
check(#rows == 1 and rows[1] == fridgeMark and removed[#removed] == freezerMark.id,
    "unmarking the freezer preserves the sibling marking")
unmark = find(menuFor(appliance), "UI_SC_Base_UnmarkStorage")
check(unmark and not find(unmark.submenu, "Food drawer (2)"),
    "an unmarked compartment never inherits its sibling's unmark action")

local barrel = container()
function barrel:getContainer() return nil end
SC.FarmStorage = { canMarkMilk = function(object) return object == barrel end }
choices = find(menuFor(barrel), "UI_SC_Base_MarkStorage")
local milk = choices and find(choices.submenu, "UI_SC_Base_Storage_milk")
check(milk and #choices.submenu.options == 1, "a fluid barrel keeps direct Milk-only marking")
select(milk)
local milkRow = rows[2]
check(milkRow.category == "milk" and registrations[milkRow.id].container == nil,
    "Milk marking does not supply an item compartment")
local removeMilk = find(menuFor(barrel), "UI_SC_Base_UnmarkStorage")
check(removeMilk and not removeMilk.submenu, "fluid storage keeps direct Unmark storage")
select(removeMilk)
pending.execute()
check(removed[#removed] == milkRow.id and #rows == 1 and rows[1] == fridgeMark,
    "unmarking fluid storage deletes its exact registration only")
SC_TEST_REPORT = "Storage world-menu compartments and removal: " .. checks .. " checks passed"
