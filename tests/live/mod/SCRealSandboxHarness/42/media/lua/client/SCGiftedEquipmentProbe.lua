-- SPDX-License-Identifier: MIT
-- Real Build 42 equipment check in a disposable cloned save.
local Probe = {}

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function safeSpawnSquare(square, utility)
    if not square or not utility.isSquareFree(square) then return false end
    return call(square, "isFree", true) ~= false
        and call(square, "isSafeToSpawn") ~= false
end

local function adjacentPair(player, utility)
    local x, y, z = tonumber(call(player, "getX")),
        tonumber(call(player, "getY")), tonumber(call(player, "getZ"))
    if not x or not y or not z then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local offsets = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
    for radius = 1, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if safeSpawnSquare(square, utility) then
                        for _, offset in ipairs(offsets) do
                            local view = utility.gridSquare(x + dx + offset[1],
                                y + dy + offset[2], z)
                            if safeSpawnSquare(view, utility) then
                                return square, view
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function isWearing(actor, item)
    local worn = call(actor, "getWornItems")
    local count = worn and call(worn, "size") or 0
    for index = 0, math.min(tonumber(count) or 0, 64) - 1 do
        if call(call(worn, "get", index), "getItem") == item then return true end
    end
    return false
end

local function movePlayerBeside(player, actor, utility)
    local x, y, z = math.floor(actor:getX()), math.floor(actor:getY()),
        math.floor(actor:getZ())
    for _, offset in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
        local square = utility.gridSquare(x + offset[1], y + offset[2], z)
        if safeSpawnSquare(square, utility) then
            local moved = pcall(function()
                player:teleportTo(square:getX() + 0.5, square:getY() + 0.5,
                    square:getZ())
            end)
            if moved and (tonumber(call(player, "DistTo", actor)) or 99) <= 1.9 then
                return true
            end
        end
    end
    return false
end

