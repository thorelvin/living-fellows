-- SPDX-License-Identifier: MIT
-- Reading acceptance at existing map computers through the native timed action.
-- No world objects, power overrides, password overrides or palettes are added.
local run={step=0,next=0,index=1,site=1,points={{12035,6739,0},{11941,6798,0},
    {11954,6860,0},{11978,6883,0},{12028,6849,1},{11951,6860,0},{11979,6884,0}}}
local function log(value)
    print("EMMA_READING|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-reading.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function shot(label)
    getCore():TakeFullScreenshot("emma-reading-computer-"..run.index.."-"..label)
    log("SHOT "..run.index.." "..label)
end
local function findDesktop()
    local p=run.points[run.site]
    local square=getCell():getGridSquare(p[1],p[2],p[3])
    if not square then return nil end
    local objects=square:getObjects()
    for index=0,objects:size()-1 do
        local object=objects:get(index)
        if SurvivorCompanion.Terminal.isComputer(object) then return object end
    end
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.Terminal or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        player:setGodMod(true) player:setGhostMode(true)
        if SC.UI and SC.UI.instance then SC.UI.instance:setVisible(false) end
        run.home={player:getX(),player:getY(),player:getZ()}
        local p=run.points[run.site]
        player:teleportTo(p[1]+1.5,p[2]+0.5,p[3])
        run.step,run.next,run.deadline=1,now+6000,now+45000
    elseif run.step==1 then
        run.object=findDesktop()
        if not run.object then
            assert(now<run.deadline,"existing map computer failed to stream")
            run.next=now+500 return
        end
        local square=run.object:getSquare()
        local spot
        local _,targets=SC.GameplayUtil.directInteractionAccess(player,run.object)
        for _,candidate in ipairs(targets) do
            if candidate:getRoom()==square:getRoom() and SC.GameplayUtil.isSquareFree(candidate)
                and SC.GameplayUtil.squareOccupyingObject(candidate)==nil then spot=candidate break end
        end
        if not spot then
            for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1},{0,2},{-1,2},{1,2},{2,0},{2,1},{2,-1}}) do
                local candidate=getCell():getGridSquare(square:getX()+offset[1],square:getY()+offset[2],square:getZ())
                if candidate and candidate:getRoom()==square:getRoom() and SC.GameplayUtil.isSquareFree(candidate)
                    and SC.GameplayUtil.squareOccupyingObject(candidate)==nil then spot=candidate break end
            end
        end
        assert(spot,"no clear adjacent standing tile beside the existing desktop")
        assert(SC.Terminal.powered(run.object),"existing desktop has no real power")
        player:teleportTo(spot:getX()+0.5,spot:getY()+0.5,spot:getZ())
        player:faceThisObject(run.object)
        local room=square:getRoom()
        log("EXISTING_DESKTOP "..square:getX()..":"..square:getY()..":"..square:getZ()
            .." sprite="..run.object:getSprite():getName().." room="..tostring(room and room:getName())
            .." powered=true camp="..tostring(SC.BaseLife.isInside(square)))
        run.step,run.next=2,now+2500
    elseif run.step==2 then
        shot("desk")
        run.step,run.next=3,now+1500
    elseif run.step==3 then
        assert(SC.Terminal.use(player,run.object),"normal native Use computer action was refused")
        run.step,run.next,run.deadline=4,now+500,now+30000
    elseif run.step==4 then
        local window=SC.Terminal.window
        if not window or window.object~=run.object then
            assert(now<run.deadline,"native Use computer action did not open the desktop")
            run.next=now+500 return
        end
        log("OPEN_NATIVE computer="..run.index.." identity="..window.system.identity
            .." brand="..tostring(window.brand).." theme="..window.system.theme
            .." locked="..tostring(window.system.locked))
        if run.index==2 and not window.system.locked then
            -- Look for a naturally locked original machine, without changing
            -- any lock or palette to manufacture a recovery screenshot.
            assert(run.site<#run.points,"none of the inspected original desktops was locked")
            window:close() run.site=run.site+1
            local p=run.points[run.site]
            player:teleportTo(p[1]+1.5,p[2]+0.5,p[3])
            run.step,run.next,run.deadline=1,now+6500,now+45000
            return
        end
        run.step,run.next=5,now+6500
    elseif run.step==5 then
        local window=assert(SC.Terminal.window)
        window:flush()
        if not window.system.locked then
            if run.index==1 then
                window:setFocusMode("chat")
                window.entry.javaObject:SetText("who is here")
                window.entry.javaObject:onKeyEnter()
            else
                window:setFocusMode("menu")
                window.entry.javaObject:SetText("2") window.entry.javaObject:onTextChange()
                assert(window.menuPage=="files","normal numbered menu did not open personal files")
                window.entry.javaObject:SetText("3") window.entry.javaObject:onTextChange()
            end
        end
        run.step,run.next=6,now+5000
    elseif run.step==6 then
        local window=assert(SC.Terminal.window)
        if not window.system.locked then window:flush() end
        if run.index==1 then
            local frame=window:readingRange(window:readingFrame(now))
            assert(frame.rows[frame.first].text=="> who is here" and window.scroll>0,
                "long native camp reply did not open at its question")
            run.chatScroll=window.scroll
            log("PASS native long reply starts at question scroll="..window.scroll)
        end
        run.step,run.next=7,now+1500
    elseif run.step==7 then
        shot("screen")
        local window=SC.Terminal.window
        window.entry.javaObject:onOtherKey(Keyboard.KEY_NEXT)
        run.step,run.next=run.index==1 and 10 or 11,now+1500
    elseif run.step==10 then
        assert(SC.Terminal.window.scroll<run.chatScroll,"native Page Down did not advance the camp reply")
        shot("paged")
        log("PASS native chat Page Down")
        run.step,run.next=8,now+1500
    elseif run.step==11 then
        local window=SC.Terminal.window
        assert(window.securityScroll>0,"native Page Down did not advance the recovery board")
        shot("paged")
        local puzzle=window.system.puzzle
        local wrong
        for _,hit in ipairs(window.securityHits) do
            if hit.value:match("^[A-Z]+$") and hit.value~=puzzle.answer then wrong=hit.value break end
        end
        assert(wrong,"no visible wrong candidate on the native recovery page")
        run.recoveryScroll,run.tries=window.securityScroll,puzzle.tries
        window.entry.javaObject:SetText(wrong)
        window.entry.javaObject:onKeyEnter()
        assert(puzzle.tries==run.tries-1,"native wrong guess did not consume exactly one attempt")
        log("PASS native recovery wrong guess="..wrong.." tries="..puzzle.tries)
        run.step,run.next=12,now+1500
    elseif run.step==12 then
        local window=SC.Terminal.window
        assert(window.securityScroll==run.recoveryScroll,"native guess lost its recovery page")
        shot("feedback")
        run.step,run.next=8,now+2000
    elseif run.step==8 then
        SC.Terminal.window:close()
        if run.index==1 then
            run.index=2
            run.site=2
            local p=run.points[run.site]
            player:teleportTo(p[1]+1.5,p[2]+0.5,p[3])
            run.step,run.next,run.deadline=1,now+6500,now+45000
        else
            player:teleportTo(run.home[1],run.home[2],run.home[3])
            log("PASS native terminal reading acceptance complete")
            run.step,run.next=99,now+1000000
        end
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
