-- SPDX-License-Identifier: MIT
-- Native animal work participates only through SCFarmWork's existing lane.
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
    cattle = { kinds = { cow = true, bull = true, cowcalf = true },
        feeds = { AnimalFeed = true, Grass = true, Hay = true, Vegetables = true, Fruits = true },
        supplies = { AnimalFeed = true, Grass = true, Hay = true },
        milk = "CowMilk", adultEnclosure = 80, calfEnclosure = 40, dawn = 7, dusk = 20 },
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
    local id=n(object,"getAnimalID")
    if id then return "animal:"..tostring(id) end
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

function A.speciesFor(kind)
    for name, species in pairs(A.species) do
        if species.kinds[kind] then return name, species end
    end
end

function A.isFeed(item, species)
    local profile = type(species)=="table" and species or A.species[species or "chicken"]
    return item ~= nil and profile ~= nil and profile.feeds[value(item, "getAnimalFeedType")] == true
        and value(item, "isRotten") ~= true
end

function A.feedAmount(item, species)
    if not A.isFeed(item, species) then return nil end
    local hunger = n(item, "getHungerChange")
    if hunger then return math.abs(hunger) end
    local uses = n(item, "getCurrentUses")
    if uses then return math.max(0, uses * 0.1) end
    return nil
end

local function feedCompatible(item,row)
    if #row.animals>0 and not A.isFeed(item,"chicken") then return false end
    if #row.cattle.animals>0 and C("animalCattleEnabled",0)==1
        and (not A.isFeed(item,"cattle")
            or not A.species.cattle.supplies[value(item,"getAnimalFeedType")]) then return false end
    return true
end

function A.cattleThreat(actor,row)
    local inspected=0
    local ax,ay,az=U().position(actor)
    for _,entry in ipairs(row and row.cattle and row.cattle.animals or {}) do
        if entry.kind=="bull" then
            inspected=inspected+1
            if inspected>8 then return true end -- Never sweep an unbounded herd in action guards.
            local bull=row.members[entry.id]
            local x,y,z=U().position(bull)
            if not ax or not x then return true end
            if az==z and (ax-x)^2+(ay-y)^2<=100 then
                local attack,known=read(bull,"isAnimalAttacking")
                local stress=n(bull,"getStress")
                if not known or not stress or attack==true or stress>40 then return true end
            end
        end
    end
    return false
end

function A.herdSpace(row)
    local herd=row and row.cattle
    if not herd or #herd.animals==0 then return nil end
    local area=n(row.native,"getFullZoneSize")
    local minimum=(herd.cows+herd.bulls)>0 and A.species.cattle.adultEnclosure
        or A.species.cattle.calfEnclosure
    return area and area>=0 and area or nil,minimum
end

local function percent(name,default)
    return math.min(100,math.max(0,C(name,default)))/100
end
local function milkNumber(number)
    return type(number)=="number" and number==number and number>=0 and number<math.huge
end

-- Native readings only. This is also the per-increment guard; it must not
-- inspect world squares or consult the main player's inventory.
function A.milkFacts(cow,row)
    if value(cow,"getAnimalType")~="cow" or value(cow,"isBaby")~=false
        or (n(cow,"getHealth") or 0)<=0 or value(cow,"isHeld")~=false then return nil end
    local data=value(cow,"getData")
    local player,playerKnown=read(data,"getAttachedPlayer")
    local tree,treeKnown=read(data,"getAttachedTree")
    local marks,marksKnown=read(cow,"getModData")
    local amount,capacity,genetic=n(data,"getMilkQuantity"),n(data,"getMaxMilkActual"),n(data,"getMaxMilk")
    local stress=n(cow,"getStress")
    if not playerKnown or not treeKnown or player or tree or not marksKnown or type(marks)~="table"
        or marks.lfOddballGroupId~=nil or marks.lfWendellGroupId~=nil
        or value(data,"isFemale")~=true or value(data,"canHaveMilk")~=true
        or not milkNumber(amount) or not milkNumber(capacity) or capacity<=0
        or not milkNumber(genetic) or genetic<=0 or not milkNumber(stress)
        or value(cow,"getMilkType")~="CowMilk" then return nil end
    local calf=false
    for _,entry in ipairs(row and row.cattle and row.cattle.animals or {}) do
        if entry.baby and (entry.motherId==nil or entry.motherId==n(cow,"getAnimalID")) then calf=true break end
    end
    -- A calf can be born between bounded zone audits. The mother's native
    -- child list is small and live; unknown or oversized evidence stops milk.
    local babies,babiesKnown=read(cow,"getBabies")
    if not babiesKnown or size(babies)>8 then return nil end
    for index=0,size(babies)-1 do
        local child=at(babies,index)
        local baby,babyKnown=read(child,"isBaby")
        local health=n(child,"getHealth")
        if not babyKnown or not health then return nil end
        local childZone=value(child,"getDZone")
        local zoneId=value(childZone,"getId")
        if baby and health>0 and (zoneId==nil or row==nil or row.id==nil or tostring(zoneId)==row.id) then calf=true end
    end
    return {amount=amount,capacity=capacity,genetic=genetic,stress=stress,calf=calf,
        reserve=calf and capacity*percent("animalMilkCalfReservePercent",40) or 0}
end

function A.milkPlan(cow,row,saved,jobId)
    local hour,hours=time()
    if C("animalCattleEnabled",0)~=1 or C("animalMilkEnabled",0)~=1
        or not hour or hour<7 or hour>=20 or not hours then return nil,"animal_milk_daylight" end
    local facts=A.milkFacts(cow,row)
    if not facts then return nil,"animal_milk_not_ready" end
    if facts.stress>math.min(40,C("animalMilkMaxStressPercent",40)) then return nil,"animal_milk_stressed" end
    local id=tostring(n(cow,"getAnimalID"))
    if saved and saved.milked~=nil and type(saved.milked)~="table" then return nil,"animal_milk_daily_limit" end
    local previous=saved and saved.milked and saved.milked[id]
    local day=math.floor(hours/24)
    local previousDay=type(previous)=="table" and tonumber(previous.day)
    if previous and (not milkNumber(previousDay) or previousDay>day
        or previousDay==day and (not jobId or previous.jobId~=jobId)) then return nil,"animal_milk_daily_limit" end
    local threshold=facts.calf and percent("animalMilkCalfStartPercent",70) or percent("animalMilkStartPercent",50)
    local continuing=jobId and previous and previousDay==day and previous.jobId==jobId
    if not continuing and facts.amount+0.0001<facts.capacity*threshold then return nil,"animal_milk_not_ready" end
    facts.day,facts.urgent=day,facts.amount>=facts.capacity*percent("animalMilkUrgentPercent",80)
    return facts
end

function A.milkContainer(item)
    local fc=value(item,"getFluidContainer")
    return Fluid and Fluid.CowMilk and fc and n(fc,"getAmount")==0
        and (n(fc,"getCapacity") or 0)>=0.1 and value(fc,"isInputLocked")==false
        and value(fc,"canAddFluid",Fluid.CowMilk)==true or false
end

-- A conservative litre-per-weight projection, including the loss of a held
-- bag discount. The native action still applies its own physical carry cap.
function A.milkRoom(actor,item,borrowed)
    local weight,limit=U().projectedCarryLoad(actor,false)
    local capacity=n(value(item,"getFluidContainer"),"getCapacity")
    if not weight or not limit or not capacity then return 0 end
    return math.max(0,math.min(capacity,limit-weight-(borrowed and 0 or U().itemWeight(item))-0.1))
end

