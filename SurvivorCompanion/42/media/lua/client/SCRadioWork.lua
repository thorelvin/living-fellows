-- SPDX-License-Identifier: MIT
-- A real camp worker at a real radio-equipped PC. The SDR is a fictional
-- search display; it never reads an online service or future radio scripts.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.RadioWork = SC.RadioWork or {}
local R = SC.RadioWork
R.KEY, R.HOURS, R.CHANCE = "LF_RadioRecruit", 4, 35
local workers = setmetatable({}, { __mode = "k" })
local invitations = {}
local voiceNext = setmetatable({}, { __mode = "k" })
local radioChecked = setmetatable({}, { __mode = "k" })
local function U() return SC.GameplayUtil end
local function call(object, method, ...) return U().call(object, method, ...) end
local function hours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber((call(time, "getWorldAgeHours"))) or 0
end
local function finite(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then return fallback end
    return math.max(0, math.min(maximum, value))
end
local function memory(object, create)
    local data = call(object, "getModData")
    local portable = type(data) == "table" and data.movableData
    if type(portable) ~= "table" then return nil end
    local value = portable[R.KEY]
    if value == nil and create then value = { version = 1, serial = 0 }; portable[R.KEY] = value end
    if type(value) ~= "table" or value.version ~= 1 then return nil end
    if value.status~=nil and not ({queued=true,approaching=true,working=true,paused=true,finishing=true,found=true,quiet=true,idle=true})[value.status] then return nil end
    for _,key in ipairs({"operatorName","operatorId","jobId","resultJob"}) do
        if value[key]~=nil and (type(value[key])~="string" or #value[key]>160) then return nil end
    end
    if value.pendingVoice~=nil and not ({found_male=true,found_female=true,quiet=true})[value.pendingVoice] then return nil end
    local c=value.contact
    if c~=nil and (type(c)~="table" or type(c.id)~="string" or #c.id>80
        or c.id:sub(1,3)~="sc-" or type(c.name)~="string" or #c.name>160
        or type(c.identity)~="table" or not ({found=true,summoning=true,invited=true,arrival_uncertain=true})[c.status]) then return nil end
    if c then
        for _,key in ipairs({"forename","surname","gender","outfit"}) do
            if type(c.identity[key])~="string" or #c.identity[key]>96 then return nil end
        end
    end
    return value
end
local function say(actor, topic)
    if not SC.Dialogue then return false end
    local okay, spoken = pcall(SC.Dialogue.say, actor, "radio_work." .. topic)
    return okay and spoken == true
end
local messages = {
    radio_work_assigned = "Radio shift assigned. The operator will walk to this computer.",
    radio_work_no_power = "The computer has no power. Shift progress is saved; the job will retry.",
    radio_work_radio_missing = "Mount a working two-way walkie-talkie on this computer first.",
    radio_work_camp_only = "Assign radio operators from a computer inside your camp.",
    radio_work_locked = "Unlock this computer before assigning a radio operator.",
    radio_work_worker_missing = "Choose a living companion on base duty, inside camp and free of restrictions.",
    radio_work_worker_busy = "This companion is finishing another camp job. Choose another operator or retry later.",
    radio_work_already_assigned = "This computer already has a radio shift assigned.",
    radio_work_contact_pending = "Decide whether to invite the current contact before starting another search.",
    radio_work_no_contact = "There is no new survivor waiting on this radio.",
    radio_work_roster_full = "Your companion limit is reached. The contact remains available.",
    radio_work_arrival_blocked = "There is no safe, loaded arrival route to camp. The contact remains available; try again later.",
    radio_work_invited = "Camp directions sent. The survivor will join your roster and approach camp.",
    radio_work_already_invited = "This survivor is already in your roster. No second arrival was created.",
    radio_work_declined = "No camp directions sent. You can assign another radio shift.",
    radio_work_interrupted = "The operator was interrupted. Progress is saved.",
    radio_work_cancelling = "Cancel requested. The operator is releasing the keyboard.",
    radio_work_cancelled = "Radio shift cancelled.",
    radio_work_finishing = "Radio shift complete. The operator is releasing the keyboard.",
    radio_work_computer_missing = "The assigned computer is missing or unloaded. Restore it, retry, or cancel this shift.",
    radio_work_memory_missing = "The computer's radio record is unavailable. Cancel the shift and reopen this PC.",
}
function R.message(reason)
    return messages[reason] or (SC.ActionFeedback and SC.ActionFeedback.describe(SC.ActionFeedback.reason(reason)))
        or "The radio action could not be completed. Check the camp job and try again."
end
function R.available(object)
    if not SC.Terminal or not SC.Terminal.isComputer(object)
        or not SC.ControlUtil.present(object) then return false, "radio_work_computer_missing" end
    if not SC.BaseLife or not SC.BaseLife.isInside(object) then return false, "radio_work_camp_only" end
    if not SC.Terminal.powered(object) then return false, "radio_work_no_power" end
    local data = call(object, "getModData")
    local portable = type(data) == "table" and data.movableData
    local system = type(portable) == "table" and portable[SC.TerminalSystem.MEMORY_KEY]
    if type(system)~="table" or system.locked or portable.LF_GridCrack then return false, "radio_work_locked" end
    local hardware = SC.TerminalHardware and SC.TerminalHardware.state(object, false)
    if not hardware or not hardware.radio then return false, "radio_work_radio_missing" end
    local cached=radioChecked[object]
    if cached and cached.generation==hardware.generation and U().nowMs()>=cached.at
        and U().nowMs()-cached.at<1000 then return true end
    local receiver, _, item = SC.TerminalHardware.receiver(object)
    if not receiver or (tonumber((call(item, "getCondition"))) or 0) <= 0 then
        return false, "radio_work_radio_missing"
    end
    radioChecked[object]={at=U().nowMs(),generation=hardware.generation}
    return true
end
local function jobFor(object)
    local base = SC.BaseLife and SC.BaseLife.active()
    if not base then return nil end
    local reference = SC.BaseLife.describeObject(object, false)
    if not reference then return nil end
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "radio_work" and job.target and job.target.objectId == reference.objectId
            and job.state ~= "cancelled" and job.state ~= "completed" then return job end
    end
end
function R.crew()
    local result = {}
    for _, record in ipairs(SC.Registry and SC.Registry.records() or {}) do
        local actor = record.actor
        local resident = SC.BaseLife and SC.BaseLife.resident(record.id)
        local commands = actor and SC.Commands and SC.Commands.peek(actor)
        if record.recruited and actor and not U().isDead(actor) and resident and resident.duty
            and commands and commands.order == "base_duty"
            and not SC.BaseLife.restriction(record.id) then
            result[#result + 1] = { id = record.id, name = U().nameOf(actor) }
        end
    end
    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end
function R.assign(object, actorId)
    local okay, why = R.available(object)
    if not okay then return false, why end
    if jobFor(object) then return false, "radio_work_already_assigned" end
    local record = SC.Registry.byId(actorId)
    local eligible = false
    for _, row in ipairs(R.crew()) do if row.id == actorId then eligible = true break end end
    if not eligible or not record or not SC.BaseLife.isInside(record.actor) then
        return false, "radio_work_worker_missing"
    end
    if SC.BaseLife.jobFor(actorId) then return false, "radio_work_worker_busy" end
    local m = memory(object, true)
    if not m then return false, "radio_work_memory_missing" end
    if m.contact and (m.contact.status == "found" or m.contact.status == "summoning") then
        return false, "radio_work_contact_pending"
    end
    local target, reason = SC.BaseLife.describeObject(object, true)
    if not target then return false, reason end
    target.radioHours, target.radioGoal = 0, R.HOURS
    local accepted, job = SC.BaseLife.enqueueJob({ type = "radio_work", target = target,
        assignedId = actorId, priority = 4 })
    if not accepted then return false, job end
    m.jobId, m.operatorId, m.operatorName = job.id, actorId, U().nameOf(record.actor)
    m.progress, m.goal, m.status, m.contact = 0, R.HOURS, "queued", nil
    return true, "radio_work_assigned"
end
function R.owns(actor, object)
    local rt = workers[actor]
    return rt ~= nil and rt.object == object and SC.BaseLife.job(rt.jobId) ~= nil
end
local function cleanup(actor, rt, reason)
    if SC.NativeActions and SC.NativeActions.cancelVisual then
        local okay, why = SC.NativeActions.cancelVisual(actor, reason)
        if okay == false then return false, why end
    end
    if SC.Navigation then
        local nav = SC.Navigation.peek(actor)
        local request = nav and nav.lastApproachRequest
        if request and request.intent and request.intent.supervisorToken == rt.supervisorToken then
            SC.Navigation.cancel(actor, reason)
        end
    end
    SC.ComputerUse.release(actor, rt)
    local m = memory(rt.object)
    if m and m.jobId == rt.jobId and m.status == "working" then m.status = "paused" end
    workers[actor] = nil
    return true
end
function R.pause(actor, reason, jobId)
    local rt = workers[actor]
    if not rt or jobId ~= nil and rt.jobId ~= jobId then return true end
    local supervisor = SC.ActionSupervisor
    if supervisor.isCurrent(rt.supervisorToken) then
        return supervisor.cancel(actor, reason or "radio_work_paused")
    end
    -- A newer owner has already cleaned/preempted us. Never cancel its pose.
    SC.ComputerUse.release(actor, rt)
    workers[actor] = nil
    return true
end
function R.stop(object)
    local job = jobFor(object)
    if not job then return false, "radio_work_not_assigned" end
    job.target.radioCancelRequested=true
    local cancelled=SC.BaseLife.cancelJob(job.id)
    return true,cancelled and "radio_work_cancelled" or "radio_work_cancelling"
end
function R.decline(object)
    local okay,why=R.available(object)
    if not okay then return false,why end
    local m=memory(object)
    if not m or not m.contact or m.contact.status~="found" then return false,"radio_work_no_contact" end
    m.contact,m.pendingVoice,m.status,m.progress=nil,nil,"idle",0
    return true,"radio_work_declined"
end
local function finish(actor, job, object, m)
    -- Commit the single roll into both job and PC before removing the job.
    -- A retry/reload cannot reroll a completed shift.
    if not job.target.radioResult then
        local roll = type(ZombRand) == "function" and ZombRand(100) or math.random(0,99)
        job.target.radioResult = roll < R.CHANCE and "found" or "quiet"
    end
    if m.resultJob ~= job.id then
        m.resultJob, m.status = job.id, job.target.radioResult
        if job.target.radioResult == "found" then
            local identity = SC.Spawn.generateIdentity({ allowFamous = false })
            m.serial = math.floor(finite(m.serial, 0, 1000000)) + 1
            local system = call(object, "getModData").movableData[SC.TerminalSystem.MEMORY_KEY]
            m.contact = { status = "found", name = identity.forename .. " " .. identity.surname,
                identity = identity, id = "sc-radio-" .. tostring(math.abs(U().stableHash(system.identity)))
                    .. "-" .. m.serial, foundHours = hours() }
            m.pendingVoice = identity.gender == "female" and "found_female" or "found_male"
        else m.pendingVoice = "quiet" end
        if say(actor,m.pendingVoice) then m.pendingVoice=nil end
    end
    local released = R.pause(actor, "radio_work_shift_complete", job.id)
    if released ~= true then
        m.status = "finishing"
        return true, "radio_work_finishing", false, false
    end
    m.status = job.target.radioResult
    return true, "radio_work_shift_complete", false, true
end
function R.update(actor, _, job)
    if not job or job.assignedId~=U().idOf(actor) or job.reservedBy~=U().idOf(actor)
        or U().isDead(actor) then return false,"job_not_owned",true end
    if job.target.radioCancelRequested then
        local cancelled=SC.BaseLife.cancelJob(job.id)
        return true,cancelled and "radio_work_cancelled" or "radio_work_cancelling",false,cancelled==true
    end
    local object = SC.BaseLife.resolveObject(job.target)
    -- Once the result is saved, only keyboard release remains. A stopped pose
    -- or a reload must not start another action before retrying that cleanup.
    if job.target.radioResult then
        local saved = memory(object)
        if saved then return finish(actor, job, object, saved) end
    end
    local okay, why = R.available(object)
    if not okay then R.pause(actor, why); return false, why, true end
    local m = memory(object, true)
    if not m then R.pause(actor, "radio_work_memory_missing"); return false, "radio_work_memory_missing", true end
    local rt, supervisor, current = workers[actor], SC.ActionSupervisor, U().nowMs()
    if not rt then
        rt = { object = object, square = U().squareOf(object), jobId = job.id,
            kind = "computer_use", radioWork = true, durationMs = 20000, fact = {} }
        workers[actor] = rt
        local token, reason = supervisor.begin(actor, { owner = "radio_work", action = "computer_use",
            targetKey = job.target.objectId, targetLabel = "Radio recruitment watch", priority = 58,
            interruptible = true, requiresVisual = false,
            -- Stock chair entry can finish a small cushion alignment after
            -- reporting its seated pose, as it does for seated reading.
            poseMaximumDisplacement = .5,
            allowedActions = { computer_use = true, move_to_computer = true, sit = true },
            deadlines = { approaching = 120000, animating = 30000 },
            onCancel = function(_, cancelled) return cleanup(actor, rt, cancelled) end })
        if not token then workers[actor] = nil; return false, reason end
        rt.supervisorToken = token
        local claimed, claimReason = SC.ComputerUse.claim(actor, rt)
        if not claimed then R.pause(actor, claimReason); return false, claimReason, true end
        local reserved, reserveReason = supervisor.reserve(token, object, "radio_work_computer")
        if not reserved then R.pause(actor,reserveReason);return false,reserveReason,true end
        rt.lastHours = hours()
    end
    if not supervisor.isCurrent(rt.supervisorToken) then R.pause(actor); return true, "radio_work_paused" end
    m.jobId, m.operatorId, m.operatorName = job.id, U().idOf(actor), U().nameOf(actor)
    m.progress = finite(job.target.radioHours, 0, R.HOURS)
    m.goal = R.HOURS
    if not rt.actionAccepted then
        m.status = rt.renewing and "working" or "approaching"
        local arrived, reason = SC.ComputerUse.approach(actor, rt)
        if not arrived then R.pause(actor, reason); return false, reason, true end
        if reason ~= "arrived" then return true, "radio_work_approaching" end
        local started, startReason = SC.ComputerUse.start(actor, rt, current)
        if not started then
            -- The engine removes the completed sit action and starts the upper
            -- body action on separate updates. Allow that bounded handoff.
            if startReason=="computer_animation_rejected" then
                rt.keyboardWaitAt=rt.keyboardWaitAt or current
                if current-rt.keyboardWaitAt<5000 then return true,"radio_work_approaching" end
            end
            R.pause(actor, startReason); return false, startReason, true
        end
        rt.keyboardWaitAt=nil
        rt.lastHours, rt.lastAt = hours(), current
        if not job.target.radioGreeted then job.target.radioGreeted = say(actor, "start") end
        return true, "radio_work_listening"
    end
    if not SC.ComputerUse.valid(actor, rt, true) then
        R.pause(actor, "radio_work_interrupted"); return false, "radio_work_interrupted", true
    end
    local status = SC.NativeActions and SC.NativeActions.visualStatus(actor, "computer_use") or "active"
    if status ~= "active" and status ~= "completed" then
        R.pause(actor, "radio_work_interrupted"); return true, "radio_work_paused"
    end
    local h = hours()
    -- Credit only observed keyboard work. Loading a save, leaving camp or a
    -- long scheduling gap must not grant hours of unattended progress.
    if current >= rt.lastAt and current - rt.lastAt <= 10000 then
        job.target.radioHours = math.min(R.HOURS, m.progress + math.max(0, math.min(.1, h - rt.lastHours)))
    end
    rt.lastHours, rt.lastAt = h, current
    m.progress, m.status = job.target.radioHours or 0, "working"
    supervisor.progress(rt.supervisorToken, m.progress)
    if m.progress >= R.HOURS then return finish(actor, job, object, m) end
    -- The short native typing pose renews regularly. Chatter belongs to the
    -- saved shift, so renewal must not postpone every line forever.
    local nextChat=finite(job.target.radioBanterAt,.35,R.HOURS+.5)
    if m.progress>=nextChat and current>=(voiceNext[actor] or 0) then
        voiceNext[actor]=current+15000
        if say(actor,"banter") then job.target.radioBanterAt=m.progress+.5 end
    end
    if status == "completed" then
        -- A normal completion preserves vanilla's seated parent state. A
        -- forced stop/reset here can get the operator out of the chair.
        SC.NativeActions.clearVisual(actor)
        rt.actionAccepted,rt.renewing = nil,true
    end
    return true, "radio_work_listening"
end
function R.snapshot(object)
    local m, job = memory(object), jobFor(object)
    if not m then return { status = job and "paused" or "idle", progress = 0, goal = R.HOURS,
        jobId=job and job.id,blocker=job and "radio_work_memory_missing" } end
    local status=job and (job.target.radioCancelRequested and "cancelling"
        or job.state=="blocked" and "paused" or job.state=="pending" and "queued" or m.status)
        or ((m.status=="found" or m.status=="quiet") and m.status or "idle")
    return { status = status or "idle",
        progress = job and finite(job.target.radioHours, 0, R.HOURS) or finite(m.progress, 0, R.HOURS),
        goal = R.HOURS, operator = m.operatorName, jobId = job and job.id,
        blocker = job and job.blocker, contact = m.contact }
end
local function arrivalSquare(player, core)
    local routes=0
    for radius = 14, 30, 4 do for index = 0, 7 do
        local angle = index * math.pi / 4
        local square = U().gridSquare(math.floor(core.x + math.cos(angle)*radius),
            math.floor(core.y + math.sin(angle)*radius), 0)
        if square and call(square,"isFree",false) == true and call(square,"TreatAsSolidFloor") == true
            and not call(square,"getVehicleContainer") and call(square,"isSafeToSpawn") == true
            and not call(square,"getRoom") then
            routes=routes+1
            if SC.Navigation.spawnAccessible(square, player) then
                -- Welcome a new arrival on safe camp ground before a building
                -- wall. Their invitation never grants keys or permission to
                -- force a locked camp door just to reach an indoor camp core.
                local welcome
                local x,y=U().position(square)
                local steps=math.ceil(math.sqrt((core.x-x)^2+(core.y-y)^2))
                for step=1,math.min(40,steps) do
                    local q=U().gridSquare(math.floor(x+(core.x-x)*step/steps),
                        math.floor(y+(core.y-y)*step/steps),0)
                    if not q or call(q,"getRoom") or call(q,"isFree",false)~=true
                        or call(q,"TreatAsSolidFloor")~=true then break end
                    -- Camp markings may be wholly upstairs, or wider than
                    -- the loaded arrival band. The ground-level entrance is
                    -- still a valid place to meet the invited survivor.
                    welcome={x=call(q,"getX"),y=call(q,"getY"),z=0}
                end
                if welcome then return square,welcome end
            end
            if routes>=4 then return nil end
        end
    end end
end
function R.invite(object, player)
    local okay, why = R.available(object)
    if not okay then return false, why end
    local m = memory(object)
    local contact = m and m.contact
    if not contact or contact.status ~= "found" then return false, "radio_work_no_contact" end
    if SC.Registry.byId(contact.id) then
        contact.status="invited"
        return false,"radio_work_already_invited"
    end
    local base = SC.BaseLife.active()
    local pendingCount=0
    for _ in pairs(invitations) do pendingCount=pendingCount+1 end
    if not base or #SC.Registry.living() + pendingCount + (SC.Vehicle and SC.Vehicle.storedCount() or 0)
        >= SC.Config.get("maxCompanions") then return false, "radio_work_roster_full" end
    local square,welcome = arrivalSquare(player, base.core)
    if not square then return false, "radio_work_arrival_blocked" end
    -- Save the identity before dispatch. Interrupted native spawns are reconciled
    -- by this exact id and are never blindly recreated after reload.
    contact.status = "summoning"
    local ticket, reason = SC.Actor.beginSpawn(square, { id = contact.id, recruited = true,
        identity = contact.identity, initialize = function(actor)
            local body=call(actor,"getBodyDamage")
            -- Vanilla distributes general damage using the native body-part
            -- weights. Setting every part to 35 would multiply that damage;
            -- setting only the aggregate would be erased on the next update.
            local _,damaged=call(body,"ReduceGeneralHealth",65)
            local _,calculated=call(body,"calculateOverallHealth")
            if not damaged or not calculated then return false,"radio_work_vitals_unavailable" end
            local saved = SC.Vitals.capture(actor)
            if not saved or saved.overallHealth<25 or saved.overallHealth>45 then
                return false,"radio_work_vitals_unavailable"
            end
            saved.hunger, saved.thirst, saved.fatigue, saved.endurance = .6, .4, .65, .35
            return SC.Vitals.apply(actor, saved)
        end })
    if not ticket then contact.status = "found"; return false, reason end
    contact.arrivalTarget=welcome
    invitations[contact.id] = { ticket = ticket, contact = contact, core = welcome }
    return true, "radio_work_invited"
end
function R.pulse()
    -- Only explicit pending invitations; no search of houses or PCs.
    for id, pending in pairs(invitations) do
        local actor, reason = SC.Actor.pollSpawn(pending.ticket)
        if actor then
            SC.BaseLife.assign(id,"generalist",false)
            local accepted = SC.Commands.issue(id,"move_to",pending.core,
                type(getSpecificPlayer)=="function" and getSpecificPlayer(0) or nil)
            pending.contact.status = accepted and "invited" or "arrival_uncertain"
            invitations[id] = nil
        elseif reason ~= "spawn_pending" then
            pending.contact.status = "arrival_uncertain"
            invitations[id] = nil
        end
    end
end
function R.observe(object)
    local m = memory(object)
    local contact = m and m.contact
    if contact and contact.status=="found" and SC.Registry.byId(contact.id) then contact.status="invited" end
    if contact and (contact.status == "summoning" or contact.status == "arrival_uncertain")
        and not invitations[contact.id] then
        contact.status = SC.Registry.byId(contact.id) and "invited" or "arrival_uncertain"
    end
    if m and m.pendingVoice and U().nowMs()>=(voiceNext[object] or 0) then
        voiceNext[object]=U().nowMs()+30000
        local record=SC.Registry.byId(m.operatorId)
        if record and record.actor and say(record.actor,m.pendingVoice) then m.pendingVoice=nil end
    end
end
function R.reset()
    for actor in pairs(workers) do R.pause(actor, "radio_work_reset") end
    for _, pending in pairs(invitations) do SC.Actor.cancelSpawn(pending.ticket) end
    workers, invitations, voiceNext = setmetatable({}, { __mode = "k" }), {}, setmetatable({}, { __mode = "k" })
    radioChecked=setmetatable({}, {__mode="k"})
end
return R
