-- SPDX-License-Identifier: MIT
-- Run with the installed ISContextMenu and the existing medical fixture.
-- These checks inspect the native option tree and dispatch real callbacks.
local T, SC = MEDICAL_CONTEXT_TEST, SurvivorCompanion
local Menu, Context = SC.ContextMenu, SC.UIContext
local nativeGet, nativeGetNew, nativeRender = ISContextMenu.get, ISContextMenu.getNew, ISContextMenu.render
assert(Menu and Context, "context helper and world menu must be loaded")
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "context menu " .. checks .. ": " .. message)
end
local restoreNative = T.installNativeMenus()
local function root()
    local menu = T.nativeMenu()
    T.nativeRoot = menu
    return menu
end
local function child(menu, option)
    return option and option.subOption and menu:getSubMenu(option.subOption) or nil
end
local function find(menu, key, direct)
    for _, option in ipairs(menu.options) do
        if option.scMenuKey == key or option.name == key then return option, menu end
        local nested = child(menu, option)
        if nested and not direct then
            local found, parent = find(nested, key)
            if found then return found, parent end
        end
    end
end
local function count(menu, name)
    local total = 0
    for _, option in ipairs(menu.options) do
        if option.name == name or option.scMenuKey == name then total = total + 1 end
        local nested = child(menu, option)
        if nested then total = total + count(nested, name) end
    end
    return total
end
local function select(option)
    assert(option and type(option.onSelect) == "function", "selectable option required")
    return option.onSelect(option.target, option.param1, option.param2, option.param3,
        option.param4, option.param5, option.param6, option.param7, option.param8,
        option.param9, option.param10)
