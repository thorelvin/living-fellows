-- SPDX-License-Identifier: MIT

-- What EMMA can see from one computer. World.new returns a provider whose
-- functions read live game and camp state and return plain Lua tables; the
-- brain never holds a game object. Every read is bounded (containers, items,
-- squares and zombies all have caps) and runs only when the operator asks a
-- question, never on a tick. A read that fails returns nil and EMMA says so
-- in her own words.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.TerminalWorld = SC.TerminalWorld or {}
local World = SC.TerminalWorld

World.ZOMBIE_RADIUS = 40
World.ZOMBIE_SCAN_LIMIT = 2000
World.GENERATOR_RADIUS = 20
World.STORAGE_CONTAINERS = 40
World.ITEMS_PER_CONTAINER = 600
World.ITEMS_TOTAL = 4000
World.PEOPLE_LIMIT = 24
World.JOB_ROWS = 40
World.SKILLS = { { "Doctor", "First aid" }, { "Woodwork", "Carpentry" },
    { "Axe", "Axe handling" }, { "Farming", "Farming" },
    { "Mechanics", "Mechanics" }, { "Electricity", "Electrical" },
    { "Cooking", "Cooking" }, { "Aiming", "Aiming" } }

local function U() return SC.GameplayUtil end

local function call(object, method, ...)
    if object == nil then return nil end
    local utility = U()
    if utility and type(utility.call) == "function" then
        local value, ok = utility.call(object, method, ...)
        if ok then return value end
        return nil
    end
    local member = object[method]
    if type(member) ~= "function" then return nil end
    local ok, value = pcall(member, object, ...)
    return ok and value or nil
end

local function gridSquare(x, y, z)
    local utility = U()
    if utility and type(utility.gridSquare) == "function" then return utility.gridSquare(x, y, z) end
    return nil
end

local function humanize(value)
    if SC.UI and type(SC.UI.humanize) == "function" then return SC.UI.humanize(value) end
    return tostring(value or "")
end

