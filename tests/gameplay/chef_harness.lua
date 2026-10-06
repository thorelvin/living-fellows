-- SPDX-License-Identifier: MIT
-- Small controller contract: safe food, stock threshold, power and one-shot order.
local SC = SurvivorCompanion
local chef, baseLife, util = SC.ChefWork, SC.BaseLife, SC.GameplayUtil
assert(baseLife.ROLES.chef and baseLife.JOB_TYPES.cook,
    "Chef must survive role and job normalization")

local function food(kind, flags)
    flags = flags or {}
    local item = {}
    function item:getFullType() return kind end
    function item:getCategory() return "Food" end
    function item:isRotten() return flags.rotten == true end
    function item:isBurnt() return flags.burnt == true end
    function item:isPoisonous() return flags.poisoned == true end
    function item:isFrozen() return flags.frozen == true end
    function item:isDangerousUncooked() return flags.raw == true end
    function item:isCooked() return flags.cooked == true end
    return item
end
assert(chef.isPrepared(food("Base.Salad")) == true)
assert(chef.isPrepared(food("Base.Salad", { rotten = true })) == false)
assert(chef.isPrepared(food("Base.PotOfSoupRecipe")) == false)
assert(chef.isPrepared(food("Base.PotOfSoupRecipe", { cooked = true })) == true)
assert(chef.isPrepared(food("Base.PotOfStew")) == false)
assert(chef.isPrepared(food("Base.PotOfStew", { cooked = true })) == true)
assert(chef.isPrepared(food("Base.SoupBowl")) == false)
assert(chef.isPrepared(food("Base.SoupBowlClay")) == false)
assert(chef.isPrepared(food("Base.StewBowl")) == false)
assert(chef.isPrepared(food("Base.StewBowlClay")) == false)
assert(chef.isPrepared(food("Base.SoupBowl", { cooked = true })) == true)
assert(chef.isPrepared(food("Base.StewBowl", { cooked = true })) == true)
assert(chef.isPrepared(food("Base.Sandwich", { raw = true })) == false)
assert(chef.isPrepared(food("Base.PanFriedVegetables")) == false)
assert(chef.isPrepared(food("Base.PanFriedVegetables", { cooked = true })) == true)
assert(chef.isPrepared(food("Base.PastaPot")) == false)
assert(chef.isPrepared(food("Base.PastaBowl")) == false)
assert(chef.isPrepared(food("Base.PastaBowlClay")) == false)
assert(chef.isPrepared(food("Base.PastaBowl", { cooked = true })) == true)

