-- SPDX-License-Identifier: MIT
-- Gordon's bunker is an actual basement; the threshold reads vanilla skin
-- blood and dirt and the barter moves the exact items between inventories.
local SC = SurvivorCompanion
SC.OddballGordon = SC.OddballGordon or {}
local Gordon = SC.OddballGordon
local ID = "gordon_pettibone"
local function U() return SC.GameplayUtil end
local function story(group)
    local v = group and group.oddball
    if type(v) ~= "table" or v.id ~= ID then return nil end
    v.trades = math.max(0, tonumber(v.trades) or 0)
    return v
end
local function actorFor(group)
    local m = group and group.members and group.members[1]
    local r = m and m.actorId and SC.Registry and SC.Registry.byId(m.actorId)
    return r and r.actor and U().isValidActor(r.actor) and r.actor or nil
end
local function door(v)
    local p = v and v.site and v.site.bunkerDoor
    local s = p and U().gridSquare(p.x, p.y, p.z)
    local objects = s and select(1, U().call(s, "getObjects"))
    local found = objects and SC.NativeList
        and SC.NativeList.get(objects, p.objectIndex)
    return found and U().instanceOf(found, "IsoDoor") and found or nil
end
local function atDoor(group, player)
    local v = story(group)
    local p = v and v.site and v.site.bunkerOutside
    if not player then return false end
    local x, y, z = U().position(player)
    return actorFor(group) ~= nil and x and p and z == p.z
        and (x-p.x)^2 + (y-p.y)^2 <= 6.25 and door(v) ~= nil
end
local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end
local function clean(player)
    local visual = player and select(1, U().call(player, "getHumanVisual"))
    if not visual or BloodBodyPartType == nil then
        return false, "visual_unavailable"
    end
    local measured = 0
    for index = 0, 16 do
        local part = BloodBodyPartType.FromIndex(index)
        if part then
            local blood, bloodOk = U().call(visual, "getBlood", part)
            local dirt, dirtOk = U().call(visual, "getDirt", part)
            if not bloodOk or not dirtOk then return false, "decon_unavailable" end
            measured = measured + 1
            if (tonumber(blood) or 0) > 0.12
                or (tonumber(dirt) or 0) > 0.12 then
                return false, "decontaminate_first"
            end
        end
    end
    return measured > 0, measured > 0 and "clean" or "visual_unavailable"
end
local function itemFor(actor, kinds)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        200, 8) or {}) do
        if kinds[U().itemType(item)] then return item end
    end
end
function Gordon.onSpawn(group, actor)
    local v = story(group)
    if not v or not actor then return false, "bunker_unavailable" end
    if v.stockSeeded then return true, "stock_present" end
    local inv = U().inventory(actor)
    if not inv then return false, "inventory_unavailable" end
    local pistol = U().addItem(inv, "Base.Pistol")
    if pistol then U().call(actor, "setPrimaryHandItem", pistol) end
    local beans = 0
    for _ = 1, 12 do
        local can = U().addItem(inv, "Base.TinnedBeans")
        if can then
            local data = U().modData(can)
            if data then data.lfGordonStock = true end
            beans = beans + 1
        end
    end
    v.stockSeeded = beans > 0
    return v.stockSeeded, "real_pantry_seeded"
end
function Gordon.canTalkThroughSlot(group, player)
    local v = story(group)
    return v and not v.decontaminated and atDoor(group, player)
        and select(1, U().call(door(v), "IsOpen")) == false or false
end
function Gordon.pulse(group, player)
    local v = story(group)
    if not v then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "bunker_unloaded" end
    if Gordon.canTalkThroughSlot(group, player) and not v.greeted then
        v.greeted = true
        group.discovered = true
        U().say(actor,
            "Twenty years I prepped for the bomb. They sent dead people. Decontaminate first!")
    elseif near(group, player) and not v.metInside then
        v.metInside = true
        group.discovered = true
        U().say(actor,
            "Canned goods, alphabetised, rotated monthly. Most prepared man in Kentucky.")
    end
    return true, v.decontaminated and "bunker_open" or "decon_required"
end
function Gordon.pulseRecruited(group, actor)
    local v = story(group)
    if not v or not actor or v.roleChosen then return false,"bunker_role_idle" end
    local id = U().idOf(actor)
    local base = SC.BaseLife
    local resident = id and base and base.resident and base.resident(id)
    if resident and resident.duty == true then
        -- Existing sort/haul work already spans marked storage on every floor.
        -- Choose that role once; the player may freely change it afterward.
        if resident.role == "generalist" and base.assign then
            local assigned = base.assign(id,"quartermaster",true)
            if assigned then
                v.roleChosen = true
                U().say(actor,
                    "These stores need rotating. Beans before bullets. Alphabetical.")
                return true,"existing_quartermaster_work"
            end
        else
            v.roleChosen = true
        end
    end
    return false,"waiting_for_base_duty"