-- Compass words from a map delta. Map x grows east and y grows south.
function World.direction(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax < 0.5 and ay < 0.5 then return "here" end
    local northSouth = dy < 0 and "north" or "south"
    local eastWest = dx > 0 and "east" or "west"
    if ax > ay * 2.414 then return eastWest end
    if ay > ax * 2.414 then return northSouth end
    return northSouth .. "-" .. eastWest
end

function World.whereText(origin, x, y, z)
    if not origin or x == nil or y == nil then return nil end
    local dx, dy = x - origin.x, y - origin.y
    local distance = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
    local floor = math.floor(z or 0) - math.floor(origin.z or 0)
    local level = floor > 0 and " upstairs" or (floor < 0 and " downstairs" or "")
    if distance < 2 then return "right here" .. level end
    return distance .. " meters " .. World.direction(dx, dy) .. level
end

-- Vanilla's own test for a powered appliance: a generator on the square, or
-- grid power inside a building while the grid still runs.
function World.powerState(square)
    if square == nil then return { generator = false, grid = false } end
    local generator = call(square, "haveElectricity") == true
    local grid = call(square, "hasGridPower") == true and call(square, "getRoom") ~= nil
    return { generator = generator, grid = grid }
end

function World.powered(square)
    local state = World.powerState(square)
    return state.generator or state.grid
end

-- Ring search outward from the terminal: the nearest running generator wins.
local function nearestGenerator(origin)
    local fallback
    for radius = 0, World.GENERATOR_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = gridSquare(origin.x + dx, origin.y + dy, origin.z)
                    local generator = square and call(square, "getGenerator") or nil
                    if generator then
                        if call(generator, "isActivated") == true then return generator end
                        fallback = fallback or generator
                    end
                end
            end
        end
    end
    return fallback
end

function World.nearestGenerator(square)
    local x, y, z = call(square, "getX"), call(square, "getY"), call(square, "getZ")
    if x == nil or y == nil or z == nil then return nil end
    return nearestGenerator({ x = x, y = y, z = z })
end

local function percent(current, maximum)
    current, maximum = tonumber(current), tonumber(maximum)
    if not current then return nil end
    if maximum and maximum > 0 then return math.max(0, math.min(100, current / maximum * 100)) end
    return math.max(0, math.min(100, current))
end

local function itemFacts(item)
    local name = call(item, "getDisplayName")
    local fullType = U() and U().itemType(item) or call(item, "getFullType")
    local category = call(item, "getDisplayCategory")
    local food = call(item, "IsFood") == true
    return tostring(name or fullType or "Unknown item"), fullType, category and tostring(category) or nil, food
end

local function containerLabel(container, storage)
    local kind = call(container, "getType")
    local label = kind and string.lower(humanize(kind)) or "container"
    if type(storage) == "table" and type(storage.category) == "string" and storage.category ~= "" then
        label = label .. " (" .. string.lower(humanize(storage.category)) .. ")"
    end
    return label
end

local function personName(id, fallback)
    if SC.UI and type(SC.UI.displayName) == "function" then
        local ok, name = pcall(SC.UI.displayName, { id = id }, fallback)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return fallback
end

function World.computerKind(object, brand)
    local square = call(object, "getSquare")
    local room = call(square, "getRoom")
    local function kindOf(candidate)
        local def = call(candidate, "getRoomDef") or candidate
        return SC.TerminalFiles.classify(call(def, "getName") or call(candidate, "getName"))
    end
    local kind = kindOf(room)
    if kind ~= "general" and kind ~= "office" then return kind end
    local businessKind=brand and SC.TerminalBrands and SC.TerminalBrands.kind(brand)
    if businessKind then return businessKind end
    local building = call(room, "getBuilding") or call(square, "getBuilding")
    local rooms = call(call(building, "getDef") or building, "getRooms")
    local size = math.min(32, tonumber(call(rooms, "size")) or 0)
    local found = {}
    for index = 0, size - 1 do found[kindOf(call(rooms, "get", index))] = true end
    local unique
    for candidate in pairs(found) do
        if candidate~="office" and candidate~="general" then
            if unique and unique~=candidate then return kind end
            unique=candidate
        end
    end
    return unique or kind
end

function World.new(player, object)
    local square = call(object, "getSquare")
    local origin
    if square then
        local x, y, z = call(square, "getX"), call(square, "getY"), call(square, "getZ")
        if x and y then origin = { x = x, y = y, z = z or 0 } end
    end
    local provider = { player = player, object = object, square = square, origin = origin }

    function provider.camp()
        local life = SC.BaseLife
        if not life or type(life.active) ~= "function" then return { configured = false } end
        local base = life.active()
        if not base then return { configured = false } end
        local inside = origin ~= nil and type(life.isInside) == "function"
            and life.isInside(origin) == true
        return { configured = true, inside = inside, name = base.name }
    end

    function provider.clock()
        if type(getGameTime) ~= "function" then return nil end
        local time = getGameTime()
        local hours = tonumber(call(time, "getWorldAgeHours")) or 0
        return {
            hour = tonumber(call(time, "getHour")) or 0,
            minute = tonumber(call(time, "getMinutes")) or 0,
            day = (tonumber(call(time, "getDay")) or 0) + 1,
            month = tonumber(call(time, "getMonth")) or 6,
            year = tonumber(call(time, "getYear")) or 1993,
            worldHours = hours,
            days = math.floor(hours / 24),
        }
    end

    function provider.weather()
        if type(getClimateManager) ~= "function" then return nil end
        local climate = getClimateManager()
        local temperature = tonumber(call(climate, "getTemperature"))
        if not temperature then return nil end
        return {
            temperature = temperature,
            rain = tonumber(call(climate, "getPrecipitationIntensity")) or 0,
            snow = call(climate, "isSnowing") == true,
            fog = tonumber(call(climate, "getFogIntensity")) or 0,
            wind = tonumber(call(climate, "getWindIntensity")) or 0,
        }
    end

    function provider.power()
        local state = World.powerState(square)
        if state.grid then return { source = "grid" } end
        if not state.generator then return { source = "none" } end
        local generator = origin and nearestGenerator(origin) or nil
        if not generator then return { source = "generator" } end
        return {
            source = "generator",
            fuel = percent(call(generator, "getFuel"), call(generator, "getMaxFuel")),
            condition = percent(call(generator, "getCondition"), 100),
        }
    end

    function provider.people()
        if provider.camp().inside ~= true then return nil end
        local result, seen = {}, {}
        local registry = SC.Registry
        if not registry or type(registry.living) ~= "function" then return result end
        for _, actor in ipairs(registry.living()) do
            if #result >= World.PEOPLE_LIMIT then break end
            local id = type(registry.idOf) == "function" and registry.idOf(actor) or nil
            local record = id and registry.byId(id) or nil
            local driver = SC.TaxiService and type(SC.TaxiService.isDriver) == "function"
                and SC.TaxiService.isDriver(actor) == true
            if record and record.recruited == true and not driver then
                local row = SC.UI and type(SC.UI.describeEntry) == "function"
                    and SC.UI.describeEntry(actor, player) or { name = U().nameOf(actor) }
                local person = { id = id, name = tostring(row.name or id) }
                seen[id] = true
                if row.expeditionAway == true then
                    person.away = true
                else
                    person.health = tonumber(row.health)
                    person.morale, person.stress = tonumber(row.morale), tonumber(row.stress)
                    person.mood = type(row.mood) == "string" and row.mood or nil
                    person.hunger, person.thirst = tonumber(row.hunger), tonumber(row.thirst)
                    person.endurance, person.fatigue = tonumber(row.endurance), tonumber(row.fatigue)
                    person.wounds, person.skills = {}, {}
                    for index, wound in ipairs(row.wounds or {}) do
                        if index > 8 then break end
                        local signs = {}
                        for _, condition in ipairs({ { "bitten", "bite" }, { "deepWound", "deep wound" },
                            { "fractured", "fracture" }, { "burned", "burn" }, { "cut", "cut" },
                            { "scratched", "scratch" }, { "bleeding", "bleeding" },
                            { "dirtyBandage", "dirty bandage" }, { "infected", "infected" } }) do
                            if wound[condition[1]] == true then signs[#signs + 1] = condition[2] end
                        end
                        if #signs > 0 then
                            person.wounds[#person.wounds + 1] = tostring(wound.name or "Unknown body part")
                                .. ": " .. table.concat(signs, ", ")
                                .. (wound.bandaged == true and "; bandaged" or "; unbandaged")
                        end
                    end
                    for _, skill in ipairs(World.SKILLS) do
                        local perk = Perks and Perks[skill[1]]
                        local level = perk and tonumber(call(actor, "getPerkLevel", perk))
                        if level then person.skills[#person.skills + 1] = { name = skill[2], level = level } end
                    end
                    local body = call(actor, "getBodyDamage")
                    person.bleeding = (tonumber(call(body, "getNumPartsBleeding")) or 0) > 0
                    local summary = row.actionSummary
                    if type(summary) == "table" and summary.active == true and SC.UI then
                        person.doing = SC.UI.stateText(summary.action)
                    elseif SC.UI and (row.activity or row.order) then
                        person.doing = SC.UI.stateText(row.activity or row.order)
                    end
                    local x, y, z = U().position(actor)
                    local where = World.whereText(origin, x, y, z)
                    local life = SC.BaseLife
                    person.atCamp = life and type(life.isInside) == "function"
                        and life.isInside(actor) == true or false
                    if where and person.atCamp then
                        where = "at camp, " .. where
                    end
                    person.where = where
                end
                result[#result + 1] = person
            end
        end
        local expedition = SC.ExpeditionPrototype
        local described = expedition and type(expedition.describeForPlayer) == "function"
            and expedition.describeForPlayer(player) or nil
        for _, member in ipairs(type(described) == "table" and described.members or {}) do
            if member.id and not seen[member.id] and #result < World.PEOPLE_LIMIT then
                seen[member.id] = true
                result[#result + 1] = { id = member.id, name = personName(member.id, member.name),
                    away = true }
            end
        end
        table.sort(result, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
        return result
    end

    function provider.jobs()
        if provider.camp().inside ~= true then return nil end
        local life = SC.BaseLife
        if not life or type(life.summary) ~= "function" then return nil end
        local summary = life.summary()
        local result = {
            active = summary.jobs and summary.jobs.active or 0,
            pending = summary.jobs and summary.jobs.pending or 0,
            blocked = summary.jobs and summary.jobs.blocked or 0,
            rows = {},
        }
        for index, row in ipairs(summary.rows or {}) do
            if index > World.JOB_ROWS then break end
            local job = humanize(row.kind or row.type or "work")
            local reason
            if row.blocker then
                reason = SC.UI and type(SC.UI.baseFailureReason) == "function"
                    and SC.UI.baseFailureReason(row.blocker, true) or nil
                if not reason or reason:find("^UI_SC_") then
                    reason = SC.TerminalLines.T.job_reason_unknown
                end
            end
            local autoRetry = row.autoRetry == true
                or row.autoRetry == nil and row.retryRemainingMs ~= nil
            result.rows[#result.rows + 1] = {
                id = row.id,
                state = row.state,
                job = job,
                who = row.reservedBy and personName(row.reservedBy, nil) or nil,
                reason = reason,
                autoRetry = autoRetry,
                retryRemainingMs = autoRetry and tonumber(row.retryRemainingMs) or nil,
            }
        end
        return result
    end

    function provider.storage()
        if provider.camp().inside ~= true then return nil end
        local life = SC.BaseLife
        if not life or type(life.storageRows) ~= "function" then return nil end
        local groups, byKey = {}, {}
        local containers, items, truncated = 0, 0, false
        for index, storage in ipairs(life.storageRows()) do
            if index > World.STORAGE_CONTAINERS then truncated = true break end
            local container = life.resolveContainer(storage)
            if not container then
                truncated = true
            else
                containers = containers + 1
                local label = containerLabel(container, storage)
                local list = U().inventoryItems(container, World.ITEMS_PER_CONTAINER + 1)
                if #list > World.ITEMS_PER_CONTAINER then truncated = true end
                for position = 1, math.min(#list, World.ITEMS_PER_CONTAINER) do
                    if items >= World.ITEMS_TOTAL then truncated = true break end
                    items = items + 1
                    local item = list[position]
                    local name, fullType, category, food = itemFacts(item)
                    local key = fullType or name
                    local group = byKey[key]
                    if not group then
                        group = { name = name, type = fullType, category = category, food = food,
                            count = 0, kcal = 0, where = {}, places = {} }
                        byKey[key] = group
                        groups[#groups + 1] = group
                    end
                    group.count = group.count + 1
                    if food then
                        group.kcal = group.kcal + math.max(0, tonumber(call(item, "getCalories")) or 0)
                    end
                    if not group.places[label] and #group.where < 3 then
                        group.places[label] = true
                        group.where[#group.where + 1] = label
                    end
                end
            end
        end
        for _, group in ipairs(groups) do group.places = nil end
        return { containers = containers, items = items, truncated = truncated, groups = groups }
    end

    function provider.shortages()
        if provider.camp().inside ~= true then return nil end
        local life = SC.BaseLife
        if not life or type(life.auditOperations) ~= "function" then return nil end
        local operations, _, pending = life.auditOperations(false)
        if type(operations) ~= "table" then return { pending = true } end
        local result = { pending = pending == true, stock = {}, alerts = {},
            unloaded = tonumber(operations.unloadedStores) or 0,
            ageSeconds = operations.auditedAt and U() and type(U().nowMs) == "function"
                and math.max(0, math.floor((U().nowMs() - operations.auditedAt) / 1000)) or nil }
        for index, row in ipairs(operations.stock or {}) do
            if index > 5 then break end
            result.stock[#result.stock + 1] = { name = humanize(row.category),
                count = tonumber(row.count), target = tonumber(row.target), status = row.status }
        end
        for index, alert in ipairs(operations.alerts or {}) do
            if index > 12 then break end
            if type(alert) == "string" then result.alerts[#result.alerts + 1] = alert end
        end
        return result
    end

    function provider.alarms()
        if provider.camp().inside ~= true then return nil end
        local service = SC.BaseAlert
        if not service or type(service.summary) ~= "function" then return nil end
        local current = service.summary()
        local cleared = service.lastCleared
        return { active = current and { level = humanize(current.level), count = current.count,
            side = current.side, spotter = personName(current.spotterId, "a resident"),
            responding = tonumber(current.responding) } or nil,
            last = cleared and { level = humanize(cleared.level), reason = humanize(cleared.reason) } or nil }
    end

    function provider.zombies()
        local utility = U()
        if not origin or not utility or type(getCell) ~= "function" then return nil end
        local list = call(getCell(), "getZombieList")
        if not list then return nil end
        local size = math.min(tonumber(call(list, "size")) or 0, World.ZOMBIE_SCAN_LIMIT)
        local radius = World.ZOMBIE_RADIUS
        local count, nearest, nearestDx, nearestDy = 0, nil, 0, 0
        for index = 0, size - 1 do
            local zombie = call(list, "get", index)
            if zombie and utility.isZombie(zombie) and not utility.isGoneTarget(zombie) then
                local x, y, z = utility.position(zombie)
                if x and math.abs(math.floor(z or 0) - math.floor(origin.z)) <= 1 then
                    local dx, dy = x - origin.x, y - origin.y
                    local distance = math.sqrt(dx * dx + dy * dy)
                    if distance <= radius then
                        count = count + 1
                        if not nearest or distance < nearest then
                            nearest, nearestDx, nearestDy = distance, dx, dy
                        end
                    end
                end
            end
        end
        return { count = count, radius = radius, nearest = nearest,
            dir = nearest and World.direction(nearestDx, nearestDy) or nil }
    end

    function provider.expedition()
        if provider.camp().inside ~= true then return nil end
        local expedition = SC.ExpeditionPrototype
        if not expedition or type(expedition.describeForPlayer) ~= "function" then
            return { active = false }
        end
        local described = expedition.describeForPlayer(player)
        if type(described) ~= "table" then
            local debrief = type(expedition.lastDebrief) == "function" and expedition.lastDebrief() or nil
            if not debrief then return { active = false } end
            local integration = debrief.integration and SC.ExpeditionIntegration
                and SC.ExpeditionIntegration.summary(debrief.integration) or nil
            return { active = false, last = {
                kind = debrief.kind and humanize(debrief.kind),
                reason = debrief.endReason and humanize(debrief.endReason),
                collected = (debrief.kind == "wood" or debrief.kind == "search") and #(debrief.acquisitions or {}) or nil,
                carried = integration and integration.carried,
                stored = integration and integration.stored,
                pending = integration and integration.pending,
                unknown = integration and integration.unknown,
                deliveryPending = integration and integration.deliveryPending,
                retryRemainingMs = integration and integration.retryRemainingMs,
            } }
        end
        local members = {}
        for _, member in ipairs(described.members or {}) do
            members[#members + 1] = personName(member.id, member.name or member.id)
        end
        local progress = described.woodProgress or described.supplyProgress
        local kind = described.kind and string.lower(humanize(described.kind)) or "supply"
        return {
            active = true,
            leader = described.leaderName,
            kind = kind,
            members = members,
            collected = type(progress) == "table" and tonumber(progress.collected) or nil,
            requested = type(progress) == "table" and tonumber(progress.requested) or nil,
            carried = type(progress) == "table" and tonumber(progress.carried) or nil,
            stored = type(progress) == "table" and tonumber(progress.stored) or nil,
            phase = described.observedPhase and humanize(described.observedPhase)
                or type(progress) == "table" and progress.phase and humanize(progress.phase) or nil,
            source = type(progress) == "table" and progress.source or nil,
            reportAt = type(progress) == "table" and tonumber(progress.at) or nil,
            partial = type(progress) == "table" and progress.partial == true or nil,
            destination = described.plannedSite,
            deliveryPending = described.delivery and described.delivery.deliveryPending,
            pending = described.delivery and tonumber(described.delivery.pending),
            retryRemainingMs = described.delivery and tonumber(described.delivery.retryRemainingMs),
        }
    end

    function provider.deliveries()
        if provider.camp().inside ~= true then return nil end
        local expedition = SC.ExpeditionPrototype
        if not expedition or type(expedition.pendingDeliveryReports) ~= "function" then return nil end
        local result = { rows = {} }
        for index, report in ipairs(expedition.pendingDeliveryReports() or {}) do
            if index > 8 then result.truncated = true break end
            local summary = report.summary
            if summary then
                result.rows[#result.rows + 1] = { kind = humanize(summary.kind or "expedition"),
                    collected = tonumber(summary.collected), carried = tonumber(summary.carried),
                    stored = tonumber(summary.stored), pending = tonumber(summary.pending),
                    unknown = tonumber(summary.unknown), toolsPending = summary.toolsPending == true,
                    retryRemainingMs = tonumber(summary.retryRemainingMs) }
            end
        end
        return result
    end

    return provider
end

return World
