-- SPDX-License-Identifier: MIT
-- Native chicken work participates only through SCFarmWork's existing lane.
local SC = SurvivorCompanion
SC.AnimalWork = SC.AnimalWork or {}
local A = SC.AnimalWork
local scan, zoneCursor, knownBase, lastAudit = nil, 0, nil, -math.huge
local zoneVisited, zoneCycleSize = 0, 0
local snapshots, claims = {}, {}
local refreshes = {}

A.species = {
    chicken = { kinds = { hen = true, cockerel = true, chick = true },
        feeds = { AnimalFeed = true, Grass = true, Hay = true, Vegetables = true,
            Fruits = true, Seeds = true, Nuts = true, Nut = true, Insect = true },
        hutch = "hutchhen", dawn = 7, dusk = 20, minimumHens = 2, minimumRoosters = 1 },
}

local function U() return SC.GameplayUtil end
local function C(key, fallback)
    local value = tonumber(U().config(key))
    return value and value == value and value ~= math.huge and value ~= -math.huge and value or fallback
end
local function read(object, method, ...) return U().call(object, method, ...) end
local function value(object, method, ...)
    local result = read(object, method, ...)
    return result
end
local function n(object, method, ...) return tonumber(value(object, method, ...)) end
local function size(list) return SC.NativeList.size(list) end
local function at(list, i) return select(1, SC.NativeList.get(list, i)) end
local function now() return U().nowMs() end
local function support() return SC.FarmWork.animalSupport end
local function key(object)
    local x, y, z = U().position(object)
    if not x or not y or not z then return nil end
    local family = value(object, "getHutch") ~= nil and "hutch:" or "trough:"
    return family .. math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z)
end
local function time()
    if type(getGameTime) ~= "function" then return nil, nil end
    local okay, gt = pcall(getGameTime)
    if not okay then return nil, nil end
    return n(gt, "getTimeOfDay"), n(gt, "getWorldAgeHours")
end
local function enabled() return C("animalWorkEnabled", 1) == 1 end
local function document()
    return SC.BaseLife and SC.BaseLife.animalDocument and SC.BaseLife.animalDocument() or nil
end
local function note()
    if SC.BaseLife.noteWorkOwnershipMutation then SC.BaseLife.noteWorkOwnershipMutation() end
end

local function coverageStamp(base)
    local parts = { tostring(base and base.id) }
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" then
            parts[#parts + 1] = table.concat({ tostring(zone.id), zone.x1, zone.y1,
                zone.x2, zone.y2, zone.z }, ":")
        end
    end
    return table.concat(parts, "|")
end

local function workDay(object)
    local hour = time()
    return SC.BaseLife.isOutdoorSquare(U().squareOf(object)) ~= true
        or (SC.BaseLife.policies() or {}).workOutsideAtNight == true
        or hour ~= nil and hour >= A.species.chicken.dawn and hour < A.species.chicken.dusk
end

function A.isFeed(item)
    return item ~= nil and A.species.chicken.feeds[value(item, "getAnimalFeedType")] == true
        and value(item, "isRotten") ~= true
end

function A.feedAmount(item)
    if not A.isFeed(item) then return nil end
    local hunger = n(item, "getHungerChange")
    if hunger then return math.abs(hunger) end
    local uses = n(item, "getCurrentUses")
    if uses then return math.max(0, uses * 0.1) end
    return nil
end

-- Stable choice within one game-minute bucket, including after save/load.
function A.choose(actorId, crop, animal)
    if not crop then return animal end
    if not animal then return crop end
    local _, hours = time()
    if hours == nil then return crop end
    return U().stableHash(tostring(actorId) .. ":farm:" .. math.floor(hours * 60)) % 2 == 0
        and animal or crop
end

local function zoneFacts(zone)
    local x, y, z, w, h = n(zone, "getX"), n(zone, "getY"), n(zone, "getZ"),
        n(zone, "getW"), n(zone, "getH")
    local id = value(zone, "getId")
    if not id or not x or not y or not z or not w or not h
        or w < 1 or h < 1 or w * h > 256 then return nil end
    return { id = tostring(id), native = zone, x1 = x, y1 = y, z = z,
        x2 = x + w - 1, y2 = y + h - 1, width = w, total = w * h,
        index = 0, animals = {}, members = {}, seen = {}, hutches = {}, troughs = {},
        hutchIndex = 0, complete = true, capacity = 0, hens = 0, roosters = 0, chicks = 0 }
end

local function contains(row, object)
    local x, y, z = U().position(object)
    return x and z == row.z and x >= row.x1 and x < row.x2 + 1
        and y >= row.y1 and y < row.y2 + 1
end

local function remember(row)
    if not snapshots[row.id] then
        local count, oldest, oldestAt = 0, nil, math.huge
        for id, cached in pairs(snapshots) do
            count=count+1
            if cached.auditedAt < oldestAt then oldest,oldestAt=id,cached.auditedAt end
        end
        if count >= 8 then snapshots[oldest]=nil end
    end
    snapshots[row.id]=row
end

local function zoneUnchanged(row)
    return n(row.native,"getX")==row.x1 and n(row.native,"getY")==row.y1
        and n(row.native,"getZ")==row.z and n(row.native,"getW")==row.width
        and n(row.native,"getH")==row.total/row.width
end

local function inspectAnimal(row, animal)
    local id = n(animal, "getAnimalID")
    if not id or id < 0 then row.complete = false return end
    if row.seen[id] then return end
    row.seen[id] = true
    if #row.animals >= 128 then row.complete = false return end
    local kind = value(animal, "getAnimalType")
    if not A.species.chicken.kinds[kind] then row.mixed = true return end
    local data, ok = read(animal, "getModData")
    if not ok or type(data) ~= "table" then row.complete = false return end
    if data.lfOddballGroupId ~= nil or data.lfWendellGroupId ~= nil then row.protected = true end
    if (n(animal, "getHealth") or 0) <= 0 then return end
    row.members[id] = animal -- Runtime only; never copied into the save document.
    local baby, babyOkay = read(animal, "isBaby")
    local name, nameOkay = read(animal, "getCustomName")
    local held, heldOkay = read(animal, "isHeld")
    local age = n(animal, "getAge")
    local animalData = value(animal, "getData")
    local female, femaleOkay = read(animalData, "isFemale")
    local cullKnown, led, wild, laying = false, nil, nil, nil
    if C("animalCullEnabled",0)==1 then
        local player,playerKnown=read(animalData,"getAttachedPlayer")
        local tree,treeKnown=read(animalData,"getAttachedTree")
        local wildKnown
        wild,wildKnown=read(animal,"isWild")
        local layingKnown=femaleOkay and female==false
        laying=false
        if female==true and type(getGameTime)=="function" then
            local okay,gt=pcall(getGameTime)
            local calendar=okay and value(gt,"getCalender")
            if calendar then laying,layingKnown=read(animalData,"isInLayingEggPeriod",calendar) end
        end
        led=player~=nil or tree~=nil
        cullKnown=nameOkay and heldOkay and femaleOkay and playerKnown and treeKnown
            and wildKnown and layingKnown and age~=nil and age>=0
    end
    if not babyOkay or not nameOkay or not heldOkay or not femaleOkay or not age then
        row.complete = false
    end
    row.animals[#row.animals + 1] = { id = id, kind = kind, baby = baby == true,
        name = name, held = held, age = age, female = female,
        cullKnown = cullKnown, led = led, wild = wild, laying = laying,
        oddball = data.lfOddballGroupId ~= nil or data.lfWendellGroupId ~= nil }
    if baby == true then row.chicks = row.chicks + 1
    elseif female == true then row.hens = row.hens + 1
    else row.roosters = row.roosters + 1 end
