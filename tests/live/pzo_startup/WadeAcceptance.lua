-- SPDX-License-Identifier: MIT
-- Run in a disposable PZO save using the ordinary native actor and radio paths.
local SC = LivingFellows
local ID = "wade_hensley"
local state = { phase = "menu" }
local ORIGINS = { { 6362, 6416 }, { 7475, 6692 }, { 6383, 7644 }, { 6680, 5227 },
    { 6880, 5232 }, { 10134, 6770 }, { 5580, 5290 }, { 5340, 5355 } }

local function write(name, text)
    local file = assert(getFileWriter(name, true, false))
    file:write(text .. "\n")
    file:close()
end

local function read(name)
    local file = getFileReader(name, false)
    local text = file and file:readLine()
    if file then file:close() end
    return text
end

local function phase(name)
    state.phase, state.since = name, getTimestampMs()
    write("wade-progress.txt", name)
    print("SC_PZO_WADE " .. name)
end

local function finish(result, reason)
    state.done = true
    write("wade-result.txt", "result=" .. result .. "\nmode=" .. state.mode .. "\nphase=" .. state.phase
        .. "\nreason=" .. tostring(reason) .. "\ncast_to_bite_ms=" .. tostring(state.biteMillis or 0))
end

local function encounter()
    for _, group in ipairs(SC.Factions.list(false)) do
        if group.oddball and group.oddball.id == ID then return group end
    end
end

local function findItem(actor, id)
    return SC.OddballKit.itemWhere(actor, function(_, item)
        return SC.GameplayUtil.itemStableId(item, false) == id
    end, 500, 32)
end

local function bankDetails(square)
    local cast = SC.Fishing.usableBank(square)
    local trees, loaded, buildings, roads, forest, maxSize = 0, 0, 0, 0, 0, 0
    for inland = 0, 10 do
        for side = -10, 10 do
            local distance = inland * inland + side * side
            if distance <= 100 then
                local tile = getCell():getGridSquare(cast.bank.x - cast.dx * inland + cast.dy * side,
                    cast.bank.y - cast.dy * inland - cast.dx * side, 0)
                if tile then
                    loaded = loaded + 1
                    local tree = tile:getTree()
                    if tree then trees, maxSize = trees + 1, math.max(maxSize, tree:getSize()) end
                    if tile:getBuilding() then buildings = buildings + 1 end
                    local floor, zone = tile:getFloor(), tile:getZone()
                    local name = floor and floor:getSprite() and floor:getSprite():getName()
                    if zone and tostring(zone:getType()):find("Forest", 1, true) then forest = forest + 1 end
                    if distance <= 25 and name and (name:find("^blends_street_") or name:find("^floors_exterior_street_")
                        or name:find("^street_curbs_")) then roads = roads + 1 end
                end
            end
        end
    end
    print("SC_PZO_WADE bank survey=" .. cast.bank.x .. "," .. cast.bank.y .. "," .. cast.dx .. "," .. cast.dy
        .. " loaded=" .. loaded .. " trees=" .. trees .. " maxSize=" .. maxSize
        .. " forest=" .. forest .. " buildings=" .. buildings .. " roads=" .. roads)
end

