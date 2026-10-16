-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, SC_REFUEL_TEST
Fluid.Water, Fluid.TaintedWater = "water", "tainted"

local car, actor, storage = T.car, T.actor, T.storage
function actor:getX() return self.square.x + 0.5 end
function actor:getY() return self.square.y + 0.5 end
local second = { id = "water:1", category = "water", reserve = 0,
    container = { items = {} } }
local tires = {
    { id = "TireFrontLeft", current = 20, capacity = 35, area = "TireFrontLeft" },
    { id = "TireFrontRight", current = 20, capacity = 35, area = "TireFrontRight" },
}
for _, tire in ipairs(tires) do
    function tire:getId() return self.id end
    function tire:getContainerContentType() return "Air" end
    function tire:getInventoryItem() return self end
    function tire:getContainerContentAmount() return self.current end
    function tire:getContainerCapacity() return self.capacity end
    function tire:getArea() return self.area end
end
local blood = { Front = 0.25, Rear = 0, Left = 0, Right = 0 }
local script = { getAreaById = function(_, area) return area end }
function car:getPartCount() return #tires end
function car:getPartByIndex(index) return tires[index + 1] end
function car:getPartById(id)
    for _, tire in ipairs(tires) do if tire.id == id then return tire end end
end
function car:getMaxPassengers() return 2 end
function car:getCharacter(seat) return self.occupied and seat == 0 and actor or nil end
function car:getScript() return script end
function car:getBloodIntensity(area) return blood[area] end
function car:isInArea() return true end

SC.BaseLife.storageRows = function(_, withdrawals)
    return withdrawals and { storage, second } or { storage, second }
end
SC.BaseLife.storage = function(id)
    if id == storage.id then return storage end
    if id == second.id then return second end
end
local native
SC.NativeActions.startTireInflation = function(_, _, part, item)
    native = { kind = "inflate_tires", part = part, item = item, active = true }
    return true
end
SC.NativeActions.startVehicleWash = function(_, _, areaId, area, item)
    native = { kind = "wash_vehicle", areaId = areaId, area = area,
        item = item, active = true }
    return true
end
SC.NativeActions.workKind = function() return native and native.kind end
SC.NativeActions.isWorkActive = function() return native and native.active or false end
SC.NativeActions.finishWork = function()
    if native and native.active then return false, "work_action_still_active" end
    native = nil
    return true
end
SC.NativeActions.cancelWork = function() native = nil return true end

local function item(id, kind, amount, tainted)
    local result = { id = id, kind = kind, data = {} }
    function result:getID() return self.id end
    if kind ~= "Base.TirePump" then
        local fluid = { amount = amount, tainted = tainted }
        function fluid:getAmount() return self.amount end
        function fluid:contains(value)
            return self.amount > 0 and value == (self.tainted
                and Fluid.TaintedWater or Fluid.Water)
        end
        result.fluid = fluid
        function result:getFluidContainer() return self.fluid end
    end
    return result
end
SC_UPKEEP_TEST = {
    car = car, actor = actor, storage = storage, waterStorage = second,
    base = T.base, tires = tires, blood = blood, item = item,
    native = function() return native end,
    finish = function(delta)
        if not native then return end
        if native.kind == "inflate_tires" then
            native.part.current = math.min(native.part.capacity,
                native.part.current + (delta or 15))
        else
            local fluid = native.item.fluid
            local used = math.min(fluid.amount, delta or 1)
            fluid.amount = fluid.amount - used
            blood[native.areaId] = math.max(0, blood[native.areaId] - used * 0.05)
        end
        native.active = false
    end,
    resetNative = function() native = nil end,
}