local saved = {}
local function swap(object, key, replacement)
    saved[#saved + 1] = { object = object, key = key, value = object[key] }
    object[key] = replacement
end
local actor, player = { id = "chef:1" }, { x = 0, y = 0, z = 0 }
local stored = {}
local fridge = { items = stored, powered = true }
function fridge:getType() return "fridge" end
function fridge:isPowered() return self.powered end
function fridge:getItems() return self.items end
local object = {}
function object:getContainer() return fridge end
local square = {}
function square:getObjects() return { object } end
local world = { zones = {
    { kind = "area", x1 = 0, x2 = 0, y1 = 0, y2 = 0, z = 0 },
}, jobs = {}, completed = {} }
swap(baseLife, "active", function() return world end)
swap(baseLife, "isInside", function() return true end)
swap(baseLife, "resident", function() return { role = "chef", duty = true } end)
swap(baseLife, "storageRows", function() return {} end)
swap(baseLife, "depositStorageRows", function() return {} end)
swap(baseLife, "summary", function() return { residentRows = {
    { id = "chef:1", duty = true }, { id = "friend:2", duty = true },
} } end)
swap(baseLife, "outdoorNightRestricted", function() return false end)
swap(baseLife, "enqueueJob", function(spec)
    spec.id, spec.state = "job:" .. tostring(#world.jobs + 1), "pending"
    world.jobs[#world.jobs + 1] = spec
    return true, spec
end)
swap(util, "gridSquare", function() return square end)
swap(util, "idOf", function(value) return value.id end)

chef.reset()
fridge.powered = false
local queued, reason = chef.ensureAutomaticJob(actor, { role = "chef", duty = true })
assert(queued == false and reason == "chef_fridge_unavailable",
    "automatic meals must wait for powered cold storage")
chef.reset()
fridge.powered = true
queued = chef.ensureAutomaticJob(actor, { role = "chef", duty = true })
assert(queued == true and #world.jobs == 1 and world.jobs[1].type == "cook",
    "one eligible Chef should queue one persisted cooking job")
queued, reason = chef.ensureAutomaticJob(actor, { role = "chef", duty = true })
assert(queued == false and reason == "chef_job_pending",
    "an active cook job must suppress stock duplicates")
world.jobs = {}
local oldZones, oldGridSquare = world.zones, util.gridSquare
local emptySquare = { getObjects = function() return {} end }
world.zones = {
    { kind = "area", x1 = 0, x2 = 1600, y1 = 0, y2 = 0, z = 0 },
    { kind = "area", x1 = 0, x2 = 0, y1 = 0, y2 = 0, z = 1 },
}
util.gridSquare = function(_, _, z)
    return z == 1 and square or emptySquare
end
chef.reset()
local upperFridgeFound = false
for _ = 1, 80 do
    queued, reason = chef.ensureAutomaticJob(actor, { role = "chef", duty = true })
    if queued then upperFridgeFound = true break end
end
assert(upperFridgeFound and #world.jobs == 1,
    "Chef discovers an upstairs fridge even after 1600 ground-floor squares")
world.jobs, world.zones, util.gridSquare = {}, oldZones, oldGridSquare
stored[1], stored[2] = food("Base.Salad"), food("Base.Sandwich")
chef.reset()
queued, reason = chef.ensureAutomaticJob(actor, { role = "chef", duty = true })
assert(queued == false and reason == "chef_stock_ready",
    "safe ready meals in the powered fridge satisfy residents")

queued = chef.requestMeal(actor, player)
assert(queued == true and world.jobs[1].target.manual == true,
    "the Chef-only order queues exactly one manual meal")
queued, reason = chef.requestMeal(actor, player)
assert(queued == false and reason == "chef_meal_already_requested")
local failed, failure, terminal = chef.update(actor, {}, {
    id = "job:reloaded", type = "cook", target = { cookPhase = "combine_queued" },
}, player)
assert(failed == false and type(failure) == "string"
    and terminal == true, "unknown native completion must not craft a second meal")

-- Exercise the actual controller steps with a native-action stand-in. The
-- stand-in only creates food when its completion callback is fired; queueing
-- alone must never count as a meal or deposit a replacement item.
local function container(kind, contents)
    local value = { kind = kind, items = contents or {} }
    function value:getType() return self.kind end
    function value:getItems() return self.items end
    function value:contains(item)
        for _, candidate in ipairs(self.items) do
            if candidate == item then return true end
        end
        return false
    end
    function value:Remove(item)
        for index, candidate in ipairs(self.items) do
            if candidate == item then table.remove(self.items, index) return end
        end
    end
    function value:AddItem(item) self.items[#self.items + 1] = item return item end
    return value
end
local bowl = food("Base.Bowl")
local tomato = food("Base.Tomato")
local shelf = container("shelves", { bowl, tomato })
local actorInventory = container("inventory", {})
function actor:getInventory() return actorInventory end
local supplyObject = {}
function supplyObject:getContainer() return shelf end
function square:getObjects() return { supplyObject, object } end
fridge.items = {}
local salad = food("Base.Salad")
local saladData = {}
function salad:getModData() return saladData end
local recipe = {}
function recipe:getUntranslatedName() return "Salad" end
function recipe:getItemsCanBeUse() return { tomato } end
local oldRecipes, oldList, oldAction, oldQueue =
    getEvolvedRecipes, ArrayList, ISAddItemInRecipe, ISTimedActionQueue
local oldInstanceItem = instanceItem
instanceItem = function(kind) return food(kind) end
getEvolvedRecipes = function() return { recipe } end
ArrayList = { new = function()
    return { add = function(self, value) self[#self + 1] = value end }
end }
-- A meal with a real ingredient but no serving vessel should name that
-- vessel, while an incompatible ingredient remains a generic stock problem.
shelf.items = { tomato }
chef.reset()
local missingBowlJob = { id = "job:missing-bowl", type = "cook", target = {} }
local bowlReady, bowlReason = chef.update(actor, {}, missingBowlJob, player)
assert(bowlReady == false and bowlReason == "chef_tool_missing:bowl"
    and shelf:contains(tomato),
    "a cook with usable food seeks a bowl instead of blaming generic stock")
shelf.items = { bowl, tomato }
local queuedAction
ISAddItemInRecipe = { new = function(_, character, selected, baseItem, usedItem)
    local action = { character = character, baseItem = baseItem,
        usedItem = usedItem }
    function action:complete()
        actorInventory:Remove(self.baseItem)
        actorInventory:Remove(self.usedItem)
        actorInventory:AddItem(salad)
        self.baseItem = salad
        return true
    end
    function action:stop() return true end
    return action
end }
ISTimedActionQueue = { add = function(action) queuedAction = action end }
swap(util, "directInteractionAccess", function() return true, {} end)
swap(util, "resolveActor", function() return actor end)
chef.reset()
local job = { id = "job:meal", type = "cook", target = { manual = false } }
local handled, progress, _, completed = chef.update(actor, {}, job, player)
assert(handled == true and completed ~= true and queuedAction ~= nil,
    "sourcing and native queueing must not count as a completed meal")
assert(#fridge.items == 0 and #actorInventory.items == 2,
    "exact bowl and ingredient are carried until native completion")
local mayCancel, cancelReason = chef.cancelJob(job, actor.id)
assert(mayCancel == false and cancelReason == "chef_native_action_pending",
    "role changes cannot delete a meal while native cooking is queued")
queuedAction:complete()
handled, progress, _, completed = chef.update(actor, {}, job, player)
assert(handled == true and completed == true and progress == "chef_meal_stored",
    "finished native meal must be moved to powered fridge")
assert(util.inventoryContains(fridge, salad) and saladData.SC_ChefJobId == job.id
    and job.target.cookPhase == "stored", "receipt identifies the exact stored meal")
chef.reset()
handled, progress, _, completed = chef.update(actor, {}, job, player)
assert(handled == true and completed == true and progress == "stored"
    and #fridge.items == 1, "reloaded delivery receipt must not cook a duplicate")

-- A safe food is not necessarily an ingredient for the native evolved recipe.
-- Refuse it before taking the base, and return exact borrowed items if a
-- queued action is interrupted before conversion.
local unusableBowl, unusableFood = food("Base.Bowl"), food("Base.Ramen")
shelf.items, actorInventory.items, fridge.items =
    { unusableBowl, unusableFood }, {}, {}
function recipe:getItemsCanBeUse() return {} end
chef.reset()
local unusableJob = { id = "job:unusable", type = "cook", target = {} }
handled, progress = chef.update(actor, {}, unusableJob, player)
assert(handled == false and progress == "chef_recipe_supplies_missing"
    and shelf:contains(unusableBowl) and #actorInventory.items == 0,
    "incompatible safe food must not withdraw a bowl or pin the native action")

local borrowedBowl, borrowedTomato = food("Base.Bowl"), food("Base.Tomato")
shelf.items = { borrowedBowl, borrowedTomato }
function recipe:getItemsCanBeUse() return { borrowedTomato } end
chef.reset()
queuedAction = nil
local cancelledJob = { id = "job:cancel", type = "cook",
    assignedId = actor.id, target = {} }
handled, progress = chef.update(actor, {}, cancelledJob, player)
assert(handled == true and cancelledJob.target.cookPhase == "combine_queued"
    and actorInventory:contains(borrowedBowl)
    and actorInventory:contains(borrowedTomato),
    "Chef holds the exact borrowed bowl and tomato while assembly is queued")
queuedAction:stop()
local cancelled, cancelReason = chef.cancelJob(cancelledJob, nil)
assert(cancelled == true and shelf:contains(borrowedBowl)
    and shelf:contains(borrowedTomato) and #actorInventory.items == 0,
    "assigned Chef cancellation returns exact borrowed supplies: "
        .. tostring(cancelReason))
local missingState, missingReason = chef.cancelJob({
    id = "job:missing-state", type = "cook", assignedId = actor.id,
    target = { cookPhase = "supplies_withdrawn" },
}, nil)
assert(missingState == false
    and missingReason == "chef_return_receipt_recovery_required",
    "a reloaded pre-native withdrawal cannot be discarded without recovery")
function recipe:getItemsCanBeUse() return { tomato } end

-- Soup has a second native transaction: heat the exact pot, divide it into
-- two bowls, store both bowls, and return the reusable pot to camp storage.
local pot = food("Base.Pot")
local potFluid = {}
function potFluid:getCapacity() return 1 end
function potFluid:getAmount() return 1 end
function potFluid:isTainted() return false end
function potFluid:getPrimaryFluidAmount() return 1 end
function potFluid:getPrimaryFluid()
    return { getFluidTypeString = function() return "Water" end }
end
function potFluid:contains(value) return Fluid and value == Fluid.Water end
function pot:getFluidContainer() return potFluid end
local bowl1, bowl2 = food("Base.Bowl"), food("Base.Bowl")
local soupFlags = { cooked = false }
local hotSoup = food("Base.PotOfSoupRecipe", soupFlags)
local hotSoupData = {}
function hotSoup:getModData() return hotSoupData end
local portion1, portion2 = food("Base.SoupBowl", { cooked = true }),
    food("Base.SoupBowl", { cooked = true })
local portionData1, portionData2 = {}, {}
function portion1:getModData() return portionData1 end
function portion2:getModData() return portionData2 end
local emptyPot = food("Base.Pot")
local emptyPotData = {}
function emptyPot:getModData() return emptyPotData end
shelf.items, fridge.items, actorInventory.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
local ovenContainer = container("stove", {})
function ovenContainer:isPowered() return self.powered ~= false end
local oven = {}
function oven:getContainer() return ovenContainer end
function oven:Activated() return true end
function square:getObjects() return { supplyObject, object, oven } end
world.jobs, world.completed = {}, {}
local oldInstanceof, oldManager, oldLogic, oldHandcraft =
    instanceof, getScriptManager, HandcraftLogic, ISHandcraftAction
instanceof = function(value, className)
    return value == oven and className == "IsoStove"
end
local soupRecipe = {}
function soupRecipe:getUntranslatedName() return "Soup" end
function soupRecipe:getItemsCanBeUse() return { tomato } end
getEvolvedRecipes = function() return { soupRecipe } end
actorInventory.items, fridge.items = {}, {}
shelf.items = { bowl1, bowl2, tomato }
chef.reset()
local missingPot = { id = "job:missing-pot", type = "cook", target = {} }
local equipped, missingReason = chef.update(actor, {}, missingPot, player)
assert(equipped == false and missingReason == "chef_tool_missing:pot",
    "a soup cook asks for the absent pot when bowls and food are ready")
shelf.items = { pot, bowl1, tomato }
chef.reset()
local missingServing = { id = "job:missing-serving", type = "cook",
    target = {} }
equipped, missingReason = chef.update(actor, {}, missingServing, player)
assert(equipped == false and missingReason == "chef_tool_missing:bowl",
    "a hot pot meal asks for the second serving bowl")
shelf.items = { pot, bowl1, bowl2, tomato }
ovenContainer.powered = false
chef.reset()
local missingHeat = { id = "job:missing-heat", type = "cook", target = {} }
equipped, missingReason = chef.update(actor, {}, missingHeat, player)
assert(equipped == false and missingReason == "chef_tool_missing:heat_source",
    "a stocked cook asks for a working heat source when the stove loses power")
ovenContainer.powered = true
shelf.items = { pot, bowl1, bowl2, tomato }
getScriptManager = function()
    return { getCraftRecipe = function(_, name)
        return name == "Make2Bowls" and {} or nil
    end }
end
HandcraftLogic = { new = function()
    return {
        setContainers = function() end,
        setRecipeFromContextClick = function() end,
        canPerformCurrentRecipe = function() return true end,
        getCreatedOutputItems = function(_, output)
            output:add(portion1)
            output:add(portion2)
            output:add(emptyPot)
        end,
    }
end }
ISHandcraftAction = { FromLogic = function(logic)
    return {
        logic = logic,
        performRecipe = function()
            actorInventory:Remove(hotSoup)
            actorInventory:Remove(bowl1)
            actorInventory:Remove(bowl2)
            actorInventory:AddItem(portion1)
            actorInventory:AddItem(portion2)
            actorInventory:AddItem(emptyPot)
        end,
        stop = function() end,
    }
end }
ISAddItemInRecipe = { new = function(_, character, selected, baseItem, usedItem)
    return {
        baseItem = baseItem,
        complete = function(self)
            actorInventory:Remove(self.baseItem)
            actorInventory:Remove(usedItem)
            actorInventory:AddItem(hotSoup)
            self.baseItem = hotSoup
            return true
        end,
        stop = function() end,
    }
end }
queuedAction = nil
chef.reset()
local soupJob = { id = "job:soup", type = "cook", target = { manual = false } }
for _ = 1, 5 do
    handled, progress = chef.update(actor, {}, soupJob, player)
    if soupJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and queuedAction ~= nil
    and soupJob.target.cookPhase == "combine_queued",
    "soup starts with the native evolved recipe: " .. tostring(progress)
        .. "/" .. tostring(soupJob.target.cookPhase))
queuedAction:complete()
handled = chef.update(actor, {}, soupJob, player)
assert(handled == true and ovenContainer:contains(hotSoup)
    and not chef.isPrepared(hotSoup), "uncooked soup stays in the heated pot")
soupFlags.cooked = true
handled = chef.update(actor, {}, soupJob, player)
assert(handled == true and soupJob.target.cookPhase == "portion_queued",
    "cooked soup queues native bowl division")
queuedAction:performRecipe()
handled, progress, _, completed = chef.update(actor, {}, soupJob, player)
assert(handled == true and completed ~= true
    and util.inventoryContains(fridge, portion1),
    "the first bowl is stored before the job can complete")
fridge.items = {} -- The player eats the first serving before a reload.
chef.reset()
handled, progress, _, completed = chef.update(actor, {}, soupJob, player)
assert(handled == true and completed ~= true
    and util.inventoryContains(fridge, portion2),
    "reload continues with the second bowl after the first was eaten")
handled, progress, _, completed = chef.update(actor, {}, soupJob, player)
assert(handled == true and completed == true
    and util.inventoryContains(shelf, emptyPot)
    and portionData1.SC_ChefJobId == soupJob.id
    and portionData2.SC_ChefPortionIndex == 2,
    "both native bowls and the returned pot have exact receipts")
chef.reset()
handled, progress, _, completed = chef.update(actor, {}, soupJob, player)
assert(handled == true and completed == true and progress == "stored",
    "a completed two-bowl delivery stays complete after the first bowl was eaten")

-- A campfire meal has no owned oven to switch off, but it is still unsafe to
-- erase its job while the exact pot sits in the fire.
local oldCampfire = CCampfireSystem
local fireContainer = container("campfire", {})
local fireObject = {}
function fireObject:getContainer() return fireContainer end
local fire = { isLit = true, fuelAmt = 20 }
function fire:getIsoObject() return fireObject end
CCampfireSystem = { instance = {
    getLuaObjectOnSquare = function() return fire end,
} }
function square:getObjects() return { supplyObject, object } end
shelf.items, actorInventory.items, fridge.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
ovenContainer.items = {}
soupFlags.cooked = false
chef.reset()
queuedAction = nil
local fireJob = { id = "job:soup:campfire", type = "cook",
    assignedId = actor.id, target = {} }
for _ = 1, 5 do
    handled, progress = chef.update(actor, {}, fireJob, player)
    if fireJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and fireJob.target.cookPhase == "combine_queued")
queuedAction:complete()
chef.update(actor, {}, fireJob, player)
assert(fireContainer:contains(hotSoup)
    and fireJob.target.cookPhase == "heating")
local fireCancelled, fireReason = chef.cancelJob(fireJob, nil)
assert(fireCancelled == false and fireReason == "chef_hot_cook_recovery_pending",
    "a campfire pot cannot be abandoned mid-cook")
fireCancelled, fireReason = chef.cancelActor(actor, "base_work_cancelled")
assert(fireCancelled == false and fireReason == "chef_hot_cook_in_progress",
    "changing work cannot drop a campfire cooking receipt")
assert(chef.mustTendHeat(actor, fireJob),
    "night shelter cannot move a Chef away from food still in a campfire")
fire.isLit = false
handled, progress = chef.update(actor, {}, fireJob, player)
assert(handled == true and progress == "chef_heat_interrupted"
    and actorInventory:contains(hotSoup)
    and fireJob.target.cookPhase == "needs_heat"
    and not chef.mustTendHeat(actor, fireJob),
    "an unlit campfire releases the unfinished pot into a recoverable phase")
fireCancelled, fireReason = chef.cancelJob(fireJob, nil)
assert(fireCancelled == true and shelf:contains(hotSoup),
    "the recovered uncooked pot can be returned when the job is cancelled: "
        .. tostring(fireReason))
-- Heat can stop on the same pulse that food finishes. A cooked result still
-- needs retrieval and portioning even though the source is no longer lit.
shelf.items, actorInventory.items, fridge.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
soupFlags.cooked, fire.isLit = false, true
chef.reset()
queuedAction = nil
local cookedFireJob = { id = "job:soup:fire-finished", type = "cook",
    assignedId = actor.id, target = {} }
for _ = 1, 5 do
    handled = chef.update(actor, {}, cookedFireJob, player)
    if cookedFireJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and queuedAction ~= nil)
queuedAction:complete()
chef.update(actor, {}, cookedFireJob, player)
soupFlags.cooked, fire.isLit = true, false
handled, progress = chef.update(actor, {}, cookedFireJob, player)
assert(handled == true and cookedFireJob.target.cookPhase == "portion_queued"
    and progress == "chef_dividing_pot_meal",
    "cooked food is retrieved and divided even when the fire goes out: "
        .. tostring(handled) .. "/" .. tostring(progress) .. "/"
        .. tostring(cookedFireJob.target.cookPhase))
CCampfireSystem = oldCampfire
function square:getObjects() return { supplyObject, object, oven } end
chef.reset()
-- The same recovery applies to a stove that loses electricity mid-cook.
shelf.items, actorInventory.items, fridge.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
ovenContainer.items, ovenContainer.powered = {}, true
soupFlags.cooked = false
queuedAction = nil
local outageJob = { id = "job:soup:outage", type = "cook",
    assignedId = actor.id, target = {} }
for _ = 1, 5 do
    handled = chef.update(actor, {}, outageJob, player)
    if outageJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and queuedAction ~= nil)
queuedAction:complete()
chef.update(actor, {}, outageJob, player)
assert(ovenContainer:contains(hotSoup)
    and chef.mustTendHeat(actor, outageJob))
ovenContainer.powered = false
handled, progress = chef.update(actor, {}, outageJob, player)
assert(handled == true and progress == "chef_heat_interrupted"
    and actorInventory:contains(hotSoup)
    and outageJob.target.cookPhase == "needs_heat",
    "power loss retrieves the unfinished pot and preserves its receipt")
fireCancelled, fireReason = chef.cancelJob(outageJob, nil)
assert(fireCancelled == true and shelf:contains(hotSoup),
    "the stove-outage job can release its exact carried food: "
        .. tostring(fireReason))
ovenContainer.powered = nil
chef.reset()

-- A supply the cook cannot reach is a failed step, not progress.
shelf.items, actorInventory.items, fridge.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
ovenContainer.items = {}
util.directInteractionAccess = function()
    return false, {}, "no_interaction_targets"
end
local unreachableTerminal
handled, progress, unreachableTerminal = chef.update(actor, {},
    { id = "job:soup:unreachable", type = "cook", assignedId = actor.id,
        target = {} }, player)
util.directInteractionAccess = function() return true, {} end
assert(handled == false and unreachableTerminal == true
    and progress == "no_interaction_targets",
    "an unreachable supply reports a failed step: " .. tostring(handled)
        .. "/" .. tostring(progress))
chef.reset()

-- The player may lift the pot out of the stove before the Chef collects it.
-- Nothing is left to tend, so the job closes instead of retrying the missing
-- pot forever behind a hot-cook guard that refuses every cancel.
shelf.items, actorInventory.items, fridge.items =
    { pot, bowl1, bowl2, tomato }, {}, {}
ovenContainer.items = {}
soupFlags.cooked = false
queuedAction = nil
local takenJob = { id = "job:soup:taken", type = "cook",
    assignedId = actor.id, target = {} }
for _ = 1, 5 do
    handled = chef.update(actor, {}, takenJob, player)
    if takenJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and queuedAction ~= nil)
queuedAction:complete()
chef.update(actor, {}, takenJob, player)
assert(ovenContainer:contains(hotSoup) and takenJob.target.cookPhase == "heating")
ovenContainer:Remove(hotSoup)
local takenTerminal
handled, progress, takenTerminal, completed = chef.update(actor, {}, takenJob, player)
assert(handled == true and completed == true and takenTerminal ~= true
    and progress == "chef_meal_taken"
    and takenJob.target.cookPhase == "meal_taken"
    and not chef.mustTendHeat(actor, takenJob),
    "a meal taken out of the stove closes its job: " .. tostring(progress)
        .. "/" .. tostring(takenJob.target.cookPhase))
chef.reset()
handled, progress, _, completed = chef.update(actor, {}, takenJob, player)
assert(handled == true and completed == true and progress == "meal_taken",
    "a reloaded taken-meal job completes instead of waiting on a receipt")
chef.reset()

-- Each named variant must choose the native recipe and its specified meat.
-- Raw fish and venison are valid only on the heated pot route; the sandwich
-- requires cooked venison before it can be assembled.
local rawFish = food("Base.FishFillet", { raw = true })
local rawVenison = food("Base.Venison", { raw = true })
local cookedVenison = food("Base.Venison", { raw = true, cooked = true })
local bread = food("Base.BreadSlices")
local soupNative, stewNative, sandwichNative = {}, {}, {}
function soupNative:getUntranslatedName() return "Soup" end
function stewNative:getUntranslatedName() return "Stew" end
function sandwichNative:getUntranslatedName() return "Sandwich" end
function soupNative:getItemsCanBeUse() return { rawFish } end
function stewNative:getItemsCanBeUse() return { rawFish, rawVenison } end
function sandwichNative:getItemsCanBeUse() return { cookedVenison } end
getEvolvedRecipes = function()
    return { soupNative, stewNative, sandwichNative }
end
ISAddItemInRecipe = { new = function(_, _, selected, _, usedItem)
    return { recipe = selected, usedItem = usedItem,
        complete = function() return true end, stop = function() end }
end }
local variants = {
    { id = "fish_soup", native = soupNative, ingredient = rawFish },
    { id = "fish_stew", native = stewNative, ingredient = rawFish },
    { id = "venison_stew", native = stewNative, ingredient = rawVenison },
    { id = "venison_sandwich", native = sandwichNative,
        ingredient = cookedVenison },
}
for index, variant in ipairs(variants) do
    actorInventory.items, fridge.items = {}, {}
    shelf.items = { pot, bowl1, bowl2, bread, rawFish, rawVenison,
        cookedVenison }
    world.completed = {}
    for count = 1, index + 2 do
        world.completed[count] = { type = "cook" }
    end
    chef.reset()
    queuedAction = nil
    local variantJob = { id = "job:variant:" .. index, type = "cook",
        target = { manual = false } }
    for _ = 1, 8 do
        handled, progress = chef.update(actor, {}, variantJob, player)
        if variantJob.target.cookPhase == "combine_queued" then break end
    end
    assert(handled == true and variantJob.target.recipe == variant.id
        and variantJob.target.cookPhase == "combine_queued"
        and queuedAction and queuedAction.recipe == variant.native
        and queuedAction.usedItem == variant.ingredient,
        "named meat dish must use the matching native recipe and safe meat: "
            .. variant.id .. "/" .. tostring(progress))
end

local stewFlags = { cooked = false }
local hotStew = food("Base.PotOfStew", stewFlags)
local stewData = {}
function hotStew:getModData() return stewData end
local stewBowl1 = food("Base.StewBowl", { cooked = true })
local stewBowl2 = food("Base.StewBowl", { cooked = true })
local stewBowlData1, stewBowlData2 = {}, {}
function stewBowl1:getModData() return stewBowlData1 end
function stewBowl2:getModData() return stewBowlData2 end
local stewPot = food("Base.Pot")
local stewPotData = {}
function stewPot:getModData() return stewPotData end
actorInventory.items, fridge.items = {}, {}
shelf.items = { pot, bowl1, bowl2, rawVenison }
world.completed = {}
for index = 1, 5 do world.completed[index] = { type = "cook" } end
getEvolvedRecipes = function() return { stewNative } end
ISAddItemInRecipe = { new = function(_, _, _, baseItem, usedItem)
    return { baseItem = baseItem,
        complete = function(self)
            actorInventory:Remove(self.baseItem)
            actorInventory:Remove(usedItem)
            actorInventory:AddItem(hotStew)
            self.baseItem = hotStew
            return true
        end,
        stop = function() end }
end }
HandcraftLogic = { new = function()
    return {
        setContainers = function() end,
        setRecipeFromContextClick = function() end,
        canPerformCurrentRecipe = function() return true end,
        getCreatedOutputItems = function(_, output)
            output:add(stewBowl1)
            output:add(stewBowl2)
            output:add(stewPot)
        end,
    }
end }
ISHandcraftAction = { FromLogic = function(logic)
    return {
        logic = logic,
        performRecipe = function()
            actorInventory:Remove(hotStew)
            actorInventory:Remove(bowl1)
            actorInventory:Remove(bowl2)
            actorInventory:AddItem(stewBowl1)
            actorInventory:AddItem(stewBowl2)
            actorInventory:AddItem(stewPot)
        end,
        stop = function() end,
    }
end }
chef.reset()
queuedAction = nil
local stewJob = { id = "job:stew", type = "cook", target = { manual = false } }
for _ = 1, 5 do
    handled, progress = chef.update(actor, {}, stewJob, player)
    if stewJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and stewJob.target.recipe == "venison_stew"
    and stewJob.target.cookPhase == "combine_queued",
    "venison stew queues the native Stew action")
queuedAction:complete()
chef.update(actor, {}, stewJob, player)
assert(ovenContainer:contains(hotStew) and not chef.isPrepared(hotStew),
    "raw venison stew stays in the oven until cooked")
stewFlags.cooked = true
chef.update(actor, {}, stewJob, player)
assert(stewJob.target.cookPhase == "portion_queued",
    "cooked venison stew queues native bowl division")
queuedAction:performRecipe()
chef.update(actor, {}, stewJob, player)
chef.update(actor, {}, stewJob, player)
handled, progress, _, completed = chef.update(actor, {}, stewJob, player)
assert(handled == true and completed == true
    and util.inventoryContains(fridge, stewBowl1)
    and util.inventoryContains(fridge, stewBowl2)
    and util.inventoryContains(shelf, stewPot)
    and stewBowlData1.SC_ChefJobId == stewJob.id
    and stewBowlData2.SC_ChefPortionIndex == 2,
    "venison stew stores two safe bowls and returns the pot")

-- A scavenged loaf is sliced natively, then raw scavenged venison is cooked
-- before the native sandwich action. The extra slices remain available to
-- this Chef for subsequent meals.
local loaf = food("Base.Bread")
local knife = food("Base.KitchenKnife")
function knife:getCategory() return "Weapon" end
local wholeFish
local breadSlices = { food("Base.BreadSlices"), food("Base.BreadSlices"),
    food("Base.BreadSlices") }
for index, slice in ipairs(breadSlices) do
    local data = {}
    function slice:getModData() return data end
    function slice:getID() return 700 + index end
end
local venisonFlags = { raw = true, cooked = false, frozen = true }
local rawSandwichVenison = food("Base.Venison", venisonFlags)
local rawSandwichData = {}
function rawSandwichVenison:getModData() return rawSandwichData end
function rawSandwichVenison:getID() return 710 end
local finishedSandwich = food("Base.Sandwich")
local sandwichData = {}
function finishedSandwich:getModData() return sandwichData end
local oldToggle = ISToggleStoveAction
oven.active = false
function oven:Activated() return self.active end
ISToggleStoveAction = { new = function(_, _, stove)
    return {
        complete = function()
            stove.active = not stove.active
            return true
        end,
        stop = function() end,
    }
end }
function square:getX() return 0 end
function square:getY() return 0 end
function square:getZ() return 0 end
function oven:getSquare() return square end
oven.active = true
getEvolvedRecipes = function() return { soupNative } end
chef.reset()
queuedAction = nil
local takenCleanupJob = { id = "job:taken-cleanup", type = "cook",
    assignedId = actor.id, target = { cookPhase = "heating", recipe = "fish_soup",
        ownOven = true,
        ownedOvenX = 0, ownedOvenY = 0, ownedOvenZ = 0 } }
hotSoupData.SC_ChefJobId = takenCleanupJob.id
ovenContainer.items = { hotSoup }
handled, progress, _, completed = chef.update(actor, {}, takenCleanupJob, player)
assert(handled == true and completed ~= true
    and progress == "chef_meal_heating",
    "a reloaded cook locates the exact pot still in its oven: "
        .. tostring(handled) .. "/" .. tostring(progress))
ovenContainer:Remove(hotSoup)
handled, progress, _, completed = chef.update(actor, {}, takenCleanupJob, player)
assert(handled == true and completed ~= true and queuedAction ~= nil
    and oven.active == true and takenCleanupJob.target.mealTakenCleanup == true,
    "taking the meal persists cleanup before queuing oven switch-off")
chef.reset() -- Reload while the native switch-off action was still queued.
queuedAction = nil
handled, progress, _, completed = chef.update(actor, {}, takenCleanupJob, player)
assert(handled == true and completed ~= true and queuedAction ~= nil,
    "a second reload reconstructs the pending cleanup")
queuedAction:complete()
handled, progress, _, completed = chef.update(actor, {}, takenCleanupJob, player)
assert(handled == true and completed == true and not oven.active
    and takenCleanupJob.target.cookPhase == "meal_taken"
    and takenCleanupJob.target.mealTakenCleanup == nil,
    "the taken meal completes only after its oven is off")
oven.active = false
swap(util, "itemHasTag", function(item, tag)
    return (item == knife and tag == "sharpknife")
        or (item == wholeFish and tag == "uncutfish")
end)
function sandwichNative:getItemsCanBeUse()
    return venisonFlags.cooked and { rawSandwichVenison } or {}
end
getEvolvedRecipes = function() return { sandwichNative } end
getScriptManager = function()
    return { getCraftRecipe = function(_, name)
        return (name == "SliceBread" or name == "SliceFillet")
            and { name = name } or nil
    end }
end
local craftInput, craftOutputItems = loaf, breadSlices
HandcraftLogic = { new = function()
    return {
        setContainers = function() end,
        setRecipeFromContextClick = function(self, recipe)
            self.recipe = recipe
        end,
        canPerformCurrentRecipe = function() return true end,
        getCreatedOutputItems = function(_, output)
            for _, item in ipairs(craftOutputItems) do output:add(item) end
        end,
    }
end }
ISHandcraftAction = { FromLogic = function(logic)
    return {
        logic = logic,
        performRecipe = function()
            actorInventory:Remove(craftInput)
            for _, item in ipairs(craftOutputItems) do
                actorInventory:AddItem(item)
            end
        end,
        stop = function() end,
    }
end }
ISAddItemInRecipe = { new = function(_, _, _, baseItem, usedItem)
    return { baseItem = baseItem, usedItem = usedItem,
        complete = function(self)
            actorInventory:Remove(self.baseItem)
            actorInventory:Remove(usedItem)
            actorInventory:AddItem(finishedSandwich)
            self.baseItem = finishedSandwich
            return true
        end,
        stop = function() end }
end }
actorInventory.items, fridge.items = {}, {}
shelf.items = { loaf, knife, rawSandwichVenison }
world.completed = {}
world.completed[1] = { type = "cook" }
chef.reset()
shelf.items = { loaf, rawSandwichVenison }
local missingKnife = { id = "job:missing-knife", type = "cook", target = {} }
local prepared, knifeReason = chef.update(actor, {}, missingKnife, player)
assert(prepared == false and knifeReason == "chef_tool_missing:knife",
    "a cook with a loaf and filling asks for a slicing knife")
shelf.items = { loaf, knife, rawSandwichVenison }
chef.reset()
queuedAction = nil
local sandwichJob = { id = "job:sandwich:raw", type = "cook",
    target = { manual = false } }
handled, progress = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and sandwichJob.target.cookPhase == "bread_slice_queued"
    and queuedAction ~= nil, "Chef slices scavenged whole bread natively")