local function transferred(player, actor, item)
    local source, destination = player:getInventory(), actor:getInventory()
    local ok, result = pcall(ISTransferAction.transferItem,
        ISTransferAction, player, item, source, destination, nil)
    return ok and result == item and item:getContainer() == destination
        and SurvivorCompanion.GameplayUtil.inventoryContains(destination, item)
        and not SurvivorCompanion.GameplayUtil.inventoryContains(source, item)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "gifted_equipment_setup" then
        -- Let the cloned save clear its load prompts before moving the observer.
        if current - H.phaseStartedAt < 22000 then return end
        local square, view = adjacentPair(H.player, SC.GameplayUtil)
        if not check("gifted_equipment_spawn_square", square ~= nil,
            "free tile beside local player") then
            setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "Gear", surname = "Tester",
                gender = "man", outfit = "Generic01" },
        })
        if not check("gifted_equipment_spawn_requested", ticket ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.giftedEquipmentTicket, H.giftedEquipmentView = ticket, view
        setPhase("gifted_equipment_spawn", current)
        return
    end
    if H.phase == "gifted_equipment_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.giftedEquipmentTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                result("FAIL", "gifted_equipment_spawn", tostring(reason))
                setPhase("finish", current)
            end
            return
        end
        H.giftedEquipmentActor = actor
        local view = H.giftedEquipmentView
        local positioned = pcall(function()
            H.player:teleportTo(view:getX() + 0.5, view:getY() + 0.5,
                view:getZ())
        end)
        if not check("gifted_equipment_player_adjacent", positioned
            and (tonumber(call(H.player, "DistTo", actor)) or 99) <= 2.5,
            "player beside recruited companion") then
            setPhase("finish", current) return
        end
        local id = SC.Registry.idOf(actor)
        local following, followReason = SC.Commands.issue(id, "follow", nil, H.player)
        if not check("gifted_equipment_follow_order", following == true,
            tostring(followReason)) then
            setPhase("finish", current) return
        end
        actor:setPrimaryHandItem(nil)
        actor:setSecondaryHandItem(nil)
        local opened, openReason = SC.UIBridge.openInventory(actor, H.player)
        if not check("gifted_equipment_inventory_open", opened == true,
            tostring(openReason)) then
            setPhase("finish", current) return
        end
        local source = H.player:getInventory()
        local types = {
            "Base.Crowbar",
            "Base.Hat_HockeyHelmet",
            "Base.Shoulderpads_IceHockey",
            "Base.IceHockeyNeckGuard",
            "Base.Shorts_HockeyPants",
        }
        H.giftedEquipmentItems = {}
        local allMoved = true
        for _, fullType in ipairs(types) do
            local item = source:AddItem(fullType)
            if item and fullType == "Base.Hat_HockeyHelmet" then
                call(item, "setFavorite", true)
            end
            local moved = item and transferred(H.player, actor, item)
            H.giftedEquipmentItems[fullType] = item
            allMoved = allMoved and moved == true
        end
        SC.UIBridge.restoreInventory()
        if not check("gifted_equipment_vanilla_transfer", allMoved,
            "same native items moved player to companion") then
            setPhase("finish", current) return
        end
        setPhase("gifted_equipment_wait", current)
        return
    end
    if H.phase == "gifted_equipment_wait" then
        if current - H.phaseStartedAt < 30000 then return end
        local actor, items = H.giftedEquipmentActor, H.giftedEquipmentItems
        local crowbar = items["Base.Crowbar"]
        check("gifted_equipment_favorite_retained",
            call(items["Base.Hat_HockeyHelmet"], "isFavorite") == true,
            "gifted helmet remains favorited")
        check("gifted_equipment_crowbar_in_hand",
            actor:getPrimaryHandItem() == crowbar,
            "native primary hand owns gifted crowbar")
        for _, fullType in ipairs({ "Base.Hat_HockeyHelmet",
            "Base.Shoulderpads_IceHockey", "Base.IceHockeyNeckGuard",
            "Base.Shorts_HockeyPants" }) do
            check("gifted_equipment_worn_" .. fullType,
                isWearing(actor, items[fullType]),
                "exact gifted item is in native worn list")
        end
        local imageName = tostring(H.config.run_id) .. "-gifted-equipment.png"
        local captured = pcall(function()
            getCore():TakeFullScreenshot(imageName)
        end)
        check("gifted_equipment_screenshot", captured, imageName)
        setPhase("gifted_equipment_manual", current)
        return
    end
    if H.phase == "gifted_equipment_manual" then
        local actor = H.giftedEquipmentActor
        if not check("gifted_equipment_player_rejoined",
            movePlayerBeside(H.player, actor, SC.GameplayUtil),
            "observer returned to companion after autonomous Follow") then
            setPhase("finish", current) return
        end
        local root = actor:getInventory()
        local bag = root:AddItem("Base.Bag_Schoolbag")
        local bagInventory = bag and bag:getInventory()
        local hammer = bagInventory and bagInventory:AddItem("Base.Hammer")
        if not check("gifted_equipment_nested_fixture", hammer ~= nil,
            "hammer added inside companion bag") then
            setPhase("finish", current) return
        end
        local ok, equipped, reason = pcall(SC.UIBridge.equipOnCompanion,
            actor, hammer, H.player, "weapon")
        H.giftedEquipmentForced = hammer
        if not check("gifted_equipment_manual_override", ok and equipped == true
            and actor:getPrimaryHandItem() == hammer,
            tostring(reason) .. " exact nested item="
                .. tostring(actor:getPrimaryHandItem() == hammer)) then
            setPhase("finish", current) return
        end
        setPhase("gifted_equipment_override_wait", current)
        return
    end
    if H.phase == "gifted_equipment_override_wait" then
        if current - H.phaseStartedAt < 3500 then return end
        check("gifted_equipment_override_retained",
            H.giftedEquipmentActor:getPrimaryHandItem()
                == H.giftedEquipmentForced,
            "manual exact-item choice persists across decision beats")
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCGiftedEquipmentProbe = Probe

return Probe