function A.milkSide(actor,cow,preferred)
    local ax,ay,az=U().position(actor)
    local _,_,z=U().position(cow)
    if not ax or not z or math.floor(az)~=math.floor(z) then return nil end
    local best
    for _,side in ipairs({{name="leftmilk",right=false},{name="rightmilk",right=true}}) do
        local vector=value(cow,"getAttachmentWorldPos",side.name)
        local x,y=n(vector,"x"),n(vector,"y")
        local square=x and y and U().gridSquare(math.floor(x),math.floor(y),math.floor(z))
        if square and U().isSquareFree(square)==true and SC.BaseLife.withinWorkReach(square)==true then
            local candidate={x=x,y=y,z=math.floor(z),right=side.right,square=square,distance=(ax-x)^2+(ay-y)^2}
            if preferred~=nil and side.right==preferred then return candidate end
            if not best or candidate.distance<best.distance then best=candidate end
        end
    end
    return best
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
    local limit=C("animalCattleEnabled",0)==1
        and math.min(1024,math.max(256,C("animalCattleZoneMaxTiles",1024))) or 256
    if not id or not x or not y or not z or not w or not h
        or w < 1 or h < 1 or w * h > limit then return nil end
    return { id = tostring(id), native = zone, x1 = x, y1 = y, z = z,
        x2 = x + w - 1, y2 = y + h - 1, width = w, total = w * h,
        index = 0, animals = {}, cattle = { animals = {}, cows = 0, bulls = 0, calves = 0 },
        members = {}, deadIds = {}, seen = {}, animalCount = 0, hutches = {}, troughs = {},
        hutchIndex = 0, complete = true, capacity = 0, hens = 0, roosters = 0, chicks = 0 }
end

local function contains(row, object)
    local x, y, z = U().position(object)
    return x and z == row.z and x >= row.x1 and x < row.x2 + 1
        and y >= row.y1 and y < row.y2 + 1
end

local function animalId(id)
    return type(id)=="number" and id==id and id>=0 and id<math.huge and id%1==0
end

