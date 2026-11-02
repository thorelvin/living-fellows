-- SPDX-License-Identifier: MIT
-- Supplied data, actual outcome function; no retuning to fit a target percentage.
local SC=SurvivorCompanion local G=SC.TerminalLockStory
local report={}
for _,c in ipairs(SC.TerminalLockStoryData.classes) do
    for _,policy in ipairs({0,40,70}) do
        local won=0
        for seed=1,10000 do
            local pick=SC.TerminalSystem.random(seed*7837+31)
            local g=G.plan(seed*5197+13,1) g.class=c.id g.hp=2+c.hp g.maxHp=g.hp
            for step=1,5 do
                g.step=step local scene=G.scene(g.scenes[step])
                local choice=pick(100)<=policy and G.best(g,scene) or pick(3)
                local r=G.outcome(g,scene.options[choice],G.isRoll(g) and pick(20) or nil,0)
                g.hp=math.max(0,math.min(g.maxHp,g.hp+r.delta))
                if g.hp<=0 then break end
            end
            if g.hp>0 then won=won+1 end
        end
        assert(won>1000 and won<10000,"all classes remain playable, with failure possible")
        report[#report+1]=c.id.." "..policy.."% sensible="..(won/100).."%"
    end
end
SC_TEST_REPORT="Story simulation 10,000 runs/class/policy (Electrical 0, supplied HP): "..table.concat(report,"; ")