queuedAction:performRecipe()
chef.reset()
handled, progress = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and sandwichJob.target.cookPhase == "thawing_ingredient"
    and util.inventoryContains(actorInventory, rawSandwichVenison),
    "Chef takes frozen scavenged venison out to thaw: "
        .. tostring(progress) .. "/" .. tostring(sandwichJob.target.cookPhase)
        .. "/" .. tostring(sandwichJob.target.recipe))
chef.reset()
venisonFlags.frozen = false
chef.update(actor, {}, sandwichJob, player)
handled, progress = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and sandwichJob.target.cookPhase
    == "prep_venison_oven_on_queued", "Chef queues the native oven switch")
queuedAction:complete()
chef.update(actor, {}, sandwichJob, player)
handled, progress = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and ovenContainer:contains(rawSandwichVenison)
    and rawSandwichData.SC_ChefPrepJobId == sandwichJob.id,
    "sliced bread survives reload and raw venison enters the cooker")
chef.reset()
venisonFlags.cooked = true
chef.update(actor, {}, sandwichJob, player)
assert(sandwichJob.target.cookPhase == "prep_venison_oven_off_queued"
    and queuedAction ~= nil, "Chef queues the oven switch-off after cooking")
queuedAction:complete()
chef.update(actor, {}, sandwichJob, player)
assert(oven.active == false, "Chef turns off the oven it started")
handled, progress = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and sandwichJob.target.cookPhase == "combine_queued"
    and queuedAction ~= nil and util.inventoryContains(actorInventory,
        rawSandwichVenison), "sandwich assembly waits for cooked venison")
