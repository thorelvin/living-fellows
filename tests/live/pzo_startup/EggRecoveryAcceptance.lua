-- SPDX-License-Identifier: MIT
-- Run in a disposable native save. The seed leaves a genuine selected receipt
-- on disk between the player's pickup and the farmer's next update.
require "TimedActions/Animals/ISHutchGrabEgg"

local SC = LivingFellows
local B, W, A, U = SC.BaseLife, SC.FarmWork, SC.AnimalWork, SC.GameplayUtil
local s = { phase = "menu", notes = {}, modals = {} }

local function write(name, contents)
    local f = assert(getFileWriter("pzo-egg-" .. name .. ".txt", true, false))
    f:write(contents .. "\n")
    f:close()
end

local function read(path)
    local f = assert(getFileReader(path, false))
    local result = f:readLine()
    f:close()
    return result
end

local function note(key, value)
    s.notes[#s.notes + 1] = key .. "=" .. tostring(value)
end

local function phase(label)
    s.phase, s.deadline, s.detail = label, getTimestampMs() + 65000, nil
    write("progress", label .. "\n" .. table.concat(s.notes, "\n"))
end

local function finish(result, reason)
    write("result", "result=" .. result .. "\nphase=" .. s.phase .. "\nreason=" .. tostring(reason)
        .. "\ndetail=" .. tostring(s.detail) .. "\n" .. table.concat(s.notes, "\n"))
    s.phase = "done"
end

local function penSite(player)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    for radius = 0, 30, 3 do
        for dx = -radius, radius, 3 do
            for dy = -radius, radius, 3 do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local clear = true
                    for xx=px+dx,px+dx+6 do
                        for yy=py+dy,py+dy+6 do
                            local q = getSquare(xx, yy, 0)
                            if not q or not q:isOutside() or not U.isSquareFree(q)
                                or U.squareOccupyingObject(q) or q:isVehicleIntersecting() then
                                clear = false
                                break
                            end
                        end
                        if not clear then break end
                    end
                    if clear then return px+dx, py+dy end
                end
            end
        end
    end
    error("no loaded outdoor pen site")
end

local function zone(kind, a, b)
    assert(B.beginZone(kind, a))
    local ok, z = B.finishZone(b, "Egg test " .. kind)
    assert(ok, tostring(z))
    return z
end

local function makeEgg()
    local egg = assert(s.hen:createEgg())
    egg:setFertilized(false)
    s.nest:addEgg(egg)
    assert(s.nest:getEggsNb() == 1 and s.nest:getEgg(0) == egg)
    return egg
end

local function seed()
    B.reset()
    local x, y = penSite(s.player)
    local function sq(dx, dy) return getSquare(x+dx, y+dy, 0) end
    assert(B.create(sq(3, 3), "Hen house"))
    zone("area", sq(0, 0), sq(6, 6))
    s.zoneId = zone("farm", sq(2, 2), sq(4, 4)).id
    assert(B.setPolicy("autoMaintenance", false))
    getGameTime():setTimeOfDay(10)
    s.pen = DesignationZoneAnimal.new("Egg acceptance", x+1, y+1, 0, x+6, y+6, true)
    local def = HutchDefinitions.hutchs.hutchhen
    s.hutch = IsoHutch.new(sq(3, 3), false, def.baseSprite, def, nil)
    if s.hutch:isDoorClosed() then s.hutch:toggleDoor() end
    if s.hutch:isEggHatchDoorClosed() then s.hutch:toggleEggHatchDoor() end
    s.nest = assert(s.hutch:getNestBox(0))
    local crate = IsoThumpable.new(getCell(), sq(1, 3), "carpentry_01_16", false, {})
    crate:setIsContainer(true)
    crate:setContainer(ItemContainer.new("crate", sq(1, 3), crate))
    crate:getContainer():setCapacity(50)
    crate:getContainer():setExplored(true)
    sq(1, 3):AddSpecialObject(crate)
    assert(B.registerStorage(crate, "fresh_food"))
    s.crate = crate:getContainer()
    local breed = assert(AnimalDefinitions.getDef("hen"):getBreedByName("rhodeisland"))
    s.hen = assert(addAnimal(getCell(), x+4.5, y+4.5, 0, "hen", breed, false))
    s.hen:addToWorld()
    s.hen:setWild(false)
    s.hen:setDZone(s.pen)
    s.pen:addAnimal(s.hen)
    s.pen:check()
    s.egg = makeEgg()
    s.player:teleportTo(x+4.5, y+3.5, 0)
    note("hutch", tostring(s.hutch:getX()) .. "," .. tostring(s.hutch:getY()))
    s.ticket = assert(SC.Actor.beginSpawn(sq(3, 4), {recruited=true,
        identity={forename="Perry", surname="Farmer", gender="man", outfit="Generic01"}}))
    phase("spawn")
end

local function obtain(operation)
    local job
    for _, candidate in ipairs(B.active().jobs) do
        if candidate.target and candidate.target.operation == operation then job = candidate break end
    end
    if not job then
        local target, why = A.candidate(B.active(), 16)
        s.detail = why or (target and target.operation)
        if not target or target.operation ~= operation then return end
        local ok
        ok, job = B.enqueueJob({type="farm", priority=target.priority, target=target})
        assert(ok, tostring(job))
    end
    local claimed, why = B.claimJob(s.actorId, function(candidate) return candidate.id == job.id end)
    assert(claimed and claimed.id == job.id, tostring(why))
    return job
end

local function tickJob()
    local ok, detail = W.update(s.actor, {}, s.job, U.peekActorState(s.actor))
    s.detail = detail
    assert(ok == true, tostring(detail))
end

local function eggCount(egg)
    local kind = egg:getFullType()
    return s.nest:getEggsNb() + s.player:getInventory():getCountTypeRecurse(kind)
        + s.actor:getInventory():getCountTypeRecurse(kind) + s.crate:getCountTypeRecurse(kind)
end
local function queuePickup()
    local action = ISHutchGrabEgg:new(s.player, s.nest, s.hutch)
    assert(action:isValid())
    -- 42.22.2 waitToStart reads this unset facing target in the stock action.
    action.tree = s.hutch
    local stockUpdate, taken = action.update, false
    action.update = function(self)
        if s.phase == "done" then return end
        if taken or self.timer + getGameTime():getMultiplier() < self.timePerEgg then
            stockUpdate(self)
            return
        end
        -- Start the farmer on the last tick before the queued player action
        -- removes egg zero. Each actor uses the game's timed-action queue.
        local ok, why = pcall(function()
            if not s.job.target.eggReceiptId then
                tickJob()
                -- Changing chores can consume one update returning the previous
                -- farmer runtime before the selected job can start.
                if not s.job.target.eggReceiptId and s.detail == "farm_previous_supplies_returned" then
                    tickJob()
                end
            end
            local id = assert(s.job.target.eggReceiptId, "farmer did not select egg: " .. tostring(s.detail))
            local receipt = assert(B.farmReceipt(id))
            assert(receipt.phase == "selected" and tostring(receipt.nativeId) == tostring(s.egg:getID()))
            assert(s.egg:getModData()[W.ITEM_MARKER] == id and W.canCancelJob(s.job.id) == false)
            assert(s.nest:getEgg(0) == s.egg and SC.NativeActions.isWorkActive(s.actor))
            s.eggsBeforePickup = eggCount(s.egg)
            stockUpdate(self)
            assert(s.nest:getEggsNb() == 0 and s.player:getInventory():contains(s.egg))
            assert(not s.actor:getInventory():contains(s.egg) and not s.crate:contains(s.egg))
            assert(eggCount(s.egg) == s.eggsBeforePickup, "native pickup changed total egg count")
            note(s.phase .. "_selection", id .. " / native egg " .. tostring(s.egg:getID()))
            s.receipt, taken = receipt, true
        end)
        if not ok then finish("FAIL", why) end
    end
    s.action = action
    ISTimedActionQueue.add(action)
end

local function assertReleased(receipt, egg)
    assert(receipt.phase == "consumed" and receipt.blocker == "animal_egg_taken_elsewhere",
        tostring(receipt.phase) .. "/" .. tostring(receipt.blocker))
    assert(W.isItemProtected(egg, s.actorId, "transfer") == false and not egg:getModData()[W.ITEM_MARKER])
    assert(W.canCancelJob(receipt.jobId) and #B.farmReceipts(receipt.jobId, false) == 0)
end

local function completed(id)
    for _, entry in ipairs(B.active().completed) do
        if entry.id == id and entry.actorId == s.actorId then return true end
    end
    return false
end

local function seedDisk(receipt)
    assert(SC.Persistence.save(s.player))
    save(false)
    assert(B.farmReceipt(receipt.id).phase == "selected" and s.job.target.eggReceiptId == receipt.id)
    write("ids", table.concat({s.actorId, s.job.id, receipt.id, s.zoneId, tostring(s.egg:getID())}, " "))
    assert(SCSplitScreenProbe.flushGlobalModDataForWorldExit())
    note("on_disk", "living farmer, selected exact egg in player inventory, outstanding job")
    finish("PASS", "player took two selected eggs, farmer cancelled first chore and completed another")
end

local function restore()
    local row = SC.Registry.byId(s.actorId)
    if not row or not row.actor then return end
    s.actor = row.actor
    if not B.resident(s.actorId) then return end
    local receipt = B.farmReceipt(s.receiptId)
    assert(receipt and receipt.actorId == s.actorId, "selected receipt missing on disk")
    local job = B.job(s.jobId)
    if not s.restored then
        assert(job and job.target.eggReceiptId == s.receiptId and not s.actor:isDead())
        assert(W.canCancelJob(job.id) == false, "restored live receipt must block cancellation")
        assert(receipt.phase == "selected", "receipt already " .. tostring(receipt.phase))
        local items = s.player:getInventory():getItems()
        for i=0,items:size()-1 do
            local item=items:get(i)
            if item:getModData()[W.ITEM_MARKER] == receipt.id then
                assert(not s.egg and tostring(item:getID()) == s.nativeId)
                s.egg = item
            end
        end
        assert(s.egg and not s.actor:getInventory():contains(s.egg))
        note("before_audit", receipt.phase .. " / " .. receipt.id .. " / native egg " .. s.nativeId)
        s.restored, s.auditCount = true, 0
    end
    if receipt.phase == "selected" then
        W.audit(B.active())
        s.auditCount = s.auditCount + 1
        assert(s.auditCount <= 256, "the restored selected receipt survived 256 bounded audits")
        return
    end
    assertReleased(receipt, s.egg)
    if job then
        s.job = job
        local claimed, why = B.claimJob(s.actorId, function(candidate) return candidate.id == job.id end)
        assert(claimed and claimed.id == job.id, tostring(why))
        tickJob()
        return
    end
    assert(completed(s.jobId))
    assert(B.removeZone(s.zoneId))
    for _, remaining in ipairs(B.active().zones) do assert(remaining.id ~= s.zoneId) end
    note("recovery", receipt.blocker .. " after " .. s.auditCount .. " bounded audit calls")
    note("zone_removed", s.zoneId)
    finish("PASS", "loaded selected egg closed, farmer finished the chore, player retained the unprotected egg")
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture") end)
Events.OnGameStart.Add(function() phase("start") end)
local function step()
    if s.phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not s.modals[modal] then
            s.modals[modal] = true
            modal:onClick(modal.yes)
        end
        return
    end
    assert(getTimestampMs() < s.deadline, "timed out " .. tostring(s.detail))
    if s.phase == "start" then
        local player = getSpecificPlayer(0)
        if not player or not player:getSquare() or not SC.Persistence.restoreStatus() then return end
        s.player = player
        if read("pzo-world-mode.txt") == "disk-restored" then
            s.actorId, s.jobId, s.receiptId, s.zoneId, s.nativeId =
                read("pzo-egg-ids.txt"):match("^(%S+) (%S+) (%S+) (%S+) (%S+)$")
            assert(s.nativeId)
            phase("reload")
        else seed() end
    elseif s.phase == "spawn" then
        local actor, why = SC.Actor.pollSpawn(s.ticket)
        assert(actor or why == "spawn_pending", tostring(why))
        if not actor then return end
        s.actor, s.actorId = actor, assert(U.idOf(actor))
        assert(B.assign(s.actorId, "farmer", true))
        phase("first")
    elseif s.phase == "first" or s.phase == "second" then
        s.job = s.job or obtain("animal_egg")
        if not s.job then return end
        if not s.action then queuePickup() end
        if not s.receipt then return end
        local receipt = s.receipt
        s.receipt, s.action = nil, nil
        if s.phase == "second" then seedDisk(receipt) return end
        local cancelled, why = W.cancelActor(s.actor, "player_collected_egg")
        assert(cancelled, tostring(why))
        assertReleased(receipt, s.egg)
        assert(eggCount(s.egg) == s.eggsBeforePickup, "recovery duplicated or lost an egg")
        note("egg_count_before_after_recovery", s.eggsBeforePickup .. "/" .. eggCount(s.egg))
        assert(B.cancelJob(s.job.id))
        note("cancel", receipt.blocker .. " / released native egg " .. tostring(s.egg:getID()))
        assert(not s.hutch:isDoorClosed())
        s.hutch:toggleDoor()
        s.job = nil
        phase("other_chore")
    elseif s.phase == "other_chore" then
        s.job = s.job or obtain("animal_open")
        if not s.job then return end
        if B.job(s.job.id) then tickJob() return end
        assert(completed(s.job.id) and not s.hutch:isDoorClosed(), "farmer did not open hen house")
        note("next_chore", s.job.id .. " / hen house door opened by farmer")
        s.egg, s.job = makeEgg(), nil
        phase("second")
    elseif s.phase == "reload" then restore() end
end

Events.OnRenderTick.Add(function()
    if s.phase == "done" then return end
    local ok, why = pcall(step)
    if not ok then finish("FAIL", why) end
end)
