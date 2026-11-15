-- SPDX-License-Identifier: MIT
SC_VOICE_GATES={}
local G=SC_VOICE_GATES
function G.failures(m)
    local errors={}
    local function need(ok,key) if not ok then errors[#errors+1]=key end end
    need(m.lines>0 and m.recalls/m.lines>=.125 and m.recalls/m.lines<=1/3,"recall_share")
    for _,row in pairs(m.companions) do need(row.lines>0 and row.recall/row.lines>=.125 and row.recall/row.lines<=1/3,"companion_share") end
    need(m.falseClaims==0,"truth")
    need(m.repeats==0,"repeats")
    need(m.threePlus>0 and m.twoBeat==0 and m.overSix==0 and m.oneSpeaker==0 and m.tagErrors==0,"shape")
    need(m.cadenceErrors==0 and m.scenes/(m.days*24)>=.4 and m.scenes/(m.days*24)<=.6,"cadence")
    need(m.aftermath==m.events and m.covered==m.events,"aftermath")
    need(m.teaseInGrief==0 and m.lightAboutDead==0,"tone")
    need(m.pausedSpeech==0,"pause")
    need(m.maxBytes<=2048 and m.voiceActors<=64,"save_bound")
    return errors
end
function G.negativeControls()
    local base={lines=1000,recalls=200,companions={a={lines=1000,recall=200}},falseClaims=0,repeats=0,
        threePlus=720,twoBeat=0,overSix=0,oneSpeaker=0,tagErrors=0,cadenceErrors=0,scenes=720,days=60,
        aftermath=26,events=26,covered=26,teaseInGrief=0,lightAboutDead=0,pausedSpeech=0,maxBytes=1600,voiceActors=64}
    assert(#G.failures(base)==0,"valid voice gate control must pass")
    local mutants={
        {"recalls",0,"recall_share"},{"falseClaims",1,"truth"},{"repeats",1,"repeats"},
        {"twoBeat",1,"shape"},{"overSix",1,"shape"},{"oneSpeaker",1,"shape"},{"tagErrors",1,"shape"},
        {"cadenceErrors",1,"cadence"},{"scenes",1000,"cadence"},{"aftermath",25,"aftermath"},
        {"covered",25,"aftermath"},{"teaseInGrief",1,"tone"},{"lightAboutDead",1,"tone"},
        {"pausedSpeech",1,"pause"},{"maxBytes",2049,"save_bound"},{"voiceActors",65,"save_bound"},
    }
    for _,mutant in ipairs(mutants) do
        local value={} for k,v in pairs(base) do value[k]=v end
        value[mutant[1]]=mutant[2]
        local found=false for _,key in ipairs(G.failures(value)) do if key==mutant[3] then found=true end end
        assert(found,"voice gate accepted mutant: "..mutant[1])
    end
    local value={} for k,v in pairs(base) do value[k]=v end
    value.companions={a={lines=500,recall=200},b={lines=500,recall=0}}
    local found=false for _,key in ipairs(G.failures(value)) do if key=="companion_share" then found=true end end
    assert(found,"aggregate recall cannot hide a companion who never remembers")
    return #mutants+1
end