queuedAction:complete()
handled, progress, _, completed = chef.update(actor, {}, sandwichJob, player)
assert(handled == true and completed == true
    and util.inventoryContains(fridge, finishedSandwich)
    and sandwichData.SC_ChefJobId == sandwichJob.id
    and util.inventoryContains(actorInventory, breadSlices[2])
    and util.inventoryContains(actorInventory, breadSlices[3]),
    "Chef stores the sandwich and keeps the spare bread slices")
function tomato:getCategory() return "Food" end
function sandwichNative:getItemsCanBeUse() return { tomato } end
shelf.items = { tomato }
world.completed = { { type = "cook" } }
chef.reset()
queuedAction = nil
local nextSandwich = { id = "job:sandwich:spare", type = "cook",
    target = { manual = false } }
handled, progress = chef.update(actor, {}, nextSandwich, player)
assert(handled == true and nextSandwich.target.recipe == "Sandwich"
    and nextSandwich.target.cookPhase == "combine_queued"
    and queuedAction and queuedAction.baseItem == breadSlices[2],
    "the next sandwich reuses carried slices without slicing a new loaf")

wholeFish = food("Base.Trout", { raw = true })
local fishFillets = { food("Base.FishFillet", { raw = true }),
    food("Base.FishFillet", { raw = true }) }
