-- Test-only native FMOD acceptance in the disposable cloned world.
local run = { step = 0, next = 0 }
local function log(value)
    print("EMMA_BOOT_AUDIO|" .. value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-boot-audio.log",true,true)
    if writer then writer:write(value .. "\n") writer:close() end
end
local function open()
    assert(SurvivorCompanion.Terminal.open(run.player,run.computer))
    run.window=SurvivorCompanion.Terminal.window
    run.handle=run.window.bootSoundId
    assert(type(run.handle)=="number" and run.handle>0,"native startup sound did not start")
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.Terminal or not player or not player:getCurrentSquare() then return end
    local manager=getSoundManager()
    if run.step==0 then
        run.player=player
        player:setGodMod(true)
        player:setGhostMode(true)
        run.computer=IsoObject.new(getCell(),player:getCurrentSquare(),"appliances_com_01_72")
        player:getCurrentSquare():AddTileObject(run.computer)
        run.computer:getModData().LF_Emma={visits=1,notes={}}
        local powered=SC.Terminal.powered
        SC.Terminal.powered=function(object) return object==run.computer or powered(object) end
        open()
        run.started=now
        log("START handle=" .. run.handle .. " volume=" .. manager:getSoundVolume())
        run.step,run.next=1,now+350
    elseif run.step==1 then
        assert(manager:isPlayingUISound(run.handle),"FMOD did not sustain the startup clip")
        local handle=run.handle
        run.window:startBootSound()
        assert(run.window.bootSoundId==handle,"a repeated UI start replaced the owned sound")
        log("PASS native playback active, repeated start preserves handle")
        run.step,run.next=2,run.started+4200
    elseif run.step==2 then
        assert(run.window.state~="booting","normal POST did not finish")
        assert(manager:isPlayingUISound(run.handle),"normal POST truncated the supplied sound")
        log("PASS clip continues over welcome after POST")
        run.step,run.next=3,run.started+8800
    elseif run.step==3 then
        assert(not manager:isPlayingUISound(run.handle),"startup clip looped beyond its duration")
        log("PASS native clip finished naturally without looping")
        run.window:close()
        open()
        run.step,run.next=4,now+350
    elseif run.step==4 then
        assert(manager:isPlayingUISound(run.handle),"a new boot did not play")
        run.window:close()
        run.step,run.next=5,now+350
    elseif run.step==5 then
        assert(not manager:isPlayingUISound(run.handle),"closing left its startup sound active")
        log("PASS native close stops owned playback")
        log("PASS native boot audio acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL " .. tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
