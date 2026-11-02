-- SPDX-License-Identifier: MIT
-- Recomputed archive vocabulary; never changes the original word generator.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local W={} SC.TerminalLockWords=W
local stop={ALWAYS=true,ANYONE=true,BEFORE=true,BETTER=true,CANNOT=true,ENOUGH=true,
    REALLY=true,SHOULD=true,THINGS=true,THOUGH=true,UNLESS=true,WITHIN=true,WOULDN=true}
local function vocabulary(state)
    local profile=SC.TerminalFiles.get(state.archive) local result,seen={},{}
    for _,entry in ipairs(profile and profile.entries or {}) do
        for word in string.upper(entry.text or ""):gmatch("[A-Z]+") do
            if #word==6 and not stop[word] and not seen[word] then seen[word]=true result[#result+1]=word end
        end
    end
    return result
end
function W.ensure(state,skill)
    if state.puzzle then return state.puzzle end
    local pool=vocabulary(state)
    if #pool<3 then state.lock.kind="word" return SC.TerminalSystem.ensurePuzzle(state,skill) end
    local System=SC.TerminalSystem local pick=System.random(state.seed)
    local count,tries=System.settings(skill)
    local answer=pool[pick(#pool)] local candidates,seen={},{}
    local function add(word)
        if word~=answer and not seen[word] then
            seen[word]=true candidates[#candidates+1]={word=word,score=System.likeness(word,answer),tie=pick(1000000)}
        end
    end
    for _,word in ipairs(pool) do add(word) end
    -- Archive decoys first, then stable best-overlap vanilla words to fill
    -- exactly the native board size even in a short owner archive.
    table.sort(candidates,function(a,b) return a.score==b.score and a.tie<b.tie or a.score>b.score end)
    local words={answer}
    for _,row in ipairs(candidates) do if #words<count then words[#words+1]=row.word end end
    local extra={} candidates=extra
    for _,word in ipairs(System.words()) do add(word) end
    table.sort(extra,function(a,b) return a.score==b.score and a.tie<b.tie or a.score>b.score end)
    for _,row in ipairs(extra) do if #words<count then words[#words+1]=row.word end end
    for i=#words,2,-1 do local j=pick(i) words[i],words[j]=words[j],words[i] end
    state.puzzle={skill=skill,words=words,answer=answer,tries=tries,maximum=tries,guessed={},removed={},used={}}
    return state.puzzle
end
function W.sentence(state,word)
    local profile=SC.TerminalFiles.get(state.archive)
    for _,entry in ipairs(profile and profile.entries or {}) do
        for sentence in (entry.text or ""):gmatch("[^.!?]+[.!?]?") do
            for token in string.upper(sentence):gmatch("[A-Z]+") do
                if token==word then return sentence:match("^%s*(.-)%s*$") end
            end
        end
    end
end
return W
