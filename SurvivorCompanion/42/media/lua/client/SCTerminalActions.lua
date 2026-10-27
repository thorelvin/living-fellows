-- SPDX-License-Identifier: MIT
-- EMMA may propose a request, but only a fresh, local confirmation can submit
-- it. Tickets are ephemeral and bind the exact computer, camp and target.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalActions = SC.TerminalActions or {}
local Actions = SC.TerminalActions
Actions.TTL_MS = 120000
local tickets = setmetatable({}, { __mode = "k" })
local function U() return SC.GameplayUtil end
local function call(object, method, ...)
    if not object then return nil end
    local value, okay = U().call(object, method, ...)
    if okay then return value end
end
local function clean(value)
    return string.lower(tostring(value or "")):gsub("[^%w ]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
local function matches(query, label)
    query, label = clean(query), " " .. clean(label) .. " "
    if query == "" then return true end
    for word in query:gmatch("%S+") do
        if not label:find(" " .. word .. " ", 1, true) then return false end
    end
    return true
end
local function reasonText(reason)
    if SC.UI and type(SC.UI.baseFailureReason) == "function" then
        local okay, text = pcall(SC.UI.baseFailureReason, reason)
        if okay and type(text) == "string" and text ~= "" then return text end
    end
    return tostring(reason or "request unavailable"):gsub("_", " ")
end
local function context(window, expectedBase, localServices)
    local terminal = SC.Terminal
    if not window or window.closed or terminal.window ~= window or not window.system
        or window.system.locked ~= false or not terminal.present(window.object)
        or not terminal.near(window.player, window.object)
        or not terminal.powered(window.object) or call(window.player, "isDead") == true then
        return nil, "This computer session is no longer available."
    end
    if type(getSpecificPlayer) ~= "function" or getSpecificPlayer(0) ~= window.player then
        return nil, "Only the main player's computer session can submit requests."
    end
    local data = call(window.object, "getModData")
    if not data or not data.movableData
        or data.movableData[SC.TerminalSystem.MEMORY_KEY] ~= window.system then
        return nil, "The computer's access record changed. Please reopen it."
    end
    if localServices then return true end
    local life = SC.BaseLife
    local base = life and type(life.active) == "function" and life.active() or nil
    if not base or expectedBase and expectedBase ~= base
        or type(life.isInside) ~= "function" or life.isInside(window.object:getSquare()) ~= true then
        return nil, "Camp requests need a computer inside the current camp."
    end
    return base
end
local function selectOne(rows)
    if #rows == 0 then return nil, "I cannot find an eligible target for that request." end
    if #rows > 1 then
        local names = {}
        for index = 1, math.min(4, #rows) do names[#names + 1] = rows[index].label end
        return nil, "Please name one target: " .. table.concat(names, "; ") .. "."
    end
    return rows[1]
end
local function actorRecord(id, expected)
    local registry = SC.Registry
    local record = registry and registry.byId(id)
    local actor = record and record.actor
    if not actor or expected and expected ~= actor or record.recruited ~= true
        or not U().isValidActor(actor) or SC.BaseLife.isInside(actor) ~= true
        or SC.ExpeditionPrototype and type(SC.ExpeditionPrototype.isMember) == "function" and SC.ExpeditionPrototype.isMember(actor)
        or SC.TaxiService and type(SC.TaxiService.isDriver) == "function" and SC.TaxiService.isDriver(actor) then return nil end
    return record
end
local function medicAvailableFor(helper, patient, player)
    local medical = SC.Medical
    if not medical or type(medical.peek) ~= "function" then return false end
    -- treat() advances any treatment the helper already owns, even when
    -- called with another patient. Readiness alone cannot bind this request.
    local active = medical.peek(helper)
    if active ~= nil and active.patient ~= patient then return false end
    return medical.travelRescueEligible(helper, patient, player)
        and medical.canTreatPatient(helper, patient)
end
local function prepareMedic(query, window)
    local medical, registry = SC.Medical, SC.Registry
    if not medical or not registry then return nil, "Medical requests are unavailable." end
    local patients, helpers = {}, {}
    for index, actor in ipairs(registry.living()) do
        if index > 24 then break end
        local id = registry.idOf(actor)
        local record = actorRecord(id, actor)
        if record then
            helpers[#helpers + 1] = record
            local assessment = medical.assess(actor, record.runtime)
            if matches(query, U().nameOf(actor)) and medical.hasActionableNeed(actor, assessment, false) then
                patients[#patients + 1] = { label = U().nameOf(actor), actor = actor, id = id }
            end
        end
    end
    local patient, reason = selectOne(patients)
    if not patient then return nil, reason end
    local best, score
    for _, record in ipairs(helpers) do
        local helper = record.actor
        if helper ~= patient.actor and medicAvailableFor(helper, patient.actor, window.player) then
            local level = Perks and Perks.Doctor and tonumber(call(helper, "getPerkLevel", Perks.Doctor)) or 0
            if not best or level > score or level == score and tostring(record.id) < tostring(best.id) then
                best, score = record, level
            end
        end
    end
    if not best then return nil, "No available camp medic can reach and treat " .. patient.label .. " with their current supplies." end
    return { kind = "medic", patient = patient.actor, patientId = patient.id,
        helper = best.actor, helperId = best.id,
        label = U().nameOf(best.actor) .. " to check " .. patient.label }
end
local function prepareTarget(window, proposal, base)
    local kind, query = proposal.kind, tostring(proposal.query or ""):sub(1, 120)
    if kind == "medic" then return prepareMedic(query, window) end
    local rows = {}
    if kind == "refuel_generator" then
        local generator = SC.TerminalWorld.nearestGenerator(window.object:getSquare())
        if not generator or not SC.GeneratorRefuel then return nil, "No loaded generator is available near this computer." end
        local okay, reason = SC.GeneratorRefuel.eligible(generator, true)
        if not okay then return nil, reasonText(reason) end
        return { kind = kind, actor = generator, label = "the nearby generator" }
    elseif kind == "refuel_vehicle" and SC.Vehicle and SC.VehicleRefuel then
        for index, vehicle in ipairs(SC.Vehicle.loadedVehicles()) do
            if index > 512 then break end
            local script = call(vehicle, "getScript")
            local name = SC.ExpeditionCar and type(SC.ExpeditionCar.displayName) == "function"
                and SC.ExpeditionCar.displayName(vehicle)
                or call(script, "getName") or call(vehicle, "getScriptName") or "Vehicle"
            local okay, info = SC.VehicleRefuel.eligible(vehicle, true)
            if okay and matches(query, name .. " " .. info.id) then
                rows[#rows + 1] = { kind = kind, actor = vehicle, id = info.id,
                    label = tostring(name) .. " (#" .. info.id .. ")" }
            end
        end
    elseif kind == "retry_job" then
        for index, job in ipairs(base.jobs or {}) do
            if index > 256 then break end
            if job.state == "blocked" and matches(query, tostring(job.id) .. " " .. tostring(job.type):gsub("_", " ")) then
                rows[#rows + 1] = { kind = kind, actor = job, id = job.id,
                    label = tostring(job.type):gsub("_", " ") .. " (#" .. tostring(job.id) .. ")" }
            end
        end
    else return nil, "I cannot submit that type of request." end
    return selectOne(rows)
end
function Actions.prepare(window, proposal)
    if type(proposal) ~= "table" then return nil, "Request unavailable." end
    local localServices = proposal.kind == "control"
    local base, reason = context(window, nil, localServices)
    if not base then return nil, reason end
    if localServices then
        local prepared, prompt = SC.TerminalServices.prepare(window, proposal)
        if not prepared then return nil, prompt end
        local ticket = {}
        tickets[ticket] = {window=window,localServices=true,target=prepared,at=U().nowMs()}
        return ticket, prompt
    end
    local target
    target, reason = prepareTarget(window, proposal, base)
    if not target then return nil, reason end
    local ticket = {}
    tickets[ticket] = { window = window, base = base, target = target, at = U().nowMs() }
    local verb = target.kind == "medic" and "Ask " or target.kind == "retry_job" and "Retry " or "Queue refuelling for "
    return ticket, verb .. target.label .. "? [Y/N]"
end
function Actions.cancel(ticket) if ticket then tickets[ticket] = nil end end
function Actions.reset() tickets = setmetatable({}, { __mode = "k" }) end
function Actions.execute(window, ticket)
    local request = ticket and tickets[ticket]
    -- Consume before any callback. Reentrancy, repeated Enter and errors cannot
    -- replay a request, even if a checked queue partially succeeds then throws.
    Actions.cancel(ticket)
    if not request or request.window ~= window then return false, "That confirmation is no longer pending." end
    local base, reason = context(window, request.base, request.localServices)
    if not base then return false, reason end
    local age = U().nowMs() - request.at
    if age < 0 or age > Actions.TTL_MS then return false, "That request expired. Please ask again." end
    if request.localServices then
        local okay, detail = SC.TerminalServices.execute(window, request.target)
        if type(detail) == "table" then detail = "Service queued. Ask about jobs to check progress." end
        return okay, reasonText(detail or (okay and "Request accepted." or "Request unavailable."))
    end
    local target = request.target
    local okay, detail
    if target.kind == "refuel_generator" then
        okay, detail = SC.GeneratorRefuel.queue(target.actor, true)
    elseif target.kind == "refuel_vehicle" then
        local eligible, info = SC.VehicleRefuel.eligible(target.actor, true)
        if not eligible or info.id ~= target.id then return false, "That vehicle is no longer eligible for refuelling." end
        okay, detail = SC.VehicleRefuel.queue(target.id, true)
    elseif target.kind == "retry_job" then
        if SC.BaseLife.job(target.id) ~= target.actor or target.actor.state ~= "blocked" then
            return false, "That job changed or is no longer blocked."
        end
        okay, detail = SC.BaseLife.retryJob(target.id)
    elseif target.kind == "medic" then
        local helper = actorRecord(target.helperId, target.helper)
        local patient = actorRecord(target.patientId, target.patient)
        if not helper or not patient or not medicAvailableFor(helper.actor, patient.actor, window.player) then
            return false, "The medic or patient is no longer available for this request."
        end
        okay, detail = SC.Medical.treat(helper.actor, patient.actor, helper.runtime)
    end
    if okay ~= true then return false, "I could not submit the request: " .. reasonText(detail) .. "." end
    if target.kind == "medic" then return true, "Asked " .. target.label .. ". Treatment still depends on safety and supplies." end
    return true, "Request submitted for " .. target.label .. ". Ask about jobs to check its progress."
end
return Actions