for index, fillet in ipairs(fishFillets) do
    local data = {}
    function fillet:getModData() return data end
    function fillet:getID() return 730 + index end
end
function pot:getID() return 720 end
craftInput, craftOutputItems = wholeFish, fishFillets
function soupNative:getItemsCanBeUse() return fishFillets end
getEvolvedRecipes = function() return { soupNative } end
actorInventory.items, fridge.items = {}, {}
shelf.items = { pot, bowl1, bowl2, wholeFish, knife }
world.completed = { { type = "cook" }, { type = "cook" },
    { type = "cook" } }
chef.reset()
shelf.items = { pot, bowl1, bowl2, wholeFish }
local missingFishKnife = { id = "job:missing-fish-knife", type = "cook",
    target = {} }
local filletReady, filletReason = chef.update(actor, {}, missingFishKnife,
    player)
assert(filletReady == false and filletReason == "chef_tool_missing:knife",
    "a whole fish cannot become soup until the cook gets a sharp knife")
shelf.items = { pot, bowl1, bowl2, wholeFish, knife }
chef.reset()
queuedAction = nil
local fishJob = { id = "job:fish:whole", type = "cook",
    target = { manual = false } }
handled, progress = chef.update(actor, {}, fishJob, player)
assert(handled == true and fishJob.target.recipe == "fish_soup"
    and fishJob.target.cookPhase == "fish_slice_queued",
    "Chef takes a whole camp fish to the native filleting action")