end
local function validTree(menu)
    check(menu.numOptions == #menu.options + 1, "native option count remains consistent")
    for index, option in ipairs(menu.options) do
        check(option.id == index, "native IDs remain contiguous after insertion/removal")
        local nested = child(menu, option)
        if nested then
            check(#nested.options > 0, "no empty submenu is exposed")
            validTree(nested)
        end
    end
end

-- Native pooling is part of the contract: clear() reuses option tables and
-- must not carry ownership tags or cached child menus into the next build.
local lifecycle = root()
local foreignTarget, foreignCalls = {}, 0
local function foreignCallback(target, argument)
    check(target == foreignTarget and argument == "kept", "foreign callback arguments survive")
    foreignCalls = foreignCalls + 1
end
local foreign = lifecycle:addOption("Shared label", foreignTarget, foreignCallback, "kept")
local first = Menu.group(lifecycle, "test.group", "Shared label")
local owned = find(lifecycle, "test.group", true)
check(owned and owned ~= foreign and owned.scLFContext == true,
    "a group owns its tagged row without taking a foreign row sharing the label")
check(first == child(lifecycle, owned), "group uses the native subOption lookup")
check(Menu.group(lifecycle, "test.group", "Shared label") == first and #lifecycle.options == 2,
    "repeated group construction is idempotent within one menu")
local payload, callbackCalls = {}, 0
local action = Menu.action(first, "test.action", "Action", payload, function(target, a, b, c)
    check(target == payload and a == "first" and b == nil and c == "third",
        "action keeps its exact callback target and sparse arguments")
    callbackCalls = callbackCalls + 1
end, "first", nil, "third")
check(action and action.scMenuKey == "test.action" and action.scLFContext == true,
    "actions carry stable ownership and logical key tags")
select(action)
local replacementTarget, replacementCalls = {}, 0
local refreshed = Menu.action(first, "test.action", "Action updated", replacementTarget, function(target)
    check(target == replacementTarget, "refreshing an action updates its exact target")
    replacementCalls = replacementCalls + 1
end)
check(refreshed == action and #first.options == 1 and refreshed.param1 == nil
    and refreshed.param3 == nil, "reusing an action key updates its callback and clears stale arguments")
select(refreshed)
Menu.reason(action, "Bring a bandage first.")
check((action.notAvailable or action.isDisabled) and action.toolTip
    and action.toolTip.description == "Bring a bandage first.", "blocked actions keep a readable reason")
Menu.removeOwned(lifecycle, function(option) return option.scMenuKey == "test.group" end)
check(#lifecycle.options == 1 and lifecycle.options[1] == foreign
    and foreign.onSelect == foreignCallback and foreign.param1 == "kept",
    "owned removal preserves a foreign row with an identical label and its callback")
select(foreign)
check(foreignCalls == 1 and callbackCalls == 1 and replacementCalls == 1,
    "menu construction and removal never execute callbacks")
validTree(lifecycle)
local priorReused = Menu.group(lifecycle, "test.reused", "Reused")
lifecycle:clear()
local reusedForeign = lifecycle:addOption("Foreign after clear", foreignTarget, foreignCallback, "kept")
check(reusedForeign.scMenuKey == nil and reusedForeign.scLFContext == nil,
    "native option-pool reuse clears all LF ownership tags")
local rebuilt = Menu.group(lifecycle, "test.reused", "Reused")
check(rebuilt and rebuilt ~= priorReused and #lifecycle.options == 2,
    "a cleared pooled menu gets a fresh attached group rather than a cached orphan")
Menu.action(rebuilt, "rebuilt.leaf", "Leaf", nil, function() end)
validTree(lifecycle)
Menu.removeOwned(lifecycle, function() return true end)
check(#lifecycle.options == 1 and lifecycle.options[1] == reusedForeign,
    "the owned-removal predicate cannot remove unowned native or foreign rows")

local repeated = root()
local foreignGroup = repeated:addOption("Foreign submenu", nil, nil)
local foreignChild = ISContextMenu:getNew(repeated)
repeated:addSubMenu(foreignGroup, foreignChild)
local foreignLeaf = foreignChild:addOption("Foreign leaf", foreignTarget, foreignCallback, "kept")
local foreignSlot = foreignGroup.subOption
local function buildRepeated()
    local parent = Menu.group(repeated, "test.repeated", "Repeated")
    local nested = Menu.group(parent, "test.repeated.child", "Nested")
    Menu.action(nested, "test.repeated.leaf", "Leaf", nil, function() end)
    return parent, nested
end
buildRepeated()
local repeatedSlots, repeatedCreations, repeatedUi = repeated.subOptionNums,
    T.nativeCreations, T.nativeUiCount
for _ = 1, 12 do
    Menu.removeOwned(repeated, function(option) return option.scMenuKey == "test.repeated" end)
    local parent, nested = buildRepeated()
    check(repeated.subOptionNums == repeatedSlots and T.nativeCreations == repeatedCreations
        and T.nativeUiCount == repeatedUi, "repeated removal/rebuild reuses bounded native slots and UI windows")
    check(foreignGroup.subOption == foreignSlot and repeated:getSubMenu(foreignSlot) == foreignChild
        and foreignChild.options[1] == foreignLeaf and foreignLeaf.onSelect == foreignCallback,
        "reusing LF slots preserves a foreign submenu number, identity and callback")
    check(parent.parent == repeated and nested.parent == parent and parent.inUI and nested.inUI,
        "reused native descendants reattach to their correct visible-window lifecycle")
end
validTree(repeated)

-- Exercise native get()/getNew(), which pool whole submenu objects without
-- calling LF retirement. Only their Java window methods use fixture seams.
do
    local pooledRoot = root()
    pooledRoot.subMenuPool = {}
    function pooledRoot:bringToTop() end
    function pooledRoot:setForceCursorVisible() end
    function pooledRoot:isOptionSingleMenu() return false end
    local styled = Menu.group(pooledRoot, "test.style", "Styled")
    local originalBackground = { r = .2, g = .3, b = .4, a = .6 }
    styled.backgroundColor = originalBackground
    local drawn
    styled.render = function(self, label)
        drawn = self.backgroundColor
        if label == "fail" then error("render failure") end
        return label, nil, "third"
    end
    function styled:initialise() end
    function styled:instantiate() end
    function styled:bringToTop() end
    Menu.action(styled, "test.style.leaf", "Leaf", nil, function() end)
    Menu.finish(pooledRoot)
    local firstResult, missingResult, thirdResult = styled:render("lf")
    check(drawn.a == .96 and drawn.r == .08 and styled.backgroundColor == originalBackground
        and firstResult == "lf" and missingResult == nil and thirdResult == "third",
        "LF drawing scopes its background and preserves renderer return values")
    local rendered = pcall(styled.render, styled, "fail")
    check(not rendered and styled.backgroundColor == originalBackground,
        "a renderer error still restores the exact prior background")
    check(ISContextMenu.render == nativeRender, "LF styling does not wrap the global native renderer")
    nativeGet(0, 20, 30)
    local reused = nativeGetNew(ISContextMenu, pooledRoot)
    local foreignParent = pooledRoot:addOption("Foreign pooled submenu", nil, nil)
    pooledRoot:addSubMenu(foreignParent, reused)
    reused:addOption("Foreign leaf", foreignTarget, foreignCallback, "kept")
    reused:render("foreign")
    check(reused == styled and drawn == originalBackground
        and reused.backgroundColor == originalBackground and foreignParent.scLFContext == nil,
        "native get/getNew reuse draws a foreign submenu with its original background")
    local fixtureGetNew = ISContextMenu.getNew
    ISContextMenu.getNew = nativeGetNew
    nativeGet(0, 25, 35)
    local ownedAgain = Menu.group(pooledRoot, "test.style.again", "Styled again")
    Menu.action(ownedAgain, "test.style.again.leaf", "Leaf", nil, function() end)
    ownedAgain:render("lf again")
    check(ownedAgain == styled and drawn.a == .96 and ownedAgain.backgroundColor == originalBackground,
        "a pooled foreign submenu regains LF styling only while its current owned row renders")
    ISContextMenu.getNew = fixtureGetNew
end

local saved = {}
for _, key in ipairs({ "Registry", "UI", "Commands", "Interaction", "Names", "Medical",
    "HomeTrip", "UIHomeTrip", "ViewControl", "BaseLife", "BaseWatch", "BaseVisuals",
    "Factions", "FactionContracts", "Oddballs", "Objectives", "FieldWork", "Terminal",
    "VehicleUnload", "VehicleRefuel", "VehicleUpkeep", "GeneratorRefuel", "ExpeditionCar",
    "TaxiService", "TaxiCab", "TaxiFares", "Convoy", "VehicleHotwire" }) do
    saved[key] = SC[key]
    SC[key] = nil
end
local oldUtil, oldInstanceof = SC.GameplayUtil, instanceof
local actors, records, issued, opened = {}, {}, {}, {}
local enumerations, descriptions, initialisations, inventoryScans = 0, 0, 0, 0
local routeAttempts, candidateScans = 0, 0
local stopped, homeOpened = 0, nil
local watchStatus, bandageReason, homeBlocker = {}, "no_wound", nil
local orderKeys = { follow = "UI_SC_Action_Follow", stay = "UI_SC_Action_Stay",
    regroup = "UI_SC_Action_Regroup", retreat = "UI_SC_Action_Retreat" }
local function text(key, name, value)
    if key == "UI_SC_Context_NamedAction" or key == "UI_SC_Context_QuickNamed" then
        return name .. ": " .. value
    end
    if key == "UI_SC_Talk_To" then return "Talk to " .. name end
    if key == "UI_SC_Action_Watch" then return "Watch " .. name end
    if key == "UI_SC_Action_StopWatchingNamed" then return "Stop watching " .. name end
    return key
end
local function actor(id, name, x, y, recruited)
    local value = T.actor(id, name, x, y, false)
    value.companion = true
    value.state = { order = "follow", group = "alpha" }
    function value:getFullName() return self.name end
    function value:getModData() return { SC_Id = self.id } end
    function value:getInventory() inventoryScans = inventoryScans + 1 error("inventory scan during menu fill") end
    records[id] = { id = id, name = name, actor = value, recruited = recruited ~= false,
        identity = { forename = name, surname = "" } }
    actors[#actors + 1] = value
    return value
end
local a = actor("clicked-a", "Alice", 11, 10)
local b = actor("selected-b", "Bess", 12, 10)
SC.Registry = { living = function() enumerations = enumerations + 1 return actors end,
    byId = function(id) return records[id] end, idOf = function(value) return value.id end }
SC.GameplayUtil = { isZombie = function(value) return value and value.kind == "IsoZombie" end,
    isGoneTarget = function() return false end,
    instanceOf = function(value, kind) return value and value.kind == kind end,
    sameFloor = function(left, right) return left:getZ() == right:getZ() end,
    isValidActor = function(value) return value and not value.dead end,
    distance = function(left, right) return left:DistTo(right) end,
    position = function(value) return value:getX(), value:getY(), value:getZ() end,
    nameOf = function(value) return value.name end }
instanceof = SC.GameplayUtil.instanceOf
SC.Commands = { peek = function()
        initialisations = initialisations + 1 error("initialising state peek during menu fill")
    end,
    peekExisting = function(value) return value.state end,
    state = function() initialisations = initialisations + 1 error("state init during menu fill") end,
    ensure = function() initialisations = initialisations + 1 error("state init during menu fill") end,
    issue = function(id, command, payload, player)
        issued[#issued + 1] = { id = id, command = command, payload = payload, player = player }
        return true
    end }
SC.UI = { text = text, instance = { selectedId = b.id },
    displayName = function(value, fallback) return value.name or fallback end,
    open = function(page, id) opened[#opened + 1] = { page = page, id = id } end,
    refresh = function() end, baseFailureReason = function(reason) return "Readable: " .. tostring(reason) end,
    describeEntry = function(value)
        descriptions = descriptions + 1
        local record = records[value.id] or value
        return { id = record.id, name = record.name, actor = record.actor or value,
            available = true, alive = true, recruited = record.recruited, distance = 1 }
    end }
SC.Interaction = { quickOrders = { "follow", "stay", "regroup", "retreat", "send_home" },
    descriptor = function(command)
        return orderKeys[command] and { key = orderKeys[command], kind = "order" } or nil
    end,
    availability = function() return true end,
    reasonText = text,
    issue = function(row, command, player)
        return SC.Commands.issue(row.id, command, nil, player)
    end }
SC.Names = { displayName = function(record) return record.name end,
    setNickname = function() return true end }
SC.Objectives = { assignableKinds = function() return { "gear" } end,
    label = function() return "Find proper gear" end }
SC.Medical = { playerBandagePreflight = function()
    return bandageReason == nil, bandageReason
end }
SC.HomeTrip = { eligibility = function(selection)
    return { canStart = homeBlocker == nil, blocker = homeBlocker,
        records = selection.records or { selection.record }, leaderId = a.id }
end, reasonText = function() return "Set a camp rally first." end,
    draft = function() routeAttempts = routeAttempts + 1 error("route planning during menu fill") end }
SC.UIHomeTrip = { openSheet = function(selection) homeOpened = selection return true end }
SC.ExpeditionCar = { displayName = function() return "Estate" end,
    fieldCandidates = function() candidateScans = candidateScans + 1 error("car scan during menu fill") end,
    preflightField = function() routeAttempts = routeAttempts + 1 error("route preflight during menu fill") end }
SC.ViewControl = { status = function() return watchStatus end,
    stopWatching = function() stopped = stopped + 1 return true end,
    watch = function(id, value) opened[#opened + 1] = { page = "watch", id = id, actor = value } return true end }

local function fill(objects, test, menu)
    menu = menu or root()
    T.nativeRoot = menu
    local before = enumerations
    local beforeDescriptions = descriptions
    Context.fillWorldObjectContextMenu(0, menu, objects or {}, test == true)
    check(descriptions == beforeDescriptions and initialisations == 0 and inventoryScans == 0
        and routeAttempts == 0 and candidateScans == 0,
        "menu construction uses no full row descriptions, state init, inventory/car scans or routes")
    if not test then check(enumerations - before == 1, "real fill enumerates the roster exactly once") end
    validTree(menu)
    return menu
end
local function group(menu, key)
    local option, parent = find(menu, key)
    return child(parent or menu, option), option
end

local clicked = fill({ a })
for _, name in ipairs({ "Talk to Alice", "Alice: " .. orderKeys.follow,
    "Alice: " .. orderKeys.stay, "Alice: " .. orderKeys.retreat }) do
    check(find(clicked, name, true) ~= nil and count(clicked, name) == 1,
        "clicked companion has one direct quick action: " .. name)
end
check(not find(clicked, orderKeys.regroup, true) and not find(clicked, "Watch Alice", true)
    and not find(clicked, "UI_SC_HomeTrip_Menu", true) and not find(clicked, "UI_SC_Nickname_Give", true)
    and not find(clicked, "UI_SC_Talk_OpenOrders", true)
    and not find(clicked, "UI_SC_Action_OpenInventory", true),
    "secondary companion actions stay out of the root quick strip")
for _, actionName in ipairs({ "follow", "stay", "retreat" }) do
    check(count(clicked, "leaf:" .. a.id .. ":" .. actionName) == 1,
        "a direct quick order is not repeated inside a child menu: " .. actionName)
end
check(not find(clicked, "Bess: UI_SC_Action_MoveHere", true),
    "clicked Alice cannot expose an unrelated selected Bess ground order")
local lf, lfOption = group(clicked, "lf")
check(lf and lfOption.name == "UI_SC_Context_LivingFellows", "the root uses the neutral Living Fellows label")
local person = group(clicked, "person:" .. a.id)
check(person and find(person, "UI_SC_Talk_OpenOrders", true)
    and find(person, orderKeys.regroup, true) and find(person, "UI_SC_HomeTrip_Menu", true)
    and find(person, "Watch Alice", true), "the clicked person's submenu keeps its remaining actions together")
check(not find(clicked, "person:" .. b.id), "selected Bess does not displace clicked Alice's primary submenu")
local nearby = group(clicked, "nearby")
check(nearby and #nearby.options == 1 and nearby.options[1].name == "Bess"
    and child(nearby, nearby.options[1]) == nil, "nearby companions are compact name actions opening Orders")
select(nearby.options[1])
check(opened[#opened].page == "orders" and opened[#opened].id == b.id,
    "a compact nearby name opens that exact person's Orders")
local c = actor("changed-c", "Cara", 13, 10)
SC.UI.instance.selectedId = c.id
select(find(clicked, "leaf:" .. a.id .. ":follow", true))
check(issued[#issued] and issued[#issued].id == a.id and issued[#issued].command == "follow",
    "an existing clicked-person callback still dispatches Alice after selection changes")
local issuedBefore = #issued
records[a.id] = { id = a.id, name = "Replacement", actor = b, recruited = true }
select(find(clicked, "leaf:" .. a.id .. ":stay", true))
check(#issued == issuedBefore, "stale clicked identity cannot send an order to a replacement record")
records[a.id] = { id = a.id, name = a.name, actor = a, recruited = true }

-- No body hit: the explicitly selected companion retains named ground and
-- object shortcuts, and an ambiguous body hit must not guess a primary.
SC.UI.instance.selectedId = b.id
local groundSquare = T.square(13, 10)
local floor = { getSquare = function() return groundSquare end }
local ground = fill({ floor })
local move = find(ground, "Bess: UI_SC_Action_MoveHere", true)
check(move ~= nil, "empty-ground shortcut explicitly names the selected recipient")
select(move)
check(issued[#issued].id == b.id and issued[#issued].command == "move_to"
    and issued[#issued].payload.x == 13, "ground shortcut keeps the selected identity and clicked square")
do
    local oldIsoX, oldIsoY, oldCell = screenToIsoX, screenToIsoY, getCell
    screenToIsoX = function(_, x) return x end
    screenToIsoY = function(_, _, y) return y end
    getCell = function() return { getGridSquare = function(_, x, y, z) return T.square(x, y, z) end } end
    local shifted = root()
    shifted.requestX, shifted.requestY, shifted.x, shifted.y = 13, 10, 97, 90
    fill({ floor }, false, shifted)
    select(find(shifted, "Bess: UI_SC_Action_MoveHere", true))
    check(issued[#issued].payload.x == 13 and issued[#issued].payload.y == 10,
        "ground commands use the immutable native click rather than the menu's shifted display position")
    screenToIsoX, screenToIsoY, getCell = oldIsoX, oldIsoY, oldCell
end
local ambiguous = fill({ a, b })
check(not find(ambiguous, "leaf:" .. a.id .. ":follow", true)
    and not find(ambiguous, "leaf:" .. b.id .. ":follow", true)
    and not find(ambiguous, "Bess: UI_SC_Action_MoveHere", true),
    "overlapping body hits cannot guess a primary person or use selected-person shortcuts")
local unknown = actor("unrecruited", "Cole", 13, 10, false)
local stranger = fill({ unknown })
check(find(stranger, "Talk to Cole", true)
    and not find(stranger, "leaf:" .. unknown.id .. ":follow", true),
    "an unrecruited companion gets conversation without recruited quick orders")

watchStatus = { watching = true, watchId = a.id, watchActor = a }
local watched = fill({ floor })
local stop = find(watched, "Stop watching Alice", true)
check(stop ~= nil and count(watched, "Stop watching Alice") == 1,
    "active watch always exposes one global Stop watching action")
select(stop)
check(stopped == 1, "global Stop watching uses the existing view-control stop")
watchStatus = {}
bandageReason, homeBlocker = "no_bandage", "rally_missing"
local blocked = fill({ a })
local bandage = find(blocked, "UI_SC_Action_Bandage")
local sendHome = find(blocked, "UI_SC_HomeTrip_Menu")
check(bandage and (bandage.notAvailable or bandage.isDisabled) and bandage.toolTip
    and bandage.toolTip.description == "UI_SC_Disabled_NoBandage", "a treatable wound keeps its missing-bandage reason")
check(sendHome and (sendHome.notAvailable or sendHome.isDisabled) and sendHome.toolTip
    and string.find(sendHome.toolTip.description, "Set a camp rally first.", 1, true),
    "a relevant blocked Send home remains visible with its reason")
bandageReason, homeBlocker = "no_wound", nil
check(not find(fill({ a }), "UI_SC_Action_Bandage"), "a healthy companion has no irrelevant Bandage action")

local door = { kind = "IsoDoor", getSquare = function() return groundSquare end,
    getObjectIndex = function() return 2 end, IsOpen = function() return false end }
check(find(fill({ door }), "Bess: UI_SC_Action_OpenDoor", true),
    "a door uses the selected recipient's named relevant shortcut")
do
    local original = SC.ForceEntry
    local carried, borrow, failed = true, false, false
    SC.ForceEntry = { eligible = function(object) return object == door end,
        tool = function() return carried and {} or nil end,
        canBorrow = function() return borrow end, failed = function() return failed end }
    local menu = fill({ door })
    local force = find(menu, "Bess: UI_SC_Action_ForceOpen")
    check(force and not find(menu, "Bess: UI_SC_Action_ForceOpen", true),
        "named crowbar command stays inside Living Fellows instead of the vanilla root")
    select(force)
    check(issued[#issued].id == b.id and issued[#issued].command == "force_open"
        and issued[#issued].payload.object == door, "forcing retains exact actor and portal")
    carried=false
    check(find(fill({door}),"Bess: UI_SC_Action_ForceOpen").notAvailable,
        "away from camp a missing carried crowbar has a disabled command")
    borrow=true
    check(not find(fill({door}),"Bess: UI_SC_Action_ForceOpen").notAvailable,
        "camp command allows automatic borrowing")
    failed=true
    check(find(fill({door}),"Bess: UI_SC_Action_RetryForceOpen"),"failed attempt exposes explicit Retry")
    SC.ForceEntry=original
end
local car = { getX = function() return 12 end, getY = function() return 10 end,
    getSqlId = function() return 7 end }
function groundSquare:getVehicleContainer() return car end
SC.VehicleRefuel = { eligible = function() return false, "fuel_missing" end }
local carMenu = fill({ floor })
local vehicleGroup = group(carMenu, "vehicle")
local refuel = find(carMenu, "UI_SC_Base_RefuelFromBase")
check(vehicleGroup and refuel and (refuel.notAvailable or refuel.isDisabled) and refuel.toolTip,
    "clicked-car work is grouped and a relevant refusal keeps its reason")
check(not find(carMenu, "UI_SC_Base_RefuelFromBase", true), "vehicle work does not spill onto the root")
groundSquare.getVehicleContainer = nil

local generator = { kind = "IsoGenerator", getSquare = function() return groundSquare end }
SC.GeneratorRefuel = { eligible = function() return false, "generator_full" end }
local generatorMenu = fill({ generator })
check(group(generatorMenu, "generator") and find(generatorMenu, "UI_SC_Base_RefuelGeneratorFromBase")
    and not find(generatorMenu, "UI_SC_Base_RefuelGeneratorFromBase", true),
    "clicked-generator work stays in its relevant Living Fellows group")

local storage = { id = "storage:context", category = "general" }
local container = { getSquare = function() return groundSquare end,
    getContainer = function() return {} end, getObjectIndex = function() return 4 end }
SC.BaseLife = { active = function() return {} end, isInside = function() return true end,
    zoneDraft = function() return nil end, constructionAt = function() return {} end,
    storageRows = function() return { storage } end,
    resolveObject = function() return container end }
SC.BaseVisuals = { status = function() return { enabled = false } end }
SC.BaseWatch = { isRemote = function() return false end }
local campMenu = fill({ container })
local lfStorage, lfStorageOption = group(campMenu, "lf")
local mark, markParent = find(campMenu, "UI_SC_Base_MarkStorage")
local unmark, unmarkParent = find(campMenu, "UI_SC_Base_UnmarkStorage")
check(mark and unmark and markParent == lfStorage and unmarkParent == lfStorage
    and not find(campMenu, "UI_SC_Base_MarkStorage", true)
    and not find(campMenu, "UI_SC_Base_UnmarkStorage", true)
    and not group(campMenu, "camp"),
    "storage marking and removal stay inside Living Fellows without Camp/Storage wrappers")
check(lfStorage.options[1] == mark and lfStorage.options[2] == unmark
    and campMenu.options[#campMenu.options] == lfStorageOption
    and child(lfStorage, mark) and #child(lfStorage, mark).options == 17,
    "a container click puts storage first inside LF while keeping LF at the bottom of the main menu")

-- Use vanilla's actual press/release dispatcher with the real LF menu action.
local priorCell = getCell
local areaDraft, areaDrag, areaBlocked, areaFinished = nil, nil, false, {}
local cell = { getGridSquare = function(_, x, y, z) return T.square(x, y, z) end }
function cell:getDrag() return areaDrag end
function cell:setDrag(value)
    local prior = areaDrag
    areaDrag = value
    if prior and prior ~= value then prior:deactivate() end
end
getCell = function() return cell end
function T.doctor:getPlayerNum() return 0 end
function T.doctor:isBuildButtonDown() return self.buildDown == true end
function T.doctor:isBuildButtonReleased() return self.buildReleased == true end
SC.BaseLife.zoneDraft = function()
    if not areaDraft then return nil end
    return { kind = areaDraft.kind, first = { x = areaDraft.first.x,
        y = areaDraft.first.y, z = areaDraft.first.z } }
end
SC.BaseLife.beginZone = function(kind, square)
    areaDraft = { kind = kind, first = { x = square:getX(), y = square:getY(), z = square:getZ() } }
    return true
end
SC.BaseLife.lockZoneEndpoint = function(square)
    areaDraft.lockedEndpoint = { x = square:getX(), y = square:getY(), z = square:getZ() }
end
SC.BaseLife.cancelZone = function() areaDraft = nil; return true end
SC.BaseLife.finishZone = function(square)
    if areaBlocked then return false, "zone_outside_base_area" end
    areaFinished[#areaFinished + 1] = { first = areaDraft.first, last = square }
    areaDraft = nil
    return true
end
SC.BaseVisuals.refresh = function() end
local areaStart = find(fill({ container }), "UI_SC_Base_Zone_rest")
select(areaStart)
check(areaDrag and areaDraft and #areaFinished == 0,
    "starting an area installs a native cursor without finishing on the menu click")
local function clickArea(x, y, z)
    local cursor, square = areaDrag, T.square(x, y, z)
    T.doctor.buildReleased, T.doctor.buildDown = false, false
    DoTileBuilding(cursor, true, x, y, z, square)
    T.doctor.buildDown = true
    DoTileBuilding(cursor, true, x, y, z, square)
    T.doctor.buildDown, T.doctor.buildReleased = false, true
    DoTileBuilding(cursor, true, x, y, z, square)
    T.doctor.buildReleased = false
end
clickArea(17, 12, 1)
check(areaDraft and areaDrag and #areaFinished == 0, "a click on another floor cannot finish the area")
areaBlocked = true
clickArea(17, 12, 0)
check(areaDraft and areaDrag and #areaFinished == 0, "a rejected rectangle stays editable")
areaBlocked = false
local originalAreaZ = T.doctor.getZ
function T.doctor:getZ() return SC_TEST_BOXED_FLOAT end
clickArea(18, 13, 0)
T.doctor.getZ = originalAreaZ
check(not areaDraft and not areaDrag and #areaFinished == 1
    and areaFinished[1].first.x == groundSquare.x and areaFinished[1].last.x == 18
    and areaFinished[1].last.y == 13, "one native left click finishes the exact area and releases the cursor")
select(areaStart)
check(not find(fill({ container }), "UI_SC_Base_FinishZone"), "area completion no longer requires a context-menu action")
cell:setDrag(nil)
check(not areaDraft and #areaFinished == 1, "native Escape/right-click cancellation leaves no area behind")
select(areaStart)
local olderCursor = areaDrag
select(areaStart)
check(areaDrag ~= olderCursor and areaDraft and areaDrag.draft.first.x == areaDraft.first.x,
    "replacing an area cursor preserves the new draft")
local foreignCursor = { deactivate = function() end }
cell:setDrag(foreignCursor)
olderCursor:update()
check(areaDrag == foreignCursor and not areaDraft, "a stale LF cursor never clears another placement tool")
getCell = priorCell
SC.BaseLife, SC.BaseVisuals, SC.BaseWatch = nil, nil, nil

local household = { id = "household", name = "Neighbours", members = {} }
local oddball = { id = "oddball", name = "Visitor", lifecycle = "settled",
    oddball = { stage = "unmet" }, members = { { actorId = unknown.id } } }
SC.Factions = { list = function(discovered) return discovered and { household } or { oddball } end,
    summary = function() return {} end }
SC.FactionContracts = { canTalk = function() return true end }
SC.Oddballs = { menuOptions = function()
    return { { id = "speak", label = "Ask the visitor", enabled = true } }
end }
local social = fill({ floor })
check(group(social, "households") and group(social, "strange_folk")
    and not find(social, "Ask the visitor", true),
    "available household and Strange Folk conversations retain separate populated groups")
local storyCalls, chatBefore = {}, #opened
oddball.oddball.id, oddball.oddball.stage = "fan_corey_biggs", "following"
SC.Factions.group = function(id) return id == oddball.id and oddball or nil end
local choicesEnabled = true
SC.Oddballs.groupForActor = function() return nil end -- Legacy affiliation flags can be absent.
SC.Oddballs.menuOptions = function()
    return { { id = "ask_diary", label = "Ask what Corey wrote", enabled = choicesEnabled } }
end
SC.Oddballs.storyAction = function(id, action, player, payload)
    storyCalls[#storyCalls + 1] = { id = id, action = action, player = player, payload = payload }
    return true, "fan_diary_recalled"
end
local coreyMenu = fill({ unknown })
local coreyTalk = find(coreyMenu, "talk:" .. unknown.id, true)
local coreyChoices = child(coreyMenu, coreyTalk)
check(coreyChoices and find(coreyChoices, "Ask what Corey wrote", true) and #opened == chatBefore,
    "a clicked unrecruited Strange Folk actor opens authored choices without requiring a roster selection")
local diary = find(coreyChoices, "Ask what Corey wrote", true)
select(diary)
check(#storyCalls == 1 and storyCalls[1].id == oddball.id and storyCalls[1].action == "ask_diary"
    and storyCalls[1].player == T.doctor and #opened == chatBefore,
    "the actual context callback dispatches Corey's diary choice to the exact story and player")
choicesEnabled = false
select(diary)
check(#storyCalls == 1, "a story choice that changed after opening cannot dispatch")
choicesEnabled = true
local previousX = unknown.square.x
unknown.square.x = previousX + 100
select(diary)
check(#storyCalls == 1, "walking away invalidates an old story popup")
unknown.square.x = previousX
local record = records[unknown.id]
records[unknown.id] = { id = unknown.id, actor = a }
select(diary)
check(#storyCalls == 1, "a removed/replaced story actor cannot inherit an old popup")
records[unknown.id] = record
oddball.members = {}
select(diary)
check(#storyCalls == 1, "a person who left this story group cannot use its stale popup")
oddball.members = { { actorId = unknown.id } }
SC.Oddballs.groupForActor = function(value) return value == unknown and oddball or nil end
local resolved = fill({ unknown })
check(child(resolved,find(resolved,"talk:" .. unknown.id,true)) ~= nil,
    "current authored affiliations use the same direct story conversation")
records[unknown.id].factionMember, records[unknown.id].factionId = true, oddball.id
unknown.square.x = T.doctor:getX() + 5
local atTalkRange = fill({ unknown })
check(child(atTalkRange, find(atTalkRange, "talk:" .. unknown.id, true)) ~= nil,
    "a Strange Folk member is directly talkable outside the medical-check range")
unknown.square.x = previousX
records[unknown.id].factionMember, records[unknown.id].factionId = nil, nil
local nestedStory = find(fill({ floor }), "Ask what Corey wrote")
select(nestedStory)
local currentCalls = #storyCalls
choicesEnabled = false
select(nestedStory)
check(#storyCalls == currentCalls, "the nested Strange Folk menu also revalidates an expired choice")
choicesEnabled = nil
local pending = fill({ unknown })
local pendingChoice = find(pending, "Ask what Corey wrote")
check(pendingChoice and pendingChoice.notAvailable,
    "an unmet story prerequisite returning nil cannot expose a selectable choice")
select(diary)
check(#storyCalls == currentCalls, "callbacks also reject nil story availability")
choicesEnabled = true
local oldOptions = SC.Oddballs.menuOptions
SC.Oddballs.menuOptions = function() return {} end
local passiveMenu = fill({ unknown })
local passiveTalk = find(passiveMenu, "talk:" .. unknown.id, true)
check(passiveTalk and passiveTalk.isDisabled and not child(passiveMenu, passiveTalk) and #opened == chatBefore,
    "passive or finished scenes explain that there is no conversation instead of opening an unusable chat")
SC.Oddballs.menuOptions = oldOptions
oddball.lifecycle = "destroyed"
local endedTalk = find(fill({ unknown }), "talk:" .. unknown.id, true)
select(nestedStory)
check(endedTalk and endedTalk.isDisabled and #storyCalls == currentCalls and #opened == chatBefore,
    "an ended scene cannot fall back to companion chat or dispatch a stale story action")
oddball.lifecycle = "settled"
local oldSee, oldRoom12, oldNate = SC.GameplayUtil.canSee, SC.OddballRoom12, SC.OddballDehydrated
SC.GameplayUtil.canSee = function() return false end
for _, name in ipairs({ "OddballRoom12", "OddballDehydrated" }) do
    SC[name] = { canTalkThroughDoor = function(value) return value == oddball end }
    check(find(group(fill({ floor }), "strange_folk"), "Ask what Corey wrote") ~= nil,
        name .. " retains its authored conversation when the closed door blocks sight")
    SC[name] = nil
end
SC.GameplayUtil.canSee, SC.OddballRoom12, SC.OddballDehydrated = oldSee, oldRoom12, oldNate
SC.Factions, SC.FactionContracts, SC.Oddballs = nil, nil, nil

local foreignMenu = root()
local foreignRow = foreignMenu:addOption("UI_SC_Context_LivingFellows", foreignTarget, foreignCallback, "kept")
fill({ a }, false, foreignMenu)
check(foreignMenu.options[1] == foreignRow and foreignRow.onSelect == foreignCallback
    and foreignRow.target == foreignTarget and foreignRow.param1 == "kept"
    and foreignRow.scLFContext == nil, "world fill preserves a foreign row sharing the LF root label")
select(foreignRow)
-- Simulate the native patient row being rebuilt for a new body hit while
-- another hook retains its own row in the root context.
foreignMenu:removeOptionByName("Medical Check")
fill({ b }, false, foreignMenu)
check(not find(foreignMenu, "leaf:" .. a.id .. ":follow", true)
    and not find(foreignMenu, "Talk to Alice", true)
    and find(foreignMenu, "leaf:" .. b.id .. ":follow", true)
    and foreignMenu.options[1] == foreignRow,
    "refilling for another clicked person replaces LF quick actions and preserves foreign rows")

local knownActors, selectedId = actors, SC.UI.instance.selectedId
local oldFactions=SC.Factions
local enemy=actor("hostile-nearby","Hostile household",11,10,false)
records[enemy.id].factionId="hostile-house"
local enemyGroup={id="hostile-house",standing="Hostile"}
SC.Factions={group=function(id) return id==enemyGroup.id and enemyGroup end}
local hostileMenu=fill({enemy})
check(not find(hostileMenu,"talk:"..enemy.id),"a hostile household is absent from nearby Talk choices")
enemyGroup.standing="Wary"
check(find(fill({enemy}),"talk:"..enemy.id),"an ordinary non-hostile household remains available to talk")
actors[#actors]=nil;records[enemy.id]=nil;SC.Factions=oldFactions
actors, SC.UI.instance.selectedId = {}, nil
local emptyWorld = fill({ floor })
check(#emptyWorld.options == 0, "an empty world click never exposes an empty Living Fellows root")
actors, SC.UI.instance.selectedId = knownActors, selectedId

local probe = root()
local untouched = probe:addOption("Native option", foreignTarget, foreignCallback, "kept")
local creationsBefore = T.nativeCreations or 0
fill({ a }, true, probe)
check(#probe.options == 1 and probe.options[1] == untouched and untouched.onSelect == foreignCallback
    and untouched.param1 == "kept" and (T.nativeCreations or 0) == creationsBefore,
    "probe passes leave native rows untouched without allocating menus")

for key, value in pairs(saved) do SC[key] = value end
SC.GameplayUtil, instanceof = oldUtil, oldInstanceof
restoreNative()
SC_TEST_REPORT = "Living Fellows structural context menu: " .. checks .. " checks passed"
