-- Glue for the EMMA playground: the real EMMA modules from the mod, one live session,
-- and a fixed test camp. EMMA's own Brain.respond writes every answer.
local js = PLAYGROUND_JS
local SC = SurvivorCompanion
local Brain = SC.TerminalBrain
local Lines = SC.TerminalLines

-- The playground never records what people type.
if SC.EmmaMissed then SC.EmmaMissed.record = function() end end

local function fixtureWorld()
    return {
        camp = function() return { configured = true, inside = true, name = "Rising" } end,
        clock = function() return { hour = 14, minute = 5, day = 12, month = 7, year = 1993, worldHours = 77, days = 3 } end,
        weather = function() return { temperature = 14, rain = 0.4, fog = 0, wind = 0.1, snow = false } end,
        power = function() return { source = "generator", fuel = 62, condition = 88 } end,
        people = function()
            return {
                { id = "sc-1", name = "Kate Miller", health = 42, bleeding = true, doing = "Chopping wood",
                    where = "at camp, 12 meters north-east", morale = 40, stress = 70 },
                { id = "sc-2", name = "Bob Fisher", health = 95, doing = "Idle", where = "at camp, right here",
                    morale = 60, stress = 20 },
                { id = "sc-4", name = "Dale", away = true },
            }
        end,
        jobs = function()
            return { active = 1, pending = 1, blocked = 1, rows = {
                { state = "active", job = "Chop wood", who = "Kate Miller" },
                { state = "blocked", job = "Build wall", reason = "Missing materials" },
                { state = "pending", job = "Farm" } } }
        end,
        storage = function()
            return { containers = 3, items = 30, truncated = false, groups = {
                { name = "Nails", type = "Base.Nails", category = "Material", count = 214, where = { "shelves (materials)" } },
                { name = "Canned Beans", type = "Base.TinnedBeans", category = "Food", food = true, kcal = 1800,
                    count = 6, where = { "shelves (food)" } },
                { name = "Water Bottle", type = "Base.WaterBottle", category = "Water", count = 4, where = { "fridge (food)" } },
                { name = "Bandage", type = "Base.Bandage", category = "FirstAid", count = 3, where = { "counter (medical)" } } } }
        end,
        zombies = function() return { count = 3, radius = 40, nearest = 17.4, dir = "north-west" } end,
        expedition = function() return { active = false } end,
    }
end
local world = fixtureWorld()

local state = { name = "Thor",voice="emma" }
local persona
local session, out, think, lastIntent, lastPrivate
-- The same rule as the mod's missed-message log: these never leave the game.
local privateIntents = { care = true, care_check = true, care_gentle = true, comfort = true, remember = true,
    callme = true, forget = true, recall = true, notes = true }
local function fresh()
    if state.voice~="emma" then
        persona=SC.TerminalPersona.new(state.voice,11)
        session=SC.TerminalPersona.session()
        return
    end
    persona=nil
    session = Brain.newSession({ operator = state.name, random = function(n)
        n = math.floor(tonumber(n) or 1)
        if n < 1 then return 1 end
        return math.random(n)
    end })
end
fresh()

local function respond(text)
    out, think, lastIntent, lastPrivate = {}, 0, "", false
    local reply
    if persona then
        local facts={days=4,hours=77,time="2:05 PM",hour=14,minute=5,zombies=3,companions=3,
            companion="Kate",drawer=persona.drawerGiven and "open" or "closed",moodles={}}
        reply=SC.TerminalPersona.respond(persona,session,text,facts)
        reply.intent=reply.layer
        reply.lines={}
        for _,row in ipairs(reply.rows or {}) do reply.lines[#reply.lines+1]=row.text end
        if reply.effects and reply.effects.drawer then SC.TerminalPersona.confirmDrawer(persona,true) end
    else reply = Brain.respond(session, text, world) or {} end
    for _, line in ipairs(reply.lines or {}) do out[#out + 1] = { tostring(line), "emma" } end
    if reply.support then
        local note = type(reply.support) == "table" and table.concat(reply.support, " ") or tostring(reply.support)
        out[#out + 1] = { note, "note" }
    end
    think = tonumber(reply.thinkMs) or 0
    lastIntent = tostring(reply.intent or "")
    lastPrivate = reply.private == true or privateIntents[lastIntent] == true
        or (SC.EmmaCare and SC.EmmaCare.quiet and SC.EmmaCare.quiet(session) and true or false)
    if reply.command == "close" then out[#out + 1] = { "[EMMA closes the session. Press Reboot to open it again.]", "sys" } end
end

local function boot(newSession)
    out, think, lastIntent, lastPrivate = {}, 0, "", false
    if newSession then fresh() end
    if persona then
        out={{SC.TerminalPersonaData[state.voice].title,"boot"},{"Line open. Type a message.","sys"}}
        return
    end
    local reply = Brain.boot(session, world) or {}
    lastPrivate=reply.private==true or privateIntents[reply.intent]==true or SC.EmmaCare.quiet(session) and true or false
    local banner = Lines and type(Lines.BOOT) == "table" and #Lines.BOOT or 0
    for index, line in ipairs(reply.lines or {}) do out[#out + 1] = { tostring(line), index <= banner and "boot" or "emma" } end
end

-- Interop passes `this` first, and it can be nil, so read arguments from the end.
local function quote(text)
    text = string.gsub(tostring(text), '[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end)
    return '"' .. text .. '"'
end
local function encode()
    local rows = {}
    for _, row in ipairs(out or {}) do rows[#rows + 1] = '{"t":' .. quote(row[1]) .. ',"k":' .. quote(row[2]) .. '}' end
    local readout = "Living Fellows 0.27.21 / "..state.voice.." / turn " .. tostring(session and session.turns or 0)
    return '{"rows":[' .. table.concat(rows, ",") .. '],"think":' .. tostring(math.floor(think or 0))
        .. ',"intent":' .. quote(lastIntent or "") .. ',"private":' .. (lastPrivate and "true" or "false")
        .. ',"readout":' .. quote(readout) .. '}'
end
js.global.EMMA_say = function(...)
    local n = select("#", ...)
    local text = select(n, ...)
    text=tostring(text or "")
    local normalized=text:lower():gsub("^emma[,:%s]+","")
    local privateInput=SC.EmmaUnderstand.careSignal(text)~=nil or SC.EmmaCare.quiet(session)
        or normalized:find("^remember%s") or normalized:find("^call me%s")
        or normalized:find("^my name is%s") or normalized:find("^forget%s")
    local ok, err = pcall(respond, text)
    if not ok then out = { { "Internal error: " .. tostring(err), "sys" } } end
    if privateInput then lastPrivate=true end
    return encode()
end
js.global.EMMA_boot = function(...)
    local n = select("#", ...)
    local which = select(n, ...)
    local ok, err = pcall(boot, which == "new")
    if not ok then out = { { "Internal error: " .. tostring(err), "sys" } } end
    return encode()
end
js.global.EMMA_set = function(...)
    local n = select("#", ...)
    local key, value = select(n - 1, ...), select(n, ...)
    if key=="voice" and (value=="emma" or SC.TerminalPersonaData[value]) then state.voice=value fresh()
    elseif key == "name" then
        state.name = tostring(value or "") ~= "" and tostring(value) or "Thor"
        if session then session.operator = state.name end
    end
    out = {}
    return encode()
end