-- A native zone's live set shrinks when a bird wanders outside it. Preserve
-- observed identities across audits/reloads: missing is not evidence of death.
local function rememberFlock(row)
    local doc=document()
    local saved=doc and doc.zones[row.id]
    local savedValid=saved==nil or type(saved)=="table"
    if not savedValid then saved=nil end
    local previous=snapshots[row.id]
    local ids,seen,objects={}, {}, {}
    local verified=savedValid and not (saved and saved.flockUnverified)
    local function add(id, bird)
        if not animalId(id) then verified=false return end
        if row.deadIds[id] then return end
        if bird and n(bird,"getAnimalID")==id then
            local health=n(bird,"getHealth")
            if health and health<=0 then return end -- Only a positively observed death.
            objects[id]=bird
        end
        if not seen[id] then
            if #ids>=128 then verified=false return end
            ids[#ids+1],seen[id]=id,true
        end
    end
    local retained=saved and saved.flockIds
    if retained~=nil then
        if type(retained)~="table" or #retained>128 then verified=false
        else
            local count=0
            for index,id in pairs(retained) do
                count=count+1
                if count>128 then verified=false break end
                if type(index)~="number" or index%1~=0 or index<1 or index>#retained
                    or seen[id] then verified=false
                else add(id,row.members[id] or previous and previous.knownMembers
                    and previous.knownMembers[id]) end
            end
            if count~=#retained then verified=false end
        end
    end
    for _,bird in ipairs(row.animals) do add(bird.id,row.members[bird.id]) end
    table.sort(ids)
    row.flockIds,row.knownMembers,row.rosterVerified=ids,objects,verified
end

local function saveFlock(row,saved)
    if row.rosterVerified then
        saved.flockIds={}
        for index,id in ipairs(row.flockIds) do saved.flockIds[index]=id end
    else
        saved.flockUnverified=true -- Do not replace ambiguous saved evidence with a smaller flock.
    end
end

local function remember(row)
    rememberFlock(row)
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
    if not animalId(id) then row.complete = false return end
    if row.seen[id] then return end
    row.seen[id] = true
    if row.animalCount >= 128 then row.complete = false return end
    row.animalCount = row.animalCount + 1
    local kind = value(animal, "getAnimalType")
    local species = A.speciesFor(kind)
    local data, ok = read(animal, "getModData")
    if not ok or type(data) ~= "table" then row.complete = false return end
    if data.lfOddballGroupId ~= nil or data.lfWendellGroupId ~= nil then row.protected = true end
    if not species then row.unsupported = true return end
    local health=n(animal,"getHealth")
    if not health or health~=health then row.complete=false return end
    if health<=0 then row.deadIds[id]=true return end
    row.members[id] = animal -- Runtime only; never copied into the save document.
    local baby, babyOkay = read(animal, "isBaby")
    local name, nameOkay = read(animal, "getCustomName")
    local held, heldOkay = read(animal, "isHeld")
    local age = n(animal, "getAge")
    local animalData = value(animal, "getData")
    local female, femaleOkay = read(animalData, "isFemale")
    local cullKnown, led, wild, laying = false, nil, nil, nil
    if species=="chicken" and C("animalCullEnabled",0)==1 then
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
    local entry = { id = id, kind = kind, species = species, baby = baby == true,
        name = name, held = held, age = age, female = female,
        cullKnown = cullKnown, led = led, wild = wild, laying = laying,
        oddball = data.lfOddballGroupId ~= nil or data.lfWendellGroupId ~= nil }
    if species=="cattle" then
        if baby==true then entry.motherId=n(value(animal,"getMother"),"getAnimalID") end
        row.cattle.animals[#row.cattle.animals+1]=entry
        local count=baby==true and "calves" or female==true and "cows" or "bulls"
        row.cattle[count]=row.cattle[count]+1
        return
    end
    row.animals[#row.animals + 1] = entry
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
        if SC.BaseLife.withinWorkReach({ x = x, y = y, z = row.z }) ~= true then
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
    if C("animalCattleEnabled",0)==1 then
        if not row.registeredAnimals then
            local registered,known=read(row.native,"getAnimalsInZone")
            local count=size(registered)
            if not known or count>128 or not ArrayList or not ArrayList.new then row.complete=false return done(true) end
            local made,copied=pcall(ArrayList.new)
            local _,added=read(made and copied or nil,"addAll",registered)
            if not made or not added or size(copied)~=count then row.complete=false return done(true) end
            row.registeredAnimals,row.registeredIndex=copied,0
        end
        -- A moving cow can cross from an unscanned tile into an already read
        -- tile. Reconcile the native zone set with the same animal budget;
        -- never expand the read-only action guards into another world scan.
        while row.registeredIndex<size(row.registeredAnimals) and animalBudget>0 do
            if outOfTime(start) then return done(false) end
            local animal=at(row.registeredAnimals,row.registeredIndex)
            local kind=value(animal,"getAnimalType")
            if not kind then row.complete=false
            elseif A.species.cattle.kinds[kind] and contains(row,animal) then inspectAnimal(row,animal)
            elseif not A.speciesFor(kind) then row.unsupported=true end
            row.registeredIndex,animalBudget=row.registeredIndex+1,animalBudget-1
        end
        if row.registeredIndex<size(row.registeredAnimals) then return done(false) end
    end
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
        local maxNest=n(hutch,"getMaxNestBox")
        if not maxNest or maxNest<0 or maxNest>15 then row.complete=false return done(true) end
        row.nestAnimalIndex=row.nestAnimalIndex or 0
        while row.nestAnimalIndex<=maxNest and animalBudget>0 do
            if outOfTime(start) then return done(false) end
            local bird,known=read(hutch,"getAnimalInNestBox",row.nestAnimalIndex)
            if not known then row.complete=false return done(true) end
            if bird then inspectAnimal(row,bird) animalBudget=animalBudget-1 end
            row.nestAnimalIndex=row.nestAnimalIndex+1
        end
        if row.nestAnimalIndex<=maxNest then return done(false) end
        local chicken = row.animals[1] and row.members[row.animals[1].id]
        local compatible, exposed = read(chicken, "canBePutInHutch", hutch)
        if chicken and (not exposed or compatible~=true) then row.complete = false end
        row.occupants, row.occupantIndex, row.hutchIndex = nil, nil, row.hutchIndex + 1
        row.nestAnimalIndex=nil
    end
    return done(row.hutchIndex >= #row.hutches)
end

local function openJob(base, object, operation)
    local targetKey = key(object)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "farm" and job.target and job.target.animal
            and job.target.deviceKey == targetKey
            and job.state ~= "completed" and job.state ~= "cancelled" then
            local door=operation=="animal_open" or operation=="animal_close"
            if not door or job.target.operation==operation or job.state=="active"
                or job.reservedBy~=nil then return job end
        end
    end
    return false
end

local function candidateAt(row, operation, object, priority)
    local x, y, z = U().position(object)
    return { animal = true, operation = operation, priority = priority or 4,
        zoneId = "animal:" .. row.id, nativeZoneId = row.id,
        deviceKey = key(object), cattle = C("animalCattleEnabled",0)==1 and #row.cattle.animals>0 or nil,
        x = math.floor(x), y = math.floor(y), z = z }
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

function A.milkDepositRows()
    local rows={}
    for _,category in ipairs({"fresh_food","food"}) do
        for index,storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
            if index>32 then break end
            rows[#rows+1]=storage
        end
    end
    return rows
end

function A.milkDestination(actor,item,extra)
    for _,storage in ipairs(A.milkDepositRows()) do
        local container=SC.BaseLife.resolveContainer(storage)
        local room=container and SC.BaseLife.storageAcceptsDeposit(storage,container)==true
            and SC.WorkTransport.hasRoom(container,actor,item)==true
        if room and extra and extra>0 then
            local used,capacity=n(container,"getCapacityWeight"),n(container,"getEffectiveCapacity",actor)
            room=used~=nil and capacity~=nil and used+U().itemWeight(item)+extra<=capacity
        end
        if room then return storage,container end
    end
end

local function milkCandidate(row,base)
    if C("animalMilkEnabled",0)~=1 then return nil end
    local saved=document() and document().zones[row.id]
    local count=#row.cattle.animals
    if not saved or count==0 or saved.milkAttempts~=nil and type(saved.milkAttempts)~="table" then return nil end
    local cursor=math.floor(tonumber(saved.milkCursor) or 0)%count
    local best
    for _=1,math.min(4,count) do
        cursor=cursor%count+1
        local entry=row.cattle.animals[cursor]
        local cow=row.members[entry.id]
        if cow and contains(row,cow) then
            local existing=openJob(base,cow)
            local facts=A.milkPlan(cow,row,saved,existing and existing.id)
            if existing then
                -- A queued ordinary job must become urgent when its live udder
                -- crosses the welfare mark; its creation-time flag is not truth.
                if facts and facts.urgent and not existing.target.urgent then
                    existing.target.urgent=true existing.priority=5 existing.updatedAt=now() note()
                    if existing.state=="blocked" and existing.blocker=="animal_milk_food_storage_missing" then
                        existing.retryAt=now()
                    end
                end
            else
                local attempt=saved.milkAttempts and saved.milkAttempts[tostring(entry.id)]
                local _,hours=time()
                local attemptHour=type(attempt)=="table" and tonumber(attempt.hour)
                if facts and (not attempt or milkNumber(attemptHour) and attemptHour<math.floor(hours)) then
                    local target=candidateAt(row,"animal_milk",cow,facts.urgent and 6 or 3.5)
                    target.cowId,target.milkDay,target.urgent=entry.id,facts.day,facts.urgent
                    if facts.urgent then saved.milkCursor=cursor return target end
                    best=best or target
                end
            end
        end
    end
    saved.milkCursor=cursor
    return best
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
    if not row.complete or row.protected or row.mixed or row.unsupported then
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
    if type(row)~="table" or row.complete~=true or row.protected or row.mixed or row.unsupported
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

function A.doorJob(job)
    if not enabled() or not job or job.type~="farm" or not job.target or job.target.animal~=true then
        return false
    end
    return job.target.operation=="animal_open"
        or job.target.operation=="animal_close" and C("animalCloseEnabled",0)==1
end

function A.urgentMilkJob(job)
    return enabled() and C("animalCattleEnabled",0)==1 and C("animalMilkEnabled",0)==1
        and job and job.type=="farm" and job.target and job.target.operation=="animal_milk"
        and job.target.urgent==true or false
end

function A.nightClosingJob(job)
    return A.doorJob(job) and job.target.operation=="animal_close"
end

function A.hutchOperation(hour, closed, inside, total)
    if hour == nil or type(closed) ~= "boolean" then return nil end
    local species = A.species.chicken
    local night = hour >= species.dusk or hour < species.dawn
    if night and not closed and C("animalCloseEnabled", 0) == 1 then
        -- Grace expiry is a warning, never permission to lock late birds out.
        if type(total)=="number" and total>0 and inside==total then return "animal_close" end
    elseif not night and closed then return "animal_open" end
    return nil
end

function A.roostReady(row, strict)
    if not row or row.complete~=true or row.protected or row.mixed
        or row.rosterVerified~=true or not row.flockIds
        or #row.flockIds==0 or #row.flockIds>128 then return false,"population_unknown" end
    local total, sheltered = 0, {}
    for _, hutch in ipairs(row.hutches) do
        if (n(hutch,"getObjectIndex") or -1)<0 then return false,"hutch_removed" end
        local occupants=value(hutch,"getAnimalInside")
        local count=n(occupants,"size")
        if not count or count<0 or total+count>128 then return false,"occupants_unknown" end
        total=total+count
        if strict then
            if not ArrayList or not ArrayList.new then return false,"occupants_unknown" end
            local made, copy=pcall(ArrayList.new)
            local _, added=read(made and copy or nil,"addAll",value(occupants,"values"))
            if not made or not added or size(copy)~=count then return false,"occupants_unknown" end
            for index=0,count-1 do sheltered[at(copy,index)]=true end
        end
        local maxNest=n(hutch,"getMaxNestBox")
        if not maxNest or maxNest<0 or maxNest>15 then return false,"nest_unknown" end
        for index=0,maxNest do
            local bird,known=read(hutch,"getAnimalInNestBox",index)
            if not known then return false,"nest_unknown" end
            if bird then
                total=total+1
                if strict then sheltered[bird]=true end
            end
        end
        if total>128 then return false,"occupants_unknown" end
    end
    if total~=#row.flockIds then return false,"population_changed:"..total..":"..#row.flockIds end
    if not strict then return true end
    -- Only candidate admission and the irreversible door commit copy the local
    -- native roster. Per-frame animation guards read bounded occupancy counts.
    local shelteredIds={}
    for bird in pairs(sheltered) do
        local id=n(bird,"getAnimalID")
        if not animalId(id) or shelteredIds[id] or (n(bird,"getHealth") or 0)<=0 then
            return false,"sheltered_identity_unknown"
        end
        shelteredIds[id]=true
    end
    for _,id in ipairs(row.flockIds) do
        if not shelteredIds[id] then return false,"known_bird_outside" end
    end
    local registered, known=read(row.native,"getAnimalsInZone")
    local count=known and n(registered,"size")
    if not count or count>128 then return false,"registered_unknown" end
    local made, copy=pcall(ArrayList.new)
    local _, added=read(made and copy or nil,"addAll",registered)
    if not made or not added or size(copy)~=count then return false,"registered_unknown" end
    for index=0,count-1 do
        local bird=at(copy,index)
        local kind=value(bird,"getAnimalType")
        if not kind then return false,"registered_unknown" end
        if A.species.chicken.kinds[kind] and not sheltered[bird] then
            return false,"registered_bird_outside"
        end
    end
    return true
end

local function roostWaiting()
    local hour=time()
    if hour and ((hour-A.species.chicken.dusk)%24)*60>=C("animalDuskGraceMinutes",60) then
        return "animal_roost_delayed"
    end
    return "animal_roost_waiting"
end

local function hutchCandidate(row, base, milk)
    if #row.animals==0 then return milk end -- Cattle never create chicken housing work.
    local hour = time()
    local waiting
    for _, hutch in ipairs(row.hutches) do
        do
            local ready=A.roostReady(row,false)
            local operation = A.hutchOperation(hour, value(hutch, "isDoorClosed"),
                ready and #row.animals or nil, #row.animals)
            if (operation=="animal_open" or operation=="animal_close" and A.roostReady(row,true))
                and not openJob(base,hutch,operation) then
                return candidateAt(row, operation, hutch, 4)
            end
            if hour and (hour>=A.species.chicken.dusk or hour<A.species.chicken.dawn)
                and value(hutch,"isDoorClosed")==false and C("animalCloseEnabled",0)==1 then
                waiting=roostWaiting()
            end
        end
    end
    if milk then return milk end
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
    return nil,waiting
end

local function deviceCandidate(row, base)
    local milk=milkCandidate(row,base)
    local high = math.min(1, math.max(0.01, C("animalFeedHighPercent", 90) / 100))
    local low = math.min(high, math.max(0, C("animalFeedLowPercent", 25) / 100))
    local best, waterAssigned, empty = nil, false, {}
    local saved=document() and document().zones[row.id]
    local refills=saved and type(saved.refills)=="table" and saved.refills or {}
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
    if milk and milk.urgent then return milk end
    for _, trough in ipairs(row.troughs) do
        if not openJob(base, trough) and workDay(trough) then
            local water, capacity = n(trough, "getWater"), n(trough, "getMaxWater")
            if water and capacity and water>=capacity*high then refills[key(trough)]=nil end
            if row.troughRoles[key(trough)] == "water"
                and water and capacity and capacity > 0
                and (water < capacity * low or refills[key(trough)]==true and water<capacity*high) then
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
    if best then return best end
    return hutchCandidate(row, base, milk)
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
            if row and SC.BaseLife.withinWorkReach({x=row.x1,y=row.y1,z=row.z}) == true then
                scan = row break
            end
        end
        if zoneVisited >= count then zoneVisited = 0 end
        if not scan then return nil, "animal_audit_pending", zoneVisited > 0 end
    end
    if not advance(scan, squareLimit) then return nil, "animal_audit_pending", true end
    local row = scan
    scan = nil
    local hasCattle=C("animalCattleEnabled",0)==1 and #row.cattle.animals>0
    if row.rejected or not row.complete or row.protected
        or #row.animals==0 and not hasCattle or row.total>256 and not hasCattle then
        snapshots[row.id] = nil
        local reason = row.rejected and "animal_zone_outside_camp"
            or not row.complete and "animal_audit_incomplete"
            or row.protected and "animal_story_animals"
            or #row.cattle.animals>0 and "animal_species_not_supported" or "animal_flock_not_loaded"
        return nil, reason
    end
    local doc = document()
    local count = 0
    for id, saved in pairs(doc.zones) do
        if type(saved) ~= "table" then doc.zones[id] = nil
        else count = count + 1 end
    end
    if not doc.zones[row.id] and count >= math.min(8, math.max(1, C("animalMaxZones", 8))) then
        -- Retained flock identities are safety evidence, not an LRU cache.
        -- Replacing one would silently forget birds still outside its hutch.
        return nil,"animal_zone_limit"
    end
    row.auditedAt, row.coverageStamp = now(), coverageStamp(base)
    remember(row)
    local saved = doc.zones[row.id] or { cooldowns = {} }
    saveFlock(row,saved)
    saved.hens, saved.roosters, saved.chicks = row.hens, row.roosters, row.chicks
    saved.capacity, saved.auditedAt = row.capacity, row.auditedAt
    saved.census={chicken={hens=row.hens,roosters=row.roosters,chicks=row.chicks},
        cattle={cows=row.cattle.cows,bulls=row.cattle.bulls,calves=row.cattle.calves},
        unsupported=row.unsupported==true}
    saved.enclosureTiles,saved.minimumEnclosureTiles=A.herdSpace(row)
    local target=A.breedingPlan(row,nil)
    saved.targetHens,saved.targetRoosters=target.hens,target.roosters
    saved.breedingBlocker=target.reason
    saved.cooldowns = type(saved.cooldowns) == "table" and saved.cooldowns or {}
    local currentDevices = {}
    for _, objects in ipairs({ row.hutches, row.troughs }) do
        for _, object in ipairs(objects) do currentDevices[key(object)] = true end
    end
    for _,entry in ipairs(row.cattle.animals) do currentDevices["animal:"..tostring(entry.id)]=true end
    -- Expired evidence for animals that left the pen must not accumulate
    -- forever. Current-day milk evidence remains even for a missing cow.
    local _,hours=time()
    for _,spec in ipairs({{"milked","day",hours and math.floor(hours/24)},
        {"milkAttempts","hour",hours and math.floor(hours)}}) do
        local records=saved[spec[1]]
        if type(records)=="table" and spec[3] then
            local inspected=0
            for id,entry in pairs(records) do
                inspected=inspected+1 if inspected>256 then break end
                local stamp=type(entry)=="table" and tonumber(entry[spec[2]])
                if stamp and stamp<spec[3] and not row.seen[tonumber(id)] then records[id]=nil end
            end
        end
    end
    for device in pairs(type(saved.refills)=="table" and saved.refills or {}) do
        if not currentDevices[device] then saved.refills[device]=nil end
    end
    for device, cooldown in pairs(saved.cooldowns) do
        if not currentDevices[device] or type(cooldown) ~= "table"
            or (tonumber(cooldown.failures) or 0) >= 3 then
            saved.cooldowns[device] = nil -- A new complete audit wakes dormant candidates.
        end
    end
    doc.zones[row.id] = saved
    local selected, deviceReason = deviceCandidate(row, base)
    local water, feed = false, false
    for _, mode in pairs(row.troughRoles or {}) do
        water,feed=water or mode=="water",feed or mode=="feed"
    end
    saved.blocker = #row.animals>0 and #row.hutches==0 and "animal_hutch_missing"
        or not water and "animal_water_trough_missing"
        or not feed and "animal_feed_trough_missing"
        or saved.enclosureTiles and saved.enclosureTiles<saved.minimumEnclosureTiles
            and "animal_cattle_enclosure_small" or deviceReason
    note()
    if selected then
        local cooldown = saved.cooldowns[selected.deviceKey]
        local door=selected.operation=="animal_open" or selected.operation=="animal_close"
        if cooldown and (not door or cooldown.operation==selected.operation)
            and (tonumber(cooldown.untilMs) or 0) > now() then return nil end
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
            or code=="animal_water_trough_missing" or code=="animal_feed_trough_missing"
            or code=="animal_roost_delayed" or code=="animal_cattle_enclosure_small") then return code end
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
        if pending.rejected or not pending.complete or pending.protected then
            snapshots[target.nativeZoneId] = nil
            return nil, "animal_zone_unavailable"
        end
        pending.auditedAt, pending.coverageStamp = now(), coverageStamp(base)
        remember(pending)
        local doc=document()
        local saved=doc and doc.zones[pending.id]
        if type(saved)=="table" then saveFlock(pending,saved) note() end
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
    if target.operation=="animal_milk" then
        local cow=row.members[target.cowId]
        if cow and n(cow,"getAnimalID")==target.cowId and contains(row,cow)
            and SC.BaseLife.withinWorkReach(cow)==true then return cow,row end
        return nil,"animal_milk_cow_unavailable"
    end
    for _, list in ipairs({ row.troughs, row.hutches }) do
        for _, object in ipairs(list) do
            if key(object) == target.deviceKey and U().squareOf(object)
                and (n(object,"getObjectIndex") or -1)>=0
                and contains(row, object) and SC.BaseLife.withinWorkReach(object) == true then return object, row end
        end
    end
    return nil, "animal_device_unavailable"
end

-- A fully checked animal zone may use the same bounded reach as crop fields,
-- lumber and burial areas. Devices must still belong to that exact zone.
function A.allowsWorkReach(job)
    local target = job and job.type == "farm" and job.target
    local row = target and target.animal and snapshots[target.nativeZoneId]
    -- An expired work snapshot must be refreshed by update, not divert travel
    -- to the rally point before that update can run. Effect guards stay fresh.
    return enabled() and row ~= nil and row.coverageStamp == coverageStamp(SC.BaseLife.active())
        and zoneUnchanged(row)
        and value(row.native, "isFullyStreamed") == true
        and SC.BaseLife.withinWorkReach(target) == true or false
end

local function releaseMilkHold(held)
    if held and held.milkBehavior then
        read(held.milkBehavior,"setBlockMovement",false)
        held.milkBehavior,held.milkApproachAt=nil,nil
    end
end

local function claim(actor, job)
    local target, current = job.target, now()
    local id, active, workers = U().idOf(actor), 0, {}
    for k, held in pairs(claims) do
        if held.expires <= current then releaseMilkHold(held) claims[k] = nil
        elseif held.zone == target.nativeZoneId and held.actor ~= id and not workers[held.actor] then
            active, workers[held.actor] = active + 1, true
        end
    end
    local held = claims[target.deviceKey]
    if held and (held.actor ~= id or held.job ~= job.id) or active >= 2 then return false end
    held=held or {}
    held.actor,held.job,held.zone,held.expires=id,job.id,target.nativeZoneId,current+30000
    claims[target.deviceKey]=held
    return true
end

local function release(actor, job)
    local held = claims[job.target.deviceKey]
    if held and held.actor == U().idOf(actor) and held.job == job.id then
        releaseMilkHold(held)
        claims[job.target.deviceKey] = nil
    end
end

local function fail(actor, job, reason)
    local doc = document()
    local saved = doc and doc.zones[job.target.nativeZoneId]
    if saved then
        local old = saved.cooldowns[job.target.deviceKey] or { failures = 0 }
        if old.operation~=job.target.operation then old={failures=0} end
        old.failures = math.min(3, old.failures + 1)
        old.at, old.untilMs = now(), now() + 15000 * 2 ^ (old.failures - 1)
        old.reason = reason
        old.operation = job.target.operation
        saved.cooldowns[job.target.deviceKey] = old
        note()
    end
    release(actor, job)
    return false, reason, true
end

function A.retryDelay(job,reason)
    if job and job.target and job.target.operation=="animal_milk"
        and (reason=="animal_milk_food_storage_missing" or reason=="animal_milk_container_unavailable"
            or reason=="farm_food_storage_missing") then return 180000 end
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
    local current,row = findDevice(job.target)
    if not enabled() or U().isDead(actor) or current ~= object
        or job.reservedBy ~= U().idOf(actor)
        or not held or held.actor ~= U().idOf(actor) or held.job ~= job.id
        or held.expires <= now() or support().threat(actor) then return false end
    if job.target.cattle and (C("animalCattleEnabled",0)~=1 or A.cattleThreat(actor,row)) then return false end
    if job.target.operation=="animal_milk" then
        local saved=document() and document().zones[job.target.nativeZoneId]
        if not A.milkPlan(object,row,saved,job.id)
            or U().directInteractionAccess(actor,object,{cardinalOnly=false})~=true then return false end
    end
    if not workDay(object) and not A.nightClosingJob(job) then return false end
    local resident = SC.BaseLife.resident(U().idOf(actor))
    if not resident or resident.role ~= "farmer" or resident.duty ~= true then return false end
    if item and not U().inventoryContains(U().inventory(actor), item) then return false end
    local ax, ay, az = U().position(actor)
    local ox, oy, oz = U().position(object)
    if not ax or not ox or az ~= oz or (ax-ox)^2+(ay-oy)^2 > 6.25 then return false end
    if job.target.operation == "animal_feed" then
        local species=#row.animals>0 and "chicken" or "cattle"
        local feed, maximum, amount = n(object, "getCurrentFeedAmount"),
            n(object, "getMaxFeed"), A.feedAmount(item,species)
        if (n(object, "getWater") or math.huge) > 0 or not feed or not maximum or not amount or feed >= job.target.high
            or feed + amount > maximum or not feedCompatible(item,row) then return false end
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
            A.roostReady(row,false) and #row.animals or nil, #row.animals) == operation
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
        action = "farm_" .. operation, targetKey = job.id,
        targetLabel = job.target.cattle and "cattle pasture" or "chicken pen",
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
            milkGuard = state.milk and state.milk.guard,
            milkCommit = state.milk and state.milk.commit,
            milkResult = state.milk,
            right = state.milk and state.milk.right,
            validate = function()
                return A.canUse(actor, job, object, item)
                    and A.canHutchWork(actor, job, state, object, operation)
                    and (operation ~= "animal_egg" or A.canTakeEgg(actor, job, state, object))
            end,
            beforeCommit = operation=="animal_close" and function()
                return A.roostReady(snapshots[job.target.nativeZoneId],true)
            end or nil })
    end)
    if not started then supervisor.fail(token, detail) return false, detail end
    if operation=="animal_water" and job.target.cattle then
        job.target.waterTrips=(tonumber(job.target.waterTrips) or 0)+1
        local doc=document() local saved=doc and doc.zones[job.target.nativeZoneId]
        if saved then
            saved.refills=type(saved.refills)=="table" and saved.refills or {}
            saved.refills[job.target.deviceKey]=true
        end
        note()
    end
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

-- Cancelling a staged load may close the loan because the same container is
-- already back at its source. Ordinary logistics can then deliver its milk.
function A.releaseStagedMilk(receipt)
    if not receipt.milk or not receipt.milk.staged or receipt.milkInvalid then return false end
    local source=SC.BaseLife.storage(receipt.sourceStorageId)
    local container=source and SC.BaseLife.resolveContainer(source)
    if not source or source.category~="farming" or not container then return false end
    for _,item in ipairs(U().inventoryItems(container,256)) do
        local marks=U().modData(item)
        if marks and marks[SC.FarmWork.ITEM_MARKER]==receipt.id
            and U().itemType(item)==receipt.itemType
            and tostring(value(item,"getID"))==tostring(receipt.nativeId)
            and value(item,"getContainer")==container then
            support().unmark(item,receipt.id)
            return SC.BaseLife.updateFarmReceipt(receipt.id,{phase="returned",blocker=false})
        end
    end
    return false
end

-- Reconcile selected eggs against the exact nest or the exact actor inventory.
-- No native lookup failure authorizes manufacturing an egg or replaying pickup.
function A.recoverReceipt(receipt)
    if receipt.milkInvalid then return true end -- Unknown milk evidence stays quarantined.
    if receipt.milk and (tonumber(receipt.milk.litres) or 0)>0 then
        local doc=document() local saved=doc and doc.zones[receipt.milk.zoneId]
        if saved then
            if saved.milked==nil then saved.milked={} end
            if type(saved.milked)=="table" then
                local id=tostring(receipt.milk.cowId)
                local previous=saved.milked[id]
                local day=type(previous)=="table" and tonumber(previous.day)
                if previous==nil or day and day<receipt.milk.day then
                    saved.milked[id]={day=receipt.milk.day,jobId=receipt.jobId} note()
                end
            end
        end
    end
    if receipt.milk and (receipt.phase~="recovery" or receipt.milk.staged) then
        -- Runtime closures never survive reload. Keep the exact pending loan
        -- attached to its original job; updateMilk reconciles its real owner.
        local job=SC.BaseLife.job(receipt.jobId)
        if job and job.target and job.target.operation=="animal_milk"
            and job.state~="completed" and job.state~="cancelled" then
            job.target.milkReceiptId=receipt.id
            return true
        end
    end
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
        if job.target.operation=="animal_milk" then A.reconcileMilk(actor,job,state) end
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

local function milkSaved(target)
    local doc=document()
    return doc and doc.zones[target.nativeZoneId]
end

function A.reconcileMilk(actor,job,state)
    local loan=state.borrowed
    local receipt=loan and SC.BaseLife.farmReceipt(loan.receiptId)
    if not receipt or not receipt.milk then return false end
    local fc=value(loan.item,"getFluidContainer")
    local amount=n(fc,"getAmount")
    if not milkNumber(amount) then return false end
    local milk=receipt.milk
    if amount+0.005<milk.after then
        milk.lost=milk.lost+milk.after-amount milk.uncertain=true
    end
    milk.after=amount
    local world=value(loan.item,"getWorldItem")
    local wx,wy,wz=U().position(world)
    if wx and wy and wz then milk.dropX,milk.dropY,milk.dropZ=math.floor(wx),math.floor(wy),math.floor(wz) end
    SC.BaseLife.updateFarmReceipt(receipt.id,{milk=milk})
    if value(loan.item,"getContainer")==U().inventory(actor)
        and U().inventoryContains(U().inventory(actor),loan.item) then
        if amount>0.0001 and value(fc,"isPureFluid",Fluid and Fluid.CowMilk)==true then
            SC.BaseLife.updateFarmReceipt(receipt.id,{kind="output",destinationCategory="fresh_food",phase="carried"})
            state.outputs={{item=loan.item,receiptId=receipt.id,category="fresh_food",milk=true}}
            state.borrowed=nil
        end
        return true
    end
    SC.BaseLife.updateFarmReceipt(receipt.id,{phase="recovery",blocker="animal_milk_container_missing"})
    return false
end

local function resumeMilkLoan(actor,baseState,job,state)
    local receipt=SC.BaseLife.farmReceipt(job.target.milkReceiptId)
    if not receipt then return false,"animal_milk_receipt_missing" end
    if receipt.milkInvalid then return false,"animal_milk_uncertain" end
    A.recoverReceipt(receipt) -- Rebuild daily evidence before permitting another native increment.
    if receipt.phase=="delivered" or receipt.phase=="returned" then
        job.target.milkReceiptId=nil state.milk=nil return true
    end
    if receipt.actorId~=U().idOf(actor) then return false,"animal_milk_carrier_unavailable" end
    local item,world
    local function matches(candidate)
        local data=U().modData(candidate)
        return data and data[SC.FarmWork.ITEM_MARKER]==receipt.id
            and tostring(value(candidate,"getID"))==tostring(receipt.nativeId)
    end
    for _,candidate in ipairs(U().inventoryItems(U().inventory(actor),256)) do
        if matches(candidate) then item=candidate break end
    end
    local source=SC.BaseLife.storage(receipt.sourceStorageId)
    local container=source and SC.BaseLife.resolveContainer(source)
    local destination=receipt.milk and SC.BaseLife.storage(receipt.milk.destinationStorageId)
    local deposited=destination and SC.BaseLife.resolveContainer(destination)
    if deposited and (destination.category=="food" or destination.category=="fresh_food")
        and SC.BaseLife.storageAcceptsDeposit(destination,deposited)==true then
        for _,candidate in ipairs(U().inventoryItems(deposited,256)) do
            local marks=U().modData(candidate)
            local owned=marks and (marks[SC.FarmWork.ITEM_MARKER]==nil
                or marks[SC.FarmWork.ITEM_MARKER]==receipt.id)
            if owned and U().itemType(candidate)==receipt.itemType
                and tostring(value(candidate,"getID"))==tostring(receipt.nativeId)
                and value(candidate,"getContainer")==deposited then
                if item and item~=candidate then return false,"animal_milk_uncertain" end
                support().unmark(candidate,receipt.id)
                SC.BaseLife.updateFarmReceipt(receipt.id,{phase="delivered",blocker=false})
                job.target.milkReceiptId=nil state.milk=nil
                return true
            end
        end
    end
    if not item and container then
        for _,candidate in ipairs(U().inventoryItems(container,256)) do
            if matches(candidate) then
                if receipt.milk and receipt.milk.staged and not A.milkDestination(actor,candidate) then
                    return false,"animal_milk_food_storage_missing"
                end
                support().unmark(candidate,receipt.id)
                local moved,why=SC.BaseWork.withdrawFromStorage(actor,baseState,source,container,candidate)
                support().mark(candidate,receipt.id)
                if moved and why=="base_supply_taken" then item=candidate
                else return moved==true,why end
                break
            end
        end
    end
    local milk=receipt.milk
    if not item and milk and milk.dropX and milk.dropY and milk.dropZ then
        local square=U().gridSquare(milk.dropX,milk.dropY,milk.dropZ)
        local objects=value(square,"getWorldObjects")
        if size(objects)<=32 and SC.BaseLife.withinWorkReach(square)==true then
            for index=0,size(objects)-1 do
                local candidateWorld=at(objects,index)
                local candidate=value(candidateWorld,"getItem")
                if candidate and matches(candidate) and value(candidate,"getWorldItem")==candidateWorld then
                    item,world=candidate,candidateWorld break
                end
            end
        end
        if item then
            local status,why=support().approach(actor,U().squareOf(world),world,A.allowsWorkReach(job))
            if status~="arrived" then return status~="failed",why end
            if SC.WorkTransport.hasRoom(U().inventory(actor),actor,item)~=true then return false,"animal_carry_capacity_low" end
            U().takeWorldItemVerified(world,U().inventory(actor),item)
            if value(item,"getContainer")~=U().inventory(actor)
                or value(item,"getWorldItem")~=nil then return false,"animal_milk_container_missing" end
        end
    end
    if not item then
        -- A missing identity never authorizes replacement stock or milk.
        return false,"animal_milk_container_missing"
    end
    state.borrowed={item=item,receiptId=receipt.id,storage=source,container=container}
    local amount=n(value(item,"getFluidContainer"),"getAmount")
    if not amount then return false,"animal_milk_uncertain" end
    if amount>0.0001 then
        A.reconcileMilk(actor,job,state)
    elseif receipt.milk and receipt.milk.litres>0 then
        state.milk={reason="animal_milk_uncertain"}
        state.animalReturn=true
    end
    return true
end

function A.deliverMilk(actor,baseState,job,state)
    local output=state.outputs and state.outputs[1]
    if not output or A.milkDestination(actor,output.item) then
        local moved,why,pending=support().deposit(actor,baseState,state)
        local receipt=output and SC.BaseLife.farmReceipt(output.receiptId)
        if receipt and receipt.phase=="delivered" and job.target.milkReceiptId==receipt.id then
            -- Terminal receipts are compacted when any worker borrows again.
            -- Clear this pointer at the verified deposit, before that can happen.
            job.target.milkReceiptId=nil state.milk=nil note()
        end
        return moved,why,pending
    end
    local receipt=SC.BaseLife.farmReceipt(output.receiptId)
    if not receipt or not receipt.milk or not receipt.milk.urgent then
        return false,"animal_milk_food_storage_missing",true
    end
    local source=SC.BaseLife.storage(receipt.sourceStorageId)
    local container=source and SC.BaseLife.resolveContainer(source)
    if not source or source.category~="farming" or not container
        or SC.BaseLife.storageAcceptsDeposit(source,container)~=true
        or SC.WorkTransport.hasRoom(container,actor,output.item)~=true then
        return false,"animal_milk_food_storage_missing",true
    end
    support().unmark(output.item,receipt.id)
    local moved,why=SC.BaseWork.depositToStorage(actor,baseState,source,container,output.item)
    if not support().mark(output.item,receipt.id) then return false,"animal_milk_uncertain",true end
    if moved and why=="base_supply_returned" then
        receipt.milk.staged=true
        SC.BaseLife.updateFarmReceipt(receipt.id,{phase="recovery",milk=receipt.milk,
            blocker="animal_milk_food_storage_missing"})
        state.outputs=nil release(actor,job)
        return false,"animal_milk_food_storage_missing",true
    end
    return moved==true,why,moved~=true
end

-- One ordinary farm job owns all loads of this cow's daily milking. Delivery
-- and reconciliation precede any further animal interaction, including reload.
function A.updateMilk(actor,baseState,job,runtime,state)
    local target,S=job.target,support()
    if state.animalWork then refreshTarget(target) end -- Retained, bounded census while the native action runs.
    if target.milkReceiptId and not state.borrowed and not state.outputs then
        local okay,why=resumeMilkLoan(actor,baseState,job,state)
        if not okay then return false,why,true end
        if why then return true,why end
    end
    if state.outputs then return A.deliverMilk(actor,baseState,job,state) end
    if target.milkStoppedReason then state.animalReturn=true end
    if state.animalReturn then
        local settled,why,pending=S.settle(actor,baseState,state)
        if not settled then return pending==true,why end
        if target.milkStoppedReason then
            local why=target.milkStoppedReason
            target.milkStoppedReason=nil state.animalReturn=nil
            local _,hours=time()
            target.milkRetryHour=hours and math.floor(hours)+1 or nil
            return fail(actor,job,why)
        end
        release(actor,job)
        local completed,why=SC.BaseLife.completeJob(job.id,U().idOf(actor),"cattle_care")
        return completed==true,completed and "farm_job_complete" or why
    end
    local cow,row=findDevice(target)
    if not cow then
        if row=="animal_audit_pending" then refreshTarget(target) return true,row end
        return fail(actor,job,row)
    end
    if not claim(actor,job) then return true,"animal_work_reserved" end
    local _,hours=time()
    if target.milkRetryHour and (not hours or hours<target.milkRetryHour) then
        return fail(actor,job,"animal_milk_resting")
    end
    local saved=milkSaved(target)
    local facts,reason=A.milkPlan(cow,row,saved,job.id)
    if state.animalWork then
        if not facts or S.threat(actor,runtime) or A.cattleThreat(actor,row) then
            local stopped,why=SC.NativeActions.cancelWork(actor,"animal_milk_interrupted")
            if not stopped then return true,why end
            state.milk.reason=reason or "animal_milk_interrupted"
        elseif SC.NativeActions.isWorkActive(actor) then
            if now()-state.animalWork.startedAt<=120000 then return true,"farm_animal_milk_active" end
            local stopped,why=SC.NativeActions.cancelWork(actor,"animal_action_timeout")
            if not stopped then return true,why end
            state.milk.reason="animal_action_timeout"
        end
        local finished,why=SC.NativeActions.finishWork(actor)
        if not finished then return true,why end
        local result=state.milk and state.milk.reason
        state.animalWork=nil
        if result=="animal_milk_uncertain" and state.borrowed then
            local receipt=SC.BaseLife.farmReceipt(state.borrowed.receiptId)
            if receipt and receipt.milk then
                receipt.milk.uncertain=true
                SC.BaseLife.updateFarmReceipt(receipt.id,{milk=receipt.milk})
            end
        end
        if not A.reconcileMilk(actor,job,state) then return fail(actor,job,"animal_milk_container_missing") end
        if result~="animal_milk_load_full" then state.animalReturn=true end
        if result~="animal_milk_load_full" and result~="animal_milk_finished" then
            target.milkStoppedReason=result or "animal_milk_uncertain"
        end
        return true,"animal_milk_delivering"
    end
    if not facts then
        releaseMilkHold(claims[target.deviceKey])
        if state.borrowed then state.animalReturn=true return true,reason end
        return fail(actor,job,reason)
    end
    if facts.amount-facts.reserve<0.1 then state.animalReturn=true return true,"animal_milk_finished" end
    if S.threat(actor,runtime) or A.cattleThreat(actor,row) then return fail(actor,job,"animal_cattle_unsafe") end
    if not state.borrowed then
        local handled,why,pending=S.borrow(actor,baseState,job,state,function(item)
            if not A.milkContainer(item) or A.milkRoom(actor,item,false)<0.1 then return false end
            state.milkContainerSeen=true
            return facts.urgent or A.milkDestination(actor,item,.1)~=nil
        end,{"farming"},"animal_milk_container",function(item) return A.milkRoom(actor,item,false) end)
        if not handled and why=="farm_supply_missing" then
            why=state.milkContainerSeen and "animal_milk_food_storage_missing" or "animal_milk_container_unavailable"
        end
        return handled,why,pending
    end
    local loan=state.borrowed
    if not A.milkContainer(loan.item) then
        return fail(actor,job,"animal_milk_container_changed")
    end
    local receipt=SC.BaseLife.farmReceipt(loan.receiptId)
    if not receipt then return fail(actor,job,"animal_milk_receipt_missing") end
    local destination,destinationContainer=A.milkDestination(actor,loan.item,.1)
    if not destination and not facts.urgent then
        target.milkStoppedReason="animal_milk_food_storage_missing" state.animalReturn=true
        return true,"animal_returning_supplies"
    end
    if not receipt.milk then
        local milk={version=1,cowId=target.cowId,zoneId=target.nativeZoneId,day=facts.day,
            fluid="CowMilk",before=0,after=0,litres=0,lost=0,urgent=facts.urgent}
        local okay=SC.BaseLife.updateFarmReceipt(receipt.id,{milk=milk})
        if not okay then return fail(actor,job,"animal_milk_receipt_missing") end
        target.milkReceiptId=receipt.id note()
    end
    -- Vanilla holds the animal before walking to its milking attachment. Keep
    -- that short approach under this exact claim; native action cleanup takes
    -- over after enqueue. No position, health or production value is changed.
    local held=claims[target.deviceKey]
    if not held.milkBehavior then
        held.milkBehavior=value(cow,"getBehavior")
        held.milkApproachAt=now()
    end
    if now()-held.milkApproachAt>15000 then
        state.milkSideRight=nil
        return fail(actor,job,"animal_milk_approach_timeout")
    end
    local _,paused=read(held.milkBehavior,"setBlockMovement",true)
    if not paused then return fail(actor,job,"animal_milk_approach_missing") end
    local side=A.milkSide(actor,cow,state.milkSideRight)
    if not side then return fail(actor,job,"animal_milk_approach_missing") end
    state.milkSideRight=side.right
    -- Use the same unobstructed adjacent-square interaction contract as other
    -- animal chores. Chasing a sub-tile point inside the cow's collision body
    -- can never finish; the stock action independently validates its distance.
    if U().directInteractionAccess(actor,cow,{cardinalOnly=false})~=true then
        local accepted,why=SC.Navigation.request(actor,side.square,"walk",{
            action="move_to_farm_plot",targetSquare=U().squareOf(cow),arrivalDistance=.15,
            interceptPosition={x=side.x,y=side.y,z=side.z},movingFormation=true,
            workCampOnly=true,workReach=A.allowsWorkReach(job)})
        if accepted~=true then
            state.milkSideRight=nil
            return fail(actor,job,why or "animal_milk_approach_missing")
        end
        return accepted==true,why,accepted~=true
    end
    state.milk={right=side.right}
    state.milk.guard=function()
        local owner=SC.BaseLife.farmReceipt(loan.receiptId)
        local marks=U().modData(loan.item)
        if state.borrowed~=loan or owner~=receipt or receipt.actorId~=U().idOf(actor)
            or receipt.jobId~=job.id or not marks or marks[SC.FarmWork.ITEM_MARKER]~=receipt.id
            or tostring(value(loan.item,"getID"))~=tostring(receipt.nativeId)
            or SC.BaseLife.storage(receipt.sourceStorageId)~=loan.storage
            or SC.BaseLife.withdrawable(loan.storage)~=true then return false,"animal_milk_uncertain" end
        local current=A.milkFacts(cow,snapshots[target.nativeZoneId])
        local fc=value(loan.item,"getFluidContainer")
        local amount=n(fc,"getAmount")
        local capacity=n(fc,"getCapacity")
        if not current or current.stress>math.min(40,C("animalMilkMaxStressPercent",40))
            or not amount or not capacity or amount>0 and value(fc,"isPureFluid",Fluid.CowMilk)~=true
            or value(fc,"isInputLocked")~=false then return false,"animal_milk_uncertain" end
        -- Capacity can grow by 0.1% of the genetic maximum during this step.
        local growth=current.calf and current.genetic*0.001*percent("animalMilkCalfReservePercent",40) or 0
        if current.calf and current.amount-0.1<current.reserve+growth+0.0001
            or not current.calf and current.amount<0.1 then return false,"animal_milk_finished" end
        if capacity-amount<0.0999 or A.milkRoom(actor,loan.item,true)<0.0999 then
            return false,"animal_milk_load_full"
        end
        if destination then
            local current=SC.BaseLife.storage(destination.id)
            local used=n(destinationContainer,"getCapacityWeight")
            local maximum=n(destinationContainer,"getEffectiveCapacity",actor)
            if current~=destination or SC.BaseLife.resolveContainer(current)~=destinationContainer
                or SC.BaseLife.storageAcceptsDeposit(current,destinationContainer)~=true
                or not used or not maximum or used+U().itemWeight(loan.item)+.1>maximum then
                return false,"animal_milk_load_full"
            end
        end
        return true
    end
    state.milk.commit=function(beforeMilk,beforeAmount)
        local fc=value(loan.item,"getFluidContainer")
        local afterMilk=n(value(cow,"getData"),"getMilkQuantity")
        local afterAmount=n(fc,"getAmount")
        local milk=receipt.milk
        if not milk or not afterMilk or not afterAmount then return false end
        local gain,loss=afterAmount-beforeAmount,beforeMilk-afterMilk
        local verified=gain>0 and gain<=0.101 and math.abs(gain-loss)<=0.005
            and value(fc,"isPureFluid",Fluid.CowMilk)==true
        milk.after=afterAmount
        milk.litres=milk.litres+math.max(0,gain)
        milk.lost=milk.lost+math.max(0,beforeAmount-afterAmount)
        milk.uncertain=milk.uncertain==true or not verified
        SC.BaseLife.updateFarmReceipt(receipt.id,{milk=milk})
        if gain>0 then
            saved.milked=type(saved.milked)=="table" and saved.milked or {}
            saved.milked[tostring(target.cowId)]={day=facts.day,jobId=job.id}
            note()
        end
        return verified
    end
    saved.milkAttempts=type(saved.milkAttempts)=="table" and saved.milkAttempts or {}
    local _,hours=time()
    saved.milkAttempts[tostring(target.cowId)]={hour=math.floor(hours),jobId=job.id}
    note()
    local started,why=begin(actor,job,state,cow,loan.item,"animal_milk")
    if started then
        held.milkBehavior,held.milkApproachAt=nil,nil -- Stock stop/complete now owns the hold.
    else
        releaseMilkHold(held)
        target.milkRetryHour=math.floor(hours)+1 note()
    end
    return started,why
end

function A.update(actor, baseState, job, runtime, state)
    local target, S = job.target, support()
    if target.operation=="animal_milk" then return A.updateMilk(actor,baseState,job,runtime,state) end
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
    if target.cattle and (C("animalCattleEnabled",0)~=1 or A.cattleThreat(actor,row)) then
        local stopped,why=A.cancel(actor,job,state,"animal_cattle_unsafe")
        if not stopped then return true,why end
        return fail(actor,job,"animal_cattle_unsafe")
    end
    local waterTripLimit=target.cattle and target.operation=="animal_water"
        and (tonumber(target.waterTrips) or 0)>=math.min(8,math.max(1,C("animalWaterTripsPerJob",2)))
    if waterTripLimit and not state.animalWork then state.animalReturn=true end
    if not state.animalWork and (target.operation=="animal_open" or target.operation=="animal_close") then
        local hour=time()
        local closed,known=read(object,"isDoorClosed")
        local night=hour and (hour>=A.species.chicken.dusk or hour<A.species.chicken.dawn)
        if known and (closed==(target.operation=="animal_close")
            or hour and (target.operation=="animal_close" and not night
                or target.operation=="animal_open" and night)) then
            state.animalReturn=true -- Already satisfied or superseded by dawn/dusk.
        end
    end
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
        if not okay then return true, reason end
        state.animalReturn = true
    end
    if not workDay(object) and not A.nightClosingJob(job) then
        local okay,reason=A.cancel(actor,job,state,"farm_outside_night")
        if not okay then return true,reason end
        state.animalReturn=true
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
        if not finished then return true,detail end -- Native hand/loan cleanup still owns the actor.
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
        if target.high then state.animalReturn = waterTripLimit
            or amount ~= nil and amount + 0.001 >= target.high end
    end
    if state.outputs then return S.deposit(actor, baseState, state) end
    if state.animalReturn then
        return true, "animal_returning_supplies"
    end
    if target.operation == "animal_egg" then
        local status, detail = S.approach(actor, U().squareOf(object), object,A.allowsWorkReach(job))
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
        if target.operation=="animal_close" and not A.roostReady(row,true) then
            return true,roostWaiting()
        end
        local status, detail = S.approach(actor, U().squareOf(object), object,A.allowsWorkReach(job))
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
        local status, detail = S.approach(actor, U().squareOf(object), object,A.allowsWorkReach(job))
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
                local amount = A.feedAmount(item,#row.animals>0 and "chicken" or "cattle")
                local current = n(object, "getCurrentFeedAmount")
                local maximum = n(object, "getMaxFeed")
                return amount and amount > 0 and feedCompatible(item,row) and current and maximum and current < target.high
                    and current + amount <= maximum
            end
        return S.borrow(actor, baseState, job, state, predicate,
            target.operation == "animal_water" and { "farming", "water" } or { "farming" },
            target.operation == "animal_water" and "water" or target.cattle and "cattle_feed" or "chicken_feed")
    end
    if target.operation == "animal_water" and S.waterUses(supply.item) <= 0 then
        local source, reason = S.findWater(actor, state, row)
        if not source then return reason == "water_source_scanning", reason, reason ~= "water_source_scanning" end
        local status, detail = S.approach(actor, U().squareOf(source), source,A.allowsWorkReach(job))
        if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
        return begin(actor, job, state, source, supply.item, "fill_water")
    end
    local status, detail = S.approach(actor, U().squareOf(object), object,A.allowsWorkReach(job))
    if status ~= "arrived" then return status ~= "failed", detail, status == "failed" end
    return begin(actor, job, state, object, supply.item, target.operation)
end

function A.reset(actor)
    if actor then
        for k, held in pairs(claims) do
            if held.actor == U().idOf(actor) then releaseMilkHold(held) claims[k] = nil end
        end
    else
        for _,held in pairs(claims) do releaseMilkHold(held) end
        scan, snapshots, claims, refreshes = nil, {}, {}, {}
        knownBase, zoneCursor, lastAudit = nil, 0, -math.huge
        zoneVisited, zoneCycleSize = 0, 0
    end
end

return A