queuedAction:performRecipe()
chef.reset()
for _ = 1, 4 do
    handled, progress = chef.update(actor, {}, fishJob, player)
    if fishJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and fishJob.target.cookPhase == "combine_queued"
    and queuedAction and queuedAction.usedItem == fishFillets[1]
    and util.inventoryContains(actorInventory, fishFillets[2]),
    "filleted catch survives reload and supplies fish soup: "
        .. tostring(progress) .. "/" .. tostring(fishJob.target.cookPhase)
        .. "/" .. tostring(queuedAction and queuedAction.usedItem))
local frozenFishFlags = { raw = true, frozen = true }
local frozenFillet = food("Base.FishFillet", frozenFishFlags)
local frozenFishData = {}
function frozenFillet:getModData() return frozenFishData end
function frozenFillet:getID() return 740 end
function soupNative:getItemsCanBeUse() return { frozenFillet } end
actorInventory.items, fridge.items = {}, {}
shelf.items = { pot, bowl1, bowl2, frozenFillet }
world.completed = { { type = "cook" }, { type = "cook" } }
chef.reset()
queuedAction = nil
local thawedFishJob = { id = "job:fish:frozen", type = "cook",
    target = { manual = false } }
handled, progress = chef.update(actor, {}, thawedFishJob, player)
assert(handled == true and thawedFishJob.target.recipe == "fish_soup"
    and thawedFishJob.target.cookPhase == "thawing_ingredient"
    and frozenFishData.SC_ChefPrepKind == "thaw",
    "Chef carries scavenged frozen fish out to thaw")
