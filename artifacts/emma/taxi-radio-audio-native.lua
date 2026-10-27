-- Test-only radio context callback and native FMOD playback; no cab dispatch.
local run={step=0,next=0,reason="booking_received"}
local function log(value)
    print("TAXI_RADIO_AUDIO|" .. value)
    local writer=getFileWriter("SurvivorCompanionHarness/taxi-radio-audio.log",true,true)
    if writer then writer:write(value .. "\n") writer:close() end
end
local function menu()
    local result={options={}}
    function result:addOption(label,target,callback,...)
        local entry={label=label,target=target,callback=callback,args={...}}
        self.options[#self.options+1]=entry
        return entry
    end
    result.addOptionOnTop=result.addOption
    function result:addSubMenu(entry,child) entry.subMenu=child end
    return result
end
local function findCall(root)
    for _,entry in ipairs(root.options) do
        if entry.args[3]=="request" then return entry end
        if entry.subMenu then local call=findCall(entry.subMenu) if call then return call end end
    end
end
local function click()
    assert(run.call.callback(run.call.target,unpack(run.call.args)),"booking callback rejected the fixture")
    local sound=SurvivorCompanion.UIContext._taxiCallAudio
    assert(sound and sound.handle>0,"native booking audio did not start")
    run.handle=sound.handle
end
local function restore()
    if run.original then
        local service=SurvivorCompanion.TaxiService
        service.request,service.current,service.cancel=run.original.request,run.original.current,run.original.cancel
        run.original=nil
    end
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.UIContext or not player or not player:getCurrentSquare() then return end
    local manager=getSoundManager()
    if run.step==0 then
        run.player=player
        player:setGodMod(true)
        player:setGhostMode(true)
        run.radio=player:getInventory():AddItem("Base.WalkieTalkie2")
        assert(run.radio,"native handset unavailable")
        local service=SC.TaxiService
        run.original={request=service.request,current=service.current,cancel=service.cancel}
        service.current=function() return nil end
        service.request=function(actor,radio)
            assert(actor==player and radio==run.radio,"wrong booking caller")
            return true,run.reason
        end
        service.cancel=function() return true,"booking_cancelled" end
        local previous=ISContextMenu.getNew
        ISContextMenu.getNew=function() return menu() end
        local root=menu()
        local okay,reason=pcall(SC.UIContext.fillRadioContextMenu,0,root,{run.radio})
        ISContextMenu.getNew=previous
        assert(okay,tostring(reason))
        run.call=findCall(root)
        assert(run.call,"radio booking option missing")
        click()
        run.started=now
        log("START actual radio-menu callback, dispatch result stubbed; handle=" .. run.handle)
        run.step,run.next=1,now+350
    elseif run.step==1 then
        assert(manager:isPlayingUISound(run.handle),"FMOD playback unavailable")
        local handle=run.handle
        run.reason="already_booked"
        click()
        assert(run.handle==handle,"duplicate booking replayed its audio")
        log("PASS native radio audio active; duplicate click retained handle")
        run.step,run.next=2,run.started+8800
    elseif run.step==2 then
        assert(not manager:isPlayingUISound(run.handle),"radio clip looped")
        log("PASS native radio clip finished naturally")
        run.reason="booking_received"
        click()
        run.step,run.next=3,now+350
    elseif run.step==3 then
        assert(manager:isPlayingUISound(run.handle),"new request did not play")
        assert(SC.UIContext.taxiCabAction(nil,player,"cancel"),"cancel callback failed")
        run.step,run.next=4,now+350
    elseif run.step==4 then
        assert(not manager:isPlayingUISound(run.handle),"cancellation left radio audio active")
        restore()
        player:getInventory():Remove(run.radio)
        log("PASS native booking cancellation stopped owned audio")
        log("PASS native taxi radio audio acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then restore() log("FAIL " .. tostring(reason)) run.next=getTimestampMs()+1000000 end
end)
