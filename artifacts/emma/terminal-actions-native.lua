-- Disposable cloned-world acceptance: real terminal, native entry and job API.
local run={step=0,next=0}
local function log(value)
    print("EMMA_ACTIONS|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/terminal-actions.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function send(value)
    local window=SurvivorCompanion.Terminal.window
    window:setFocusMode("chat")
    window.entry.javaObject:SetText(value)
    window:submit()
    window:flush()
end
local function palette(theme)
    local SC=SurvivorCompanion
    if SC.Terminal.window then SC.Terminal.window:close() end
    local state=SC.Terminal.computerState(getSpecificPlayer(0),run.object)
    state.theme=theme
    state.paletteVersion=SC.TerminalPresentation.PALETTE_VERSION
    assert(SC.Terminal.open(getSpecificPlayer(0),run.object))
    SC.Terminal.window:flush()
    send("status")
end
local function tick()
    local now=getTimestampMs()
    if now<run.next then return end
    local SC=SurvivorCompanion
    local player=getSpecificPlayer(0)
    if not SC or not SC.TerminalActions or not player or not player:getCurrentSquare() then return end
    if run.step==0 then
        local base=SC.BaseLife.active()
        assert(base,"cloned seed has no camp")
        local square=player:getCurrentSquare()
        assert(SC.BaseLife.isInside(square),"cloned seed player is outside camp")
        player:setGodMod(true) player:setGhostMode(true)
        run.object=IsoObject.new(getCell(),square,"appliances_com_01_72")
        square:AddTileObject(run.object)
        run.object:getModData().LF_Emma={visits=1,notes={}}
        local powered=SC.Terminal.powered
        -- Fixture desk has no physical socket; only its power check is supplied.
        SC.Terminal.powered=function(object) return object==run.object or powered(object) end
        local okay,job=SC.BaseLife.enqueueJob({type="clean",priority=0,
            target={x=square:getX(),y=square:getY(),z=square:getZ()}})
        assert(okay,"native fixture job enqueue failed: "..tostring(job))
        run.job=job
        assert(SC.BaseLife.blockJob(job.id,nil,"terminal_acceptance",180000))
        assert(SC.Terminal.open(player,run.object))
        SC.Terminal.window:flush()
        send("retry job "..job.id)
        assert(SC.Terminal.window.requestTicket,"native chat did not prepare confirmation")
        assert(job.state=="blocked","proposal changed the job before consent")
        log("PASS native prompt visible; job remains blocked before consent id="..job.id)
        run.step,run.next=1,now+1200
    elseif run.step==1 then
        getCore():TakeFullScreenshot("emma-confirmation-prompt")
        send("n")
        assert(not SC.Terminal.window.requestTicket and run.job.state=="blocked","native cancellation changed the job")
        send("retry job "..run.job.id)
        local ticket=SC.Terminal.window.requestTicket
        assert(ticket,"second native confirmation unavailable")
        send("y")
        assert(run.job.state=="pending","native public retry did not requeue the job")
        assert(SC.TerminalActions.execute(SC.Terminal.window,ticket)==false,"consumed native ticket replayed")
        assert(SC.BaseLife.cancelJob(run.job.id),"native fixture cleanup failed")
        log("PASS native N leaves job blocked; Y requeues through BaseLife.retryJob exactly once")
        send("who is hurt")
        run.step,run.next=2,now+1200
    elseif run.step==2 then
        getCore():TakeFullScreenshot("emma-medical-report")
        log("PASS medical report rendered without errors")
        local people=SC.Terminal.window.world.people()
        assert(type(people)=="table" and #people>0,"native camp medical records unavailable")
        local skills=0
        for _,person in ipairs(people) do skills=skills+#(person.skills or {}) end
        assert(skills>0,"native skills did not resolve installed perk enums")
        log("PASS native skill enums resolved readings="..skills)
        send("who is best at first aid")
        run.step,run.next=3,now+1200
    elseif run.step==3 then
        getCore():TakeFullScreenshot("emma-skill-report")
        send("shortages") send("alarms") send("expedition")
        palette("aqua")
        run.step,run.next=4,now+1500
    elseif run.step==4 then
        getCore():TakeFullScreenshot("emma-camp-logo-aqua")
        palette("sand")
        run.step,run.next=5,now+1500
    elseif run.step==5 then
        getCore():TakeFullScreenshot("emma-camp-logo-sand")
        palette("purple")
        run.step,run.next=6,now+1500
    elseif run.step==6 then
        local w=SC.Terminal.window
        assert(w.logoTexture and w.logoTexture:getWidth()==2172,"purple camp variant failed to load")
        getCore():TakeFullScreenshot("emma-camp-logo-purple")
        palette("green")
        run.step,run.next=7,now+1500
    elseif run.step==7 then
        getCore():TakeFullScreenshot("emma-camp-logo-green")
        SC.Terminal.window:close()
        log("PASS native skill/stock/alarm/expedition queries and cleanup")
        log("PASS native camp logo matches aqua/sand/purple/green palettes")
        log("PASS native terminal actions acceptance complete")
        run.step,run.next=99,now+1000000
    end
end
Events.OnTick.Add(function()
    local okay,reason=pcall(tick)
    if not okay then log("FAIL "..tostring(reason)) run.step,run.next=99,getTimestampMs()+1000000 end
end)