end
function Gordon.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" then return {mode="hostile",priority=110} end
    local threats = snapshot and (tonumber(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return {mode="zombie_defense",priority=18} end
    return {mode="oddball_idle",priority=28}
end
function Gordon.canRecruit(group)
    local v = story(group)
    return v and v.decontaminated == true and v.trades >= 3
        and group.standing == "Trusted" or false,
        "wash_and_complete_three_real_trades"
end
function Gordon.menuOptions(group, player)
    local v = story(group)
    if not v or not (near(group, player) or atDoor(group, player)) then
        return {} end
    local washed = clean(player)
    local payment = itemFor(player,
        { ["Base.Battery"]=true, ["Base.ElectronicsScrap"]=true })
    local can = itemFor(actorFor(group), { ["Base.TinnedBeans"]=true })
    return {
        { id="decon", label="Show Gordon you washed",
            enabled=not v.decontaminated and washed },
        { id="ask_bomb", label="Ask about the wrong apocalypse", enabled=true },
        { id="trade", label="Trade a battery or radio part for beans",
            enabled=v.decontaminated and payment ~= nil and can ~= nil },
        { id="recruit", label="Invite Gordon and his suit to camp",
            enabled=Gordon.canRecruit(group)==true },
    }
end
function Gordon.action(group, action, player)
    local v = story(group)
    if not v then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile") end
    if not (near(group, player) or atDoor(group, player)) then
        return false, "bunker_too_far" end
    local actor = actorFor(group)
    if action == "decon" and not v.decontaminated then
        local washed, reason = clean(player)
        if not washed then
            U().say(actor, "Wash it off. I can see the blood from here.")
            return false, reason
        end
        local entry = door(v)
        if not entry then return false, "bunker_door_unloaded" end
        U().call(entry, "setLocked", false)
        if select(1, U().call(entry, "IsOpen")) == false then
            U().call(entry, "ToggleDoor", actor)
        end
        if select(1, U().call(entry, "IsOpen")) ~= true then
            return false, "bunker_door_did_not_open"
        end
        v.decontaminated = true
        SC.Factions.adjustStanding(group.id, 10, "real_decontamination")
        U().say(actor,
            "All right. Come in. Duck and cover won't help now; I checked.")
        return true, "bunker_opened_after_washing"
    end
    if action == "ask_bomb" then
        local lines = {
            "Iodine pills, a shelter, a radiation meter. Useless. All of it useless.",
            "Commies, ready. Meteors, ready. Dead people walking? Come on.",
            "I'll trade a can of beans for news. Real news. Not radio news.",
        }
        v.line = ((tonumber(v.line) or 0) % #lines) + 1
        U().say(actor, lines[v.line])
        return true, "gordon_spoke"
    end
    if action == "trade" and v.decontaminated then
        local payment = itemFor(player,
            { ["Base.Battery"]=true, ["Base.ElectronicsScrap"]=true })
        local can = itemFor(actor, { ["Base.TinnedBeans"]=true })
        local source = payment and select(1, U().call(payment,"getContainer"))
        local stock = can and select(1, U().call(can,"getContainer"))
        local target, playerInv = U().inventory(actor), U().inventory(player)
        if not source or not stock then return false, "stock_or_parts_missing" end
        if not U().transferItemVerified(source,target,payment) then
            return false, "parts_transfer_failed" end
        if not U().transferItemVerified(stock,playerInv,can) then
            U().transferItemVerified(target,source,payment)
            return false, "beans_transfer_failed"
        end
        v.trades = v.trades + 1
        if v.trades >= 3 then SC.Factions.forceStanding(group.id,"Trusted")
        else SC.Factions.adjustStanding(group.id,12,"bunker_trade") end
        U().say(actor, "A can for your news. Shelves still have a few.")
        return true, "real_bunker_trade"
    end
    if action == "recruit" and Gordon.canRecruit(group)==true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id,player,false)
        if not asked then return false,reason end
        U().say(actor,
            "Fine. But the suit comes. The suit stays on. Don't ask about the suit.")
        return SC.FactionRecruitment.startTrial(group.id,player,false)
    end
    return false, "bunker_choice_unavailable"
end
return Gordon
