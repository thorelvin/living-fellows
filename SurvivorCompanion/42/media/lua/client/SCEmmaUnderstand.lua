-- SPDX-License-Identifier: MIT
-- Bounded foreground parser, based on the reviewed original prototype.
local SC = SurvivorCompanion
require "SCTerminalLines"
require "SCTerminalKnowledge"
require "SCTerminalConversation"
if not SC.TerminalBrain then require "SCTerminalBrain" end
require "SCEmmaLanguageData"
require "SCEmmaWords"
require "SCEmmaCare"
require "SCEmmaSurvival"
require "SCEmmaFollowups"
require "SCEmmaReadings"
local Brain = SC.TerminalBrain
local D = SC.EmmaLanguageData
SC.EmmaUnderstand = SC.EmmaUnderstand or {}
local M = SC.EmmaUnderstand
local Conv = SC.TerminalConversation

local function set(list) local s = {} for _, v in ipairs(list or {}) do s[v] = true end return s end
local function trim(s) return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")) end
local function words(text) local out = {} for w in string.gmatch(text, "%S+") do out[#out + 1] = w end return out end
local function first(s) return string.sub(s, 1, 1) end
local REAL_WORDS
local function near(a, b) return not (REAL_WORDS and REAL_WORDS[a]) and #b >= 4 and #a >= 3
    and first(a) == first(b) and Brain.distance(a, b, 1) <= 1 end

-- Spelling guard (4.5): a real word is never "fixed".
local REAL = {}
local function addWords(text) for w in string.gmatch(string.lower(text), "%a+") do if #w >= 2 then REAL[w] = true end end end
local visited = {}
local function walk(t, depth)
    if depth > 7 or visited[t] then return end
    visited[t] = true
    for k, v in pairs(t) do
        if type(k) == "string" then addWords(k) end
        if type(v) == "string" then addWords(v) elseif type(v) == "table" then walk(v, depth + 1) end
    end
end
walk(SC.TerminalLines, 0) walk(Conv, 0) walk(D.pools, 0) if SC.TerminalKnowledge then walk(SC.TerminalKnowledge, 0) end
for w in string.gmatch(SC.EmmaWords.common, "%a+") do REAL[w] = true end
for w in string.gmatch(SC.EmmaWords.items, "%a+") do REAL[w] = true end
for _,word in ipairs(D.WORTH_WORDS) do REAL[word]=true end
REAL_WORDS = REAL
function M.known(word) return REAL[word] == true end

-- Mirrors CONTRACTIONS in SCTerminalBrain.lua (a local there), plus a few the corpus showed.
local CONTRACT = {
    whats = "what is", wheres = "where is", whos = "who is", hows = "how is", thats = "that is", theres = "there is",
    heres = "here is", its = "it is", im = "i am", ive = "i have", youre = "you are", youve = "you have",
    theyre = "they are", dont = "do not", doesnt = "does not", didnt = "did not", cant = "can not", cannot = "can not",
    wont = "will not", isnt = "is not", arent = "are not", wasnt = "was not", hes = "he is", shes = "she is",
    lets = "let us", ya = "you", yall = "you all", pls = "please", plz = "please", thx = "thanks", ty = "thanks",
    thanx = "thanks", thnx = "thanks", tnx = "thanks", wanna = "want to", gonna = "going to", gotta = "got to",
    gimme = "give me", genny = "generator", meds = "medicine", howdy = "hello", hiya = "hello", greetings = "hello",
    yeah = "yes", nope = "no", okay = "ok", zeds = "zombies", nite = "night", wouldnt = "would not",
    couldnt = "could not" }
local KEYS, KEY_LIST = {}, {}
for k, v in pairs(D.SLANG) do KEYS[k] = v end
for k, v in pairs(CONTRACT) do KEYS[k] = v end
for k in pairs(KEYS) do if #k >= 4 then KEY_LIST[#KEY_LIST + 1] = k end end
table.sort(KEY_LIST)

-- Rule 2: collapse letters repeated for emphasis, when that makes a known word.
-- Kahlua patterns have no back-references, so runs are squeezed by hand. Only runs of three or
-- more change; double letters are ordinary English.
local function squeeze(w, keep)
    local out, k = {}, 1
    while k <= #w do
        local c, j = string.sub(w, k, k), k
        while string.sub(w, j + 1, j + 1) == c do j = j + 1 end
        local run = j - k + 1
        out[#out + 1] = string.rep(c, run >= 3 and keep or run)
        k = j + 1
    end
    return table.concat(out)
end
local function collapse(w)
    if REAL[w] or KEYS[w] then return w end
    for _, candidate in ipairs({ squeeze(w, 1), squeeze(w, 2) }) do
        if candidate ~= w and (REAL[candidate] or KEYS[candidate]) then return candidate end
    end
    local last = string.sub(w, -1)
    if #w > 2 and string.sub(w, -2, -2) == last then
        local trimmed = string.sub(w, 1, -2)
        if REAL[trimmed] or KEYS[trimmed] then return trimmed end
    end
    return w
end
local function expand(tokens)
    local out, multi, typo = {}, #tokens > 1, false
    for _, raw in ipairs(tokens) do
        local w = collapse(raw)
        local rep = D.SLANG[w]
        if rep and (#w > 1 or multi) then
            for p in string.gmatch(rep, "%S+") do out[#out + 1] = p end
        elseif not REAL[w] and #w >= 3 then
            local hit
            for _, key in ipairs(KEY_LIST) do if near(w, key) then hit = KEYS[key] break end end
            if hit then for p in string.gmatch(hit, "%S+") do out[#out + 1] = p end
            else out[#out + 1] = w if not tonumber(w) then typo = true end end
        else
            out[#out + 1] = w
        end
    end
    return out, typo
end
local PHRASE_CACHE = {}
local function pwords(phrase)
    local cached = PHRASE_CACHE[phrase]
    if not cached then cached = Brain.tokens(phrase) PHRASE_CACHE[phrase] = cached end
    return cached
end
-- Rule 1: every table tolerates one typo per word of four letters or more.
local function phraseIn(toks, phrase, fuzzy)
    local pw = pwords(phrase)
    local n = #pw
    if n == 0 then return false end
    for start = 1, #toks - n + 1 do
        local ok = true
        for k = 1, n do
            local t, w = toks[start + k - 1], pw[k]
            if t ~= w and not (fuzzy and near(t, w)) then ok = false break end
        end
        if ok then return true end
    end
    return false
end
local function exactly(toks, phrase, fuzzy)
    local pw = pwords(phrase)
    if #pw ~= #toks then return false end
    local oneWord = #pw == 1
    for k = 1, #toks do
        if toks[k] ~= pw[k] and not (fuzzy and (not oneWord or #pw[k] >= 5) and near(toks[k], pw[k])) then return false end
    end
    return true
end

local function careOf(toks) return SC.EmmaCare.assess(table.concat(toks, " ")) end

local worthFillers=set({"so","such","a","an","just","really","completely","totally","the","biggest","absolute","total"})
local worthNegation=set({"not","never","no","longer"})
local worthTail=set({"and","lol","emma","today"})
local function worthEnding(tokens,at)
    for index=at+1,#tokens do if not worthTail[tokens[index]] then return false end end
    return true
end
local function worthWord(token)
    for _,word in ipairs(D.WORTH_WORDS) do
        if token==word or #word>=6 and near(token,word) then return true end
    end
    return false
end
local function worthOf(tokens)
    for at=1,#tokens-1 do
        local statement=tokens[at]=="i" and tokens[at+1]=="am"
        local question=tokens[at]=="am" and tokens[at+1]=="i"
        if statement or question then
            local cursor,negated=at+2,false
            while cursor<=#tokens do
                local word=tokens[cursor]
                -- These complete negative predicates really are put-downs;
                -- negating a negative adjective ("not stupid") is different.
                for _,predicate in ipairs({"not good enough","no good","bad person","bad leader"}) do
                    local words=pwords(predicate)
                    local match=true
                    for offset,value in ipairs(words) do if tokens[cursor+offset-1]~=value then match=false end end
                    if match and worthEnding(tokens,cursor+#words-1) then return negated and "news_plain" or "worth" end
                end
                if worthWord(word) then
                    if worthEnding(tokens,cursor) then return negated and "news_plain" or "worth" end
                    break
                elseif worthNegation[word] then negated=true
                elseif not worthFillers[word] then break end
                cursor=cursor+1
            end
        end
    end
    -- Authored non-copular put-downs still need a self reference. A copular
    -- phrase must use the bounded predicate above, never a substring match.
    local own=false
    for _,word in ipairs(tokens) do if word=="i" or word=="my" or word=="myself" then own=true end end
    if own then for _,phrase in ipairs(D.WORTH_PHRASES) do
        if phrase:sub(1,5)~="i am " and phraseIn(tokens,phrase,true) then return "worth" end
    end end
end

local TARGET = set({ "you", "your", "emma", "this", "u", "yourself" })
local GROUPS = { D.ME_INTENTS, D.TIME_INTENTS, D.HER_INTENTS, D.MORE_INTENTS }
local THEY = set({ "they", "them", "anyone", "anybody", "everyone", "everybody", "people" })
local function exactFirst(toks, fuzzy)
    for _, group in ipairs(GROUPS) do
        for _, spec in ipairs(group) do
            for _, e in ipairs(spec.exact or {}) do if exactly(toks, e, fuzzy) then return spec.id end end
        end
    end
end
local function scored(toks, fuzzy, names)
    local best, bestScore = nil, 0
    for _, group in ipairs(GROUPS) do
        for _, spec in ipairs(group) do
            local s = 0
            for _, e in ipairs(spec.exact or {}) do if exactly(toks, e, fuzzy) then s = s + 100 end end
            for phrase, w in pairs(spec.phrases or {}) do if phraseIn(toks, phrase, fuzzy) then s = s + w end end
            for word, w in pairs(spec.words or {}) do
                for _, t in ipairs(toks) do if t == word or (fuzzy and #word >= 5 and near(t, word)) then s = s + w break end end
            end
            if s>0 and spec.requires then
                local found=false
                for _,phrase in ipairs(spec.requires) do if phraseIn(toks,phrase,fuzzy) then found=true;break end end
                if not found then s=0 end
            end
            -- Rule 12: the name bonus only lifts the weak private-feelings phrases.
            if spec.id == "people_private" and s > 0 and s < 8 then
                local who = false
                for _, t in ipairs(toks) do if names[t] or THEY[t] then who = true end end
                s = who and s + 4 or 0
            end
            if s > bestScore then best, bestScore = spec.id, s end
        end
    end
    if bestScore >= 8 then return best end
end
local function conceptOf(tokens,fuzzy)
    local function any(list)
        for _,phrase in ipairs(list or {}) do if phraseIn(tokens,phrase,fuzzy) then return true end end
    end
    for _,spec in ipairs(D.CONCEPTS) do
        local okay=not spec.maxWords or #tokens<=spec.maxWords
        if spec.none and any(spec.none) then okay=false end
        for _,list in ipairs(spec.all) do if not any(list) then okay=false;break end end
        if okay and M.supported(spec.id) then return spec.id end
    end
end

-- Survival (section 13), rules 9 and 10.
local STOP = set({ "how", "do", "i", "a", "an", "the", "to", "is", "what", "can", "my", "it", "of", "in", "on", "for",
    "does", "you", "me", "should", "where", "when", "are", "with", "get", "any", "this", "that", "there", "be",
    "we", "am", "if", "or", "and", "from", "at", "your", "about", "need", "want", "not", "will", "some", "now",
    "out", "so", "emma", "please", "why", "which", "who", "happens", "safe", "best", "way" })
local SURV = {}
for _, topic in ipairs(SC.EmmaSurvivalData) do
    local qs = {}
    for _, q in ipairs(topic.questions) do
        local n, ws = 0, {}
        for _, t in ipairs(Brain.tokens(q)) do if not STOP[t] then ws[Brain.singular(t)] = true n = n + 1 end end
        qs[#qs + 1] = { toks = Brain.tokens(q), words = ws, n = n }
    end
    SURV[#SURV + 1] = { id = topic.id, qs = qs }
end
local CUES = { "how to", "what do i", "what should i", "can i", "should i", "is it safe", "what happens", "where do i",
    "where can i", "when should", "do i need", "best way", "what is", "what are", "my" }
local function howTo(toks, joined)
    if toks[1] == "how" then
        local second = toks[2]
        return second ~= "many" and second ~= "much" and second ~= "long" and second ~= "far" and second ~= "is"
            and second ~= "are" and second ~= "about" and second ~= "was" and second ~= "old"
    end
    if (toks[1] == "is" or toks[1] == "are") then for _, t in ipairs(toks) do if t == "safe" then return true end end end
    for _, cue in ipairs(CUES) do if string.find(" " .. joined .. " ", " " .. cue .. " ", 1, true) then return true end end
    return false
end
local function survivalExact(toks, fuzzy)
    for _, topic in ipairs(SURV) do for _, q in ipairs(topic.qs) do
        if exactly(toks, table.concat(q.toks, " "), fuzzy) then return topic.id end
    end end
end
local function survivalOf(toks, joined, fuzzy)
    if not howTo(toks, joined) then return nil end
    local content = {}
    for _, t in ipairs(toks) do if not STOP[t] then content[#content + 1] = Brain.singular(t) end end
    if #content == 0 then return nil end
    local bestId, best = nil, 0
    for _, topic in ipairs(SURV) do
        for _, q in ipairs(topic.qs) do
            local hit = 0
            for _, c in ipairs(content) do
                if q.words[c] then hit = hit + 1
                elseif fuzzy then for w in pairs(q.words) do if near(c, w) then hit = hit + 1 break end end end
            end
            local need = math.min(2, #content, q.n)
            local r = hit / math.max(q.n, #content)
            if hit >= need and need > 0 and r > best then best, bestId = r, topic.id end
        end
    end
    if best >= 0.5 then return bestId end
end

-- Statements (section 7), rules 6 and 8.
local LEADS, VERBS = set(D.STATEMENT_LEADS), set(D.STATEMENT_VERBS)
VERBS.going, VERBS.heading = true, true
local QWORDS = set({ "what", "where", "when", "why", "how", "who", "which", "is", "are", "do", "does", "did", "can",
    "could", "will", "would", "should", "am", "has", "have" })
local function statementOf(toks, raw, names, fuzzy)
    local lead = toks[1]
    local question = string.find(raw, "?", 1, true) or (lead and QWORDS[lead])
    for _, t in ipairs(toks) do if QWORDS[t] and (t == "what" or t == "how" or t == "why" or t == "where") then question = true end end
    local isStatement = not question and lead and (LEADS[lead] or VERBS[lead] or names[lead])
    for _, group in ipairs(D.NEWS) do
        if (isStatement or (group.anywhere and not question)) and (not group.resident or names[lead]) then
            for _, p in ipairs(group.phrases) do if phraseIn(toks, p, fuzzy) then return group.id end end
            for _, w in ipairs(group.whole or {}) do if #toks == 1 and toks[1] == w then return group.id end end
        end
    end
    return nil, isStatement
end
-- Rule 7: a command starts the line.
local POLITE = set({ "please", "can", "could", "you", "would", "will", "emma", "now" })
local function commandOf(toks, fuzzy)
    if #toks > 8 then return nil end
    local start = 1
    while toks[start] and POLITE[toks[start]] do start = start + 1 end
    local verb = toks[start]
    if not verb then return nil end
    for _, spec in ipairs(D.COMMANDS) do
        local verbOk = false
        for _, v in ipairs(spec.verbs) do if verb == v or (fuzzy and near(verb, v)) then verbOk = true end end
        if verbOk then
            for k = start, #toks do
                for _, o in ipairs(spec.objects) do
                    if toks[k] == o or (fuzzy and near(toks[k], o)) then return spec.id end
                end
            end
        end
    end
end

-- Rule 11: storage only for real items, follow-ups excepted.
local ITEMS = {}
for w in string.gmatch(SC.EmmaWords.items, "%a+") do ITEMS[w] = true end
for _,w in ipairs({"medicine","meds","fuel","supplies","weapons","guns","food","drink","drinks",
    "tools","materials","lumber","wood","seeds"}) do ITEMS[w]=true end
local function realItem(w)
    local s = Brain.singular(w)
    if ITEMS[w] or ITEMS[s] then return true end
    for item in pairs(ITEMS) do if near(w, item) or near(w, Brain.singular(item)) then return true end end
    return false
end
local function storageOk(itemWords)
    if type(itemWords) ~= "table" or #itemWords == 0 then return true end
    local numeric = true
    local FOLLOW = { more = true, them = true, it = true, those = true, these = true, that = true, any = true, left = true }
    for _, w in ipairs(itemWords) do if not tonumber((string.gsub(w, ",", ""))) and not FOLLOW[w] then numeric = false end end
    if numeric then return true end
    for _, w in ipairs(itemWords) do if realItem(w) then return true end end
    return false
end

local knockProtected=set({"status","food","storage","people_list","people_hurt","people_mood","person",
    "jobs","blocked","skills","shortages","alarms","deliveries","expedition","power","weather","time","date",
    "math","guide","survival","grid_control","notes","recall","help","conversation_history","more",
    "request","remember","forget","callme","factory_reset","yes","no"})

local ARITH = { { " times ", " * " }, { " multiplied by ", " * " }, { " plus ", " + " }, { " minus ", " - " },
    { " divided by ", " / " } }

local function contractions(text)
    return (string.gsub(text, "[%a]+'[%a]*", function(word)
        local letters = string.gsub(string.lower(word), "'", "")
        if CONTRACT[letters] then return word end
        -- Rule 16 overrides the known-word rule: an apostrophe means a contraction was meant.
        for key in pairs(CONTRACT) do
            if #key >= 4 and #letters >= 3 and first(letters) == first(key) and Brain.distance(letters, key, 1) <= 1 then return key end
        end
        return word
    end))
end
function M.careSignal(raw)
    local result=SC.EmmaCare.assess(raw)
    if result then return result end
    -- An apostrophe makes "ca't" a mistyped contraction, rather than the real
    -- word "cat". All entry points must share this override before dispatch.
    local expanded=expand(Brain.tokens(contractions(tostring(raw or ""))))
    result=SC.EmmaCare.assess(table.concat(expanded," "))
    if result then return result end
    local value=trim(tostring(raw or ""):lower())
    if #words(value)<=3 and value:find("</3",1,true) then return "comfort" end
end
function M.parse(session, text, world, turn, baseParse)
    turn=turn or {cache={}}
    text=tostring(text or ""):sub(1,Brain.MAX_INPUT)
    local care=M.careSignal(text)
    if care then return care, {} end
    local literal=text:lower():gsub("^emma[,:%s]+", "")
    if literal:find("^remember%s") or literal:find("^call me%s") or literal:find("^forget%s")
        or literal:find("^my name is%s") or literal:find("^factory reset")
        or literal:find("^refuel%s") or literal:find("^retry%s") or literal:find("^send%s")
        or literal:find("^ask the medic%s") or literal:find("^treat%s") then
        return baseParse(session,text,world,turn)
    end
    local answer=table.concat(Brain.tokens(text)," ")
    if session.context and (session.context.pending or session.context.personChoices)
        and (answer=="yes" or answer=="no" or answer=="ok" or answer=="y" or answer=="n"
            or answer=="first" or answer=="second" or answer=="third" or tonumber(answer))
        or Brain.arithmetic(text) then return baseParse(session,text,world,turn) end
    local names = {}
    SC.EmmaSurvival.install()
    text = contractions(text)
    local raw = string.lower(trim(text))
    local base = Brain.tokens(text)
    local toks, typo = expand(base)
    local fuzzy = typo
    -- Care is checked with and without typo-corrected slang; either match counts.
    local plain = {}
    for _, w in ipairs(base) do
        local rep = D.SLANG[w]
        if rep and (#w > 1 or #base > 1) then for q in string.gmatch(rep, "%S+") do plain[#plain + 1] = q end
        else plain[#plain + 1] = w end
    end
    local care = careOf(toks) or careOf(plain)
    if care then return care end
    -- Care wins first. Ordinary self put-downs receive warmth before hostile
    -- vocabulary or resource words can misclassify them.
    local worth=worthOf(toks)
    if worth then return worth,{} end
    if literal:find("^go back") or literal:find("^back to") then return baseParse(session,text,world,turn) end
    if phraseIn(toks,"scan radio channels",fuzzy) then return "guide",{guideId="scanner",page=1} end
    local direct=Conv.findGuide(text,Brain.tokens,Brain.distance,true)
    if direct then return "guide",{guideId=direct.id,page=1} end
    local function readingMatch(phrase) return phraseIn(toks,phrase,fuzzy) end
    local reading=exactFirst(toks,fuzzy) or scored(toks,fuzzy,{})
    if SC.EmmaReadings.intents[reading] then return reading,SC.EmmaReadings.slots(reading,table.concat(toks," "),readingMatch) end
    local readingFollow,readingSlots=SC.EmmaReadings.followup(session,table.concat(toks," "),readingMatch)
    if readingFollow then return readingFollow,readingSlots end
    local follow,followSlots=SC.EmmaFollowups.resolve(session,table.concat(toks," "))
    if follow then return follow,followSlots end
    local knockQuestion=QWORDS[toks[1]] and not (toks[1]=="do" and toks[2]=="not")
    if session.emmaKnock and session.emmaKnock.stage==2 and session.turns-session.emmaKnock.at<=3
        and #base<=8 and not text:find("?",1,true) and not knockQuestion then
        -- Data and checked requests keep their real handler. Otherwise the
        -- next short statement is the punchline, even if it mentions a joke.
        -- Count typed words: expanding "don't" and "it's" adds tokens, and
        -- an imperative "do not cry" is not a question starting with "do".
        local id,slots=baseParse(session,text,world,turn)
        if knockProtected[id] or SC.EmmaReadings.intents[id] then return id,slots end
        return "knock",{punchline=table.concat(toks," ")}
    end
    -- Raw forms (4.11), rule 3: ignore "emma" at either end.
    local rawCore = trim(string.gsub(string.gsub(raw, "^emma[,:%s]+", ""), "[,%s]+emma$", ""))
    local laughing=#toks>0 and #toks<=4
    for _,token in ipairs(toks) do
        if not (token:match("^lmao+$") or token:match("^lol+$") or token=="rofl" or token=="lmfao"
            or #token>=4 and token:gsub("ha","")=="") then laughing=false end
    end
    if laughing then return "laugh",{} end
    for id, forms in pairs(D.RAW_FORMS) do
        for _, f in ipairs(forms) do
            local plain = string.gsub(f, "%p", "%%%0")
            if rawCore == f or (string.find(rawCore, "%s" .. plain .. "$") and #words(rawCore) <= 3)
                or (string.find(rawCore, "^" .. plain .. "%s") and #words(rawCore) <= 3) then
                return id == "heartbreak" and "comfort" or id
            end
        end
    end
    local whole = {}
    for id, list in pairs(D.WHOLE_WORDS) do for _, p in ipairs(list) do whole[#whole + 1] = { id, p } end end
    for _, entry in ipairs(whole) do if exactly(toks, entry[2], fuzzy) then return entry[1] end end
    -- Rule 3: drop a leading "emma".
    while toks[1] == "emma" and #toks > 1 do table.remove(toks, 1) end
    for _, entry in ipairs(whole) do if exactly(toks, entry[2], fuzzy) then return entry[1] end end
    -- Swearing (4.3).
    local stripped, swore = {}, false
    for _, t in ipairs(toks) do if D.SWEARS[t] then swore = true else stripped[#stripped + 1] = t end end
    for _, p in ipairs(D.HOSTILE_PHRASES) do if phraseIn(toks, p, fuzzy) then return "insult" end end
    if swore then
        local noThe = {}
        for _, t in ipairs(stripped) do if t ~= "the" and t ~= "a" then noThe[#noThe + 1] = t end end
        for _, p in ipairs(D.HOSTILE_PHRASES) do if phraseIn(noThe, p, fuzzy) then return "insult" end end
        if #stripped == 0 then return "exclaim" end
        local target = false
        for _, t in ipairs(stripped) do if TARGET[t] then target = true end end
        if target and #stripped <= 6 then return "insult" end
        for _, entry in ipairs(whole) do if exactly(stripped, entry[2], fuzzy) then return entry[1] end end
        if #stripped <= 1 then return "exclaim" end
        toks = stripped
    end
    local joined = table.concat(toks, " ")
    -- Resident statements alone need a name vocabulary. No actor scan for
    -- ordinary chat or guides, and no camp readings from outside terminals.
    if toks[1] and toks[2] and (VERBS[toks[2]] or toks[2]=="is" or toks[2]=="died")
        and not LEADS[toks[1]] and not QWORDS[toks[1]] and world and type(world.camp)=="function" then
        local okay,camp=pcall(world.camp)
        if okay and type(camp)=="table" and camp.inside==true and type(world.people)=="function" then
            local called,people=pcall(world.people)
            if called and type(people)=="table" then
                turn.cache=turn.cache or {};turn.cache.people=people
                for index,person in ipairs(people) do
                    if index>256 then break end
                    for word in tostring(person.name or ""):lower():gmatch("%a+") do names[word]=true end
                end
            end
        end
    end
    local exactId = exactFirst(toks, fuzzy)
    if exactId and M.supported(exactId) then return exactId, {} end
    local survivalExact = survivalExact(toks, fuzzy)
    if survivalExact then return "guide", {guideId="survival_"..survivalExact,page=1} end
    local news, isStatement = statementOf(toks, raw, names, fuzzy)
    if news then
        if table.concat(toks," "):find("almost died",1,true) or table.concat(toks," "):find("nearly died",1,true) then return "news_escape",{} end
        return news, { statement=text }
    end
    -- A specific how-to question is advice, not a live threat/body count just
    -- because it contains "zombies", "infected" or "wounds".
    local survivalQuestion=survivalOf(toks,joined,fuzzy)
    if survivalQuestion then return "guide",{guideId="survival_"..survivalQuestion,page=1} end
    local intent = scored(toks, fuzzy, names)
    if intent and M.supported(intent) then return intent, SC.EmmaReadings.intents[intent] and SC.EmmaReadings.slots(intent,joined,readingMatch) or {} end
    local meaning=conceptOf(toks,fuzzy)
    if meaning then return meaning,{} end
    local command = commandOf(toks, fuzzy)
    if command then return "emma_controls", {} end
    local guide = Conv.findGuide(text, Brain.tokens, Brain.distance)
    if guide then return "guide", { guideId=guide.id, page=1 } end
    local survival = survivalOf(toks, joined, fuzzy)
    if survival then return "guide", {guideId="survival_"..survival,page=1} end
    if (toks[1] == "any" or (toks[1] == "do" and toks[2] == "we" and toks[3] == "have")) then
        local rest = {}
        for k = (toks[1] == "any" and 2 or 4), #toks do
            if toks[k]~="any" and toks[k]~="some" then rest[#rest + 1] = toks[k] end
        end
        for _, w in ipairs(rest) do if realItem(w) then return "storage",{item=rest,itemText=rest} end end
    end
    -- Rule 4: the old parser gets the expanded text when slang changed something; rule 5: arithmetic words.
    local changed = #base ~= #toks
    if not changed then for k = 1, #base do if base[k] ~= toks[k] then changed = true break end end end
    local forBrain = changed and joined or text
    if string.find(forBrain, "%d") then
        forBrain = " " .. string.lower(forBrain) .. " "
        for _, pair in ipairs(ARITH) do forBrain = string.gsub(forBrain, pair[1], pair[2]) end
        forBrain = trim(forBrain)
    end
    local brainIntent, slots = baseParse(session, forBrain, world, turn)
    if brainIntent=="insult" and isStatement then
        local target=false
        for _,word in ipairs(toks) do if TARGET[word] then target=true end end
        -- The fallback scorer can hear "dump" as "dumb". An ordinary
        -- first-person statement without a target is not hostility at EMMA.
        if not target then return "news_plain",{} end
    end
    if brainIntent == "storage" and not storageOk(slots and slots.item) then
        local stored=turn.cache and turn.cache.storage
        if not stored and world and type(world.storage)=="function" and type(world.camp)=="function" then
            local okay,camp=pcall(world.camp)
            if okay and type(camp)=="table" and camp.inside then
                local read,index=pcall(world.storage)
                if read then turn.cache=turn.cache or {};turn.cache.storage=index;stored=index end
            end
        end
        local found=false
        for _,group in ipairs(type(stored)=="table" and stored.groups or {}) do
            local name=tostring(group.name or ""):lower()
            local matches=true
            for _,word in ipairs(slots.item or {}) do
                if not name:find(Brain.singular(word),1,true) then matches=false;break end
            end
            if matches then found=true;break end
        end
        if not found then brainIntent="fallback" end
    end
    if isStatement and (brainIntent == "fallback" or brainIntent == "did_you_mean" or brainIntent == "mash") then
        if session.emmaKnock and session.turns-session.emmaKnock.at<=3 and #toks<=8 then
            return "knock",{punchline=joined}
        end
        return "news_plain"
    end
    if brainIntent=="fallback" and session.emmaKnock and session.turns-session.emmaKnock.at<=3 and #toks<=8 then
        return "knock",{punchline=joined}
    end
    return brainIntent, slots
end


local unsupported={her_memory=true}
function M.supported(id)
    if id:find("^time_") then return false end
    return not unsupported[id] and (D.pools[id]~=nil or Brain.hasHandler and Brain.hasHandler(id))
end

local function expandedRows(session,id,fields)
    local chosen=Brain.pick(session,id)
    if not chosen then return {} end
    local rows=type(chosen)=="table" and chosen or {chosen}
    local out={}
    for _,line in ipairs(rows) do
        local value=Brain.fill(line,fields)
        if not value:find("{[%w_]+}") then out[#out+1]=value end
    end
    return out
end
function M.install()
    if M.installed then return end
    M.installed=true
    SC.EmmaSurvival.install()
    SC.EmmaReadings.install()
    Brain.registerHandler("followup_clarify",SC.EmmaFollowups.clarify)
    Brain.registerHandler("her_last_operator",function(session,reply)
        reply.category="chat"
        -- The authored reveal has no unlocked milestone yet. Do not pretend
        -- that a fragment from an unrelated computer confirms this biography.
        reply.lines=expandedRows(session,"her_last_operator_guarded",{})
    end)
    Brain.registerHandler("memories",function(session,reply)
        reply.category="memory"
        reply.lines=SC.EmmaMind.report(session)
        reply.lines[#reply.lines+1]="Ask about EMMA's origins for the available county file. Your notes are separate; ask to recall them."
    end)
    Brain.registerHandler("quiet",function(session,reply)
        session.emmaBrief=true;reply.lines=expandedRows(session,"quiet_on",{});reply.category="chat"
    end)
    Brain.registerHandler("normal",function(session,reply)
        session.emmaBrief=nil;reply.lines=expandedRows(session,"quiet_off",{});reply.category="chat"
    end)
    Brain.registerHandler("knock",function(session,reply,turn)
        local previous=session.emmaKnock
        if not turn.slots.punchline then
            session.emmaKnock={stage=1,at=session.turns}
            reply.lines=expandedRows(session,"knock_open",{})
        elseif previous and previous.stage==1 then
            session.emmaKnock={stage=2,at=session.turns}
            reply.lines={turn.slots.punchline:sub(1,48).." who?"}
        else
            session.emmaKnock=nil;reply.lines=expandedRows(session,"knock_end",{})
        end
        reply.category="chat"
    end)
    for _,topic in ipairs({"distance","nearest"}) do
        local id=topic
        Brain.registerHandler(id,function(_,reply)
            reply.category="world"
            -- Recovered fragments carry town names, not coordinates or a
            -- surveyed route. Never turn them into an invented nearest place.
            reply.lines={id=="distance"
                and "I do not have a verified distance or route from this terminal. Use your map to check the town and approach."
                or "I do not have a verified nearby location for that here. Check your explored map before setting out."}
        end)
    end
    for id,rows in pairs(D.pools) do
        -- Regard and grudges belong to the later mind phase. Use the neutral
        -- authored variation until those signals actually exist.
        if rows.plain then rows=rows.plain end
        if id:find("_more$") then
            local target=SC.TerminalLines.POOLS[id:gsub("_more$","")]
            if target then for _,line in ipairs(rows) do target[#target+1]=line end end
        elseif not SC.TerminalLines.POOLS[id] then SC.TerminalLines.POOLS[id]=rows end
        if M.supported(id) and not Brain.hasHandler(id) then
            local intent=id
            Brain.registerHandler(intent,function(session,reply,turn)
                reply.category="chat"
                local slots=turn.slots or {}
                local fields={name=session.operator~="" and session.operator or "operator",
                    word=slots.word or "that",n=tonumber(tostring(slots.statement or ""):match("%d+")) or 0}
                if intent=="news_death" then
                    reply.lines={"I do not have a confirmed death record. If you have lost someone, I am sorry. You can tell me about them."}
                elseif intent=="news_bitten" or intent=="news_hurt" then
                    reply.lines={"Treat the wound and get somewhere safe. I cannot confirm your own condition from this terminal's records."}
                elseif intent=="news_killed" then
                    reply.lines={"You came back. That matters more than the count. Check your wounds before your supplies."}
                elseif intent=="declined" then
                    reply.lines={"Understood. I will skip the "..tostring(slots.topic or "subject").."."}
                else reply.lines=expandedRows(session,intent,fields) end
                if #reply.lines==0 then reply.lines={"I do not have a verified record for that here. Ask about supplies, people, jobs or survival files."} end
            end)
        end
    end
    Brain.registerHandler("news_escape",function(_,reply)
        reply.lines={"You made it back. Good. Take a moment before you try that again."};reply.category="chat"
    end)
    Brain.registerHandler("emma_controls",function(_,reply)
        reply.lines={"Use Local services and choose the named equipment. Read its checked request before confirming it."};reply.category="chat"
    end)
    Brain.registerHandler("fallback_echo",function(session,reply,turn)
        local fields={word=(turn.slots or {}).word or "that"}
        reply.lines=expandedRows(session,"fallback_echo",fields);reply.category="chat"
    end)
end

local literal={remember=true,forget=true,callme=true,factory_reset=true,request=true}
local function isLiteral(raw)
    local value=raw:lower():gsub("^emma[,:%s]+","")
    return value:find("^remember%s") or value:find("^call me%s") or value:find("^my name is%s")
        or value:find("^forget%s") or Brain.arithmetic(raw)
end
local function classify(raw,session,world)
    local context={}
    for key,value in pairs(session.context or {}) do context[key]=value end
    local conversation
    if session.conversation then
        conversation={topics={},history={},lastAt=session.conversation.lastAt}
        for _,topic in ipairs(session.conversation.topics or {}) do conversation.topics[#conversation.topics+1]=topic end
    end
    local copy={context=context,conversation=conversation,operator=session.operator,turns=session.turns,notes=session.notes,
        recent={},random=session.random,nowMs=session.nowMs}
    return M.parse(copy,raw,world,{cache={}},Brain.parseBase)
end
M.preview=function(session,raw,world) return classify(raw,session,world) end
function M.clauses(raw,session,world)
    if isLiteral(raw) then return {raw} end
    local pieces={raw}
    for _,separator in ipairs({"?","!",";",". "}) do
        local nextPieces={}
        for _,part in ipairs(pieces) do
            local from=1
            while true do
                local at=part:find(separator,from,true)
                if not at then nextPieces[#nextPieces+1]=part:sub(from);break end
                nextPieces[#nextPieces+1]=part:sub(from,at-1);from=at+#separator
            end
        end
        pieces=nextPieces
    end
    local out={}
    for _,part in ipairs(pieces) do
        part=trim(part)
        local left,right=part:match("^(.-)%s+and%s+(.+)$")
        if not left then left,right=part:match("^(.-)%s+also%s+(.+)$") end
        if left and right then
            local a,b=classify(left,session,world),classify(right,session,world)
            if a and b and a~="fallback" and a~="fallback_echo" and b~="fallback" and b~="fallback_echo"
                and a~="did_you_mean" and b~="did_you_mean" then
                out[#out+1]=trim(left);out[#out+1]=trim(right)
            else out[#out+1]=part end
        elseif part~="" then out[#out+1]=part end
        if #out>=3 then break end
    end
    return #out>0 and out or {raw}
end

function M.respond(session,raw,world,baseRespond)
    M.install()
    local intent=M.careSignal(raw)
    if not intent and SC.EmmaCare.quiet(session) then intent=classify(raw,session,world) end
    local care=SC.EmmaCare.respond(session,raw,intent,false)
    if care then return care end
    local negative=SC.EmmaCare.tokens(raw)
    local actions={refuel=true,retry=true,send=true,treat=true,lock=true,unlock=true,open=true,
        close=true,turn=true,switch=true,sound=true,start=true,run=true,activate=true,queue=true,
        reset=true,forget=true,delete=true,remove=true}
    local leads={["do"]=true,please=true,can=true,could=true,would=true,will=true,emma=true,
        ["not"]=true,never=true}
    local imperative=leads[negative[1]] or negative[1]=="i" and negative[2]=="do"
        and negative[3]=="not" and negative[4]=="want"
    local cancelled=table.concat(negative," "):find("actually do not",1,true)
    if imperative then
        for at,word in ipairs(negative) do
            if word=="not" or word=="never" then
                for offset=1,4 do if actions[negative[at+offset]] then cancelled=true end end
            end
        end
    end
    if cancelled then
        session.context.pending=nil
        return {intent="declined",category="chat",thinkMs=0,
            lines={"Understood. I have not prepared or carried out that action."}}
    end
    for at,word in ipairs(negative) do
        if word=="not" or word=="never" then
            for offset=1,4 do
                local topic=negative[at+offset]
                if topic=="joke" or topic=="story" or topic=="poem" or topic=="sing" or topic=="advice" then
                return {intent="declined",category="chat",lines={"Understood. I will skip the "..topic.."."},thinkMs=0}
                end
            end
        end
    end
    local clauses=M.clauses(raw,session,world)
    -- An input containing an action is one confirmation transaction. A second
    -- clause, even 'yes', cannot authorize or replace it inside this message.
    if #clauses>1 then
        for _,part in ipairs(clauses) do
            local id=classify(part,session,world)
            if literal[id] or id=="emma_controls" or id=="yes" or id=="no" then
                session.context.pending=nil
                return {intent="clarify_action",category="chat",thinkMs=0,lines={
                    "Ask for one action at a time. I have not prepared or carried out either request."}}
            end
        end
    end
    local reply
    local start=session.turns
    for index=1,math.min(2,#clauses) do
        local result=baseRespond(session,clauses[index],world)
        session.turns=start+1
        if not reply then reply=result
        else
            for _,line in ipairs(result.lines or {}) do reply.lines[#reply.lines+1]=line end
            reply.thinkMs=math.max(reply.thinkMs or 0,result.thinkMs or 0)
            reply.intent=result.intent
            reply.sensitive=reply.sensitive or result.sensitive
        end
        if result.proposal or result.command or session.context.pending then break end
    end
    if #clauses>2 then reply.lines[#reply.lines+1]="I answered two. Ask the rest separately." end
    if session.emmaBrief and reply.category=="chat" and #reply.lines>1 and not reply.proposal and not reply.command then
        reply.lines={reply.lines[1]}
    end
    if reply.intent=="fallback" then
        local word
        for candidate in raw:lower():gmatch("%a+") do
            if #candidate>=3 and not STOP[candidate] and not D.SWEARS[candidate]
                and (not word or #candidate>#word) then word=candidate end
        end
        if word then
            word=word:sub(1,16)
            reply.intent="fallback_echo"
            reply.lines=expandedRows(session,"fallback_echo",{word=word})
        end
    end
    if #clauses>1 then session.context.last={lines=reply.lines,category=reply.category,sensitive=reply.sensitive} end
    return reply
end

return M