local function findBank(player)
    local origin = ORIGINS[state.shore]
    for _ = 1, 38 do
        local index = state.scan or 0
        state.scan = index + 1
        if index >= 1400 then
            local summary = {}
            for key, count in pairs(state.selection or {}) do summary[#summary + 1] = key .. "=" .. count end
            print("SC_PZO_WADE shore=" .. origin[1] .. "," .. origin[2] .. " " .. table.concat(summary, " "))
            state.selection = nil
            state.shore = state.shore + 1
            local nextOrigin = ORIGINS[state.shore]
            assert(nextOrigin, "no loaded wooded riverbank passed site selection")
            player:teleportTo(nextOrigin[1] + 0.5, nextOrigin[2] + 0.5, 0)
            state.scan = 0
            phase("shore-load")
            return nil
        end
        local angle = index * 2.399963229728653
        local radius = 35 + (index * 19 % 45)
        local x = math.floor(origin[1] + math.cos(angle) * radius)
        local y = math.floor(origin[2] + math.sin(angle) * radius)
        local square = getCell():getGridSquare(x, y, 0)
        local site, why
        if square then site, why = SC.OddballWade.siteFor(square, player, true) end
        if site then return site end
        why = why or (square and "other" or "unloaded")
        state.selection = state.selection or {}
        if (why == "bank_not_secluded" or why == "bank_no_canoe_tree") and (state.selection[why] or 0) < 3 then
            bankDetails(square)
        end
        state.selection[why] = (state.selection[why] or 0) + 1
    end
end

local function canoe(group)
    local post = group.oddball.site.canoePost
    local square = getCell():getGridSquare(post.x, post.y, post.z)
    local objects = square and square:getObjects()
    local count = 0
    for i = 0, objects and objects:size() - 1 or -1 do
        local object = objects:get(i)
        if object:getModData().LF_WadeCanoeOwner == group.id then
            assert(object:getSprite() and object:getSprite():getName(), "canoe has no visible sprite")
            count = count + 1
        end
    end
    assert(count == 1, "expected exactly one canoe at the bank")
end

local function checkOutfit(actor)
    local clothing = {
        ["Base.Hat_FishermanRainHat"] = true, ["Base.Dungarees"] = true,
        ["Base.Shoes_Wellies"] = true, ["Base.Shirt_Lumberjack"] = true,
    }
    local function observe(object, method, ...)
        local value, okay = SC.GameplayUtil.call(object, method, ...)
        assert(okay, "native wardrobe method unavailable: " .. method)
        return value
    end
    local worn = observe(actor, "getWornItems")
    for index = 0, observe(worn, "size") - 1 do
        local item = assert(observe(worn, "getItemByIndex", index), "missing outfit inventory item")
        local kind = observe(item, "getFullType")
        if kind == "Base.Shirt_Lumberjack" then
            assert(observe(observe(item, "getVisual"), "getBaseTexture") == 3, "Wade's flannel is not red")
        end
        clothing[kind] = nil
    end
    for missing in pairs(clothing) do error("Wade's native clothes are incomplete: " .. missing) end
    assert(observe(observe(actor, "getHumanVisual"), "getBeardModel") == "Full", "Wade's native beard differs")
end

local function pauseAt(group, stage)
    local pulse = SC.OddballWade.pulse
    SC.OddballWade.pulse = function(current, ...)
        if current == group and current.oddball.stage == stage then return true, "fixture_checkpoint" end
        return pulse(current, ...)
    end
    assert(SC.Persistence.save(state.player))
    save(false)
    phase("disk-save")
end

Events.OnInitGlobalModData.Add(function()
    if read("wade-mode.txt") == "offer" then
        ModData.getOrCreate(SC.Identity.worldSaveKey).document = {
            schema = SC.Identity.saveSchema, companions = {}, factionActors = {},
        }
    end
end)
Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
local shown = {}
Events.OnRenderTick.Add(function()
    local modal = MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not shown[modal] then shown[modal] = true; modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    state.mode = read("wade-mode.txt") or "offer"
    state.player = assert(getSpecificPlayer(0))
    if state.mode == "offer" then
        state.shore = 1
        state.player:teleportTo(ORIGINS[1][1] + 0.5, ORIGINS[1][2] + 0.5, 0)
    end
    local begin = SC.Fishing.beginScriptedCast
    SC.Fishing.beginScriptedCast = function(actor, site, rod, token, onHook)
        state.attempts = (state.attempts or 0) + 1
        local okay, reason = begin(actor, site, rod, token, function(...)
            state.hooks = (state.hooks or 0) + 1
            state.biteMillis = getTimestampMs() - assert(state.splashAt, "hook preceded bobber placement")
            return onHook(...)
        end)
        if okay then state.fisher, state.token = actor, token end
        print("SC_PZO_WADE cast " .. tostring(okay) .. " " .. tostring(reason))
        return okay, reason
    end
    local say = SC.GameplayUtil.say
    SC.GameplayUtil.say = function(actor, line)
        local group = actor and SC.Oddballs.groupForActor(actor)
        if group and group.oddball.id == ID then
            state.lines = state.lines or {}
            state.lines[#state.lines + 1] = line
            print("SC_PZO_WADE line " .. line)
        end
        return say(actor, line)
    end
    phase("load")
end)

local function step()
    local now = getTimestampMs()
    local player = state.player
    if state.fisher then
        local cast = SC.Fishing.scriptedCastStatus(state.fisher, state.token)
        if cast == "waiting" and not state.splashAt then
            state.splashAt = now
            print("SC_PZO_WADE splash")
        end
    end
    if state.phase == "load" or state.phase == "shore-load" then
        if now - state.since < (state.phase == "load" and 11000 or 5000) then return end
        assert(PZOEngine and SCBridge and SC.OddballWade, "real game or Wade module unavailable")
        if state.mode == "offer" then
            if not state.receiverStarted then
                state.receiverStarted = now
                player:setPrimaryHandItem(nil)
                player:setSecondaryHandItem(nil)
            end
            local powered, why = SC.OddballDistressRadio.provisionRadio(player, true)
            if not powered then
                if not state.receiverTrace then
                    state.receiverTrace = true
                    local item = player:getSecondaryHandItem()
                    local data = item and item:getDeviceData()
                    print("SC_PZO_WADE receiver=" .. tostring(why) .. " exact="
                        .. tostring(item ~= nil and player:getEquipedRadio() == item)
                        .. " turnedOn=" .. tostring(data and data:getIsTurnedOn())
                        .. " power=" .. tostring(data and data:getPower())
                        .. " channel=" .. tostring(data and data:getChannel()))
                end
                assert(now - state.receiverStarted < 10000, why)
                return
            end
            phase("site")
        else
            phase("resume")
        end
    elseif state.phase == "site" then
        local site = findBank(player)
        if not site then return end
        state.group = assert(SC.Factions.createOddballGroup(site, SC.Oddballs.definition(ID), true))
        print("SC_PZO_WADE bank=" .. site.spawn.x .. "," .. site.spawn.y)
        phase("radio")
    elseif state.phase == "radio" then
        local group = state.group
        local story, actor = group.oddball, SC.OddballKit.livingActor(group, 1)
        if not actor or not story.rodId or not story.radioSeeded then return end
        if not state.checkedScene then
            canoe(group)
            local dressed, outfitProblem = pcall(checkOutfit, actor)
            print("SC_PZO_WADE outfit=" .. tostring(dressed) .. " " .. tostring(outfitProblem))
            state.outfitProblem = not dressed and outfitProblem or nil
            state.checkedScene = true
        end
        if not story.radioHeard then return end
        assert(SC.OddballDistressRadio.answer(group.id, player), "native radio reply rejected")
        assert(story.radioAnswered and story.radioMapText == "Wade's fishing camp", "missing authored map marker")
        local spot = story.site.bankEscape[2]
        player:teleportTo(spot.x + 0.5, spot.y + 0.5, 0)
        player:faceLocationF(actor:getX(), actor:getY())
        phase("offer")
    elseif state.phase == "offer" then
        local group = state.group
        if not group.oddball.greeted then return end
        local inventory = player:getInventory()
        local choice = assert(SC.OddballWade.menuOptions(group, player)[1])
        assert(choice.enabled ~= true, "Wade offered a trade without line")
        local empty = assert(inventory:AddItem("Base.PremiumFishingLine"))
        empty:setUsedDelta(0)
        assert(not SC.Oddballs.storyAction(group.id, "offer_line", player), "Wade accepted an empty spool")
        local line = assert(inventory:AddItem("Base.FishingLine"))
        local id = assert(SC.GameplayUtil.itemStableId(line, true))
        assert(SC.Oddballs.storyAction(group.id, "offer_line", player, choice.payload))
        assert(group.oddball.lineId == id and not inventory:contains(line) and inventory:contains(empty), "wrong spool transferred")
        assert(not SC.Oddballs.storyAction(group.id, "offer_line", player), "Wade accepted a second trade")
        pauseAt(group, "accepted")
    elseif state.phase == "resume" then
        local group = encounter()
        if not group then return end
        local story, actor = group.oddball, SC.OddballKit.livingActor(group, 1)
        if not actor then return end
        canoe(group)
        assert(not findItem(player, story.lineId), "spool came back after reload")
        state.group = group
        phase(state.mode == "catch" and "catch" or "supper")
    elseif state.phase == "catch" then
        local group, story = state.group, state.group.oddball
        local actor = SC.OddballKit.livingActor(group, 1)
        if story.stage ~= "release" then return end
        assert(state.hooks == 1 and state.biteMillis >= 5800 and state.biteMillis <= 6400, "native bite outside the six-second window")
        assert(findItem(actor, story.bassId):getFullType() == "Base.SmallmouthBass", "native bass missing")
        assert(findItem(actor, story.lureId):getFullType() == "Base.JigLure", "recovered lure missing")
        assert(state.lines and state.lines[#state.lines]:find("There's my lure", 1, true), "lure line did not follow the catch")
        pauseAt(group, "release")
    elseif state.phase == "supper" then
        local group, story = state.group, state.group.oddball
        if story.stage ~= "complete" then return end
        local actor = SC.OddballKit.livingActor(group, 1)
        assert(state.attempts == nil and state.hooks == nil, "recorded catch replayed")
        assert(not findItem(actor, story.bassId) and findItem(actor, story.lureId), "bass release or lure retention failed")
        assert(findItem(player, story.filletId):getFullType() == "Base.FishFillet"
            and not findItem(actor, story.filletId), "reward missing or duplicated")
        assert(state.lines and state.lines[#state.lines - 1] == "That one and me are even now."
            and state.lines[#state.lines] == "Here. Cleaned this one this morning.", "release and reward lines out of order")
        pauseAt(group, "complete")
    elseif state.phase == "disk-save" and now - state.since >= 6500 then
        if state.outfitProblem then finish("FAIL", state.outfitProblem)
        else finish("PASS", state.group.oddball.stage) end
    end
    assert(now - state.since < 120000, "timed out at " .. state.phase)
end

Events.OnTick.Add(function()
    if state.done or state.phase == "menu" then return end
    local okay, reason = pcall(step)
    if not okay then finish("FAIL", reason) end
end)
