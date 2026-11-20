-- SPDX-License-Identifier: MIT
-- Runs the shipping medical owner/visual/commit pipeline on a disposable actor.
local Probe={}
local function queueCount(actor)
    local queue=ISTimedActionQueue and ISTimedActionQueue.queues and ISTimedActionQueue.queues[actor]
    return queue and queue.queue and #queue.queue or 0
end
local function limp(actor)
    return math.abs(assert(tonumber(actor:GetVariable('WalkInjury')),'native WalkInjury is unavailable'))
end
local function compareCaptures(s,check,note,label)
    local M=SurvivorCompanion.Medical
    local bridge=SCBridge
    local native=M.assess(s.actor)
    SCBridge=nil
    local okay,fallback=pcall(M.assess,s.actor)
    SCBridge=bridge
    assert(okay,fallback)
    for _,field in ipairs({'woundCount','dirtyBandages','bites','openWounds','maintenanceCount'}) do
        check(native[field]==fallback[field],label..' native/fallback '..field)
    end
    check(#native.wounds==#fallback.wounds,label..' native/fallback display rows')
    for i,row in ipairs(native.wounds) do
        local other
        for _,candidate in ipairs(fallback.wounds) do if row.index==candidate.index then other=candidate break end end
        check(other~=nil,label..' native/fallback same body part')
        for _,field in ipairs({'healed','stitched','stitchReady','splinted','boneHealed','bitten','scratched','cut','deepWound'}) do
            check(row[field]==other[field],label..' native/fallback '..field)
        end
    end
    note('production_capture='..label..'; active='..native.woundCount..'; rows='..#native.wounds..'; maintenance='..native.maintenanceCount)
    return native
end
function Probe.step(s,check,note,phase)
    local SC=SurvivorCompanion;local M=SC.Medical;local actor=s.actor
    local now=getTimestampMs()
    if string.sub(s.phase,1,16)~='acceptance-wash-' and string.sub(s.phase,1,16)~='acceptance-camp-' then
        -- Observe the loaded world through production senses; elective care
        -- must never obtain permission from an absent or invented snapshot.
        SC.Senses.snapshot(actor,s.primary,SC.GameplayUtil.actorState(actor))
    end
    if s.phase=='acceptance-start' then
        s.playerQueueBefore=queueCount(s.primary)
        local p=s.partReset();p:setBandaged(true,15,false,'Base.Bandage')
        local assessment=compareCaptures(s,check,note,'healed-clean')
        check(assessment.woundCount==0 and assessment.wounds[1].healed,'production healed clean dressing stays display-only')
        p:setBandaged(true,0,false,'Base.Bandage')
        assessment=compareCaptures(s,check,note,'healed-dirty')
        check(assessment.dirtyBandages==0 and not assessment.needsBandageChange,'production healed dirty dressing never requests replacement')
        for _,row in ipairs({
            {'bite',function(q) q:SetBitten(true,true);q:setBiteTime(9) end},
            {'scratch',function(q) q:setScratched(true,true);q:setScratchTime(9) end},
            {'cut',function(q) q:setCut(true,true);q:setCutTime(9) end},
            {'deep',function(q) q:setDeepWounded(true);q:setDeepWoundTime(9) end},
        }) do
            p=s.partReset();row[2](p);p:setBandaged(true,15,false,'Base.Bandage')
            assessment=compareCaptures(s,check,note,'hidden-'..row[1])
            check(assessment.woundCount==1,'production hidden '..row[1]..' counts as an active wound')
        end
        p=s.partReset();p:setStitched(true);p:setStitchTime(39);p:setBandaged(true,15,false,'Base.Bandage')
        s.medicalPart=p;phase('acceptance-stitch39')
    elseif s.phase=='acceptance-stitch39' then
        if now-s.at<700 then return end
        local assessment=compareCaptures(s,check,note,'hidden-stitch39')
        check(assessment.woundCount==1 and not assessment.needsMaintenance,'production39 stays attached')
        local okay,why=M.replaceDirtyBandage(actor)
        check(not okay and s.medicalPart:getStitchTime()<40 and M.peek(actor)==nil,'production refuses native39 removal: '..tostring(why))
        s.stitchLimp39=limp(actor);check(s.stitchLimp39>0,'native39 stitches cause actual WalkInjury')
        -- Leave a single exact fresh dressing to prove reserve/consume identity.
        local root=actor:getInventory();local items=root:getItems()
        for i=items:size()-1,0,-1 do if items:get(i):isCanBandage() then root:Remove(items:get(i)) end end
        s.medicalFresh=assert(root:AddItem('Base.Bandage'))
        s.medicalPart:setStitchTime(40);phase('acceptance-stitch40')
    elseif s.phase=='acceptance-stitch40' then
        if now-s.at<700 then return end
        local assessment=compareCaptures(s,check,note,'hidden-stitch40')
        check(assessment.needsMaintenance and assessment.wounds[1].stitchReady,'production40 is ready on actual hidden native timer')
        s.stitchLimp40=limp(actor)
        local okay,why=M.replaceDirtyBandage(actor)
        check(okay and M.peek(actor)~=nil,'production supervised visual starts for covered stitch removal: '..tostring(why))
        phase('acceptance-stitch-running')
    elseif s.phase=='acceptance-stitch-running' then
        check(now-s.at<25000,'production stitch action completes within bound')
        local okay,why=M.replaceDirtyBandage(actor)
        if M.peek(actor)~=nil then check(okay,'production stitch pipeline keeps ownership: '..tostring(why));return end
        check(okay and why=='stitches_removed','production stitch pipeline reports verified removal: '..tostring(why))
        check(s.medicalPart:getStitchTime()==0 and not s.medicalPart:stitched() and s.medicalPart:getScratchTime()>0,'production native removal leaves vanilla scratch')
        check(s.medicalPart:bandaged() and s.medicalFresh:getContainer()==nil,'production redress consumes reserved exact fresh supply')
        check(s.count(actor:getInventory(),'Base.Bandage')==1,'production previous clean covering returns exactly once')
        phase('acceptance-stitch-settled')
    elseif s.phase=='acceptance-stitch-settled' then
        if now-s.at<700 then return end
        local after=limp(actor)
        check(after<s.stitchLimp40,'actual native WalkInjury improves after ready stitch removal')
        note('production_stitch_walkinjury: at39='..s.stitchLimp39..'; at40='..s.stitchLimp40..'; removed='..after)
        local p=s.partReset();p:setFractureTime(0);p:setSplint(true,0);p:setSplintItem('Base.Plank')
        s.medicalPart=p;s.planksBefore=s.count(actor:getInventory(),'Base.Plank');s.ragsBefore=s.count(actor:getInventory(),'Base.RippedSheets')
        phase('acceptance-splint-ready')
    elseif s.phase=='acceptance-splint-ready' then
        if now-s.at<700 then return end
        check(now-s.at<30000,'ordinary medical action pacing expires before next acceptance episode')
        if SC.NativeActions.pacingStatus(actor) then return end
        local assessment=compareCaptures(s,check,note,'spent-zero-splint')
        check(assessment.woundCount==0 and assessment.needsMaintenance and assessment.wounds[1].boneHealed,'production true/zero-factor spent splint visible and maintainable')
        s.splintLimp=limp(actor);check(s.splintLimp>0,'native true/zero-factor splint causes actual WalkInjury')
        local okay,why=M.replaceDirtyBandage(actor)
        check(okay and M.peek(actor)~=nil,'production supervised visual starts for spent splint: '..tostring(why))
        phase('acceptance-splint-running')
    elseif s.phase=='acceptance-splint-running' then
        check(now-s.at<25000,'production splint action completes within bound')
        local okay,why=M.replaceDirtyBandage(actor)
        if M.peek(actor)~=nil then check(okay,'production splint pipeline keeps ownership: '..tostring(why));return end
        check(okay and why=='splint_removed' and not s.medicalPart:isSplint(),'production clears actual spent native attachment: '..tostring(why))
        check(s.count(actor:getInventory(),'Base.Plank')==s.planksBefore+1 and s.count(actor:getInventory(),'Base.RippedSheets')==s.ragsBefore+1,'production returns exact recorded splint materials once')
        phase('acceptance-splint-settled')
    elseif s.phase=='acceptance-splint-settled' then
        if now-s.at<700 then return end
        local after=limp(actor);check(after<0.001,'actual native spent-splint limp disappears')
        note('production_splint_walkinjury: attached='..s.splintLimp..'; removed='..after)
        check(queueCount(s.primary)==s.playerQueueBefore,'medical acceptance never queues a player timed action')
        phase('acceptance-wash-start')
    elseif string.sub(s.phase,1,16)=='acceptance-wash-' then
        if s.phase=='acceptance-wash-start' and SC.NativeActions.pacingStatus(actor) then
            check(now-s.at<30000,'ordinary medical action pacing expires before washing acceptance')
            return
        end
        s.washingAcceptance=s.washingAcceptance or require 'MedicalWashingAcceptance'
        if s.washingAcceptance.step(s,check,note,phase)==true then phase('acceptance-camp-start') end
    elseif string.sub(s.phase,1,16)=='acceptance-camp-' then
        s.campProbe=s.campProbe or require 'MedicalCampAcceptance'
        return s.campProbe.step(s,check,note,phase)
    end
end
return Probe
