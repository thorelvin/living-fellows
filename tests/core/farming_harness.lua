-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local FarmWork = SC.FarmWork
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then error("check " .. tostring(checks) .. " failed: " .. message) end
end

local clock, hour = 1000, 12
SC.GameplayUtil.nowMs = function() return clock end
SC.GameplayUtil.config = function(key)
    local values = {
        farmScanSquaresPerSlice = 4, farmRecoveryPerPulse = 2,
        farmSeedSpareReserve = 2, campStorageItemBudget = 80,
        farmDayStartHour = 6, farmDayEndHour = 21,
    }
    return values[key]
end

function getGameTime()
    return {
        getTimeOfDay = function() return hour end,
        getMonth = function() return 4 end,
    }
end

function getSandboxOptions()
    return {
        getOptionByName = function()
            return { getValue = function() return true end }
        end,
    }
end

local foodType = { toString = function() return "Food" end }
ScriptManager = { instance = {
    getItem = function(_, itemType)
        if itemType == "Base.Tomato" then
            return { getItemType = function() return foodType end }
        end
        return nil
    end,
} }

farming_vegetableconf = { props = {
    Tomato = {
        vegetableName = "Base.Tomato", seedTypes = { "Base.TomatoSeed" },
        sowMonth = { 5 }, bestMonth = { 5 }, riskMonth = {}, growBack = 2,
    },
} }

local function square(x, y, plant)
    return { x = x, y = y, z = 0, plant = plant,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function(self) return self.z end }
end

local squares = {}
SC.GameplayUtil.gridSquare = function(x, y, z)
    return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)]
end
SC.GameplayUtil.position = function(value)
    return value and value.x, value and value.y, value and value.z
end

CFarmingSystem = { instance = {
    getLuaObjectOnSquare = function(_, value) return value and value.plant or nil end,
} }

local base
local storage = { id = "storage:1", category = "farming", withdrawals = true }
local seed = {
    fullType = "Base.TomatoSeed", tags = {}, modData = {},
    getFullType = function(self) return self.fullType end,
    getType = function() return "TomatoSeed" end,
    getModData = function(self) return self.modData end,
    getContainer = function(self) return self.container end,
    hasTag = function(self, tag) return self.tags[string.lower(tostring(tag))] == true end,
}
local seedContainer = { items = { seed }, getItems = function(self) return self.items end }
seed.container = seedContainer

SC.BaseLife = {
    active = function() return base end,
    isInside = function(value)
        local x, y, z = SC.GameplayUtil.position(value)
        for _, zone in ipairs(base and base.zones or {}) do
            if zone.kind == "area" and zone.z == z and x >= zone.x1 and x <= zone.x2
                and y >= zone.y1 and y <= zone.y2 then return true, zone end
        end
        return false
    end,
    storageRows = function(category)
        if category == "farming" then return { storage } end
        if category == "food" then return { { id = "storage:2", category = "food" } } end
        return {}
    end,
    resolveContainer = function(row)
        if row and row.id == storage.id then return seedContainer end
        return { items = {}, getItems = function(self) return self.items end }
    end,
    availableCount = function() return 1 end,
    enqueueJob = function(spec)
        spec.id, spec.state = "job:" .. tostring(#base.jobs + 1), "pending"
        base.jobs[#base.jobs + 1] = spec
        return true, spec
    end,
    farmReceipts = function() return {} end,
    resident = function() return nil end,
}

SC.Registry = { byId = function() return nil end }

local ripe = {
    state = "seeded", typeOfSeed = "Tomato", hasVegetable = true,
    hasSeeds = false, waterLvl = 80, waterNeeded = 70,
    canHarvest = function() return true end,
}
local farmSquare = square(1, 1, ripe)
squares["1:1:0"] = farmSquare
base = {
    zones = {
        { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 3, y2 = 3, z = 0 },
        { id = "zone:farm", kind = "farm", x1 = 1, y1 = 1, x2 = 1, y2 = 1, z = 0 },
    },
    jobs = {}, storages = { storage },
}

local queued, job = FarmWork.audit(base)
check(queued == true, "a ripe grow-back crop queues farm work")
check(job.type == "farm" and job.target.operation == "harvest", "harvest job shape is explicit")
check(job.target.zoneId == "zone:farm" and job.target.x == 1 and job.target.y == 1,
    "harvest job remains tied to its farm zone and tile")

base.jobs = {}
farmSquare.plant = nil
queued = FarmWork.audit(base)
check(queued == false, "an untouched square is never plowed")

local remotePlant = {
    state = "seeded", typeOfSeed = "Tomato", hasVegetable = true,
    hasSeeds = false, waterLvl = 80, waterNeeded = 70,
    canHarvest = function() return true end,
}
local remoteSquare = square(10, 10, remotePlant)
squares["10:10:0"] = remoteSquare
base.zones[2] = { id = "zone:remote", kind = "farm", x1 = 10, y1 = 10,
    x2 = 10, y2 = 10, z = 0 }
hour = 22
queued = FarmWork.audit(base)
check(queued == false, "outside farm work is not queued at night")

FarmWork.reset()
hour = 12
base.jobs = {}
local secondRipe = {
    state = "seeded", typeOfSeed = "Tomato", hasVegetable = true,
    hasSeeds = false, waterLvl = 80, waterNeeded = 70,
    canHarvest = function() return true end,
}
squares["20:20:0"] = square(20, 20, nil)
squares["21:21:0"] = square(21, 21, secondRipe)
base.zones = {
    { id = "zone:area", kind = "area", x1 = 0, y1 = 0, x2 = 30, y2 = 30, z = 0 },
    { id = "zone:farm-a", kind = "farm", x1 = 20, y1 = 20, x2 = 20, y2 = 20, z = 0 },
    { id = "zone:farm-b", kind = "farm", x1 = 21, y1 = 21, x2 = 21, y2 = 21, z = 0 },
}
queued, job = FarmWork.audit(base)
check(queued == true and job.target.zoneId == "zone:farm-b",
    "bounded scans rotate fairly across multiple farm zones")

Perks.Farming = { name = "Farming" }
local skilled = { getPerkLevel = function() return 4 end }
local modifier, eligible = FarmWork.jobModifier("worker", { target = { minFarming = 3 } },
    nil, { actor = skilled })
check(eligible == true and modifier == 12, "real Farming skill adds three score per level")
local novice = { getPerkLevel = function() return 2 end }
modifier, eligible = FarmWork.jobModifier("worker", { target = { minFarming = 3 } },
    nil, { actor = novice })
check(eligible == false, "disease treatment respects the Farming 3 requirement")

local shovel = {
    fullType = "Base.Shovel", getFullType = function(self) return self.fullType end,
    hasTag = function(_, tag) return tostring(tag) == "DIG_PLOW" end,
}
check(FarmWork.isFarmingSupply(seed) == true, "seeds classify as farming supplies")
check(FarmWork.isFarmingSupply(shovel) == true, "plowing tools classify as farming supplies")

print("FARMING_KAHLUA_PASS checks=" .. tostring(checks))