chef.reset()
frozenFishFlags.frozen = false
chef.update(actor, {}, thawedFishJob, player)
for _ = 1, 4 do
    handled, progress = chef.update(actor, {}, thawedFishJob, player)
    if thawedFishJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and thawedFishJob.target.cookPhase == "combine_queued"
    and queuedAction and queuedAction.usedItem == frozenFillet,
    "the thawed fillet enters fish soup without a duplicate withdrawal")

-- Everyday meals use the same native heat path. A stir fry must cook before
-- it can be stored; a pot of dry pasta must first be prepared by handcraft.
local pan = food("Base.Pan")
local potato = food("Base.Potato")
local stirFlags = { cooked = false }
local stirDish = food("Base.PanFriedVegetables", stirFlags)
local stirData = {}
function stirDish:getModData() return stirData end
local stirNative = {}
function stirNative:getUntranslatedName() return "Stir fry" end
function stirNative:getItemsCanBeUse() return { potato } end
getEvolvedRecipes = function() return { stirNative } end
ISAddItemInRecipe = { new = function(_, _, _, baseItem, usedItem)
    return { baseItem = baseItem, usedItem = usedItem,
        complete = function(self)
            actorInventory:Remove(self.baseItem)
            actorInventory:Remove(usedItem)
            actorInventory:AddItem(stirDish)
            self.baseItem = stirDish
            return true
        end,
        stop = function() end }
end }
shelf.items, actorInventory.items, fridge.items = { pan, potato }, {}, {}
world.completed = {}
for _ = 1, 7 do world.completed[#world.completed + 1] = { type = "cook" } end
oven.active = true
chef.reset()
shelf.items = { potato }
local missingPan = { id = "job:missing-pan", type = "cook", target = {} }
local panReady, panReason = chef.update(actor, {}, missingPan, player)
assert(panReady == false and panReason == "chef_tool_missing:pan",
    "a cook with a fryable vegetable asks for the missing pan")
shelf.items = { pan, potato }
chef.reset()
queuedAction = nil
local stirJob = { id = "job:stir", type = "cook", target = {} }
handled, progress = chef.update(actor, {}, stirJob, player)
assert(handled == true and stirJob.target.recipe == "stir_fry"
    and stirJob.target.cookPhase == "combine_queued"
    and queuedAction.usedItem == potato,
    "stir fry uses a native evolved recipe with an available vegetable")
queuedAction:complete()
chef.update(actor, {}, stirJob, player)
assert(ovenContainer:contains(stirDish) and not chef.isPrepared(stirDish),
    "uncooked stir fry cannot count toward Chef stock")
stirFlags.cooked = true
handled, progress, _, completed = chef.update(actor, {}, stirJob, player)
assert(handled == true and completed == true
    and util.inventoryContains(fridge, stirDish)
    and stirData.SC_ChefJobId == stirJob.id,
    "cooked stir fry is stored with its exact receipt")

local pastaPot = food("Base.Pot")
local pastaFluid = {}
local pastaFluidType = "Water"
local pastaFluidWaterAmount = 2
function pastaFluid:getCapacity() return 2 end
function pastaFluid:getAmount() return 2 end
function pastaFluid:isTainted() return false end
function pastaFluid:getPrimaryFluidAmount() return pastaFluidWaterAmount end
function pastaFluid:getPrimaryFluid()
    return { getFluidTypeString = function() return pastaFluidType end }
end
function pastaFluid:contains(value)
    return pastaFluidType == "Water" and Fluid and value == Fluid.Water
end
function pastaPot:getFluidContainer() return pastaFluid end
function pastaPot:getID() return 780 end
local dryPasta = food("Base.Pasta")
function dryPasta:getID() return 781 end
local wetPasta = food("Base.WaterPotPasta")
local wetPastaData = {}
function wetPasta:getModData() return wetPastaData end
function wetPasta:getID() return 782 end
local pastaFlags = { cooked = false }
local pastaDish = food("Base.PastaPot", pastaFlags)
local pastaData = {}
function pastaDish:getModData() return pastaData end
local pastaBowl1 = food("Base.PastaBowl", { cooked = true })
local pastaBowl2 = food("Base.PastaBowl", { cooked = true })
local pastaBowlData1, pastaBowlData2 = {}, {}
function pastaBowl1:getModData() return pastaBowlData1 end
function pastaBowl2:getModData() return pastaBowlData2 end
local pastaEmptyPot = food("Base.Pot")
local pastaEmptyData = {}
function pastaEmptyPot:getModData() return pastaEmptyData end
local pastaNative = {}
function pastaNative:getUntranslatedName() return "PastaPot" end
function pastaNative:getItemsCanBeUse() return { tomato } end
getEvolvedRecipes = function() return { pastaNative } end
getScriptManager = function()
    return { getCraftRecipe = function(_, name)
        return (name == "PlacePastaInCookingPot2" or name == "Make2Bowls")
            and { name = name } or nil
    end }
end
HandcraftLogic = { new = function()
    return {
        setContainers = function() end,
        setRecipeFromContextClick = function(self, recipe) self.recipe = recipe end,
        canPerformCurrentRecipe = function() return true end,
        getCreatedOutputItems = function(self, output)
            if self.recipe.name == "PlacePastaInCookingPot2" then
                output:add(wetPasta)
            else
                output:add(pastaBowl1)
                output:add(pastaBowl2)
                output:add(pastaEmptyPot)
            end
        end,
    }
end }
ISHandcraftAction = { FromLogic = function(logic)
    return { logic = logic,
        performRecipe = function()
            if logic.recipe.name == "PlacePastaInCookingPot2" then
                actorInventory:Remove(pastaPot)
                actorInventory:Remove(dryPasta)
                actorInventory:AddItem(wetPasta)
            else
                actorInventory:Remove(pastaDish)
                actorInventory:Remove(bowl1)
                actorInventory:Remove(bowl2)
                actorInventory:AddItem(pastaBowl1)
                actorInventory:AddItem(pastaBowl2)
                actorInventory:AddItem(pastaEmptyPot)
            end
        end,
        stop = function() end }
end }
ISAddItemInRecipe = { new = function(_, _, _, baseItem, usedItem)
    return { baseItem = baseItem, usedItem = usedItem,
        complete = function(self)
            actorInventory:Remove(self.baseItem)
            actorInventory:Remove(usedItem)
            actorInventory:AddItem(pastaDish)
            self.baseItem = pastaDish
            return true
        end,
        stop = function() end }
end }
shelf.items, actorInventory.items, fridge.items =
    { pastaPot, dryPasta, bowl1, bowl2, tomato }, {}, {}
world.completed = {}
for _ = 1, 8 do world.completed[#world.completed + 1] = { type = "cook" } end
chef.reset()
queuedAction = nil
local wrongFluidJob = { id = "job:pasta:wrong-fluid", type = "cook", target = {} }
pastaFluidType = "Bleach"
handled, progress = chef.update(actor, {}, wrongFluidJob, player)
assert(handled == false and progress == "chef_recipe_supplies_missing"
    and shelf:contains(pastaPot) and #actorInventory.items == 0,
    "a non-water-filled pot must be refused before withdrawal")
pastaFluidType = "Water"
pastaFluidWaterAmount = 1
chef.reset()
handled, progress = chef.update(actor, {}, wrongFluidJob, player)
assert(handled == false and progress == "chef_recipe_supplies_missing"
    and shelf:contains(pastaPot) and #actorInventory.items == 0,
    "a water-dominant mixture must not count as enough recipe water")
pastaFluidWaterAmount = 2
chef.reset()
-- A personally carried pot remains the companion's after cancellation, even
-- when native portioning has replaced it with a new tagged empty pot.
shelf.items, actorInventory.items, fridge.items =
    { dryPasta, bowl1, bowl2, tomato }, { pastaPot }, {}
local personalPotJob = { id = "job:pasta:own-pot", type = "cook",
    assignedId = actor.id, target = {} }
handled, progress = chef.update(actor, {}, personalPotJob, player)
assert(handled == true and personalPotJob.target.cookPhase == "pasta_prep_queued",
    "Chef can prepare dry pasta using a personally carried pot")
queuedAction:performRecipe()
for _ = 1, 5 do
    chef.update(actor, {}, personalPotJob, player)
    if personalPotJob.target.cookPhase == "combine_queued" then break end
end
assert(personalPotJob.target.cookPhase == "combine_queued")
queuedAction:complete()
chef.update(actor, {}, personalPotJob, player)
pastaFlags.cooked = true
chef.update(actor, {}, personalPotJob, player)
assert(personalPotJob.target.cookPhase == "portion_queued")
queuedAction:performRecipe()
cancelled, cancelReason = chef.cancelJob(personalPotJob, nil)
assert(cancelled == true and actorInventory:contains(pastaEmptyPot)
    and util.inventoryContains(fridge, pastaBowl1)
    and util.inventoryContains(fridge, pastaBowl2),
    "cancellation stores cooked portions but keeps the personal pot: "
        .. tostring(cancelReason))
pastaFlags.cooked = false
shelf.items, actorInventory.items, fridge.items =
    { pastaPot, dryPasta, bowl1, bowl2, tomato }, {}, {}
ovenContainer.items = {}
chef.reset()
local pastaJob = { id = "job:pasta", type = "cook", target = {} }
handled, progress = chef.update(actor, {}, pastaJob, player)
assert(handled == true and pastaJob.target.recipe == "pasta"
    and pastaJob.target.cookPhase == "pasta_prep_queued"
    and queuedAction ~= nil,
    "dry pasta and a water-filled pot enter native preparation")
queuedAction:performRecipe()
chef.reset()
for _ = 1, 5 do
    handled, progress = chef.update(actor, {}, pastaJob, player)
    if pastaJob.target.cookPhase == "combine_queued" then break end
end
assert(handled == true and pastaJob.target.cookPhase == "combine_queued"
    and queuedAction.usedItem == tomato and wetPastaData.SC_ChefPrepJobId
        == pastaJob.id,
    "prepared pasta survives reload and gets a native topping")
queuedAction:complete()
chef.update(actor, {}, pastaJob, player)
assert(ovenContainer:contains(pastaDish) and not chef.isPrepared(pastaDish),
    "raw pasta is kept in the cooker")
pastaFlags.cooked = true
chef.update(actor, {}, pastaJob, player)
assert(pastaJob.target.cookPhase == "portion_queued",
    "cooked pasta enters native bowl division")
queuedAction:performRecipe()
for _ = 1, 3 do
    handled, progress, _, completed = chef.update(actor, {}, pastaJob, player)
end
assert(handled == true and completed == true
    and util.inventoryContains(fridge, pastaBowl1)
    and util.inventoryContains(fridge, pastaBowl2)
    and util.inventoryContains(shelf, pastaEmptyPot)
    and pastaBowlData1.SC_ChefJobId == pastaJob.id
    and pastaBowlData2.SC_ChefPortionIndex == 2,
    "Chef stores two pasta bowls and returns the pot")
instanceof, getScriptManager, HandcraftLogic, ISHandcraftAction =
    oldInstanceof, oldManager, oldLogic, oldHandcraft
ISToggleStoveAction = oldToggle
getEvolvedRecipes, ArrayList, ISAddItemInRecipe, ISTimedActionQueue =
    oldRecipes, oldList, oldAction, oldQueue
instanceItem = oldInstanceItem

for index = #saved, 1, -1 do
    local row = saved[index]
    row.object[row.key] = row.value
end
chef.reset()
print("CHEF_HARNESS_PASS")