end

local function allowedBudget(kind, count)
    if SC.Performance and SC.Performance.claimUnits then
        return SC.Performance.claimUnits(kind, count, false, true)
    end
    return count
end
local function outOfTime(start)
    local remaining = SC.Performance and SC.Performance.remainingBudgetMs()
    return SC.Performance and (SC.Performance.preciseNowMs() - start >= 1.5
        or remaining ~= nil and remaining <= 0)
end

-- No whole-world animal census. Rectangle coverage, square animals and hutch
-- occupants each resume their own cursor; unknown evidence is never absence.
local function advance(row, squareLimit)
    local start = SC.Performance and SC.Performance.preciseNowMs() or 0
    local squares, unitClaim = allowedBudget("scavengeSquares", squareLimit or 16)
    local usedSquares = 0
    local function done(complete)
        if unitClaim and SC.Performance and SC.Performance.settleUnits then
            SC.Performance.settleUnits(unitClaim, usedSquares)
        end
        return complete
    end
    local animalBudget = math.min(32, math.max(1, C("animalAuditAnimalBudget", 32)))
    while row.index < row.total and squares > 0 and animalBudget > 0 do
        if outOfTime(start) then return done(false) end
        local x = row.x1 + row.index % row.width
        local y = row.y1 + math.floor(row.index / row.width)
        if SC.BaseLife.isInside({ x = x, y = y, z = row.z }) ~= true then
            row.rejected = true return done(true)
        end
        local square = U().gridSquare(x, y, row.z)
        usedSquares=usedSquares+1
        if not square then row.complete = false end
        local animals, available = read(square, "getAnimals")
        if square and not available then row.complete = false end
        local count = size(animals)
        row.animalIndex = row.animalIndex or 0
        while row.animalIndex < count and animalBudget > 0 do
            inspectAnimal(row, at(animals, row.animalIndex))
            row.animalIndex, animalBudget = row.animalIndex + 1, animalBudget - 1
        end
        if row.animalIndex < count then return done(false) end
        row.index, row.animalIndex, squares = row.index + 1, nil, squares - 1
    end
    if row.index < row.total then return done(false) end
    if not row.objectsRead then
        if value(row.native, "isFullyStreamed") ~= true then row.complete = false end
        for _, spec in ipairs({ { "getHutchs", row.hutches }, { "getTroughs", row.troughs } }) do
            local objects, okay = read(row.native, spec[1])
            if not okay or size(objects) > 8 then row.complete = false return done(true) end
            local seen = {}
            for i = 0, size(objects) - 1 do
                local object = at(objects, i)
                if spec[1] == "getHutchs" then object = value(object, "getHutch") end
                if object and not seen[object] and contains(row, object) then
                    spec[2][#spec[2] + 1], seen[object] = object, true
                end
            end
        end
        row.objectsRead = true
    end
    while row.hutchIndex < #row.hutches and animalBudget > 0 do
        if outOfTime(start) then return done(false) end
        local hutch = row.hutches[row.hutchIndex + 1]
        if not row.occupants then
            local capacity = n(hutch, "getMaxAnimals")
            if not capacity then row.complete = false return done(true) end
            row.capacity = row.capacity + capacity
            local occupants = value(hutch, "getAnimalInside")
            local values = value(occupants, "values")
            local count = n(occupants, "size")
            if not count or count > 128 or not ArrayList or not ArrayList.new then
                row.complete = false return done(true)
            end
            local made, copied = pcall(ArrayList.new)
            local _, added = read(made and copied or nil, "addAll", values)
            if not made or not added or size(copied) ~= count then row.complete = false return done(true) end
            row.occupants, row.occupantIndex = copied, 0
        end
        while row.occupantIndex < size(row.occupants) and animalBudget > 0 do
            inspectAnimal(row, at(row.occupants, row.occupantIndex))
            row.occupantIndex = row.occupantIndex + 1
            animalBudget = animalBudget - 1
        end
        if row.occupantIndex < size(row.occupants) then return done(false) end
        local chicken = row.animals[1] and row.members[row.animals[1].id]
        local compatible, exposed = read(chicken, "canBePutInHutch", hutch)
        if not exposed then row.complete = false
        elseif compatible ~= true then row.mixed = true end
        row.occupants, row.occupantIndex, row.hutchIndex = nil, nil, row.hutchIndex + 1
    end
    return done(row.hutchIndex >= #row.hutches)
end

local function openJob(base, object)
    local targetKey = key(object)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "farm" and job.target and job.target.animal
            and job.target.deviceKey == targetKey
            and job.state ~= "completed" and job.state ~= "cancelled" then return true end
    end
    return false
end

local function candidateAt(row, operation, object, priority)
    local x, y, z = U().position(object)
    return { animal = true, operation = operation, priority = priority or 4,
        zoneId = "animal:" .. row.id, nativeZoneId = row.id,
        deviceKey = key(object), x = math.floor(x), y = math.floor(y), z = z }
end

-- A missing capacity or access reading is a refusal, including before pickup.
function A.foodDestination(actor, item)
    if not SC.WorkTransport or not SC.WorkTransport.hasRoom then return nil end
    for index, storage in ipairs(SC.BaseLife.foodDepositRows(item)) do
        if index > 32 then break end
        local container = SC.BaseLife.resolveContainer(storage)
        if container and SC.BaseLife.storageAcceptsDeposit(storage, container) == true
            and SC.WorkTransport.hasRoom(container, actor, item) == true then return storage end
    end
    return nil
end

-- Pure policy; no animal, egg or inventory mutation. A forecast must come from
-- verified native evidence before this policy may permit breeding or culling.
function A.flockTarget(capacity)
    capacity=tonumber(capacity)
    if not capacity or capacity~=capacity or capacity==math.huge or capacity<4 then
        return nil,"animal_roost_capacity_low"
    end
    capacity=math.floor(capacity)
    local minimum=A.species.chicken
    local reserve=math.min(capacity-3,math.max(1,math.ceil(capacity
        *math.max(0,math.min(100,C("animalHutchReservePercent",10)))/100)))
    local roosters=minimum.minimumRoosters
    local hens=capacity-reserve-roosters
    if hens>math.max(2,C("animalSecondRoosterHens",12)) then
        roosters=2
        hens=capacity-reserve-roosters
    end
    return {capacity=capacity,reserve=reserve,hens=hens,roosters=roosters}
end

function A.breedingPlan(row,forecast)
    local target,reason=A.flockTarget(row and row.capacity)
    if not target then return {verified=false,reason=reason} end
    target.verified=false
    if not row.complete or row.protected or row.mixed then
        target.reason="animal_audit_incomplete" return target
    end
    local stock=forecast and tonumber(forecast.stock)
    local rate=forecast and tonumber(forecast.dailyPerBird)
    if not forecast or forecast.verified~=true or not stock or stock~=stock or stock<0
        or stock==math.huge or not rate or rate~=rate or rate<=0 or rate==math.huge then
        target.reason="animal_feed_forecast_unverified" return target
    end
    local days=math.max(1,C("animalFeedHorizonDays",3))
    local supported=math.floor(stock/(rate*days))
    if supported<target.hens+target.roosters then
        target.roosters=A.species.chicken.minimumRoosters
        target.hens=math.max(A.species.chicken.minimumHens,
            math.min(target.hens,supported-target.roosters))
    end
    local chicks=math.max(0,tonumber(row.chicks) or 0)
    local count=(tonumber(row.hens) or 0)+(tonumber(row.roosters) or 0)+chicks
    target.verified,target.feedEnough=true,supported>=count
    -- Count all chicks as potential hens until a complete native sex census
    -- proves otherwise. Never hatch extra chicks merely to guess their sex.
    target.retain=target.feedEnough and (tonumber(row.roosters) or 0)>0
        and math.max(0,math.min(target.hens-(tonumber(row.hens) or 0)-chicks,
            target.capacity-target.reserve-count,supported-count)) or 0
    target.reason=not target.feedEnough and "animal_feed_horizon_low" or nil
    return target
end

function A.eggRetention(plan,ids,complete)
    if not plan or plan.verified~=true or complete~=true or type(ids)~="table" or #ids>128 then
        return nil,"animal_egg_census_incomplete"
    end
    local ordered,seen={},{}
    for index=1,#ids do
        local id=ids[index]
        if type(id)~="number" or id~=id or id<0 or id==math.huge or seen[id] then
            return nil,"animal_egg_census_incomplete"
        end
        ordered[#ordered+1],seen[id]=id,true
    end
    table.sort(ordered)
    local keep={}
    for index=1,math.min(#ordered,math.max(0,tonumber(plan.retain) or 0)) do
        keep[tostring(ordered[index])]=true
    end
    return keep
end

function A.keepEgg(row, egg)
    local fertile, okay = read(egg, "isFertilized")
    -- Until a breeding/feed-horizon audit can prove otherwise, protect fertile
    -- eggs. Never rearrange nest contents merely to reach another egg.
    if not okay then return true end
    if fertile~=true then return false end
    local policy=row and row.eggPolicy
    if C("animalBreedingEnabled",0)~=1 or not policy or policy.verified~=true
        or type(policy.keep)~="table" then return true end
    local id=n(egg,"getID")
    return id==nil or policy.keep[tostring(id)]==true
end

function A.cullsToday(saved,hours)
    hours=tonumber(hours)
    if not hours or hours~=hours or hours<0 or hours==math.huge then return nil end
    if saved==nil then return 0 end
    if type(saved)~="table" then return nil end
    if saved.cullDay==nil and saved.culls==nil then return 0 end
    local day,count=tonumber(saved.cullDay),tonumber(saved.culls)
    if not day or day~=day or day<0 or day%1~=0 or day>math.floor(hours/24)
        or not count or count~=count or count<0 or count%1~=0 then return nil end
    return day==math.floor(hours/24) and count or 0
end

-- Read-only admission policy, not a kill command. Native corpse attribution,
-- output forecasts and the irreversible action chain remain unvalidated and
-- deliberately have no production dispatcher in this release.
function A.cullPlan(row,plan,evidence)
    if C("animalCullEnabled",0)~=1 then return nil,"animal_cull_disabled" end
    if type(row)~="table" or row.complete~=true or row.protected or row.mixed
        or type(row.animals)~="table" or type(plan)~="table" or plan.verified~=true
        or type(plan.hens)~="number" or type(plan.roosters)~="number"
        or plan.hens~=plan.hens or plan.roosters~=plan.roosters
        or type(row.hens)~="number" or type(row.roosters)~="number" or type(row.chicks)~="number"
        or plan.hens<A.species.chicken.minimumHens
        or plan.roosters<A.species.chicken.minimumRoosters then return nil,"animal_audit_incomplete" end
    local age=tonumber(row.auditedAt) and now()-row.auditedAt
    if not age or age<0 or age>15000 or #row.animals>128
        or #row.animals~=row.hens+row.roosters+row.chicks then return nil,"animal_audit_incomplete" end
    if type(evidence)~="table" or evidence.populationComplete~=true or evidence.safe~=true
        or evidence.daylight~=true or evidence.toolsVerified~=true
        or evidence.outputCapacityVerified~=true or evidence.claimAvailable~=true then
        return nil,"animal_cull_evidence_missing"
    end
    local _,hours=time()
    local used=A.cullsToday(evidence.counters,hours)
    local limit=math.min(1,math.max(0,math.floor(C("animalCullPerZonePerDay",1))))
    if used==nil then return nil,"animal_cull_counter_unverified" end
    if used>=limit then return nil,"animal_cull_daily_limit" end
    local candidates,seen={},{}
    for _,bird in ipairs(row.animals) do
        if type(bird)~="table" or type(bird.id)~="number" or bird.id~=bird.id
            or bird.id<0 or bird.id==math.huge or seen[bird.id] then return nil,"animal_audit_incomplete" end
        seen[bird.id]=true
        if bird.cullKnown==true and bird.baby==false and bird.oddball~=true
            and bird.held==false and bird.led==false and bird.wild==false
            and (bird.name==nil or bird.name=="") and type(bird.age)=="number"
            and bird.age==bird.age and bird.age>=0 and bird.age<math.huge then
            local rank
            if bird.female==false and row.roosters>plan.roosters then rank=1
            elseif bird.female==true and row.hens>plan.hens then rank=bird.laying==false and 2 or 3 end
            if rank then candidates[#candidates+1]={id=bird.id,rank=rank,age=bird.age} end
        end
    end
    table.sort(candidates,function(a,b)
        if a.rank~=b.rank then return a.rank<b.rank end
        if a.age~=b.age then return a.age>b.age end
        return a.id<b.id
    end)
    return candidates[1] and candidates[1].id or nil,"animal_cull_proposal_only"
end

local function eggCandidate(row, base)
    for _, hutch in ipairs(row.hutches) do
        if not openJob(base, hutch) and workDay(hutch) then
            local maximum = n(hutch, "getMaxNestBox")
            if maximum and maximum >= 0 and maximum <= 15 then
                for index = 0, maximum do
                    local nest = value(hutch, "getNestBox", index)
                    local count = n(nest, "getEggsNb")
                    local egg = count and count > 0 and value(nest, "getEgg", 0)
                    if egg and not A.keepEgg(row, egg) then
                        local result = candidateAt(row, "animal_egg", hutch, 3)
                        result.nestIndex = index
                        return result
                    end
                end
            end
        end
    end
end

function A.nightClosingJob(job)
    return enabled() and C("animalCloseEnabled", 0) == 1 and job and job.type == "farm"
        and job.target and job.target.animal == true and job.target.operation == "animal_close"
end

function A.hutchOperation(hour, closed, inside, total)
    if hour == nil or type(closed) ~= "boolean" then return nil end
    local species = A.species.chicken
    local night = hour >= species.dusk or hour < species.dawn
    if night and not closed and C("animalCloseEnabled", 0) == 1 then
        local elapsed = ((hour - species.dusk) % 24) * 60
        if inside ~= nil and total ~= nil and (inside >= total
            or elapsed >= C("animalDuskGraceMinutes", 60)) then return "animal_close" end
    elseif not night and closed then return "animal_open" end
    return nil
end

local function hutchCandidate(row, base)
    local hour = time()
    for _, hutch in ipairs(row.hutches) do
        if not openJob(base, hutch) then
            local operation = A.hutchOperation(hour, value(hutch, "isDoorClosed"),
                n(value(hutch, "getAnimalInside"), "size"), #row.animals)
            if operation then return candidateAt(row, operation, hutch, 4) end
        end
    end
    local egg = eggCandidate(row, base)
    if egg then return egg end
    if C("animalCleanEnabled", 0) == 1 then
        for _, hutch in ipairs(row.hutches) do
            if not openJob(base, hutch) and workDay(hutch) then
                if (n(hutch, "getHutchDirt") or 0) >= 25 then
                    return candidateAt(row, "animal_clean_floor", hutch, 2)
                elseif (n(hutch, "getNestBoxDirt") or 0) >= 25 then
                    return candidateAt(row, "animal_clean_nest", hutch, 2)
                end
            end
        end
    end
end

local function deviceCandidate(row, base)
    local high = math.min(1, math.max(0.01, C("animalFeedHighPercent", 90) / 100))
    local low = math.min(high, math.max(0, C("animalFeedLowPercent", 25) / 100))
    local best, waterAssigned, empty = nil, false, {}
    row.troughRoles = {}
    -- 42.22.2 troughs switch container mode when filled with fluid. Preserve
    -- occupied modes; choose one deterministic empty trough for water and use
    -- the remaining empty troughs for feed. Never erase feed to make water.
    for _, trough in ipairs(row.troughs) do
        local water, feed = n(trough, "getWater"), n(trough, "getCurrentFeedAmount")
        local container = value(trough, "getContainer")
        local items, itemsKnown = read(container, "getItems")
        if water and water > 0 then
            row.troughRoles[key(trough)], waterAssigned = "water", true
        elseif feed and feed > 0 or container and itemsKnown and size(items) > 0 then
            row.troughRoles[key(trough)] = "feed"
        elseif water ~= nil and feed ~= nil then empty[#empty+1] = trough end
    end
    table.sort(empty, function(a,b) return key(a) < key(b) end)
    for _, trough in ipairs(empty) do
        row.troughRoles[key(trough)] = waterAssigned and "feed" or "water"
        waterAssigned = true
    end
    for _, trough in ipairs(row.troughs) do
        if not openJob(base, trough) and workDay(trough) then
            local water, capacity = n(trough, "getWater"), n(trough, "getMaxWater")
            if row.troughRoles[key(trough)] == "water"
                and water and capacity and capacity > 0 and water < capacity * low then
                local result = candidateAt(row, "animal_water", trough, 5)
                result.high = capacity * high
                return result
            end
            local container = value(trough, "getContainer")
            local items = value(container, "getItems")
            if row.troughRoles[key(trough)] == "feed" and container and size(items) <= 64 then
                local feed, maxFeed = n(trough, "getCurrentFeedAmount"), n(trough, "getMaxFeed")
                if feed and maxFeed and maxFeed > 0 and feed < maxFeed * low and not best then
                    best = candidateAt(row, "animal_feed", trough)
                    best.high = maxFeed * high
                end
            end
        end
    end
    return best or hutchCandidate(row, base)
end

function A.candidate(base, squareLimit)
    if not enabled() or not document() then return nil end
    if base ~= knownBase then A.reset() knownBase = base end
    lastAudit = now()
    if not scan then
        if not DesignationZoneAnimal or not DesignationZoneAnimal.getAllZones then return nil end
        local okay, zones = pcall(DesignationZoneAnimal.getAllZones)
        if not okay or size(zones) == 0 then return nil end
        local count = size(zones)
        if count ~= zoneCycleSize then zoneVisited, zoneCycleSize = 0, count end
        local start = SC.Performance and SC.Performance.preciseNowMs() or 0
        for _=1,math.min(4,count-zoneVisited) do
            if outOfTime(start) then return nil, "animal_audit_pending", true end
            zoneCursor = zoneCursor % count
            local row = zoneFacts(at(zones, zoneCursor))
            zoneCursor, zoneVisited = zoneCursor + 1, zoneVisited + 1
            if row and SC.BaseLife.isInside({x=row.x1,y=row.y1,z=row.z}) == true then
                scan = row break
            end
        end
        if zoneVisited >= count then zoneVisited = 0 end
        if not scan then return nil, "animal_audit_pending", zoneVisited > 0 end
    end
    if not advance(scan, squareLimit) then return nil, "animal_audit_pending", true end
    local row = scan
    scan = nil
    if row.rejected or not row.complete or row.protected or row.mixed or #row.animals == 0 then
        snapshots[row.id] = nil
        local reason = row.rejected and "animal_zone_outside_camp"
            or not row.complete and "animal_audit_incomplete"
            or row.protected and "animal_story_animals"
            or row.mixed and "animal_species_not_supported" or "animal_flock_not_loaded"
        return nil, reason
    end
    row.auditedAt, row.coverageStamp = now(), coverageStamp(base)
    remember(row)
    local doc = document()
    local count, oldest, oldestAt = 0, nil, math.huge
    for id, saved in pairs(doc.zones) do
        if type(saved) ~= "table" then doc.zones[id] = nil
        else
            count = count + 1
            if (tonumber(saved.auditedAt) or 0) < oldestAt then
                oldest, oldestAt = id, tonumber(saved.auditedAt) or 0
            end
        end
    end
    if not doc.zones[row.id] and count >= math.min(8, math.max(1, C("animalMaxZones", 8))) then
        doc.zones[oldest], snapshots[oldest] = nil, nil
    end
    local saved = doc.zones[row.id] or { cooldowns = {} }
    saved.hens, saved.roosters, saved.chicks = row.hens, row.roosters, row.chicks
    saved.capacity, saved.auditedAt = row.capacity, row.auditedAt
    local target=A.breedingPlan(row,nil)
    saved.targetHens,saved.targetRoosters=target.hens,target.roosters
    saved.breedingBlocker=target.reason
    saved.cooldowns = type(saved.cooldowns) == "table" and saved.cooldowns or {}
    local currentDevices = {}
    for _, objects in ipairs({ row.hutches, row.troughs }) do
        for _, object in ipairs(objects) do currentDevices[key(object)] = true end
    end
    for device, cooldown in pairs(saved.cooldowns) do
        if not currentDevices[device] or type(cooldown) ~= "table"
            or (tonumber(cooldown.failures) or 0) >= 3 then
            saved.cooldowns[device] = nil -- A new complete audit wakes dormant candidates.
        end
    end
    doc.zones[row.id] = saved
    local selected = deviceCandidate(row, base)
    local water, feed = false, false
    for _, mode in pairs(row.troughRoles or {}) do
        water,feed=water or mode=="water",feed or mode=="feed"
    end
    saved.blocker = #row.hutches==0 and "animal_hutch_missing"
        or not water and "animal_water_trough_missing"
        or not feed and "animal_feed_trough_missing" or nil
    note()
    if selected then
        local cooldown = saved.cooldowns[selected.deviceKey]
        if cooldown and (tonumber(cooldown.untilMs) or 0) > now() then return nil end
    end
    return selected
end

-- Menu reads use the retained audit result, never a world scan.
function A.blocker()
    local doc = enabled() and document()
    local inspected=0
    for _, saved in pairs(doc and doc.zones or {}) do
        inspected=inspected+1
        if inspected>8 then break end
        local age=type(saved)=="table" and now()-(tonumber(saved.auditedAt) or 0)
        local code=type(saved)=="table" and saved.blocker
        if age and age>=0 and age<=180000 and (code=="animal_hutch_missing"
            or code=="animal_water_trough_missing" or code=="animal_feed_trough_missing") then return code end
    end
end

local function refreshTarget(target)
        local base = SC.BaseLife.active()
        if not DesignationZoneAnimal or not DesignationZoneAnimal.getZoneById then
            return nil, "animal_audit_pending"
        end
        local okay, zone = pcall(DesignationZoneAnimal.getZoneById, tonumber(target.nativeZoneId))
        if not okay or not zone then return nil, "animal_zone_missing" end
        local pending = refreshes[target.nativeZoneId] or zoneFacts(zone)
        if not pending then return nil, "animal_zone_unavailable" end
        if not refreshes[target.nativeZoneId] then
            local count = 0
            for _ in pairs(refreshes) do count=count+1 end
            if count >= 8 then return nil, "animal_audit_pending" end
        end
        refreshes[target.nativeZoneId] = pending
        if not advance(pending) then return nil, "animal_audit_pending" end
        refreshes[target.nativeZoneId] = nil
        if pending.rejected or not pending.complete or pending.protected or pending.mixed then
            snapshots[target.nativeZoneId] = nil
            return nil, "animal_zone_unavailable"
        end
        pending.auditedAt, pending.coverageStamp = now(), coverageStamp(base)
        remember(pending)
        return true
end

-- Effect guards are read-only: scans run in the farm decision, never in a
-- native action's per-frame update/complete callbacks.
local function findDevice(target)
    local row = snapshots[target.nativeZoneId]
    local base = SC.BaseLife.active()
    if not row or now() - row.auditedAt > 30000 or row.coverageStamp ~= coverageStamp(base)
        or not zoneUnchanged(row)
        or value(row.native, "isFullyStreamed") ~= true then return nil, "animal_audit_pending" end
    for _, list in ipairs({ row.troughs, row.hutches }) do
        for _, object in ipairs(list) do
            if key(object) == target.deviceKey and U().squareOf(object)
                and (n(object,"getObjectIndex") or -1)>=0
                and contains(row, object) and SC.BaseLife.isInside(object) == true then return object, row end
        end
    end
    return nil, "animal_device_unavailable"
end

-- Travel between camp areas may cross the existing bounded reach band.
-- This never grants permission to interact with a device outside camp.
function A.allowsWorkReach(job)
    local target = job and job.type == "farm" and job.target
    local row = target and target.animal and snapshots[target.nativeZoneId]
    -- An expired work snapshot must be refreshed by update, not divert travel
    -- to the rally point before that update can run. Effect guards stay fresh.
    return enabled() and row ~= nil and row.coverageStamp == coverageStamp(SC.BaseLife.active())
        and zoneUnchanged(row)
        and value(row.native, "isFullyStreamed") == true
        and SC.BaseLife.isInside(target) == true or false
end

local function claim(actor, job)
    local target, current = job.target, now()
    local id, active, workers = U().idOf(actor), 0, {}
    for k, held in pairs(claims) do
        if held.expires <= current then claims[k] = nil
        elseif held.zone == target.nativeZoneId and held.actor ~= id and not workers[held.actor] then
            active, workers[held.actor] = active + 1, true
        end
    end
    local held = claims[target.deviceKey]
    if held and (held.actor ~= id or held.job ~= job.id) or active >= 2 then return false end
    claims[target.deviceKey] = { actor = id, job = job.id,
        zone = target.nativeZoneId, expires = current + 30000 }
    return true
end

local function release(actor, job)
    local held = claims[job.target.deviceKey]
    if held and held.actor == U().idOf(actor) and held.job == job.id then
        claims[job.target.deviceKey] = nil
    end
end

local function fail(actor, job, reason)
    local doc = document()
    local saved = doc and doc.zones[job.target.nativeZoneId]
    if saved then
        local old = saved.cooldowns[job.target.deviceKey] or { failures = 0 }
        old.failures = math.min(3, old.failures + 1)
        old.at, old.untilMs = now(), now() + 15000 * 2 ^ (old.failures - 1)
        old.reason = reason
        saved.cooldowns[job.target.deviceKey] = old
        note()
    end
    release(actor, job)
    return false, reason, true
end

function A.retryDelay(job,reason)
    local target=job and job.type=="farm" and job.target
    local doc=target and target.animal and document()
    local saved=doc and doc.zones[target.nativeZoneId]
    local cooldown=saved and saved.cooldowns and saved.cooldowns[target.deviceKey]
    if type(cooldown)=="table" and cooldown.reason==reason then
        return math.max(15000,(tonumber(cooldown.untilMs) or now())-now())
    end
end

function A.borrowWasConsumed(receipt)
    local job = SC.BaseLife.job(receipt.jobId)
    if not job or not job.target or job.target.operation ~= "animal_feed" then return false end
    local object = findDevice(job.target)
    local container = object and value(object, "getContainer")
    local items = value(container, "getItems")
    if not container or size(items) > 64 then return false end
    for i = 0, size(items) - 1 do
        local item = at(items, i)
        local data = U().modData(item)
        if data and data[SC.FarmWork.ITEM_MARKER] == receipt.id
            and value(item, "getContainer") == container
            and value(container, "contains", item) == true then
            support().unmark(item, receipt.id)
            return true
        end
    end
    return false
end

function A.canUse(actor, job, object, item)
    local held = claims[job.target.deviceKey]
    local current = findDevice(job.target)
    if not enabled() or U().isDead(actor) or current ~= object
        or job.reservedBy ~= U().idOf(actor)
        or not held or held.actor ~= U().idOf(actor) or held.job ~= job.id
        or held.expires <= now() or support().threat(actor) then return false end
    if not workDay(object) and not A.nightClosingJob(job) then return false end
    local resident = SC.BaseLife.resident(U().idOf(actor))
    if not resident or resident.role ~= "farmer" or resident.duty ~= true then return false end
    if item and not U().inventoryContains(U().inventory(actor), item) then return false end
    local ax, ay, az = U().position(actor)
    local ox, oy, oz = U().position(object)
    if not ax or not ox or az ~= oz or (ax-ox)^2+(ay-oy)^2 > 6.25 then return false end
    if job.target.operation == "animal_feed" then
        local feed, maximum, amount = n(object, "getCurrentFeedAmount"),
            n(object, "getMaxFeed"), A.feedAmount(item)
        if (n(object, "getWater") or math.huge) > 0 or not feed or not maximum or not amount or feed >= job.target.high
            or feed + amount > maximum then return false end
    elseif job.target.operation == "animal_water" then
        local facts = SC.CleaningSupplies and SC.CleaningSupplies.inspect(item)
        local destination = SC.CleaningSupplies and SC.CleaningSupplies.inspect(object)
        local receiver = value(object, "getFluidContainer")
        local foodContainer = value(object, "getContainer")
        local items, contentsKnown = read(foodContainer, "getItems")
        if not facts or not facts.waterOnly or facts.amount <= 0 or not receiver
            or value(receiver, "isInputLocked") ~= false or not destination or not destination.known
            or not (destination.empty or destination.waterOnly)
            or foodContainer and (not contentsKnown or size(items) > 0) then return false end
    end
    return SC.BaseLife.job(job.id) == job
end

function A.canHutchWork(actor, job, state, object, operation)
    if operation == "animal_open" or operation == "animal_close" then
        local row = snapshots[job.target.nativeZoneId]
        return row and A.hutchOperation(time(), value(object, "isDoorClosed"),
            n(value(object, "getAnimalInside"), "size"), #row.animals) == operation
    elseif operation == "animal_hatch_open" then
        return value(object, "isEggHatchDoorClosed") == true
    elseif operation == "animal_clean_floor" then
        if C("animalCleanEnabled", 0) ~= 1 then return false end
        local loans = state.animalLoans or {}
        local tool = loans[1] and loans[1].borrowed and loans[1].borrowed.item
        local water = loans[2] and loans[2].borrowed and loans[2].borrowed.item
        local cleaner = loans[3] and loans[3].borrowed and loans[3].borrowed.item
        local W = water and SC.CleaningSupplies.inspect(water)
        local B = cleaner and SC.CleaningSupplies.inspect(cleaner)
        return tool and SC.CleaningSupplies.tool(tool) and W and W.waterOnly and W.amount >= 0.01
            and B and B.known and B.cleaner and B.amount >= 0.002
            and U().inventoryContains(U().inventory(actor), water)
            and U().inventoryContains(U().inventory(actor), cleaner)
            and (n(object, "getHutchDirt") or 0) > 0
    elseif operation == "animal_clean_nest" then
        return C("animalCleanEnabled", 0) == 1 and (n(object, "getNestBoxDirt") or 0) > 0
    end
    return true
end

local function begin(actor, job, state, object, item, operation)
    local supervisor = SC.ActionSupervisor
    local token, reason = supervisor.begin(actor, { owner = "work",
        action = "farm_" .. operation, targetKey = job.id, targetLabel = "chicken pen",
        priority = supervisor.Priority.WORK, ignoreRetry = true, interruptible = true })
    if not token then return false, reason end
    if SC.Navigation then SC.Navigation.cancel(actor, "animal_interaction") end
    local stopped, stopReason = SC.NativeActions.stopDirect(actor)
    if not stopped then supervisor.fail(token, stopReason) return false, stopReason end
    supervisor.transition(token, "committing")
    local before = operation == "animal_water" and n(object, "getWater")
        or operation == "fill_water" and support().waterUses(item)
        or n(object, "getCurrentFeedAmount")
    if operation == "animal_open" or operation == "animal_close" then before = value(object, "isDoorClosed")
    elseif operation == "animal_hatch_open" then before = value(object, "isEggHatchDoorClosed")
    elseif operation == "animal_clean_floor" then before = n(object, "getHutchDirt")
    elseif operation == "animal_clean_nest" then before = n(object, "getNestBoxDirt") end
    local started, detail = supervisor.commit(token, function()
        if operation == "fill_water" then
            return SC.NativeActions.startFarm(actor, { operation = "fill_water",
                item = item, object = object })
        end
        local items = {}
        for _, loan in ipairs(state.animalLoans or {}) do
            if loan.borrowed then items[#items + 1] = loan.borrowed.item end
        end
        return SC.NativeActions.startAnimal(actor, { operation = operation, item = item,
            object = object, high = job.target.high,
            items = #items > 0 and items or nil, water = items[2], cleaner = items[3],
            nest = state.animalEgg and state.animalEgg.nest,
            validate = function()
                return A.canUse(actor, job, object, item)
                    and A.canHutchWork(actor, job, state, object, operation)
                    and (operation ~= "animal_egg" or A.canTakeEgg(actor, job, state, object))
            end })
    end)
    if not started then supervisor.fail(token, detail) return false, detail end
    supervisor.transition(token, "verifying")
    supervisor.complete(token, "animal_native_started")
    state.animalWork = { operation = operation, before = before, startedAt = now(),
        object = object, item = item }
    return true, "farm_" .. operation .. "_active"
end

local function reconcileFeed(job, state)
    if not state.borrowed then return true end
    local receipt = SC.BaseLife.farmReceipt(state.borrowed.receiptId)
    if receipt and A.borrowWasConsumed(receipt) then
        SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "consumed", blocker = false })
        state.borrowed = nil
    end
    return true
end

function A.canTakeEgg(actor, job, state, object)
    local selected = state.animalEgg
    if not selected then return false end
    local row = snapshots[job.target.nativeZoneId]
    local data = U().modData(selected.item)
    return row and (n(selected.nest, "getEggsNb") or 0) > 0
        and value(selected.nest, "getEgg", 0) == selected.item
        and not A.keepEgg(row, selected.item) and A.foodDestination(actor, selected.item) ~= nil
        and SC.WorkTransport.hasRoom(U().inventory(actor), actor, selected.item) == true
        and type(data) == "table" and data[SC.FarmWork.ITEM_MARKER] == selected.receiptId
end

local function reconcileEgg(actor, job, state)
    local selected = state.animalEgg
    if not selected then return false end
    local inventory = U().inventory(actor)
    if value(selected.item, "getContainer") ~= inventory
        or value(inventory, "contains", selected.item) ~= true then return false end
    SC.BaseLife.updateFarmReceipt(selected.receiptId, { phase = "carried", blocker = false })
    state.outputs = { { item = selected.item, receiptId = selected.receiptId,
        category = SC.BaseLife.foodStorageCategory(selected.item) } }
    state.animalEgg = nil
    return true
end

-- Reconcile selected eggs against the exact nest or the exact actor inventory.
-- No native lookup failure authorizes manufacturing an egg or replaying pickup.
function A.recoverReceipt(receipt)
    if receipt.phase ~= "selected" then return false end
    local job = SC.BaseLife.job(receipt.jobId)
    local target = job and job.target
    if not target or target.operation ~= "animal_egg" then return false end
    local object = findDevice(target)
    local nest = object and value(object, "getNestBox", target.nestIndex)
    local count = n(nest, "getEggsNb")
    if not count or count > 64 then return false end
    for index = 0, count - 1 do
        local egg = value(nest, "getEgg", index)
        local data = egg and U().modData(egg)
        if data and data[SC.FarmWork.ITEM_MARKER] == receipt.id
            and tostring(value(egg, "getID")) == tostring(receipt.nativeId) then
            support().unmark(egg, receipt.id)
            SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "consumed",
                blocker = "animal_egg_left_in_nest" })
            return true
        end
    end
    return false
end

function A.cancel(actor, job, state, reason)
    if state.animalWork then
        local stopped, detail = SC.NativeActions.cancelWork(actor, reason or "animal_cancelled")
        if not stopped then return false, detail end
        reconcileFeed(job, state)
        reconcileEgg(actor, job, state)
        state.animalWork = nil
    end
    if state.animalEgg then
        local receipt = SC.BaseLife.farmReceipt(state.animalEgg.receiptId)
        if not receipt or not A.recoverReceipt(receipt) then return false, "animal_egg_recovery_pending" end
        state.animalEgg = nil
    end
    for _, loan in ipairs(state.animalLoans or {}) do
        local okay, detail = support().restore(actor, loan, reason)
        if not okay then return false, detail end
    end
    state.animalLoans = nil
    release(actor, job)
    return true
end

function A.update(actor, baseState, job, runtime, state)
    local target, S = job.target, support()
    -- Delivery and loan returns no longer depend on keeping the pen loaded.
    if state.outputs then return S.deposit(actor, baseState, state) end
    if state.animalReturn and not state.animalWork then
        for _, loan in ipairs(state.animalLoans or {}) do
            local settled, reason, pending = S.settle(actor, baseState, loan)
            if not settled then return pending == true, reason end
        end
        state.animalLoans = nil
        local settled, reason, pending = S.settle(actor, baseState, state)
        if not settled then return pending == true, reason end
        release(actor, job)
        local completed, detail = SC.BaseLife.completeJob(job.id, U().idOf(actor), "chicken_care")
        return completed == true, completed and "farm_job_complete" or detail
    end
    local object, row = findDevice(target)
    if not object then
        if row ~= "animal_audit_pending" then return fail(actor, job, row) end
        local _, detail = refreshTarget(target)
        if detail and detail ~= "animal_audit_pending" then return fail(actor, job, detail) end
        return true, row
    end -- bounded audit re-establishes native references after load
    if not claim(actor, job) then return true, "animal_work_reserved" end
    if target.high and not state.animalWork then
        local amount = target.operation == "animal_water" and n(object, "getWater")
            or n(object, "getCurrentFeedAmount")
        if amount and amount + 0.001 >= target.high then state.animalReturn = true end
    end
    if target.eggReceiptId and not state.animalEgg and not state.outputs and not state.animalWork then
        local receipt = SC.BaseLife.farmReceipt(target.eggReceiptId)
        if receipt and (receipt.phase == "delivered" or receipt.phase == "consumed") then
            state.animalReturn = true
        else return true, "animal_egg_recovery_pending" end
    end
    if not enabled() or S.threat(actor, runtime) then
        local okay, reason = A.cancel(actor, job, state, "animal_work_interrupted")
        if not okay then return false, reason end
        state.animalReturn = true
    end
    if state.animalWork then
        local work = state.animalWork
        if SC.NativeActions.isWorkActive(actor) then
            if now() - work.startedAt > 120000 then
                local cancelled, detail = A.cancel(actor, job, state, "animal_action_timeout")
                if not cancelled then return true, detail or "animal_cleanup_pending" end
                return fail(actor, job, "animal_action_timeout")
            end
            return true, "farm_" .. work.operation .. "_active"
        end
        local finished, detail = SC.NativeActions.finishWork(actor)
        if not finished then return fail(actor, job, detail) end
        reconcileFeed(job, state)
        local eggTaken = reconcileEgg(actor, job, state)
        local verified = work.operation == "animal_feed" and not state.borrowed
            or work.operation == "animal_water" and (n(object, "getWater") or -1) > work.before
            or work.operation == "fill_water" and S.waterUses(work.item) > work.before
            or work.operation == "animal_egg" and eggTaken
            or work.operation == "animal_open" and value(object, "isDoorClosed") == false
            or work.operation == "animal_close" and value(object, "isDoorClosed") == true
            or work.operation == "animal_hatch_open" and value(object, "isEggHatchDoorClosed") == false
            or work.operation == "animal_clean_floor" and (n(object, "getHutchDirt") or math.huge) < work.before
            or work.operation == "animal_clean_nest" and (n(object, "getNestBoxDirt") or math.huge) < work.before
        state.animalWork = nil
        if not verified then return fail(actor, job, "animal_action_incomplete") end
        if work.operation == "fill_water" then return true, "animal_water_container_filled" end
        if work.operation == "animal_hatch_open" then return true, "animal_egg_hatch_open" end
        if work.operation == "animal_egg" then state.animalReturn = true end
        if not target.high then state.animalReturn = true end
        local amount = target.operation == "animal_water" and n(object, "getWater")
            or n(object, "getCurrentFeedAmount")
        if target.high then state.animalReturn = amount ~= nil and amount + 0.001 >= target.high end
    end
    if state.outputs then return S.deposit(actor, baseState, state) end
    if state.animalReturn then
        return true, "animal_returning_supplies"
    end
    if target.operation == "animal_egg" then
        local status, detail = S.approach(actor, U().squareOf(object), object)
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        if value(object, "isEggHatchDoorClosed") == true then
            return begin(actor, job, state, object, nil, "animal_hatch_open")
        end
        local nest = value(object, "getNestBox", target.nestIndex)
        local count = n(nest, "getEggsNb")
        local egg = count and count > 0 and value(nest, "getEgg", 0)
        if not egg or A.keepEgg(row, egg) then return fail(actor, job, "animal_egg_reserved") end
        if not A.foodDestination(actor, egg) then return fail(actor, job, "farm_food_storage_missing") end
        if SC.WorkTransport.hasRoom(U().inventory(actor), actor, egg) ~= true then
            return fail(actor, job, "animal_carry_capacity_low")
        end
        local receipt, reason = S.receipt(actor, job, "output", egg, nil,
            SC.BaseLife.foodStorageCategory(egg))
        if not receipt then return fail(actor, job, reason) end
        target.eggReceiptId = receipt.id
        SC.BaseLife.updateFarmReceipt(receipt.id, { phase = "selected", blocker = false })
        state.animalEgg = { item = egg, receiptId = receipt.id, nest = nest }
        note()
        return begin(actor, job, state, object, nil, "animal_egg")
    end
    if target.operation == "animal_open" or target.operation == "animal_close"
        or target.operation == "animal_clean_nest" then
        local status, detail = S.approach(actor, U().squareOf(object), object)
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        return begin(actor, job, state, object, nil, target.operation)
    end
    if target.operation == "animal_clean_floor" then
        if C("animalCleanEnabled", 0) ~= 1 then return fail(actor, job, "animal_clean_disabled") end
        local C = SC.CleaningSupplies
        if not C then return fail(actor, job, "animal_clean_supplies_missing") end
        local specs = {
            { predicate = C.tool, categories = { "farming", "tools" }, key = "animal_mop" },
            { predicate = function(item)
                local facts = C.inspect(item)
                return facts and facts.waterOnly and facts.amount >= 0.01
            end, categories = { "farming", "water" }, key = "animal_clean_water" },
            { predicate = function(item)
                local facts = C.inspect(item)
                return facts and facts.known and facts.cleaner and facts.amount >= 0.002
            end, categories = { "farming", "crafting" }, key = "animal_cleaner" },
        }
        state.animalLoans = state.animalLoans or {}
        for index, spec in ipairs(specs) do
            local loan = state.animalLoans[index] or { jobId = job.id }
            state.animalLoans[index] = loan
            if not loan.borrowed then
                return S.borrow(actor, baseState, job, loan, spec.predicate, spec.categories, spec.key)
            end
        end
        local status, detail = S.approach(actor, U().squareOf(object), object)
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        return begin(actor, job, state, object, state.animalLoans[1].borrowed.item, target.operation)
    end
    local supply = state.borrowed or state.carriedWaterSupply
    if not supply then
        local predicate = target.operation == "animal_water" and function(item)
                if not S.waterPredicate(item) then return false end
                local facts = SC.CleaningSupplies and SC.CleaningSupplies.inspect(item)
                return facts and facts.known and (facts.amount <= 0 or facts.waterOnly)
            end
            or function(item)
                local amount = A.feedAmount(item)
                local current = n(object, "getCurrentFeedAmount")
                local maximum = n(object, "getMaxFeed")
                return amount and amount > 0 and current and maximum and current < target.high
                    and current + amount <= maximum
            end
        return S.borrow(actor, baseState, job, state, predicate,
            target.operation == "animal_water" and { "farming", "water" } or { "farming" },
            target.operation == "animal_water" and "water" or "chicken_feed")
    end
    if target.operation == "animal_water" and S.waterUses(supply.item) <= 0 then
        local source, reason = S.findWater(actor, state, row)
        if not source then return reason == "water_source_scanning", reason, reason ~= "water_source_scanning" end
        local status, detail = S.approach(actor, U().squareOf(source), source)
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        return begin(actor, job, state, source, supply.item, "fill_water")
    end
    local status, detail = S.approach(actor, U().squareOf(object), object)
    if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
    return begin(actor, job, state, object, supply.item, target.operation)
end

function A.reset(actor)
    if actor then
        for k, held in pairs(claims) do if held.actor == U().idOf(actor) then claims[k] = nil end end
    else
        scan, snapshots, claims, refreshes = nil, {}, {}, {}
        knownBase, zoneCursor, lastAudit = nil, 0, -math.huge
        zoneVisited, zoneCycleSize = 0, 0
    end
end

return A
